import Foundation
import Security
import SwiftUI

enum HarvestTheme {
    static let green = Color(red: 0.18, green: 0.56, blue: 0.36)
    static let mint = Color(red: 0.46, green: 0.91, blue: 0.67)
    static let coral = Color(red: 0.91, green: 0.36, blue: 0.46)
    static let amber = Color(red: 0.94, green: 0.64, blue: 0.10)
    static let blue = Color(red: 0.20, green: 0.52, blue: 0.87)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.11)
    static let panel = Color(uiColor: .secondarySystemBackground)
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

struct APIError: LocalizedError {
    let statusCode: Int
    let message: String

    var errorDescription: String? { message }
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
    static let serverStatus = "/api/auth/server/status"
    static let serverRestart = "/api/auth/server/restart"
    static let dashboard = "/api/mysite/dashboard"
    static let sites = "/api/mysite/mysite"
    static let websiteToAdd = "/api/mysite/website/add"
    static let siteSearch = "/api/mysite/search"
    static let siteStatus = "/api/mysite/info/"
    static let siteSign = "/api/mysite/sign/"
    static let siteRepeat = "/api/mysite/repeat/"
    static let siteImport = "/api/mysite/import"
    static let downloaders = "/api/option/downloaders"
    static let downloaderSpeed = "/api/ws/downloader/speed"
    static let downloaderTorrents = "/api/ws/downloader"
    static let downloaderMain = "/api/option/downloaders/main/"
    static let downloaderControl = "/api/option/downloaders/control/"
    static let pushTorrent = "/api/option/push_torrent"
    static let schedules = "/api/option/schedule"
    static let taskTypes = "/api/option/tasks"
    static let crontabs = "/api/option/crontabs"
    static let taskResults = "/api/option/task-results/"
    static let taskExecute = "/api/option/exec"
    static let notices = "/api/option/notice"
    static let noticesRead = "/api/option/notice/read"
    static let options = "/api/option/options"
    static let notifyTest = "/api/option/test"
    static let tmdbSearch = "/api/tmdb/search"
    static let tmdbPopularMovies = "/api/tmdb/popular/movies"
    static let tmdbPopularTV = "/api/tmdb/popular/tvs"
    static let doubanSearch = "/api/option/douban/search"
    static let doubanHot = "/api/option/douban/hot"
    static let resourceSearch = "/api/mysite/torrents"
    static let adminUsers = "/api/auth/admin/users"
    static let users = "/api/auth/user"
    static let logs = "/api/logging"
    static let cacheClear = "/api/mysite/cache/clear"
    static let setupStatus = "/api/setup/status"
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
        return json
    }

    func streamSSE(
        baseURL: String,
        path: String,
        token: String,
        body: [String: Any]
    ) -> AsyncThrowingStream<[String: Any], Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    while normalized.hasSuffix("/") { normalized.removeLast() }
                    guard let url = URL(string: normalized + path) else {
                        throw APIError(statusCode: 0, message: "搜索地址无效")
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = HTTPMethod.post.rawValue
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw APIError(statusCode: 0, message: "搜索服务未返回有效响应")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw APIError(statusCode: http.statusCode, message: "资源搜索连接失败（\(http.statusCode)）")
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
        }
    }
}

enum KeychainStore {
    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "HarvestNative",
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
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "HarvestNative",
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
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "HarvestNative",
            kSecAttrAccount as String: key
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
    var isActive: Bool

