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

// Shared plumbing for the §6 golden surface. Lives in test_goldens/ so the
// default `flutter test` (test/ only) never runs goldens locally — refs are
// CI-generated on the pinned Flutter (see .gitlab-ci.yml goldens jobs);
// rendering on the dev machine's SDK would produce false diffs.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/design/theme.dart';

/// Loads the exact Roboto TTFs that ship inside the Flutter SDK cache
/// (`bin/cache/artifacts/material_fonts`) under the family 'Roboto', which
/// the host themes below select explicitly. Determinism rationale: refs are
/// generated and compared inside the same pinned CI image, so the TTF bytes
/// and the rasterizer are identical in both runs; production Android text
/// *is* Roboto, so the goldens stay faithful.
Future<void> loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    throw StateError(
      'FLUTTER_ROOT unset — goldens must run under `flutter test`',
    );
  }
  final loader = FontLoader('Roboto');
  for (final file in const [
    'Roboto-Light.ttf',
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]) {
    final bytes = File(
      '$root/bin/cache/artifacts/material_fonts/$file',
    ).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();

  // Icons.* resolve to family 'MaterialIcons'; without this the glyphs are
  // tofu boxes in flutter_test.
  final icons = FontLoader('MaterialIcons');
  icons.addFont(
    File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes().then(ByteData.sublistView),
  );
  await icons.load();
}

/// Phone viewport every golden renders at (§6 pins the phone layout).
void usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

ThemeData goldTheme(Brightness brightness) {
  final theme = brightness == Brightness.light
      ? AppTheme.light()
      : AppTheme.dark();
  return theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Roboto'));
}

/// Standalone-widget host (TransactionRow, BalanceStrip, EmptyMonth).
/// The RepaintBoundary is what `matchesGoldenFile(finder)` uses to crop the
/// shot tightly to the subject instead of grabbing the whole viewport — and
/// because the crop only contains this subtree, it must paint its own
/// background (transparent crops preview as black).
Widget goldHost({required Brightness brightness, required Widget child}) {
  return MaterialApp(
    theme: goldTheme(Brightness.light),
    darkTheme: goldTheme(Brightness.dark),
    themeMode: brightness == Brightness.light
        ? ThemeMode.light
        : ThemeMode.dark,
    home: Builder(
      builder: (context) => Scaffold(
        body: RepaintBoundary(
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: child,
          ),
        ),
      ),
    ),
  );
}

String modeName(Brightness brightness) => brightness.name; // light / dark
