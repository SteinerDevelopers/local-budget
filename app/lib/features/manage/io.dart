import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

/// One file chosen through [Io.pickFile] — bytes already in memory, because
/// every consumer (CSV parse, backup open) works on bytes and the OS file
/// handle would not survive the platform-channel hop anyway.
class PickedFile {
  const PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// The app's only file-boundary seam (E5 §3): everything above the Data
/// section of Manage talks to this interface, so export/backup/restore/
/// import are fully widget-testable with an in-memory fake.
abstract interface class Io {
  /// System file picker; `null` means the user cancelled.
  Future<PickedFile?> pickFile({List<String>? extensions});

  /// Hands [bytes] to the OS share sheet under [fileName] (temp file first).
  Future<void> shareFile({required Uint8List bytes, required String fileName});
}

/// Production wiring: file_picker 13.x (static pickFiles, empty list =
/// cancel) and share_plus 13 (ShareParams with a file attach).
class RealIo implements Io {
  const RealIo();

  @override
  Future<PickedFile?> pickFile({List<String>? extensions}) async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Choose a file',
      type: extensions == null ? FileType.any : FileType.custom,
      allowedExtensions: extensions,
    );
    if (picked.isEmpty) return null;
    final file = picked.first;
    final bytes = await file.readAsBytes();
    return PickedFile(file.name, bytes);
  }

  @override
  Future<void> shareFile({
    required Uint8List bytes,
    required String fileName,
  }) async {
    // The share sheet shows the file's own name — write it once, named right.
    final path = '${Directory.systemTemp.path}/$fileName';
    await File(path).writeAsBytes(bytes, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, name: fileName)],
        subject: fileName,
      ),
    );
    if (result.status == ShareResultStatus.unavailable) {
      throw StateError('Sharing is not available on this device.');
    }
  }
}
