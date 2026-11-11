import 'package:flutter/material.dart';

/// Offline help articles (feasibility §4.1-10, E2 §7). Everything ships in
/// the binary — search runs over these strings, so "offline" is literal,
/// not a promise about a network cache.
///
/// Voice rules (§ copy bar): plain second person, no feature branding of
/// any kind — the reader-facing app never names the machinery behind a
/// reading, it says what the app did and what the user can do next. Every
/// article ends where the user can act; none is a dead end.
///
/// Audience: the family budgeting at the kitchen table, not the reviewer in
/// the repo. Everyday words only — engineering vocabulary ("ledger",
/// "rendered", "snapshot", "taxonomy") belongs in commit messages, and UI
/// labels the reader can see on screen are quoted exactly as they read.
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
      'The app reads the picture on your phone and fills in what it '
          'recognises — the shop, the date and the total — then opens a '
          'review screen so you can fix anything before it is kept.',
      'Nothing is ever saved by itself. The review screen is only a '
          'suggestion: the entry joins your list when you tap Save, and '
          'swiping it away or pressing back changes nothing at all.',
      'You can edit every field once, twice or not at all. A scanned entry '
          'behaves like a typed one afterwards — swipe to delete, tap to '
          'edit, five seconds of Undo.',
    ],
  ),
  HelpArticle(
    icon: Icons.edit_note_outlined,
    title: 'Why is a field highlighted?',
    paragraphs: [
      'A field with an amber outline is the app being honest: it read '
          'that value from the receipt, but it is not sure it got it '
          'right. A blurry photo, a glare, a crease in the paper, '
          'handwriting, or a total printed far away from the word '
          '"total" can all cause it.',
      'Tap a highlighted field to fix it. The outline disappears as soon '
          'as you type — the app stops guessing the moment you answer.',
      'Give the other fields a quick look too: no outline means the app '
          'is fairly sure, never certain. The point of the review step '
          'is that you decide, not the app.',
      'If a field you need is simply missing, type it in — an empty field '
          'is the app saying "I could not read this", and your keyboard is '
          'always the better reader.',
    ],
  ),
  HelpArticle(
    icon: Icons.picture_as_pdf_outlined,
    title: 'Importing PDFs & screenshots',
    paragraphs: [
      'A PDF opens at its first page: the app shows that page, reads the '
          'text on it, and the review screen appears like any other '
          'scan. The original PDF stays exactly where it was — the app '
          'only ever copies what you chose, into its own folder.',
      'You can also send receipts to the app instead of hunting for them: '
          'use Share or Open with from your files app, email or scanner '
          'app and pick Steiner Budget. If you share several at once they '
          'arrive one at a time — review one, then the next.',
      'If the source sheet shows a "Recent screenshot" row, the most '
          'recent screenshot on your phone is one tap away. The row only '
          'appears when your phone lets the app see screenshots at all, '
          'and picking one copies just that single image into the app.',
      'None of this needs the internet. PDFs, images and screenshots are '
          'read on your phone and stored in the app’s own folder until '
          'you delete the entry.',
    ],
  ),
  HelpArticle(
    icon: Icons.tips_and_updates_outlined,
    title: 'Tips for better scans',
    paragraphs: [
      'Lay the receipt flat on a dark, plain surface and fill the frame — '
          'a receipt floating in the middle of the photo is text seen from '
          'far away.',
      'Even light beats bright light: shade and cloudy days are fine, a '
          'flash glare across the total is not. A second spent adjusting '
          'the angle saves a round of corrections.',
      'Hold steady and let the picture focus. Blur is the single biggest '
          'cause of amber outlines and wrong amounts.',
      'Scan one receipt at a time. Two overlapping receipts make one '
          'muddled shop name and two crossed totals.',
      'For PDFs, use the original file instead of photographing a screen '
          '— text from a real PDF file reads better than any photo ever '
          'will.',
      'Crop close to the receipt when your gallery app offers it. '
          'Clutter around the edges makes the words harder to find.',
    ],
  ),
  HelpArticle(
    icon: Icons.savings_outlined,
    title: 'Budgets, bills & goals',
    paragraphs: [
      'The bar at the bottom of the app switches between the four '
          'places: Receipts, Budgets, Bills and Goals. The Budgets '
          'screen follows whichever month you are on in Receipts — '
          'tapping the Expenses tile there walks you straight over. '
          'Manage still opens everything in one sheet too. A budget '
          'counts every expense in '
          'its period, across all your accounts, and its bar fills as '
          'you spend. Weekly and yearly budgets track their own week or '
          'year; you move between months the same way whichever budget '
          'you set.',
      'Rollover is the switch at the bottom of the Budgets screen. '
          'Here '
          'is exactly what it does. With it on, a month you did not '
          'spend out of passes the leftover along: a badge like +\$20 '
          'from Oct means last month’s leftover is part of this '
          'month’s limit. The leftover never grows past your own limit '
          '— a \$30 budget carries at most \$30, however many good '
          'months came before it — and if you overspent, the overshoot '
          'carries the same way: a \$50 budget finished \$80 over '
          'starts the next month at −\$30. If a month has no budget for '
          'that category, the carry-along stops there.',
      'Only monthly budgets roll over. A weekly or yearly budget shows '
          'progress for its own period and carries nothing forward. You '
          'never have to remember which months rolled — the badge shows '
          'it.',
      'Money you move to a goal is saving, not spending — so a goal '
          'transfer never appears in the day list, the month totals, or '
          'a budget’s spent number. Open a goal to see every deposit '
          'and withdrawal it received; archiving a goal pauses new '
          'transfers and keeps its history.',
      'A bill can ask to be remembered on its due day, and the app is '
          'straight with you about it: the reminder is a nudge, the '
          'Bills tab is the truth. Android sometimes delays or drops '
          'reminders to save battery — an overdue bill always waits for '
          'you as a Due row in the list, and tapping Mark paid (or '
          'simply opening the app again) is what records the payment. '
          'Nothing hinges on a reminder arriving on time.',
    ],
  ),
  HelpArticle(
    icon: Icons.insights_outlined,
    title: 'Reports & privacy',
    paragraphs: [
      'The small chart icon at the top of the month screen opens Reports: '
          'three views of the same entries — Month, Year and Actual. '
          'Every number on them is worked out on your phone from what '
          'you already saved. Reports never send anything anywhere: '
          'there is no account, nothing syncs, and there is nothing to '
          'turn off.',
      'Month shows what you spent, earned and kept, and — during the '
          'current month — a best guess at the end of the month, based '
          'on your pace so far. It is a sum, not advice; a quiet week '
          'or a big bill both move it. Tap a slice of the category '
          'donut to see exactly the entries behind it, listed just like '
          'your day list.',
      'Year draws one bar per month and a dashed line at the average. '
          'Months with no spending count as zero — the average includes '
          'every month, not just the busy ones. Tap any bar to jump '
          'straight to that month in the Month view.',
      'Actual answers "how close am I to my limits?" using the very '
          'same numbers the Budgets tab shows, drawn as bars with a '
          'mark at each limit. When rollover is on, a faint second mark '
          'shows your plain limit, while the bar itself is measured '
          'against the carried-over one. A category without a limit '
          'stays out of the way.',
      'Reports read only what is on this phone, so airplane mode '
          'changes nothing about them. If a number looks wrong, the fix '
          'is always in your entries: tap through to the rows, correct '
          'or delete, and every report updates the moment you go back.',
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
          'can look unavailable for reasons the app cannot see. When '
          'your store cannot take payment here, the same row offers a '
          'web page instead — nothing here is required either way.',
      'The second option, Get Pro, is described in the next article. '
          'Neither one sends your entries anywhere: support and '
          'upgrades never read your data.',
    ],
  ),
  HelpArticle(
    icon: Icons.swap_horiz,
    title: 'Upgrading to Pro, and copying your data',
    paragraphs: [
      'Pro is a separate app in the store, bought once — not a feature '
          'switch inside this one. It is the same app you know with '
          'three extras: a cloud backup to storage you own, home-screen '
          'widgets and in-depth reports. The free app keeps everything '
          'it does today; nothing is taken away when you upgrade.',
      'To move your data, first copy it out of the free app: open '
          'Manage → Get Pro → Copy my data to Pro. The app makes an '
          'encrypted copy of everything you have saved — entries and '
          'receipt photos alike — right on your phone, and holds it for '
          'the other app. No internet is involved at any step.',
      'Then open Pro. Its Manage screen shows a Transfer from free app '
          'row with how fresh the copied data is — only tap it once '
          'the age looks right. Transfer replaces everything in Pro with '
          'the copy, after asking you to confirm, so the free app '
          'wins: two apps, one set of entries.',
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
          'right. Underneath, the spending and income figures summarise '
          'the month, and the chart icon opens Reports for the deeper '
          'views. Next to them, the question mark opens this Help, and '
          'the gear opens Manage — the app’s settings and tools all '
          'live there.',
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
          'number; income gets its own number and never eats a '
          'budget.',
    ],
  ),
  HelpArticle(
    icon: Icons.file_download_outlined,
    title: 'Importing a bank statement',
    paragraphs: [
      'Manage → Import statement turns a file from your bank into '
          'entries. Two kinds of file work: a CSV (the spreadsheet '
          'export your bank’s website offers) and an OFX statement (a '
          'ready-made format some banks use). Everything is read on '
          'your phone; nothing is uploaded.',
      'Pick which account the rows belong to, then tell the app which '
          'column holds the date, the description and the amount — CSV '
          'files look different from bank to bank, which is why the '
          'wizard asks instead of guessing. OFX files carry their own '
          'labels, so there is less to sort out. If your card writes '
          'expenses as positive numbers, leave “Debit means expense” '
          'on; turn it off only for statements that flip the sign.',
      'Before anything is saved you see a preview of every row. Rows '
          'with an unreadable date or amount are listed as skipped — '
          'fix them in the file or add them by hand. Rows the app has '
          'seen before are marked “already imported” and stay out of '
          'the count, so importing the same statement twice never '
          'counts an expense twice.',
      'Import adds the rows you tick; once you have picked the columns '
          'once, the app remembers them and next month’s file from the '
          'same bank arrives already set up. Once imported, the rows '
          'are ordinary entries: tap to edit, swipe to delete — this '
          'stays the one place your money is written down.',
    ],
  ),
  HelpArticle(
    icon: Icons.document_scanner_outlined,
    title: 'Import a bill or statement from a photo/PDF',
    paragraphs: [
      'Some paperwork is a photo or a scan rather than a file from your '
          'bank’s website. Manage → Import statement has a third row, '
          '“Photo or PDF”: photograph (or pick) a bill or a '
          'statement — a PDF works too — and the app reads the text '
          'off it on your phone.',
      'A statement comes back as rows: the app finds the date, the '
          'description and the amount on each line and opens them in '
          'the same preview as a CSV or OFX import. Rows it has seen '
          'before are marked “already imported” and stay out of the '
          'count, so re-importing last month’s statement never counts '
          'anything twice. Tick what you want, import, done.',
      'A bill becomes a head start on a reminder: the payee, the '
          'amount and the due date arrive typed in, and you still '
          'choose when it repeats and tap Save. For a credit-card '
          'statement the amount filled in is the minimum payment '
          'due — the figure you actually pay each month — not the '
          'balance sitting on the page. The document alone '
          'never writes to your ledger or your bills.',
      'In a hurry, the Bills tab has its own “Scan a bill” '
          'button. It reads a bill the same way; if your photo turns '
          'out to be a full statement instead, it says so and points '
          'you at the import wizard, where you can review every '
          'transaction before anything lands.',
      'When the app can’t make out either shape in your photo, it says '
          'so and points at CSV or OFX instead — it would rather hand '
          'you the honest no than guess at your money. Reading happens '
          'on your phone: no upload, and nothing is saved until you '
          'say so.',
    ],
  ),
  HelpArticle(
    icon: Icons.backup_outlined,
    title: 'Backup and restore',
    paragraphs: [
      'Manage → Back up now writes one file to your phone containing '
          'every entry you '
          'have, encrypted with a passphrase you choose. The '
          'encryption is real, which means the passphrase is the only '
          'key: write it down somewhere safe, because nobody — not the '
          'developer, not your bank, not support — can open a file '
          'without it.',
      'Restore from backup picks a file and puts your phone back to how '
          'it was when '
          'that file was made, after asking you to confirm. It replaces '
          'what is here, so a backup made before something important also '
          'removes it — check the file’s age before you reach for it.',
      'The file is yours to keep wherever you like: the Files app, a '
          'drive that is yours, an external disk. The app never uploads '
          'it anywhere. Changing phones is the simple case: back up on '
          'the old phone, restore on the new one, and the passphrase is '
          'the only thing that travels with you.',
      'If you turn on Pro’s cloud backups, the automatic copies are '
          'exactly this same encrypted file — read “Pro extras” for '
          'when they run. A manual backup before a big tidy-up is '
          'always a good habit: it is '
          'fast, and it can undo almost anything.',
      'If a “Database check” banner appears at the top of the app, the app '
          'could not read part of your saved data cleanly — everything still '
          'works, and the banner is safe to dismiss. If anything looks odd '
          'later, restoring a backup you trust from Manage puts things '
          'right. The banner only appears when something is genuinely '
          'wrong, so quiet days need no action.',
    ],
  ),
  HelpArticle(
    icon: Icons.currency_exchange_outlined,
    title: 'Currencies and exchange rates',
    paragraphs: [
      'The app keeps one home currency — the currency every amount is '
          'shown in — and you choose it in Manage. Your sums, budgets '
          'and reports all speak that currency.',
      'Individual entries can be in a different currency: the entry form '
          'and the scan review both offer an “Entry currency” choice. The '
          'entry remembers the amount as you typed it and shows its value '
          'in your home currency alongside, so nothing is changed '
          'behind your back.',
      'The “Live FX rates” switch in Manage decides where exchange '
          'rates come from. It starts off: until you turn it on, nothing '
          'is ever looked up and entries use the rates the app already '
          'has. Turning it on asks first and says what it does: the app '
          'looks up current rates from frankfurter.dev when there is '
          'internet, carrying only the two currency codes. Either way '
          'the choice is remembered on this phone.',
      'A converted amount is the app’s best help, not a bank '
          'statement: if one looks off, edit the entry and type the '
          'value you actually paid — your number is the one that gets '
          'kept.',
    ],
  ),
  HelpArticle(
    icon: Icons.sell_outlined,
    title: 'Categories that fit your life',
    paragraphs: [
      'Every entry carries one category, and categories are what the '
          'donut in Reports, the Budgets screen and the home-screen '
          'widget all read. The app ships a sensible default set '
          '— groceries, dining, transport, utilities and the rest — each '
          'with its own icon.',
      'The quick-add sheet shows your most-used categories as little '
          'buttons you tap; the Manage button on the same row opens the '
          'category editor, where you name a new category and pick its '
          'icon. Making one is a few seconds, and it is instantly '
          'available everywhere.',
      'Rename a category whenever you like — existing entries follow the '
          'new name automatically, and old entries keep counting under '
          'it. A category earns a budget on the Budgets screen, '
          'where it gets a limit and, if you switch it on, rollover.',
      'Keep the list small on purpose: if you can never tell two '
          'categories apart at a glance, merge them — a report you do '
          'not read is a report that does not help.',
    ],
  ),
  HelpArticle(
    icon: Icons.privacy_tip_outlined,
    title: 'Your data stays yours',
    paragraphs: [
      'There is no account, no sign-in and no profile. Your entries live '
          'in this phone’s own storage, and the app collects nothing: '
          'no tracking, no ads, no reports about you leaving the '
          'phone. The store’s own privacy form should read the same way — '
          'data is not collected — and if it ever reads differently, '
          'that is a bug worth reporting.',
      'Receipt scanning runs entirely on your phone. The photos and PDFs '
          'you pick are copied into the app’s own folder for your review '
          'and go no further; deleting an entry deletes its picture too.',
      'The app reaches outside the phone in exactly three situations, '
          'and you can see every one of them: exchange rates when the '
          'Live rates switch is on, the cloud storage you set up when a '
          'Pro automatic backup runs, and the store when you buy a tip or '
          'Pro. Everything else — every entry, edit, search and report '
          '— works in airplane mode because it never needed the internet.',
      'Backups and exports are your copies, made on your phone and '
          'encrypted with your passphrase. Uninstalling the app removes '
          'everything it holds. If you ever leave, the door is wide open '
          '— that is the whole design.',
    ],
  ),
  HelpArticle(
    icon: Icons.workspace_premium_outlined,
    title: 'Pro extras: cloud, widgets & insights',
    paragraphs: [
      'Pro adds three things to the same app and takes nothing away. '
          '“Upgrading to Pro” explains the switch itself; this article is '
          'about using the extras.',
      'Cloud backups (Pro): Manage → Cloud backups asks for the '
          'address, user name and password of storage you own online — '
          'a home server (NAS) or web hosting that speaks WebDAV. '
          'Every upload is the same encrypted backup file the manual '
          'backup makes, and the auto-backup switch runs on its own at '
          'most once a day, only when the phone is online and not saving '
          'battery. The screen shows when a copy '
          'last succeeded, so “automatic” is never “mysterious”.',
      'Widgets (Pro): long-press an empty spot on your home screen, open '
          'the widget picker and find Steiner Budget Pro. Spend this month '
          'opens Reports when tapped; Envelope left shows whichever '
          'budget has the least room left — long-press the widget while '
          'placing it to pin a specific one — and Quick scan opens the '
          'receipt camera right away. A widget showing a dash means '
          'its number is from another month: open the app and every '
          'widget refreshes.',
      'Insights (Pro): the fourth tab inside Reports answers questions '
          'like “what did I spend on groceries this year?” — pick the '
          'stretch of time with the buttons at the top and share a tidy '
          'PDF of exactly what you see, made on your phone like '
          'everything else.',
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
