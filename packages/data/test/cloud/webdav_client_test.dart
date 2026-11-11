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

// E7b §6 — the WebDAV client against an in-test shelf server: auth, the
// MKCOL-405 dance, PROPFIND parsing, partial-upload retry, and the
// upload-then-prune ordering of §3.2. No LAN box is ever contacted.
import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:typed_data';

import 'package:data/cloud/cloud.dart';
import 'package:shelf/shelf.dart' show Request, Response;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

class FakeNas {
  static const user = 'nas';
  static const pass = 'app-pw';
  static String get authHeader =>
      'Basic ${base64Encode(utf8.encode('$user:$pass'))}';

  final files = <String, List<int>>{}; // '/dav/bk/name' → bytes
  final cols = <String>{}; // '/dav/bk'
  final putFailures = <String, int>{}; // path → remaining forced 500s
  final putAttempts = <String, int>{};
  final events = <String>[]; // order log: 'PUT …' / 'DEL …'

  Future<Response> handle(Request rq) async {
    final path = rq.requestedUri.path;
    if (rq.headers['authorization'] != authHeader) {
      return Response(401, body: 'wrong or missing credentials');
    }
    switch (rq.method) {
      case 'MKCOL':
        if (cols.contains(path)) return Response(405, body: 'exists');
        cols.add(path);
        return Response(201);
      case 'PUT':
        putAttempts[path] = (putAttempts[path] ?? 0) + 1;
        if ((putFailures[path] ?? 0) > 0) {
          putFailures[path] = putFailures[path]! - 1;
          return Response(500, body: 'transient NAS hiccup');
        }
        files[path] = await rq.read().fold(<int>[], (acc, c) => acc..addAll(c));
        events.add('PUT $path');
        return Response(201);
      case 'GET':
        final f = files[path];
        return f == null ? Response(404) : Response(200, body: f);
      case 'DELETE':
        if (files.remove(path) != null) {
          events.add('DEL $path');
          return Response(204);
        }
        return Response(404);
      case 'PROPFIND':
        if (!cols.contains(path)) {
          return Response(404, body: 'no such folder');
        }
        final prefix = '$path/';
        final sb = StringBuffer(
          '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">',
        );
        sb.write(
          '<d:response><d:href>$path/</d:href><d:propstat><d:prop>'
          '<d:resourcetype><d:collection/></d:resourcetype>'
          '</d:prop></d:propstat></d:response>',
        );
        for (final entry in files.entries) {
          if (!entry.key.startsWith(prefix)) continue;
          final child = entry.key.substring(prefix.length);
          if (child.contains('/')) continue; // only Depth:1
          sb.write(
            '<d:response><d:href>$prefix${Uri.encodeComponent(child)}</d:href>'
            '<d:propstat><d:prop>'
            '<d:getcontentlength>${entry.value.length}</d:getcontentlength>'
            '<d:getlastmodified>'
            '${HttpDate.format(DateTime.utc(2026, 10, 1, 8))}'
            '</d:getlastmodified>'
            '</d:prop></d:propstat></d:response>',
          );
        }
        sb.write('</d:multistatus>');
        return Response(
          207,
          body: sb.toString(),
          headers: {'content-type': 'application/xml'},
        );
      default:
        return Response(405);
    }
  }
}

