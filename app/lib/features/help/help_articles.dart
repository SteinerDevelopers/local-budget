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
];

/// Case-insensitive substring search over title and body — enough for a
/// few dozen offline articles, and it keeps "search" honest: whatever a
/// user can read, a user can find.
List<HelpArticle> searchHelpArticles(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return kHelpArticles;
  return kHelpArticles.where((a) => a.haystack.contains(q)).toList();
}
