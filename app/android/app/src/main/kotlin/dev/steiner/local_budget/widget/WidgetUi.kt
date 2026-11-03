package dev.steiner.local_budget.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.Action
import androidx.glance.action.ActionParameters
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

/**
 * E7c §4.1 — shared chrome for the trio. One dark card, one type scale;
 * the widgets differ only in content. Everything here renders from the
 * parsed snapshot, never from the ledger (§4.2's contract).
 */
internal object WidgetUi {
    val InkDark: Int = 0xFF10131A.toInt()
    val TextPrimary = ColorProvider(0xFFFFFFFF.toInt())
    val TextMuted = ColorProvider(0xFF9AA3B2.toInt())
    val TextOver = ColorProvider(0xFFFF6B6B.toInt())

    fun money(minor: Long, currencyCode: String): String = try {
        val f = NumberFormat.getCurrencyInstance(Locale.getDefault())
        f.currency = Currency.getInstance(currencyCode)
        f.format(minor / 100.0)
    } catch (_: Throwable) {
        // Unknown code (shouldn't happen — core pins the set): plain number.
        if (minor % 100L == 0L) minor.div(100).toString()
        else "%.2f".format(minor / 100.0)
    }
}

/**
 * Tap routes are compiled callbacks — widgets serialize the *class*, so
 * these must stay concrete classes with a no-arg constructor (§4.1).
 */
internal class OpenReportsAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) = WidgetRoutes.launch(context, WidgetRoutes.REPORTS)
}

internal class OpenBudgetsAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) = WidgetRoutes.launch(context, WidgetRoutes.BUDGETS)
}

internal class OpenCaptureAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) = WidgetRoutes.launch(context, WidgetRoutes.CAPTURE)
}

@Composable
internal fun WidgetCard(tap: Action, content: @Composable () -> Unit) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(WidgetUi.InkDark)
            .padding(12.dp)
            .clickable(tap),
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.Start,
    ) {
        content()
    }
}

@Composable
internal fun Title(text: String) {
    Text(text, style = TextStyle(color = WidgetUi.TextMuted, fontSize = 12.sp))
}

@Composable
internal fun Headline(text: String, overBudget: Boolean = false) {
    Text(
        text,
        style = TextStyle(
            color = if (overBudget) WidgetUi.TextOver else WidgetUi.TextPrimary,
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
        ),
    )
}

@Composable
internal fun SubNote(text: String) {
    Text(text, style = TextStyle(color = WidgetUi.TextMuted, fontSize = 12.sp))
}

/** "No data yet" is honest; a stale month's numbers would be a lie. */
@Composable
internal fun EmptyBody() {
    Title("LocalBudget")
    Headline("—")
    SubNote("Open the app to refresh")
}
