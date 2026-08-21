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
}

private enum DashboardMonthlyDefaults {
    static let visibleMonthCount = 3
    // The API also returns older month-end snapshots; 30 daily points stay below PostgreSQL's argument limit.
    static let historyDays = 30
    static let cacheKey = "dashboard.data"
    static let bootstrapCachePrefix = "dashboard.bootstrap.v1"
    static let legacyCacheKeys = [
        "dashboard.data.30",
        "dashboard.data.93",
        "dashboard.data.7",
        "dashboard.data.1",
        "dashboard.data.14",
        "dashboard.data.60",
        "dashboard.data.90",
        "dashboard.data.180",
        "dashboard.data.0"
    ]
    static let chartHeight = 176.0
}

private enum DashboardListLayout {
    static let visibleRows = 10
    static let siteRowHeight: CGFloat = 54
    static let distributionRowHeight: CGFloat = 46
    static let incrementRowHeight: CGFloat = 46
    static let accountRowHeight: CGFloat = 34
}

private func isDashboardRequestCancellation(_ error: Error) -> Bool {
    isRequestCancellation(error)
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

private struct DashboardRawPayload: @unchecked Sendable {
    let value: Any
}

struct DashboardSnapshot: @unchecked Sendable {
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

    var hasDisplayableData: Bool {
        siteCount > 0
            || uploaded > 0
            || downloaded > 0
            || seeding > 0
            || !siteStatuses.isEmpty
            || !siteHistory.isEmpty
            || !trends.isEmpty
    }

    var persistentPayload: [String: Any] {
        var payload: [String: Any] = [
            "totalUploaded": uploaded,
            "totalDownloaded": downloaded,
            "ratio": ratio,
            "siteCount": siteCount,
            "totalSeeding": seeding,
            "totalSeedVol": seedVolume,
            "totalLeeching": leeching,
            "totalPublished": published,
            "todayUploadIncrement": todayUploaded,
            "todayDownloadIncrement": todayDownloaded,
            "unread": unread,
            "updatedAt": updatedAt,
            "server": ["cpu": cpu, "memory": memory, "disk": disk],
            "statusList": siteStatuses.map { item -> [String: Any] in
                [
                    "name": item.name,
                    "value": [
                        "uploaded": item.uploaded,
                        "downloaded": item.downloaded,
                        "published": item.published
                    ] as [String: Any]
                ]
            },
            "uploadMonthIncrementDataList": siteHistory.map { series -> [String: Any] in
                [
                    "name": series.name,
                    "value": series.points.map { point -> [String: Any] in
                        [
                            "created_at": point.key,
                            "uploaded": point.uploaded,
                            "downloaded": point.downloaded,
                            "published": point.published
                        ]
                    }
                ]
            },
            "seedDataList": seedDistribution.map { ["name": $0.name, "value": $0.value] as [String: Any] },
            "uploadIncrementDataList": todayUploadDistribution.map { ["name": $0.name, "value": $0.value] as [String: Any] },
            "downloadIncrementDataList": todayDownloadDistribution.map { ["name": $0.name, "value": $0.value] as [String: Any] },
            "usernameCount": usernameDistribution.map { ["name": $0.name, "value": $0.value] as [String: Any] },
            "emailCount": emailDistribution.map { ["name": $0.name, "value": $0.value] as [String: Any] }
        ]
        if !earliestSite.isEmpty || !earliestJoinedAt.isEmpty {
            payload["earliestSite"] = ["site": earliestSite, "time_join": earliestJoinedAt]
        }
        return payload
    }

    var bootstrapPayload: [String: Any] {
        [
            "totalUploaded": uploaded,
            "totalDownloaded": downloaded,
            "ratio": ratio,
            "siteCount": siteCount,
            "totalSeeding": seeding,
            "totalSeedVol": seedVolume,
            "totalLeeching": leeching,
            "totalPublished": published,
            "todayUploadIncrement": todayUploaded,
            "todayDownloadIncrement": todayDownloaded,
            "unread": unread,
            "updatedAt": updatedAt,
            "server": ["cpu": cpu, "memory": memory, "disk": disk],
            "uploadMonthIncrementDataList": [
                [
                    "name": "summary",
                    "value": monthlyHistory.map { point -> [String: Any] in
                        [
                            "created_at": point.key,
                            "uploaded": point.uploaded,
                            "downloaded": point.downloaded,
                            "published": point.published
                        ]
                    }
                ]
            ]
        ]
    }

    init(_ raw: Any) {
        guard let root = jsonPayloadDictionary(raw) else { return }
        let overview = root.dict("overview", "summary", "statistics", "stats") ?? root
        uploaded = overview.double("totalUploaded", "total_uploaded", "uploaded", "upload", "upload_total", "total_upload") ?? 0
        downloaded = overview.double("totalDownloaded", "total_downloaded", "downloaded", "download", "download_total", "total_download") ?? 0
        let calculatedRatio = downloaded > 0 ? uploaded / downloaded : 0
        ratio = overview.double("ratio", "share_ratio") ?? (calculatedRatio.isFinite ? calculatedRatio : 0)
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

    init(sites: [SiteItem]) {
        let visibleSites = sites.filter(\.showInDashboard)
        siteCount = visibleSites.count
        uploaded = visibleSites.reduce(0) { $0 + max(0, $1.uploaded) }
        downloaded = visibleSites.reduce(0) { $0 + max(0, $1.downloaded) }
        ratio = downloaded > 0 ? uploaded / downloaded : 0
        seeding = visibleSites.reduce(0) { $0 + max(0, $1.seeding) }
        seedVolume = visibleSites.reduce(0) { $0 + max(0, $1.seedVolume) }
        leeching = visibleSites.reduce(0) { $0 + max(0, $1.leeching) }
        published = visibleSites.reduce(0) { $0 + max(0, $1.published) }
        todayUploaded = visibleSites.reduce(0) { $0 + max(0, $1.uploadDelta) }
        todayDownloaded = visibleSites.reduce(0) { $0 + max(0, $1.downloadDelta) }
        unread = visibleSites.reduce(0) { $0 + max(0, $1.unread) }

        siteStatuses = visibleSites.compactMap { site in
            guard site.uploaded > 0 || site.downloaded > 0 || site.published > 0 else { return nil }
            return DashboardSiteStatusItem(
                name: site.name,
                uploaded: site.uploaded,
                downloaded: site.downloaded,
                published: Double(site.published)
            )
        }
        .sorted { $0.uploaded > $1.uploaded }
        siteUploadDistribution = siteStatuses.map { DashboardDistributionItem(name: $0.name, value: $0.uploaded) }
            .filter { $0.value > 0 }
        siteDownloadDistribution = siteStatuses.map { DashboardDistributionItem(name: $0.name, value: $0.downloaded) }
            .filter { $0.value > 0 }
        seedDistribution = visibleSites.compactMap { site in
            guard site.seedVolume > 0 else { return nil }
            return DashboardDistributionItem(name: site.name, value: site.seedVolume)
        }
        .sorted { $0.value > $1.value }
        todayUploadDistribution = visibleSites.compactMap { site in
            guard site.uploadDelta > 0 else { return nil }
            return DashboardDistributionItem(name: site.name, value: site.uploadDelta)
        }
        .sorted { $0.value > $1.value }
        todayDownloadDistribution = visibleSites.compactMap { site in
            guard site.downloadDelta > 0 else { return nil }
            return DashboardDistributionItem(name: site.name, value: site.downloadDelta)
        }
        .sorted { $0.value > $1.value }

        siteHistory = visibleSites.compactMap { site in
            let points = site.statusHistory.compactMap { row -> DashboardSiteHistoryPoint? in
                guard let key = row.string("date", "created_at", "createdAt", "updated_at")?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !key.isEmpty else { return nil }
                return DashboardSiteHistoryPoint(
                    key: key,
                    uploaded: row.double("uploaded", "upload") ?? 0,
                    downloaded: row.double("downloaded", "download") ?? 0,
                    published: row.double("published", "publish") ?? 0
                )
            }
            guard !points.isEmpty else { return nil }
            return DashboardSiteHistorySeries(name: site.name, points: points)
        }
        monthlyHistory = dashboardMonthlyHistory(siteHistory)

        var trendTotals: [String: (upload: Double, download: Double)] = [:]
        for series in siteHistory {
            for point in series.points {
                let current = trendTotals[point.key] ?? (0, 0)
                trendTotals[point.key] = (current.upload + point.uploaded, current.download + point.downloaded)
            }
        }
        trends = trendTotals.keys.sorted().compactMap { key in
            guard let date = parseDate(key), let value = trendTotals[key] else { return nil }
            return TrendPoint(date: date, upload: value.upload, download: value.download)
        }

        func groupedDistribution(_ values: [String]) -> [DashboardDistributionItem] {
            var counts: [String: Double] = [:]
            for value in values {
                let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty { counts[key, default: 0] += 1 }
            }
            return counts.map { DashboardDistributionItem(name: $0.key, value: $0.value) }
                .sorted { $0.value > $1.value }
        }
        usernameDistribution = groupedDistribution(visibleSites.map(\.username))
        emailDistribution = groupedDistribution(visibleSites.map(\.email))

        if let earliest = visibleSites.compactMap({ site -> (site: SiteItem, date: Date)? in
            guard let date = parseDate(site.joinedAt) else { return nil }
            return (site, date)
        }).min(by: { $0.date < $1.date }) {
            earliestSite = earliest.site.name
            earliestJoinedAt = earliest.site.joinedAt
        }
        updatedAt = visibleSites.map(\.updatedAt).filter { !$0.isEmpty }.max() ?? ""
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

@MainActor
private func dashboardBootstrapCacheKey(_ appState: AppState) -> String? {
    let username = appState.profile?.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    guard !appState.baseURL.isEmpty, !username.isEmpty else { return nil }
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in "\(appState.baseURL)|\(username)".utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 1_099_511_628_211
    }
    return "\(DashboardMonthlyDefaults.bootstrapCachePrefix).\(String(hash, radix: 16))"
}

@MainActor
private func readDashboardBootstrapCache(_ appState: AppState) -> (snapshot: DashboardSnapshot, cachedAt: Date?)? {
    guard let key = dashboardBootstrapCacheKey(appState),
          let data = UserDefaults.standard.data(forKey: key),
          let raw = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
    let snapshot = DashboardSnapshot(raw)
    guard snapshot.hasDisplayableData else { return nil }
    let timestamp = UserDefaults.standard.double(forKey: "\(key).cachedAt")
    return (snapshot, timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil)
}

@MainActor
private func writeDashboardBootstrapCache(_ snapshot: DashboardSnapshot, appState: AppState, cachedAt: Date) {
    guard snapshot.hasDisplayableData,
          let key = dashboardBootstrapCacheKey(appState),
          JSONSerialization.isValidJSONObject(snapshot.bootstrapPayload),
          let data = try? JSONSerialization.data(withJSONObject: snapshot.bootstrapPayload) else { return }
    UserDefaults.standard.set(data, forKey: key)
    UserDefaults.standard.set(cachedAt.timeIntervalSince1970, forKey: "\(key).cachedAt")
}

@MainActor
private func removeDashboardBootstrapCache(_ appState: AppState) {
    guard let key = dashboardBootstrapCacheKey(appState) else { return }
    UserDefaults.standard.removeObject(forKey: key)
    UserDefaults.standard.removeObject(forKey: "\(key).cachedAt")
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
            guard let monthKey = dashboardMonthKey(point.key) else { continue }
            let current = totals[monthKey] ?? (0, 0, 0)
            totals[monthKey] = (
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

private func dashboardMonthKey(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let timestamp = Double(trimmed), timestamp.isFinite, timestamp >= 100_000_000 {
        let date = Date(timeIntervalSince1970: timestamp > 100_000_000_000 ? timestamp / 1_000 : timestamp)
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        if let year = components.year, let month = components.month {
            return String(format: "%04d-%02d", year, month)
        }
    }

    let normalized = trimmed
        .replacingOccurrences(of: "年", with: "-")
        .replacingOccurrences(of: "月", with: "-")
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ".", with: "-")
    let components = normalized.split(separator: "-", omittingEmptySubsequences: true)
    if components.count >= 2,
       let year = Int(components[0]),
       let month = Int(String(components[1].prefix { $0.isNumber })),
       (1...12).contains(month) {
        return String(format: "%04d-%02d", year, month)
    }

    guard let date = parseDate(trimmed) else { return nil }
    let dateComponents = Calendar.current.dateComponents([.year, .month], from: date)
    guard let year = dateComponents.year, let month = dateComponents.month else { return nil }
    return String(format: "%04d-%02d", year, month)
}

private func dashboardMonthKey(_ key: String, offset: Int) -> String? {
    let components = key.split(separator: "-")
    guard components.count == 2,
          let year = Int(components[0]),
          let month = Int(components[1]),
          (1...12).contains(month) else { return nil }
    let absoluteMonth = year * 12 + month - 1 + offset
    guard absoluteMonth >= 0 else { return nil }
    return String(format: "%04d-%02d", absoluteMonth / 12, absoluteMonth % 12 + 1)
}

private func dashboardRecentMonthlyPoints(
    _ points: [DashboardMonthlyPoint],
    count: Int = DashboardMonthlyDefaults.visibleMonthCount
) -> [DashboardMonthlyPoint] {
    guard count > 0 else { return [] }
    var valuesByMonth: [String: (uploaded: Double, downloaded: Double, published: Double)] = [:]
    for point in points {
        guard let monthKey = dashboardMonthKey(point.key) else { continue }
        let current = valuesByMonth[monthKey] ?? (0, 0, 0)
        let uploaded = current.uploaded + point.uploaded
        let downloaded = current.downloaded + point.downloaded
        let published = current.published + point.published
        valuesByMonth[monthKey] = (
            uploaded.isFinite ? uploaded : 0,
            downloaded.isFinite ? downloaded : 0,
            published.isFinite ? published : 0
        )
    }
    guard let latestMonth = valuesByMonth.keys.max() else { return [] }
    return (0..<count).reversed().compactMap { distance in
        guard let key = dashboardMonthKey(latestMonth, offset: -distance) else { return nil }
        let value = valuesByMonth[key] ?? (0, 0, 0)
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
        guard let amount = row.double("value", "count", "total", "size"), amount > 0 else { return nil }
        return DashboardDistributionItem(name: name, value: amount)
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
            let upload = current.upload + (row.double("uploaded", "upload", "up") ?? 0)
            let download = current.download + (row.double("downloaded", "download", "down") ?? 0)
            totals[key] = (
                upload.isFinite ? upload : 0,
                download.isFinite ? download : 0
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
        guard timestamp.isFinite, timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp > 100_000_000_000 ? timestamp / 1_000 : timestamp)
    }
    guard let text = value as? String else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let timestamp = Double(trimmed), timestamp.isFinite, timestamp > 0 {
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
            let text = dashboardAuthorizationText(nestedValue, privacy: privacy, key: nestedKey)
            return text.isEmpty ? nil : "\(dashboardAuthorizationLabel(nestedKey))：\(text)"
        }
        .sorted()
        .joined(separator: "；")
    }
    let text = String(describing: value)
    guard privacy else { return text }
    let normalizedKey = key.lowercased()
    if normalizedKey.contains("email") || normalizedKey.contains("mail") || text.contains("@") {
        return privacyMaskedText(text, enabled: true)
    }
    if normalizedKey.contains("username") || normalizedKey.contains("user_name") {
        return privacyMaskedText(text, enabled: true)
    }
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
    private var cacheRestoreTask: Task<Void, Never>?
    private var dashboardLoadInProgress = false
    private var downloaderSpeedTask: Task<Void, Never>?
    private var downloaderSpeedMonitoring = false
    private var downloaders: [DownloaderItem] = []

    var hasDisplayableData: Bool { snapshot.hasDisplayableData }

    func load(_ appState: AppState, days _: Int? = nil) async {
        guard !dashboardLoadInProgress else { return }
        let performanceInterval = HarvestPerformanceMonitor.shared.begin(.dashboardLoad)
        defer { performanceInterval.end() }
        dashboardLoadInProgress = true
        defer {
            dashboardLoadInProgress = false
            isLoading = false
        }

        let historyDays = DashboardMonthlyDefaults.historyDays
        let cacheKey = DashboardMonthlyDefaults.cacheKey
        if restoredCacheKey != cacheKey {
            restoredCacheKey = cacheKey
            restoreBootstrapSnapshot(appState)
            cacheRestoreTask?.cancel()
            cacheRestoreTask = Task { [weak self] in
                await self?.restoreCachedSnapshot(appState, cacheKey: cacheKey)
            }
        }
        isLoading = !usingCachedData && !hasDisplayableData
        if usingCachedData || hasDisplayableData { await Task.yield() }

        do {
            let raw = try await appState.api(
                APIPath.dashboard,
                query: ["days": historyDays],
                timeoutInterval: 15
            )
            await applyDashboardPayload(raw, appState: appState, cacheKey: cacheKey)
        } catch {
            handleDashboardLoadFailure(error, appState: appState)
        }
        guard !Task.isCancelled else { return }
        Task { [weak self] in
            guard let self else { return }
            async let authorizationLoad: Void = self.loadAuthorization(appState)
            async let downloaderLoad: Void = self.loadDownloaderSpeeds(appState)
            _ = await (authorizationLoad, downloaderLoad)
        }
    }

    private func restoreBootstrapSnapshot(_ appState: AppState) {
        guard let cached = readDashboardBootstrapCache(appState) else { return }
        snapshot = cached.snapshot
        lastUpdated = cached.cachedAt
        cachedAt = cached.cachedAt
        usingCachedData = true
        isLoading = false
    }

    private func restoreCachedSnapshot(_ appState: AppState, cacheKey: String) async {
        guard usingCachedData || !hasDisplayableData else { return }
        let candidateKeys = [cacheKey] + DashboardMonthlyDefaults.legacyCacheKeys
        for candidateKey in candidateKeys {
            guard let cached = await appState.readSessionCacheData(candidateKey) else { continue }
            let cachedSnapshot = await Task.detached(priority: .utility) { () -> DashboardSnapshot? in
                guard let raw = try? JSONSerialization.jsonObject(
                    with: cached.payload,
                    options: [.fragmentsAllowed]
                ),
                    let root = jsonPayloadDictionary(raw),
                    !root.isEmpty else { return nil }
                let snapshot = DashboardSnapshot(raw)
                return snapshot.hasDisplayableData ? snapshot : nil
            }.value
            guard let cachedSnapshot else { continue }
            guard usingCachedData || !hasDisplayableData else { return }
            snapshot = cachedSnapshot
            lastUpdated = cached.cachedAt
            cachedAt = cached.cachedAt
            usingCachedData = true
            isLoading = false
            writeDashboardBootstrapCache(cachedSnapshot, appState: appState, cachedAt: cached.cachedAt)
            if candidateKey != cacheKey {
                await appState.writeSessionCacheData(cached.payload, name: cacheKey)
            }
            return
        }

        if let cachedSites = await appState.readSessionCacheData("site.info.list") {
            let cachedSnapshot = await Task.detached(priority: .utility) {
                guard let raw = try? JSONSerialization.jsonObject(
                    with: cachedSites.payload,
                    options: [.fragmentsAllowed]
                ) else { return DashboardSnapshot([String: Any]()) }
                let sites = jsonRows(raw).map(SiteItem.init)
                return DashboardSnapshot(sites: sites)
            }.value
            if cachedSnapshot.hasDisplayableData, usingCachedData || !hasDisplayableData {
                snapshot = cachedSnapshot
                lastUpdated = cachedSites.cachedAt
                cachedAt = cachedSites.cachedAt
                usingCachedData = true
                isLoading = false
                recordAppLog(.info, "仪表盘已从本地站点缓存恢复")
                writeDashboardBootstrapCache(cachedSnapshot, appState: appState, cachedAt: cachedSites.cachedAt)
                await appState.writeSessionCache(cachedSnapshot.persistentPayload, name: cacheKey)
            }
        }
    }

    private func applyDashboardPayload(_ raw: Any, appState: AppState, cacheKey: String) async {
        let payload = DashboardRawPayload(value: raw)
        let parsedSnapshot = await Task.detached(priority: .userInitiated) {
            DashboardSnapshot(payload.value)
        }.value
        var updatedSnapshot = parsedSnapshot
        updatedSnapshot.uploadSpeed = snapshot.uploadSpeed
        updatedSnapshot.downloadSpeed = snapshot.downloadSpeed
        snapshot = updatedSnapshot
        let updatedDate = Date()
        lastUpdated = updatedDate
        cachedAt = nil
        usingCachedData = false
        writeDashboardBootstrapCache(updatedSnapshot, appState: appState, cachedAt: updatedDate)
        isLoading = false
        await Task.yield()
        await appState.writeSessionCache(updatedSnapshot.persistentPayload, name: cacheKey)
    }

    private func handleDashboardLoadFailure(_ error: Error, appState: AppState) {
        guard !Task.isCancelled, !isDashboardRequestCancellation(error) else { return }
        recordAppLog(.error, "仪表盘数据加载失败：\(error.localizedDescription)")
        if usingCachedData || hasDisplayableData {
            cachedAt = cachedAt ?? lastUpdated
            usingCachedData = true
        } else {
            appState.presentedError = "仪表盘数据加载失败，请稍后重试"
        }
        isLoading = false
    }

    func startDownloaderSpeedMonitoring(_ appState: AppState) {
        downloaderSpeedMonitoring = true
        guard downloaderSpeedTask == nil || downloaderSpeedTask?.isCancelled == true else { return }
        downloaderSpeedTask = Task { [weak self] in
            await self?.watchDownloaderSpeeds(appState)
        }
    }

    func stopDownloaderSpeedMonitoring() {
        downloaderSpeedMonitoring = false
        downloaderSpeedTask?.cancel()
        downloaderSpeedTask = nil
    }

    private func loadDownloaderSpeeds(_ appState: AppState) async {
        do {
            let raw = try await appState.api(APIPath.downloaders, query: ["with_status": true])
            guard !Task.isCancelled else { return }
            downloaders = jsonRows(raw).map(DownloaderItem.init)
            applyDownloaderSpeeds()
        } catch {
            guard !Task.isCancelled, !isDashboardRequestCancellation(error) else { return }
            recordAppLog(.warning, "仪表盘读取下载器速度失败：\(error.localizedDescription)")
        }
    }

    private func watchDownloaderSpeeds(_ appState: AppState) async {
        var lastErrorMessage = ""
        while downloaderSpeedMonitoring, !Task.isCancelled {
            do {
                let stream = APIClient.shared.streamWebSocket(
                    baseURL: appState.baseURL,
                    path: APIPath.downloaderSpeed,
                    token: appState.accessToken,
                    subscription: ["interval": 5]
                )
                for try await event in stream {
                    guard downloaderSpeedMonitoring, !Task.isCancelled else { return }
                    lastErrorMessage = ""
                    let data = (event["data"] as? [String: Any]) ?? jsonPayloadDictionary(event) ?? [:]
                    guard !data.isEmpty else { continue }
                    var liveByKey: [String: [String: Any]] = [:]
                    for (key, value) in data {
                        if let value = value as? [String: Any] {
                            liveByKey[key.lowercased()] = value
                        }
                    }
                    var updated = downloaders
                    var changed = false
                    for index in updated.indices {
                        let downloader = updated[index]
                        let websocketKey = "\(downloader.name)-\(downloader.id)-\(downloader.category)".lowercased()
                        guard let live = liveByKey[websocketKey] ?? liveByKey[String(downloader.id)] else { continue }
                        var merged = downloader.raw
                        merged["status"] = live
                        updated[index] = DownloaderItem(merged)
                        changed = true
                    }
                    guard changed else { continue }
                    downloaders = updated
                    applyDownloaderSpeeds()
                }
            } catch {
                guard downloaderSpeedMonitoring, !Task.isCancelled else { return }
                let message = error.localizedDescription
                if message != lastErrorMessage {
                    recordAppLog(.warning, "仪表盘下载器速度连接中断：\(message)")
                    lastErrorMessage = message
                }
            }
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
        }
    }

    private func applyDownloaderSpeeds() {
        let enabledDownloaders = downloaders.filter(\.enabled)
        var updatedSnapshot = snapshot
        updatedSnapshot.uploadSpeed = enabledDownloaders.reduce(0) { $0 + max(0, $1.uploadSpeed) }
        updatedSnapshot.downloadSpeed = enabledDownloaders.reduce(0) { $0 + max(0, $1.downloadSpeed) }
        snapshot = updatedSnapshot
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
                    snapshot = updatedSnapshot
                    let serverUploadSpeed = network?.double("uploadSpeed", "upload_speed") ?? 0
                    let serverDownloadSpeed = network?.double("downloadSpeed", "download_speed") ?? 0
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
                        uploadSpeed: serverUploadSpeed,
                        downloadSpeed: serverDownloadSpeed,
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
    case accountDistribution
    case siteUploadDistribution
    case siteDownloadDistribution
    case todayIncrement
    case seedDistribution
    case monthlyUpload
    case monthlyDownload
    case monthlyPublish

    var id: String { rawValue }

    static let defaultOrder: [DashboardModule] = [
        .hero, .designation, .overview, .userInfo, .quickActions, .siteStatus, .trend,
        .serverResources, .todayIncrement, .siteUploadDistribution,
        .siteDownloadDistribution, .seedDistribution, .accountDistribution,
        .monthlyUpload, .monthlyDownload, .monthlyPublish
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
        case .accountDistribution: "账号分布"
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
        case .accountDistribution: "person.text.rectangle"
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
        var decoded = raw.split(separator: ",").compactMap { value -> DashboardModule? in
            let rawValue = String(value)
            if rawValue == "usernameDistribution" || rawValue == "emailDistribution" {
                return .accountDistribution
            }
            return DashboardModule(rawValue: rawValue)
        }
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
        let feedbackID = appState.beginManualTask("正在清理本机缓存")
        let defaults = UserDefaults.standard
        let keys = [
            "privacyMode",
            "media.tmdbEnabled",
            "media.doubanEnabled",
            "search.history",
            "search.maxCount",
            "search.sitesEnabled",
            "search.siteIDs",
            "site.filter.query",
            "site.filter.availability",
            "site.filter.condition",
            "site.filter.selectedTags",
            "site.filter.activeTags",
            "site.filter.selectedTypes",
            "site.filter.selectedUsername",
            "site.filter.selectedEmail",
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
        BrandMarkStore.restoreDefault()
        removeDashboardBootstrapCache(appState)
        await appState.clearSessionCache()
        appState.setPrivacyMode(false)
        appState.setMediaTMDBEnabled(false)
        appState.setMediaDoubanEnabled(false)
        NotificationCenter.default.post(name: .harvestLocalUIReset, object: nil)
        statusMessage = "本机页面缓存与界面设置已清理"
        appState.requestAutomaticRefresh(force: true)
        await onCleared()
        appState.finishManualTask(feedbackID, success: true, message: "本机缓存已清理")
    }
}

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = DashboardViewModel()
    @AppStorage("dashboard.trendDays") private var trendDays = 7
    @AppStorage("dashboard.autoRefresh") private var autoRefresh = true
    @AppStorage("dashboard.refreshInterval") private var refreshInterval = 300
    @AppStorage("dashboard.chartHeight") private var chartHeight = DashboardChartDefaults.height
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
    @AppStorage("dashboard.moduleOrder.designationAboveOverview.v1") private var didMigrateDesignationOrder = false
    @State private var showSettings = false
    @State private var showCacheClear = false
    @State private var showShare = false
    @State private var shareImage: UIImage?
    @State private var isRenderingShare = false
    @State private var runningQuickAction: DashboardQuickAction?
    @State private var showAccountAgeWeeks = false
    @State private var dashboardGlowRotation = 0.0

    private var moduleOrder: [DashboardModule] { DashboardModule.decode(moduleOrderRaw) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if model.isLoading && !model.usingCachedData && !model.hasDisplayableData {
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
        .environment(\.flowingGlowRotation, dashboardGlowRotation)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 8) {
                Spacer()
                Button { showSettings = true } label: {
                    FlowingSymbolBadge(
                        icon: "slider.horizontal.3",
                        color: HarvestTheme.blue,
                        size: 34,
                        glowRotation: dashboardGlowRotation
                    )
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.58), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
                .accessibilityLabel("仪表盘卡片设置")
                Button { showCacheClear = true } label: {
                    FlowingSymbolBadge(
                        icon: "trash",
                        color: HarvestTheme.coral,
                        size: 34,
                        glowRotation: dashboardGlowRotation
                    )
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.58), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
                .accessibilityLabel("缓存清理")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .refreshable { await model.load(appState, days: trendDays) }
        .onAppear {
            migrateDesignationOrderIfNeeded()
            updateDashboardGlowAnimation()
        }
        .onDisappear { stopDashboardGlowAnimation() }
        .onChange(of: reduceMotion) { _, _ in updateDashboardGlowAnimation() }
        .task(id: "\(trendDays)-\(autoRefresh)-\(refreshInterval)") {
            await model.load(appState, days: trendDays)
            guard !Task.isCancelled else { return }
            model.startDownloaderSpeedMonitoring(appState)
            guard autoRefresh else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(max(30, refreshInterval)))
                if !Task.isCancelled { await model.load(appState, days: trendDays) }
            }
        }
        .task(id: "\(model.isLoading)-\(showServerResources)-\(serverResourceAutoStart)-\(serverResourceInterval)-\(serverResourceDuration)") {
            guard !model.isLoading else { return }
            model.configureServerMonitoring(
                appState,
                visible: showServerResources,
                autoStart: serverResourceAutoStart,
                interval: serverResourceInterval,
                duration: serverResourceDuration
            )
        }
        .onDisappear {
            model.stopServerMonitoring()
            model.stopDownloaderSpeedMonitoring()
        }
        .navigationTitle("仪表盘")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button { Task { await runGlobal(APIPath.siteStatus) } } label: { Label("刷新全部站点", systemImage: "arrow.clockwise") }
                    Button { Task { await runGlobal(APIPath.siteSign) } } label: { Label("全部站点签到", systemImage: "checkmark.seal") }
                    Button { showCacheClear = true } label: { Label("缓存清理", systemImage: "trash.slash") }
                } label: {
                    FlowingSymbolBadge(
                        icon: "bolt.fill",
                        color: HarvestTheme.amber,
                        size: 26,
                        glowRotation: dashboardGlowRotation
                    )
                }
                .accessibilityLabel("仪表盘快捷操作")
                Button {
                    Task { await renderShareImage() }
                } label: {
                    FlowingSymbolBadge(
                        icon: "square.and.arrow.up",
                        color: HarvestTheme.blue,
                        size: 26,
                        glowRotation: dashboardGlowRotation,
                        showsProgress: isRenderingShare
                    )
                }
                    .disabled(isRenderingShare)
                    .accessibilityLabel("分享仪表盘长图")
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

    private func updateDashboardGlowAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dashboardGlowRotation = reduceMotion ? 42 : 0
        }
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 3.6).repeatForever(autoreverses: false)) {
            dashboardGlowRotation = 360
        }
    }

    private func stopDashboardGlowAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dashboardGlowRotation = 0
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
                DashboardTrafficTrendView(
                    points: model.snapshot.trends,
                    days: trendDays,
                    height: CGFloat(chartHeight)
                )
            }
        case .siteStatus:
            if showSiteStatus && !model.snapshot.siteStatuses.isEmpty {
                DashboardSiteStatusView(items: model.snapshot.siteStatuses, privacy: appState.privacyMode)
            }
        case .serverResources:
            if showServerResources {
                DashboardServerResourcesView(
                    model: model,
                    hostLabel: serverHostLabel,
                    refreshInterval: serverResourceInterval
                )
            }
        case .accountDistribution:
            if (showUsernameDistribution || showEmailDistribution)
                && (!model.snapshot.usernameDistribution.isEmpty || !model.snapshot.emailDistribution.isEmpty) {
                DashboardAccountDistributionView(
                    usernames: model.snapshot.usernameDistribution,
                    emails: model.snapshot.emailDistribution,
                    privacy: appState.privacyMode
                )
            }
        case .siteUploadDistribution:
            if showSiteUploadDistribution && !model.snapshot.siteUploadDistribution.isEmpty {
                DistributionView(title: module.title, items: model.snapshot.siteUploadDistribution, metric: .bytes(.upload), privacy: appState.privacyMode)
            }
        case .siteDownloadDistribution:
            if showSiteDownloadDistribution && !model.snapshot.siteDownloadDistribution.isEmpty {
                DistributionView(title: module.title, items: model.snapshot.siteDownloadDistribution, metric: .bytes(.download), privacy: appState.privacyMode)
            }
        case .todayIncrement:
            if showTodayIncrement {
                DashboardIncrementRankingView(
                    items: model.snapshot.siteIncrements(days: trendDays),
                    days: trendDays,
                    privacy: appState.privacyMode
                )
            }
        case .seedDistribution:
            if showSeedDistribution && !model.snapshot.seedDistribution.isEmpty {
                DistributionView(title: module.title, items: model.snapshot.seedDistribution, metric: .bytes(.seed), privacy: appState.privacyMode)
            }
        case .monthlyUpload:
            if showMonthlyUpload && !model.snapshot.monthlyHistory.isEmpty {
                DashboardMonthlyMetricView(metric: .upload, points: model.snapshot.monthlyHistory)
            }
        case .monthlyDownload:
            if showMonthlyDownload && !model.snapshot.monthlyHistory.isEmpty {
                DashboardMonthlyMetricView(metric: .download, points: model.snapshot.monthlyHistory)
            }
        case .monthlyPublish:
            if showMonthlyPublish && !model.snapshot.monthlyHistory.isEmpty {
                DashboardMonthlyMetricView(metric: .publish, points: model.snapshot.monthlyHistory)
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
            case .accountDistribution: showUsernameDistribution || showEmailDistribution
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
            .accountDistribution: Binding(
                get: { showUsernameDistribution || showEmailDistribution },
                set: { value in
                    showUsernameDistribution = value
                    showEmailDistribution = value
                }
            ),
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
        let username = privacyMaskedText(appState.profile?.username ?? "用户", enabled: appState.privacyMode)
        return "\(text)，\(username)"
    }

    private var serverHostLabel: String {
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
        let siteName = privacyMaskedText(model.snapshot.earliestSite, enabled: appState.privacyMode)
        return siteName.isEmpty ? mode : "\(mode) · \(siteName)"
    }

    private func migrateDesignationOrderIfNeeded() {
        guard !didMigrateDesignationOrder else { return }
        var modules = DashboardModule.decode(moduleOrderRaw)
        modules.removeAll { $0 == .designation }
        let overviewIndex = modules.firstIndex(of: .overview) ?? modules.startIndex
        modules.insert(.designation, at: overviewIndex)
        moduleOrderRaw = DashboardModule.encode(modules)
        didMigrateDesignationOrder = true
    }

    @MainActor private func runGlobal(_ path: String) async {
        let endpoint = path.hasSuffix("/") ? String(path.dropLast()) : path
        let signing = path == APIPath.siteSign
        _ = await appState.runManualTask(
            title: signing ? "正在为全部站点签到" : "正在刷新全部站点",
            successMessage: signing ? "全部站点签到完成" : "全部站点数据已更新"
        ) {
            guard await appState.perform(endpoint, method: .get, showsFeedback: false) else { return false }
            await model.load(appState, days: trendDays)
            return appState.presentedError == nil
        }
    }

    @MainActor private func runQuickAction(_ action: DashboardQuickAction) async {
        guard runningQuickAction == nil else { return }
        runningQuickAction = action
        defer { runningQuickAction = nil }
        switch action {
        case .refreshSites:
            await runGlobal(APIPath.siteStatus)
        case .refreshDashboard:
            await appState.runManualRefresh(title: "正在刷新仪表盘", successMessage: "仪表盘已更新") {
                await model.load(appState, days: trendDays)
            }
        case .signSites:
            await runGlobal(APIPath.siteSign)
        }
    }

    @MainActor private func renderShareImage() async {
        guard !isRenderingShare else { return }
        isRenderingShare = true
        let feedbackID = appState.beginManualTask("正在生成仪表盘长图")
        defer { isRenderingShare = false }
        await Task.yield()
        let renderer = ImageRenderer(content: DashboardShareContent(
            snapshot: model.snapshot,
            profile: appState.profile,
            authorizationInfo: model.authorizationInfo,
            authorizationError: model.authorizationError,
            serverPoint: model.latestServerPoint,
            rangeDays: trendDays,
            privacy: appState.privacyMode
        ))
        renderer.scale = min(UIScreen.main.scale, 2)
        guard let image = renderer.uiImage else {
            appState.finishManualTask(feedbackID, success: false, message: "长图生成失败")
            appState.presentedError = "仪表盘长图生成失败"
            return
        }
        shareImage = image
        showShare = true
        appState.finishManualTask(feedbackID, success: true, message: "长图已生成")
    }
}

