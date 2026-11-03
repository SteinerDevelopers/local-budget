package dev.steiner.local_budget.widget

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.ListView
import androidx.glance.appwidget.AppWidgetId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * E7c §4.1 — per-instance envelope picker, launched by the launcher when
 * the user drops the "Envelope left" tile (android:configure in
 * widget_envelope_info.xml). Deliberately framework-plain (ListView):
 * this runs before any Flutter engine exists and must stay up even when
 * the app process is otherwise cold.
 */
class WidgetConfigureActivity : Activity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Until the user confirms, the host must treat the add as canceled.
        widgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        val cancel = Intent().putExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            widgetId,
        )
        setResult(RESULT_CANCELED, cancel)
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        // No snapshot (or no envelopes) yet: accept "auto" now and let the
        // user long-press later — configuring must never dead-end a drop.
        val envelopes = WidgetState.read(this)?.envelopes ?: emptyList()
        if (envelopes.isEmpty()) {
            confirm(null)
            return
        }

        val labels = ArrayList<String>(envelopes.size + 1)
        labels.add("Auto — tightest envelope")
        envelopes.forEach { labels.add(it.name) }
        val pinAtDrop = WidgetPrefs.pinName(this, widgetId)
        setContentView(
            ListView(this).apply {
                adapter = ArrayAdapter(
                    this@WidgetConfigureActivity,
                    android.R.layout.simple_list_item_1,
                    labels,
                )
                val initial = envelopes.indexOfFirst { it.name == pinAtDrop } + 1
                if (initial > 0) setSelection(initial)
                setOnItemClickListener { _, _, position, _ ->
                    confirm(if (position == 0) null else envelopes[position - 1].name)
                }
            },
        )
    }

    private fun confirm(name: String?) {
        WidgetPrefs.setPin(this, widgetId, name)
        CoroutineScope(Dispatchers.Main).launch {
            EnvelopeWidget().update(this@WidgetConfigureActivity, AppWidgetId(widgetId))
        }
        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
        finish()
    }
}
