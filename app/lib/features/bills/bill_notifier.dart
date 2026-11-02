// #35 — local bill reminders (design e3 §5). The notification is the hint;
// the Bills list is the truth. We schedule the NEXT occurrence at 09:00
// local in an inexact ±60-min window and never ask for exact-alarm
// permission — the Doze caveat ships as help text, not as a workaround.
import 'dart:async' show TimeoutException;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
  static void Function(int ruleId)? onOpen;

  /// A cold-launch tap that arrived before the shell installed [onOpen];
  /// the shell drains this after its first frame.
  static int? pendingOpenRuleId;

  static const _window = Duration(minutes: 60);

  /// Hard cap on the whole bootstrap: a wedged platform channel or an
  /// untappable runtime-permission dialog (headless emulators, background
  /// launches) must never hold `main()` before the first frame — the hint
  /// stays optional, the Due rows stay the truth (§5). If the orphaned
  /// inner future still completes, [active] flips on for later schedules.
  static Future<void> bootstrap() async {
    if (active) return;
    try {
      await _bootstrap().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      debugPrint('BillNotifier bootstrap timed out; staying inert');
      active = false;
    }
  }

  static Future<void> _bootstrap() async {
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
      // Android 13+ runtime permission; a denial changes nothing else —
      // the in-app Due rows stay correct (§5).
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      active = true;
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if ((launch?.didNotificationLaunchApp ?? false) && payload != null) {
        _openPayload(payload);
      }
    } catch (e, s) {
      // Missing plugin implementation (tests, desktop): stay inert.
      debugPrint('BillNotifier disabled: $e\n$s');
      active = false;
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
  }) async {
    if (!active) return;
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
