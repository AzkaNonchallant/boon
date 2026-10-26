import 'dart:convert';
import 'dart:io';

import 'device_identity.dart';

/// Persistent store of paired (trusted) devices.
/// After a successful pairing each device keeps:
///   { deviceId: { "name": ..., "keyHex": shared secret hex } }
/// Only trusted devices may exchange clipboard/files/notifications.
class TrustedDeviceStore {
  // ignore: no_leaked_values, prefer_initializing_formals
  TrustedDeviceStore({String? storePath}) : _storePath = storePath;

  final String? _storePath;

  final Map<String, PairedDevice> _devices = {};

  Map<String, PairedDevice> get all => Map.unmodifiable(_devices);

  bool isTrusted(String id) => _devices.containsKey(id);

  Future<void> load() async {
    final file = await _file();
    if (!await file.exists()) return;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      for (final entry in json.entries) {
        _devices[entry.key] = PairedDevice.fromJson(
          entry.key,
          (entry.value ?? const {}) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      // Start fresh on a corrupt store rather than blocking pairing.
    }
  }

  Future<void> save() async {
    final file = await _file();
    final json = {for (final e in _devices.entries) e.key: e.value.toJson()};
    await file.writeAsString(jsonEncode(json));
  }

  void put(PairedDevice device) {
    _devices[device.id] = device;
    save();
  }

  void remove(String id) {
    _devices.remove(id);
    save();
  }

  Future<File> _file() async {
    if (_storePath != null) return File(_storePath);
    final dir = await DeviceIdentity.supportDir();
    return File('${dir.path}${Platform.pathSeparator}trusted_devices.json');
  }
}

class PairedDevice {
  PairedDevice({required this.id, required this.name, required this.keyHex});

  final String id;
  final String name;
  final String keyHex;

  factory PairedDevice.fromJson(String id, Map<String, dynamic> json) =>
      PairedDevice(
        id: id,
        name: json['name'] as String? ?? 'Device',
        keyHex: json['keyHex'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'name': name, 'keyHex': keyHex};
}
