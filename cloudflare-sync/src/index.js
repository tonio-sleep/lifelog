const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };
// Cloudflare Workers WebCrypto currently supports PBKDF2 iteration counts up to 100000.
const PBKDF2_ITERATIONS = 100000;
const SESSION_TTL_SECONDS = 60 * 60 * 24 * 30; // 30 days
const APP_KEY_HEADER = "x-lifelog-app-key";
const MEDIA_MAX_BYTES = 300 * 1024 * 1024;
const THUMB_MAX_BYTES = 32 * 1024 * 1024;
const BACKUP_MAX_BYTES = 512 * 1024 * 1024;
// R2 multipart parts must be uniform and at least 5 MiB except for the last.
// 8 MiB keeps each client request below Cloudflare's 100 MB body limit while
// giving the app a server-confirmed progress event for every part.
const UPLOAD_PART_SIZE = 8 * 1024 * 1024;
const MAX_UPLOAD_PARTS = 10000;

export default {
  async fetch(request, env, ctx) {
    try {
      return await handle(request, env);
    } catch (err) {
      console.error("Unhandled worker error", err?.stack || err);
      // Avoid leaking internal details to clients.
      return json({ error: "Internal server error" }, 500, request);
    }
  },
};

function serverConfigError(request, env) {
  if (!env || !env.BACKUP_BUCKET) {
    return json({ error: "Server not configured: missing R2 bucket binding" }, 500, request);
  }
  if (!env.TOKEN_SECRET) {
    return json({ error: "Server not configured: missing TOKEN_SECRET" }, 500, request);
  }
  if (!env.APP_KEY) {
    return json({ error: "Server not configured: missing APP_KEY" }, 500, request);
  }
  return null;
}

// Every endpoint except CORS preflight requires the compiled-in app key.
// This is a gate, not authentication: a key extracted from a released IPA can
// be replayed. Keep it rotatable and keep the account session requirement.
function requireAppKey(request, env) {
  if (!env || !env.APP_KEY) {
    return json({ error: "Server not configured: missing APP_KEY" }, 500, request);
  }
  const presented = String(request.headers.get(APP_KEY_HEADER) || "");
  if (!timingSafeEqualBytesString(presented, String(env.APP_KEY))) {
    return json({ error: "App key rejected" }, 401, request);
  }
  return null;
}

