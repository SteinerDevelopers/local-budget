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

  /// Hard cap on the channel-bound bootstrap, armed only here, at the one
  /// shell call site: a wedged platform channel must never leave the
  /// notifier half-ready. If the orphaned inner future still completes,
  /// [active] flips on for later schedules.
  ///
  /// The Android 13+ permission prompt deliberately rides *outside* the
  /// cap's await (field test, Coosea SL219A / Android 14: a budget phone
  /// renders the dialog slower than any sane cap, and a user still reading
  /// it is not a reason to kill reminders for the session). A denial
  /// changes nothing else — §5 again.
  static Future<void> bootstrap() {
    if (active) return Future.value();
    return _inFlight ??= _cappedBootstrap();
  }

  static Future<void>? _inFlight;

  static Future<void> _cappedBootstrap() async {
    try {
      await _bootstrapCore().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      debugPrint('BillNotifier bootstrap timed out; staying inert');
      // Never force active=false here: the orphaned core may complete
      // after the cap and flip it on — that late success is real.
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
      // The permission prompt rides outside every await in here: it can
      // sit on screen for as long as the user likes.
      unawaited(_requestPermission());
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

  static Future<void> _requestPermission([
    FlutterSecureStorage? storage,
  ]) async {
    try {
      // Device bug (SL219A, 2026-11-05): the ask rode on *every* bootstrap,
      // so each cold start re-prompted an owner who had already answered.
      // Ask at most once per install; a later grant from system settings is
      // picked up silently, and a denial changes nothing else (§5).
      final prefs = storage ?? const FlutterSecureStorage();
      if (await prefs.read(key: _notifAskedKey) != null) return;
      final android = _plugin.resolvePlatformSpecificImplementation<
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
  }) async {
    // A boot now races the first frame (see bootstrap): a bill added in
    // that window must not silently lose its reminder. Rides the
    // in-flight bootstrap if one is running; never starts one itself.
    await _ensureReady();
    if (!active) return; // genuinely unavailable — the hint stays optional
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
