import 'dart:io';

import 'package:boon/core/networking/transport/peer_connection.dart';
import 'package:boon/core/security/link_crypto.dart';

const desktopId = '6d42fd2571cf495c7af08704572367d9';

List<int> hexToBytes(String hex) {
  final out = <int>[];
  for (var i = 0; i + 1 < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}

Future<void> main(List<String> args) async {
  final ip = args[0];
  final keyHex = args[1];
  final action = args[2];
  final key = hexToBytes(keyHex);

  final conn = await PeerConnection.connectTo(ip, 45022);
  conn.onLine = (line) => stdout.writeln('<- $line');
  conn.sendJson({
    'type': 'hello',
    'from': desktopId,
    'payload': {
      'id': desktopId,
      'name': 'fedora',
      'type': 'desktop',
      'caps': ['clipboard', 'file_transfer'],
    },
  });
  await Future<void>.delayed(const Duration(milliseconds: 400));
  final sealed = await LinkCrypto.encrypt(key, {
    'type': 'media_action',
    'payload': {'action': action},
  });
  conn.sendJson({
    'type': 'secure',
    'from': desktopId,
    'payload': {'data': sealed},
  });
  await Future<void>.delayed(const Duration(seconds: 2));
  await conn.close();
  exit(0);
}
