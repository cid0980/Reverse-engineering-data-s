package com.example.fingerprint_test

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var fingerprintPlugin: FingerprintTestPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        fingerprintPlugin = FingerprintTestPlugin(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger
        )
    }

    override fun onDestroy() {
        fingerprintPlugin?.dispose()
        fingerprintPlugin = null
        super.onDestroy()
    }
}
