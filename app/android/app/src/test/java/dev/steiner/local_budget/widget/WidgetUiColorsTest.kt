package dev.steiner.local_budget.widget

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.colorspace.ColorSpaces
import androidx.compose.ui.graphics.toArgb
import androidx.glance.unit.FixedColorProvider
import androidx.glance.unit.ResourceColorProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The "Can't load widget" guard (Verge SL219A, 2026-11-24). Glance's Int
 * color APIs are resource-id lookups: `ColorProvider(int)` returns a
 * ResourceColorProvider and `background(Int)` takes a @ColorRes/@DrawableRes
 * id — both compile happily with a raw ARGB and then die at the launcher,
 * where `getColor(0xFF10131A)` throws and the whole tile fails to inflate.
 * Emulators swallowed it; a real launcher does not. These asserts pin the
 * widget palette to fixed (non-resource-backed) providers.
 */
class WidgetUiColorsTest {
    @Test
    fun textPaletteIsNotResourceBacked() {
        listOf(WidgetUi.TextPrimary, WidgetUi.TextMuted, WidgetUi.TextOver)
            .forEach {
                assertTrue(
                    "ARGB literal routed through resource lookup — launcher " +
                        "will throw getColor(); pass a compose Color instead",
                    it !is ResourceColorProvider,
                )
            }
    }

    @Test
    fun inkIsFixedColorNotResId() {
        // WidgetCard backgrounds must pass a compose Color; the Int overload
        // of background() is the resource-id trap.
        assertEquals(Color(0xFF10131A), WidgetUi.Ink)
    }

    @Test
    fun paletteIsPackedAsSrgbNotRawBits() {
        // Trap #2 (Verge, same evening): a ULong literal (0xFF10131Au) binds
        // to `value class Color(val value: ULong)`'s raw packed ctor, not to
        // the ARGB factory. Its blue byte lands in the 6-bit colorSpace slot
        // (value and 0x3f) and every downstream getColorSpace()/toArgb() call
        // throws ArrayIndexOutOfBoundsException — in-JVM, no launcher needed.
        // toArgb() here is the canary: it only survives if the palette went
        // through the documented Color(Long)/Color(Int) factory.
        assertEquals(0xFF10131A.toInt(), WidgetUi.Ink.toArgb())
        assertEquals(ColorSpaces.Srgb, WidgetUi.Ink.colorSpace)
        // (ColorProvider's invoke is @Composable-only; unwrap the fixed impl.)
        assertEquals(0xFFFFFFFF.toInt(), (WidgetUi.TextPrimary as FixedColorProvider).color.toArgb())
        assertEquals(0xFF9AA3B2.toInt(), (WidgetUi.TextMuted as FixedColorProvider).color.toArgb())
        assertEquals(0xFFFF6B6B.toInt(), (WidgetUi.TextOver as FixedColorProvider).color.toArgb())
    }
}
