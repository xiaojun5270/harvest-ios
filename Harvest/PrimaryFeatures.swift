import Charts
import Foundation
import SwiftUI

struct TrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let upload: Double
    let download: Double
}

struct DashboardSnapshot {
    var uploaded: Double = 0
    var downloaded: Double = 0
    var uploadSpeed: Double = 0
    var downloadSpeed: Double = 0
    var ratio: Double = 0
    var siteCount: Int = 0
    var seeding: Int = 0
    var unread: Int = 0
    var cpu: Double = 0
    var memory: Double = 0
    var disk: Double = 0
    var trends: [TrendPoint] = []

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
        unread = overview.int("unread", "unread_count", "notice_count") ?? 0

        let resource = root.dict("server", "resource", "system", "server_resource") ?? [:]
        cpu = resource.double("cpu", "cpu_percent", "cpu_usage") ?? 0
        memory = resource.double("memory", "memory_percent", "memory_usage") ?? 0
        disk = resource.double("disk", "disk_percent", "disk_usage") ?? 0
        trends = dashboardTrendPoints(root)
    }
}

private func dashboardTrendPoints(_ root: [String: Any]) -> [TrendPoint] {
    let series = root.rows(
        "uploadMonthIncrementDataList",
        "upload_month_increment_data_list",
        "stackChartDataList",
        "stack_chart_data_list"
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

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var snapshot = DashboardSnapshot([String: Any]())
    @Published var isLoading = true
    @Published var lastUpdated: Date?
    @Published var serverConnected = false

    func load(_ appState: AppState) async {
        isLoading = snapshot.siteCount == 0
        defer { isLoading = false }
        do {
            let raw = try await appState.api(APIPath.dashboard)
            snapshot = DashboardSnapshot(raw)
            lastUpdated = Date()
        } catch {
            appState.presentedError = error.localizedDescription
        }
    }

    func watchServer(_ appState: AppState) async {
        do {
            for try await event in APIClient.shared.streamSSE(
                baseURL: appState.baseURL,
                path: APIPath.serverStatus,
                token: appState.accessToken,
                method: .get,
                query: ["interval": 5]
            ) {
                guard !Task.isCancelled,
                      let payload = jsonPayloadDictionary(event),
                      payload.string("type") != "connected" else { continue }
                let cpu = payload.dict("cpu")
                let memory = payload.dict("memory")
                let network = payload.dict("network")
                snapshot.cpu = cpu?.double("percent") ?? snapshot.cpu
                snapshot.memory = memory?.double("percent") ?? snapshot.memory
                snapshot.uploadSpeed = network?.double("uploadSpeed", "upload_speed") ?? snapshot.uploadSpeed
                snapshot.downloadSpeed = network?.double("downloadSpeed", "download_speed") ?? snapshot.downloadSpeed
                serverConnected = true
            }
        } catch {
            if !Task.isCancelled { serverConnected = false }
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = DashboardViewModel()

    var body: some View {
        ScrollView {
            if model.isLoading {
                LoadingState()
            } else {
                LazyVStack(spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(greeting).font(.title2.weight(.bold))
                            Text(model.lastUpdated?.formatted(date: .omitted, time: .shortened) ?? "刚刚同步")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(
                            label: model.serverConnected ? "资源监控在线" : "数据已同步",
                            color: model.serverConnected ? HarvestTheme.green : HarvestTheme.blue
                        )
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        MetricCard(label: "总上传", value: hidden(formatBytes(model.snapshot.uploaded)), detail: formatSpeed(model.snapshot.uploadSpeed), icon: "arrow.up", color: HarvestTheme.green)
                        MetricCard(label: "总下载", value: hidden(formatBytes(model.snapshot.downloaded)), detail: formatSpeed(model.snapshot.downloadSpeed), icon: "arrow.down", color: HarvestTheme.blue)
                        MetricCard(label: "分享率", value: hidden(String(format: "%.2f", model.snapshot.ratio)), detail: "\(model.snapshot.seeding) 个做种任务", icon: "arrow.triangle.2.circlepath", color: HarvestTheme.amber)
                        MetricCard(label: "站点", value: "\(model.snapshot.siteCount)", detail: "\(model.snapshot.unread) 条未读消息", icon: "globe.americas", color: HarvestTheme.coral)
                    }

                    if !model.snapshot.trends.isEmpty {
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
                            .frame(height: 220)
                        }
                        .cardSurface()
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "服务器资源", subtitle: "当前占用")
                        ResourceRow(label: "CPU", value: model.snapshot.cpu, color: HarvestTheme.coral)
                        ResourceRow(label: "内存", value: model.snapshot.memory, color: HarvestTheme.amber)
                        HStack {
                            Label(formatSpeed(model.snapshot.downloadSpeed), systemImage: "arrow.down")
                                .foregroundStyle(HarvestTheme.blue)
                            Spacer()
                            Label(formatSpeed(model.snapshot.uploadSpeed), systemImage: "arrow.up")
                                .foregroundStyle(HarvestTheme.green)
                        }
                        .font(.caption.monospacedDigit())
                    }
                    .cardSurface()
                }
                .padding(16)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable { await model.load(appState) }
        .task {
            if model.isLoading { await model.load(appState) }
            await model.watchServer(appState)
        }
        .navigationTitle("仪表盘")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let text = hour < 6 ? "夜深了" : hour < 12 ? "早上好" : hour < 18 ? "下午好" : "晚上好"
        return "\(text)，\(appState.profile?.username ?? "用户")"
    }

    private func hidden(_ value: String) -> String { appState.privacyMode ? "••••" : value }
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
    var uploaded: Double
    var downloaded: Double
    var ratio: Double
    var seeding: Int
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
    var updatedAt: String
    var raw: [String: Any]

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
        uploaded = latestStatus?.double("uploaded", "upload", "uploaded_size") ?? json.double("uploaded", "upload", "uploaded_size") ?? 0
        downloaded = latestStatus?.double("downloaded", "download", "downloaded_size") ?? json.double("downloaded", "download", "downloaded_size") ?? 0
        ratio = latestStatus?.double("ratio", "share_ratio") ?? json.double("ratio", "share_ratio") ?? (downloaded > 0 ? uploaded / downloaded : 0)
        seeding = latestStatus?.int("seed", "seeding", "seeding_count") ?? json.int("seeding", "seed", "seeding_count") ?? 0
        unread = (json.int("mail") ?? 0) + (json.int("notice") ?? 0)
        if unread == 0 { unread = json.int("unread", "message", "message_count") ?? 0 }
        enabled = json.bool("available", "enable", "enabled", "is_active") ?? true
        signed = signInfo[isoDayKey()] != nil || json.bool("signed", "signin") == true
        signIn = json.bool("sign_in", "signin") ?? false
        getInfo = json.bool("get_info", "getInfo") ?? true
        repeatTorrents = json.bool("repeat_torrents", "repeatTorrents") ?? false
        searchTorrents = json.bool("search_torrents", "searchTorrents") ?? false
        brushFree = json.bool("brush_free", "brushFree") ?? true
        brushRSS = json.bool("brush_rss", "brushRss") ?? false
        packageFile = json.bool("package_file", "packageFile") ?? false
        hrDiscern = json.bool("hr_discern", "hrDiscern") ?? false
        showInDashboard = json.bool("show_in_dash", "showInDash") ?? true
        updatedAt = latestStatus?.string("updated_at", "created_at") ?? json.string("updated_at", "update_time", "last_update") ?? ""
        raw = json
    }
}

private func isoDayKey(_ date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

@MainActor
final class SitesViewModel: ObservableObject {
    @Published var sites: [SiteItem] = []
    @Published var isLoading = true
    @Published var query = ""

    var filtered: [SiteItem] {
        guard !query.isEmpty else { return sites }
        return sites.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.username.localizedCaseInsensitiveContains(query) }
    }

    func load(_ appState: AppState) async {
        isLoading = sites.isEmpty
        defer { isLoading = false }
        do { sites = jsonRows(try await appState.api(APIPath.sites)).map(SiteItem.init) }
        catch { appState.presentedError = error.localizedDescription }
    }

    func operate(_ appState: AppState, site: SiteItem, path: String) async {
        if await appState.perform(path + "\(site.id)", method: .get) { await load(appState) }
    }

    func delete(_ appState: AppState, site: SiteItem) async {
        if await appState.perform("\(APIPath.sites)/\(site.id)", method: .delete) { sites.removeAll { $0.id == site.id } }
    }
}

struct SitesView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = SitesViewModel()
    @State private var showAdd = false
    @State private var selectedSite: SiteItem?
    @State private var editingSite: SiteItem?

    var body: some View {
        Group {
            if model.isLoading { LoadingState() }
            else if model.filtered.isEmpty {
                EmptyState(icon: "globe.badge.chevron.backward", title: model.query.isEmpty ? "还没有站点" : "没有匹配站点", detail: "添加站点后可同步流量、签到和辅种状态", actionTitle: model.query.isEmpty ? "添加站点" : nil) { showAdd = true }
            } else {
                List {
                    ForEach(model.filtered) { site in
                        Button { selectedSite = site } label: { SiteRow(site: site, privacy: appState.privacyMode) }
                            .buttonStyle(.plain)
                            .contextMenu { SiteActions(site: site, model: model) }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button { Task { await model.operate(appState, site: site, path: APIPath.siteSign) } } label: { Label("签到", systemImage: "checkmark.seal") }.tint(HarvestTheme.green)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button { editingSite = site } label: { Label("编辑", systemImage: "pencil") }.tint(HarvestTheme.amber)
                                Button { Task { await model.operate(appState, site: site, path: APIPath.siteStatus) } } label: { Label("刷新", systemImage: "arrow.clockwise") }.tint(HarvestTheme.blue)
                                Button(role: .destructive) { Task { await model.delete(appState, site: site) } } label: { Label("删除", systemImage: "trash") }
                            }
                    }
                }
                .listStyle(.plain)
                .refreshable { await model.load(appState) }
            }
        }
        .searchable(text: $model.query, prompt: "站点、账号")
        .navigationTitle("站点")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加站点") } }
        .task { if model.isLoading { await model.load(appState) } }
        .sheet(isPresented: $showAdd) { SiteEditorSheet(onSaved: { await model.load(appState) }).environmentObject(appState) }
        .sheet(item: $editingSite) { site in SiteEditorSheet(site: site, onSaved: { await model.load(appState) }).environmentObject(appState) }
        .sheet(item: $selectedSite) { site in SiteDetailView(site: site, model: model).environmentObject(appState).presentationDetents([.medium, .large]) }
    }

    @ViewBuilder private func SiteActions(site: SiteItem, model: SitesViewModel) -> some View {
        Button { editingSite = site } label: { Label("编辑", systemImage: "pencil") }
        Button { Task { await model.operate(appState, site: site, path: APIPath.siteStatus) } } label: { Label("刷新数据", systemImage: "arrow.clockwise") }
        Button { Task { await model.operate(appState, site: site, path: APIPath.siteSign) } } label: { Label("签到", systemImage: "checkmark.seal") }
        Button { Task { await model.operate(appState, site: site, path: APIPath.siteRepeat) } } label: { Label("辅种", systemImage: "square.stack.3d.up") }
    }
}

