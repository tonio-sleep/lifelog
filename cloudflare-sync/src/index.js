const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };
const PBKDF2_ITERATIONS = 310000;
const SESSION_TTL_SECONDS = 60 * 60 * 24 * 30; // 30 days

export default {
  async fetch(request, env, ctx) {
    try {
      return await handle(request, env);
    } catch (err) {
      console.error("Unhandled worker error", err);
      // Avoid leaking internal details.
      return json({ error: "Internal server error" }, 500, request);
    }
  },
};

async function handle(request, env) {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "") || "/";
  const method = (request.method || "GET").toUpperCase();

  if (method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(request) });
  }

  if (method === "GET" && path === "/api/health") {
    return json({ ok: true, service: "lifelog-cloudflare-sync" }, 200, request);
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
    return json({ ok: true, username: auth.user.username, connectedAt: auth.user.createdAt || null }, 200, request);
  }
  if (path === "/api/backup/meta" && method === "GET") {
    const auth = await requireAuth(request, env);
    if (!auth.ok) return auth.response;
    return backupMeta(request, env, auth.user.username);
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

  return json({ error: "Not found" }, 404, request);
}

function corsHeaders(request) {
  // Native app clients are not browser-CORS constrained, but keep permissive headers for flexibility.
  const origin = request.headers.get("Origin") || "*";
  return {
    "access-control-allow-origin": origin,
    "access-control-allow-methods": "GET,PUT,POST,DELETE,OPTIONS",
    "access-control-allow-headers": "Authorization,Content-Type",
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
  const obj = await env.BACKUP_BUCKET.get("auth/user.json");
  if (!obj) return null;
  try {
    return await obj.json();
  } catch {
    return null;
  }
}
async function putUser(env, user) {
  await env.BACKUP_BUCKET.put("auth/user.json", JSON.stringify(user), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
  });
}

async function register(request, env) {
  const body = await readJson(request);
  if (!body.ok) return json({ error: body.error }, 400, request);
  const username = normalizeUsername(body.value.username);
  const password = body.value.password;
  if (!validUsername(username)) return json({ error: "Invalid username" }, 400, request);
  if (!validPassword(password)) return json({ error: "Password must be at least 10 characters" }, 400, request);
  if (!env.TOKEN_SECRET) return json({ error: "Server not configured" }, 500, request);

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
  const body = await readJson(request);
  if (!body.ok) return json({ error: body.error }, 400, request);
  const username = normalizeUsername(body.value.username);
  const password = body.value.password;
  if (typeof password !== "string") return json({ error: "Invalid credentials" }, 401, request);
  if (!env.TOKEN_SECRET) return json({ error: "Server not configured" }, 500, request);

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
  } catch {
    return json({ error: "Invalid credentials" }, 401, request);
  }
  const token = await createToken(env, user);
  return json({ ok: true, token, username: user.username, expiresIn: SESSION_TTL_SECONDS }, 200, request);
}

async function requireAuth(request, env) {
  if (!env.TOKEN_SECRET) return { ok: false, response: json({ error: "Server not configured" }, 500, request) };
  const header = request.headers.get("Authorization") || "";
  const m = header.match(/^Bearer\s+(.+)$/i);
  if (!m) return { ok: false, response: json({ error: "Unauthorized" }, 401, request) };
  const payload = await verifyToken(env, m[1].trim());
  if (!payload) return { ok: false, response: json({ error: "Unauthorized" }, 401, request) };
  const user = await getUser(env);
  if (!user || user.username !== payload.sub) return { ok: false, response: json({ error: "Unauthorized" }, 401, request) };
  if (Number(payload.v || 0) !== Number(user.tokenVersion || 0)) {
    return { ok: false, response: json({ error: "Unauthorized" }, 401, request) };
  }
  return { ok: true, user };
}

async function backupMeta(request, env, username) {
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
    modifiedAt: (head.customMetadata && head.customMetadata.modifiedAt) || (head.uploaded ? head.uploaded.toISOString() : null),
  }, 200, request);
}

async function uploadBackup(request, env, username) {
  const max = 512 * 1024 * 1024; // 512 MB safety cap for encrypted backup blobs (including media); very large libraries may require chunked/object strategies
  const len = Number(request.headers.get("content-length") || "0");
  if (len && len > max) return json({ error: "Backup too large" }, 413, request);
  const body = await request.arrayBuffer();
  if (body.byteLength === 0) return json({ error: "Empty backup" }, 400, request);
  if (body.byteLength > max) return json({ error: "Backup too large" }, 413, request);
  const now = new Date().toISOString();
  const key = backupKey(username);
  await env.BACKUP_BUCKET.put(key, body, {
    httpMetadata: { contentType: "application/octet-stream" },
    customMetadata: { modifiedAt: now, kind: "lifelog-encrypted-backup" },
  });
  return json({ ok: true, uploadedAt: now, size: body.byteLength }, 200, request);
}

async function downloadBackup(request, env, username) {
  const key = backupKey(username);
  const obj = await env.BACKUP_BUCKET.get(key);
  if (!obj) return json({ error: "No backup found" }, 404, request);
  const headers = {
    "content-type": "application/octet-stream",
    "cache-control": "no-store",
    ...corsHeaders(request),
  };
  const modifiedAt = (obj.customMetadata && obj.customMetadata.modifiedAt) || (obj.uploaded ? obj.uploaded.toISOString() : null);
  if (modifiedAt) headers["x-backup-modified-at"] = modifiedAt;
  headers["etag"] = obj.etag || "";
  return new Response(obj.body, { status: 200, headers });
}

function backupKey(username) {
  const safe = String(username || "user").replace(/[^a-z0-9._@-]/gi, "_");
  return `backups/${safe}/latest.lifelog`;
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