async function handle(request, env) {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "") || "/";
  const method = String(request.method || "GET").toUpperCase();

  if (method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(request) });
  }

  const appKeyFailure = requireAppKey(request, env);
  if (appKeyFailure) return appKeyFailure;

  if (method === "GET" && path === "/api/health") {
    const configured =
      Boolean(env?.BACKUP_BUCKET) &&
      Boolean(env?.TOKEN_SECRET) &&
      Boolean(env?.APP_KEY);
    return json(
      { ok: true, service: "lifelog-cloudflare-sync", configured },
      200,
      request,
    );
  }

  if (path === "/api/auth/register" && method === "POST") {
    return register(request, env);
  }
  if (path === "/api/auth/login" && method === "POST") {
    return login(request, env);
  }

  // Authenticated routes
  if (path === "/api/auth/me" && method === "GET") {
    const auth = await requireAuth(request, env);
    if (!auth.ok) return auth.response;
    return json(
      { ok: true, username: auth.user.username, connectedAt: auth.user.createdAt || null },
      200,
      request,
    );
  }
  if (path === "/api/backup/meta" && method === "GET") {
    const auth = await requireAuth(request, env);
    if (!auth.ok) return auth.response;
    return backupMeta(request, env, auth.user.username);
  }

  // Resumable, server-confirmed uploads. Each part is a separate request so a
  // large backup or video never has to be buffered by the Worker in one body.
  if (path === "/api/uploads/begin" && method === "POST") {
    const auth = await requireAuth(request, env);
    if (!auth.ok) return auth.response;
    return beginUpload(request, env, auth.user.username);
  }
  const uploadPartMatch = path.match(/^\/api\/uploads\/([A-Za-z0-9_-]+)\/parts\/(\d+)$/);
  if (uploadPartMatch && method === "PUT") {
    const auth = await requireAuth(request, env);
    if (!auth.ok) return auth.response;
    return uploadPart(request, env, auth.user.username, uploadPartMatch[1], uploadPartMatch[2]);
  }
  const uploadCompleteMatch = path.match(/^\/api\/uploads\/([A-Za-z0-9_-]+)\/complete$/);
  if (uploadCompleteMatch && method === "POST") {
    const auth = await requireAuth(request, env);
    if (!auth.ok) return auth.response;
    return completeUpload(request, env, auth.user.username, uploadCompleteMatch[1]);
  }
  const uploadAbortMatch = path.match(/^\/api\/uploads\/([A-Za-z0-9_-]+)$/);
  if (uploadAbortMatch && method === "DELETE") {
    const auth = await requireAuth(request, env);
    if (!auth.ok) return auth.response;
    return abortUpload(request, env, auth.user.username, uploadAbortMatch[1]);
  }

  if (path === "/api/backup" && method === "PUT") {
    const auth = await requireAuth(request, env);
    if (!auth.ok) return auth.response;
    return uploadBackup(request, env, auth.user.username);
  }
  if (path === "/api/backup" && method === "GET") {
    const auth = await requireAuth(request, env);
    if (!auth.ok) return auth.response;
    return downloadBackup(request, env, auth.user.username);
  }

  const mediaMatch = path.match(/^\/api\/media\/([^/]+)\/(original|thumb)$/);
  if (mediaMatch && ["GET", "HEAD", "PUT", "DELETE"].includes(method)) {
    const auth = await requireAuth(request, env);
    if (!auth.ok) return auth.response;
    return handleMedia(request, env, auth.user.username, mediaMatch[1], mediaMatch[2], method);
  }

  return json({ error: "Not found" }, 404, request);
}

function corsHeaders(request) {
  // Native app clients are not browser-CORS constrained, but keep permissive headers for flexibility.
  const origin = request.headers.get("Origin") || "*";
  return {
    "access-control-allow-origin": origin,
    "access-control-allow-methods": "GET,HEAD,PUT,POST,DELETE,OPTIONS",
    "access-control-allow-headers": `Authorization,Content-Type,${APP_KEY_HEADER}`,
    "access-control-max-age": "86400",
    vary: "Origin",
  };
}

function json(data, status = 200, request = null) {
  const headers = { ...JSON_HEADERS };
  if (request) Object.assign(headers, corsHeaders(request));
  return new Response(JSON.stringify(data), { status, headers });
}

async function readJson(request, maxBytes = 64 * 1024) {
  const ct = request.headers.get("content-type") || "";
  if (!ct.toLowerCase().includes("application/json")) {
    return { ok: false, error: "Expected application/json" };
  }
  const len = Number(request.headers.get("content-length") || "0");
  if (len && len > maxBytes) return { ok: false, error: "Request too large" };
  let text;
  try {
    text = await request.text();
  } catch {
    return { ok: false, error: "Invalid request body" };
  }
  if (text.length > maxBytes) return { ok: false, error: "Request too large" };
  try {
    return { ok: true, value: JSON.parse(text) };
  } catch {
    return { ok: false, error: "Invalid JSON" };
  }
}

function normalizeUsername(u) {
  if (typeof u !== "string") return "";
  return u.trim().toLowerCase();
}
function validUsername(u) {
  return /^[a-z0-9][a-z0-9._@-]{1,62}[a-z0-9]$/.test(u) || /^[a-z0-9]{2}$/.test(u);
}
function validPassword(p) {
  return typeof p === "string" && p.length >= 10 && p.length <= 1024;
}

async function getUser(env) {
  if (!env?.BACKUP_BUCKET) return null;
  const obj = await env.BACKUP_BUCKET.get("auth/user.json");
  if (!obj) return null;
  try {
    return await obj.json();
  } catch {
    return null;
  }
}
async function putUser(env, user) {
  if (!env?.BACKUP_BUCKET) throw new Error("Missing BACKUP_BUCKET binding");
  await env.BACKUP_BUCKET.put("auth/user.json", JSON.stringify(user), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
  });
}

