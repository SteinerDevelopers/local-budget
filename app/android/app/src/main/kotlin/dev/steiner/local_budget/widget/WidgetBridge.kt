package dev.steiner.local_budget.widget

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * E7c §4.2 — the only door between Dart and widget-land. Dart sends the
 * finished snapshot JSON (it never touches the filesystem); this writes
 * it atomically into `filesDir/widget/state.json` and refreshes the trio.
 * Kotlin never computes an aggregate, Dart never writes a file: the seam
 * is exactly one string in, one file out.
 *
 * Cold taps are the second duty: [pushRoute] forwards a warm tap straight
 * into Dart; a cold one waits in [WidgetRoutes.pending] for `takeRoute`.
 */
class WidgetBridge(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val appContext = context.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL).apply {
        setMethodCallHandler(this@WidgetBridge)
    }
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "publish" -> {
                val json = call.argument<String>("json")
                val ok = json != null && json.isNotBlank() && writeAtomic(json)
                if (ok) {
                    // Refresh is fire-and-forget: a dead widget host must
                    // not fail the publish Dart is awaiting.
                    CoroutineScope(Dispatchers.Main).launch {
                        WidgetUpdater.refreshAll(appContext)
                    }
                }
                result.success(ok)
            }
            "takeRoute" -> result.success(
                WidgetRoutes.pending.also { WidgetRoutes.pending = null },
            )
            else -> result.notImplemented()
        }
    }

    /** Warm tap while the engine lives: skip the mailbox, navigate now. */
    fun pushRoute(route: String) {
        WidgetRoutes.pending = route
        if (Looper.myLooper() == Looper.getMainLooper()) {
            channel.invokeMethod("route", route)
        } else {
            mainHandler.post { channel.invokeMethod("route", route) }
        }
    }

    /** tmp + ATOMIC_MOVE — a widget render mid-write must never see half
     * a JSON document (same discipline as TransferBridge's staging). */
    private fun writeAtomic(json: String): Boolean = try {
        val target = WidgetState.file(appContext)
        val dir = target.parentFile ?: return false
        if (!dir.exists() && !dir.mkdirs()) return false
        val tmp = File(dir, "state.json.tmp")
        tmp.writeText(json)
        Files.move(tmp.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE)
        true
    } catch (_: Throwable) {
        false
    }

    companion object {
        const val CHANNEL = "dev.steiner.local_budget/widget"
    }
}
