# Reverse Engineering Report — "Device Info" Android App

**Package:** `com.ytheekshana.deviceinfo`
**App name:** Device Info: System & CPU Info
**Version analyzed:** 3.4.3.4 (versionCode 330)
**Developer:** Yasiru Nayanajith (Sri Lanka) — support@deviceinfo.app
**Source of APK:** APKPure (XAPK, split APKs)
**Tool used:** jadx 1.5.1 (decompiled 6,768 classes → 10,867 Java files)

---

## 1. High-level verdict

The app is a **single-Activity, tab-based system-instrumentation app** built with
Material Components + ViewPager2. It is **obfuscated with R8/ProGuard** (most app
classes are renamed to `sp2`, `vp2`, `q41`, …), which is why it looks opaque at
first glance. It is a legitimate, feature-rich app: mostly local reads of Android
APIs, plus **ads** (AdMob + Facebook), **analytics/crash reporting** (Firebase),
and **two outbound API calls** described below.

---

## 2. Architecture

```
SplashActivity
   └── MainActivity (single Activity)
         ├── MaterialToolbar + TabLayout + ViewPager2  (offscreen limit 2)
         │     └── 14 fragments — one per tab
         ├── OnBackPressedCallback (back → Dashboard, then "enjoy/review" prompt)
         ├── Play Core in-app-update listener (update dialog: btnLater/…)
         └── SharedPreferences: theme, temperature unit, review-request flags

MonitorService (foreground service)  → floating overlay monitors (FPS, RAM, battery…)
16 × test Activities                 → hardware self-tests
10 × tool Activities                 → utilities (see §4)
9 × widget classes + config Activities → home-screen widgets (Material You)
```

**Key internal classes (deobfuscated meaning):**

| Obfuscated | Role |
|---|---|
| `q41` | Global static data hub — every device field (RAM, battery, SOC…) stored as `static` fields |
| `j03` | Info-gathering utilities (runs `getenforce` for root/SELinux detection, etc.) |
| `va` | ViewPager2 `FragmentStateAdapter` (14 pages) |
| `xq` | "Public IP" bottom-sheet (calls api.seeip.org) |
| `b12` | Network request to the developer's spec-lookup API |

**Tech stack:** Java/Kotlin (R8-obfuscated), Material Design 3, ViewPager2,
MPAndroidChart (`info.appdev.charting`) for graphs, OkHttp, Firebase,
Play Billing, Kotlin coroutines (`defpackage` = removed package names).

---

## 3. The 14 main tabs

| # | Tab | Layout | Reads |
|---|-----|--------|-------|
| 0 | **Dashboard** | `tab_dashboard` | CPU/RAM/battery/storage gauges + ad card |
| 1 | **Device** | `tab_device` | `Build.*`, manufacture date, device age, product/sales code |
| 2 | **System** | `tab_system` | Android version/API, kernel, security patch, OpenGL/Vulkan |
| 3 | **CPU** | `tab_cpu` | Arch, cores, frequencies, per-core usage |
| 4 | **Battery** | (chart-based) | `BatteryManager` + `LineChart` history, `BatteryView` |
| 5 | **Network** | `tab_network` | Wi-Fi/mobile info, public IP sheet |
| 6 | **Bluetooth** | (adapter-based) | `BluetoothAdapter` state, paired devices |
| 7 | **Display** | `tab_display` | Resolution, density, refresh rate, HDR, screen-off timeout |
| 8 | **Memory** | `tab_memory` | RAM total/free + ad card |
| 9 | **Camera** | `tab_camera` | Camera specs (API 21+ characteristics) |
| 10 | **Thermal** | `tab_thermal` | Thermal zones / temperature |
| 11 | **Sensor** | `tab_sensor` | Full sensor list via `SensorManager` |
| 12 | **Apps** | `tab_apps` | Installed apps (uses `QUERY_ALL_PACKAGES`) |
| 13 | **Tests** | `tab_tests` | Launcher for the hardware tests |

---

## 4. Tools section (`com.ytheekshana.deviceinfo.tools`)

- `AppAnalyzerActivity` — per-app APK analysis (manifest, signatures, graphs)
- `AppDataUsageActivity` / `DataUsageActivity` — per-app data usage (`NetworkStats`)
- `AppScreenTimeActivity` / `ScreenTimeActivity` — usage stats (`PACKAGE_USAGE_STATS`)
- `CompassActivity`, `WifiAnalyzerActivity`, `PermissionActivity`
- `ExportActivity` — export full report as **TXT or PDF**

## 5. Hardware tests (16 activities in `tests/`)

Accelerometer, Automatic (full run), Bluetooth, Charging, Display (also
full-screen), Ear proximity, Ear speaker, Flashlight, Light sensor, Loudspeaker,
Microphone, Multitouch, Vibration, Volume Up, Volume Down.

---

## 6. Permissions & why they're used

