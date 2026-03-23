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

class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();

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
        GoRoute(
          path: '/',
          builder: (context, state) => const SplashScreen(),
        ),

        // ── Home — intercepts back button to show exit dialog
        GoRoute(
          path: '/home',
          builder: (context, state) => const _BackHandlerWrapper(
            child: HomeScreen(),
          ),
        ),

        GoRoute(
          path: '/about',
          builder: (context, state) => const AboutScreen(),
        ),
        GoRoute(
          path: '/contact',
          builder: (context, state) => const ContactScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: '/hostels',
          builder: (context, state) => const HostelsScreen(),
        ),
        GoRoute(
          path: '/hostels/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return HostelDetailScreen(hostelId: id);
          },
        ),
        GoRoute(
          path: '/bookings',
          builder: (context, state) => const BookingsScreen(),
        ),

        // ── Booking confirm — uses bookingId (Firestore doc ID)
        GoRoute(
          path: '/book/:bookingId',
          builder: (context, state) {
            final bookingId = state.pathParameters['bookingId']!;
            return BookingConfirmScreen(bookingId: bookingId);
          },
        ),

        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/landlord',
          builder: (context, state) => const LandlordDashboardScreen(),
        ),
        GoRoute(
          path: '/admin',
          builder: (context, state) => const AdminDashboardScreen(),
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
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
    );
  }
}

// ─── Back Button Handler ──────────────────────────────────────────────────────

class _BackHandlerWrapper extends StatelessWidget {
  final Widget child;
  const _BackHandlerWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (context.canPop()) {
          context.pop();
          return;
        }

        final shouldExit = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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
                child: const Text('Stay',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: Color(0xFF0F766E))),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Exit',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

        if (shouldExit == true && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: child,
    );
  }
}
