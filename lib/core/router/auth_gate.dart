// lib/core/router/auth_gate.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';

/// AuthGate handles ONLY the cold app launch.
/// It shows a spinner, loads the session once, then navigates by role.
/// Login/logout handle their own navigation directly — AuthGate is never
/// revisited after the initial start.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const _green = Color(0xFF0D3D2B);
  static const _greenAccent = Color(0xFF34C77B);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final authService = context.read<AuthService>();

    // Load Firestore profile for whoever is signed in (if anyone)
    await authService.loadSession();

    if (!mounted) return;

    final isLoggedIn = authService.isLoggedIn;
    final role = authService.userRole;

    if (!isLoggedIn) {
      context.go('/login');
    } else if (role == 'admin') {
      context.go('/admin');
    } else if (role == 'landlord') {
      context.go('/landlord');
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6F1),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _greenAccent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.home_work_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: _green,
                strokeWidth: 2.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
