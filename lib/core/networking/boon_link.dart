import 'dart:async';

import 'link_service.dart';

/// Common exchange surface used by the app state. Implemented by
/// [LinkService] (real LAN peers) and MockLinkService (demo data),
/// so mock and real services are never mixed.
abstract class BoonLink {
  Stream<SecureAppMessage> get appData;
  Stream<void> get sessionsChanged;

  bool get hasLinkedPeer;

  Future<void> start();
  Future<void> stop();

  Future<void> sendClipboardText(String text);
  Future<void> sendToPeer(String peerId, String type, Map<String, dynamic> payload);
}
