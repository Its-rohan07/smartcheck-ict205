import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final Stream<User?> _authStream;
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    _authStream = FirebaseAuth.instance.userChanges();
  }

  void _openLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const LoginScreen(),
      ),
      (route) => false,
    );
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true || _isLoggingOut) return;

    setState(() => _isLoggingOut = true);

    try {
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      _openLogin();
    } catch (_) {
      if (!mounted) return;

      setState(() => _isLoggingOut = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not log out. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
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
                  onPressed: _isLoggingOut ? null : _openLogin,
                  child: Text(
                    _isLoggingOut ? 'Logging Out...' : 'Go to Login',
                  ),
                ),
              );
            }

            return _ProfileContent(
              key: ValueKey(user.uid),
              user: user,
              isLoggingOut: _isLoggingOut,
              onLogout: _logout,
            );
          },
        ),
      ),
    );
  }
}

class _ProfileContent extends StatefulWidget {
  final User user;
  final bool isLoggingOut;
  final VoidCallback onLogout;

  const _ProfileContent({
    super.key,
    required this.user,
    required this.isLoggingOut,
    required this.onLogout,
  });

  @override
  State<_ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends State<_ProfileContent> {
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _profileStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _attendanceStream;

  @override
  void initState() {
    super.initState();
    _loadStreams();
  }

  void _loadStreams() {
    final firestore = FirebaseFirestore.instance;

    _profileStream =
        firestore.collection('users').doc(widget.user.uid).snapshots();

    _attendanceStream = firestore
        .collection('attendance')
        .where('userId', isEqualTo: widget.user.uid)
        .snapshots();
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('About SmartCheck'),
        content: const Text(
          'SmartCheck helps students view events, '
          'check their location and record attendance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _profileStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                children: [
                  const Text(
                    'Could not load your profile. Check your connection '
                    'and Firebase profile read permissions.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _retry,
                    child: const Text('Try Again'),
                  ),
                ],
              );
            }

            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(30),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final document = snapshot.data!;
            final data = document.data() ?? <String, dynamic>{};

            final fullName = _text(
              data,
              'fullName',
              'Name not provided',
            );

            // Authentication is the source for the login email.
            final email = widget.user.email ?? 'Email not available';
            final studentId = _text(data, 'studentId', 'Not provided');
            final course = _text(data, 'course', 'Not provided');

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Colors.indigo,
                        Color(0xFF5C6BC0),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 86,
                        height: 86,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        fullName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        email,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!document.exists) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Your account is signed in, but its profile '
                    'has not been saved yet.',
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 28),
                _sectionTitle('Personal Information'),
                const SizedBox(height: 12),
                _profileTile(
                  icon: Icons.person_outline,
                  title: 'Full Name',
                  value: fullName,
                ),
                const SizedBox(height: 10),
                _profileTile(
                  icon: Icons.email_outlined,
                  title: 'Email',
                  value: email,
                ),
                const SizedBox(height: 10),
                _profileTile(
                  icon: Icons.badge_outlined,
                  title: 'Student ID',
                  value: studentId,
                ),
                const SizedBox(height: 10),
                _profileTile(
                  icon: Icons.school_outlined,
                  title: 'Course',
                  value: course,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 28),
        _sectionTitle('Attendance'),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _attendanceStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                children: [
                  const Text('Could not load your attendance count.'),
                  TextButton(
                    onPressed: _retry,
                    child: const Text('Try Again'),
                  ),
                ],
              );
            }

            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            final count = snapshot.data!.docs
                .where((doc) => doc.data()['status'] == 'present')
                .length;

            return _profileTile(
              icon: Icons.event_available,
              title: 'Events Attended',
              value: '$count',
            );
          },
        ),
        const SizedBox(height: 28),
        _sectionTitle('App Settings'),
        const SizedBox(height: 12),
        _actionTile(
          icon: Icons.location_on_outlined,
          title: 'Location Permission',
          subtitle: 'Required for GPS check-in',
          onTap: () {
            _showMessage(
              'Allow location access when checking in. '
              'You can change permission in your browser or device settings.',
            );
          },
        ),
        const SizedBox(height: 10),
        _actionTile(
          icon: Icons.notifications_outlined,
          title: 'Notifications',
          subtitle: 'Not available yet',
          onTap: () {
            _showMessage('Notifications are not available yet.');
          },
        ),
        const SizedBox(height: 10),
        _actionTile(
          icon: Icons.info_outline,
          title: 'About SmartCheck',
          subtitle: 'Location-based event attendance',
          onTap: _showAbout,
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            onPressed: widget.isLoggingOut ? null : widget.onLogout,
            icon: widget.isLoggingOut
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
            label: Text(
              widget.isLoggingOut ? 'Logging Out...' : 'Log Out',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: BorderSide(color: Colors.red.shade200),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'SmartCheck • Version 1.0',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _profileTile({
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
          _tileIcon(icon),
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

  Widget _tileIcon(IconData icon) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Colors.indigo, size: 22),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: widget.isLoggingOut ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _tileIcon(icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}