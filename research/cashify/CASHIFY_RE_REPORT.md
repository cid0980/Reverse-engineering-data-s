# Reverse Engineering Report — Cashify Diagnose (fingerprint test deep-dive)

**Package:** `in.cashify.diagno.cec`
**App name:** Cashify Diagnose (REFURBIND TECH / Cashify.in)
**Version analyzed:** 3.1.11 (versionCode 47)
**Source of APK:** APKPure (XAPK, split APKs)
**Tool:** jadx 1.5.1 → **8,922 Java files** decompiled

---

## 1. TL;DR — Answering the camera + fingerprint question

> **Claim:** "Android auth rules say camera and fingerprint are always called together,
> they can't be triggered independently. So how does Cashify trigger fingerprint alone?"

**The premise is wrong — and the decompiled code proves it.** There is **zero** camera
API usage anywhere in the fingerprint test path. The app triggers the fingerprint sensor
independently using two Android APIs, and the camera is only used by a *separate* set of
camera tests.

**Three things cause the confusion:**

| Belief | Reality |
|---|---|
| "BiometricPrompt always uses camera + fingerprint together" | On **Android 11+ the *unified biometric prompt*** listens to **all enrolled biometrics at once** (fingerprint + face). If face unlock is enrolled, the **system** may engage the camera stack during a "fingerprint" prompt. That's the OS, not the app. Apps **cannot** tell `BiometricPrompt` "fingerprint only". |
| "So fingerprint can't be tested alone" | It can: the deprecated-but-working **`FingerprintManager.authenticate()`** talks directly to the fingerprint HAL — no BiometricPrompt, no face, no camera. **This exact API is what Cashify uses** in its legacy path (`authLegacy()` → `d4/e.java`). |
| "Fingerprint needs camera hardware" | On **optical under-display** sensors, the sensor *literally is* a tiny camera module under the OLED (screen lights up = flash). But that happens **inside the biometric HAL** — invisible to apps. The app never calls camera APIs for it. |

**Camera and fingerprint are separate Android stacks, permissions, and APIs:**

```
Fingerprint:  USE_FINGERPRINT / USE_BIOMETRIC  →  FingerprintManager / BiometricPrompt
Camera:       CAMERA                          →  camera2 / CameraX
```

Cashify's manifest declares both — but the fingerprint test only checks
`USE_BIOMETRIC`/`USE_FINGERPRINT` at runtime (see §3).

---

## 2. Two separate tests, not one

From `in/cashify/diagno/sensors/types/SensorTestType.java`:

```java
FACE_ID      = new SensorTestType("FACE_ID",      6, "face_id",      706);
FINGERPRINT  = new SensorTestType("FINGERPRINT",  7, "fingerprint",  707);
```

- Separate ViewModels: `FaceIdViewModel` vs `FingerprintViewModel`
- Separate result keys: `"fid"` (`FACE_DIAGNOSE`) vs `"fp"` (`FINGER_TOUCH_DIAGNOSE`)
- The server-driven test list (mock JSON in `MockData.java`) contains them as
  independent entries: `{"id":"face_id","ty":"test",...}` and `{"id":"fingerprint","ty":"test",...}`
- Camera tests are in a **different group** entirely: group `camera` =
  `front_camera`, `camera`, `camera_flash`, `front_camera_flash` — none of which
  appear in the sensor group where fingerprint lives.

---

## 3. How the fingerprint test works (code path)

**Class:** `in/cashify/diagno/sensors/tests/fingerprint/FingerprintViewModel`
(result key `"fp"`, 238 lines)

### 3.1 Capability pre-checks

