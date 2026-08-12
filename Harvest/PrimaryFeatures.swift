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

private func isDashboardRequestCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
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
        defer { isLoading = false }
        do {
            let query: [String: Any] = days.map { ["days": $0] } ?? [:]
            let raw = try await appState.api(APIPath.dashboard, query: query)
            snapshot = DashboardSnapshot(raw)
            lastUpdated = Date()
            cachedAt = nil
            usingCachedData = false
            await appState.writeSessionCache(raw, name: cacheKey)
        } catch {
            if !Task.isCancelled, !isDashboardRequestCancellation(error), !usingCachedData {
                appState.presentedError = error.localizedDescription
            }
        }
        guard !Task.isCancelled else { return }
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
            if !Task.isCancelled, !isDashboardRequestCancellation(error) {
                authorizationError = error.localizedDescription
            }
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

private enum DashboardModule: String, CaseIterable, Hashable, Identifiable {
    case hero
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

    static let defaultOrder: [DashboardModule] = [
        .hero, .overview, .userInfo, .quickActions, .siteStatus, .trend,
        .serverResources, .designation, .todayIncrement, .siteUploadDistribution,
        .siteDownloadDistribution, .seedDistribution, .usernameDistribution,
        .emailDistribution, .monthlyUpload, .monthlyDownload, .monthlyPublish
    ]

    static var defaultOrderRaw: String { encode(defaultOrder) }

