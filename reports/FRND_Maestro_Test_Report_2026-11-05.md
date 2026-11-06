# FRND Android – Maestro Automation Report

**Date:** 5 Nov 2026  
**App:** `com.dating.for.all.debug` v2.368.0 (QA debug build)  
**Device:** Android 14 emulator (`emulator-5554`)  
**Tool:** Maestro CLI 2.12.1, driven by `run.ps1`  
**Project:** `C:\frnd-maestro` (open the folder in Android Studio to view flows and reports)

---

## 1. Summary

| Area | Status |
|---|---|
| Smoke test (app launches to login screen) | ✅ Passing |
| QA server selection (Volume Down → Select server → QA → Ok) | ✅ Passing in automation |
| Phone login with `78901XXXXX` + OTP `123456` | ✅ Passing in automation |
| New-user signup (Set Profile form) | ✅ Passing in automation |
| Signup → language → declaration → home | ✅ Verified manually · 🔄 automation rerun in progress (permission popup fix) |
| Existing-user login → home | ⏳ Pending (number `7890131746` ready to reuse) |
| Visible / Hosting flows | ⏳ Not started yet |

---

## 2. Login / signup flow (as automated)

1. **Launch:** `run.ps1` clears app data and opens the app with adb (no `launchApp`).
2. **QA server:** Volume Down opens the debug menu, then Select server → **QA** → **Ok**. The flow asserts that the QA radio button is checked.
3. **Phone:** a random `78901` + 5-digit number, then **Get OTP**.
4. **OTP:** `123456` (auto-submits).
5. **Branch:**
   - **New number → signup:**
     - Set Profile: nickname `qatest<last5>`, gender *I am Boy*, date of birth (default: exactly 18 years ago), Submit.
     - Content language: Hindi.
     - Declaration: tick the checkbox, then **जमा करें**.
     - App language: English.
   - **Existing number:** goes straight to home.
6. **Home:** dismiss the popups (Streaks video "Okay, understood", **CLAIM NOW**, "I will try later", system permission prompts, Chat Bubbles **NOT NOW**), then assert `homeTopBarRoot` and `coinAmount`.

Any Android permission dialog (notifications, location) is always answered with **Allow / While using the app**.

### Test accounts created on QA
| Phone | Type |
|---|---|
| 7890131746 | Male, signed up manually → home ✅ |
| 7890119308 | Male, created by automation run (reached Set Profile submit) |

---

## 3. Issues found and fixes

| # | Issue | Impact | Fix / workaround |
|---|---|---|---|
| 1 | **Google Play services crash-loop on the emulator** (`StackOverflowError` in `SharedLibraryInfo`, GMS 23.18.18). Android killed FRND because it depends on the dying GMS provider. | App closed right after **Get OTP** and after the declaration screen. | Cleared GMS data, rolled Chrome/WebView back to factory versions (removed the Trichrome static library), and rebooted. No GMS crashes since. `run.ps1` also hides system crash dialogs. |
| 2 | **Onboarding carousel never settles.** Maestro waits for the UI to stop moving after each tap. | One tap on "Let's Go" took **38 minutes**. | Added `waitToSettleTimeoutMs: 500` to taps on the login screens. Taps now take about 1–3 s. **Dev request:** a debug switch to disable carousel auto-scroll. |
| 3 | **Notification permission dialog** appears late on a fresh install and swallows the Volume Down key press. | Debug menu didn't open. | Retry loop: Allow (if shown) → Volume Down, until "Select server" is visible. |
| 4 | **Location permission dialog** after Set Profile submit. | Signup stopped before the language screen. | Permission subflow now also taps "While using the app". |
| 5 | **Declaration "जमा करें" does nothing until the checkbox is ticked** (`checkBoxPoliceDeclaration`). The notification permission dialog can also pop up over this screen and block the tap. | Signup appeared stuck. | Flow allows any popup, then taps the checkbox until it reports checked, then submits. |
| 6 | **The content-language choice switches the UI to Hindi** until the app-language screen. | Text-based selectors break. | Flow uses resource IDs on those screens. |
| 7 | Phone field kept stray text from the previous attempt. | 11-digit number, so OTP was not sent. | `eraseText` before typing; assert the field equals the generated number. |

---

## 4. Files

```
C:\frnd-maestro
├── CLAUDE.md                         rules: QA via Volume Down, 78901 numbers, OTP 123456, device workarounds
├── run.ps1                           runs flows; saves HTML report + screenshots + video per run
├── .maestro\smoke.yaml               smoke test
├── flows\login_or_signup_check.yaml  main check (QA → login/signup → home)
├── flows\subflows\
│   ├── select_qa_env.yaml
│   ├── login_or_signup.yaml
│   ├── signup.yaml
│   ├── home_popups.yaml
│   └── allow_notifications.yaml      (grants any runtime permission)
└── reports\<timestamp>\<flow>\report.html, screenshots, recording .mp4, summary.csv
```

**Run:**
- `.\run.ps1 flows\login_or_signup_check.yaml` — signup with a new number.
- `.\run.ps1 flows\login_or_signup_check.yaml -Phone 7890131746` — login with an existing number.

---

## 5. Next steps
1. Get the login/signup check to pass twice in a row: once as signup, once as login.
2. Build the **Visible** and **Hosting** flows. Hosting is likely female-only, so it may need a "Girl" signup.
3. Add these flows to the full suite (`.\run.ps1` runs everything in `flows\`).
