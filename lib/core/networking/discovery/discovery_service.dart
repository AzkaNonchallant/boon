import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/boon_device.dart';

/// Local-network discovery over UDP broadcast.
///
/// Every Boon node broadcasts a small identity packet every 2 seconds on
/// [discoveryPort] and listens for the same from other nodes. No central
/// server involved — peers find each other directly.
///
/// Note: on Android forward this needs CHANGE_WIFI_MULTICAST_STATE and a
/// MulticastLock in the native layer (Phase 2); broadcast discovery on
/// Wi-Fi may be restricted on some networks.
class DiscoveryService {
  static const discoveryPort = 45021;

  final _peersController = StreamController<List<BoonDevice>>.broadcast();
  final Map<String, (BoonDevice, DateTime)> _peers = {};
  RawDatagramSocket? _socket;
  Timer? _advertiseTimer;
  Timer? _pruneTimer;

  Map<String, dynamic> identityPayload;

  DiscoveryService(this.identityPayload);

  static const lifetime = Duration(seconds: 7);

  Stream<List<BoonDevice>> get peers => _peersController.stream;

  Future<void> start() async {
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: false,
      );
      _socket!.broadcastEnabled = true;
      _socket!.listen(_onPacket);
    } on SocketException catch (e) {
      // Discovery unavailable (firewall/permission) — direct connect by
      // IP is still possible via the link layer.
      errored = true;
      lastError = 'Discovery socket unavailable: ${e.message}';
    }
    _advertiseTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _advertise(),
    );
    _pruneTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pruneStale(),
    );
  }

  bool errored = false;
  String? lastError;

  void _advertise() {
    final socket = _socket;
    if (socket == null) return;
    final packet = jsonEncode(identityPayload);
    final data = utf8.encode('$packet\n');
    for (final target in const ['255.255.255.255', '127.0.0.1']) {
      try {
        socket.send(data, InternetAddress(target), discoveryPort);
      } catch (_) {}
    }
  }

  void _onPacket(RawSocketEvent event) {
    final socket = _socket;
    if (event != RawSocketEvent.read || socket == null) return;
    final datagram = socket.receive();
    if (datagram == null) return;
    final text = utf8.decode(datagram.data, allowMalformed: true);
    for (final raw in text.split('\n')) {
      if (raw.trim().isEmpty) continue;
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final device = BoonDevice.fromJson({
          ...json,
          'address': datagram.address.address,
        });
        if (device.id == identityPayload['id']) continue; // own broadcast
        final (_, seen) = _peers[device.id] ?? (null, null);
        if (seen == null || DateTime.now().difference(seen) > const Duration(seconds: 4)) {
          device.lastSeen = DateTime.now();
          _peers[device.id] = (device, DateTime.now());
          _publish();
        }
      } catch (_) {
        // Ignore malformed packets from other apps on the network.
      }
    }
  }

  void _pruneStale() {
    final now = DateTime.now();
    var changed = false;
    _peers.removeWhere((_, pair) {
      final stale = now.difference(pair.$2) > lifetime;
      if (stale) changed = true;
      return stale;
    });
    if (changed) _publish();
  }

  void _publish() {
    if (!_peersController.isClosed) {
      _peersController.add(
        _peers.keys.map((id) => _peers[id]!.$1).toList(),
      );
    }
  }

  Future<void> stop() async {
    _advertiseTimer?.cancel();
    _pruneTimer?.cancel();
    _socket?.close();
    _socket = null;
    await _peersController.close();
  }
}
