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

// E7b §3.2 — retention is a pure function over a server listing: keep the
// newest 12, collapse everything older to the newest per UTC calendar day.
// Pruning runs AFTER a successful upload (call-site contract, asserted in
// the client test), and never touches files that are not ours.
import 'backup_naming.dart';

/// One entry of a destination listing. [path] is what to GET/DELETE,
/// [name] the last path segment the naming grammar reads.
class CloudObject {
  const CloudObject({
    required this.name,
    required this.path,
    required this.size,
    required this.modified,
  });

  final String name;
  final String path;
  final int size;
  final DateTime modified;

  @override
  String toString() => 'CloudObject($name, $size B, $modified)';
}

class RetentionPlan {
  const RetentionPlan({required this.keep, required this.delete});

  final List<CloudObject> keep;
  final List<CloudObject> delete;

  @override
  String toString() =>
      'RetentionPlan(keep: ${keep.length}, del: ${delete.length})';
}

/// Timestamp of a listing entry: our own name grammar wins, the server's
/// LastModified is the fallback (foreign files, pre-grammar strays).
DateTime _stampOf(CloudObject o) => parseBackupObjectTime(o.name) ?? o.modified;

/// §3.2 retention over [all]. Only names matching the backup grammar are
/// ever candidates; foreign objects always land in `keep` untouched.
RetentionPlan prunePlan(List<CloudObject> all, {int newestToKeep = 12}) {
  final ours = all.where((o) => isBackupObject(o.name)).toList()
    ..sort((a, b) {
      final byTime = _stampOf(b).compareTo(_stampOf(a));
      return byTime != 0 ? byTime : b.name.compareTo(a.name);
    });
  final foreign = all.where((o) => !isBackupObject(o.name));

  final keep = <CloudObject>[];
  final delete = <CloudObject>[];
  keep.addAll(ours.take(newestToKeep));

  // Older-than-window: at most one survivor per UTC calendar day — a day
  // already represented inside the window gets no second slot.
  int dayKey(DateTime t) => t.year * 10000 + t.month * 100 + t.day;
  final seenDays = {for (final o in keep) dayKey(_stampOf(o))};
  for (final o in ours.skip(newestToKeep)) {
    if (seenDays.add(dayKey(_stampOf(o)))) {
      keep.add(o);
    } else {
      delete.add(o);
    }
  }
  return RetentionPlan(keep: [...keep, ...foreign], delete: delete);
}
