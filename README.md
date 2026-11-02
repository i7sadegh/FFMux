# FFMux

A minimal, open-source video & audio downloader for Android, powered by
[yt-dlp](https://github.com/yt-dlp/yt-dlp).
UI inspired by [Seal](https://github.com/junkfood02/Seal); the in-app engine
update flow is inspired by [YTDLnis](https://github.com/deniscerri/ytdlnis).

## Features

- Paste a link or share it from any app, pick a quality, download
- Video (all available resolutions, merged video+audio) or audio-only
- Live progress list with cancel / delete / open
- Choose the download folder (default: `Downloads/FFMux`)
- Update yt-dlp from inside the app — no new APK needed
- English UI, Android 10+ (API 29), arm64-v8a only

## Build without a PC (phone + browser only)

1. Create a new **empty** repository on GitHub (for example `ffmux`).
2. Open the repo → **Code** → **Codespaces** → create a Codespace (free plan is enough).
3. Download `FFMux-project.zip` and **drag it into the Codespace file explorer**.
4. In the Codespace terminal run:
   ```bash
   unzip FFMux-project.zip -d .
   rm FFMux-project.zip
   ```
   If the zip landed outside the project folder, first run `mv ~/FFMux-project.zip .`
5. Open the **Source Control** tab, type a message like `init`, then **Commit & Push**.
6. Go to the **Actions** tab and wait for **Build APK** to finish
   (10–15 minutes the first time).
7. Open the finished run → scroll to **Artifacts** → download `FFMux-arm64-release`.
8. Unzip it and install `app-release.apk`
   (allow "install unknown apps" for your browser / file manager).

Later app updates: put the new zip into the Codespace again and push.
yt-dlp itself updates **inside the app** via Settings — no repo change needed.

## How the engine works

- `python` + `yt-dlp` + `ffmpeg` are bundled through the
  [youtubedl-android](https://github.com/yausername/youtubedl-android) library
  (`io.github.junkfood02.youtubedl-android:library` / `:ffmpeg` 0.18.1),
  packaged as `lib*.zip.so` and extracted to app storage on first launch.
- Downloads run sequentially in a foreground service; finished files are
  copied into the folder you picked (SAF) or into `MediaStore.Downloads`.
- "Check for updates" swaps the single-file yt-dlp binary in place, exactly
  like Seal and YTDLnis do.

## Tech stack

Kotlin 2.1, Jetpack Compose (Material 3, single Activity), Room, DataStore,
Coroutines, Coil, GitHub Actions CI.

## Signing

A personal release keystore is committed at `keystore/ffmux.keystore`
(alias `ffmux`, password `ffmux2026`) so every CI build has the same
signature and installs on top of previous builds. This is fine for personal
use; move the keystore out of the repo (and into GitHub secrets) before any
public distribution.

## License

GPL-3.0-or-later — see [LICENSE](LICENSE).

### راهنمای سریع فارسی

۱. یک ریپوی خالی در گیت‌هاب بسازید
۲. تب Code → Codespaces را باز کنید
۳. فایل `FFMux-project.zip` را داخل فایل‌های کداسپیس بکشید
۴. در ترمینال بزنید: `unzip FFMux-project.zip -d . && rm FFMux-project.zip`
۵. از تب Source Control تغییرات را Commit & Push کنید
۶. در تب Actions صبر کنید تا ساخت تمام شود
۷. Artifacts را دانلود و `app-release.apk` را نصب کنید