    var title: String {
        switch self {
        case .hero: "仪表盘概览"
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
        case .hero: "gauge.with.dots.needle.67percent"
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
        if !seen.contains(DashboardModule.hero.rawValue) {
            decoded.insert(.hero, at: 0)
            seen.insert(DashboardModule.hero.rawValue)
        }
        decoded.append(contentsOf: defaultOrder.filter { !seen.contains($0.rawValue) })
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
            "dashboard.showHero",
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
    @AppStorage("dashboard.showHero") private var showHero = true
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
    @AppStorage("dashboard.moduleOrder") private var moduleOrderRaw = DashboardModule.defaultOrderRaw
    @State private var showSettings = false
    @State private var showCacheClear = false
    @State private var showShare = false
    @State private var shareImage: UIImage?
    @State private var runningQuickAction: DashboardQuickAction?
    @State private var showAccountAgeWeeks = false

    private var moduleOrder: [DashboardModule] { DashboardModule.decode(moduleOrderRaw) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                HStack {
                    Spacer()
                    Button { showSettings = true } label: {
                        Label("卡片设置", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(HarvestTheme.blue)
                    .accessibilityLabel("仪表盘卡片设置")
                }

                if model.isLoading {
                    LoadingState()
                } else {
                    if model.usingCachedData {
                        SessionCacheBanner(cachedAt: model.cachedAt)
                    }
                    ForEach(moduleOrder) { module in
                        dashboardModule(module)
                    }
                    if !hasVisibleModules {
                        EmptyState(
                            icon: "rectangle.grid.2x2",
                            title: "未显示仪表盘卡片",
                            detail: "可在卡片设置中重新启用需要的模块",
                            actionTitle: "打开卡片设置"
                        ) {
                            showSettings = true
                        }
                    }
                }
            }
            .padding(16)
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
                    .accessibilityLabel("仪表盘卡片设置")
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
                moduleOrderRaw: $moduleOrderRaw,
                moduleVisibilityBindings: moduleVisibilityBindings
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
        case .hero:
            if showHero {
                DashboardHeroView(
                    greeting: greeting,
                    updatedAt: model.lastUpdated,
                    serverConnected: model.serverConnected,
                    serverError: model.serverError,
                    snapshot: model.snapshot,
                    privacy: appState.privacyMode
                )
            }
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
                    accountAgeText: accountAgeText,
                    accountAgeDetail: accountAgeDetail,
                    onToggleAccountAge: { showAccountAgeWeeks.toggle() }
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

    private var hasVisibleModules: Bool {
        moduleOrder.contains { module in
            switch module {
            case .hero: showHero
            case .userInfo: showUserInfo
            case .serverResources: showServerResources
            case .designation: showDesignation
            case .overview: showOverview
            case .quickActions: showQuickActions
            case .trend: showTrend
            case .siteStatus: showSiteStatus
            case .usernameDistribution: showUsernameDistribution
            case .emailDistribution: showEmailDistribution
            case .siteUploadDistribution: showSiteUploadDistribution
            case .siteDownloadDistribution: showSiteDownloadDistribution
            case .todayIncrement: showTodayIncrement
            case .seedDistribution: showSeedDistribution
            case .monthlyUpload: showMonthlyUpload
            case .monthlyDownload: showMonthlyDownload
            case .monthlyPublish: showMonthlyPublish
            }
        }
    }

    private var moduleVisibilityBindings: [DashboardModule: Binding<Bool>] {
        [
            .hero: $showHero,
            .userInfo: $showUserInfo,
            .serverResources: $showServerResources,
            .designation: $showDesignation,
            .overview: $showOverview,
            .quickActions: $showQuickActions,
            .trend: $showTrend,
            .siteStatus: $showSiteStatus,
            .usernameDistribution: $showUsernameDistribution,
            .emailDistribution: $showEmailDistribution,
            .siteUploadDistribution: $showSiteUploadDistribution,
            .siteDownloadDistribution: $showSiteDownloadDistribution,
            .todayIncrement: $showTodayIncrement,
            .seedDistribution: $showSeedDistribution,
            .monthlyUpload: $showMonthlyUpload,
            .monthlyDownload: $showMonthlyDownload,
            .monthlyPublish: $showMonthlyPublish
        ]
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
        guard let joined = parseDate(model.snapshot.earliestJoinedAt) else { return "-" }
        let days = max(0, Calendar.current.dateComponents([.day], from: joined, to: Date()).day ?? 0)
        if showAccountAgeWeeks {
            let weeks = days / 7
            let remainingDays = days % 7
            return remainingDays == 0 ? "\(weeks)周" : "\(weeks)周\(remainingDays)天"
        }
        if days >= 365 {
            let years = days / 365
            let months = (days % 365) / 30
            return months > 0 ? "\(years)年\(months)个月" : "\(years)年"
        }
        if days >= 30 { return "\(days / 30)个月" }
        return "\(days)天"
    }

    private var accountAgeDetail: String {
        let mode = showAccountAgeWeeks ? "按周显示" : "按年显示"
        return model.snapshot.earliestSite.isEmpty ? mode : "\(mode) · \(model.snapshot.earliestSite)"
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
    let accountAgeDetail: String
    let onToggleAccountAge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "数据概览")

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

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                DashboardStatLine(
                    label: "做种数",
                    value: "\(snapshot.seeding)",
                    icon: "arrow.triangle.2.circlepath",
                    color: HarvestTheme.amber
                )
                DashboardStatLine(
                    label: "站点",
                    value: "\(snapshot.siteCount)",
                    icon: "globe.americas",
                    color: HarvestTheme.coral
                )
                DashboardStatLine(
                    label: "今日上传",
                    value: privateValue(formatBytes(snapshot.todayUploaded)),
                    icon: "arrow.up.right",
                    color: HarvestTheme.green
                )
                DashboardStatLine(
                    label: "今日下载",
                    value: privateValue(formatBytes(snapshot.todayDownloaded)),
                    icon: "arrow.down.right",
                    color: HarvestTheme.blue
                )
                DashboardStatLine(
                    label: "做种体积",
                    value: privateValue(formatBytes(snapshot.seedVolume)),
                    icon: "externaldrive.fill.badge.checkmark",
                    color: HarvestTheme.amber
                )
                DashboardStatLine(
                    label: "已发布",
                    value: "\(snapshot.published)",
                    icon: "paperplane.fill",
                    color: HarvestTheme.coral
                )
                DashboardStatLine(
                    label: "下载中",
                    value: "\(snapshot.leeching)",
                    icon: "arrow.down.circle.fill",
                    color: HarvestTheme.blue
                )
                Button(action: onToggleAccountAge) {
                    DashboardStatLine(
                        label: "P龄",
                        value: accountAgeText,
                        icon: "calendar",
                        color: HarvestTheme.green
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("P龄 \(accountAgeText)，\(accountAgeDetail)，点击切换显示方式")
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
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            SymbolBadge(icon: icon, color: color, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 36)
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

private struct DashboardSettingsSheet: View {
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
    let moduleVisibilityBindings: [DashboardModule: Binding<Bool>]
    @State private var modules: [DashboardModule]
    @State private var moduleVisibility: [DashboardModule: Bool]
    @State private var draftTrendDays: Int
    @State private var draftAutoRefresh: Bool
    @State private var draftRefreshInterval: Int
    @State private var draftServerResourceAutoStart: Bool
    @State private var draftServerResourceInterval: Int
    @State private var draftServerResourceDuration: Int
    @State private var draftChartHeight: Double
    @State private var draftItemLimit: Int

    init(
        trendDays: Binding<Int>,
        autoRefresh: Binding<Bool>,
        refreshInterval: Binding<Int>,
        serverResourceAutoStart: Binding<Bool>,
        serverResourceInterval: Binding<Int>,
        serverResourceDuration: Binding<Int>,
        chartHeight: Binding<Double>,
        itemLimit: Binding<Int>,
        moduleOrderRaw: Binding<String>,
        moduleVisibilityBindings: [DashboardModule: Binding<Bool>]
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
        self.moduleVisibilityBindings = moduleVisibilityBindings
        _modules = State(initialValue: DashboardModule.decode(moduleOrderRaw.wrappedValue))
        _moduleVisibility = State(initialValue: moduleVisibilityBindings.mapValues { $0.wrappedValue })
        _draftTrendDays = State(initialValue: trendDays.wrappedValue)
        _draftAutoRefresh = State(initialValue: autoRefresh.wrappedValue)
        _draftRefreshInterval = State(initialValue: refreshInterval.wrappedValue)
        _draftServerResourceAutoStart = State(initialValue: serverResourceAutoStart.wrappedValue)
        _draftServerResourceInterval = State(initialValue: serverResourceInterval.wrappedValue)
        _draftServerResourceDuration = State(initialValue: serverResourceDuration.wrappedValue)
        _draftChartHeight = State(initialValue: chartHeight.wrappedValue)
        _draftItemLimit = State(initialValue: itemLimit.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("趋势") {
                    Picker("数据天数", selection: $draftTrendDays) { ForEach([1, 7, 14, 30, 60, 90, 180], id: \.self) { Text($0 == 1 ? "今日" : "\($0) 天").tag($0) } }
                }
                Section("图表尺寸") {
                    LabeledContent("图表高度", value: "\(Int(draftChartHeight)) pt")
                    Slider(value: $draftChartHeight, in: DashboardChartDefaults.heightRange, step: 20) {
                        Text("图表高度")
                    } minimumValueLabel: {
                        Text("120").font(.caption2)
                    } maximumValueLabel: {
                        Text("480").font(.caption2)
                    }
                    Stepper(
                        "站点显示数量：\(draftItemLimit)",
                        value: $draftItemLimit,
                        in: DashboardChartDefaults.itemCountRange
                    )
                    Button { resetChartSizing() } label: {
                        Label("恢复默认尺寸", systemImage: "arrow.counterclockwise")
                    }
                }
                Section("自动刷新") {
                    Toggle("自动刷新仪表盘", isOn: $draftAutoRefresh)
                    Picker("刷新间隔", selection: $draftRefreshInterval) {
                        Text("1 分钟").tag(60)
                        Text("5 分钟").tag(300)
                        Text("15 分钟").tag(900)
                        Text("30 分钟").tag(1_800)
                    }
                    .disabled(!draftAutoRefresh)
                }
                Section("服务器资源监控") {
                    Toggle("进入页面自动监控", isOn: $draftServerResourceAutoStart)
                    Stepper(
                        "采样间隔：\(draftServerResourceInterval) 秒",
                        value: $draftServerResourceInterval,
                        in: DashboardServerRefreshDefaults.range
                    )
                    Stepper(
                        "自动停止：\(draftServerResourceDuration) 分钟",
                        value: $draftServerResourceDuration,
                        in: DashboardServerRefreshDefaults.range
                    )
                    Text("关闭自动监控时仅获取一次状态，也可在服务器资源卡片中手动开始连续监控。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button { resetServerResourceRefresh() } label: {
                        Label("恢复默认监控设置", systemImage: "arrow.counterclockwise")
                    }
                }
                Section("卡片顺序与显示") {
                    LabeledContent("已显示", value: "\(visibleModuleCount) / \(modules.count)")
                        .foregroundStyle(.secondary)
                    ForEach(modules) { module in
                        Toggle(isOn: visibilityBinding(for: module)) {
                            Label(module.title, systemImage: module.icon)
                        }
                    }
                    .onMove(perform: moveModules)
                    HStack(spacing: 12) {
                        Button("全部显示") { setAllModulesVisible(true) }
                            .frame(maxWidth: .infinity)
                        Divider()
                        Button("全部隐藏") { setAllModulesVisible(false) }
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        resetModules()
                    } label: {
                        Label("恢复默认顺序并全部显示", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("仪表盘卡片设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItemGroup(placement: .confirmationAction) {
                    EditButton()
                    Button("保存") { save() }
                }
            }
        }
    }

    private func visibilityBinding(for module: DashboardModule) -> Binding<Bool> {
        Binding(
            get: { moduleVisibility[module] ?? true },
            set: { moduleVisibility[module] = $0 }
        )
    }

    private func moveModules(from source: IndexSet, to destination: Int) {
        modules.move(fromOffsets: source, toOffset: destination)
    }

    private func resetModules() {
        modules = DashboardModule.defaultOrder
        moduleVisibility = Dictionary(uniqueKeysWithValues: DashboardModule.allCases.map { ($0, true) })
    }

    private var visibleModuleCount: Int {
        modules.lazy.filter { visibilityBinding(for: $0).wrappedValue }.count
    }

    private func setAllModulesVisible(_ visible: Bool) {
        for module in modules {
            visibilityBinding(for: module).wrappedValue = visible
        }
    }

    private func resetServerResourceRefresh() {
        draftServerResourceAutoStart = DashboardServerRefreshDefaults.autoStart
        draftServerResourceInterval = DashboardServerRefreshDefaults.interval
        draftServerResourceDuration = DashboardServerRefreshDefaults.duration
    }

    private func resetChartSizing() {
        draftChartHeight = DashboardChartDefaults.height
        draftItemLimit = DashboardChartDefaults.itemCount
    }

    private func save() {
        trendDays = draftTrendDays
        autoRefresh = draftAutoRefresh
        refreshInterval = draftRefreshInterval
        serverResourceAutoStart = draftServerResourceAutoStart
        serverResourceInterval = draftServerResourceInterval
        serverResourceDuration = draftServerResourceDuration
        chartHeight = draftChartHeight
        itemLimit = draftItemLimit
        moduleOrderRaw = DashboardModule.encode(modules)
        for (module, binding) in moduleVisibilityBindings {
            binding.wrappedValue = moduleVisibility[module] ?? true
        }
        dismiss()
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
                shareMetric("站点", "\(snapshot.siteCount)", HarvestTheme.coral)
                shareMetric("今日上传", privacy ? "••••" : formatBytes(snapshot.todayUploaded), HarvestTheme.green)
                shareMetric("今日下载", privacy ? "••••" : formatBytes(snapshot.todayDownloaded), HarvestTheme.blue)
                shareMetric("做种数", "\(snapshot.seeding)", HarvestTheme.amber)
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
