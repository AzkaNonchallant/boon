import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:path_provider/path_provider.dart';

/// Local Boon identity: a stable random device id + user-chosen name.
/// The identity file lives in the app-support directory and is created
/// on first run. It is what other devices will see during discovery.
class DeviceIdentity {
  DeviceIdentity({required this.id, required this.name, required this.type});

  final String id;
  final String name;
  final String type;

  static Future<DeviceIdentity> load() async {
    final dir = await supportDir();
    final file = File('${dir.path}${Platform.pathSeparator}identity.json');
    if (await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        return DeviceIdentity(
          id: json['id'] as String,
          name: json['name'] as String,
          type: json['type'] as String? ?? _defaultType(),
        );
      } catch (_) {
        // Corrupt file — regenerate below.
      }
    }
    final identity = DeviceIdentity(
      id: _generateId(),
      name: await _defaultName(),
      type: _defaultType(),
    );
    await file.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'id': identity.id, 'name': identity.name, 'type': identity.type}),
    );
    return identity;
  }

  static String _defaultType() => Platform.isAndroid ? 'phone' : 'desktop';

  /// Android reports 'localhost' for localHostname; prefer the device
  /// model so peers see "Pixel 8", not "localhost".
  static Future<String> _defaultName() async {
    if (!Platform.isAndroid) return Platform.localHostname;
    // Imported lazily here instead of a package import so tests and CLI
    // uses of the core layer keep working without a binding.
    try {
      const channel = MethodChannel('boon/status');
      final name =
          await channel.invokeMethod<String>('deviceName');
      if (name != null && name.trim().isNotEmpty) return name.trim();
    } catch (_) {
      // Channel unavailable — fall through.
    }
    return Platform.localHostname;
  }

  static String _generateId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<Directory> supportDir() async {
    if (Platform.isAndroid) {
      // No HOME environment on Android; path_provider resolves the app's
      // private storage (getApplicationSupportDirectory).
      final dir = await getApplicationSupportDirectory();
      return Directory('${dir.path}${Platform.pathSeparator}boon_identity')
        ..create(recursive: true);
    }
    // Deliberately avoids a path_provider dependency on desktop targets.
    final String base;
    if (Platform.isWindows) {
      base = Platform.environment['APPDATA'] ?? Directory.current.path;
    } else if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '.';
      base =
          Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share';
    } else if (Platform.isMacOS) {
      base = '${Platform.environment['HOME'] ?? '.'}/Library/Application Support';
    } else {
      base = Directory.current.path;
    }
    final dir = Directory('$base${Platform.pathSeparator}boon_identity');
    await dir.create(recursive: true);
    return dir;
  }
}
