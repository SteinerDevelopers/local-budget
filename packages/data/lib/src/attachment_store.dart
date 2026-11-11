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
import 'dart:typed_data';

import 'package:core/core.dart' show TransactionSource;

/// On-device original receipts (e2-capture.md §4). Files live under a single
/// flat `attachments/` directory; the database column `transactions.imageRef`
/// stores the *relative* path this class returns (schema v1, no migration).
///
/// Names are sortable and human-scannable, never content-hashed:
/// `yyyymmddhhmmss-<source>.<ext>`, collisions get `-2`, `-3`, … so a
/// same-second burst can never overwrite. Deleting the transaction deletes
/// the file via an app-layer hook *after* the DB commit — this class only
/// knows files, never rows.
class AttachmentStore {
  AttachmentStore(this.root);

  /// App documents directory; `attachments/` is created lazily.
  final Directory root;

  static const String dirName = 'attachments';
  static final RegExp _extRe = RegExp(r'^[A-Za-z0-9]{1,8}$');
  static final RegExp _traversal = RegExp(r'(^|/)\.\.(/|$)');

  /// Stores [bytes] and returns the relative path to persist in `imageRef`
  /// (always `attachments/<file>`, forward slashes — a wire format).
  String saveOriginal(
    Uint8List bytes, {
    required String extension,
    required TransactionSource source,
    DateTime? now,
  }) {
    final ext = extension.toLowerCase();
    if (!_extRe.hasMatch(ext)) {
      throw ArgumentError.value(extension, 'extension', 'not a file extension');
    }
    final t = now ?? DateTime.now();
    final stamp =
        '${_two(t.year ~/ 100)}${_two(t.year % 100)}'
        '${_two(t.month)}${_two(t.day)}'
        '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';
    final dir = Directory('${root.path}/$dirName');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    var name = '$stamp-${source.wireName}.$ext';
    for (var n = 2; File('${dir.path}/$name').existsSync(); n++) {
      name = '$stamp-${source.wireName}-$n.$ext';
    }
    File('${dir.path}/$name').writeAsBytesSync(bytes);
    return '$dirName/$name';
  }

  /// Absolute file for a stored relative path. Never trusts its input:
  /// traversal or absolute paths throw instead of touching the filesystem.
  File resolve(String rel) {
    _assertSafeRel(rel);
    return File('${root.path}/$rel');
  }

  /// Removes the file; a missing file is not an error (the row is already
  /// gone in the undo race, and crash-orphan cleanup may double-pass).
  void delete(String rel) {
    _assertSafeRel(rel);
    final f = File('${root.path}/$rel');
    if (f.existsSync()) f.deleteSync();
  }

  /// Only `attachments/<file>` relative paths — what `imageRef` stores and
  /// the only shape backup/restore is ever allowed to touch. Restore input
  /// (zip entry names from a user-picked file) is hostile by default.
  static bool isSafeRel(String rel) =>
      rel.isNotEmpty &&
      !rel.startsWith('/') &&
      !rel.contains(r'\') &&
      !rel.contains(':') &&
      !_traversal.hasMatch(rel) &&
      rel.startsWith('$dirName/');

  static void _assertSafeRel(String rel) {
    if (!isSafeRel(rel)) {
      throw ArgumentError.value(rel, 'rel', 'not an attachment path');
    }
  }

  /// All originals as `attachments/<name>` → bytes, name-sorted (the backup
  /// container input, E5 §3). Missing directory simply means "no originals".
  Map<String, Uint8List> listOriginals() {
    final dir = Directory('${root.path}/$dirName');
    if (!dir.existsSync()) return const {};
    final out = <String, Uint8List>{};
    final entries = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in entries) {
      final rel = '$dirName/${f.path.substring(dir.path.length + 1)}';
      if (isSafeRel(rel)) out[rel] = f.readAsBytesSync();
    }
    return out;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
