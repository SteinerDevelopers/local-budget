/// Persistence layer. Re-exports the database, repositories and schema types;
/// core types are intentionally NOT re-exported — depend on `package:core`
/// directly for domain types.
library;

// Value is part of the DataClass copyWith contract (e.g. clearing a row's
// imageRef on undo); callers shouldn't need a direct drift dependency.
export 'package:drift/drift.dart' show Value;

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
export 'src/database.dart';
export 'src/export_csv.dart';
export 'src/ledger_repository.dart';
export 'src/tables.dart';
