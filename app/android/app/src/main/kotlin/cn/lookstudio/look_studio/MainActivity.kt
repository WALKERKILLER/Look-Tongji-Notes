package cn.lookstudio.look_studio

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // "look/links": lookstudio:// links opened from other apps
    // (see app/lib/core/deep_links.dart).
    private var links: MethodChannel? = null
    // Links that arrived before Dart asked for them with "initial".
    private val pending = mutableListOf<String>()
    private var dartReady = false

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
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val link = linkOf(intent) ?: return
        if (dartReady) links?.invokeMethod("open", link) else pending.add(link)
    }

    private fun linkOf(intent: Intent?): String? =
        intent?.data?.takeIf { it.scheme == "lookstudio" }?.toString()
}
