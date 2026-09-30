# Research

Reverse-engineering reports from this workspace. **Analysis only** — no third-party
app binaries or decompiled source trees are committed here (proprietary code, and
GitHub rejects single files >100 MB). Both analyses used open-source `jadx` and are
fully reproducible with the steps at the bottom.

## Contents

- **[`cashify/CASHIFY_RE_REPORT.md`](cashify/CASHIFY_RE_REPORT.md)** —
  Cashify Diagnose (`in.cashify.diagno.cec`, v3.1.11, APKPure) — the fingerprint
  deep-dive that shaped this repo's app: `authLegacy()` calls legacy
  `FingerprintManager.authenticate()` (fingerprint HAL only, zero camera), manifest
  evidence, dex strings, error-code table.
- **[`device-info/REVERSE_ENGINEERING_REPORT.md`](device-info/REVERSE_ENGINEERING_REPORT.md)** —
  Device Info (`com.ytheekshana.deviceinfo`, v3.4.3.4) — earlier RE pass: structure,
  permissions, notable components.
- **[`evidence/39MB-truncated-download-error-screenshot.jpg`](evidence/)** —
  MIUI file manager showing the truncated 39.3 MB download (real APK = 42.3 MB) that
  caused *"There was a problem while parsing the package."* — the reason the released
  APK here is a small arm64-only build with a checksum.

## Reproduce any analysis

```bash
# 1. obtain the APK yourself (e.g. APKPure)   2. decompile:
jadx -d out app.apk          # github.com/skylot/jadx  (not vendored: 111 MB > GitHub limit)
# 3. start from the launcher activity / auth entry points named in each report
```
