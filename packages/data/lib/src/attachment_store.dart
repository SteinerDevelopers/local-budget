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

  static void _assertSafeRel(String rel) {
    if (rel.isEmpty ||
        rel.startsWith('/') ||
        rel.contains(r'\') ||
        rel.contains(':') ||
        _traversal.hasMatch(rel) ||
        !rel.startsWith('$dirName/')) {
      throw ArgumentError.value(rel, 'rel', 'not an attachment path');
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
