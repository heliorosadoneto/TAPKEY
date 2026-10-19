package com.helio.meu_notebook

import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity é exigido pelo local_auth (biometria / PIN do aparelho).
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Nome do aparelho (fabricante + modelo) enviado ao notebook em X-Device-Name.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tapkey/device").setMethodCallHandler { call, result ->
            if (call.method == "model") {
                val maker = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
                val model = Build.MODEL
                result.success(if (model.startsWith(maker, ignoreCase = true)) model else "$maker $model")
            } else {
                result.notImplemented()
            }
        }
    }
}
