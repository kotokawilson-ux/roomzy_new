import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../screens/splash/splash_screen.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/register_screen.dart';
import '../../screens/hostels/hostels_screen.dart';
import '../../screens/hostels/hostel_detail_screen.dart';
import '../../screens/bookings/bookings_screen.dart';
import '../../screens/bookings/booking_confirm_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../screens/about/about_screen.dart';
import '../../screens/contact/contact_screen.dart';
import '../../screens/landlord/landlord_dashboard_screen.dart';
import '../../screens/admin/admin_dashboard_screen.dart';

/// ─── BACK HANDLER WRAPPER ───────────────────────────────
/// Replaces the deprecated WillPopScope with PopScope.
/// - On HomeScreen: shows an exit confirmation dialog.
/// - On all other screens: lets GoRouter handle back navigation normally.
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
      // ── Home screen: intercept back and show exit dialog ──
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
                  Text(
                    'Exit App',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
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

    // ── All other screens: allow normal GoRouter back navigation ──
    return PopScope(
      canPop: true,
      child: child,
    );
  }
}

/// ─── APP ROUTER ─────────────────────────────────────────
class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();

  // Wrap normal screens (back navigation works as expected)
  static Widget _wrap(Widget screen) => BackHandlerWrapper(child: screen);

  // Wrap home screen (shows exit dialog on back press)
  static Widget _wrapHome(Widget screen) =>
      BackHandlerWrapper(child: screen, isHome: true);

  static GoRouter router([AuthService? authService]) {
    return GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: '/',
      redirect: (context, state) {
        if (authService == null) return null;

        final isLoggedIn = authService.isLoggedIn;
        final role = authService.userRole;
        final path = state.uri.path;

        if (path.startsWith('/landlord') && role != 'landlord') return '/login';
        if (path.startsWith('/admin') && role != 'admin') return '/login';
        if (path.startsWith('/bookings') && !isLoggedIn) return '/login';

        return null;
      },
      routes: [
        // Splash — no back navigation needed
        GoRoute(
          path: '/',
          builder: (context, state) => _wrap(const SplashScreen()),
        ),

        // Home — shows exit dialog on back press
        GoRoute(
          path: '/home',
          builder: (context, state) => _wrapHome(const HomeScreen()),
        ),

        // All other screens — normal back navigation
        GoRoute(
          path: '/about',
          builder: (context, state) => _wrap(const AboutScreen()),
        ),
        GoRoute(
          path: '/contact',
          builder: (context, state) => _wrap(const ContactScreen()),
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
          path: '/hostels',
          builder: (context, state) => _wrap(const HostelsScreen()),
        ),
        GoRoute(
          path: '/hostels/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return _wrap(HostelDetailScreen(hostelId: id));
          },
        ),
        GoRoute(
          path: '/bookings',
          builder: (context, state) => _wrap(const BookingsScreen()),
        ),
        GoRoute(
          path: '/book/:bookingId',
          builder: (context, state) {
            final bookingId = state.pathParameters['bookingId']!;
            return _wrap(BookingConfirmScreen(bookingId: bookingId));
          },
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => _wrap(const ProfileScreen()),
        ),
        GoRoute(
          path: '/landlord',
          builder: (context, state) => _wrap(const LandlordDashboardScreen()),
        ),
        GoRoute(
          path: '/admin',
          builder: (context, state) => _wrap(const AdminDashboardScreen()),
        ),
      ],
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