struct SiteRow: View {
    let site: SiteItem
    let privacy: Bool
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(site.enabled ? HarvestTheme.green.opacity(0.14) : Color.secondary.opacity(0.12)).frame(width: 48, height: 48)
                Image(systemName: site.enabled ? "globe.americas.fill" : "globe.americas").foregroundStyle(site.enabled ? HarvestTheme.green : .secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(site.name).font(.headline).lineLimit(1); if site.signed { Image(systemName: "checkmark.seal.fill").foregroundStyle(HarvestTheme.green).font(.caption) } }
                Text(site.username.isEmpty ? site.url : site.username).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 10) {
                    Label(privacy ? "••••" : formatBytes(site.uploaded), systemImage: "arrow.up").foregroundStyle(HarvestTheme.green)
                    Label(privacy ? "••••" : formatBytes(site.downloaded), systemImage: "arrow.down").foregroundStyle(HarvestTheme.blue)
                }.font(.caption2.monospacedDigit())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(String(format: "%.2f", site.ratio)).font(.subheadline.weight(.semibold)).monospacedDigit()
                Text("\(site.seeding) 做种").font(.caption2).foregroundStyle(.secondary)
                if site.unread > 0 { Text("\(site.unread) 未读").font(.caption2.weight(.semibold)).foregroundStyle(HarvestTheme.coral) }
            }
        }.padding(.vertical, 5)
    }
}

