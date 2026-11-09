# Folio

An open-source, privacy-first e-reader for personal use. Folio is built as a Kindle-style reading experience you own and control: your books stay on your devices, with no account lock-in and no cloud reading history you did not choose to sync.

## Goals

- Read common ebook formats (EPUB first; more formats over time)
- Keep your library local by default
- Comfortable reading: typography, themes, progress, bookmarks, and highlights
- Optional private sync later, under your control
- Android first, distributed as a personal sideloaded APK

## Status

Working Android app: library (imported files and indexed folders), offline EPUB reader (foliate-js in a WebView, themes, font size, table of contents, bookmarks, resume), and catalog browsing/downloading from a configurable OPDS source, Project Gutenberg, Standard Ebooks, and Open Library. See [docs/plan.md](docs/plan.md) for the architecture.

## Layout

- `apps/folio_android` - the Flutter Android app (shell, screens, storage channel)
- `packages/folio_core` - library store, EPUB metadata, offline reader
- `packages/folio_catalog` - pure-Dart OPDS / Open Library catalog clients

## Build

Requires Flutter 3.47+, JDK 17, and the Android SDK (compileSdk 36).

```sh
cd apps/folio_android
flutter pub get
flutter build apk --release
```

Release builds are signed with the keystore described in `apps/folio_android/android/key.properties` (gitignored):

```properties
storeFile=C:/Users/you/.folio/folio-release.jks
storePassword=...
keyAlias=folio
keyPassword=...
```

Without that file, release builds fall back to the debug key. Keep the keystore and its password backed up: Android only accepts updates signed with the same key.

## Install

Copy `apps/folio_android/build/app/outputs/flutter-apk/app-release.apk` to the phone and open it (allow "install unknown apps" for your file manager), or with USB debugging:

```sh
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## Adding books

- **Library > Import** picks a single EPUB, which is copied into app storage.
- **Settings > Library folders** adds a folder (e.g. Downloads/Books); EPUBs there are indexed in place and rescanned on launch and pull-to-refresh.
- Opening or sharing an `.epub` to Folio from another app imports it.
- **Settings > Primary catalog** takes any standard OPDS feed URL.

## License

MIT — see [LICENSE](LICENSE).

## Contributing

This project is open source and intended for private, personal libraries. Issues and pull requests are welcome once the first reading flow lands.
