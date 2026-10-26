import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper around the "boon/service" method channel that controls the
/// Kotlin [BoonForegroundService].
///
/// The service keeps the process (and hence the already running Dart engine,
/// sockets and timers) at foreground priority while the activity is
/// backgrounded. Every method is a safe no-op off Android, same as
/// [AndroidCompanion] — desktop does not need it.
class ForegroundService {
  ForegroundService._();

  static const MethodChannel _channel = MethodChannel('boon/service');

  static bool get available => !kIsWeb && Platform.isAndroid;

  /// Starts (or idempotently re-affirms) the foreground service with its
  /// "Boon link aktif" notification. Only called on app start and when the
  /// user turns the keep-alive toggle on — never from lifecycle events.
  static Future<void> start() async {
    if (!available) return;
    try {
      await _channel.invokeMethod('start');
    } catch (e) {
      debugPrint('ForegroundService.start failed: $e');
    }
  }

  /// Stops the service and removes the persistent notification. Only called
  /// when the user turns the toggle off.
  static Future<void> stop() async {
    if (!available) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      debugPrint('ForegroundService.stop failed: $e');
    }
  }

  /// API 33+: asks for POST_NOTIFICATIONS once. Returns false if the OS
  /// permission dialog had to be shown (the answer arrives async). The
  /// service still runs as an FGS without the grant — only the tray
  /// notification may be invisible, so the user cannot see the toggle state.
  static Future<bool> ensureNotificationPermission() async {
    if (!available) return true;
    try {
      final granted = await _channel.invokeMethod<bool>(
        'requestNotificationPermission',
      );
      return granted ?? true;
    } catch (e) {
      debugPrint('ForegroundService.ensureNotificationPermission failed: $e');
      return true;
    }
  }
}
