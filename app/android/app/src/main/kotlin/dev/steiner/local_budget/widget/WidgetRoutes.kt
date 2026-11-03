package dev.steiner.local_budget.widget

import android.content.Context
import android.content.Intent
import dev.steiner.local_budget.MainActivity

/**
 * E7c §4.1 tap targets. Taps land in a different process than the live
 * Flutter engine, so the route travels two ways: as an activity extra
 * (cold start — Dart calls `takeRoute` once the engine is up) and as a
 * live channel push (warm — MainActivity forwards immediately). Whoever
 * gets there first wins; `takeRoute` clears, so no double navigation.
 */
object WidgetRoutes {
    const val EXTRA = "widget_route"

    // Cold-start mailbox; WidgetBridge.takeRoute consumes it.
    @Volatile
    var pending: String? = null

    const val REPORTS = "reports"
    const val BUDGETS = "budgets"
    const val CAPTURE = "capture"

    fun launch(context: Context, route: String) {
        pending = route
        context.startActivity(
            Intent(context, MainActivity::class.java)
                .putExtra(EXTRA, route)
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP,
                ),
        )
    }
}