struct SiteDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let site: SiteItem
    @ObservedObject var model: SitesViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("状态") {
                    LabeledContent("分享率", value: String(format: "%.2f", site.ratio))
                    LabeledContent("做种", value: "\(site.seeding)")
                    LabeledContent("签到", value: site.signed ? "已完成" : "未完成")
                    LabeledContent("最后同步", value: site.updatedAt.isEmpty ? "未知" : site.updatedAt)
                }
                Section("流量") { LabeledContent("上传", value: formatBytes(site.uploaded)); LabeledContent("下载", value: formatBytes(site.downloaded)) }
                Section {
                    if !site.url.isEmpty {
                        NavigationLink {
                            NativeBrowserView(
                                urlString: site.url,
                                title: site.name,
                                cookie: site.cookie,
                                localStorage: site.localStorage,
                                userAgent: site.userAgent
                            )
                            .navigationTitle(site.name)
                            .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label("打开站点", systemImage: "safari")
                        }
                    }
                    Button { Task { await model.operate(appState, site: site, path: APIPath.siteStatus); dismiss() } } label: { Label("刷新站点数据", systemImage: "arrow.clockwise") }
                    Button { Task { await model.operate(appState, site: site, path: APIPath.siteSign); dismiss() } } label: { Label("执行签到", systemImage: "checkmark.seal") }
                    Button { Task { await model.operate(appState, site: site, path: APIPath.siteRepeat); dismiss() } } label: { Label("执行辅种", systemImage: "square.stack.3d.up") }
                }
            }
            .navigationTitle(site.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
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
                do {
                    async let namesRaw = appState.api(APIPath.websiteToAdd)
                    async let configsRaw = appState.api(APIPath.websiteList)
                    let (names, configs) = try await (namesRaw, configsRaw)
                    availableSites = jsonStrings(names)
                    var configMap: [String: [String: Any]] = [:]
                    for config in jsonRows(configs) {
                        if let key = config.string("name", "site"), !key.isEmpty { configMap[key] = config }
                    }
                    availableConfigs = configMap
                    if siteKey.isEmpty { siteKey = availableSites.first ?? "" }
                    applyConfigDefaults(siteKey)
                } catch { appState.presentedError = error.localizedDescription }
            }
        }
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
    var raw: [String: Any]

    init(_ json: [String: Any]) {
        let status = json.dict("status") ?? [:]
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
        raw = json
    }
}

