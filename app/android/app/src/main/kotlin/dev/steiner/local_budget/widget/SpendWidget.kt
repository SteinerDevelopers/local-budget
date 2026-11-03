package dev.steiner.local_budget.widget

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.provideContent

/**
 * E7c §4.1 widget #1 — "Spent this month": whole-month budget-counted
 * spend (unbudgeted categories included), with the budget frame as a
 * hint line when one exists. Tap → Reports (§4.1).
 */
class SpendWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snap = WidgetState.read(context)
            ?.takeIf { it.freshThisMonth() }
        provideContent {
            WidgetCard(actionRunCallback<OpenReportsAction>()) {
                if (snap == null) {
                    EmptyBody()
                } else {
                    Title("Spent this month")
                    Headline(
                        WidgetUi.money(snap.spentMinor, snap.currency),
                        overBudget = snap.budgetLimitMinor > 0 &&
                            snap.budgetSpentMinor > snap.budgetLimitMinor,
                    )
                    if (snap.budgetLimitMinor > 0) {
                        SubNote(
                            "of " + WidgetUi.money(
                                snap.budgetLimitMinor,
                                snap.currency,
                            ) + " budgeted",
                        )
                    }
                }
            }
        }
    }
}

class SpendWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = SpendWidget()
}
