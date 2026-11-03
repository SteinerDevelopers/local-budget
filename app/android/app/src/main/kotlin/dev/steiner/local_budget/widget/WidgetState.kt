package dev.steiner.local_budget.widget

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.time.YearMonth

/**
 * E7c §4.2 — the Kotlin half of the widget snapshot contract. The Dart
 * writer (`widget_snapshot_service.dart`) owns the bytes; this file owns
 * the read. The key allow-list is asserted on BOTH sides: a payload that
 * grew a key (or lost the version stamp) is rejected here exactly like
 * `decodeWidgetSnapshot` rejects it in Dart — privacy §4.4 is a property
 * of the format, not of the renderer.
 *
 * Mirrors `packages/core/lib/src/widget_state.dart`; the parity test
 * (`WidgetStateTest`) parses the committed Dart fixture from this parser.
 */
data class Envelope(val name: String, val remainingMinor: Long)

data class WidgetSnapshot(
    val updatedAtMs: Long,
    val yearMonth: String,
    val currency: String,
    val spentMinor: Long,
    val budgetSpentMinor: Long,
    val budgetLimitMinor: Long,
    val envelopes: List<Envelope>,
) {
    /** Bar fraction against the budget frame; null = no frame to draw. */
    val budgetFraction: Float?
        get() = if (budgetLimitMinor > 0)
            (budgetSpentMinor.toFloat() / budgetLimitMinor).coerceIn(0f, 1f)
        else null
}

object WidgetState {
    /** §4.4 allow-list — keep byte-for-byte in step with the Dart list. */
    val KEYS: Set<String> = setOf(
        "v", "updatedAtMs", "yearMonth", "currency",
        "spentMinor", "budgetSpentMinor", "budgetLimitMinor", "envelopes",
    )
    val ENVELOPE_KEYS: Set<String> = setOf("name", "remainingMinor")
    const val SCHEMA_V = 1

    /** The one path the trio reads; the bridge is the one path that writes. */
    fun file(context: Context): File =
        File(File(context.filesDir, "widget"), "state.json")

    fun read(context: Context): WidgetSnapshot? = try {
        parse(file(context).readText())
    } catch (_: Throwable) {
        null // no file yet (fresh install, pre-first-publish)
    }

    fun parse(text: String): WidgetSnapshot? = try {
        val o = JSONObject(text)
        // Strict set equality: an unknown key is a contract break, not a
        // detail to ignore — a future writer must not leak through here.
        if (o.keys().asSequence().toSet() != KEYS) return null
        if (o.optInt("v", -1) != SCHEMA_V) return null
        val arr = o.getJSONArray("envelopes")
        val env = ArrayList<Envelope>(arr.length())
        for (i in 0 until arr.length()) {
            val e = arr.getJSONObject(i)
            if (e.keys().asSequence().toSet() != ENVELOPE_KEYS) return null
            env.add(Envelope(e.getString("name"), e.getLong("remainingMinor")))
        }
        WidgetSnapshot(
            updatedAtMs = o.getLong("updatedAtMs"),
            yearMonth = o.getString("yearMonth"),
            currency = o.getString("currency"),
            spentMinor = o.getLong("spentMinor"),
            budgetSpentMinor = o.getLong("budgetSpentMinor"),
            budgetLimitMinor = o.getLong("budgetLimitMinor"),
            envelopes = env,
        )
    } catch (_: Throwable) {
        null
    }
}

/** YearMonth.toString() is ISO "2026-11" — same string Dart writes. */
fun currentYearMonth(): String = YearMonth.now().toString()

/** A snapshot from last month shows as empty, never as stale numbers. */
fun WidgetSnapshot.freshThisMonth(): Boolean = yearMonth == currentYearMonth()
