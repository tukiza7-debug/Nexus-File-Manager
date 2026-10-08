package com.tukiza7.nexus

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Nexus entry activity.
 *
 * Beyond hosting Flutter, this activity receives files shared into Nexus from
 * other apps (ACTION_SEND / ACTION_SEND_MULTIPLE — the receiving half of the
 * Storage Access Framework flow). Shared streams are copied into the app cache
 * immediately (the granting URIs expire quickly) and the local paths are
 * delivered to Dart over the "nexus/incoming" method channel:
 *
 *  - Kotlin pushes "onSharedFiles" whenever new files arrive while Dart runs.
 *  - Dart pulls "pendingSharedFiles" at startup / on resume (covers files that
 *    arrived before the Flutter handler was registered).
 *  - Dart calls "clearPendingSharedFiles" after saving or discarding.
 */
class MainActivity : FlutterActivity() {

    private val pending = mutableListOf<String>()
    private var channel: MethodChannel? = null

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
                        files.forEach { runCatching { File(it).delete() } }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // Deliver anything collected before the Dart side was listening.
        deliver()
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
        for (uri in uris) {
            runCatching {
                val dir = File(cacheDir, "incoming").apply { mkdirs() }
                val name = queryDisplayName(uri)
                    ?: "shared-${System.currentTimeMillis()}-${pending.size}"
                val dest = uniqueChild(dir, name)
                val input = contentResolver.openInputStream(uri)
                if (input == null) return@runCatching
                input.use { stream ->
                    dest.outputStream().use { output -> stream.copyTo(output) }
                }
                pending.add(dest.absolutePath)
            }
        }
    }

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

    private fun deliver() {
        channel?.invokeMethod("onSharedFiles", pending.toList())
    }
}
