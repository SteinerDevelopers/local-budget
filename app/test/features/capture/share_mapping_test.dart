import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/capture/capture_intake.dart';

/// Issue #28 — the share/open-with mapping (§5, decision 5). Pure tier on
/// purpose: the plugin adapter itself is never imported by a unit test
/// (§7 hermetic rule), only this contract it obeys.
void main() {
  group('shareChoiceFor', () {
    test('a shared PDF behaves like the PDF row', () {
      expect(shareChoiceFor('application/pdf'), CaptureChoice.pdf);
    });

    test('shared images behave like the screenshot row', () {
      for (final mime in ['image/png', 'image/jpeg', 'image/jpg']) {
        expect(shareChoiceFor(mime), CaptureChoice.screenshot, reason: mime);
      }
    });

    test(
      'text, url and unknown shares are not receipts — ignored, not half-imported',
      () {
        for (final mime in ['text/plain', 'image/gif', 'video/mp4', null]) {
          expect(shareChoiceFor(mime), isNull, reason: '$mime');
        }
      },
    );

    test('the mapped choices carry the review badge + storage extension', () {
      // Shared pdf  → PDF badge, .pdf original.
      expect(shareChoiceFor('application/pdf')!.source.wireName, 'pdf_import');
      expect(shareChoiceFor('application/pdf')!.fileExtension, 'pdf');
      // Shared image → Screenshot badge, .jpg original (png bytes are fine
      // under the image extension the store whitelist knows).
      expect(shareChoiceFor('image/png')!.source.wireName, 'screenshot_import');
    });
  });
}
