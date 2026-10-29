import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/boon_device.dart';
import '../protocol/boon_message.dart';
import '../security/link_crypto.dart';
import '../security/device_identity.dart';
import '../security/trusted_store.dart';
import 'discovery/discovery_service.dart';
import 'transport/peer_connection.dart';
import 'boon_link.dart';

/// One side of a Boon link: identity of the remote device + the
/// connection and its (optional) session key.
class LinkSession {
  LinkSession(this.info, this.conn);

  BoonDevice info;
  PeerConnection conn;
  List<int>? key;

  /// Last frame seen on this connection; drives the keep-alive reaper
  /// that clears half-open sockets.
  DateTime lastActivity = DateTime.now();

  // Pairing handshake working state (cleared once paired).
  String? pendingIncomingNonce;
  String? pendingIncomingOwnNonce;
  String? pendingIncomingCode;
  String? pendingIncomingHalf;
  String? pendingOutgoingHalf;
  String? pendingOutgoingNonce;

  bool get paired => key != null;
}

/// A pairing interaction shown in the UI.
class PairingEvent {
  PairingEvent({
    required this.peerId,
    required this.peerName,
    required this.stage,
    this.verificationCode,
  });

  static const incoming = 'incoming'; // remote asked to pair; show prompt
  static const outgoingWaiting = 'outgoing'; // we asked; waiting confirm
  static const code = 'code'; // both sides now display the code
  static const complete = 'complete';
  static const rejected = 'rejected';
  static const failed = 'failed';

  final String peerId;
  final String peerName;
  final String stage;
  final String? verificationCode;
}

/// Decrypted application-layer message from a peer.
class SecureAppMessage {
  SecureAppMessage(this.peerId, this.type, this.payload);

  final String peerId;
  final String type;
  final Map<String, dynamic> payload;
}

/// Orchestrates discovery, pairing, authenticated sessions and secure
/// application messages. Runs entirely between peers on the LAN —
/// there is no central server.
class LinkService implements BoonLink {
  LinkService(this.identity, {this.linkPortOverride, String? storePath})
      : trusted = TrustedDeviceStore(storePath: storePath);

  final DeviceIdentity identity;

  /// Allows overriding the TCP link port (useful for running two nodes
  /// on one machine in tests); falls back to [linkPort].
  final int? linkPortOverride;

  late final int _linkPort = linkPortOverride ?? linkPort;

  final TrustedDeviceStore trusted;

  @override
  bool get hasLinkedPeer => _sessions.values.any((s) => s.paired);

  late final DiscoveryService _discovery = DiscoveryService({
    'id': identity.id,
    'name': identity.name,
    'type': identity.type,
    'port': _linkPort,
    'caps': ['clipboard', 'file_transfer', 'notifications', 'media_control'],
  });

  static const linkPort = 45022;

  final Map<String, LinkSession> _sessions = {};
  ServerSocket? _server;

  final _pairingStream = StreamController<PairingEvent>.broadcast();
  final _appDataStream = StreamController<SecureAppMessage>.broadcast();
  final _sessionsChanged = StreamController<void>.broadcast();

  Stream<PairingEvent> get pairingEvents => _pairingStream.stream;
  @override
  Stream<SecureAppMessage> get appData => _appDataStream.stream;
  @override
  Stream<void> get sessionsChanged => _sessionsChanged.stream;
  Stream<List<BoonDevice>> get discoveredPeers => _discovery.peers;

  bool get discoveryUnavailable => _discovery.errored;
  String? get discoveryErrorText => _discovery.lastError;

  List<PairedDevice> get trustedDevices => trusted.all.values.toList();

  List<BoonDevice> get connectedDevices =>
      _sessions.keys.map((id) => _sessions[id]!.info).toList();