void main() {
  late FakeNas nas;

  Future<({WebdavClient client, Future<void> Function() close})> connect({
    String? user = FakeNas.user,
  }) async {
    final server = await shelf_io.serve(nas.handle, '127.0.0.1', 0);
    final client = WebdavClient(
      baseUrl: 'http://127.0.0.1:${server.port}/dav',
      user: user,
      password: FakeNas.pass,
      sleep: (_) async {},
    );
    return (
      client: client,
      close: () async {
        client.close();
        await server.close(force: true);
      },
    );
  }

  String seed(int day, int minute) => backupObjectName(
    profileName: 'NAS Test',
    now: DateTime.utc(2026, 10, day, 9, minute),
  );

  void seedFile(String name) {
    nas.cols.add('/dav/bk');
    nas.files['/dav/bk/$name'] = List.filled(40, 0x42);
  }

  setUp(() => nas = FakeNas());

  group('checkWebdavUrl (§3.1)', () {
    test('https anywhere is ok', () {
      expect(
        checkWebdavUrl('https://nas.example.com/dav').status,
        WebdavUrlStatus.ok,
      );
      expect(checkWebdavUrl('https://192.168.1.9/dav').needsBanner, isFalse);
    });
    test('plain http survives only on RFC1918/loopback, with banner', () {
      for (final h in [
        'http://192.168.1.50:5005/dav',
        'http://10.0.0.7/dav',
        'http://172.20.3.4/dav',
        'http://127.0.0.1:8080/dav',
        'http://localhost/dav',
      ]) {
        final c = checkWebdavUrl(h);
        expect(c.allowed, isTrue, reason: h);
        expect(c.needsBanner, isTrue, reason: h);
      }
      expect(
        checkWebdavUrl('http://172.32.0.1/dav').status,
        WebdavUrlStatus.rejected,
      );
    });
    test('public http, other schemes, userinfo and junk are rejected', () {
      expect(checkWebdavUrl('http://backup.example.com/dav').allowed, isFalse);
      expect(checkWebdavUrl('ftp://192.168.1.5/dav').allowed, isFalse);
      expect(checkWebdavUrl('https://nas:pw@192.168.1.5/dav').allowed, isFalse);
      expect(checkWebdavUrl('https:///dav').allowed, isFalse);
      expect(checkWebdavUrl('not a url at all').allowed, isFalse);
    });
  });

  test('every verb carries Basic auth; 401 surfaces', () async {
    final t = await connect(user: 'wrong-user');
    addTearDown(t.close);
    expect(t.client.base.path, '/dav');
    await expectLater(t.client.list('bk'), throwsA(isA<WebdavException>()));
  });

  test('MKCOL creates once, 405 the second time, never throws', () async {
    final t = await connect();
    addTearDown(t.close);
    await t.client.ensureCollection('bk');
    expect(nas.cols, contains('/dav/bk'));
    await t.client.ensureCollection('bk'); // 405 → ok per §6
    expect(nas.cols.length, 1);
  });

  test('list parses multistatus, skips the folder itself', () async {
    final a = seed(1, 1), b = seed(2, 2);
    nas.cols.add('/dav/bk');
    nas.files['/dav/bk/$a'] = List.filled(40, 1);
    nas.files['/dav/bk/$b'] = List.filled(17, 2);
    nas.files['/dav/bk/holiday.jpg'] = List.filled(7, 3);
    final t = await connect();
    addTearDown(t.close);
    final objs = await t.client.list('bk');
    expect(objs.map((o) => o.name), unorderedEquals([a, b, 'holiday.jpg']));
    expect(objs.every((o) => o.path.startsWith('bk/')), isTrue);
    expect(objs.firstWhere((o) => o.name == b).size, 17);
    expect(
      objs.firstWhere((o) => o.name == a).modified,
      DateTime.utc(2026, 10, 1, 8),
    );
  });

  test('PROPFIND on a missing folder throws', () async {
    final t = await connect();
    addTearDown(t.close);
    await expectLater(
      t.client.list('missing'),
      throwsA(
        isA<WebdavException>().having((e) => e.statusCode, 'status', 404),
      ),
    );
  });

  test('PUT recovers from a transient 500 (partial-upload retry)', () async {
    final t = await connect();
    addTearDown(t.close);
    final path = '/dav/one.lzbak';
    nas.putFailures[path] = 1; // first attempt 500s, second lands
    await t.client.put('one.lzbak', Uint8List.fromList([1, 2, 3]));
    expect(nas.putAttempts[path], 2);
    expect(nas.files[path], [1, 2, 3]);
  });

  test('PUT gives up after the retry budget on hard 500s', () async {
    final t = await connect();
    addTearDown(t.close);
    final path = '/dav/dead.lzbak';
    nas.putFailures[path] = 99;
    await expectLater(
      t.client.put('dead.lzbak', Uint8List(4)),
      throwsA(
        isA<WebdavException>().having((e) => e.statusCode, 'status', 500),
      ),
    );
    expect(nas.putAttempts[path], 3); // 1 + retries: 2
  });

  test('GET round-trips, 404 throws; DELETE is prune-idempotent', () async {
    final t = await connect();
    addTearDown(t.close);
    await t.client.put('r.lzbak', Uint8List.fromList([9, 8, 7]));
    expect(await t.client.get('r.lzbak'), [9, 8, 7]);
    await expectLater(
      t.client.get('nope.lzbak'),
      throwsA(isA<WebdavException>()),
    );
    await t.client.delete('r.lzbak');
    await t.client.delete('r.lzbak'); // 404 → already gone, fine
  });

  test('putAndPrune uploads FIRST, then deletes per retention plan', () async {
    for (var m = 0; m < 8; m++) {
      seedFile(seed(1, m)); // Oct 1 — 8 older
    }
    for (var m = 0; m < 5; m++) {
      seedFile(seed(2, m)); // Oct 2 — 5 older
    }
    final t = await connect();
    addTearDown(t.close);
    final newName = seed(3, 0);
    final plan = await t.client.putAndPrune(
      folder: 'bk',
      name: newName,
      bytes: Uint8List.fromList(List.filled(50, 7)),
    );
    // 14 total → newest 12 kept (Oct3×1 + Oct2×5 + Oct1×6); the two
    // OLDEST Oct-1 entries are gone, nothing else.
    expect(plan.delete.map((o) => o.name), [seed(1, 1), seed(1, 0)]);
    expect(plan.keep.length, 12 + 0); // foreign: none
    expect(nas.files['/dav/bk/$newName'], hasLength(50));
    expect(nas.files.keys.any((k) => k.endsWith(seed(1, 0))), isFalse);
    expect(nas.files.length, 12);
    // Ordering is the §3.2 contract: the first event is the upload.
    expect(nas.events.first, startsWith('PUT '));
    expect(nas.events.where((e) => e.startsWith('DEL ')).length, 2);
    final firstDel = nas.events.indexWhere((e) => e.startsWith('DEL '));
    final putIdx = nas.events.indexOf('PUT /dav/bk/$newName');
    expect(putIdx, lessThan(firstDel));
  });

  test('prune ignores foreign files sharing the folder', () async {
    nas.cols.add('/dav/bk');
    nas.files['/dav/bk/holiday.jpg'] = List.filled(7, 9);
    final t = await connect();
    addTearDown(t.close);
    await t.client.putAndPrune(
      folder: 'bk',
      name: seed(4, 0),
      bytes: Uint8List(5),
    );
    expect(nas.files['/dav/bk/holiday.jpg'], isNotNull);
  });
}
