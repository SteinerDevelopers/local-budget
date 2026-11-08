package dev.steiner.local_budget

import android.content.Context
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Native half of the E6 §3 free→paid transfer channel
 * (`dev.steiner.local_budget/transfer`). One bridge compiled into both
 * flavors; each side simply calls its half (design e6-monetization §3):
 *
 *  - `stage` (free): Dart has already built the encrypted snapshot — the
 *    same envelope as a manual backup with the compiled-in transfer
 *    passphrase. Kotlin only spools it to `filesDir/transfer/staged.lzb`
 *    for the flavor-free app's `TransferProvider` to serve. It never
 *    *generates* anything: the provider must stay trivially correct, so
 *    backup-building stays in Dart where the tests live.
 *  - `pull` / `snapshotMeta` / `freeAvailable` (pro): read the free app's
 *    provider — a signature-permission ContentProvider, so no runtime
 *    permission dialog ever appears and nothing resolves without both
 *    apps signed with the same key.
 *  - `proInstalled` (free): the Get Pro page's honest "already have it?"
 *    note, via the manifest `<queries>` entry.
 *
 * Every failure collapses to `null`/`false`: the UI hides the row or shows
 * the one §6 snackbar, never a stack trace. And no code path here touches
 * the network (decision 8).
 */
class TransferBridge(private val context: Context) {

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "freeAvailable" -> result.success(freeAvailable())
                    "proInstalled" -> result.success(proInstalled())
                    "stage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) {
                            result.error("stage", "missing bytes", null)
                        } else {
                            stage(bytes)
                            result.success(null)
                        }
                    }
                    "pull" -> result.success(pull())
                    "snapshotMeta" -> result.success(snapshotMeta())
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                // One honest failure signal; the Dart side maps it to the
                // §6 copy ("Couldn't read from the free app…").
                result.error("transfer", e.message, null)
            }
        }
    }

    /** Does a Steiner Budget transfer provider resolve on this device? (Pro
     *  asks; same-key installs are the only way it can answer true.) */
    @Suppress("DEPRECATION") // PackageManager is still the direct metadata probe
    private fun freeAvailable(): Boolean =
        context.packageManager.resolveContentProvider(AUTHORITY, 0) != null

    /** Free side only: is the paid listing installed next door? */
    private fun proInstalled(): Boolean = try {
        context.packageManager.getPackageInfo(PRO_PACKAGE, 0)
        true
    } catch (_: Exception) {
        false
    }

    /** Atomic publish: temp file + rename, so the provider never serves a
     *  half-written snapshot no matter when Pro taps "Transfer". */
    private fun stage(bytes: ByteArray) {
        val dir = File(context.filesDir, "transfer").apply { mkdirs() }
        val tmp = File(dir, "staged.tmp")
        tmp.writeBytes(bytes)
        val staged = File(dir, "staged.lzb")
        if (!tmp.renameTo(staged)) {
            // Rename across filesystems is the only failure worth handling.
            tmp.copyTo(staged, overwrite = true)
            tmp.delete()
        }
    }

    /** Pro side: spool the provider's stream into cacheDir and hand Dart
     *  the path; Dart reads it once and deletes it (see transfer.dart). */
    private fun pull(): String? {
        val uri = Uri.parse("content://$AUTHORITY/snapshot")
        return try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                val spool = File(context.cacheDir, "transfer-spool.lzb")
                spool.outputStream().use { output -> input.copyTo(output) }
                spool.absolutePath
            }
        } catch (_: Exception) {
            null // no provider, nothing staged, or refused — same answer
        }
    }

    /** Pro side: (size, mtime) for the freshness line in Manage. */
    private fun snapshotMeta(): Map<String, Long>? {
        val uri = Uri.parse("content://$AUTHORITY/snapshot")
        return try {
            context.contentResolver
                .query(uri, arrayOf("size", "mtime"), null, null, null)
                ?.use { cursor ->
                    if (!cursor.moveToFirst()) return null
                    mapOf(
                        "size" to cursor.getLong(0),
                        "mtimeMs" to cursor.getLong(1),
                    )
                }
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        const val CHANNEL = "dev.steiner.local_budget/transfer"

        /** Mirrors the authority in src/free/AndroidManifest.xml and
         *  TransferProvider; three known places, one string, grep for it. */
        const val AUTHORITY = "dev.steiner.local_budget.transfer"

        /** The paid listing's applicationId (build.gradle.kts suffix). */
        const val PRO_PACKAGE = "dev.steiner.local_budget.pro"
    }
}