    init(_ json: [String: Any]) {
        id = json.int("id") ?? 0
        username = json.string("username", "name") ?? "用户"
        email = json.string("email") ?? ""
        isSuperuser = json.bool("is_superuser", "isSuperuser", "admin") ?? false
        isActive = json.bool("is_active", "isActive") ?? true
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var isRestoringSession = true
    @Published var isAuthenticated = false
    @Published var isBusy = false
    @Published var profile: UserProfile?
    @Published var selectedTab = 2
    @Published var presentedError: String?
    @Published var appearance: AppAppearance
    @Published var privacyMode: Bool

    private(set) var baseURL: String
    private(set) var accessToken: String
    private(set) var refreshToken: String

    var colorScheme: ColorScheme? { appearance.scheme }
    var loginHistory: [LoginRecord] { loadLoginHistory() }

    init() {
        let defaults = UserDefaults.standard
        baseURL = defaults.string(forKey: "harvest.baseURL") ?? ""
        accessToken = KeychainStore.get("accessToken") ?? ""
        refreshToken = KeychainStore.get("refreshToken") ?? ""
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        privacyMode = defaults.bool(forKey: "privacyMode")
        Task { await restoreSession() }
    }

    func setAppearance(_ value: AppAppearance) {
        appearance = value
        UserDefaults.standard.set(value.rawValue, forKey: "appearance")
    }

    func setPrivacyMode(_ value: Bool) {
        privacyMode = value
        UserDefaults.standard.set(value, forKey: "privacyMode")
    }

    func restoreSession() async {
        defer { isRestoringSession = false }
        guard !baseURL.isEmpty, !accessToken.isEmpty else { return }
        do {
            try await loadProfile()
            isAuthenticated = true
        } catch let error as APIError where error.statusCode == 401 {
            do {
                try await refreshAccessToken()
                try await loadProfile()
                isAuthenticated = true
            } catch {
                clearSession()
            }
        } catch {
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

        isBusy = true
        defer { isBusy = false }
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
            baseURL = normalized
            accessToken = access
            refreshToken = tokens.string("refresh", "refresh_token", "refreshToken") ?? ""
            UserDefaults.standard.set(normalized, forKey: "harvest.baseURL")
            KeychainStore.set(accessToken, for: "accessToken")
            KeychainStore.set(refreshToken, for: "refreshToken")
            KeychainStore.set(password, for: "password.\(normalized).\(username)")
            saveLoginRecord(server: normalized, username: username)
            try await loadProfile(fallbackUsername: username)
            isAuthenticated = true
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func requiresSetup(server: String) async -> Bool? {
        let normalized = normalizeServer(server)
        guard let url = URL(string: normalized), url.scheme == "http" || url.scheme == "https" else { return nil }
        do {
            let raw = try await APIClient.shared.request(baseURL: normalized, path: APIPath.setupStatus)
            return jsonPayloadDictionary(raw)?.bool("needs_setup", "needsSetup")
        } catch {
            return nil
        }
    }

    func setupDatabase(server: String, payload: [String: Any]) async throws {
        _ = try await APIClient.shared.request(
            baseURL: normalizeServer(server),
            path: "/api/setup/database",
            method: .post,
            body: payload
        )
    }

    func setupAdministrator(server: String, username: String, password: String) async throws {
        _ = try await APIClient.shared.request(
            baseURL: normalizeServer(server),
            path: "/api/setup/init",
            method: .post,
            body: ["admin_user": username, "admin_pass": password]
        )
    }

    func logout() {
        clearSession()
    }

    func quickLogin(_ record: LoginRecord) async {
        guard let password = KeychainStore.get("password.\(record.server).\(record.username)") else {
            presentedError = "该账号没有已保存的密码，请重新输入"
            return
        }
        await login(server: record.server, username: record.username, password: password)
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
            return try await APIClient.shared.request(
                baseURL: baseURL,
                path: path,
                method: method,
                token: accessToken,
                query: query,
                body: body
            )
        } catch let error as APIError where error.statusCode == 401 && retry && !refreshToken.isEmpty {
            try await refreshAccessToken()
            return try await api(path, method: method, query: query, body: body, retry: false)
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

    private func loadProfile(fallbackUsername: String = "") async throws {
        let raw = try await APIClient.shared.request(
            baseURL: baseURL,
            path: APIPath.userInfo,
            token: accessToken
        )
        if let dict = jsonPayloadDictionary(raw) {
            profile = UserProfile(dict)
            if profile?.isSuperuser != true && ![0, 3, 5].contains(selectedTab) {
                selectedTab = 3
            }
        } else if !fallbackUsername.isEmpty {
            profile = UserProfile(["username": fallbackUsername])
            selectedTab = 3
        }
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
        isAuthenticated = false
        KeychainStore.delete("accessToken")
        KeychainStore.delete("refreshToken")
    }

    private func normalizeServer(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasSuffix("/") { result.removeLast() }
        return result
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

func jsonMessage(_ value: Any) -> String? {
    if let text = value as? String { return text }
    guard let dict = jsonDictionary(value) else { return nil }
    for key in ["message", "msg", "info", "detail", "error", "result", "data"] {
        if let text = dict[key] as? String, !text.isEmpty { return text }
        if let nested = dict[key], let text = jsonMessage(nested) { return text }
    }
    return nil
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
