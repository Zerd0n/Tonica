import Foundation

struct CoverResult: Identifiable, Hashable {
    var id: String { fullURL.absoluteString }
    let thumbURL: URL
    let fullURL: URL
    let title: String
    let subtitle: String
    let source: String
}

enum CoverSize: Int, CaseIterable, Identifiable {
    case medium = 600, large = 1200, max = 3000
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .medium: "600 px"
        case .large: "1200 px"
        case .max: "Максимум"
        }
    }
}

// iTunes Search API + Deezer API, ключи не нужны
enum CoverSearch {
    static func search(_ query: String, size: CoverSize) async -> [CoverResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        async let apple = itunes(q, size: size)
        async let deezer = deezer(q, size: size)
        let (a, d) = await (apple, deezer)

        var seen = Set<String>(), merged: [CoverResult] = []
        for i in 0..<max(a.count, d.count) {
            for r in [i < a.count ? a[i] : nil, i < d.count ? d[i] : nil].compactMap({ $0 }) {
                let key = (r.subtitle + "|" + r.title).lowercased()
                if seen.insert(key).inserted { merged.append(r) }
            }
        }
        return merged
    }

    private static func fetchJSON(_ url: URL) async -> [String: Any]? {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Tonica/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func itunes(_ q: String, size: CoverSize) async -> [CoverResult] {
        var results: [CoverResult] = []
        var seenAlbums = Set<Int>()
        for entity in ["song", "album"] {
            var c = URLComponents(string: "https://itunes.apple.com/search")!
            c.queryItems = [.init(name: "term", value: q), .init(name: "media", value: "music"),
                            .init(name: "entity", value: entity), .init(name: "limit", value: "25")]
            guard let json = await fetchJSON(c.url!), let items = json["results"] as? [[String: Any]] else { continue }
            for item in items {
                guard let art = item["artworkUrl100"] as? String, let thumb = URL(string: art) else { continue }
                if let cid = item["collectionId"] as? Int, !seenAlbums.insert(cid).inserted { continue }
                let px = size == .max ? 3000 : size.rawValue
                let suffix = size == .max ? "\(px)x\(px)bb-100.jpg" : "\(px)x\(px)bb.jpg"
                let full = art.replacingOccurrences(of: #"\d+x\d+bb\.jpg$"#, with: suffix, options: .regularExpression)
                guard let fullURL = URL(string: full) else { continue }
                let thumbBig = URL(string: art.replacingOccurrences(of: "100x100bb", with: "300x300bb")) ?? thumb
                results.append(CoverResult(
                    thumbURL: thumbBig, fullURL: fullURL,
                    title: item["collectionName"] as? String ?? "",
                    subtitle: item["artistName"] as? String ?? "",
                    source: "Apple Music"))
            }
        }
        return results
    }

    private static func deezer(_ q: String, size: CoverSize) async -> [CoverResult] {
        var results: [CoverResult] = []
        var seenAlbums = Set<Int>()
        for endpoint in ["search", "search/album"] {
            var c = URLComponents(string: "https://api.deezer.com/\(endpoint)")!
            c.queryItems = [.init(name: "q", value: q), .init(name: "limit", value: "25")]
            guard let json = await fetchJSON(c.url!), let items = json["data"] as? [[String: Any]] else { continue }
            for item in items {
                let album = (item["album"] as? [String: Any]) ?? item
                guard let id = album["id"] as? Int, seenAlbums.insert(id).inserted,
                      let xl = album["cover_xl"] as? String, let medium = album["cover_medium"] as? String,
                      let thumb = URL(string: medium) else { continue }
                // размер у deezer задаётся прямо в url
                let px = size == .max ? 1800 : size.rawValue
                let full = xl.replacingOccurrences(of: #"/\d+x\d+-"#, with: "/\(px)x\(px)-", options: .regularExpression)
                guard let fullURL = URL(string: full) else { continue }
                let artist = ((item["artist"] as? [String: Any]) ?? [:])["name"] as? String ?? ""
                results.append(CoverResult(
                    thumbURL: thumb, fullURL: fullURL,
                    title: album["title"] as? String ?? "", subtitle: artist, source: "Deezer"))
            }
        }
        return results
    }

    static func download(_ url: URL) async throws -> URL {
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue("Tonica/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw FFmpegError(message: "Сервер вернул код \(http.statusCode)")
        }
        return try TempFiles.storeImage(data: data)
    }
}
