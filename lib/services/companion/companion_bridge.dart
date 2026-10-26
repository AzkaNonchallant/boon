import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android Phone Buddy bridge.
///
/// Native side: `MainActivity` ("boon/companion") plus
/// `BoonNotificationListener` (events stream). The listener requires the
/// user to grant Notification Access in system Settings; the same grant
/// unlocks MediaSessionManager, so notifications and media control share
/// one permission.
///
/// Everything is a safe no-op off Android so AppState wiring is unchanged
/// on Windows/Linux.
class CompanionBridge {
  CompanionBridge._();

  static const _channel = MethodChannel('boon/companion');
  static const _eventChannel = EventChannel('boon/companion/events');

  static Stream<Map<String, dynamic>>? _events;

  static bool get available => !kIsWeb && Platform.isAndroid;

  /// Notification and media events from the native listener.
  ///
  /// Map shapes:
  /// - `{kind: listener, connected: bool}`
  /// - `{kind: notification, appId, appName, title, body, time}`
  /// - `{kind: media, available, playing, title?, artist?, album?,
  ///    positionMs?, durationMs?}`
  static Stream<Map<String, dynamic>> get events {
    if (!available) return Stream<Map<String, dynamic>>.empty();
    return _events ??= _eventChannel.receiveBroadcastStream().map(
          (event) => (event as Map).cast<String, dynamic>(),
        );
  }

  /// Whether the system currently lets Boon read notifications/media.
  static Future<bool> isListening() async {
    if (!available) return false;
    try {
      return await _channel.invokeMethod<bool>('isListening') ?? false;
    } catch (e) {
      debugPrint('CompanionBridge.isListening failed: $e');
      return false;
    }
  }

  /// Opens the Android "Notification access" special-access screen.
  static Future<void> openListenerSettings() async {
    if (!available) return;
    try {
      await _channel.invokeMethod('openListenerSettings');
    } catch (e) {
      debugPrint('CompanionBridge.openListenerSettings failed: $e');
    }
  }

  /// Asks the OS to rebind the listener after the user grants access.
  static Future<void> requestRebind() async {
    if (!available) return;
    try {
      await _channel.invokeMethod('requestRebind');
    } catch (e) {
      debugPrint('CompanionBridge.requestRebind failed: $e');
    }
  }

  /// Applies `play|pause|prev|next` to the phone's active media session.
  /// Returns false when no session is available.
  static Future<bool> applyMediaAction(String action) async {
    if (!available) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'applyMediaAction',
            {'action': action},
          ) ??
          false;
    } catch (e) {
      debugPrint('CompanionBridge.applyMediaAction failed: $e');
      return false;
    }
  }
}
