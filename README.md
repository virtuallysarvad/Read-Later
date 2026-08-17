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
- **File backup** — export your library to a JSON file (and restore it)
  through the Android native files app; you decide where it lives.
- **Auto backup** — optionally save a JSON backup automatically every
  12 hours, 24 hours, 1 day or 15 days (Settings → Backup → Auto backup).
  The periodic backup runs in the background via Android WorkManager, even
  when the app is closed, and lands in the app's external storage.
- Favorites, archiving, search, read-progress tracking, light/dark themes.
- **Simple theming** — **Light**, **Dark** (Pocket red palette) or
  **Dynamic** (follows your system's Material You colors and light/dark mode),
  selectable in **Settings → Appearance**. Bold black text in light mode,
  bold white text in dark mode.

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

## File backup

Backup/restore lives in **Settings → Backup**. No account or permissions are
needed:

- **Back up** opens the Android native files app where you choose the location
  (e.g. Downloads, or Google Drive if you have it) and saves a
  `read_later_backup.json`.
- **Restore** opens the files app to pick a backup file. It merges by URL,
  keeping the newer copy of each article — local-only articles are never
  deleted.
- **Auto backup** saves the same JSON automatically at the frequency you pick
  (12 hours, 24 hours, 1 day or 15 days). The task is scheduled with Android
  WorkManager, so it runs even when the app isn't open, and writes
  `read_later_auto_backup.json` to the app's external files directory. The
  **Back up now** button runs it immediately; the last backup time and article
  count are shown below the picker.

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
│   └── backup_service.dart    # JSON export/import via the native file picker
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
- **Storage** — all data lives in a local SQLite database; backups are JSON
  files the user saves/opens through the native files app.

## Tests

```bash
flutter test
```

Covers the text chunker, on-device extraction (incl. ad-stripping and the
metadata fallback), the repository (persistence, upsert-by-URL, backup merge,
JSON round-trip), the theme system, and app-level provider wiring.

## Roadmap ideas

- Download article images for fully offline reading
- Tags and text search over full content
