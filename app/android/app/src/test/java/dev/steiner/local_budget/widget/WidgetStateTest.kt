package dev.steiner.local_budget.widget

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * E7c §4.2 parity guard: the committed Dart codec fixture — golden for
 * `decodeWidgetSnapshot` in packages/core — must parse here into exactly
 * the same aggregates. If either side's contract drifts, one of the two
 * suites goes red with this same file as the witness.
 */
class WidgetStateTest {
    private fun fixture(): String {
        // Gradle unit tests run with the module dir as CWD; walk up to the
        // repo root instead of hardcoding a depth that refactors break.
        val root = generateSequence(File("").absoluteFile) { it.parentFile }
            .first { File(it, "packages/core/test/fixtures/widget_state.json").exists() }
        return File(root, "packages/core/test/fixtures/widget_state.json")
            .readText(Charsets.UTF_8)
    }

    @Test
    fun dartFixtureParsesToIdenticalAggregates() {
        val snap = WidgetState.parse(fixture())
        checkNotNull(snap)
        assertEquals(1793692800000L, snap.updatedAtMs)
        assertEquals("2026-11", snap.yearMonth)
        assertEquals("USD", snap.currency)
        assertEquals(41275L, snap.spentMinor)
        assertEquals(38900L, snap.budgetSpentMinor)
        assertEquals(90000L, snap.budgetLimitMinor)
        // Wire order is the Dart sort (tightest first) — preserved as-is.
        assertEquals(
            listOf(Envelope("Groceries", 12100L), Envelope("Fun", -800L)),
            snap.envelopes,
        )
        assertEquals(38900f / 90000f, snap.budgetFraction!!, 1e-6f)
    }

    @Test
    fun unknownKeyIsRejectedNotIgnored() {
        val leaked = fixture().replaceFirst(
            "\"currency\":\"USD\"",
            "\"currency\":\"USD\",\"memo\":\"kid's school\"",
        )
        assertNull(WidgetState.parse(leaked))
    }

    @Test
    fun wrongSchemaVersionIsRejected() {
        assertNull(WidgetState.parse(fixture().replaceFirst("\"v\":1", "\"v\":2")))
    }

    @Test
    fun envelopeKeyDriftIsRejected() {
        val leaked = fixture().replaceFirst(
            "\"remainingMinor\":12100",
            "\"remainingMinor\":12100,\"txCount\":34",
        )
        assertNull(WidgetState.parse(leaked))
    }

    @Test
    fun missingKeyIsRejected() {
        assertNull(WidgetState.parse(fixture().replaceFirst("\"currency\":\"USD\",", "")))
    }

    @Test
    fun garbageIsRejected() {
        assertNull(WidgetState.parse(""))
        assertNull(WidgetState.parse("{"))
        assertNull(WidgetState.parse("[]"))
    }
}
