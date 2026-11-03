package dev.steiner.local_budget.widget

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.time.Duration
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.concurrent.TimeUnit

/**
 * E7c §4.3 — the day-rollover tick. state.json only changes while the app
 * runs, but *today* changes at midnight with the phone in a pocket: the
 * widgets must notice. Renders re-read the file, so this worker is three
 * cheap re-renders; a stale-month snapshot then renders as "—", never as
 * yesterday's total. Scheduled daily from the pro Application only.
 */
class WidgetRefreshWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        WidgetUpdater.refreshAll(applicationContext)
        return Result.success()
    }

    companion object {
        private const val UNIQUE = "widget-day-rollover"

        fun schedule(context: Context) {
            val now = ZonedDateTime.now(ZoneId.systemDefault())
            val nextMidnight = now.toLocalDate().plusDays(1)
                .atStartOfDay(now.zone)
            val delay = Duration.between(now, nextMidnight).toMillis()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE,
                ExistingPeriodicWorkPolicy.UPDATE,
                PeriodicWorkRequestBuilder<WidgetRefreshWorker>(1, TimeUnit.DAYS)
                    .setInitialDelay(delay, TimeUnit.MILLISECONDS)
                    .build(),
            )
        }
    }
}
