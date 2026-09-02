// lib/services/onesignal_web_impl.dart
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

Future<String?> getOneSignalWebPlayerId() async {
  try {
    final globalThis = globalContext;
    if (!globalThis.hasProperty('getOneSignalPlayerId'.toJS).toDart) {
      return null;
    }
    final fn =
        globalThis.getProperty('getOneSignalPlayerId'.toJS) as JSFunction;
    final promise = fn.callAsFunction(globalThis) as JSPromise;
    final result = await promise.toDart;
    return (result as JSString?)?.toDart;
  } catch (_) {
    return null;
  }
}