struct TorrentItem: Identifiable {
    let id: String
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
    var raw: [String: Any]

    init(_ json: [String: Any]) {
        numericID = json.int("id", "torrent_id") ?? 0
        id = json.string("hashString", "hash_string", "hash", "infohash_v1", "torrent_hash") ?? (numericID > 0 ? String(numericID) : UUID().uuidString)
        name = json.string("name", "title") ?? "未命名任务"
        downloaderID = json.int("downloader_id", "downloader", "client_id") ?? 0
        downloaderCategory = json.string("downloader_category", "client_type") ?? "Qb"
        status = torrentStatusLabel(json.string("state", "status") ?? "unknown", client: downloaderCategory)
        let rawProgress = json.double("percentDone", "percentComplete", "percent_done", "progress", "completed") ?? 0
        progress = rawProgress > 1 ? rawProgress / 100 : rawProgress
        size = json.double("sizeWhenDone", "totalSize", "size", "total_size", "length") ?? 0
        uploadSpeed = json.double("rateUpload", "upspeed", "upload_speed", "rate_upload") ?? 0
        downloadSpeed = json.double("rateDownload", "dlspeed", "download_speed", "rate_download") ?? 0
        ratio = json.double("uploadRatio", "ratio", "upload_ratio") ?? 0
        category = json.string("category", "label") ?? ""
        raw = json
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

@MainActor
final class DownloadsViewModel: ObservableObject {
    @Published var downloaders: [DownloaderItem] = []
    @Published var torrents: [TorrentItem] = []
    @Published var isLoading = true
    @Published var query = ""
    @Published var filter = "全部"

    var filtered: [TorrentItem] {
        torrents.filter { item in
            let queryMatch = query.isEmpty || item.name.localizedCaseInsensitiveContains(query)
            let state = item.status.lowercased()
            let filterMatch = filter == "全部" || (filter == "下载中" && (state.contains("down") || state.contains("下载") || item.downloadSpeed > 0)) || (filter == "做种" && (state.contains("seed") || state.contains("upload") || state.contains("做种"))) || (filter == "暂停" && (state.contains("pause") || state.contains("stop") || state.contains("暂停")))
            return queryMatch && filterMatch
        }
    }

    func load(_ appState: AppState) async {
        isLoading = downloaders.isEmpty && torrents.isEmpty
        defer { isLoading = false }
        do {
            let raw = try await appState.api(APIPath.downloaders, query: ["with_status": true])
            downloaders = jsonRows(raw).map(DownloaderItem.init)
            var collected: [TorrentItem] = []
            for downloader in downloaders where downloader.enabled {
                let main = try await appState.api("\(APIPath.downloaderMain)\(downloader.id)")
                collected.append(contentsOf: jsonRows(main).map {
                    var row = $0
                    row["downloader_id"] = downloader.id
                    row["downloader_category"] = downloader.category
                    return TorrentItem(row)
                })
            }
            torrents = collected
        } catch { appState.presentedError = error.localizedDescription }
    }

    func control(_ appState: AppState, torrent: TorrentItem, command: String) async {
        let downloader = torrent.downloaderID == 0 ? downloaders.first?.id ?? 0 : torrent.downloaderID
        let isTransmission = torrent.downloaderCategory.lowercased().contains("tr")
        let body: [String: Any]
        if isTransmission {
            let mapped = command == "resume" ? "start_torrent" : command == "pause" ? "stop_torrent" : "remove_torrent"
            body = [
                "command": mapped,
                "ids": [torrent.numericID],
                "delete_data": false
            ]
        } else {
            body = [
                "torrent_hashes": [torrent.id],
                "command": command,
                "delete_files": false
            ]
        }
        if await appState.perform(APIPath.downloaderControl + "\(downloader)", method: .post, body: body) { await load(appState) }
    }

    func toggle(_ appState: AppState, downloader: DownloaderItem) async {
        var body = downloader.raw
        body["is_active"] = !downloader.enabled
        if await appState.perform("\(APIPath.downloaders)/\(downloader.id)", method: .put, body: body) {
            await load(appState)
        }
    }

    func remove(_ appState: AppState, downloader: DownloaderItem) async {
        if await appState.perform("\(APIPath.downloaders)/\(downloader.id)", method: .delete) {
            downloaders.removeAll { $0.id == downloader.id }
            torrents.removeAll { $0.downloaderID == downloader.id }
        }
    }

    func repeatTorrents(_ appState: AppState, downloader: DownloaderItem) async {
        _ = await appState.perform("\(APIPath.downloaderRepeat)/\(downloader.id)", method: .get)
    }
}

struct DownloadsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = DownloadsViewModel()
    @State private var showAddTorrent = false
    @State private var showAddDownloader = false
    @State private var editingDownloader: DownloaderItem?
    @State private var settingsDownloader: DownloaderItem?
    @State private var selectedTorrent: TorrentItem?

    var body: some View {
        ScrollView {
            if model.isLoading { LoadingState() }
            else {
                LazyVStack(spacing: 16) {
                    if !model.downloaders.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(model.downloaders) { downloader in
                                    DownloaderCard(
                                        item: downloader,
                                        onEdit: { editingDownloader = downloader },
                                        onSettings: { settingsDownloader = downloader },
                                        onToggle: { Task { await model.toggle(appState, downloader: downloader) } },
                                        onRepeat: { Task { await model.repeatTorrents(appState, downloader: downloader) } },
                                        onDelete: { Task { await model.remove(appState, downloader: downloader) } }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    VStack(spacing: 12) {
                        Picker("状态", selection: $model.filter) { ForEach(["全部", "下载中", "做种", "暂停"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                        if model.filtered.isEmpty {
                            EmptyState(icon: "arrow.down.doc", title: "没有种子任务", detail: "推送磁力链接或种子地址后会显示在这里", actionTitle: "添加种子") { showAddTorrent = true }
                                .frame(minHeight: 260)
                        } else {
                            LazyVStack(spacing: 9) { ForEach(model.filtered) { torrent in TorrentRow(item: torrent, model: model) { selectedTorrent = torrent } } }
                        }
                    }.padding(.horizontal, 16)
                }.padding(.vertical, 12)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .searchable(text: $model.query, prompt: "搜索种子")
        .refreshable { await model.load(appState) }
        .navigationTitle("下载")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Menu { Button { showAddTorrent = true } label: { Label("添加种子", systemImage: "link.badge.plus") }; Button { showAddDownloader = true } label: { Label("添加下载器", systemImage: "externaldrive.badge.plus") } } label: { Image(systemName: "plus") }
        } }
        .task {
            if model.isLoading { await model.load(appState) }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled { await model.load(appState) }
            }
        }
        .sheet(isPresented: $showAddTorrent) { AddTorrentSheet(downloaders: model.downloaders) { await model.load(appState) }.environmentObject(appState) }
        .sheet(isPresented: $showAddDownloader) { DownloaderEditorSheet { await model.load(appState) }.environmentObject(appState) }
        .sheet(item: $editingDownloader) { downloader in DownloaderEditorSheet(downloader: downloader) { await model.load(appState) }.environmentObject(appState) }
        .sheet(item: $settingsDownloader) { downloader in DownloaderSettingsSheet(downloader: downloader).environmentObject(appState) }
        .sheet(item: $selectedTorrent) { torrent in TorrentDetailSheet(item: torrent, model: model).environmentObject(appState).presentationDetents([.medium, .large]) }
    }
}

struct DownloaderCard: View {
    let item: DownloaderItem
    let onEdit: () -> Void
    let onSettings: () -> Void
    let onToggle: () -> Void
    let onRepeat: () -> Void
    let onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: item.category == "Tr" || item.category.lowercased().contains("trans") ? "point.3.connected.trianglepath.dotted" : "bolt.horizontal.circle").foregroundStyle(HarvestTheme.green)
                Spacer()
                if item.main { Text("主下载器").font(.caption2.weight(.bold)).foregroundStyle(HarvestTheme.coral) }
                Menu {
                    Button(action: onEdit) { Label("编辑", systemImage: "pencil") }
                    Button(action: onSettings) { Label("下载器设置", systemImage: "slider.horizontal.3") }
                    Button(action: onRepeat) { Label("执行辅种", systemImage: "square.stack.3d.up") }
                    Button(action: onToggle) { Label(item.enabled ? "停用" : "启用", systemImage: item.enabled ? "pause" : "play") }
                    Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            Text(item.name).font(.headline).lineLimit(1)
            Text("\(item.networkProtocol)://\(item.host)\(item.port > 0 ? ":\(item.port)" : "")").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            HStack { Label(formatSpeed(item.downloadSpeed), systemImage: "arrow.down").foregroundStyle(HarvestTheme.blue); Label(formatSpeed(item.uploadSpeed), systemImage: "arrow.up").foregroundStyle(HarvestTheme.green) }.font(.caption.monospacedDigit())
        }
        .padding(14).frame(width: 250, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
                .stroke(item.enabled ? HarvestTheme.green.opacity(0.25) : Color.primary.opacity(0.08))
        )
    }
}

struct TorrentRow: View {
    @EnvironmentObject private var appState: AppState
    let item: TorrentItem
    @ObservedObject var model: DownloadsViewModel
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) { Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(2); Text(item.category.isEmpty ? item.status : "\(item.status) · \(item.category)").font(.caption2).foregroundStyle(.secondary) }
                Spacer()
                Menu { Button { Task { await model.control(appState, torrent: item, command: "resume") } } label: { Label("开始", systemImage: "play") }; Button { Task { await model.control(appState, torrent: item, command: "pause") } } label: { Label("暂停", systemImage: "pause") }; Button(role: .destructive) { Task { await model.control(appState, torrent: item, command: "delete") } } label: { Label("删除", systemImage: "trash") } } label: { Image(systemName: "ellipsis").frame(width: 30, height: 30) }
            }
            ProgressView(value: item.progress).tint(progressColor)
            HStack { Text("\(Int(item.progress * 100))%").fontWeight(.semibold); Text(formatBytes(item.size)); Spacer(); Label(formatSpeed(item.downloadSpeed), systemImage: "arrow.down").foregroundStyle(HarvestTheme.blue); Label(formatSpeed(item.uploadSpeed), systemImage: "arrow.up").foregroundStyle(HarvestTheme.green) }.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .cardSurface()
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var progressColor: Color { item.progress >= 1 ? HarvestTheme.green : item.downloadSpeed > 0 ? HarvestTheme.blue : HarvestTheme.amber }
}

struct TorrentDetailSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let item: TorrentItem
    @ObservedObject var model: DownloadsViewModel
    @State private var detail: [String: Any]?
    @State private var isLoading = true

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
                if isLoading { Section { ProgressView().frame(maxWidth: .infinity) } }
                if let tracker = resolved.string("tracker", "tracker_url", "announce"), !tracker.isEmpty {
                    Section("Tracker") { Text(tracker).font(.caption.monospaced()).textSelection(.enabled) }
                }
                let files = resolved.rows("files", "fileStats")
                if !files.isEmpty {
                    Section("文件") {
                        ForEach(Array(files.prefix(50).enumerated()), id: \.offset) { _, file in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.string("name", "path") ?? "未命名文件").font(.caption).lineLimit(2)
                                if let size = file.double("length", "size") { Text(formatBytes(size)).font(.caption2).foregroundStyle(.secondary) }
                            }
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
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await load() }
        }
    }

    private var resolved: [String: Any] { detail ?? item.raw }

    private func load() async {
        defer { isLoading = false }
        guard item.downloaderID > 0 else { return }
        do {
            detail = jsonPayloadDictionary(try await appState.api(
                "\(APIPath.downloaderTorrentDetail)\(item.downloaderID)",
                query: ["torrent_hash": item.id]
            ))
        } catch { appState.presentedError = error.localizedDescription }
    }
}

