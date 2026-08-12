import Charts
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct TrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let upload: Double
    let download: Double
}

struct DashboardServerPoint: Identifiable {
    let id = UUID()
    let date: Date
    let isDocker: Bool
    let cpu: Double
    let cpuUsageSeconds: Double
    let cpuLimitCores: Double
    let memory: Double
    let memoryUsage: Double
    let memoryWorkingSet: Double
    let memoryLimit: Double
    let uploadSpeed: Double
    let downloadSpeed: Double
    let bytesSent: Double
    let bytesReceived: Double
}

private enum DashboardServerRefreshDefaults {
    static let autoStartKey = "dashboard.serverResource.autoStart"
    static let intervalKey = "dashboard.serverResource.interval"
    static let durationKey = "dashboard.serverResource.duration"
    static let autoStart = true
    static let interval = 5
    static let duration = 5
    static let range = 1...60
}

private enum DashboardChartDefaults {
    static let height = 260.0
    static let heightRange = 120.0...480.0
    static let itemCount = 15
    static let itemCountRange = 10...50
}

struct DashboardDistributionItem: Identifiable {
    let name: String
    let value: Double
    var id: String { name }
}

struct DashboardSiteStatusItem: Identifiable {
    let name: String
    let uploaded: Double
    let downloaded: Double
    let published: Double
    var id: String { name }
}

struct DashboardSiteHistoryPoint {
    let key: String
    let uploaded: Double
    let downloaded: Double
    let published: Double
}

struct DashboardSiteHistorySeries: Identifiable {
    let name: String
    let points: [DashboardSiteHistoryPoint]
    var id: String { name }
}

struct DashboardSiteIncrementItem: Identifiable {
    let name: String
    let uploaded: Double
    let downloaded: Double
    var id: String { name }
}

struct DashboardMonthlyPoint: Identifiable {
    let key: String
    let uploaded: Double
    let downloaded: Double
    let published: Double
    var id: String { key }
}

struct DashboardSnapshot {
    var uploaded: Double = 0
    var downloaded: Double = 0
    var uploadSpeed: Double = 0
    var downloadSpeed: Double = 0
    var ratio: Double = 0
    var siteCount: Int = 0
    var seeding: Int = 0
    var seedVolume: Double = 0
    var leeching: Int = 0
    var published: Int = 0
    var todayUploaded: Double = 0
    var todayDownloaded: Double = 0
    var unread: Int = 0
    var cpu: Double = 0
    var memory: Double = 0
    var disk: Double = 0
    var trends: [TrendPoint] = []
    var usernameDistribution: [DashboardDistributionItem] = []
    var emailDistribution: [DashboardDistributionItem] = []
    var siteUploadDistribution: [DashboardDistributionItem] = []
    var siteDownloadDistribution: [DashboardDistributionItem] = []
    var seedDistribution: [DashboardDistributionItem] = []
    var todayUploadDistribution: [DashboardDistributionItem] = []
    var todayDownloadDistribution: [DashboardDistributionItem] = []
    var siteStatuses: [DashboardSiteStatusItem] = []
    var siteHistory: [DashboardSiteHistorySeries] = []
    var monthlyHistory: [DashboardMonthlyPoint] = []
    var earliestSite = ""
    var earliestJoinedAt = ""
    var updatedAt = ""

    init(_ raw: Any) {
        guard let root = jsonPayloadDictionary(raw) else { return }
        let overview = root.dict("overview", "summary", "statistics", "stats") ?? root
        uploaded = overview.double("totalUploaded", "total_uploaded", "uploaded", "upload", "upload_total", "total_upload") ?? 0
        downloaded = overview.double("totalDownloaded", "total_downloaded", "downloaded", "download", "download_total", "total_download") ?? 0
        uploadSpeed = overview.double("uploadSpeed", "upload_speed", "upspeed", "up_speed") ?? 0
        downloadSpeed = overview.double("downloadSpeed", "download_speed", "dlspeed", "down_speed") ?? 0
        ratio = overview.double("ratio", "share_ratio") ?? (downloaded > 0 ? uploaded / downloaded : 0)
        siteCount = overview.int("siteCount", "site_count", "sites") ?? 0
        seeding = overview.int("totalSeeding", "total_seeding", "seeding", "seeding_count", "seed_count") ?? 0
        seedVolume = overview.double("totalSeedVol", "total_seed_vol", "total_seed_volume", "seed_volume") ?? 0
        leeching = overview.int("totalLeeching", "total_leeching", "leeching") ?? 0
        published = overview.int("totalPublished", "total_published", "published") ?? 0
        todayUploaded = overview.double("todayUploadIncrement", "today_upload_increment") ?? 0
        todayDownloaded = overview.double("todayDownloadIncrement", "today_download_increment") ?? 0
        unread = overview.int("unread", "unread_count", "notice_count") ?? 0

        let resource = root.dict("server", "resource", "system", "server_resource") ?? [:]
        cpu = resource.double("cpu", "cpu_percent", "cpu_usage") ?? 0
        memory = resource.double("memory", "memory_percent", "memory_usage") ?? 0
        disk = resource.double("disk", "disk_percent", "disk_usage") ?? 0
        trends = dashboardTrendPoints(root)
        usernameDistribution = dashboardDistribution(root["usernameCount"] ?? root["username_count"])
        emailDistribution = dashboardDistribution(root["emailCount"] ?? root["email_count"])
        let statuses = root.rows("statusList", "status_list")
        siteUploadDistribution = dashboardStatusDistribution(statuses, keys: ["uploaded", "upload"])
        siteDownloadDistribution = dashboardStatusDistribution(statuses, keys: ["downloaded", "download"])
        siteStatuses = dashboardSiteStatuses(statuses)
        seedDistribution = dashboardDistribution(root["seedDataList"] ?? root["seed_data_list"])
        todayUploadDistribution = dashboardDistribution(root["uploadIncrementDataList"] ?? root["upload_increment_data_list"])
        todayDownloadDistribution = dashboardDistribution(root["downloadIncrementDataList"] ?? root["download_increment_data_list"])
        siteHistory = dashboardSiteHistory(root)
        monthlyHistory = dashboardMonthlyHistory(siteHistory)
        let earliest = root.dict("earliestSite", "earliest_site") ?? [:]
        earliestSite = earliest.string("site", "name", "nickname") ?? ""
        earliestJoinedAt = earliest.string("time_join", "timeJoin", "joined_at") ?? ""
        updatedAt = root.string("updatedAt", "updated_at") ?? ""
    }

    func siteIncrements(days: Int) -> [DashboardSiteIncrementItem] {
        let normalizedDays = max(1, days)
        let keys = Array(Set(siteHistory.flatMap { $0.points.map(\.key) })).sorted()
        let visibleKeys = Set(keys.suffix(normalizedDays))
        var values = siteHistory.compactMap { series -> DashboardSiteIncrementItem? in
            let points = series.points.filter { visibleKeys.contains($0.key) }
            let uploaded = points.reduce(0) { $0 + $1.uploaded }
            let downloaded = points.reduce(0) { $0 + $1.downloaded }
            guard uploaded > 0 || downloaded > 0 else { return nil }
            return DashboardSiteIncrementItem(name: series.name, uploaded: uploaded, downloaded: downloaded)
        }
        if values.isEmpty {
            let names = Set(todayUploadDistribution.map(\.name) + todayDownloadDistribution.map(\.name))
            values = names.compactMap { name in
                let uploaded = todayUploadDistribution.first { $0.name == name }?.value ?? 0
                let downloaded = todayDownloadDistribution.first { $0.name == name }?.value ?? 0
                guard uploaded > 0 || downloaded > 0 else { return nil }
                return DashboardSiteIncrementItem(name: name, uploaded: uploaded, downloaded: downloaded)
            }
        }
        return values.sorted { ($0.uploaded + $0.downloaded) > ($1.uploaded + $1.downloaded) }
    }
}

private func dashboardSiteStatuses(_ rows: [[String: Any]]) -> [DashboardSiteStatusItem] {
    rows.compactMap { row in
        guard let name = row.string("name", "site", "label"), !name.isEmpty else { return nil }
        let value = row.dict("value", "status") ?? row
        let uploaded = value.double("uploaded", "upload") ?? 0
        let downloaded = value.double("downloaded", "download") ?? 0
        let published = value.double("published", "publish") ?? 0
        guard uploaded > 0 || downloaded > 0 || published > 0 else { return nil }
        return DashboardSiteStatusItem(name: name, uploaded: uploaded, downloaded: downloaded, published: published)
    }
    .sorted { $0.uploaded > $1.uploaded }
}

private func dashboardSiteHistory(_ root: [String: Any]) -> [DashboardSiteHistorySeries] {
    root.rows("uploadMonthIncrementDataList", "upload_month_increment_data_list").compactMap { series in
        guard let name = series.string("name", "site", "label"), !name.isEmpty else { return nil }
        let points = series.rows("value", "items", "records").compactMap { row -> DashboardSiteHistoryPoint? in
            guard let key = row.string("created_at", "createdAt", "date", "time")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !key.isEmpty else { return nil }
            return DashboardSiteHistoryPoint(
                key: key,
                uploaded: row.double("uploaded", "upload") ?? 0,
                downloaded: row.double("downloaded", "download") ?? 0,
                published: row.double("published", "publish") ?? 0
            )
        }
        return DashboardSiteHistorySeries(name: name, points: points)
    }
}

private func dashboardMonthlyHistory(_ series: [DashboardSiteHistorySeries]) -> [DashboardMonthlyPoint] {
    var totals: [String: (uploaded: Double, downloaded: Double, published: Double)] = [:]
    for site in series {
        for point in site.points {
            let current = totals[point.key] ?? (0, 0, 0)
            totals[point.key] = (
                current.uploaded + point.uploaded,
                current.downloaded + point.downloaded,
                current.published + point.published
            )
        }
    }
    return totals.keys.sorted().compactMap { key in
        guard let value = totals[key] else { return nil }
        return DashboardMonthlyPoint(
            key: key,
            uploaded: value.uploaded,
            downloaded: value.downloaded,
            published: value.published
        )
    }
}

private func dashboardStatusDistribution(_ rows: [[String: Any]], keys: [String]) -> [DashboardDistributionItem] {
    rows.compactMap { row in
        guard let name = row.string("name", "site", "label"), !name.isEmpty else { return nil }
        let value = row.dict("value", "status") ?? row
        let amount = keys.compactMap { value.double($0) }.first ?? 0
        guard amount > 0 else { return nil }
        return DashboardDistributionItem(name: name, value: amount)
    }
    .sorted { $0.value > $1.value }
}

private func dashboardDistribution(_ value: Any?) -> [DashboardDistributionItem] {
    guard let value else { return [] }
    return jsonRows(value).compactMap { row in
        guard let name = row.string("name", "key", "label", "site"), !name.isEmpty else { return nil }
        return DashboardDistributionItem(name: name, value: row.double("value", "count", "total", "size") ?? 0)
    }.sorted { $0.value > $1.value }
}

private func dashboardTrendPoints(_ root: [String: Any]) -> [TrendPoint] {
    let series = root.rows(
        "stackChartDataList",
        "stack_chart_data_list",
        "uploadMonthIncrementDataList",
        "upload_month_increment_data_list"
    )
    var totals: [String: (upload: Double, download: Double)] = [:]
    for group in series {
        for row in group.rows("value") {
            guard let key = row.string("created_at", "createdAt", "date", "time") else { continue }
            let current = totals[key] ?? (0, 0)
            totals[key] = (
                current.upload + (row.double("uploaded", "upload", "up") ?? 0),
                current.download + (row.double("downloaded", "download", "down") ?? 0)
            )
        }
    }
    return totals.keys.sorted().compactMap { key in
        guard let value = totals[key], let date = parseDate(key) else { return nil }
        return TrendPoint(date: date, upload: value.upload, download: value.download)
    }
}

private func dashboardAuthorizationValue(_ value: Any, keys: [String]) -> Any? {
    if let dictionary = value as? [String: Any] {
        for key in keys where dictionary[key] != nil { return dictionary[key] }
        for nested in dictionary.values {
            if let match = dashboardAuthorizationValue(nested, keys: keys) { return match }
        }
    } else if let values = value as? [Any] {
        for nested in values {
            if let match = dashboardAuthorizationValue(nested, keys: keys) { return match }
        }
    }
    return nil
}

private func dashboardAuthorizationBool(_ value: Any?) -> Bool? {
    if let value = value as? Bool { return value }
    if let value = value as? NSNumber { return value.boolValue }
    guard let text = value as? String else { return nil }
    switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "true", "1", "yes", "active", "enabled": return true
    case "false", "0", "no", "inactive", "disabled": return false
    default: return nil
    }
}

private func dashboardAuthorizationDate(_ value: Any?) -> Date? {
    if let value = value as? Date { return value }
    if let value = value as? NSNumber {
        let timestamp = value.doubleValue
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp > 100_000_000_000 ? timestamp / 1_000 : timestamp)
    }
    guard let text = value as? String else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let timestamp = Double(trimmed), timestamp > 0 {
        return Date(timeIntervalSince1970: timestamp > 100_000_000_000 ? timestamp / 1_000 : timestamp)
    }
    return parseDate(trimmed)
}

private func dashboardAuthorizationHealthy(_ info: [String: Any]) -> Bool {
    let value = dashboardAuthorizationValue(info, keys: ["active", "is_active"])
    return dashboardAuthorizationBool(value) ?? true
}

private func dashboardAuthorizationExpiringSoon(_ info: [String: Any]) -> Bool {
    let value = dashboardAuthorizationValue(
        info,
        keys: ["time_expire", "time expire", "timeExpire", "expire", "expire_time", "expired_at", "expires_at"]
    )
    guard let date = dashboardAuthorizationDate(value) else { return false }
    let remaining = date.timeIntervalSinceNow
    return remaining >= 0 && remaining < 15 * 24 * 60 * 60
}

private func dashboardAuthorizationText(_ value: Any?, privacy: Bool, key: String = "") -> String {
    guard let value, !(value is NSNull) else { return "" }
    if let value = value as? Bool { return value ? "有效" : "无效" }
    if let value = value as? NSNumber { return value.stringValue }
    if let values = value as? [Any] {
        return values.map { dashboardAuthorizationText($0, privacy: privacy, key: key) }
            .filter { !$0.isEmpty }
            .joined(separator: "，")
    }
    if let dictionary = value as? [String: Any] {
        return dictionary.compactMap { nestedKey, nestedValue -> String? in
            guard !["username", "user_name", "name", "email", "mail", "user_email"].contains(nestedKey.lowercased()) else { return nil }
            let text = dashboardAuthorizationText(nestedValue, privacy: privacy, key: nestedKey)
            return text.isEmpty ? nil : "\(dashboardAuthorizationLabel(nestedKey))：\(text)"
        }
        .sorted()
        .joined(separator: "；")
    }
    let text = String(describing: value)
    guard privacy else { return text }
    let normalizedKey = key.lowercased()
    if normalizedKey.contains("token") || normalizedKey.contains("email") || text.contains("@") { return "••••" }
    return text
}

private func dashboardAuthorizationLabel(_ key: String) -> String {
    switch key {
    case "active", "is_active": "状态"
    case "expire", "time expire", "time_expire", "timeExpire", "expire_time", "expired_at", "expires_at": "到期时间"
    case "pay": "授权额度"
    case "invite": "邀请次数"
    case "try_user": "试用用户"
    case "marked": "备注"
    case "token": "授权 Token"
    default: key
    }
}

private func dashboardAuthorizationSummary(_ info: [String: Any], privacy: Bool) -> String {
    let fields: [(String, [String])] = [
        ("状态", ["active", "is_active"]),
        ("到期", ["time_expire", "time expire", "timeExpire", "expire", "expire_time", "expired_at", "expires_at"]),
        ("额度", ["pay"]),
        ("邀请", ["invite"])
    ]
    let values = fields.compactMap { label, keys -> String? in
        let text = dashboardAuthorizationText(
            dashboardAuthorizationValue(info, keys: keys),
            privacy: privacy,
            key: keys.first ?? ""
        )
        return text.isEmpty ? nil : "\(label) \(text)"
    }
    if !values.isEmpty { return values.joined(separator: " · ") }
    let fallback = dashboardAuthorizationText(info, privacy: privacy)
    return fallback.isEmpty ? "暂无授权信息" : fallback
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var snapshot = DashboardSnapshot([String: Any]())
    @Published var isLoading = true
    @Published var lastUpdated: Date?
    @Published private(set) var usingCachedData = false
    @Published private(set) var cachedAt: Date?
    @Published private(set) var serverConnected = false
    @Published private(set) var serverMonitoring = false
    @Published private(set) var serverDeadline: Date?
    @Published private(set) var serverHistory: [DashboardServerPoint] = []
    @Published private(set) var serverError: String?
    @Published private(set) var authorizationInfo: [String: Any]?
    @Published private(set) var authorizationLoading = true
    @Published private(set) var authorizationError: String?
    private var serverWatchTask: Task<Void, Never>?
    private var serverCountdownTask: Task<Void, Never>?
    private var serverWatchToken: UUID?
    private var serverViewActive = false
    private var serverResourceVisible = true
    private var serverInterval = DashboardServerRefreshDefaults.interval
    private var serverDuration = DashboardServerRefreshDefaults.duration
    private var restoredCacheKey: String?

    func load(_ appState: AppState, days: Int? = nil) async {
        let cacheKey = "dashboard.data.\(days ?? 0)"
        if restoredCacheKey != cacheKey {
            restoredCacheKey = cacheKey
            if let cached = await appState.readSessionCache(cacheKey) {
                snapshot = DashboardSnapshot(cached.value)
                lastUpdated = cached.cachedAt
                cachedAt = cached.cachedAt
                usingCachedData = true
            }
        }
        isLoading = snapshot.siteCount == 0 && !usingCachedData
        do {
            let query: [String: Any] = days.map { ["days": $0] } ?? [:]
            let raw = try await appState.api(APIPath.dashboard, query: query)
            snapshot = DashboardSnapshot(raw)
            lastUpdated = Date()
            cachedAt = nil
            usingCachedData = false
            await appState.writeSessionCache(raw, name: cacheKey)
        } catch {
            if !usingCachedData { appState.presentedError = error.localizedDescription }
        }
        isLoading = false
        await loadAuthorization(appState)
    }

    private func loadAuthorization(_ appState: AppState) async {
        authorizationLoading = authorizationInfo == nil
        defer { authorizationLoading = false }
        do {
            let raw = try await appState.api(APIPath.authInfo)
            guard let value = jsonPayloadDictionary(raw) else {
                throw APIError(statusCode: 0, message: "授权信息响应无效")
            }
            authorizationInfo = value
            authorizationError = nil
        } catch {
            authorizationError = error.localizedDescription
        }
    }

    func serverCountdownText(at date: Date = Date()) -> String {
        let remaining = max(0, Int((serverDeadline?.timeIntervalSince(date) ?? 0).rounded(.up)))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    var latestServerPoint: DashboardServerPoint? { serverHistory.last }

    func configureServerMonitoring(
        _ appState: AppState,
        visible: Bool,
        autoStart: Bool,
        interval: Int,
        duration: Int
    ) {
        serverViewActive = true
        serverResourceVisible = visible
        serverInterval = min(max(interval, DashboardServerRefreshDefaults.range.lowerBound), DashboardServerRefreshDefaults.range.upperBound)
        serverDuration = min(max(duration, DashboardServerRefreshDefaults.range.lowerBound), DashboardServerRefreshDefaults.range.upperBound)
        guard visible else {
            stopActiveServerMonitoring(clearRemaining: true)
            return
        }
        beginServerMonitoring(appState, continuous: autoStart)
    }

    func toggleServerMonitoring(_ appState: AppState) {
        guard serverViewActive, serverResourceVisible else { return }
        if serverMonitoring {
            stopActiveServerMonitoring(clearRemaining: true)
        } else {
            beginServerMonitoring(appState, continuous: true)
        }
    }

    func stopServerMonitoring() {
        serverViewActive = false
        stopActiveServerMonitoring(clearRemaining: true)
    }

    private func beginServerMonitoring(_ appState: AppState, continuous: Bool) {
        stopActiveServerMonitoring(clearRemaining: false)
        guard serverViewActive, serverResourceVisible else { return }
        serverMonitoring = true
        serverConnected = false
        serverError = nil
        serverDeadline = continuous ? Date().addingTimeInterval(TimeInterval(serverDuration * 60)) : nil
        let token = UUID()
        serverWatchToken = token
        serverWatchTask = Task { [weak self] in
            await self?.watchServer(appState, token: token, continuous: continuous)
        }
        guard continuous else { return }
        serverCountdownTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: .seconds(self.serverDuration * 60)) }
            catch { return }
            guard self.isCurrentServerWatch(token) else { return }
            self.stopActiveServerMonitoring(clearRemaining: true)
        }
    }

    private func stopActiveServerMonitoring(clearRemaining: Bool) {
        serverMonitoring = false
        serverConnected = false
        serverError = nil
        serverWatchToken = nil
        serverWatchTask?.cancel()
        serverWatchTask = nil
        serverCountdownTask?.cancel()
        serverCountdownTask = nil
        if clearRemaining { serverDeadline = nil }
    }

    private func watchServer(_ appState: AppState, token: UUID, continuous: Bool) async {
        while isCurrentServerWatch(token), !Task.isCancelled {
            do {
                for try await event in APIClient.shared.streamSSE(
                    baseURL: appState.baseURL,
                    path: APIPath.serverStatus,
                    token: appState.accessToken,
                    method: .get,
                    query: ["interval": serverInterval]
                ) {
                    guard isCurrentServerWatch(token), !Task.isCancelled else { return }
                    guard let payload = jsonPayloadDictionary(event),
                          payload.string("type") != "connected" else { continue }
                    let cpu = payload.dict("cpu")
                    let memory = payload.dict("memory")
                    let network = payload.dict("network")
                    var updatedSnapshot = snapshot
                    updatedSnapshot.cpu = cpu?.double("percent") ?? updatedSnapshot.cpu
                    updatedSnapshot.memory = memory?.double("percent") ?? updatedSnapshot.memory
                    updatedSnapshot.uploadSpeed = network?.double("uploadSpeed", "upload_speed") ?? updatedSnapshot.uploadSpeed
                    updatedSnapshot.downloadSpeed = network?.double("downloadSpeed", "download_speed") ?? updatedSnapshot.downloadSpeed
                    snapshot = updatedSnapshot
                    var updatedHistory = serverHistory
                    updatedHistory.append(DashboardServerPoint(
                        date: parseDate(payload.string("timestamp", "time", "created_at")) ?? Date(),
                        isDocker: payload.bool("isDocker", "is_docker") ?? false,
                        cpu: updatedSnapshot.cpu,
                        cpuUsageSeconds: cpu?.double("usageSeconds", "usage_seconds", "usage") ?? 0,
                        cpuLimitCores: cpu?.double("limitCores", "limit_cores", "cores") ?? 0,
                        memory: updatedSnapshot.memory,
                        memoryUsage: memory?.double("usage") ?? 0,
                        memoryWorkingSet: memory?.double("workingSet", "working_set") ?? 0,
                        memoryLimit: memory?.double("limit", "total") ?? 0,
                        uploadSpeed: updatedSnapshot.uploadSpeed,
                        downloadSpeed: updatedSnapshot.downloadSpeed,
                        bytesSent: network?.double("bytesSent", "bytes_sent") ?? 0,
                        bytesReceived: network?.double("bytesRecv", "bytes_recv", "bytesReceived", "bytes_received") ?? 0
                    ))
                    if updatedHistory.count > 60 { updatedHistory.removeFirst(updatedHistory.count - 60) }
                    serverHistory = updatedHistory
                    if !serverConnected { serverConnected = true }
                    if serverError != nil { serverError = nil }
                    if !continuous {
                        finishCurrentServerMonitoring(token)
                        return
                    }
                }
                if isCurrentServerWatch(token) {
                    serverConnected = false
                    if !continuous {
                        finishCurrentServerMonitoring(token, error: "服务器未返回资源数据")
                        return
                    }
                    serverError = "连接已中断，正在重试"
                }
            } catch {
                if isCurrentServerWatch(token) {
                    serverConnected = false
                    if !continuous {
                        finishCurrentServerMonitoring(token, error: "资源采样失败")
                        return
                    }
                    serverError = "连接失败，正在重试"
                }
            }
            guard isCurrentServerWatch(token), !Task.isCancelled else { return }
            do { try await Task.sleep(for: .seconds(serverInterval)) }
            catch { return }
        }
    }

    private func isCurrentServerWatch(_ token: UUID) -> Bool {
        serverViewActive && serverResourceVisible && serverMonitoring && serverWatchToken == token
    }

    private func finishCurrentServerMonitoring(_ token: UUID, error: String? = nil) {
        guard serverWatchToken == token else { return }
        serverMonitoring = false
        serverConnected = false
        serverError = error
        serverWatchToken = nil
        serverWatchTask = nil
        serverCountdownTask?.cancel()
        serverCountdownTask = nil
        serverDeadline = nil
    }
}

private enum DashboardModule: String, CaseIterable, Identifiable {
    case userInfo
    case serverResources
    case designation
    case overview
    case quickActions
    case trend
    case siteStatus
    case usernameDistribution
    case emailDistribution
    case siteUploadDistribution
    case siteDownloadDistribution
    case todayIncrement
    case seedDistribution
    case monthlyUpload
    case monthlyDownload
    case monthlyPublish

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userInfo: "用户信息"
        case .serverResources: "服务器资源"
        case .designation: "称号进度"
        case .overview: "数据总览"
        case .quickActions: "快捷操作"
        case .trend: "流量趋势"
        case .siteStatus: "站点状态"
        case .usernameDistribution: "用户名分布"
        case .emailDistribution: "邮箱分布"
        case .siteUploadDistribution: "站点上传分布"
        case .siteDownloadDistribution: "站点下载分布"
        case .todayIncrement: "增量排行"
        case .seedDistribution: "做种分布"
        case .monthlyUpload: "月度上传"
        case .monthlyDownload: "月度下载"
        case .monthlyPublish: "月度发种"
        }
    }

    var icon: String {
        switch self {
        case .userInfo: "person.crop.circle"
        case .serverResources: "server.rack"
        case .designation: "medal"
        case .overview: "rectangle.grid.2x2"
        case .quickActions: "bolt.circle"
        case .trend: "chart.xyaxis.line"
        case .siteStatus: "chart.pie"
        case .usernameDistribution: "person.2"
        case .emailDistribution: "envelope"
        case .siteUploadDistribution: "arrow.up.circle"
        case .siteDownloadDistribution: "arrow.down.circle"
        case .todayIncrement: "chart.bar.xaxis"
        case .seedDistribution: "externaldrive.badge.checkmark"
        case .monthlyUpload: "arrow.up.right"
        case .monthlyDownload: "arrow.down.right"
        case .monthlyPublish: "paperplane"
        }
    }

    static func decode(_ raw: String) -> [DashboardModule] {
        var decoded = raw.split(separator: ",").compactMap { DashboardModule(rawValue: String($0)) }
        var seen = Set<String>()
        decoded = decoded.filter { seen.insert($0.rawValue).inserted }
        decoded.append(contentsOf: allCases.filter { !seen.contains($0.rawValue) })
        return decoded
    }

    static func encode(_ modules: [DashboardModule]) -> String {
        modules.map(\.rawValue).joined(separator: ",")
    }
}

private enum DashboardQuickAction: String, Identifiable, Equatable {
    case refreshSites
    case refreshDashboard
    case signSites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .refreshSites: "抓取数据"
        case .refreshDashboard: "拉取数据"
        case .signSites: "签到任务"
        }
    }

    var subtitle: String {
        switch self {
        case .refreshSites: "刷新站点数据"
        case .refreshDashboard: "拉取仪表盘数据"
        case .signSites: "领取每日奖励"
        }
    }

    var icon: String {
        switch self {
        case .refreshSites: "arrow.clockwise"
        case .refreshDashboard: "arrow.triangle.2.circlepath"
        case .signSites: "calendar.badge.checkmark"
        }
    }

    var color: Color {
        switch self {
        case .refreshSites: HarvestTheme.green
        case .refreshDashboard: HarvestTheme.blue
        case .signSites: HarvestTheme.amber
        }
    }
}

private struct DashboardCacheTarget: Identifiable {
    let label: String
    let key: String
    var id: String { key }
}

private let dashboardCacheTargets = [
    DashboardCacheTarget(label: "豆瓣缓存数据", key: "*douban*"),
    DashboardCacheTarget(label: "TMDB 缓存数据", key: "*tmdb_*"),
    DashboardCacheTarget(label: "影视 Token 数据", key: "tmdb_api_auth"),
    DashboardCacheTarget(label: "RSS 缓存数据", key: "rss_data_list"),
    DashboardCacheTarget(label: "单下载器缓存", key: "repeat_info_hash_cache:*-*"),
    DashboardCacheTarget(label: "站点删种缓存", key: "repeat_404_cache:*-*"),
    DashboardCacheTarget(label: "辅种错误缓存", key: "repeat_error_cache:*-*"),
    DashboardCacheTarget(label: "辅种成功缓存", key: "repeat_success_cache:*-*"),
    DashboardCacheTarget(label: "辅种数据缓存", key: "repeat_info_hash_cache"),
    DashboardCacheTarget(label: "站点配置缓存", key: "website_list"),
    DashboardCacheTarget(label: "我的站点缓存", key: "my_site_list"),
    DashboardCacheTarget(label: "首页数据缓存", key: "dashboard_data_*")
]

private struct DashboardCacheClearSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onCleared: () async -> Void
    @State private var clearingKey: String?
    @State private var statusMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("本机") {
                    Button { Task { await clearLocalScope() } } label: {
                        Label("清理本机缓存并重置界面设置", systemImage: "internaldrive")
                    }
                    .disabled(clearingKey != nil)
                    Text("不会退出登录；会清除搜索记录、通知去重记录和网络缓存，并恢复仪表盘、日志及影视入口的本机设置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("服务端缓存") {
                    ForEach(dashboardCacheTargets) { target in
                        Button { Task { await clearServer(target) } } label: {
                            HStack {
                                Label(target.label, systemImage: "externaldrive")
                                Spacer()
                                if clearingKey == target.key { ProgressView().controlSize(.small) }
                            }
                        }
                        .disabled(clearingKey != nil)
                    }
                }
                if !statusMessage.isEmpty {
                    Section("结果") { Text(statusMessage).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("缓存清理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(clearingKey != nil) }
            }
        }
    }

    @MainActor private func clearServer(_ target: DashboardCacheTarget) async {
        clearingKey = target.key
        defer { clearingKey = nil }
        if await appState.perform(APIPath.cacheClear, method: .get, query: ["key": target.key]) {
            statusMessage = "\(target.label)已清理"
            await onCleared()
        }
    }

    @MainActor private func clearLocalScope() async {
        clearingKey = "__local_scope__"
        defer { clearingKey = nil }
        let defaults = UserDefaults.standard
        let keys = [
            "privacyMode",
            "media.tmdbEnabled",
            "media.doubanEnabled",
            "search.history",
            "search.maxCount",
            "search.sitesEnabled",
            "search.siteIDs",
            "site.filter.availability",
            "site.filter.condition",
            "site.filter.sortField",
            "site.filter.ascending",
            "site.timeline.titleShowDuration",
            "site.timeline.showDuration",
            "site.timeline.showUploaded",
            "site.timeline.showDownloaded",
            "site.timeline.showInvitation",
            "site.timeline.showUsername",
            "site.timeline.showEmail",
            "site.timeline.showUID",
            "logs.fontSize",
            "dashboard.trendDays",
            "dashboard.autoRefresh",
            "dashboard.refreshInterval",
            "dashboard.chartHeight",
            "dashboard.itemLimit",
            DashboardServerRefreshDefaults.autoStartKey,
            DashboardServerRefreshDefaults.intervalKey,
            DashboardServerRefreshDefaults.durationKey,
            "dashboard.showUserInfo",
            "dashboard.showDesignation",
            "dashboard.showOverview",
            "dashboard.showQuickActions",
            "dashboard.showTrend",
            "dashboard.showServerResources",
            "dashboard.showSiteStatus",
            "dashboard.showUsernameDistribution",
            "dashboard.showEmailDistribution",
            "dashboard.showSiteUploadDistribution",
            "dashboard.showSiteDownloadDistribution",
            "dashboard.showTodayIncrement",
            "dashboard.showSeedDistribution",
            "dashboard.showMonthlyUpload",
            "dashboard.showMonthlyDownload",
            "dashboard.showMonthlyPublish",
            "dashboard.moduleOrder"
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
        let accountKey = "\(appState.baseURL)|\(appState.profile?.username ?? "")"
        for key in [
            "notifications.knownByAccount",
            "notifications.lastIDByAccount",
            "notifications.fallbackIDsByAccount"
        ] {
            var values = defaults.dictionary(forKey: key) ?? [:]
            values.removeValue(forKey: accountKey)
            defaults.set(values, forKey: key)
        }
        URLCache.shared.removeAllCachedResponses()
        await RemoteImageDataCache.shared.removeAll()
        await appState.clearSessionCache()
        appState.setPrivacyMode(false)
        appState.setMediaTMDBEnabled(false)
        appState.setMediaDoubanEnabled(false)
        NotificationCenter.default.post(name: .harvestLocalUIReset, object: nil)
        statusMessage = "本机页面缓存与界面设置已清理"
        appState.requestAutomaticRefresh(force: true)
        await onCleared()
    }
}

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = DashboardViewModel()
    @AppStorage("dashboard.trendDays") private var trendDays = 7
    @AppStorage("dashboard.autoRefresh") private var autoRefresh = true
    @AppStorage("dashboard.refreshInterval") private var refreshInterval = 300
    @AppStorage("dashboard.chartHeight") private var chartHeight = DashboardChartDefaults.height
    @AppStorage("dashboard.itemLimit") private var itemLimit = DashboardChartDefaults.itemCount
    @AppStorage("dashboard.serverResource.autoStart") private var serverResourceAutoStart = DashboardServerRefreshDefaults.autoStart
    @AppStorage("dashboard.serverResource.interval") private var serverResourceInterval = DashboardServerRefreshDefaults.interval
    @AppStorage("dashboard.serverResource.duration") private var serverResourceDuration = DashboardServerRefreshDefaults.duration
    @AppStorage("dashboard.showUserInfo") private var showUserInfo = true
    @AppStorage("dashboard.showDesignation") private var showDesignation = true
    @AppStorage("dashboard.showOverview") private var showOverview = true
    @AppStorage("dashboard.showQuickActions") private var showQuickActions = true
    @AppStorage("dashboard.showTrend") private var showTrend = true
    @AppStorage("dashboard.showServerResources") private var showServerResources = true
    @AppStorage("dashboard.showSiteStatus") private var showSiteStatus = true
    @AppStorage("dashboard.showUsernameDistribution") private var showUsernameDistribution = true
    @AppStorage("dashboard.showEmailDistribution") private var showEmailDistribution = true
    @AppStorage("dashboard.showSiteUploadDistribution") private var showSiteUploadDistribution = true
    @AppStorage("dashboard.showSiteDownloadDistribution") private var showSiteDownloadDistribution = true
    @AppStorage("dashboard.showTodayIncrement") private var showTodayIncrement = true
    @AppStorage("dashboard.showSeedDistribution") private var showSeedDistribution = true
    @AppStorage("dashboard.showMonthlyUpload") private var showMonthlyUpload = true
    @AppStorage("dashboard.showMonthlyDownload") private var showMonthlyDownload = true
    @AppStorage("dashboard.showMonthlyPublish") private var showMonthlyPublish = true
    @AppStorage("dashboard.moduleOrder") private var moduleOrderRaw = "overview,userInfo,quickActions,siteStatus,trend,serverResources,designation,todayIncrement,siteUploadDistribution,siteDownloadDistribution,seedDistribution,usernameDistribution,emailDistribution,monthlyUpload,monthlyDownload,monthlyPublish"
    @State private var showSettings = false
    @State private var showCacheClear = false
    @State private var showShare = false
    @State private var shareImage: UIImage?
    @State private var runningQuickAction: DashboardQuickAction?

    private var moduleOrder: [DashboardModule] { DashboardModule.decode(moduleOrderRaw) }

    var body: some View {
        ScrollView {
            if model.isLoading {
                LoadingState()
            } else {
                LazyVStack(spacing: 14) {
                    if model.usingCachedData {
                        SessionCacheBanner(cachedAt: model.cachedAt)
                    }
                    DashboardHeroView(
                        greeting: greeting,
                        updatedAt: model.lastUpdated,
                        serverConnected: model.serverConnected,
                        serverError: model.serverError,
                        snapshot: model.snapshot,
                        privacy: appState.privacyMode
                    )

                    ForEach(moduleOrder) { module in
                        dashboardModule(module)
                    }
                }
                .padding(16)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable { await model.load(appState, days: trendDays) }
        .task(id: "\(trendDays)-\(autoRefresh)-\(refreshInterval)") {
            await model.load(appState, days: trendDays)
            guard autoRefresh else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(max(30, refreshInterval)))
                if !Task.isCancelled { await model.load(appState, days: trendDays) }
            }
        }
        .task(id: "\(showServerResources)-\(serverResourceAutoStart)-\(serverResourceInterval)-\(serverResourceDuration)") {
            model.configureServerMonitoring(
                appState,
                visible: showServerResources,
                autoStart: serverResourceAutoStart,
                interval: serverResourceInterval,
                duration: serverResourceDuration
            )
        }
        .onDisappear { model.stopServerMonitoring() }
        .navigationTitle("仪表盘")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button { Task { await runGlobal(APIPath.siteStatus) } } label: { Label("刷新全部站点", systemImage: "arrow.clockwise") }
                    Button { Task { await runGlobal(APIPath.siteSign) } } label: { Label("全部站点签到", systemImage: "checkmark.seal") }
                    Button { showCacheClear = true } label: { Label("缓存清理", systemImage: "trash.slash") }
                } label: { Image(systemName: "bolt.circle") }
                Button {
                    renderShareImage()
                    showShare = shareImage != nil
                } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("分享仪表盘长图")
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("仪表盘设置")
            }
        }
        .sheet(isPresented: $showSettings) {
            DashboardSettingsSheet(
                trendDays: $trendDays,
                autoRefresh: $autoRefresh,
                refreshInterval: $refreshInterval,
                serverResourceAutoStart: $serverResourceAutoStart,
                serverResourceInterval: $serverResourceInterval,
                serverResourceDuration: $serverResourceDuration,
                chartHeight: $chartHeight,
                itemLimit: $itemLimit,
                moduleOrderRaw: $moduleOrderRaw
            )
        }
        .sheet(isPresented: $showCacheClear) {
            DashboardCacheClearSheet {
                await model.load(appState, days: trendDays)
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $showShare) {
            if let shareImage { ActivityShareSheet(items: [shareImage]) }
        }
    }

    @ViewBuilder private func dashboardModule(_ module: DashboardModule) -> some View {
        switch module {
        case .userInfo:
            if showUserInfo {
                DashboardUserInfoView(
                    profile: appState.profile,
                    authorizationInfo: model.authorizationInfo,
                    authorizationLoading: model.authorizationLoading,
                    authorizationError: model.authorizationError,
                    privacy: appState.privacyMode,
                    onLogout: appState.logout
                )
            }
        case .designation:
            if showDesignation {
                DashboardDesignationView(siteCount: model.snapshot.siteCount)
            }
        case .overview:
            if showOverview {
                DashboardOverviewView(
                    snapshot: model.snapshot,
                    privacy: appState.privacyMode,
                    accountAgeText: accountAgeText
                )
            }
        case .quickActions:
            if showQuickActions {
                DashboardQuickActionsView(running: runningQuickAction) { action in
                    Task { await runQuickAction(action) }
                }
            }
        case .trend:
            if showTrend && !model.snapshot.trends.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "流量趋势", subtitle: "最近同步周期")
                    Chart(model.snapshot.trends) { point in
                        LineMark(x: .value("时间", point.date), y: .value("上传", point.upload))
                            .foregroundStyle(HarvestTheme.green).interpolationMethod(.catmullRom)
                        LineMark(x: .value("时间", point.date), y: .value("下载", point.download))
                            .foregroundStyle(HarvestTheme.blue).interpolationMethod(.catmullRom)
                    }
                    .chartYAxis { AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel { if let number = value.as(Double.self) { Text(formatBytes(number)).font(.caption2) } }
                    } }
                    .frame(height: CGFloat(chartHeight))
                }
                .cardSurface()
            }
        case .siteStatus:
            if showSiteStatus && !model.snapshot.siteStatuses.isEmpty {
                DashboardSiteStatusView(items: model.snapshot.siteStatuses, limit: itemLimit, privacy: appState.privacyMode)
            }
        case .serverResources:
            if showServerResources {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("服务器资源").font(.title3.weight(.bold))
                            if let error = model.serverError {
                                Text(error).font(.caption).foregroundStyle(.secondary)
                            } else if model.serverMonitoring {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    Text("每 \(serverResourceInterval) 秒采样 · \(model.serverCountdownText(at: context.date)) 后停止")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("实时监控已停止").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Button { model.toggleServerMonitoring(appState) } label: {
                            Image(systemName: model.serverMonitoring ? "pause.fill" : "play.fill")
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.bordered)
                        .clipShape(Circle())
                        .accessibilityLabel(model.serverMonitoring ? "暂停服务器资源监控" : "开始服务器资源监控")
                    }
                    HStack(spacing: 8) {
                        Label(serverHostLabel, systemImage: model.latestServerPoint?.isDocker == true ? "shippingbox" : "server.rack")
                            .lineLimit(1)
                        Spacer()
                        if let latest = model.latestServerPoint {
                            Text(latest.date.formatted(date: .omitted, time: .standard))
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ResourceRow(label: "CPU", value: model.snapshot.cpu, color: HarvestTheme.coral)
                    if let latest = model.latestServerPoint {
                        HStack {
                            Text("\(latest.cpuLimitCores.formatted(.number.precision(.fractionLength(1)))) 核")
                            Spacer()
                            Text("累计 \(latest.cpuUsageSeconds.formatted(.number.precision(.fractionLength(1)))) 秒")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    ResourceRow(label: "内存", value: model.snapshot.memory, color: HarvestTheme.amber)
                    if let latest = model.latestServerPoint {
                        HStack {
                            Text("工作集 \(formatBytes(latest.memoryWorkingSet))")
                            Spacer()
                            Text("上限 \(formatBytes(latest.memoryLimit))")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label(formatSpeed(model.snapshot.downloadSpeed), systemImage: "arrow.down").foregroundStyle(HarvestTheme.blue)
                        Spacer()
                        Label(formatSpeed(model.snapshot.uploadSpeed), systemImage: "arrow.up").foregroundStyle(HarvestTheme.green)
                    }
                    .font(.caption.monospacedDigit())
                    if let latest = model.latestServerPoint {
                        HStack {
                            Text("累计下载 \(formatBytes(latest.bytesReceived))")
                            Spacer()
                            Text("累计上传 \(formatBytes(latest.bytesSent))")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    if model.serverHistory.count > 1 {
                        Divider()
                        HStack(spacing: 16) {
                            Label("CPU", systemImage: "circle.fill").foregroundStyle(HarvestTheme.coral)
                            Label("内存", systemImage: "circle.fill").foregroundStyle(HarvestTheme.amber)
                            Spacer()
                        }
                        .font(.caption2)
                        Chart(model.serverHistory) { point in
                            LineMark(x: .value("时间", point.date), y: .value("CPU", point.cpu))
                                .foregroundStyle(HarvestTheme.coral)
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("时间", point.date), y: .value("内存", point.memory))
                                .foregroundStyle(HarvestTheme.amber)
                                .interpolationMethod(.catmullRom)
                        }
                        .chartYScale(domain: 0...100)
                        .chartXAxis(.hidden)
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: 120)

                        let peakSpeed = model.serverHistory.map { max($0.uploadSpeed, $0.downloadSpeed) }.max() ?? 0
                        if peakSpeed > 0 {
                            HStack(spacing: 16) {
                                Label("下载", systemImage: "circle.fill").foregroundStyle(HarvestTheme.blue)
                                Label("上传", systemImage: "circle.fill").foregroundStyle(HarvestTheme.green)
                                Spacer()
                            }
                            .font(.caption2)
                            Chart(model.serverHistory) { point in
                                LineMark(x: .value("时间", point.date), y: .value("下载", point.downloadSpeed))
                                    .foregroundStyle(HarvestTheme.blue)
                                    .interpolationMethod(.catmullRom)
                                LineMark(x: .value("时间", point.date), y: .value("上传", point.uploadSpeed))
                                    .foregroundStyle(HarvestTheme.green)
                                    .interpolationMethod(.catmullRom)
                            }
                            .chartXAxis(.hidden)
                            .chartYAxis {
                                AxisMarks(position: .leading) { value in
                                    AxisGridLine().foregroundStyle(.quaternary)
                                    AxisValueLabel {
                                        if let speed = value.as(Double.self) { Text(formatSpeed(speed)).font(.caption2) }
                                    }
                                }
                            }
                            .frame(height: 120)
                        }
                    }
                }
                .cardSurface()
            }
        case .usernameDistribution:
            if showUsernameDistribution && !model.snapshot.usernameDistribution.isEmpty {
                DistributionView(title: module.title, items: model.snapshot.usernameDistribution, limit: itemLimit, privacy: appState.privacyMode)
            }
        case .emailDistribution:
            if showEmailDistribution && !model.snapshot.emailDistribution.isEmpty {
                DistributionView(title: module.title, items: model.snapshot.emailDistribution, limit: itemLimit, privacy: appState.privacyMode)
            }
        case .siteUploadDistribution:
            if showSiteUploadDistribution && !model.snapshot.siteUploadDistribution.isEmpty {
                DistributionView(title: module.title, items: model.snapshot.siteUploadDistribution, limit: itemLimit, privacy: appState.privacyMode)
            }
        case .siteDownloadDistribution:
            if showSiteDownloadDistribution && !model.snapshot.siteDownloadDistribution.isEmpty {
                DistributionView(title: module.title, items: model.snapshot.siteDownloadDistribution, limit: itemLimit, privacy: appState.privacyMode)
            }
        case .todayIncrement:
            if showTodayIncrement {
                DashboardIncrementRankingView(
                    items: model.snapshot.siteIncrements(days: trendDays),
                    days: trendDays,
                    limit: itemLimit,
                    privacy: appState.privacyMode
                )
            }
        case .seedDistribution:
            if showSeedDistribution && !model.snapshot.seedDistribution.isEmpty {
                DistributionView(title: module.title, items: model.snapshot.seedDistribution, limit: itemLimit, privacy: appState.privacyMode)
            }
        case .monthlyUpload:
            if showMonthlyUpload && !model.snapshot.monthlyHistory.isEmpty {
                DashboardMonthlyMetricView(metric: .upload, points: model.snapshot.monthlyHistory, chartHeight: chartHeight)
            }
        case .monthlyDownload:
            if showMonthlyDownload && !model.snapshot.monthlyHistory.isEmpty {
                DashboardMonthlyMetricView(metric: .download, points: model.snapshot.monthlyHistory, chartHeight: chartHeight)
            }
        case .monthlyPublish:
            if showMonthlyPublish && !model.snapshot.monthlyHistory.isEmpty {
                DashboardMonthlyMetricView(metric: .publish, points: model.snapshot.monthlyHistory, chartHeight: chartHeight)
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let text = hour < 6 ? "夜深了" : hour < 12 ? "早上好" : hour < 18 ? "下午好" : "晚上好"
        return "\(text)，\(appState.profile?.username ?? "用户")"
    }

    private func hidden(_ value: String) -> String { appState.privacyMode ? "••••" : value }

    private var serverHostLabel: String {
        guard !appState.privacyMode else { return "••••" }
        return URL(string: appState.baseURL)?.host ?? appState.baseURL
    }

    private var accountAgeText: String {
        guard let joined = parseDate(model.snapshot.earliestJoinedAt) else { return model.snapshot.earliestSite.isEmpty ? "最早站点未知" : model.snapshot.earliestSite }
        let days = max(0, Calendar.current.dateComponents([.day], from: joined, to: Date()).day ?? 0)
        return model.snapshot.earliestSite.isEmpty ? "P 龄 \(days) 天" : "\(model.snapshot.earliestSite) · \(days) 天"
    }

    @MainActor private func runGlobal(_ path: String) async {
        let endpoint = path.hasSuffix("/") ? String(path.dropLast()) : path
        if await appState.perform(endpoint, method: .get) { await model.load(appState, days: trendDays) }
    }

    @MainActor private func runQuickAction(_ action: DashboardQuickAction) async {
        guard runningQuickAction == nil else { return }
        runningQuickAction = action
        defer { runningQuickAction = nil }
        switch action {
        case .refreshSites:
            await runGlobal(APIPath.siteStatus)
        case .refreshDashboard:
            await model.load(appState, days: trendDays)
        case .signSites:
            await runGlobal(APIPath.siteSign)
        }
    }

    @MainActor private func renderShareImage() {
        let renderer = ImageRenderer(content: DashboardShareContent(
            snapshot: model.snapshot,
            profile: appState.profile,
            authorizationInfo: model.authorizationInfo,
            authorizationError: model.authorizationError,
            serverPoint: model.latestServerPoint,
            rangeDays: trendDays,
            itemLimit: itemLimit,
            privacy: appState.privacyMode
        ))
        renderer.scale = UIScreen.main.scale
        shareImage = renderer.uiImage
    }
}

private struct DashboardHeroView: View {
    let greeting: String
    let updatedAt: Date?
    let serverConnected: Bool
    let serverError: String?
    let snapshot: DashboardSnapshot
    let privacy: Bool

    private var statusLabel: String {
        if serverError != nil { return "资源监控异常" }
        return serverConnected ? "资源监控在线" : "数据已同步"
    }

    private var statusColor: Color {
        if serverError != nil { return HarvestTheme.coral }
        return serverConnected ? HarvestTheme.green : HarvestTheme.blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                SymbolBadge(icon: "chart.xyaxis.line", color: statusColor, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting)
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(updatedAt?.formatted(date: .omitted, time: .shortened) ?? "刚刚同步")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                StatusPill(label: statusLabel, color: statusColor)
            }

            HStack(spacing: 0) {
                heroMetric(
                    label: "站点",
                    value: "\(snapshot.siteCount)",
                    detail: "\(snapshot.unread) 条未读",
                    color: HarvestTheme.coral
                )
                Divider().frame(height: 46)
                heroMetric(
                    label: "下载速度",
                    value: privacy ? "••••" : formatSpeed(snapshot.downloadSpeed),
                    detail: "实时",
                    color: HarvestTheme.blue
                )
                Divider().frame(height: 46)
                heroMetric(
                    label: "上传速度",
                    value: privacy ? "••••" : formatSpeed(snapshot.uploadSpeed),
                    detail: "实时",
                    color: HarvestTheme.green
                )
            }
        }
        .padding(18)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
                .stroke(statusColor.opacity(0.18), lineWidth: 1)
        }
    }

    private func heroMetric(label: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

private struct DashboardOverviewView: View {
    let snapshot: DashboardSnapshot
    let privacy: Bool
    let accountAgeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "数据概览", subtitle: "累计数据与今日增量")

            HStack(spacing: 0) {
                overviewPrimaryMetric(
                    label: "总上传",
                    value: privateValue(formatBytes(snapshot.uploaded)),
                    detail: formatSpeed(snapshot.uploadSpeed),
                    icon: "arrow.up",
                    color: HarvestTheme.green
                )
                Divider().frame(height: 54)
                overviewPrimaryMetric(
                    label: "总下载",
                    value: privateValue(formatBytes(snapshot.downloaded)),
                    detail: formatSpeed(snapshot.downloadSpeed),
                    icon: "arrow.down",
                    color: HarvestTheme.blue
                )
            }

            Divider()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                DashboardStatLine(
                    label: "分享率",
                    value: privateValue(String(format: "%.2f", snapshot.ratio)),
                    detail: "\(snapshot.seeding) 个做种任务",
                    icon: "arrow.triangle.2.circlepath",
                    color: HarvestTheme.amber
                )
                DashboardStatLine(
                    label: "站点",
                    value: "\(snapshot.siteCount)",
                    detail: "\(snapshot.unread) 条未读消息",
                    icon: "globe.americas",
                    color: HarvestTheme.coral
                )
                DashboardStatLine(
                    label: "今日上传",
                    value: privateValue(formatBytes(snapshot.todayUploaded)),
                    detail: "今日增量",
                    icon: "arrow.up.right",
                    color: HarvestTheme.green
                )
                DashboardStatLine(
                    label: "今日下载",
                    value: privateValue(formatBytes(snapshot.todayDownloaded)),
                    detail: "今日增量",
                    icon: "arrow.down.right",
                    color: HarvestTheme.blue
                )
                DashboardStatLine(
                    label: "做种体积",
                    value: privateValue(formatBytes(snapshot.seedVolume)),
                    detail: "\(snapshot.leeching) 个下载中",
                    icon: "externaldrive.fill.badge.checkmark",
                    color: HarvestTheme.amber
                )
                DashboardStatLine(
                    label: "已发布",
                    value: "\(snapshot.published)",
                    detail: accountAgeText,
                    icon: "paperplane.fill",
                    color: HarvestTheme.coral
                )
            }
        }
        .cardSurface()
    }

    private func overviewPrimaryMetric(label: String, value: String, detail: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(detail)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private func privateValue(_ value: String) -> String { privacy ? "••••" : value }
}

private struct DashboardStatLine: View {
    let label: String
    let value: String
    let detail: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            SymbolBadge(icon: icon, color: color, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DashboardUserInfoView: View {
    let profile: UserProfile?
    let authorizationInfo: [String: Any]?
    let authorizationLoading: Bool
    let authorizationError: String?
    let privacy: Bool
    let onLogout: () -> Void
    @State private var confirmingLogout = false

    private var username: String {
        guard let profile else { return "未登录" }
        return privacy ? "••••" : profile.username
    }

    private var role: String {
        guard let profile else { return "等待登录状态同步" }
        if profile.isSuperuser { return "超级管理员" }
        if profile.isStaff { return "管理员" }
        return "普通用户"
    }

    private var authorizationTitle: String {
        if authorizationLoading { return "授权校验中" }
        if authorizationError != nil { return "授权获取失败" }
        guard let authorizationInfo else { return "暂无授权" }
        return dashboardAuthorizationHealthy(authorizationInfo) ? "授权有效" : "授权异常"
    }

    private var authorizationSubtitle: String {
        if authorizationLoading { return "正在读取授权信息" }
        if let authorizationError { return authorizationError }
        guard let authorizationInfo else { return "暂无授权信息" }
        return dashboardAuthorizationSummary(authorizationInfo, privacy: privacy)
    }

    private var authorizationColor: Color {
        guard !authorizationLoading, authorizationError == nil, let authorizationInfo else { return HarvestTheme.amber }
        return dashboardAuthorizationHealthy(authorizationInfo) ? HarvestTheme.green : HarvestTheme.coral
    }

    private var expiringSoon: Bool {
        authorizationInfo.map(dashboardAuthorizationExpiringSoon) ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                SymbolBadge(icon: "person.crop.circle.fill", color: HarvestTheme.blue, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("用户信息").font(.title3.weight(.bold))
                        if expiringSoon {
                            Text("即将到期")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(HarvestTheme.amber)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(HarvestTheme.amber.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(username).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button(role: .destructive) { confirmingLogout = true } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("退出登录")
            }
            HStack(alignment: .top, spacing: 10) {
                DashboardUserMetricView(
                    icon: "person.fill",
                    label: "登录用户",
                    title: username,
                    subtitle: role,
                    color: HarvestTheme.blue
                )
                DashboardUserMetricView(
                    icon: "checkmark.shield.fill",
                    label: "授权信息",
                    title: expiringSoon ? "\(authorizationTitle) · 即将到期" : authorizationTitle,
                    subtitle: authorizationSubtitle,
                    color: authorizationColor
                )
            }
        }
        .cardSurface()
        .confirmationDialog("确定退出当前账号？", isPresented: $confirmingLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { onLogout() }
        }
    }
}

private struct DashboardUserMetricView: View {
    let icon: String
    let label: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
            Text(title)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardDesignationLevel: Identifiable {
    let threshold: Int
    let title: String
    var id: Int { threshold }
}

private let dashboardDesignationLevels = [
    DashboardDesignationLevel(threshold: 1, title: "初窥门径"),
    DashboardDesignationLevel(threshold: 10, title: "星辰初现"),
    DashboardDesignationLevel(threshold: 20, title: "光耀九天"),
    DashboardDesignationLevel(threshold: 30, title: "龙腾九霄"),
    DashboardDesignationLevel(threshold: 50, title: "纵横天下"),
    DashboardDesignationLevel(threshold: 100, title: "天命之子"),
    DashboardDesignationLevel(threshold: 150, title: "九天霸主"),
    DashboardDesignationLevel(threshold: 200, title: "万界之尊")
]

private struct DashboardDesignationView: View {
    let siteCount: Int

    private var current: DashboardDesignationLevel? {
        dashboardDesignationLevels.last { siteCount >= $0.threshold }
    }

    private var next: DashboardDesignationLevel? {
        dashboardDesignationLevels.first { siteCount < $0.threshold }
    }

    private var progress: Double {
        guard let next else { return 1 }
        let start = current?.threshold ?? 0
        let span = max(1, next.threshold - start)
        return min(max(Double(siteCount - start) / Double(span), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "称号进度", subtitle: "\(siteCount) 个站点接入")
                Spacer()
                SymbolBadge(icon: "medal.fill", color: HarvestTheme.coral, size: 44)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(current?.title ?? "无称号")
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                if let next {
                    Text("距 \(next.title) 还差 \(max(0, next.threshold - siteCount)) 站")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                } else {
                    Text("已达到最高等级").font(.caption).foregroundStyle(HarvestTheme.green)
                }
            }
            ProgressView(value: progress).tint(HarvestTheme.coral)
        }
        .cardSurface()
    }
}

private struct DashboardQuickActionsView: View {
    let running: DashboardQuickAction?
    let onAction: (DashboardQuickAction) -> Void
    private let actions: [DashboardQuickAction] = [.refreshSites, .refreshDashboard, .signSites]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "快捷操作")
            HStack(alignment: .top, spacing: 8) {
                ForEach(actions) { action in
                    Button { onAction(action) } label: {
                        VStack(spacing: 9) {
                            Group {
                                if running == action {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: action.icon)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 42, height: 42)
                            .background(action.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(action.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(action.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(running != nil)
                    .accessibilityLabel(action.title)
                }
            }
        }
        .cardSurface()
    }
}

private struct DashboardSiteStatusView: View {
    let items: [DashboardSiteStatusItem]
    let limit: Int
    let privacy: Bool

    private var visibleItems: [DashboardSiteStatusItem] { Array(items.prefix(max(1, limit))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "站点状态", subtitle: "按累计上传排序")
            ForEach(visibleItems) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(privacy ? "••••" : item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        if item.published > 0 {
                            Label(formatCompactNumber(item.published), systemImage: "paperplane")
                                .font(.caption2)
                                .foregroundStyle(HarvestTheme.coral)
                        }
                    }
                    HStack {
                        Label(formatBytes(item.uploaded), systemImage: "arrow.up")
                            .foregroundStyle(HarvestTheme.green)
                        Spacer()
                        Label(formatBytes(item.downloaded), systemImage: "arrow.down")
                            .foregroundStyle(HarvestTheme.blue)
                    }
                    .font(.caption.monospacedDigit())
                }
                if item.id != visibleItems.last?.id { Divider() }
            }
        }
        .cardSurface()
    }
}

private struct DashboardIncrementRankingView: View {
    let items: [DashboardSiteIncrementItem]
    let days: Int
    let limit: Int
    let privacy: Bool

    private var visibleItems: [DashboardSiteIncrementItem] { Array(items.prefix(max(1, limit))) }
    private var maximum: Double {
        max(visibleItems.map { max($0.uploaded, $0.downloaded) }.max() ?? 1, 1)
    }

    private var rangeLabel: String {
        days == 1 ? "当日增量排行" : "近 \(days) 天增量排行"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: rangeLabel, subtitle: "上传与下载前 \(visibleItems.count) 个站点")
            if visibleItems.isEmpty {
                Text("暂无增量数据").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ForEach(visibleItems) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(privacy ? "••••" : item.name).font(.caption.weight(.semibold)).lineLimit(1)
                        dashboardIncrementBar(label: "上传", value: item.uploaded, color: HarvestTheme.green)
                        dashboardIncrementBar(label: "下载", value: item.downloaded, color: HarvestTheme.blue)
                    }
                }
            }
        }
        .cardSurface()
    }

    private func dashboardIncrementBar(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 28, alignment: .leading)
            ProgressView(value: value, total: maximum).tint(color)
            Text(formatBytes(value)).monospacedDigit().frame(minWidth: 72, alignment: .trailing)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

private enum DashboardMonthlyMetric: Equatable {
    case upload
    case download
    case publish

    var title: String {
        switch self {
        case .upload: "月度上传"
        case .download: "月度下载"
        case .publish: "月度发种"
        }
    }

    var color: Color {
        switch self {
        case .upload: HarvestTheme.green
        case .download: HarvestTheme.blue
        case .publish: HarvestTheme.coral
        }
    }

    func value(_ point: DashboardMonthlyPoint) -> Double {
        switch self {
        case .upload: point.uploaded
        case .download: point.downloaded
        case .publish: point.published
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .upload, .download: formatBytes(value)
        case .publish: "\(formatCompactNumber(value)) 个"
        }
    }
}

private struct DashboardMonthlyMetricView: View {
    let metric: DashboardMonthlyMetric
    let points: [DashboardMonthlyPoint]
    let chartHeight: Double

    private var visiblePoints: [DashboardMonthlyPoint] { Array(points.suffix(12)) }
    private var total: Double { visiblePoints.reduce(0) { $0 + metric.value($1) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.title).font(.title3.weight(.bold))
                    Text("最近 \(visiblePoints.count) 个周期").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(metric.format(total)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            Chart(visiblePoints) { point in
                BarMark(
                    x: .value("周期", dashboardMonthLabel(point.key)),
                    y: .value(metric.title, metric.value(point))
                )
                .foregroundStyle(metric.color)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(metric == .publish ? formatCompactNumber(number) : formatBytes(number)).font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: min(6, max(visiblePoints.count, 1)))) }
            .frame(height: CGFloat(chartHeight))
        }
        .cardSurface()
    }

    private func dashboardMonthLabel(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 7 else { return trimmed }
        let yearEnd = trimmed.index(trimmed.startIndex, offsetBy: 4)
        let monthStart = trimmed.index(trimmed.startIndex, offsetBy: 5)
        let monthEnd = trimmed.index(monthStart, offsetBy: 2)
        let year = String(trimmed[..<yearEnd])
        let monthText = String(trimmed[monthStart..<monthEnd])
        guard let month = Int(monthText) else { return String(trimmed.prefix(7)) }
        return month == 1 ? "\(year.suffix(2))-01" : "\(month)月"
    }
}

struct DistributionView: View {
    let title: String
    let items: [DashboardDistributionItem]
    let limit: Int
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, subtitle: "前 \(min(max(1, limit), items.count)) 项")
            let maximum = max(items.map(\.value).max() ?? 1, 1)
            ForEach(items.prefix(max(1, limit))) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(privacy ? "••••" : item.name).lineLimit(1); Spacer(); Text(formatCompactNumber(item.value)).monospacedDigit() }
                        .font(.caption)
                    ProgressView(value: item.value, total: maximum).tint(HarvestTheme.green)
                }
            }
        }
        .cardSurface()
    }
}

struct DashboardSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var trendDays: Int
    @Binding var autoRefresh: Bool
    @Binding var refreshInterval: Int
    @Binding var serverResourceAutoStart: Bool
    @Binding var serverResourceInterval: Int
    @Binding var serverResourceDuration: Int
    @Binding var chartHeight: Double
    @Binding var itemLimit: Int
    @Binding var moduleOrderRaw: String
    @AppStorage("dashboard.showUserInfo") private var showUserInfo = true
    @AppStorage("dashboard.showDesignation") private var showDesignation = true
    @AppStorage("dashboard.showOverview") private var showOverview = true
    @AppStorage("dashboard.showQuickActions") private var showQuickActions = true
    @AppStorage("dashboard.showTrend") private var showTrend = true
    @AppStorage("dashboard.showServerResources") private var showServerResources = true
    @AppStorage("dashboard.showSiteStatus") private var showSiteStatus = true
    @AppStorage("dashboard.showUsernameDistribution") private var showUsernameDistribution = true
    @AppStorage("dashboard.showEmailDistribution") private var showEmailDistribution = true
    @AppStorage("dashboard.showSiteUploadDistribution") private var showSiteUploadDistribution = true
    @AppStorage("dashboard.showSiteDownloadDistribution") private var showSiteDownloadDistribution = true
    @AppStorage("dashboard.showTodayIncrement") private var showTodayIncrement = true
    @AppStorage("dashboard.showSeedDistribution") private var showSeedDistribution = true
    @AppStorage("dashboard.showMonthlyUpload") private var showMonthlyUpload = true
    @AppStorage("dashboard.showMonthlyDownload") private var showMonthlyDownload = true
    @AppStorage("dashboard.showMonthlyPublish") private var showMonthlyPublish = true
    @State private var modules: [DashboardModule]

    init(
        trendDays: Binding<Int>,
        autoRefresh: Binding<Bool>,
        refreshInterval: Binding<Int>,
        serverResourceAutoStart: Binding<Bool>,
        serverResourceInterval: Binding<Int>,
        serverResourceDuration: Binding<Int>,
        chartHeight: Binding<Double>,
        itemLimit: Binding<Int>,
        moduleOrderRaw: Binding<String>
    ) {
        _trendDays = trendDays
        _autoRefresh = autoRefresh
        _refreshInterval = refreshInterval
        _serverResourceAutoStart = serverResourceAutoStart
        _serverResourceInterval = serverResourceInterval
        _serverResourceDuration = serverResourceDuration
        _chartHeight = chartHeight
        _itemLimit = itemLimit
        _moduleOrderRaw = moduleOrderRaw
        _modules = State(initialValue: DashboardModule.decode(moduleOrderRaw.wrappedValue))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("趋势") {
                    Picker("数据天数", selection: $trendDays) { ForEach([1, 7, 14, 30, 60, 90, 180], id: \.self) { Text($0 == 1 ? "今日" : "\($0) 天").tag($0) } }
                }
                Section("图表尺寸") {
                    LabeledContent("图表高度", value: "\(Int(chartHeight)) pt")
                    Slider(value: $chartHeight, in: DashboardChartDefaults.heightRange, step: 20) {
                        Text("图表高度")
                    } minimumValueLabel: {
                        Text("120").font(.caption2)
                    } maximumValueLabel: {
                        Text("480").font(.caption2)
                    }
                    Stepper(
                        "站点显示数量：\(itemLimit)",
                        value: $itemLimit,
                        in: DashboardChartDefaults.itemCountRange
                    )
                    Button { resetChartSizing() } label: {
                        Label("恢复默认尺寸", systemImage: "arrow.counterclockwise")
                    }
                }
                Section("自动刷新") {
                    Toggle("自动刷新仪表盘", isOn: $autoRefresh)
                    Picker("刷新间隔", selection: $refreshInterval) {
                        Text("1 分钟").tag(60)
                        Text("5 分钟").tag(300)
                        Text("15 分钟").tag(900)
                        Text("30 分钟").tag(1_800)
                    }
                    .disabled(!autoRefresh)
                }
                Section("服务器资源监控") {
                    Toggle("进入页面自动监控", isOn: $serverResourceAutoStart)
                    Stepper(
                        "采样间隔：\(serverResourceInterval) 秒",
                        value: $serverResourceInterval,
                        in: DashboardServerRefreshDefaults.range
                    )
                    Stepper(
                        "自动停止：\(serverResourceDuration) 分钟",
                        value: $serverResourceDuration,
                        in: DashboardServerRefreshDefaults.range
                    )
                    Text("关闭自动监控时仅获取一次状态，也可在服务器资源卡片中手动开始连续监控。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button { resetServerResourceRefresh() } label: {
                        Label("恢复默认监控设置", systemImage: "arrow.counterclockwise")
                    }
                }
                Section("模块顺序与显示") {
                    ForEach(modules) { module in
                        Toggle(isOn: visibilityBinding(for: module)) {
                            Label(module.title, systemImage: module.icon)
                        }
                    }
                    .onMove(perform: moveModules)
                    Button {
                        resetModules()
                    } label: {
                        Label("恢复默认顺序并全部显示", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("仪表盘设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }

    private func visibilityBinding(for module: DashboardModule) -> Binding<Bool> {
        switch module {
        case .userInfo: $showUserInfo
        case .designation: $showDesignation
        case .overview: $showOverview
        case .quickActions: $showQuickActions
        case .trend: $showTrend
        case .serverResources: $showServerResources
        case .siteStatus: $showSiteStatus
        case .usernameDistribution: $showUsernameDistribution
        case .emailDistribution: $showEmailDistribution
        case .siteUploadDistribution: $showSiteUploadDistribution
        case .siteDownloadDistribution: $showSiteDownloadDistribution
        case .todayIncrement: $showTodayIncrement
        case .seedDistribution: $showSeedDistribution
        case .monthlyUpload: $showMonthlyUpload
        case .monthlyDownload: $showMonthlyDownload
        case .monthlyPublish: $showMonthlyPublish
        }
    }

    private func moveModules(from source: IndexSet, to destination: Int) {
        modules.move(fromOffsets: source, toOffset: destination)
        moduleOrderRaw = DashboardModule.encode(modules)
    }

    private func resetModules() {
        modules = DashboardModule.allCases
        moduleOrderRaw = DashboardModule.encode(modules)
        showUserInfo = true
        showDesignation = true
        showOverview = true
        showQuickActions = true
        showTrend = true
        showServerResources = true
        showSiteStatus = true
        showUsernameDistribution = true
        showEmailDistribution = true
        showSiteUploadDistribution = true
        showSiteDownloadDistribution = true
        showTodayIncrement = true
        showSeedDistribution = true
        showMonthlyUpload = true
        showMonthlyDownload = true
        showMonthlyPublish = true
    }

    private func resetServerResourceRefresh() {
        serverResourceAutoStart = DashboardServerRefreshDefaults.autoStart
        serverResourceInterval = DashboardServerRefreshDefaults.interval
        serverResourceDuration = DashboardServerRefreshDefaults.duration
    }

    private func resetChartSizing() {
        chartHeight = DashboardChartDefaults.height
        itemLimit = DashboardChartDefaults.itemCount
    }
}

private struct DashboardShareContent: View {
    let snapshot: DashboardSnapshot
    let profile: UserProfile?
    let authorizationInfo: [String: Any]?
    let authorizationError: String?
    let serverPoint: DashboardServerPoint?
    let rangeDays: Int
    let itemLimit: Int
    let privacy: Bool

    private var shareItemLimit: Int { min(max(itemLimit, 1), 15) }

    private var username: String {
        guard let profile else { return "未登录" }
        return privacy ? "••••" : profile.username
    }

    private var role: String {
        guard let profile else { return "未获取用户信息" }
        if profile.isSuperuser { return "超级管理员" }
        if profile.isStaff { return "管理员" }
        return "普通用户"
    }

    private var authorizationStatus: String {
        if authorizationError != nil { return "授权获取失败" }
        guard let authorizationInfo else { return "暂无授权" }
        let status = dashboardAuthorizationHealthy(authorizationInfo) ? "授权有效" : "授权异常"
        return dashboardAuthorizationExpiringSoon(authorizationInfo) ? "\(status) · 即将到期" : status
    }

    private var designation: String {
        dashboardDesignationLevels.last { snapshot.siteCount >= $0.threshold }?.title ?? "无称号"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                BrandMark(size: 54)
                VStack(alignment: .leading) { Text("Harvest").font(.largeTitle.bold()); Text("仪表盘 · \(Date().formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary) }
            }
            HStack(alignment: .top, spacing: 14) {
                shareMetric("登录用户", username, HarvestTheme.blue, detail: role)
                shareMetric(
                    "授权信息",
                    authorizationStatus,
                    authorizationError ?? authorizationInfo.map { dashboardAuthorizationSummary($0, privacy: privacy) } ?? "暂无授权信息",
                    HarvestTheme.green
                )
                shareMetric("称号进度", designation, HarvestTheme.coral, detail: "\(snapshot.siteCount) 个站点接入")
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                shareMetric("总上传", privacy ? "••••" : formatBytes(snapshot.uploaded), HarvestTheme.green)
                shareMetric("总下载", privacy ? "••••" : formatBytes(snapshot.downloaded), HarvestTheme.blue)
                shareMetric("做种体积", privacy ? "••••" : formatBytes(snapshot.seedVolume), HarvestTheme.amber)
                shareMetric("站点 / 做种", "\(snapshot.siteCount) / \(snapshot.seeding)", HarvestTheme.coral)
                shareMetric("今日上传", privacy ? "••••" : formatBytes(snapshot.todayUploaded), HarvestTheme.green)
                shareMetric("今日下载", privacy ? "••••" : formatBytes(snapshot.todayDownloaded), HarvestTheme.blue)
                shareMetric("分享率", privacy ? "••••" : String(format: "%.2f", snapshot.ratio), HarvestTheme.amber)
                shareMetric("发种 / 下载中", "\(snapshot.published) / \(snapshot.leeching)", HarvestTheme.coral)
            }
            if let serverPoint {
                shareSectionTitle("服务器状态", subtitle: serverPoint.isDocker ? "Docker 资源" : "主机资源")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    shareMetric("CPU", String(format: "%.1f%%", serverPoint.cpu), HarvestTheme.coral)
                    shareMetric("内存", String(format: "%.1f%%", serverPoint.memory), HarvestTheme.amber)
                    shareMetric("上传速度", formatSpeed(serverPoint.uploadSpeed), HarvestTheme.green)
                    shareMetric("下载速度", formatSpeed(serverPoint.downloadSpeed), HarvestTheme.blue)
                }
            }
            if !snapshot.trends.isEmpty {
                shareSectionTitle("流量趋势", subtitle: rangeDays == 1 ? "今日" : "最近 \(rangeDays) 天")
                Chart(snapshot.trends) { point in
                    LineMark(x: .value("日期", point.date), y: .value("上传", point.upload)).foregroundStyle(HarvestTheme.green)
                    LineMark(x: .value("日期", point.date), y: .value("下载", point.download)).foregroundStyle(HarvestTheme.blue)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel {
                            if let number = value.as(Double.self) { Text(formatBytes(number)).font(.caption2) }
                        }
                    }
                }
                .frame(height: 300)
            }
            if !snapshot.siteStatuses.isEmpty {
                shareSectionTitle("站点状态", subtitle: "按累计上传排序")
                let visibleStatuses = Array(snapshot.siteStatuses.prefix(shareItemLimit))
                VStack(spacing: 0) {
                    ForEach(visibleStatuses.indices, id: \.self) { index in
                        let item = visibleStatuses[index]
                        HStack(spacing: 16) {
                            Text(privacy ? "••••" : item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Label(formatBytes(item.uploaded), systemImage: "arrow.up").foregroundStyle(HarvestTheme.green)
                            Label(formatBytes(item.downloaded), systemImage: "arrow.down").foregroundStyle(HarvestTheme.blue)
                            Label(formatCompactNumber(item.published), systemImage: "paperplane").foregroundStyle(HarvestTheme.coral)
                        }
                        .font(.caption.monospacedDigit())
                        .padding(.vertical, 10)
                        if index < visibleStatuses.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal, 16)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous))
            }
            let increments = snapshot.siteIncrements(days: rangeDays)
            if !increments.isEmpty {
                shareSectionTitle("增量排行", subtitle: rangeDays == 1 ? "当日上传与下载" : "近 \(rangeDays) 天上传与下载")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(increments.prefix(shareItemLimit)) { item in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(privacy ? "••••" : item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            HStack { Label(formatBytes(item.uploaded), systemImage: "arrow.up").foregroundStyle(HarvestTheme.green); Spacer(); Label(formatBytes(item.downloaded), systemImage: "arrow.down").foregroundStyle(HarvestTheme.blue) }
                                .font(.caption.monospacedDigit())
                        }
                        .padding(14)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous))
                    }
                }
            }
            let distributions: [(String, [DashboardDistributionItem], Color)] = [
                ("站点上传分布", snapshot.siteUploadDistribution, HarvestTheme.green),
                ("站点下载分布", snapshot.siteDownloadDistribution, HarvestTheme.blue),
                ("做种分布", snapshot.seedDistribution, HarvestTheme.amber),
                ("用户名分布", snapshot.usernameDistribution, HarvestTheme.coral),
                ("邮箱分布", snapshot.emailDistribution, HarvestTheme.blue)
            ]
            if distributions.contains(where: { !$0.1.isEmpty }) {
                shareSectionTitle("数据分布", subtitle: "各项前 \(shareItemLimit) 名")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(Array(distributions.enumerated()), id: \.offset) { _, distribution in
                        if !distribution.1.isEmpty {
                            shareDistribution(distribution.0, items: distribution.1, color: distribution.2)
                        }
                    }
                }
            }
            if !snapshot.monthlyHistory.isEmpty {
                shareSectionTitle("月度统计", subtitle: "最近 \(min(snapshot.monthlyHistory.count, 12)) 个周期")
                VStack(spacing: 14) {
                    shareMonthlyMetric(.upload)
                    shareMonthlyMetric(.download)
                    shareMonthlyMetric(.publish)
                }
            }
        }
        .padding(36)
        .frame(width: 760)
        .background(Color(uiColor: .systemBackground))
    }

    private func shareSectionTitle(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title).font(.title2.bold())
            Spacer()
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func shareMetric(_ label: String, _ value: String, _ color: Color, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.65)
            if let detail, !detail.isEmpty { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
        }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous))
    }

    private func shareMetric(_ label: String, _ value: String, _ detail: String, _ color: Color) -> some View {
        shareMetric(label, value, color, detail: detail)
    }

    private func shareDistribution(_ title: String, items: [DashboardDistributionItem], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            let maximum = max(items.map(\.value).max() ?? 1, 1)
            ForEach(items.prefix(shareItemLimit)) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(privacy ? "••••" : item.name).lineLimit(1); Spacer(); Text(formatCompactNumber(item.value)).monospacedDigit() }
                        .font(.caption)
                    ProgressView(value: item.value, total: maximum).tint(color)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous))
    }

    private func shareMonthlyMetric(_ metric: DashboardMonthlyMetric) -> some View {
        let points = Array(snapshot.monthlyHistory.suffix(12))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(metric.title).font(.headline)
                Spacer()
                Text(metric.format(points.reduce(0) { $0 + metric.value($1) }))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Chart(points) { point in
                BarMark(x: .value("周期", point.key), y: .value(metric.title, metric.value(point)))
                    .foregroundStyle(metric.color)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(metric == .publish ? formatCompactNumber(number) : formatBytes(number)).font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 180)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous))
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

struct ResourceRow: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 7) {
            HStack { Text(label).font(.subheadline.weight(.semibold)); Spacer(); Text("\(Int(value))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            ProgressView(value: max(0, min(value, 100)), total: 100).tint(color)
        }
    }
}

struct StatusPill: View {
    let label: String
    let color: Color
    var body: some View {
        HStack(spacing: 6) { Circle().fill(color).frame(width: 7, height: 7); Text(label).font(.caption.weight(.semibold)) }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct SiteItem: Identifiable {
    let id: Int
    var sortID: Int
    var siteKey: String
    var name: String
    var url: String
    var userID: String
    var username: String
    var email: String
    var cookie: String
    var userAgent: String
    var passkey: String
    var authkey: String
    var localStorage: String
    var rss: String
    var torrentsURL: String
    var proxy: String
    var tags: [String]
    var siteType: String
    var iconURL: String
    var uploaded: Double
    var downloaded: Double
    var ratio: Double
    var seeding: Int
    var leeching: Int
    var published: Int
    var invitations: Int
    var seedDays: Int
    var magic: Double
    var bonusHour: Double
    var score: Double
    var seedVolume: Double
    var hr: String
    var level: String
    var mail: Int
    var notice: Int
    var unread: Int
    var enabled: Bool
    var signed: Bool
    var signIn: Bool
    var getInfo: Bool
    var repeatTorrents: Bool
    var searchTorrents: Bool
    var brushFree: Bool
    var brushRSS: Bool
    var packageFile: Bool
    var hrDiscern: Bool
    var showInDashboard: Bool
    var joinedAt: String
    var latestActive: String
    var updatedAt: String
    var statusHistory: [[String: Any]]
    var signHistory: [[String: Any]]
    var raw: [String: Any]

    var uploadDelta: Double { dailyDelta(for: "uploaded", aliases: ["upload"]) }
    var downloadDelta: Double { dailyDelta(for: "downloaded", aliases: ["download"]) }
    var hasTodayData: Bool {
        guard let latest = statusHistory.last else { return false }
        let updated = latest.string("updated_at", "created_at") ?? ""
        return !updated.isEmpty && updated.hasPrefix(isoDayKey())
    }

    init(_ json: [String: Any]) {
        let statusMap = json.dict("status") ?? [:]
        let latestStatus = statusMap.keys.sorted().last.flatMap { statusMap[$0] as? [String: Any] }
        let signInfo = json.dict("sign_info", "signInfo") ?? [:]
        id = json.int("id", "site_id") ?? abs((json.string("name") ?? UUID().uuidString).hashValue)
        sortID = json.int("sort_id", "sortId") ?? 1
        siteKey = json.string("site", "website_name", "name") ?? ""
        name = json.string("nickname") ?? siteKey
        if name.isEmpty { name = "未命名站点" }
        url = json.string("mirror", "url", "base_url") ?? ""
        userID = json.string("user_id", "userId", "uid") ?? ""
        username = json.string("username", "user_name") ?? ""
        email = json.string("email") ?? ""
        cookie = json.string("cookie") ?? ""
        userAgent = json.string("user_agent", "userAgent") ?? ""
        passkey = json.string("passkey") ?? ""
        authkey = json.string("authkey") ?? ""
        if let text = json.string("local_storage", "localStorage") { localStorage = text }
        else if let value = json["local_storage"] { localStorage = prettyJSON(value) }
        else { localStorage = "" }
        rss = json.string("rss") ?? ""
        torrentsURL = json.string("torrents") ?? ""
        proxy = json.string("proxy") ?? ""
        tags = json.strings("tags")
        siteType = json.string("type", "site_type", "siteType") ?? ""
        iconURL = json.string("icon", "logo", "favicon", "icon_url", "iconUrl") ?? ""
        uploaded = latestStatus?.double("uploaded", "upload", "uploaded_size") ?? json.double("uploaded", "upload", "uploaded_size") ?? 0
        downloaded = latestStatus?.double("downloaded", "download", "downloaded_size") ?? json.double("downloaded", "download", "downloaded_size") ?? 0
        ratio = latestStatus?.double("ratio", "share_ratio") ?? json.double("ratio", "share_ratio") ?? (downloaded > 0 ? uploaded / downloaded : 0)
        seeding = latestStatus?.int("seed", "seeding", "seeding_count") ?? json.int("seeding", "seed", "seeding_count") ?? 0
        leeching = latestStatus?.int("leech", "leeching", "downloading") ?? 0
        published = latestStatus?.int("publish", "published") ?? 0
        invitations = latestStatus?.int("invitation", "invitations") ?? 0
        seedDays = latestStatus?.int("seed_days", "seedDays") ?? 0
        magic = latestStatus?.double("my_bonus", "bonus", "magic") ?? 0
        bonusHour = latestStatus?.double("bonus_hour", "bonusHour") ?? 0
        score = latestStatus?.double("my_score", "score", "credits") ?? 0
        seedVolume = latestStatus?.double("seed_volume", "seedVolume") ?? 0
        hr = latestStatus?.string("my_hr", "hr") ?? "0"
        level = latestStatus?.string("my_level", "level") ?? ""
        mail = json.int("mail") ?? 0
        notice = json.int("notice") ?? 0
        unread = mail + notice
        if unread == 0 { unread = json.int("unread", "message", "message_count") ?? 0 }
        enabled = json.bool("available", "enable", "enabled", "is_active") ?? false
        signed = signInfo[isoDayKey()] != nil || json.bool("signed", "signin") == true
        signIn = json.bool("sign_in", "signin") ?? false
        getInfo = json.bool("get_info", "getInfo") ?? false
        repeatTorrents = json.bool("repeat_torrents", "repeatTorrents") ?? false
        searchTorrents = json.bool("search_torrents", "searchTorrents") ?? false
        brushFree = json.bool("brush_free", "brushFree") ?? false
        brushRSS = json.bool("brush_rss", "brushRss") ?? false
        packageFile = json.bool("package_file", "packageFile") ?? false
        hrDiscern = json.bool("hr_discern", "hrDiscern") ?? false
        showInDashboard = json.bool("show_in_dash", "showInDash") ?? true
        joinedAt = json.string("time_join", "timeJoin", "registered_at") ?? ""
        latestActive = json.string("latest_active", "latestActive", "last_visit") ?? ""
        updatedAt = latestStatus?.string("updated_at", "created_at") ?? json.string("updated_at", "update_time", "last_update") ?? ""
        statusHistory = statusMap.keys.sorted().compactMap { key in
            guard var row = statusMap[key] as? [String: Any] else { return nil }
            row["date"] = key
            return row
        }
        signHistory = signInfo.keys.sorted(by: >).compactMap { key in
            guard let value = signInfo[key] else { return nil }
            var row = (value as? [String: Any]) ?? ["info": String(describing: value)]
            row["date"] = key
            return row
        }
        raw = json
    }

    private func dailyDelta(for key: String, aliases: [String]) -> Double {
        let today = isoDayKey()
        guard let yesterdayDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return 0 }
        let yesterday = isoDayKey(yesterdayDate)
        let todayRow = statusHistory.first { ($0.string("date") ?? "").hasPrefix(today) }
        let yesterdayRow = statusHistory.first { ($0.string("date") ?? "").hasPrefix(yesterday) }
        let keys = [key] + aliases
        guard let todayRow, let yesterdayRow,
              let current = keys.compactMap({ todayRow.double($0) }).first,
              let previous = keys.compactMap({ yesterdayRow.double($0) }).first else { return 0 }
        return current - previous
    }
}

private func isoDayKey(_ date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

enum SiteAvailabilityFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case alive = "存活"
    case dead = "失效"
    var id: String { rawValue }
}

enum SiteConditionFilter: String, CaseIterable, Identifiable {
    case all = "全部条件"
    case unsigned = "今日未签到"
    case hasNewMessage = "有新邮件"
    case hasNewAnnouncement = "有新公告"
    case hasNewNotification = "有新通知"
    case noTodayData = "无今日数据"
    case hasUploadDelta = "有上传增量"
    case hasDownloadDelta = "有下载增量"
    case hasDelta = "有任意增量"
    case noProxy = "缺少 Proxy"
    case noCookie = "缺少 Cookie"
    case noUID = "缺少 UID"
    case noUsername = "缺少用户名"
    case noEmail = "缺少邮箱"
    case noSignInRecord = "无签到记录"
    case noPasskey = "缺少 Passkey"
    case noAuthkey = "缺少 Authkey"
    case noData = "没有站点数据"
    case abnormalJoinTime = "注册时间异常"
    case invitations = "有邀请"
    case keepAccount = "已保号"
    case graduated = "已毕业"
    case noSeeding = "没有做种"
    case downloading = "正在下载"
    case lowRatio = "分享率低于 1"
    var id: String { rawValue }
}

enum SiteSortField: String, CaseIterable, Identifiable {
    case updated = "更新时间"
    case name = "站点名称"
    case nickname = "昵称"
    case joined = "注册时间"
    case lastVisit = "最后访问"
    case seedVolume = "做种体积"
    case magic = "魔力值"
    case score = "积分"
    case uploaded = "上传量"
    case uploadDelta = "上传增量"
    case downloaded = "下载量"
    case downloadDelta = "下载增量"
    case published = "发种数"
    case bonusHour = "时魔"
    case invitations = "邀请"
    case leeching = "正在下载"
    case seeding = "做种数"
    case ratio = "分享率"
    case sortID = "排序 ID"
    var id: String { rawValue }

    var defaultAscending: Bool {
        self == .updated || self == .sortID
    }
}

private enum SiteFilterStorageKey {
    static let availability = "site.filter.availability"
    static let condition = "site.filter.condition"
    static let sortField = "site.filter.sortField"
    static let ascending = "site.filter.ascending"
}

private enum SiteLevelMilestone {
    case keepAccount
    case graduation
}

@MainActor
final class SitesViewModel: ObservableObject {
    private(set) var sites: [SiteItem] = [] { didSet { rebuildFilteredSites() } }
    @Published private(set) var filtered: [SiteItem] = []
    private var siteConfigs: [String: [String: Any]] = [:] { didSet { rebuildFilteredSites() } }
    @Published var isLoading = true
    @Published private(set) var usingCachedData = false
    @Published private(set) var cachedAt: Date?
    @Published var query = "" { didSet { rebuildFilteredSites() } }
    @Published var availability: SiteAvailabilityFilter = .alive {
        didSet {
            UserDefaults.standard.set(availability.rawValue, forKey: SiteFilterStorageKey.availability)
            rebuildFilteredSites()
        }
    }
    @Published var condition: SiteConditionFilter = .all {
        didSet {
            UserDefaults.standard.set(condition.rawValue, forKey: SiteFilterStorageKey.condition)
            rebuildFilteredSites()
        }
    }
    @Published var sortField: SiteSortField = .updated {
        didSet {
            UserDefaults.standard.set(sortField.rawValue, forKey: SiteFilterStorageKey.sortField)
            rebuildFilteredSites()
        }
    }
    @Published var ascending = true {
        didSet {
            UserDefaults.standard.set(ascending, forKey: SiteFilterStorageKey.ascending)
            rebuildFilteredSites()
        }
    }
    @Published var selectedTags: Set<String> = [] { didSet { rebuildFilteredSites() } }
    @Published var selectedTypes: Set<String> = [] { didSet { rebuildFilteredSites() } }
    @Published var selectedUsername = "" { didSet { rebuildFilteredSites() } }
    @Published var selectedEmail = "" { didSet { rebuildFilteredSites() } }
    private var didRestoreCache = false

    init() {
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: SiteFilterStorageKey.availability),
           let restored = SiteAvailabilityFilter(rawValue: value) {
            availability = restored
        }
        if let value = defaults.string(forKey: SiteFilterStorageKey.condition),
           let restored = SiteConditionFilter(rawValue: value) {
            condition = restored
        }
        if let value = defaults.string(forKey: SiteFilterStorageKey.sortField),
           let restored = SiteSortField(rawValue: value) {
            sortField = restored
        }
        ascending = defaults.object(forKey: SiteFilterStorageKey.ascending) == nil
            ? sortField.defaultAscending
            : defaults.bool(forKey: SiteFilterStorageKey.ascending)
    }

    private func rebuildFilteredSites() {
        filtered = computeFilteredSites()
    }

    private func computeFilteredSites() -> [SiteItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let compactQuery = compactSiteSearchText(normalizedQuery)
        let values = sites.filter { site in
            if !normalizedQuery.isEmpty {
                let config = config(for: site)
                let searchableValues = [site.name, site.siteKey, site.url, site.username, site.email]
                    + [config?.string("name", "site"), config?.string("nickname")].compactMap { $0 }
                    + (config.map { configStrings($0["url"]) } ?? [])
                let matches = searchableValues.contains { value in
                    value.localizedCaseInsensitiveContains(normalizedQuery)
                        || (!compactQuery.isEmpty && compactSiteSearchText(value).contains(compactQuery))
                }
                if !matches { return false }
            }
            if availability == .alive && !site.enabled { return false }
            if availability == .dead && site.enabled { return false }
            switch condition {
            case .all: break
            case .unsigned: if !site.signIn || site.signed { return false }
            case .hasNewMessage: if site.mail <= 0 { return false }
            case .hasNewAnnouncement: if site.notice <= 0 { return false }
            case .hasNewNotification: if site.unread <= 0 { return false }
            case .noTodayData: if site.hasTodayData { return false }
            case .hasUploadDelta: if site.uploadDelta <= 0 { return false }
            case .hasDownloadDelta: if site.downloadDelta <= 0 { return false }
            case .hasDelta: if site.uploadDelta <= 0 && site.downloadDelta <= 0 { return false }
            case .noProxy: if !site.proxy.isEmpty { return false }
            case .noCookie: if !site.cookie.isEmpty { return false }
            case .noUID: if !site.userID.isEmpty { return false }
            case .noUsername: if !site.username.isEmpty { return false }
            case .noEmail: if !site.email.isEmpty { return false }
            case .noSignInRecord: if !site.signIn || !site.signHistory.isEmpty { return false }
            case .noPasskey: if !site.passkey.isEmpty { return false }
            case .noAuthkey: if !site.authkey.isEmpty { return false }
            case .noData: if !site.statusHistory.isEmpty { return false }
            case .abnormalJoinTime: if !site.joinedAt.isEmpty && !site.joinedAt.hasPrefix("0001") { return false }
            case .invitations: if site.invitations <= 0 { return false }
            case .keepAccount: if milestone(for: site) != .keepAccount { return false }
            case .graduated: if milestone(for: site) != .graduation { return false }
            case .noSeeding: if site.seeding > 0 { return false }
            case .downloading: if site.leeching <= 0 { return false }
            case .lowRatio: if site.ratio >= 1 { return false }
            }
            if !selectedTags.isEmpty && selectedTags.isDisjoint(with: site.tags) { return false }
            if !selectedTypes.isEmpty && !selectedTypes.contains(resolvedSiteType(for: site)) { return false }
            if !selectedUsername.isEmpty
                && normalizedSiteIdentity(site.username) != normalizedSiteIdentity(selectedUsername) { return false }
            if !selectedEmail.isEmpty
                && normalizedSiteIdentity(site.email) != normalizedSiteIdentity(selectedEmail) { return false }
            return true
        }
        return values.sorted { left, right in
            if left.unread != right.unread { return left.unread > right.unread }
            let comparison: ComparisonResult
            switch sortField {
            case .updated: comparison = left.updatedAt.compare(right.updatedAt)
            case .name: comparison = left.siteKey.localizedCaseInsensitiveCompare(right.siteKey)
            case .nickname: comparison = left.name.localizedCaseInsensitiveCompare(right.name)
            case .joined: comparison = left.joinedAt.compare(right.joinedAt)
            case .lastVisit: comparison = left.latestActive.compare(right.latestActive)
            case .seedVolume: comparison = numberCompare(left.seedVolume, right.seedVolume)
            case .magic: comparison = numberCompare(left.magic, right.magic)
            case .score: comparison = numberCompare(left.score, right.score)
            case .uploaded: comparison = numberCompare(left.uploaded, right.uploaded)
            case .uploadDelta: comparison = numberCompare(left.uploadDelta, right.uploadDelta)
            case .downloaded: comparison = numberCompare(left.downloaded, right.downloaded)
            case .downloadDelta: comparison = numberCompare(left.downloadDelta, right.downloadDelta)
            case .published: comparison = numberCompare(Double(left.published), Double(right.published))
            case .bonusHour: comparison = numberCompare(left.bonusHour, right.bonusHour)
            case .invitations: comparison = numberCompare(Double(left.invitations), Double(right.invitations))
            case .leeching: comparison = numberCompare(Double(left.leeching), Double(right.leeching))
            case .seeding: comparison = numberCompare(Double(left.seeding), Double(right.seeding))
            case .ratio: comparison = numberCompare(left.ratio, right.ratio)
            case .sortID: comparison = left.sortID == right.sortID ? .orderedSame : (left.sortID < right.sortID ? .orderedAscending : .orderedDescending)
            }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    var availableTags: [String] { Array(Set(sites.flatMap(\.tags))).filter { !$0.isEmpty }.sorted() }
    var availableTypes: [String] { Array(Set(sites.map { resolvedSiteType(for: $0) })).filter { !$0.isEmpty }.sorted() }
    var availableUsernames: [String] {
        Array(Set(sites.map { $0.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }))
            .filter { !$0.isEmpty }
            .sorted()
    }
    var availableEmails: [String] {
        Array(Set(sites.map { $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }))
            .filter { !$0.isEmpty }
            .sorted()
    }
    var activeSiteCount: Int { sites.lazy.filter(\.enabled).count }
    var pendingSignInCount: Int { sites.lazy.filter { $0.enabled && $0.signIn && !$0.signed }.count }
    var unreadCount: Int { sites.reduce(0) { $0 + $1.unread } }
    var hasFilters: Bool {
        availability != .alive || condition != .all || !selectedTags.isEmpty || !selectedTypes.isEmpty
            || !selectedUsername.isEmpty || !selectedEmail.isEmpty || sortField != .updated || !ascending
    }

    func resetFilters() {
        availability = .alive
        condition = .all
        sortField = .updated
        ascending = SiteSortField.updated.defaultAscending
        selectedTags = []
        selectedTypes = []
        selectedUsername = ""
        selectedEmail = ""
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: SiteFilterStorageKey.availability)
        defaults.removeObject(forKey: SiteFilterStorageKey.condition)
        defaults.removeObject(forKey: SiteFilterStorageKey.sortField)
        defaults.removeObject(forKey: SiteFilterStorageKey.ascending)
    }

    func selectSortField(_ field: SiteSortField) {
        guard sortField != field else { return }
        sortField = field
        ascending = field.defaultAscending
    }

    func load(_ appState: AppState, cached: Bool = true) async {
        let cacheKey = "site.info.list"
        if !didRestoreCache {
            didRestoreCache = true
            if let cached = await appState.readSessionCache(cacheKey) {
                sites = jsonRows(cached.value).map(SiteItem.init)
                cachedAt = cached.cachedAt
                usingCachedData = true
            }
        }
        isLoading = sites.isEmpty && !usingCachedData
        defer { isLoading = false }
        do {
            let raw = try await appState.api(APIPath.sites, query: ["cached": cached])
            sites = jsonRows(raw).map(SiteItem.init)
            cachedAt = nil
            usingCachedData = false
            await appState.writeSessionCache(sites.map(sitePersistentCacheRow), name: cacheKey)
        } catch {
            if !usingCachedData { appState.presentedError = error.localizedDescription }
        }
        do {
            let configs = jsonRows(try await appState.api(APIPath.websiteList))
            var indexed: [String: [String: Any]] = [:]
            for config in configs {
                guard let key = config.string("name", "site")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                      !key.isEmpty else { continue }
                indexed[key] = config
            }
            siteConfigs = indexed
        } catch { }
    }

    func operate(_ appState: AppState, site: SiteItem, path: String) async {
        if await appState.perform(path + "\(site.id)", method: .get) {
            await load(appState, cached: false)
        }
    }

    func delete(_ appState: AppState, site: SiteItem) async {
        if await appState.perform("\(APIPath.sites)/\(site.id)", method: .delete) {
            sites.removeAll { $0.id == site.id }
            await appState.removeSessionCache("site.info.list")
            await load(appState, cached: false)
        }
    }

    private func numberCompare(_ left: Double, _ right: Double) -> ComparisonResult {
        if left == right { return .orderedSame }
        return left < right ? .orderedAscending : .orderedDescending
    }

    private func compactSiteSearchText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private func normalizedSiteIdentity(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func sitePersistentCacheRow(_ site: SiteItem) -> [String: Any] {
        site.raw.filter { key, _ in
            let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
            if normalized.contains("password") || normalized.contains("token") || normalized.contains("secret") {
                return false
            }
            return ![
                "cookie", "cookies", "passkey", "authkey", "localstorage",
                "authorization", "apikey", "rss", "torrents"
            ].contains(normalized)
        }
    }

    private func config(for site: SiteItem) -> [String: Any]? {
        siteConfigs[site.siteKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    private func resolvedSiteType(for site: SiteItem) -> String {
        config(for: site)?.string("type", "site_type", "siteType") ?? site.siteType
    }

    func logoCandidates(for site: SiteItem, appState: AppState) -> [RemoteImageCandidate] {
        var candidates: [RemoteImageCandidate] = []
        var seen = Set<String>()

        let siteName = site.siteKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var server = appState.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while server.hasSuffix("/") { server.removeLast() }
        if !siteName.isEmpty, let serverURL = URL(string: server + "/") {
            let headers = appState.accessToken.isEmpty
                ? [:]
                : ["Authorization": "Bearer \(appState.accessToken)"]
            for fileExtension in ["png", "gif", "jpg", "jpeg", "webp", "ico"] {
                let relative = "local/icons/\(urlPathSegment(siteName)).\(fileExtension)"
                guard let url = URL(string: relative, relativeTo: serverURL)?.absoluteURL else { continue }
                if seen.insert(url.absoluteString).inserted {
                    candidates.append(RemoteImageCandidate(url: url, headers: headers))
                }
            }
        }

        if let url = logoURL(for: site), seen.insert(url.absoluteString).inserted {
            candidates.append(RemoteImageCandidate(url: url))
        }
        return candidates
    }

    private func logoURL(for site: SiteItem) -> URL? {
        let siteConfig = config(for: site)
        let candidates = [
            site.iconURL,
            siteConfig?.string("logo", "icon", "favicon") ?? ""
        ]
        let baseValues = [site.url] + (siteConfig.map { configStrings($0["url"]) } ?? [])

        for rawValue in candidates {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            if value.hasPrefix("//") {
                let scheme = baseValues.compactMap { URL(string: $0)?.scheme }.first ?? "https"
                if let url = URL(string: "\(scheme):\(value)") { return url }
            }
            if let absolute = URL(string: value), ["http", "https"].contains(absolute.scheme?.lowercased() ?? "") {
                return absolute
            }
            for baseValue in baseValues {
                guard let baseURL = URL(string: baseValue),
                      ["http", "https"].contains(baseURL.scheme?.lowercased() ?? ""),
                      let resolved = URL(string: value, relativeTo: baseURL)?.absoluteURL else { continue }
                return resolved
            }
        }
        return nil
    }

    private func milestone(for site: SiteItem) -> SiteLevelMilestone? {
        guard let levels = config(for: site)?["level"] as? [String: Any] else { return nil }
        let parsed = levels.compactMap { key, value -> SiteLevelRequirement? in
            guard let row = value as? [String: Any] else { return nil }
            return SiteLevelRequirement(key: key, value: row)
        }
        let currentName = site.level.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentName.isEmpty,
              let current = parsed.first(where: { $0.key == currentName || $0.level == currentName || $0.name == currentName }) else { return nil }
        let reached = parsed.filter { level in
            if current.levelID > 0, level.levelID > 0 { return level.levelID <= current.levelID }
            return level.key == current.key
        }
        if reached.contains(where: \.graduation) { return .graduation }
        if reached.contains(where: \.keepAccount) { return .keepAccount }
        return nil
    }
}

struct SitesView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = SitesViewModel()
    @State private var showAdd = false
    @State private var showFilters = false
    @State private var showImport = false
    @State private var showGenerator = false
    @State private var showTimeline = false
    @State private var selectedSite: SiteItem?
    @State private var editingSite: SiteItem?
    @State private var deletingSite: SiteItem?
    @State private var repeatingSite: SiteItem?

    var body: some View {
        Group {
            if model.isLoading { LoadingState() }
            else if model.filtered.isEmpty {
                EmptyState(
                    icon: "globe.badge.chevron.backward",
                    title: model.sites.isEmpty ? "还没有站点" : "没有匹配站点",
                    detail: model.sites.isEmpty ? "添加站点后可同步流量、签到和辅种状态" : "调整搜索或筛选条件后再试",
                    actionTitle: model.sites.isEmpty ? "添加站点" : "清除筛选"
                ) {
                    if model.sites.isEmpty { showAdd = true }
                    else {
                        model.query = ""
                        model.resetFilters()
                    }
                }
            } else {
                VStack(spacing: 0) {
                    if model.usingCachedData {
                        SessionCacheBanner(cachedAt: model.cachedAt)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                    }
                    SiteListSummaryBar(
                        visibleCount: model.filtered.count,
                        totalCount: model.sites.count,
                        activeCount: model.activeSiteCount,
                        pendingSignInCount: model.pendingSignInCount,
                        unreadCount: model.unreadCount
                    )
                    List {
                        ForEach(model.filtered) { site in
                            Button {
                                selectedSite = site
                            } label: {
                                SiteRow(
                                    site: site,
                                    privacy: appState.privacyMode,
                                    iconCandidates: model.logoCandidates(for: site, appState: appState)
                                )
                            }
                                .buttonStyle(.plain)
                                .contextMenu { SiteActions(site: site, model: model) }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button { Task { await model.operate(appState, site: site, path: APIPath.siteSign) } } label: { Label("签到", systemImage: "checkmark.seal") }.tint(HarvestTheme.green)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button { editingSite = site } label: { Label("编辑", systemImage: "pencil") }.tint(HarvestTheme.amber)
                                    Button { Task { await model.operate(appState, site: site, path: APIPath.siteStatus) } } label: { Label("刷新", systemImage: "arrow.clockwise") }.tint(HarvestTheme.blue)
                                    Button(role: .destructive) { deletingSite = site } label: { Label("删除", systemImage: "trash") }
                                }
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color(uiColor: .systemGroupedBackground))
                    .refreshable { await model.load(appState) }
                }
            }
        }
        .searchable(text: $model.query, prompt: "站点、昵称、镜像、账号")
        .navigationTitle("站点")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showFilters = true } label: {
                    Image(systemName: model.hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("筛选和排序")
                Menu {
                    Button { showAdd = true } label: { Label("添加站点", systemImage: "plus") }
                    Button { showImport = true } label: { Label("导入站点", systemImage: "square.and.arrow.down") }
                    Button { showGenerator = true } label: { Label("配置生成器", systemImage: "doc.badge.gearshape") }
                    Button { showTimeline = true } label: { Label("站点时间轴", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("站点工具")
            }
        }
        .task { if model.isLoading { await model.load(appState) } }
        .onChange(of: appState.refreshGeneration) { _, _ in Task { await model.load(appState) } }
        .onReceive(NotificationCenter.default.publisher(for: .harvestLocalUIReset)) { _ in
            model.query = ""
            model.resetFilters()
        }
        .sheet(isPresented: $showAdd) { SiteEditorSheet(onSaved: { await model.load(appState, cached: false) }).environmentObject(appState) }
        .sheet(isPresented: $showFilters) { SiteFilterSheet(model: model) }
        .sheet(isPresented: $showImport) { SiteImportSheet(onComplete: { await model.load(appState, cached: false) }).environmentObject(appState) }
        .sheet(isPresented: $showGenerator) {
            SiteConfigGeneratorSheet(onSaved: { await model.load(appState, cached: false) })
                .environmentObject(appState)
        }
        .sheet(isPresented: $showTimeline) { SiteTimelineView(model: model).environmentObject(appState) }
        .sheet(item: $editingSite) { site in SiteEditorSheet(site: site, onSaved: { await model.load(appState, cached: false) }).environmentObject(appState) }
        .sheet(item: $selectedSite) { site in SiteDetailView(site: site, model: model).environmentObject(appState).presentationDetents([.medium, .large]) }
        .confirmationDialog(
            "确定删除站点「\(deletingSite?.name ?? "")」？",
            isPresented: Binding(get: { deletingSite != nil }, set: { if !$0 { deletingSite = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除站点", role: .destructive) {
                guard let site = deletingSite else { return }
                deletingSite = nil
                Task { await model.delete(appState, site: site) }
            }
            Button("取消", role: .cancel) { deletingSite = nil }
        }
        .confirmationDialog(
            "确定让站点「\(repeatingSite?.name ?? "")」执行辅种？",
            isPresented: Binding(get: { repeatingSite != nil }, set: { if !$0 { repeatingSite = nil } }),
            titleVisibility: .visible
        ) {
            Button("执行辅种") {
                guard let site = repeatingSite else { return }
                repeatingSite = nil
                Task { await model.operate(appState, site: site, path: APIPath.siteRepeat) }
            }
            Button("取消", role: .cancel) { repeatingSite = nil }
        }
    }

    @ViewBuilder private func SiteActions(site: SiteItem, model: SitesViewModel) -> some View {
        Button { editingSite = site } label: { Label("编辑", systemImage: "pencil") }
        Button { Task { await model.operate(appState, site: site, path: APIPath.siteStatus) } } label: { Label("刷新数据", systemImage: "arrow.clockwise") }
        Button { Task { await model.operate(appState, site: site, path: APIPath.siteSign) } } label: { Label("签到", systemImage: "checkmark.seal") }
        Button { repeatingSite = site } label: { Label("辅种", systemImage: "square.stack.3d.up") }
    }
}

private enum SiteTimelineOwnership: String, CaseIterable, Identifiable {
    case all = "全部站点"
    case owned = "仅已添加"
    case unowned = "仅未添加"
    var id: String { rawValue }
}

private enum SiteTimelineInviteFilter: String, CaseIterable, Identifiable {
    case all = "邀请：全部"
    case hasInvites = "有邀请"
    case noInvites = "无邀请"
    var id: String { rawValue }
}

private enum SiteTimelineSort: String, CaseIterable, Identifiable {
    case registered = "注册时间"
    case invitations = "邀请数量"
    case name = "站点名称"
    var id: String { rawValue }
}

private struct SiteTimelineEntry: Identifiable {
    let key: String
    let config: [String: Any]
    let site: SiteItem?

    var id: String { key.lowercased() }
    var displayName: String {
        let value = site?.name ?? config.string("nickname", "name") ?? key
        return value.isEmpty ? "未命名站点" : value
    }
    var isOwned: Bool { site != nil }
    var isDisabled: Bool { site?.enabled == false }
    var invitationCount: Int { site?.invitations ?? 0 }
    var registeredAt: Date? { site.flatMap { parseDate($0.joinedAt) } }
    var registeredText: String {
        guard let date = registeredAt else { return "未登记" }
        let values = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year ?? 0, values.month ?? 0, values.day ?? 0)
    }
    var durationText: String {
        guard let date = registeredAt else { return "-" }
        let days = max(0, Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0)
        let weeks = days / 7
        let remainingDays = days % 7
        if days == 0 { return "0周0天" }
        if remainingDays == 0 { return "\(weeks)周" }
        return "\(weeks)周\(remainingDays)天"
    }
    var urls: [String] {
        var values = site.map { [$0.url] } ?? []
        values.append(contentsOf: configStrings(config["url"]))
        return Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }
    var primaryURL: String { site?.url.isEmpty == false ? site?.url ?? "" : urls.first ?? "" }
    var browserSite: SiteItem {
        if let site { return site }
        let tagValues = configStrings(config["tags"])
            .flatMap { $0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } }
            .filter { !$0.isEmpty }
        let payload: [String: Any] = [
            "id": 0,
            "site": key,
            "nickname": displayName,
            "sort_id": 1,
            "mirror": primaryURL,
            "cookie": "",
            "local_storage": "",
            "user_agent": "",
            "tags": tagValues,
            "icon": config.string("icon", "logo", "favicon") ?? "",
            "available": true,
            "sign_in": config.bool("sign_in", "signIn") ?? true,
            "get_info": config.bool("get_info", "getInfo") ?? true,
            "repeat_torrents": config.bool("repeat_torrents", "repeatTorrents") ?? true,
            "search_torrents": config.bool("search_torrents", "searchTorrents") ?? true,
            "brush_free": config.bool("brush_free", "brushFree") ?? true,
            "brush_rss": config.bool("brush_rss", "brushRss") ?? false,
            "package_file": config.bool("package_file", "packageFile") ?? false,
            "hr_discern": config.bool("hr_discern", "hrDiscern") ?? false,
            "show_in_dash": true
        ]
        return SiteItem(payload)
    }
}

struct SiteTimelineView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: SitesViewModel
    @State private var configs: [[String: Any]] = []
    @State private var isLoading = true
    @State private var ownership: SiteTimelineOwnership = .all
    @State private var inviteFilter: SiteTimelineInviteFilter = .all
    @State private var sort: SiteTimelineSort = .registered
    @State private var ascending = true
    @AppStorage("site.timeline.titleShowDuration") private var showDurationOnTitle = false
    @AppStorage("site.timeline.showDuration") private var showDuration = false
    @AppStorage("site.timeline.showUploaded") private var showUploaded = false
    @AppStorage("site.timeline.showDownloaded") private var showDownloaded = false
    @AppStorage("site.timeline.showInvitation") private var showInvitation = true
    @AppStorage("site.timeline.showUsername") private var showUsername = false
    @AppStorage("site.timeline.showEmail") private var showEmail = false
    @AppStorage("site.timeline.showUID") private var showUID = false

    private var entries: [SiteTimelineEntry] {
        var sitesByKey: [String: SiteItem] = [:]
        for site in model.sites { sitesByKey[site.siteKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = site }
        var values: [SiteTimelineEntry] = configs.compactMap { config in
            guard let name = config.string("name", "site"), !name.isEmpty else { return nil }
            return SiteTimelineEntry(key: name, config: config, site: sitesByKey.removeValue(forKey: name.lowercased()))
        }
        values.append(contentsOf: sitesByKey.values.map { SiteTimelineEntry(key: $0.siteKey, config: [:], site: $0) })
        values = values.filter { entry in
            if ownership == .owned && !entry.isOwned { return false }
            if ownership == .unowned && entry.isOwned { return false }
            if inviteFilter == .hasInvites && entry.invitationCount <= 0 { return false }
            if inviteFilter == .noInvites && entry.invitationCount > 0 { return false }
            return true
        }
        let sorted = values.sorted { left, right in
            let comparison: ComparisonResult
            switch sort {
            case .registered:
                switch (left.registeredAt, right.registeredAt) {
                case let (lhs?, rhs?):
                    comparison = lhs == rhs ? left.displayName.localizedCaseInsensitiveCompare(right.displayName) : (lhs < rhs ? .orderedAscending : .orderedDescending)
                case (_?, nil): comparison = .orderedAscending
                case (nil, _?): comparison = .orderedDescending
                default: comparison = left.displayName.localizedCaseInsensitiveCompare(right.displayName)
                }
            case .invitations:
                comparison = left.invitationCount == right.invitationCount
                    ? left.displayName.localizedCaseInsensitiveCompare(right.displayName)
                    : (left.invitationCount < right.invitationCount ? .orderedAscending : .orderedDescending)
            case .name:
                comparison = left.displayName.localizedCaseInsensitiveCompare(right.displayName)
            }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
        let enabledOwned = sorted.filter { $0.isOwned && !$0.isDisabled }
        let disabledOwned = sorted.filter { $0.isOwned && $0.isDisabled }
        let unowned = sorted.filter { !$0.isOwned }.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        return enabledOwned + disabledOwned + unowned
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    LoadingState()
                } else if entries.isEmpty {
                    EmptyState(icon: "clock", title: "没有时间轴数据", detail: "添加站点配置后会在这里显示账号生命周期")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            timelineControls
                            ForEach(entries) { entry in timelineRow(entry) }
                        }
                        .padding(16)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .navigationTitle("站点时间轴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await load() }
        }
    }

    private var timelineControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("站点范围", selection: $ownership) { ForEach(SiteTimelineOwnership.allCases) { Text($0.rawValue).tag($0) } }
                } label: { Label(ownership.rawValue, systemImage: "line.3.horizontal.decrease") }
                .buttonStyle(.bordered)
                Menu {
                    Picker("邀请筛选", selection: $inviteFilter) { ForEach(SiteTimelineInviteFilter.allCases) { Text($0.rawValue).tag($0) } }
                } label: { Label(inviteFilter.rawValue, systemImage: "envelope") }
                .buttonStyle(.bordered)
                Menu {
                    Picker("排序字段", selection: $sort) { ForEach(SiteTimelineSort.allCases) { Text($0.rawValue).tag($0) } }
                    Divider()
                    Button { ascending.toggle() } label: { Label(ascending ? "正序" : "倒序", systemImage: ascending ? "arrow.up" : "arrow.down") }
                } label: { Label(sort.rawValue, systemImage: "arrow.up.arrow.down") }
                .buttonStyle(.bordered)
                Menu {
                    Picker("标题", selection: $showDurationOnTitle) {
                        Text("标题显示：注册日期").tag(false)
                        Text("标题显示：注册时长").tag(true)
                    }
                    Divider()
                    Toggle("注册时长", isOn: $showDuration)
                    Toggle("上传量", isOn: $showUploaded)
                    Toggle("下载量", isOn: $showDownloaded)
                    Toggle("邀请数", isOn: $showInvitation)
                    Toggle("用户名", isOn: $showUsername)
                    Toggle("邮箱", isOn: $showEmail)
                    Toggle("UID", isOn: $showUID)
                } label: { Label("显示字段", systemImage: "eye") }
                .buttonStyle(.bordered)
            }
        }
    }

    private func timelineRow(_ entry: SiteTimelineEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.displayName).font(.headline).lineLimit(1)
                    Text(entry.key).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(showDurationOnTitle ? entry.durationText : entry.registeredText)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                StatusPill(label: entry.isOwned ? (entry.isDisabled ? "已停用" : "已添加") : "未添加", color: entry.isOwned && !entry.isDisabled ? HarvestTheme.green : .secondary)
                if showInvitation { StatusPill(label: "\(entry.invitationCount) 个邀请", color: HarvestTheme.amber) }
                Spacer()
                if entry.urls.count > 1 {
                    Menu {
                        ForEach(entry.urls, id: \.self) { url in
                            NavigationLink {
                                browserDestination(entry, urlString: url)
                            } label: {
                                Label(browserURLLabel(url), systemImage: "globe")
                            }
                        }
                    } label: {
                        Image(systemName: "safari")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("选择 \(entry.displayName) 镜像")
                } else if !entry.primaryURL.isEmpty {
                    NavigationLink { browserDestination(entry, urlString: entry.primaryURL) } label: { Image(systemName: "safari") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("打开 \(entry.displayName)")
                }
            }
            if showDuration { timelineMetric("注册时长", value: entry.durationText) }
            if showUploaded { timelineMetric("上传量", value: entry.site.map { formatBytes($0.uploaded) } ?? "-") }
            if showDownloaded { timelineMetric("下载量", value: entry.site.map { formatBytes($0.downloaded) } ?? "-") }
            if showUsername { timelineMetric("用户名", value: privateValue(entry.site?.username ?? "-")) }
            if showEmail { timelineMetric("邮箱", value: privateValue(entry.site?.email ?? "-")) }
            if showUID { timelineMetric("UID", value: privateValue(entry.site?.userID ?? "-")) }
        }
        .cardSurface()
    }

    private func timelineMetric(_ label: String, value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).lineLimit(1).minimumScaleFactor(0.75) }
            .font(.caption)
    }

    private func privateValue(_ value: String) -> String { appState.privacyMode && value != "-" ? "••••" : value }

    @ViewBuilder private func browserDestination(_ entry: SiteTimelineEntry, urlString: String) -> some View {
        SiteBrowserScreen(site: entry.browserSite, urlString: urlString, title: entry.displayName) {
            await model.load(appState, cached: false)
        }
    }

    private func browserURLLabel(_ value: String) -> String {
        URL(string: value)?.host ?? value
    }

    @MainActor private func load() async {
        defer { isLoading = false }
        if model.sites.isEmpty { await model.load(appState) }
        do { configs = jsonRows(try await appState.api(APIPath.websiteList)) }
        catch { appState.presentedError = error.localizedDescription }
    }
}

struct SiteFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: SitesViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("状态") {
                    Picker("存活状态", selection: $model.availability) {
                        ForEach(SiteAvailabilityFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("详细条件", selection: $model.condition) {
                        ForEach(SiteConditionFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                if !model.availableTags.isEmpty {
                    Section("标签") {
                        ForEach(model.availableTags, id: \.self) { tag in
                            Toggle(tag, isOn: tagBinding(tag))
                        }
                    }
                }
                if !model.availableTypes.isEmpty {
                    Section("类型") {
                        ForEach(model.availableTypes, id: \.self) { type in
                            Toggle(type, isOn: typeBinding(type))
                        }
                    }
                }
                Section("身份") {
                    filterPicker("用户名", selection: $model.selectedUsername, values: model.availableUsernames)
                    filterPicker("邮箱", selection: $model.selectedEmail, values: model.availableEmails)
                }
                Section("排序") {
                    Picker(
                        "字段",
                        selection: Binding(
                            get: { model.sortField },
                            set: { model.selectSortField($0) }
                        )
                    ) {
                        ForEach(SiteSortField.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("方向", selection: $model.ascending) {
                        Text("降序").tag(false)
                        Text("升序").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("筛选和排序")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重置") { model.resetFilters() }.disabled(!model.hasFilters)
                }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func filterPicker(_ title: String, selection: Binding<String>, values: [String]) -> some View {
        Picker(title, selection: selection) {
            Text("全部").tag("")
            ForEach(values, id: \.self) { Text($0).tag($0) }
        }
    }

    private func tagBinding(_ tag: String) -> Binding<Bool> {
        Binding(
            get: { model.selectedTags.contains(tag) },
            set: { selected in
                if selected { model.selectedTags.insert(tag) }
                else { model.selectedTags.remove(tag) }
            }
        )
    }

    private func typeBinding(_ type: String) -> Binding<Bool> {
        Binding(
            get: { model.selectedTypes.contains(type) },
            set: { selected in
                if selected { model.selectedTypes.insert(type) }
                else { model.selectedTypes.remove(type) }
            }
        )
    }
}

private struct SiteUploadFile: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
    let mimeType: String
}

private enum SiteBackupSource: String, CaseIterable, Identifiable {
    case ptpp = "PTPP"
    case ptd = "PT-depiler"
    var id: String { rawValue }
    var path: String { self == .ptpp ? APIPath.siteImportPTPP : APIPath.siteImportPTD }
}

struct SiteImportSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onComplete: () async -> Void
    @State private var tomlFiles: [SiteUploadFile] = []
    @State private var backupFile: SiteUploadFile?
    @State private var backupSource: SiteBackupSource = .ptpp
    @State private var overwrite = false
    @State private var showTomlPicker = false
    @State private var showBackupPicker = false
    @State private var bulkField = "user_agent"
    @State private var bulkValue = ""
    @State private var bulkStatus = ""
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section("TOML 站点配置") {
                    Button { showTomlPicker = true } label: {
                        Label(tomlFiles.isEmpty ? "选择 TOML 文件" : "已选择 \(tomlFiles.count) 个文件", systemImage: "doc.badge.plus")
                    }
                    ForEach(tomlFiles) { file in
                        HStack {
                            Image(systemName: "doc.text")
                            Text(file.name).lineLimit(1)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { tomlFiles.remove(atOffsets: $0) }
                    Toggle("覆盖同名配置", isOn: $overwrite)
                    Button { Task { await uploadTOML() } } label: {
                        Label("上传配置", systemImage: "square.and.arrow.up")
                    }
                    .disabled(tomlFiles.isEmpty || isWorking)
                }

                Section("外部站点备份") {
                    Picker("来源", selection: $backupSource) {
                        ForEach(SiteBackupSource.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Button { showBackupPicker = true } label: {
                        Label(backupFile?.name ?? "选择备份文件", systemImage: "archivebox")
                    }
                    Button { Task { await uploadBackup() } } label: {
                        Label("导入 \(backupSource.rawValue)", systemImage: "square.and.arrow.down")
                    }
                    .disabled(backupFile == nil || isWorking)
                }

                Section("CookieCloud") {
                    Button { Task { await syncCookieCloud() } } label: {
                        Label("同步站点数据", systemImage: "icloud.and.arrow.down")
                    }
                    .disabled(isWorking)
                }

                Section("批量替换") {
                    Picker("字段", selection: $bulkField) {
                        Text("User-Agent").tag("user_agent")
                        Text("Proxy").tag("proxy")
                    }
                    TextField(bulkField == "user_agent" ? "Mozilla/5.0 ..." : "代理地址或 JSON", text: $bulkValue, axis: .vertical)
                        .textInputAutocapitalization(.never)
                    Button(role: .destructive) { Task { await bulkUpgrade() } } label: {
                        Label("提交批量替换", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(bulkValue.isEmpty || isWorking)
                    if !bulkStatus.isEmpty {
                        Label(bulkStatus, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(HarvestTheme.green)
                    }
                }
            }
            .disabled(isWorking)
            .overlay { if isWorking { ProgressView().controlSize(.large) } }
            .navigationTitle("导入与批量工具")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(isWorking) } }
            .fileImporter(
                isPresented: $showTomlPicker,
                allowedContentTypes: [UTType(filenameExtension: "toml") ?? .plainText],
                allowsMultipleSelection: true,
                onCompletion: selectTOML
            )
            .fileImporter(
                isPresented: $showBackupPicker,
                allowedContentTypes: [.data, .json, .archive],
                allowsMultipleSelection: false,
                onCompletion: selectBackup
            )
        }
    }

    private func selectTOML(_ result: Result<[URL], Error>) {
        do {
            tomlFiles = try result.get().filter { $0.pathExtension.lowercased() == "toml" }.map {
                SiteUploadFile(name: $0.lastPathComponent, data: try readImportedFile($0), mimeType: "application/toml")
            }
            if tomlFiles.isEmpty { appState.presentedError = "请选择 TOML 配置文件" }
        } catch { appState.presentedError = "读取配置文件失败：\(error.localizedDescription)" }
    }

    private func selectBackup(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            backupFile = SiteUploadFile(name: url.lastPathComponent, data: try readImportedFile(url), mimeType: "application/octet-stream")
        } catch { appState.presentedError = "读取备份文件失败：\(error.localizedDescription)" }
    }

    @MainActor private func uploadTOML() async {
        guard !tomlFiles.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await appState.upload(
                APIPath.siteImportTOML,
                fields: ["overwrite": String(overwrite)],
                parts: tomlFiles.map { MultipartPart(fieldName: "files", fileName: $0.name, mimeType: $0.mimeType, data: $0.data) }
            )
            tomlFiles = []
            await onComplete()
        } catch { appState.presentedError = error.localizedDescription }
    }

    @MainActor private func uploadBackup() async {
        guard let backupFile else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await appState.upload(
                backupSource.path,
                parts: [MultipartPart(fieldName: "file", fileName: backupFile.name, mimeType: backupFile.mimeType, data: backupFile.data)]
            )
            self.backupFile = nil
            await onComplete()
        } catch { appState.presentedError = error.localizedDescription }
    }

    @MainActor private func syncCookieCloud() async {
        isWorking = true
        defer { isWorking = false }
        if await appState.perform(APIPath.siteImportCookieCloud, method: .get) { await onComplete() }
    }

    @MainActor private func bulkUpgrade() async {
        let value = parseJSONFragment(bulkValue)
        isWorking = true
        defer { isWorking = false }
        if await appState.perform(APIPath.siteBulkUpgrade, body: ["key": bulkField, "value": value]) {
            bulkStatus = "批量替换任务已提交"
            bulkValue = ""
            await onComplete()
        }
    }
}

struct SiteConfigGeneratorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onSaved: () async -> Void
    @State private var configs: [[String: Any]] = []
    @State private var selectedName = ""
    @State private var configName = ""
    @State private var content = ""
    @State private var overwrite = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var exportedFile: GeneratedSiteConfigFile?
    @State private var editorMode = SiteConfigEditorMode.form

    init(onSaved: @escaping () async -> Void = {}) {
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("模板") {
                    Picker("站点模板", selection: $selectedName) {
                        ForEach(configNames, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: selectedName) { _, value in Task { await loadTemplate(value) } }
                    TextField("配置名称", text: $configName)
                    Picker("编辑模式", selection: $editorMode) {
                        ForEach(SiteConfigEditorMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if editorMode == .form {
                    SiteConfigStructuredEditor(content: $content)
                } else {
                    Section("TOML") {
                        TextEditor(text: $content)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 340)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                Section {
                    Toggle("覆盖同名配置", isOn: $overwrite)
                    Button { export() } label: {
                        Label("导出或分享 TOML", systemImage: "square.and.arrow.up")
                    }
                    .disabled(configName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.isEmpty || isSaving)
                    Button {
                        UIPasteboard.general.string = synchronizedContent
                    } label: {
                        Label("复制 TOML", systemImage: "doc.on.doc")
                    }
                    .disabled(content.isEmpty)
                    Button { Task { await save() } } label: {
                        Label("保存到服务器", systemImage: "externaldrive.badge.checkmark")
                    }
                    .disabled(configName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.isEmpty || isSaving)
                }
            }
            .overlay { if isLoading || isSaving { ProgressView().controlSize(.large) } }
            .navigationTitle("站点配置生成器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(isSaving) } }
            .task { await loadConfigs() }
            .sheet(item: $exportedFile) { file in ActivityShareSheet(items: [file.url]) }
        }
    }

    private var configNames: [String] {
        configs.compactMap { $0.string("name", "site") }.filter { !$0.isEmpty }
    }

    @MainActor private func loadConfigs() async {
        isLoading = true
        defer { isLoading = false }
        do {
            configs = jsonRows(try await appState.api(APIPath.websiteList))
            selectedName = configNames.first(where: { $0 == "NP模板" }) ?? configNames.first ?? ""
            await loadTemplate(selectedName)
        } catch { appState.presentedError = error.localizedDescription }
    }

    @MainActor private func loadTemplate(_ name: String) async {
        guard !name.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let raw = try await appState.api("\(APIPath.websiteList)/\(urlPathSegment(name))")
            content = extractTOML(raw) ?? configToTOML(configs.first { $0.string("name", "site") == name } ?? [:])
            configName = tomlName(content) ?? name
        } catch {
            content = configToTOML(configs.first { $0.string("name", "site") == name } ?? [:])
            configName = name
            appState.presentedError = "模板接口加载失败，已使用列表数据生成基础模板"
        }
    }

    @MainActor private func save() async {
        let normalizedName = safeFileName(configName)
        guard !normalizedName.isEmpty, let data = synchronizedContent.data(using: .utf8) else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await appState.upload(
                APIPath.siteImportTOML,
                fields: ["overwrite": String(overwrite)],
                parts: [MultipartPart(fieldName: "files", fileName: "\(normalizedName).toml", mimeType: "application/toml", data: data)]
            )
            await onSaved()
        } catch { appState.presentedError = error.localizedDescription }
    }

    @MainActor private func export() {
        let normalizedName = safeFileName(configName)
        guard !normalizedName.isEmpty, let data = synchronizedContent.data(using: .utf8) else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("harvest_site_configs", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(normalizedName).toml")
            try data.write(to: url, options: .atomic)
            exportedFile = GeneratedSiteConfigFile(url: url)
        } catch {
            appState.presentedError = "导出站点配置失败：\(error.localizedDescription)"
        }
    }

    private var synchronizedContent: String {
        replacingTOMLName(in: content, with: configName.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private enum SiteConfigEditorMode: String, CaseIterable, Identifiable {
    case form = "表单"
    case source = "源码"
    var id: String { rawValue }
}

private enum TOMLStructuredValueKind: Equatable {
    case string
    case number
    case boolean
    case list
}

private struct TOMLStructuredField: Identifiable {
    let section: String?
    let key: String
    let lineIndex: Int
    let rawValue: String
    let comment: String
    let kind: TOMLStructuredValueKind

    var id: String { "\(section ?? "root")|\(key)|\(lineIndex)" }
}

private struct TOMLStructuredLevel: Identifiable {
    let section: String
    let startLine: Int
    let endLine: Int
    let fields: [TOMLStructuredField]

    var id: String { "\(section)|\(startLine)" }
    var displayName: String {
        let name = fields.first(where: { $0.key == "name" }).map { tomlEditableValue($0.rawValue, kind: $0.kind) } ?? ""
        if !name.isEmpty { return name }
        let level = fields.first(where: { $0.key == "level" }).map { tomlEditableValue($0.rawValue, kind: $0.kind) } ?? ""
        return level.isEmpty ? section.replacingOccurrences(of: "level.", with: "") : level
    }
}

private struct TOMLStructuredDocument {
    let fields: [TOMLStructuredField]
    let levels: [TOMLStructuredLevel]

    init(_ content: String) {
        let lines = content.components(separatedBy: "\n")
        var parsedFields: [TOMLStructuredField] = []
        var sections: [(name: String, line: Int)] = []
        var activeSection: String?

        for (index, line) in lines.enumerated() {
            if let section = tomlSectionName(line) {
                activeSection = section
                sections.append((section, index))
                continue
            }
            guard let assignment = tomlAssignment(line) else { continue }
            parsedFields.append(
                TOMLStructuredField(
                    section: activeSection,
                    key: assignment.key,
                    lineIndex: index,
                    rawValue: assignment.value,
                    comment: assignment.comment,
                    kind: inferTOMLKind(assignment.value)
                )
            )
        }

        fields = parsedFields
        levels = sections.enumerated().compactMap { index, section in
            guard section.name.hasPrefix("level.") else { return nil }
            let nextStart = sections.indices.contains(index + 1) ? sections[index + 1].line : lines.count
            return TOMLStructuredLevel(
                section: section.name,
                startLine: section.line,
                endLine: max(section.line, nextStart - 1),
                fields: parsedFields.filter { $0.section == section.name }
            )
        }
    }
}

private struct TOMLFieldGroup: Identifiable {
    let title: String
    let fields: [TOMLStructuredField]
    var id: String { title }
}

private struct SiteConfigStructuredEditor: View {
    @Binding var content: String

    private var document: TOMLStructuredDocument { TOMLStructuredDocument(content) }
    private var groups: [TOMLFieldGroup] { tomlFieldGroups(document.fields.filter { $0.section == nil }) }

    var body: some View {
        if groups.isEmpty && document.levels.isEmpty {
            Section {
                ContentUnavailableView("没有可编辑字段", systemImage: "doc.text.magnifyingglass")
            }
        } else {
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.fields) { field in fieldEditor(field) }
                }
            }
            Section("等级信息") {
                Button { content = appendingTOMLLevel(to: content) } label: {
                    Label("添加等级", systemImage: "plus")
                }
                ForEach(document.levels) { level in
                    DisclosureGroup {
                        ForEach(level.fields) { field in fieldEditor(field) }
                        Button(role: .destructive) {
                            content = removingTOMLLevel(level, from: content)
                        } label: {
                            Label("删除等级", systemImage: "trash")
                        }
                    } label: {
                        Label(level.displayName, systemImage: "medal")
                    }
                }
            }
        }
    }

    @ViewBuilder private func fieldEditor(_ field: TOMLStructuredField) -> some View {
        if field.kind == .boolean {
            Toggle(tomlFieldLabel(field.key), isOn: booleanBinding(for: field))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(tomlFieldLabel(field.key)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField(field.key, text: textBinding(for: field), axis: .vertical)
                    .lineLimit(field.kind == .list ? 2...6 : 1...4)
                    .font(.system(.body, design: field.key.hasSuffix("_rule") ? .monospaced : .default))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(field.kind == .number ? .decimalPad : .default)
            }
            .padding(.vertical, 2)
        }
    }

    private func textBinding(for field: TOMLStructuredField) -> Binding<String> {
        Binding {
            let current = TOMLStructuredDocument(content).fields.first { $0.id == field.id } ?? field
            return tomlEditableValue(current.rawValue, kind: current.kind)
        } set: { value in
            let current = TOMLStructuredDocument(content).fields.first { $0.id == field.id } ?? field
            content = replacingTOMLField(current, with: value, in: content)
        }
    }

    private func booleanBinding(for field: TOMLStructuredField) -> Binding<Bool> {
        Binding {
            let current = TOMLStructuredDocument(content).fields.first { $0.id == field.id } ?? field
            return current.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
        } set: { value in
            let current = TOMLStructuredDocument(content).fields.first { $0.id == field.id } ?? field
            content = replacingTOMLField(current, with: value ? "true" : "false", in: content)
        }
    }
}

private func tomlFieldGroups(_ fields: [TOMLStructuredField]) -> [TOMLFieldGroup] {
    let hidden = Set(["name", "site", "buy_page", "buy_action"])
    let available = fields.filter { !hidden.contains($0.key) }
    var consumed: Set<String> = []
    var groups: [TOMLFieldGroup] = []

    func append(_ title: String, matching predicate: (TOMLStructuredField) -> Bool) {
        let matches = available.filter { !consumed.contains($0.id) && predicate($0) }
        guard !matches.isEmpty else { return }
        consumed.formUnion(matches.map(\.id))
        groups.append(TOMLFieldGroup(title: title, fields: matches))
    }

    let base = Set(["url", "nickname", "logo", "tracker", "sp_full", "limit_speed", "tags", "iyuu", "structure", "type", "nation", "sign_type"])
    let hr = Set(["hr", "hr_rate", "hr_time"])
    let switches = Set(["sign_in", "get_info", "repeat_torrents", "brush_free", "brush_rss", "hr_discern", "search_torrents", "alive", "pieces_repeat", "proxy"])
    append("基础信息") { base.contains($0.key) }
    append("HR 相关") { hr.contains($0.key) }
    append("功能开关") { switches.contains($0.key) }
    append("页面链接") { $0.key.hasPrefix("page_") }
    append("个人信息规则") { ($0.key.hasPrefix("my_") && $0.key.hasSuffix("_rule")) || $0.key.hasPrefix("sign_info_") }
    append("种子列表规则") { $0.key == "torrents_rule" || ($0.key.hasPrefix("torrent_") && $0.key.hasSuffix("_rule")) }
    append("种子详情规则") { $0.key.hasPrefix("detail_") && $0.key.hasSuffix("_rule") }
    append("其他字段") { _ in true }
    return groups
}

private func tomlSectionName(_ line: String) -> String? {
    let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.hasPrefix("["), !text.hasPrefix("[["), let end = text.firstIndex(of: "]") else { return nil }
    let start = text.index(after: text.startIndex)
    let name = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : name
}

private func tomlAssignment(_ line: String) -> (key: String, value: String, comment: String)? {
    guard let separator = line.firstIndex(of: "=") else { return nil }
    let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
    let tail = String(line[line.index(after: separator)...])
    let split = splitTOMLComment(tail)
    guard !split.value.isEmpty else { return nil }
    return (key, split.value, split.comment)
}

private func splitTOMLComment(_ value: String) -> (value: String, comment: String) {
    var quote: Character?
    var escaped = false
    for index in value.indices {
        let character = value[index]
        if escaped {
            escaped = false
            continue
        }
        if character == "\\", quote == "\"" {
            escaped = true
            continue
        }
        if character == "\"" || character == "'" {
            if quote == character { quote = nil }
            else if quote == nil { quote = character }
            continue
        }
        if character == "#", quote == nil {
            let raw = String(value[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
            let comment = String(value[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw, comment)
        }
    }
    return (value.trimmingCharacters(in: .whitespacesAndNewlines), "")
}

private func inferTOMLKind(_ rawValue: String) -> TOMLStructuredValueKind {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if value == "true" || value == "false" { return .boolean }
    if value.hasPrefix("[") { return .list }
    if Double(value) != nil { return .number }
    return .string
}

private func tomlEditableValue(_ rawValue: String, kind: TOMLStructuredValueKind) -> String {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if kind == .list {
        guard value.hasPrefix("["), value.hasSuffix("]") else { return value }
        return value.dropFirst().dropLast().split(separator: ",", omittingEmptySubsequences: true)
            .map { unquoteTOMLString(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
    return kind == .string ? unquoteTOMLString(value) : value
}

private func unquoteTOMLString(_ value: String) -> String {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.count >= 2,
          (text.hasPrefix("\"") && text.hasSuffix("\"") || text.hasPrefix("'") && text.hasSuffix("'")) else { return text }
    return String(text.dropFirst().dropLast())
        .replacingOccurrences(of: "\\\"", with: "\"")
        .replacingOccurrences(of: "\\\\", with: "\\")
}

private func formattedTOMLValue(_ value: String, kind: TOMLStructuredValueKind) -> String {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    switch kind {
    case .boolean:
        return text.lowercased() == "true" ? "true" : "false"
    case .number:
        return text.isEmpty ? "0" : text
    case .string:
        return tomlQuotedString(text)
    case .list:
        let items = text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { unquoteTOMLString($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
            .map(tomlQuotedString)
            .joined(separator: ", ")
        return items.isEmpty ? "[]" : "[ \(items),]"
    }
}

private func tomlQuotedString(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

private func replacingTOMLField(_ field: TOMLStructuredField, with value: String, in content: String) -> String {
    var lines = content.components(separatedBy: "\n")
    guard lines.indices.contains(field.lineIndex) else { return content }
    let formatted = formattedTOMLValue(value, kind: field.kind)
    lines[field.lineIndex] = "\(field.key) = \(formatted)\(field.comment.isEmpty ? "" : " \(field.comment)")"
    return lines.joined(separator: "\n")
}

private func appendingTOMLLevel(to content: String) -> String {
    let document = TOMLStructuredDocument(content)
    let usedIDs = Set(document.levels.compactMap { level in
        level.fields.first(where: { $0.key == "level_id" }).flatMap { Int(tomlEditableValue($0.rawValue, kind: $0.kind)) }
    })
    var nextID = 1
    while usedIDs.contains(nextID) { nextID += 1 }
    let name = "Level\(nextID)"
    let block = """
    [level.\(name)]
    level_id = \(nextID)
    level = "\(name)"
    name = "\(name)"
    days = 0
    downloaded = "0"
    uploaded = "0"
    ratio = 0.0
    bonus = 0.0
    score = 0
    torrents = 0
    leeches = 0
    seeding_delta = 0.0
    keep_account = false
    graduation = false
    rights = ""
    """
    var updated = content
    if !updated.isEmpty, !updated.hasSuffix("\n") { updated += "\n" }
    if !updated.isEmpty { updated += "\n" }
    return updated + block + "\n"
}

private func removingTOMLLevel(_ level: TOMLStructuredLevel, from content: String) -> String {
    var lines = content.components(separatedBy: "\n")
    guard lines.indices.contains(level.startLine), lines.indices.contains(level.endLine) else { return content }
    lines.removeSubrange(level.startLine...level.endLine)
    if level.startLine > 0, lines.indices.contains(level.startLine - 1), lines[level.startLine - 1].isEmpty,
       lines.indices.contains(level.startLine), lines[level.startLine].isEmpty {
        lines.remove(at: level.startLine)
    }
    return lines.joined(separator: "\n")
}

private func tomlFieldLabel(_ key: String) -> String {
    let labels = [
        "url": "站点地址", "nickname": "站点昵称", "logo": "站点图标", "tracker": "Tracker 域名",
        "sp_full": "满魔力阈值", "limit_speed": "限速阈值", "tags": "站点标签", "iyuu": "IYUU ID",
        "structure": "站点架构", "type": "站点类型", "nation": "站点地区", "sign_type": "签到类型",
        "hr": "启用 HR", "hr_rate": "HR 分享率要求", "hr_time": "HR 时间要求",
        "sign_in": "启用签到", "get_info": "获取用户信息", "repeat_torrents": "辅种识别",
        "brush_free": "免费刷流", "brush_rss": "RSS 刷流", "hr_discern": "HR 识别",
        "search_torrents": "资源搜索", "alive": "配置启用", "pieces_repeat": "分片辅种", "proxy": "使用代理",
        "torrents_rule": "种子列表行规则", "level_id": "等级 ID", "level": "等级名称", "name": "显示名称",
        "days": "注册周数要求", "uploaded": "上传量要求", "downloaded": "下载量要求", "bonus": "魔力值要求",
        "score": "积分要求", "ratio": "分享率要求", "torrents": "发布种子要求", "leeches": "下载任务要求",
        "seeding_delta": "做种增量要求", "keep_account": "保留账号", "graduation": "毕业等级", "rights": "等级权益说明"
    ]
    if let label = labels[key] { return label }
    if key.hasPrefix("page_") { return "页面路径：\(key.dropFirst(5))" }
    if key.hasPrefix("my_"), key.hasSuffix("_rule") { return "用户信息规则：\(key.dropFirst(3).dropLast(5))" }
    if key.hasPrefix("torrent_"), key.hasSuffix("_rule") { return "种子列表规则：\(key.dropFirst(8).dropLast(5))" }
    if key.hasPrefix("detail_"), key.hasSuffix("_rule") { return "详情页规则：\(key.dropFirst(7).dropLast(5))" }
    if key.hasPrefix("sign_info_") { return "签到信息：\(key.dropFirst(10))" }
    return key
}

private struct GeneratedSiteConfigFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

private func readImportedFile(_ url: URL) throws -> Data {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return try Data(contentsOf: url, options: .mappedIfSafe)
}

private func parseJSONFragment(_ value: String) -> Any {
    guard let data = value.data(using: .utf8),
          let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return value }
    return parsed
}

private func extractTOML(_ value: Any) -> String? {
    if let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
    guard let dictionary = value as? [String: Any] else { return nil }
    for key in ["content", "toml", "text", "file", "config", "data", "result"] {
        if let nested = dictionary[key], let text = extractTOML(nested) { return text }
    }
    return dictionary.isEmpty ? nil : configToTOML(dictionary)
}

private func configToTOML(_ dictionary: [String: Any]) -> String {
    let ignored = Set(["id", "created_at", "updated_at"])
    var chunks: [String] = []

    func appendTable(_ values: [String: Any], path: [String]) {
        let keys = values.keys.filter { !ignored.contains($0) }.sorted()
        let scalarLines = keys.compactMap { key -> String? in
            guard let value = values[key], value as? [String: Any] == nil,
                  let literal = tomlLiteral(value) else { return nil }
            return "\(tomlTableKey(key)) = \(literal)"
        }
        if !scalarLines.isEmpty {
            let header = path.isEmpty ? "" : "[\(path.map(tomlTableKey).joined(separator: "."))]\n"
            chunks.append(header + scalarLines.joined(separator: "\n"))
        }
        for key in keys {
            guard let nested = values[key] as? [String: Any] else { continue }
            appendTable(nested, path: path + [key])
        }
    }

    appendTable(dictionary, path: [])
    return chunks.joined(separator: "\n\n") + (chunks.isEmpty ? "" : "\n")
}

private func tomlTableKey(_ value: String) -> String {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
    if !value.isEmpty, value.unicodeScalars.allSatisfy({ allowed.contains($0) }) { return value }
    return tomlQuotedString(value)
}

private func tomlLiteral(_ value: Any) -> String? {
    if value is NSNull { return nil }
    if let value = value as? Bool { return value ? "true" : "false" }
    if let value = value as? NSNumber { return value.stringValue }
    if let values = value as? [Any] {
        return "[" + values.compactMap(tomlLiteral).joined(separator: ", ") + "]"
    }
    let text = String(describing: value).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(text)\""
}

private func tomlName(_ content: String) -> String? {
    let pattern = #"(?m)^\s*name\s*=\s*[\"']([^\"']+)[\"']"#
    guard let expression = try? NSRegularExpression(pattern: pattern),
          let match = expression.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
          let range = Range(match.range(at: 1), in: content) else { return nil }
    return String(content[range])
}

private func replacingTOMLName(in content: String, with name: String) -> String {
    guard !name.isEmpty else { return content }
    let escaped = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let replacement = "name = \"\(escaped)\""
    let pattern = #"(?m)^\s*name\s*=\s*[^\r\n]+"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return content }
    let searchRange = NSRange(content.startIndex..., in: content)
    if let match = expression.firstMatch(in: content, range: searchRange),
       let range = Range(match.range, in: content) {
        var updated = content
        updated.replaceSubrange(range, with: replacement)
        return updated
    }
    return replacement + "\n" + content
}

private func safeFileName(_ value: String) -> String {
    let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
    return value.components(separatedBy: invalid).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
}

struct SiteRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let site: SiteItem
    let privacy: Bool
    let iconCandidates: [RemoteImageCandidate]

    init(site: SiteItem, privacy: Bool, iconCandidates: [RemoteImageCandidate] = []) {
        self.site = site
        self.privacy = privacy
        self.iconCandidates = iconCandidates
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            trafficSection
            coreMetrics
            Divider()
            accountMetadata
            Divider()
            activityMetadata
        }
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
                .stroke(site.enabled ? HarvestTheme.green.opacity(0.22) : HarvestTheme.coral.opacity(0.18))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var metricColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    private var metadataColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            siteLogo(size: 54)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(site.name)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    SiteAvailabilityBadge(enabled: site.enabled)
                }

                Text(siteIdentityText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if !headerStatuses.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            ForEach(headerStatuses) { status in
                                SiteInlineStatus(status: status)
                            }
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(headerStatuses) { status in
                                SiteInlineStatus(status: status)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var trafficSection: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                uploadMetric
                Divider()
                downloadMetric
            }
        } else {
            HStack(spacing: 0) {
                uploadMetric
                Divider().frame(height: 60)
                downloadMetric
            }
        }
    }

    private var uploadMetric: some View {
        SiteTrafficMetric(
            label: "上传",
            value: privateValue(formatBytes(site.uploaded)),
            delta: dailyDeltaText(site.uploadDelta),
            icon: "arrow.up",
            color: HarvestTheme.green
        )
    }

    private var downloadMetric: some View {
        SiteTrafficMetric(
            label: "下载",
            value: privateValue(formatBytes(site.downloaded)),
            delta: dailyDeltaText(site.downloadDelta),
            icon: "arrow.down",
            color: HarvestTheme.blue
        )
    }

    private var coreMetrics: some View {
        LazyVGrid(columns: metricColumns, spacing: 10) {
            SiteCardMetric(icon: "leaf.fill", label: "做种", value: "\(site.seeding)", color: HarvestTheme.green)
            SiteCardMetric(icon: "arrow.down.circle.fill", label: "下载中", value: "\(site.leeching)", color: HarvestTheme.blue)
            SiteCardMetric(icon: "bolt.fill", label: "魔力", value: formatCompactNumber(site.magic), color: HarvestTheme.amber)
            SiteCardMetric(icon: "diamond.fill", label: "积分", value: formatCompactNumber(site.score), color: HarvestTheme.coral)
            SiteCardMetric(icon: "arrow.triangle.2.circlepath", label: "分享率", value: ratioText, color: ratioColor)
            SiteCardMetric(icon: "timer", label: "时魔", value: formatCompactNumber(site.bonusHour), color: HarvestTheme.amber)
            SiteCardMetric(icon: "paperplane.fill", label: "发种", value: "\(site.published)", color: HarvestTheme.blue)
            SiteCardMetric(icon: "externaldrive.fill", label: "做种量", value: privateValue(formatBytes(site.seedVolume)), color: HarvestTheme.green)
        }
        .padding(.top, 2)
    }

    private var accountMetadata: some View {
        LazyVGrid(columns: metadataColumns, alignment: .leading, spacing: 11) {
            SiteMetadataMetric(icon: "ticket.fill", label: "邀请", value: "\(site.invitations)", color: HarvestTheme.coral)
            SiteMetadataMetric(icon: "calendar", label: "做种天数", value: "\(site.seedDays) 天", color: HarvestTheme.green)
            SiteMetadataMetric(icon: "exclamationmark.triangle.fill", label: "H&R", value: hrText, color: HarvestTheme.amber)
            SiteMetadataMetric(icon: "envelope.fill", label: "邮件", value: "\(site.mail)", color: HarvestTheme.blue)
            SiteMetadataMetric(icon: "bell.fill", label: "通知", value: "\(site.notice)", color: HarvestTheme.coral)
            SiteMetadataMetric(icon: "bell.badge.fill", label: "未读", value: "\(site.unread)", color: HarvestTheme.coral)
        }
    }

    private var activityMetadata: some View {
        VStack(spacing: 8) {
            SiteDetailLine(icon: "person.badge.clock", label: "注册", value: joinedText, color: HarvestTheme.blue)
            SiteDetailLine(icon: "clock.fill", label: "活跃", value: shortDate(site.latestActive), color: HarvestTheme.green)
            SiteDetailLine(icon: "arrow.clockwise", label: "同步", value: shortDate(site.updatedAt), color: HarvestTheme.amber)
            if !site.tags.isEmpty {
                SiteDetailLine(
                    icon: "tag.fill",
                    label: "标签",
                    value: site.tags.joined(separator: " · "),
                    color: HarvestTheme.blue,
                    lineLimit: nil
                )
            }
        }
    }

    private func siteLogo(size: CGFloat) -> some View {
        let radius = min(14, size * 0.24)
        return ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(site.enabled ? HarvestTheme.blue : Color.secondary)
            CachedRemoteImageCandidates(candidates: iconCandidates) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.12)
            } placeholder: {
                Image(systemName: site.enabled ? "globe.asia.australia.fill" : "globe.asia.australia")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(site.enabled ? HarvestTheme.green : HarvestTheme.coral)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                .offset(x: 2, y: 2)
        }
        .accessibilityHidden(true)
    }

    private var headerStatuses: [SiteStatusDescriptor] {
        var statuses: [SiteStatusDescriptor] = []
        if site.signed {
            statuses.append(SiteStatusDescriptor(id: "signed", label: "今日已签到", icon: "checkmark.seal.fill", color: HarvestTheme.green))
        } else if site.signIn {
            statuses.append(SiteStatusDescriptor(id: "sign", label: "今日待签到", icon: "checkmark.seal", color: HarvestTheme.amber))
        }
        let level = site.level.trimmingCharacters(in: .whitespacesAndNewlines)
        if !level.isEmpty {
            statuses.append(SiteStatusDescriptor(id: "level", label: level, icon: "medal.fill", color: HarvestTheme.blue))
        }
        return statuses
    }

    private func dailyDeltaText(_ value: Double) -> String {
        guard !privacy else { return "今日 ••••" }
        guard site.hasTodayData else { return "今日暂无增量" }
        let prefix = value > 0 ? "+" : value < 0 ? "-" : ""
        return "今日 \(prefix)\(formatBytes(abs(value)))"
    }

    private var siteIdentityText: String {
        let host = URL(string: site.url)?.host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !host.isEmpty, !site.siteKey.isEmpty, host.caseInsensitiveCompare(site.siteKey) != .orderedSame {
            return "\(site.siteKey) · \(host)"
        }
        if !host.isEmpty { return host }
        return site.siteKey.isEmpty ? "未配置站点地址" : site.siteKey
    }

    private var joinedText: String {
        guard let joined = parseDate(site.joinedAt) else { return shortDate(site.joinedAt) }
        let days = max(0, Calendar.current.dateComponents([.day], from: joined, to: Date()).day ?? 0)
        return "\(days) 天"
    }

    private var ratioText: String { privateValue(String(format: "%.2f", site.ratio)) }
    private var ratioColor: Color { !privacy && site.downloaded > 0 && site.ratio < 1 ? HarvestTheme.coral : HarvestTheme.green }
    private var hrText: String {
        let value = site.hr.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "0" : value
    }

    private func shortDate(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "-" }
        if let date = parseDate(trimmed) {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return String(trimmed.prefix(10))
    }

    private func privateValue(_ value: String) -> String { privacy ? "••••" : value }

    private var accessibilitySummary: String {
        let state = site.enabled ? "可用" : "停用"
        let traffic = privacy
            ? "流量数据已隐藏"
            : "上传 \(formatBytes(site.uploaded))，下载 \(formatBytes(site.downloaded))，分享率 \(String(format: "%.2f", site.ratio))"
        let signStatus = site.signed ? "，今日已签到" : (site.signIn ? "，今日待签到" : "")
        let unread = site.unread > 0 ? "，未读 \(site.unread)" : ""
        return "\(site.name)，\(state)\(signStatus)，\(traffic)，\(site.seeding) 个做种\(unread)"
    }
}

private struct SiteStatusDescriptor: Identifiable {
    let id: String
    let label: String
    let icon: String
    let color: Color
}

private struct SiteAvailabilityBadge: View {
    let enabled: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(enabled ? HarvestTheme.green : HarvestTheme.coral)
                .frame(width: 7, height: 7)
            Text(enabled ? "可用" : "停用")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityLabel(enabled ? "站点可用" : "站点停用")
    }
}

private struct SiteInlineStatus: View {
    let status: SiteStatusDescriptor

    var body: some View {
        Label(status.label, systemImage: status.icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(status.color)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SiteTrafficMetric: View {
    let label: String
    let value: String
    let delta: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            SymbolBadge(icon: icon, color: color, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text(delta)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct SiteCardMetric: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.52)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .accessibilityLabel("\(label) \(value)")
    }
}

private struct SiteMetadataMetric: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct SiteDetailLine: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    let lineLimit: Int?

    init(icon: String, label: String, value: String, color: Color, lineLimit: Int? = 1) {
        self.icon = icon
        self.label = label
        self.value = value
        self.color = color
        self.lineLimit = lineLimit
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 30, alignment: .leading)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(lineLimit)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SiteListSummaryBar: View {
    let visibleCount: Int
    let totalCount: Int
    let activeCount: Int
    let pendingSignInCount: Int
    let unreadCount: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            summaryContent(showActive: true)
            summaryContent(showActive: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func summaryContent(showActive: Bool) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("\(visibleCount)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                Text("/ \(totalCount) 个站点")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .accessibilityLabel("显示 \(visibleCount)，共 \(totalCount) 个站点")
            Spacer(minLength: 4)
            if showActive {
                summaryMetric("可用", value: activeCount, icon: "checkmark.circle.fill", color: HarvestTheme.green)
            }
            summaryMetric("待签", value: pendingSignInCount, icon: "checkmark.seal", color: HarvestTheme.amber)
            summaryMetric("未读", value: unreadCount, icon: "bell.badge.fill", color: HarvestTheme.coral)
        }
    }

    private func summaryMetric(_ label: String, value: Int, icon: String, color: Color) -> some View {
        Label("\(label) \(value)", systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .accessibilityLabel("\(label) \(value)")
    }
}

private struct SiteHistoryPoint: Identifiable {
    let id: String
    let date: Date
    let uploaded: Double
    let downloaded: Double
}

private enum SiteFeatureFlag: String, CaseIterable, Identifiable {
    case available
    case signIn
    case getInfo
    case repeatTorrents
    case brushFree
    case brushRSS
    case packageFile
    case hrDiscern
    case searchTorrents
    case showInDashboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .available: return "可用"
        case .signIn: return "签到"
        case .getInfo: return "信息"
        case .repeatTorrents: return "辅种"
        case .brushFree: return "刷流"
        case .brushRSS: return "RSS"
        case .packageFile: return "拆包"
        case .hrDiscern: return "HR"
        case .searchTorrents: return "搜索"
        case .showInDashboard: return "首页"
        }
    }

    var icon: String {
        switch self {
        case .available: return "checkmark.circle"
        case .signIn: return "calendar.badge.checkmark"
        case .getInfo: return "info.circle"
        case .repeatTorrents: return "square.on.square"
        case .brushFree: return "arrow.down.circle"
        case .brushRSS: return "dot.radiowaves.left.and.right"
        case .packageFile: return "shippingbox"
        case .hrDiscern: return "exclamationmark.triangle"
        case .searchTorrents: return "magnifyingglass"
        case .showInDashboard: return "rectangle.3.group"
        }
    }

    var apiKey: String {
        switch self {
        case .available: return "available"
        case .signIn: return "sign_in"
        case .getInfo: return "get_info"
        case .repeatTorrents: return "repeat_torrents"
        case .brushFree: return "brush_free"
        case .brushRSS: return "brush_rss"
        case .packageFile: return "package_file"
        case .hrDiscern: return "hr_discern"
        case .searchTorrents: return "search_torrents"
        case .showInDashboard: return "show_in_dash"
        }
    }

    func value(in site: SiteItem) -> Bool {
        switch self {
        case .available: return site.enabled
        case .signIn: return site.signIn
        case .getInfo: return site.getInfo
        case .repeatTorrents: return site.repeatTorrents
        case .brushFree: return site.brushFree
        case .brushRSS: return site.brushRSS
        case .packageFile: return site.packageFile
        case .hrDiscern: return site.hrDiscern
        case .searchTorrents: return site.searchTorrents
        case .showInDashboard: return site.showInDashboard
        }
    }
}

private struct SiteStatusHistoryPoint: Identifiable {
    let id: String
    let date: Date
    let dateKey: String
    let uploaded: Double
    let downloaded: Double
    let magic: Double
    let score: Double
    let seeding: Double
    let leeching: Double
    let published: Double
    let invitations: Double
    let ratio: Double
    let seedVolume: Double
    let seedDays: Double
    let bonusHour: Double
    let uploadDelta: Double
    let downloadDelta: Double
    let magicDelta: Double
    let scoreDelta: Double
    let seedVolumeDelta: Double
    let seedDaysDelta: Double

    init(row: [String: Any], dateKey: String, date: Date, previous: SiteStatusHistoryPoint?) {
        let uploadedValue = row.double("uploaded", "upload", "uploaded_size") ?? 0
        let downloadedValue = row.double("downloaded", "download", "downloaded_size") ?? 0
        let magicValue = row.double("my_bonus", "bonus", "magic") ?? 0
        let scoreValue = row.double("my_score", "score", "credits") ?? 0
        let seedVolumeValue = row.double("seed_volume", "seedVolume") ?? 0
        let seedDaysValue = row.double("seed_days", "seedDays") ?? 0
        id = dateKey
        self.date = date
        self.dateKey = dateKey
        uploaded = uploadedValue
        downloaded = downloadedValue
        magic = magicValue
        score = scoreValue
        seeding = row.double("seed", "seeding", "seeding_count") ?? 0
        leeching = row.double("leech", "leeching", "downloading") ?? 0
        published = row.double("publish", "published") ?? 0
        invitations = row.double("invitation", "invitations") ?? 0
        ratio = row.double("ratio", "share_ratio") ?? 0
        seedVolume = seedVolumeValue
        seedDays = seedDaysValue
        bonusHour = row.double("bonus_hour", "bonusHour") ?? 0
        uploadDelta = previous.map { uploadedValue - $0.uploaded } ?? 0
        downloadDelta = previous.map { downloadedValue - $0.downloaded } ?? 0
        magicDelta = previous.map { magicValue - $0.magic } ?? 0
        scoreDelta = previous.map { scoreValue - $0.score } ?? 0
        seedVolumeDelta = previous.map { seedVolumeValue - $0.seedVolume } ?? 0
        seedDaysDelta = previous.map { seedDaysValue - $0.seedDays } ?? 0
    }
}

private struct SiteMonthlyHistoryPoint: Identifiable {
    let id: String
    let date: Date
    let monthKey: String
    let firstDateKey: String
    let lastDateKey: String
    let days: Int
    let uploaded: Double
    let downloaded: Double
    let magic: Double
    let score: Double
    let seeding: Double
    let leeching: Double
    let published: Double
    let invitations: Double
    let ratio: Double
    let seedVolume: Double
    let seedDays: Double
    let bonusHour: Double
    let uploadDelta: Double
    let downloadDelta: Double
    let magicDelta: Double
    let scoreDelta: Double
    let seedingDelta: Double
    let leechingDelta: Double
    let publishedDelta: Double
    let invitationDelta: Double
    let ratioDelta: Double
    let seedVolumeDelta: Double
    let seedDaysDelta: Double
    let bonusHourDelta: Double

    init(monthKey: String, date: Date, points: [SiteStatusHistoryPoint]) {
        let first = points.first!
        let last = points.last!
        id = monthKey
        self.date = date
        self.monthKey = monthKey
        firstDateKey = first.dateKey
        lastDateKey = last.dateKey
        days = points.count
        uploaded = last.uploaded
        downloaded = last.downloaded
        magic = last.magic
        score = last.score
        seeding = last.seeding
        leeching = last.leeching
        published = last.published
        invitations = last.invitations
        ratio = last.ratio
        seedVolume = last.seedVolume
        seedDays = last.seedDays
        bonusHour = last.bonusHour
        uploadDelta = last.uploaded - first.uploaded
        downloadDelta = last.downloaded - first.downloaded
        magicDelta = last.magic - first.magic
        scoreDelta = last.score - first.score
        seedingDelta = last.seeding - first.seeding
        leechingDelta = last.leeching - first.leeching
        publishedDelta = last.published - first.published
        invitationDelta = last.invitations - first.invitations
        ratioDelta = last.ratio - first.ratio
        seedVolumeDelta = last.seedVolume - first.seedVolume
        seedDaysDelta = last.seedDays - first.seedDays
        bonusHourDelta = last.bonusHour - first.bonusHour
    }
}

private func buildSiteStatusHistory(_ site: SiteItem) -> [SiteStatusHistoryPoint] {
    let rows = site.statusHistory.compactMap { row -> (String, Date, [String: Any])? in
        guard let key = row.string("date", "created_at", "updated_at"),
              let date = parseDate(key) else { return nil }
        return (key, date, row)
    }.sorted { left, right in
        left.1 == right.1 ? left.0 < right.0 : left.1 < right.1
    }

    var result: [SiteStatusHistoryPoint] = []
    for (key, date, row) in rows {
        result.append(SiteStatusHistoryPoint(row: row, dateKey: key, date: date, previous: result.last))
    }
    return result
}

private func buildSiteMonthlyHistory(_ points: [SiteStatusHistoryPoint]) -> [SiteMonthlyHistoryPoint] {
    let calendar = Calendar(identifier: .gregorian)
    let grouped = Dictionary(grouping: points) { point -> String in
        let components = calendar.dateComponents([.year, .month], from: point.date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }
    return grouped.keys.sorted().compactMap { key in
        guard let values = grouped[key]?.sorted(by: { $0.date < $1.date }),
              !values.isEmpty,
              let monthDate = parseDate("\(key)-01") else { return nil }
        return SiteMonthlyHistoryPoint(monthKey: key, date: monthDate, points: values)
    }
}

private struct SiteChartPoint: Identifiable {
    let id: String
    let date: Date
    let values: [String: Double]
}

private struct SiteChartSeries: Identifiable {
    let id: String
    let label: String
    let color: Color
}

private enum SiteChartStyle: Equatable {
    case line
    case bar
}

private func siteSignedBytes(_ value: Double, includePositiveSign: Bool = true) -> String {
    let prefix = value < 0 ? "-" : (includePositiveSign && value > 0 ? "+" : "")
    return prefix + formatBytes(abs(value))
}

private func siteSignedNumber(_ value: Double, includePositiveSign: Bool = true) -> String {
    let prefix = value < 0 ? "-" : (includePositiveSign && value > 0 ? "+" : "")
    return prefix + formatCompactNumber(abs(value))
}

private struct SiteMetricChart: View {
    let title: String
    let subtitle: String
    let points: [SiteChartPoint]
    let series: [SiteChartSeries]
    let style: SiteChartStyle
    let formatsBytes: Bool
    let monthly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ForEach(series) { item in
                    Label {
                        Text(item.label).font(.caption2)
                    } icon: {
                        Circle().fill(item.color).frame(width: 7, height: 7)
                    }
                }
            }
            Chart {
                ForEach(series) { item in
                    ForEach(points) { point in
                        if style == .bar {
                            BarMark(
                                x: .value("日期", point.date),
                                y: .value(item.label, point.values[item.id] ?? 0)
                            )
                            .foregroundStyle(item.color)
                            .position(by: .value("指标", item.label))
                        } else {
                            LineMark(
                                x: .value("日期", point.date),
                                y: .value(item.label, point.values[item.id] ?? 0),
                                series: .value("指标", item.label)
                            )
                            .foregroundStyle(item.color)
                            .interpolationMethod(.catmullRom)
                            PointMark(
                                x: .value("日期", point.date),
                                y: .value(item.label, point.values[item.id] ?? 0)
                            )
                            .foregroundStyle(item.color)
                            .symbolSize(16)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(monthly
                                ? date.formatted(.dateTime.year().month(.twoDigits))
                                : date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(formatsBytes
                                ? siteSignedBytes(number, includePositiveSign: false)
                                : siteSignedNumber(number, includePositiveSign: false))
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 220)
        }
        .padding(.vertical, 4)
    }
}

private enum SiteHistoryPeriod: String, CaseIterable, Identifiable {
    case daily = "按日"
    case monthly = "按月"
    var id: String { rawValue }
}

private enum SiteHistoryMetric: String, CaseIterable, Identifiable {
    case traffic = "流量"
    case points = "积分"
    case activity = "活动"
    case efficiency = "效率"
    var id: String { rawValue }
}

private struct SiteStatusHistoryView: View {
    let site: SiteItem
    private let dailyPoints: [SiteStatusHistoryPoint]
    private let monthlyPoints: [SiteMonthlyHistoryPoint]
    @State private var period: SiteHistoryPeriod = .daily
    @State private var metric: SiteHistoryMetric = .traffic
    @State private var dayCount: Int
    @State private var monthCount: Int

    init(site: SiteItem) {
        self.site = site
        let daily = buildSiteStatusHistory(site)
        dailyPoints = daily
        monthlyPoints = buildSiteMonthlyHistory(daily)
        _dayCount = State(initialValue: min(15, max(daily.count, 1)))
        _monthCount = State(initialValue: min(6, max(monthlyPoints.count, 1)))
    }

    private var visibleDaily: [SiteStatusHistoryPoint] {
        Array(dailyPoints.suffix(min(dayCount, dailyPoints.count)))
    }

    private var visibleMonthly: [SiteMonthlyHistoryPoint] {
        Array(monthlyPoints.suffix(min(monthCount, monthlyPoints.count)))
    }

    private var dayOptions: [Int] {
        Array(Set([7, 15, 30, dailyPoints.count].filter { $0 > 0 && $0 <= dailyPoints.count })).sorted()
    }

    private var monthOptions: [Int] {
        Array(Set([3, 6, 12, monthlyPoints.count].filter { $0 > 0 && $0 <= monthlyPoints.count })).sorted()
    }

    var body: some View {
        List {
            Section {
                Picker("周期", selection: $period) {
                    ForEach(SiteHistoryPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("指标", selection: $metric) {
                    ForEach(SiteHistoryMetric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if period == .daily {
                    Picker("显示范围", selection: $dayCount) {
                        ForEach(dayOptions, id: \.self) { count in
                            Text(count == dailyPoints.count ? "全部 \(count) 天" : "最近 \(count) 天").tag(count)
                        }
                    }
                } else {
                    Picker("显示范围", selection: $monthCount) {
                        ForEach(monthOptions, id: \.self) { count in
                            Text(count == monthlyPoints.count ? "全部 \(count) 个月" : "最近 \(count) 个月").tag(count)
                        }
                    }
                }
            }

            if period == .daily {
                dailyCharts
                Section("每日明细") {
                    ForEach(Array(visibleDaily.reversed())) { point in
                        SiteDailyHistoryRow(point: point)
                    }
                }
            } else {
                monthlyCharts
                Section("月度明细") {
                    ForEach(Array(visibleMonthly.reversed())) { point in
                        SiteMonthlyHistoryRow(point: point)
                    }
                }
            }
        }
        .navigationTitle("状态图表")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var dailyCharts: some View {
        switch metric {
        case .traffic:
            Section {
                SiteMetricChart(
                    title: "每日增量",
                    subtitle: "相邻两条状态记录的上传与下载变化",
                    points: visibleDaily.map { point in
                        SiteChartPoint(id: point.id, date: point.date, values: ["upload": point.uploadDelta, "download": point.downloadDelta])
                    },
                    series: trafficSeries,
                    style: .bar,
                    formatsBytes: true,
                    monthly: false
                )
            }
            Section {
                SiteMetricChart(
                    title: "每日总量",
                    subtitle: "上传与下载累计值",
                    points: visibleDaily.map { point in
                        SiteChartPoint(id: point.id, date: point.date, values: ["upload": point.uploaded, "download": point.downloaded])
                    },
                    series: trafficSeries,
                    style: .line,
                    formatsBytes: true,
                    monthly: false
                )
            }
        case .points:
            Section {
                SiteMetricChart(
                    title: "每日增量",
                    subtitle: "魔力值与积分变化",
                    points: visibleDaily.map { point in
                        SiteChartPoint(id: point.id, date: point.date, values: ["magic": point.magicDelta, "score": point.scoreDelta])
                    },
                    series: pointSeries,
                    style: .bar,
                    formatsBytes: false,
                    monthly: false
                )
            }
            Section {
                SiteMetricChart(
                    title: "每日总量",
                    subtitle: "魔力值与积分累计值",
                    points: visibleDaily.map { point in
                        SiteChartPoint(id: point.id, date: point.date, values: ["magic": point.magic, "score": point.score])
                    },
                    series: pointSeries,
                    style: .line,
                    formatsBytes: false,
                    monthly: false
                )
            }
        case .activity:
            Section {
                SiteMetricChart(
                    title: "活跃数据",
                    subtitle: "做种、下载、发布与邀请",
                    points: visibleDaily.map { point in
                        SiteChartPoint(id: point.id, date: point.date, values: [
                            "seed": point.seeding, "leech": point.leeching,
                            "publish": point.published, "invite": point.invitations
                        ])
                    },
                    series: activitySeries,
                    style: .line,
                    formatsBytes: false,
                    monthly: false
                )
            }
        case .efficiency:
            Section {
                SiteMetricChart(
                    title: "做种效率",
                    subtitle: "分享率、做种天数与时魔",
                    points: visibleDaily.map { point in
                        SiteChartPoint(id: point.id, date: point.date, values: [
                            "ratio": point.ratio, "days": point.seedDays, "hour": point.bonusHour
                        ])
                    },
                    series: efficiencySeries,
                    style: .line,
                    formatsBytes: false,
                    monthly: false
                )
            }
            Section {
                SiteMetricChart(
                    title: "做种量",
                    subtitle: "做种体积历史",
                    points: visibleDaily.map { point in
                        SiteChartPoint(id: point.id, date: point.date, values: ["volume": point.seedVolume])
                    },
                    series: volumeSeries,
                    style: .line,
                    formatsBytes: true,
                    monthly: false
                )
            }
        }
    }

    @ViewBuilder private var monthlyCharts: some View {
        switch metric {
        case .traffic:
            Section {
                SiteMetricChart(
                    title: "月度增量",
                    subtitle: "当月最后一条减去第一条状态记录",
                    points: visibleMonthly.map { point in
                        SiteChartPoint(id: point.id, date: point.date, values: ["upload": point.uploadDelta, "download": point.downloadDelta])
                    },
                    series: trafficSeries,
                    style: .bar,
                    formatsBytes: true,
                    monthly: true
                )
            }
            Section {
                SiteMetricChart(
                    title: "月度趋势",
                    subtitle: "每月最后一条上传与下载累计值",
                    points: visibleMonthly.map { point in
                        SiteChartPoint(id: point.id, date: point.date, values: ["upload": point.uploaded, "download": point.downloaded])
                    },
                    series: trafficSeries,
                    style: .line,
                    formatsBytes: true,
                    monthly: true
                )
            }
        case .points:
            Section {
                SiteMetricChart(
                    title: "月度增量",
                    subtitle: "当月魔力值与积分变化",
                    points: visibleMonthly.map { point in
                        SiteChartPoint(id: point.id, date: point.date, values: ["magic": point.magicDelta, "score": point.scoreDelta])
                    },
                    series: pointSeries,
                    style: .bar,
                    formatsBytes: false,
                    monthly: true
                )
            }
            Section {
                SiteMetricChart(
                    title: "月度趋势",
                    subtitle: "每月最后一条魔力值与积分",
                    points: visibleMonthly.map { point in
                        SiteChartPoint(id: point.id, date: point.date, values: ["magic": point.magic, "score": point.score])
                    },
                    series: pointSeries,
                    style: .line,
                    formatsBytes: false,
                    monthly: true
                )
            }
        case .activity:
            Section {
                SiteMetricChart(
                    title: "月末活动",
                    subtitle: "每月最后一条做种、下载、发布与邀请数据",
                    points: visibleMonthly.map { point in
                        SiteChartPoint(id: point.id, date: point.date, values: [
                            "seed": point.seeding, "leech": point.leeching,
                            "publish": point.published, "invite": point.invitations
                        ])
                    },
                    series: activitySeries,
                    style: .line,
                    formatsBytes: false,
                    monthly: true
                )
            }
        case .efficiency:
            Section {
                SiteMetricChart(
                    title: "月末效率",
                    subtitle: "每月最后一条分享率、做种天数与时魔",
                    points: visibleMonthly.map { point in
                        SiteChartPoint(id: point.id, date: point.date, values: [
                            "ratio": point.ratio, "days": point.seedDays, "hour": point.bonusHour
                        ])
                    },
                    series: efficiencySeries,
                    style: .line,
                    formatsBytes: false,
                    monthly: true
                )
            }
            Section {
                SiteMetricChart(
                    title: "月末做种量",
                    subtitle: "每月最后一条做种体积",
                    points: visibleMonthly.map { point in
                        SiteChartPoint(id: point.id, date: point.date, values: ["volume": point.seedVolume])
                    },
                    series: volumeSeries,
                    style: .line,
                    formatsBytes: true,
                    monthly: true
                )
            }
        }
    }

    private var trafficSeries: [SiteChartSeries] {
        [
            SiteChartSeries(id: "upload", label: "上传", color: HarvestTheme.green),
            SiteChartSeries(id: "download", label: "下载", color: HarvestTheme.blue)
        ]
    }

    private var pointSeries: [SiteChartSeries] {
        [
            SiteChartSeries(id: "magic", label: "魔力", color: HarvestTheme.amber),
            SiteChartSeries(id: "score", label: "积分", color: HarvestTheme.coral)
        ]
    }

    private var activitySeries: [SiteChartSeries] {
        [
            SiteChartSeries(id: "seed", label: "做种", color: HarvestTheme.green),
            SiteChartSeries(id: "leech", label: "下载", color: HarvestTheme.coral),
            SiteChartSeries(id: "publish", label: "发布", color: HarvestTheme.blue),
            SiteChartSeries(id: "invite", label: "邀请", color: .purple)
        ]
    }

    private var efficiencySeries: [SiteChartSeries] {
        [
            SiteChartSeries(id: "ratio", label: "分享率", color: HarvestTheme.blue),
            SiteChartSeries(id: "days", label: "做种天数", color: HarvestTheme.coral),
            SiteChartSeries(id: "hour", label: "时魔", color: HarvestTheme.amber)
        ]
    }

    private var volumeSeries: [SiteChartSeries] {
        [SiteChartSeries(id: "volume", label: "做种量", color: HarvestTheme.green)]
    }
}

private struct SiteDailyHistoryRow: View {
    let point: SiteStatusHistoryPoint

    var body: some View {
        DisclosureGroup {
            LabeledContent("上传增量", value: siteSignedBytes(point.uploadDelta))
            LabeledContent("下载增量", value: siteSignedBytes(point.downloadDelta))
            LabeledContent("魔力增量", value: siteSignedNumber(point.magicDelta))
            LabeledContent("积分增量", value: siteSignedNumber(point.scoreDelta))
            LabeledContent("做种量增量", value: siteSignedBytes(point.seedVolumeDelta))
            LabeledContent("做种天数增量", value: siteSignedNumber(point.seedDaysDelta))
            LabeledContent("上传总量", value: formatBytes(point.uploaded))
            LabeledContent("下载总量", value: formatBytes(point.downloaded))
            LabeledContent("魔力值", value: formatCompactNumber(point.magic))
            LabeledContent("积分", value: formatCompactNumber(point.score))
            LabeledContent("做种 / 下载", value: "\(Int(point.seeding)) / \(Int(point.leeching))")
            LabeledContent("发布 / 邀请", value: "\(Int(point.published)) / \(Int(point.invitations))")
            LabeledContent("分享率", value: String(format: "%.2f", point.ratio))
            LabeledContent("做种量", value: formatBytes(point.seedVolume))
            LabeledContent("做种天数", value: formatCompactNumber(point.seedDays))
            LabeledContent("时魔", value: String(format: "%.1f/h", point.bonusHour))
        } label: {
            Text(point.dateKey).font(.subheadline.weight(.semibold))
        }
    }
}

private struct SiteMonthlyHistoryRow: View {
    let point: SiteMonthlyHistoryPoint

    var body: some View {
        DisclosureGroup {
            LabeledContent("统计区间", value: "\(point.firstDateKey) - \(point.lastDateKey)")
            LabeledContent("记录天数", value: "\(point.days)")
            LabeledContent("上传增量", value: siteSignedBytes(point.uploadDelta))
            LabeledContent("下载增量", value: siteSignedBytes(point.downloadDelta))
            LabeledContent("魔力增量", value: siteSignedNumber(point.magicDelta))
            LabeledContent("积分增量", value: siteSignedNumber(point.scoreDelta))
            LabeledContent("做种 / 下载变化", value: "\(siteSignedNumber(point.seedingDelta)) / \(siteSignedNumber(point.leechingDelta))")
            LabeledContent("发布 / 邀请变化", value: "\(siteSignedNumber(point.publishedDelta)) / \(siteSignedNumber(point.invitationDelta))")
            LabeledContent("分享率变化", value: siteSignedNumber(point.ratioDelta))
            LabeledContent("做种量变化", value: siteSignedBytes(point.seedVolumeDelta))
            LabeledContent("做种天数变化", value: siteSignedNumber(point.seedDaysDelta))
            LabeledContent("时魔变化", value: siteSignedNumber(point.bonusHourDelta))
            LabeledContent("月末上传", value: formatBytes(point.uploaded))
            LabeledContent("月末下载", value: formatBytes(point.downloaded))
            LabeledContent("月末魔力", value: formatCompactNumber(point.magic))
            LabeledContent("月末积分", value: formatCompactNumber(point.score))
            LabeledContent("月末做种 / 下载", value: "\(Int(point.seeding)) / \(Int(point.leeching))")
            LabeledContent("月末发布 / 邀请", value: "\(Int(point.published)) / \(Int(point.invitations))")
            LabeledContent("月末分享率", value: String(format: "%.2f", point.ratio))
            LabeledContent("月末做种量", value: formatBytes(point.seedVolume))
            LabeledContent("月末做种天数", value: formatCompactNumber(point.seedDays))
            LabeledContent("月末时魔", value: String(format: "%.1f/h", point.bonusHour))
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(point.monthKey).font(.subheadline.weight(.semibold))
                Text("\(point.days) 条记录").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SiteLevelRequirement: Identifiable {
    let key: String
    let levelID: Int
    let level: String
    let name: String
    let days: Int
    let uploaded: Double
    let downloaded: Double
    let bonus: Double
    let score: Double
    let ratio: Double
    let torrents: Int
    let rights: String
    let keepAccount: Bool
    let graduation: Bool

    var id: String { key }
    var displayName: String { name.isEmpty ? (level.isEmpty ? key : level) : name }

    init(key: String, value: [String: Any]) {
        self.key = key
        levelID = value.int("level_id", "levelId") ?? 0
        level = value.string("level") ?? key
        name = value.string("name") ?? ""
        days = value.int("days") ?? 0
        uploaded = parseLevelSize(value["uploaded"])
        downloaded = parseLevelSize(value["downloaded"])
        bonus = value.double("bonus") ?? 0
        score = value.double("score") ?? 0
        ratio = value.double("ratio") ?? 0
        torrents = value.int("torrents") ?? 0
        rights = value.string("rights") ?? ""
        keepAccount = value.bool("keep_account", "keepAccount") ?? false
        graduation = value.bool("graduation") ?? false
    }
}

private func parseSiteLevels(_ value: Any?) -> [SiteLevelRequirement] {
    guard let dictionary = value as? [String: Any] else { return [] }
    return dictionary.compactMap { key, raw in
        guard let row = raw as? [String: Any] else { return nil }
        return SiteLevelRequirement(key: key, value: row)
    }
    .filter { $0.levelID != 0 }
    .sorted { left, right in
        if left.levelID == right.levelID { return left.displayName < right.displayName }
        return left.levelID > right.levelID
    }
}

private func parseLevelSize(_ value: Any?) -> Double {
    if let number = value as? NSNumber { return number.doubleValue }
    guard var text = value as? String else { return 0 }
    text = text.uppercased().replacingOccurrences(of: " ", with: "")
    let units: [(String, Double)] = [
        ("PIB", pow(1024, 5)), ("PB", pow(1000, 5)),
        ("TIB", pow(1024, 4)), ("TB", pow(1000, 4)),
        ("GIB", pow(1024, 3)), ("GB", pow(1000, 3)),
        ("MIB", pow(1024, 2)), ("MB", pow(1000, 2)),
        ("KIB", 1024), ("KB", 1000), ("B", 1)
    ]
    for (suffix, multiplier) in units where text.hasSuffix(suffix) {
        text.removeLast(suffix.count)
        return (Double(text) ?? 0) * multiplier
    }
    return Double(text) ?? 0
}

private struct SiteLevelProgressView: View {
    let site: SiteItem
    let levels: [SiteLevelRequirement]

    private var currentIndex: Int? {
        let current = site.level.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return nil }
        return levels.firstIndex { $0.key == current || $0.level == current || $0.name == current }
    }
    private var nextLevel: SiteLevelRequirement? {
        guard let index = currentIndex, index > 0 else { return nil }
        return levels[index - 1]
    }
    private var reachedLevels: [SiteLevelRequirement] {
        guard let index = currentIndex else { return [] }
        return Array(levels[index...])
    }

    var body: some View {
        List {
            Section("当前等级") {
                LabeledContent("等级", value: site.level.isEmpty ? "未知" : site.level)
                if reachedLevels.contains(where: { $0.graduation }) {
                    Label("已达到毕业等级", systemImage: "graduationcap.fill").foregroundStyle(HarvestTheme.amber)
                } else if reachedLevels.contains(where: { $0.keepAccount }) {
                    Label("已达到保号等级", systemImage: "checkmark.shield.fill").foregroundStyle(HarvestTheme.green)
                }
            }
            if let nextLevel {
                Section("下一等级 · \(nextLevel.displayName)") {
                    levelProgressRows(nextLevel)
                    if !nextLevel.rights.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        LabeledContent("新增权利", value: nextLevel.rights)
                    }
                }
            } else if currentIndex != nil {
                Section { Label("已达到最高配置等级", systemImage: "checkmark.seal.fill").foregroundStyle(HarvestTheme.green) }
            }
            Section("等级列表") {
                ForEach(levels) { level in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(level.displayName).font(.subheadline.weight(.semibold))
                            Spacer()
                            if currentIndex.map({ levels[$0].id == level.id }) == true {
                                StatusPill(label: "当前", color: HarvestTheme.green)
                            }
                        }
                        Text(levelSummary(level)).font(.caption).foregroundStyle(.secondary)
                        if !level.rights.isEmpty { Text(level.rights).font(.caption2).foregroundStyle(.tertiary) }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .navigationTitle("等级进度")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func levelProgressRows(_ level: SiteLevelRequirement) -> some View {
        let requiredUpload = level.uploaded > 0
            ? level.uploaded
            : (level.downloaded > 0 && level.ratio > 0 ? max(site.downloaded, level.downloaded) * level.ratio : 0)
        if requiredUpload > 0 { progressRow("上传量", current: site.uploaded, required: requiredUpload, formatter: formatBytes) }
        if level.downloaded > 0 { progressRow("下载量", current: site.downloaded, required: level.downloaded, formatter: formatBytes) }
        if level.score > 0 { progressRow("做种积分", current: site.score, required: level.score, formatter: formatCompactNumber) }
        if level.bonus > 0 { progressRow("魔力值", current: site.magic, required: level.bonus, formatter: formatCompactNumber) }
        if level.torrents > 0 { progressRow("发种数", current: Double(site.published), required: Double(level.torrents)) { String(format: "%.0f", $0) } }
        if level.days > 0 {
            let joined = parseDate(site.joinedAt)
            let days = joined.map { Double(max(0, Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0)) } ?? 0
            progressRow("注册天数", current: days, required: Double(level.days)) { String(format: "%.0f 天", $0) }
        }
        if level.ratio > 0 { progressRow("分享率", current: site.ratio, required: level.ratio) { String(format: "%.2f", $0) } }
    }

    private func progressRow(_ label: String, current: Double, required: Double, formatter: (Double) -> String) -> some View {
        let progress = required > 0 ? min(max(current / required, 0), 1) : 1
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(formatter(current)) / \(formatter(required))").font(.caption.monospacedDigit())
                Image(systemName: current >= required ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(current >= required ? HarvestTheme.green : HarvestTheme.amber)
            }
            ProgressView(value: progress).tint(current >= required ? HarvestTheme.green : HarvestTheme.amber)
        }
    }

    private func levelSummary(_ level: SiteLevelRequirement) -> String {
        var values: [String] = []
        if level.days > 0 { values.append("\(level.days) 天") }
        if level.uploaded > 0 { values.append("上传 \(formatBytes(level.uploaded))") }
        if level.downloaded > 0 { values.append("下载 \(formatBytes(level.downloaded))") }
        if level.ratio > 0 { values.append("分享率 \(String(format: "%.2f", level.ratio))") }
        if level.torrents > 0 { values.append("发种 \(level.torrents)") }
        return values.isEmpty ? "无升级条件" : values.joined(separator: " · ")
    }
}

private struct SitePageShortcut: Identifiable {
    let key: String
    let label: String
    let icon: String
    let path: String
    var id: String { key + path }
}

struct SiteDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let site: SiteItem
    @ObservedObject var model: SitesViewModel
    @State private var latestSite: SiteItem?
    @State private var siteConfig: [String: Any] = [:]
    @State private var isLoading = false
    @State private var confirmRepeat = false
    @State private var savingFlag: SiteFeatureFlag?

    private var current: SiteItem { latestSite ?? site }
    private var levelRequirements: [SiteLevelRequirement] { parseSiteLevels(siteConfig["level"]) }
    private var historyPoints: [SiteHistoryPoint] {
        current.statusHistory.compactMap { row in
            guard let key = row.string("date", "created_at", "updated_at"), let date = parseDate(key) else { return nil }
            return SiteHistoryPoint(
                id: key,
                date: date,
                uploaded: row.double("uploaded", "upload") ?? 0,
                downloaded: row.double("downloaded", "download") ?? 0
            )
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        SiteDetailIcon(
                            site: current,
                            iconCandidates: model.logoCandidates(for: current, appState: appState)
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(current.name).font(.headline)
                            Text(current.siteType.isEmpty ? current.siteKey : current.siteType)
                                .font(.caption).foregroundStyle(.secondary)
                            StatusPill(label: current.enabled ? "站点可用" : "站点停用", color: current.enabled ? HarvestTheme.green : .secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("功能开关") {
                    ForEach(SiteFeatureFlag.allCases) { flag in
                        Toggle(isOn: Binding(
                            get: { flag.value(in: current) },
                            set: { value in Task { await updateFlag(flag, value: value) } }
                        )) {
                            HStack(spacing: 10) {
                                Label(flag.title, systemImage: flag.icon)
                                if savingFlag == flag {
                                    Spacer()
                                    ProgressView().controlSize(.small)
                                }
                            }
                        }
                        .disabled(savingFlag != nil)
                    }
                }
                Section("账号") {
                    detailValue("用户名", value: current.username)
                    detailValue("邮箱", value: current.email, privateValue: true)
                    detailValue("用户 ID", value: current.userID, privateValue: true)
                    if !current.level.isEmpty {
                        if levelRequirements.isEmpty {
                            detailValue("等级", value: current.level)
                        } else {
                            NavigationLink {
                                SiteLevelProgressView(site: current, levels: levelRequirements)
                            } label: {
                                LabeledContent("等级", value: current.level)
                            }
                        }
                    }
                    detailValue("注册时间", value: current.joinedAt)
                    detailValue("最后活动", value: current.latestActive)
                }
                Section("数据") {
                    LabeledContent("上传量", value: privateText(formatBytes(current.uploaded)))
                    if current.uploadDelta != 0 { LabeledContent("今日上传增量", value: privateText(formatBytes(current.uploadDelta))) }
                    LabeledContent("下载量", value: privateText(formatBytes(current.downloaded)))
                    if current.downloadDelta != 0 { LabeledContent("今日下载增量", value: privateText(formatBytes(current.downloadDelta))) }
                    LabeledContent("分享率", value: privateText(String(format: "%.2f", current.ratio)))
                    LabeledContent("做种体积", value: privateText(formatBytes(current.seedVolume)))
                    LabeledContent("做种天数", value: "\(current.seedDays)")
                    LabeledContent("魔力值", value: privateText(formatCompactNumber(current.magic)))
                    LabeledContent("时魔", value: privateText(formatCompactNumber(current.bonusHour)))
                    LabeledContent("积分", value: privateText(formatCompactNumber(current.score)))
                }
                Section("活动") {
                    LabeledContent("做种", value: "\(current.seeding)")
                    LabeledContent("下载中", value: "\(current.leeching)")
                    LabeledContent("已发布", value: "\(current.published)")
                    LabeledContent("邀请", value: "\(current.invitations)")
                    LabeledContent("HR", value: current.hr)
                    LabeledContent("未读短消息", value: "\(current.mail)")
                    LabeledContent("未读公告", value: "\(current.notice)")
                    if current.mail == 0, current.notice == 0, current.unread > 0 {
                        LabeledContent("其他未读", value: "\(current.unread)")
                    }
                    LabeledContent("今日签到", value: current.signed ? "已完成" : "未完成")
                    LabeledContent("最后同步", value: current.updatedAt.isEmpty ? "未知" : current.updatedAt)
                }

                if !historyPoints.isEmpty {
                    Section("流量趋势") {
                        Chart(historyPoints) { point in
                            LineMark(x: .value("日期", point.date), y: .value("上传", point.uploaded))
                                .foregroundStyle(HarvestTheme.green)
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("日期", point.date), y: .value("下载", point.downloaded))
                                .foregroundStyle(HarvestTheme.blue)
                                .interpolationMethod(.catmullRom)
                        }
                        .chartYAxis { AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(.quaternary)
                            AxisValueLabel { if let bytes = value.as(Double.self) { Text(formatBytes(bytes)).font(.caption2) } }
                        } }
                        .frame(height: 210)
                        NavigationLink {
                            SiteStatusHistoryView(site: current)
                        } label: {
                            Label("查看完整状态图表", systemImage: "chart.xyaxis.line")
                        }
                    }
                }

                if !current.signHistory.isEmpty {
                    Section("签到历史") {
                        ForEach(Array(current.signHistory.enumerated()), id: \.offset) { _, row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.string("date") ?? "未知日期").font(.subheadline.weight(.semibold))
                                Text(signHistoryText(row)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                if let time = row.string("updated_at"), !time.isEmpty {
                                    Text(time).font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                if !pageShortcuts.isEmpty {
                    Section("站点页面") {
                        ForEach(pageShortcuts) { shortcut in
                            NavigationLink {
                                SiteBrowserScreen(
                                    site: current,
                                    urlString: resolvedPageURL(shortcut.path),
                                    title: shortcut.label,
                                    onSynced: {
                                        await model.load(appState, cached: false)
                                        await loadDetail()
                                    }
                                )
                            } label: {
                                Label(shortcut.label, systemImage: shortcut.icon)
                            }
                        }
                    }
                }

                Section {
                    if !current.url.isEmpty {
                        NavigationLink {
                            SiteBrowserScreen(
                                site: current,
                                urlString: current.url,
                                title: current.name,
                                onSynced: {
                                    await model.load(appState, cached: false)
                                    await loadDetail()
                                }
                            )
                        } label: {
                            Label("打开站点", systemImage: "safari")
                        }
                    }
                    Button { Task { await operate(APIPath.siteStatus) } } label: { Label("刷新站点数据", systemImage: "arrow.clockwise") }
                    Button { Task { await operate(APIPath.siteSign) } } label: { Label("执行签到", systemImage: "checkmark.seal") }
                    Button { confirmRepeat = true } label: { Label("执行辅种", systemImage: "square.stack.3d.up") }
                }
            }
            .overlay { if isLoading { ProgressView().controlSize(.large) } }
            .navigationTitle(current.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await loadDetail() }
            .confirmationDialog("确定让站点「\(current.name)」执行辅种？", isPresented: $confirmRepeat, titleVisibility: .visible) {
                Button("执行辅种") { Task { await operate(APIPath.siteRepeat) } }
                Button("取消", role: .cancel) { }
            }
        }
    }

    private var pageShortcuts: [SitePageShortcut] {
        var values: [SitePageShortcut] = []
        let definitions: [(String, String, String)] = [
            ("page_index", "首页", "house"),
            ("page_torrents", "种子列表", "list.bullet.rectangle"),
            ("page_sign_in", "签到页", "checkmark.seal"),
            ("page_control_panel", "控制面板", "slider.horizontal.3"),
            ("page_user", "个人中心", "person.crop.circle"),
            ("page_message", "消息", "envelope"),
            ("page_hr", "HR", "exclamationmark.triangle"),
            ("page_leeching", "下载中", "arrow.down.circle"),
            ("page_uploaded", "已发布", "arrow.up.circle"),
            ("page_seeding", "做种中", "leaf"),
            ("page_completed", "已完成", "checkmark.circle"),
            ("page_mybonus", "魔力值", "wand.and.stars")
        ]
        for (key, label, icon) in definitions {
            if let path = firstConfigString(siteConfig[key]), !path.isEmpty {
                values.append(SitePageShortcut(key: key, label: label, icon: icon, path: path))
            }
        }
        for (index, path) in configStrings(siteConfig["page_search"]).enumerated() where !path.isEmpty {
            values.append(SitePageShortcut(key: "search\(index)", label: index == 0 ? "搜索" : "搜索 \(index + 1)", icon: "magnifyingglass", path: path))
        }
        return values
    }

    @ViewBuilder private func detailValue(_ label: String, value: String, privateValue: Bool = false) -> some View {
        if !value.isEmpty { LabeledContent(label, value: privateValue ? privateText(value) : value) }
    }

    private func privateText(_ value: String) -> String { appState.privacyMode ? "••••" : value }

    private func signHistoryText(_ row: [String: Any]) -> String {
        let text = row.string("info", "message", "content") ?? prettyJSON(row)
        if let range = text.range(of: "签到返回信息：") { return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines) }
        return text
    }

    private func resolvedPageURL(_ path: String) -> String {
        var value = path.replacingOccurrences(of: "{}", with: current.userID)
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }
        let base = current.url.isEmpty ? configStrings(siteConfig["url"]).first ?? "" : current.url
        guard !base.isEmpty else { return value }
        if !value.hasPrefix("/") { value = "/" + value }
        guard let origin = URL(string: base), var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else { return base + value }
        components.path = value
        components.query = nil
        return components.url?.absoluteString ?? base + value
    }

    @MainActor private func loadDetail() async {
        isLoading = true
        defer { isLoading = false }
        async let detail = loadDetailPayload("\(APIPath.sites)/\(site.id)")
        async let config = loadDetailPayload("\(APIPath.websiteList)/\(urlPathSegment(site.siteKey))")
        let values = await (detail, config)
        if let row = values.0 { latestSite = SiteItem(row) }
        if let config = values.1 { siteConfig = config }
    }

    @MainActor private func loadDetailPayload(_ path: String) async -> [String: Any]? {
        do { return jsonPayloadDictionary(try await appState.api(path)) }
        catch {
            await AppLogStore.shared.append(.warning, "站点详情子请求失败 \(path)：\(error.localizedDescription)")
            return nil
        }
    }

    @MainActor private func updateFlag(_ flag: SiteFeatureFlag, value: Bool) async {
        guard savingFlag == nil, flag.value(in: current) != value else { return }
        let previous = current
        var body = current.raw
        body[flag.apiKey] = value
        let updated = SiteItem(body)
        latestSite = updated
        savingFlag = flag
        defer { savingFlag = nil }

        guard await appState.perform("\(APIPath.sites)/\(current.id)", method: .put, body: body) else {
            latestSite = previous
            return
        }

        await model.load(appState, cached: false)
        if let reloaded = model.sites.first(where: { $0.id == current.id }),
           flag.value(in: reloaded) == value {
            latestSite = reloaded
        } else {
            latestSite = updated
        }
    }

    @MainActor private func operate(_ path: String) async {
        await model.operate(appState, site: current, path: path)
        await loadDetail()
    }
}

private struct BrowserPushPayload: Identifiable {
    let id = UUID()
    let input: String
    let cookie: String
}

private struct BrowserExtractedTorrent: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let detailURL: String
    let downloadURL: String
    let category: String
    let posterURL: String
    let size: String
    let progress: String
    let promotion: String
    let promotionExpiry: String
    let published: String
    let seeders: String
    let leechers: String
    let completers: String
    let tags: [String]
    let hr: String

    init(_ json: [String: Any]) {
        title = json.string("title", "name") ?? "未命名种子"
        subtitle = json.string("subtitle", "description") ?? ""
        detailURL = json.string("detailUrl", "detail_url") ?? ""
        downloadURL = json.string("magnetUrl", "downloadUrl", "download_url", "url") ?? ""
        category = json.string("category") ?? ""
        posterURL = json.string("poster", "posterUrl", "poster_url") ?? ""
        size = json.string("size") ?? ""
        progress = json.string("progress") ?? ""
        promotion = json.string("sale", "promotion") ?? ""
        promotionExpiry = json.string("saleExpire", "promotion_expire") ?? ""
        published = json.string("release", "published") ?? ""
        seeders = json.string("seeders") ?? ""
        leechers = json.string("leechers") ?? ""
        completers = json.string("completers") ?? ""
        tags = json.strings("tags")
        hr = json.string("hr") ?? ""
    }

    var pushURL: String { downloadURL.isEmpty ? detailURL : downloadURL }
    var seederCount: Int { Int(seeders.filter(\.isNumber)) ?? 0 }
    var byteSize: Double {
        let text = size.uppercased().replacingOccurrences(of: ",", with: "")
        guard let match = text.range(of: #"[0-9]+(?:\.[0-9]+)?"#, options: .regularExpression),
              let value = Double(text[match]) else { return 0 }
        let powers = ["KB": 1.0, "KIB": 1.0, "MB": 2.0, "MIB": 2.0, "GB": 3.0, "GIB": 3.0, "TB": 4.0, "TIB": 4.0]
        let power = powers.first(where: { text.contains($0.key) })?.value ?? 0
        return value * pow(1024, power)
    }
}

private struct BrowserProfileMetric: Identifiable {
    let key: String
    let label: String
    let value: String
    var id: String { key }
    var displayValue: String {
        guard key == "passkey", !value.isEmpty else { return value }
        if value.count <= 8 { return String(repeating: "•", count: value.count) }
        return "\(value.prefix(3))••••\(value.suffix(3))"
    }
}

private struct BrowserBonusItem: Identifiable {
    let name: String
    let cost: Double
    let option: String
    let action: String
    let hiddenInputs: [String: String]
    let disabled: Bool
    var id: String { action + "#" + option }
}

private struct BrowserBonusPage: Identifiable {
    let id = UUID()
    let balance: Double
    let items: [BrowserBonusItem]
}

@MainActor
private final class BrowserBonusExchangeState: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isCancelled = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var remaining = 0.0
    @Published private(set) var countdown = 0
    @Published var isPaused = false

    var progress: Double { total > 0 ? Double(completed) / Double(total) : 0 }

    func begin(quantity: Int, balance: Double) {
        isRunning = true
        isCancelled = false
        isPaused = false
        completed = 0
        total = max(0, quantity)
        remaining = max(0, balance)
        countdown = 0
    }

    func recordCompletion(cost: Double) {
        completed = min(total, completed + 1)
        remaining = max(0, remaining - cost)
    }

    func togglePause() {
        guard isRunning, !isCancelled else { return }
        isPaused.toggle()
    }

    func stop() {
        guard isRunning else { return }
        isCancelled = true
        isPaused = false
        countdown = 0
    }

    func finish() {
        isRunning = false
        isPaused = false
        countdown = 0
    }

    func waitUntilResumed() async throws {
        while isPaused && !isCancelled {
            try await Task.sleep(for: .milliseconds(250))
        }
        try Task.checkCancellation()
        if isCancelled { throw CancellationError() }
    }

    func waitBetweenSubmissions(seconds: Int) async throws {
        guard seconds > 0 else { return }
        for value in stride(from: seconds, through: 1, by: -1) {
            countdown = value
            try await waitUntilResumed()
            try await Task.sleep(for: .seconds(1))
        }
        countdown = 0
    }
}

private func browserJavaScriptLiteral(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value),
          let text = String(data: data, encoding: .utf8) else { return "null" }
    return text
}

private func parsedBrowserJavaScriptValue(_ value: Any?) -> Any? {
    guard let value else { return nil }
    if let text = value as? String,
       let data = text.data(using: .utf8),
       let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
        return decoded
    }
    return value
}

private func browserTorrentExtractionScript(config: [String: Any], detail: Bool) -> String {
    let keys = detail
        ? [
            "title": "detail_title_rule", "subtitle": "detail_subtitle_rule",
            "download": "detail_download_url_rule", "category": "detail_category_rule",
            "poster": "detail_poster_rule", "size": "detail_size_rule", "hr": "detail_hr_rule", "sale": "detail_free_rule",
            "saleExpiry": "detail_free_expire_rule", "tags": "detail_tags_rule"
        ]
        : [
            "row": "torrents_rule", "title": "torrent_title_rule", "subtitle": "torrent_subtitle_rule",
            "detail": "torrent_detail_url_rule", "download": "torrent_magnet_url_rule",
            "category": "torrent_category_rule", "poster": "torrent_poster_rule",
            "size": "torrent_size_rule", "progress": "torrent_progress_rule", "hr": "torrent_hr_rule",
            "sale": "torrent_sale_rule", "saleExpiry": "torrent_sale_expire_rule",
            "published": "torrent_release_rule", "seeders": "torrent_seeders_rule",
            "leechers": "torrent_leechers_rule", "completers": "torrent_completers_rule",
            "tags": "torrent_tags_rule"
        ]
    var rules: [String: String] = [:]
    for (name, key) in keys { rules[name] = firstConfigString(config[key]) ?? "" }
    let literal = browserJavaScriptLiteral(rules)
    return """
    (() => {
      const rules = \(literal);
      const variants = (rule) => {
        const raw = String(rule || '').trim();
        if (!raw) return [];
        const values = new Set([raw]);
        values.add(raw.replace(/\\/tbody(?=\\/|$)/gi, ''));
        values.add(raw.replace(/(\\/table(?:\\[[^\\]]+\\])?)(?=\\/tr(?:\\[[^\\]]+\\])?(?:\\/|$))/gi, '$1/tbody'));
        return Array.from(values).filter(Boolean);
      };
      const clean = (value) => String(value || '').replace(/\\u00a0/g, ' ').replace(/\\s+/g, ' ').trim();
      const read = (node) => {
        if (!node) return '';
        if (node.nodeType === Node.ATTRIBUTE_NODE || node.nodeType === Node.TEXT_NODE || node.nodeType === Node.CDATA_SECTION_NODE) return clean(node.nodeValue);
        if (node instanceof HTMLAnchorElement) return clean(node.getAttribute('href') || node.href || node.textContent);
        if (node instanceof HTMLImageElement) return clean(node.getAttribute('src') || node.src);
        return clean(node.textContent);
      };
      const nodes = (root, rule) => {
        for (const candidate of variants(rule)) {
          try {
            const result = document.evaluate(candidate, root, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            const values = [];
            for (let index = 0; index < result.snapshotLength; index += 1) values.push(result.snapshotItem(index));
            if (values.length) return values;
          } catch (_) {}
        }
        return [];
      };
      const value = (root, rule) => {
        for (const candidate of variants(rule)) {
          try {
            const result = document.evaluate(candidate, root, null, XPathResult.ANY_TYPE, null);
            if (result.resultType === XPathResult.STRING_TYPE && clean(result.stringValue)) return clean(result.stringValue);
            if (result.resultType === XPathResult.NUMBER_TYPE && Number.isFinite(result.numberValue)) return String(result.numberValue);
            const node = result.singleNodeValue || (result.iterateNext ? result.iterateNext() : null);
            const text = read(node);
            if (text) return text;
          } catch (_) {}
        }
        const list = nodes(root, rule);
        return list.length ? read(list[0]) : '';
      };
      const absolute = (text) => { try { return text ? new URL(text, window.location.href).href : ''; } catch (_) { return text || ''; } };
      const build = (root, isDetail) => ({
        title: value(root, rules.title), subtitle: value(root, rules.subtitle),
        detailUrl: isDetail ? window.location.href : absolute(value(root, rules.detail)),
        magnetUrl: absolute(value(root, rules.download)), category: value(root, rules.category),
        poster: absolute(value(root, rules.poster)), size: value(root, rules.size),
        progress: value(root, rules.progress), hr: value(root, rules.hr), sale: value(root, rules.sale),
        saleExpire: value(root, rules.saleExpiry), release: value(root, rules.published),
        seeders: value(root, rules.seeders), leechers: value(root, rules.leechers),
        completers: value(root, rules.completers), tags: nodes(root, rules.tags).map(read).filter(Boolean)
      });
      const result = \(detail ? "build(document, true)" : "nodes(document, rules.row).map((row) => build(row, false)).filter((item) => item.title || item.detailUrl || item.magnetUrl)");
      return JSON.stringify(result);
    })();
    """
}

private func browserProfileExtractionScript(config: [String: Any]) -> String {
    let definitions: [(String, String, String)] = [
        ("username", "用户名", "my_username_rule"), ("email", "邮箱", "my_email_rule"),
        ("uid", "UID", "my_uid_rule"), ("passkey", "Passkey", "my_passkey_rule"),
        ("time_join", "注册时间", "my_time_join_rule"), ("latest_active", "最后活动", "my_latest_active_rule"),
        ("level", "等级", "my_level_rule"), ("uploaded", "上传量", "my_uploaded_rule"),
        ("downloaded", "下载量", "my_downloaded_rule"), ("ratio", "分享率", "my_ratio_rule"),
        ("bonus", "魔力值", "my_bonus_rule"), ("bonus_hour", "每小时魔力", "my_per_hour_bonus_rule"),
        ("score", "积分", "my_score_rule"), ("invitation", "邀请", "my_invitation_rule"),
        ("seed", "做种数", "my_seed_rule"), ("seed_volume", "做种体积", "my_seed_vol_rule"),
        ("leech", "下载中", "my_leech_rule"), ("publish", "发布数", "my_publish_rule"),
        ("hr", "HR", "my_hr_rule")
    ]
    let specs = definitions.map { ["key": $0.0, "label": $0.1, "rule": firstConfigString(config[$0.2]) ?? ""] }
    let pageUser = firstConfigString(config["page_user"]) ?? ""
    return """
    (() => {
      const specs = \(browserJavaScriptLiteral(specs));
      const pageUser = \(browserJavaScriptLiteral([pageUser])).at(0) || '';
      const clean = (value) => String(value || '').replace(/\\u00a0/g, ' ').replace(/\\s+/g, ' ').trim();
      const read = (node) => {
        if (!node) return '';
        if (node.nodeType === Node.ATTRIBUTE_NODE || node.nodeType === Node.TEXT_NODE) return clean(node.nodeValue);
        if (node instanceof HTMLAnchorElement) return clean(node.getAttribute('href') || node.href || node.textContent);
        return clean(node.textContent);
      };
      const evaluate = (rule) => {
        if (!rule) return '';
        for (const candidate of [rule, rule.replace(/\\/tbody(?=\\/|$)/gi, '')]) {
          try {
            const result = document.evaluate(candidate, document, null, XPathResult.ANY_TYPE, null);
            if (result.resultType === XPathResult.STRING_TYPE && clean(result.stringValue)) return clean(result.stringValue);
            if (result.resultType === XPathResult.NUMBER_TYPE && Number.isFinite(result.numberValue)) return String(result.numberValue);
            const text = read(result.singleNodeValue || (result.iterateNext ? result.iterateNext() : null));
            if (text) return text;
          } catch (_) {}
        }
        return '';
      };
      const uid = (raw) => {
        if (/^\\d+$/.test(raw)) return raw;
        for (const candidate of [raw, window.location.href, ...Array.from(document.querySelectorAll('a[href]')).map((a) => a.href)]) {
          try {
            const url = new URL(candidate, window.location.href);
            for (const key of ['id', 'uid', 'user_id', 'userid']) { const value = url.searchParams.get(key); if (value) return value; }
            const match = url.pathname.match(/(?:user|users|userdetails)[^0-9]*(\\d+)/i); if (match) return match[1];
          } catch (_) {}
        }
        if (pageUser.includes('{}')) { const match = window.location.href.match(/\\d+/g); if (match) return match.at(-1); }
        return raw;
      };
      return JSON.stringify(specs.map((spec) => {
        const raw = evaluate(spec.rule);
        return { key: spec.key, label: spec.label, value: spec.key === 'uid' ? uid(raw) : raw };
      }).filter((item) => item.value));
    })();
    """
}

private func browserBonusExtractionScript(config: [String: Any]) -> String {
    let bonusRule = firstConfigString(config["my_bonus_rule"]) ?? ""
    return """
    (() => {
      const bonusRule = \(browserJavaScriptLiteral([bonusRule]))[0] || '';
      const clean = (value) => String(value || '').replace(/\\u00a0/g, ' ').replace(/\\s+/g, ' ').trim();
      const number = (value) => {
        const match = clean(value).replace(/,/g, '').match(/[0-9]+(?:\\.[0-9]+)?/);
        return match ? Number(match[0]) : 0;
      };
      let balance = 0;
      if (bonusRule) {
        try {
          const result = document.evaluate(bonusRule, document, null, XPathResult.STRING_TYPE, null);
          balance = number(result.stringValue);
        } catch (_) {
          try {
            const result = document.evaluate(bonusRule, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null);
            balance = number(result.singleNodeValue?.textContent);
          } catch (_) {}
        }
      }
      const bodyText = clean(document.body?.innerText);
      if (!balance) {
        const match = bodyText.match(/(?:魔力|bonus|karma|积分|爆米花|幸运星|猫粮|啤酒瓶|电力值|电力|余额)[：:\\s]*([0-9,.]+)/i)
          || bodyText.match(/([0-9,.]+)\\s*(?:魔力|bonus|karma|积分|爆米花|幸运星|猫粮|啤酒瓶|电力值|电力)/i);
        if (match) balance = number(match[1]);
      }
      const seen = new Set();
      const items = [];
      for (const form of Array.from(document.querySelectorAll('form'))) {
        const optionInput = form.querySelector('input[name="option"]');
        if (!optionInput || !optionInput.value || seen.has(optionInput.value)) continue;
        const container = form.closest('tr, [class*="bonus"], [class*="exchange"], article, li') || form;
        const submit = form.querySelector('button[type="submit"], input[type="submit"]');
        const text = clean(container.innerText || container.textContent);
        if (!text || /赠送|捐赠|消除|头衔|免费|置顶|H&R/i.test(text)) continue;
        const titleNode = container.querySelector('h1, h2, h3, [class*="title"], [class*="name"], td');
        let name = clean(titleNode?.innerText || titleNode?.textContent || text.split(/\\s{2,}|\\n/)[0]);
        if (name.length > 80) name = name.slice(0, 80);
        let cost = 0;
        for (const node of Array.from(container.querySelectorAll('[class*="price"], [class*="cost"], [class*="points"], .red, strong'))) {
          const value = number(node.innerText || node.textContent);
          if (value > 0) { cost = value; break; }
        }
        if (!cost) {
          const match = text.match(/([0-9,.]+)\\s*(?:Points?|魔力|bonus|karma|积分|爆米花|幸运星|猫粮|啤酒瓶|电力值|电力)/i);
          if (match) cost = number(match[1]);
        }
        if (!cost) {
          const values = (text.match(/[0-9][0-9,.]*/g) || []).map(number).filter((value) => value >= 10 && value !== Number(optionInput.value));
          if (values.length) cost = values.at(-1);
        }
        if (!cost) continue;
        const hiddenInputs = {};
        for (const input of Array.from(form.querySelectorAll('input[type="hidden"]'))) {
          if (input.name) hiddenInputs[input.name] = input.value || '';
        }
        hiddenInputs.option = optionInput.value;
        seen.add(optionInput.value);
        items.push({
          name: name || `Option ${optionInput.value}`,
          cost, option: optionInput.value,
          action: form.getAttribute('action') || window.location.href,
          hiddenInputs, disabled: Boolean(submit?.disabled)
        });
      }
      return JSON.stringify({ balance, items });
    })();
    """
}

private func parsedBrowserBonusPage(_ raw: Any?) -> BrowserBonusPage? {
    guard let parsed = parsedBrowserJavaScriptValue(raw), let dictionary = jsonDictionary(parsed) else { return nil }
    let items = dictionary.rows("items").compactMap { row -> BrowserBonusItem? in
        guard let option = row.string("option", "optionValue"), !option.isEmpty else { return nil }
        let hidden = (row.dict("hiddenInputs", "hidden_inputs") ?? [:]).reduce(into: [String: String]()) { result, entry in
            result[entry.key] = String(describing: entry.value)
        }
        return BrowserBonusItem(
            name: row.string("name") ?? "兑换项目",
            cost: row.double("cost") ?? 0,
            option: option,
            action: row.string("action", "formAction") ?? "",
            hiddenInputs: hidden,
            disabled: row.bool("disabled") ?? false
        )
    }.filter { $0.cost > 0 && !$0.disabled }
    guard !items.isEmpty else { return nil }
    return BrowserBonusPage(balance: dictionary.double("balance", "currentBonus") ?? 0, items: items)
}

private func browserBonusSubmitScript(_ item: BrowserBonusItem) -> String {
    var inputs = item.hiddenInputs
    inputs["option"] = item.option
    return """
    const action = \(browserJavaScriptLiteral([item.action]))[0] || window.location.href;
    const inputs = \(browserJavaScriptLiteral(inputs));
    const body = new URLSearchParams();
    Object.entries(inputs).forEach(([key, value]) => body.append(key, String(value)));
    const response = await fetch(new URL(action, window.location.href), {
      method: 'POST', credentials: 'include', redirect: 'follow',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' }, body
    });
    return JSON.stringify({ ok: response.ok, status: response.status });
    """
}

private let browserSafariMacUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
private let browserSafariPhoneUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
private let browserChromeAndroidUserAgent = "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
private let browserChromeWindowsUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
private let browserEdgeWindowsUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0"
private let browserFirefoxWindowsUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0"

struct SiteBrowserScreen: View {
    @EnvironmentObject private var appState: AppState
    let site: SiteItem
    let urlString: String
    let title: String
    let onSynced: () async -> Void
    @StateObject private var session = BrowserSessionModel()
    @State private var isSyncing = false
    @State private var isWorking = false
    @State private var siteConfig: [String: Any] = [:]
    @State private var downloaders: [DownloaderItem] = []
    @State private var pushPayload: BrowserPushPayload?
    @State private var extractedTorrents: [BrowserExtractedTorrent] = []
    @State private var showExtractedTorrents = false
    @State private var profileMetrics: [BrowserProfileMetric] = []
    @State private var showProfile = false
    @State private var bonusPage: BrowserBonusPage?
    @StateObject private var bonusExchangeState = BrowserBonusExchangeState()
    @State private var screenshotImage: UIImage?
    @State private var showScreenshotShare = false
    @State private var isCapturingScreenshot = false
    @State private var createdSiteID: Int?
    @State private var persistedSiteBody: [String: Any]?

    init(site: SiteItem, urlString: String, title: String, onSynced: @escaping () async -> Void = {}) {
        self.site = site
        self.urlString = urlString
        self.title = title
        self.onSynced = onSynced
    }

    var body: some View {
        ZStack(alignment: .top) {
            NativeBrowserView(
                urlString: urlString,
                title: title,
                cookie: site.cookie,
                localStorage: site.localStorage,
                userAgent: site.userAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? browserSafariMacUserAgent : site.userAgent,
                localStorageURLs: browserLocalStorageURLs,
                installsLocalStorageAuthBridge: installsBrowserAuthBridge,
                session: session
            )
            if let error = session.loadError, !session.isLoading {
                ContentUnavailableView {
                    Label("网页加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    VStack(spacing: 6) {
                        Text(error)
                        Text((session.currentURL ?? URL(string: urlString))?.absoluteString ?? urlString)
                            .font(.caption2.monospaced())
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                } actions: {
                    Button { session.reload() } label: {
                        Label("重新加载", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HarvestTheme.green)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial)
            }
            if session.isLoading {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(HarvestTheme.green)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !browserShortcuts.isEmpty {
                        Menu {
                            ForEach(browserShortcuts) { shortcut in
                                Button { openBrowserShortcut(shortcut) } label: {
                                    Label(shortcut.label, systemImage: shortcut.icon)
                                }
                            }
                        } label: {
                            Label("站点快捷入口", systemImage: "safari")
                        }
                        Divider()
                    }
                    Button { copyCurrentLink() } label: {
                        Label("复制当前链接", systemImage: "link")
                    }
                    Button { Task { await captureLongScreenshot() } } label: {
                        Label("网页长截图", systemImage: "camera.viewfinder")
                    }
                    .disabled(isCapturingScreenshot || isWorking)
                    Button { Task { await copyAuthorizationInfo() } } label: {
                        Label("复制授权信息", systemImage: "doc.on.clipboard")
                    }
                    Button { Task { await copyAuthorizationDiagnostics() } } label: {
                        Label("复制授权诊断", systemImage: "checkmark.shield")
                    }
                    Menu {
                        if !site.userAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("站点配置") { session.setUserAgent(site.userAgent) }
                        }
                        Button("Safari macOS") { session.setUserAgent(browserSafariMacUserAgent) }
                        Button("Safari iPhone") { session.setUserAgent(browserSafariPhoneUserAgent) }
                        Button("系统默认") { session.setUserAgent(nil) }
                        Divider()
                        Button("Chrome Android") { session.setUserAgent(browserChromeAndroidUserAgent) }
                        Button("Chrome Windows") { session.setUserAgent(browserChromeWindowsUserAgent) }
                        Button("Edge Windows") { session.setUserAgent(browserEdgeWindowsUserAgent) }
                        Button("Firefox Windows") { session.setUserAgent(browserFirefoxWindowsUserAgent) }
                    } label: {
                        Label("切换 User-Agent", systemImage: "globe")
                    }
                    Divider()
                    if effectiveSiteID > 0 {
                        Button { Task { await syncCredentials() } } label: {
                            Label("同步 Cookie 与 LocalStorage", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(isSyncing || isWorking)
                    }
                    if hasTorrentListRules {
                        Button { Task { await extractTorrentList() } } label: {
                            Label("提取种子列表", systemImage: "list.bullet.rectangle")
                        }
                    }
                    if hasTorrentDetailRules {
                        Button { Task { await extractTorrentDetail() } } label: {
                            Label("提取当前种子", systemImage: "arrow.down.doc")
                        }
                    }
                    if hasProfileRules {
                        Button { Task { await extractProfile() } } label: {
                            Label("提取用户资料", systemImage: "person.text.rectangle")
                        }
                    }
                    if hasBonusRules {
                        Button { Task { await extractBonusPage() } } label: {
                            Label("魔力值兑换", systemImage: "wand.and.stars")
                        }
                    }
                    Button { Task { await clearBrowserData() } } label: {
                        Label("清理当前站点数据", systemImage: "trash")
                    }
                    if let url = session.currentURL ?? URL(string: urlString) {
                        Link(destination: url) { Label("在 Safari 中打开", systemImage: "safari") }
                        ShareLink(item: url) { Label("分享当前页面", systemImage: "square.and.arrow.up") }
                    }
                } label: {
                    if isSyncing || isWorking || isCapturingScreenshot { ProgressView() } else { Image(systemName: "ellipsis.circle") }
                }
                .accessibilityLabel("网页工具")
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button { session.goBack() } label: { Image(systemName: "chevron.backward") }
                    .disabled(!session.canGoBack)
                    .accessibilityLabel("后退")
                Button { session.goForward() } label: { Image(systemName: "chevron.forward") }
                    .disabled(!session.canGoForward)
                    .accessibilityLabel("前进")
                if !browserShortcuts.isEmpty {
                    Menu {
                        ForEach(browserShortcuts) { shortcut in
                            Button { openBrowserShortcut(shortcut) } label: {
                                Label(shortcut.label, systemImage: shortcut.icon)
                            }
                        }
                    } label: {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("站点快捷入口")
                }
                Spacer()
                Button { session.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("刷新网页")
            }
        }
        .task {
            await loadBrowserConfig()
            await loadDownloaders()
        }
        .onChange(of: session.pendingTorrent) { _, request in
            guard let request else { return }
            session.pendingTorrent = nil
            Task { await presentPush(input: request.url.absoluteString) }
        }
        .sheet(item: $pushPayload) { payload in
            AddTorrentSheet(
                downloaders: downloaders,
                initialInput: payload.input,
                initialCookie: payload.cookie,
                initialSiteID: site.id,
                initialSiteKey: site.siteKey,
                onSaved: { }
            )
            .environmentObject(appState)
        }
        .sheet(isPresented: $showExtractedTorrents) {
            BrowserTorrentExtractionSheet(items: extractedTorrents) { selected in
                showExtractedTorrents = false
                let input = selected.map(\.pushURL).filter { !$0.isEmpty }.joined(separator: "\n")
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    await presentPush(input: input)
                }
            }
        }
        .sheet(isPresented: $showProfile) {
            BrowserProfileSheet(
                metrics: profileMetrics,
                actionTitle: effectiveSiteID > 0 ? "更新站点" : "添加站点"
            ) { await saveProfile() }
        }
        .sheet(item: $bonusPage) { page in
            BrowserBonusSheet(page: page, exchangeState: bonusExchangeState) { item, quantity, delay in
                await exchangeBonus(item: item, quantity: quantity, delaySeconds: delay, balance: page.balance)
            }
        }
        .sheet(isPresented: $showScreenshotShare) {
            if let screenshotImage { ActivityShareSheet(items: [screenshotImage]) }
        }
    }

    @MainActor private func copyCurrentLink() {
        UIPasteboard.general.string = (session.currentURL ?? URL(string: urlString))?.absoluteString ?? urlString
    }

    private var browserLocalStorageURLs: [String] {
        [urlString, site.url, site.rss, site.torrentsURL] + configStrings(siteConfig["url"])
    }

    private var installsBrowserAuthBridge: Bool {
        let storage = site.localStorage.lowercased()
        guard storage.contains("auth") || storage.contains("token") else { return false }
        let configuredIdentity = [
            firstConfigString(siteConfig["name"]),
            firstConfigString(siteConfig["nickname"]),
            firstConfigString(siteConfig["tracker"])
        ].compactMap { $0 }
        let identity = ([site.siteKey, site.name, site.url, urlString] + configuredIdentity + configStrings(siteConfig["url"]))
            .joined(separator: " ")
            .lowercased()
        return identity.contains("m-team") || identity.contains("mteam") || identity.contains("rousi")
    }

    private var browserShortcuts: [SitePageShortcut] {
        var shortcuts: [SitePageShortcut] = []
        var seen: Set<String> = []

        func append(
            key: String,
            label: String,
            icon: String,
            rawPath: String,
            fallbackToSite: Bool = false,
            hideAPI: Bool = false,
            replaceUserID: Bool = false,
            clearPlaceholder: Bool = false
        ) {
            guard let url = resolvedBrowserShortcutURL(
                rawPath,
                fallbackToSite: fallbackToSite,
                hideAPI: hideAPI,
                replaceUserID: replaceUserID,
                clearPlaceholder: clearPlaceholder
            ) else { return }
            let identity = "\(label)|\(url.absoluteString)"
            guard seen.insert(identity).inserted else { return }
            shortcuts.append(SitePageShortcut(key: key, label: label, icon: icon, path: url.absoluteString))
        }

        append(key: "page_index", label: "首页", icon: "house", rawPath: firstConfigString(siteConfig["page_index"]) ?? "", fallbackToSite: true)
        append(key: "page_sign_in", label: "签到页", icon: "checkmark.seal", rawPath: firstConfigString(siteConfig["page_sign_in"]) ?? "", hideAPI: true)
        append(key: "page_torrents", label: "种子页", icon: "list.bullet.rectangle", rawPath: firstConfigString(siteConfig["page_torrents"]) ?? "")
        for (index, path) in configStrings(siteConfig["page_search"]).enumerated() {
            append(
                key: "page_search_\(index)",
                label: index == 0 ? "搜索页" : "搜索页 \(index + 1)",
                icon: "magnifyingglass",
                rawPath: path,
                clearPlaceholder: true
            )
        }
        append(key: "page_user", label: "个人中心", icon: "person.crop.circle", rawPath: firstConfigString(siteConfig["page_user"]) ?? "", hideAPI: true, replaceUserID: true)
        append(key: "page_control_panel", label: "控制中心", icon: "slider.horizontal.3", rawPath: firstConfigString(siteConfig["page_control_panel"]) ?? "", replaceUserID: true)
        append(key: "page_message", label: "消息中心", icon: "envelope", rawPath: firstConfigString(siteConfig["page_message"]) ?? "")
        append(key: "page_mybonus", label: "魔力页面", icon: "wand.and.stars", rawPath: firstConfigString(siteConfig["page_mybonus"]) ?? "")
        return shortcuts
    }

    private func resolvedBrowserShortcutURL(
        _ rawPath: String,
        fallbackToSite: Bool,
        hideAPI: Bool,
        replaceUserID: Bool,
        clearPlaceholder: Bool
    ) -> URL? {
        var value = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            guard fallbackToSite else { return nil }
            value = site.url.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if hideAPI, value.lowercased().contains("api/") { return nil }
        if clearPlaceholder { value = value.replacingOccurrences(of: "{}", with: "") }
        if replaceUserID, value.contains("{}") {
            let userID = site.userID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !userID.isEmpty else { return nil }
            value = value.replacingOccurrences(of: "{}", with: userID)
        }
        if value.hasPrefix("//") {
            value = "/" + String(value.drop(while: { $0 == "/" }))
        }
        if let absolute = URL(string: value), absolute.scheme != nil { return absolute }

        let baseText = site.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: baseText), base.scheme != nil else { return nil }
        return URL(string: value, relativeTo: base)?.absoluteURL
    }

    @MainActor private func openBrowserShortcut(_ shortcut: SitePageShortcut) {
        guard let url = URL(string: shortcut.path) else {
            appState.presentedError = "站点快捷链接无效"
            return
        }
        session.load(url)
    }

    @MainActor private func captureLongScreenshot() async {
        guard !isCapturingScreenshot else { return }
        isCapturingScreenshot = true
        defer { isCapturingScreenshot = false }
        do {
            screenshotImage = try await session.captureLongScreenshot()
            showScreenshotShare = screenshotImage != nil
        } catch {
            appState.presentedError = error.localizedDescription
        }
    }

    @MainActor private func copyAuthorizationInfo() async {
        do {
            let storage = try await session.captureStorage()
            UIPasteboard.general.string = prettyJSON([
                "cookie": storage.cookie,
                "localstorage": storage.localStorage
            ])
        } catch {
            appState.presentedError = error.localizedDescription
        }
    }

    @MainActor private func copyAuthorizationDiagnostics() async {
        let storage = try? await session.captureStorage()
        UIPasteboard.general.string = prettyJSON([
            "current_url": session.currentURL?.absoluteString ?? urlString,
            "initial_url": urlString,
            "configured_localstorage_length": site.localStorage.count,
            "configured_localstorage": site.localStorage,
            "cookie_length": storage?.cookie.count ?? 0,
            "cookie": storage?.cookie ?? "",
            "localstorage_length": storage?.localStorage.count ?? 0,
            "localstorage": storage?.localStorage ?? "",
            "user_agent": session.webView?.customUserAgent ?? "系统默认"
        ])
    }

    @MainActor private func syncCredentials() async {
        guard effectiveSiteID > 0 else {
            appState.presentedError = "请先提取用户资料并添加站点"
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let storage = try await session.captureStorage()
            var body = persistedSiteBody ?? site.raw
            body["id"] = effectiveSiteID
            body["cookie"] = storage.cookie
            body["local_storage"] = storage.localStorage
            if await appState.perform("\(APIPath.sites)/\(effectiveSiteID)", method: .put, body: body) {
                persistedSiteBody = body
                await onSynced()
            }
        } catch {
            appState.presentedError = error.localizedDescription
        }
    }

    private var hasTorrentListRules: Bool {
        !(firstConfigString(siteConfig["torrents_rule"]) ?? "").isEmpty
    }

    private var hasTorrentDetailRules: Bool {
        !(firstConfigString(siteConfig["detail_download_url_rule"]) ?? "").isEmpty
            || !(firstConfigString(siteConfig["detail_title_rule"]) ?? "").isEmpty
    }

    private var hasProfileRules: Bool {
        (firstConfigString(siteConfig["page_user"]) ?? "").contains("{}")
            || siteConfig.keys.contains {
                $0.hasPrefix("my_") && $0.hasSuffix("_rule") && !(firstConfigString(siteConfig[$0]) ?? "").isEmpty
            }
    }

    private var hasBonusRules: Bool {
        !(firstConfigString(siteConfig["page_mybonus"]) ?? "").isEmpty
            || !(firstConfigString(siteConfig["buy_page"]) ?? "").isEmpty
            || siteConfig["buy_action"] != nil
    }

    private var effectiveSiteID: Int { site.id > 0 ? site.id : createdSiteID ?? 0 }

    @MainActor private func loadBrowserConfig() async {
        guard siteConfig.isEmpty, !site.siteKey.isEmpty else { return }
        do {
            siteConfig = jsonPayloadDictionary(try await appState.api(
                "\(APIPath.websiteList)/\(urlPathSegment(site.siteKey))"
            )) ?? [:]
        } catch {
            siteConfig = [:]
        }
    }

    @MainActor private func loadDownloaders() async {
        guard downloaders.isEmpty else { return }
        do {
            downloaders = jsonRows(try await appState.api(APIPath.downloaders))
                .map(DownloaderItem.init)
                .filter(\.enabled)
        } catch {
            downloaders = []
        }
    }

    @MainActor private func presentPush(input: String) async {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        await loadDownloaders()
        let cookie = (try? await session.captureStorage())?.cookie ?? site.cookie
        pushPayload = BrowserPushPayload(input: value, cookie: cookie)
    }

    @MainActor private func extractTorrentList() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let raw = try await session.evaluateJavaScript(browserTorrentExtractionScript(config: siteConfig, detail: false))
            let rows = jsonRows(parsedBrowserJavaScriptValue(raw) ?? [])
            let items = rows.map(BrowserExtractedTorrent.init).filter { !$0.pushURL.isEmpty }
            guard !items.isEmpty else { throw APIError(statusCode: 0, message: "当前页面未提取到种子") }
            extractedTorrents = items
            showExtractedTorrents = true
        } catch {
            appState.presentedError = error.localizedDescription
        }
    }

    @MainActor private func extractTorrentDetail() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let raw = try await session.evaluateJavaScript(browserTorrentExtractionScript(config: siteConfig, detail: true))
            guard let parsed = parsedBrowserJavaScriptValue(raw), let row = jsonDictionary(parsed) else {
                throw APIError(statusCode: 0, message: "当前页面未提取到种子详情")
            }
            let item = BrowserExtractedTorrent(row)
            guard !item.pushURL.isEmpty else { throw APIError(statusCode: 0, message: "当前页面未提取到种子详情") }
            await presentPush(input: item.pushURL)
        } catch {
            appState.presentedError = error.localizedDescription
        }
    }

    @MainActor private func extractProfile() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let raw = try await session.evaluateJavaScript(browserProfileExtractionScript(config: siteConfig))
            let rows = jsonRows(parsedBrowserJavaScriptValue(raw) ?? [])
            profileMetrics = rows.compactMap { row in
                guard let key = row.string("key"), let value = row.string("value"), !value.isEmpty else { return nil }
                return BrowserProfileMetric(key: key, label: row.string("label") ?? key, value: value)
            }
            guard !profileMetrics.isEmpty else { throw APIError(statusCode: 0, message: "当前页面未提取到用户资料") }
            showProfile = true
        } catch {
            appState.presentedError = error.localizedDescription
        }
    }

    @MainActor private func saveProfile() async -> Bool {
        func value(_ key: String) -> String? { profileMetrics.first(where: { $0.key == key })?.value }
        guard let uid = value("uid"), !uid.isEmpty else {
            appState.presentedError = "未提取到 UID，无法更新站点"
            return false
        }
        var body = persistedSiteBody ?? site.raw
        body["id"] = effectiveSiteID
        body["site"] = site.siteKey
        body["nickname"] = site.name
        body["sort_id"] = site.sortID
        body["mirror"] = site.url
        body["user_id"] = uid
        let fields = [
            "username": "username", "email": "email", "passkey": "passkey",
            "time_join": "time_join", "latest_active": "latest_active"
        ]
        for (source, target) in fields {
            if let item = value(source), !item.isEmpty { body[target] = item }
        }
        do {
            let storage = try await session.captureStorage()
            body["cookie"] = storage.cookie
            body["local_storage"] = storage.localStorage
        } catch { }
        let isNew = effectiveSiteID == 0
        let path = isNew ? APIPath.sites : "\(APIPath.sites)/\(effectiveSiteID)"
        let saved = await appState.perform(path, method: isNew ? .post : .put, body: body)
        if saved {
            persistedSiteBody = body
            if isNew { await resolveCreatedSite() }
            await onSynced()
        }
        return saved
    }

    @MainActor private func resolveCreatedSite() async {
        do {
            let sites = jsonRows(try await appState.api(APIPath.sites)).map(SiteItem.init)
            guard let saved = sites.first(where: {
                $0.siteKey.caseInsensitiveCompare(site.siteKey) == .orderedSame
            }) else { return }
            createdSiteID = saved.id
            persistedSiteBody = saved.raw
        } catch {
            await AppLogStore.shared.append(.warning, "新增站点后读取 ID 失败：\(error.localizedDescription)")
        }
    }

    @MainActor private func extractBonusPage() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let raw = try await session.evaluateJavaScript(browserBonusExtractionScript(config: siteConfig))
            guard let page = parsedBrowserBonusPage(raw) else {
                throw APIError(statusCode: 0, message: "当前页面未识别到可兑换项目")
            }
            bonusPage = page
        } catch {
            appState.presentedError = error.localizedDescription
        }
    }

    @MainActor private func exchangeBonus(
        item: BrowserBonusItem,
        quantity: Int,
        delaySeconds: Int,
        balance: Double
    ) async -> Bool {
        guard quantity > 0 else { return false }
        isWorking = true
        bonusExchangeState.begin(quantity: quantity, balance: balance)
        defer {
            isWorking = false
            bonusExchangeState.finish()
        }
        do {
            for index in 0..<quantity {
                try await bonusExchangeState.waitUntilResumed()
                let raw = try await session.callAsyncJavaScript(browserBonusSubmitScript(item))
                guard let parsed = parsedBrowserJavaScriptValue(raw),
                      let result = jsonDictionary(parsed),
                      result.bool("ok") == true else {
                    throw APIError(statusCode: 0, message: "第 \(index + 1) 次兑换失败")
                }
                bonusExchangeState.recordCompletion(cost: item.cost)
                if bonusExchangeState.remaining < item.cost { break }
                if index < quantity - 1 {
                    try await bonusExchangeState.waitBetweenSubmissions(seconds: min(120, max(12, delaySeconds)))
                }
            }
            session.reload()
            return !bonusExchangeState.isCancelled && bonusExchangeState.completed == quantity
        } catch is CancellationError {
            session.reload()
            return false
        } catch {
            appState.presentedError = error.localizedDescription
            session.reload()
            return false
        }
    }

    @MainActor private func clearBrowserData() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.clearCurrentSiteData()
        } catch {
            appState.presentedError = error.localizedDescription
        }
    }
}

private enum BrowserTorrentSort: String, CaseIterable, Identifiable {
    case name = "名称"
    case seeders = "做种人数"
    case size = "大小"
    var id: String { rawValue }
}

private struct BrowserTorrentExtractionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let items: [BrowserExtractedTorrent]
    let onPush: ([BrowserExtractedTorrent]) -> Void
    @State private var selected: Set<UUID>
    @State private var query = ""
    @State private var promotion = ""
    @State private var category = ""
    @State private var tags: Set<String> = []
    @State private var sort = BrowserTorrentSort.seeders
    @State private var ascending = false

    init(items: [BrowserExtractedTorrent], onPush: @escaping ([BrowserExtractedTorrent]) -> Void) {
        self.items = items
        self.onPush = onPush
        _selected = State(initialValue: Set(items.filter { !$0.pushURL.isEmpty }.map(\.id)))
    }

    private var promotions: [String] { Array(Set(items.map(\.promotion).filter { !$0.isEmpty })).sorted() }
    private var categories: [String] { Array(Set(items.map(\.category).filter { !$0.isEmpty })).sorted() }
    private var allTags: [String] { Array(Set(items.flatMap(\.tags))).sorted() }
    private var filtered: [BrowserExtractedTorrent] {
        var result = items.filter { item in
            let queryMatch = query.isEmpty
                || item.title.localizedCaseInsensitiveContains(query)
                || item.subtitle.localizedCaseInsensitiveContains(query)
            let promotionMatch = promotion.isEmpty || item.promotion == promotion
            let categoryMatch = category.isEmpty || item.category == category
            let tagMatch = tags.isEmpty || !Set(item.tags).isDisjoint(with: tags)
            return queryMatch && promotionMatch && categoryMatch && tagMatch
        }
        result.sort { left, right in
            let comparison: Int
            switch sort {
            case .name:
                comparison = left.title.localizedCaseInsensitiveCompare(right.title).rawValue
            case .seeders:
                comparison = left.seederCount == right.seederCount ? 0 : (left.seederCount < right.seederCount ? -1 : 1)
            case .size:
                comparison = left.byteSize == right.byteSize ? 0 : (left.byteSize < right.byteSize ? -1 : 1)
            }
            return ascending ? comparison < 0 : comparison > 0
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                Section("筛选与排序") {
                    if !promotions.isEmpty {
                        Picker("优惠", selection: $promotion) {
                            Text("全部").tag("")
                            ForEach(promotions, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    if !categories.isEmpty {
                        Picker("分类", selection: $category) {
                            Text("全部").tag("")
                            ForEach(categories, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Picker("排序", selection: $sort) {
                        ForEach(BrowserTorrentSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("方向", selection: $ascending) {
                        Text("升序").tag(true)
                        Text("降序").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                if !allTags.isEmpty {
                    Section("标签") {
                        ForEach(allTags, id: \.self) { tag in
                            Toggle(tag, isOn: Binding(
                                get: { tags.contains(tag) },
                                set: { enabled in
                                    if enabled { tags.insert(tag) } else { tags.remove(tag) }
                                }
                            ))
                        }
                    }
                }

                Section("种子（\(filtered.count)）") {
                    ForEach(filtered) { item in
                        Button {
                            if selected.contains(item.id) { selected.remove(item.id) }
                            else { selected.insert(item.id) }
                        } label: {
                            HStack(alignment: .top, spacing: 11) {
                                Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(item.id) ? HarvestTheme.green : .secondary)
                                if let posterURL = URL(string: item.posterURL), !item.posterURL.isEmpty {
                                    CachedRemoteImage(url: posterURL) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Color.secondary.opacity(0.1)
                                            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                                    }
                                    .frame(width: 48, height: 68)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                                    if !item.subtitle.isEmpty { Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                    HStack(spacing: 9) {
                                        if !item.size.isEmpty { Label(item.size, systemImage: "externaldrive") }
                                        if !item.progress.isEmpty { Label(item.progress, systemImage: "chart.bar.fill") }
                                        if !item.seeders.isEmpty { Label(item.seeders, systemImage: "arrow.up") }
                                        if !item.promotion.isEmpty { Text(item.promotion).foregroundStyle(HarvestTheme.green) }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(item.pushURL.isEmpty)
                    }
                }
            }
            .searchable(text: $query, prompt: "搜索提取结果")
            .navigationTitle("提取种子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Menu {
                        Button("选择当前结果") { selected.formUnion(filtered.map(\.id)) }
                        Button("清空选择") { selected = [] }
                    } label: { Image(systemName: "checklist") }
                    Button("推送 \(selected.count)") {
                        onPush(items.filter { selected.contains($0.id) })
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}

private struct BrowserProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    let metrics: [BrowserProfileMetric]
    let actionTitle: String
    let onSave: () async -> Bool
    @State private var isSaving = false

    private var hasUID: Bool { metrics.contains { $0.key == "uid" && !$0.value.isEmpty } }

    var body: some View {
        NavigationStack {
            List {
                if !hasUID {
                    Section { Label("未提取到 UID，不能回写站点", systemImage: "exclamationmark.triangle.fill").foregroundStyle(HarvestTheme.coral) }
                }
                Section("账号资料") {
                    ForEach(metrics) { metric in
                        LabeledContent(metric.label) {
                            Text(metric.displayValue).multilineTextAlignment(.trailing).textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("用户资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中" : actionTitle) {
                        Task {
                            isSaving = true
                            let saved = await onSave()
                            isSaving = false
                            if saved { dismiss() }
                        }
                    }
                    .disabled(!hasUID || isSaving)
                }
            }
            .overlay { if isSaving { ProgressView().controlSize(.large) } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct BrowserBonusSheet: View {
    @Environment(\.dismiss) private var dismiss
    let page: BrowserBonusPage
    @ObservedObject var exchangeState: BrowserBonusExchangeState
    let onExchange: (BrowserBonusItem, Int, Int) async -> Bool
    @State private var selectedID: String
    @State private var quantity = 1
    @State private var delaySeconds = 12
    @State private var isStarting = false

    init(
        page: BrowserBonusPage,
        exchangeState: BrowserBonusExchangeState,
        onExchange: @escaping (BrowserBonusItem, Int, Int) async -> Bool
    ) {
        self.page = page
        self.exchangeState = exchangeState
        self.onExchange = onExchange
        _selectedID = State(initialValue: page.items.first?.id ?? "")
    }

    private var selectedItem: BrowserBonusItem? {
        page.items.first(where: { $0.id == selectedID }) ?? page.items.first
    }

    private var maximumQuantity: Int {
        guard let item = selectedItem, item.cost > 0, page.balance > 0 else { return 0 }
        return max(0, Int(page.balance / item.cost))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("余额") {
                    LabeledContent("当前魔力值", value: formatCompactNumber(page.balance))
                    if let item = selectedItem {
                        LabeledContent("单次消耗", value: formatCompactNumber(item.cost))
                        LabeledContent("兑换后剩余", value: formatCompactNumber(max(0, page.balance - item.cost * Double(quantity))))
                    }
                }
                Section("兑换设置") {
                    Picker("项目", selection: $selectedID) {
                        ForEach(page.items) { item in
                            Text("\(item.name) · \(formatCompactNumber(item.cost))").tag(item.id)
                        }
                    }
                    Stepper("数量：\(quantity)", value: $quantity, in: 1...max(1, maximumQuantity))
                    Stepper("提交间隔：\(delaySeconds) 秒", value: $delaySeconds, in: 12...120)
                }
                .disabled(exchangeState.isRunning || isStarting)

                if exchangeState.isRunning {
                    Section("兑换进度") {
                        ProgressView(value: exchangeState.progress)
                        LabeledContent("已完成", value: "\(exchangeState.completed) / \(exchangeState.total)")
                        LabeledContent("剩余魔力", value: formatCompactNumber(exchangeState.remaining))
                        if exchangeState.countdown > 0 {
                            LabeledContent("下次提交", value: "\(exchangeState.countdown) 秒")
                        }
                        HStack {
                            Button {
                                exchangeState.togglePause()
                            } label: {
                                Label(exchangeState.isPaused ? "继续" : "暂停", systemImage: exchangeState.isPaused ? "play.fill" : "pause.fill")
                            }
                            Spacer()
                            Button(role: .destructive) {
                                exchangeState.stop()
                            } label: {
                                Label("停止", systemImage: "stop.fill")
                            }
                        }
                    }
                }
            }
            .navigationTitle("魔力值兑换")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(exchangeState.isRunning || isStarting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(exchangeState.isRunning || isStarting ? "兑换中" : "兑换") {
                        guard let item = selectedItem else { return }
                        Task {
                            isStarting = true
                            let succeeded = await onExchange(item, quantity, delaySeconds)
                            isStarting = false
                            if succeeded || exchangeState.isCancelled { dismiss() }
                        }
                    }
                    .disabled(selectedItem == nil || exchangeState.isRunning || isStarting || maximumQuantity == 0 || quantity > maximumQuantity)
                }
            }
            .onChange(of: selectedID) { _, _ in quantity = min(quantity, max(1, maximumQuantity)) }
        }
        .interactiveDismissDisabled(exchangeState.isRunning || isStarting)
        .presentationDetents([.medium, .large])
    }
}

private struct SiteDetailIcon: View {
    let site: SiteItem
    let iconCandidates: [RemoteImageCandidate]
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(site.enabled ? HarvestTheme.blue : Color.secondary)
            CachedRemoteImageCandidates(candidates: iconCandidates) { image in
                image.resizable().scaledToFit().padding(8)
            } placeholder: {
                Image(systemName: "globe.americas.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private func firstConfigString(_ value: Any?) -> String? {
    if let text = value as? String { return text }
    if let values = value as? [Any] { return values.compactMap { $0 as? String }.first }
    return value.map { String(describing: $0) }
}

private func configStrings(_ value: Any?) -> [String] {
    if let text = value as? String { return text.isEmpty ? [] : [text] }
    if let values = value as? [Any] { return values.compactMap { $0 as? String } }
    return []
}

private func formatCompactNumber(_ value: Double) -> String {
    if value >= 1_000_000 { return String(format: "%.2fM", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.2fK", value / 1_000) }
    return String(format: value.rounded() == value ? "%.0f" : "%.2f", value)
}

struct SiteEditorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let site: SiteItem?
    let onSaved: () async -> Void
    @State private var siteKey: String
    @State private var availableSites: [String] = []
    @State private var availableConfigs: [String: [String: Any]] = [:]
    @State private var name: String
    @State private var sortID: String
    @State private var url = ""
    @State private var userID: String
    @State private var username: String
    @State private var cookie: String
    @State private var userAgent: String
    @State private var email: String
    @State private var passkey: String
    @State private var authkey: String
    @State private var localStorage: String
    @State private var rss: String
    @State private var torrentsURL: String
    @State private var proxy: String
    @State private var tags: String
    @State private var enabled: Bool
    @State private var signin: Bool
    @State private var getInfo: Bool
    @State private var repeatTorrents: Bool
    @State private var searchTorrents: Bool
    @State private var brushFree: Bool
    @State private var brushRSS: Bool
    @State private var packageFile: Bool
    @State private var hrDiscern: Bool
    @State private var showInDashboard: Bool

    init(site: SiteItem? = nil, onSaved: @escaping () async -> Void) {
        self.site = site
        self.onSaved = onSaved
        _siteKey = State(initialValue: site?.siteKey ?? "")
        _name = State(initialValue: site?.name ?? "")
        _sortID = State(initialValue: String(site?.sortID ?? 1))
        _url = State(initialValue: site?.url ?? "")
        _userID = State(initialValue: site?.userID ?? "")
        _username = State(initialValue: site?.username ?? "")
        _cookie = State(initialValue: site?.cookie ?? "")
        _userAgent = State(initialValue: site?.userAgent ?? "")
        _email = State(initialValue: site?.email ?? "")
        _passkey = State(initialValue: site?.passkey ?? "")
        _authkey = State(initialValue: site?.authkey ?? "")
        _localStorage = State(initialValue: site?.localStorage ?? "")
        _rss = State(initialValue: site?.rss ?? "")
        _torrentsURL = State(initialValue: site?.torrentsURL ?? "")
        _proxy = State(initialValue: site?.proxy ?? "")
        _tags = State(initialValue: site?.tags.joined(separator: ", ") ?? "")
        _enabled = State(initialValue: site?.enabled ?? true)
        _signin = State(initialValue: site?.signIn ?? true)
        _getInfo = State(initialValue: site?.getInfo ?? true)
        _repeatTorrents = State(initialValue: site?.repeatTorrents ?? true)
        _searchTorrents = State(initialValue: site?.searchTorrents ?? true)
        _brushFree = State(initialValue: site?.brushFree ?? true)
        _brushRSS = State(initialValue: site?.brushRSS ?? false)
        _packageFile = State(initialValue: site?.packageFile ?? false)
        _hrDiscern = State(initialValue: site?.hrDiscern ?? false)
        _showInDashboard = State(initialValue: site?.showInDashboard ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    if site == nil {
                        Picker("站点配置", selection: $siteKey) {
                            if availableSites.isEmpty { Text("暂无可用配置").tag("") }
                            ForEach(availableSites, id: \.self) { Text($0).tag($0) }
                        }
                        .onChange(of: siteKey) { _, value in applyConfigDefaults(value) }
                    } else {
                        LabeledContent("站点配置", value: siteKey)
                    }
                    TextField("显示名称", text: $name)
                    TextField("排序", text: $sortID).keyboardType(.numberPad)
                    TextField("镜像地址（可选）", text: $url).textInputAutocapitalization(.never).keyboardType(.URL)
                }
                Section("凭据") {
                    TextField("用户 ID（可选）", text: $userID).textInputAutocapitalization(.never)
                    TextField("用户名（可选）", text: $username).textInputAutocapitalization(.never)
                    TextField("Cookie", text: $cookie, axis: .vertical).lineLimit(3...6)
                    TextField("User-Agent（可选）", text: $userAgent)
                    TextField("邮箱（可选）", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("Passkey（可选）", text: $passkey)
                    TextField("Authkey（可选）", text: $authkey)
                    TextField("LocalStorage JSON（可选）", text: $localStorage, axis: .vertical).lineLimit(3...8).font(.system(.caption, design: .monospaced))
                }
                Section("地址与标签") {
                    TextField("RSS 地址（可选）", text: $rss).textInputAutocapitalization(.never).keyboardType(.URL)
                    TextField("种子页地址（可选）", text: $torrentsURL).textInputAutocapitalization(.never).keyboardType(.URL)
                    TextField("代理地址（可选）", text: $proxy).textInputAutocapitalization(.never).keyboardType(.URL)
                    TextField("标签，使用逗号分隔", text: $tags)
                }
                Section("能力") {
                    Toggle("站点可用", isOn: $enabled)
                    Toggle("获取数据", isOn: $getInfo)
                    Toggle("参与签到", isOn: $signin)
                    Toggle("参与辅种", isOn: $repeatTorrents)
                    Toggle("允许搜索", isOn: $searchTorrents)
                    Toggle("抓取免费种", isOn: $brushFree)
                    Toggle("抓取 RSS", isOn: $brushRSS)
                    Toggle("识别 HR", isOn: $hrDiscern)
                    Toggle("打包种子文件", isOn: $packageFile)
                    Toggle("显示在仪表盘", isOn: $showInDashboard)
                }
            }
            .navigationTitle(site == nil ? "添加站点" : "编辑站点").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task {
                    var body = site?.raw ?? [:]
                    body["id"] = site?.id ?? 0
                    body["site"] = siteKey
                    body["nickname"] = name
                    body["sort_id"] = Int(sortID.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
                    body["mirror"] = nullableText(url)
                    body["user_id"] = nullableText(userID)
                    body["username"] = nullableText(username)
                    body["cookie"] = cookie
                    body["user_agent"] = userAgent
                    body["email"] = nullableText(email)
                    body["passkey"] = nullableText(passkey)
                    body["authkey"] = nullableText(authkey)
                    body["local_storage"] = localStorage
                    body["rss"] = nullableText(rss)
                    body["torrents"] = nullableText(torrentsURL)
                    body["proxy"] = nullableText(proxy)
                    body["tags"] = tags.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    body["available"] = enabled
                    body["get_info"] = getInfo
                    body["sign_in"] = signin
                    body["repeat_torrents"] = repeatTorrents
                    body["search_torrents"] = searchTorrents
                    body["brush_free"] = brushFree
                    body["brush_rss"] = brushRSS
                    body["package_file"] = packageFile
                    body["hr_discern"] = hrDiscern
                    body["show_in_dash"] = showInDashboard
                    let path = site.map { "\(APIPath.sites)/\($0.id)" } ?? APIPath.sites
                    let method: HTTPMethod = site == nil ? .post : .put
                    if await appState.perform(path, method: method, body: body) { await onSaved(); dismiss() }
                } }.disabled(siteKey.isEmpty || name.isEmpty) }
            }
            .task {
                guard site == nil, availableSites.isEmpty else { return }
                async let namesResult = loadSiteEditorValue(APIPath.websiteToAdd)
                async let configsResult = loadSiteEditorValue(APIPath.websiteList)
                let values = await (namesResult, configsResult)
                if let names = values.0.value { availableSites = jsonStrings(names) }
                if let configs = values.1.value {
                    var configMap: [String: [String: Any]] = [:]
                    for config in jsonRows(configs) {
                        if let key = config.string("name", "site"), !key.isEmpty { configMap[key] = config }
                    }
                    availableConfigs = configMap
                }
                if siteKey.isEmpty { siteKey = availableSites.first ?? "" }
                applyConfigDefaults(siteKey)
                let errors = [values.0.errorMessage, values.1.errorMessage].compactMap { $0 }
                if !errors.isEmpty { appState.presentedError = errors.joined(separator: "\n") }
            }
        }
    }

    @MainActor private func loadSiteEditorValue(_ path: String) async -> (value: Any?, errorMessage: String?) {
        do { return (try await appState.api(path), nil) }
        catch { return (nil, error.localizedDescription) }
    }

    private func applyConfigDefaults(_ key: String) {
        guard site == nil, let config = availableConfigs[key] else {
            if site == nil, name.isEmpty { name = key }
            return
        }
        name = config.string("nickname", "name") ?? key
        if url.isEmpty { url = config.strings("url").first ?? config.string("url") ?? "" }
        signin = config.bool("sign_in", "signIn") ?? signin
        getInfo = config.bool("get_info", "getInfo") ?? getInfo
        repeatTorrents = config.bool("repeat_torrents", "repeatTorrents") ?? repeatTorrents
        searchTorrents = config.bool("search_torrents", "searchTorrents") ?? searchTorrents
        brushFree = config.bool("brush_free", "brushFree") ?? brushFree
        brushRSS = config.bool("brush_rss", "brushRss") ?? brushRSS
        packageFile = config.bool("package_file", "packageFile") ?? packageFile
        hrDiscern = config.bool("hr_discern", "hrDiscern") ?? hrDiscern
    }

    private func nullableText(_ value: String) -> Any {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? NSNull() : normalized
    }
}

struct DownloaderItem: Identifiable {
    let id: Int
    var name: String
    var category: String
    var networkProtocol: String
    var host: String
    var externalHost: String
    var port: Int
    var username: String
    var password: String
    var enabled: Bool
    var brush: Bool
    var sortID: Int
    var torrentPath: String
    var main: Bool
    var uploadSpeed: Double
    var downloadSpeed: Double
    var activeTorrentCount: Int
    var pausedTorrentCount: Int
    var totalTorrentCount: Int
    var freeSpace: Double
    var uploadedSession: Double
    var downloadedSession: Double
    var uploadLimit: Double
    var downloadLimit: Double
    var alternativeSpeedEnabled: Bool
    var connectionStatus: String
    var version: String
    var hasLiveStatus: Bool
    var raw: [String: Any]

    init(_ json: [String: Any]) {
        let envelope = json.dict("status") ?? [:]
        let payload = envelope.dict("data") ?? envelope
        let preferences = payload.dict("prefs", "preferences") ?? json.dict("prefs", "preferences") ?? [:]
        let status = payload.dict("info", "status", "server_state") ?? payload
        let currentStats = status.dict("current-stats", "currentStats") ?? [:]
        id = json.int("id") ?? abs((json.string("name") ?? UUID().uuidString).hashValue)
        name = json.string("name", "nickname", "title") ?? "下载器"
        category = json.string("category", "type", "client") ?? "qBittorrent"
        networkProtocol = json.string("protocol") ?? "http"
        host = json.string("host", "external_host", "url") ?? ""
        externalHost = json.string("external_host", "externalHost") ?? ""
        port = json.int("port") ?? 0
        username = json.string("username") ?? ""
        password = json.string("password") ?? ""
        enabled = json.bool("enable", "enabled", "is_active") ?? true
        brush = json.bool("brush") ?? false
        sortID = json.int("sort_id", "sortId") ?? 0
        torrentPath = json.string("torrent_path", "torrentPath") ?? ""
        main = json.bool("main", "is_main", "default") ?? false
        uploadSpeed = status.double("uploadSpeed", "upload_speed", "up_info_speed") ?? json.double("upload_speed", "up_speed", "upspeed") ?? 0
        downloadSpeed = status.double("downloadSpeed", "download_speed", "dl_info_speed") ?? json.double("download_speed", "down_speed", "dlspeed") ?? 0
        activeTorrentCount = status.int("activeTorrentCount", "active_torrent_count") ?? 0
        pausedTorrentCount = status.int("pausedTorrentCount", "paused_torrent_count") ?? 0
        totalTorrentCount = status.int("torrentCount", "torrent_count", "totalTorrentCount") ?? 0
        freeSpace = downloaderFreeSpace(status) ?? downloaderFreeSpace(preferences) ?? 0
        uploadedSession = status.double("up_info_data", "uploadedSession", "uploadedBytes")
            ?? currentStats.double("uploadedBytes", "uploaded_bytes") ?? 0
        downloadedSession = status.double("dl_info_data", "downloadedSession", "downloadedBytes")
            ?? currentStats.double("downloadedBytes", "downloaded_bytes") ?? 0
        uploadLimit = status.double("up_rate_limit", "uploadLimit") ?? preferences.double("up_limit", "speed-limit-up", "alt-speed-up") ?? 0
        downloadLimit = status.double("dl_rate_limit", "downloadLimit") ?? preferences.double("dl_limit", "speed-limit-down", "alt-speed-down") ?? 0
        alternativeSpeedEnabled = status.bool("use_alt_speed_limits", "alternativeSpeedEnabled", "alt-speed-enabled", "slow_mode")
            ?? preferences.bool("use_alt_speed_limits", "alternativeSpeedEnabled", "alt-speed-enabled") ?? false
        connectionStatus = status.string("connection_status", "connectionStatus") ?? ""
        version = downloaderVersion(status, preferences: preferences)
        hasLiveStatus = !status.isEmpty
        raw = json
    }
}

private func downloaderFreeSpace(_ dictionary: [String: Any]) -> Double? {
    let keys = [
        "free_space_on_disk", "freeSpaceOnDisk", "free_space", "freeSpace",
        "download-dir-free-space", "downloadDirFreeSpace", "download_dir_free_space",
        "freeSpaceBytes", "free_space_bytes", "disk_free_space", "availableSpace"
    ]
    if let value = keys.compactMap({ dictionary.double($0) }).first { return value }
    for value in dictionary.values {
        if let nested = value as? [String: Any], let result = downloaderFreeSpace(nested), result > 0 { return result }
        if let rows = value as? [[String: Any]] {
            for row in rows {
                if let result = downloaderFreeSpace(row), result > 0 { return result }
            }
        }
    }
    return nil
}

private func downloaderVersion(_ status: [String: Any], preferences: [String: Any]) -> String {
    let candidates = [
        status.string("version", "app_version", "appVersion", "qb_version", "qbVersion"),
        preferences.string("version", "app_version", "appVersion", "qb_version", "qbVersion")
    ]
    guard var value = candidates.compactMap({ $0 }).first?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return "" }
    if let separator = value.firstIndex(of: " ") { value = String(value[..<separator]) }
    return value.lowercased().hasPrefix("v") ? value : "v" + value
}

enum TorrentSortField: String, CaseIterable, Identifiable {
    case name = "名称"
    case size = "大小"
    case progress = "进度"
    case downloadSpeed = "下载速度"
    case uploadSpeed = "上传速度"
    case ratio = "分享率"
    var id: String { rawValue }
}

struct ExportedTorrentFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

private func decodedTorrentFile(_ raw: Data) -> Data? {
    if raw.first == Character("d").asciiValue { return raw }
    guard let value = try? JSONSerialization.jsonObject(with: raw, options: [.fragmentsAllowed]) else { return nil }
    return decodedTorrentFile(value)
}

private func decodedTorrentFile(_ value: Any) -> Data? {
    if let data = value as? Data, data.first == Character("d").asciiValue { return data }
    if let bytes = value as? [NSNumber] {
        let data = Data(bytes.map { $0.uint8Value })
        return data.first == Character("d").asciiValue ? data : nil
    }
    if let text = value as? String {
        let payload = text.contains(",") ? String(text.split(separator: ",", maxSplits: 1).last ?? "") : text
        if let data = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters]), data.first == Character("d").asciiValue {
            return data
        }
        let data = Data(text.utf8)
        return data.first == Character("d").asciiValue ? data : nil
    }
    if let dictionary = value as? [String: Any] {
        for key in ["torrent", "torrent_file", "torrentFile", "content", "file", "base64", "data", "result"] {
            if let nested = dictionary[key], let data = decodedTorrentFile(nested) { return data }
        }
    }
    return nil
}

private func torrentFileName(_ preferred: String?, fallback: String) -> String {
    let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
    let source = (preferred?.isEmpty == false ? preferred! : fallback)
    var name = source.components(separatedBy: invalid).joined(separator: "_")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty { name = "torrent" }
    if !name.lowercased().hasSuffix(".torrent") { name += ".torrent" }
    return name
}

struct TorrentItem: Identifiable, @unchecked Sendable {
    let id: String
    var torrentHash: String
    var numericID: Int
    var name: String
    var downloaderID: Int
    var downloaderCategory: String
    var status: String
    var progress: Double
    var size: Double
    var uploadSpeed: Double
    var downloadSpeed: Double
    var ratio: Double
    var category: String
    var tags: [String]
    var savePath: String
    var tracker: String
    var trackerURLs: [String]
    var siteHint: String
    var magnetLink: String
    var errorText: String
    var hasError: Bool
    var forceStart: Bool
    var autoManaged: Bool
    var superSeeding: Bool
    var raw: [String: Any]

    init(_ json: [String: Any]) {
        numericID = json.int("id", "torrent_id") ?? 0
        torrentHash = json.string("hashString", "hash_string", "hash", "infohash_v1", "torrent_hash") ?? (numericID > 0 ? String(numericID) : UUID().uuidString)
        name = json.string("name", "title") ?? "未命名任务"
        downloaderID = json.int("downloader_id", "downloader", "client_id") ?? 0
        id = "\(downloaderID):\(torrentHash)"
        downloaderCategory = json.string("downloader_category", "client_type") ?? "Qb"
        status = torrentStatusLabel(json.string("state", "status") ?? "unknown", client: downloaderCategory)
        let rawProgress = json.double("percentDone", "percentComplete", "percent_done", "progress", "completed") ?? 0
        progress = rawProgress > 1 ? rawProgress / 100 : rawProgress
        size = json.double("sizeWhenDone", "totalSize", "size", "total_size", "length") ?? 0
        uploadSpeed = json.double("rateUpload", "upspeed", "upload_speed", "rate_upload") ?? 0
        downloadSpeed = json.double("rateDownload", "dlspeed", "download_speed", "rate_download") ?? 0
        ratio = json.double("uploadRatio", "ratio", "upload_ratio") ?? 0
        category = json.string("category", "label") ?? ""
        tags = json.strings("tags", "labels")
        if tags.isEmpty, let text = json.string("tags", "labels") {
            tags = text.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        savePath = json.string("save_path", "savePath", "downloadDir", "download_dir") ?? ""
        let trackerRows = json.rows("trackers", "trackerStats", "tracker_stats")
        trackerURLs = trackerRows.compactMap { $0.string("announce", "url", "tracker", "host") }
        if let direct = json.string("tracker", "tracker_url", "trackerUrl", "announce"), !direct.isEmpty {
            trackerURLs.insert(direct, at: 0)
        }
        var seenTrackers: Set<String> = []
        trackerURLs = trackerURLs.filter { seenTrackers.insert($0).inserted }
        tracker = trackerURLs.first ?? ""
        siteHint = json.string("site", "site_name", "siteName")
            ?? trackerRows.compactMap { $0.string("sitename", "site_name", "siteName") }.first
            ?? ""
        magnetLink = json.string("magnetLink", "magnet_link", "magnet_uri", "magnet") ?? ""
        errorText = json.string("errorString", "error_string", "error_message") ?? ""
        if errorText.isEmpty {
            errorText = trackerRows.first(where: {
                $0.bool("lastAnnounceSucceeded", "last_announce_succeeded") == false
                    && !($0.string("lastAnnounceResult", "last_announce_result") ?? "").isEmpty
            })?.string("lastAnnounceResult", "last_announce_result") ?? ""
        }
        hasError = (json.int("error", "error_code") ?? 0) != 0
            || !errorText.isEmpty
            || (json.string("state") ?? "").lowercased().contains("error")
            || (json.string("state") ?? "").lowercased().contains("missing")
        forceStart = json.bool("force_start", "forceStart") ?? false
        autoManaged = json.bool("auto_tmm", "auto_managed", "autoManaged") ?? false
        superSeeding = json.bool("super_seeding", "superSeeding") ?? false
        raw = json
    }

    var copyMagnet: String {
        magnetLink.isEmpty ? "magnet:?xt=urn:btih:\(torrentHash)" : magnetLink
    }
}

private func torrentStatusLabel(_ value: String, client: String) -> String {
    guard client.lowercased().contains("tr"), let code = Int(value) else { return value }
    switch code {
    case 0: return "暂停"
    case 1, 2: return "校验中"
    case 3: return "等待下载"
    case 4: return "下载中"
    case 5: return "等待做种"
    case 6: return "做种"
    default: return value
    }
}

private enum DownloaderRefreshDefaults {
    static let enabledKey = "downloads.refresh.enabled"
    static let intervalKey = "downloads.refresh.interval"
    static let durationKey = "downloads.refresh.duration"
    static let interval = 5
    static let duration = 5
    static let range = 1...60
}

private struct TorrentDerivedState {
    var filtered: [TorrentItem] = []
    var categories: [String] = []
    var tags: [String] = []
    var sites: [String] = []
    var siteLabels: [String: String] = [:]
}

@MainActor
final class DownloadsViewModel: ObservableObject {
    @Published var downloaders: [DownloaderItem] = []
    private(set) var torrents: [TorrentItem] = [] {
        didSet { rebuildTorrentMetadata() }
    }
    private(set) var sites: [SiteItem] = [] {
        didSet {
            rebuildSiteIndex()
            rebuildTorrentMetadata()
        }
    }
    @Published var isLoading = true
    @Published var query = "" { didSet { rebuildFilteredTorrents() } }
    @Published var filter = "全部" { didSet { rebuildFilteredTorrents() } }
    @Published var downloaderFilter = 0 { didSet { rebuildFilteredTorrents() } }
    @Published var categoryFilter = "" { didSet { rebuildFilteredTorrents() } }
    @Published var tagFilters: Set<String> = [] { didSet { rebuildFilteredTorrents() } }
    @Published var siteFilter = "" { didSet { rebuildFilteredTorrents() } }
    @Published var sortField = TorrentSortField.name { didSet { rebuildFilteredTorrents() } }
    @Published var sortAscending = true { didSet { rebuildFilteredTorrents() } }
    @Published var socketConnections: Set<Int> = []
    @Published private(set) var refreshEnabled = true
    @Published private(set) var refreshPaused = false
    @Published private(set) var refreshInterval = DownloaderRefreshDefaults.interval
    @Published private(set) var refreshDuration = DownloaderRefreshDefaults.duration
    @Published private(set) var refreshDeadline: Date?
    @Published private(set) var cachedAt: Date?
    @Published private(set) var usingCachedData = false
    @Published private var derived = TorrentDerivedState()
    private var speedWatchTask: Task<Void, Never>?
    private var downloaderWatchTasks: [Int: Task<Void, Never>] = [:]
    private var downloaderWatchTokens: [Int: UUID] = [:]
    private var downloaderWatchSignatures: [Int: String] = [:]
    private var torrentSnapshotSignatures: [Int: Int] = [:]
    private var countdownTask: Task<Void, Never>?
    private var cacheWriteTask: Task<Void, Never>?
    private var isViewActive = false
    private var isWatching = false
    private var restoredCache = false
    private var siteHostLabels: [(host: String, label: String)] = []
    private var siteKeyLabels: [(key: String, label: String)] = []
    private let sessionCacheKey: String
    private let includesTorrentData: Bool

    init(includesTorrentData: Bool = true) {
        self.includesTorrentData = includesTorrentData
        self.sessionCacheKey = includesTorrentData
            ? "downloads.snapshot.v1"
            : "downloads.downloaders.snapshot.v1"
    }

    let statusFilters = ["全部", "下载中", "做种中", "等待中", "已暂停", "错误"]

    var availableCategories: [String] { derived.categories }

    var availableTags: [String] { derived.tags }

    var availableSites: [String] { derived.sites }

    var activeFilterCount: Int {
        (filter == "全部" ? 0 : 1)
            + (downloaderFilter == 0 ? 0 : 1)
            + (categoryFilter.isEmpty ? 0 : 1)
            + (tagFilters.isEmpty ? 0 : 1)
            + (siteFilter.isEmpty ? 0 : 1)
            + (sortField == .name && sortAscending ? 0 : 1)
    }

    var filtered: [TorrentItem] { derived.filtered }

    private func rebuildFilteredTorrents() {
        var next = derived
        next.filtered = makeFilteredTorrents(siteLabels: next.siteLabels)
        derived = next
    }

    private func makeFilteredTorrents(siteLabels: [String: String]) -> [TorrentItem] {
        var result = torrents.filter { item in
            let queryMatch = query.isEmpty || item.name.localizedCaseInsensitiveContains(query)
            let downloaderMatch = downloaderFilter == 0 || item.downloaderID == downloaderFilter
            let categoryMatch = categoryFilter.isEmpty || item.category == categoryFilter
            let tagMatch = tagFilters.isEmpty || item.tags.contains(where: tagFilters.contains)
            let siteMatch = siteFilter.isEmpty || siteLabels[item.id] == siteFilter
            return queryMatch && downloaderMatch && categoryMatch && tagMatch && siteMatch && matchesStatus(item)
        }
        result.sort { left, right in
            let comparison: Int
            switch sortField {
            case .name:
                comparison = left.name.localizedCaseInsensitiveCompare(right.name).rawValue
            case .size:
                comparison = left.size == right.size ? 0 : (left.size < right.size ? -1 : 1)
            case .progress:
                comparison = left.progress == right.progress ? 0 : (left.progress < right.progress ? -1 : 1)
            case .downloadSpeed:
                comparison = left.downloadSpeed == right.downloadSpeed ? 0 : (left.downloadSpeed < right.downloadSpeed ? -1 : 1)
            case .uploadSpeed:
                comparison = left.uploadSpeed == right.uploadSpeed ? 0 : (left.uploadSpeed < right.uploadSpeed ? -1 : 1)
            case .ratio:
                comparison = left.ratio == right.ratio ? 0 : (left.ratio < right.ratio ? -1 : 1)
            }
            if comparison == 0 { return left.id < right.id }
            return sortAscending ? comparison < 0 : comparison > 0
        }
        return result
    }

    private func rebuildTorrentMetadata() {
        var next = derived
        var labels: [String: String] = [:]
        labels.reserveCapacity(torrents.count)
        for torrent in torrents {
            let label = resolvedSiteLabel(for: torrent)
            if !label.isEmpty { labels[torrent.id] = label }
        }
        next.categories = Array(Set(torrents.lazy.map(\.category).filter { !$0.isEmpty })).sorted()
        next.tags = Array(Set(torrents.lazy.flatMap(\.tags))).sorted()
        next.siteLabels = labels
        next.sites = Array(Set(labels.values)).sorted()
        next.filtered = makeFilteredTorrents(siteLabels: labels)
        derived = next
    }

    private func rebuildSiteIndex() {
        var hostLabels: [(String, String)] = []
        var keyLabels: [(String, String)] = []
        for site in sites {
            for value in [site.url, site.torrentsURL, site.rss] {
                guard var host = URL(string: value)?.host?.lowercased(), !host.isEmpty else { continue }
                if host.hasPrefix("www.") { host.removeFirst(4) }
                hostLabels.append((host, site.name))
            }
            let key = site.siteKey.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { keyLabels.append((key, site.name)) }
        }
        siteHostLabels = hostLabels
        siteKeyLabels = keyLabels
    }

    func resetFilters() {
        filter = "全部"
        downloaderFilter = 0
        categoryFilter = ""
        tagFilters = []
        siteFilter = ""
        sortField = .name
        sortAscending = true
    }

    func load(_ appState: AppState) async {
        await restoreCacheIfNeeded(appState)
        isLoading = downloaders.isEmpty && torrents.isEmpty
        defer {
            isLoading = false
            reconcileWatching(appState)
        }
        do {
            let raw = try await appState.api(APIPath.downloaders, query: ["with_status": true])
            downloaders = jsonRows(raw).map(DownloaderItem.init)
            // The compact downloads screen only needs aggregate downloader status.
            guard includesTorrentData else {
                torrents = []
                sites = []
                usingCachedData = false
                cachedAt = nil
                await persistCache(appState)
                return
            }
            let previousTorrents = torrents
            var collected: [TorrentItem] = []
            var successfulDownloaderLoads = 0
            var firstDownloaderError: String?
            let enabledDownloaders = downloaders.filter(\.enabled)
            let loads = await withTaskGroup(of: (Int, Data?, String?).self) { group in
                for downloader in enabledDownloaders {
                    let downloaderID = downloader.id
                    group.addTask {
                        do {
                            let main = try await appState.api("\(APIPath.downloaderMain)\(downloaderID)")
                            guard JSONSerialization.isValidJSONObject(main),
                                  let data = try? JSONSerialization.data(withJSONObject: main) else {
                                return (downloaderID, nil, "下载器返回了无效数据")
                            }
                            return (downloaderID, data, nil)
                        } catch {
                            return (downloaderID, nil, error.localizedDescription)
                        }
                    }
                }
                var values: [(Int, Data?, String?)] = []
                for await value in group { values.append(value) }
                return values
            }
            let downloaderByID = Dictionary(uniqueKeysWithValues: enabledDownloaders.map { ($0.id, $0) })
            for (downloaderID, data, errorMessage) in loads {
                guard let downloader = downloaderByID[downloaderID] else { continue }
                if let data,
                   let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                    successfulDownloaderLoads += 1
                    collected.append(contentsOf: jsonRows(value).map {
                        var row = $0
                        row["downloader_id"] = downloader.id
                        row["downloader_category"] = downloader.category
                        return TorrentItem(row)
                    })
                } else {
                    firstDownloaderError = firstDownloaderError ?? errorMessage
                    collected.append(contentsOf: previousTorrents.filter { $0.downloaderID == downloader.id })
                }
            }
            torrents = collected
            if successfulDownloaderLoads == 0,
               downloaders.contains(where: \.enabled),
               let firstDownloaderError {
                if previousTorrents.isEmpty { appState.presentedError = firstDownloaderError }
                else { recordAppLog(.warning, "下载器实时数据不可用，继续显示缓存：\(firstDownloaderError)") }
            }
            if sites.isEmpty || usingCachedData {
                do {
                    let siteRaw = try await appState.api(APIPath.sites)
                    sites = jsonRows(siteRaw).map(SiteItem.init)
                } catch { }
            }
            usingCachedData = successfulDownloaderLoads < enabledDownloaders.count
            if !usingCachedData { cachedAt = nil }
            if !usingCachedData { await persistCache(appState) }
        } catch {
            usingCachedData = !downloaders.isEmpty || !torrents.isEmpty
            if usingCachedData {
                recordAppLog(.warning, "下载页刷新失败，继续显示缓存：\(error.localizedDescription)")
            } else {
                appState.presentedError = error.localizedDescription
            }
        }
    }

    private func restoreCacheIfNeeded(_ appState: AppState) async {
        guard !restoredCache else { return }
        restoredCache = true
        var cached = await appState.readSessionCache(sessionCacheKey)
        if cached == nil, !includesTorrentData {
            cached = await appState.readSessionCache("downloads.snapshot.v1")
        }
        guard let cached,
              let root = cached.value as? [String: Any] else { return }
        let cachedDownloaders = (root["downloaders"] as? [[String: Any]] ?? []).map(DownloaderItem.init)
        let cachedTorrents: [TorrentItem] = includesTorrentData
            ? (root["torrents"] as? [[String: Any]] ?? []).map(TorrentItem.init)
            : []
        let cachedSites: [SiteItem] = includesTorrentData
            ? (root["sites"] as? [[String: Any]] ?? []).map(SiteItem.init)
            : []
        guard !cachedDownloaders.isEmpty || !cachedTorrents.isEmpty else { return }
        downloaders = cachedDownloaders
        torrents = cachedTorrents
        sites = cachedSites
        cachedAt = cached.cachedAt
        usingCachedData = true
        isLoading = false
    }

    private func persistCache(_ appState: AppState) async {
        guard !downloaders.isEmpty || !torrents.isEmpty else { return }
        await appState.writeSessionCache(cacheSnapshot(), name: sessionCacheKey)
    }

    private func scheduleCachePersistence(_ appState: AppState) {
        guard cacheWriteTask == nil else { return }
        cacheWriteTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            await self.persistCache(appState)
            self.cacheWriteTask = nil
        }
    }

    private func cacheSnapshot() -> [String: Any] {
        [
            "downloaders": downloaders.map(downloaderCacheRow),
            "torrents": torrents.map(torrentCacheRow),
            "sites": sites.map(siteCacheRow)
        ]
    }

    private func downloaderCacheRow(_ item: DownloaderItem) -> [String: Any] {
        [
            "id": item.id,
            "name": item.name,
            "category": item.category,
            "protocol": item.networkProtocol,
            "host": item.host,
            "external_host": item.externalHost,
            "port": item.port,
            "enable": item.enabled,
            "brush": item.brush,
            "sort_id": item.sortID,
            "main": item.main,
            "status": [
                "uploadSpeed": item.uploadSpeed,
                "downloadSpeed": item.downloadSpeed,
                "activeTorrentCount": item.activeTorrentCount,
                "pausedTorrentCount": item.pausedTorrentCount,
                "torrentCount": item.totalTorrentCount,
                "freeSpace": item.freeSpace,
                "uploadedSession": item.uploadedSession,
                "downloadedSession": item.downloadedSession,
                "uploadLimit": item.uploadLimit,
                "downloadLimit": item.downloadLimit,
                "alternativeSpeedEnabled": item.alternativeSpeedEnabled,
                "connectionStatus": item.connectionStatus,
                "version": item.version
            ]
        ]
    }

    private func torrentCacheRow(_ item: TorrentItem) -> [String: Any] {
        [
            "id": item.numericID,
            "hash": item.torrentHash,
            "name": item.name,
            "downloader_id": item.downloaderID,
            "downloader_category": item.downloaderCategory,
            "state": item.status,
            "progress": item.progress,
            "size": item.size,
            "upload_speed": item.uploadSpeed,
            "download_speed": item.downloadSpeed,
            "ratio": item.ratio,
            "category": item.category,
            "tags": item.tags,
            "site": siteLabel(for: item),
            "error_string": item.errorText,
            "force_start": item.forceStart,
            "auto_tmm": item.autoManaged,
            "super_seeding": item.superSeeding
        ]
    }

    private func siteCacheRow(_ item: SiteItem) -> [String: Any] {
        [
            "id": item.id,
            "site": item.siteKey,
            "nickname": item.name,
            "mirror": item.url,
            "rss": item.rss,
            "torrents": item.torrentsURL,
            "icon": item.iconURL,
            "available": item.enabled
        ]
    }

    func exportTorrent(_ appState: AppState, torrent: TorrentItem) async -> ExportedTorrentFile? {
        guard !torrent.downloaderCategory.lowercased().contains("tr") else {
            appState.presentedError = "Transmission 不支持导出 .torrent 文件"
            return nil
        }
        do {
            let response = try await appState.download(
                APIPath.downloaderControl + "\(torrent.downloaderID)",
                method: .post,
                body: ["command": "export", "torrent_hash": torrent.torrentHash]
            )
            guard let data = decodedTorrentFile(response.data) else {
                throw APIError(statusCode: 0, message: "服务端未返回有效的 .torrent 文件")
            }
            let name = torrentFileName(response.fileName, fallback: torrent.name)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: [.atomic])
            return ExportedTorrentFile(url: url)
        } catch {
            appState.presentedError = error.localizedDescription
            return nil
        }
    }

    func siteLabel(for torrent: TorrentItem) -> String {
        derived.siteLabels[torrent.id] ?? resolvedSiteLabel(for: torrent)
    }

    private func resolvedSiteLabel(for torrent: TorrentItem) -> String {
        if !torrent.siteHint.isEmpty { return torrent.siteHint }
        let trackerText = torrent.trackerURLs.joined(separator: " ").lowercased()
        for tracker in torrent.trackerURLs {
            guard var host = URL(string: tracker)?.host?.lowercased(), !host.isEmpty else { continue }
            if host.hasPrefix("www.") { host.removeFirst(4) }
            if let match = siteHostLabels.first(where: { host == $0.host || host.hasSuffix(".\($0.host)") }) {
                return match.label
            }
        }
        if let match = siteKeyLabels.first(where: { trackerText.contains($0.key) }) {
            return match.label
        }
        for tracker in torrent.trackerURLs {
            if let host = URL(string: tracker)?.host, !host.isEmpty { return host }
        }
        return ""
    }

    private func matchesStatus(_ item: TorrentItem) -> Bool {
        let state = item.status.lowercased()
        switch filter {
        case "下载中":
            return state.contains("down") || state.contains("下载") || item.downloadSpeed > 0
        case "做种中":
            return state.contains("seed") || state.contains("upload") || state.contains("做种")
        case "等待中":
            return state.contains("wait") || state.contains("queue") || state.contains("check") || state.contains("等待") || state.contains("校验")
        case "已暂停":
            return state.contains("pause") || state.contains("stop") || state.contains("暂停") || state.contains("停止")
        case "错误":
            return item.hasError || state.contains("error") || state.contains("missing") || state.contains("错误")
        default:
            return true
        }
    }

    func control(
        _ appState: AppState,
        torrent: TorrentItem,
        command: String,
        deleteFilesWhenUnpreserved: Bool = false
    ) async {
        if command == "delete" {
            await deleteTorrents(
                appState,
                torrents: [torrent],
                deleteFilesWhenUnpreserved: deleteFilesWhenUnpreserved
            )
            return
        }
        let trCommand = command == "resume" ? "start_torrent" : "stop_torrent"
        await execute(appState, torrents: [torrent], qbCommand: command, trCommand: trCommand)
    }

    @discardableResult
    func execute(
        _ appState: AppState,
        torrents selected: [TorrentItem],
        qbCommand: String,
        trCommand: String,
        qbExtra: [String: Any] = [:],
        trExtra: [String: Any] = [:],
        reload: Bool = true
    ) async -> Bool {
        let grouped = Dictionary(grouping: selected) { $0.downloaderID }
        var succeeded = true
        for (downloaderID, items) in grouped where downloaderID > 0 {
            let isTransmission = items.first?.downloaderCategory.lowercased().contains("tr") == true
            var body: [String: Any] = isTransmission
                ? ["command": trCommand, "ids": items.map(\.torrentHash)]
                : ["command": qbCommand, "torrent_hashes": items.map(\.torrentHash)]
            for (key, value) in (isTransmission ? trExtra : qbExtra) { body[key] = value }
            let ok = await appState.perform(APIPath.downloaderControl + "\(downloaderID)", method: .post, body: body)
            succeeded = succeeded && ok
        }
        if succeeded && reload { await load(appState) }
        return succeeded
    }

    func deleteTorrents(
        _ appState: AppState,
        torrents selected: [TorrentItem],
        deleteFilesWhenUnpreserved: Bool
    ) async {
        let deletingIDs = Set(selected.map(\.id))
        let withFiles = selected.filter {
            deleteFilesWhenUnpreserved && !hasOtherPreservingSameContent($0, deletingIDs: deletingIDs)
        }
        let withFilesIDs = Set(withFiles.map(\.id))
        let metadataOnly = selected.filter { !withFilesIDs.contains($0.id) }
        var succeeded = true
        if !metadataOnly.isEmpty {
            let result = await execute(
                appState,
                torrents: metadataOnly,
                qbCommand: "delete",
                trCommand: "remove_torrent",
                qbExtra: ["delete_files": false],
                trExtra: ["delete_data": false],
                reload: false
            )
            succeeded = succeeded && result
        }
        if !withFiles.isEmpty {
            let result = await execute(
                appState,
                torrents: withFiles,
                qbCommand: "delete",
                trCommand: "remove_torrent",
                qbExtra: ["delete_files": true],
                trExtra: ["delete_data": true],
                reload: false
            )
            succeeded = succeeded && result
        }
        if succeeded { await load(appState) }
    }

    private func hasOtherPreservingSameContent(_ target: TorrentItem, deletingIDs: Set<String>) -> Bool {
        let targetKey = normalizedContentKey(target)
        guard !targetKey.isEmpty else { return false }
        return torrents.contains { candidate in
            guard !deletingIDs.contains(candidate.id), normalizedContentKey(candidate) == targetKey else { return false }
            let state = candidate.status.lowercased()
            return candidate.progress >= 0.999 || state.contains("seed") || state.contains("upload")
                || state.contains("complete") || state.contains("finish") || state.contains("做种")
        }
    }

    private func normalizedContentKey(_ torrent: TorrentItem) -> String {
        let direct = torrent.raw.string("content_path", "contentPath")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let value = direct.isEmpty ? "\(torrent.savePath)/\(torrent.name)" : direct
        var normalized = value.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.count > 1 && normalized.hasSuffix("/") { normalized.removeLast() }
        return normalized.lowercased()
    }

    func replaceTrackers(_ appState: AppState, torrents selected: [TorrentItem], tracker: String) async {
        let grouped = Dictionary(grouping: selected.filter { !$0.downloaderCategory.lowercased().contains("tr") }) { $0.downloaderID }
        var succeeded = true
        for (downloaderID, items) in grouped where downloaderID > 0 {
            let ok = await appState.perform(
                APIPath.downloaderReplaceTrackers + "\(downloaderID)",
                method: .put,
                body: ["torrent_hashes": items.map(\.torrentHash), "new_tracker": tracker]
            )
            succeeded = succeeded && ok
        }
        if succeeded { await load(appState) }
    }

    func toggle(_ appState: AppState, downloader: DownloaderItem) async {
        var body = downloader.raw
        body["is_active"] = !downloader.enabled
        if await appState.perform("\(APIPath.downloaders)/\(downloader.id)", method: .put, body: body) {
            await load(appState)
        }
    }

    func toggleBrush(_ appState: AppState, downloader: DownloaderItem) async {
        var body = downloader.raw
        body["brush"] = !downloader.brush
        if await appState.perform("\(APIPath.downloaders)/\(downloader.id)", method: .put, body: body) {
            await load(appState)
        }
    }

    func remove(_ appState: AppState, downloader: DownloaderItem) async {
        if await appState.perform("\(APIPath.downloaders)/\(downloader.id)", method: .delete) {
            downloaders.removeAll { $0.id == downloader.id }
            torrents.removeAll { $0.downloaderID == downloader.id }
            if downloaderFilter == downloader.id { downloaderFilter = 0 }
            reconcileWatching(appState)
            scheduleCachePersistence(appState)
        }
    }

    func repeatTorrents(_ appState: AppState, downloader: DownloaderItem) async {
        _ = await appState.perform("\(APIPath.downloaderRepeat)/\(downloader.id)", method: .get)
    }

    func refreshCountdownText(at date: Date = Date()) -> String {
        let remaining = max(0, Int((refreshDeadline?.timeIntervalSince(date) ?? 0).rounded(.up)))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    func startWatching(
        _ appState: AppState,
        enabled: Bool,
        interval: Int,
        duration: Int
    ) {
        isViewActive = true
        updateRefreshConfiguration(
            appState,
            enabled: enabled,
            interval: interval,
            duration: duration
        )
        if refreshEnabled && !refreshPaused && !isWatching {
            beginWatching(appState)
        }
    }

    func stopWatching() {
        isViewActive = false
        stopActiveWatching(clearRemaining: true)
    }

    func updateRefreshConfiguration(
        _ appState: AppState,
        enabled: Bool,
        interval: Int,
        duration: Int
    ) {
        let normalizedInterval = min(max(interval, DownloaderRefreshDefaults.range.lowerBound), DownloaderRefreshDefaults.range.upperBound)
        let normalizedDuration = min(max(duration, DownloaderRefreshDefaults.range.lowerBound), DownloaderRefreshDefaults.range.upperBound)
        let changed = refreshEnabled != enabled
            || refreshInterval != normalizedInterval
            || refreshDuration != normalizedDuration

        refreshEnabled = enabled
        refreshInterval = normalizedInterval
        refreshDuration = normalizedDuration
        guard isViewActive, changed else { return }

        if enabled && !refreshPaused {
            beginWatching(appState)
        } else {
            stopActiveWatching(clearRemaining: true)
        }
    }

    func toggleRefreshPause(_ appState: AppState) {
        guard refreshEnabled, isViewActive else { return }
        refreshPaused.toggle()
        if refreshPaused {
            stopActiveWatching(clearRemaining: true)
        } else {
            beginWatching(appState)
        }
    }

    private func beginWatching(_ appState: AppState) {
        stopActiveWatching(clearRemaining: false)
        guard isViewActive, refreshEnabled, !refreshPaused else { return }
        isWatching = true
        refreshDeadline = Date().addingTimeInterval(TimeInterval(refreshDuration * 60))
        reconcileWatching(appState)
        countdownTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: .seconds(self.refreshDuration * 60)) }
            catch { return }
            guard self.isWatching else { return }
            self.refreshPaused = true
            self.stopActiveWatching(clearRemaining: true)
        }
    }

    private func stopActiveWatching(clearRemaining: Bool) {
        isWatching = false
        countdownTask?.cancel()
        countdownTask = nil
        speedWatchTask?.cancel()
        speedWatchTask = nil
        downloaderWatchTasks.values.forEach { $0.cancel() }
        downloaderWatchTasks = [:]
        downloaderWatchTokens = [:]
        downloaderWatchSignatures = [:]
        torrentSnapshotSignatures = [:]
        socketConnections = []
        if clearRemaining { refreshDeadline = nil }
    }

    private func reconcileWatching(_ appState: AppState) {
        guard isWatching else { return }
        if speedWatchTask == nil || speedWatchTask?.isCancelled == true {
            speedWatchTask = Task { [weak self] in
                await self?.watchDownloaderSpeeds(appState)
            }
        }

        guard includesTorrentData else {
            downloaderWatchTasks.values.forEach { $0.cancel() }
            downloaderWatchTasks = [:]
            downloaderWatchTokens = [:]
            downloaderWatchSignatures = [:]
            torrentSnapshotSignatures = [:]
            socketConnections = []
            return
        }

        let enabledDownloaders = downloaders.filter(\.enabled)
        let enabledIDs = Set(enabledDownloaders.map(\.id))
        for id in Set(downloaderWatchTasks.keys).subtracting(enabledIDs) {
            downloaderWatchTasks[id]?.cancel()
            downloaderWatchTasks[id] = nil
            downloaderWatchTokens[id] = nil
            downloaderWatchSignatures[id] = nil
            socketConnections.remove(id)
        }

        for downloader in enabledDownloaders {
            let signature = "\(downloader.id)|\(downloader.category)"
            guard downloaderWatchTasks[downloader.id] == nil
                    || downloaderWatchTasks[downloader.id]?.isCancelled == true
                    || downloaderWatchSignatures[downloader.id] != signature else { continue }
            downloaderWatchTasks[downloader.id]?.cancel()
            socketConnections.remove(downloader.id)
            let token = UUID()
            downloaderWatchTokens[downloader.id] = token
            downloaderWatchSignatures[downloader.id] = signature
            downloaderWatchTasks[downloader.id] = Task { [weak self] in
                await self?.watchDownloader(appState, downloader: downloader, token: token)
            }
        }
    }

    private func watchDownloaderSpeeds(_ appState: AppState) async {
        while isWatching && !Task.isCancelled {
            do {
                let stream = APIClient.shared.streamWebSocket(
                    baseURL: appState.baseURL,
                    path: APIPath.downloaderSpeed,
                    token: appState.accessToken,
                    subscription: ["interval": refreshInterval]
                )
                for try await event in stream {
                    guard isWatching, !Task.isCancelled else { return }
                    let data = (event["data"] as? [String: Any]) ?? jsonPayloadDictionary(event) ?? [:]
                    guard !data.isEmpty else { continue }
                    var liveByKey: [String: [String: Any]] = [:]
                    for (key, value) in data {
                        if let value = value as? [String: Any] { liveByKey[key.lowercased()] = value }
                    }
                    var updated = downloaders
                    var changed = false
                    for index in updated.indices {
                        let downloader = updated[index]
                        let websocketKey = "\(downloader.name)-\(downloader.id)-\(downloader.category)".lowercased()
                        guard let live = liveByKey[websocketKey] ?? liveByKey[String(downloader.id)] else { continue }
                        var merged = downloader.raw
                        merged["status"] = live
                        let next = DownloaderItem(merged)
                        guard downloaderLiveSignature(next) != downloaderLiveSignature(downloader) else { continue }
                        updated[index] = next
                        changed = true
                    }
                    if changed { downloaders = updated }
                }
            } catch { }
            if isWatching && !Task.isCancelled { try? await Task.sleep(for: .seconds(3)) }
        }
    }

    private func watchDownloader(_ appState: AppState, downloader: DownloaderItem, token: UUID) async {
        while isCurrentWatch(downloader.id, token: token) && !Task.isCancelled {
            do {
                let stream = APIClient.shared.streamWebSocket(
                    baseURL: appState.baseURL,
                    path: APIPath.downloaderTorrents,
                    token: appState.accessToken,
                    subscription: ["downloader_id": downloader.id, "interval": refreshInterval]
                )
                var receivedFrame = false
                for try await event in stream {
                    guard isCurrentWatch(downloader.id, token: token), !Task.isCancelled else { return }
                    if !receivedFrame {
                        receivedFrame = true
                        socketConnections.insert(downloader.id)
                    }
                    let payload = jsonPayloadDictionary(event) ?? event
                    guard JSONSerialization.isValidJSONObject(payload),
                          let payloadData = try? JSONSerialization.data(withJSONObject: payload) else { continue }
                    let downloaderID = downloader.id
                    let downloaderCategory = downloader.category
                    let incoming = await Task.detached(priority: .utility) {
                        guard let value = try? JSONSerialization.jsonObject(with: payloadData, options: [.fragmentsAllowed]) else {
                            return [TorrentItem]()
                        }
                        return jsonRows(value).map {
                            var row = $0
                            row["downloader_id"] = downloaderID
                            row["downloader_category"] = downloaderCategory
                            return TorrentItem(row)
                        }
                    }.value
                    guard !incoming.isEmpty else { continue }
                    let signature = torrentSnapshotSignature(incoming)
                    guard torrentSnapshotSignatures[downloader.id] != signature else { continue }
                    torrentSnapshotSignatures[downloader.id] = signature
                    var updated = torrents.filter { $0.downloaderID != downloader.id }
                    updated.append(contentsOf: incoming)
                    torrents = updated
                    scheduleCachePersistence(appState)
                }
                if isCurrentWatch(downloader.id, token: token) { socketConnections.remove(downloader.id) }
            } catch {
                if isCurrentWatch(downloader.id, token: token) { socketConnections.remove(downloader.id) }
            }
            if isCurrentWatch(downloader.id, token: token), !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func isCurrentWatch(_ downloaderID: Int, token: UUID) -> Bool {
        isWatching && downloaderWatchTokens[downloaderID] == token
    }

    private func downloaderLiveSignature(_ item: DownloaderItem) -> Int {
        var hasher = Hasher()
        hasher.combine(item.uploadSpeed)
        hasher.combine(item.downloadSpeed)
        hasher.combine(item.activeTorrentCount)
        hasher.combine(item.pausedTorrentCount)
        hasher.combine(item.totalTorrentCount)
        hasher.combine(item.freeSpace)
        hasher.combine(item.uploadedSession)
        hasher.combine(item.downloadedSession)
        hasher.combine(item.uploadLimit)
        hasher.combine(item.downloadLimit)
        hasher.combine(item.alternativeSpeedEnabled)
        hasher.combine(item.connectionStatus)
        hasher.combine(item.version)
        return hasher.finalize()
    }

    private func torrentSnapshotSignature(_ items: [TorrentItem]) -> Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        for item in items {
            hasher.combine(item.id)
            hasher.combine(item.status)
            hasher.combine(item.progress)
            hasher.combine(item.uploadSpeed)
            hasher.combine(item.downloadSpeed)
            hasher.combine(item.ratio)
            hasher.combine(item.category)
            hasher.combine(item.tags)
            hasher.combine(item.errorText)
        }
        return hasher.finalize()
    }
}

struct DownloadsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = DownloadsViewModel(includesTorrentData: false)
    @AppStorage(DownloaderRefreshDefaults.enabledKey) private var refreshEnabled = true
    @AppStorage(DownloaderRefreshDefaults.intervalKey) private var refreshInterval = DownloaderRefreshDefaults.interval
    @AppStorage(DownloaderRefreshDefaults.durationKey) private var refreshDuration = DownloaderRefreshDefaults.duration
    @State private var showAddTorrent = false
    @State private var addTorrentDownloaderID = 0
    @State private var showAddDownloader = false
    @State private var editingDownloader: DownloaderItem?
    @State private var settingsDownloader: DownloaderItem?
    @State private var toolsDownloader: DownloaderItem?
    @State private var deletingDownloader: DownloaderItem?
    @State private var repeatingDownloader: DownloaderItem?
    @State private var showRefreshSettings = false

    var body: some View {
        ScrollView {
            if model.isLoading { LoadingState() }
            else {
                LazyVStack(spacing: 16) {
                    if model.usingCachedData {
                        SessionCacheBanner(cachedAt: model.cachedAt)
                            .padding(.horizontal, 16)
                    }
                    if model.downloaders.isEmpty {
                        EmptyState(
                            icon: "externaldrive.badge.plus",
                            title: "暂无下载器",
                            detail: "添加下载器后，这里会显示连接状态、速度和空间信息。",
                            actionTitle: "添加下载器"
                        ) {
                            showAddDownloader = true
                        }
                        .frame(minHeight: 260)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(model.downloaders) { downloader in
                                DownloaderCard(
                                    item: downloader,
                                    onAddTorrent: {
                                        addTorrentDownloaderID = downloader.id
                                        showAddTorrent = true
                                    },
                                    onEdit: { editingDownloader = downloader },
                                    onSettings: { settingsDownloader = downloader },
                                    onTools: { toolsDownloader = downloader },
                                    onToggle: { Task { await model.toggle(appState, downloader: downloader) } },
                                    onToggleBrush: { Task { await model.toggleBrush(appState, downloader: downloader) } },
                                    onRepeat: { repeatingDownloader = downloader },
                                    onDelete: { deletingDownloader = downloader }
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }.padding(.vertical, 12)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable { await model.load(appState) }
        .navigationTitle("下载")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { Task { await model.load(appState) } } label: {
                    Image(systemName: "arrow.clockwise")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("刷新下载器")
                .help("刷新下载器")
                Button { model.toggleRefreshPause(appState) } label: {
                    Image(systemName: model.refreshPaused ? "play.fill" : "pause.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(!model.refreshEnabled)
                .accessibilityLabel(model.refreshPaused ? "恢复自动刷新" : "暂停自动刷新")
                .help(model.refreshPaused ? "恢复自动刷新" : "暂停自动刷新")
                Menu {
                    Button { showRefreshSettings = true } label: { Label("刷新设置", systemImage: "gearshape") }
                    Button { showAddDownloader = true } label: { Label("添加下载器", systemImage: "externaldrive.badge.plus") }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("下载器操作")
            }
        }
        .task {
            if model.isLoading { await model.load(appState) }
            model.startWatching(
                appState,
                enabled: refreshEnabled,
                interval: refreshInterval,
                duration: refreshDuration
            )
        }
        .onDisappear { model.stopWatching() }
        .onChange(of: refreshEnabled) { _, _ in synchronizeRefreshSettings() }
        .onChange(of: refreshInterval) { _, _ in synchronizeRefreshSettings() }
        .onChange(of: refreshDuration) { _, _ in synchronizeRefreshSettings() }
        .sheet(isPresented: $showAddTorrent) {
            AddTorrentSheet(
                downloaders: model.downloaders,
                initialDownloaderID: addTorrentDownloaderID > 0 ? addTorrentDownloaderID : nil,
                onSaved: { await model.load(appState) }
            )
            .environmentObject(appState)
        }
        .sheet(isPresented: $showAddDownloader) { DownloaderEditorSheet { await model.load(appState) }.environmentObject(appState) }
        .sheet(item: $editingDownloader) { downloader in DownloaderEditorSheet(downloader: downloader) { await model.load(appState) }.environmentObject(appState) }
        .sheet(item: $settingsDownloader) { downloader in DownloaderSettingsSheet(downloader: downloader).environmentObject(appState) }
        .sheet(item: $toolsDownloader) { downloader in DownloaderToolsSheet(downloader: downloader).environmentObject(appState) }
        .sheet(isPresented: $showRefreshSettings) {
            DownloaderRefreshSettingsSheet(
                enabled: $refreshEnabled,
                interval: $refreshInterval,
                duration: $refreshDuration
            )
        }
        .confirmationDialog(
            "确定删除下载器「\(deletingDownloader?.name ?? "")」？",
            isPresented: Binding(get: { deletingDownloader != nil }, set: { if !$0 { deletingDownloader = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除下载器", role: .destructive) {
                guard let downloader = deletingDownloader else { return }
                deletingDownloader = nil
                Task { await model.remove(appState, downloader: downloader) }
            }
            Button("取消", role: .cancel) { deletingDownloader = nil }
        } message: {
            Text("此操作不会删除下载器中的种子数据。")
        }
        .confirmationDialog(
            "确定让下载器「\(repeatingDownloader?.name ?? "")」执行辅种？",
            isPresented: Binding(get: { repeatingDownloader != nil }, set: { if !$0 { repeatingDownloader = nil } }),
            titleVisibility: .visible
        ) {
            Button("执行辅种") {
                guard let downloader = repeatingDownloader else { return }
                repeatingDownloader = nil
                Task { await model.repeatTorrents(appState, downloader: downloader) }
            }
            Button("取消", role: .cancel) { repeatingDownloader = nil }
        }
    }

    private func synchronizeRefreshSettings() {
        model.updateRefreshConfiguration(
            appState,
            enabled: refreshEnabled,
            interval: refreshInterval,
            duration: refreshDuration
        )
    }
}

struct DownloaderRefreshSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var enabled: Bool
    @Binding var interval: Int
    @Binding var duration: Int

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("自动刷新数据", isOn: $enabled)
                } footer: {
                    Text("关闭后停止下载器状态和速度的实时连接。")
                }

                if enabled {
                    Section("刷新间隔") {
                        refreshSlider(value: $interval, unit: "秒")
                    }
                    Section {
                        refreshSlider(value: $duration, unit: "分钟")
                    } header: {
                        Text("自动停止")
                    } footer: {
                        Text("到达设定时长后自动暂停，可在下载页手动恢复。")
                    }
                }
            }
            .navigationTitle("刷新设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private func refreshSlider(value: Binding<Int>, unit: String) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("1 \(unit)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(value.wrappedValue) \(unit)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Spacer()
                Text("60 \(unit)").font(.caption).foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: Double(DownloaderRefreshDefaults.range.lowerBound)...Double(DownloaderRefreshDefaults.range.upperBound),
                step: 1
            )
        }
        .padding(.vertical, 4)
    }
}

struct TorrentFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: DownloadsViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("范围") {
                    Picker("状态", selection: $model.filter) {
                        ForEach(model.statusFilters, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("下载器", selection: $model.downloaderFilter) {
                        Text("全部下载器").tag(0)
                        ForEach(model.downloaders) { Text($0.name).tag($0.id) }
                    }
                    if !model.availableCategories.isEmpty {
                        Picker("分类", selection: $model.categoryFilter) {
                            Text("全部分类").tag("")
                            ForEach(model.availableCategories, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    if !model.availableSites.isEmpty {
                        Picker("站点", selection: $model.siteFilter) {
                            Text("全部站点").tag("")
                            ForEach(model.availableSites, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }

                if !model.availableTags.isEmpty {
                    Section("标签") {
                        ForEach(model.availableTags, id: \.self) { tag in
                            Toggle(tag, isOn: Binding(
                                get: { model.tagFilters.contains(tag) },
                                set: { selected in
                                    if selected { model.tagFilters.insert(tag) }
                                    else { model.tagFilters.remove(tag) }
                                }
                            ))
                        }
                    }
                }

                Section("排序") {
                    Picker("字段", selection: $model.sortField) {
                        ForEach(TorrentSortField.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("方向", selection: $model.sortAscending) {
                        Text("升序").tag(true)
                        Text("降序").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("筛选与排序")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重置") { model.resetFilters() }
                        .disabled(model.activeFilterCount == 0)
                }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CompactFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0
        var contentHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = rowWidth == 0 ? size.width : rowWidth + spacing + size.width
            if rowWidth > 0 && nextWidth > maxWidth {
                contentWidth = max(contentWidth, rowWidth)
                contentHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth = nextWidth
                rowHeight = max(rowHeight, size.height)
            }
        }
        contentWidth = max(contentWidth, rowWidth)
        contentHeight += rowHeight
        return CGSize(width: min(maxWidth, contentWidth), height: contentHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct DownloaderCard: View {
    let item: DownloaderItem
    let onAddTorrent: () -> Void
    let onEdit: () -> Void
    let onSettings: () -> Void
    let onTools: () -> Void
    let onToggle: () -> Void
    let onToggleBrush: () -> Void
    let onRepeat: () -> Void
    let onDelete: () -> Void
    private var connected: Bool {
        let state = item.connectionStatus.lowercased()
        return item.hasLiveStatus && !state.contains("disconnected") && !state.contains("offline")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                SymbolBadge(
                    icon: item.category == "Tr" || item.category.lowercased().contains("trans")
                        ? "point.3.connected.trianglepath.dotted"
                        : "bolt.horizontal.circle.fill",
                    color: HarvestTheme.green,
                    size: 36
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.headline).lineLimit(1)
                    if !item.version.isEmpty { Text(item.version).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 6)
                Menu {
                    Button(action: onAddTorrent) { Label("添加种子", systemImage: "link.badge.plus") }
                    Divider()
                    Button(action: onEdit) { Label("编辑", systemImage: "pencil") }
                    Button(action: onSettings) { Label("下载器设置", systemImage: "slider.horizontal.3") }
                    Button(action: onTools) { Label("分类与标签", systemImage: "tag") }
                    if !item.brush {
                        Button(action: onRepeat) { Label("执行辅种", systemImage: "square.stack.3d.up") }
                    }
                    Button(action: onToggle) { Label(item.enabled ? "停用" : "启用", systemImage: item.enabled ? "pause" : "play") }
                    Button(action: onToggleBrush) { Label(item.brush ? "开启辅种" : "关闭辅种", systemImage: "bolt.horizontal") }
                    Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            Text("\(item.networkProtocol)://\(item.host)\(item.port > 0 ? ":\(item.port)" : "")").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            CompactFlowLayout(spacing: 7) {
                StatusPill(label: connected ? "已连接" : "未连接", color: connected ? HarvestTheme.green : HarvestTheme.coral)
                StatusPill(label: item.enabled ? "已启用" : "已停用", color: item.enabled ? HarvestTheme.blue : .secondary)
                StatusPill(label: item.brush ? "辅种关闭" : "辅种开启", color: item.brush ? .secondary : HarvestTheme.green)
                if item.main { StatusPill(label: "主下载器", color: HarvestTheme.amber) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                transferMetric("已下载", value: formatBytes(item.downloadedSession), speed: formatSpeed(item.downloadSpeed), icon: "arrow.down", color: HarvestTheme.blue)
                Divider().frame(height: 48)
                transferMetric("已上传", value: formatBytes(item.uploadedSession), speed: formatSpeed(item.uploadSpeed), icon: "arrow.up", color: HarvestTheme.green)
            }
            HStack(spacing: 7) {
                smallMetric("活跃", value: "\(item.activeTorrentCount)")
                smallMetric("总数", value: "\(item.totalTorrentCount)")
                smallMetric("剩余", value: item.freeSpace > 0 ? formatBytes(item.freeSpace) : "-")
            }
            if item.uploadLimit > 0 || item.downloadLimit > 0 || item.alternativeSpeedEnabled {
                HStack(spacing: 5) {
                    Image(systemName: "gauge.with.dots.needle.33percent").foregroundStyle(HarvestTheme.amber)
                    Text(item.alternativeSpeedEnabled ? "备用限速" : "速度限制")
                    Spacer()
                    if item.downloadLimit > 0 { Text("↓ \(formatSpeed(normalizedLimit(item.downloadLimit)))") }
                    if item.uploadLimit > 0 { Text("↑ \(formatSpeed(normalizedLimit(item.uploadLimit)))") }
                }
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
                .stroke(item.enabled ? HarvestTheme.green.opacity(0.25) : Color.primary.opacity(0.08))
        )
    }

    private func transferMetric(_ label: String, value: String, speed: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) { Image(systemName: icon); Text(label) }.font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(speed).font(.caption2.monospacedDigit()).foregroundStyle(color).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func smallMetric(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
    }

    private func normalizedLimit(_ value: Double) -> Double {
        item.category.lowercased().contains("tr") ? value * 1000 : value
    }
}

private struct ManagedDownloaderCategory: Identifiable {
    let name: String
    let savePath: String
    var id: String { name }
}

struct DownloaderToolsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let downloader: DownloaderItem
    @State private var tags: [String] = []
    @State private var categories: [ManagedDownloaderCategory] = []
    @State private var newTag = ""
    @State private var categoryName = ""
    @State private var categoryPath = ""
    @State private var editingCategory: String?
    @State private var speedLimited = false
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var testResult = ""
    @State private var deletingTag: String?
    @State private var deletingCategory: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("连接") {
                    Toggle("限速模式", isOn: $speedLimited)
                        .onChange(of: speedLimited) { oldValue, newValue in
                            guard !isLoading, oldValue != newValue else { return }
                            Task { await setSpeedMode(newValue) }
                        }
                    Button { Task { await testConnection() } } label: {
                        Label("测试下载器连接", systemImage: "network")
                    }
                    if !testResult.isEmpty { Text(testResult).font(.caption).foregroundStyle(.secondary) }
                }

                if !downloader.category.lowercased().contains("tr") {
                    Section("标签") {
                        ForEach(tags, id: \.self) { tag in
                            HStack { Label(tag, systemImage: "tag"); Spacer(); Button(role: .destructive) { deletingTag = tag } label: { Image(systemName: "trash") }.buttonStyle(.plain) }
                        }
                        HStack {
                            TextField("新标签", text: $newTag)
                            Button { Task { await addTag() } } label: { Image(systemName: "plus.circle.fill") }
                                .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    Section("分类") {
                        ForEach(categories) { category in
                            Button {
                                editingCategory = category.name
                                categoryName = category.name
                                categoryPath = category.savePath
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(category.name).foregroundStyle(.primary)
                                        if !category.savePath.isEmpty { Text(category.savePath).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    Image(systemName: "pencil").foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) { deletingCategory = category.name } label: { Label("删除", systemImage: "trash") }
                            }
                        }
                        TextField("分类名称", text: $categoryName)
                        TextField("保存路径（可选）", text: $categoryPath)
                        HStack {
                            if editingCategory != nil {
                                Button("取消编辑") { editingCategory = nil; categoryName = ""; categoryPath = "" }
                            }
                            Spacer()
                            Button(editingCategory == nil ? "添加分类" : "保存分类") { Task { await saveCategory() } }
                                .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .disabled(isWorking)
            .overlay { if isLoading || isWorking { ProgressView().controlSize(.large) } }
            .navigationTitle(downloader.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(isWorking) } }
            .task { await load() }
            .confirmationDialog(
                "确定删除标签「\(deletingTag ?? "")」？",
                isPresented: Binding(get: { deletingTag != nil }, set: { if !$0 { deletingTag = nil } }),
                titleVisibility: .visible
            ) {
                Button("删除标签", role: .destructive) {
                    guard let tag = deletingTag else { return }
                    deletingTag = nil
                    Task { await deleteTag(tag) }
                }
                Button("取消", role: .cancel) { deletingTag = nil }
            }
            .confirmationDialog(
                "确定删除分类「\(deletingCategory ?? "")」？",
                isPresented: Binding(get: { deletingCategory != nil }, set: { if !$0 { deletingCategory = nil } }),
                titleVisibility: .visible
            ) {
                Button("删除分类", role: .destructive) {
                    guard let category = deletingCategory else { return }
                    deletingCategory = nil
                    Task { await deleteCategory(category) }
                }
                Button("取消", role: .cancel) { deletingCategory = nil }
            } message: {
                Text("不会删除分类中的种子文件。")
            }
        }
    }

    @MainActor private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let tagResult = loadToolValue(APIPath.downloaderTags + "\(downloader.id)", label: "标签")
        async let categoryResult = loadToolValue(APIPath.downloaderCategories + "\(downloader.id)", label: "分类")
        async let preferencesResult = loadToolValue(
            APIPath.downloaderPreferences + "\(downloader.id)",
            query: ["with_status": true],
            label: "下载器设置"
        )
        let values = await (tagResult, categoryResult, preferencesResult)
        if let tagValue = values.0.value { tags = normalizedTags(tagValue) }
        if let categoryValue = values.1.value { categories = normalizedCategories(categoryValue) }
        if let preferencesValue = values.2.value {
            let preferences = jsonPayloadDictionary(preferencesValue) ?? [:]
            speedLimited = preferences.bool("use_alt_speed_limits", "alt_speed_limits_enabled", "speed_limit_mode") ?? false
        }
        let errors = [values.0.errorMessage, values.1.errorMessage, values.2.errorMessage].compactMap { $0 }
        if !errors.isEmpty { appState.presentedError = errors.joined(separator: "\n") }
    }

    @MainActor private func setSpeedMode(_ enabled: Bool) async {
        isWorking = true
        defer { isWorking = false }
        _ = await appState.perform(APIPath.downloaderToggleSpeed + "\(downloader.id)", method: .get, query: ["state": enabled])
    }

    @MainActor private func testConnection() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let raw = try await appState.api(APIPath.downloaderTest + "\(downloader.id)")
            testResult = jsonMessage(raw) ?? "连接成功"
        } catch {
            testResult = "连接失败：\(error.localizedDescription)"
        }
    }

    @MainActor private func addTag() async {
        let value = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        if await appState.perform(APIPath.downloaderTags + "\(downloader.id)", body: ["tag": value]) {
            newTag = ""
            await reloadLists()
        }
    }

    @MainActor private func deleteTag(_ tag: String) async {
        isWorking = true
        defer { isWorking = false }
        if await appState.perform(APIPath.downloaderTags + "\(downloader.id)", method: .delete, body: ["tag": tag]) { await reloadLists() }
    }

    @MainActor private func saveCategory() async {
        let value = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        let method: HTTPMethod = editingCategory == nil ? .post : .put
        if await appState.perform(
            APIPath.downloaderCategories + "\(downloader.id)",
            method: method,
            body: ["category": value, "save_path": categoryPath.trimmingCharacters(in: .whitespacesAndNewlines)]
        ) {
            editingCategory = nil
            categoryName = ""
            categoryPath = ""
            await reloadLists()
        }
    }

    @MainActor private func deleteCategory(_ category: String) async {
        isWorking = true
        defer { isWorking = false }
        if await appState.perform(APIPath.downloaderCategories + "\(downloader.id)", method: .delete, body: ["category": category]) { await reloadLists() }
    }

    @MainActor private func reloadLists() async {
        async let tagResult = loadToolValue(APIPath.downloaderTags + "\(downloader.id)", label: "标签")
        async let categoryResult = loadToolValue(APIPath.downloaderCategories + "\(downloader.id)", label: "分类")
        let values = await (tagResult, categoryResult)
        if let tagValue = values.0.value { tags = normalizedTags(tagValue) }
        if let categoryValue = values.1.value { categories = normalizedCategories(categoryValue) }
        let errors = [values.0.errorMessage, values.1.errorMessage].compactMap { $0 }
        if !errors.isEmpty { appState.presentedError = errors.joined(separator: "\n") }
    }

    @MainActor private func loadToolValue(
        _ path: String,
        query: [String: Any] = [:],
        label: String
    ) async -> (value: Any?, errorMessage: String?) {
        do { return (try await appState.api(path, query: query), nil) }
        catch { return (nil, "\(label)：\(error.localizedDescription)") }
    }

    private func normalizedTags(_ raw: Any) -> [String] {
        let strings = jsonStrings(raw)
        if !strings.isEmpty { return Array(Set(strings)).sorted() }
        return Array(Set(jsonRows(raw).compactMap { $0.string("name", "tag", "label") })).sorted()
    }

    private func normalizedCategories(_ raw: Any) -> [ManagedDownloaderCategory] {
        let rows = jsonRows(raw)
        if !rows.isEmpty {
            return rows.compactMap { row in
                guard let name = row.string("name", "category", "hash"), !name.isEmpty else { return nil }
                return ManagedDownloaderCategory(name: name, savePath: row.string("savePath", "save_path", "path") ?? "")
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return jsonStrings(raw).map { ManagedDownloaderCategory(name: $0, savePath: "") }.sorted { $0.name < $1.name }
    }
}

struct TorrentRow: View {
    @EnvironmentObject private var appState: AppState
    let item: TorrentItem
    @ObservedObject var model: DownloadsViewModel
    let isSelecting: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleSelection: () -> Void
    let onAdvanced: () -> Void
    let onExport: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                if isSelecting {
                    Button(action: onToggleSelection) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(isSelected ? HarvestTheme.green : .secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    SymbolBadge(icon: statusIcon, color: progressColor, size: 34)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(metadataLine).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Menu {
                    Button { Task { await model.control(appState, torrent: item, command: "resume") } } label: { Label("开始", systemImage: "play") }
                    Button { Task { await model.control(appState, torrent: item, command: "pause") } } label: { Label("暂停", systemImage: "pause") }
                    Button(action: onAdvanced) { Label("高级操作", systemImage: "slider.horizontal.3") }
                    Menu {
                        copyButton("名称", value: item.name, icon: "textformat")
                        copyButton("Hash", value: item.torrentHash, icon: "number")
                        copyButton("磁力链接", value: item.copyMagnet, icon: "link")
                        copyButton("Tracker", value: item.trackerURLs.joined(separator: "\n"), icon: "network")
                        copyButton("保存路径", value: item.savePath, icon: "folder")
                    } label: { Label("复制", systemImage: "doc.on.doc") }
                    if !item.downloaderCategory.lowercased().contains("tr") {
                        Button(action: onExport) { Label("导出 .torrent", systemImage: "square.and.arrow.up") }
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("删除", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis").frame(width: 30, height: 30) }
            }
            ProgressView(value: item.progress).tint(progressColor)
            HStack { Text("\(Int(item.progress * 100))%").fontWeight(.semibold); Text(formatBytes(item.size)); Spacer(); Label(formatSpeed(item.downloadSpeed), systemImage: "arrow.down").foregroundStyle(HarvestTheme.blue); Label(formatSpeed(item.uploadSpeed), systemImage: "arrow.up").foregroundStyle(HarvestTheme.green) }.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .cardSurface()
        .contentShape(RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous))
        .onTapGesture(perform: onSelect)
        .confirmationDialog("确定删除种子「\(item.name)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("仅删除种子", role: .destructive) {
                Task { await model.control(appState, torrent: item, command: "delete") }
            }
            Button("删除种子及未被保留的文件", role: .destructive) {
                Task { await model.control(appState, torrent: item, command: "delete", deleteFilesWhenUnpreserved: true) }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("若相同内容路径仍有其他做种任务，数据文件会自动保留。")
        }
    }

    private var progressColor: Color {
        item.hasError ? HarvestTheme.coral : item.progress >= 1 ? HarvestTheme.green : item.downloadSpeed > 0 ? HarvestTheme.blue : HarvestTheme.amber
    }

    private var statusIcon: String {
        if item.hasError { return "exclamationmark.triangle.fill" }
        if item.progress >= 1 { return "checkmark.circle.fill" }
        if item.downloadSpeed > 0 { return "arrow.down.circle.fill" }
        if item.uploadSpeed > 0 { return "arrow.up.circle.fill" }
        return "pause.circle.fill"
    }

    private var metadataLine: String {
        var values = [item.status]
        let site = model.siteLabel(for: item)
        if !site.isEmpty { values.append(site) }
        if !item.category.isEmpty { values.append(item.category) }
        if !item.tags.isEmpty { values.append(item.tags.prefix(2).joined(separator: ", ")) }
        return values.joined(separator: " · ")
    }

    private func copyButton(_ title: String, value: String, icon: String) -> some View {
        Button {
            UIPasteboard.general.string = value
        } label: {
            Label(title, systemImage: icon)
        }
        .disabled(value.isEmpty)
    }
}

struct TorrentAdvancedActionsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let torrents: [TorrentItem]
    @ObservedObject var model: DownloadsViewModel
    let onComplete: () -> Void
    @State private var savePath: String
    @State private var category: String
    @State private var tags: String
    @State private var tracker: String
    @State private var uploadLimitKB = ""
    @State private var ratioLimit = ""
    @State private var seedingHours = ""
    @State private var forceStart: Bool
    @State private var autoManagement: Bool
    @State private var superSeeding: Bool
    @AppStorage("torrent.deleteFilesWhenUnpreserved") private var deleteFiles = true
    @State private var isWorking = false
    @State private var confirmDelete = false

    init(torrents: [TorrentItem], model: DownloadsViewModel, onComplete: @escaping () -> Void) {
        self.torrents = torrents
        self.model = model
        self.onComplete = onComplete
        let first = torrents.first
        _savePath = State(initialValue: first?.savePath ?? "")
        _category = State(initialValue: first?.category ?? "")
        _tags = State(initialValue: first?.tags.joined(separator: ", ") ?? "")
        _tracker = State(initialValue: first?.tracker ?? "")
        _forceStart = State(initialValue: first?.forceStart ?? false)
        _autoManagement = State(initialValue: first?.autoManaged ?? false)
        _superSeeding = State(initialValue: first?.superSeeding ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("已选择 \(torrents.count) 个任务") {
                    Button { run(qb: "resume", tr: "start_torrent") } label: { Label("开始", systemImage: "play.fill") }
                    Button { run(qb: "pause", tr: "stop_torrent") } label: { Label("暂停", systemImage: "pause.fill") }
                    if hasTransmission {
                        Button { runTR("start_torrent", extra: ["bypass_queue": true]) } label: {
                            Label("Transmission 强制开始", systemImage: "forward.fill")
                        }
                    }
                    Button { run(qb: "recheck", tr: "verify_torrent") } label: { Label("重新校验", systemImage: "checkmark.shield") }
                    Button { run(qb: "reannounce", tr: "reannounce_torrent") } label: { Label("重新汇报", systemImage: "megaphone") }
                }

                Section("队列优先级") {
                    HStack {
                        actionIcon("队列顶部", icon: "arrow.up.to.line") { run(qb: "top_priority", tr: "queue_top") }
                        Spacer()
                        actionIcon("上移", icon: "arrow.up") { run(qb: "increase_priority", tr: "queue_up") }
                        Spacer()
                        actionIcon("下移", icon: "arrow.down") { run(qb: "decrease_priority", tr: "queue_down") }
                        Spacer()
                        actionIcon("队列底部", icon: "arrow.down.to.line") { run(qb: "bottom_priority", tr: "queue_bottom") }
                    }
                }

                Section("位置与归类") {
                    TextField("保存路径", text: $savePath)
                    Button("更改保存位置") {
                        run(
                            qb: "set_location",
                            tr: "move_torrent_data",
                            qbExtra: ["location": savePath],
                            trExtra: ["location": savePath, "move": true]
                        )
                    }.disabled(savePath.isEmpty)
                    TextField("分类 / Transmission 标签", text: $category)
                    Button("应用分类") {
                        run(qb: "set_category", tr: "change_torrent", qbExtra: ["category": category], trExtra: ["labels": category.isEmpty ? [] : [category]])
                    }
                    TextField("标签，使用逗号分隔", text: $tags)
                    Button("应用标签") {
                        let values = splitValues(tags)
                        run(qb: "add_tags", tr: "change_torrent", qbExtra: ["tags": values], trExtra: ["labels": values])
                    }
                }

                Section("Tracker") {
                    TextField("Tracker 地址，每行一个", text: $tracker, axis: .vertical).lineLimit(3...7).textInputAutocapitalization(.never)
                    Button("替换 Tracker") { Task { await replaceTrackers() } }.disabled(tracker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if hasQBittorrent {
                    Section("qBittorrent 高级设置") {
                        Toggle("强制启动", isOn: $forceStart)
                        Button("应用强制启动") { runQB("set_force_start", extra: ["enable": forceStart]) }
                        Toggle("自动管理", isOn: $autoManagement)
                        Button("应用自动管理") { runQB("set_auto_management", extra: ["enable": autoManagement]) }
                        Toggle("超级做种", isOn: $superSeeding)
                        Button("应用超级做种") { runQB("set_super_seeding", extra: ["enable": superSeeding]) }
                        TextField("上传限制（KB/s，0 为不限速）", text: $uploadLimitKB).keyboardType(.numberPad)
                        Button("设置上传限制") {
                            let bytes = max(0, (Int(uploadLimitKB) ?? 0) * 1024)
                            runQB("set_upload_limit", extra: ["limit": bytes])
                        }
                        TextField("分享率限制（如 2.0，-1 不限制）", text: $ratioLimit).keyboardType(.decimalPad)
                        TextField("做种时间限制（小时）", text: $seedingHours).keyboardType(.decimalPad)
                        Button("设置分享限制") {
                            let ratio = Double(ratioLimit) ?? -2
                            let seconds = (Double(seedingHours) ?? 0) * 3600
                            runQB("set_share_limits", extra: ["ratio_limit": ratio, "seeding_time_limit": seconds])
                        }
                    }
                }

                Section {
                    Toggle("无其他同路径做种时删除文件", isOn: $deleteFiles)
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: { Label("删除所选任务", systemImage: "trash") }
                }
            }
            .disabled(isWorking || torrents.isEmpty)
            .overlay { if isWorking { ProgressView().controlSize(.large) } }
            .navigationTitle("种子高级操作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(isWorking) } }
            .confirmationDialog("确定删除所选的 \(torrents.count) 个种子？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) { Task { await deleteSelected() } }
                Button("取消", role: .cancel) { }
            } message: {
                Text(deleteFiles ? "相同内容路径仍有其他做种任务时只删除种子，否则同时删除文件。" : "只删除下载器中的种子任务，保留数据文件。")
            }
        }
    }

    private var hasQBittorrent: Bool { torrents.contains { !$0.downloaderCategory.lowercased().contains("tr") } }
    private var hasTransmission: Bool { torrents.contains { $0.downloaderCategory.lowercased().contains("tr") } }

    private func actionIcon(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 34, height: 34) }
            .buttonStyle(.bordered)
            .accessibilityLabel(title)
    }

    private func splitValues(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func run(qb: String, tr: String, qbExtra: [String: Any] = [:], trExtra: [String: Any] = [:]) {
        Task { await perform(qb: qb, tr: tr, qbExtra: qbExtra, trExtra: trExtra) }
    }

    private func runQB(_ command: String, extra: [String: Any]) {
        let selected = torrents.filter { !$0.downloaderCategory.lowercased().contains("tr") }
        Task {
            isWorking = true
            await model.execute(appState, torrents: selected, qbCommand: command, trCommand: command, qbExtra: extra)
            isWorking = false
        }
    }

    private func runTR(_ command: String, extra: [String: Any]) {
        let selected = torrents.filter { $0.downloaderCategory.lowercased().contains("tr") }
        Task {
            isWorking = true
            await model.execute(appState, torrents: selected, qbCommand: command, trCommand: command, trExtra: extra)
            isWorking = false
        }
    }

    @MainActor private func perform(qb: String, tr: String, qbExtra: [String: Any] = [:], trExtra: [String: Any] = [:]) async {
        isWorking = true
        await model.execute(appState, torrents: torrents, qbCommand: qb, trCommand: tr, qbExtra: qbExtra, trExtra: trExtra)
        isWorking = false
    }

    @MainActor private func deleteSelected() async {
        isWorking = true
        await model.deleteTorrents(appState, torrents: torrents, deleteFilesWhenUnpreserved: deleteFiles)
        isWorking = false
        onComplete()
        dismiss()
    }

    @MainActor private func replaceTrackers() async {
        let values = splitValues(tracker)
        guard let primary = values.first else { return }
        isWorking = true
        let qbItems = torrents.filter { !$0.downloaderCategory.lowercased().contains("tr") }
        let trItems = torrents.filter { $0.downloaderCategory.lowercased().contains("tr") }
        if !qbItems.isEmpty { await model.replaceTrackers(appState, torrents: qbItems, tracker: primary) }
        if !trItems.isEmpty {
            await model.execute(appState, torrents: trItems, qbCommand: "set_tracker", trCommand: "change_torrent", trExtra: ["tracker_list": values])
        }
        isWorking = false
    }
}

struct TorrentDetailSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let item: TorrentItem
    @ObservedObject var model: DownloadsViewModel
    @State private var detail: [String: Any]?
    @State private var isLoading = true
    @State private var loadError = ""

    var body: some View {
        NavigationStack {
            List {
                Section("传输") {
                    LabeledContent("状态", value: item.status)
                    LabeledContent("进度", value: "\(Int(item.progress * 100))%")
                    LabeledContent("大小", value: formatBytes(item.size))
                    LabeledContent("分享率", value: String(format: "%.2f", item.ratio))
                    LabeledContent("下载速度", value: formatSpeed(item.downloadSpeed))
                    LabeledContent("上传速度", value: formatSpeed(item.uploadSpeed))
                }
                Section("存储与分类") {
                    if !item.siteHint.isEmpty { LabeledContent("站点", value: item.siteHint) }
                    LabeledContent("分类", value: item.category.isEmpty ? "未分类" : item.category)
                    LabeledContent("标签", value: item.tags.isEmpty ? "无" : item.tags.joined(separator: "、"))
                    if !savePath.isEmpty { LabeledContent("保存路径", value: savePath) }
                    if !contentPath.isEmpty { LabeledContent("内容路径", value: contentPath) }
                    if !addedAt.isEmpty { LabeledContent("添加时间", value: addedAt) }
                    if !activityAt.isEmpty { LabeledContent("活动时间", value: activityAt) }
                    if let totalSize, totalSize > 0 { LabeledContent("总大小", value: formatBytes(totalSize)) }
                }
                if isLoading { Section { ProgressView().frame(maxWidth: .infinity) } }
                if !loadError.isEmpty {
                    Section { Label(loadError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(HarvestTheme.coral) }
                }
                if !trackers.isEmpty {
                    Section("Tracker") {
                        ForEach(Array(trackers.enumerated()), id: \.offset) { _, tracker in
                            VStack(alignment: .leading, spacing: 6) {
                                let url = tracker.string("announce", "url", "tracker", "host") ?? "未知 Tracker"
                                Text(tracker.string("host") ?? url).font(.subheadline.weight(.medium)).lineLimit(1)
                                if tracker.string("host") != nil, tracker.string("host") != url {
                                    Text(url).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                                }
                                let seeds = tracker.int("seeds", "seederCount", "num_seeds")
                                let leeches = tracker.int("leeches", "leecherCount", "num_leeches")
                                let message = tracker.string("msg", "message", "lastAnnounceResult", "last_announce_result") ?? ""
                                HStack(spacing: 12) {
                                    if let seeds { Label("\(seeds)", systemImage: "arrow.up.circle") }
                                    if let leeches { Label("\(leeches)", systemImage: "arrow.down.circle") }
                                    if let status = tracker.string("status"), !status.isEmpty { Text(status) }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                if !message.isEmpty { Text(message).font(.caption2).foregroundStyle(.secondary) }
                            }
                            .textSelection(.enabled)
                            .padding(.vertical, 3)
                        }
                    }
                }
                if !files.isEmpty {
                    Section("文件") {
                        OutlineGroup(fileTree, children: \.outlineChildren) { node in
                            TorrentFileTreeLabel(node: node)
                        }
                    }
                }
                Section("原始详情") { Text(prettyJSON(resolved)).font(.caption2.monospaced()).textSelection(.enabled) }
                Section {
                    Button { Task { await model.control(appState, torrent: item, command: "resume"); dismiss() } } label: { Label("开始", systemImage: "play.fill") }
                    Button { Task { await model.control(appState, torrent: item, command: "pause"); dismiss() } } label: { Label("暂停", systemImage: "pause.fill") }
                }
            }
            .navigationTitle(item.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(isLoading)
                        .accessibilityLabel("刷新种子详情")
                }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var resolved: [String: Any] { detail ?? item.raw }
    private var properties: [String: Any] { resolved.dict("properties", "props") ?? [:] }
    private var files: [[String: Any]] { resolved.rows("files", "contents", "fileStats") }
    private var fileTree: [TorrentFileNode] { buildTorrentFileTree(files) }
    private var trackers: [[String: Any]] {
        let values = resolved.rows("trackers", "trackerStats", "tracker_stats")
        let candidates: [[String: Any]]
        if !values.isEmpty {
            candidates = values
        } else if !item.trackerURLs.isEmpty {
            candidates = item.trackerURLs.map { ["announce": $0] }
        } else if let value = resolved.string("tracker", "tracker_url", "announce"), !value.isEmpty {
            candidates = [["announce": value]]
        } else {
            candidates = []
        }
        return candidates.filter { !isVirtualTorrentTracker($0) }
    }
    private var savePath: String { resolved.string("save_path", "savePath", "downloadDir", "download_dir") ?? item.savePath }
    private var contentPath: String { resolved.string("content_path", "contentPath") ?? properties.string("content_path", "contentPath") ?? "" }
    private var addedAt: String { resolved.string("added_on", "addedDate", "added_date", "added_at") ?? properties.string("added_on", "addedDate", "added_date", "added_at") ?? "" }
    private var activityAt: String { resolved.string("last_activity", "activityDate", "activity_date", "last_activity_at") ?? properties.string("last_activity", "activityDate", "activity_date", "last_activity_at") ?? "" }
    private var totalSize: Double? { properties.double("total_size", "totalSize", "total_size_bytes") ?? resolved.double("total_size", "totalSize") }

    @MainActor
    private func load() async {
        guard !isLoading || detail == nil else { return }
        isLoading = true
        loadError = ""
        defer { isLoading = false }
        guard item.downloaderID > 0 else { return }
        do {
            detail = jsonPayloadDictionary(try await appState.api(
                "\(APIPath.downloaderTorrentDetail)\(item.downloaderID)",
                query: ["torrent_hash": item.torrentHash]
            ))
        } catch {
            loadError = "加载详情失败：\(error.localizedDescription)"
        }
    }
}

private struct TorrentFileNode: Identifiable {
    let id: String
    let name: String
    let size: Double
    let progress: Double
    let children: [TorrentFileNode]

    var outlineChildren: [TorrentFileNode]? { children.isEmpty ? nil : children }
    var isFolder: Bool { !children.isEmpty }
}

private final class TorrentFileTreeBuilder {
    let name: String
    let path: String
    var folders: [String: TorrentFileTreeBuilder] = [:]
    var files: [TorrentFileNode] = []

    init(name: String, path: String) {
        self.name = name
        self.path = path
    }

    func insert(parts: ArraySlice<String>, size: Double, progress: Double, index: Int) {
        guard let part = parts.first else { return }
        if parts.count == 1 {
            let filePath = path.isEmpty ? part : "\(path)/\(part)"
            files.append(TorrentFileNode(
                id: "\(filePath)#\(index)",
                name: part,
                size: size,
                progress: progress,
                children: []
            ))
            return
        }
        let folderPath = path.isEmpty ? part : "\(path)/\(part)"
        let folder = folders[part] ?? TorrentFileTreeBuilder(name: part, path: folderPath)
        folders[part] = folder
        folder.insert(parts: parts.dropFirst(), size: size, progress: progress, index: index)
    }

    func frozenChildren() -> [TorrentFileNode] {
        let folderNodes = folders.values.map { folder -> TorrentFileNode in
            let children = folder.frozenChildren()
            let totalSize = children.reduce(0) { $0 + $1.size }
            let progress: Double
            if totalSize > 0 {
                progress = children.reduce(0) { $0 + ($1.size * $1.progress) } / totalSize
            } else if children.isEmpty {
                progress = 0
            } else {
                progress = children.reduce(0) { $0 + $1.progress } / Double(children.count)
            }
            return TorrentFileNode(
                id: folder.path,
                name: folder.name,
                size: totalSize,
                progress: progress,
                children: children
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let fileNodes = files.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return folderNodes + fileNodes
    }
}

private func buildTorrentFileTree(_ files: [[String: Any]]) -> [TorrentFileNode] {
    let root = TorrentFileTreeBuilder(name: "", path: "")
    for (index, file) in files.enumerated() {
        let rawPath = file.string("name", "path")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = rawPath.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init)
        let normalizedParts = parts.isEmpty ? ["未命名文件"] : parts
        let size = max(0, file.double("length", "size") ?? 0)
        let rawProgress = file.double("progress", "availability", "percentDone", "percent_done") ?? 0
        let progress = min(1, max(0, rawProgress > 1 ? rawProgress / 100 : rawProgress))
        root.insert(parts: normalizedParts[...], size: size, progress: progress, index: index)
    }
    return root.frozenChildren()
}

private struct TorrentFileTreeLabel: View {
    let node: TorrentFileNode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: node.isFolder ? "folder.fill" : "doc")
                    .foregroundStyle(node.isFolder ? HarvestTheme.amber : .secondary)
                Text(node.name).font(.caption).lineLimit(2)
                Spacer(minLength: 8)
                if node.isFolder {
                    Text("\(node.children.count) 项").font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text(node.size > 0 ? formatBytes(node.size) : "未知大小")
                Spacer()
                Text("\(Int(node.progress * 100))%")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            ProgressView(value: node.progress)
                .tint(node.progress >= 1 ? HarvestTheme.green : HarvestTheme.blue)
        }
        .padding(.vertical, 2)
    }
}

private func isVirtualTorrentTracker(_ tracker: [String: Any]) -> Bool {
    let values = [
        tracker.string("announce", "url", "tracker"),
        tracker.string("host"),
        tracker.string("name", "sitename", "site_name")
    ]
    return values.compactMap { $0 }.contains { value in
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered.hasPrefix("dht") || lowered.hasPrefix("pex") || lowered.hasPrefix("lsd") { return true }
        let normalized = lowered.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return normalized == "dht" || normalized == "pex" || normalized == "lsd"
    }
}

struct AddTorrentSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let downloaders: [DownloaderItem]
    let initialSiteID: Int?
    let onSaved: () async -> Void
    @State private var input: String
    @State private var downloaderID: Int
    @State private var category = ""
    @State private var savePath = ""
    @State private var suggestedPaths: [String] = []
    @State private var sites: [SiteItem] = []
    @State private var siteIdentifier: String
    @State private var cookie: String
    @State private var generateTorrentURL: Bool
    @State private var tags = ""
    @State private var paused = false
    @State private var skipChecking = false
    @State private var showAdvanced = false
    @State private var rename = ""
    @State private var uploadLimit = ""
    @State private var downloadLimit = ""
    @State private var ratioLimit = ""
    @State private var seedingTimeLimit = ""
    @State private var autoManagement = false
    @State private var createSubfolder = false
    @State private var sequentialDownload = false
    @State private var firstLastPiecePriority = false
    @State private var addToTop = false
    @State private var forced = false
    @State private var contentLayout = "Original"
    @State private var stopCondition = ""
    @State private var shareLimitAction = ""
    @State private var isSaving = false

    init(
        downloaders: [DownloaderItem],
        initialInput: String = "",
        initialCookie: String = "",
        initialSiteID: Int? = nil,
        initialSiteKey: String? = nil,
        initialDownloaderID: Int? = nil,
        onSaved: @escaping () async -> Void
    ) {
        self.downloaders = downloaders
        self.initialSiteID = initialSiteID
        self.onSaved = onSaved
        _input = State(initialValue: initialInput)
        _downloaderID = State(initialValue: initialDownloaderID ?? 0)
        _siteIdentifier = State(initialValue: initialSiteKey ?? initialSiteID.map { String($0) } ?? "")
        _cookie = State(initialValue: initialCookie)
        let normalizedSite = (initialSiteKey ?? "")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        _generateTorrentURL = State(initialValue: normalizedSite == "mteam")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("种子来源") { TextField("磁力链接、种子 URL 或站点种子 ID", text: $input, axis: .vertical).lineLimit(4...8) }
                Section("下载设置") {
                    Picker("下载器", selection: $downloaderID) { ForEach(downloaders) { Text($0.name).tag($0.id) } }
                    if !suggestedPaths.isEmpty {
                        Picker("常用路径", selection: $savePath) { Text("不指定").tag(""); ForEach(suggestedPaths, id: \.self) { Text($0).tag($0) } }
                    }
                    TextField("保存路径（可选）", text: $savePath)
                    TextField("分类（可选）", text: $category)
                    TextField("标签，使用逗号分隔", text: $tags)
                    Toggle("添加后暂停", isOn: $paused)
                    Toggle("跳过文件校验", isOn: $skipChecking)
                    Toggle("高级设置", isOn: $showAdvanced)
                }
                if showAdvanced {
                    Section("下载链接") {
                        Toggle(
                            "自动生成下载链接",
                            isOn: Binding(
                                get: { effectiveGenerateTorrentURL },
                                set: { if !mustGenerateTorrentURL { generateTorrentURL = $0 } }
                            )
                        )
                        .disabled(mustGenerateTorrentURL)
                        TextField("站点标识（批量推送必填）", text: $siteIdentifier)
                            .textInputAutocapitalization(.never)
                        if !sites.isEmpty {
                            Menu("从站点选择") {
                                ForEach(sites) { site in
                                    Button(site.name) {
                                        siteIdentifier = site.siteKey.isEmpty ? String(site.id) : site.siteKey
                                        if cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            cookie = site.cookie
                                        }
                                    }
                                }
                            }
                        }
                        TextField("Cookie（可选）", text: $cookie, axis: .vertical)
                            .lineLimit(2...5)
                            .textInputAutocapitalization(.never)
                    }
                    Section("高级推送") {
                        TextField("任务名称（可选）", text: $rename)
                        TextField("上传限制（KB/s）", text: $uploadLimit).keyboardType(.numberPad)
                        TextField("下载限制（KB/s）", text: $downloadLimit).keyboardType(.numberPad)
                        TextField("分享率限制", text: $ratioLimit).keyboardType(.decimalPad)
                        TextField("做种时间限制（分钟）", text: $seedingTimeLimit).keyboardType(.numberPad)
                        if isQBittorrent {
                            Picker("内容布局", selection: $contentLayout) {
                                Text("原始").tag("Original")
                                Text("不创建子文件夹").tag("NoSubfolder")
                                Text("创建子文件夹").tag("Subfolder")
                            }
                            Picker("停止条件", selection: $stopCondition) {
                                Text("不自动停止").tag("")
                                Text("收到元数据后停止").tag("MetadataReceived")
                                Text("文件校验后停止").tag("FilesChecked")
                            }
                            Picker("分享限制动作", selection: $shareLimitAction) {
                                Text("使用默认").tag("")
                                Text("停止做种").tag("Stop")
                                Text("移除任务").tag("Remove")
                                Text("移除并删除内容").tag("RemoveWithContent")
                                Text("启用超级做种").tag("EnableSuperSeeding")
                            }
                            Toggle("自动种子管理", isOn: $autoManagement)
                            Toggle("创建根目录", isOn: $createSubfolder)
                            Toggle("顺序下载", isOn: $sequentialDownload)
                            Toggle("优先首尾块", isOn: $firstLastPiecePriority)
                            Toggle("添加到队列顶部", isOn: $addToTop)
                            Toggle("强制启动", isOn: $forced)
                        }
                    }
                }
            }
            .navigationTitle("添加种子").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("推送") { Task { await push() } }
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || downloaderID == 0 || isSaving)
                }
            }
            .onAppear {
                if !downloaders.contains(where: { $0.id == downloaderID }) {
                    downloaderID = downloaders.first?.id ?? 0
                }
            }
            .onChange(of: downloaders.map(\.id)) { _, _ in
                if !downloaders.contains(where: { $0.id == downloaderID }) { downloaderID = downloaders.first?.id ?? 0 }
            }
            .task {
                do {
                    suggestedPaths = jsonPathStrings(try await appState.api(APIPath.downloaderPaths))
                } catch {
                    suggestedPaths = []
                }
                do {
                    sites = jsonRows(try await appState.api(APIPath.sites)).map(SiteItem.init)
                    if let initialSiteID,
                       let initialSite = sites.first(where: { $0.id == initialSiteID }) {
                        siteIdentifier = initialSite.siteKey.isEmpty ? String(initialSite.id) : initialSite.siteKey
                        if cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            cookie = initialSite.cookie
                        }
                    }
                } catch {
                    sites = []
                }
            }
            .overlay { if isSaving { ProgressView().controlSize(.large) } }
        }
    }

    private var selectedDownloader: DownloaderItem? {
        downloaders.first { $0.id == downloaderID }
    }

    private var isQBittorrent: Bool {
        guard let selectedDownloader else { return false }
        let value = selectedDownloader.category.lowercased()
        return !value.contains("tr") && !value.contains("transmission")
    }

    private var mustGenerateTorrentURL: Bool {
        if isMTeamSiteIdentifier(siteIdentifier) { return true }
        let raw = siteIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let site = sites.first(where: {
            String($0.id) == raw
                || $0.siteKey.caseInsensitiveCompare(raw) == .orderedSame
                || $0.name.caseInsensitiveCompare(raw) == .orderedSame
        }) else { return false }
        return isMTeamSiteIdentifier(site.siteKey) || isMTeamSiteIdentifier(site.name)
    }

    private var effectiveGenerateTorrentURL: Bool {
        generateTorrentURL || mustGenerateTorrentURL
    }

    private func isMTeamSiteIdentifier(_ value: String) -> Bool {
        value.lowercased().filter { $0.isLetter || $0.isNumber } == "mteam"
    }

    @MainActor private func push() async {
        let urls = parsedTorrentInputs(input)
        guard !urls.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        var body: [String: Any] = [
            "is_paused": paused,
            "is_skip_checking": skipChecking
        ]
        if urls.count == 1 { body["urls"] = urls[0] }
        else { body["urls"] = urls }
        let trimmedPath = savePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagValues = tags.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !trimmedPath.isEmpty { body["save_path"] = trimmedPath }
        if !trimmedCategory.isEmpty { body["category"] = trimmedCategory }
        let trimmedSiteIdentifier = siteIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCookie = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if effectiveGenerateTorrentURL && !trimmedSiteIdentifier.isEmpty { body["site_id"] = trimmedSiteIdentifier }
        if !trimmedCookie.isEmpty { body["cookie"] = trimmedCookie }
        if !tagValues.isEmpty { body["tags"] = tagValues }
        if !rename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["rename"] = rename.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = Int(uploadLimit), value > 0 { body["upload_limit"] = value }
        if let value = Int(downloadLimit), value > 0 { body["download_limit"] = value }
        if let value = Double(ratioLimit) { body["ratio_limit"] = value }
        if let value = Int(seedingTimeLimit) { body["seeding_time_limit"] = value }
        let torrentIDs = urls.compactMap(torrentIDFromInput).uniqued()
        if torrentIDs.count == 1 { body["ids"] = torrentIDs[0] }
        else if !torrentIDs.isEmpty { body["ids"] = torrentIDs }

        if isQBittorrent {
            body["use_auto_torrent_management"] = autoManagement
            body["is_root_folder"] = createSubfolder
            body["is_sequential_download"] = sequentialDownload
            body["is_first_last_piece_priority"] = firstLastPiecePriority
            body["add_to_top_of_queue"] = addToTop
            body["content_layout"] = contentLayout
            body["forced"] = forced
            if !stopCondition.isEmpty { body["stop_condition"] = stopCondition }
            if !shareLimitAction.isEmpty { body["share_limit_action"] = shareLimitAction }
        }

        if urls.count > 1 {
            let selectedSite = sites.first {
                String($0.id) == trimmedSiteIdentifier
                    || $0.siteKey.caseInsensitiveCompare(trimmedSiteIdentifier) == .orderedSame
                    || $0.name.caseInsensitiveCompare(trimmedSiteIdentifier) == .orderedSame
            }
            guard let batchSiteID = selectedSite?.id ?? Int(trimmedSiteIdentifier), batchSiteID > 0 else {
                appState.presentedError = "批量推送需要可识别的站点 ID"
                return
            }
            guard !torrentIDs.isEmpty else {
                appState.presentedError = "批量推送未解析到种子 ID，请输入种子 ID 或详情链接"
                return
            }
            if let data = try? JSONSerialization.data(withJSONObject: tagValues),
               let encoded = String(data: data, encoding: .utf8) { body["tags"] = encoded }
            if await appState.perform("\(APIPath.pushTorrentMonkey)\(downloaderID)/\(batchSiteID)", method: .post, body: body) {
                await onSaved()
                dismiss()
            }
        } else if await appState.perform("\(APIPath.pushTorrent)/\(downloaderID)", method: .post, body: body) {
            await onSaved()
            dismiss()
        }
    }

    private func parsedTorrentInputs(_ value: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;，；"))
        return value.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
    }

    private func torrentIDFromInput(_ value: String) -> String? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty, raw.allSatisfy(\.isNumber) { return raw }
        if let components = URLComponents(string: raw) {
            for key in ["tid", "id", "torrentid", "topicid"] {
                if let item = components.queryItems?.first(where: { $0.name.lowercased() == key }),
                   let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
            }
            for segment in components.path.split(separator: "/").reversed() {
                let value = String(segment)
                if value.allSatisfy(\.isNumber) { return value }
            }
        }
        guard let expression = try? NSRegularExpression(pattern: #"[?&](?:tid|id|torrentid|topicid)=([^&#]+)"#, options: .caseInsensitive),
              let match = expression.firstMatch(in: raw, range: NSRange(raw.startIndex..<raw.endIndex, in: raw)),
              let range = Range(match.range(at: 1), in: raw) else { return nil }
        return String(raw[range]).removingPercentEncoding ?? String(raw[range])
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

struct DownloaderEditorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let downloader: DownloaderItem?
    let onSaved: () async -> Void
    @State private var name: String
    @State private var type: String
    @State private var networkProtocol: String
    @State private var host: String
    @State private var externalHost: String
    @State private var port: String
    @State private var username: String
    @State private var password: String
    @State private var enabled: Bool
    @State private var brush: Bool
    @State private var sortID: String
    @State private var torrentPath: String
    @State private var suggestedPaths: [String] = []
    @State private var isLoadingPaths = false
    @State private var isSaving = false
    @State private var validationError: String?

    init(downloader: DownloaderItem? = nil, onSaved: @escaping () async -> Void) {
        self.downloader = downloader
        self.onSaved = onSaved
        _name = State(initialValue: downloader?.name ?? "")
        _type = State(initialValue: downloader?.category ?? "Qb")
        _networkProtocol = State(initialValue: downloader?.networkProtocol ?? "http")
        _host = State(initialValue: downloader?.host ?? "")
        _externalHost = State(initialValue: downloader?.externalHost ?? "")
        _port = State(initialValue: downloader.map { String($0.port) } ?? "8080")
        _username = State(initialValue: downloader?.username ?? "")
        _password = State(initialValue: downloader?.password ?? "")
        _enabled = State(initialValue: downloader?.enabled ?? true)
        _brush = State(initialValue: downloader?.brush ?? false)
        _sortID = State(initialValue: downloader.map { String($0.sortID) } ?? "0")
        _torrentPath = State(initialValue: downloader?.torrentPath ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("下载器") {
                    TextField("名称", text: $name)
                    Picker("类型", selection: $type) { Text("qBittorrent").tag("Qb"); Text("Transmission").tag("Tr") }
                    Picker("协议", selection: $networkProtocol) { Text("HTTP").tag("http"); Text("HTTPS").tag("https") }
                    TextField("主机地址", text: $host).textInputAutocapitalization(.never).keyboardType(.URL)
                    TextField("端口", text: $port).keyboardType(.numberPad)
                    TextField("外部访问地址（可选）", text: $externalHost).textInputAutocapitalization(.never).keyboardType(.URL)
                }
                Section("认证") { TextField("账号", text: $username); SecureField("密码", text: $password) }
                Section("任务") {
                    Toggle("启用下载器", isOn: $enabled)
                    Toggle("参与辅种", isOn: Binding(get: { !brush }, set: { brush = !$0 }))
                    TextField("排序值", text: $sortID).keyboardType(.numberPad)
                    if isLoadingPaths { HStack { ProgressView(); Text("正在读取种子目录").foregroundStyle(.secondary) } }
                    if !suggestedPaths.isEmpty {
                        Picker("种子文件目录", selection: $torrentPath) {
                            Text("请选择").tag("")
                            ForEach(suggestedPaths, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    TextField("种子文件目录", text: $torrentPath)
                }
                if let validationError {
                    Section { Label(validationError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(HarvestTheme.coral) }
                }
            }
            .navigationTitle(downloader == nil ? "添加下载器" : "编辑下载器").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(name.isEmpty || host.isEmpty || isSaving)
                }
            }
            .overlay { if isSaving { ProgressView().controlSize(.large) } }
            .task { await loadSuggestedPaths() }
        }
    }

    @MainActor private func loadSuggestedPaths() async {
        isLoadingPaths = true
        defer { isLoadingPaths = false }
        do {
            suggestedPaths = jsonPathStrings(try await appState.api(APIPath.downloaderPaths))
            if !torrentPath.isEmpty, !suggestedPaths.contains(torrentPath) { suggestedPaths.insert(torrentPath, at: 0) }
            if torrentPath.isEmpty { torrentPath = suggestedPaths.first ?? "" }
        } catch {
            if !torrentPath.isEmpty { suggestedPaths = [torrentPath] }
        }
    }

    @MainActor private func save() async {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = torrentPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { validationError = "请输入下载器名称"; return }
        guard !normalizedHost.isEmpty else { validationError = "请输入主机地址"; return }
        guard let portValue = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65_535).contains(portValue) else {
            validationError = "端口必须在 1 到 65535 之间"
            return
        }
        guard !normalizedUsername.isEmpty else { validationError = "请输入下载器账号"; return }
        guard !password.isEmpty else { validationError = "请输入下载器密码"; return }
        guard !normalizedPath.isEmpty else { validationError = "请选择种子文件目录"; return }

        validationError = nil
        isSaving = true
        defer { isSaving = false }
        var body = downloader?.raw ?? [:]
        body["name"] = normalizedName
        body["category"] = type
        body["protocol"] = networkProtocol
        body["host"] = normalizedHost
        let normalizedExternalHost = externalHost.trimmingCharacters(in: .whitespacesAndNewlines)
        body["external_host"] = normalizedExternalHost.isEmpty
            ? "\(networkProtocol)://\(normalizedHost):\(portValue)"
            : normalizedExternalHost
        body["port"] = portValue
        body["username"] = normalizedUsername
        body["password"] = password
        body["is_active"] = enabled
        body["brush"] = brush
        body["sort_id"] = Int(sortID) ?? downloader?.sortID ?? 0
        body["torrent_path"] = normalizedPath
        let path = downloader.map { "\(APIPath.downloaders)/\($0.id)" } ?? APIPath.downloaders
        let method: HTTPMethod = downloader == nil ? .post : .put
        if await appState.perform(path, method: method, body: body) {
            await onSaved()
            dismiss()
        }
    }
}

private enum DownloaderPreferenceKind: Equatable {
    case boolean
    case integer
    case decimal
    case text
    case json
}

private struct DownloaderPreferenceDraft: Identifiable {
    let key: String
    let section: String
    let kind: DownloaderPreferenceKind
    var text: String
    var boolValue: Bool
    var id: String { key }

    init(key: String, value: Any, section: String) {
        self.key = key
        self.section = section
        if let bool = value as? Bool {
            kind = .boolean
            boolValue = bool
            text = ""
        } else if let integer = value as? Int {
            kind = .integer
            boolValue = false
            text = String(integer)
        } else if let number = value as? NSNumber {
            kind = .decimal
            boolValue = false
            text = number.stringValue
        } else if value is [Any] || value is [String: Any] {
            kind = .json
            boolValue = false
            text = prettyJSON(value)
        } else {
            kind = .text
            boolValue = false
            text = value is NSNull ? "" : String(describing: value)
        }
    }

    func resolvedValue() throws -> Any {
        switch kind {
        case .boolean:
            return boolValue
        case .integer:
            guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw APIError(statusCode: 0, message: "\(preferenceLabel(key)) 必须是整数")
            }
            return value
        case .decimal:
            guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw APIError(statusCode: 0, message: "\(preferenceLabel(key)) 必须是数字")
            }
            return value
        case .text:
            return text
        case .json:
            guard let data = text.data(using: .utf8) else { return [] }
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        }
    }
}

private struct DownloaderPreferenceChoice: Identifiable {
    let value: String
    let title: String
    var id: String { value }
}

private let transmissionWritablePreferenceKeys: Set<String> = [
    "download-dir", "incomplete-dir", "incomplete-dir-enabled", "rename-partial-files",
    "speed-limit-down", "speed-limit-up", "speed-limit-down-enabled", "speed-limit-up-enabled",
    "alt-speed-down", "alt-speed-up", "alt-speed-enabled", "alt-speed-time-enabled",
    "alt-speed-time-begin", "alt-speed-time-end", "alt-speed-time-day",
    "peer-limit-global", "peer-limit-per-torrent", "peer-port", "port-forwarding-enabled",
    "peer-port-random-on-start", "tcp-enabled", "download-queue-enabled", "download-queue-size",
    "seed-queue-enabled", "seed-queue-size", "queue-stalled-enabled", "queue-stalled-minutes",
    "seedRatioLimited", "seedRatioLimit", "idle-seeding-limit-enabled", "idle-seeding-limit",
    "dht-enabled", "pex-enabled", "lpd-enabled", "utp-enabled", "encryption",
    "blocklist-enabled", "blocklist-url", "start-added-torrents", "trash-original-torrent-files",
    "cache-size-mb"
]

struct DownloaderSettingsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let downloader: DownloaderItem
    @State private var drafts: [DownloaderPreferenceDraft] = []
    @State private var selectedSection = ""
    @State private var query = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var parseError: String?

    private var isTransmission: Bool { downloader.category.lowercased().contains("tr") || downloader.category.lowercased().contains("trans") }
    private var sections: [String] {
        let preferred = isTransmission
            ? ["下载设置", "带宽设置", "网络设置", "队列设置", "高级"]
            : ["行为", "下载", "连接", "速度", "BitTorrent", "RSS", "WebUI", "高级"]
        return preferred.filter { section in drafts.contains { $0.section == section } }
    }
    private var visibleDrafts: [DownloaderPreferenceDraft] {
        drafts.filter { draft in
            (selectedSection.isEmpty || draft.section == selectedSection)
                && (query.isEmpty || preferenceLabel(draft.key).localizedCaseInsensitiveContains(query) || draft.key.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    Section { ProgressView().frame(maxWidth: .infinity) }
                } else {
                    Section {
                        Picker("设置分组", selection: $selectedSection) {
                            ForEach(sections, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Section(selectedSection) {
                        ForEach(visibleDrafts) { draft in preferenceControl(draft) }
                    }
                    if visibleDrafts.isEmpty {
                        Section { Text("没有匹配的设置项").foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                    }
                }
                if let parseError {
                    Section { Label(parseError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(HarvestTheme.coral) }
                }
            }
            .searchable(text: $query, prompt: "搜索设置")
            .navigationTitle("\(downloader.name) · 参数设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }.disabled(isLoading || isSaving || drafts.isEmpty)
                }
            }
            .overlay { if isSaving { ProgressView().controlSize(.large) } }
            .task { await load() }
        }
    }

    @ViewBuilder private func preferenceControl(_ draft: DownloaderPreferenceDraft) -> some View {
        let choices = preferenceChoices(draft.key, transmission: isTransmission)
        if !choices.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Picker(preferenceLabel(draft.key), selection: textBinding(draft.key)) {
                    if !choices.contains(where: { $0.value == draft.text }) {
                        Text("当前值：\(draft.text)").tag(draft.text)
                    }
                    ForEach(choices) { choice in Text(choice.title).tag(choice.value) }
                }
                Text(draft.key).font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
        } else {
            switch draft.kind {
            case .boolean:
                VStack(alignment: .leading, spacing: 3) {
                    Toggle(preferenceLabel(draft.key), isOn: boolBinding(draft.key))
                    Text(draft.key).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                }
            case .integer, .decimal:
                VStack(alignment: .leading, spacing: 4) {
                    TextField(preferenceLabel(draft.key), text: textBinding(draft.key))
                        .keyboardType(draft.kind == .integer ? .numbersAndPunctuation : .decimalPad)
                    Text(draft.key).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                }
            case .text:
                VStack(alignment: .leading, spacing: 4) {
                    if draft.key.lowercased().contains("password") {
                        SecureField(preferenceLabel(draft.key), text: textBinding(draft.key))
                    } else {
                        TextField(preferenceLabel(draft.key), text: textBinding(draft.key), axis: .vertical).lineLimit(1...5)
                    }
                    Text(draft.key).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                }
            case .json:
                VStack(alignment: .leading, spacing: 5) {
                    Text(preferenceLabel(draft.key)).font(.subheadline)
                    TextEditor(text: textBinding(draft.key)).font(.caption.monospaced()).frame(minHeight: 100)
                    Text(draft.key).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func boolBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { drafts.first(where: { $0.key == key })?.boolValue ?? false },
            set: { value in
                guard let index = drafts.firstIndex(where: { $0.key == key }) else { return }
                drafts[index].boolValue = value
            }
        )
    }

    private func textBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { drafts.first(where: { $0.key == key })?.text ?? "" },
            set: { value in
                guard let index = drafts.firstIndex(where: { $0.key == key }) else { return }
                drafts[index].text = value
            }
        )
    }

    @MainActor private func load() async {
        defer { isLoading = false }
        do {
            let raw = try await appState.api(
                "\(APIPath.downloaderPreferences)\(downloader.id)",
                query: ["with_status": true]
            )
            let root = jsonPayloadDictionary(raw) ?? jsonDictionary(raw) ?? [:]
            let preferences = root.dict("prefs", "preferences") ?? root
            let editableKeys = preferences.keys.filter { key in
                !isTransmission || transmissionWritablePreferenceKeys.contains(key)
            }
            drafts = editableKeys.sorted().compactMap { key in
                guard let value = preferences[key] else { return nil }
                return DownloaderPreferenceDraft(key: key, value: value, section: preferenceSection(key, transmission: isTransmission))
            }
            selectedSection = sections.first ?? ""
        } catch { appState.presentedError = error.localizedDescription }
    }

    @MainActor private func save() async {
        do {
            var value: [String: Any] = [:]
            for draft in drafts { value[draft.key] = try draft.resolvedValue() }
            parseError = nil
            isSaving = true
            defer { isSaving = false }
            if await appState.perform(
                "\(APIPath.downloaderPreferences)\(downloader.id)",
                method: .put,
                body: value
            ) { dismiss() }
        } catch { parseError = error.localizedDescription }
    }
}

private func preferenceChoices(_ key: String, transmission: Bool) -> [DownloaderPreferenceChoice] {
    func choices(_ values: [(String, String)]) -> [DownloaderPreferenceChoice] {
        values.map { DownloaderPreferenceChoice(value: $0.0, title: $0.1) }
    }
    if transmission {
        guard key == "encryption" else { return [] }
        return choices([
            ("tolerated", "允许明文"), ("preferred", "优先加密"), ("required", "强制加密")
        ])
    }
    switch key {
    case "locale":
        return choices([("zh_CN", "简体中文"), ("en", "English"), ("ja", "日本語"), ("ko", "한국어")])
    case "torrent_content_layout":
        return choices([("Original", "原始"), ("Subfolder", "子文件夹"), ("NoSubfolder", "无子文件夹")])
    case "torrent_stop_condition":
        return choices([("None", "无"), ("MetadataReceived", "获取元数据后"), ("FilesChecked", "文件校验后")])
    case "proxy_type":
        return choices([("None", "无"), ("SOCKS4", "SOCKS4"), ("SOCKS5", "SOCKS5"), ("HTTP", "HTTP")])
    case "resume_data_storage_type":
        return choices([("Legacy", "传统模式"), ("SQLite", "SQLite")])
    case "torrent_content_remove_option":
        return choices([("Delete", "删除"), ("MoveToTrash", "移动到回收站")])
    case "file_log_age_type":
        return choices([("0", "天"), ("1", "月"), ("2", "年")])
    case "scheduler_days":
        return choices([("0", "每天"), ("62", "工作日"), ("65", "周末")])
    case "encryption":
        return choices([("0", "允许加密"), ("1", "强制加密"), ("2", "禁用加密")])
    case "max_ratio_act":
        return choices([("0", "停止 Torrent"), ("1", "删除 Torrent")])
    case "dyndns_service":
        return choices([("0", "DynDNS"), ("1", "NoIP")])
    case "disk_io_type":
        return choices([("0", "默认"), ("1", "mmap")])
    case "disk_io_read_mode", "disk_io_write_mode":
        return choices([("0", "禁用 OS 缓存"), ("1", "启用 OS 缓存")])
    case "utp_tcp_mixed_mode":
        return choices([("0", "优先使用 TCP"), ("1", "优先使用 µTP"), ("2", "仅 TCP")])
    case "upload_choking_algorithm":
        return choices([("0", "固定上传槽位"), ("1", "反阻塞")])
    default:
        return []
    }
}

private func preferenceSection(_ key: String, transmission: Bool) -> String {
    let value = key.lowercased()
    if transmission {
        if value.hasPrefix("speed-limit") || value.hasPrefix("alt-speed") { return "带宽设置" }
        if value.hasPrefix("peer-") || value.contains("port-forward") || value == "tcp-enabled" || value.hasPrefix("dht-") || value.hasPrefix("pex-") || value.hasPrefix("lpd-") || value.hasPrefix("utp-") || value == "encryption" || value.hasPrefix("blocklist-") { return "网络设置" }
        if value.contains("queue") { return "队列设置" }
        if value.contains("download-dir") || value.contains("incomplete") || value.contains("partial") || value.contains("seedratio") || value.contains("seeding-limit") || value.contains("start-added") || value.contains("trash-original") || value.contains("cache-size") { return "下载设置" }
        return "高级"
    }
    if value.hasPrefix("rss_") { return "RSS" }
    if value.hasPrefix("web_ui") || value.hasPrefix("bypass_") || value.hasPrefix("alternative_webui") || value.hasPrefix("dyndns_") || value == "use_https" { return "WebUI" }
    if value.hasPrefix("dl_limit") || value.hasPrefix("up_limit") || value.hasPrefix("alt_dl") || value.hasPrefix("alt_up") || value.hasPrefix("scheduler") || value.hasPrefix("schedule_") || value.hasPrefix("limit_") { return "速度" }
    if value.hasPrefix("listen_") || value == "upnp" || value.contains("port") || value.hasPrefix("max_connec") || value.hasPrefix("max_uploads") || value.hasPrefix("proxy_") { return "连接" }
    if value == "dht" || value == "pex" || value == "lsd" || value.contains("encryption") || value.contains("anonymous") || value.contains("queueing") || value.hasPrefix("max_active") || value.hasPrefix("slow_torrent") || value.hasPrefix("max_ratio") || value.hasPrefix("max_seeding") || value.hasPrefix("add_trackers") || value.hasPrefix("embedded_tracker") { return "BitTorrent" }
    if value.contains("save_path") || value.contains("temp_path") || value.hasPrefix("export_") || value.contains("incomplete") || value.hasPrefix("auto_tmm") || value.contains("category_changed") || value.contains("torrent_changed") || value.contains("preallocate") || value.contains("unwanted") || value.hasPrefix("mail_notification") || value.hasPrefix("autorun") || value.hasPrefix("add_to_top") || value.hasPrefix("add_stopped") { return "下载" }
    if value.hasPrefix("confirm_") || value.hasPrefix("file_log") || value.contains("performance_warning") || value.contains("status_bar") || value.contains("torrent_content_layout") { return "行为" }
    return "高级"
}

private func preferenceLabel(_ key: String) -> String {
    let labels: [String: String] = [
        "save_path": "默认保存路径", "download-dir": "默认保存目录", "temp_path": "临时目录",
        "temp_path_enabled": "启用临时目录", "incomplete-dir": "未完成目录", "incomplete-dir-enabled": "启用未完成目录",
        "dl_limit": "下载速度限制", "up_limit": "上传速度限制", "alt_dl_limit": "备用下载速度",
        "alt_up_limit": "备用上传速度", "speed-limit-down": "最大下载速度", "speed-limit-up": "最大上传速度",
        "speed-limit-down-enabled": "启用下载限速", "speed-limit-up-enabled": "启用上传限速",
        "alt-speed-down": "备用下载速度", "alt-speed-up": "备用上传速度", "alt-speed-enabled": "启用备用限速",
        "listen_port": "传入连接端口", "peer-port": "连接端口", "max_connec": "全局最大连接数",
        "max_connec_per_torrent": "单种最大连接数", "peer-limit-global": "全局 Peer 上限",
        "peer-limit-per-torrent": "单种 Peer 上限", "dht": "启用 DHT", "dht-enabled": "启用 DHT",
        "pex": "启用 PEX", "pex-enabled": "启用 PEX", "lsd": "启用本地发现", "lpd-enabled": "启用本地发现",
        "utp-enabled": "启用 µTP", "queueing_enabled": "启用队列管理", "download-queue-enabled": "启用下载队列",
        "download-queue-size": "最大同时下载数", "seed-queue-enabled": "启用上传队列", "seed-queue-size": "最大同时上传数",
        "max_active_downloads": "最大活动下载数", "max_active_uploads": "最大活动上传数", "max_active_torrents": "最大活动种子数",
        "max_ratio_enabled": "启用分享率限制", "max_ratio": "默认分享率上限", "seedRatioLimited": "启用做种分享率限制",
        "seedRatioLimit": "默认分享率上限", "rss_processing_enabled": "启用 RSS", "rss_auto_downloading_enabled": "启用 RSS 自动下载",
        "web_ui_address": "WebUI 监听地址", "web_ui_port": "WebUI 端口", "web_ui_username": "WebUI 用户名",
        "use_https": "WebUI 使用 HTTPS", "proxy_ip": "代理地址", "proxy_port": "代理端口",
        "proxy_username": "代理用户名", "proxy_password": "代理密码", "confirm_torrent_deletion": "删除种子前确认",
        "confirm_torrent_recheck": "重新校验前确认", "start-added-torrents": "自动启动新种子",
        "trash-original-torrent-files": "删除原始种子文件", "cache-size-mb": "磁盘缓存大小"
    ]
    if let label = labels[key] { return label }
    return key.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
}
