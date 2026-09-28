package com.oleksandrshabaldas.tranquillo

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// Shares its Flutter engine with the background audio service, so playback
// keeps going (and the UI reconnects) when the app goes to the background.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Used by lib/updates/update_service.dart: opens Android's install
        // screen for a downloaded update, or a web page.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tranquillo/installer").setMethodCallHandler { call, result ->
            val context = applicationContext
            try {
                val intent = when (call.method) {
                    "install" -> {
                        val apk = File(call.argument<String>("path")!!)
                        val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", apk)
                        Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    "openUrl" -> Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url")))
                    else -> null
                }
                if (intent == null) {
                    result.notImplemented()
                } else {
                    context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
            } catch (e: Exception) {
                result.error("failed", e.message, null)
            }
        }
    }
}
