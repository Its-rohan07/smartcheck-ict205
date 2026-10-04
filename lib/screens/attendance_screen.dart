import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late final Stream<User?> _authStream;

  @override
  void initState() {
    super.initState();
    _authStream = FirebaseAuth.instance.authStateChanges();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Attendance History',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: StreamBuilder<User?>(
          stream: _authStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Text('Could not check your login. Please retry.'),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final user = snapshot.data;

            if (user == null) {
              return const Center(
                child: Text('Please log in to view your attendance.'),
              );
            }

            return _AttendanceHistory(
              key: ValueKey(user.uid),
              userId: user.uid,
            );
          },
        ),
      ),
    );
  }
}

class _AttendanceHistory extends StatefulWidget {
  final String userId;

  const _AttendanceHistory({
    super.key,
    required this.userId,
  });

  @override
  State<_AttendanceHistory> createState() => _AttendanceHistoryState();
}

class _AttendanceHistoryState extends State<_AttendanceHistory> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _attendanceStream;

  @override
  void initState() {
    super.initState();
    _attendanceStream = _createStream();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _createStream() {
    return FirebaseFirestore.instance
        .collection('attendance')
        .where('userId', isEqualTo: widget.userId)
        .snapshots();
  }

  void _retry() {
    setState(() {
      _attendanceStream = _createStream();
    });
  }

  int _timestampValue(Map<String, dynamic> data) {
    final timestamp = data['timestamp'];
    return timestamp is Timestamp ? timestamp.millisecondsSinceEpoch : 0;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _attendanceStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          final message = error is FirebaseException &&
                  error.code == 'permission-denied'
              ? 'Firebase denied access to your attendance. '
                  'Check that the attendance read rules are published.'
              : 'Could not load attendance. Check your connection '
                  'and try again.';

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _retry,
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        // Sort this student's records newest first.
        final records = snapshot.data!.docs.toList()
          ..sort(
            (a, b) =>
                _timestampValue(b.data()).compareTo(_timestampValue(a.data())),
          );

        final checkedInCount = records
            .where((record) => record.data()['status'] == 'present')
            .length;

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _summaryCard(checkedInCount),
            const SizedBox(height: 28),
            const Text(
              'Recent Attendance',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            if (records.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.event_note,
                      size: 40,
                      color: Colors.indigo,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No attendance yet',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Check in to an event to see your record here.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              for (final record in records)
                _attendanceCard(record.data()),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.indigo.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.indigo.withValues(alpha: 0.12),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.indigo,
                    size: 24,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'These are your saved check-ins. '
                      'Dates and times use your device’s local time.',
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _summaryCard(int count) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.indigo, Color(0xFF5C6BC0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            height: 58,
            width: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.event_available,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Events Attended',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Your saved check-ins',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _attendanceCard(Map<String, dynamic> data) {
    final titleValue = data['eventTitle'];
    final title = titleValue is String && titleValue.trim().isNotEmpty
        ? titleValue
        : 'Untitled event';

    final timestamp = data['timestamp'];
    final checkedInAt =
        timestamp is Timestamp ? timestamp.toDate().toLocal() : null;

final date = checkedInAt == null
    ? 'Date unavailable'
    : DateFormat('d MMMM yyyy', 'en_US').format(checkedInAt);

final time = checkedInAt == null
    ? 'Time unavailable'
    : DateFormat('h:mm a', 'en_US').format(checkedInAt);
    final distance = data['distanceMetres'];
    final distanceText =
        distance is num && distance.isFinite && distance >= 0
            ? '${distance.toStringAsFixed(1)} m from venue at check-in'
            : 'Distance unavailable';

    final isPresent = data['status'] == 'present';
    final status = isPresent ? 'Checked in' : 'Status unavailable';
    final statusColor = isPresent ? Colors.green : Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: Colors.indigo.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.event_available,
              color: Colors.indigo,
              size: 27,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _detailRow(Icons.calendar_today_outlined, date),
                const SizedBox(height: 5),
                _detailRow(Icons.access_time_rounded, time),
                const SizedBox(height: 5),
                _detailRow(Icons.location_on_outlined, distanceText),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: Colors.grey.shade600),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }
}