import Charts
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    case unsigned = "未签到"
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
    case lastVisit = "最后活跃时间"
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

    var icon: String {
        switch self {
        case .updated: "clock.arrow.circlepath"
        case .name: "globe"
        case .nickname: "textformat"
        case .joined: "calendar"
        case .lastVisit: "clock"
        case .seedVolume: "externaldrive.fill"
        case .magic: "bolt.fill"
        case .score: "diamond.fill"
        case .uploaded, .uploadDelta: "arrow.up"
        case .downloaded, .downloadDelta: "arrow.down"
        case .published: "paperplane.fill"
        case .bonusHour: "timer"
        case .invitations: "person.fill"
        case .leeching: "arrow.down.circle.fill"
        case .seeding: "leaf.fill"
        case .ratio: "arrow.triangle.2.circlepath"
        case .sortID: "number"
        }
    }
}

private enum SiteFilterStorageKey {
    static let query = "site.filter.query"
    static let availability = "site.filter.availability"
    static let condition = "site.filter.condition"
    static let selectedTags = "site.filter.selectedTags"
    static let selectedTypes = "site.filter.selectedTypes"
    static let selectedUsername = "site.filter.selectedUsername"
    static let selectedEmail = "site.filter.selectedEmail"
    static let sortField = "site.filter.sortField"
    static let ascending = "site.filter.ascending"
}

enum SiteLevelMilestone {
    case keepAccount
    case graduation
}

private struct SiteBrowserTarget: Identifiable {
    let site: SiteItem
    let url: String
    let config: [String: Any]
    var id: Int { site.id }
}

