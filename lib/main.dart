// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart'; // ← new

// ── Global navigator key — shared with NotificationService so it can
//    call go_router navigation when the user taps a notification.
final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final authService = AuthService();

  // Router created ONCE — never recreated on rebuilds
  final router = AppRouter.router(authService);

  // Boot notifications: requests OS permission on first launch,
  // wires foreground / background / terminated tap handlers.
  await NotificationService.instance.init(
    navKey: _navigatorKey,
    router: router, // lets the service use go_router for navigation
  );

  // Whenever auth state changes to a real user, persist the FCM token
  authService.addListener(() {
    final uid = authService.currentUser?.id ?? '';
    if (uid.isNotEmpty) {
      NotificationService.instance.saveTokenForUser(uid);
    }
  });

  runApp(
    ChangeNotifierProvider<AuthService>.value(
      value: authService,
      child: RoomzyFindApp(router: router, navigatorKey: _navigatorKey),
    ),
  );
}

class RoomzyFindApp extends StatelessWidget {
  const RoomzyFindApp({
    super.key,
    required this.router,
    required this.navigatorKey,
  });

  final dynamic router;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    // context.read — NOT context.watch — so rebuilds don't affect the router
    return MaterialApp.router(
      title: 'RoomzyFind',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
      scrollBehavior: _AppScrollBehavior(),
      builder: _responsiveBuilder,
    );
  }

  Widget _responsiveBuilder(BuildContext context, Widget? child) {
    return ResponsiveBreakpoints.builder(
      child: child!,
      breakpoints: const [
        Breakpoint(start: 0, end: 450, name: MOBILE),
        Breakpoint(start: 451, end: 800, name: TABLET),
        Breakpoint(start: 801, end: 1280, name: DESKTOP),
        Breakpoint(start: 1281, end: double.infinity, name: '4K'),
      ],
    );
  }
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.mouse,
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
      };
}
