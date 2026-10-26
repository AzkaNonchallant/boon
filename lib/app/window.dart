import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native window shell for the floating Boon widget (Windows).
///
/// All behavior lives in the native runner (windows/runner):
///   - win32_window.cpp applies the frameless + transparent composition
///     (WS_CAPTION stripped, DwmExtendFrameIntoClientArea, transparent accent
///     policy) so the desktop wallpaper is visible behind the dashboard.
///   - flutter_window.cpp exposes the "boon/window" method channel used here.
///
/// Calls are safe no-ops on platforms without this runner (Linux etc.).
class BoonWindow {
  BoonWindow._();

  static const MethodChannel _channel = MethodChannel('boon/window');

  static bool get supportsWidget => Platform.isWindows;

  static bool _alwaysOnTop = true;

  static bool get alwaysOnTop => _alwaysOnTop;

  static Future<void> configure() async {
    if (!supportsWidget) return;
    await setAlwaysOnTop(_alwaysOnTop);
  }

  static Future<void> setAlwaysOnTop(bool on) async {
    _alwaysOnTop = on;
    if (!supportsWidget) return;
    try {
      await _channel.invokeMethod<void>('setAlwaysOnTop', on);
    } catch (e) {
      debugPrint('BoonWindow.setAlwaysOnTop failed: $e');
    }
  }

  /// Initiates a native title-bar drag (frameless window move).
  static Future<void> startDragging() async {
    if (!supportsWidget) return;
    try {
      await _channel.invokeMethod<void>('startDragging');
    } catch (e) {
      debugPrint('BoonWindow.startDragging failed: $e');
    }
  }

  static Future<void> minimize() async {
    if (!supportsWidget) return;
    try {
      await _channel.invokeMethod<void>('minimize');
    } catch (e) {
      debugPrint('BoonWindow.minimize failed: $e');
    }
  }

  static Future<void> close() async {
    if (!supportsWidget) return;
    await _channel.invokeMethod<void>('close');
  }
}
