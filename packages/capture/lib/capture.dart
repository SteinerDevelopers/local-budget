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

/// E2 capture pipeline — tiers 1–3 orchestration (docs/design/e2-capture.md).
///
/// Pure Dart: everything here runs (and is tested) without Flutter, plugins
/// or a device. Platform adapters (ML Kit, image_picker, platform channels)
/// implement the interfaces below in the app layer; tests use fakes.
library;

export 'src/capture_pipeline.dart';
export 'src/document_extract.dart';
export 'src/document_router.dart';
export 'src/interfaces.dart';
export 'src/llm_json.dart';
export 'src/merge.dart';
export 'src/pdf_text.dart';