async function register(request, env) {
  const cfg = serverConfigError(request, env);
  if (cfg) return cfg;
  const body = await readJson(request);
  if (!body.ok) return json({ error: body.error }, 400, request);
  const username = normalizeUsername(body.value?.username);
  const password = body.value?.password;
  if (!validUsername(username)) return json({ error: "Invalid username" }, 400, request);
  if (!validPassword(password)) {
    return json({ error: "Password must be at least 10 characters" }, 400, request);
  }

  const existing = await getUser(env);
  if (existing) return json({ error: "Account already exists" }, 409, request);

  const salt = crypto.getRandomValues(new Uint8Array(16));
  const hash = await pbkdf2(password, salt, PBKDF2_ITERATIONS);
  const user = {
    username,
    salt: b64urlEncode(salt),
    hash: b64urlEncode(hash),
    iterations: PBKDF2_ITERATIONS,
    algo: "pbkdf2-sha256",
    tokenVersion: 1,
    createdAt: new Date().toISOString(),
  };
  await putUser(env, user);
  const token = await createToken(env, user);
  return json({ ok: true, token, username, expiresIn: SESSION_TTL_SECONDS }, 200, request);
}

async function login(request, env) {
  const cfg = serverConfigError(request, env);
  if (cfg) return cfg;
  const body = await readJson(request);
  if (!body.ok) return json({ error: body.error }, 400, request);
  const username = normalizeUsername(body.value?.username);
  const password = body.value?.password;
  if (typeof password !== "string") return json({ error: "Invalid credentials" }, 401, request);

  const user = await getUser(env);
  if (!user || user.username !== username) {
    // Perform dummy work to reduce trivial timing differences.
    await pbkdf2("dummy-password", crypto.getRandomValues(new Uint8Array(16)), PBKDF2_ITERATIONS);
    return json({ error: "Invalid credentials" }, 401, request);
  }
  try {
    const salt = b64urlDecode(user.salt);
    const expected = b64urlDecode(user.hash);
    const iters = Number(user.iterations) || PBKDF2_ITERATIONS;
    const actual = await pbkdf2(password, salt, iters);
    if (!timingSafeEqual(actual, expected)) {
      return json({ error: "Invalid credentials" }, 401, request);
    }
  } catch (err) {
    console.error("Login verification error", err?.stack || err);
    return json({ error: "Invalid credentials" }, 401, request);
  }
  const token = await createToken(env, user);
  return json({ ok: true, token, username: user.username, expiresIn: SESSION_TTL_SECONDS }, 200, request);
}

async function requireAuth(request, env) {
  const cfg = serverConfigError(request, env);
  if (cfg) return { ok: false, response: cfg };
  const header = request.headers.get("Authorization") || "";
  const m = header.match(/^Bearer\s+(.+)$/i);
  if (!m) return { ok: false, response: json({ error: "Unauthorized" }, 401, request) };
  const payload = await verifyToken(env, m[1].trim());
  if (!payload) return { ok: false, response: json({ error: "Unauthorized" }, 401, request) };
  const user = await getUser(env);
  if (!user || user.username !== payload.sub) {
    return { ok: false, response: json({ error: "Unauthorized" }, 401, request) };
  }
  if (Number(payload.v || 0) !== Number(user.tokenVersion || 0)) {
    return { ok: false, response: json({ error: "Unauthorized" }, 401, request) };
  }
  return { ok: true, user };
}

async function backupMeta(request, env, username) {
  if (!env?.BACKUP_BUCKET) {
    return json({ error: "Server not configured: missing R2 bucket binding" }, 500, request);
  }
  const key = backupKey(username);
  const head = await env.BACKUP_BUCKET.head(key);
  if (!head) return json({ ok: true, exists: false }, 200, request);
  return json({
    ok: true,
    exists: true,
    key,
    size: head.size,
    etag: head.etag || null,
    uploadedAt: head.uploaded ? head.uploaded.toISOString() : null,
    modifiedAt:
      (head.customMetadata && head.customMetadata.modifiedAt) ||
      (head.uploaded ? head.uploaded.toISOString() : null),
  }, 200, request);
}

