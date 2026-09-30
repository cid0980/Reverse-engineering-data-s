# Install the iOS build WITHOUT a Mac (and without a paid developer account)

You only have a regular (free) Apple ID and no Mac. That is enough — a free
Apple ID can sign and install apps on your own iPhone (install expires after
**7 days**, max **3 apps** at a time — we only use 1). The only catch: iOS
apps must be *built* with Xcode on macOS somewhere. We rent GitHub's Macs for
free instead of yours.

```
┌──────────────┐   push    ┌──────────────────────────┐  download .ipa  ┌────────────────┐
│ Any computer │ ────────► │ GitHub Actions (free     │ ──────────────► │ Your Windows PC│
│ (Linux OK)   │           │ macOS runner, ~10 min)   │                 │ + USB cable    │
└──────────────┘           └──────────────────────────┘                 └───────┬────────┘
                                                                               │ Sideloadly /
                                                                               │ 3uTools signs
                                                                               │ with YOUR free
                                                                               │ Apple ID →
                                                                               ▼
                                                                       ┌────────────────┐
                                                                       │ iPhone: app +  │
                                                                       │ Face ID test   │
                                                                       └────────────────┘
```

**You need:** a GitHub account (free), a computer with a USB port for ~10
minutes (yours or a borrowed Windows laptop — this is the ONLY step needing
a computer besides the first push), an iPhone cable, and your Apple ID.

---

## Step 1 — Put the project on GitHub (any OS, one time)

```bash
cd apps/fingerprint_test
git remote add origin https://github.com/YOUR_USERNAME/fingerprint_test.git
git push -u origin master   # branch may be 'main' — check with: git branch
```

Create the empty repo on github.com first (no README/license, so push works).
Building starts automatically; or run it manually: **Actions → Build unsigned
iOS IPA → Run workflow**.

> Repo can be **public** (unlimited free build minutes) — the code is just a
> demo test app. Private repos also work (~10 free builds/month).

## Step 2 — Download the .ipa (~10 min later)

GitHub → your repo → **Actions** → green check → **fingerprint_test_ipa**
→ download `fingerprint_test_unsigned.ipa`.

## Step 3 — Sign + install on your iPhone (Windows, ~5 minutes)

Option A — **Sideloadly** (simplest):

1. On the Windows PC install **iTunes** (Microsoft Store) + **Sideloadly**
   (https://sideloadly.com).
2. Connect the iPhone with the USB cable → unlock → tap **Trust**.
3. Open Sideloadly → drag in `fingerprint_test_unsigned.ipa` → enter your
   **Apple ID email** (the free one) → **Start**.
4. On the iPhone: **Settings → General → VPN & Device Management → your
   Apple ID → Trust** → launch **Fingerprint Test**.

Option B — **3uTools** (very common in India): Device tab → **Import IPA →
Signature** → sign with Apple ID → install. Same result.

Option C — **AltServer** (AltStore): after the first USB install, AltStore
can refresh the app over Wi-Fi from the phone itself, so future weekly
renewals may not need the PC at all.

## Step 4 — Verify the Face ID test

Title shows **"Face ID Test"** → chips: Hardware ✔ Enrolled ✔ → **Start
test** → system Face ID prompt → look with enrolled face → **PASS**.
Wrong face twice → FAIL. Cancel → "Test stopped."

## Weekly renewal (free account limit)

After 7 days the app stops opening (Apple's rule for free accounts). Fix:
reconnect the phone to the PC, open Sideloadly, select the same .ipa,
**Start** again — 30 seconds, no rebuild. (Only rebuild on GitHub when the
code changes.)

## If you truly have NO computer at all

A computer must touch the phone once — no way around Apple's rules for free
accounts. Your options:

1. **Borrow any Windows laptop for 10 min** (best) — then weekly 30 s.
2. **Save for the paid Apple Developer account ($99/yr)** → **TestFlight**:
   install and update entirely from the phone, no computer ever again.
3. If your iPhone runs **iOS 16.6.1 or older**, research **TrollStore** —
   a permanent installer (one-time computer step, then never again).
   Not possible on newer iOS.

## ⚠️ Security warning

Never type your Apple ID password into random websites, Telegram bots, or
"online IPA signing" services — that is how accounts get physically stolen.
Only desktop tools above (Sideloadly/3uTools/AltServer) or Xcode should ever
see your Apple ID, and Apple will show a 2FA code you control.

## Free-account limits (recap)

- Install validity: **7 days** (renew by re-signing)
- Max **3 apps** installed at once (we use 1)
- Max **10 new app IDs per week** (irrelevant at this scale)