  bool _started = false;
  final Map<String, DateTime> _connectAttempts = {};
  Timer? _keepAliveTimer;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await trusted.load();
    await _discovery.start();
    _discovery.peers.listen(_onDiscovered);
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, _linkPort);
    _server!.listen(_onInboundConnection);
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 20), (_) => _keepAlive());
  }

  /// Half-open TCP sockets never notice the peer disappeared: no FIN/error
  /// until a write fails or never. Ping every session and drop sessions
  /// that stopped answering, so status and reconnect behavior stay honest.
  void _keepAlive() {
    final now = DateTime.now();
    for (final session in List.of(_sessions.values)) {
      if (_sessions[session.info.id] != session) continue;
      // Never reap while a pairing handshake is mid-flight.
      final pairingInFlight = session.pendingOutgoingNonce != null ||
          session.pendingIncomingNonce != null;
      if (pairingInFlight) continue;
      session.conn.sendJson({'type': BoonMessage.tPing, 'from': identity.id, 'payload': const {}});
      final idle = now.difference(session.lastActivity);
      final limit = session.info.id.startsWith('pending:')
          ? const Duration(seconds: 30)
          : const Duration(seconds: 75);
      if (idle > limit) {
        unawaited(session.conn.close());
        if (_sessions[session.info.id] == session) {
          _sessions.remove(session.info.id);
          _notifySessions();
        }
      }
    }
  }

  @override
  Future<void> stop() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    await _discovery.stop();
    final conns = [for (final s in _sessions.values) s.conn];
    _sessions.clear();
    for (final conn in conns) {
      await conn.close();
    }
    await _server?.close();
    _server = null;
    _started = false;
  }

  // ------------------------------------------------------------------
  // Discovery-driven auto-connect (trusted peers only)
  // ------------------------------------------------------------------

  void _onDiscovered(List<BoonDevice> devices) {
    for (final d in devices) {
      if (!trusted.isTrusted(d.id)) continue;
      final session = _sessions[d.id];
      if (session != null && session.conn.isClosed) {
        _sessions.remove(d.id);
        _notifySessions();
      }
      if (_sessions.containsKey(d.id)) continue;
      final last = _connectAttempts[d.id];
      if (last != null && DateTime.now().difference(last) < const Duration(seconds: 5)) {
        continue;
      }
      _connectAttempts[d.id] = DateTime.now();
      _connectTo(d);
    }
  }

  // ------------------------------------------------------------------
  // Connections
  // ------------------------------------------------------------------

  Future<void> _connectTo(BoonDevice device) async {
    final port = device.port ?? _linkPort;
    if (device.address == null) return;
    try {
      final conn = await PeerConnection.connectTo(device.address!, port);
      final session = _registerSession(device, conn);
      if (!identical(session.conn, conn)) {
        // A live session already exists — the duplicate was closed.
        return;
      }
      _wireSession(session);
      conn.sendJson({
        'type': BoonMessage.tHello,
        'from': identity.id,
        'payload': _identityJson(),
      });
    } catch (_) {
      // Peer unreachable right now; discovery will retry.
    }
  }

  Future<void> pairWith(String address, int? port) async {
    try {
      final conn = await PeerConnection.connectTo(address, port ?? _linkPort);
      final probe = BoonDevice(
        id: 'pending:${DateTime.now().microsecondsSinceEpoch}',
        name: address,
        type: DeviceType.unknown,
        address: address,
        port: port ?? _linkPort,
      );
      final session = _registerSession(probe, conn);
      _wireSession(session);
      conn.sendJson({
        'type': BoonMessage.tHello,
        'from': identity.id,
        'payload': _identityJson(),
      });
      final nonce = _randomNonce();
      session.pendingOutgoingHalf = LinkCrypto.randomHalfSecret();
      session.pendingOutgoingNonce = nonce;
      conn.sendJson({
        'type': BoonMessage.tPairRequest,
        'from': identity.id,
        'payload': {'nonce': nonce},
      });
      _pairingStream.add(PairingEvent(
        peerId: session.info.id,
        peerName: session.info.name,
        stage: PairingEvent.outgoingWaiting,
      ));
    } catch (e) {
      _pairingStream.add(
        PairingEvent(peerId: 'unknown', peerName: address, stage: PairingEvent.failed),
      );
    }
  }

  void _onInboundConnection(Socket socket) {
    final conn = PeerConnection.fromSocket(socket);
    conn.onLine = (line) {
      try {
        final msg = BoonMessage.fromJson(jsonDecode(line) as Map<String, dynamic>);
        if (msg.type == BoonMessage.tHello) {
          final device = BoonDevice.fromJson(
            (msg.payload['identity'] ?? msg.payload).cast<String, dynamic>(),
          );
          final existing = _sessions[device.id];
          if (existing != null && identical(existing.conn, conn)) {
            // Already attached to this exact socket — ignore the replay.
            conn.close();
            return;
          }
          if (existing != null) {
            // Prefer the fresh inbound connection: the existing one may be
            // half-open after a network change and would otherwise block
            // reconnection forever.
            _sessions.remove(existing.info.id);
            unawaited(existing.conn.close());
            _notifySessions();
          }
          final session = _registerSession(device, conn);
          _wireSession(session);
          final storeEntry = trusted.all[device.id];
          if (storeEntry != null && storeEntry.keyHex.isNotEmpty) {
            session.key = _keyFromHex(storeEntry.keyHex);
          }
          // Reply with our identity so the peer knows who we are.
          conn.sendJson({
            'type': BoonMessage.tHello,
            'from': identity.id,
            'payload': _identityJson(),
          });
          _notifySessions();
          return;
        }
        final session = _findSession(conn);
        if (session != null) {
          unawaited(_onFrame(session, msg));
        }
      } catch (_) {
        conn.close();
      }
    };
  }

  LinkSession? _findSession(PeerConnection conn) {
    for (final session in _sessions.values) {
      if (identical(session.conn, conn)) return session;
    }
    return null;
  }

  LinkSession _registerSession(BoonDevice device, PeerConnection conn) {
    final existing = _sessions[device.id];
    if (existing != null) {
      // Prefer keeping the current session; close the duplicate.
      conn.close();
      return existing;
    }
    final session = LinkSession(device, conn);
    _sessions[device.id] = session;
    device.lastSeen = DateTime.now();
    return session;
  }

  void _wireSession(LinkSession session) {
    session.conn.onLine = (line) {
      session.lastActivity = DateTime.now();
      try {
        final msg = BoonMessage.fromJson(jsonDecode(line) as Map<String, dynamic>);
        unawaited(_onFrame(session, msg));
      } catch (_) {}
    };
    session.conn.onClosed = () {
      if (_sessions[session.info.id] == session) {
        _sessions.remove(session.info.id);
        _notifySessions();
      }
    };
  }

  Map<String, dynamic> _identityJson() => {
        'id': identity.id,
        'name': identity.name,
        'type': identity.type,
        'caps': const ['clipboard', 'file_transfer'],
      };

  // ------------------------------------------------------------------
  // Pairing state machine
  // ------------------------------------------------------------------

  Future<void> _onFrame(LinkSession session, BoonMessage msg) async {
    _adoptRealId(session, msg);
    switch (msg.type) {
      case BoonMessage.tPing:
        session.conn.sendJson({'type': BoonMessage.tPong, 'from': identity.id, 'payload': const {}});

      case BoonMessage.tPong:
        break; // keep-alive only; lastActivity already refreshed

      case BoonMessage.tHello:
        // Update peer info (e.g. the initiator previously only knew an IP).
        final isNewName = session.info.name == session.info.address;
        session.info.name = (msg.payload['name'] as String?) ?? session.info.name;
        session.info.type = BoonDevice.typeFrom(msg.payload['type'] as String? ?? 'unknown');
        final storeEntry = trusted.all[session.info.id];
        if (storeEntry != null && isNewName) {
          trusted.put(PairedDevice(
            id: session.info.id,
            name: session.info.name,
            keyHex: storeEntry.keyHex,
          ));
        }
        // Outbound/auto-reconnect of an already-trusted peer: the inbound
        // side restores its key on hello, this side must do the same —
        // otherwise both ends sit in a "connected but unauthenticated"
        // session and every secure frame gets dropped silently.
        if (session.key == null &&
            storeEntry != null &&
            storeEntry.keyHex.isNotEmpty) {
          session.key = _keyFromHex(storeEntry.keyHex);
        }
        _notifySessions();

      case BoonMessage.tPairRequest:
        if (session.paired) return;
        final nonce = msg.payload['nonce'] as String? ?? '';
        session.pendingIncomingNonce = nonce;
        final sessionNonce = _randomNonce();
        session.pendingIncomingOwnNonce = sessionNonce;
        session.pendingIncomingHalf = LinkCrypto.randomHalfSecret();
        final code = LinkCrypto.verificationCode(
          material: utf8.encode([nonce, sessionNonce].join('|')),
          idA: identity.id,
          idB: session.info.id,
        );
        session.pendingIncomingCode = code;
        _pairingStream.add(PairingEvent(
          peerId: session.info.id,
          peerName: session.info.name,
          stage: PairingEvent.incoming,
          verificationCode: code,
        ));

      case BoonMessage.tPairAccept:
        if (session.paired || session.pendingOutgoingNonce == null) return;
        final nonceB = msg.payload['nonce'] as String? ?? '';
        final halfB = msg.payload['half'] as String? ?? '';
        session.pendingIncomingCode = LinkCrypto.verificationCode(
          material: utf8.encode([session.pendingOutgoingNonce!, nonceB].join('|')),
          idA: identity.id,
          idB: session.info.id,
        );
        session.pendingIncomingHalf = halfB;
        _pairingStream.add(PairingEvent(
          peerId: session.info.id,
          peerName: session.info.name,
          stage: PairingEvent.code,
          verificationCode: session.pendingIncomingCode,
        ));

      case BoonMessage.tPairConfirm:
        if (session.paired || session.pendingIncomingHalf == null) return;
        final halfA = msg.payload['half'] as String? ?? '';
        session.key = LinkCrypto.sessionKeyFromHalves(session.pendingIncomingHalf!, halfA);
        trusted.put(PairedDevice(
          id: session.info.id,
          name: session.info.name,
          keyHex: _keyToHex(session.key!),
        ));
        _clearPending(session);
        session.conn.sendJson({
          'type': BoonMessage.tPairComplete,
          'from': identity.id,
          'payload': const {},
        });
        _pairingStream.add(PairingEvent(
          peerId: session.info.id,
          peerName: session.info.name,
          stage: PairingEvent.complete,
        ));
        _notifySessions();

      case BoonMessage.tPairComplete:
        if (session.paired) return;
        session.key = LinkCrypto.sessionKeyFromHalves(
          session.pendingOutgoingHalf!,
          session.pendingIncomingHalf!,
        );
        trusted.put(PairedDevice(
          id: session.info.id,
          name: session.info.name,
          keyHex: _keyToHex(session.key!),
        ));
        _clearPending(session);
        _pairingStream.add(PairingEvent(
          peerId: session.info.id,
          peerName: session.info.name,
          stage: PairingEvent.complete,
        ));
        _notifySessions();

      case BoonMessage.tPairReject:
        _pairingStream.add(PairingEvent(
          peerId: session.info.id,
          peerName: session.info.name,
          stage: PairingEvent.rejected,
        ));
        await session.conn.close();
        _sessions.remove(session.info.id);
        _notifySessions();

      case BoonMessage.tSecure:
        if (session.key == null) return; // reject unauthenticated frames
        final decrypted = await LinkCrypto.decrypt(
          session.key!,
          msg.payload['data'] as String? ?? '',
        );
        final type = decrypted?['type'] as String?;
        if (decrypted == null || type == null) return;
        if (!_appDataStream.isClosed) {
          _appDataStream.add(
            SecureAppMessage(session.info.id, type, decrypted['payload'] ?? const {}),
          );
        }
    }
  }

  /// Outbound sessions start with a 'pending:' id until the peer's hello
  /// reveals the real device id. Adopt `from` as soon as any frame with a
  /// real id arrives (pair frames / hello), so codes and the trusted
  /// store use the same key on both sides.
  void _adoptRealId(LinkSession session, BoonMessage msg) {
    final from = msg.from;
    if (from.isEmpty || from == session.info.id) return;
    if (!session.info.id.startsWith('pending:') && session.info.id.startsWith('node-')) {
      return;
    }
    if (!session.info.id.startsWith('pending:')) return;
    _sessions.remove(session.info.id);
    session.info.id = from;
    final store = trusted.all[from];
    if (store != null && store.name != session.info.name && session.info.name != session.info.address) {
      trusted.put(PairedDevice(
        id: from,
        name: session.info.name,
        keyHex: store.keyHex,
      ));
    }
    _sessions[from] = session;
  }

  void _clearPending(LinkSession session) {
    session.pendingIncomingNonce = null;
    session.pendingIncomingOwnNonce = null;
    session.pendingIncomingCode = null;
    session.pendingIncomingHalf = null;
    session.pendingOutgoingHalf = null;
    session.pendingOutgoingNonce = null;
  }

  // ------------------------------------------------------------------
  // User decisions
  // ------------------------------------------------------------------

  /// The remote device asked us to pair; user accepted in the UI.
  Future<void> acceptIncomingPairing(String peerId) async {
    final session = _sessions[peerId];
    if (session == null || session.paired) return;
    session.conn.sendJson({
      'type': BoonMessage.tPairAccept,
      'from': identity.id,
      'payload': {
        'nonce': session.pendingIncomingOwnNonce,
        'half': session.pendingIncomingHalf,
      },
    });
  }

  void rejectIncomingPairing(String peerId) {
    final session = _sessions[peerId];
    session?.conn.sendJson({
      'type': BoonMessage.tPairReject,
      'from': identity.id,
      'payload': const {},
    });
    session?.conn.close();
    _sessions.remove(peerId);
    _notifySessions();
  }

  /// User confirmed the code matches on the initiator side.
  Future<void> confirmOutgoingPairing(String peerId) async {
    final session = _sessions[peerId];
    if (session == null || session.paired) return;
    if (session.pendingIncomingHalf == null || session.pendingOutgoingHalf == null) {
      return;
    }
    final key = LinkCrypto.sessionKeyFromHalves(
      session.pendingOutgoingHalf!,
      session.pendingIncomingHalf!,
    );
    trusted.put(PairedDevice(
      id: session.info.id,
      name: session.info.name,
      keyHex: _keyToHex(key),
    ));
    session.key = key;
    session.conn.sendJson({
      'type': BoonMessage.tPairConfirm,
      'from': identity.id,
      'payload': {'half': session.pendingOutgoingHalf},
    });
    _clearPending(session);
    _pairingStream.add(PairingEvent(
      peerId: peerId,
      peerName: session.info.name,
      stage: PairingEvent.complete,
    ));
    _notifySessions();
  }

  void forgetDevice(String peerId) {
    trusted.remove(peerId);
    final session = _sessions[peerId];
    if (session != null) {
      session.conn.close();
      _sessions.remove(peerId);
    }
    _notifySessions();
  }

  // ------------------------------------------------------------------
  // Secure application messages
  // ------------------------------------------------------------------

  Future<void> _sendSecure(LinkSession session, String type, Map<String, dynamic> payload) async {
    if (!session.paired || session.key == null) return;
    final sealed = await LinkCrypto.encrypt(session.key!, {'type': type, 'payload': payload});
    session.conn.sendJson({
      'type': BoonMessage.tSecure,
      'from': identity.id,
      'payload': {'data': sealed},
    });
  }

  @override
  Future<void> sendClipboardText(String text) async {
    for (final session in List.of(_sessions.values)) {
      await _sendSecure(session, BoonMessage.tClipboardText, {'text': text});
    }
  }

  @override
  Future<void> sendToPeer(String peerId, String type, Map<String, dynamic> payload) async {
    final session = _sessions[peerId];
    if (session == null) return;
    await _sendSecure(session, type, payload);
  }

  Future<void> broadcastStatus(Map<String, dynamic> status) async {
    for (final session in List.of(_sessions.values)) {
      await _sendSecure(session, BoonMessage.tDeviceStatus, status);
    }
  }

  /// Fan-out for application messages that every paired peer may consume
  /// (mirrored notifications, media snapshots).
  Future<void> broadcastApp(String type, Map<String, dynamic> payload) async {
    for (final session in List.of(_sessions.values)) {
      await _sendSecure(session, type, payload);
    }
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  void _notifySessions() {
    if (!_sessionsChanged.isClosed) _sessionsChanged.add(null);
  }

  static String _randomNonce() {
    final bytes = List<int>.generate(8, (_) => Random.secure().nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<int> _keyFromHex(String hex) {
    final out = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  static String _keyToHex(List<int> key) =>
      key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
