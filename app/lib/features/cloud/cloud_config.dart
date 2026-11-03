// E7b §3.1 — destination records. Everything here is non-secret (label,
// endpoint, user); the password goes through CloudSecretStore, so this
// JSON may sit in the app's support dir without leaking anything usable.
import 'dart:convert';
import 'dart:io';

class CloudDestination {
  const CloudDestination({
    required this.id,
    required this.label,
    required this.url,
    required this.user,
    required this.folder,
    this.autoBackup = false,
    this.autoFails = 0,
  });

  final String id;
  final String label;
  final String url;
  final String user;

  /// Remote folder holding this destination's .lzbak objects (§3.2).
  final String folder;

  /// §3.3 — "Back up automatically" toggle (the enrolled backup key is a
  /// precondition; scheduling happens in auto_backup.dart).
  final bool autoBackup;

  /// Consecutive auto-backup failures; the quiet badge lights at 3 (§3.3).
  final int autoFails;

  CloudDestination copyWith({
    String? label,
    String? url,
    String? user,
    String? folder,
    bool? autoBackup,
    int? autoFails,
  }) => CloudDestination(
    id: id,
    label: label ?? this.label,
    url: url ?? this.url,
    user: user ?? this.user,
    folder: folder ?? this.folder,
    autoBackup: autoBackup ?? this.autoBackup,
    autoFails: autoFails ?? this.autoFails,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'url': url,
    'user': user,
    'folder': folder,
    'autoBackup': autoBackup,
    'autoFails': autoFails,
  };

  static CloudDestination fromJson(Map<String, Object?> j) {
    String s(String k) {
      final v = j[k];
      if (v is! String) throw FormatException('cloud destination: $k');
      return v;
    }

    return CloudDestination(
      id: s('id'),
      label: s('label'),
      url: s('url'),
      user: s('user'),
      folder: j['folder'] is String ? j['folder']! as String : 'localbudget',
      autoBackup: j['autoBackup'] == true,
      autoFails: j['autoFails'] is int ? j['autoFails']! as int : 0,
    );
  }
}

/// JSON list in the app support dir (§3.1: "no local manifest" applies to
/// versions — destinations are app configuration, not backup state).
class CloudConfigStore {
  CloudConfigStore(this._file);

  final File _file;

  List<CloudDestination> load() {
    if (!_file.existsSync()) return const [];
    try {
      final raw = jsonDecode(utf8.decode(_file.readAsBytesSync()));
      if (raw is! List) return const [];
      return [
        for (final e in raw)
          if (e is Map<String, Object?>) CloudDestination.fromJson(e),
      ];
    } on FormatException {
      // A corrupt config must not brick the whole Manage screen.
      return const [];
    }
  }

  Future<void> save(List<CloudDestination> destinations) async {
    await _file.parent.create(recursive: true);
    final enc = const JsonEncoder.withIndent('  ');
    await _file.writeAsString(
      enc.convert([for (final d in destinations) d.toJson()]),
    );
  }
}
