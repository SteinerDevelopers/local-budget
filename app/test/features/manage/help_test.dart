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

// #30 — the Help section (E2 §7): offline articles behind a search
// box, entered from the About & help sheet. Search must find the terms
// the acceptance criteria name, and the no-match copy must never dead
// end — it hands the reader words that do work.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/help/help_articles.dart';
import 'package:local_budget/features/help/help_screen.dart';
import 'package:local_budget/features/manage/manage_screen.dart';

Future<void> pumpHelp(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(theme: ThemeData.light(), home: const HelpScreen()),
  );
  await tester.pumpAndSettle();
}

Future<void> search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump();
}

// The topic list is lazy (ListView.separated); at the test viewport the
// later articles only exist once the list has reached them.
Future<void> reveal(WidgetTester tester, String text) async {
  final item = find.text(text);
  if (item.evaluate().isEmpty) {
    // Positive delta reveals rows below the fold (scrollUntilVisible
    // negates it into a finger swipe).
    await tester.scrollUntilVisible(
      item,
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every article is listed', (tester) async {
    await pumpHelp(tester);
    for (final article in kHelpArticles) {
      await reveal(tester, article.title);
      expect(find.text(article.title), findsOneWidget);
    }
  });

  testWidgets('“highlight” finds the highlight article only', (tester) async {
    await pumpHelp(tester);
    await search(tester, 'highlight');
    expect(find.text('Why is a field highlighted?'), findsOneWidget);
    expect(find.text('Tips for better scans'), findsNothing);
    expect(find.text('Scanning receipts'), findsNothing);
  });

  testWidgets('“total” finds the reading articles', (tester) async {
    await pumpHelp(tester);
    await search(tester, 'total');
    expect(find.text('Scanning receipts'), findsOneWidget);
    expect(find.text('Why is a field highlighted?'), findsOneWidget);
    expect(find.text('Importing PDFs & screenshots'), findsNothing);
  });

  testWidgets('“PDF” finds the import article', (tester) async {
    await pumpHelp(tester);
    await search(tester, 'PDF');
    expect(find.text('Importing PDFs & screenshots'), findsOneWidget);
    expect(find.text('Why is a field highlighted?'), findsNothing);
  });

  // #39 — the E3 article rides the same index; searching a rollover word
  // must land on it and nothing else.
  testWidgets('“rollover” finds the budgets article', (tester) async {
    await pumpHelp(tester);
    await search(tester, 'rollover');
    expect(find.text('Budgets, bills & goals'), findsOneWidget);
    expect(find.text('Scanning receipts'), findsNothing);
    expect(find.text('Tips for better scans'), findsNothing);
  });

  testWidgets('no match points at terms that do work', (tester) async {
    await pumpHelp(tester);
    await search(tester, 'zebra');
    expect(find.textContaining('Nothing found'), findsOneWidget);
    expect(find.text('Scanning receipts'), findsNothing);
  });

  // #9 — E8: the corpus covers every screen now; the issue’s acceptance
  // terms must surface the article a reader would actually need.
  testWidgets('“statement” finds the import guide', (tester) async {
    await pumpHelp(tester);
    await search(tester, 'statement');
    expect(find.text('Importing a bank statement'), findsOneWidget);
    expect(find.text('Scanning receipts'), findsNothing);
  });

  testWidgets('“passphrase” finds the backup article', (tester) async {
    await pumpHelp(tester);
    await search(tester, 'passphrase');
    expect(find.text('Backup and restore'), findsOneWidget);
  });

  testWidgets('“privacy” finds the promise', (tester) async {
    await pumpHelp(tester);
    await search(tester, 'privacy');
    expect(find.text('Your data stays yours'), findsOneWidget);
  });

  testWidgets('“widget” finds the Pro extras', (tester) async {
    await pumpHelp(tester);
    await search(tester, 'widget');
    expect(find.text('Pro extras: cloud, widgets & insights'), findsOneWidget);
  });

  testWidgets('a half-typed word still lands', (tester) async {
    await pumpHelp(tester);
    await search(tester, 'passphras');
    expect(find.text('Backup and restore'), findsOneWidget);
  });

  testWidgets('opening an article reads and backs out', (tester) async {
    await pumpHelp(tester);
    await tester.tap(find.text('Why is a field highlighted?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('amber outline'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HelpArticlePage), findsNothing);
    expect(find.text('Scanning receipts'), findsOneWidget);
  });

  testWidgets('a wide article reads at a measure, not wall to wall', (
    tester,
  ) async {
    // T2 (tablet audit 2026-11-10): sw800 paragraphs ran >110 characters.
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: HelpArticlePage(article: kHelpArticles.first),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ListView)).width, lessThanOrEqualTo(640));
  });

  testWidgets('the About & help sheet links to all topics', (tester) async {
    late final BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );
    showManageHelp(context);
    await tester.pumpAndSettle();
    // The sheet scrolls; the entry sits below the first screenful.
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('All help topics'), findsOneWidget);

    await tester.tap(find.text('All help topics'));
    await tester.pumpAndSettle();
    expect(find.byType(HelpScreen), findsOneWidget);
    expect(find.text('Scanning receipts'), findsOneWidget);
  });
}
