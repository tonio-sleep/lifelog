# Backup and recovery

Backups are encrypted files you create yourself. You can keep them locally or,
if you opt in, sync the same encrypted blob to Cloudflare R2 through a Worker.

## Creating a backup

1. Open Settings → Backup and recovery → **Create backup**.
2. Enter a passphrase of at least 8 characters. Confirm it.
3. Choose a destination and file name. The file uses the `.lifelog` extension.

The backup is a pretty-printed JSON container:

```json
{
  "format": "lifelog-backup",
  "version": 1,
  "createdAt": "...",
  "includesMedia": false,
  "cipher": "aes-256-gcm",
  "kdf": {
    "name": "argon2id",
    "memory": 19456,
    "iterations": 2,
    "parallelism": 1,
    "salt": "..."
  },
  "payload": "base64(AES-256-GCM ciphertext)"
}
```

The payload is the encrypted JSON archive document. The key is derived from
your passphrase using Argon2id with the salt and parameters stored in the
container. The archive key is never reused for backups.

## What is included

- The entire structured archive: journal entries, media metadata, trackers and
  records, meals, timeline events, places, visits, scrobbles, check-ins,
  location samples and reminders.

## What is excluded

- **Media bytes.** Originals and thumbnails in `media/` are not included.
- Preferences in `settings.json` (theme, PIN, Last.fm username, etc.).
- The root archive key.

This means a restored backup replaces the archive but **clears the current
encrypted media vault**, because the media files no longer match the restored
records. If you need media after a restore, copy the `media/` folder
separately while the source install can still read it.

## Restoring

1. Open Settings → Backup and recovery → **Restore from backup**.
2. Select the `.lifelog` file.
3. Enter the passphrase.
4. Review the counts shown (journal entries, media records, trackers,
   tracks) and the backup's creation date.
5. Confirm. The current archive and media vault are replaced.

Restoring is destructive and cannot be undone. Create a backup of the current
archive first if you are unsure.

## Cloudflare sync

In Settings → Cloudflare you can register or sign in, then upload and download
the same encrypted backup container. The session token authenticates requests
to your Worker; the backup passphrase is used only on the device to encrypt or
decrypt the payload. It is remembered encrypted with the archive key so later
syncs and restores do not ask again, but it is never sent to the Worker or R2.
Switching accounts clears the remembered passphrase. Upload progress is shown
in Settings as the encrypted bytes stream.

## Recovery limits

- **No passphrase recovery.** Argon2id is intentionally slow; there is no reset
  path. A lost passphrase means the backup is unrecoverable.
- **No PIN recovery.** The PIN protects the running app only; it does not gate
  backups.
- **Key loss.** If the root key is lost (secure storage cleared and fallback
  file deleted), `archive.lifelog` cannot be opened. Back up the key file or
  keep a recent backup with a known passphrase.
- **Version mismatch.** A backup written by a newer format version is rejected
  rather than partially read.
- **Corruption.** A damaged or truncated backup fails authentication and is
  rejected. Keep more than one copy.

## Recommended practice

- Keep at least two backups on different media.
- Test a restore into a fresh install before relying on a backup.
- Rotate passphrases if you suspect one was exposed.
- Treat the backup passphrase like any other secret: never store it next to
  the backup file.
