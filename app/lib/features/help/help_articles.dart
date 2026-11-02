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
];

/// Case-insensitive substring search over title and body — enough for a
/// few dozen offline articles, and it keeps "search" honest: whatever a
/// user can read, a user can find.
List<HelpArticle> searchHelpArticles(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return kHelpArticles;
  return kHelpArticles.where((a) => a.haystack.contains(q)).toList();
}
