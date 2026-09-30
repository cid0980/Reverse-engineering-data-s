# Fingerprint-Only Test App (Flutter)

A single-feature Flutter app that tests the phone's **fingerprint sensor alone** —
**no camera, no face, no unified BiometricPrompt**. Built as a *reference implementation*
you can copy into your own Flutter app.

```
✅ flutter analyze   → No issues found
✅ flutter test      → 3/3 widget tests passed
✅ flutter build apk → build/app/outputs/flutter-apk/app-debug.apk
✅ APK verified      → USE_FINGERPRINT declared, CAMERA NOT declared
```

---

## 1. Why your Flutter app couldn't do "fingerprint only"

| What you probably tried | Why it fails |
|---|---|
| `local_auth` plugin | It calls androidx **`BiometricPrompt`** — the *unified* system prompt. It listens to **every enrolled biometric at once** (fingerprint + face). If the user enrolled face unlock, the system may engage the **camera** stack in the same prompt — and **Android has no API to say "fingerprint only"** through BiometricPrompt. |
| Thinking it's an Android rule | It isn't. Camera and fingerprint are separate APIs, permissions, and HALs. The coupling you saw is an *artifact of BiometricPrompt's unified design*, not a platform rule. |

**The trick used by production apps** (verified by reverse-engineering
*Cashify Diagnose* `in.cashify.diagno.cec` — its `authLegacy()` path):

```kotlin
// Talks DIRECTLY to the fingerprint HAL. No system dialog, no face, no camera.
fingerprintManager.authenticate(
    null,                // CryptoObject (null is fine for a hardware test)
    cancellationSignal,  // allows cancellation
    0,                   // flags
    callback,            // success / failed / help / error
    handler              // main thread
)
```

`FingerprintManager` is deprecated (API 28) but **fully functional on current Android**
— Cashify ships it in production in 2026. The app never declares
`android.permission.CAMERA`, so a camera call is *impossible* from this code path.

---

## 2. Project layout (what matters)

```
fingerprint_test/
├── lib/
│   ├── main.dart                     # app entry
│   ├── fingerprint_test_channel.dart # Dart side of the platform channels
│   └── fingerprint_test_page.dart    # the whole feature: UI + state machine
├── test/
│   └── fingerprint_test_page_test.dart  # 3 widget tests (happy path, retry policy, error)
└── android/app/src/main/
    ├── AndroidManifest.xml           # + USE_FINGERPRINT (NO CAMERA)
    └── kotlin/com/example/fingerprint_test/
        ├── MainActivity.kt           # registers the plugin
        └── FingerprintTestPlugin.kt  # ★ the fingerprint-only engine
```

### Channel API

**MethodChannel `fingerprint_test/methods`**

| method | argument | returns |
|---|---|---|
| `getInfo` | – | `{hasHardware, isHardwareDetected, hasEnrolled, sdkInt}` |
| `startTest` | – | `null` (events arrive on the stream) |
| `stopTest` | – | `null` |
| `openEnrollmentSettings` | – | `null` (jumps to system enrollment UI) |

**EventChannel `fingerprint_test/events`** → `{type, code, message}` where `type` is:

| type | meaning |
|---|---|
| `listening` | sensor armed, waiting for a finger |
| `help` | recoverable hint (dirty/slow/fast finger) |
| `failed` | read a fingerprint, no match → UI allows 1 retry (Cashify policy) |
| `success` | matched → **PASS** |
| `stopped` | cancelled by the app/user |
| `error` | `100` no hardware · `101` nothing enrolled · `7`/`9` lockout · `5` canceled · other = raw FingerprintManager error codes |

---

## 3. Adding this feature to YOUR Flutter app

