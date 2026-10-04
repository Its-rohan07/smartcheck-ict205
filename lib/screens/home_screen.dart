import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'events_screen.dart';
import 'attendance_screen.dart';
import 'profile_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Stream<User?> _authStream;
  bool _openingScreen = false;

  @override
  void initState() {
    super.initState();
    _authStream = FirebaseAuth.instance.authStateChanges();
  }

  void _openLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const LoginScreen(),
      ),
      (route) => false,
    );
  }

  Future<void> _openScreen(int index) async {
    if (index == 0 || _openingScreen) return;

    if (FirebaseAuth.instance.currentUser == null) {
      _openLogin();
      return;
    }

    final Widget screen;

    switch (index) {
      case 1:
        screen = const EventsScreen();
        break;
      case 2:
        screen = const AttendanceScreen();
        break;
      case 3:
        screen = const ProfileScreen();
        break;
      default:
        return;
    }

    _openingScreen = true;

    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => screen,
        ),
      );
    } finally {
      _openingScreen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'SmartCheck',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.person_outline),
            onPressed: () => _openScreen(3),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<User?>(
          stream: _authStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: ElevatedButton(
                  onPressed: _openLogin,
                  child: const Text('Return to Login'),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            final user = snapshot.data;

            if (user == null) {
              return Center(
                child: ElevatedButton(
                  onPressed: _openLogin,
                  child: const Text('Go to Login'),
                ),
              );
            }

            return _HomeContent(
              key: ValueKey(user.uid),
              userId: user.uid,
              onOpen: _openScreen,
            );
          },
        ),
      ),
      bottomNavigationBar: NavigationBar(
        // Other screens open as separate pages.
        // Returning to this page selects Home.
        selectedIndex: 0,
        onDestinationSelected: _openScreen,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_outlined),
            selectedIcon: Icon(Icons.event),
            label: 'Events',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Attendance',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _HomeContent extends StatefulWidget {
  final String userId;
  final ValueChanged<int> onOpen;

  const _HomeContent({
    super.key,
    required this.userId,
    required this.onOpen,
  });

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<_HomeContent> {
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _profileStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _attendanceStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _eventsStream;

  @override
  void initState() {
    super.initState();
    _loadStreams();
  }

  void _loadStreams() {
    final firestore = FirebaseFirestore.instance;

    _profileStream =
        firestore.collection('users').doc(widget.userId).snapshots();

    _attendanceStream = firestore
        .collection('attendance')
        .where('userId', isEqualTo: widget.userId)
        .snapshots();

    _eventsStream = firestore.collection('events').snapshots();
  }

  void _retry() {
    setState(_loadStreams);
  }

  String _text(
    Map<String, dynamic> data,
    String field,
    String fallback,
  ) {
    final value = data[field];

    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _eventsStream,
      builder: (context, eventSnapshot) {
        final events = eventSnapshot.hasError
            ? <QueryDocumentSnapshot<Map<String, dynamic>>>[]
            : eventSnapshot.data?.docs.toList() ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        // Event dates are currently text, so list alphabetically.
        events.sort(
          (a, b) => _text(a.data(), 'title', '')
              .toLowerCase()
              .compareTo(
                _text(b.data(), 'title', '').toLowerCase(),
              ),
        );

        final eventCount = eventSnapshot.hasError
            ? 'Unavailable'
            : !eventSnapshot.hasData
                ? '…'
                : '${events.length}';

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _profileStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _greeting('Welcome 👋'),
                      _errorBox('Could not load your name.'),
                    ],
                  );
                }

                if (!snapshot.hasData) {
                  return _greeting('Welcome 👋');
                }

                final data =
                    snapshot.data!.data() ?? <String, dynamic>{};
                final name = _text(data, 'fullName', '');

                return _greeting(
                  name.isEmpty ? 'Welcome 👋' : 'Hello, $name 👋',
                );
              },
            ),
            const SizedBox(height: 6),
            Text(
              'Ready to check in to your next event?',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            _checkInCard(),
            const SizedBox(height: 24),
            _sectionTitle('Attendance Overview'),
            const SizedBox(height: 14),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _attendanceStream,
              builder: (context, snapshot) {
                String attendanceCount = '…';

                if (snapshot.hasError) {
                  attendanceCount = 'Unavailable';
                } else if (snapshot.hasData) {
                  final count = snapshot.data!.docs
                      .where(
                        (doc) => doc.data()['status'] == 'present',
                      )
                      .length;

                  attendanceCount = '$count';
                }

                return Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _statCard(
                            icon: Icons.event_available_outlined,
                            value: attendanceCount,
                            label: 'Events Attended',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _statCard(
                            icon: Icons.event_note_outlined,
                            value: eventCount,
                            label: 'Total Events',
                          ),
                        ),
                      ],
                    ),
                    if (snapshot.hasError)
                      _errorBox(
                        'Could not load your attendance count.',
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            _sectionTitle('Events'),
            const SizedBox(height: 14),
            if (eventSnapshot.hasError)
              _errorBox(
                'Could not load events. Check your connection '
                'and Firebase read permissions.',
              )
            else if (!eventSnapshot.hasData)
              const Center(child: CircularProgressIndicator())
            else if (events.isEmpty)
              const Text('No events have been added yet.')
            else ...[
              for (final event in events.take(3))
                _eventCard(event.data()),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => widget.onOpen(1),
                  child: const Text('View All Events'),
                ),
              ),
            ],
            const SizedBox(height: 28),
            _sectionTitle('Quick Actions'),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _quickAction(
                    icon: Icons.event_outlined,
                    title: 'Events',
                    onTap: () => widget.onOpen(1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _quickAction(
                    icon: Icons.history,
                    title: 'Attendance',
                    onTap: () => widget.onOpen(2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _quickAction(
                    icon: Icons.location_on_outlined,
                    title: 'Check-in',
                    onTap: () => widget.onOpen(1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _quickAction(
                    icon: Icons.person_outline,
                    title: 'Profile',
                    onTap: () => widget.onOpen(3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _greeting(String message) {
    return Text(
      message,
      style: const TextStyle(
        fontSize: 27,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _errorBox(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(color: Colors.red),
          ),
          TextButton(
            onPressed: _retry,
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _checkInCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.indigo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.location_on_outlined,
            color: Colors.white,
            size: 32,
          ),
          const SizedBox(height: 14),
          const Text(
            'Quick GPS Check-in',
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Choose an event and check in within '
            '100 metres of its venue.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: () => widget.onOpen(1),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.indigo,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Check In',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: 18,
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.indigo, size: 25),
          const SizedBox(height: 8),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventCard(Map<String, dynamic> data) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: Colors.indigo.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.event,
              color: Colors.indigo,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _text(data, 'title', 'Untitled event'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _text(data, 'date', 'Date not provided'),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _text(data, 'location', 'Location not provided'),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.indigo, size: 28),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}