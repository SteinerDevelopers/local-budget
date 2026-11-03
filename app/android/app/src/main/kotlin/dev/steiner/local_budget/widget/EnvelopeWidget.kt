package dev.steiner.local_budget.widget

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.appwidget.AppWidgetId
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.provideContent

/**
 * E7c §4.1 widget #2 — "Envelope left": the pinned envelope when
 * configured ([WidgetConfigureActivity]), else the tightest one. Tap
 * opens the budgets sheet (§4.1), so the tile and its detail always
 * agree on which envelope is "the one you should look at".
 */
class EnvelopeWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val widgetId = (id as? AppWidgetId)?.appWidgetId ?: -1
        val snap = WidgetState.read(context)?.takeIf { it.freshThisMonth() }
        val pin = snap?.let { s -> WidgetPrefs.pinName(context, widgetId) }
        val pinned = snap?.let { s ->
            pin?.let { name -> s.envelopes.firstOrNull { it.name == name } }
                ?: s.envelopes.minByOrNull { e -> e.remainingMinor }
        }
        // Plain values for the composable — the snapshot itself may be null
        // and Glance content lambdas don't smart-cast.
        val currency = snap?.currency ?: ""
        val showHint = (snap?.envelopes?.size ?: 0) > 1 && pin == null
        provideContent {
            WidgetCard(actionRunCallback<OpenBudgetsAction>()) {
                if (pinned == null) {
                    EmptyBody()
                } else {
                    Title("“${pinned.name}” left")
                    Headline(
                        WidgetUi.money(pinned.remainingMinor, currency),
                        overBudget = pinned.remainingMinor < 0,
                    )
                    if (showHint) {
                        SubNote("tap to pin an envelope")
                    }
                }
            }
        }
    }
}

class EnvelopeWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = EnvelopeWidget()

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        WidgetPrefs.clearPins(context, appWidgetIds)
    }
}