1. **Copy the Kotlin files** into your app:
   `android/app/src/main/kotlin/<your/package>/FingerprintTestPlugin.kt`
   (keep the `package` line matching *your* app's package).

2. **Register it** in your existing `MainActivity`:

   ```kotlin
   class MainActivity : FlutterActivity() {
       private var fp: FingerprintTestPlugin? = null

       override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
           super.configureFlutterEngine(flutterEngine)
           fp = FingerprintTestPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
       }

       override fun onDestroy() {
           fp?.dispose(); fp = null
           super.onDestroy()
       }
   }
   ```

3. **Manifest** — add next to your `<application>` tag (nothing else!):

   ```xml
   <uses-permission android:name="android.permission.USE_FINGERPRINT"/>
   ```

   Do **not** add CAMERA for this feature. `USE_FINGERPRINT` is a *normal*
   (install-time) permission — no runtime dialog.

4. **minSdk ≥ 23** (Android 6.0). Flutter's default (24) already satisfies this.

5. **Copy the two Dart files** (`fingerprint_test_channel.dart`,
   `fingerprint_test_page.dart`) into your `lib/` and either show
   `FingerprintTestPage` as a screen or lift the pattern into your own widget:
   - subscribe `channel.events` → update your state on each event type
   - call `startTest()` when the user taps your "test" button
   - PASS on `success`; allow one retry on `failed` (policy in
     `_maxFailedMatches`); treat `error 101` as "enroll first" and 7/9 as lockout.

6. **No third-party packages needed** — pure `flutter/services.dart`.

---

## 4. Test behaviour (mirrors Cashify Diagnose)

- Pre-checks: feature flag → `isHardwareDetected()` → `hasEnrolledFingerprints()`
- On non-match: retry **once** (2nd non-match ⇒ FAIL) — same as Cashify's `sa/b` controller
- Lockout (7/9) ⇒ FAIL with "wait 30 s" message
- No enrollment ⇒ friendly error + button opening system enrollment settings
- Stop button cancels via `CancellationSignal` (→ `stopped` event)

## 5. Honest caveats

- `FingerprintManager` is **deprecated**. It works today (production apps rely on it),
  but for a Google Play release review Google's current biometric-auth guidance and be
  ready to migrate. There is *no* drop-in replacement that is guaranteed fingerprint-only —
  that's the Android limitation this app documents.
- `BiometricPrompt` with `setAllowedAuthenticators(BIOMETRIC_STRONG)` *usually* behaves as
  fingerprint-only (many OEM faces are only "weak"), **but not on Class-3 face devices**
  (e.g., Pixel face unlock) — so it cannot guarantee "no camera".
- Runtime verification needs a physical device with a fingerprint sensor:
  `flutter run` → Start test → touch the sensor. `adb install` the debug APK and check
  `adb logcat | grep -i camera` — you'll see the camera stack stays silent while the
  fingerprint test runs.

## 6. Commands

```bash
flutter analyze      # static check
flutter test         # 3 widget tests
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

---

## iOS support (Face ID / Touch ID)

### What Cashify does on iOS (reverse-engineering notes)

- **Android APK** (decompiled earlier): uses the legacy
  `FingerprintManager.authenticate()` path (`authLegacy`) — fingerprint HAL
  only, zero camera.
- **iOS app** ("Cashify Diagnose", App Store id 1575706806, by Refurbind
  Private Limited): the public test list is *Automated: GPS, Camera,
  Bluetooth, Speaker/Microphone, Wi-Fi — Assisted: Multitouch, Screen Lock
  Key, Volume Key*. **No Face ID test is advertised** on iOS. (Their iOS
  binary is FairPlay-encrypted and only obtainable through an Apple ID, so
  deeper binary RE wasn't performed.)
- On iOS there is exactly **one** Apple-sanctioned way to check Face ID:
  `LocalAuthentication` / `LAContext.evaluatePolicy(...)`. That is what this
  implementation uses — identical to how every iOS app (banking apps, 1Password,
  …) verifies Face ID.

### Why this is still "no camera"

The Android version deliberately avoids `BiometricPrompt` (which can engage
the face stack/camera) and uses `FingerprintManager` only. On iOS the mirror
rule is:

- The app calls `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`.
- The **system** drives the TrueDepth/secure-enclave prompt.
- The app **never** opens the camera: no preview, no frames, no photo/video,
  and `NSCameraUsageDescription` is deliberately absent. Face ID works
  without any camera permission — only `NSFaceIDUsageDescription` (a usage
  string, not a permission) is required, and it is already in
  `ios/Runner/Info.plist`.

### Files added/changed for iOS

| File | Purpose |
|---|---|
| `ios/Runner/AppDelegate.swift` | `FingerprintTestPlugin` (Swift) — same MethodChannel/EventChannel contract as the Kotlin plugin |
| `ios/Runner/Info.plist` | `NSFaceIDUsageDescription` (mandatory for Face ID) |
| `lib/fingerprint_test_channel.dart` | adds `biometryType` (`faceID`/`touchID`/`opticID`) to `getInfo` |
| `lib/fingerprint_test_page.dart` | platform-aware wording/icons (Face ID vs fingerprint) |

Channel contract (identical on both platforms):

- `fingerprint_test/methods`: `getInfo`, `startTest`, `stopTest`,
  `openEnrollmentSettings`
- `fingerprint_test/events`: `{type, code, message}` with
  `type ∈ listening | help | failed | success | error | stopped`
- App error codes: `100` no hardware, `101` not enrolled, `102` passcode not
  set (iOS), `103` lockout (iOS). Two `failed` reads = FAIL (same Cashify
  retry policy as Android).

### Building — requires macOS + Xcode (Apple's toolchain is macOS-only)

```bash
# on a Mac with Xcode 15+ installed (App Store or developer.apple.com)
cd fingerprint_test
flutter doctor -c            # check: "Xcode" and "iOS toolchain" green
flutter build ios --release  # or just: flutter run (debug)
```

### How to install & check it on an iPhone

**Option A — Simulator (no Apple ID, no device) — quickest logic check**

1. `flutter run` (or Xcode ▸ open `ios/Runner.xcworkspace` ▸ pick an iPhone
   simulator ▸ Run).
2. In the Simulator menu: **Features ▸ Face ID ▸ Enrolled**.
3. Tap **Start test** in the app, then **Features ▸ Face ID ▸ Matching Face**
   → app must show *PASS*; **Non-matching Face** twice → *FAIL*.

**Option B — Real iPhone with a FREE Apple ID (7-day install)**

1. Mac: Xcode ▸ **Xcode ▸ Settings ▸ Accounts ▸ +** → sign in with your
   Apple ID (no $99 needed).
2. Select the `Runner` project ▸ **Signing & Capabilities** tab ▸
   *Automatically manage signing* ✔ ▸ **Team**: "Your Name (Personal Team)".
3. Plug the iPhone in (tap **Trust** on the phone). In Xcode's device
   dropdown pick your iPhone, press **Run** (▶) — or run `flutter run -d <device>`.
4. First run on the phone: **Settings ▸ General ▸ VPN & Device Management ▸
   developer certificate ▸ Trust** (Enter phone passcode → Trust).
5. ⏱ Free accounts expire the install after **7 days** — rebuild/re-run once
   a week (AltStore/Sideloadly can auto-refresh if you don't want to rebuild).

**Option C — TestFlight / App Store (paid Apple Developer, $99/yr)**

`flutter build ipa` ▸ Xcode ▸ Organizer ▸ Distribute ▸ TestFlight — install
on any device via the TestFlight app (1-year certificates, no weekly refresh).

> There is **no way to build/install an iOS app from Linux or Windows
> alone** — Xcode (macOS) is mandatory. Borrow/rent a Mac for option B.

### Checking that Face ID really works

1. Open **Fingerprint Test** on the iPhone (title becomes "Face ID Test").
2. Chips must show: Hardware ✔ Enrolled ✔ iOS <version>.
3. **Start test** → the **system** Face ID prompt appears (this is the test).
4. Look at the phone with an enrolled face → **PASS — Face ID is working.**
5. Cancel → *Test stopped*; use a non-enrolled face twice → **FAIL**.
6. If chips show Enrolled ✖ → **Settings ▸ Face ID & Passcode ▸ Set up Face ID**,
   then retry.

### iOS notes

- `stopTest` cannot dismiss the system prompt (Apple has no cancel API) —
  the user dismisses it with **Cancel**, which emits `stopped`.
- Minimum iOS: 15.0 (Flutter template default). Face ID devices: iPhone X
  and later; Touch ID devices get the same test with fingerprint wording.
