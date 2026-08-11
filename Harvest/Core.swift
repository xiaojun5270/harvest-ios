import Foundation
import Security
import SwiftUI
import UserNotifications
import WebKit

enum HarvestTheme {
    static let green = Color(red: 0.18, green: 0.56, blue: 0.36)
    static let mint = Color(red: 0.46, green: 0.91, blue: 0.67)
    static let coral = Color(red: 0.91, green: 0.36, blue: 0.46)
    static let amber = Color(red: 0.94, green: 0.64, blue: 0.10)
    static let blue = Color(red: 0.20, green: 0.52, blue: 0.87)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.11)
    static let panel = Color(uiColor: .secondarySystemBackground)
    static let cardCornerRadius: CGFloat = 24
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"

    var id: String { rawValue }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppAccent: String, CaseIterable, Identifiable {
    case harvest
    case slate
    case gray
    case zinc
    case neutral
    case stone
    case red
    case orange
    case amber
    case yellow
    case lime
    case green
    case emerald
    case teal
    case cyan
    case sky
    case blue
    case indigo
    case violet
    case purple
    case fuchsia
    case pink
    case rose

    var id: String { rawValue }
    var title: String {
        switch self {
        case .harvest: "Harvest"
        case .slate: "石板"
        case .gray: "灰色"
        case .zinc: "锌灰"
        case .neutral: "中性"
        case .stone: "石色"
        case .red: "红色"
        case .orange: "橙色"
        case .amber: "琥珀"
        case .yellow: "黄色"
        case .lime: "青柠"
        case .green: "绿色"
        case .emerald: "翠绿"
        case .teal: "蓝绿"
        case .cyan: "青色"
        case .sky: "天蓝"
        case .blue: "蓝色"
        case .indigo: "靛蓝"
        case .violet: "紫罗兰"
        case .purple: "紫色"
        case .fuchsia: "品红"
        case .pink: "粉色"
        case .rose: "玫瑰"
        }
    }
    var color: Color {
        switch self {
        case .harvest: HarvestTheme.green
        case .slate: Self.rgb(0x64748B)
        case .gray: Self.rgb(0x6B7280)
        case .zinc: Self.rgb(0x71717A)
        case .neutral: Self.rgb(0x737373)
        case .stone: Self.rgb(0x78716C)
        case .red: Self.rgb(0xEF4444)
        case .orange: Self.rgb(0xF97316)
        case .amber: Self.rgb(0xF59E0B)
        case .yellow: Self.rgb(0xEAB308)
        case .lime: Self.rgb(0x84CC16)
        case .green: Self.rgb(0x22C55E)
        case .emerald: Self.rgb(0x10B981)
        case .teal: Self.rgb(0x14B8A6)
        case .cyan: Self.rgb(0x06B6D4)
        case .sky: Self.rgb(0x0EA5E9)
        case .blue: Self.rgb(0x3B82F6)
        case .indigo: Self.rgb(0x6366F1)
        case .violet: Self.rgb(0x8B5CF6)
        case .purple: Self.rgb(0xA855F7)
        case .fuchsia: Self.rgb(0xD946EF)
        case .pink: Self.rgb(0xEC4899)
        case .rose: Self.rgb(0xF43F5E)
        }
    }

    private static func rgb(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

enum AppInterfaceDensity: String, CaseIterable, Identifiable {
    case compact = "紧凑"
    case standard = "标准"
    case spacious = "宽松"

    var id: String { rawValue }
    var controlSize: ControlSize {
        switch self {
        case .compact: .small
        case .standard: .regular
        case .spacious: .large
        }
    }
    var minimumRowHeight: CGFloat {
        switch self {
        case .compact: 38
        case .standard: 44
        case .spacious: 52
        }
    }
}

enum AppInterfaceScale: String, CaseIterable, Identifiable {
    case compact = "紧凑"
    case system = "跟随系统"
    case large = "大号"

    var id: String { rawValue }
}

struct APIError: LocalizedError {
    let statusCode: Int
    let message: String

    var errorDescription: String? { message }
}

enum AppLogLevel: String, Codable, CaseIterable, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

struct AppLogRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: AppLogLevel
    let message: String
}

actor AppLogStore {
    static let shared = AppLogStore()

    private let fileURL: URL
    private var records: [AppLogRecord]

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Harvest", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("app-log.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([AppLogRecord].self, from: data) {
            records = Array(decoded.suffix(2_000))
        } else {
            records = []
        }
    }

    func append(_ level: AppLogLevel, _ message: String) {
        records.append(AppLogRecord(id: UUID(), timestamp: Date(), level: level, message: message))
        if records.count > 2_000 { records.removeFirst(records.count - 2_000) }
        persist()
    }

    func snapshot() -> [AppLogRecord] { records }

    func clear() {
        records.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

func recordAppLog(_ level: AppLogLevel, _ message: String) {
    Task { await AppLogStore.shared.append(level, message) }
}

struct AppSessionCacheRecord: Sendable {
    let payload: Data
    let cachedAt: Date
}

actor AppSessionCache {
    static let shared = AppSessionCache()

    private struct Envelope: Codable {
        let scope: String
        let name: String
        let cachedAt: Date
        let payload: Data
    }

    private let directoryURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directoryURL = base
            .appendingPathComponent("Harvest", isDirectory: true)
            .appendingPathComponent("session-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func read(scope: String, name: String) -> AppSessionCacheRecord? {
        let url = fileURL(scope: scope, name: name)
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.scope == scope,
              envelope.name == name else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return AppSessionCacheRecord(payload: envelope.payload, cachedAt: envelope.cachedAt)
    }

    func write(scope: String, name: String, payload: Data) {
        let envelope = Envelope(scope: scope, name: name, cachedAt: Date(), payload: payload)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? data.write(to: fileURL(scope: scope, name: name), options: .atomic)
    }

    func remove(scope: String, name: String) {
        try? FileManager.default.removeItem(at: fileURL(scope: scope, name: name))
    }

    func clear(scope: String) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
                  envelope.scope == scope else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: directoryURL)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func fileURL(scope: String, name: String) -> URL {
        directoryURL.appendingPathComponent(stableHash("\(scope)|\(name)")).appendingPathExtension("json")
    }

    private func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

enum APIPath {
    static let tokenPair = "/api/token/pair"
    static let tokenRefresh = "/api/token/refresh"
    static let userInfo = "/api/auth/userinfo"
    static let authInfo = "/api/auth/auth_info"
    static let serverStatus = "/api/auth/server/status"
    static let serverRestart = "/api/auth/server/restart"
    static let dashboard = "/api/mysite/dashboard"
    static let websiteList = "/api/mysite/website"
    static let sites = "/api/mysite/mysite"
    static let websiteToAdd = "/api/mysite/website/add"
    static let siteSearch = "/api/mysite/search"
    static let siteStatus = "/api/mysite/info/"
    static let siteSign = "/api/mysite/sign/"
    static let siteRepeat = "/api/mysite/repeat/"
    static let siteImport = "/api/mysite/import"
    static let siteImportTOML = "/api/mysite/import/toml"
    static let siteBulkUpgrade = "/api/mysite/bulk/upgrade"
    static let siteImportPTPP = "/api/mysite/cookie/ptpp"
    static let siteImportPTD = "/api/mysite/cookie/ptd"
    static let siteImportCookieCloud = "/api/mysite/cookie/cloud"
    static let siteStatusChart = "/api/mysite/status/chart/v2"
    static let siteSort = "/api/mysite/sort"
    static let siteStatusToday = "/api/mysite/status/today"
    static let downloaders = "/api/option/downloaders"
    static let downloaderSpeed = "/api/ws/downloader/speed"
    static let downloaderTorrents = "/api/ws/downloader"
    static let downloaderMain = "/api/option/downloaders/main/"
    static let downloaderControl = "/api/option/downloaders/control/"
    static let downloaderPreferences = "/api/option/downloaders/preferences/"
    static let downloaderTorrentDetail = "/api/option/downloaders/torrent/detail/"
    static let downloaderToggleSpeed = "/api/option/downloaders/toggle_speed_limit/"
    static let downloaderTest = "/api/option/downloaders/test/"
    static let downloaderTags = "/api/option/downloaders/tags/"
    static let downloaderSetTags = "/api/option/downloaders/tags/set/"
    static let downloaderCategories = "/api/option/downloaders/category/"
    static let downloaderSetCategory = "/api/option/downloaders/category/set/"
    static let downloaderReplaceTrackers = "/api/option/downloaders/trackers/replace/"
    static let downloaderRepeat = "/api/option/repeat"
    static let downloaderPaths = "/api/option/paths"
    static let pushTorrent = "/api/option/push_torrent"
    static let pushTorrentMonkey = "/api/option/push_monkey/"
    static let schedules = "/api/option/schedule"
    static let taskTypes = "/api/option/tasks"
    static let crontabs = "/api/option/crontabs"
    static let taskResults = "/api/option/task-results/"
    static let taskExecute = "/api/option/exec"
    static let notices = "/api/option/notice"
    static let noticesRead = "/api/option/notice/read"
    static let options = "/api/option/options"
    static let notifyTest = "/api/option/test"
    static let telegramWebhook = "/api/option/tg/webhook"
    static let speedTest = "/api/option/speedtest"
    static let programUpdate = "/api/option/update/"
    static let tmdbSearch = "/api/tmdb/search"
    static let tmdbMovie = "/api/tmdb/movie/"
    static let tmdbTV = "/api/tmdb/tv/"
    static let tmdbPerson = "/api/tmdb/person/"
    static let tmdbPopularMovies = "/api/tmdb/popular/movies"
    static let tmdbPopularTV = "/api/tmdb/popular/tvs"
    static let tmdbPlayingMovies = "/api/tmdb/playing/movies"
    static let tmdbUpcomingMovies = "/api/tmdb/upcoming/movies"
    static let tmdbTopMovies = "/api/tmdb/top_rated/movies"
    static let tmdbAiringTodayTV = "/api/tmdb/airing_today/tvs"
    static let tmdbOnTheAirTV = "/api/tmdb/on_the_air/tvs"
    static let tmdbTopTV = "/api/tmdb/top_rated/tvs"
    static let doubanSearch = "/api/option/douban/search"
    static let doubanHot = "/api/option/douban/hot"
    static let doubanTop250 = "/api/option/douban/top250"
    static let doubanRank = "/api/option/douban/rank"
    static let doubanTags = "/api/option/douban/tags"
    static let doubanSubject = "/api/option/douban/subject/"
    static let resourceSearch = "/api/mysite/torrents"
    static let adminUsers = "/api/auth/admin/users"
    static let adminSendToken = "/api/auth/admin/send"
    static let adminResetToken = "/api/auth/admin/reset/token"
    static let adminResetInvite = "/api/auth/admin/reset/invite/"
    static let adminCacheClear = "/api/auth/admin/cache/clear"
    static let users = "/api/auth/user"
    static let logs = "/api/auth/logs"
    static let logsStream = "/api/auth/logs/stream"
    static let updateLog = "/api/auth/update/log"
    static let updateSites = "/api/auth/update/sites"
    static let appVersionLatest = "/api/app/version/latest"
    static let appVersionList = "/api/app/version/list"
    static let cacheClear = "/api/mysite/cache/clear"
    static let setupStatus = "/api/setup/status"
    static let setupDatabase = "/api/setup/database"
    static let setupInit = "/api/setup/init"
    static let setupImport = "/api/setup/import"
    static let setupSQLite = "/api/setup/sqlite"
    static let setupBackup = "/api/setup/backup"
    static let wechatQRCode = "/api/option/wechatbot/qrcode"
    static let wechatQRCodeStatus = "/api/option/wechatbot/qrcode/status"
}

struct MultipartPart {
    let fieldName: String
    let fileName: String
    let mimeType: String
    let data: Data
}

final class APIClient {
    static let shared = APIClient()
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    func request(
        baseURL: String,
        path: String,
        method: HTTPMethod = .get,
        token: String? = nil,
        query: [String: Any] = [:],
        body: Any? = nil
    ) async throws -> Any {
        var normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") { normalized.removeLast() }
        guard var components = URLComponents(string: normalized + path) else {
            throw APIError(statusCode: 0, message: "服务器地址无效")
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: String(describing: $0.value)) }
        }
        guard let url = components.url else {
            throw APIError(statusCode: 0, message: "请求地址无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Harvest-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(statusCode: 0, message: "服务器未返回有效响应")
        }
        let json: Any
        if data.isEmpty {
            json = [:]
        } else {
            json = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ??
                String(data: data, encoding: .utf8) ?? [:]
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(statusCode: http.statusCode, message: jsonMessage(json) ?? "请求失败（\(http.statusCode)）")
        }
        if let businessError = jsonBusinessError(json, fallback: "请求失败") {
            throw businessError
        }
        return json
    }

    func upload(
        baseURL: String,
        path: String,
        token: String,
        fields: [String: String] = [:],
        parts: [MultipartPart],
        query: [String: Any] = [:]
    ) async throws -> Any {
        var normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") { normalized.removeLast() }
        guard var components = URLComponents(string: normalized + path) else {
            throw APIError(statusCode: 0, message: "上传地址无效")
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: String(describing: $0.value)) }
        }
        guard let url = components.url else { throw APIError(statusCode: 0, message: "上传地址无效") }

        let boundary = "HarvestBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var data = Data()
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            data.append(Data("--\(boundary)\r\n".utf8))
            data.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            data.append(Data("\(value)\r\n".utf8))
        }
        for part in parts {
            let fileName = part.fileName.replacingOccurrences(of: "\"", with: "_")
            data.append(Data("--\(boundary)\r\n".utf8))
            data.append(Data("Content-Disposition: form-data; name=\"\(part.fieldName)\"; filename=\"\(fileName)\"\r\n".utf8))
            data.append(Data("Content-Type: \(part.mimeType)\r\n\r\n".utf8))
            data.append(part.data)
            data.append(Data("\r\n".utf8))
        }
        data.append(Data("--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Harvest-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(statusCode: 0, message: "服务器未返回有效响应")
        }
        let value: Any = responseData.isEmpty
            ? [:]
            : ((try? JSONSerialization.jsonObject(with: responseData, options: [.fragmentsAllowed]))
                ?? String(data: responseData, encoding: .utf8)
                ?? [:])
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(statusCode: http.statusCode, message: jsonMessage(value) ?? "上传失败（\(http.statusCode)）")
        }
        if let businessError = jsonBusinessError(value, fallback: "上传失败") { throw businessError }
        return value
    }

    func download(
        baseURL: String,
        path: String,
        token: String,
        query: [String: Any] = [:],
        method: HTTPMethod = .get,
        body: [String: Any]? = nil
    ) async throws -> (data: Data, fileName: String?) {
        var normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") { normalized.removeLast() }
        guard var components = URLComponents(string: normalized + path) else {
            throw APIError(statusCode: 0, message: "下载地址无效")
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: String(describing: $0.value)) }
        }
        guard let url = components.url else { throw APIError(statusCode: 0, message: "下载地址无效") }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Harvest-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(statusCode: 0, message: "服务器未返回有效响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let value = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
                ?? String(data: data, encoding: .utf8)
                ?? [:]
            throw APIError(statusCode: http.statusCode, message: jsonMessage(value) ?? "下载失败（\(http.statusCode)）")
        }
        return (data, responseFileName(http.value(forHTTPHeaderField: "Content-Disposition")))
    }

    private func responseFileName(_ disposition: String?) -> String? {
        guard let disposition, !disposition.isEmpty else { return nil }
        if let range = disposition.range(of: "filename*=UTF-8''", options: .caseInsensitive) {
            let encoded = disposition[range.upperBound...].split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
            return encoded.removingPercentEncoding ?? encoded
        }
        guard let range = disposition.range(of: "filename=", options: .caseInsensitive) else { return nil }
        return disposition[range.upperBound...]
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: " \""))
    }

    func streamSSE(
        baseURL: String,
        path: String,
        token: String,
        method: HTTPMethod = .post,
        query: [String: Any] = [:],
        body: [String: Any]? = nil
    ) -> AsyncThrowingStream<[String: Any], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    while normalized.hasSuffix("/") { normalized.removeLast() }
                    guard var components = URLComponents(string: normalized + path) else {
                        throw APIError(statusCode: 0, message: "流式请求地址无效")
                    }
                    if !query.isEmpty {
                        components.queryItems = query.map {
                            URLQueryItem(name: $0.key, value: String(describing: $0.value))
                        }
                    }
                    guard let url = components.url else {
                        throw APIError(statusCode: 0, message: "流式请求地址无效")
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = method.rawValue
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    if let body {
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    }

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw APIError(statusCode: 0, message: "流式服务未返回有效响应")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw APIError(statusCode: http.statusCode, message: "流式连接失败（\(http.statusCode)）")
                    }
                    for try await line in bytes.lines {
                        var payload = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if payload.hasPrefix("data:") { payload = String(payload.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
                        guard !payload.isEmpty, let data = payload.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data),
                              let event = object as? [String: Any] else { continue }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func streamWebSocket(
        baseURL: String,
        path: String,
        token: String,
        subscription: [String: Any]
    ) -> AsyncThrowingStream<[String: Any], Error> {
        AsyncThrowingStream { continuation in
            var normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            while normalized.hasSuffix("/") { normalized.removeLast() }
            if normalized.hasPrefix("https://") { normalized.replaceSubrange(normalized.startIndex..<normalized.index(normalized.startIndex, offsetBy: 5), with: "wss") }
            else if normalized.hasPrefix("http://") { normalized.replaceSubrange(normalized.startIndex..<normalized.index(normalized.startIndex, offsetBy: 4), with: "ws") }
            guard var components = URLComponents(string: normalized + path) else {
                continuation.finish(throwing: APIError(statusCode: 0, message: "WebSocket 地址无效"))
                return
            }
            var queryItems = components.queryItems ?? []
            if !token.isEmpty, !queryItems.contains(where: { $0.name == "token" }) {
                queryItems.append(URLQueryItem(name: "token", value: token))
            }
            components.queryItems = queryItems
            guard let url = components.url else {
                continuation.finish(throwing: APIError(statusCode: 0, message: "WebSocket 地址无效"))
                return
            }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("Harvest-iOS/1.0", forHTTPHeaderField: "User-Agent")
            let socket = session.webSocketTask(with: request)
            let task = Task {
                do {
                    socket.resume()
                    let subscriptionData = try JSONSerialization.data(withJSONObject: subscription)
                    guard let subscriptionText = String(data: subscriptionData, encoding: .utf8) else {
                        throw APIError(statusCode: 0, message: "WebSocket 订阅参数无效")
                    }
                    try await socket.send(.string(subscriptionText))
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        let data: Data
                        switch message {
                        case .string(let text): data = Data(text.utf8)
                        case .data(let value): data = value
                        @unknown default: continue
                        }
                        guard let object = try? JSONSerialization.jsonObject(with: data),
                              let event = object as? [String: Any] else { continue }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    if Task.isCancelled { continuation.finish() }
                    else { continuation.finish(throwing: error) }
                }
                socket.cancel(with: .goingAway, reason: nil)
            }
            continuation.onTermination = { _ in
                task.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }
}

enum KeychainStore {
    private static var service: String { Bundle.main.bundleIdentifier ?? "HarvestNative" }

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct LoginRecord: Codable, Identifiable, Hashable {
    let server: String
    let username: String
    var lastUsed: Date
    var id: String { "\(server)|\(username)" }
}

struct UserProfile: Identifiable {
    var id: Int
    var username: String
    var email: String
    var isSuperuser: Bool
    var isStaff: Bool
    var isActive: Bool

    init(_ json: [String: Any]) {
        id = json.int("id") ?? 0
        username = json.string("username", "name") ?? "用户"
        email = json.string("email") ?? ""
        isSuperuser = json.bool("is_superuser", "isSuperuser", "admin") ?? false
        isStaff = json.bool("is_staff", "isStaff", "staff") ?? false
        isActive = json.bool("is_active", "isActive") ?? true
    }
}

struct SetupDatabaseDefaults {
    let type: String
    let host: String
    let port: String
    let name: String
    let user: String
    let password: String
    let hasPassword: Bool

    init(_ json: [String: Any]) {
        type = json.string("type", "database_type", "databaseType") ?? ""
        host = json.string("host") ?? ""
        port = json.string("port") ?? ""
        name = json.string("name", "database", "path") ?? ""
        user = json.string("user", "username") ?? ""
        password = json.string("pass", "password") ?? ""
        hasPassword = json.bool("has_password", "hasPassword") ?? !password.isEmpty
    }
}

struct HarvestSetupStatus {
    let initialized: Bool
    let needsSetup: Bool
    let databaseDefaults: [String: SetupDatabaseDefaults]

    init(_ raw: Any) {
        let payload = jsonPayloadDictionary(raw) ?? [:]
        initialized = payload.bool("initialized") ?? false
        needsSetup = payload.bool("needs_setup", "needsSetup") ?? false

        var defaults: [String: SetupDatabaseDefaults] = [:]
        if let values = payload.dict("database_defaults", "databaseDefaults") {
            for (key, value) in values {
                guard let dictionary = value as? [String: Any] else { continue }
                defaults[key.lowercased()] = SetupDatabaseDefaults(dictionary)
            }
        }
        databaseDefaults = defaults
    }

    func defaults(for type: String) -> SetupDatabaseDefaults? {
        let normalized = type.lowercased()
        if let value = databaseDefaults[normalized] { return value }
        let aliases = normalized == "pgsql" ? ["postgres", "postgresql"] : [normalized]
        for alias in aliases {
            if let value = databaseDefaults[alias] { return value }
        }
        return databaseDefaults.values.first { value in
            let candidate = value.type.lowercased()
            return candidate == normalized || aliases.contains(candidate)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var isRestoringSession = true
    @Published var isAuthenticated = false
    @Published var isBusy = false
    @Published var profile: UserProfile?
    @Published var canOpenAdminUsers = false
    @Published var selectedTab = 2
    @Published var pendingResourceSearch: String?
    @Published var presentedError: String?
    @Published var appearance: AppAppearance
    @Published var accent: AppAccent
    @Published var interfaceDensity: AppInterfaceDensity
    @Published var interfaceScale: AppInterfaceScale
    @Published var privacyMode: Bool
    @Published var mediaTMDBEnabled: Bool
    @Published var mediaDoubanEnabled: Bool
    @Published var autoRefreshMinutes: Int
    @Published var refreshGeneration = 0
    @Published var sessionGeneration = 0
    @Published var unreadNoticeCount = 0
    @Published var noticePresentationGeneration = 0

    private(set) var baseURL: String
    private(set) var accessToken: String
    private(set) var refreshToken: String
    private var lastAutomaticRefresh = Date.distantPast
    private var loginAttemptID: UUID?

    var colorScheme: ColorScheme? { appearance.scheme }
    var loginHistory: [LoginRecord] { loadLoginHistory() }

    init() {
        let defaults = UserDefaults.standard
        baseURL = defaults.string(forKey: "harvest.baseURL") ?? ""
        accessToken = KeychainStore.get("accessToken") ?? ""
        refreshToken = KeychainStore.get("refreshToken") ?? ""
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        accent = AppAccent(rawValue: defaults.string(forKey: "appearance.accent") ?? "") ?? .harvest
        interfaceDensity = AppInterfaceDensity(rawValue: defaults.string(forKey: "appearance.density") ?? "") ?? .standard
        interfaceScale = AppInterfaceScale(rawValue: defaults.string(forKey: "appearance.scale") ?? "") ?? .system
        privacyMode = defaults.bool(forKey: "privacyMode")
        mediaTMDBEnabled = defaults.bool(forKey: "media.tmdbEnabled")
        mediaDoubanEnabled = defaults.bool(forKey: "media.doubanEnabled")
        let savedRefreshMinutes = defaults.object(forKey: "app.autoRefreshMinutes") == nil ? 10 : defaults.integer(forKey: "app.autoRefreshMinutes")
        autoRefreshMinutes = min(max(savedRefreshMinutes, 1), 1_440)
        unreadNoticeCount = max(0, defaults.integer(forKey: "notifications.unreadCount"))
        recordAppLog(.info, "Harvest iOS 启动")
        Task { await restoreSession() }
    }

    func setAppearance(_ value: AppAppearance) {
        appearance = value
        UserDefaults.standard.set(value.rawValue, forKey: "appearance")
    }

    func setAccent(_ value: AppAccent) {
        accent = value
        UserDefaults.standard.set(value.rawValue, forKey: "appearance.accent")
    }

    func setInterfaceDensity(_ value: AppInterfaceDensity) {
        interfaceDensity = value
        UserDefaults.standard.set(value.rawValue, forKey: "appearance.density")
    }

    func setInterfaceScale(_ value: AppInterfaceScale) {
        interfaceScale = value
        UserDefaults.standard.set(value.rawValue, forKey: "appearance.scale")
    }

    func resetAppearanceSettings() {
        setAppearance(.system)
        setAccent(.harvest)
        setInterfaceDensity(.standard)
        setInterfaceScale(.system)
    }

    func setPrivacyMode(_ value: Bool) {
        privacyMode = value
        UserDefaults.standard.set(value, forKey: "privacyMode")
    }

    func setMediaTMDBEnabled(_ value: Bool) {
        mediaTMDBEnabled = value
        UserDefaults.standard.set(value, forKey: "media.tmdbEnabled")
    }

    func setMediaDoubanEnabled(_ value: Bool) {
        mediaDoubanEnabled = value
        UserDefaults.standard.set(value, forKey: "media.doubanEnabled")
    }

    func setAutoRefreshMinutes(_ value: Int) {
        autoRefreshMinutes = min(max(value, 1), 1_440)
        UserDefaults.standard.set(autoRefreshMinutes, forKey: "app.autoRefreshMinutes")
    }

    func requestAutomaticRefresh(force: Bool = false) {
        let interval = TimeInterval(autoRefreshMinutes * 60)
        guard force || Date().timeIntervalSince(lastAutomaticRefresh) >= interval else { return }
        lastAutomaticRefresh = Date()
        refreshGeneration &+= 1
        if isAuthenticated { Task { await refreshAuthorizationAccess() } }
    }

    func requestNotificationAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            recordAppLog(.warning, "通知权限请求失败：\(error.localizedDescription)")
        }
    }

    func refreshNoticeState(deliverNew: Bool = true) async {
        guard isAuthenticated else {
            await updateUnreadNoticeCount(0)
            return
        }
        do {
            let rows = jsonRows(try await api(APIPath.notices))
            let unreadRows = rows.filter { row in
                !(row.bool("is_read", "isRead", "read", "readed", "has_read")
                    ?? (row.string("read_at", "readAt", "read_time", "readTime") != nil))
            }
            await updateUnreadNoticeCount(unreadRows.count)

            let accountKey = "\(baseURL)|\(profile?.username ?? "")"
            let defaults = UserDefaults.standard
            var lastIDsByAccount = defaults.dictionary(forKey: "notifications.lastIDByAccount") ?? [:]
            var fallbackIDsByAccount = defaults.dictionary(forKey: "notifications.fallbackIDsByAccount") ?? [:]

            // Migrate the earlier snapshot-based baseline without replaying existing notices.
            let legacyByAccount = defaults.dictionary(forKey: "notifications.knownByAccount") ?? [:]
            let legacyIDs = legacyByAccount[accountKey] as? [String]
            let storedLastID = (lastIDsByAccount[accountKey] as? NSNumber)?.intValue
                ?? (lastIDsByAccount[accountKey] as? String).flatMap(Int.init)
            let legacyLastID = legacyIDs?.compactMap(Int.init).max()
            let lastNotifiedID = storedLastID ?? legacyLastID
            var fallbackIDs = fallbackIDsByAccount[accountKey] as? [String] ?? []
            var fallbackIDSet = Set(fallbackIDs)
            for identifier in legacyIDs ?? [] where Int(identifier) == nil && fallbackIDSet.insert(identifier).inserted {
                fallbackIDs.append(identifier)
            }
            let hadBaseline = lastNotifiedID != nil
                || fallbackIDsByAccount[accountKey] != nil
                || legacyIDs != nil

            if deliverNew && hadBaseline {
                for row in unreadRows {
                    let shouldDeliver: Bool
                    if let identifier = noticeNumericIdentifier(row) {
                        shouldDeliver = identifier > (lastNotifiedID ?? identifier)
                    } else {
                        shouldDeliver = !fallbackIDSet.contains(noticeIdentifier(row))
                    }
                    if shouldDeliver {
                        await deliverLocalNotice(row, badgeCount: unreadRows.count)
                    }
                }
            }

            if let currentMaximum = rows.compactMap(noticeNumericIdentifier).max() {
                lastIDsByAccount[accountKey] = max(lastNotifiedID ?? 0, currentMaximum)
            }
            for row in rows where noticeNumericIdentifier(row) == nil {
                let identifier = noticeIdentifier(row)
                if fallbackIDSet.insert(identifier).inserted { fallbackIDs.append(identifier) }
            }
            if fallbackIDs.count > 1_000 {
                fallbackIDs.removeFirst(fallbackIDs.count - 1_000)
            }
            if !fallbackIDs.isEmpty {
                fallbackIDsByAccount[accountKey] = fallbackIDs
            }
            defaults.set(lastIDsByAccount, forKey: "notifications.lastIDByAccount")
            defaults.set(fallbackIDsByAccount, forKey: "notifications.fallbackIDsByAccount")
        } catch {
            recordAppLog(.warning, "同步通知失败：\(error.localizedDescription)")
        }
    }

    func updateUnreadNoticeCount(_ count: Int) async {
        let normalized = max(0, count)
        unreadNoticeCount = normalized
        UserDefaults.standard.set(normalized, forKey: "notifications.unreadCount")
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.badgeSetting == .enabled else { return }
        do {
            try await center.setBadgeCount(normalized)
        } catch {
            recordAppLog(.warning, "同步应用角标失败：\(error.localizedDescription)")
        }
    }

    func clearDeliveredNotice(id: Int) {
        guard id > 0 else { return }
        let identifier = "harvest-notice-\(id)"
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func clearDeliveredNotices() {
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }

    func clearAllPersistentData() async {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.removeAllDeliveredNotifications()
        notificationCenter.removeAllPendingNotificationRequests()
        try? await notificationCenter.setBadgeCount(0)

        let dataStore = WKWebsiteDataStore.default()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dataStore.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            ) {
                continuation.resume()
            }
        }
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        URLCache.shared.removeAllCachedResponses()
        await AppLogStore.shared.clear()
        await AppSessionCache.shared.clearAll()
        KeychainStore.deleteAll()

        let defaults = UserDefaults.standard
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleIdentifier)
        } else {
            defaults.dictionaryRepresentation().keys.forEach(defaults.removeObject)
        }

        baseURL = ""
        accessToken = ""
        refreshToken = ""
        profile = nil
        canOpenAdminUsers = false
        isAuthenticated = false
        isRestoringSession = false
        isBusy = false
        selectedTab = 2
        pendingResourceSearch = nil
        presentedError = nil
        appearance = .system
        privacyMode = false
        mediaTMDBEnabled = false
        mediaDoubanEnabled = false
        autoRefreshMinutes = 10
        unreadNoticeCount = 0
        refreshGeneration = 0
        sessionGeneration = 0
        lastAutomaticRefresh = .distantPast
        loginAttemptID = nil
        objectWillChange.send()
    }

    private func noticeIdentifier(_ row: [String: Any]) -> String {
        if let id = row.string("id", "uuid", "notice_id", "noticeId"), !id.isEmpty { return id }
        if let id = row.int("id", "notice_id", "noticeId") { return String(id) }
        return [
            row.string("title", "subject", "name") ?? "",
            row.string("created_at", "create_time", "created", "time", "date") ?? "",
            row.string("content", "message", "text", "body") ?? ""
        ].joined(separator: "|")
    }

    private func noticeNumericIdentifier(_ row: [String: Any]) -> Int? {
        row.int("id", "notice_id", "noticeId")
    }

    private func deliverLocalNotice(_ row: [String: Any], badgeCount: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
        let content = UNMutableNotificationContent()
        content.title = row.string("title", "subject", "name") ?? "Harvest"
        content.body = row.string("content", "message", "text", "body") ?? "收到一条新消息"
        content.sound = .default
        content.badge = NSNumber(value: max(0, badgeCount))
        content.categoryIdentifier = "HARVEST_NOTICE"
        content.userInfo = ["noticeID": noticeIdentifier(row)]
        let request = UNNotificationRequest(
            identifier: "harvest-notice-\(noticeIdentifier(row))",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            recordAppLog(.warning, "投递本地通知失败：\(error.localizedDescription)")
        }
    }

    func restoreSession() async {
        defer { isRestoringSession = false }
        guard !baseURL.isEmpty, !accessToken.isEmpty else { return }
        do {
            try await loadProfile()
            isAuthenticated = true
            await refreshAuthorizationAccess()
            recordAppLog(.info, "已恢复 \(profile?.username ?? "用户") 的登录会话")
            await refreshNoticeState(deliverNew: false)
        } catch let error as APIError where error.statusCode == 401 {
            do {
                try await refreshAccessToken()
                try await loadProfile()
                isAuthenticated = true
                await refreshAuthorizationAccess()
                recordAppLog(.info, "刷新令牌后恢复登录会话")
                await refreshNoticeState(deliverNew: false)
            } catch {
                recordAppLog(.warning, "登录会话已失效：\(error.localizedDescription)")
                clearSession()
            }
        } catch {
            recordAppLog(.error, "恢复登录会话失败：\(error.localizedDescription)")
            presentedError = "无法恢复会话：\(error.localizedDescription)"
        }
    }

    func login(server: String, username: String, password: String) async {
        let normalized = normalizeServer(server)
        guard let url = URL(string: normalized), url.scheme == "http" || url.scheme == "https" else {
            presentedError = "请输入完整的 HTTP 或 HTTPS 服务器地址"
            return
        }
        guard !username.isEmpty, !password.isEmpty else {
            presentedError = "请输入账号和密码"
            return
        }

        let attemptID = UUID()
        loginAttemptID = attemptID
        isBusy = true
        defer {
            if loginAttemptID == attemptID {
                loginAttemptID = nil
                isBusy = false
            }
        }
        recordAppLog(.info, "正在登录 Harvest 服务")
        do {
            let raw = try await APIClient.shared.request(
                baseURL: normalized,
                path: APIPath.tokenPair,
                method: .post,
                body: ["username": username, "password": password]
            )
            if let businessError = jsonBusinessError(raw, fallback: "登录失败") {
                throw businessError
            }
            guard let tokens = jsonAuthTokenDictionary(raw),
                  let access = tokens.string("access", "access_token", "accessToken", "token") else {
                throw APIError(
                    statusCode: 0,
                    message: jsonMessage(raw) ?? "登录响应缺少访问令牌"
                )
            }
            let nextRefreshToken = tokens.string("refresh", "refresh_token", "refreshToken") ?? ""
            let nextProfile = try await fetchProfile(baseURL: normalized, token: access)
            guard loginAttemptID == attemptID else { return }

            let accountChanged = baseURL != normalized || profile?.username != nextProfile.username
            baseURL = normalized
            accessToken = access
            refreshToken = nextRefreshToken
            profile = nextProfile
            canOpenAdminUsers = false
            pendingResourceSearch = nil
            selectedTab = nextProfile.isSuperuser ? 2 : 3
            UserDefaults.standard.set(normalized, forKey: "harvest.baseURL")
            KeychainStore.set(accessToken, for: "accessToken")
            KeychainStore.set(refreshToken, for: "refreshToken")
            KeychainStore.set(password, for: "password.\(normalized).\(username)")
            saveLoginRecord(server: normalized, username: username)
            isAuthenticated = true
            sessionGeneration &+= 1
            if accountChanged {
                clearDeliveredNotices()
                unreadNoticeCount = 0
                UserDefaults.standard.set(0, forKey: "notifications.unreadCount")
                Task { _ = try? await UNUserNotificationCenter.current().setBadgeCount(0) }
            }
            await refreshAuthorizationAccess()
            recordAppLog(.info, "账号 \(username) 登录成功")
            await refreshNoticeState(deliverNew: false)
        } catch {
            guard loginAttemptID == attemptID else { return }
            recordAppLog(.error, "登录失败：\(error.localizedDescription)")
            presentedError = error.localizedDescription
        }
    }

    func fetchSetupStatus(server: String) async -> HarvestSetupStatus? {
        let normalized = normalizeServer(server)
        guard let url = URL(string: normalized), url.scheme == "http" || url.scheme == "https" else { return nil }
        do {
            let raw = try await APIClient.shared.request(baseURL: normalized, path: APIPath.setupStatus)
            return HarvestSetupStatus(raw)
        } catch {
            await AppLogStore.shared.append(.warning, "读取初始化状态失败：\(error.localizedDescription)")
            return nil
        }
    }

    func requiresSetup(server: String) async -> Bool? {
        await fetchSetupStatus(server: server)?.needsSetup
    }

    func setupDatabase(server: String, payload: [String: Any]) async throws {
        _ = try await APIClient.shared.request(
            baseURL: normalizeServer(server),
            path: APIPath.setupDatabase,
            method: .post,
            body: payload
        )
    }

    func setupAdministrator(
        server: String,
        username: String,
        password: String
    ) async throws {
        _ = try await APIClient.shared.request(
            baseURL: normalizeServer(server),
            path: APIPath.setupInit,
            method: .post,
            body: ["admin_user": username, "admin_pass": password]
        )
    }

    func openResourceSearch(_ query: String) {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        pendingResourceSearch = value
        selectedTab = 5
    }

    func logout() {
        recordAppLog(.info, "账号已退出登录")
        loginAttemptID = nil
        isBusy = false
        clearSession()
        Task { await updateUnreadNoticeCount(0) }
    }

    func quickLogin(_ record: LoginRecord) async {
        guard let password = savedPassword(for: record) else {
            presentedError = "该账号没有已保存的密码，请重新输入"
            return
        }
        await login(server: record.server, username: record.username, password: password)
    }

    func savedPassword(for record: LoginRecord) -> String? {
        KeychainStore.get("password.\(record.server).\(record.username)")
    }

    func readSessionCache(_ name: String) async -> (value: Any, cachedAt: Date)? {
        guard let scope = sessionCacheScope,
              let record = await AppSessionCache.shared.read(scope: scope, name: name),
              let value = try? JSONSerialization.jsonObject(with: record.payload, options: [.fragmentsAllowed]) else {
            return nil
        }
        return (value, record.cachedAt)
    }

    func writeSessionCache(_ value: Any, name: String) async {
        guard let scope = sessionCacheScope,
              JSONSerialization.isValidJSONObject(value),
              let payload = try? JSONSerialization.data(withJSONObject: value) else { return }
        await AppSessionCache.shared.write(scope: scope, name: name, payload: payload)
    }

    func removeSessionCache(_ name: String) async {
        guard let scope = sessionCacheScope else { return }
        await AppSessionCache.shared.remove(scope: scope, name: name)
    }

    func clearSessionCache() async {
        guard let scope = sessionCacheScope else { return }
        await AppSessionCache.shared.clear(scope: scope)
    }

    func removeLoginRecord(_ record: LoginRecord) {
        var records = loadLoginHistory()
        records.removeAll { $0.id == record.id }
        persistLoginHistory(records)
        KeychainStore.delete("password.\(record.server).\(record.username)")
        objectWillChange.send()
    }

    func api(
        _ path: String,
        method: HTTPMethod = .get,
        query: [String: Any] = [:],
        body: Any? = nil,
        retry: Bool = true
    ) async throws -> Any {
        do {
            let result = try await APIClient.shared.request(
                baseURL: baseURL,
                path: path,
                method: method,
                token: accessToken,
                query: query,
                body: body
            )
            return result
        } catch let error as APIError where error.statusCode == 401 && retry && !refreshToken.isEmpty {
            await AppLogStore.shared.append(.warning, "\(method.rawValue) \(path) 返回 401，正在刷新令牌")
            try await refreshAccessToken()
            return try await api(path, method: method, query: query, body: body, retry: false)
        } catch {
            await AppLogStore.shared.append(.error, "\(method.rawValue) \(path) 失败：\(error.localizedDescription)")
            throw error
        }
    }

    func upload(
        _ path: String,
        fields: [String: String] = [:],
        parts: [MultipartPart],
        retry: Bool = true
    ) async throws -> Any {
        do {
            let result = try await APIClient.shared.upload(
                baseURL: baseURL,
                path: path,
                token: accessToken,
                fields: fields,
                parts: parts
            )
            await AppLogStore.shared.append(.info, "POST \(path) 上传完成")
            return result
        } catch let error as APIError where error.statusCode == 401 && retry && !refreshToken.isEmpty {
            try await refreshAccessToken()
            return try await upload(path, fields: fields, parts: parts, retry: false)
        } catch {
            await AppLogStore.shared.append(.error, "POST \(path) 上传失败：\(error.localizedDescription)")
            throw error
        }
    }

    func download(
        _ path: String,
        query: [String: Any] = [:],
        method: HTTPMethod = .get,
        body: [String: Any]? = nil,
        retry: Bool = true
    ) async throws -> (data: Data, fileName: String?) {
        do {
            let result = try await APIClient.shared.download(
                baseURL: baseURL,
                path: path,
                token: accessToken,
                query: query,
                method: method,
                body: body
            )
            await AppLogStore.shared.append(.info, "\(method.rawValue) \(path) 下载完成")
            return result
        } catch let error as APIError where error.statusCode == 401 && retry && !refreshToken.isEmpty {
            try await refreshAccessToken()
            return try await download(path, query: query, method: method, body: body, retry: false)
        } catch {
            await AppLogStore.shared.append(.error, "\(method.rawValue) \(path) 下载失败：\(error.localizedDescription)")
            throw error
        }
    }

    func perform(
        _ path: String,
        method: HTTPMethod = .post,
        query: [String: Any] = [:],
        body: Any? = nil
    ) async -> Bool {
        do {
            _ = try await api(path, method: method, query: query, body: body)
            return true
        } catch {
            presentedError = error.localizedDescription
            return false
        }
    }

    func refreshAuthorizationAccess() async {
        guard isAuthenticated else {
            canOpenAdminUsers = false
            return
        }
        do {
            let payload = jsonPayloadDictionary(try await api(APIPath.authInfo))
            let username = payload?.string("username")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            canOpenAdminUsers = username == "ngfchl@126.com"
        } catch {
            canOpenAdminUsers = false
            recordAppLog(.warning, "读取授权管理访问条件失败：\(error.localizedDescription)")
        }
    }

    private func loadProfile() async throws {
        let nextProfile = try await fetchProfile(baseURL: baseURL, token: accessToken)
        profile = nextProfile
        if !nextProfile.isSuperuser && ![0, 3, 5].contains(selectedTab) {
            selectedTab = 3
        }
    }

    private func fetchProfile(baseURL: String, token: String) async throws -> UserProfile {
        let raw = try await APIClient.shared.request(
            baseURL: baseURL,
            path: APIPath.userInfo,
            token: token
        )
        guard let payload = jsonPayloadDictionary(raw),
              payload.string("username", "name") != nil else {
            throw APIError(statusCode: 0, message: jsonMessage(raw) ?? "用户信息响应无效")
        }
        return UserProfile(payload)
    }

    private func refreshAccessToken() async throws {
        guard !refreshToken.isEmpty else { throw APIError(statusCode: 401, message: "登录已过期") }
        let raw = try await APIClient.shared.request(
            baseURL: baseURL,
            path: APIPath.tokenRefresh,
            method: .post,
            body: ["refresh": refreshToken]
        )
        if let businessError = jsonBusinessError(raw, fallback: "登录已过期") {
            throw businessError
        }
        guard let tokens = jsonAuthTokenDictionary(raw),
              let next = tokens.string("access", "access_token", "accessToken", "token") else {
            throw APIError(statusCode: 401, message: "登录已过期")
        }
        accessToken = next
        KeychainStore.set(next, for: "accessToken")
        if let nextRefresh = tokens.string("refresh", "refresh_token", "refreshToken") {
            refreshToken = nextRefresh
            KeychainStore.set(nextRefresh, for: "refreshToken")
        }
    }

    private func clearSession() {
        accessToken = ""
        refreshToken = ""
        profile = nil
        canOpenAdminUsers = false
        isAuthenticated = false
        unreadNoticeCount = 0
        UserDefaults.standard.set(0, forKey: "notifications.unreadCount")
        KeychainStore.delete("accessToken")
        KeychainStore.delete("refreshToken")
        Task { _ = try? await UNUserNotificationCenter.current().setBadgeCount(0) }
    }

    private func normalizeServer(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasSuffix("/") { result.removeLast() }
        return result
    }

    private var sessionCacheScope: String? {
        let username = profile?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !baseURL.isEmpty, !username.isEmpty else { return nil }
        return "\(baseURL)|\(username.lowercased())"
    }

    private func saveLoginRecord(server: String, username: String) {
        var records = loadLoginHistory()
        records.removeAll { $0.server == server && $0.username == username }
        records.insert(LoginRecord(server: server, username: username, lastUsed: Date()), at: 0)
        persistLoginHistory(Array(records.prefix(12)))
    }

    private func loadLoginHistory() -> [LoginRecord] {
        guard let data = UserDefaults.standard.data(forKey: "loginHistory"),
              let records = try? JSONDecoder().decode([LoginRecord].self, from: data) else { return [] }
        return records.sorted { $0.lastUsed > $1.lastUsed }
    }

    private func persistLoginHistory(_ records: [LoginRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: "loginHistory")
    }
}

func jsonDictionary(_ value: Any) -> [String: Any]? {
    value as? [String: Any]
}

func jsonBusinessError(_ value: Any, fallback: String) -> APIError? {
    guard let dict = jsonDictionary(value) else { return nil }
    let code = dict.int("code")
    let failed = dict.bool("succeed") == false || (code != nil && code != 0)
    guard failed else { return nil }
    return APIError(statusCode: code ?? 0, message: jsonMessage(value) ?? fallback)
}

func jsonAuthTokenDictionary(_ value: Any, depth: Int = 0) -> [String: Any]? {
    guard depth < 6, let dict = jsonDictionary(value) else { return nil }
    if dict.string("access", "access_token", "accessToken", "token") != nil {
        return dict
    }
    for key in ["data", "result", "token", "tokens"] {
        if let nested = dict[key],
           let tokens = jsonAuthTokenDictionary(nested, depth: depth + 1) {
            return tokens
        }
    }
    return nil
}

func jsonPayloadDictionary(_ value: Any) -> [String: Any]? {
    guard let dict = jsonDictionary(value) else { return nil }
    for key in ["data", "result", "user"] {
        if let nested = dict[key] as? [String: Any] { return nested }
    }
    return dict
}

func jsonRows(_ value: Any) -> [[String: Any]] {
    if let rows = value as? [[String: Any]] { return rows }
    guard let dict = jsonDictionary(value) else { return [] }
    for key in ["data", "results", "items", "list", "rows", "records", "torrents", "tasks", "schedules", "notices", "users"] {
        if let rows = dict[key] as? [[String: Any]] { return rows }
        if let nested = dict[key] as? [String: Any] {
            let rows = jsonRows(nested)
            if !rows.isEmpty { return rows }
        }
    }
    let objectRows = dict.compactMap { key, value -> [String: Any]? in
        guard var row = value as? [String: Any] else { return nil }
        if row["id"] == nil && row["hash"] == nil { row["hash"] = key }
        return row
    }
    if !objectRows.isEmpty { return objectRows }
    return []
}

func jsonStrings(_ value: Any) -> [String] {
    if let values = value as? [String] { return values }
    guard let dict = jsonDictionary(value) else { return [] }
    for key in ["data", "results", "items", "list", "tasks"] {
        if let nested = dict[key] {
            let values = jsonStrings(nested)
            if !values.isEmpty { return values }
        }
    }
    return []
}

func jsonPathStrings(_ value: Any) -> [String] {
    let direct = jsonStrings(value)
    if !direct.isEmpty { return Array(Set(direct)).sorted() }
    let paths = jsonRows(value).compactMap {
        $0.string("path", "save_path", "savePath", "download_dir", "downloadDir", "value", "name")
    }
    return Array(Set(paths)).sorted()
}

func jsonMessage(_ value: Any) -> String? {
    if let text = value as? String { return text }
    guard let dict = jsonDictionary(value) else { return nil }
    for key in ["message", "msg", "info", "detail", "error", "result", "data"] {
        if let text = dict[key] as? String, !text.isEmpty { return text }
        if let nested = dict[key], let text = jsonMessage(nested) { return text }
    }
    return nil
}

func urlPathSegment(_ value: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#%")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

func prettyJSON(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
          let text = String(data: data, encoding: .utf8) else {
        return String(describing: value)
    }
    return text
}

func markdownAttributedString(_ value: String, inlineOnly: Bool = false) -> AttributedString {
    if inlineOnly {
        return (try? AttributedString(
            markdown: value,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(value)
    }
    return (try? AttributedString(
        markdown: value,
        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
    )) ?? AttributedString(value)
}

extension Notification.Name {
    static let harvestOpenNotices = Notification.Name("HarvestOpenNotices")
    static let harvestLocalUIReset = Notification.Name("HarvestLocalUIReset")
}

extension Dictionary where Key == String, Value == Any {
    func string(_ keys: String...) -> String? {
        for key in keys {
            if let value = self[key] as? String, !value.isEmpty { return value }
            if let value = self[key] as? NSNumber { return value.stringValue }
        }
        return nil
    }

    func int(_ keys: String...) -> Int? {
        for key in keys {
            if let value = self[key] as? Int { return value }
            if let value = self[key] as? NSNumber { return value.intValue }
            if let value = self[key] as? String, let number = Int(value) { return number }
        }
        return nil
    }

    func double(_ keys: String...) -> Double? {
        for key in keys {
            if let value = self[key] as? Double { return value }
            if let value = self[key] as? NSNumber { return value.doubleValue }
            if let value = self[key] as? String, let number = Double(value) { return number }
        }
        return nil
    }

    func bool(_ keys: String...) -> Bool? {
        for key in keys {
            if let value = self[key] as? Bool { return value }
            if let value = self[key] as? NSNumber { return value.boolValue }
            if let value = self[key] as? String {
                if ["true", "1", "yes", "on"].contains(value.lowercased()) { return true }
                if ["false", "0", "no", "off"].contains(value.lowercased()) { return false }
            }
        }
        return nil
    }

    func dict(_ keys: String...) -> [String: Any]? {
        for key in keys { if let value = self[key] as? [String: Any] { return value } }
        return nil
    }

    func rows(_ keys: String...) -> [[String: Any]] {
        for key in keys { if let value = self[key] { let rows = jsonRows(value); if !rows.isEmpty { return rows } } }
        return []
    }

    func strings(_ keys: String...) -> [String] {
        for key in keys {
            guard let value = self[key] else { continue }
            if let values = value as? [String] { return values }
            if let values = value as? [Any] {
                let result = values.compactMap { item -> String? in
                    if let text = item as? String { return text }
                    if let number = item as? NSNumber { return number.stringValue }
                    return nil
                }
                if !result.isEmpty { return result }
            }
        }
        return []
    }
}

func formatBytes(_ bytes: Double) -> String {
    guard bytes.isFinite else { return "--" }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB, .usePB]
    formatter.includesUnit = true
    return formatter.string(fromByteCount: Int64(max(0, bytes)))
}

func formatSpeed(_ bytes: Double) -> String {
    "\(formatBytes(bytes))/s"
}

func parseDate(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    let iso = ISO8601DateFormatter()
    if let date = iso.date(from: value) { return date }
    for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        if let date = formatter.date(from: value) { return date }
    }
    return nil
}
