package dev.steiner.local_budget

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException

/**
 * The free flavor's read-only window onto its staged transfer snapshot
 * (design e6-monetization §3). Exported, but gated by a **signature**
 * permission: only a same-signed LocalBudget Pro can open it, and opening
 * it reveals nothing beyond bytes that snapshot already holds.
 *
 * Deliberately dumb — it never builds a backup (Dart stages the bytes via
 * TransferBridge.stage), never writes, never deletes. Serving a file you
 * cannot accidentally corrupt is the whole point of the split.
 *
 * Lives in src/free/ so the Pro build cannot contain the provider at all.
 */
class TransferProvider : ContentProvider() {

    private fun staged(): File? =
        context?.let {
            File(File(it.filesDir, "transfer"), "staged.lzb").takeIf { f -> f.exists() }
        }

    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String = "application/octet-stream"

    /** Columns (size, mtime) — the freshness line. One row or none. */
    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val file = staged() ?: return MatrixCursor(COLUMNS, 0)
        return MatrixCursor(COLUMNS, 1).apply {
            addRow(arrayOf(file.length(), file.lastModified()))
        }
    }

    /** The one content hook: the framework's default openAssetFileDescriptor
     *  and openInputStream delegate here, so overriding openFile serves the
     *  whole read surface (that's also how androidx FileProvider does it). */
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor =
        staged()?.let { ParcelFileDescriptor.open(it, ParcelFileDescriptor.MODE_READ_ONLY) }
            ?: throw FileNotFoundException("no staged snapshot")

    // Read-only surface: the write verbs exist only because the framework
    // demands them, and refuse.
    override fun insert(uri: Uri, values: ContentValues?) =
        throw UnsupportedOperationException("read-only")

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ) = throw UnsupportedOperationException("read-only")

    override fun delete(
        uri: Uri,
        selection: String?,
        selectionArgs: Array<out String>?,
    ) = throw UnsupportedOperationException("read-only")

    companion object {
        const val AUTHORITY = "dev.steiner.local_budget.transfer"
        private val COLUMNS = arrayOf("size", "mtime")
    }
}