```java
// hardware present?
hasSystemFeature("android.hardware.fingerprint")     // via helper d4/e.b()

// can we authenticate?  → r/C1832s.a()  (mini re-implementation of BiometricManager)
//   API ≥ 30 : BiometricManager.canAuthenticate(255)   // any biometric/credential
//   API 29   : BiometricManager.canAuthenticate()      // pre-flag overload
//   API 28   : KeyguardManager.isDeviceSecure() + FingerprintManager fallback
//   else     : FingerprintManager.isHardwareDetected() + hasEnrolledFingerprints()

// permissions actually requested for this test:
USE_BIOMETRIC + USE_FINGERPRINT   (API ≥ 28)   // camera NOT required
```

### 3.2 Path A — modern: BiometricPrompt (API 29/30+)

The app bundles a **vendored fork of androidx.biometric** (`androidx.biometric.BiometricViewModel`
plus custom classes in package `r/`):

- `r/x.java` — prompt driver built like androidx's `BiometricPrompt(FragmentActivity, Executor, Callback)`;
  method `x.a(r.w)` (PromptInfo: title, subtitle, description, negative button) reads biometric-availability
  args (`has_iris` seen in the bytecode — the fork detects available modalities the way PromptFragment does)
- `r/AbstractC1825l.java` — platform `android.hardware.biometrics.BiometricPrompt`:
  - `.authenticate(crypto, signal, executor, callback)` and `.authenticate(signal, executor, callback)`
  - Builder: `setTitle/setSubtitle/setDescription/setNegativeButton`
  - `r/AbstractC1826m` → `setDeviceCredentialAllowed(z)`
  - `r/AbstractC1827n` → `setAllowedAuthenticators(i)` (API 30+ authenticator flags)
- `r/C1815b.java` — `BiometricPrompt$AuthenticationCallback` → success/error/failed → `sa.b` controller
- `r/C1810J.java` — the app's own **dialog UI** (inflates `R.layout.fingerprint_dialog_layout`
  with fp icon/error views) bound to `BiometricViewModel`

### 3.3 Path B — legacy: FingerprintManager alone (fingerprint-only!)

```java
// FingerprintViewModel.authLegacy()
if (!hasPermissions(USE_BIOMETRIC, USE_FINGERPRINT)) return false;
FingerprintManager fp = e.b(context);              // d4/e helper
if (fp == null || !fp.hasEnrolledFingerprints()) { promptToEnroll(); return true; }
e.a(cryptoObject, cancellationSignal, callback, handler);
//  → FingerprintManager.authenticate(cryptoObject, cancellationSignal,
//                                    0, AuthenticationCallback, handler)
```

This path **exercises the fingerprint sensor exclusively** — no BiometricPrompt, so no
face/camera can be involved. `d4/e.java` builds the `CryptoObject` (Cipher/Signature/Mac)
and wires `CancellationSignal` for cancellation.

### 3.4 Shared controller & result logic (`sa/b.java`)

```
attempt counter f23027g  →  one retry allowed (≤1), then FAIL
error 10 → user cancel  → DiagnoState.Skipped
error 11 → not enrolled → StatusPendingReason.SystemSetting → deep-link to system
           enrollment settings (isFingerprintEnableRequested flag; FAIL if user returns
           without enrolling)
error 12 → NOT_SUPPORTED
error 1/5 → lockout → FAIL(INITIALIZATION_ERROR)
onAuthenticationSucceeded → SUCCESS  (+1 failed-attempt count reported in result)
```

### 3.5 The FaceId test for comparison (`FaceIdViewModel`)

- Requires API ≥ 29, else immediate `FAIL(NOT_SUPPORTED)`
- Requires `hasSystemFeature("android.hardware.biometrics.face")`
- Uses the **same** shared `sa.b` controller + `r.x` BiometricPrompt driver
- **No camera API calls either** — the *system's* face auth service uses the IR/front
  camera internally when `authenticate()` runs

---

## 4. Where the camera IS used (completely separate code)

