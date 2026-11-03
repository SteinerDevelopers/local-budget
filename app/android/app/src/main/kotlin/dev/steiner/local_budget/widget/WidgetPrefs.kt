package dev.steiner.local_budget.widget

import android.content.Context

/**
 * E7c §4.1 — the envelope widget's per-instance pin: which envelope this
 * tile shows, chosen at pin time by [WidgetConfigureActivity]. Keyed by
 * widget id; pinned by NAME (position would drift with spending, §4.1's
 * "that envelope" promise survives re-sorts). A vanished name falls back
 * to the tightest envelope — the tile never goes blank over a rename.
 */
object WidgetPrefs {
    private const val PREFS = "widget_prefs"

    fun pinName(context: Context, widgetId: Int): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString("pin_$widgetId", null)

    fun setPin(context: Context, widgetId: Int, name: String?) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .apply {
                if (name == null) remove("pin_$widgetId")
                else putString("pin_$widgetId", name)
            }
            .apply()
    }

    fun clearPins(context: Context, widgetIds: IntArray) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .apply { widgetIds.forEach { remove("pin_$it") } }
            .apply()
    }
}
