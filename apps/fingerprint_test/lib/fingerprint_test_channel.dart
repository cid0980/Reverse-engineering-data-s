import 'dart:async';

import 'package:flutter/services.dart';

/// A single event pushed from the platform side.
///
/// Types:
///  - `listening` : sensor/prompt is armed, waiting for the user
///  - `help`      : acquire help (finger dirty / too slow / …), see [code]
///  - `failed`    : biometric read, but it did NOT match enrollment
///  - `success`   : matched → test PASS
///  - `error`     : authentication error, see [code]
///                 (100 = no hardware, 101 = nothing enrolled,
///                  102 = passcode not set (iOS), 103 = lockout (iOS),
///                  7/9 = Android lockout, negative codes = raw LAError on iOS)
///  - `stopped`   : test cancelled by the user/app
class FingerprintEvent {
  const FingerprintEvent({required this.type, this.code = 0, this.message});

  final String type;
  final int code;
  final String? message;

  factory FingerprintEvent.fromMap(Map<dynamic, dynamic> map) => FingerprintEvent(
        type: map['type'] as String,
        code: (map['code'] as num?)?.toInt() ?? 0,
        message: map['message'] as String?,
      );
}

/// Snapshot of the biometric hardware/enrollment state.
class FingerprintDeviceInfo {
  const FingerprintDeviceInfo({
    required this.hasHardware,
    required this.isHardwareDetected,
    required this.hasEnrolled,
    required this.sdkInt,
    this.biometryType,
  });

  final bool hasHardware;
  final bool isHardwareDetected;
  final bool hasEnrolled;

  /// Android: API level. iOS: major iOS version.
  final int sdkInt;

  /// iOS only (LAContext.biometryType):
  /// `faceID` | `touchID` | `opticID` | `none`.
  /// `null` on Android (fingerprint sensor assumed when hasHardware).
  final String? biometryType;

  bool get canTest => hasHardware && isHardwareDetected && hasEnrolled;

  factory FingerprintDeviceInfo.fromMap(Map<dynamic, dynamic> map) => FingerprintDeviceInfo(
        hasHardware: map['hasHardware'] as bool? ?? false,
        isHardwareDetected: map['isHardwareDetected'] as bool? ?? false,
        hasEnrolled: map['hasEnrolled'] as bool? ?? false,
        sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
        biometryType: map['biometryType'] as String?,
      );
}

/// Thin wrapper around the platform channels implemented in Kotlin (Android)
/// and Swift (iOS).
///
/// Channel names (must match FingerprintTestPlugin.kt / AppDelegate.swift):
///   - `fingerprint_test/methods`  (MethodChannel: get info / start / stop / settings)
///   - `fingerprint_test/events`   (EventChannel: stream of authentication events)
class FingerprintTestChannel {
  static const MethodChannel methods = MethodChannel('fingerprint_test/methods');
  static const EventChannel eventsChannel = EventChannel('fingerprint_test/events');

  Stream<FingerprintEvent>? _events;

  /// Broadcast stream of biometric events from native code.
  Stream<FingerprintEvent> get events {
    return _events ??= eventsChannel
        .receiveBroadcastStream()
        .map((dynamic e) => FingerprintEvent.fromMap(e as Map<dynamic, dynamic>));
  }

  Future<FingerprintDeviceInfo> getInfo() async {
    final Map<dynamic, dynamic> map =
        await methods.invokeMapMethod<dynamic, dynamic>('getInfo') ??
            <dynamic, dynamic>{};
    return FingerprintDeviceInfo.fromMap(map);
  }

  /// Arms the test: FingerprintManager.authenticate (Android) /
  /// LAContext.evaluatePolicy (iOS).
  Future<void> startTest() => methods.invokeMethod<void>('startTest');

  /// Cancels the current authentication (Android: CancellationSignal.cancel;
  /// iOS: the system prompt must be dismissed by the user — see README).
  Future<void> stopTest() => methods.invokeMethod<void>('stopTest');

  /// Opens the system biometric enrollment screen (Android) / app Settings (iOS).
  Future<void> openEnrollmentSettings() =>
      methods.invokeMethod<void>('openEnrollmentSettings');
}
