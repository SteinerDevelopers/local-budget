package dev.steiner.local_budget.widget

import android.content.Context
import androidx.glance.appwidget.updateAll

/**
 * E7c §4.3 — the single refresh fan-out. Called after every snapshot
 * publish (bridge) and by the day-rollover tick (WorkManager); re-renders
 * read state.json again, so "refresh" costs nothing but three file reads.
 */
object WidgetUpdater {
    suspend fun refreshAll(context: Context) {
        SpendWidget().updateAll(context)
        EnvelopeWidget().updateAll(context)
        QuickScanWidget().updateAll(context)
    }
}