| Permission | Purpose found in code |
|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE` | Public-IP sheet, ads, analytics, spec lookup |
| `ACCESS_WIFI_STATE` / `CHANGE_WIFI_STATE` | Wi-Fi analyzer |
| `ACCESS_FINE/COARSE_LOCATION` | Required by Android to read Wi-Fi SSID/BSSID |
| `CAMERA`, `FLASHLIGHT` | Camera tab + flashlight test |
| `RECORD_AUDIO` | Microphone test |
| `BLUETOOTH*` | Bluetooth tab/test |
| `READ_PHONE_STATE` | SIM/network info |
| `QUERY_ALL_PACKAGES` | Apps tab / app analyzer |
| `PACKAGE_USAGE_STATS` | Screen-time & data usage tools |
| `SYSTEM_ALERT_WINDOW` | Floating monitor overlay |
| `FOREGROUND_SERVICE(_SPECIAL_USE)` | `MonitorService` for overlay |
| `VIBRATE`, `MODIFY_AUDIO_SETTINGS` | Tests |
| `BILLING` | Optional donations (Play Billing) |
| `AD_ID` (+ AdServices) | Ads (Google Advertising ID) |
| `WRITE_EXTERNAL_STORAGE` | Saving exported reports |

---

## 7. Network behavior (everything it sends out)

1. **Device-spec lookup** — `POST https://www.deviceinfo.app/web-services/get-details-v2.php`
   Payload (JSON): only `model` (`Build.MODEL`), `codename` (`Build.DEVICE`),
   `manufacturer` (`Build.BRAND`). Request tag: `DeviceInfoRequest`, timeout 10 s.
   → Used to fetch known specs (e.g., battery capacity) for the device model from
   the developer's own database. **No personal data in the payload.**

2. **Public IP feature** — `GET https://api.seeip.org/geoip` (tag `DeviceInfoRequestIP`)
   → Displays your public IP, ISP, country, timezone in the Network tab.
   Third-party geolocation API; triggered only when that sheet opens.

3. **Ads** — Google AdMob (publisher `ca-app-pub-9823272508031979`, 6 ad units found,
   e.g. `…/8271956043` on Dashboard, `…/6183992526` on Memory) +
   Facebook Audience Network (`audience_network` assets, `com.facebook.ads`).
   Consent flow: `fundingchoicesmessages.google.com/a/consent`.

4. **Firebase** — Analytics (`app-measurement.com`), Crashlytics (crash reports,
   cached-report logic present), Firebase Installations (`firebaseinstallations.googleapis.com`).

5. **Developer site/links** — deviceinfo.app, XDA thread, social links, OneSky
   (translation strings).

**Bottom line on privacy:** the app's own code sends only device model identifiers
to its server; the heavier telemetry comes from the ad/analytics SDKs (AdMob,
Facebook, Firebase) declared in the Play Store listing.

---

## 8. How the app actually reads device info (techniques to learn from)

- **Build properties:** `Build.MODEL/BRAND/DEVICE/BOARD/FINGERPRINT/…`
- **System properties:** reflective `SystemProperties` / `getprop`-style reads
- **Shell commands:** `Runtime.exec("getenforce")` → SELinux/root check
- **Files:** `/proc`-style reads for CPU/kernel details
- **Android APIs:** `BatteryManager`, `SensorManager`, `CameraManager`,
  `DisplayManager`, `ConnectivityManager`, `NetworkStats`, `UsageStatsManager`,
  `Settings.System` (screen timeout), `BluetoothAdapter`, `TelephonyManager`
- **Aggregation pattern:** all values dumped into one static "god object" (`q41`)
  that fragments read from — simple, though not lifecycle-safe (a design smell).

---

## 9. Reproducing this analysis (tools)

```bash
# 1. Get the APK/XAPK from your phone:
adb shell pm path com.ytheekshana.deviceinfo
adb pull <path-from-above>

# 2. Decompile
jadx -d out deviceinfo.apk          # Java sources (or jadx-gui for browsing)

# 3. Resources / manifest
jadx --no-src -d res_out deviceinfo.apk

# 4. Deeper options
apktool d deviceinfo.apk            # smali + resources
dex2jar + jd-gui                     # alternative decompiler
Frida / objection                    # dynamic tracing on a device
MobSF                               # automated security/privacy scan
```

> Note: The analyzed file was an **XAPK** (base APK + config splits for arm64,
> languages). jadx unpacked the base APK automatically.

---

## 10. Findings summary

✅ **Strengths**
- Clean Material Design 3 architecture, sensible single-Activity + tabs pattern
- Huge feature set (14 tabs, 16 hardware tests, 10 tools, widgets, floating monitor)
- Its own server call is minimal (model/brand only) and on its own domain
- "No data collection" claim is *mostly* about first-party data — ad SDKs still collect IDs

⚠️ **Worth knowing**
- Heavily R8-obfuscated (normal for production apps, but nothing to "read" easily)
- Ad + Facebook + Firebase SDKs → advertising identifiers & usage telemetry
- Location permission is required only because Android gates Wi-Fi details behind it
- `QUERY_ALL_PACKAGES` lets it see all installed apps (Play Store permits this for
  app-manager/utility categories)
- Static global data hub (`q41`) = fragile design if this were your codebase to improve

*Report generated by static analysis only (jadx). No dynamic/runtime analysis was performed.*
