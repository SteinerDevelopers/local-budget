/// Backup container crypto primitives (E5 spec §3). Pure Dart so restore
/// works anywhere the zip does; no Flutter, no platform channels.
///
/// Layout of a `.lzbak` file:
///   magic "LZBK1" (5) | version u8 | salt (16) | iterations u32 BE |
///   nonce (12) | AES-256-GCM ciphertext+tag
/// The header is AAD, so a tampered salt/nonce/iteration count fails the tag
/// exactly like a wrong passphrase does — the file is its own integrity seal.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

const String backupMagic = 'LZBK1';
const int backupFormatVersion = 1;
const int backupSaltBytes = 16;
const int backupNonceBytes = 12;

/// OWASP 2023 guidance for PBKDF2-HMAC-SHA256. On-device derivation runs in
/// ~1–2 s; the UI is expected to show progress and stay interactive.
const int backupDefaultKdfIterations = 600000;
const int _minIterations = 1000;
const int _maxIterations = 100000000;

/// 5 + 1 + 16 + 4 + 12 — everything before the ciphertext; also the AAD.
const int backupHeaderBytes = 38;
const int _gcmTagBytes = 16;
const int _keyBytes = 32;

/// Container is not a backup at all (magic, version, sizes, zip, manifest).
class BackupFormatException implements Exception {
  const BackupFormatException([this.message = 'not a valid backup file']);
  final String message;
  @override
  String toString() => 'BackupFormatException: $message';
}

/// GCM tag mismatch: wrong passphrase *or* a modified file — the spec
/// deliberately collapses both into one user-facing message.
class BackupPassphraseException implements Exception {
  const BackupPassphraseException([
    this.message = 'wrong password or corrupt file',
  ]);
  final String message;
  @override
  String toString() => 'BackupPassphraseException: $message';
}

Uint8List _randomBytes(int n) {
  final r = Random.secure();
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = r.nextInt(256);
  }
  return b;
}

Uint8List backupRandomSalt() => _randomBytes(backupSaltBytes);

Uint8List backupRandomNonce() => _randomBytes(backupNonceBytes);

/// PBKDF2-HMAC-SHA256 → 256-bit key. Deliberately slow (see
/// [backupDefaultKdfIterations]); callers off-thread it above the UI.
Uint8List backupDeriveKey({
  required String passphrase,
  required Uint8List salt,
  required int iterations,
}) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, iterations, _keyBytes));
  return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
}

/// Header bytes (AAD material) for a fresh container.
Uint8List backupBuildHeader({
  required Uint8List salt,
  required int iterations,
  required Uint8List nonce,
}) {
  assert(salt.length == backupSaltBytes && nonce.length == backupNonceBytes);
  final out = Uint8List(backupHeaderBytes);
  out.setRange(0, 5, latin1.encode(backupMagic));
  out[5] = backupFormatVersion;
  out.setRange(6, 6 + salt.length, salt);
  final bd = ByteData.sublistView(out, 22, 26);
  bd.setUint32(0, iterations, Endian.big);
  out.setRange(26, 38, nonce);
  return out;
}

/// Parsed header fields; throws [BackupFormatException] before deriving
/// anything (never hand a hostile salt/iteration count to PBKDF2).
({Uint8List salt, int iterations, Uint8List nonce}) backupParseHeader(
  Uint8List bytes,
) {
  if (bytes.length < backupHeaderBytes + _gcmTagBytes) {
    throw const BackupFormatException('file too short');
  }
  if (latin1.decode(bytes.sublist(0, 5)) != backupMagic) {
    throw const BackupFormatException('missing LZBK1 magic');
  }
  if (bytes[5] != backupFormatVersion) {
    throw const BackupFormatException('unsupported backup version');
  }
  final iterations = ByteData.sublistView(
    bytes,
    22,
    26,
  ).getUint32(0, Endian.big);
  if (iterations < _minIterations || iterations > _maxIterations) {
    throw const BackupFormatException('implausible KDF iterations');
  }
  return (
    salt: Uint8List.sublistView(bytes, 6, 22),
    iterations: iterations,
    nonce: Uint8List.sublistView(bytes, 26, 38),
  );
}

Uint8List backupSeal({
  required Uint8List plaintext,
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List aad,
}) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), 128, nonce, aad));
  return cipher.process(plaintext);
}

/// Opens the sealed body; any tag failure surfaces as
/// [BackupPassphraseException] (spec: one message for wrong pw and damage).
Uint8List backupOpen({
  required Uint8List sealed,
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List aad,
}) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(false, AEADParameters(KeyParameter(key), 128, nonce, aad));
  try {
    return cipher.process(sealed);
  } on InvalidCipherTextException {
    throw const BackupPassphraseException();
  }
}
