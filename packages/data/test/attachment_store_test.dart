import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late AttachmentStore store;
  final t = DateTime(2026, 11, 2, 14, 22, 1);
  final bytes = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3]);

  setUp(() {
    root = Directory.systemTemp.createTempSync('attachments');
    store = AttachmentStore(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  group('saveOriginal', () {
    test('name = yyyymmddhhmmss-source.ext under attachments/', () {
      final rel = store.saveOriginal(
        bytes,
        extension: 'jpg',
        source: TransactionSource.cameraScan,
        now: t,
      );
      expect(rel, 'attachments/20261102142201-camera_scan.jpg');
      expect(File('${root.path}/$rel').readAsBytesSync(), bytes);
    });

    test('directory is created lazily; pdf/screenshot sources name-clean', () {
      final rel = store.saveOriginal(
        bytes,
        extension: 'PDF',
        source: TransactionSource.pdfImport,
        now: t,
      );
      expect(rel, 'attachments/20261102142201-pdf_import.pdf');
    });

    test('same-second burst never overwrites: -2, -3 …', () {
      final a = store.saveOriginal(
        bytes,
        extension: 'jpg',
        source: TransactionSource.cameraScan,
        now: t,
      );
      final b = store.saveOriginal(
        bytes,
        extension: 'jpg',
        source: TransactionSource.cameraScan,
        now: t,
      );
      final c = store.saveOriginal(
        bytes,
        extension: 'jpg',
        source: TransactionSource.cameraScan,
        now: t,
      );
      expect(a, isNot(b));
      expect(b.endsWith('-2.jpg'), isTrue);
      expect(c.endsWith('-3.jpg'), isTrue);
      expect(Directory('${root.path}/attachments').listSync().length, 3);
    });

    test('bogus extensions rejected before any write', () {
      expect(
        () => store.saveOriginal(
          bytes,
          extension: 'jpg/../../etc/passwd',
          source: TransactionSource.cameraScan,
          now: t,
        ),
        throwsArgumentError,
      );
      expect(
        () => store.saveOriginal(
          bytes,
          extension: '',
          source: TransactionSource.cameraScan,
          now: t,
        ),
        throwsArgumentError,
      );
      expect(root.listSync(), isEmpty);
    });
  });

  group('resolve / delete path safety', () {
    test('resolve is absolute inside the store', () {
      final rel = store.saveOriginal(
        bytes,
        extension: 'jpg',
        source: TransactionSource.screenshotImport,
        now: t,
      );
      final f = store.resolve(rel);
      expect(f.isAbsolute, isTrue);
      expect(f.path, startsWith(root.path));
      expect(f.readAsBytesSync(), bytes);
    });

    test('delete removes; missing file is a no-op', () {
      final rel = store.saveOriginal(
        bytes,
        extension: 'jpg',
        source: TransactionSource.cameraScan,
        now: t,
      );
      store.delete(rel);
      expect(File('${root.path}/$rel').existsSync(), isFalse);
      expect(() => store.delete(rel), returnsNormally);
    });

    for (final bad in [
      '',
      '/etc/passwd',
      'attachments/../../secret.txt',
      'attachments/../attachments/x.jpg',
      r'attachments\evil.jpg',
      'C:/x',
      'other/x.jpg',
    ]) {
      test('rejects "$bad"', () {
        expect(() => store.resolve(bad), throwsArgumentError);
        expect(() => store.delete(bad), throwsArgumentError);
      });
    }
  });
}
