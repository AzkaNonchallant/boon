import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/models/transfer_record.dart';
import '../../core/networking/boon_link.dart';
import '../../core/protocol/boon_message.dart';

typedef TransferSend = Future<void> Function(
  String peerId,
  String type,
  Map<String, dynamic> payload,
);

/// File transfer over an already authenticated Boon link.
///
/// The receiver acknowledges the request, then acknowledges the final
/// checksum. A sender is only marked completed after that second response.
class TransferService {
  TransferService({
    required this.link,
    required this.getPeerName,
    required this.onUpdated,
    this.onIncomingCompleted,
  });

  final BoonLink link;
  final String Function(String peerId) getPeerName;
  final void Function() onUpdated;
  final FutureOr<void> Function(TransferRecord record)? onIncomingCompleted;

  static const chunkSize = 128 * 1024;
  static const _responseTimeout = Duration(seconds: 20);

  final List<TransferRecord> history = [];
  final Map<String, _IncomingTransfer> _incoming = {};
  final Map<String, Completer<bool>> _accepted = {};
  final Map<String, Completer<bool>> _completed = {};
  final List<TransferRecord> _pendingSends = [];

  bool _sendingBusy = false;
  bool _historyLoaded = false;
  Future<void> _saveQueue = Future<void>.value();

