package cn.lookstudio.look_studio

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    // "look/links": lookstudio:// links opened from other apps
    // (see app/lib/core/deep_links.dart).
    private var links: MethodChannel? = null
    // Links that arrived before Dart asked for them with "initial".
    private val pending = mutableListOf<String>()
    private var dartReady = false

    // A "saveAs" waiting for the system's create-document screen.
    private var saving: Pair<File, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        linkOf(intent)?.let { pending.add(it) }
        links = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "look/links").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "initial") {
                    result.success(pending.toList())
                    pending.clear()
                    dartReady = true
                } else {
                    result.notImplemented()
                }
            }
        }
        // "look/android": what the Linux workspace and file handling need
        // (see app/lib/core/android_bridge.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "look/android").setMethodCallHandler(::onAndroid)
    }

    private fun onAndroid(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "info" -> result.success(
                mapOf(
                    "nativeLibraryDir" to applicationInfo.nativeLibraryDir,
                    "filesDir" to filesDir.absolutePath,
                    "cacheDir" to cacheDir.absolutePath,
                    "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
                    "sdk" to Build.VERSION.SDK_INT,
                    "device" to "${Build.MANUFACTURER} ${Build.MODEL}",
                    "timezone" to java.util.TimeZone.getDefault().id,
                ),
            )
            "extractAsset" -> {
                val name = call.argument<String>("name")!!
                val dest = File(call.argument<String>("dest")!!)
                thread {
                    try {
                        dest.parentFile?.mkdirs()
                        val tmp = File(dest.path + ".tmp")
                        assets.open(name).use { input -> tmp.outputStream().use { input.copyTo(it) } }
                        tmp.renameTo(dest)
                        runOnUiThread { result.success(true) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("asset", e.message, null) }
                    }
                }
            }
            "openFile" -> result.success(view(File(call.argument<String>("path")!!)))
            "share" -> {
                val file = File(call.argument<String>("path")!!)
                val send = Intent(Intent.ACTION_SEND)
                    .setType(mimeOf(file))
                    .putExtra(Intent.EXTRA_STREAM, uriOf(file))
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                startActivity(Intent.createChooser(send, call.argument<String>("title")))
                result.success(true)
            }
            "saveAs" -> {
                saving?.second?.success(false)
                saving = File(call.argument<String>("path")!!) to result
                val create = Intent(Intent.ACTION_CREATE_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType(call.argument<String>("mime") ?: "application/octet-stream")
                    .putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
                try {
                    @Suppress("DEPRECATION")
                    startActivityForResult(create, SAVE_REQUEST)
                } catch (e: ActivityNotFoundException) {
                    saving = null
                    result.success(false)
                }
            }
            "keepAlive" -> {
                val service = Intent(this, WorkspaceService::class.java)
                if (call.argument<Boolean>("on") == true) {
                    service.putExtra("text", call.argument<String>("text"))
                    if (Build.VERSION.SDK_INT >= 26) startForegroundService(service) else startService(service)
                } else {
                    stopService(service)
                }
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_REQUEST) return
        val (file, result) = saving ?: return
        saving = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(false)
            return
        }
        thread {
            try {
                contentResolver.openOutputStream(uri, "wt")!!.use { out -> file.inputStream().use { it.copyTo(out) } }
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread { result.error("save", e.message, null) }
            }
        }
    }

    private fun uriOf(file: File) = FileProvider.getUriForFile(this, "$packageName.files", file)

    private fun mimeOf(file: File): String =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase()) ?: "application/octet-stream"

    /** Opens a file in another app; false when none can show it. */
    private fun view(file: File): Boolean {
        if (!file.isFile) return false
        val open = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uriOf(file), mimeOf(file))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(open)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val link = linkOf(intent) ?: return
        if (dartReady) links?.invokeMethod("open", link) else pending.add(link)
    }

    private fun linkOf(intent: Intent?): String? =
        intent?.data?.takeIf { it.scheme == "lookstudio" }?.toString()

    companion object {
        private const val SAVE_REQUEST = 4101
    }
}
