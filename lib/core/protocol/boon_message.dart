/// Message envelope for the Boon link protocol.
///
/// Transport framing: newline-delimited UTF-8 JSON over TCP.
/// Pairing frames are sent in plaintext; all application data after a
/// successful pairing is encrypted payloads `{iv, data}` (AES-GCM)
/// using the session key agreed during pairing (see core/security).
class BoonMessage {
  BoonMessage({
    required this.type,
    required this.from,
    this.payload = const {},
  });

  final String type;
  final String from;
  final Map<String, dynamic> payload;

  // Handshake / pairing
  static const tHello = 'hello'; // first frame: identity exchange
  static const tPing = 'ping'; // keep-alive (plaintext, no content)
  static const tPong = 'pong'; // keep-alive reply
  static const tPairRequest = 'pair_request';
  static const tPairAccept = 'pair_accept';
  static const tPairConfirm = 'pair_confirm'; // carries our half-secret
  static const tPairComplete = 'pair_complete'; // confirmed on both sides
  static const tPairReject = 'pair_reject';

  // Signed/encrypted application data (payload has iv + data)
  static const tSecure = 'secure';

  // Application message types (inside secure payload 'data')
  static const tClipboardText = 'clipboard_text';
  static const tDeviceStatus = 'device_status';
  static const tMediaState = 'media_state';
  static const tMediaAction = 'media_action';
  static const tSendText = 'send_text';
  static const tSendLink = 'send_link';
  static const tNotification = 'notification';
  static const tCompanionAction = 'companion_action';
  static const tScreenFrame = 'screen_frame';

  // File transfer stream
  static const tTransferRequest = 'transfer_request';
  static const tTransferChunk = 'transfer_chunk';
  static const tTransferEnd = 'transfer_end';
  static const tTransferCancel = 'transfer_cancel';
  static const tTransferAccept = 'transfer_accept';
  static const tTransferReject = 'transfer_reject';
  static const tTransferComplete = 'transfer_complete';

  factory BoonMessage.fromJson(Map<String, dynamic> json) => BoonMessage(
    type: json['type'] as String,
    from: (json['from'] ?? '') as String,
    payload: (json['payload'] ?? const {}) as Map<String, dynamic>,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'from': from,
    'payload': payload,
  };
}
