// lib/services/notification_service_web_stub.dart
//
// This file is used ONLY on web (via the conditional import in
// notification_service.dart). It provides empty stand-ins for the OneSignal
// classes so the web build compiles without the native plugin.
//
// Do NOT add real logic here — all OneSignal calls are already guarded by
// kIsWeb checks before they reach any of these stubs.

class OneSignal {
  static final Notifications = _Notifications();
  static final User = _User();

  static void initialize(String appId) {}
}

class _Notifications {
  Future<bool> requestPermission(bool fallbackToSettings) async => false;
  void addClickListener(Function(dynamic) handler) {}
  void addForegroundWillDisplayListener(Function(dynamic) handler) {}
}

class _User {
  final pushSubscription = _PushSubscription();
}

class _PushSubscription {
  String? get id => null;
}
