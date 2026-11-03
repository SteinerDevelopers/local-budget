import 'package:flutter/material.dart';

/// Offline help articles (feasibility §4.1-10, E2 §7). Everything ships in
/// the binary — search runs over these strings, so "offline" is literal,
/// not a promise about a network cache.
///
/// Voice rules (§ copy bar): plain second person, no feature branding of
/// any kind — the reader-facing app never names the machinery behind a
/// reading, it says what the app did and what the user can do next. Every
/// article ends where the user can act; none is a dead end.
class HelpArticle {
  const HelpArticle({
    required this.icon,
    required this.title,
    required this.paragraphs,
  });

  final IconData icon;
  final String title;
  final List<String> paragraphs;

  /// One lowercase haystack per article: search is a substring test, and
  /// the acceptance terms (highlight, total, PDF) must live in real copy,
  /// never in hidden keyword lists.
  String get haystack => [title, ...paragraphs].join(' ').toLowerCase();
}

const List<HelpArticle> kHelpArticles = [
  HelpArticle(
    icon: Icons.document_scanner_outlined,
    title: 'Scanning receipts',
    paragraphs: [
      'Tap the camera button on the month screen and choose where the '
          'receipt comes from: the camera, your gallery, a PDF file, or a '
          'recent screenshot when the gallery has one.',
      'The app reads the picture on this device and fills in what it '
          'recognises — merchant, date and total — then opens a review '
          'screen so you can fix anything before it is kept.',
      'Nothing is ever saved by itself. The review screen is a suggestion: '
          'the entry only reaches your ledger when you tap Save, and '
          'swiping it away or pressing back keeps your ledger exactly as '
          'it was.',
      'You can edit every field once, twice or not at all. A scanned entry '
          'behaves like a typed one afterwards — swipe to delete, tap to '
          'edit, five seconds of Undo.',
    ],
  ),
  HelpArticle(
    icon: Icons.edit_note_outlined,
    title: 'Why is a field highlighted?',
    paragraphs: [
      'A field drawn with an amber outline is the app being honest: that '
          'value was read from the receipt, but the reading was uncertain. '
          'Blur, glare, a crease, handwriting or a total printed far from '
          'the word "total" all cause it.',
      'Tap a highlighted field to correct it. The outline disappears as '
          'soon as you type — the app stops guessing the moment you answer.',
      'Fields without an outline still deserve a glance: an unmarked '
          'reading is a likely one, not a guaranteed one. The whole point '
          'of the review step is that you decide, not the app.',
      'If a field you need is simply missing, type it in — an empty field '
          'is the app saying "I could not read this", and your keyboard is '
          'always the better reader.',
    ],
  ),
  HelpArticle(
    icon: Icons.picture_as_pdf_outlined,
    title: 'Importing PDFs & screenshots',
    paragraphs: [
      'A PDF opens at its first page: the page is rendered on the device, '
          'its text is read, and the review screen appears like any other '
          'scan. The original PDF stays exactly where it was — the app '
          'only ever copies what you explicitly picked, into its own '
          'folder.',
      'You can also send receipts to the app instead of hunting for them: '
          'use Share or Open with from your files app, email or scanner '
          'app and pick Local Budget. If you share several at once they '
          'arrive one at a time — review one, then the next.',
      'If the source sheet shows a "Recent screenshot" row, the most '
          'recent screenshot on the device is one tap away. The row only '
          'appears when the system lets the app see a screenshot at all, '
          'and picking one copies just that single image into the app.',
      'None of this touches a network. PDFs, images and screenshots are '
          'processed on the device and stored in the app’s own folder '
          'until you delete the entry.',
    ],
  ),
  HelpArticle(
    icon: Icons.tips_and_updates_outlined,
    title: 'Tips for better scans',
    paragraphs: [
      'Lay the receipt flat on a dark, plain surface and fill the frame — '
          'a receipt floating in the middle of the photo is text seen from '
          'far away.',
      'Even light beats bright light: shade and overcasts are fine, a '
          'flash glare across the total is not. A second of adjusting the '
          'angle saves a round of corrections.',
      'Hold steady and let the picture fill focus. Blur is the single '
          'biggest cause of amber outlines and wrong amounts.',
      'Scan one receipt at a time. Two overlapping receipts make one '
          'muddled merchant and two crossed totals.',
      'For PDFs, export the original document instead of photographing a '
          'screen — native PDF text reads better than any photo ever will.',
      'Crop close to the receipt when your gallery app offers it. '
          'Clutter around the edges is noise the reader has to skip.',
    ],
  ),
  HelpArticle(
    icon: Icons.savings_outlined,
    title: 'Budgets, bills & goals',
    paragraphs: [
      'Open the Budgets sheet from the Expenses stat on the month screen, '
          'or through Manage. A budget counts every expense in its '
          'period, across all your accounts, and its bar fills as the '
          'period fills up. Weekly and yearly budgets track their own '
          'week or year; the month switcher stays your waypoint either '
          'way.',
      'Rollover is a switch at the bottom of the Budgets sheet, and it '
          'has exact rules. With it on, a month you did not fully spend '
          'passes the remainder along: a badge like +\$20 from Oct means '
          'last month’s leftover is part of this month’s limit. A '
          'surplus never grows past your own limit — a \$30 budget '
          'carries at most \$30, however many good months came before '
          'it — and a month you overspent passes the hole along whole: '
          'a \$50 budget finished \$80 over starts the next month at '
          '−\$30. A category with no budget for a month breaks the '
          'chain, and that roll stops there.',
      'Rollover works on monthly budgets only. A weekly or yearly budget '
          'shows progress for its own period and never carries anything '
          'forward, and a Monthly budget needs no label at all — the '
          'badge tells you when a roll has happened.',
      'Money you move to a goal is saving, not spending — so goal '
          'transfers never appear in the day list, the month totals, or '
          'a budget’s spent number. Open the goal to read every deposit '
          'and withdrawal it received; archiving a goal pauses new '
          'transfers and keeps its history intact.',
      'A bill can ask to be remembered on its due day, and the app '
          'keeps that promise honestly: the notification is a hint, the '
          'Bills tab is the truth. Android sometimes delays or drops '
          'notifications to save battery — an overdue bill always waits '
          'for you as a Due row in the list, and tapping Mark paid (or '
          'simply opening the app again) is what records the payment. '
          'Nothing hinges on a notification arriving on time.',
    ],
  ),
  HelpArticle(
    icon: Icons.insights_outlined,
    title: 'Reports & privacy',
    paragraphs: [
      'The small chart icon at the top of the month screen opens Reports: '
          'three readings of the same ledger — Month, Year and Actual. '
          'Everything on them is computed on this device from the entries '
          'you already saved. Reports never send anything anywhere; there '
          'is no account, no sync and nothing to opt out of.',
      'Month shows what you spent, earned and kept, and — during the '
          'current month — a projection: your pace so far carried to the '
          'end of the month. It is arithmetic, not advice; a quiet week '
          'or a big bill both move it. Tap a slice of the category donut '
          'to see exactly the transactions behind it, in the same list '
          'style as the ledger.',
      'Year draws one bar per month and a dashed line at the average. Tap '
          'any bar to jump straight to that month in the Month view. '
          'Months with no spending count as zero in the average — a '
          'honest denominator, not a flattering one.',
      'Actual answers "how far into my limits am I?" with the very same '
          'numbers the Budgets tab uses, drawn as bars with a marker at '
          'the limit. When rollover is on, a faint ghost marker shows '
          'the plain limit while the bar is measured against the carried, '
          'adjusted one. A category without a limit stays out of the way.',
      'Reports read only what is on this phone, so airplane mode changes '
          'nothing about them. If a number looks wrong, the fix is always '
          'in the ledger: tap through to the rows, correct or delete, and '
          'every report updates the moment you go back.',
    ],
  ),
  HelpArticle(
    icon: Icons.coffee_outlined,
    title: 'Buy me a coffee',
    paragraphs: [
      'Manage has a Support row with two options. A tip — a small, medium '
          'or large coffee — is charged by your app store exactly like any '
          'other in-app purchase, and it unlocks nothing. Every feature '
          'this app has today is free forever; a tip is simply you telling '
          'the developer the app is worth a coffee.',
      'Tips are one-time each: buying one never starts a subscription, and '
          'there is nothing to cancel. If a purchase takes a while, the app '
          'says so — a tip that is still processing completes on its own, '
          'and a cancelled one costs you nothing.',
      'Tipping depends on your store account and country, so the buttons '
          'can be grey for reasons the app cannot see. When store billing '
          'is unavailable, the same row offers a web page instead — '
          'nothing here is required either way.',
      'The second option, Get Pro, is described in the next article. '
          'Neither one sends your ledger anywhere: support and upgrades '
          'never read your data.',
    ],
  ),
  HelpArticle(
    icon: Icons.swap_horiz,
    title: 'Upgrading to Pro, and copying your data',
    paragraphs: [
      'Pro is a separate app in the store, bought once — not a feature '
          'switch inside this one. It is the same ledger with three extra '
          'things: an encrypted personal cloud backup, home-screen '
          'widgets and detailed analytics. The free app keeps everything '
          'it does today; nothing is taken away when you upgrade.',
      'To move your data, first copy it out of the free app: open '
          'Manage → Get Pro → Copy my data to Pro. The app encrypts a '
          'snapshot of your ledger and attachments on this device — the '
          'same envelope as an exported backup file — and holds it for '
          'the other app. No network is involved at any step.',
      'Then open Pro. Its Manage screen shows a Transfer from free app '
          'row with how fresh the copied snapshot is — only tap it once '
          'the age looks right. Transfer replaces everything in Pro with '
          'the copy, after asking you to confirm, because the free app '
          'wins: two apps, one ledger.',
      'The free app is never changed by copying or transferring, and '
          'keeping it installed is optional afterwards — Pro keeps every '
          'entry it received. If the two apps cannot see each other (for '
          'example, one came from a different store), export a backup '
          'file from the free app and restore it in Pro instead; that '
          'path always works.',
    ],
  ),
  // ── E8 §2: the remaining screens, one article each ───────────────────────
  HelpArticle(
    icon: Icons.calendar_month_outlined,
    title: 'Your month at a glance',
    paragraphs: [
      'The main screen is one month at a time. The name across the top is '
          'the month you are looking at; the arrows beside it step to the '
          'next or previous month, and you can also drag the row left or '
          'right. Underneath, the spending and income readings summarise '
          'the month, and the chart icon opens Reports for the deeper '
          'views.',
      'Below the summary, your entries sit in day groups, newest day '
          'first. Tap any row to edit it. Swipe a row to delete it, and '
          'the bar that appears offers five seconds of Undo — a deleted '
          'entry is only really gone when that bar is gone.',
      'The plus button adds an entry by hand: an amount, a category, and '
          'whether it is an expense or income. “Today”, “Yesterday” and '
          'the calendar set its date, and everything stays editable '
          'afterwards like any scanned entry.',
      'The camera button next to it scans a receipt — that flow has its '
          'own article. Money moved to a goal counts as saving, not '
          'spending, so it never appears in the day list or the spending '
          'reading; income lands in its own reading and never eats a '
          'budget.',
    ],
  ),
  HelpArticle(
    icon: Icons.file_download_outlined,
    title: 'Importing a bank statement',
    paragraphs: [
      'Manage → Import statement turns a bank export into entries. Two '
          'kinds of file work: a CSV (the spreadsheet export your bank’s '
          'website offers) and an OFX statement, the bank-format file. '
          'Everything is read on this device; nothing is uploaded.',
      'Pick which account the rows belong to, then tell the app which '
          'column holds the date, the description and the amount — CSV '
          'files vary wildly here, which is why the wizard asks instead '
          'of guessing. OFX files carry their own labels, so there is '
          'less to map. If your card writes expenses as positive numbers, '
          'leave “Debit means expense” on; turn it off only for statements '
          'that flip the sign.',
      'Before anything is saved you see a preview of every row. Rows with '
          'an unreadable date or amount are listed as skipped — fix them '
          'in the file or add them by hand. Rows the app has seen before '
          'are marked “already imported” and stay out of the count, so '
          'importing the same statement twice never doubles your ledger.',
      'Import adds the checked rows; save the mapping as a profile and '
          'next month’s export from the same bank arrives already mapped. '
          'Once imported, the rows are ordinary entries: tap to edit, '
          'swipe to delete, and the ledger stays the single place your '
          'money is written down.',
    ],
  ),
  HelpArticle(
    icon: Icons.backup_outlined,
    title: 'Backup and restore',
    paragraphs: [
      'Manage → Back up writes one file to this device containing your '
          'whole ledger, encrypted with a passphrase you choose. The '
          'encryption is real, which means the passphrase is the only '
          'key: write it down somewhere safe, because nobody — not the '
          'developer, not your bank, not support — can recover a file '
          'without it.',
      'Restore picks a file and puts this device back to how it was when '
          'that file was made, after asking you to confirm. It replaces '
          'what is here, so a backup made before something important also '
          'removes it — check the file’s age before you reach for it.',
      'The file is yours to keep wherever you like: the Files app, a '
          'drive that is yours, an external disk. The app never uploads '
          'it anywhere. Changing phones is the simple case: back up on '
          'the old phone, restore on the new one, and the passphrase is '
          'the only thing that travels with you.',
      'If you use Pro’s cloud destinations, automatic copies use exactly '
          'this same encrypted file — read “Pro extras” for the schedule. '
          'A manual backup before a big cleanup is always a good habit: it is '
          'fast, and it can undo almost anything.',
    ],
  ),
  HelpArticle(
    icon: Icons.currency_exchange_outlined,
    title: 'Currencies and exchange rates',
    paragraphs: [
      'The app keeps one home currency — the one every reading is shown '
          'in — and you choose it in Manage. Your sums, budgets and '
          'reports all speak that currency.',
      'Individual entries can be in a different currency: the entry form '
          'and the scan review both offer an “Entry currency” choice. The '
          'entry remembers the amount as you typed it and shows its value '
          'in your home currency alongside, so nothing is silently '
          'rewritten.',
      'The “Live exchange rates” switch in Manage decides where rates '
          'come from. With it on, the app fetches current rates when the '
          'network is available; with it off, nothing is ever fetched and '
          'entries use the rates the app already has. Either way the '
          'choice is remembered on this device.',
      'A rate is a conversion aid, not a bank statement: if one looks '
          'off, edit the entry and type the value you actually paid — '
          'your number is the one the ledger keeps.',
    ],
  ),
  HelpArticle(
    icon: Icons.sell_outlined,
    title: 'Categories that fit your life',
    paragraphs: [
      'Every entry carries one category, and categories are what the '
          'donut in Reports, the Budgets screen and the home-screen '
          'envelope widget all read. The app ships a sensible default set '
          '— groceries, dining, transport, utilities and the rest — each '
          'with its own icon.',
      'The quick-add sheet shows your most-used categories as chips; the '
          'Manage chip on the same row opens the category editor, where '
          'you name a new category and pick its icon. Making one is a '
          'few seconds, and it is instantly available everywhere.',
      'Rename a category whenever you like — existing entries follow the '
          'new name, because the ledger remembers the category, not a '
          'spelling. A category earns a budget on the Budgets screen, '
          'where it gets a limit and, if you switch it on, rollover.',
      'The best taxonomy is a small one: if you can never tell two '
          'categories apart at a glance, merge them — a report you do '
          'not read is a report that does not help.',
    ],
  ),
  HelpArticle(
    icon: Icons.privacy_tip_outlined,
    title: 'Your data stays yours',
    paragraphs: [
      'There is no account, no sign-in and no profile. Your ledger lives '
          'in this device’s own storage, and the app collects nothing: '
          'no analytics, no ads, no statistics about you leaving the '
          'phone. The store’s own privacy form should read the same way — '
          'data is not collected — and if it ever reads differently, '
          'that is a bug worth reporting.',
      'Receipt scanning runs entirely on the device. The photos and PDFs '
          'you pick are copied into the app’s own folder for your review '
          'and go no further; deleting an entry deletes its attachment.',
      'The app reaches outside the phone in exactly three situations, '
          'and you can see every one of them: exchange rates when the '
          'Live rates switch is on, your own WebDAV destination when a '
          'Pro automatic backup runs, and the store when you buy a tip or '
          'Pro. Everything else — every reading, edit, search and report '
          '— works in airplane mode because it never needed the network.',
      'Backups and exports are your copies, made on the device and '
          'encrypted with your passphrase. Uninstalling the app removes '
          'everything it holds. If you ever leave, the door is wide open '
          '— that is the whole design.',
    ],
  ),
  HelpArticle(
    icon: Icons.workspace_premium_outlined,
    title: 'Pro extras: cloud, widgets & insights',
    paragraphs: [
      'Pro adds three things to the same ledger and takes nothing away. '
          '“Upgrading to Pro” explains the switch itself; this article is '
          'about using the extras.',
      'Cloud backups (Pro): Manage → Cloud destinations takes a WebDAV '
          'address, user name and password — your own server or hosting. '
          'Every upload is the same encrypted backup file the manual '
          'export makes, and the auto-backup switch keeps at most one '
          'unattended copy per day, only when the phone has network and '
          'is not saving battery. The destination row shows when a copy '
          'last succeeded, so “automatic” is never “mysterious”.',
      'Widgets (Pro): long-press an empty spot on your home screen, open '
          'the widget picker and find LocalBudget Pro. Spend this month '
          'opens Reports when tapped; Envelope left shows whichever '
          'envelope has the least room left — long-press the widget while '
          'placing it to pin a specific one — and Quick scan lands '
          'straight on the capture sheet. A widget showing a dash means '
          'its reading is from another month: open the app and every '
          'tile refreshes.',
      'Insights (Pro): the fourth tab inside Reports answers the "over '
          'what range?" questions — pick a range with the chip at the '
          'top and share a tidy PDF of exactly what you see, built on '
          'the device like everything else.',
    ],
  ),
];

