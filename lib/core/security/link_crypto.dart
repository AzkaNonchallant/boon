import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

/// Cryptography helpers for the Boon link protocol.
///
/// - Session key: SHA-256 over the two random half-secrets exchanged
///   during pairing (each side contributes one half).
/// - Application messages: AES-256-GCM with random 12-byte nonce,
///   framed as base64(nonce | ciphertext | mac).
class LinkCrypto {
  LinkCrypto._();

  static final AesGcm _aes = AesGcm.with256bits();

  static String randomHalfSecret() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Derives the shared session key from the two pairing half-secrets.
  static List<int> sessionKeyFromHalves(String halfA, String halfB) {
    final sorted = [halfA, halfB]..sort();
    return sha256.convert(utf8.encode(sorted.join('|'))).bytes;
  }

  /// 6-digit verification code both screens show during pairing.
  /// Derived from pairing material + both device ids so the code binds
  /// to this specific exchange.
  static String verificationCode({
    required List<int> material,
    required String idA,
    required String idB,
  }) {
    final ids = [idA, idB]..sort();
    final digest = sha256.convert([...material, ...utf8.encode(ids.join('|'))]);
    final num = (digest.bytes[0] << 8) | digest.bytes[1];
    return (100000 + num % 900000).toString();
  }

  static Future<String> encrypt(List<int> key, Map<String, dynamic> data) async {
    final nonce = List<int>.generate(12, (_) => Random.secure().nextInt(256));
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: SecretKeyData(key),
      nonce: nonce,
    );
    final framed = [...nonce, ...box.cipherText, ...box.mac.bytes];
    return base64Encode(framed);
  }

  static Future<Map<String, dynamic>?> decrypt(List<int> key, String sealed) async {
    try {
      final raw = base64Decode(sealed);
      if (raw.length < 28) return null;
      final nonce = raw.sublist(0, 12);
      final cipher = raw.sublist(12, raw.length - 16);
      final macBytes = raw.sublist(raw.length - 16);
      final plain = await _aes.decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(macBytes)),
        secretKey: SecretKeyData(key),
      );
      return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