  /// Loads metadata only. File contents are never copied into history.
  Future<void> loadHistory() async {
    if (_historyLoaded) return;
    _historyLoaded = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}transfers.json');
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;
      for (final value in decoded) {
        if (value is Map<String, dynamic>) {
          try {
            history.add(TransferRecord.fromJson(value));
          } catch (_) {
            // Ignore one corrupt record instead of hiding the whole history.
          }
        }
      }
    } catch (_) {
      // History is best effort and must not block device connectivity.
    }
  }

  void _persistHistory() {
    _saveQueue = _saveQueue.then<void>((_) async {
      try {
        final dir = await getApplicationSupportDirectory();
        await dir.create(recursive: true);
        final file = File('${dir.path}${Platform.pathSeparator}transfers.json');
        await file.writeAsString(
          jsonEncode(history.map((r) => r.toJson()).toList()),
        );
      } catch (_) {
        // The live transfer remains usable when local history cannot be saved.
      }
    });
  }

  void _updated({bool persist = false}) {
    if (persist) _persistHistory();
    onUpdated();
  }

  /// Offers a local file to a trusted peer.
  Future<void> offer(String peerId, String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;
    final record = TransferRecord(
      id: 't${DateTime.now().microsecondsSinceEpoch}',
      fileName: file.uri.pathSegments.last,
      sizeBytes: await file.length(),
      peerId: peerId,
      peerName: getPeerName(peerId),
      outgoing: true,
      time: DateTime.now(),
      status: TransferStatus.queued,
      path: filePath,
    );
    history.add(record);
    _pendingSends.add(record);
    _updated(persist: true);
    unawaited(_drainQueue());
  }

  Future<void> cancel(String transferId) async {
    final record = find(transferId);
    if (record == null ||
        (record.status != TransferStatus.queued &&
            record.status != TransferStatus.active)) {
      return;
    }

    record.status = TransferStatus.cancelled;
    _pendingSends.remove(record);
    _accepted[transferId]?.complete(false);
    _completed[transferId]?.complete(false);
    final incoming = _incoming.remove(transferId);
    await incoming?.sink.close();
    await record.file?.delete();
    try {
      await link.sendToPeer(record.peerId, BoonMessage.tTransferCancel, {
        'transferId': transferId,
      });
    } catch (_) {}
    _updated(persist: true);
  }

  Future<void> _drainQueue() async {
    if (_sendingBusy) return;
    _sendingBusy = true;
    try {
      while (_pendingSends.isNotEmpty) {
        await _sendOne(_pendingSends.removeAt(0));
      }
    } finally {
      _sendingBusy = false;
    }
  }

  Future<void> _sendOne(TransferRecord record) async {
    final path = record.path;
    if (path == null) {
      record.status = TransferStatus.failed;
      _updated(persist: true);
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      record.status = TransferStatus.failed;
      _updated(persist: true);
      return;
    }

    record.status = TransferStatus.active;
    _updated(persist: true);
    final accepted = Completer<bool>();
    final completed = Completer<bool>();
    _accepted[record.id] = accepted;
    _completed[record.id] = completed;

    try {
      final digest = await sha256.bind(file.openRead()).first;
      await link.sendToPeer(record.peerId, BoonMessage.tTransferRequest, {
        'transferId': record.id,
        'name': record.fileName,
        'size': record.sizeBytes,
        'sha256': digest.toString(),
      });

      final canSend = await accepted.future.timeout(
        _responseTimeout,
        onTimeout: () => false,
      );
      if (!canSend || record.status == TransferStatus.cancelled) {
        if (record.status != TransferStatus.cancelled) {
          record.status = TransferStatus.failed;
          _updated(persist: true);
        }
        return;
      }

      final totalChunks = record.sizeBytes == 0
          ? 1
          : (record.sizeBytes + chunkSize - 1) ~/ chunkSize;
      var index = 0;
      await for (final bytes in file.openRead()) {
        if (record.status == TransferStatus.cancelled) return;
        await link.sendToPeer(record.peerId, BoonMessage.tTransferChunk, {
          'transferId': record.id,
          'index': index,
          'data': base64Encode(bytes),
        });
        index++;
        record.progress = (index / totalChunks).clamp(0.0, 1.0);
        _updated();
      }
      await link.sendToPeer(record.peerId, BoonMessage.tTransferEnd, {
        'transferId': record.id,
      });

      final verified = await completed.future.timeout(
        _responseTimeout,
        onTimeout: () => false,
      );
      if (record.status != TransferStatus.cancelled) {
        record.progress = verified ? 1 : record.progress;
        record.status = verified
            ? TransferStatus.completed
            : TransferStatus.failed;
        _updated(persist: true);
      }
    } catch (_) {
      if (record.status != TransferStatus.cancelled) {
        record.status = TransferStatus.failed;
        _updated(persist: true);
      }
    } finally {
      _accepted.remove(record.id);
      _completed.remove(record.id);
    }
  }

  TransferRecord? find(String transferId) {
    for (final record in history) {
      if (record.id == transferId) return record;
    }
    return null;
  }

  Future<void> handle(
    String peerId,
    String type,
    Map<String, dynamic> payload,
  ) async {
    switch (type) {
      case BoonMessage.tTransferRequest:
        await _startIncoming(peerId, payload);
      case BoonMessage.tTransferAccept:
        if (payload['accepted'] == true) {
          _accepted[payload['transferId'] as String? ?? '']?.complete(true);
        }
      case BoonMessage.tTransferChunk:
        await _receiveChunk(payload);
      case BoonMessage.tTransferEnd:
        await _finishIncoming(peerId, payload);
      case BoonMessage.tTransferComplete:
        _completed[payload['transferId'] as String? ?? '']?.complete(true);
      case BoonMessage.tTransferReject:
        _rejectOutgoing(payload['transferId'] as String? ?? '');
      case BoonMessage.tTransferCancel:
        await _handleRemoteCancel(payload['transferId'] as String? ?? '');
    }
  }

  Future<void> _startIncoming(
    String peerId,
    Map<String, dynamic> payload,
  ) async {
    final id = payload['transferId'] as String? ?? '';
    final size = (payload['size'] as num?)?.toInt() ?? -1;
    final expectedSha = payload['sha256'] as String? ?? '';
    if (id.isEmpty ||
        size < 0 ||
        expectedSha.isEmpty ||
        _incoming.containsKey(id)) {
      return;
    }

    final name = _safeName(payload['name'] as String? ?? 'file');
    try {
      final dir = await _downloadsDir();
      final path = await _uniquePath(dir, name);
      final file = File(path);
      await file.create();
      final record = TransferRecord(
        id: id,
        fileName: name,
        sizeBytes: size,
        peerId: peerId,
        peerName: getPeerName(peerId),
        outgoing: false,
        time: DateTime.now(),
        status: TransferStatus.active,
        path: path,
      )..file = file;
      record.expectSha = expectedSha;
      record.received = 0;
      final incoming = _IncomingTransfer(
        record: record,
        sink: file.openWrite(),
      );
      history.add(record);
      _incoming[id] = incoming;
      await link.sendToPeer(peerId, BoonMessage.tTransferAccept, {
        'transferId': id,
        'accepted': true,
      });
      _updated(persist: true);
    } catch (_) {
      await _sendReject(peerId, id, 'Unable to create destination file');
    }
  }

  Future<void> _receiveChunk(Map<String, dynamic> payload) async {
    final id = payload['transferId'] as String? ?? '';
    final incoming = _incoming[id];
    if (incoming == null) return;
    final index = (payload['index'] as num?)?.toInt();
    final encoded = payload['data'] as String?;
    if (index != incoming.nextIndex || encoded == null) {
      await _failIncoming(incoming, 'Invalid chunk sequence');
      return;
    }
    try {
      final data = base64Decode(encoded);
      final received = (incoming.record.received ?? 0) + data.length;
      if (received > incoming.record.sizeBytes) {
        await _failIncoming(incoming, 'Received more bytes than expected');
        return;
      }
      incoming.sink.add(data);
      incoming.nextIndex++;
      incoming.record.received = received;
      incoming.record.progress = incoming.record.sizeBytes == 0
          ? 0
          : received / incoming.record.sizeBytes;
      _updated();
    } catch (_) {
      await _failIncoming(incoming, 'Invalid transfer chunk');
    }
  }

  Future<void> _finishIncoming(
    String peerId,
    Map<String, dynamic> payload,
  ) async {
    final id = payload['transferId'] as String? ?? '';
    final incoming = _incoming.remove(id);
    if (incoming == null) return;
    await incoming.sink.flush();
    await incoming.sink.close();
    final file = incoming.record.file;
    final received = incoming.record.received ?? 0;
    final digest = file == null
        ? ''
        : (await sha256.bind(file.openRead()).first).toString();
    final verified =
        file != null &&
        received == incoming.record.sizeBytes &&
        digest == incoming.record.expectSha;
    if (verified) {
      incoming.record.progress = 1;
      incoming.record.status = TransferStatus.completed;
      await link.sendToPeer(peerId, BoonMessage.tTransferComplete, {
        'transferId': id,
      });
    } else {
      incoming.record.status = TransferStatus.failed;
      await _sendReject(peerId, id, 'SHA-256 or file size verification failed');
      await file?.delete();
    }
    _updated(persist: true);
    if (verified && onIncomingCompleted != null) {
      await onIncomingCompleted!(incoming.record);
    }
  }

  Future<void> _failIncoming(_IncomingTransfer incoming, String reason) async {
    final id = incoming.record.id;
    if (_incoming.remove(id) == null) return;
    await incoming.sink.close();
    await incoming.record.file?.delete();
    incoming.record.status = TransferStatus.failed;
    await _sendReject(incoming.record.peerId, id, reason);
    _updated(persist: true);
  }

  Future<void> _sendReject(String peerId, String id, String reason) async {
    try {
      await link.sendToPeer(peerId, BoonMessage.tTransferReject, {
        'transferId': id,
        'reason': reason,
      });
    } catch (_) {}
  }

  void _rejectOutgoing(String id) {
    if (id.isEmpty) return;
    _accepted[id]?.complete(false);
    _completed[id]?.complete(false);
    final record = find(id);
    if (record != null &&
        record.status != TransferStatus.completed &&
        record.status != TransferStatus.cancelled) {
      record.status = TransferStatus.failed;
      _updated(persist: true);
    }
  }

  Future<void> _handleRemoteCancel(String id) async {
    if (id.isEmpty) return;
    final incoming = _incoming.remove(id);
    if (incoming != null) {
      await incoming.sink.close();
      await incoming.record.file?.delete();
      incoming.record.status = TransferStatus.cancelled;
      _updated(persist: true);
      return;
    }
    final record = find(id);
    if (record != null && record.status == TransferStatus.active) {
      record.status = TransferStatus.cancelled;
      _accepted[id]?.complete(false);
      _completed[id]?.complete(false);
      _updated(persist: true);
    }
  }

  Future<Directory> _downloadsDir() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null) {
        final downloads = Directory(
          '$home${Platform.pathSeparator}Downloads${Platform.pathSeparator}Boon',
        );
        await downloads.create(recursive: true);
        return downloads;
      }
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}Boon');
    await dir.create(recursive: true);
    return dir;
  }

  String _safeName(String name) {
    final leaf = name.split(RegExp(r'[\\/]')).last.trim();
    final safe = leaf.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return safe.isEmpty ? 'file' : safe;
  }

  Future<String> _uniquePath(Directory dir, String name) async {
    var base = name;
    var ext = '';
    final dot = name.lastIndexOf('.');
    if (dot > 0) {
      base = name.substring(0, dot);
      ext = name.substring(dot);
    }
    for (var i = 0; i < 1000; i++) {
      final candidate = i == 0 ? name : '$base ($i)$ext';
      final path = '${dir.path}${Platform.pathSeparator}$candidate';
      if (!await File(path).exists()) return path;
    }
    return '${dir.path}${Platform.pathSeparator}$base-${DateTime.now().millisecondsSinceEpoch}$ext';
  }

  List<TransferRecord> get recent => List.unmodifiable(history.reversed);

  void markGallerySaved(String transferId) {
    final record = find(transferId);
    if (record == null) return;
    record.gallerySaved = true;
    _updated(persist: true);
  }
}

class _IncomingTransfer {
  _IncomingTransfer({required this.record, required this.sink});

  final TransferRecord record;
  final IOSink sink;
  int nextIndex = 0;
}
