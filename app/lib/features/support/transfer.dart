// Steiner Budget — local-first budgeting, https://steinerdevelopers.dev
// Copyright (C) 2026 Steiner Developers, L.L.C.
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import 'dart:io';

import 'package:data/data.dart';
import 'package:flutter/services.dart';

import '../../version.dart';

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
  FakeFreeTransfer({
    this.free = false,
    this.pro = false,
    this.snapshot,
    this.metaMs = 1762000000000,
  });

  bool free;
  bool pro;
  Uint8List? snapshot;
  Uint8List? staged;

  /// Staged-at stamp the fake reports; tests move it around the wal mtime
  /// to drive the staleness probe.
  final int metaMs;

  @override
  Future<bool> freeAvailable() async => free;

  @override
  Future<bool> proInstalled() async => pro;

  @override
  Future<void> stage(Uint8List bytes) async => staged = bytes;

  @override
  Future<Uint8List?> pull() async => snapshot;

  @override
  Future<({int size, int mtimeMs})?> snapshotMeta() async =>
      snapshot == null ? null : (size: snapshot!.length, mtimeMs: metaMs);
}

/// E6 §3 opportunistic pause-staging, the free side. The same envelope the
/// *Copy my data* button stages, refreshed when the user walks away from the
/// app — "again opportunistically on app pause when anything changed since
/// the last stage" (§3). Opt-in by construction: it never stages for anyone
/// who has not pressed the button at least once ([snapshotMeta] gate), and
/// opportunistic by contract: every failure is swallowed and the previous,
/// still-true snapshot keeps being served. A concurrent button stage racing
/// this path is harmless — both bytes are valid snapshots, last write wins.
class TransferRestager {
  TransferRestager({
    required this.transfer,
    required this.db,
    required this.attachments,
    required this.dbFile,
    this.kdfIterations = backupDefaultKdfIterations,
  });

  final FreeTransfer transfer;
  final AppDatabase db;
  final AttachmentStore attachments;
  final File dbFile;
  final int kdfIterations;

  bool _inFlight = false;

  Future<void> restageIfStale() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      if (!await transfer.proInstalled()) return;
      final meta = await transfer.snapshotMeta();
      if (meta == null) return; // the button remains the only entrance
      if (!await _changedSince(meta.mtimeMs)) return;
      final bytes = await createBackup(
        db: db,
        attachments: attachments,
        passphrase: transferPassphrase,
        appVersion: appVersion,
        kdfIterations: kdfIterations,
      );
      await transfer.stage(bytes);
    } catch (_) {
      // Opportunistic: an old-but-true snapshot beats no snapshot, and the
      // next pause retries while the staleness probe still says "changed".
    } finally {
      _inFlight = false;
    }
  }

  /// SQLite writes through `…-wal` while WAL is live and the plain db file's
  /// mtime trails, so both are probed. A false "changed" only re-stages
  /// identical bytes; a missed change would need a write touching neither
  /// file, which sqlite does not perform.
  Future<bool> _changedSince(int mtimeMs) async {
    final staged = DateTime.fromMillisecondsSinceEpoch(mtimeMs);
    for (final path in [dbFile.path, '${dbFile.path}-wal']) {
      try {
        if ((await File(path).stat()).modified.isAfter(staged)) return true;
      } on FileSystemException {
        // Absent wal before the first write is normal.
      }
    }
    return false;
  }
}
