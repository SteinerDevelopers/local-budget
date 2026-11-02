package dev.steiner.local_budget

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.graphics.pdf.PdfRenderer
import com.google.common.util.concurrent.FutureCallback
import com.google.common.util.concurrent.Futures
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.GenerateContentRequest
import com.google.mlkit.genai.prompt.GenerateContentResponse
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.ImagePart
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.java.GenerativeModelFutures
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Native half of the capture intake (issue #28, design e2-capture §5).
 * Surfaces, none of them a runtime permission:
 *
 *  - `openDocument`: SAF ACTION_OPEN_DOCUMENT accepting image and
 *    application/pdf MIME types; the picked content:// stream is read into
 *    bytes here, so Dart never touches a storage permission.
 *  - `latestScreenshot`: an opportunistic MediaStore probe. Without
 *    READ_MEDIA_* the platform yields nothing (Android 13+) or throws
 *    SecurityException (older APIs); both collapse to `null`, the app hides
 *    the Recent-screenshot row and *never prompts* (§2.1 escape hatch).
 *  - `renderPdfFirstPage`: page 1 rasterized to PNG by the platform
 *    PdfRenderer — no pdfium to bundle, no native asset to compile, parsing
 *    stays on device (decision 8).
 *  - `nanoStatus` / `nanoPrompt`: feature detection and fill-only inference
 *    for Gemini Nano via ML Kit GenAI (issue #29) — see the nano section
 *    below for why this is a platform channel and never a download.
 *
 * Shares (ACTION_SEND / SEND_MULTIPLE) arrive through the manifest intent
 * filters and are handled entirely in Dart by receive_sharing_intent.
 */
class MainActivity : FlutterActivity() {

    /** One SAF dialog at a time; its reply waits on the activity callback. */
    private var pendingReply: MethodChannel.Result? = null

    /** Lazily bound Gemini Nano handle; callbacks reply off the main thread,
     *  which MethodChannel.Result explicitly allows. */
    private var nanoModel: GenerativeModelFutures? = null
    private val nanoExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openDocument" -> {
                        if (pendingReply != null) {
                            result.error("busy", "A document pick is already open", null)
                        } else {
                            val pick = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "*/*"
                                putExtra(
                                    Intent.EXTRA_MIME_TYPES,
                                    arrayOf("image/*", "application/pdf"),
                                )
                            }
                            try {
                                pendingReply = result
                                startActivityForResult(pick, REQ_OPEN_DOCUMENT)
                            } catch (e: Exception) {
                                pendingReply = null
                                result.error("unavailable", e.message, null)
                            }
                        }
                    }

                    "latestScreenshot" ->
                        // Denied, unavailable or simply "no screenshots" —
                        // all the same honest answer: null means "no row".
                        result.success(latestScreenshot())

                    "renderPdfFirstPage" -> {
                        val pdf = call.argument<ByteArray>("pdf")
                        if (pdf == null) {
                            result.error("bad_args", "pdf bytes required", null)
                        } else {
                            result.success(renderPdfFirstPage(pdf))
                        }
                    }

                    "nanoStatus" -> nanoStatus(result)

                    "nanoPrompt" -> nanoPrompt(call, result)

                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_OPEN_DOCUMENT) return
        val reply = pendingReply ?: return
        pendingReply = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            reply.success(null) // backed out — the Dart contract's "cancelled"
            return
        }
        try {
            reply.success(readContent(uri))
        } catch (e: Exception) {
            reply.error("read_failed", e.message, null)
        }
    }

    /** Bytes + best-effort display name; the SAF grant covers this stream. */
    private fun readContent(uri: Uri): Map<String, Any> {
        val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: throw IllegalStateException("cannot read $uri")
        var name: String? = null
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                name = cursor.getString(0)
            }
        }
        return mapOf("name" to (name ?: "receipt.pdf"), "bytes" to bytes)
    }

    private fun latestScreenshot(): ByteArray? {
        return try {
            val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            val projection = arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DATA,
            )
            val selection = "${MediaStore.Images.Media.RELATIVE_PATH} LIKE ?"
            val order = "${MediaStore.Images.Media.DATE_ADDED} DESC"
            contentResolver.query(
                collection,
                projection,
                selection,
                arrayOf("%Screenshot%"),
                order,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return null
                val dataPath = if (cursor.isNull(1)) null else cursor.getString(1)
                if (dataPath != null) {
                    val file = File(dataPath)
                    if (file.canRead()) return file.readBytes()
                }
                // Scoped-storage rows without a readable _DATA path still
                // open through their content uri.
                contentResolver.openInputStream(
                    Uri.withAppendedPath(collection, cursor.getLong(0).toString()),
                )?.use { return it.readBytes() }
            }
            null
        } catch (e: Exception) {
            null // SecurityException (pre-33) is the documented "row hides"
        }
    }

    /**
     * Page 1 as PNG via the platform's PdfRenderer (API 21+). Small pages
     * are scaled up toward ~1200 px — ML Kit's recognition sweet spot — and
     * the same bitmap doubles as the Review thumbnail (§2.3). A corrupt or
     * unreadable PDF answers null: Review keeps its icon and degrades to
     * "no text layer", never an error dialog.
     */
    private fun renderPdfFirstPage(pdf: ByteArray): ByteArray? {
        val tmp = File.createTempFile("render", ".pdf", cacheDir)
        var pfd: ParcelFileDescriptor? = null
        var renderer: PdfRenderer? = null
        var page: PdfRenderer.Page? = null
        return try {
            tmp.writeBytes(pdf)
            pfd = ParcelFileDescriptor.open(
                tmp,
                ParcelFileDescriptor.MODE_READ_ONLY,
            )
            val r = PdfRenderer(pfd)
            renderer = r
            if (r.pageCount == 0) return null
            val pg = r.openPage(0)
            page = pg
            val scale = (1200.0 / pg.width).coerceIn(0.25, 4.0)
            val width = (pg.width * scale).toInt().coerceAtLeast(1)
            val height = (pg.height * scale).toInt().coerceAtLeast(1)
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(Color.WHITE) // PDF pages are transparent-paper
            pg.render(
                bitmap,
                null,
                null,
                PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY,
            )
            val out = java.io.ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            bitmap.recycle()
            out.toByteArray()
        } catch (e: Exception) {
            null
        } finally {
            try {
                page?.close()
            } catch (_: Exception) {
            }
            try {
                renderer?.close()
            } catch (_: Exception) {
            }
            try {
                pfd?.close()
            } catch (_: Exception) {
            }
            tmp.delete()
        }
    }

    /**
     * Gemini Nano, tier 3 of the capture pipeline (issue #29, decision 10).
     * The official Flutter wrapper of ML Kit GenAI stubs its inference call,
     * so the app reaches `com.google.mlkit:genai-prompt` through these two
     * methods instead - exactly the "thin platform channel" the feasibility
     * doc prescribes. Status is answered as a plain bool (anything that is
     * not AVAILABLE is unavailable); inference answers with the model's raw
     * text, or null on any failure - Dart's parser owns the contract.
     *
     * No download is ever triggered here: the model is multi-GB and the app
     * has no consent UI to ask for it (decision 10). An already-installed
     * AICore feature is used; everything else behaves like E1.
     */
    private fun nanoStatus(result: MethodChannel.Result) {
        val client = nanoClient()
        if (client == null) {
            result.success(false)
            return
        }
        try {
            Futures.addCallback(
                client.checkStatus(),
                object : FutureCallback<Int> {
                    override fun onSuccess(status: Int?) {
                        result.success(status == FeatureStatus.AVAILABLE)
                    }

                    override fun onFailure(t: Throwable) {
                        result.success(false)
                    }
                },
                nanoExecutor,
            )
        } catch (e: Throwable) {
            result.success(false)
        }
    }

    private fun nanoPrompt(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text")
        if (text == null) {
            result.error("bad_args", "text required", null)
            return
        }
        val client = nanoClient()
        if (client == null) {
            result.success(null)
            return
        }
        try {
            // ImagePart accepts the encoded receipt bytes directly; without
            // an image this degrades to a plain-text prompt over OCR lines.
            val builder = when (val image = call.argument<ByteArray>("image")) {
                null -> GenerateContentRequest.Builder(TextPart(text))
                else -> GenerateContentRequest.Builder(ImagePart(image), TextPart(text))
            }
            builder.maxOutputTokens = NANO_MAX_TOKENS
            val request = builder.build()
            Futures.addCallback(
                client.generateContent(request),
                object : FutureCallback<GenerateContentResponse> {
                    override fun onSuccess(response: GenerateContentResponse?) {
                        result.success(response?.candidates?.firstOrNull()?.text)
                    }

                    override fun onFailure(t: Throwable) {
                        result.success(null)
                    }
                },
                nanoExecutor,
            )
        } catch (e: Throwable) {
            result.success(null)
        }
    }

    /** Created once per engine; a device without GenAI support fails here
     *  (and in checkStatus) exactly once, quietly. */
    private fun nanoClient(): GenerativeModelFutures? =
        nanoModel ?: try {
            GenerativeModelFutures.from(Generation.getClient())
                .also { nanoModel = it }
        } catch (e: Throwable) {
            null
        }

    companion object {
        private const val CHANNEL = "localbudget/capture"
        private const val REQ_OPEN_DOCUMENT = 0x4305
        private const val NANO_MAX_TOKENS = 400
    }
}
