import Charts
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