@MainActor
final class SitesViewModel: ObservableObject {
    private(set) var sites: [SiteItem] = [] { didSet { rebuildFilteredSites() } }
    @Published private(set) var filtered: [SiteItem] = []
    private var siteConfigs: [String: [String: Any]] = [:] { didSet { rebuildFilteredSites() } }
    @Published var isLoading = true
    @Published private(set) var usingCachedData = false
    @Published private(set) var cachedAt: Date?
    @Published var query = "" {
        didSet {
            UserDefaults.standard.set(query, forKey: SiteFilterStorageKey.query)
            rebuildFilteredSites()
        }
    }
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
    @Published var selectedTags: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(selectedTags.sorted(), forKey: SiteFilterStorageKey.selectedTags)
            rebuildFilteredSites()
        }
    }
    @Published var selectedTypes: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(selectedTypes.sorted(), forKey: SiteFilterStorageKey.selectedTypes)
            rebuildFilteredSites()
        }
    }
    @Published var selectedUsername = "" {
        didSet {
            UserDefaults.standard.set(selectedUsername, forKey: SiteFilterStorageKey.selectedUsername)
            rebuildFilteredSites()
        }
    }
    @Published var selectedEmail = "" {
        didSet {
            UserDefaults.standard.set(selectedEmail, forKey: SiteFilterStorageKey.selectedEmail)
            rebuildFilteredSites()
        }
    }
    private var didRestoreCache = false

    init() {
        let defaults = UserDefaults.standard
        query = defaults.string(forKey: SiteFilterStorageKey.query) ?? ""
        if let value = defaults.string(forKey: SiteFilterStorageKey.availability),
           let restored = SiteAvailabilityFilter(rawValue: value) {
            availability = restored
        }
        if let value = defaults.string(forKey: SiteFilterStorageKey.condition),
           let restored = SiteConditionFilter(rawValue: value) {
            condition = restored
        }
        if let value = defaults.string(forKey: SiteFilterStorageKey.sortField) {
            if value == "最后访问" {
                sortField = .lastVisit
            } else if let restored = SiteSortField(rawValue: value) {
                sortField = restored
            }
        }
        selectedTags = Set(defaults.stringArray(forKey: SiteFilterStorageKey.selectedTags) ?? [])
        selectedTypes = Set(defaults.stringArray(forKey: SiteFilterStorageKey.selectedTypes) ?? [])
        selectedUsername = defaults.string(forKey: SiteFilterStorageKey.selectedUsername) ?? ""
        selectedEmail = defaults.string(forKey: SiteFilterStorageKey.selectedEmail) ?? ""
        ascending = defaults.object(forKey: SiteFilterStorageKey.ascending) == nil
            ? sortField.defaultAscending
            : defaults.bool(forKey: SiteFilterStorageKey.ascending)
    }

    private func rebuildFilteredSites() {
        filtered = computeFilteredSites()
    }

    private func computeFilteredSites() -> [SiteItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchTerms = normalizedQuery
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
        let values = sites.filter { site in
            if !searchTerms.isEmpty {
                let config = config(for: site)
                let searchableValues = [
                    site.name, site.siteKey, site.url, site.username, site.email, site.userID,
                    site.level, site.siteType, resolvedSiteType(for: site)
                ]
                    + site.tags
                    + [config?.string("name", "site"), config?.string("nickname"), config?.string("tracker")].compactMap { $0 }
                    + (config.map { configStrings($0["url"]) } ?? [])
                let matches = searchTerms.allSatisfy { term in
                    let compactTerm = compactSiteSearchText(term)
                    return searchableValues.contains { value in
                        value.localizedCaseInsensitiveContains(term)
                            || (!compactTerm.isEmpty && compactSiteSearchText(value).contains(compactTerm))
                    }
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
            case .hasNewNotification: if site.mail <= 0 && site.notice <= 0 { return false }
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
            case .lowRatio: if site.statusHistory.isEmpty || site.ratio >= 1 { return false }
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
            if comparison == .orderedSame { return left.id < right.id }
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
    var activeFilterCount: Int {
        var count = 0
        if availability != .alive { count += 1 }
        if condition != .all { count += 1 }
        count += selectedTags.count + selectedTypes.count
        if !selectedUsername.isEmpty { count += 1 }
        if !selectedEmail.isEmpty { count += 1 }
        return count
    }
    var hasFilters: Bool {
        activeFilterCount > 0
    }

    func clearFilters() {
        availability = .alive
        condition = .all
        selectedTags = []
        selectedTypes = []
        selectedUsername = ""
        selectedEmail = ""
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: SiteFilterStorageKey.availability)
        defaults.removeObject(forKey: SiteFilterStorageKey.condition)
        defaults.removeObject(forKey: SiteFilterStorageKey.selectedTags)
        defaults.removeObject(forKey: SiteFilterStorageKey.selectedTypes)
        defaults.removeObject(forKey: SiteFilterStorageKey.selectedUsername)
        defaults.removeObject(forKey: SiteFilterStorageKey.selectedEmail)
    }

    func resetFilters() {
        query = ""
        clearFilters()
        sortField = .updated
        ascending = SiteSortField.updated.defaultAscending
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: SiteFilterStorageKey.query)
        defaults.removeObject(forKey: SiteFilterStorageKey.sortField)
        defaults.removeObject(forKey: SiteFilterStorageKey.ascending)
    }

    func selectSortField(_ field: SiteSortField) {
        if sortField == field {
            ascending.toggle()
            return
        }
        setSortField(field)
    }

    func setSortField(_ field: SiteSortField) {
        sortField = field
        ascending = field.defaultAscending
    }

    func showActiveSites() {
        clearSummaryConflictingFilters()
        availability = .alive
        condition = .all
    }

    func showPendingSignInSites() {
        clearSummaryConflictingFilters()
        availability = .alive
        condition = .unsigned
    }

    func showUnreadSites() {
        clearSummaryConflictingFilters()
        availability = .all
        condition = .hasNewNotification
    }

    private func clearSummaryConflictingFilters() {
        query = ""
        selectedTags = []
        selectedTypes = []
        selectedUsername = ""
        selectedEmail = ""
    }

    func levelRules(for site: SiteItem) -> Any? {
        config(for: site)?["level"]
    }

    func browserURL(for site: SiteItem) -> String {
        let directURL = site.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !directURL.isEmpty { return directURL }
        guard let siteConfig = config(for: site) else { return "" }
        return configStrings(siteConfig["url"]).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
        let displayName = privacyMaskedText(site.name, enabled: appState.privacyMode)
        let title: String
        let successMessage: String
        if path == APIPath.siteSign {
            title = "正在为\(displayName)签到"
            successMessage = "\(displayName)签到完成"
        } else if path == APIPath.siteRepeat {
            title = "正在为\(displayName)辅种"
            successMessage = "\(displayName)辅种任务已提交"
        } else {
            title = "正在刷新\(displayName)"
            successMessage = "\(displayName)数据已更新"
        }
        _ = await appState.runManualTask(title: title, successMessage: successMessage) {
            guard await appState.perform(path + "\(site.id)", method: .get, showsFeedback: false) else {
                return false
            }
            await load(appState, cached: false)
            return appState.presentedError == nil
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

    func config(for site: SiteItem) -> [String: Any]? {
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
            for fileExtension in ["gif", "png", "jpg", "jpeg", "webp", "ico"] {
                let relative = "local/icons/\(urlPathSegment(siteName)).\(fileExtension)"
                guard let url = URL(string: relative, relativeTo: serverURL)?.absoluteURL else { continue }
                if seen.insert(url.absoluteString).inserted {
                    candidates.append(RemoteImageCandidate(
                        url: url,
                        headers: headers,
                        persistentCacheID: "site-icon|\(url.absoluteString)"
                    ))
                }
            }
        }

        if let url = logoURL(for: site), seen.insert(url.absoluteString).inserted {
            candidates.append(RemoteImageCandidate(
                url: url,
                persistentCacheID: "site-icon|\(url.absoluteString)"
            ))
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

    func milestone(for site: SiteItem) -> SiteLevelMilestone? {
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
    @State private var browserTarget: SiteBrowserTarget?
    @State private var levelSite: SiteItem?
    @State private var signInSite: SiteItem?
    @State private var editingSite: SiteItem?
    @State private var deletingSite: SiteItem?
    @State private var repeatingSite: SiteItem?
    @State private var isRunningGlobalAction = false

    var body: some View {
        VStack(spacing: 0) {
            if model.usingCachedData {
                SessionCacheBanner(cachedAt: model.cachedAt)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            SiteSearchFilterBar(model: model) { showFilters = true }
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
                        else { model.resetFilters() }
                    }
                } else {
                    SiteListSummaryBar(
                        visibleCount: model.filtered.count,
                        totalCount: model.sites.count,
                        activeCount: model.activeSiteCount,
                        pendingSignInCount: model.pendingSignInCount,
                        unreadCount: model.unreadCount,
                        showActiveSites: model.showActiveSites,
                        showPendingSignInSites: model.showPendingSignInSites,
                        showUnreadSites: model.showUnreadSites
                    )
                    List {
                        ForEach(model.filtered) { site in
                            SiteRow(
                                site: site,
                                privacy: appState.privacyMode,
                                iconCandidates: model.logoCandidates(for: site, appState: appState),
                                milestone: model.milestone(for: site),
                                onOpenDetails: { selectedSite = site },
                                onOpenBrowser: { openBrowser(for: site) },
                                onOpenLevel: { levelSite = site },
                                onOpenSignIn: { signInSite = site }
                            )
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
                    .listRowSpacing(0)
                    .contentMargins(.vertical, 0, for: .scrollContent)
                    .scrollContentBackground(.hidden)
                    .background(Color(uiColor: .systemGroupedBackground))
                    .refreshable { await model.load(appState) }
                }
            }
        }
        .navigationTitle("站点")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Section("站点数据") {
                        Button { Task { await runGlobalAction(APIPath.siteStatus) } } label: {
                            Label("刷新全部站点", systemImage: "arrow.clockwise")
                        }
                        Button { Task { await runGlobalAction(APIPath.siteSign) } } label: {
                            Label("全部站点签到", systemImage: "checkmark.seal")
                        }
                    }
                    Section("配置") {
                    Button { showAdd = true } label: { Label("添加站点", systemImage: "plus") }
                    Button { showImport = true } label: { Label("导入站点", systemImage: "square.and.arrow.down") }
                    Button { showGenerator = true } label: { Label("配置生成器", systemImage: "doc.badge.gearshape") }
                    Button { showTimeline = true } label: { Label("站点时间轴", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                    }
                } label: {
                    if isRunningGlobalAction {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                .disabled(isRunningGlobalAction)
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
        .sheet(item: $selectedSite) { site in SiteDetailView(site: site, model: model).environmentObject(appState).presentationDetents([.large]) }
        .sheet(item: $signInSite) { site in
            SiteSignInDetailView(site: site, model: model)
                .environmentObject(appState)
                .presentationDetents([.large])
        }
        .sheet(item: $levelSite) { site in
            NavigationStack {
                SiteLevelProgressView(site: site, levels: parseSiteLevels(model.levelRules(for: site)))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { levelSite = nil }
                        }
                    }
            }
            .presentationDetents([.large])
        }
        .fullScreenCover(item: $browserTarget) { target in
            NavigationStack {
                SiteBrowserScreen(
                    site: target.site,
                    urlString: target.url,
                    title: privacyMaskedText(target.site.name, enabled: appState.privacyMode),
                    initialConfig: target.config,
                    onSynced: { await model.load(appState, cached: false) }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { browserTarget = nil }
                    }
                }
            }
            .environmentObject(appState)
        }
        .confirmationDialog(
            "确定删除站点「\(privacyMaskedText(deletingSite?.name ?? "", enabled: appState.privacyMode))」？",
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
            "确定让站点「\(privacyMaskedText(repeatingSite?.name ?? "", enabled: appState.privacyMode))」执行辅种？",
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

    private func openBrowser(for site: SiteItem) {
        var url = model.browserURL(for: site)
        if url.hasPrefix("//") {
            url = "https:\(url)"
        } else if URL(string: url)?.scheme == nil, !url.isEmpty {
            url = "https://\(url)"
        }
        guard let parsedURL = URL(string: url),
              ["http", "https"].contains(parsedURL.scheme?.lowercased() ?? "") else {
            appState.presentedError = "站点地址无效，无法打开"
            return
        }
        browserTarget = SiteBrowserTarget(site: site, url: url, config: model.config(for: site) ?? [:])
    }

    @ViewBuilder private func SiteActions(site: SiteItem, model: SitesViewModel) -> some View {
        Button { editingSite = site } label: { Label("编辑", systemImage: "pencil") }
        Button { Task { await model.operate(appState, site: site, path: APIPath.siteStatus) } } label: { Label("刷新数据", systemImage: "arrow.clockwise") }
        Button { Task { await model.operate(appState, site: site, path: APIPath.siteSign) } } label: { Label("签到", systemImage: "checkmark.seal") }
        Button { repeatingSite = site } label: { Label("辅种", systemImage: "square.stack.3d.up") }
    }

    @MainActor private func runGlobalAction(_ path: String) async {
        guard !isRunningGlobalAction else { return }
        isRunningGlobalAction = true
        defer { isRunningGlobalAction = false }
        let endpoint = path.hasSuffix("/") ? String(path.dropLast()) : path
        let signing = path == APIPath.siteSign
        _ = await appState.runManualTask(
            title: signing ? "正在为全部站点签到" : "正在刷新全部站点",
            successMessage: signing ? "全部站点签到完成" : "全部站点数据已更新"
        ) {
            guard await appState.perform(endpoint, method: .get, showsFeedback: false) else { return false }
            await model.load(appState, cached: false)
            return appState.presentedError == nil
        }
    }
}

private struct SiteSearchFilterBar: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var model: SitesViewModel
    let openFilters: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    SiteSearchTextField(
                        text: $model.query,
                        placeholder: "搜索站点、镜像、账号、标签"
                    )
                    .frame(height: 24)
                    if !model.query.isEmpty {
                        Button { model.query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 36)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button(action: openFilters) {
                    Label(
                        model.activeFilterCount == 0 ? "筛选" : "筛选 \(model.activeFilterCount)",
                        systemImage: model.hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(model.hasFilters ? HarvestTheme.blue : .secondary)
                .accessibilityLabel("筛选，已启用 \(model.activeFilterCount) 项")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    Menu {
                        ForEach(SiteSortField.allCases) { field in
                            Button {
                                model.setSortField(field)
                            } label: {
                                if model.sortField == field {
                                    Label(field.rawValue, systemImage: "checkmark")
                                } else {
                                    Label(field.rawValue, systemImage: field.icon)
                                }
                            }
                        }
                    } label: {
                        Text(model.sortField.rawValue)
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(HarvestTheme.blue)
                    .accessibilityLabel("排序维度：\(model.sortField.rawValue)")

                    Button {
                        model.ascending.toggle()
                    } label: {
                        Label(model.ascending ? "升序" : "降序", systemImage: model.ascending ? "arrow.up" : "arrow.down")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(HarvestTheme.blue)
                    .accessibilityLabel("当前\(model.ascending ? "升序" : "降序")，点击切换")

                    if model.availability != .alive {
                        filterToken(model.availability.rawValue)
                    }
                    if model.condition != .all {
                        filterToken(model.condition.rawValue)
                    }
                    ForEach(model.selectedTypes.sorted(), id: \.self) { type in
                        filterToken(type)
                    }
                    ForEach(model.selectedTags.sorted(), id: \.self) { tag in
                        filterToken(tag)
                    }
                    if !model.selectedUsername.isEmpty {
                        filterToken(privacyMaskedText(model.selectedUsername, enabled: appState.privacyMode))
                    }
                    if !model.selectedEmail.isEmpty {
                        filterToken(privacyMaskedText(model.selectedEmail, enabled: appState.privacyMode))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func filterToken(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .foregroundStyle(HarvestTheme.blue)
            .background(HarvestTheme.blue.opacity(0.11), in: Capsule())
            .overlay { Capsule().stroke(HarvestTheme.blue.opacity(0.18), lineWidth: 0.75) }
            .accessibilityLabel("当前筛选：\(title)")
    }
}

private struct SiteSearchTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.font = .preferredFont(forTextStyle: .body)
        textField.textColor = .label
        textField.tintColor = UIColor(HarvestTheme.blue)
        textField.backgroundColor = .clear
        textField.borderStyle = .none
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.returnKeyType = .search
        textField.clearButtonMode = .never
        textField.adjustsFontForContentSizeCategory = true
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        textField.text = text
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.text = $text
        textField.placeholder = placeholder
        guard textField.markedTextRange == nil, textField.text != text else { return }
        textField.text = text
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextField,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? uiView.intrinsicContentSize.width,
            height: 24
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        private var compositionGeneration = 0

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func textChanged(_ textField: UITextField) {
            compositionGeneration &+= 1
            if textField.markedTextRange == nil {
                commit(textField.text ?? "")
                return
            }
            commitAfterCompositionEnds(textField, generation: compositionGeneration)
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            guard textField.markedTextRange == nil else { return }
            compositionGeneration &+= 1
            commit(textField.text ?? "")
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            compositionGeneration &+= 1
            if textField.markedTextRange == nil {
                commit(textField.text ?? "")
            }
            textField.resignFirstResponder()
            return true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            compositionGeneration &+= 1
            commit(textField.text ?? "")
        }

        private func commit(_ value: String) {
            guard text.wrappedValue != value else { return }
            text.wrappedValue = value
        }

        private func commitAfterCompositionEnds(_ textField: UITextField, generation: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self, weak textField] in
                guard let self, let textField,
                      generation == self.compositionGeneration,
                      textField.markedTextRange == nil else { return }
                self.commit(textField.text ?? "")
            }
        }
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
                    Text(privacyMaskedText(entry.displayName, enabled: appState.privacyMode)).font(.headline).lineLimit(1)
                    Text(privacyMaskedText(entry.key, enabled: appState.privacyMode)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                    .accessibilityLabel("选择 \(privacyMaskedText(entry.displayName, enabled: appState.privacyMode)) 镜像")
                } else if !entry.primaryURL.isEmpty {
                    NavigationLink { browserDestination(entry, urlString: entry.primaryURL) } label: { Image(systemName: "safari") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("打开 \(privacyMaskedText(entry.displayName, enabled: appState.privacyMode))")
                }
            }
            if showDuration { timelineMetric("注册时长", value: entry.durationText) }
            if showUploaded { timelineMetric("上传量", value: entry.site.map { formatBytes($0.uploaded) } ?? "-") }
            if showDownloaded { timelineMetric("下载量", value: entry.site.map { formatBytes($0.downloaded) } ?? "-") }
            if showUsername { timelineMetric("用户名", value: privateValue(entry.site?.username ?? "-")) }
            if showEmail { timelineMetric("邮箱", value: privateValue(entry.site?.email ?? "-")) }
            if showUID { timelineMetric("UID", value: entry.site?.userID ?? "-") }
        }
        .cardSurface()
    }

    private func timelineMetric(_ label: String, value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).lineLimit(1).minimumScaleFactor(0.75) }
            .font(.caption)
    }

    private func privateValue(_ value: String) -> String {
        value == "-" ? value : privacyMaskedText(value, enabled: appState.privacyMode)
    }

    @ViewBuilder private func browserDestination(_ entry: SiteTimelineEntry, urlString: String) -> some View {
        SiteBrowserScreen(
            site: entry.browserSite,
            urlString: urlString,
            title: privacyMaskedText(entry.displayName, enabled: appState.privacyMode),
            initialConfig: entry.config
        ) {
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
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: SitesViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label("筛选结果", systemImage: "line.3.horizontal.decrease.circle")
                        Spacer()
                        Text("\(model.filtered.count) / \(model.sites.count)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(model.hasFilters ? HarvestTheme.blue : .secondary)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        SiteSearchTextField(
                            text: $model.query,
                            placeholder: "搜索站点、镜像、账号、标签"
                        )
                        .frame(height: 24)
                        if !model.query.isEmpty {
                            Button { model.query = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("清除搜索")
                        }
                    }
                }
                Section("状态") {
                    Picker("存活状态", selection: $model.availability) {
                        ForEach(SiteAvailabilityFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("详细条件", selection: $model.condition) {
                        ForEach(SiteConditionFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                if !model.availableTags.isEmpty {
                    Section {
                        ForEach(model.availableTags, id: \.self) { tag in
                            Toggle(tag, isOn: tagBinding(tag))
                        }
                    } header: {
                        filterSectionHeader("标签", selectedCount: model.selectedTags.count) {
                            model.selectedTags.removeAll()
                        }
                    }
                }
                if !model.availableTypes.isEmpty {
                    Section {
                        ForEach(model.availableTypes, id: \.self) { type in
                            Toggle(type, isOn: typeBinding(type))
                        }
                    } header: {
                        filterSectionHeader("类型", selectedCount: model.selectedTypes.count) {
                            model.selectedTypes.removeAll()
                        }
                    }
                }
                Section("身份") {
                    filterPicker("用户名", selection: $model.selectedUsername, values: model.availableUsernames, masksValues: true)
                    filterPicker("邮箱", selection: $model.selectedEmail, values: model.availableEmails, masksValues: true)
                }
            }
            .navigationTitle("筛选站点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用筛选") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func filterSectionHeader(
        _ title: String,
        selectedCount: Int,
        clear: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(selectedCount == 0 ? title : "\(title) · 已选 \(selectedCount)")
            Spacer()
            if selectedCount > 0 {
                Button("清除", action: clear)
                    .font(.caption)
                    .textCase(nil)
            }
        }
    }

    @ViewBuilder
    private func filterPicker(
        _ title: String,
        selection: Binding<String>,
        values: [String],
        masksValues: Bool = false
    ) -> some View {
        Picker(title, selection: selection) {
            Text("全部").tag("")
            ForEach(values, id: \.self) { value in
                Text(privacyMaskedText(value, enabled: masksValues && appState.privacyMode)).tag(value)
            }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var metricGlowRotation = 0.0
    let site: SiteItem
    let privacy: Bool
    let iconCandidates: [RemoteImageCandidate]
    let milestone: SiteLevelMilestone?
    let onOpenDetails: () -> Void
    let onOpenBrowser: () -> Void
    let onOpenLevel: () -> Void
    let onOpenSignIn: () -> Void

    init(
        site: SiteItem,
        privacy: Bool,
        iconCandidates: [RemoteImageCandidate] = [],
        milestone: SiteLevelMilestone? = nil,
        onOpenDetails: @escaping () -> Void = {},
        onOpenBrowser: @escaping () -> Void = {},
        onOpenLevel: @escaping () -> Void = {},
        onOpenSignIn: @escaping () -> Void = {}
    ) {
        self.site = site
        self.privacy = privacy
        self.iconCandidates = iconCandidates
        self.milestone = milestone
        self.onOpenDetails = onOpenDetails
        self.onOpenBrowser = onOpenBrowser
        self.onOpenLevel = onOpenLevel
        self.onOpenSignIn = onOpenSignIn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Button(action: onOpenDetails) {
                VStack(alignment: .leading, spacing: 8) {
                    trafficSection
                    coreMetrics
                    activitySection
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看\(privacyMaskedText(site.name, enabled: privacy))详情")
        }
        .padding(11)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
                .stroke(site.enabled ? HarvestTheme.green.opacity(0.22) : HarvestTheme.coral.opacity(0.18))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 1)
        .contentShape(RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .onAppear { updateMetricGlowAnimation() }
        .onDisappear { stopMetricGlowAnimation() }
        .onChange(of: reduceMotion) { _, _ in updateMetricGlowAnimation() }
    }

    private var metricColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 6), count: count)
    }

    private func updateMetricGlowAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            metricGlowRotation = reduceMotion ? 42 : 0
        }
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 3.6).repeatForever(autoreverses: false)) {
            metricGlowRotation = 360
        }
    }

    private func stopMetricGlowAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            metricGlowRotation = 0
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 9) {
            Button(action: onOpenBrowser) {
                siteLogo(size: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("进入\(privacyMaskedText(site.name, enabled: privacy))站点")
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 5) {
                    Button(action: onOpenDetails) {
                        Text(privacyMaskedText(site.name, enabled: privacy))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 4)
                    if hasCompactAccountSummary {
                        Button(action: onOpenDetails) {
                            compactAccountSummary
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看\(privacyMaskedText(site.name, enabled: privacy))提醒详情")
                    }
                    if let levelStatus {
                        Button(action: onOpenLevel) {
                            SiteInlineStatus(status: levelStatus)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看等级\(levelStatus.label)详情")
                    }
                }
                HStack(alignment: .center, spacing: 8) {
                    Button(action: onOpenDetails) {
                        HStack(spacing: 2) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 15, height: 16, alignment: .center)
                            Text(joinedText)
                                .font(.caption2.weight(.medium).monospacedDigit())
                                .lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 4)
                    if let milestoneStatus {
                        Button(action: onOpenLevel) {
                            SiteInlineStatus(status: milestoneStatus)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看\(privacyMaskedText(site.name, enabled: privacy))\(milestoneStatus.label)详情")
                    }
                    if let signStatus {
                        Button(action: onOpenSignIn) {
                            SiteInlineStatus(status: signStatus)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看\(privacyMaskedText(site.name, enabled: privacy))签到详情")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var compactAccountSummary: some View {
        HStack(spacing: 3) {
            if site.notice > 0 {
                SiteHeaderCompactMetric(icon: "bell.fill", label: "通知", value: "\(site.notice)", color: HarvestTheme.coral, breathes: true)
            }
            if site.unread > 0 {
                SiteHeaderCompactMetric(icon: "bell.badge.fill", label: "未读", value: "\(site.unread)", color: HarvestTheme.coral, breathes: true)
            }
            if site.mail > 0 {
                SiteHeaderCompactMetric(icon: "envelope.fill", label: "邮件", value: "\(site.mail)", color: HarvestTheme.blue, breathes: true)
            }
            if site.invitations > 0 {
                SiteHeaderCompactMetric(icon: "person.fill", label: "邀请", value: "\(site.invitations)", color: HarvestTheme.coral)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
    }

    private var hasCompactAccountSummary: Bool {
        site.invitations > 0 || site.mail > 0 || site.notice > 0 || site.unread > 0
    }

    private var hasHRContent: Bool {
        let value = site.hr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        if let number = Double(value.replacingOccurrences(of: ",", with: "")) { return number > 0 }
        return !["-", "--", "无", "none", "null", "nil"].contains(value.lowercased())
    }

    @ViewBuilder private var trafficSection: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
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
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 0.75)
        }
    }

    private var uploadMetric: some View {
        SiteTrafficMetric(
            label: "上传",
            value: formatBytes(site.uploaded),
            delta: dailyDeltaText(site.uploadDelta),
            icon: "arrow.up",
            color: HarvestTheme.green,
            glowRotation: metricGlowRotation
        )
    }

    private var downloadMetric: some View {
        SiteTrafficMetric(
            label: "下载",
            value: formatBytes(site.downloaded),
            delta: dailyDeltaText(site.downloadDelta),
            icon: "arrow.down",
            color: HarvestTheme.blue,
            glowRotation: metricGlowRotation
        )
    }

    private var coreMetrics: some View {
        LazyVGrid(columns: metricColumns, spacing: 5) {
            SiteCardMetric(icon: "leaf.fill", label: "做种", value: "\(site.seeding)", color: HarvestTheme.green, glowRotation: metricGlowRotation)
            SiteCardMetric(icon: "arrow.down.circle.fill", label: "下载中", value: "\(site.leeching)", color: HarvestTheme.blue, glowRotation: metricGlowRotation)
            SiteCardMetric(icon: "bolt.fill", label: "魔力", value: wanMetricText(site.magic), color: HarvestTheme.amber, glowRotation: metricGlowRotation)
            SiteCardMetric(icon: "diamond.fill", label: "积分", value: wanMetricText(site.score), color: HarvestTheme.coral, glowRotation: metricGlowRotation)
            SiteCardMetric(icon: "arrow.triangle.2.circlepath", label: "分享率", value: ratioText, color: ratioColor, glowRotation: metricGlowRotation)
            SiteCardMetric(icon: "timer", label: "时魔", value: percentageMetricText(site.bonusHour), color: HarvestTheme.purple, glowRotation: metricGlowRotation)
            SiteCardMetric(icon: "paperplane.fill", label: "发种", value: "\(site.published)", color: HarvestTheme.orange, glowRotation: metricGlowRotation)
            SiteCardMetric(icon: "externaldrive.fill", label: "做种量", value: formatBytes(site.seedVolume), color: HarvestTheme.indigo, glowRotation: metricGlowRotation)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 7)
        .background(HarvestTheme.blue.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(HarvestTheme.blue.opacity(0.09), lineWidth: 0.75)
        }
    }

    private var activitySection: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 8) {
                SiteDetailLine(
                    icon: "clock.arrow.circlepath",
                    label: "最近时间",
                    value: recentTimeText(relativeTo: context.date),
                    color: HarvestTheme.green,
                    glowRotation: metricGlowRotation
                )
                if hasHRContent {
                    SiteHeaderCompactMetric(
                        icon: "exclamationmark.triangle.fill",
                        label: "H&R",
                        value: hrText,
                        color: HarvestTheme.amber
                    )
                    .frame(maxWidth: 180, alignment: .trailing)
                    .layoutPriority(1)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .background(HarvestTheme.green.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(HarvestTheme.green.opacity(0.09), lineWidth: 0.75)
        }
    }

    private func siteLogo(size: CGFloat) -> some View {
        return ZStack {
            Circle()
                .fill(Color.white)
            CachedAnimatedRemoteImageCandidates(
                candidates: iconCandidates,
                maximumPixelSize: size * UIScreen.main.scale
            ) {
                Image(systemName: site.enabled ? "globe.asia.australia.fill" : "globe.asia.australia")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(site.enabled ? HarvestTheme.blue : Color.secondary)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .opacity(site.enabled ? 1 : 0.62)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.75)
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(site.enabled ? HarvestTheme.green : HarvestTheme.coral)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                .offset(x: 4, y: 4)
        }
        .accessibilityHidden(true)
    }

    private var signStatus: SiteStatusDescriptor? {
        if site.signed {
            return SiteStatusDescriptor(id: "signed", label: "已签到", icon: "checkmark.seal.fill", color: HarvestTheme.green)
        }
        if site.signIn {
            return SiteStatusDescriptor(id: "sign", label: "未签到", icon: "checkmark.seal", color: HarvestTheme.amber)
        }
        return nil
    }

    private var levelStatus: SiteStatusDescriptor? {
        let level = site.level.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !level.isEmpty else { return nil }
        return SiteStatusDescriptor(id: "level", label: level, icon: "medal.fill", color: HarvestTheme.blue)
    }

    private var milestoneStatus: SiteStatusDescriptor? {
        switch milestone {
        case .graduation:
            return SiteStatusDescriptor(
                id: "graduation",
                label: "已毕业",
                icon: "graduationcap.fill",
                color: HarvestTheme.amber
            )
        case .keepAccount:
            return SiteStatusDescriptor(
                id: "keep-account",
                label: "已保号",
                icon: "checkmark.shield.fill",
                color: HarvestTheme.green
            )
        case nil:
            return nil
        }
    }

    private func dailyDeltaText(_ value: Double) -> String {
        guard site.hasTodayData else { return "今日暂无增量" }
        let prefix = value > 0 ? "+" : value < 0 ? "-" : ""
        return "今日 \(prefix)\(formatBytes(abs(value)))"
    }

    private var joinedText: String {
        guard let joined = parseDate(site.joinedAt) else { return "未登记" }
        let days = max(0, Calendar.current.dateComponents([.day], from: joined, to: Date()).day ?? 0)
        return "\(days / 7)周\(days % 7)天"
    }

    private func recentTimeText(relativeTo now: Date) -> String {
        let dates = [parseDate(site.latestActive), parseDate(site.updatedAt)].compactMap { $0 }
        guard let mostRecent = dates.max() else { return "-" }
        let elapsed = max(0, now.timeIntervalSince(mostRecent))
        if elapsed < 60 { return "刚刚" }
        let minutes = Int(elapsed / 60)
        if minutes < 60 { return "\(minutes)分钟前" }
        let hours = Int(elapsed / 3_600)
        if hours < 24 { return "\(hours)小时前" }
        let days = Int(elapsed / 86_400)
        if days < 7 { return "\(days)天前" }
        if days < 30 { return "\(days / 7)周前" }
        if days < 365 { return "\(days / 30)个月前" }
        return "\(days / 365)年前"
    }

    private var ratioText: String { percentageMetricText(site.ratio) }
    private var ratioColor: Color { site.downloaded > 0 && site.ratio < 1 ? HarvestTheme.coral : HarvestTheme.teal }
    private func wanMetricText(_ value: Double) -> String {
        guard abs(value) >= 10_000 else { return metricDecimalText(value) }
        return "\(metricDecimalText(value / 10_000))w"
    }

    private func percentageMetricText(_ value: Double) -> String {
        "\(metricDecimalText(value))%"
    }

    private func metricDecimalText(_ value: Double) -> String {
        String(format: "%.2f", value)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private var hrText: String {
        let value = site.hr.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "0" : value
    }

}

private struct SiteStatusDescriptor: Identifiable {
    let id: String
    let label: String
    let icon: String
    let color: Color
}

private struct SiteInlineStatus: View {
    let status: SiteStatusDescriptor

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: status.icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 15, height: 17, alignment: .center)
            Text(status.label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(status.color)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SiteHeaderCompactMetric: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let icon: String
    let label: String
    let value: String
    let color: Color
    let breathes: Bool
    @State private var isBright = false

    init(icon: String, label: String, value: String, color: Color, breathes: Bool = false) {
        self.icon = icon
        self.label = label
        self.value = value
        self.color = color
        self.breathes = breathes
    }

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 6.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14, alignment: .center)
                .background(color, in: RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                .opacity(breathes && !reduceMotion ? (isBright ? 1 : 0.3) : 1)
                .animation(
                    breathes && !reduceMotion
                        ? .easeInOut(duration: 1.15).repeatForever(autoreverses: true)
                        : .default,
                    value: isBright
                )
            Text(value)
                .font(.system(size: 8, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(minHeight: 16, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
        .onAppear { updateBreathingState() }
        .onChange(of: reduceMotion) { _, _ in updateBreathingState() }
    }

    private func updateBreathingState() {
        isBright = breathes && !reduceMotion
    }
}

private struct SiteMetricIcon: View {
    let icon: String
    let color: Color
    let size: CGFloat
    let glowRotation: Double

    private var cornerRadius: CGFloat { max(5, size * 0.2) }
    private var glowLineWidth: CGFloat { max(1.15, size * 0.05) }
    private var phaseOffset: Double {
        Double(icon.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 360 })
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color)
                .padding(1.1)

            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(color.opacity(0.24), lineWidth: 0.7)

            AngularGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.54),
                    .init(color: color.opacity(0.06), location: 0.62),
                    .init(color: color.opacity(0.24), location: 0.74),
                    .init(color: color.opacity(0.56), location: 0.86),
                    .init(color: Color.white.opacity(0.9), location: 0.93),
                    .init(color: color.opacity(0.22), location: 0.975),
                    .init(color: .clear, location: 1)
                ]),
                center: .center
            )
            .rotationEffect(.degrees(glowRotation + phaseOffset))
            .mask {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(lineWidth: glowLineWidth)
            }
            .shadow(color: color.opacity(0.3), radius: max(1.2, size * 0.055))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct SiteTrafficMetric: View {
    let label: String
    let value: String
    let delta: String
    let icon: String
    let color: Color
    let glowRotation: Double

    var body: some View {
        HStack(spacing: 8) {
            SiteMetricIcon(icon: icon, color: color, size: 32, glowRotation: glowRotation)
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
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct SiteCardMetric: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    let glowRotation: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                SiteMetricIcon(icon: icon, color: color, size: 24, glowRotation: glowRotation)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.52)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, minHeight: 45)
        .padding(.horizontal, 2)
        .accessibilityLabel("\(label) \(value)")
    }
}

private struct SiteDetailLine: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    let lineLimit: Int?
    let glowRotation: Double

    init(icon: String, label: String, value: String, color: Color, lineLimit: Int? = 1, glowRotation: Double = 0) {
        self.icon = icon
        self.label = label
        self.value = value
        self.color = color
        self.lineLimit = lineLimit
        self.glowRotation = glowRotation
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            SiteMetricIcon(icon: icon, color: color, size: 22, glowRotation: glowRotation)
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
    let showActiveSites: () -> Void
    let showPendingSignInSites: () -> Void
    let showUnreadSites: () -> Void

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
                summaryMetric(
                    "可用",
                    value: activeCount,
                    icon: "checkmark.circle.fill",
                    color: HarvestTheme.green,
                    action: showActiveSites
                )
            }
            summaryMetric(
                "未签到",
                value: pendingSignInCount,
                icon: "checkmark.seal",
                color: HarvestTheme.amber,
                action: showPendingSignInSites
            )
            summaryMetric(
                "未读",
                value: unreadCount,
                icon: "bell.badge.fill",
                color: HarvestTheme.coral,
                action: showUnreadSites
            )
        }
    }

    private func summaryMetric(
        _ label: String,
        value: Int,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label("\(label) \(value)", systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("筛选\(label)站点，共 \(value)")
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
    let leeches: Int
    let seedingDelta: Double
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
        leeches = value.int("leeches") ?? 0
        seedingDelta = value.double("seeding_delta", "seedingDelta") ?? 0
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
    .filter { level in
        level.levelID != 0
            || !level.level.isEmpty
            || !level.name.isEmpty
            || level.days > 0
            || level.uploaded > 0
            || level.downloaded > 0
            || level.bonus > 0
            || level.score > 0
            || level.ratio > 0
            || level.torrents > 0
            || level.leeches > 0
            || level.seedingDelta > 0
            || level.keepAccount
            || level.graduation
            || !level.rights.isEmpty
    }
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
            if levels.isEmpty {
                Section("等级规则") {
                    Label("该站点暂未配置等级规则", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("当前等级仍以站点同步结果为准。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
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
        if level.leeches > 0 { LabeledContent("下载任务要求", value: "\(level.leeches)") }
        if level.seedingDelta > 0 { LabeledContent("做种增量要求", value: formatCompactNumber(level.seedingDelta)) }
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
        if level.leeches > 0 { values.append("下载中 \(level.leeches)") }
        if level.seedingDelta > 0 { values.append("做种增量 \(formatCompactNumber(level.seedingDelta))") }
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

private struct SiteSignInDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let site: SiteItem
    @ObservedObject var model: SitesViewModel
    @State private var latestSite: SiteItem?
    @State private var isLoading = false
    @State private var isOperating = false
    @State private var savingFlag: SiteFeatureFlag?

    private var current: SiteItem { latestSite ?? site }
    private var logoCandidates: [RemoteImageCandidate] {
        model.logoCandidates(for: current, appState: appState)
    }
    private var featureColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    accountSummary
                    featureSection
                    basicInformationSection
                    signInSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .refreshable { await loadDetail() }
            .overlay {
                if isLoading, latestSite == nil {
                    ProgressView()
                        .controlSize(.large)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .navigationTitle("签到信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await loadDetail() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading || isOperating || savingFlag != nil)
                    .accessibilityLabel("刷新签到信息")
                }
            }
            .task { await loadDetail() }
        }
    }

    private var accountSummary: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 13) {
                SiteDetailIcon(site: current, iconCandidates: logoCandidates)
                VStack(alignment: .leading, spacing: 4) {
                    Text(privacyMaskedText(current.name, enabled: appState.privacyMode))
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    Text(accountSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        signInPill
                        if current.unread > 0 {
                            Label("\(current.unread)", systemImage: "bell.badge.fill")
                                .foregroundStyle(HarvestTheme.coral)
                        }
                        if !current.level.isEmpty {
                            Label(current.level, systemImage: "medal.fill")
                                .foregroundStyle(HarvestTheme.blue)
                        }
                    }
                    .font(.caption2.weight(.semibold))
                }
                Spacer(minLength: 0)
            }
            Divider()
            HStack(spacing: 12) {
                summaryFootnote("注册", value: registeredSummary, icon: "calendar")
                Spacer(minLength: 4)
                summaryFootnote("最近活动", value: recentActivityText, icon: "clock")
            }
        }
        .cardSurface()
    }

    private var featureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("功能开关", icon: "switch.2")
            LazyVGrid(columns: featureColumns, spacing: 8) {
                ForEach(SiteFeatureFlag.allCases) { flag in
                    Button {
                        Task { await updateFlag(flag, value: !flag.value(in: current)) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: flag.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 18)
                            Text(flag.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            if savingFlag == flag {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: flag.value(in: current) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundStyle(flag.value(in: current) ? HarvestTheme.blue : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                        .padding(.horizontal, 10)
                        .background(
                            (flag.value(in: current) ? HarvestTheme.blue.opacity(0.09) : Color.primary.opacity(0.035)),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(flag.value(in: current) ? HarvestTheme.blue.opacity(0.18) : Color.primary.opacity(0.07))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(savingFlag != nil || isOperating)
                    .accessibilityValue(flag.value(in: current) ? "已开启" : "已关闭")
                }
            }
        }
    }

    private var basicInformationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("基础信息", icon: "info.circle")
            VStack(spacing: 0) {
                informationRow("站点名称", value: privacyMaskedText(current.siteKey.isEmpty ? current.name : current.siteKey, enabled: appState.privacyMode))
                informationRow("昵称", value: privacyMaskedText(current.name, enabled: appState.privacyMode))
                informationRow("排序 ID", value: "\(current.sortID)")
                if !current.siteType.isEmpty { informationRow("站点类型", value: current.siteType) }
                if !current.username.isEmpty { informationRow("用户名", value: privateText(current.username)) }
                if !current.email.isEmpty { informationRow("邮箱", value: privateText(current.email)) }
                if !current.userID.isEmpty { informationRow("用户 ID", value: current.userID) }
                informationRow("注册时间", value: registeredDetail)
                if !current.latestActive.isEmpty { informationRow("最后活动", value: current.latestActive) }
                informationRow("最后同步", value: current.updatedAt.isEmpty ? "未知" : current.updatedAt, drawsDivider: false)
            }
            .cardSurface()
        }
    }

    private var signInSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("签到记录", icon: "checkmark.seal")
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: current.signed ? "checkmark.seal.fill" : "checkmark.seal")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(current.signed ? HarvestTheme.green : HarvestTheme.amber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.signed ? "今日已签到" : "今日未签到")
                            .font(.headline)
                        Text(latestSignInSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                    if !current.signed {
                        Button {
                            Task { await signIn() }
                        } label: {
                            if isOperating {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("立即签到")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HarvestTheme.green)
                        .disabled(!current.signIn || isOperating || savingFlag != nil)
                    }
                }

                if !current.signIn {
                    Label("该站点未开启自动签到", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !current.signHistory.isEmpty {
                    Divider()
                    ForEach(Array(current.signHistory.prefix(12).enumerated()), id: \.offset) { index, row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.string("date") ?? "未知日期")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                if let time = row.string("updated_at", "created_at", "time"), !time.isEmpty {
                                    Text(time)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Text(signHistoryText(row))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if index < min(current.signHistory.count, 12) - 1 { Divider() }
                    }
                }
            }
            .cardSurface()
        }
    }

    private var signInPill: some View {
        Label(current.signed ? "已签到" : "未签到", systemImage: current.signed ? "checkmark.seal.fill" : "checkmark.seal")
            .foregroundStyle(current.signed ? HarvestTheme.green : HarvestTheme.amber)
    }

    private var accountSubtitle: String {
        let values = [current.username, current.email]
            .filter { !$0.isEmpty }
            .map { privateText($0) }
        let fallback = current.siteKey.isEmpty
            ? "站点账号"
            : privacyMaskedText(current.siteKey, enabled: appState.privacyMode)
        return values.isEmpty ? fallback : values.joined(separator: " · ")
    }

    private var registeredSummary: String {
        guard let joined = parseDate(current.joinedAt) else { return current.joinedAt.isEmpty ? "未登记" : current.joinedAt }
        let days = max(0, Calendar.current.dateComponents([.day], from: joined, to: Date()).day ?? 0)
        return "\(days / 7)周\(days % 7)天"
    }

    private var registeredDetail: String {
        guard let joined = parseDate(current.joinedAt) else { return current.joinedAt.isEmpty ? "未登记" : current.joinedAt }
        return "\(joined.formatted(date: .numeric, time: .omitted)) · \(registeredSummary)"
    }

    private var recentActivityText: String {
        let dates = [parseDate(current.latestActive), parseDate(current.updatedAt)].compactMap { $0 }
        guard let latest = dates.max() else { return "未知" }
        let elapsed = max(0, Date().timeIntervalSince(latest))
        if elapsed < 60 { return "刚刚" }
        let minutes = Int(elapsed / 60)
        if minutes < 60 { return "\(minutes)分钟前" }
        let hours = Int(elapsed / 3_600)
        if hours < 24 { return "\(hours)小时前" }
        let days = Int(elapsed / 86_400)
        if days < 7 { return "\(days)天前" }
        if days < 30 { return "\(days / 7)周前" }
        if days < 365 { return "\(days / 30)个月前" }
        return "\(days / 365)年前"
    }

    private var latestSignInSummary: String {
        guard let row = current.signHistory.first else {
            return current.signed ? "签到已完成，暂无返回详情" : "暂无今日签到记录"
        }
        return signHistoryText(row)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private func summaryFootnote(_ label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
        }
    }

    private func informationRow(_ label: String, value: String, drawsDivider: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                Text(value.isEmpty ? "-" : value)
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 10)
            if drawsDivider { Divider() }
        }
    }

    private func signHistoryText(_ row: [String: Any]) -> String {
        let text = row.string("info", "message", "content") ?? prettyJSON(row)
        if let range = text.range(of: "签到返回信息：") {
            return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private func privateText(_ value: String) -> String {
        privacyMaskedText(value, enabled: appState.privacyMode)
    }

    @MainActor private func loadDetail() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let payload = try await appState.api("\(APIPath.sites)/\(site.id)")
            if let row = jsonPayloadDictionary(payload) { latestSite = SiteItem(row) }
        } catch {
            await AppLogStore.shared.append(.warning, "签到详情加载失败：\(error.localizedDescription)")
        }
    }

    @MainActor private func updateFlag(_ flag: SiteFeatureFlag, value: Bool) async {
        guard savingFlag == nil, flag.value(in: current) != value else { return }
        let previous = current
        var body = current.raw
        body[flag.apiKey] = value
        latestSite = SiteItem(body)
        savingFlag = flag
        defer { savingFlag = nil }

        guard await appState.perform("\(APIPath.sites)/\(current.id)", method: .put, body: body) else {
            latestSite = previous
            return
        }
        await model.load(appState, cached: false)
        latestSite = model.sites.first(where: { $0.id == current.id }) ?? SiteItem(body)
    }

    @MainActor private func signIn() async {
        guard !isOperating else { return }
        isOperating = true
        defer { isOperating = false }
        await model.operate(appState, site: current, path: APIPath.siteSign)
        await loadDetail()
    }
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
    private var featureColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }
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
                            Text(privacyMaskedText(current.name, enabled: appState.privacyMode)).font(.headline)
                            Text(current.siteType.isEmpty
                                ? privacyMaskedText(current.siteKey, enabled: appState.privacyMode)
                                : current.siteType)
                                .font(.caption).foregroundStyle(.secondary)
                            StatusPill(label: current.enabled ? "站点可用" : "站点停用", color: current.enabled ? HarvestTheme.green : .secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("功能开关") {
                    LazyVGrid(columns: featureColumns, spacing: 10) {
                        ForEach(SiteFeatureFlag.allCases) { flag in
                            HStack(spacing: 7) {
                                Image(systemName: flag.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(flag.value(in: current) ? HarvestTheme.blue : Color.secondary)
                                    .frame(width: 18)
                                Text(flag.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                if savingFlag == flag {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 51)
                                } else {
                                    Toggle("", isOn: Binding(
                                        get: { flag.value(in: current) },
                                        set: { value in Task { await updateFlag(flag, value: value) } }
                                    ))
                                    .labelsHidden()
                                    .controlSize(.mini)
                                    .tint(HarvestTheme.blue)
                                    .disabled(savingFlag != nil)
                                    .accessibilityLabel(flag.title)
                                    .accessibilityValue(flag.value(in: current) ? "已开启" : "已关闭")
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .padding(.horizontal, 10)
                            .background(
                                flag.value(in: current) ? HarvestTheme.blue.opacity(0.08) : Color.secondary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(flag.value(in: current) ? HarvestTheme.blue.opacity(0.18) : Color.secondary.opacity(0.10))
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                Section("账号") {
                    detailValue("用户名", value: current.username, privateValue: true)
                    detailValue("邮箱", value: current.email, privateValue: true)
                    detailValue("用户 ID", value: current.userID)
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
                    LabeledContent("上传量", value: formatBytes(current.uploaded))
                    if current.uploadDelta != 0 { LabeledContent("今日上传增量", value: formatBytes(current.uploadDelta)) }
                    LabeledContent("下载量", value: formatBytes(current.downloaded))
                    if current.downloadDelta != 0 { LabeledContent("今日下载增量", value: formatBytes(current.downloadDelta)) }
                    LabeledContent("分享率", value: String(format: "%.2f", current.ratio))
                    LabeledContent("做种体积", value: formatBytes(current.seedVolume))
                    LabeledContent("做种天数", value: "\(current.seedDays)")
                    LabeledContent("魔力值", value: formatCompactNumber(current.magic))
                    LabeledContent("时魔", value: formatCompactNumber(current.bonusHour))
                    LabeledContent("积分", value: formatCompactNumber(current.score))
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
                                    initialConfig: siteConfig,
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
                                title: privacyMaskedText(current.name, enabled: appState.privacyMode),
                                initialConfig: siteConfig,
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
            .navigationTitle(privacyMaskedText(current.name, enabled: appState.privacyMode)).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await loadDetail() }
            .confirmationDialog("确定让站点「\(privacyMaskedText(current.name, enabled: appState.privacyMode))」执行辅种？", isPresented: $confirmRepeat, titleVisibility: .visible) {
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

    private func privateText(_ value: String) -> String {
        privacyMaskedText(value, enabled: appState.privacyMode)
    }

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
    let fileCount: String
    let infoHash: String
    let doubanURL: String
    let imdbURL: String
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
        fileCount = json.string("fileCount", "countFiles", "file_count") ?? ""
        infoHash = json.string("hash", "infoHash", "info_hash") ?? ""
        doubanURL = json.string("douban", "doubanUrl", "douban_url") ?? ""
        imdbURL = json.string("imdb", "imdbUrl", "imdb_url") ?? ""
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
    let method: String
    let hiddenInputs: [String: String]
    let disabled: Bool
    var id: String { method + "#" + action + "#" + option }
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
            "saleExpiry": "detail_free_expire_rule", "tags": "detail_tags_rule",
            "fileCount": "detail_count_files_rule", "hash": "detail_hash_rule",
            "douban": "detail_douban_rule", "imdb": "detail_imdb_rule"
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
        values.add(raw.replace(/\\/tbody(?=\\/|$)/gi, '').replace(/(\\/table(?:\\[[^\\]]+\\])?)(?=\\/tr(?:\\[[^\\]]+\\])?(?:\\/|$))/gi, '$1/tbody'));
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
      const joined = (root, rule) => {
        const list = nodes(root, rule).map(read).filter(Boolean);
        return list.length > 1 ? clean(list.join(' ')) : value(root, rule);
      };
      const absolute = (text) => { try { return text ? new URL(text, window.location.href).href : ''; } catch (_) { return text || ''; } };
      const build = (root, isDetail) => ({
        title: value(root, rules.title), subtitle: value(root, rules.subtitle),
        detailUrl: isDetail ? window.location.href : absolute(value(root, rules.detail)),
        magnetUrl: absolute(value(root, rules.download)), category: value(root, rules.category),
        poster: absolute(value(root, rules.poster)), size: joined(root, rules.size),
        fileCount: value(root, rules.fileCount), hash: value(root, rules.hash),
        douban: absolute(value(root, rules.douban)), imdb: absolute(value(root, rules.imdb)),
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
    let pageUser = firstConfigString(config["page_user"]) ?? ""
    let specs = definitions.compactMap { definition -> [String: String]? in
        let rule = firstConfigString(config[definition.2]) ?? ""
        guard !rule.isEmpty || (definition.0 == "uid" && pageUser.contains("{}")) else { return nil }
        return ["key": definition.0, "label": definition.1, "rule": rule]
    }
    return """
    (() => {
      const specs = \(browserJavaScriptLiteral(specs));
      const pageUser = \(browserJavaScriptLiteral([pageUser])).at(0) || '';
      const clean = (value) => String(value || '').replace(/\\u00a0/g, ' ').replace(/\\s+/g, ' ').trim();
      const variants = (rule) => {
        const raw = clean(rule);
        if (!raw) return [];
        const values = new Set([raw]);
        const withoutTbody = raw.replace(/\\/tbody(?=\\/|$)/gi, '');
        const withTbody = raw.replace(/(\\/table(?:\\[[^\\]]+\\])?)(?=\\/tr(?:\\[[^\\]]+\\])?(?:\\/|$))/gi, '$1/tbody');
        values.add(withoutTbody);
        values.add(withTbody);
        values.add(withoutTbody.replace(/(\\/table(?:\\[[^\\]]+\\])?)(?=\\/tr(?:\\[[^\\]]+\\])?(?:\\/|$))/gi, '$1/tbody'));
        return Array.from(values).filter(Boolean);
      };
      const read = (node, key) => {
        if (!node) return '';
        if (node.nodeType === Node.ATTRIBUTE_NODE || node.nodeType === Node.TEXT_NODE || node.nodeType === Node.CDATA_SECTION_NODE) return clean(node.nodeValue);
        if (node instanceof HTMLAnchorElement) {
          return key === 'uid'
            ? clean(node.getAttribute('href') || node.href || node.textContent)
            : clean(node.textContent || node.getAttribute('href') || node.href);
        }
        if (node instanceof HTMLImageElement) return clean(node.getAttribute('alt') || node.getAttribute('title') || node.getAttribute('src') || node.src);
        return clean(node.textContent);
      };
      const nodes = (rule) => {
        if (!rule) return [];
        for (const candidate of variants(rule)) {
          try {
            const result = document.evaluate(candidate, document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            const values = [];
            for (let index = 0; index < result.snapshotLength; index += 1) values.push(result.snapshotItem(index));
            if (values.length) return values;
          } catch (_) {}
        }
        return [];
      };
      const evaluate = (rule, key) => {
        if (!rule) return '';
        for (const candidate of variants(rule)) {
          try {
            const result = document.evaluate(candidate, document, null, XPathResult.ANY_TYPE, null);
            if (result.resultType === XPathResult.STRING_TYPE && clean(result.stringValue)) return clean(result.stringValue);
            if (result.resultType === XPathResult.NUMBER_TYPE && Number.isFinite(result.numberValue)) return String(result.numberValue);
            if (result.resultType === XPathResult.BOOLEAN_TYPE && result.booleanValue) return 'true';
            const text = read(result.singleNodeValue || (result.iterateNext ? result.iterateNext() : null), key);
            if (text) return text;
          } catch (_) {}
        }
        return nodes(rule).map((node) => read(node, key)).filter(Boolean).join(' ').replace(/\\s+/g, ' ').trim();
      };
      const escape = (value) => {
        let escaped = String(value);
        for (const character of ['\\\\', '^', '$', '.', '|', '?', '*', '+', '(', ')', '[', ']', '{', '}']) {
          escaped = escaped.split(character).join('\\\\' + character);
        }
        return escaped;
      };
      const userID = (raw) => {
        const source = clean(raw);
        if (/^\\d+$/.test(source)) return source;
        const candidates = [source, window.location.href, ...Array.from(document.querySelectorAll('a[href]')).flatMap((anchor) => [anchor.getAttribute('href') || '', anchor.href || ''])].filter(Boolean);
        if (pageUser.includes('{}')) {
          const marker = '__HARVEST_USER_ID__';
          try {
            const target = new URL(pageUser.replaceAll('{}', marker), window.location.origin + '/');
            for (const candidate of candidates) {
              const current = new URL(candidate, window.location.href);
              for (const [key, value] of target.searchParams.entries()) {
                if (value === marker && current.origin === target.origin && current.pathname.replace(/\\/$/, '') === target.pathname.replace(/\\/$/, '')) {
                  const found = clean(current.searchParams.get(key));
                  if (found) return decodeURIComponent(found);
                }
              }
              const pattern = new RegExp('^' + escape(target.href).replace(escape(marker), '([^/?#&]+)') + '(?:[?#&].*)?$');
              const match = current.href.match(pattern);
              if (match && match[1]) return decodeURIComponent(match[1]);
            }
          } catch (_) {}
        }
        for (const candidate of candidates) {
          try {
            const url = new URL(candidate, window.location.href);
            for (const key of ['uid', 'user_id', 'userid', 'id']) {
              const found = clean(url.searchParams.get(key));
              if (found && /^\\d+$/.test(found)) return found;
            }
            const match = url.pathname.match(/(?:user|users|userdetails)[^0-9]*(\\d+)/i);
            if (match) return match[1];
          } catch (_) {}
        }
        return source;
      };
      const normalize = (key, raw) => {
        let value = clean(raw);
        if (!value || ['-', '--', '---', '—', 'n/a', 'null', 'none', '暂无', '无'].includes(value.toLowerCase())) return '';
        if (key === 'uid') return userID(value);
        if (key === 'email') {
          const match = value.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}/i);
          if (match) value = match[0];
        }
        if (key === 'level') value = value.replace(/_Name\\b/g, '').trim();
        return value;
      };
      return JSON.stringify(specs.map((spec) => {
        const raw = evaluate(spec.rule, spec.key);
        return { key: spec.key, label: spec.label, value: normalize(spec.key, raw) };
      }).filter((item) => item.value));
    })();
    """
}

private func browserBonusExtractionScript(config: [String: Any]) -> String {
    let bonusRule = firstConfigString(config["my_bonus_rule"]) ?? ""
    let actionValues: [String: Any]
    if let dictionary = config["buy_action"] as? [String: Any] {
        actionValues = dictionary
    } else if let dictionary = config["buy_action"] as? NSDictionary {
        actionValues = dictionary.reduce(into: [String: Any]()) { result, entry in
            result[String(describing: entry.key)] = entry.value
        }
    } else {
        actionValues = [:]
    }
    let configuredAction = actionValues.reduce(into: [String: String]()) { result, entry in
        result[entry.key] = String(describing: entry.value)
    }
    return """
    (() => {
      const bonusRule = \(browserJavaScriptLiteral([bonusRule]))[0] || '';
      const configuredAction = \(browserJavaScriptLiteral(configuredAction));
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
      const exchangeWords = ['exchange', '兑换', '购买', 'buy', '交换'];
      const forms = Array.from(document.querySelectorAll('form'));
      for (const form of forms) {
        const optionInput = form.querySelector('input[name="option"]');
        let option = optionInput?.value || '';
        const container = form.closest('tr, [class*="bonus"], [class*="exchange"], article, li') || form;
        const submit = form.querySelector('button[type="submit"], input[type="submit"]');
        const text = clean(container.innerText || container.textContent);
        const actionText = clean(form.getAttribute('action')).toLowerCase();
        const submitText = clean(submit?.value || submit?.innerText).toLowerCase();
        const hasConfiguredAction = Boolean(configuredAction.action || configuredAction.url);
        const isExchangeForm = actionText.includes('exchange') || actionText.includes('buy') || actionText.includes('bonus')
          || exchangeWords.some((word) => submitText.includes(word)) || (Boolean(option) && hasConfiguredAction);
        if (!option && isExchangeForm) {
          const rowID = clean(container.querySelector('td')?.innerText || '');
          if (/^\\d+$/.test(rowID)) option = rowID;
        }
        if (!option || seen.has(option) || !isExchangeForm) continue;
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
          const values = (text.match(/[0-9][0-9,.]*/g) || []).map(number).filter((value) => value >= 10 && value !== Number(option));
          if (values.length) cost = values.at(-1);
        }
        if (!cost) continue;
        const hiddenInputs = {};
        for (const input of Array.from(form.querySelectorAll('input[type="hidden"]'))) {
          if (input.name) hiddenInputs[input.name] = input.value || '';
        }
        if (!hiddenInputs.option) hiddenInputs.option = option;
        for (const [key, value] of Object.entries(configuredAction || {})) {
          if (!(key in hiddenInputs) && !['action', 'url', 'method'].includes(key)) hiddenInputs[key] = String(value);
        }
        seen.add(option);
        items.push({
          name: name || `Option ${option}`,
          cost, option,
          action: form.getAttribute('action') || configuredAction.action || configuredAction.url || window.location.href,
          method: form.getAttribute('method') || configuredAction.method || 'POST',
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
            method: row.string("method") ?? "POST",
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
    const method = String(\(browserJavaScriptLiteral([item.method]))[0] || 'POST').toUpperCase();
    const inputs = \(browserJavaScriptLiteral(inputs));
    const body = new URLSearchParams();
    Object.entries(inputs).forEach(([key, value]) => body.append(key, String(value)));
    const target = new URL(action, window.location.href);
    const options = { method, credentials: 'include', redirect: 'follow', headers: {} };
    if (method === 'GET') {
      body.forEach((value, key) => target.searchParams.append(key, value));
    } else {
      options.headers['Content-Type'] = 'application/x-www-form-urlencoded;charset=UTF-8';
      options.body = body;
    }
    const response = await fetch(target, options);
    const responseText = await response.text();
    return JSON.stringify({
      ok: response.ok,
      status: response.status,
      url: response.url,
      response: responseText.replace(/\\s+/g, ' ').slice(0, 500)
    });
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
    @State private var siteConfig: [String: Any]
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

    init(
        site: SiteItem,
        urlString: String,
        title: String,
        initialConfig: [String: Any] = [:],
        onSynced: @escaping () async -> Void = {}
    ) {
        self.site = site
        self.urlString = urlString
        self.title = title
        _siteConfig = State(initialValue: initialConfig)
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
                    Image(systemName: "globe")
                }
                .accessibilityLabel("切换 User-Agent")
                Spacer()
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

        append(
            key: "page_index",
            label: "首页",
            icon: "house",
            rawPath: firstConfigString(siteConfig["page_index"]) ?? "",
            fallbackToSite: true
        )
        append(key: "page_sign_in", label: "签到页", icon: "checkmark.seal", rawPath: firstConfigString(siteConfig["page_sign_in"]) ?? "", hideAPI: true)
        append(
            key: "page_torrents",
            label: "种子页",
            icon: "list.bullet.rectangle",
            rawPath: nonEmptyConfigString(siteConfig["page_torrents"]) ?? site.torrentsURL
        )
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
        append(
            key: "page_mybonus",
            label: "魔力页面",
            icon: "wand.and.stars",
            rawPath: nonEmptyConfigString(siteConfig["page_mybonus"])
                ?? nonEmptyConfigString(siteConfig["buy_page"])
                ?? ""
        )
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
        let storage = try? await session.captureStorage(allowEmpty: true)
        UIPasteboard.general.string = prettyJSON([
            "current_url": session.currentURL?.absoluteString ?? urlString,
            "initial_url": urlString,
            "site_id": effectiveSiteID,
            "site_key": site.siteKey,
            "config_loaded": !siteConfig.isEmpty,
            "configured_localstorage_length": site.localStorage.count,
            "configured_localstorage": site.localStorage,
            "cookie_length": storage?.cookie.count ?? 0,
            "cookie": storage?.cookie ?? "",
            "localstorage_item_count": storage?.localStorageItemCount ?? 0,
            "localstorage_length": storage?.localStorage.count ?? 0,
            "localstorage": storage?.localStorage ?? "",
            "user_agent": session.webView?.customUserAgent ?? "系统默认",
            "has_torrent_list_rules": hasTorrentListRules,
            "has_torrent_detail_rules": hasTorrentDetailRules,
            "has_profile_rules": hasProfileRules,
            "has_bonus_rules": hasBonusRules
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

    private func browserConfigHasInterfaces(_ config: [String: Any]) -> Bool {
        config.keys.contains { key in
            key.hasPrefix("page_")
                || key.hasSuffix("_rule")
                || key == "buy_page"
                || key == "buy_action"
        }
    }

    @MainActor private func loadBrowserConfig() async {
        guard !browserConfigHasInterfaces(siteConfig), !site.siteKey.isEmpty else { return }
        do {
            let direct = jsonPayloadDictionary(try await appState.api(
                "\(APIPath.websiteList)/\(urlPathSegment(site.siteKey))"
            )) ?? [:]
            if browserConfigHasInterfaces(direct) {
                siteConfig = direct
                return
            }
        } catch {
            // The detail endpoint is not available on older servers. Use the
            // complete website list as a compatibility fallback below.
        }

        do {
            let configs = jsonRows(try await appState.api(APIPath.websiteList))
            let siteKey = site.siteKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let siteName = site.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let siteHost = URL(string: site.url)?.host?.lowercased()
            siteConfig = configs.first(where: { config in
                let names = [
                    config.string("name", "site"),
                    config.string("nickname"),
                    config.string("tracker")
                ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                if names.contains(where: { !$0.isEmpty && ($0 == siteKey || $0 == siteName) }) { return true }
                guard let siteHost, !siteHost.isEmpty else { return false }
                return configStrings(config["url"]).contains { URL(string: $0)?.host?.lowercased() == siteHost }
            }) ?? [:]
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

    @MainActor private func loadConfiguredActionPage(
        keys: [String],
        fallbackPath: String = "",
        replaceUserID: Bool = false
    ) async throws -> Bool {
        var paths: [String] = []
        for key in keys {
            guard let path = nonEmptyConfigString(siteConfig[key]) else { continue }
            if key == "page_user", path.lowercased().contains("api/") { continue }
            paths.append(path)
        }
        if !fallbackPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            paths.append(fallbackPath)
        }
        for rawPath in paths where !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let target = resolvedBrowserShortcutURL(
                rawPath,
                fallbackToSite: false,
                hideAPI: false,
                replaceUserID: replaceUserID,
                clearPlaceholder: false
            ) else { continue }
            if target.absoluteString == session.currentURL?.absoluteString { continue }
            try await session.loadAndWait(target)
            return true
        }
        return false
    }

    @MainActor private func extractedTorrentItems(detail: Bool) async throws -> [BrowserExtractedTorrent] {
        let raw = try await session.evaluateJavaScript(browserTorrentExtractionScript(config: siteConfig, detail: detail))
        let parsed = parsedBrowserJavaScriptValue(raw)
        if detail {
            guard let parsed, let row = jsonDictionary(parsed) else { return [] }
            return [BrowserExtractedTorrent(row)]
        }
        return jsonRows(parsed ?? []).map(BrowserExtractedTorrent.init)
    }

    @MainActor private func extractedProfileMetrics() async throws -> [BrowserProfileMetric] {
        let raw = try await session.evaluateJavaScript(browserProfileExtractionScript(config: siteConfig))
        return jsonRows(parsedBrowserJavaScriptValue(raw) ?? []).compactMap { row in
            guard let key = row.string("key"), let value = row.string("value"), !value.isEmpty else { return nil }
            return BrowserProfileMetric(key: key, label: row.string("label") ?? key, value: value)
        }
    }

    @MainActor private func extractTorrentList() async {
        isWorking = true
        defer { isWorking = false }
        do {
            var items = try await extractedTorrentItems(detail: false)
            items = items.filter { !$0.pushURL.isEmpty }
            if items.isEmpty,
               try await loadConfiguredActionPage(keys: ["page_torrents"], fallbackPath: site.torrentsURL) {
                items = try await extractedTorrentItems(detail: false)
                items = items.filter { !$0.pushURL.isEmpty }
            }
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
            let items = try await extractedTorrentItems(detail: true)
            guard let item = items.first else {
                throw APIError(statusCode: 0, message: "当前页面未提取到种子详情")
            }
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
            profileMetrics = try await extractedProfileMetrics()
            for key in ["page_user", "page_control_panel"] where profileMetrics.isEmpty {
                if try await loadConfiguredActionPage(keys: [key], replaceUserID: true) {
                    profileMetrics = try await extractedProfileMetrics()
                }
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
            var raw = try await session.evaluateJavaScript(browserBonusExtractionScript(config: siteConfig))
            var page = parsedBrowserBonusPage(raw)
            for key in ["page_mybonus", "buy_page"] where page == nil {
                if try await loadConfiguredActionPage(keys: [key]) {
                    raw = try await session.evaluateJavaScript(browserBonusExtractionScript(config: siteConfig))
                    page = parsedBrowserBonusPage(raw)
                }
            }
            guard let page else {
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
        .presentationDetents([.large])
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
        .presentationDetents([.large])
    }
}

private struct SiteDetailIcon: View {
    let site: SiteItem
    let iconCandidates: [RemoteImageCandidate]
    var body: some View {
        let size: CGFloat = 64
        ZStack {
            Circle().fill(Color.white)
            CachedAnimatedRemoteImageCandidates(
                candidates: iconCandidates,
                maximumPixelSize: size * UIScreen.main.scale
            ) {
                Image(systemName: "globe.americas.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(site.enabled ? HarvestTheme.blue : Color.secondary)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .opacity(site.enabled ? 1 : 0.62)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .overlay {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.75)
        }
    }
}

private func firstConfigString(_ value: Any?) -> String? {
    if let text = value as? String { return text }
    if let values = value as? [Any] { return values.compactMap { $0 as? String }.first }
    return value.map { String(describing: $0) }
}

private func nonEmptyConfigString(_ value: Any?) -> String? {
    guard let text = firstConfigString(value)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !text.isEmpty else { return nil }
    return text
}

private func configStrings(_ value: Any?) -> [String] {
    if let text = value as? String { return text.isEmpty ? [] : [text] }
    if let values = value as? [Any] { return values.compactMap { $0 as? String } }
    return []
}

func formatCompactNumber(_ value: Double) -> String {
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
    @State private var siteSearchQuery = ""
    @State private var showSitePicker = false
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
                        Button { showSitePicker = true } label: {
                            HStack {
                                Text("站点配置")
                                Spacer()
                                Text(siteKey.isEmpty ? "选择站点" : siteKey)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .disabled(availableSites.isEmpty)
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
            .sheet(isPresented: $showSitePicker) {
                NavigationStack {
                    List {
                        if filteredAvailableSites.isEmpty {
                            ContentUnavailableView.search(text: siteSearchQuery)
                        } else {
                            ForEach(filteredAvailableSites, id: \.self) { key in
                                Button {
                                    siteKey = key
                                    applyConfigDefaults(key)
                                    showSitePicker = false
                                } label: {
                                    HStack {
                                        Text(key).foregroundStyle(.primary)
                                        Spacer()
                                        if siteKey == key {
                                            Image(systemName: "checkmark").foregroundStyle(HarvestTheme.green)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $siteSearchQuery, prompt: "搜索站点配置")
                    .navigationTitle("选择站点")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { showSitePicker = false }
                        }
                    }
                }
                .presentationDetents([.large])
            }
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

    private var filteredAvailableSites: [String] {
        let query = siteSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return availableSites }
        let compactQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        return availableSites.filter { key in
            if key.localizedCaseInsensitiveContains(query) { return true }
            let compactKey = key.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .joined()
            return !compactQuery.isEmpty && compactKey.contains(compactQuery)
        }
    }

    private func nullableText(_ value: String) -> Any {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? NSNull() : normalized
    }
}
