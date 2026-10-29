import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:boon/core/networking/link_service.dart';
import 'package:boon/core/protocol/boon_message.dart';
import 'package:boon/core/security/device_identity.dart';

Future<T> waitFor<T>(bool Function() check, T Function() extract) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (DateTime.now().isBefore(deadline)) {
    if (check()) return extract();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('condition was not reached in time');
}

void main() {
  test('one node pairs with multiple peers and broadcasts clipboard text', () async {
    // Isolated store paths so reruns / other suites cannot see prior pairings.
    final dirA = await Directory.systemTemp.createTemp('boon_a');
    final dirB = await Directory.systemTemp.createTemp('boon_b');
    final dirC = await Directory.systemTemp.createTemp('boon_c');
    final nodeA = LinkService(
      _fakeIdentity('A', 'node-a'),
      linkPortOverride: 45560,
      storePath: '${dirA.path}/trusted.json',
    );
    final nodeB = LinkService(
      _fakeIdentity('B', 'node-b'),
      linkPortOverride: 45561,
      storePath: '${dirB.path}/trusted.json',
    );
    final nodeC = LinkService(
      _fakeIdentity('C', 'node-c'),
      linkPortOverride: 45562,
      storePath: '${dirC.path}/trusted.json',
    );
    await nodeA.start();
    await nodeB.start();
    await nodeC.start();

    final appA = <SecureAppMessage>[];
    final appB = <SecureAppMessage>[];
    final appC = <SecureAppMessage>[];
    nodeA.appData.listen(appA.add);
    nodeB.appData.listen(appB.add);
    nodeC.appData.listen(appC.add);

    final incomingB = <PairingEvent>[];
    final incomingCEvents = <PairingEvent>[];
    final outgoingA = <PairingEvent>[];
    nodeB.pairingEvents.listen(incomingB.add);
    nodeC.pairingEvents.listen(incomingCEvents.add);
    nodeA.pairingEvents.listen(outgoingA.add);

    // A initiates pairing towards B.
    unawaited(nodeA.pairWith('127.0.0.1', 45561));

    // B got an incoming prompt with a code.
    var prompt = await waitFor(
      () => incomingB.any((e) => e.stage == PairingEvent.incoming),
      () => incomingB.firstWhere((e) => e.stage == PairingEvent.incoming),
    );
    expect(prompt.verificationCode, matches(RegExp(r'\d{6}')));

    // B accepts, A receives the code prompt.
    await nodeB.acceptIncomingPairing(prompt.peerId);
    var codeEvent = await waitFor(
      () => outgoingA.any((e) => e.stage == PairingEvent.code),
      () => outgoingA.firstWhere((e) => e.stage == PairingEvent.code),
    );
    expect(codeEvent.verificationCode, prompt.verificationCode);

    // A confirms the code; handshake completes with half-secret exchange.
    await nodeA.confirmOutgoingPairing(codeEvent.peerId);
    await waitFor(
      () => nodeA.trustedDevices.isNotEmpty && nodeB.trustedDevices.isNotEmpty,
      () => nodeA.trustedDevices.length,
    );

    // Pair a second peer to prove one node can hold and broadcast to several
    // independent trusted sessions at once.
    unawaited(nodeA.pairWith('127.0.0.1', 45562));
    final incomingC = await waitFor(
      () => incomingCEvents.any((e) => e.stage == PairingEvent.incoming),
      () => incomingCEvents.firstWhere((e) => e.stage == PairingEvent.incoming),
    );
    await nodeC.acceptIncomingPairing(incomingC.peerId);
    final codeC = await waitFor(
      () => outgoingA.any(
        (e) => e.stage == PairingEvent.code && e.peerId == 'C',
      ),
      () => outgoingA.firstWhere(
        (e) => e.stage == PairingEvent.code && e.peerId == 'C',
      ),
    );
    await nodeA.confirmOutgoingPairing(codeC.peerId);
    await waitFor(
      () => nodeA.trustedDevices.length == 2 && nodeC.trustedDevices.isNotEmpty,
      () => nodeA.trustedDevices.length,
    );

    // Encrypted clipboard fan-out reaches both paired peers.
    await nodeA.sendClipboardText('halo dari A');
    var clipB = await waitFor(
      () => appB.any((m) => m.type == BoonMessage.tClipboardText),
      () => appB.firstWhere((m) => m.type == BoonMessage.tClipboardText),
    );
    expect(clipB.payload['text'], 'halo dari A');
    final clipC = await waitFor(
      () => appC.any((m) => m.type == BoonMessage.tClipboardText),
      () => appC.firstWhere((m) => m.type == BoonMessage.tClipboardText),
    );
    expect(clipC.payload['text'], 'halo dari A');

    await nodeB.sendClipboardText('halo dari B');
    await waitFor(
      () => appA.any((m) => m.type == BoonMessage.tClipboardText),
      () => appA.firstWhere((m) => m.type == BoonMessage.tClipboardText),
    );

    await nodeA.stop();
    await nodeB.stop();
    await nodeC.stop();
    await dirA.delete(recursive: true);
    await dirB.delete(recursive: true);
    await dirC.delete(recursive: true);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

DeviceIdentity _fakeIdentity(String id, String name) =>
    DeviceIdentity(id: id, name: name, type: 'desktop');