// ── Local search index (E8 §1) ──────────────────────────────────────────────
//
// A tiny inverted index over the same strings the reader sees — built once
// at first use, no network, no plugin. "Local" is literal: the corpus ships
// in the binary and the index is a few kilobytes of Dart maps.
//
// Ranking is deliberately boring and deterministic: an exact whole-query
// phrase match gets a small head start (the old substring behaviour
// survives), per-token hits stack on top weighted title > body, and a
// prefix allowance lets a half-typed word still land ("passphras" →
// "passphrase"). A query whose words no article contains literally falls
// back to the old substring test, so odd single letters keep matching the
// way people expect while typing.

final RegExp _wordPattern = RegExp(r'[a-z0-9]+');

/// token → article indices, per field; built lazily from [kHelpArticles].
final (Map<String, Set<int>>, Map<String, Set<int>>) _index = () {
  final t = <String, Set<int>>{};
  final b = <String, Set<int>>{};
  for (var i = 0; i < kHelpArticles.length; i++) {
    for (final m in _wordPattern.allMatches(
      kHelpArticles[i].title.toLowerCase(),
    )) {
      t.putIfAbsent(m[0]!, () => {}).add(i);
    }
    for (final paragraph in kHelpArticles[i].paragraphs) {
      for (final m in _wordPattern.allMatches(paragraph.toLowerCase())) {
        b.putIfAbsent(m[0]!, () => {}).add(i);
      }
    }
  }
  return (t, b);
}();

