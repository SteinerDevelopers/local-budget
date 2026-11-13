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

// #35 — local bill reminders (design e3 §5). The notification is the hint;
// the Bills list is the truth. We schedule the NEXT occurrence at 09:00
// local in an inexact ±60-min window and never ask for exact-alarm
// permission — the Doze caveat ships as help text, not as a workaround.
import 'dart:async' show TimeoutException, unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Static, inert-by-default scheduling facade. The app shell calls
/// [bootstrap] once on launch ([active] flips to true); widget tests and
/// platforms without the plugin never touch a method channel.
class BillNotifier {
  BillNotifier._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// False until [bootstrap] succeeds; every method is a no-op before that.
  static bool active = false;

  /// Set by the app shell: notification taps carry the rule id payload.
  /// Assigning it also drains a cold-launch tap that arrived first
  /// ([pendingOpenRuleId]), so the handoff is safe in either order —
  /// which is what lets [bootstrap] leave the boot critical path.
  static void Function(int ruleId)? get onOpen => _onOpen;
  static set onOpen(void Function(int ruleId)? cb) {
    _onOpen = cb;
    final pending = pendingOpenRuleId;
    if (cb != null && pending != null) {
      pendingOpenRuleId = null;
      cb(pending);
    }
  }

  static void Function(int ruleId)? _onOpen;

  /// A cold-launch tap that arrived before the shell installed [onOpen];
  /// installing [onOpen] drains this.
  static int? pendingOpenRuleId;

  static const _window = Duration(minutes: 60);

  /// Escalating caps on the channel-bound bootstrap, armed only here, at
  /// the one shell call site: a wedged platform channel must never leave
  /// the notifier half-ready. One cap was tuned on sane hardware and lied
  /// about ours — field test (SL219A, 2026-11-05): a slow cold boot starves
  /// the channel past 5 s and the session kept inert reminders on the one
  /// class of device that needs them. So the cap retries instead of
  /// surrendering; schedules ride the in-flight future and fire once any
  /// attempt lands. If the orphaned inner future still completes, [active]
  /// flips on for later schedules.
  ///
  /// Bootstrapping never asks for the notification permission (F5, issue
  /// #49 — measured fresh-install ambush on the bench, 2026-11-09); the
  /// ask rides on [schedule], the user's first recurring-bill save. The
  /// field-test lesson still governs that ask: a budget phone renders the
  /// dialog slower than any sane cap (Coosea SL219A / Android 14), so it
  /// stays unawaited and a denial changes nothing else — §5 again.
  static Future<void> bootstrap() {
    if (active) return Future.value();
    return _inFlight ??= _cappedBootstrap();
  }

  static Future<void>? _inFlight;

