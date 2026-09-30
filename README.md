# Reverse-engineering-data-s

Biometric diagnostic app (**fingerprint test on Android / Face ID test on iOS**) plus the reverse-engineering work that shaped it.

## Repository map

| Path | What it is |
|---|---|
| [`apps/fingerprint_test/`](apps/fingerprint_test/) | The Flutter app — Android uses legacy `FingerprintManager` only, iOS uses `LocalAuthentication` (Face ID). Source, tests, and the full integration guide. |
| [`releases/android/`](releases/android/) | Built APK(s) + `SHA256SUMS`. |
| [`docs/`](docs/) | Install guides — e.g. [install on iPhone without a Mac](docs/INSTALL_IOS_WITHOUT_MAC.md). |
| [`research/`](research/) | Reverse-engineering reports and evidence from the Cashify Diagnose analysis. |
| [`.github/workflows/ios-ipa.yml`](.github/workflows/ios-ipa.yml) | CI: builds an **unsigned iOS .ipa** on GitHub's free macOS runner (Actions tab → Run workflow). |

## Quick start

- **Android install** → `releases/android/fingerprint_test_arm64_v1.0.0_arm64.apk` (14.8 MiB, arm64 — both target phones are arm64). **Check the file size before tapping install**; a truncated download is what caused the original “parsing the package” error.
- **iPhone install** (free Apple ID, no Mac) → [`docs/INSTALL_IOS_WITHOUT_MAC.md`](docs/INSTALL_IOS_WITHOUT_MAC.md).
- **Copy this feature into your own app** → step-by-step in [`apps/fingerprint_test/README.md`](apps/fingerprint_test/README.md).

## Design rules (identical channel contract on both platforms)

- **Android:** legacy `FingerprintManager.authenticate()` — no `BiometricPrompt`, no camera permission declared.
- **iOS:** `LAContext.evaluatePolicy()` system prompt — no camera permission declared (`NSFaceIDUsageDescription` only).
- Shared Dart UI over `fingerprint_test/methods` + `fingerprint_test/events`.
- **2 non-matching reads = FAIL** (same retry policy Cashify Diagnose uses).

## Deliberately excluded

Third-party APKs, decompiled proprietary sources, and the `jadx` tooling are **not** committed (copyright, and single files >100 MB are rejected by GitHub). The findings are in `research/`, and every analysis is reproducible with open-source `jadx`.