function uploadMetaKey(username, uploadId) {
  return `uploads/${String(username || "user").replace(/[^a-z0-9._@-]/gi, "_")}/${uploadId}.json`;
}

function validUploadId(uploadId) {
  return /^[A-Za-z0-9_-]{1,80}$/.test(String(uploadId || ""));
}

async function putUploadMeta(env, meta) {
  await env.BACKUP_BUCKET.put(uploadMetaKey(meta.owner, meta.uploadId), JSON.stringify(meta), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
  });
}

async function loadUpload(request, env, username, uploadId) {
  if (!validUploadId(uploadId)) {
    return { ok: false, response: json({ error: "Invalid upload id" }, 400, request) };
  }
  let raw;
  try {
    const obj = await env.BACKUP_BUCKET.get(uploadMetaKey(username, uploadId));
    raw = obj ? await obj.json() : null;
  } catch (err) {
    console.error("Upload state read failed", err?.stack || err);
    return { ok: false, response: json({ error: "Could not read upload state" }, 500, request) };
  }
  if (!raw || raw.owner !== username || !raw.key || !raw.r2UploadId) {
    return { ok: false, response: json({ error: "Upload not found" }, 404, request) };
  }
  return {
    ok: true,
    meta: raw,
    resume: env.BACKUP_BUCKET.resumeMultipartUpload(raw.key, raw.r2UploadId),
  };
}

async function beginUpload(request, env, username) {
  if (!env?.BACKUP_BUCKET) {
    return json({ error: "Server not configured: missing R2 bucket binding" }, 500, request);
  }
  const body = await readJson(request);
  if (!body.ok) return json({ error: body.error }, 400, request);

  const target = body.value?.target;
  const size = Number(body.value?.size);
  if (!Number.isSafeInteger(size) || size <= 0) {
    return json({ error: "Invalid upload size" }, 400, request);
  }

  let key;
  let limit;
  const customMetadata = { kind: "lifelog-encrypted-upload" };
  if (target === "backup") {
    key = backupKey(username);
    limit = BACKUP_MAX_BYTES;
    customMetadata.kind = "lifelog-encrypted-backup";
  } else if (target === "media") {
    const id = String(body.value?.id || "");
    const kind = String(body.value?.mediaKind || "");
    if (!validMediaId(id) || !["original", "thumb"].includes(kind)) {
      return json({ error: "Invalid media upload target" }, 400, request);
    }
    key = mediaKey(username, id, kind);
    limit = kind === "thumb" ? THUMB_MAX_BYTES : MEDIA_MAX_BYTES;
    customMetadata.kind = "lifelog-encrypted-media";
    customMetadata.mediaKind = kind;
  } else {
    return json({ error: "Invalid upload target" }, 400, request);
  }
  if (size > limit) return json({ error: "Upload too large" }, 413, request);

  const partCount = Math.ceil(size / UPLOAD_PART_SIZE);
  if (partCount > MAX_UPLOAD_PARTS) {
    return json({ error: "Upload has too many parts" }, 413, request);
  }

  const now = new Date().toISOString();
  customMetadata.modifiedAt = now;
  let multipart;
  try {
    multipart = await env.BACKUP_BUCKET.createMultipartUpload(key, {
      httpMetadata: { contentType: "application/octet-stream" },
      customMetadata,
    });
  } catch (err) {
    console.error("R2 multipart create failed", err?.stack || err);
    return json({ error: "Could not start upload" }, 500, request);
  }

  // The public id is app-generated and safe for URLs. R2's own uploadId can
  // contain characters that are awkward in paths, so it stays server-side.
  const uploadId = crypto.randomUUID();
  const meta = {
    uploadId,
    r2UploadId: multipart.uploadId,
    owner: username,
    key,
    target,
    size,
    partSize: UPLOAD_PART_SIZE,
    partCount,
    parts: [],
    createdAt: now,
    modifiedAt: now,
  };
  try {
    await putUploadMeta(env, meta);
  } catch (err) {
    console.error("Upload state write failed", err?.stack || err);
    try {
      await multipart.abort();
    } catch (_) {
      // Best effort cleanup.
    }
    return json({ error: "Could not start upload" }, 500, request);
  }

  return json(
    { ok: true, uploadId, partSize: UPLOAD_PART_SIZE, partCount, confirmedBytes: 0, size },
    200,
    request,
  );
}