List<HelpArticle> searchHelpArticles(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return kHelpArticles;

  // Phrase first: whatever contains the whole query as written edges
  // ahead of scattered word hits, but tokens still stack on top, so an
  // article whose title matches both words stays ahead of one that only
  // happens to carry the phrase in its body.
  final scores = List<double>.filled(kHelpArticles.length, 0);
  var anyPhrase = false;
  for (var i = 0; i < kHelpArticles.length; i++) {
    if (kHelpArticles[i].haystack.contains(q)) {
      scores[i] += 4;
      anyPhrase = true;
    }
  }

  final words = _wordPattern.allMatches(q).map((m) => m[0]!).toSet();
  final anyExactWord = words.any(
    (w) => _index.$1.containsKey(w) || _index.$2.containsKey(w),
  );
  if (!anyPhrase && !anyExactWord) {
    // Nothing to rank — old substring semantics for stray fragments.
    return kHelpArticles.where((a) => a.haystack.contains(q)).toList();
  }

  for (final word in words) {
    for (var i = 0; i < kHelpArticles.length; i++) {
      final titleExact = _index.$1[word]?.contains(i) ?? false;
      final bodyExact = _index.$2[word]?.contains(i) ?? false;
      if (titleExact) scores[i] += 3;
      if (bodyExact) scores[i] += 2;
      if (word.length >= 3) {
        // Half-typed words earn a little via prefixes: an article whose
        // title hosts the plural (“pdfs” for “pdf”) is a strong hint and
        // counts whether or not the body mentions the word too; a bare
        // body prefix counts less.
        if (!titleExact &&
            _index.$1.keys.any(
              (t) =>
                  t != word && t.startsWith(word) && _index.$1[t]!.contains(i),
            )) {
          scores[i] += 1;
        }
        if (!bodyExact &&
            _index.$2.keys.any(
              (t) =>
                  t != word && t.startsWith(word) && _index.$2[t]!.contains(i),
            )) {
          scores[i] += 0.5;
        }
      }
    }
  }

  final hits = [
    for (var i = 0; i < kHelpArticles.length; i++)
      if (scores[i] > 0) i,
  ];
  // Sort by score, ties broken by listing order — deterministic for the
  // acceptance tests and predictable for the reader (List.sort itself is
  // not stable, so the index tiebreaker is spelled out).
  hits.sort((a, b) {
    final byScore = scores[b].compareTo(scores[a]);
    return byScore != 0 ? byScore : a.compareTo(b);
  });
  return [for (final i in hits) kHelpArticles[i]];
}
