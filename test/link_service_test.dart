import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:boon/core/networking/link_service.dart';
import 'package:boon/core/protocol/boon_message.dart';
import 'package:boon/core/security/device_identity.dart';

Future<T> waitFor<T>(
  bool Function() check,
  T Function() extract,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (DateTime.now().isBefore(deadline)) {
    if (check()) return extract();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('condition was not reached in time');
}

void main() {
  test('two nodes pair and exchange encrypted clipboard text', () async {
    // Isolated store paths so reruns / other suites cannot see prior pairings.
    final dirA = await Directory.systemTemp.createTemp('boon_a');
    final dirB = await Directory.systemTemp.createTemp('boon_b');
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
    await nodeA.start();
    await nodeB.start();

    final appA = <SecureAppMessage>[];
    final appB = <SecureAppMessage>[];
    nodeA.appData.listen(appA.add);
    nodeB.appData.listen(appB.add);

    final incomingB = <PairingEvent>[];
    final outgoingA = <PairingEvent>[];
    nodeB.pairingEvents.listen(incomingB.add);
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

    // Encrypted application data flows both directions.
    await nodeA.sendClipboardText('halo dari A');
    var clipB = await waitFor(
      () => appB.any((m) => m.type == BoonMessage.tClipboardText),
      () => appB.firstWhere((m) => m.type == BoonMessage.tClipboardText),
    );
    expect(clipB.payload['text'], 'halo dari A');

    await nodeB.sendClipboardText('halo dari B');
    await waitFor(
      () => appA.any((m) => m.type == BoonMessage.tClipboardText),
      () => appA.firstWhere((m) => m.type == BoonMessage.tClipboardText),
    );

    await nodeA.stop();
    await nodeB.stop();
    await dirA.delete(recursive: true);
    await dirB.delete(recursive: true);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

DeviceIdentity _fakeIdentity(String id, String name) =>
    DeviceIdentity(id: id, name: name, type: 'desktop');