private struct DashboardTrafficTrendView: View {
    let points: [TrendPoint]
    let days: Int
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "流量趋势", subtitle: "最近同步周期")
            Chart(Array(points.suffix(max(1, days)))) { point in
                LineMark(x: .value("时间", point.date), y: .value("上传", point.upload))
                    .foregroundStyle(HarvestTheme.green)
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("时间", point.date), y: .value("下载", point.download))
                    .foregroundStyle(HarvestTheme.blue)
                    .interpolationMethod(.catmullRom)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(dashboardCompactBytes(number)).font(.caption2)
                        }
                    }
                }
            }
            .frame(height: height)
        }
        .cardSurface()
    }
}

private struct DashboardServerResourcesView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var model: DashboardViewModel
    let hostLabel: String
    let refreshInterval: Int

    private var peakSpeed: Double {
        model.serverHistory.map { max($0.uploadSpeed, $0.downloadSpeed) }.max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            hostSummary
            ResourceRow(label: "CPU", value: model.snapshot.cpu, color: HarvestTheme.coral)
            cpuDetails
            ResourceRow(label: "内存", value: model.snapshot.memory, color: HarvestTheme.amber)
            memoryDetails
            transferSummary
            cumulativeTransferSummary
            historyCharts
        }
        .cardSurface()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("服务器资源").font(.title3.weight(.bold))
                if let error = model.serverError {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                } else if model.serverMonitoring {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("每 \(refreshInterval) 秒采样 · \(model.serverCountdownText(at: context.date)) 后停止")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("实时监控已停止").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button { model.toggleServerMonitoring(appState) } label: {
                FlowingSymbolBadge(
                    icon: model.serverMonitoring ? "pause.fill" : "play.fill",
                    color: model.serverMonitoring ? HarvestTheme.amber : HarvestTheme.green,
                    size: 30
                )
                .frame(width: 40, height: 40)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.serverMonitoring ? "暂停服务器资源监控" : "开始服务器资源监控")
        }
    }

    private var hostSummary: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                FlowingSymbolBadge(
                    icon: model.latestServerPoint?.isDocker == true ? "shippingbox" : "server.rack",
                    color: HarvestTheme.blue,
                    size: 20
                )
                Text(hostLabel)
            }
            .lineLimit(1)
            Spacer()
            if let latest = model.latestServerPoint {
                Text(latest.date.formatted(date: .omitted, time: .standard))
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var cpuDetails: some View {
        if let latest = model.latestServerPoint {
            HStack {
                Text("\(latest.cpuLimitCores.formatted(.number.precision(.fractionLength(1)))) 核")
                Spacer()
                Text("累计 \(latest.cpuUsageSeconds.formatted(.number.precision(.fractionLength(1)))) 秒")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var memoryDetails: some View {
        if let latest = model.latestServerPoint {
            HStack {
                Text("工作集 \(dashboardCompactBytes(latest.memoryWorkingSet))")
                Spacer()
                Text("上限 \(dashboardCompactBytes(latest.memoryLimit))")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var transferSummary: some View {
        HStack {
            HStack(spacing: 4) {
                FlowingSymbolBadge(icon: "arrow.down", color: HarvestTheme.blue, size: 18)
                Text(formatSpeed(model.latestServerPoint?.downloadSpeed ?? 0))
            }
                .foregroundStyle(HarvestTheme.blue)
            Spacer()
            HStack(spacing: 4) {
                FlowingSymbolBadge(icon: "arrow.up", color: HarvestTheme.green, size: 18)
                Text(formatSpeed(model.latestServerPoint?.uploadSpeed ?? 0))
            }
                .foregroundStyle(HarvestTheme.green)
        }
        .font(.caption.monospacedDigit())
    }

    @ViewBuilder private var cumulativeTransferSummary: some View {
        if let latest = model.latestServerPoint {
            HStack {
                Text("累计下载 \(dashboardCompactBytes(latest.bytesReceived))")
                Spacer()
                Text("累计上传 \(dashboardCompactBytes(latest.bytesSent))")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var historyCharts: some View {
        if model.serverHistory.count > 1 {
            Divider()
            chartLegend(
                first: ("CPU", HarvestTheme.coral),
                second: ("内存", HarvestTheme.amber)
            )
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

            if peakSpeed > 0 {
                chartLegend(
                    first: ("下载", HarvestTheme.blue),
                    second: ("上传", HarvestTheme.green)
                )
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
                            if let speed = value.as(Double.self) {
                                Text(formatSpeed(speed)).font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 120)
            }
        }
    }

    private func chartLegend(
        first: (label: String, color: Color),
        second: (label: String, color: Color)
    ) -> some View {
        HStack(spacing: 16) {
            Label(first.label, systemImage: "circle.fill").foregroundStyle(first.color)
            Label(second.label, systemImage: "circle.fill").foregroundStyle(second.color)
            Spacer()
        }
        .font(.caption2)
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
                FlowingSymbolBadge(icon: "chart.xyaxis.line", color: statusColor, size: 44)
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

            HStack(alignment: .top, spacing: 0) {
                heroMetric(
                    label: "站点",
                    value: "\(snapshot.siteCount)",
                    detail: snapshot.unread > 0 ? "\(snapshot.unread) 条未读" : nil,
                    color: HarvestTheme.coral
                )
                Divider().frame(height: 46)
                heroMetric(
                    label: "下载速度",
                    value: formatSpeed(snapshot.downloadSpeed),
                    detail: "实时",
                    color: HarvestTheme.blue
                )
                Divider().frame(height: 46)
                heroMetric(
                    label: "上传速度",
                    value: formatSpeed(snapshot.uploadSpeed),
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

    private func heroMetric(label: String, value: String, detail: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
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
                    value: dashboardCompactBytes(snapshot.uploaded),
                    icon: "arrow.up",
                    color: HarvestTheme.green
                )
                Divider().frame(height: 46)
                overviewPrimaryMetric(
                    label: "总下载",
                    value: dashboardCompactBytes(snapshot.downloaded),
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
                    value: dashboardCompactBytes(snapshot.todayUploaded),
                    icon: "arrow.up.right",
                    color: HarvestTheme.green
                )
                DashboardStatLine(
                    label: "今日下载",
                    value: dashboardCompactBytes(snapshot.todayDownloaded),
                    icon: "arrow.down.right",
                    color: HarvestTheme.blue
                )
                DashboardStatLine(
                    label: "做种体积",
                    value: dashboardCompactBytes(snapshot.seedVolume),
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

    private func overviewPrimaryMetric(label: String, value: String, detail: String? = nil, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                FlowingSymbolBadge(icon: icon, color: color, size: 22)
                Text(label)
            }
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

}

private struct DashboardStatLine: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            FlowingSymbolBadge(icon: icon, color: color, size: 32)
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
        return privacyMaskedText(profile.username, enabled: privacy)
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
                FlowingSymbolBadge(icon: "person.crop.circle.fill", color: HarvestTheme.blue, size: 44)
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
                    FlowingSymbolBadge(
                        icon: "rectangle.portrait.and.arrow.right",
                        color: HarvestTheme.coral,
                        size: 30
                    )
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
            HStack(spacing: 5) {
                FlowingSymbolBadge(icon: icon, color: color, size: 22)
                Text(label)
            }
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
                FlowingSymbolBadge(icon: "medal.fill", color: HarvestTheme.coral, size: 44)
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
                            FlowingSymbolBadge(
                                icon: action.icon,
                                color: action.color,
                                size: 42,
                                showsProgress: running == action
                            )
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
    let privacy: Bool

    private var maximumUpload: Double {
        max(items.map(\.uploaded).filter { $0.isFinite }.max() ?? 1, 1)
    }

    private var maximumDownload: Double {
        max(items.map(\.downloaded).filter { $0.isFinite }.max() ?? 1, 1)
    }

    var body: some View {
        DashboardScrollableModule(
            title: "站点状态",
            subtitle: "累计上传 / 下载对比",
            icon: "globe.asia.australia.fill",
            color: HarvestTheme.blue,
            itemCount: items.count,
            rowHeight: DashboardListLayout.siteRowHeight
        ) {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            dashboardRank(index + 1, color: HarvestTheme.blue, compact: true)
                            Text(privacyMaskedText(item.name, enabled: privacy))
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if item.published > 0 {
                                HStack(spacing: 4) {
                                    FlowingSymbolBadge(icon: "paperplane", color: HarvestTheme.coral, size: 18)
                                    Text(formatCompactNumber(item.published))
                                }
                                    .font(.caption2.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(HarvestTheme.coral)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(HarvestTheme.coral.opacity(0.10), in: Capsule())
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        HStack(spacing: 8) {
                            dashboardCapacityMetric(
                                item.uploaded,
                                maximum: maximumUpload,
                                icon: "arrow.up",
                                color: HarvestTheme.green,
                                emphasizesLeadingEdge: index < 3
                            )
                            dashboardCapacityMetric(
                                item.downloaded,
                                maximum: maximumDownload,
                                icon: "arrow.down",
                                color: HarvestTheme.blue,
                                emphasizesLeadingEdge: index < 3
                            )
                        }
                        .padding(.leading, 20)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: DashboardListLayout.siteRowHeight)
                    .overlay(alignment: .bottom) {
                        if index < items.count - 1 { Divider().padding(.leading, 10) }
                    }
                }
            }
        }
    }

    private func dashboardCapacityMetric(
        _ value: Double,
        maximum: Double,
        icon: String,
        color: Color,
        emphasizesLeadingEdge: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                FlowingSymbolBadge(icon: icon, color: color, size: 18)
                Text(dashboardCompactBytes(value))
            }
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            DashboardMetricBar(
                value: value,
                maximum: maximum,
                color: color,
                height: 5,
                emphasizesLeadingEdge: emphasizesLeadingEdge
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardIncrementRankingView: View {
    let items: [DashboardSiteIncrementItem]
    let days: Int
    let privacy: Bool

    private var maximumUpload: Double {
        max(items.map(\.uploaded).filter { $0.isFinite }.max() ?? 1, 1)
    }

    private var maximumDownload: Double {
        max(items.map(\.downloaded).filter { $0.isFinite }.max() ?? 1, 1)
    }

    private var rangeLabel: String {
        days == 1 ? "当日增量排行" : "近 \(days) 天增量排行"
    }

    var body: some View {
        DashboardScrollableModule(
            title: rangeLabel,
            subtitle: "上传与下载增量",
            icon: "chart.bar.xaxis",
            color: HarvestTheme.green,
            itemCount: items.count,
            rowHeight: DashboardListLayout.incrementRowHeight
        ) {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            dashboardRank(index + 1, color: HarvestTheme.green)
                            Text(privacyMaskedText(item.name, enabled: privacy))
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            incrementMetric(item.uploaded, icon: "arrow.up", color: HarvestTheme.green)
                            incrementMetric(item.downloaded, icon: "arrow.down", color: HarvestTheme.blue)
                        }
                        HStack(spacing: 6) {
                            DashboardMetricBar(
                                value: item.uploaded,
                                maximum: maximumUpload,
                                color: HarvestTheme.green,
                                height: 5,
                                emphasizesLeadingEdge: index < 3
                            )
                            DashboardMetricBar(
                                value: item.downloaded,
                                maximum: maximumDownload,
                                color: HarvestTheme.blue,
                                height: 5,
                                emphasizesLeadingEdge: index < 3
                            )
                        }
                        .padding(.leading, 20)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: DashboardListLayout.incrementRowHeight)
                    .overlay(alignment: .bottom) {
                        if index < items.count - 1 { Divider().padding(.leading, 10) }
                    }
                }
            }
        }
    }

    private func incrementMetric(_ value: Double, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            FlowingSymbolBadge(icon: icon, color: color, size: 18)
            Text(dashboardCompactBytes(value))
        }
            .font(.caption2.weight(.medium).monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.66)
            .frame(width: 82, alignment: .trailing)
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
        case .upload, .download: dashboardCompactBytes(value)
        case .publish: "\(formatCompactNumber(value)) 个"
        }
    }
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

private struct DashboardMonthlyMetricView: View {
    let metric: DashboardMonthlyMetric
    let points: [DashboardMonthlyPoint]

    private var visiblePoints: [DashboardMonthlyPoint] { dashboardRecentMonthlyPoints(points) }
    private var total: Double { visiblePoints.reduce(0) { $0 + metric.value($1) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.title).font(.title3.weight(.bold))
                    Text("近 3 个月对比").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(metric.format(total)).font(.subheadline.weight(.semibold))
                    Text("三月合计").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Chart(visiblePoints) { point in
                BarMark(
                    x: .value("周期", dashboardMonthLabel(point.key)),
                    y: .value(metric.title, metric.value(point)),
                    width: .fixed(38)
                )
                .foregroundStyle(metric.color)
                .cornerRadius(7)
                .annotation(position: .top, spacing: 4) {
                    Text(metric.format(metric.value(point)))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(metric.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(metric == .publish ? formatCompactNumber(number) : dashboardCompactBytes(number)).font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: visiblePoints.map { dashboardMonthLabel($0.key) }) { _ in
                    AxisValueLabel().font(.caption.weight(.medium))
                }
            }
            .frame(height: CGFloat(DashboardMonthlyDefaults.chartHeight))
        }
        .cardSurface()
    }
}

private enum DashboardDistributionMetric {
    case count
    case bytes(DashboardDistributionByteKind)

    var color: Color {
        switch self {
        case .count: HarvestTheme.coral
        case .bytes(.upload): HarvestTheme.green
        case .bytes(.download): HarvestTheme.blue
        case .bytes(.seed): HarvestTheme.amber
        }
    }

    var icon: String? {
        switch self {
        case .count: nil
        case .bytes(.upload): "arrow.up"
        case .bytes(.download): "arrow.down"
        case .bytes(.seed): "externaldrive.fill"
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .count: formatCompactNumber(value)
        case .bytes: dashboardCompactBytes(value)
        }
    }
}

private enum DashboardDistributionByteKind {
    case upload
    case download
    case seed
}

private struct DistributionView: View {
    let title: String
    let items: [DashboardDistributionItem]
    let metric: DashboardDistributionMetric
    let privacy: Bool

    var body: some View {
        DashboardScrollableModule(
            title: title,
            subtitle: "站点容量排行",
            icon: metric.icon ?? "chart.bar.fill",
            color: metric.color,
            itemCount: items.count,
            rowHeight: DashboardListLayout.distributionRowHeight
        ) {
            let maximum = max(items.map(\.value).filter { $0.isFinite }.max() ?? 1, 1)
            let total = max(
                items.reduce(0) { result, item in
                    result + (item.value.isFinite ? max(item.value, 0) : 0)
                },
                1
            )
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            dashboardRank(index + 1, color: metric.color)
                            Text(privacyMaskedText(item.name, enabled: privacy))
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 4) {
                                if let icon = metric.icon {
                                    FlowingSymbolBadge(icon: icon, color: metric.color, size: 18)
                                }
                                Text(metric.format(item.value))
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(metric.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .frame(width: 86, alignment: .trailing)
                            Text(dashboardPercentage(item.value, total: total))
                                .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(metric.color)
                                .frame(width: 34, alignment: .trailing)
                        }
                        DashboardMetricBar(
                            value: item.value,
                            maximum: maximum,
                            color: metric.color,
                            height: 7,
                            emphasizesLeadingEdge: index < 3
                        )
                        .padding(.leading, 20)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: DashboardListLayout.distributionRowHeight)
                    .overlay(alignment: .bottom) {
                        if index < items.count - 1 { Divider().padding(.leading, 10) }
                    }
                }
            }
        }
    }
}

private struct DashboardMetricBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Double
    let maximum: Double
    let color: Color
    var height: CGFloat = 6
    var emphasizesLeadingEdge = false
    @State private var shimmerPhase = 0.0

    private var progress: Double {
        guard value.isFinite, maximum.isFinite, maximum > 0 else { return 0 }
        return min(max(value / maximum, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let filledWidth = proxy.size.width * progress
            let shimmerWidth = min(max(filledWidth * 0.24, 10), 30)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.065))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.48), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Capsule()
                        .stroke(color.opacity(0.34), lineWidth: 0.6)
                    if reduceMotion {
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.72)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: min(shimmerWidth, filledWidth))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    } else if emphasizesLeadingEdge, filledWidth > 2 {
                        let shimmerOffset = -shimmerWidth + (filledWidth + shimmerWidth) * shimmerPhase
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.92),
                                color.opacity(0.30),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: shimmerWidth, height: height + 4)
                        .offset(x: shimmerOffset)
                        .blur(radius: 0.35)
                    }
                }
                    .frame(width: filledWidth)
                    .clipShape(Capsule())
                    .shadow(
                        color: emphasizesLeadingEdge ? color.opacity(0.24) : .clear,
                        radius: 4,
                        x: 0,
                        y: 1
                    )
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 2.2).repeatForever(autoreverses: false), value: shimmerPhase)
        .onAppear {
            guard !reduceMotion, emphasizesLeadingEdge, progress > 0 else { return }
            shimmerPhase = 1
        }
        .onChange(of: reduceMotion) { _, isReduced in
            if isReduced {
                shimmerPhase = 0
            } else if emphasizesLeadingEdge, progress > 0 {
                shimmerPhase = 1
            }
        }
        .accessibilityHidden(true)
    }
}

