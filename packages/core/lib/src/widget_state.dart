// E7c §4.2 — the widget snapshot contract, one schema both sides compile
// against. Dart writes this JSON to `filesDir/widget/state.json`; Kotlin
// reads that file and *nothing else* (the E6 transfer-channel discipline:
// widget code never opens the DB and nothing passes through Dart at render
// time). The privacy rule is schema-enforced: §4.4 forbids transaction
// rows, merchant names and paths, and `encodeWidgetSnapshot` only ever
// emits the keys in [widgetSnapshotKeys] — the Dart and Kotlin parity
// tests both run the same committed fixture through it.
//
// Keep this file pure Dart + dart:convert: the Kotlin side parses these
// key names directly (org.json), so renames here are contract breaks the
// parity tests must catch.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The complete key allow-list (§4.4): everything outside it is a schema
/// violation, whether produced by a bug or by a future careless addition.
const List<String> widgetSnapshotKeys = [
  'v', // schema version, [kWidgetSnapshotSchemaV]
  'updatedAtMs', // epoch ms of the write, drives the stale marker
  'yearMonth', // 'YYYY-MM' the totals belong to; day-rollover guard
  'currency', // ISO 4217 base code, for formatting on the Kotlin side
  'spentMinor', // whole-month spend (all categories, refunds folded)
  'budgetSpentMinor', // spend counted by budget envelopes
  'budgetLimitMinor', // summed effective limits; 0 = no target set
  'envelopes', // per-envelope rows, see [widgetEnvelopeKeys]
];

/// Allow-list for one entry of `envelopes`. Envelope names are user-owned
/// labels the Envelope widget shows by design (§4.1) — categories, not
/// merchants; no ids cross the boundary, the widget matches by name.
const List<String> widgetEnvelopeKeys = [
  'name',
  'remainingMinor',
];

const int kWidgetSnapshotSchemaV = 1;

/// The aggregates the three Glance widgets render (§4.1). Plain fields —
/// construction validates nothing except the schema version, matching the
/// package's "data classes, no policy" style; the writer computes, the
/// widgets display.
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.updatedAtMs,
    required this.yearMonth,
    required this.currency,
    required this.spentMinor,
    required this.budgetSpentMinor,
    required this.budgetLimitMinor,
    required this.envelopes,
  });

  final int updatedAtMs;
  final String yearMonth;
  final String currency;
  final int spentMinor;

  /// Spend *counted toward budgets* — the Envelope widget's own frame;
  /// kept apart from [spentMinor] so the spend widget can show totals
  /// honestly even with unbudgeted categories around.
  final int budgetSpentMinor;
  final int budgetLimitMinor;

  /// Per-envelope remaining, sorted remaining-asc (tightest first) by the
  /// writer; the Envelope widget picks its configured name from here.
  final List<WidgetEnvelope> envelopes;

  factory WidgetSnapshot.fromJson(Map<String, Object?> j) => WidgetSnapshot(
        updatedAtMs: j['updatedAtMs']! as int,
        yearMonth: j['yearMonth']! as String,
        currency: j['currency']! as String,
        spentMinor: j['spentMinor']! as int,
        budgetSpentMinor: j['budgetSpentMinor']! as int,
        budgetLimitMinor: j['budgetLimitMinor']! as int,
        envelopes: [
          for (final e in (j['envelopes']! as List))
            WidgetEnvelope.fromJson(e! as Map<String, Object?>),
        ],
      );

  Map<String, Object?> toJson() => {
        'v': kWidgetSnapshotSchemaV,
        'updatedAtMs': updatedAtMs,
        'yearMonth': yearMonth,
        'currency': currency,
        'spentMinor': spentMinor,
        'budgetSpentMinor': budgetSpentMinor,
        'budgetLimitMinor': budgetLimitMinor,
        'envelopes': [for (final e in envelopes) e.toJson()],
      };
}

/// One envelope's line in the snapshot (§4.1 "Envelope left": configured
/// per widget instance by name at pin time).
class WidgetEnvelope {
  const WidgetEnvelope({required this.name, required this.remainingMinor});

  final String name;
  final int remainingMinor;

  factory WidgetEnvelope.fromJson(Map<String, Object?> j) => WidgetEnvelope(
        name: j['name']! as String,
        remainingMinor: j['remainingMinor']! as int,
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'remainingMinor': remainingMinor,
      };
}

/// Serializes [s] under the allow-list: an unknown or missing key throws
/// instead of shipping a snapshot Kotlin can't contract-match. The byte
/// order is insertion order of [toJson] — stable, so the parity fixture is
/// a golden string, not just a golden object.
Uint8List encodeWidgetSnapshot(WidgetSnapshot s) {
  final j = s.toJson();
  final extra = j.keys.toSet().difference(widgetSnapshotKeys.toSet());
  final missing = widgetSnapshotKeys.toSet().difference(j.keys.toSet());
  if (extra.isNotEmpty || missing.isNotEmpty) {
    throw StateError(
      'widget snapshot schema drift: extra=$extra missing=$missing',
    );
  }
  return utf8.encode(jsonEncode(j)) as Uint8List;
}

/// Parses a snapshot, rejecting any document with keys outside the
/// allow-list (§4.4 — the Kotlin reader applies the same rule; malformed or
/// over-privileged files make the widgets show the stale marker, never
/// partial guesses).
WidgetSnapshot decodeWidgetSnapshot(Uint8List bytes) {
  final j = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
  final extra = j.keys.toSet().difference(widgetSnapshotKeys.toSet());
  if (extra.isNotEmpty) {
    throw FormatException('widget snapshot has unknown keys: $extra');
  }
  final v = j['v'];
  if (v != kWidgetSnapshotSchemaV) {
    throw FormatException('unsupported widget snapshot schema version: $v');
  }
  return WidgetSnapshot.fromJson(j);
}