async function uploadPart(request, env, username, uploadId, rawPartNumber) {
  const loaded = await loadUpload(request, env, username, uploadId);
  if (!loaded.ok) return loaded.response;
  const meta = loaded.meta;
  const partNumber = Number(rawPartNumber);
  if (!Number.isSafeInteger(partNumber) || partNumber < 1 || partNumber > meta.partCount) {
    return json({ error: "Invalid part number" }, 400, request);
  }

  const expected =
    partNumber === meta.partCount
      ? meta.size - meta.partSize * (meta.partCount - 1)
      : meta.partSize;
  const declared = Number(request.headers.get("content-length") || "0");
  if (declared && declared !== expected) {
    return json({ error: "Unexpected part size" }, 400, request);
  }

  let body;
  try {
    body = await request.arrayBuffer();
  } catch {
    return json({ error: "Invalid upload part" }, 400, request);
  }
  if (!body || body.byteLength !== expected) {
    return json({ error: "Unexpected part size" }, 400, request);
  }

  let uploaded;
  try {
    uploaded = await loaded.resume.uploadPart(partNumber, body);
  } catch (err) {
    console.error("R2 part upload failed", err?.stack || err);
    return json({ error: "Could not store upload part" }, 500, request);
  }

  const parts = meta.parts.filter((part) => part.partNumber !== partNumber);
  parts.push({ partNumber, size: expected, etag: uploaded.etag });
  parts.sort((a, b) => a.partNumber - b.partNumber);
  meta.parts = parts;
  meta.modifiedAt = new Date().toISOString();
  try {
    await putUploadMeta(env, meta);
  } catch (err) {
    console.error("Upload state write failed", err?.stack || err);
    return json({ error: "Could not record upload part" }, 500, request);
  }

  const confirmedBytes = parts.reduce((sum, part) => sum + part.size, 0);
  return json(
    {
      ok: true,
      partNumber,
      size: expected,
      confirmedBytes,
      totalBytes: meta.size,
      complete: confirmedBytes === meta.size,
    },
    200,
    request,
  );
}

async function completeUpload(request, env, username, uploadId) {
  const loaded = await loadUpload(request, env, username, uploadId);
  if (!loaded.ok) return loaded.response;
  const meta = loaded.meta;
  if (meta.parts.length !== meta.partCount) {
    return json({ error: "Upload is incomplete" }, 409, request);
  }
  const total = meta.parts.reduce((sum, part) => sum + part.size, 0);
  if (total !== meta.size) {
    return json({ error: "Upload size does not match" }, 409, request);
  }

  let object;
  try {
    object = await loaded.resume.complete(
      meta.parts.map((part) => ({ partNumber: part.partNumber, etag: part.etag })),
    );
  } catch (err) {
    console.error("R2 multipart complete failed", err?.stack || err);
    return json({ error: "Could not finish upload" }, 500, request);
  }
  try {
    await env.BACKUP_BUCKET.delete(uploadMetaKey(username, uploadId));
  } catch (_) {
    // Upload is already committed; stale state is harmless and expires with cleanup.
  }
  return json(
    {
      ok: true,
      size: object?.size ?? meta.size,
      etag: object?.etag ?? null,
      uploadedAt: new Date().toISOString(),
    },
    200,
    request,
  );
}

async function abortUpload(request, env, username, uploadId) {
  const loaded = await loadUpload(request, env, username, uploadId);
  if (!loaded.ok) return loaded.response;
  try {
    await loaded.resume.abort();
  } catch (err) {
    console.error("R2 multipart abort failed", err?.stack || err);
  }
  try {
    await env.BACKUP_BUCKET.delete(uploadMetaKey(username, uploadId));
  } catch (_) {
    // Best effort cleanup.
  }
  return json({ ok: true }, 200, request);
}

