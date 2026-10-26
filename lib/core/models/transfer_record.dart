import 'dart:io';

enum TransferStatus { queued, active, completed, failed, cancelled }

/// Transfer metadata stored locally for the history view.
/// The record doubles as live progress state while a transfer runs.
class TransferRecord {
  TransferRecord({
    required this.id,
    required this.fileName,
    required this.sizeBytes,
    required this.peerId,
    required this.peerName,
    required this.outgoing,
    required this.time,
    this.status = TransferStatus.queued,
    this.progress = 0,
    this.gallerySaved = false,
    this.path,
  });

  final String id;
  final String fileName;
  final int sizeBytes;
  final String peerId;
  final String peerName;
  final bool outgoing;
  final DateTime time;
  TransferStatus status;
  double progress;
  bool gallerySaved;

  /// Local file being sent (outgoing) or being written (incoming).
  File? file;

  /// Sync progress bookkeeping for the receiver.
  int? received;
  String? expectSha;
  String? path;

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'sizeBytes': sizeBytes,
    'peerId': peerId,
    'peerName': peerName,
    'outgoing': outgoing,
    'time': time.toIso8601String(),
    'status': status.name,
    'progress': progress,
    'gallerySaved': gallerySaved,
    if (path != null) 'path': path,
  };

  factory TransferRecord.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? TransferStatus.failed.name;
    final status = TransferStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => TransferStatus.failed,
    );
    final record = TransferRecord(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      peerId: json['peerId'] as String,
      peerName: json['peerName'] as String? ?? 'Device',
      outgoing: json['outgoing'] == true,
      time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
      status: status,
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      gallerySaved: json['gallerySaved'] == true,
      path: json['path'] as String?,
    );
    // An in-flight transfer cannot safely resume after process termination.
    if (record.status == TransferStatus.queued ||
        record.status == TransferStatus.active) {
      record.status = TransferStatus.failed;
    }
    return record;
  }
}
