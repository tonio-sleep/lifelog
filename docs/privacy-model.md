# Privacy model

Lifelog is local-first. Its privacy claims are deliberately narrow so they can
be checked against the code and the network.

## What is encrypted at rest

- `archive.lifelog`: the entire structured archive (journal, trackers, records,
  places, visits, music, events, media metadata) is AES-256-GCM encrypted as
  one document.
- `media/*.bin` and `media/*.thumb.bin`: each original and thumbnail is
  encrypted individually with AES-256-GCM. File names are random UUIDs; the
  original file name is not written to disk.
- Backups: encrypted with a separate key derived from the backup passphrase.

## What is not encrypted

- `settings.json` contains preferences and the Last.fm username. It does not
  contain journal text, media bytes or tracker values. It does contain the
  Last.fm API key, encrypted with the archive key and a separate AAD.
- The PIN salt and hash.
- The application support directory name and file layout.
- Anything displayed on screen while the archive is unlocked.

## Root key handling

1. Lifelog first tries platform secure storage (`flutter_secure_storage`) to
   read or write a 32-byte key.
2. If that fails, it uses `master.key` in the data folder, base64-encoded.
   This fallback is weaker and is shown in Settings as
   `Local key file (platform secure storage unavailable)`.
3. The key is never derived from a password and never leaves the device.

## PIN

The optional PIN is a convenience lock for the running app:

- Stored as a salted Argon2id hash in settings.
- Verified in memory; no attempt counter is kept.
- There is no recovery. Forgetting it means removing the app's local data.
- The PIN does **not** replace or harden the archive key. It only hides the UI.

## Network traffic

- There is no analytics, crash reporting, update check, cloud sync, account
  system or map tile service.
- The only optional outbound request is Last.fm's `user.getrecenttracks`, made
  only when you connect an account and press sync. It sends your username and
  API key to Last.fm. Your archive is never sent.
- The map is a local canvas. It does not request tiles and does not send
  coordinates to any provider.
- Background location is not collected. A location fix happens only when you
  press the button in a place editor, and the result is stored locally.

## Threat model

Lifelog protects against:

- casual access to the device's storage
- offline inspection of `archive.lifelog` or media files without the key
- tampering with stored ciphertext (AES-256-GCM authentication)

Lifelog does **not** protect against:

- a running, unlocked session
- a compromised operating system or a malicious process on the same machine
- physical access while the app is unlocked
- a forgotten backup passphrase or PIN
- loss of the device together with its fallback key file
- side channels and memory forensics on a hostile machine

## Media

Originals and thumbnails are encrypted individually. Captions, tags, dimensions
and the creation timestamp live in the encrypted archive, so they are not
readable from the file system either. Deleting media deletes the encrypted
files.

## Backups

Backups use a separate key derived from the backup passphrase with Argon2id, so
the archive key is never reused. Media bytes are excluded in this build. See
[backup-and-recovery.md](backup-and-recovery.md).

## Honest limits

Lifelog's privacy is a property of its storage and network behaviour, not a
marketing claim. Every statement above can be verified from
`lib/core/crypto`, `lib/core/storage` and `lib/integrations/lastfm`.
