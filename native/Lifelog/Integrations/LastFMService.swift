import Foundation

enum LastFMError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

/// Read-only Last.fm Web API client. Only a public API key is used; the shared
/// secret is never stored or sent.
struct LastFMService {
    private let base = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func fetchRecentTracks(
        username: String,
        apiKey: String,
        from: Date? = nil,
        to: Date? = nil,
        maxPages: Int = 10
    ) async throws -> [MusicScrobble] {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else { throw LastFMError.message("Enter your Last.fm username.") }
        guard !key.isEmpty else {
            throw LastFMError.message("A Last.fm API key is required to sync listening history. Add your API key in Last.fm settings, then try again.")
        }

        var results: [MusicScrobble] = []
        var page = 1
        var totalPages = 1

        while page <= totalPages && page <= maxPages {
            var query: [String: String] = [
                "method": "user.getrecenttracks",
                "user": user,
                "api_key": key,
                "format": "json",
                "limit": "200",
                "page": "\(page)",
                "extended": "1",
            ]
            if let from { query["from"] = "\(SafeNumber.truncatingInt(from.timeIntervalSince1970) ?? 0)" }
            if let to { query["to"] = "\(SafeNumber.truncatingInt(to.timeIntervalSince1970) ?? 0)" }
            guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { break }
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            guard let url = components.url else { break }

            let data: Data
            let urlResponse: URLResponse
            do {
                (data, urlResponse) = try await session.data(from: url)
            } catch {
                throw LastFMError.message("Could not reach Last.fm. Check your connection and try again.")
            }
            guard let response = urlResponse as? HTTPURLResponse else {
                throw LastFMError.message("Last.fm returned an unexpected response.")
            }
            guard response.statusCode == 200 else {
                var detail = "Last.fm returned HTTP \(response.statusCode)."
                if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = body["message"] as? String, !message.isEmpty {
                    detail = "Last.fm: \(message)"
                }
                throw LastFMError.message("\(detail) Check your username and API key.")
            }
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LastFMError.message("Last.fm returned an unexpected response.")
            }
            if let error = root["error"] {
                let message = root["message"] as? String ?? "request failed"
                throw LastFMError.message("Last.fm: \(message) (\(error))")
            }
            guard let recent = root["recenttracks"] as? [String: Any] else { break }
            let rawTracks: [Any]
            if let list = recent["track"] as? [Any] { rawTracks = list }
            else if let one = recent["track"] { rawTracks = [one] }
            else { rawTracks = [] }

            for raw in rawTracks {
                guard let track = raw as? [String: Any] else { continue }
                if let attrs = track["@attr"] as? [String: Any],
                   let nowPlaying = attrs["nowplaying"] as? String, nowPlaying == "true" { continue }
                guard let date = track["date"] as? [String: Any],
                      let uts = Int("\(date["uts"] ?? "")") else { continue }
                let artist: String
                if let artistObject = track["artist"] as? [String: Any] {
                    artist = artistObject["name"] as? String ?? ""
                } else {
                    artist = track["artist"] as? String ?? ""
                }
                let title = track["name"] as? String ?? ""
                guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let album: String
                if let albumObject = track["album"] as? [String: Any] {
                    album = albumObject["#text"] as? String ?? ""
                } else {
                    album = track["album"] as? String ?? ""
                }
                results.append(MusicScrobble(
                    artist: artist.trimmingCharacters(in: .whitespacesAndNewlines),
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    playedAt: Date(timeIntervalSince1970: TimeInterval(uts)),
                    album: album,
                    artworkUrl: Self.artwork(track["image"]),
                    source: "lastfm"
                ))
            }

            if let attrs = recent["@attr"] as? [String: Any],
               let pages = Int("\(attrs["totalPages"] ?? "")") { totalPages = pages }
            if rawTracks.count < 200 { break }
            page += 1
        }

        return results.sorted { $0.playedAt < $1.playedAt }
    }

    private static func artwork(_ raw: Any?) -> String? {
        guard let images = raw as? [Any] else { return nil }
        var best: String?
        for rawImage in images {
            guard let image = rawImage as? [String: Any],
                  let text = image["#text"] as? String else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { best = trimmed }
        }
        return best
    }
}
