# FRND Maestro tests

App: `com.dating.for.all.debug` (FRND Android debug build). Maestro CLI: `C:\maestro\maestro\bin`.

## Running
- `.\run.ps1 flows\login_or_signup_check.yaml` - clears app data, launches the app via adb, runs the flow.
- `-Phone 78901xxxxx` reuses an existing number (login path); without it a random number is generated (signup path).
- `.\run.ps1` alone runs every flow in `flows\` (not subflows). `-NoClear` skips clearing app data. `-SkipOnboarding` taps "Let's Go" via adb before Maestro starts.
- Smoke test: `maestro test .maestro/`.
- Every run saves `reports\<timestamp>\<flow>\report.html` + screenshots + screen recording (`.mp4`) + `summary.csv`. Open `C:\frnd-maestro` in Android Studio to browse flows and reports.

## Test rules (always)
- **Server:** on the phone-login screen press **Volume Down** -> "Select server" -> **QA** -> **Ok**. Verify the QA radio is checked. Subflow: `flows/subflows/select_qa_env.yaml`.
- **Phone:** always `78901` + 5 random digits (10 digits).
- **OTP:** always `123456` (auto-submits after 6 digits).
- New number -> signup (`flows/subflows/signup.yaml`); existing number -> home. Home popups: `flows/subflows/home_popups.yaml`.

## Device workarounds
- No `launchApp` in flows - `run.ps1` clears data and launches the app with adb.
- If the onboarding carousel hangs Maestro, use `run.ps1 -SkipOnboarding`.
- If `inputText` hangs, use `setClipboard` + `pasteText` instead.
- Emulator: Play services 23.18 crash-loops (`StackOverflowError`) and its dialog backgrounds FRND. `run.ps1` sets `hide_error_dialogs=1`; if it gets bad, `adb reboot`.
- Git Bash: set `MSYS_NO_PATHCONV=1` before `adb shell ... /sdcard/...`, or paths get mangled.

## Screen notes
- Signup "Set Profile": `nicknameTextField`, `genderSelector` -> "I am Boy", `dobSelector` -> "Done" (defaults to exactly 18y), `submitButton`.
- Content language "Hindi" switches the UI to Hindi until the app-language screen ("English" -> `btnSetAppLanguage`).
- Declaration: tick `checkBoxPoliceDeclaration` before `btnPoliceDeclaration` (जमा करें) - the button does nothing otherwise.
- Home: `homeTopBarRoot`, `coinAmount`. Popups: Streaks video ("Okay, understood"), "CLAIM NOW", `badgeEarnedPostClaimTryLaterText`.
