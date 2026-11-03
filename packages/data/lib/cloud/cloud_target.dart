/// The surface a cloud backup needs from a transport (§3.1 table):
/// WebDAV ships in E7b, the Drive provider follows the same shape. The
/// app layer codes against this so widget tests fake it in-memory.
import 'dart:typed_data';

import 'retention.dart';

abstract interface class CloudTarget {
  Future<void> ensureCollection(String relPath);
  Future<List<CloudObject>> list(String relPath);
  Future<void> put(String relPath, Uint8List bytes);
  Future<Uint8List> get(String relPath);
  Future<void> delete(String relPath);
}
