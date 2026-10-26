import 'dart:io';

import 'package:flutter/services.dart';

/// Android-only file actions. Other platforms return false without throwing.
class AndroidFiles {
  AndroidFiles._();

  static const _channel = MethodChannel('boon/files');

  static bool get available => Platform.isAndroid;

  static Future<bool> saveToGallery({
    required String path,
    required String name,
    required String mimeType,
  }) async {
    if (!available) return false;
    try {
      return await _channel.invokeMethod<bool>('saveToGallery', {
            'path': path,
            'name': name,
            'mimeType': mimeType,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openFile({
    required String path,
    required String mimeType,
  }) async {
    if (!available) return false;
    try {
      return await _channel.invokeMethod<bool>('openFile', {
            'path': path,
            'mimeType': mimeType,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
