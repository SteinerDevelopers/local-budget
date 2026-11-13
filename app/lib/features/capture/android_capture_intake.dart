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

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'capture_intake.dart';
import 'capture_services.dart';

/// Real-device intake (issue #28, design sections 2.2/5). Every path here is
/// the permission-less system story: ML Kit's scanner activity, the system
/// camera/gallery pickers and SAF -- the app itself declares no media or
/// camera runtime permissions.
///
/// Tests never import this file (the fake intake keeps the review tier
/// hermetic, section 7); nothing here runs in a unit test.
class AndroidCaptureIntake implements CaptureIntake {
  AndroidCaptureIntake() {
    _probeScreenshot();
  }

  /// Native half (section 5): SAF `ACTION_OPEN_DOCUMENT` + an opportunistic
  /// MediaStore probe, both served by `MainActivity`.
  static const MethodChannel _channel = MethodChannel('localbudget/capture');

  final ImagePicker _picker = ImagePicker();

  Uint8List? _screenshot;

  /// Section 2.1 escape hatch: the row exists only while the probe found
  /// bytes without any permission; a hidden row is never a dead end.
  @override
  bool get hasScreenshotRow => _screenshot != null;

  /// #56 consent gate: set before every pick by `gateScannerConsent`; false
  /// skips the GMS scanner entirely (its first use may download Google's
  /// module) and opens the plain camera directly.
  @override
  bool allowScanner = true;

  Future<void> _probeScreenshot() async {
    try {
      _screenshot = await _channel.invokeMethod<Uint8List>('latestScreenshot');
    } catch (_) {
      _screenshot = null; // no row, no prompt -- the documented fallback
    }
  }

  @override
  Future<CapturePick?> pick(CaptureChoice choice) => switch (choice) {
    CaptureChoice.camera => _camera(),
    CaptureChoice.photos => _image(ImageSource.gallery, choice),
    CaptureChoice.pdf => _document(),
    CaptureChoice.screenshot => _screenshotPick(),
  };

  /// Section 2.2 verbatim: the scanner is the fast path; unavailable (plugin
  /// missing, old device) or cancelled, the plain camera takes over --
  /// "still one image out". Multi-page scans keep page 1: the receipt face.
  Future<CapturePick?> _camera() async {
    // #56: a declined consent skips the scanner construction entirely —
    // instantiating it is what may trigger Google's module download.
    if (allowScanner) {
      try {
        final scanner = DocumentScanner(
          options: DocumentScannerOptions(
            documentFormats: const {DocumentFormat.jpeg},
            pageLimit: 1,
          ),
        );
        final result = await scanner.scanDocument();
        final images = result.images;
        final path = (images == null || images.isEmpty) ? null : images.first;
        if (path != null) {
          return CapturePick(
            bytes: await File(path).readAsBytes(),
            choice: CaptureChoice.camera,
          );
        }
        // A null/empty result means the user cancelled the scanner; section
        // 2.2's fallback chain continues into the plain camera rather than
        // dead-ending.
      } catch (_) {
        // PlatformException / MissingPluginException -- scanner unavailable.
      }
    }
    return _image(ImageSource.camera, CaptureChoice.camera);
  }

  Future<CapturePick?> _image(ImageSource source, CaptureChoice choice) async {
    // System pickers (Photo Picker / camera intent): zero permissions, and
    // no imageQuality -- section 4 stores the original bytes untouched.
    final file = await _picker.pickImage(source: source);
    if (file == null) return null;
    return CapturePick(bytes: await file.readAsBytes(), choice: choice);
  }

  /// SAF document picker accepting `image/*` and `application/pdf`
  /// (section 5). The row invites PDFs; an image picked there is still a
  /// legit receipt, so it keeps image semantics end-to-end instead of
  /// masquerading as a PDF.
  Future<CapturePick?> _document() async {
    final picked = await _channel.invokeMethod<Map<Object?, Object?>>(
      'openDocument',
    );
    if (picked == null) return null; // user backed out of SAF
    final bytes = picked['bytes'];
    if (bytes is! Uint8List) return null;
    final name = (picked['name'] as String?)?.toLowerCase() ?? '';
    final isImage =
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png');
    return CapturePick(
      bytes: bytes,
      choice: isImage ? CaptureChoice.photos : CaptureChoice.pdf,
    );
  }

  Future<CapturePick?> _screenshotPick() async {
    // The row only renders once the probe found bytes; re-probe on tap so a
    // screenshot taken after launch is the one that opens (section 2.1).
    await _probeScreenshot();
    final shot = _screenshot;
    return shot == null
        ? null
        : CapturePick(bytes: shot, choice: CaptureChoice.screenshot);
  }
}

/// Share / open-with ingest over `receive_sharing_intent` (section 5). The
/// intent filters live in `AndroidManifest.xml`; files arrive copied to the
/// app's cache by the plugin, so reading them needs no permission.
class PluginShareIngest implements ShareIngest {
  String? _lastSignature;
  DateTime? _lastAt;

  @override
  Future<List<CapturePick>> initial() async {
    ReceiveSharingIntent.instance.reset();
    return _toPicks(await ReceiveSharingIntent.instance.getInitialMedia());
  }

  @override
  Stream<List<CapturePick>> get stream =>
      ReceiveSharingIntent.instance.getMediaStream().asyncMap((files) {
        ReceiveSharingIntent.instance.reset();
        return _toPicks(files);
      });

  Future<List<CapturePick>> _toPicks(List<SharedMediaFile> files) async {
    if (files.isEmpty) return const [];
    // Some platforms replay the launching intent onto the fresh stream
    // listener; delivering the identical file set twice would stack two
    // Review sheets, which decision 5 forbids in spirit.
    final signature = [for (final f in files) f.path].join(' ');
    final now = DateTime.now();
    if (_lastSignature == signature &&
        _lastAt != null &&
        now.difference(_lastAt!) < const Duration(seconds: 15)) {
      return const [];
    }
    _lastSignature = signature;
    _lastAt = now;
    final picks = <CapturePick>[];
    for (final file in files) {
      final choice = shareChoiceFor(file.mimeType);
      if (choice == null) continue; // text/url shares are not receipts
      try {
        picks.add(
          CapturePick(
            bytes: await File(file.path).readAsBytes(),
            choice: choice,
          ),
        );
      } catch (_) {
        // An unreadable shared file behaves like a cancelled picker.
      }
    }
    return picks;
  }
}
