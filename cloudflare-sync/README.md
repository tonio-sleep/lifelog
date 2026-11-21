# Lifelog Cloudflare Sync Worker

Cloudflare Worker + R2 backend for Lifelog cloud login and encrypted backup sync.

## Security model

- **Client-side encryption:** the Lifelog app encrypts backups with a user passphrase (Argon2id + AES-256-GCM) before upload. The Worker and R2 store only encrypted backup blobs.
- **Server-side secrets only:** R2 is accessed via a Worker binding. Do **not** put Cloudflare API tokens or R2 S3 keys in the app or repository.
- **Authentication:** account password is hashed with PBKDF2-SHA256 (salted, high iteration count) and stored in R2 as `auth/user.json`. Login returns an HMAC-signed session token (Bearer token) with expiry; tokens are validated by the Worker using `TOKEN_SECRET`.
- **App key:** every non-`OPTIONS` request must send `X-Lifelog-App-Key`. The Worker compares it to the `APP_KEY` secret before any route logic. This is a gate/obfuscation only: a released IPA can be reverse engineered, so it does not replace account sessions or client-side encryption. Rotate `APP_KEY` and rebuild the app together.
- **Transport:** use HTTPS Worker URLs only.
- **Operational security:** rotate/revoke any credentials that were exposed (chat logs, screenshots, commits, etc.). Use strong unique passwords for the app sync account and backup passphrase.

> No system can eliminate all risk. Keep devices updated, protect your Cloudflare account with MFA, and restrict who can access the Worker/account.

## What it stores in R2

- `auth/user.json` – single-user account record (username, password salt/hash metadata, token version). No plaintext password.
- `backups/<username>/latest.lifelog` – latest client-side encrypted archive blob (cloud-primary snapshots omit embedded media).
- `media/<username>/<id>/original.bin` and `media/<username>/<id>/thumb.bin` – client-side encrypted media objects fetched on demand and cached locally by the app.

## Prerequisites

- Node.js 18+
- Cloudflare account
- Wrangler CLI (installed via npm in this folder, or globally)

## Setup

1. **Rotate exposed credentials first** if any API/R2 keys were shared or committed.
2. Install dependencies:
   ```bash
   cd cloudflare-sync
   npm install
   ```
3. Log in to Cloudflare:
   ```bash
   npx wrangler login
   ```
4. Create an R2 bucket (name must match `wrangler.toml`, default `lifelog-backups`):
   ```bash
   npx wrangler r2 bucket create lifelog-backups
   ```
5. Set the secrets (use long random values, keep them private):
   ```bash
   npx wrangler secret put TOKEN_SECRET
   npx wrangler secret put APP_KEY
   ```
   Use the same `APP_KEY` value as the Flutter build's `LIFELOG_API_KEY` dart-define.
6. Deploy:
   ```bash
   npx wrangler deploy
   ```
7. Copy the deployed Worker URL (for example `https://lifelog-cloudflare-sync.<subdomain>.workers.dev`) and enter it in the Lifelog app.

## Local development

```bash
npx wrangler dev
```

For local dev you still need an R2 bucket/binding and `TOKEN_SECRET` configured appropriately for the environment you run.

## API (used by the app)

All routes require the `X-Lifelog-App-Key` header. Data routes also require `Authorization: Bearer <token>`.

- `GET /api/health`
- `POST /api/auth/register` `{ username, password }` (first account only; single-user)
- `POST /api/auth/login` `{ username, password }` -> `{ token, ... }`
- `GET /api/auth/me`
- `GET /api/backup/meta`
- `PUT /api/backup` (`application/octet-stream` encrypted archive)
- `GET /api/backup` (returns encrypted archive bytes)
- `GET|HEAD|PUT|DELETE /api/media/<id>/original` (encrypted original)
- `GET|HEAD|PUT|DELETE /api/media/<id>/thumb` (encrypted thumbnail)

Run `npm test` for the app-key gate and route contract checks.

## Notes

- This Worker is designed for **single-user/personal** sync. Registration is allowed only when no account exists.
- Backups are stored as the latest encrypted blob (plus R2 object metadata) and may include media, so uploads can be large. Create local/linked-folder backups as additional recovery copies and consider size/platform limits when syncing very large libraries.
- If you forget the **Worker account password**, you can redeploy/reset by removing/replacing `auth/user.json` in R2 (and you will need to register again). If you forget the **backup passphrase**, encrypted backups cannot be recovered.
- Session tokens are stateless and expire (30 days). Changing `TOKEN_SECRET` or the account token version invalidates existing sessions.
- Consider enabling Cloudflare account MFA and reviewing Worker/R2 access controls in your Cloudflare dashboard.

