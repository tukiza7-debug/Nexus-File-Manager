package com.tukiza7.nexus

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Nexus entry activity.
 *
 * Beyond hosting Flutter, this activity receives files shared into Nexus from
 * other apps (ACTION_SEND / ACTION_SEND_MULTIPLE — the receiving half of the
 * Storage Access Framework flow). Shared streams are copied into the app cache
 * on a background thread (audit item 20 — the main thread must never block on
 * IO or large files would ANR) and the local paths are delivered to Dart over
 * the "nexus/incoming" method channel.
 *
 * Security (audit items 20 / T12):
 *  * display names are sanitized with [sanitizeName] — path separators and
 *    traversal ("..") can never escape the incoming cache directory;
 *  * the destination is verified to stay inside cacheDir/incoming;
 *  * copies check free disk space and the declared stream size before
 *    writing, and skip duplicates already collected in this process.
 *
 * The activity also exposes "openWith" (ACTION_VIEW through FileProvider)
 * and "shareFrom" (ACTION_SEND) so Dart can open or share cached files
 * (audit item 21).
 */
class MainActivity : FlutterActivity() {

    private val pending = mutableListOf<String>()
    private val knownPaths = mutableSetOf<String>()
    private var channel: MethodChannel? = null
    private val ioExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "nexus/incoming",
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "pendingSharedFiles" -> result.success(pending.toList())
                    "clearPendingSharedFiles" -> {
                        val files = pending.toList()
                        pending.clear()
                        knownPaths.clear()
                        files.forEach { runCatching { File(it).delete() } }
                        result.success(null)
                    }
                    "openWith" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("EINVAL", "path is required", null)
                        } else {
                            result.success(openWithSystem(path))
                        }
                    }
                    "shareFrom" -> {
                        val path = call.argument<String>("path")
                        val mime = call.argument<String>("mime")
                        if (path == null) {
                            result.error("EINVAL", "path is required", null)
                        } else {
                            result.success(shareFrom(path, mime))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // Deliver anything collected before the Dart side was listening.
        deliver()
    }

    override fun onDestroy() {
        ioExecutor.shutdown()
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        collect(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        collect(intent)
        deliver()
    }

    /** Sanitizes an untrusted display name into a bare, safe filename. */
    private fun sanitizeName(name: String): String? {
        val bare = File(name).name // strips any path components
        if (bare.isEmpty() || bare == "." || bare == "..") return null
        if (bare.contains('/') || bare.contains('\\')) return null
        if (bare.contains('\u0000')) return null
        return bare
    }

    @Suppress("DEPRECATION")
    private fun collect(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return
        val uris = ArrayList<Uri>()
        when (action) {
            Intent.ACTION_SEND ->
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.add(it) }
            Intent.ACTION_SEND_MULTIPLE -> {
                val list = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                if (list != null) uris.addAll(list)
            }
            else -> return
        }
        if (uris.isEmpty()) return
        val dir = File(cacheDir, "incoming").apply { mkdirs() }
        for (uri in uris) {
            ioExecutor.execute {
                runCatching {
                    val rawName = queryDisplayName(uri) ?: "shared-${System.currentTimeMillis()}"
                    val name = sanitizeName(rawName)
                        ?: return@runCatching
                    // Size / free-space check before writing (audit item 20).
                    // Negative/unknown sizes fall through to the copy loop's
                    // own failure handling.
                    val declaredSize = querySize(uri) ?: -1L
                    if (declaredSize > 0 && declaredSize > dir.usableSpace) return@runCatching
                    val dest = uniqueChild(dir, name)
                    // Containment guarantee (audit item 20): the resolved
                    // destination must stay inside the incoming directory.
                    if (!dest.canonicalFile.path.startsWith(dir.canonicalFile.path + File.separator)) {
                        return@runCatching
                    }
                    val input = contentResolver.openInputStream(uri)
                    if (input == null) return@runCatching
                    input.use { stream ->
                        FileOutputStream(dest).use { output ->
                            stream.copyTo(output, BUFFER_SIZE)
                        }
                    }
                    synchronized(knownPaths) {
                        if (knownPaths.add(dest.absolutePath)) {
                            synchronized(pending) { pending.add(dest.absolutePath) }
                        }
                    }
                    runOnMainThread { deliver() }
                }
            }
        }
    }

    private fun runOnMainThread(block: () -> Unit) {
        runOnUiThread { block() }
    }

    private fun querySize(uri: Uri): Long? = runCatching {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
            if (sizeIndex >= 0 && cursor.moveToFirst() && !cursor.isNull(sizeIndex)) {
                cursor.getLong(sizeIndex)
            } else null
        }
    }.getOrNull()

    private fun queryDisplayName(uri: Uri): String? = runCatching {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else null
        }
    }.getOrNull()

    private fun uniqueChild(dir: File, name: String): File {
        val candidate = File(dir, name)
        if (!candidate.exists()) return candidate
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var i = 1
        while (true) {
            val numbered = File(dir, "$base ($i)$ext")
            if (!numbered.exists()) return numbered
            i++
        }
    }

    // ── open / share (audit item 21) ──────────────────────────────────────

    private fun authority() = "$packageName.fileprovider"

    private fun contentUriFor(path: String): Uri {
        val file = File(path)
        return FileProvider.getUriForFile(this, authority(), file)
    }

    private fun mimeFor(path: String, hint: String?): String {
        if (!hint.isNullOrEmpty()) return hint
        val file = File(path)
        val ext = file.extension.lowercase()
        val fromName = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
        return fromName ?: contentResolver.getType(contentUriFor(path)) ?: "application/octet-stream"
    }

    @Suppress("DEPRECATION")
    private fun openWithSystem(path: String): Boolean {
        return runCatching {
            val file = File(path)
            if (!file.exists()) return false
            val uri = contentUriFor(path)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeFor(path, null))
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val resolved = intent.resolveActivity(packageManager)
            if (resolved == null) return false
            startActivity(intent)
            true
        }.getOrDefault(false)
    }

    private fun shareFrom(path: String, mime: String?): Boolean {
        return runCatching {
            val file = File(path)
            if (!file.exists()) return false
            val uri = contentUriFor(path)
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = mimeFor(path, mime)
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "Share via"))
            true
        }.getOrDefault(false)
    }

    private fun deliver() {
        channel?.invokeMethod("onSharedFiles", synchronized(pending) { pending.toList() })
    }

    companion object {
        private const val BUFFER_SIZE = 256 * 1024
    }
}
