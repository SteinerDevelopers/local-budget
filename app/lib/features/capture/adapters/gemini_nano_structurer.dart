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

import 'dart:async';

import 'package:capture/capture.dart';
import 'package:core/core.dart';
import 'package:flutter/services.dart';

/// Tier-3 structurer backed by Gemini Nano (ML Kit GenAI via AICore).
///
/// The official `google_mlkit_genai_prompt` package stubs inference natively,
/// so the app talks to `com.google.mlkit:genai-prompt` through its own thin
/// methods on the `localbudget/capture` channel (as the feasibility doc
/// prescribes). Only two questions ever cross: is the feature available, and
/// what does the model say about this image.
///
/// Availability is probed once at startup, fire-and-forget: devices without
/// AICore answer `false` (or time out), the pipeline skips Tier 3, and the
/// capture flow is byte-for-byte the E1 behaviour. We never trigger a model
/// download - it is multi-GB, and decision 10 forbids the consent UI that
/// would be required to ask; an already-installed feature is used, end of
/// story. No UI ever mentions AI: fills arrive at `FieldConfidence.low` and
/// surface only as the amber review outlines users already know.
class GeminiNanoStructurer {
  GeminiNanoStructurer() {
    unawaited(_probe());
  }

  static const MethodChannel _channel = MethodChannel('localbudget/capture');

  /// Status round-trip budget. A hung AICore binding must never delay a
  /// capture; "unknown" is "unavailable".
  static const Duration _probeBudget = Duration(seconds: 8);
  static const Duration _inferenceBudget = Duration(seconds: 25);

  bool _available = false;

  Future<void> _probe() async {
    try {
      final ok = await _channel
          .invokeMethod<bool>('nanoStatus')
          .timeout(_probeBudget);
      _available = ok ?? false;
    } on Object {
      _available = false;
    }
  }

  /// A structurer view bound to [currency] - the app currency is runtime
  /// mutable, so the pipeline hands one of these per capture.
  LlmStructurer forCurrency(Currency currency) => _Bound(this, currency);
}

class _Bound implements LlmStructurer {
  const _Bound(this._owner, this._currency);

  final GeminiNanoStructurer _owner;
  final Currency _currency;

  @override
  bool isAvailable() => _owner._available;

  @override
  Future<ReceiptDraft?> structure(
    Uint8List imageBytes,
    List<String> ocrLines,
  ) async {
    if (!isAvailable()) return null;
    try {
      final raw = await GeminiNanoStructurer._channel
          .invokeMethod<String>('nanoPrompt', {
            'text': structurerPrompt(ocrLines),
            // ImagePart accepts encoded bytes natively; no decode round-trip.
            // Empty means text-only (the pipeline passes Uint8List(0) when a
            // PDF gave up its lines but has no renderable image).
            if (imageBytes.isNotEmpty) 'image': imageBytes,
          })
          .timeout(GeminiNanoStructurer._inferenceBudget);
      if (raw == null) return null;
      return parseStructurerJson(raw, currency: _currency);
    } on Object {
      return null;
    }
  }
}
