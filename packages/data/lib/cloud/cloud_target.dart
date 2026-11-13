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

/// The surface a cloud backup needs from a transport (§3.1 table):
/// WebDAV ships in E7b, the Drive provider follows the same shape. The
/// app layer codes against this so widget tests fake it in-memory.
import 'dart:typed_data';

import 'retention.dart';

abstract interface class CloudTarget {
  Future<void> ensureCollection(String relPath);
  Future<List<CloudObject>> list(String relPath);
  Future<void> put(String relPath, Uint8List bytes);
  Future<Uint8List> get(String relPath);
  Future<void> delete(String relPath);
}
