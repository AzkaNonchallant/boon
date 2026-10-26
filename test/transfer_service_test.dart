import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:boon/core/models/transfer_record.dart';
import 'package:boon/core/networking/boon_link.dart';
import 'package:boon/core/networking/link_service.dart';
import 'package:boon/services/transfer/transfer_service.dart';

void main() {
  test(
    'transfers a file and completes only after receiver verification',
    () async {
      late TransferService sender;
      late TransferService receiver;
      final senderLink = _LoopbackLink();
      final receiverLink = _LoopbackLink();

      sender = TransferService(
        link: senderLink,
        getPeerName: (_) => 'Receiver',
        onUpdated: () {},
      );
      receiver = TransferService(
        link: receiverLink,
        getPeerName: (_) => 'Sender',
        onUpdated: () {},
      );
      senderLink.forward = (type, payload) =>
          receiver.handle('sender', type, payload);
      receiverLink.forward = (type, payload) =>
          sender.handle('receiver', type, payload);

      final sourceDir = await Directory.systemTemp.createTemp('boon_transfer');
      final source = File('${sourceDir.path}/hello.txt');
      await source.writeAsString('hello from boon');

      await sender.offer('receiver', source.path);
      await _waitFor(
        () => sender.history.first.status == TransferStatus.completed,
      );

      expect(receiver.history.single.status, TransferStatus.completed);
      expect(
        await receiver.history.single.file!.readAsString(),
        'hello from boon',
      );

      await receiver.history.single.file!.delete();
      await sourceDir.delete(recursive: true);
    },
  );
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('transfer did not complete in time');
}

class _LoopbackLink implements BoonLink {
  Future<void> Function(String type, Map<String, dynamic> payload)? forward;

  @override
  Stream<SecureAppMessage> get appData => const Stream.empty();

  @override
  Stream<void> get sessionsChanged => const Stream.empty();

  @override
  bool get hasLinkedPeer => true;

  @override
  Future<void> sendClipboardText(String text) async {}

  @override
  Future<void> sendToPeer(
    String peerId,
    String type,
    Map<String, dynamic> payload,
  ) async {
    await forward?.call(type, payload);
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
