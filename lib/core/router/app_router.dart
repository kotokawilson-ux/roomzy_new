import 'package:flutter/material.dart';
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
  // authService is now optional — pass null until auth is ready
  static GoRouter router([AuthService? authService]) {
    return GoRouter(
      initialLocation: '/',
      redirect: (context, state) {
        // Skip all route protection until auth is implemented
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
        GoRoute(
          path: '/home',
          builder: (context, state) => const HomeScreen(),
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
        GoRoute(
          path: '/book/:roomId',
          builder: (context, state) {
            final roomId = int.parse(state.pathParameters['roomId']!);
            return BookingConfirmScreen(roomId: roomId);
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
