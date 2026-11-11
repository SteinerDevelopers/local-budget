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

/// Persistence layer. Re-exports the database, repositories and schema types;
/// core types are intentionally NOT re-exported — depend on `package:core`
/// directly for domain types.
library;

// Value is part of the DataClass copyWith contract (e.g. clearing a row's
// imageRef on undo); callers shouldn't need a direct drift dependency.
export 'package:drift/drift.dart' show Value;

// E7b own-cloud transport (naming grammar, retention, WebDAV client).
export 'cloud/cloud.dart';

export 'src/attachment_store.dart';
export 'src/backup.dart';
export 'src/backup_crypto.dart'
    show
        BackupFormatException,
        BackupPassphraseException,
        backupDefaultKdfIterations,
        backupMagic,
        backupFormatVersion,
        backupHeaderBytes;
export 'src/converters.dart';
export 'src/csv_codec.dart';
export 'src/csv_import.dart';
export 'src/database.dart';
export 'src/export_csv.dart';
export 'src/fx_service.dart';
export 'src/integrity.dart';
export 'src/ledger_repository.dart';
export 'src/ofx_import.dart';
export 'src/report_workbook.dart';
export 'src/statement_lines.dart';
export 'src/tables.dart';
export 'src/xlsx.dart';
