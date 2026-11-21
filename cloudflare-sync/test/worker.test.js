import assert from "node:assert/strict";
import test from "node:test";

import worker from "../src/index.js";

const APP_KEY = "test-app-key";
const PART_SIZE = 8 * 1024 * 1024;

function makeEnv() {
  const objects = new Map();
  const uploads = new Map();
  const encoder = new TextEncoder();

  function objectFrom(value, options = {}) {
    const bytes =
      typeof value === "string"
        ? encoder.encode(value)
        : value instanceof Uint8Array
          ? value
          : new Uint8Array(value);
    return { bytes, size: bytes.byteLength, ...options };
  }

  function multipartFor(record) {
    const api = {
      uploadId: record.uploadId,
      async uploadPart(partNumber, value) {
        const stored = objectFrom(value);
        record.parts.set(partNumber, {
          partNumber,
          bytes: stored.bytes,
          size: stored.size,
          etag: `part-${partNumber}`,
        });
        return { partNumber, etag: `part-${partNumber}` };
      },
      async complete(parts) {
        const chunkBytes = parts.reduce((sum, part) => sum + record.parts.get(part.partNumber).size, 0);
        const merged = new Uint8Array(chunkBytes);
        let offset = 0;
        for (const part of parts) {
          const stored = record.parts.get(part.partNumber);
          merged.set(stored.bytes, offset);
          offset += stored.size;
        }
        objects.set(record.key, objectFrom(merged, record.options));
        uploads.delete(record.uploadId);
        return { key: record.key, size: chunkBytes, etag: "final-etag" };
      },
      async abort() {
        uploads.delete(record.uploadId);
      },
    };
    return api;
  }

  const env = {
    APP_KEY,
    TOKEN_SECRET: "test-token-secret",
    BACKUP_BUCKET: {
      async put(key, body, options = {}) {
        objects.set(key, objectFrom(body, options));
      },
      async get(key) {
        const found = objects.get(key);
        if (!found) return null;
        return {
          body: found.bytes,
          size: found.size,
          etag: found.etag || "etag",
          customMetadata: found.customMetadata || {},
          uploaded: found.uploaded || new Date(),
          async json() {
            return JSON.parse(new TextDecoder().decode(found.bytes));
          },
        };
      },
      async head(key) {
        const found = objects.get(key);
        if (!found) return null;
        return {
          size: found.size,
          etag: found.etag || "etag",
          customMetadata: found.customMetadata || {},
          uploaded: found.uploaded || new Date(),
        };
      },
      async delete(key) {
        objects.delete(key);
      },
      async createMultipartUpload(key, options = {}) {
        const record = {
          uploadId: `r2-${uploads.size + 1}`,
          key,
          options,
          parts: new Map(),
        };
        uploads.set(record.uploadId, record);
        return multipartFor(record);
      },
      resumeMultipartUpload(key, uploadId) {
        const record = uploads.get(uploadId);
        if (!record || record.key !== key) {
          return {
            async uploadPart() {
              throw new Error("NoSuchUpload");
            },
            async complete() {
              throw new Error("NoSuchUpload");
            },
            async abort() {},
          };
        }
        return multipartFor(record);
      },
    },
  };
  env.__objects = objects;
  return env;
}

function request(path, { method = "GET", appKey = APP_KEY, body, headers = {} } = {}) {
  const allHeaders = { ...headers };
  if (appKey !== null) allHeaders["x-lifelog-app-key"] = appKey;
  if (body !== undefined && !allHeaders["content-type"]) {
    allHeaders["content-type"] = "application/json";
  }
  return new Request(`https://worker.example${path}`, {
    method,
    headers: allHeaders,
    body,
  });
}

async function signedRequest(path, env, options = {}) {
  const now = Math.floor(Date.now() / 1000);
  const enc = new TextEncoder();
  const payload = btoa(
    String.fromCharCode(...enc.encode(JSON.stringify({ sub: "user", exp: now + 3600, iat: now, v: 1 }))),
  )
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(env.TOKEN_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, enc.encode(payload)),
  );
  const sig = btoa(String.fromCharCode(...signature))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
  return request(path, {
    ...options,
    headers: { ...(options.headers || {}), authorization: `Bearer ${payload}.${sig}` },
  });
}

async function seedUser(env) {
  await env.BACKUP_BUCKET.put(
    "auth/user.json",
    JSON.stringify({ username: "user", tokenVersion: 1 }),
    { contentType: "application/json" },
  );
}