async function uploadBackup(request, env, username) {
  if (!env?.BACKUP_BUCKET) {
    return json({ error: "Server not configured: missing R2 bucket binding" }, 500, request);
  }
  const max = BACKUP_MAX_BYTES;
  const len = Number(request.headers.get("content-length") || "0");
  if (len && len > max) return json({ error: "Backup too large" }, 413, request);

  let body;
  try {
    body = await request.arrayBuffer();
  } catch (err) {
    console.error("Failed to read upload body", err?.stack || err);
    return json({ error: "Invalid upload payload" }, 400, request);
  }
  if (!body || body.byteLength === 0) return json({ error: "Empty backup" }, 400, request);
  if (body.byteLength > max) return json({ error: "Backup too large" }, 413, request);

  const now = new Date().toISOString();
  const key = backupKey(username);
  try {
    await env.BACKUP_BUCKET.put(key, body, {
      httpMetadata: { contentType: "application/octet-stream" },
      customMetadata: { modifiedAt: now, kind: "lifelog-encrypted-backup" },
    });
  } catch (err) {
    console.error("R2 put failed", err?.stack || err);
    return json({ error: "Could not store backup" }, 500, request);
  }
  return json({ ok: true, uploadedAt: now, size: body.byteLength }, 200, request);
}

async function downloadBackup(request, env, username) {
  if (!env?.BACKUP_BUCKET) {
    return json({ error: "Server not configured: missing R2 bucket binding" }, 500, request);
  }
  const key = backupKey(username);
  let obj;
  try {
    obj = await env.BACKUP_BUCKET.get(key);
  } catch (err) {
    console.error("R2 get failed", err?.stack || err);
    return json({ error: "Could not read backup" }, 500, request);
  }
  if (!obj) return json({ error: "No backup found" }, 404, request);
  const headers = {
    "content-type": "application/octet-stream",
    "cache-control": "no-store",
    ...corsHeaders(request),
  };
  const modifiedAt =
    (obj.customMetadata && obj.customMetadata.modifiedAt) ||
    (obj.uploaded ? obj.uploaded.toISOString() : null);
  if (modifiedAt) headers["x-backup-modified-at"] = modifiedAt;
  if (obj.etag) headers["etag"] = obj.etag;
  return new Response(obj.body, { status: 200, headers });
}

function backupKey(username) {
  const safe = String(username || "user").replace(/[^a-z0-9._@-]/gi, "_");
  return `backups/${safe}/latest.lifelog`;
}

function mediaKey(username, id, kind) {
  const safeUser = String(username || "user").replace(/[^a-z0-9._@-]/gi, "_");
  return `media/${safeUser}/${id}/${kind}.bin`;
}

function validMediaId(id) {
  return /^[A-Za-z0-9_-]{1,64}$/.test(String(id || ""));
}