| Area | Package | API |
|---|---|---|
| Photo/video/torch/autofocus tests | `in.cashify.diagno.cam.tests.*` (`PhotoCameraViewModel`, `RearCameraViewModel`, `FlashlightViewModel`, `VideoCameraViewModel` …) | camera2 / CameraX-style |
| OCR capture, barcode scanner | `in.cashify.cashify_vision`, `in.cashify.barcode_scanner` | ML Kit + camera preview |
| Physical-inspection photos (PDD/capture) | `in.cashify.pdd`, `in.cashify.capture` | camera preview + S3 upload |

Camera2 imports in obfuscated files (e.g. `D/Z.java`) belong to these camera flows and
CameraX pipeline lambdas — **never** to the fingerprint/face test paths.

**Manifest permissions (relevant):**
`CAMERA`, `USE_BIOMETRIC`, `USE_FINGERPRINT`, `TRANSMIT_IR`, `NFC`, `RECORD_AUDIO`,
`ACCESS_FINE_LOCATION`, `READ_PHONE_STATE`, `BLUETOOTH_CONNECT`, … (full list extracted).

---

## 5. App context (what else it does)

- **Test flow is server-driven:** `in.cashify.capture.remote.Flow/Flows/RequiredConfig`
  + `MockData` shows groups: network, multimedia, sensor, device, display, location,
  camera, long_duration, capture (mirror photos), …
- **Test list:** Wi-Fi, Bluetooth, GPS/location, battery, cameras, speakers/mics,
  screen (LCD, backlight, copy-screen), multitouch, buttons, sensors (accel, gyro,
  compass, proximity, light, face_id, fingerprint), NFC, SIM/eSIM, IVR live-call
  checks (`DialerActivity` + `CallService`), stress test, OTG, SD card…
- **Output:** Exchange Reference Code / QR for pickup executive; results posted via
  Retrofit to Cashify endpoints; analytics (Firebase, AD_ID permission present).
- **Other subsystems:** WebView bridge (`cdp`), PDD photo defect detection (ML Kit),
  license/OTP modules, localization SDK, Play-Core style updates.
- **Obfuscation:** single/double-letter packages (`r`, `sa`, `d4`, `Da`…) = R8 with
  class renaming; the `in.cashify.*` business logic keeps readable names.

---

## 6. Key file map (decompiled sources)

| File | Role |
|---|---|
| `in/cashify/diagno/sensors/tests/fingerprint/FingerprintViewModel.java` | **The fingerprint test** (both paths, pre-checks, lifecycle) |
| `in/cashify/diagno/sensors/tests/faceid/FaceIdViewModel.java` | Face test (separate) |
| `in/cashify/diagno/sensors/types/SensorTestType.java` | Test IDs: `face_id`=706, `fingerprint`=707 |
| `sa/b.java` | Shared auth controller: retries, error codes → results |
| `d4/e.java` | Legacy `FingerprintManager.authenticate(...)` wrapper |
| `j2/C1394a.java` | Legacy `FingerprintManager.AuthenticationCallback` |
| `r/C1832s.java` | `canAuthenticate()` logic across API levels |
| `r/x.java`, `r/AbstractC1825l.java` | Vendored androidx.biometric → platform BiometricPrompt |
| `r/C1815b.java`, `r/C1814a.java` | Modern auth callback + result routing |
| `r/C1810J.java` | Custom fingerprint dialog (`fingerprint_dialog_layout.xml`) |
| `in/cashify/diagno/core/data/RequestMask.java` | Result keys: `FINGER_TOUCH_DIAGNOSE="fp"`, `FACE_DIAGNOSE="fid"` |
| `in/cashify/diagno/ui/base/theme/mockdata/MockData.java` | Server test-list schema (all test IDs + groups) |

---

## 7. Reproduce it yourself

```bash
# pull the XAPK/APK, then:
jadx -d cashify_out in.cashify.diagno.cec.apk
# search the fingerprint path:
grep -rn "FingerprintViewModel\|FingerprintManager.authenticate" cashify_out/sources/in cashify_out/sources/d4
```

*Static analysis only — no dynamic instrumentation was performed.*
