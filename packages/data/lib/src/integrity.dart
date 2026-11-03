import 'package:drift/drift.dart' show QueryRow;

import 'database.dart';

/// E5 §7 — the boot health probe, plus the WAL checkpoint that keeps
/// snapshots honest.
///
/// The app runs [check] *off the critical path* (never blocks first
/// frame) and surfaces failures as a passive Settings banner — never a
/// dialog, never a crash. Logging is the caller's job (the data layer
/// stays dependency-free); this returns a structured report.
class IntegrityReport {
  const IntegrityReport({required this.ok, required this.problems});

  static const okReport = IntegrityReport(ok: true, problems: <String>[]);

  final bool ok;

  /// Human-readable one-liners, safe to show verbatim in the banner.
  final List<String> problems;
}

class DbIntegrity {
  /// `PRAGMA integrity_check` + `PRAGMA foreign_keys` + foreign_key_check.
  /// Never throws: a database sick enough to reject a pragma answers with
  /// a problem line instead (that is the whole point of running it).
  static Future<IntegrityReport> check(AppDatabase db) async {
    final problems = <String>[];

    try {
      final rows = await db.customSelect('PRAGMA integrity_check').get();
      final verdict = rows.isEmpty ? null : rows.first.data['integrity_check'];
      if (rows.length != 1 || verdict != 'ok') {
        for (final r in rows) {
          problems.add('integrity: ${r.data.values.join(' ')}');
        }
        // SQLite stops early on serious damage; make silence impossible.
        if (rows.isEmpty) problems.add('integrity: check returned nothing');
      }
    } on Object catch (e) {
      problems.add('integrity: check failed ($e)');
    }

    try {
      // drift's generated DDL carries no FK clauses at all (its
      // .references() only types joins — verified), so `foreign_keys =
      // OFF` is the expected posture here. Flag it only when the schema
      // really declares constraints (column-inline REFERENCES included)
      // that are then left unenforced.
      final declaring = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM sqlite_master "
            "WHERE type = 'table' AND sql LIKE '%REFERENCES%'",
          )
          .get();
      final hasFks = (declaring.first.data['n'] as int) > 0;

      final fk = await db.customSelect('PRAGMA foreign_keys').get();
      final on = fk.isNotEmpty && fk.first.data['foreign_keys'] == 1;
      if (hasFks && !on) {
        // Something reopened the store through another path — orphan
        // protection is currently *off*, which the user must see.
        problems.add('foreign key enforcement is disabled');
      }

      // Bound the scan at the SQL layer: a catastrophically corrupt store
      // can hold millions of violations and `PRAGMA …` materialises all of
      // them, so prefer the table-valued form (SQLite ≥3.16) with LIMIT —
      // the row past the report cap triggers the overflow line. Older
      // SQLite without the TVF falls back to the plain pragma (bounded in
      // the report below instead).
      List<QueryRow> violations;
      try {
        violations = await db
            .customSelect('SELECT * FROM pragma_foreign_key_check LIMIT 21')
            .get();
      } on Object {
        violations = await db.customSelect('PRAGMA foreign_key_check').get();
      }
      for (final v in violations.take(20)) {
        final d = v.data;
        problems.add(
          'dangling reference: ${d['table']} row ${d['rowid']} -> '
          '${d['parent'] ?? 'missing parent'}',
        );
      }
      if (violations.length > 20) {
        problems.add('…and more violations (showing first 20)');
      }
    } on Object catch (e) {
      problems.add('foreign key check failed ($e)');
    }

    return problems.isEmpty
        ? IntegrityReport.okReport
        : IntegrityReport(ok: false, problems: problems);
  }

  /// E5 §7 — checkpoint WAL before any snapshot (export list, backup) so
  /// a restore is never missing recent commits. On rollback-journal
  /// databases this is a cheap no-op; the call stays so mobile opens that
  /// do run WAL are covered without remembering this rule at each site.
  static Future<void> walCheckpoint(AppDatabase db) =>
      db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
}
