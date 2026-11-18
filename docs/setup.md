# Setup and troubleshooting

## Prerequisites

- Flutter 3.47 or newer
- Dart 3.13 or newer
- Windows 10/11 with Visual Studio 2022 build tools (Desktop development with C++)
  for the Windows target
- Optional: a Last.fm API key from https://www.last.fm/api/account/create

Check your toolchain:

```powershell
flutter doctor
```

## First run

```powershell
cd C:\Users\dullb\Downloads\journal
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

On first launch Lifelog creates its data folder, generates the root key and
shows the onboarding tour. The archive starts empty.

## Data location

By default Lifelog uses the Flutter application support directory:

```text
%APPDATA%\lifelog
```

That folder contains:

- `archive.lifelog` — encrypted archive
- `settings.json` — preferences
- `master.key` — root key fallback, only if secure storage is unavailable
- `media/` — encrypted originals and thumbnails

Back up this folder (or export a backup from Settings) before reinstalling
Windows or removing the app.

## Last.fm

1. Create an API key at https://www.last.fm/api/account/create.
2. In Lifelog open Settings → Integrations → Last.fm → **Connect**.
3. Enter your username and the API key. The key is encrypted before it is
   stored.
4. Press **Sync** to import recent tracks.

Only your username and API key are stored. The shared secret is never needed
and must not be entered. Listening history depends on your scrobbling setup;
missing music means missing data.

## Building

Debug build:

```powershell
flutter build windows --debug
```

Release build:

```powershell
flutter build windows --release
```

The executable is written to `build\windows\x64\runner\Release\lifelog.exe`.

## Troubleshooting

### `flutter analyze` reports missing plugins

Run `flutter pub get` again. If the error persists, delete
`.dart_tool/` and `build/` and rerun.

### The archive cannot be opened

The root key may have changed (for example after reinstalling the OS) or the
file may be damaged. Do not delete `archive.lifelog`. Copy the whole data
folder somewhere safe, then create a fresh install and restore from a backup.
If you still have `master.key`, keep it with the archive.

### Secure storage is unavailable

On some Windows configurations `flutter_secure_storage` cannot read or write.
Lifelog falls back to `master.key` and Settings shows
`Local key file (platform secure storage unavailable)`. This is usable but
weaker; see [privacy-model.md](privacy-model.md).

### Media files will not import

- Files larger than 250 MB are rejected.
- Very large images may fail thumbnail generation; the original is still
  imported.
- Imports are cancelled if you close the details dialog.

### The app shows the unlock screen every time

A PIN is enabled. Enter it, or remove it from Settings after unlocking. If
you forgot the PIN, remove the app's local data folder and start again. The
PIN never protects the archive key, so the archive file itself is unaffected.

### Performance with large archives

The whole structured archive is held in memory and persisted as one document.
Hundreds of thousands of records will slow startup and saves. This is a known
limit of the current design.