async function handleMedia(request, env, username, rawId, kind, method) {
  const cfg = serverConfigError(request, env);
  if (cfg) return cfg;
  const id = String(rawId || "");
  if (!validMediaId(id)) return json({ error: "Invalid media id" }, 400, request);

  const key = mediaKey(username, id, kind);
  const maxBytes = kind === "thumb" ? THUMB_MAX_BYTES : MEDIA_MAX_BYTES;

  if (method === "PUT") {
    const len = Number(request.headers.get("content-length") || "0");
    if (len && len > maxBytes) return json({ error: "Media too large" }, 413, request);
    let body;
    try {
      body = await request.arrayBuffer();
    } catch {
      return json({ error: "Invalid media payload" }, 400, request);
    }
    if (!body || body.byteLength === 0) {
      return json({ error: "Empty media" }, 400, request);
    }
    if (body.byteLength > maxBytes) {
      return json({ error: "Media too large" }, 413, request);
    }
    const now = new Date().toISOString();
    try {
      await env.BACKUP_BUCKET.put(key, body, {
        httpMetadata: { contentType: "application/octet-stream" },
        customMetadata: { modifiedAt: now, kind: "lifelog-encrypted-media", mediaKind: kind },
      });
    } catch (err) {
      console.error("R2 media put failed", err?.stack || err);
      return json({ error: "Could not store media" }, 500, request);
    }
    return json({ ok: true, size: body.byteLength, uploadedAt: now }, 200, request);
  }

  if (method === "DELETE") {
    try {
      await env.BACKUP_BUCKET.delete(key);
    } catch (err) {
      console.error("R2 media delete failed", err?.stack || err);
      return json({ error: "Could not delete media" }, 500, request);
    }
    return json({ ok: true }, 200, request);
  }

  let obj;
  try {
    obj = method === "HEAD"
      ? await env.BACKUP_BUCKET.head(key)
      : await env.BACKUP_BUCKET.get(key);
  } catch (err) {
    console.error("R2 media read failed", err?.stack || err);
    return method === "HEAD"
      ? new Response(null, { status: 500, headers: corsHeaders(request) })
      : json({ error: "Could not read media" }, 500, request);
  }
  if (!obj) {
    return method === "HEAD"
      ? new Response(null, { status: 404, headers: corsHeaders(request) })
      : json({ error: "Media not found" }, 404, request);
  }
  const headers = {
    "content-type": "application/octet-stream",
    "cache-control": "no-store",
    "content-length": String(obj.size),
    ...corsHeaders(request),
  };
  if (obj.etag) headers.etag = obj.etag;
  const modifiedAt =
    (obj.customMetadata && obj.customMetadata.modifiedAt) ||
    (obj.uploaded ? obj.uploaded.toISOString() : null);
  if (modifiedAt) headers["x-media-modified-at"] = modifiedAt;
  if (method === "HEAD") {
    return new Response(null, { status: 200, headers });
  }
  return new Response(obj.body, { status: 200, headers });
}

async function pbkdf2(password, salt, iterations) {
  const enc = new TextEncoder();
  const keyMaterial = await crypto.subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt, iterations },
    keyMaterial,
    256
  );
  return new Uint8Array(bits);
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

async function createToken(env, user) {
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    sub: user.username,
    exp: now + SESSION_TTL_SECONDS,
    iat: now,
    v: Number(user.tokenVersion || 1),
  };
  const payloadPart = b64urlEncode(new TextEncoder().encode(JSON.stringify(payload)));
  const sig = await hmacSign(env.TOKEN_SECRET, payloadPart);
  return `${payloadPart}.${sig}`;
}

async function verifyToken(env, token) {
  const parts = String(token).split(".");
  if (parts.length !== 2) return null;
  const [payloadPart, sigPart] = parts;
  const expected = await hmacSign(env.TOKEN_SECRET, payloadPart);
  const ok = timingSafeEqualBytesString(expected, sigPart);
  if (!ok) return null;
  try {
    const payloadJson = new TextDecoder().decode(b64urlDecode(payloadPart));
    const payload = JSON.parse(payloadJson);
    const now = Math.floor(Date.now() / 1000);
    if (!payload || typeof payload.sub !== "string") return null;
    if (!payload.exp || Number(payload.exp) <= now) return null;
    return payload;
  } catch {
    return null;
  }
}

async function hmacSign(secret, data) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(String(secret)),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(data));
  return b64urlEncode(new Uint8Array(sig));
}

function timingSafeEqualBytesString(aStr, bStr) {
  // Compare in constant time over same-length strings; if lengths differ, still do work.
  const a = String(aStr);
  const b = String(bStr);
  const len = Math.max(a.length, b.length);
  let diff = a.length === b.length ? 0 : 1;
  for (let i = 0; i < len; i++) {
    const ca = i < a.length ? a.charCodeAt(i) : 0;
    const cb = i < b.length ? b.charCodeAt(i) : 0;
    diff |= ca ^ cb;
  }
  return diff === 0;
}

function b64urlEncode(bytes) {
  let bin = "";
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  for (let i = 0; i < arr.length; i++) bin += String.fromCharCode(arr[i]);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
function b64urlDecode(str) {
  const s = String(str).replace(/-/g, "+").replace(/_/g, "/");
  const pad = s.length % 4 === 0 ? "" : "=".repeat(4 - (s.length % 4));
  const bin = atob(s + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

