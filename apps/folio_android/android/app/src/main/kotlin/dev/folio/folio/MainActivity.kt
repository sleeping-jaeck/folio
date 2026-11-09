package dev.folio.folio

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Hosts the `dev.folio/storage` channel: Storage Access Framework folders and documents. */
class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingIncoming: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingIncoming = documentFrom(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(::onMethodCall)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        documentFrom(intent)?.let { channel?.invokeMethod("incomingDocument", it) }
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFolder" -> startPicker(REQ_FOLDER, result) {
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                )
            }
            "pickEpubFile" -> startPicker(REQ_FILE, result) {
                Intent(Intent.ACTION_OPEN_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("*/*")
                    .putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/epub+zip", "application/octet-stream"))
            }
            "listEpubs" -> background(result) { listEpubs(Uri.parse(call.argument<String>("treeUri")!!)) }
            "copyToFile" -> background(result) {
                copyToFile(Uri.parse(call.argument<String>("uri")!!), File(call.argument<String>("path")!!))
                null
            }
            "hasPermission" -> {
                val uri = Uri.parse(call.argument<String>("treeUri")!!)
                result.success(contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission })
            }
            "releaseFolder" -> {
                try {
                    contentResolver.releasePersistableUriPermission(
                        Uri.parse(call.argument<String>("treeUri")!!),
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                } catch (_: SecurityException) {
                }
                result.success(null)
            }
            "takeIncomingDocument" -> {
                result.success(pendingIncoming)
                pendingIncoming = null
            }
            else -> result.notImplemented()
        }
    }

    private fun startPicker(code: Int, result: MethodChannel.Result, build: () -> Intent) {
        if (pendingResult != null) {
            result.error("busy", "A picker is already open", null)
            return
        }
        pendingResult = result
        @Suppress("DEPRECATION")
        startActivityForResult(build(), code)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_FOLDER && requestCode != REQ_FILE) return
        val result = pendingResult ?: return
        pendingResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        if (requestCode == REQ_FILE) {
            result.success(uri.toString())
            return
        }
        contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        result.success(mapOf("uri" to uri.toString(), "name" to folderName(uri)))
    }

    private fun folderName(treeUri: Uri): String {
        val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, DocumentsContract.getTreeDocumentId(treeUri))
        contentResolver.query(docUri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) return it.getString(0)
        }
        return DocumentsContract.getTreeDocumentId(treeUri).substringAfterLast(':').substringAfterLast('/')
    }

    private fun listEpubs(treeUri: Uri): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        val pending = ArrayDeque<String>().apply { add(DocumentsContract.getTreeDocumentId(treeUri)) }
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        while (pending.isNotEmpty()) {
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, pending.removeFirst())
            contentResolver.query(children, columns, null, null, null)?.use { c ->
                while (c.moveToNext()) {
                    val id = c.getString(0)
                    val name = c.getString(1) ?: continue
                    if (c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        pending.add(id)
                    } else if (name.endsWith(".epub", ignoreCase = true)) {
                        out.add(
                            mapOf(
                                "uri" to DocumentsContract.buildDocumentUriUsingTree(treeUri, id).toString(),
                                "name" to name,
                                "size" to (if (c.isNull(3)) 0L else c.getLong(3)),
                                "modified" to (if (c.isNull(4)) 0L else c.getLong(4)),
                            )
                        )
                    }
                }
            }
        }
        return out
    }

    private fun copyToFile(uri: Uri, target: File) {
        target.parentFile?.mkdirs()
        val input = contentResolver.openInputStream(uri) ?: throw IllegalStateException("Cannot open $uri")
        input.use { src -> target.outputStream().use { src.copyTo(it, 64 * 1024) } }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("storage", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun documentFrom(intent: Intent?): String? {
        if (intent == null) return null
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            else -> null
        }
        return uri?.toString()
    }

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "dev.folio/storage"
        private const val REQ_FOLDER = 4101
        private const val REQ_FILE = 4102
    }
}
