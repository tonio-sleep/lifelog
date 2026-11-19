import Foundation

struct CloudflareSession: Codable {
    var token: String
    var username: String
    var expiresInSeconds: Int?
    var obtainedAt: Date?

    enum CodingKeys: String, CodingKey {
        case token, username, expiresInSeconds, obtainedAt
    }

    init(token: String, username: String, expiresInSeconds: Int? = nil, obtainedAt: Date? = Date()) {
        self.token = token
        self.username = username
        self.expiresInSeconds = expiresInSeconds
        self.obtainedAt = obtainedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = (try? c.decode(String.self, forKey: .token)) ?? ""
        username = (try? c.decode(String.self, forKey: .username)) ?? ""
        expiresInSeconds = try? c.decode(Int.self, forKey: .expiresInSeconds)
        obtainedAt = DateCodec.parse(try? c.decode(String.self, forKey: .obtainedAt))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(token, forKey: .token)
        try c.encode(username, forKey: .username)
        try c.encodeIfPresent(expiresInSeconds, forKey: .expiresInSeconds)
        try c.encode(DateCodec.string(obtainedAt ?? Date()), forKey: .obtainedAt)
    }
}

struct CloudflareBackupMeta {
    var exists: Bool
    var size: Int?
    var uploadedAt: Date?
    var modifiedAt: Date?
    var etag: String?
}

enum CloudflareError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

/// Client for the Lifelog Cloudflare Worker sync API. The Worker stores only
/// client-side encrypted backup blobs and auth metadata.
struct CloudflareService {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    static func normalizeBaseURL(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return value }
        if !value.contains("://") { value = "https://\(value)" }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    private func url(_ baseURL: String, _ path: String) throws -> URL {
        let base = Self.normalizeBaseURL(baseURL)
        guard !base.isEmpty else { throw CloudflareError.message("Worker URL is required.") }
        guard let url = URL(string: base + path) else {
            throw CloudflareError.message("The Worker URL is not valid.")
        }
        return url
    }

    func checkHealth(baseURL: String) async throws {
        _ = try await request(URLRequest(url: try url(baseURL, "/api/health")))
    }

    func register(baseURL: String, username: String, password: String) async throws -> CloudflareSession {
        try await authenticate(baseURL: baseURL, path: "/api/auth/register", username: username, password: password)
    }

    func login(baseURL: String, username: String, password: String) async throws -> CloudflareSession {
        try await authenticate(baseURL: baseURL, path: "/api/auth/login", username: username, password: password)
    }

    private func authenticate(
        baseURL: String,
        path: String,
        username: String,
        password: String
    ) async throws -> CloudflareSession {
        var request = URLRequest(url: try url(baseURL, path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "username": username.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
        ])
        let data = try await self.request(request)
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = body["token"] as? String, !token.isEmpty,
              let user = (body["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !user.isEmpty else {
            throw CloudflareError.message("Invalid response from sync server.")
        }
        return CloudflareSession(
            token: token,
            username: user,
            expiresInSeconds: (body["expiresInSeconds"] as? NSNumber)?.intValue,
            obtainedAt: Date()
        )
    }

    func getBackupMeta(baseURL: String, token: String) async throws -> CloudflareBackupMeta {
        var request = URLRequest(url: try url(baseURL, "/api/backup/meta"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data = try await self.request(request)
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudflareError.message("Could not check cloud backup.")
        }
        guard (body["exists"] as? Bool) == true else {
            return CloudflareBackupMeta(exists: false)
        }
        return CloudflareBackupMeta(
            exists: true,
            size: (body["size"] as? NSNumber)?.intValue,
            uploadedAt: DateCodec.parse(body["uploadedAt"] as? String),
            modifiedAt: DateCodec.parse(body["modifiedAt"] as? String),
            etag: body["etag"] as? String
        )
    }

    func uploadBackup(baseURL: String, token: String, bytes: Data) async throws {
        var request = URLRequest(url: try url(baseURL, "/api/backup"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = bytes
        _ = try await self.request(request)
    }

    func downloadBackup(baseURL: String, token: String) async throws -> Data {
        var request = URLRequest(url: try url(baseURL, "/api/backup"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudflareError.message("Could not download backup.")
        }
        if http.statusCode == 401 { throw CloudflareError.message("Session expired. Please sign in again.") }
        if http.statusCode == 404 { throw CloudflareError.message("No cloud backup found.") }
        guard (200..<300).contains(http.statusCode) else {
            throw CloudflareError.message(Self.friendlyError(http.statusCode, fallback: "Could not download backup."))
        }
        return data
    }

    private func request(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudflareError.message("Could not reach the sync server.")
        }
        let message = Self.message(from: data)
        if http.statusCode == 401 {
            throw CloudflareError.message(message ?? "Session expired. Please sign in again.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CloudflareError.message(message ?? Self.friendlyError(http.statusCode, fallback: "Could not reach the sync server."))
        }
        return data
    }

    private static func message(from data: Data) -> String? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let raw = body["error"] ?? body["message"]
        guard let text = raw as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func friendlyError(_ status: Int, fallback: String) -> String {
        if status == 403 { return "Access denied." }
        if status == 404 { return "Not found." }
        if status >= 500 { return "Sync server error. Please try again later." }
        return fallback
    }
}
