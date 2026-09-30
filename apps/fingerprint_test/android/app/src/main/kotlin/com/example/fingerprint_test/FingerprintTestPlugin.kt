package com.example.fingerprint_test

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.fingerprint.FingerprintManager
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Fingerprint-only test channel.
 *
 * Direct port of the trick used by the production app "Cashify Diagnose"
 * (in.cashify.diagno.cec) in its authLegacy() path:
 *
 *     FingerprintManager.authenticate(crypto, cancellationSignal, 0, cb, handler)
 *
 * Why not BiometricPrompt / local_auth?
 *  - BiometricPrompt is the UNIFIED system prompt: it listens to EVERY
 *    enrolled biometric at once (fingerprint + face). On Android 11+ the
 *    system may engage the face stack (which uses the camera) during the
 *    same prompt, and there is NO API to say "fingerprint only".
 *  - FingerprintManager (deprecated since API 28 but fully functional on
 *    all current Android versions — production apps still ship it) talks
 *    DIRECTLY to the fingerprint HAL. No system dialog, no face, no camera.
 *
 * This app never declares android.permission.CAMERA, so a camera call from
 * this code path is not even possible.
 */
@Suppress("DEPRECATION")
class FingerprintTestPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger
) {
    companion object {
        const val METHODS = "fingerprint_test/methods"
        const val EVENTS = "fingerprint_test/events"

        // App-level pseudo error codes (>= 100 so they never clash with
        // FingerprintManager's own error codes 1..99).
        const val ERR_NO_HARDWARE = 100
        const val ERR_NOT_ENROLLED = 101
    }

    private val appContext: Context get() = activity.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())

    private var cancelSignal: CancellationSignal? = null
    private var isListening = false
    private var userStopped = false
    private var eventSink: EventChannel.EventSink? = null

    init {
        MethodChannel(messenger, METHODS).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getInfo" -> result.success(getInfo())
                    "startTest" -> {
                        startTest()
                        result.success(null)
                    }
                    "stopTest" -> {
                        stopTest()
                        result.success(null)
                    }
                    "openEnrollmentSettings" -> {
                        openEnrollmentSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                result.error("FP_INTERNAL", t.message, null)
            }
        }

        EventChannel(messenger, EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                }

                override fun onCancel(args: Any?) {
                    eventSink = null
                }
            }
        )
    }

    /** Same hardware probe as Cashify's helper: feature flag + system service. */
    private fun fingerprintManager(): FingerprintManager? {
        val pm = appContext.packageManager
        if (!pm.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)) return null
        return appContext.getSystemService(Context.FINGERPRINT_SERVICE) as? FingerprintManager
    }

    private fun getInfo(): Map<String, Any> {
        val fm = fingerprintManager()
        return mapOf(
            "hasHardware" to (fm != null),
            "isHardwareDetected" to
                runCatching { fm?.isHardwareDetected == true }.getOrDefault(false),
            "hasEnrolled" to
                runCatching { fm?.hasEnrolledFingerprints() == true }.getOrDefault(false),
            "sdkInt" to android.os.Build.VERSION.SDK_INT
        )
    }

    /**
     * Arm the sensor. Requires the USE_FINGERPRINT permission, which is a
     * NORMAL (install-time) permission declared in the manifest — hence the
     * MissingPermission lint suppression below.
     */
    @SuppressLint("MissingPermission")
    private fun startTest() {
        if (isListening) return

        val fm = fingerprintManager()
        if (fm == null) {
            emit("error", ERR_NO_HARDWARE, "Fingerprint feature not present")
            return
        }
        val hwOk = runCatching { fm.isHardwareDetected }.getOrDefault(false)
        if (!hwOk) {
            emit("error", ERR_NO_HARDWARE, "Fingerprint hardware not detected")
            return
        }
        val enrolled = runCatching { fm.hasEnrolledFingerprints() }.getOrDefault(false)
        if (!enrolled) {
            emit("error", ERR_NOT_ENROLLED, "No fingerprint enrolled")
            return
        }

        userStopped = false
        cancelSignal = CancellationSignal()
        try {
            // *** THE KEY CALL — fingerprint HAL only, no BiometricPrompt ***
            // Identical to Cashify's authLegacy(): crypto object = null.
            fm.authenticate(
                null,            // CryptoObject — null is fine for a hardware test
                cancelSignal,    // lets stopTest() cancel via CancellationSignal
                0,               // flags
                authCallback,    // success / failed / help / error
                mainHandler      // callbacks delivered on the main thread
            )
            isListening = true
            emit("listening")
        } catch (t: Throwable) {
            cancelSignal = null
            emit("error", ERR_NO_HARDWARE, "authenticate() failed: ${t.message}")
        }
    }

    private fun stopTest() {
        if (!isListening) return
        userStopped = true
        // cancel() makes the system deliver onAuthenticationError(ERROR_CANCELED);
        // the callback below converts that into a "stopped" event.
        cancelSignal?.cancel()
        cancelSignal = null
    }

    private val authCallback = object : FingerprintManager.AuthenticationCallback() {

        override fun onAuthenticationSucceeded(result: FingerprintManager.AuthenticationResult?) {
            isListening = false
            cancelSignal = null
            emit("success", 0, "Fingerprint matched")
        }

        /** Sensor read a fingerprint, but it did not match enrollment. */
        override fun onAuthenticationFailed() {
            emit("failed", 0, "Fingerprint read, no match")
        }

        /** Recoverable guidance: finger dirty, placed too slow / too fast, … */
        override fun onAuthenticationHelp(code: Int, help: CharSequence?) {
            emit("help", code, help?.toString())
        }

        override fun onAuthenticationError(code: Int, msg: CharSequence?) {
            isListening = false
            cancelSignal = null
            // ERROR_CANCELED = 5. If *we* cancelled → "stopped", else a real error.
            if (code == 5 && userStopped) {
                emit("stopped", code, msg?.toString())
            } else {
                emit("error", code, msg?.toString())
            }
        }
    }

    /**
     * Jump to the enrollment UI so a factory-reset phone can add a finger.
     * Tries the dedicated action first, falls back to Security settings.
     */
    private fun openEnrollmentSettings() {
        val attempts = listOf(
            "android.settings.FINGERPRINT_ENROLL",
            Settings.ACTION_SECURITY_SETTINGS
        )
        for (action in attempts) {
            try {
                activity.startActivity(Intent(action))
                return
            } catch (_: Throwable) {
                // try the next one
            }
        }
    }

    fun dispose() {
        stopTest()
        eventSink = null
    }

    private fun emit(type: String, code: Int = 0, message: String? = null) {
        // Always deliver events to Dart on the main thread.
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "type" to type,
                    "code" to code,
                    "message" to message
                )
            )
        }
    }
}
