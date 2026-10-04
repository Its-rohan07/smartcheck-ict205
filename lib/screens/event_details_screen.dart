import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/location_service.dart';

class EventDetailsScreen extends StatefulWidget {
  final String eventId;
  final String title;
  final String date;
  final String time;
  final String location;
  final String description;
  final IconData icon;
  final double latitude;
  final double longitude;

  const EventDetailsScreen({
    super.key,
    required this.eventId,
    required this.title,
    required this.date,
    required this.time,
    required this.location,
    required this.description,
    required this.icon,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  bool _isCheckingIn = false;
  bool _hasCheckedIn = false;
  String _progressLabel = 'Checking attendance...';

  Future<void> _checkIn() async {
    if (_isCheckingIn || _hasCheckedIn) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showResultDialog(
        title: 'Please log in',
        message: 'Log in before checking in to an event.',
        icon: Icons.lock_outline,
        color: Colors.orange,
      );
      return;
    }

    setState(() {
      _isCheckingIn = true;
      _progressLabel = 'Checking attendance...';
    });

    try {
      final firestore = FirebaseFirestore.instance;

      // One attendance document per student and event.
      final attendanceRef = firestore
          .collection('attendance')
          .doc('${user.uid}_${widget.eventId}');

      final eventRef =
          firestore.collection('events').doc(widget.eventId);

      // Check the server first so an existing check-in
      // does not require another GPS request.
      final existing = await attendanceRef.get(
        const GetOptions(source: Source.server),
      );

      if (!mounted) return;

      if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
        throw const _CheckInIssue(
          'Session changed',
          'Please log in again before checking in.',
        );
      }

      if (existing.exists) {
        _showAlreadyCheckedIn();
        return;
      }

      setState(() => _progressLabel = 'Checking location...');

      final position = await LocationService.getCurrentLocation();

      if (!mounted) return;

      setState(() => _progressLabel = 'Saving attendance...');

      final distance = await firestore.runTransaction<double?>(
        (transaction) async {
          if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
            throw const _CheckInIssue(
              'Session changed',
              'Please log in again before checking in.',
            );
          }

          // Recheck inside the transaction to prevent
          // simultaneous attempts from creating duplicates.
          final attendanceSnapshot =
              await transaction.get(attendanceRef);

          if (attendanceSnapshot.exists) {
            return null;
          }

          // Use the current event coordinates from Firebase.
          final eventSnapshot = await transaction.get(eventRef);
          final event = eventSnapshot.data();

          if (!eventSnapshot.exists || event == null) {
            throw const _CheckInIssue(
              'Event unavailable',
              'This event no longer exists.',
            );
          }

          final latitude = event['latitude'];
          final longitude = event['longitude'];
          final title = event['title'];

          if (latitude is! num ||
              longitude is! num ||
              !latitude.isFinite ||
              !longitude.isFinite ||
              latitude < -90 ||
              latitude > 90 ||
              longitude < -180 ||
              longitude > 180 ||
              title is! String ||
              title.trim().isEmpty) {
            throw const _CheckInIssue(
              'Event details incomplete',
              'The event needs a valid title, latitude and longitude '
                  'in Firebase before check-in is available.',
            );
          }

          final distanceInMetres = LocationService.calculateDistance(
            userLatitude: position.latitude,
            userLongitude: position.longitude,
            eventLatitude: latitude.toDouble(),
            eventLongitude: longitude.toDouble(),
          );

          if (!distanceInMetres.isFinite || distanceInMetres < 0) {
            throw const _CheckInIssue(
              'Location unavailable',
              'Your distance could not be calculated. Please try again.',
            );
          }

          if (distanceInMetres > 100) {
            throw _CheckInIssue(
              'You are too far away',
              'You are approximately '
                  '${distanceInMetres.toStringAsFixed(1)} metres '
                  'from the event venue.\n\n'
                  'You must be within 100 metres to check in. '
                  'No attendance was saved.',
            );
          }

          transaction.set(attendanceRef, {
            'userId': user.uid,
            'eventId': widget.eventId,
            'eventTitle': title,
            'timestamp': FieldValue.serverTimestamp(),
            'latitude': position.latitude,
            'longitude': position.longitude,
            'distanceMetres': distanceInMetres,
            'status': 'present',
          });

          return distanceInMetres;
        },
      );

      if (!mounted) return;

      if (distance == null) {
        _showAlreadyCheckedIn();
        return;
      }

      setState(() => _hasCheckedIn = true);

      _showResultDialog(
        title: 'Attendance saved',
        message: 'You have successfully checked in.\n\n'
            'Distance from venue: '
            '${distance.toStringAsFixed(1)} metres.',
        icon: Icons.check_circle,
        color: Colors.green,
      );
    } on _CheckInIssue catch (error) {
      if (!mounted) return;

      _showResultDialog(
        title: error.title,
        message: error.message,
        icon: Icons.info_outline,
        color: Colors.orange,
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;

      String message;

      switch (error.code) {
        case 'permission-denied':
          message = 'Firebase denied this request. Make sure you '
              'published the attendance rules in the correct '
              'Firebase project.';
          break;
        case 'unauthenticated':
          message = 'Please log out, log in again and retry.';
          break;
        case 'unavailable':
        case 'deadline-exceeded':
        case 'aborted':
          message = 'Attendance could not be confirmed. Check your '
              'internet connection and try again. The app checks '
              'for an existing record before saving.';
          break;
        default:
          message = 'Attendance could not be confirmed.\n\n'
              'Firebase error: ${error.code}';
      }

      _showResultDialog(
        title: 'Check-in error',
        message: message,
        icon: Icons.error_outline,
        color: Colors.red,
      );
    } catch (error) {
      if (!mounted) return;

      _showResultDialog(
        title: 'Check-in error',
        message: error.toString().replaceFirst('Exception: ', ''),
        icon: Icons.error_outline,
        color: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() => _isCheckingIn = false);
      }
    }
  }

  void _showAlreadyCheckedIn() {
    setState(() => _hasCheckedIn = true);

    _showResultDialog(
      title: 'Already checked in',
      message: 'Your attendance for this event is already saved.',
      icon: Icons.check_circle,
      color: Colors.green,
    );
  }

  void _showResultDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(icon, color: color, size: 55),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Event Details',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.indigo, Color(0xFF5C6BC0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  children: [
                    Container(
                      height: 72,
                      width: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        widget.icon,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Event Details',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Event Information',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _informationTile(
                icon: Icons.calendar_today_outlined,
                title: 'Date',
                value: widget.date,
              ),
              const SizedBox(height: 12),
              _informationTile(
                icon: Icons.access_time_rounded,
                title: 'Time',
                value: widget.time,
              ),
              const SizedBox(height: 12),
              _informationTile(
                icon: Icons.location_on_outlined,
                title: 'Address',
                value: widget.location,
              ),
              const SizedBox(height: 28),
              const Text(
                'About This Event',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.description,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.indigo.withValues(alpha: 0.15),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.location_searching_rounded,
                      color: Colors.indigo,
                      size: 28,
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Location-based check-in',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Check in within 100 metres of the venue '
                            'to save your attendance.',
                            style: TextStyle(
                              height: 1.4,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed:
                      _hasCheckedIn || _isCheckingIn ? null : _checkIn,
                  icon: _isCheckingIn
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                          ),
                        )
                      : Icon(
                          _hasCheckedIn
                              ? Icons.check_circle
                              : Icons.location_on_rounded,
                        ),
                  label: Text(
                    _isCheckingIn
                        ? _progressLabel
                        : _hasCheckedIn
                            ? 'Checked In'
                            : 'Check In to This Event',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'Location permission and internet are required.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _informationTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: Colors.indigo.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.indigo, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckInIssue implements Exception {
  final String title;
  final String message;

  const _CheckInIssue(this.title, this.message);

  @override
  String toString() => '$title: $message';
}