struct AddTorrentSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let downloaders: [DownloaderItem]
    let onSaved: () async -> Void
    @State private var input = ""
    @State private var downloaderID = 0
    @State private var category = ""
    @State private var savePath = ""
    @State private var suggestedPaths: [String] = []
    @State private var tags = ""
    @State private var paused = false
    @State private var skipChecking = false

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
                }
            }
            .navigationTitle("添加种子").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("推送") { Task {
                    var body: [String: Any] = ["urls": input, "is_paused": paused, "is_skip_checking": skipChecking]
                    if !savePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["save_path"] = savePath.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if !category.isEmpty { body["category"] = category }
                    let tagValues = tags.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    if !tagValues.isEmpty { body["tags"] = tagValues }
                    if await appState.perform("\(APIPath.pushTorrent)/\(downloaderID)", method: .post, body: body) { await onSaved(); dismiss() }
                } }.disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || downloaderID == 0) }
            }
            .onAppear { if downloaderID == 0 { downloaderID = downloaders.first?.id ?? 0 } }
            .task {
                do {
                    suggestedPaths = jsonPathStrings(try await appState.api(APIPath.downloaderPaths))
                } catch {
                    suggestedPaths = []
                }
            }
        }
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
                Section("任务") { Toggle("启用下载器", isOn: $enabled); Toggle("参与辅种", isOn: $brush); TextField("排序值", text: $sortID).keyboardType(.numberPad); TextField("种子文件目录（可选）", text: $torrentPath) }
            }
            .navigationTitle(downloader == nil ? "添加下载器" : "编辑下载器").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task {
                    var body = downloader?.raw ?? [:]
                    body["name"] = name
                    body["category"] = type
                    body["protocol"] = networkProtocol
                    body["host"] = host
                    body["external_host"] = externalHost
                    body["port"] = Int(port) ?? 0
                    body["username"] = username
                    body["password"] = password
                    body["is_active"] = enabled
                    body["brush"] = brush
                    body["sort_id"] = Int(sortID) ?? 0
                    body["torrent_path"] = torrentPath
                    let path = downloader.map { "\(APIPath.downloaders)/\($0.id)" } ?? APIPath.downloaders
                    let method: HTTPMethod = downloader == nil ? .post : .put
                    if await appState.perform(path, method: method, body: body) { await onSaved(); dismiss() }
                } }.disabled(name.isEmpty || host.isEmpty) }
            }
        }
    }
}

struct DownloaderSettingsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let downloader: DownloaderItem
    @State private var jsonText = "{}"
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var parseError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("下载器偏好设置") {
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        TextEditor(text: $jsonText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 360)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if let parseError {
                        Label(parseError, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(HarvestTheme.coral)
                    }
                }
            }
            .navigationTitle(downloader.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }.disabled(isLoading || isSaving)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            let raw = try await appState.api(
                "\(APIPath.downloaderPreferences)\(downloader.id)",
                query: ["with_status": true]
            )
            let value = jsonPayloadDictionary(raw) ?? jsonDictionary(raw) ?? [:]
            let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            jsonText = String(data: data, encoding: .utf8) ?? "{}"
        } catch { appState.presentedError = error.localizedDescription }
    }

    private func save() async {
        guard let data = jsonText.data(using: .utf8) else { return }
        do {
            guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                parseError = "设置必须是 JSON 对象"
                return
            }
            parseError = nil
            isSaving = true
            if await appState.perform(
                "\(APIPath.downloaderPreferences)\(downloader.id)",
                method: .put,
                body: value
            ) { dismiss() }
            isSaving = false
        } catch { parseError = "JSON 格式错误：\(error.localizedDescription)" }
    }
}
