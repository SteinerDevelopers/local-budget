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

// #9 — E8 §1: the Help search is a real local index over the corpus, so
// the list is ordered by relevance and half-typed words still land. Pure
// Dart over pure Dart — same honesty promise as the articles themselves.
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/help/help_articles.dart';

String _title(HelpArticle a) => a.title;

void main() {
  test('an empty query is the whole corpus, in listing order', () {
    expect(searchHelpArticles(''), kHelpArticles);
    expect(
      searchHelpArticles('   ').map(_title).toList(),
      kHelpArticles.map(_title).toList(),
    );
  });

  test('unknown words find nothing', () {
    expect(searchHelpArticles('zebra'), isEmpty);
  });

  test('a title match outranks a body mention', () {
    final hits = searchHelpArticles('privacy').map(_title).toList();
    expect(hits.first, 'Reports & privacy');
    expect(hits, contains('Your data stays yours'));
  });

  test('a whole phrase lands its article first', () {
    expect(
      searchHelpArticles('better scans').first.title,
      'Tips for better scans',
    );
    expect(
      searchHelpArticles('bank statement').first.title,
      'Importing a bank statement',
    );
  });

  test('every word of a multi-word query has to earn its place', () {
    final hits = searchHelpArticles('receipts total').map(_title).toList();
    expect(hits.first, 'Scanning receipts');
    expect(hits, contains('Why is a field highlighted?'));
  });

  test('half-typed words still land', () {
    final hits = searchHelpArticles('passphras').map(_title).toList();
    expect(hits, contains('Backup and restore'));
    expect(
      searchHelpArticles('highlight').first.title,
      'Why is a field highlighted?',
    );
  });

  test('the acceptance terms resolve to one clear winner', () {
    // The no-match copy promises these three; keep that promise exact.
    expect(searchHelpArticles('highlight').map(_title).toList(), [
      'Why is a field highlighted?',
    ]);
    // E11 added a photo/PDF import article whose title carries the
    // exact token; the E2 receipt-PDF article must still be right there.
    expect(
      searchHelpArticles('PDF').first.title,
      'Import a bill or statement from a photo/PDF',
    );
    expect(
      searchHelpArticles('PDF').map(_title),
      contains('Importing PDFs & screenshots'),
    );
    expect(searchHelpArticles('total').first.title, 'Scanning receipts');
  });

  test('the startup integrity banner is explained, not just shown', () {
    expect(
      searchHelpArticles('database check').map(_title),
      contains('Backup and restore'),
    );
  });

  test('the corpus covers the E8 screens', () {
    expect(
      kHelpArticles.map(_title),
      containsAll(<String>[
        'Your month at a glance',
        'Importing a bank statement',
        'Backup and restore',
        'Currencies and exchange rates',
        'Categories that fit your life',
        'Your data stays yours',
        'Pro extras: cloud, widgets & insights',
        'Import a bill or statement from a photo/PDF',
      ]),
    );
  });
}