private func dashboardPercentage(_ value: Double, total: Double) -> String {
    guard value.isFinite, total.isFinite, value > 0, total > 0 else { return "0%" }
    let percentage = value / total * 100
    if percentage >= 10 { return String(format: "%.0f%%", percentage) }
    return String(format: "%.1f%%", percentage)
}

private struct DashboardAccountDistributionView: View {
    let usernames: [DashboardDistributionItem]
    let emails: [DashboardDistributionItem]
    let privacy: Bool
    @State private var selection = AccountDistributionKind.username

    private var selectedItems: [DashboardDistributionItem] {
        selection == .username ? usernames : emails
    }

    var body: some View {
        DashboardScrollableModule(
            title: "账号分布",
            subtitle: selection == .username ? "用户名使用分布" : "邮箱使用分布",
            icon: "person.text.rectangle",
            color: HarvestTheme.coral,
            itemCount: selectedItems.count,
            rowHeight: DashboardListLayout.accountRowHeight,
            contentHeightAdjustment: 38
        ) {
            LazyVStack(spacing: 0) {
                Picker("账号类型", selection: $selection) {
                    ForEach(AccountDistributionKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.icon).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 6)
                .frame(height: 38)

                ForEach(Array(selectedItems.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 6) {
                        dashboardRank(index + 1, color: HarvestTheme.coral)
                        Text(privacyMaskedText(item.name, enabled: privacy))
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(selection == .email ? 0.68 : 0.82)
                            .allowsTightening(true)
                            .layoutPriority(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(formatCompactNumber(item.value))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(HarvestTheme.coral)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: DashboardListLayout.accountRowHeight)
                    .overlay(alignment: .bottom) {
                        if index < selectedItems.count - 1 { Divider().padding(.leading, 8) }
                    }
                }
            }
        }
    }
}

private enum AccountDistributionKind: String, CaseIterable, Identifiable {
    case username
    case email

