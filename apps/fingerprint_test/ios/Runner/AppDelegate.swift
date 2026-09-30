import Flutter
import UIKit
import LocalAuthentication

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Same channel contract as FingerprintTestPlugin.kt on Android.
    FingerprintTestPlugin.register(with: engineBridge.pluginRegistry)
  }
}

/// iOS face/fingerprint test plugin.
///
/// Channel contract is IDENTICAL to the Android side (FingerprintTestPlugin.kt):
///   - MethodChannel `fingerprint_test/methods`: getInfo / startTest / stopTest / openEnrollmentSettings
///   - EventChannel  `fingerprint_test/events` : {type, code, message}
///     type ∈ listening | help | failed | success | error | stopped
///
/// Implementation = Apple's LocalAuthentication (LAContext.evaluatePolicy).
/// This is the ONLY Apple-sanctioned way to check Face ID / Touch ID. The
/// SYSTEM shows the biometric prompt (TrueDepth / secure enclave); this app
/// never opens the camera — no preview, no photo, no video, no camera
/// permission is even declared. That preserves the "no camera, biometrics
/// only" rule from the Android fingerprint version.
///
/// Info.plist must contain NSFaceIDUsageDescription (already added) or iOS
/// terminates the app the first time Face ID is evaluated.
class FingerprintTestPlugin: NSObject, FlutterStreamHandler {

  private var eventSink: FlutterEventSink?
  private var activeContext: LAContext?
  private var isTesting = false

  static let methodsChannelName = "fingerprint_test/methods"
  static let eventsChannelName = "fingerprint_test/events"

  // MARK: - registration

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "FingerprintTestPlugin") else {
      return
    }
    let instance = FingerprintTestPlugin()

    let methods = FlutterMethodChannel(
      name: methodsChannelName, binaryMessenger: registrar.messenger())
    methods.setMethodCallHandler { call, result in
      switch call.method {
      case "getInfo":
        result(instance.getInfo())
      case "startTest":
        instance.startTest()
        result(nil)
      case "stopTest":
        instance.stopTest()
        result(nil)
      case "openEnrollmentSettings":
        instance.openEnrollmentSettings()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let events = FlutterEventChannel(
      name: eventsChannelName, binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
    // The messenger retains the handler closures (and therefore `instance`)
    // for the lifetime of the engine — intentional app-lifetime singleton.
  }

  // MARK: - FlutterStreamHandler

  func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  // MARK: - getInfo

  private func getInfo() -> [String: Any] {
    let context = LAContext()
    var policyError: NSError?
    // Note: biometryType is populated as a side effect of canEvaluatePolicy.
    let canEvaluate = context.canEvaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics, error: &policyError)

    var biometry = "none"
    switch context.biometryType {
    case .faceID:
      biometry = "faceID"
    case .touchID:
      biometry = "touchID"
    case .opticID:
      biometry = "opticID"
    default:
      break
    }
    if biometry == "none" && canEvaluate {
      // Extremely old devices where biometryType is never set.
      biometry = "touchID"
    }

    var hasHardware = biometry != "none" || canEvaluate
    var hasEnrolled = canEvaluate

    if let error = policyError as? LAError {
      switch error.code {
      case .biometryNotAvailable:
        hasHardware = false
        hasEnrolled = false
      case .biometryNotEnrolled, .passcodeNotSet:
        hasHardware = true
        hasEnrolled = false
      default:
        break
      }
    }

    return [
      "hasHardware": hasHardware,
      "isHardwareDetected": hasHardware,
      "hasEnrolled": hasEnrolled,
      "sdkInt": ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
      "biometryType": biometry,
    ]
  }

  // MARK: - startTest

  private func startTest() {
    if isTesting { return }

    let context = LAContext()
    var policyError: NSError?
    guard context.canEvaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics, error: &policyError)
    else {
      if let error = policyError as? LAError {
        switch error.code {
        case .biometryNotEnrolled:
          emit(type: "error", code: 101, message: "No biometric enrolled")
        case .biometryNotAvailable:
          emit(type: "error", code: 100, message: "Biometric hardware not available")
        case .passcodeNotSet:
          emit(type: "error", code: 102, message: "Device passcode is not set")
        case .biometryLockout:
          emit(type: "error", code: 103, message: "Biometry locked out")
        default:
          emit(type: "error", code: error.code.rawValue, message: error.localizedDescription)
        }
      } else {
        emit(
          type: "error", code: 100,
          message: policyError?.localizedDescription ?? "Biometrics unavailable")
      }
      return
    }

    isTesting = true
    activeContext = context
    emit(type: "listening")

    context.evaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics,
      localizedReason: "Test whether biometric authentication works on this device"
    ) { [weak self] success, evaluateError in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.isTesting = false
        self.activeContext = nil

        if success {
          self.emit(type: "success", code: 0, message: "Biometric matched")
          return
        }
        if let error = evaluateError as? LAError {
          switch error.code {
          case .authenticationFailed:
            // System READ the face/fingerprint but it did not match enrollment.
            // Same semantic as Android's onAuthenticationFailed → Dart counts
            // two of these as FAIL.
            self.emit(type: "failed", code: 0, message: "Biometric read, no match")
          case .userCancel, .systemCancel, .appCancel:
            self.emit(type: "stopped", code: error.code.rawValue, message: "Cancelled")
          case .biometryLockout:
            self.emit(type: "error", code: 103, message: "Biometry locked out")
          default:
            self.emit(type: "error", code: error.code.rawValue, message: error.localizedDescription)
          }
        } else {
          self.emit(
            type: "error", code: 0,
            message: evaluateError?.localizedDescription ?? "Authentication failed")
        }
      }
    }
  }

  // MARK: - stopTest

  private func stopTest() {
    // iOS provides NO programmatic cancel for evaluatePolicy — the user
    // dismisses the system prompt with Cancel, which arrives as .userCancel
    // → 'stopped' event (see startTest completion). Kept for API parity with
    // the Android plugin; safe to call at any time.
    if !isTesting { return }
  }

  // MARK: - openEnrollmentSettings

  private func openEnrollmentSettings() {
    // Opens this app's settings page; Face ID enrollment itself lives in
    // Settings → Face ID & Passcode (Apple exposes no public deep link to it).
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
  }

  // MARK: - emit

  private func emit(type: String, code: Int = 0, message: String? = nil) {
    DispatchQueue.main.async { [weak self] in
      guard let sink = self?.eventSink else { return }
      sink(["type": type, "code": code, "message": message ?? ""])
    }
  }
}
