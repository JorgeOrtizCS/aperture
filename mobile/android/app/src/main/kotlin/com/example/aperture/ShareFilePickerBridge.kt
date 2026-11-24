package com.example.aperture

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.CancellationSignal
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Holds only the temporary SAF grant until Flutter is ready to read. */
internal class ShareFilePickerBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private data class Pick(val id: Int, val reply: MethodChannel.Result)
    private data class Read(val id: Int, val reply: MethodChannel.Result, val signal: CancellationSignal)
    private data class Document(val id: Int, val uri: Uri)
    private class FileProblem(val code: String) : Exception()
    private data class FileData(val name: String, val mimeType: String?, val bytes: ByteArray)

    private val channel = MethodChannel(messenger, "aperture/share_file_picker")
    private val worker = Executors.newSingleThreadExecutor()
    private var pick: Pick? = null
    private var chooserOpen = false
    private var selected: Document? = null
    private var reading: Read? = null

    init {
        channel.setMethodCallHandler { call, reply ->
            val id = call.argument<Int>("id")
            if (id == null || id <= 0) {
                reply.error("unreadable", null, null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "pick" -> open(id, reply)
                "read" -> read(id, call.argument<Int>("maxBytes"), reply)
                "discard" -> {
                    if (selected?.id == id) selected = null
                    if (reading?.id == id) cancelRead()
                    val pending = pick
                    if (pending?.id == id) {
                        pick = null
                        pending.reply.success(false)
                        // The pending system callback still owns the request
                        // code; do not reuse it until that callback arrives.
                        activity.finishActivity(REQUEST)
                    }
                    reply.success(null)
                }
                else -> reply.notImplemented()
            }
        }
    }

    private fun open(id: Int, reply: MethodChannel.Result) {
        if (chooserOpen || selected != null || reading != null) {
            reply.error("busy", null, null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/png"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        pick = Pick(id, reply)
        chooserOpen = true
        try {
            activity.startActivityForResult(intent, REQUEST)
        } catch (_: Exception) {
            chooserOpen = false
            pick = null
            reply.error("unavailable", null, null)
        }
    }

    fun onResult(resultCode: Int, intent: Intent?) {
        chooserOpen = false
        val pending = pick ?: return
        pick = null
        if (resultCode != Activity.RESULT_OK) {
            pending.reply.success(false)
            return
        }
        val uri = intent?.data
        if (uri == null || uri.scheme != "content") {
            pending.reply.error("unreadable", null, null)
            return
        }
        selected = Document(pending.id, uri)
        pending.reply.success(true)
    }

    private fun read(id: Int, limit: Int?, reply: MethodChannel.Result) {
        val document = selected
        if (document == null || document.id != id || limit == null || limit !in 1..MAX_BYTES || reading != null) {
            reply.error("unreadable", null, null)
            return
        }
        selected = null
        val pending = Read(id, reply, CancellationSignal())
        reading = pending
        worker.execute {
            var data: FileData? = null
            var error = "unreadable"
            try {
                data = load(document.uri, limit, pending.signal)
            } catch (e: FileProblem) {
                error = e.code
            } catch (_: Exception) {
                // Provider messages can include sensitive document paths.
            }
            activity.runOnUiThread {
                val file = data
                try {
                    if (reading === pending) {
                        reading = null
                        if (file == null) {
                            reply.error(error, null, null)
                        } else {
                            reply.success(mapOf(
                                "name" to file.name,
                                "mimeType" to file.mimeType,
                                "bytes" to file.bytes,
                            ))
                        }
                    }
                } finally {
                    // The standard codec synchronously copies into its envelope.
                    file?.bytes?.fill(0)
                }
            }
        }
    }

    private fun load(uri: Uri, limit: Int, signal: CancellationSignal): FileData {
        val resolver = activity.contentResolver
        val projection = arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val name = resolver.query(uri, projection, null, null, null, signal)?.use { cursor ->
            if (!cursor.moveToFirst()) throw FileProblem("unreadable")
            val size = cursor.getColumnIndex(OpenableColumns.SIZE)
            if (size >= 0 && !cursor.isNull(size) && cursor.getLong(size) > limit) {
                throw FileProblem("too_large")
            }
            val label = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (label < 0) null else cursor.getString(label)
        } ?: throw FileProblem("unreadable")
        val mime = resolver.getType(uri)
        if (!name.endsWith(".png", ignoreCase = true) ||
            (mime != null && mime.lowercase() !in PNG_MIME_TYPES)
        ) throw FileProblem("unsupported")

        // The metadata is only a hint. Read at most limit + one byte even
        // when a provider omits the size or reports an incorrect size.
        val staging = ByteArray(limit + 1)
        try {
            val count = resolver.openAssetFileDescriptor(uri, "r", signal)?.use { descriptor ->
                descriptor.createInputStream().use { input ->
                    var used = 0
                    while (used < staging.size) {
                        signal.throwIfCanceled()
                        val n = input.read(staging, used, minOf(65536, staging.size - used))
                        if (n < 0) break
                        if (n == 0) throw FileProblem("unreadable")
                        used += n
                    }
                    used
                }
            } ?: throw FileProblem("unreadable")
            signal.throwIfCanceled()
            if (count == 0) throw FileProblem("empty")
            if (count > limit) throw FileProblem("too_large")
            return FileData(name, mime, staging.copyOf(count))
        } finally {
            staging.fill(0)
        }
    }

    fun cancelRead() {
        val pending = reading ?: return
        reading = null
        pending.signal.cancel()
        pending.reply.error("unreadable", null, null)
    }

    fun destroy() {
        channel.setMethodCallHandler(null)
        pick?.reply?.success(false)
        pick = null
        selected = null
        cancelRead()
        worker.shutdownNow()
    }

    companion object {
        const val REQUEST = 0xA02
        private const val MAX_BYTES = 5 * 1024 * 1024
        private val PNG_MIME_TYPES = setOf("image/png", "image/x-png", "application/octet-stream")
    }
}
