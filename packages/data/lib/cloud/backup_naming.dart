// E7b §3.2 — the `.lzbak` object name is the ONLY identity a cloud
// destination has (no local manifest), so naming lives in one module and
// retention parses back exactly what it writes.

/// `localbudget-<profileSlug>-<yyyymmdd-hhmm>.lzbak`, UTC, to the minute.
final RegExp backupObjectPattern = RegExp(
  r'^(.+)-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})\.lzbak$',
);

const String _prefix = 'localbudget';

/// Lower-case ASCII slug for object names: everything outside `[a-z0-9]`
/// collapses to a single `-`, leading/trailing dashes trimmed. Empty or
/// symbol-only names fall back to `default` (a single-profile install
/// passes its display name; the slug must still be a valid filename).
String profileSlug(String profileName) {
  final collapsed = profileName
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return collapsed.isEmpty ? 'default' : collapsed;
}

/// Full remote object name for one upload. `now` is the test seam —
//  retention ordering trusts the timestamp embedded here.
String backupObjectName({required String profileName, required DateTime now}) {
  final t = now.toUtc();
  final stamp =
      '${t.year.toString().padLeft(4, '0')}'
      '${t.month.toString().padLeft(2, '0')}'
      '${t.day.toString().padLeft(2, '0')}'
      '-${t.hour.toString().padLeft(2, '0')}'
      '${t.minute.toString().padLeft(2, '0')}';
  return '$_prefix-${profileSlug(profileName)}-$stamp.lzbak';
}

/// True when a server-side listing entry is one of OUR backups — foreign
/// files in the same folder are never prune candidates (§3.2).
bool isBackupObject(String name) =>
    name.startsWith('$_prefix-') && backupObjectPattern.hasMatch(name);

/// The upload time embedded in [name], or null when it isn't ours or the
/// stamp is not a real UTC minute.
DateTime? parseBackupObjectTime(String name) {
  final m = backupObjectPattern.firstMatch(name);
  if (m == null || !name.startsWith('$_prefix-')) return null;
  final y = int.tryParse(m.group(2)!);
  final mo = int.tryParse(m.group(3)!);
  final d = int.tryParse(m.group(4)!);
  final h = int.tryParse(m.group(5)!);
  final mi = int.tryParse(m.group(6)!);
  if (y == null ||
      mo == null ||
      d == null ||
      h == null ||
      mi == null ||
      mo < 1 ||
      mo > 12 ||
      d < 1 ||
      d > 31 ||
      h > 23 ||
      mi > 59) {
    return null;
  }
  final parsed = DateTime.utc(y, mo, d, h, mi);
  // DateTime.utc normalizes overflow (Feb 31 → Mar); reject the drift.
  if (parsed.month != mo || parsed.day != d) return null;
  return parsed;
}