const guardedRoutes = [
  ["/api/health", "GET"],
  ["/api/auth/register", "POST"],
  ["/api/auth/login", "POST"],
  ["/api/auth/me", "GET"],
  ["/api/backup/meta", "GET"],
  ["/api/uploads/begin", "POST"],
  ["/api/uploads/id/parts/1", "PUT"],
  ["/api/uploads/id/complete", "POST"],
  ["/api/uploads/id", "DELETE"],
  ["/api/backup", "PUT"],
  ["/api/backup", "GET"],
  ["/api/media/123/original", "GET"],
  ["/api/media/123/original", "HEAD"],
  ["/api/media/123/original", "PUT"],
  ["/api/media/123/original", "DELETE"],
  ["/api/media/123/thumb", "GET"],
];

test("every endpoint rejects a missing app key", async () => {
  const env = makeEnv();
  for (const [path, method] of guardedRoutes) {
    const response = await worker.fetch(request(path, { method, appKey: null }), env);
    assert.equal(response.status, 401, `${method} ${path}`);
    const body = await response.json();
    assert.equal(body.error, "App key rejected");
  }
});

test("every endpoint rejects a wrong app key", async () => {
  const env = makeEnv();
  for (const [path, method] of guardedRoutes) {
    const response = await worker.fetch(
      request(path, { method, appKey: "not-the-key" }),
      env,
    );
    assert.equal(response.status, 401, `${method} ${path}`);
  }
});

test("CORS preflight is allowed without the app key and advertises it", async () => {
  const response = await worker.fetch(
    request("/api/backup", { method: "OPTIONS", appKey: null }),
    makeEnv(),
  );
  assert.equal(response.status, 204);
  assert.match(
    response.headers.get("access-control-allow-headers") || "",
    /x-lifelog-app-key/i,
  );
});

test("media routes are present but still require a session", async () => {
  const env = makeEnv();
  const response = await worker.fetch(
    request("/api/media/media-id/original", { method: "GET" }),
    env,
  );
  assert.equal(response.status, 401);
  const body = await response.json();
  assert.equal(body.error, "Unauthorized");
});

test("valid app key reaches health with bindings configured", async () => {
  const response = await worker.fetch(request("/api/health"), makeEnv());
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.ok, true);
  assert.equal(body.configured, true);
});

test("chunked uploads confirm every part before completing the object", async () => {
  const env = makeEnv();
  await seedUser(env);
  const total = PART_SIZE + 3;

  const begin = await worker.fetch(
    await signedRequest(
      "/api/uploads/begin",
      env,
      {
        method: "POST",
        body: JSON.stringify({
          target: "media",
          id: "clip-1",
          mediaKind: "original",
          size: total,
        }),
      },
    ),
    env,
  );
  assert.equal(begin.status, 200);
  const started = await begin.json();
  assert.equal(started.partSize, PART_SIZE);
  assert.equal(started.partCount, 2);
  assert.equal(started.confirmedBytes, 0);

  const first = new Uint8Array(PART_SIZE).fill(7);
  const partOne = await worker.fetch(
    await signedRequest(
      `/api/uploads/${started.uploadId}/parts/1`,
      env,
      { method: "PUT", body: first, headers: { "content-type": "application/octet-stream" } },
    ),
    env,
  );
  assert.equal(partOne.status, 200);
  const one = await partOne.json();
  assert.equal(one.confirmedBytes, PART_SIZE);
  assert.equal(one.complete, false);

  const partTwo = await worker.fetch(
    await signedRequest(
      `/api/uploads/${started.uploadId}/parts/2`,
      env,
      {
        method: "PUT",
        body: new Uint8Array([1, 2, 3]),
        headers: { "content-type": "application/octet-stream" },
      },
    ),
    env,
  );
  assert.equal(partTwo.status, 200);
  const two = await partTwo.json();
  assert.equal(two.confirmedBytes, total);
  assert.equal(two.complete, true);

  const complete = await worker.fetch(
    await signedRequest(
      `/api/uploads/${started.uploadId}/complete`,
      env,
      { method: "POST", body: "{}" },
    ),
    env,
  );
  assert.equal(complete.status, 200);
  const done = await complete.json();
  assert.equal(done.size, total);

  const head = await worker.fetch(
    await signedRequest("/api/media/clip-1/original", env, { method: "HEAD" }),
    env,
  );
  assert.equal(head.status, 200);
  assert.equal(head.headers.get("content-length"), String(total));
});