    var id: String { rawValue }

    var title: String {
        switch self {
        case .username: "用户名"
        case .email: "邮箱"
        }
    }

    var icon: String {
        switch self {
        case .username: "person.fill"
        case .email: "envelope.fill"
        }
    }
}

private func dashboardRank(_ rank: Int, color: Color, compact: Bool = false) -> some View {
    Circle()
        .fill(rank <= 3 ? color : Color.secondary.opacity(0.35))
        .frame(width: compact ? 7 : 8, height: compact ? 7 : 8)
        .overlay {
            if rank <= 3 {
                Circle().stroke(color.opacity(0.24), lineWidth: 2)
            }
        }
        .frame(width: compact ? 8 : 9, height: compact ? 22 : 22)
        .accessibilityLabel("第\(rank)名")
}

private struct DashboardScrollableModule<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let itemCount: Int
    let rowHeight: CGFloat
    let contentHeightAdjustment: CGFloat
    let content: Content

    init(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        itemCount: Int,
        rowHeight: CGFloat,
        contentHeightAdjustment: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.color = color
        self.itemCount = itemCount
        self.rowHeight = rowHeight
        self.contentHeightAdjustment = contentHeightAdjustment
        self.content = content()
    }

    private var visibleRowCount: Int { min(max(itemCount, 1), DashboardListLayout.visibleRows) }
    private var viewportHeight: CGFloat {
        CGFloat(visibleRowCount) * rowHeight + contentHeightAdjustment
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                FlowingSymbolBadge(icon: icon, color: color, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline.weight(.bold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                Spacer(minLength: 4)
                Text("\(itemCount) 项")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(color.opacity(0.10), in: Capsule())
            }

            ScrollView(.vertical) {
                content
            }
            .frame(height: viewportHeight)
            .scrollDisabled(itemCount <= DashboardListLayout.visibleRows)
            .scrollIndicators(itemCount > DashboardListLayout.visibleRows ? .visible : .hidden)
            .scrollBounceBehavior(.basedOnSize)
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.clear, color.opacity(0.28), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
            }
        }
        .padding(10)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(0.16), Color.primary.opacity(0.045), color.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .shadow(color: color.opacity(0.045), radius: 12, x: 0, y: 6)
    }
}

