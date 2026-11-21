import assert from "node:assert/strict";
import test from "node:test";

import worker from "../src/index.js";

const APP_KEY = "test-app-key";

function makeEnv() {
  const objects = new Map();
  return {
    APP_KEY,
    TOKEN_SECRET: "test-token-secret",
    BACKUP_BUCKET: {
      async put(key, body, options = {}) {
        const bytes = new Uint8Array(body);
        objects.set(key, { bytes, size: bytes.byteLength, ...options });
      },
      async get(key) {
        const found = objects.get(key);
        if (!found) return null;
        return {
          body: found.bytes,
          size: found.size,
          etag: "etag",
          customMetadata: {},
          uploaded: new Date(),
        };
      },
      async head(key) {
        const found = objects.get(key);
        if (!found) return null;
        return {
          size: found.size,
          etag: "etag",
          customMetadata: {},
          uploaded: new Date(),
        };
      },
      async delete(key) {
        objects.delete(key);
      },
    },
  };
}

function request(path, { method = "GET", appKey = APP_KEY, body } = {}) {
  const headers = {};
  if (appKey !== null) headers["x-lifelog-app-key"] = appKey;
  if (body !== undefined) headers["content-type"] = "application/json";
  return new Request(`https://worker.example${path}`, {
    method,
    headers,
    body,
  });
}

const guardedRoutes = [
  ["/api/health", "GET"],
  ["/api/auth/register", "POST"],
  ["/api/auth/login", "POST"],
  ["/api/auth/me", "GET"],
  ["/api/backup/meta", "GET"],
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
