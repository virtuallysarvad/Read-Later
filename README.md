# Read Later

A Pocket-inspired read-later app for Android, built with Flutter.

- **Save anything** — share a link to Read Later from any app, or paste a URL.
- **Ad-free reading** — articles are extracted **on-device** with a Dart port of
  [Mozilla's Readability](https://github.com/mozilla/readability), so navigation,
  ads and clutter are stripped before anything is stored. Works offline.
- **Listen like a podcast** — the Android TTS engine reads articles aloud
  paragraph by paragraph with play/pause, skip, and playback-speed controls.
  The current paragraph is highlighted and auto-scrolled, and your position is
  saved so you can resume later. While playing, a **media notification** with
  play/pause, skip and a seek bar appears — including **lock-screen controls**
  (`audio_service`), and playback keeps running in the background.
- **Google Drive backup** — the library syncs to a private *"Read Later Backup"*
  folder in your own Google Drive (no third-party server).
- Favorites, archiving, search, read-progress tracking, light/dark themes.

## Getting started

```bash
flutter pub get
flutter run
```

### JDK note

Gradle 8.14 cannot run on the Java 25 runtime bundled with Android Studio. The
project's `android/gradle.properties` points Gradle at the JDK 24 installed on
this machine (`org.gradle.java.home`). If you build on another machine, adjust
that line or set `JAVA_HOME` to a JDK 21–24. `kotlin.jvm.target.validation.mode=warning`
is set because the `receive_sharing_intent` plugin mixes JVM targets under newer JDKs.

## Saving articles

1. In any app, tap **Share** and pick **Read Later** (a "text/plain" share).
2. Or open the app, tap **+**, and paste a link.
3. The app fetches the page, extracts the readable content, and saves it.

## Google Drive backup (optional)

Backup/restore lives in **Settings → Backup**. It uses the `drive.file` scope,
so Read Later can only see the folder and file it creates.

To enable sign-in you must register an OAuth client ID for this app:

1. In [Google Cloud Console](https://console.cloud.google.com), create a project
   (or reuse one) and enable the **Google Drive API**.
2. Go to **APIs & Services → Credentials → Create credentials → OAuth client ID**,
   choose **Android**, and enter:
   - Package name: `com.readlater.read_later`
   - SHA-1 signing certificate fingerprint. For the debug build it is the
     debug keystore's fingerprint:
     ```bash
     keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android
     ```
     (Add the release keystore's fingerprint too when you ship.)
3. Save, then reinstall the app on the device. **Back up now** uploads a
   `read_later_backup.json`; **Restore** downloads it and merges by URL, keeping
   the newer copy of each article (local-only articles are never deleted).

## Architecture

```
lib/
├── main.dart                  # entry point; wires up the Android share sheet
├── app.dart                   # providers + MaterialApp (theme, navigation)
├── models/article.dart        # Article model (statuses, JSON/DB serialization)
├── data/
│   ├── app_database.dart      # sqflite schema
│   └── article_repository.dart# ChangeNotifier store: CRUD, upsert-by-URL, merge
├── services/
│   ├── article_extractor.dart # fetch + Readability extraction + URL absolutizing
│   ├── tts_service.dart       # podcast-style TTS: segments, position, speed
│   └── drive_sync_service.dart# Google Drive backup/restore
├── screens/                   # home, add-article, reader, listening, settings
├── widgets/                   # article card, mini player bar
├── theme/app_theme.dart       # Material 3 theme (Pocket red, serif reader text)
└── utils/text_chunker.dart    # splits articles into paragraphs/TTS segments
```

- **Reading** — the reader renders the extracted HTML with
  `flutter_widget_from_html`, tracks scroll progress, and shows a mini player.
- **Listening** — text is chunked into ~350-character segments; each segment is
  spoken and then the next starts, mirroring Pocket's Listen feature. Progress
  (character offset + segment index) is persisted per article.
- **Storage** — all data lives in a local SQLite database; Drive is only a
  backup/restore channel.

## Tests

```bash
flutter test
```

Covers the text chunker, on-device extraction (incl. ad-stripping and the
metadata fallback), and the repository (persistence, upsert-by-URL, backup
merge, JSON round-trip).

## Roadmap ideas

- Download article images for fully offline reading
- Background playback / notification controls (media session)
- Tags and text search over full content
- Auto-sync on article save
