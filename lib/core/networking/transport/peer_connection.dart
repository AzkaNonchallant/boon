import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

/// Line-delimited JSON framing over a TCP socket, shared by initiator and
/// listener sides of the link.
class PeerConnection {
  PeerConnection._(this._socket, this.remoteHost);

  final Socket _socket;
  final String remoteHost;
  final _buffer = BytesBuilder();
  bool _closed = false;

  /// Single frame handler. Frames are delivered exactly once — a second
  /// (subscription-based) path could drop buffered frames between
  /// listener swaps during the handshake.
  void Function(String line)? onLine;
  void Function()? onClosed;

  bool get isClosed => _closed;

  Socket get rawSocket => _socket;

  static Future<PeerConnection> connectTo(String host, int port) async {
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
    final conn = PeerConnection._(socket, host);
    conn._listen();
    return conn;
  }

  static PeerConnection fromSocket(Socket socket) {
    final conn = PeerConnection._(
      socket,
      socket.remoteAddress.address,
    );
    conn._listen();
    return conn;
  }

  void _listen() {
    _socket.listen(
      (data) {
        _buffer.add(data);
        final bytes = _buffer.takeBytes();
        var start = 0;
        for (var i = 0; i < bytes.length; i++) {
          if (bytes[i] == 0x0A) {
            final line = utf8.decode(bytes.sublist(start, i), allowMalformed: true);
            onLine?.call(line);
            start = i + 1;
          }
        }
        final rest = bytes.sublist(start);
        _buffer.add(rest);
      },
      onDone: () {
        close();
        onClosed?.call();
      },
      onError: (_) {
        close();
        onClosed?.call();
      },
    );
  }

  void sendJson(Map<String, dynamic> json) {
    if (_closed) return;
    try {
      _socket.add(utf8.encode('${jsonEncode(json)}\n'));
    } catch (_) {
      close();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _socket.destroy();
  }
}
