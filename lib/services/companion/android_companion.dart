import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Results read from the device battery broadcast.
class AndroidBattery {
  const AndroidBattery({required this.level, required this.charging});

  /// 0–100, or -1 when unknown.
  final int level;
  final bool charging;
}

/// Native companions used by the Android build:
///
/// - "boon/status"    device status (battery, model name)
/// - "boon/discovery" Wi-Fi multicast lock for UDP discovery
///
/// Every method is a safe no-op off Android so the same AppState wiring
/// runs unchanged on Windows/Linux.
class AndroidCompanion {
  AndroidCompanion._();

  static const _status = MethodChannel('boon/status');
  static const _discovery = MethodChannel('boon/discovery');

  static bool get available =>
      !kIsWeb && Platform.isAndroid;

  static Future<void> start() async {
    if (!available) return;
    try {
      await _status.invokeMethod('start');
    } catch (e) {
      debugPrint('AndroidCompanion.start failed: $e');
    }
  }

  static Future<void> stop() async {
    if (!available) return;
    try {
      await _status.invokeMethod('stop');
    } catch (e) {
      debugPrint('AndroidCompanion.stop failed: $e');
    }
  }

  /// Current battery state, or null when unavailable/unknown.
  static Future<AndroidBattery?> readBattery() async {
    if (!available) return null;
    try {
      final json = await _status.invokeMapMethod<String, dynamic>('battery');
      final level = (json?['level'] as num?)?.toInt() ?? -1;
      if (level < 0) return null;
      return AndroidBattery(level: level, charging: json?['charging'] == true);
    } catch (e) {
      debugPrint('AndroidCompanion.readBattery failed: $e');
      return null;
    }
  }

  /// Human-readable model name (e.g. "Google Pixel 8"), null off Android.
  static Future<String?> deviceName() async {
    if (!available) return null;
    try {
      return await _status.invokeMethod<String>('deviceName');
    } catch (e) {
      debugPrint('AndroidCompanion.deviceName failed: $e');
      return null;
    }
  }

  /// Must be acquired before the discovery socket binds, released on stop —
  /// otherwise Wi-Fi multicast/broadcast packets are dropped by the kernel.
  static Future<void> acquireMulticast() async {
    if (!available) return;
    try {
      await _discovery.invokeMethod('acquire');
    } catch (e) {
      debugPrint('AndroidCompanion.acquireMulticast failed: $e');
    }
  }

  static Future<void> releaseMulticast() async {
    if (!available) return;
    try {
      await _discovery.invokeMethod('release');
    } catch (e) {
      debugPrint('AndroidCompanion.releaseMulticast failed: $e');
    }
  }
}