private func dashboardCompactBytes(_ bytes: Double) -> String {
    guard bytes.isFinite, bytes > 0 else { return "0 KB" }
    let units = ["KB", "MB", "GB", "TB", "PB", "EB"]
    var value = max(bytes, 0) / 1_024
    var unitIndex = 0
    while value >= 1_024, unitIndex < units.count - 1 {
        value /= 1_024
        unitIndex += 1
    }
    let format = value >= 100 ? "%.0f %@" : value >= 10 ? "%.1f %@" : "%.2f %@"
    return String(format: format, value, units[unitIndex])
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
    @State private var isEditingModules = false

    private let moduleColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    init(
        trendDays: Binding<Int>,
        autoRefresh: Binding<Bool>,
        refreshInterval: Binding<Int>,
        serverResourceAutoStart: Binding<Bool>,
        serverResourceInterval: Binding<Int>,
        serverResourceDuration: Binding<Int>,
        chartHeight: Binding<Double>,
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
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("趋势") {
                    Picker("数据天数", selection: $draftTrendDays) { ForEach([1, 7, 14, 30, 60, 90, 180], id: \.self) { Text($0 == 1 ? "今日" : "\($0) 天").tag($0) } }
                }
                Section("图表与列表") {
                    LabeledContent("图表高度", value: "\(Int(draftChartHeight)) pt")
                    Slider(value: $draftChartHeight, in: DashboardChartDefaults.heightRange, step: 20) {
                        Text("图表高度")
                    } minimumValueLabel: {
                        Text("120").font(.caption2)
                    } maximumValueLabel: {
                        Text("480").font(.caption2)
                    }
                    LabeledContent("列表可视行数", value: "10")
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
                    LazyVGrid(columns: moduleColumns, spacing: 8) {
                        ForEach(Array(modules.enumerated()), id: \.element.id) { index, module in
                            moduleTile(module, at: index)
                        }
                    }
                    .padding(.vertical, 4)
                    HStack(spacing: 8) {
                        Button {
                            setAllModulesVisible(true)
                        } label: {
                            Label("全部显示", systemImage: "eye")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            setAllModulesVisible(false)
                        } label: {
                            Label("全部隐藏", systemImage: "eye.slash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
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
                    Button(isEditingModules ? "完成" : "编辑") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditingModules.toggle()
                        }
                    }
                    Button("保存") { save() }
                }
            }
        }
    }

    @ViewBuilder
    private func moduleTile(_ module: DashboardModule, at index: Int) -> some View {
        if isEditingModules {
            HStack(spacing: 7) {
                moduleLabel(module)
                Spacer(minLength: 2)
                VStack(spacing: 2) {
                    moduleMoveButton(systemImage: "chevron.up", module: module, index: index, offset: -1)
                    moduleMoveButton(systemImage: "chevron.down", module: module, index: index, offset: 1)
                }
            }
            .dashboardModuleTileSurface()
        } else {
            Button {
                moduleVisibility[module] = !(moduleVisibility[module] ?? true)
            } label: {
                HStack(spacing: 7) {
                    moduleLabel(module)
                    Spacer(minLength: 2)
                    Image(systemName: (moduleVisibility[module] ?? true) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle((moduleVisibility[module] ?? true) ? Color.accentColor : Color.secondary)
                }
                .dashboardModuleTileSurface()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(module.title)
            .accessibilityValue((moduleVisibility[module] ?? true) ? "显示" : "隐藏")
        }
    }

    private func moduleLabel(_ module: DashboardModule) -> some View {
        HStack(spacing: 7) {
            Image(systemName: module.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            Text(module.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func moduleMoveButton(
        systemImage: String,
        module: DashboardModule,
        index: Int,
        offset: Int
    ) -> some View {
        Button {
            moveModule(at: index, by: offset)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 20)
        }
        .buttonStyle(.borderless)
        .disabled(index + offset < modules.startIndex || index + offset >= modules.endIndex)
        .accessibilityLabel("将\(module.title)\(offset < 0 ? "前移" : "后移")")
    }

    private func visibilityBinding(for module: DashboardModule) -> Binding<Bool> {
        Binding(
            get: { moduleVisibility[module] ?? true },
            set: { moduleVisibility[module] = $0 }
        )
    }

    private func moveModule(at index: Int, by offset: Int) {
        let destination = index + offset
        guard modules.indices.contains(index), modules.indices.contains(destination) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            modules.swapAt(index, destination)
        }
    }

    private func resetModules() {
        modules = DashboardModule.defaultOrder
        moduleVisibility = Dictionary(
            DashboardModule.allCases.map { ($0, true) },
            uniquingKeysWith: { current, _ in current }
        )
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
    }

    private func save() {
        trendDays = draftTrendDays
        autoRefresh = draftAutoRefresh
        refreshInterval = draftRefreshInterval
        serverResourceAutoStart = draftServerResourceAutoStart
        serverResourceInterval = draftServerResourceInterval
        serverResourceDuration = draftServerResourceDuration
        chartHeight = draftChartHeight
        moduleOrderRaw = DashboardModule.encode(modules)
        for (module, binding) in moduleVisibilityBindings {
            binding.wrappedValue = moduleVisibility[module] ?? true
        }
        dismiss()
    }
}

private extension View {
    func dashboardModuleTileSurface() -> some View {
        self
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DashboardShareContent: View {
    let snapshot: DashboardSnapshot
    let profile: UserProfile?
    let authorizationInfo: [String: Any]?
    let authorizationError: String?
    let serverPoint: DashboardServerPoint?
    let rangeDays: Int
    let privacy: Bool

    private let shareItemLimit = DashboardListLayout.visibleRows

    private var username: String {
        guard let profile else { return "未登录" }
        return privacyMaskedText(profile.username, enabled: privacy)
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
                shareMetric("总上传", dashboardCompactBytes(snapshot.uploaded), HarvestTheme.green)
                shareMetric("总下载", dashboardCompactBytes(snapshot.downloaded), HarvestTheme.blue)
                shareMetric("做种体积", dashboardCompactBytes(snapshot.seedVolume), HarvestTheme.amber)
                shareMetric("站点", "\(snapshot.siteCount)", HarvestTheme.coral)
                shareMetric("今日上传", dashboardCompactBytes(snapshot.todayUploaded), HarvestTheme.green)
                shareMetric("今日下载", dashboardCompactBytes(snapshot.todayDownloaded), HarvestTheme.blue)
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
            let visibleTrends = Array(snapshot.trends.suffix(max(1, rangeDays)))
            if !visibleTrends.isEmpty {
                shareSectionTitle("流量趋势", subtitle: rangeDays == 1 ? "今日" : "最近 \(rangeDays) 天")
                Chart(visibleTrends) { point in
                    LineMark(x: .value("日期", point.date), y: .value("上传", point.upload)).foregroundStyle(HarvestTheme.green)
                    LineMark(x: .value("日期", point.date), y: .value("下载", point.download)).foregroundStyle(HarvestTheme.blue)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel {
                            if let number = value.as(Double.self) { Text(dashboardCompactBytes(number)).font(.caption2) }
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
                            Text(privacyMaskedText(item.name, enabled: privacy)).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Label(dashboardCompactBytes(item.uploaded), systemImage: "arrow.up").foregroundStyle(HarvestTheme.green)
                            Label(dashboardCompactBytes(item.downloaded), systemImage: "arrow.down").foregroundStyle(HarvestTheme.blue)
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
                            Text(privacyMaskedText(item.name, enabled: privacy)).font(.subheadline.weight(.semibold)).lineLimit(1)
                            HStack {
                                Label(dashboardCompactBytes(item.uploaded), systemImage: "arrow.up")
                                    .foregroundStyle(HarvestTheme.green)
                                Spacer()
                                Label(dashboardCompactBytes(item.downloaded), systemImage: "arrow.down")
                                    .foregroundStyle(HarvestTheme.blue)
                            }
                                .font(.caption.monospacedDigit())
                        }
                        .padding(14)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous))
                    }
                }
            }
            let distributions: [(String, [DashboardDistributionItem], DashboardDistributionMetric)] = [
                ("站点上传分布", snapshot.siteUploadDistribution, .bytes(.upload)),
                ("站点下载分布", snapshot.siteDownloadDistribution, .bytes(.download)),
                ("做种分布", snapshot.seedDistribution, .bytes(.seed))
            ]
            if distributions.contains(where: { !$0.1.isEmpty }) {
                shareSectionTitle("数据分布", subtitle: "各项前 \(shareItemLimit) 名")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(Array(distributions.enumerated()), id: \.offset) { _, distribution in
                        if !distribution.1.isEmpty {
                            shareDistribution(distribution.0, items: distribution.1, metric: distribution.2)
                        }
                    }
                }
            }
            if !snapshot.usernameDistribution.isEmpty || !snapshot.emailDistribution.isEmpty {
                shareAccountDistribution()
            }
            if !snapshot.monthlyHistory.isEmpty {
                shareSectionTitle("月度统计", subtitle: "近 3 个月对比")
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

    private func shareDistribution(
        _ title: String,
        items: [DashboardDistributionItem],
        metric: DashboardDistributionMetric
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            let maximum = max(items.map(\.value).max() ?? 1, 1)
            ForEach(items.prefix(shareItemLimit)) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(privacyMaskedText(item.name, enabled: privacy)).lineLimit(1); Spacer(); Text(metric.format(item.value)).monospacedDigit() }
                        .font(.caption)
                    ProgressView(value: item.value, total: maximum).tint(metric.color)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous))
    }

    private func shareAccountDistribution() -> some View {
        let usernames = Array(snapshot.usernameDistribution.prefix(shareItemLimit))
        let emails = Array(snapshot.emailDistribution.prefix(shareItemLimit))
        let count = max(usernames.count, emails.count)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("账号分布", systemImage: "person.text.rectangle").font(.headline)
                Spacer()
                Text("用户名 / 邮箱").font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                shareAccountColumn("用户名", items: usernames, count: count)
                Divider()
                shareAccountColumn("邮箱", items: emails, count: count)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous))
    }

    private func shareAccountColumn(
        _ title: String,
        items: [DashboardDistributionItem],
        count: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: 6) {
                    dashboardRank(index + 1, color: HarvestTheme.coral, compact: true)
                    if items.indices.contains(index) {
                        let item = items[index]
                        Text(privacyMaskedText(item.name, enabled: privacy))
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                            .layoutPriority(1)
                        Spacer(minLength: 2)
                        Text(formatCompactNumber(item.value))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func shareMonthlyMetric(_ metric: DashboardMonthlyMetric) -> some View {
        let points = dashboardRecentMonthlyPoints(snapshot.monthlyHistory)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(metric.title).font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(metric.format(points.reduce(0) { $0 + metric.value($1) }))
                        .font(.caption.weight(.semibold))
                    Text("三月合计").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Chart(points) { point in
                BarMark(
                    x: .value("周期", dashboardMonthLabel(point.key)),
                    y: .value(metric.title, metric.value(point)),
                    width: .fixed(48)
                )
                    .foregroundStyle(metric.color)
                    .cornerRadius(8)
                    .annotation(position: .top, spacing: 6) {
                        Text(metric.format(metric.value(point)))
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(metric.color)
                    }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(metric == .publish ? formatCompactNumber(number) : dashboardCompactBytes(number)).font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: points.map { dashboardMonthLabel($0.key) }) { _ in
                    AxisValueLabel().font(.caption.weight(.medium))
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
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = controller.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

struct ResourceRow: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        let safeValue = value.isFinite ? min(max(value, 0), 100) : 0
        VStack(spacing: 7) {
            HStack { Text(label).font(.subheadline.weight(.semibold)); Spacer(); Text("\(clampedInt(safeValue))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            ProgressView(value: safeValue, total: 100).tint(color)
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
