package dev.steiner.local_budget.widget

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.provideContent

/**
 * E7c §4.1 widget #3 — "Quick scan": no data at all, purely an entry
 * point. Tap opens the capture-source sheet (camera / gallery / file),
 * the shortest path from pocket to parsed receipt.
 */
class QuickScanWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            WidgetCard(actionRunCallback<OpenCaptureAction>()) {
                Title("Receipts")
                Headline("Scan one")
                SubNote("photo · gallery · file")
            }
        }
    }
}

class QuickScanWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = QuickScanWidget()
}
