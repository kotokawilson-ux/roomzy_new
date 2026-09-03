// lib/core/router/app_router.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/register_screen.dart';
import '../../screens/auth/landlord_register_screen.dart';
import '../../screens/hostels/hostels_screen.dart';
import '../../screens/hostels/hostel_detail_screen.dart';
import '../../screens/bookings/bookings_screen.dart';
import '../../screens/bookings/booking_confirm_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../screens/about/about_screen.dart';
import '../../screens/contact/contact_screen.dart';
import '../../screens/landlord/landlord_portal.dart';
import '../../screens/admin/admin_dashboard_screen.dart';
import '../../screens/chat/chat_screen.dart';
import 'auth_gate.dart';
import 'app_shell.dart';
import '../../screens/admin/chat/admin_live_chat_screen.dart';
import '../../screens/landlord/dashboard/landlord_dashboard.dart';
import '../../services/landlord_service.dart';
import 'package:roomzy_find/screens/settings/settings_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  BACK HANDLER  –  unchanged
// ─────────────────────────────────────────────────────────────────────────────
class BackHandlerWrapper extends StatelessWidget {
  final Widget child;
  final bool isHome;

  const BackHandlerWrapper({
    required this.child,
    this.isHome = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (isHome) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          final shouldExit = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.exit_to_app_rounded, color: Color(0xFF0F766E)),
                  SizedBox(width: 10),
                  Text('Exit App',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
              content: const Text(
                'Are you sure you want to exit RoomzyFind?',
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Stay'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Exit'),
                ),
              ],
            ),
          );
          if (shouldExit == true) {
            if (!kIsWeb) SystemNavigator.pop();
          }
        },
        child: child,
      );
    }
    return PopScope(canPop: true, child: child);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ROUTER
// ─────────────────────────────────────────────────────────────────────────────
class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final _shellNavigatorKey = GlobalKey<NavigatorState>();

  static Widget _wrap(Widget screen) => BackHandlerWrapper(child: screen);
  static Widget _wrapHome(Widget screen) =>
      BackHandlerWrapper(child: screen, isHome: true);

  // Only these are reachable without an active session. Everything
  // else in the app — including /about, /contact, /home, /hostels,
  // /settings — requires login first, even via a direct/deep link.
  static const _publicRoutes = {
    '/', // AuthGate decides where to send people itself
    '/login',
    '/register',
    '/landlord-register',
  };

  static GoRouter router([AuthService? authService]) {
    return GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: '/',

      // Re-run redirect whenever auth state changes (login, logout,
      // session expiry) — not just when the user navigates. Without
      // this, someone whose session dies while sitting on a protected
      // page would stay there until they happened to tap a link.
      refreshListenable: authService,

      // ── Redirect — strict: login required for everything except
      // the auth entry points themselves ─────────────────────────────
      redirect: (context, state) {
        if (authService == null) return null;

        final path = state.uri.path;

        // Resolve auth state before deciding anything.
        if (!authService.isInitialized) {
          authService.loadSession(); // no-ops if already in flight/done
          return null; // show AuthGate's splash while it resolves
        }

        final isLoggedIn = authService.isLoggedIn;
        final role = authService.userRole;
        final isPublic = _publicRoutes.contains(path);

        // Not logged in, trying to reach anything else → bounce to login.
        if (!isLoggedIn && !isPublic) {
          return '/login';
        }

        // Logged in but sitting on /login or /register → send them
        // straight to their dashboard instead of showing the form again.
        if (isLoggedIn && (path == '/login' || path == '/register')) {
          if (role == 'admin' || role == 'super_admin') return '/admin';
          if (role == 'landlord') return '/landlord';
          return '/home';
        }

        // Role gating — logged in, but wrong section for their role.
        if (isLoggedIn) {
          final isAdmin = role == 'admin' || role == 'super_admin';
          if (path.startsWith('/admin') && !isAdmin) return '/home';
          if (path.startsWith('/landlord') &&
              path != '/landlord-register' &&
              role != 'landlord') {
            return '/home';
          }
        }

        return null;
      },
      routes: [
        // ── Auth & entry routes (NO shell, NO bottom nav) ─────────────────
        GoRoute(
          path: '/',
          builder: (context, state) => const AuthGate(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => _wrap(const LoginScreen()),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => _wrap(const RegisterScreen()),
        ),
        GoRoute(
          path: '/landlord-register',
          builder: (context, state) => _wrap(const LandlordRegisterScreen()),
        ),
        GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen()),
        GoRoute(
            path: '/about', builder: (context, state) => const AboutScreen()),
        GoRoute(
            path: '/contact',
            builder: (context, state) => const ContactScreen()),

        // ── Role-specific dashboards (NO shell, NO bottom nav) ────────────
        GoRoute(
          path: '/landlord',
          builder: (context, state) => _wrap(const LandlordPortal()),
        ),
        GoRoute(
          path: '/admin',
          builder: (context, state) => _wrap(const AdminDashboardScreen()),
        ),

        // ── SHELL: routes that show the bottom nav bar ────────────────────
        ShellRoute(
          navigatorKey: _shellNavigatorKey,
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            // Home tab
            GoRoute(
              path: '/home',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: _wrapHome(const HomeScreen()),
              ),
            ),

            // Hostels tab
            GoRoute(
              path: '/hostels',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: _wrap(const HostelsScreen()),
              ),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return _wrap(HostelDetailScreen(hostelId: id));
                  },
                ),
              ],
            ),

            // Bookings tab
            GoRoute(
              path: '/bookings',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: _wrap(const BookingsScreen()),
              ),
              routes: [
                GoRoute(
                  path: ':bookingId',
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) {
                    final bookingId = state.pathParameters['bookingId']!;
                    return _wrap(BookingConfirmScreen(bookingId: bookingId));
                  },
                ),
              ],
            ),

            // Chat tab
            GoRoute(
              path: '/chat',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: _wrap(const ChatScreen()),
              ),
            ),

            // Profile tab
            GoRoute(
              path: '/profile',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: _wrap(const ProfileScreen()),
              ),
            ),
          ],
        ),
      ],

      // ── Error page — unchanged ──────────────────────────────────────────
      errorBuilder: (context, state) => _wrap(
        Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Page not found: ${state.uri}'),
                TextButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Go Home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
