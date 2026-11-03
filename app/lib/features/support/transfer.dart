import 'dart:io';

import 'package:flutter/services.dart';

/// E6 §3 free→paid transfer, Dart side of `dev.steiner.local_budget/transfer`.
/// The free app *stages* an encrypted snapshot (its Dart writes bytes through
/// the channel; Kotlin stores them for the ContentProvider); the Pro app
/// *pulls* whatever the free app's provider serves. Neither side ever talks
/// to a network (§decision 8), and the free app is never modified.
abstract class FreeTransfer {
  /// Pro side: does the free app's provider resolve on this device? Drives
  /// the row's visibility — hidden, never disabled (spec §6).
  Future<bool> freeAvailable();

  /// Free side: is the Pro package visible (manifest `<queries>`)? Drives
  /// the Get Pro page's "Pro installed?" note.
  Future<bool> proInstalled();

  /// Free side: publish [bytes] as the transfer snapshot for Pro to pull.
  Future<void> stage(Uint8List bytes);

  /// Pro side: fetch the staged snapshot; `null` when nothing is staged.
  Future<Uint8List?> pull();

  /// Pro side: (size in bytes, staged-at ms since epoch) of the snapshot,
  /// for the honest freshness line (spec §3). `null` when nothing is staged.
  Future<({int size, int mtimeMs})?> snapshotMeta();
}

class ChannelFreeTransfer implements FreeTransfer {
  const ChannelFreeTransfer();

  static const _ch = MethodChannel('dev.steiner.local_budget/transfer');

  @override
  Future<bool> freeAvailable() async {
    try {
      return await _ch.invokeMethod<bool>('freeAvailable') ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> proInstalled() async {
    try {
      return await _ch.invokeMethod<bool>('proInstalled') ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> stage(Uint8List bytes) =>
      _ch.invokeMethod<void>('stage', {'bytes': bytes});

  @override
  Future<Uint8List?> pull() async {
    final path = await _ch.invokeMethod<String>('pull');
    if (path == null) return null;
    final file = File(path);
    final bytes = await file.readAsBytes();
    // One read, then the spool is gone — a stray copy of ledger data in
    // cacheDir outliving the flow is exactly what decision 8 avoids.
    try {
      await file.delete();
    } on FileSystemException {
      // Cache hygiene is best-effort; the bytes are already in hand.
    }
    return bytes;
  }

  @override
  Future<({int size, int mtimeMs})?> snapshotMeta() async {
    final meta = await _ch.invokeMethod<Map<Object?, Object?>>('snapshotMeta');
    if (meta == null) return null;
    return (
      size: (meta['size'] as num).toInt(),
      mtimeMs: (meta['mtimeMs'] as num).toInt(),
    );
  }
}

/// Widget-test/golden double: in-memory snapshot, switchable availability.
class FakeFreeTransfer implements FreeTransfer {
  FakeFreeTransfer({this.free = false, this.pro = false, this.snapshot});

  bool free;
  bool pro;
  Uint8List? snapshot;
  Uint8List? staged;

  @override
  Future<bool> freeAvailable() async => free;

  @override
  Future<bool> proInstalled() async => pro;

  @override
  Future<void> stage(Uint8List bytes) async => staged = bytes;

  @override
  Future<Uint8List?> pull() async => snapshot;

  @override
  Future<({int size, int mtimeMs})?> snapshotMeta() async => snapshot == null
      ? null
      : (size: snapshot!.length, mtimeMs: 1762000000000);
}