  /// Attempt budgets: the first covers any healthy boot; the tail exists
  /// for phones whose first frames hog the isolate for tens of seconds.
  /// Ascending, and short enough that even the full ladder finishes well
  /// inside a cold start the user would notice.
  static const bootBudgets = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 40),
  ];

  static Future<void> _cappedBootstrap() async {
    try {
      for (var attempt = 0; attempt < bootBudgets.length; attempt++) {
        try {
          await _bootstrapCore().timeout(bootBudgets[attempt]);
          return;
        } on TimeoutException {
          debugPrint(
            'BillNotifier bootstrap over budget '
            '(${bootBudgets[attempt].inSeconds}s, attempt '
            '${attempt + 1}/${bootBudgets.length})',
          );
          // Never force active=false here: the orphaned core may complete
          // after the cap and flip it on — that late success is real.
        }
      }
      debugPrint('BillNotifier bootstrap exhausted budgets; staying inert');
    } finally {
      _inFlight = null;
    }
  }

  /// Wait for an *already started* bootstrap; never starts one. This is
  /// the whole schedule/cancel guard: the shell owns bootstrap, so widget
  /// tests — which never boot the shell — still never touch a method
  /// channel (their schedules stay no-ops, §5), while a bill saved during
  /// the first frames rides the in-flight future instead of losing its
  /// reminder.
  static Future<void> _ensureReady() => _inFlight ?? Future.value();

  static Future<void> _bootstrapCore() async {
    if (active) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final zone = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(zone.identifier));
      } catch (_) {
        // Unknown/ambiguous zone: UTC is honest enough for an inexact hint.
      }
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _handle,
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      // Flip on only once the tz + channel are genuinely usable — schedule
      // computes its fire time against tz.local.
      active = true;
      // The permission prompt is NOT asked here (F5, issue #49): a fresh
      // install must earn the ask first. It rides on schedule() instead —
      // the moment the user saves a recurring bill and the reminder is
      // genuinely needed. The field-test lesson stands: whenever it does
      // appear it stays unawaited, so a slow dialog never stalls a save.
      if ((launch?.didNotificationLaunchApp ?? false) && payload != null) {
        _openPayload(payload);
      }
    } catch (e, s) {
      // Missing plugin implementation (tests, desktop): stay inert.
      debugPrint('BillNotifier disabled: $e\n$s');
      active = false;
    }
  }

  static const _notifAskedKey = 'notif_asked_v1';

  /// The retry ladder can leave an orphaned core racing its replacement;
  /// a second success must not open a second permission dialog. The
  /// secure-storage marker alone does not cover the read-then-write window.
  static bool _permissionStarted = false;

  static Future<void> _requestPermission([
    FlutterSecureStorage? storage,
  ]) async {
    if (_permissionStarted) return;
    _permissionStarted = true;
    try {
      // Device bug (SL219A, 2026-11-05): the ask rode on *every* bootstrap,
      // so each cold start re-prompted an owner who had already answered.
      // Ask at most once per install; a later grant from system settings is
      // picked up silently, and a denial changes nothing else (§5).
      final prefs = storage ?? const FlutterSecureStorage();
      if (await prefs.read(key: _notifAskedKey) != null) return;
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) return;
      if (await android.areNotificationsEnabled() == true) {
        await prefs.write(key: _notifAskedKey, value: 'granted');
        return;
      }
      await android.requestNotificationsPermission();
      await prefs.write(key: _notifAskedKey, value: 'asked');
    } catch (e) {
      debugPrint('BillNotifier permission request failed: $e');
    }
  }

  static void _handle(NotificationResponse response) =>
      _openPayload(response.payload);

  static void _openPayload(String? payload) {
    final id = int.tryParse(payload ?? '');
    if (id == null) return;
    final open = onOpen;
    if (open != null) {
      open(id);
    } else {
      pendingOpenRuleId = id;
    }
  }

  /// Remind for [due] (a calendar-local date) at 09:00 ± window (§5).
  static Future<void> schedule({
    required int ruleId,
    required String name,
    required DateTime due,
    // The permission ask belongs to a user's own action (F5, #49): save,
    // paid, resume pass true. Background materialization — boot, app
    // resume — schedules silently and asks nothing; a reminder the machine
    // decided on never interrupts a person for consent.
    bool askPermission = false,
  }) async {
    // A boot now races the first frame (see bootstrap): a bill added in
    // that window must not silently lose its reminder. Rides the
    // in-flight bootstrap if one is running; never starts one itself.
    await _ensureReady();
    if (!active) return; // genuinely unavailable — the hint stays optional
    // First need for a reminder = first legitimate moment to ask (F5,
    // issue #49) — but only when a person performed the action. Once per
    // install, marker-guarded; never delays the save.
    if (askPermission) unawaited(_requestPermission());
    try {
      final fire = tz.TZDateTime(
        tz.local,
        due.year,
        due.month,
        due.day,
        9,
        30, // middle of the 08:00–10:00 inexact window
      );
      if (!fire.isAfter(tz.TZDateTime.now(tz.local))) return;
      await _plugin.zonedSchedule(
        id: ruleId,
        scheduledDate: fire,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'bills',
            'Bills',
            channelDescription:
                'A hint that a bill is due — the app always shows the truth.',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: 'Bill due',
        body: '$name · ${_dayText(due)}',
        payload: '$ruleId',
      );
    } catch (e) {
      debugPrint('BillNotifier.schedule failed: $e');
    }
  }

  static Future<void> cancel(int ruleId) async {
    // Same boot race as schedule: dropping a cancel would leave a stale
    // alarm scheduled that the user already deleted.
    await _ensureReady();
    if (!active) return;
    try {
      await _plugin.cancel(id: ruleId);
    } catch (e) {
      debugPrint('BillNotifier.cancel failed: $e');
    }
  }

  // The window is the contract (§5); the ±60 min never crosses into
  // "exact", so no SCHEDULE_EXACT_ALARM / USE_EXACT_ALARMS permission.
  static Duration get reminderWindow => _window;

  static String _dayText(DateTime d) {
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${wd[d.weekday - 1]} ${d.day} ${mo[d.month - 1]}';
  }
}
