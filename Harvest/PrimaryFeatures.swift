import Charts
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
        uploaded = overview.double("uploaded", "upload", "upload_total", "total_upload") ?? 0
        downloaded = overview.double("downloaded", "download", "download_total", "total_download") ?? 0
        uploadSpeed = overview.double("upload_speed", "upspeed", "up_speed") ?? 0
        downloadSpeed = overview.double("download_speed", "dlspeed", "down_speed") ?? 0
        ratio = overview.double("ratio", "share_ratio") ?? (downloaded > 0 ? uploaded / downloaded : 0)
        siteCount = overview.int("site_count", "sites", "siteCount") ?? jsonRows(root).count
        seeding = overview.int("seeding", "seeding_count", "seed_count") ?? 0
        unread = overview.int("unread", "unread_count", "notice_count") ?? 0

        let resource = root.dict("server", "resource", "system", "server_resource") ?? [:]
        cpu = resource.double("cpu", "cpu_percent", "cpu_usage") ?? 0
        memory = resource.double("memory", "memory_percent", "memory_usage") ?? 0
        disk = resource.double("disk", "disk_percent", "disk_usage") ?? 0

        let rows = root.rows("chart", "trend", "trends", "history", "status_chart")
        trends = rows.enumerated().map { index, row in
            let date = parseDate(row.string("date", "time", "created_at")) ?? Calendar.current.date(byAdding: .day, value: index - rows.count, to: Date())!
            return TrendPoint(
                date: date,
                upload: row.double("upload", "uploaded", "up") ?? 0,
                download: row.double("download", "downloaded", "down") ?? 0
            )
        }
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var snapshot = DashboardSnapshot([String: Any]())
    @Published var isLoading = true
    @Published var lastUpdated: Date?

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
                        StatusPill(label: "服务在线", color: HarvestTheme.green)
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
                        ResourceRow(label: "磁盘", value: model.snapshot.disk, color: HarvestTheme.blue)
                    }
                    .cardSurface()
                }
                .padding(16)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable { await model.load(appState) }
        .task { if model.isLoading { await model.load(appState) } }
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

struct SiteItem: Identifiable, Hashable {
    let id: Int
    var name: String
    var url: String
    var username: String
    var uploaded: Double
    var downloaded: Double
    var ratio: Double
    var seeding: Int
    var unread: Int
    var enabled: Bool
    var signed: Bool
    var updatedAt: String

    init(_ json: [String: Any]) {
        id = json.int("id", "site_id") ?? abs((json.string("name") ?? UUID().uuidString).hashValue)
        name = json.string("nickname", "name", "site", "website_name") ?? "未命名站点"
        url = json.string("url", "mirror", "base_url") ?? ""
        username = json.string("username", "user_name") ?? ""
        uploaded = json.double("uploaded", "upload", "uploaded_size") ?? 0
        downloaded = json.double("downloaded", "download", "downloaded_size") ?? 0
        ratio = json.double("ratio", "share_ratio") ?? (downloaded > 0 ? uploaded / downloaded : 0)
        seeding = json.int("seeding", "seed", "seeding_count") ?? 0
        unread = json.int("unread", "message", "message_count") ?? 0
        enabled = json.bool("enable", "enabled", "is_active") ?? true
        signed = json.bool("signed", "sign_in", "signin") ?? false
        updatedAt = json.string("updated_at", "update_time", "last_update") ?? ""
    }
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
        .sheet(item: $selectedSite) { site in SiteDetailView(site: site, model: model).environmentObject(appState).presentationDetents([.medium, .large]) }
    }

    @ViewBuilder private func SiteActions(site: SiteItem, model: SitesViewModel) -> some View {
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
    @State private var name = ""
    @State private var url = ""
    @State private var cookie = ""
    @State private var userAgent = ""
    @State private var enabled = true
    @State private var signin = true
    let onSaved: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") { TextField("站点名称", text: $name); TextField("站点地址", text: $url).textInputAutocapitalization(.never).keyboardType(.URL) }
                Section("凭据") { TextField("Cookie", text: $cookie, axis: .vertical).lineLimit(3...6); TextField("User-Agent（可选）", text: $userAgent) }
                Section("能力") { Toggle("启用站点", isOn: $enabled); Toggle("参与签到", isOn: $signin) }
            }
            .navigationTitle("添加站点").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task {
                    let body: [String: Any] = ["name": name, "url": url, "cookie": cookie, "user_agent": userAgent, "enable": enabled, "signin": signin]
                    if await appState.perform(APIPath.sites, method: .post, body: body) { await onSaved(); dismiss() }
                } }.disabled(name.isEmpty || url.isEmpty || cookie.isEmpty) }
            }
        }
    }
}

struct DownloaderItem: Identifiable, Hashable {
    let id: Int
    var name: String
    var category: String
    var host: String
    var enabled: Bool
    var main: Bool
    var uploadSpeed: Double
    var downloadSpeed: Double

    init(_ json: [String: Any]) {
        id = json.int("id") ?? abs((json.string("name") ?? UUID().uuidString).hashValue)
        name = json.string("name", "nickname", "title") ?? "下载器"
        category = json.string("category", "type", "client") ?? "qBittorrent"
        host = json.string("host", "url") ?? ""
        enabled = json.bool("enable", "enabled", "is_active") ?? true
        main = json.bool("main", "is_main", "default") ?? false
        uploadSpeed = json.double("upload_speed", "up_speed", "upspeed") ?? 0
        downloadSpeed = json.double("download_speed", "down_speed", "dlspeed") ?? 0
    }
}

struct TorrentItem: Identifiable, Hashable {
    let id: String
    var name: String
    var downloaderID: Int
    var status: String
    var progress: Double
    var size: Double
    var uploadSpeed: Double
    var downloadSpeed: Double
    var ratio: Double
    var category: String

    init(_ json: [String: Any]) {
        id = json.string("hash", "id", "torrent_id") ?? UUID().uuidString
        name = json.string("name", "title") ?? "未命名任务"
        downloaderID = json.int("downloader_id", "downloader", "client_id") ?? 0
        status = json.string("state", "status") ?? "unknown"
        let rawProgress = json.double("progress", "completed") ?? 0
        progress = rawProgress > 1 ? rawProgress / 100 : rawProgress
        size = json.double("size", "total_size", "length") ?? 0
        uploadSpeed = json.double("upspeed", "upload_speed", "rate_upload") ?? 0
        downloadSpeed = json.double("dlspeed", "download_speed", "rate_download") ?? 0
        ratio = json.double("ratio", "upload_ratio") ?? 0
        category = json.string("category", "label") ?? ""
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
            let filterMatch = filter == "全部" || (filter == "下载中" && (state.contains("down") || item.downloadSpeed > 0)) || (filter == "做种" && (state.contains("seed") || state.contains("upload"))) || (filter == "暂停" && (state.contains("pause") || state.contains("stop")))
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
                    return TorrentItem(row)
                })
            }
            torrents = collected
        } catch { appState.presentedError = error.localizedDescription }
    }

    func control(_ appState: AppState, torrent: TorrentItem, command: String) async {
        let downloader = torrent.downloaderID == 0 ? downloaders.first?.id ?? 0 : torrent.downloaderID
        let body: [String: Any] = ["hashes": [torrent.id], "torrent_hashes": [torrent.id], "command": command, "action": command]
        if await appState.perform(APIPath.downloaderControl + "\(downloader)", method: .post, body: body) { await load(appState) }
    }
}

struct DownloadsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = DownloadsViewModel()
    @State private var showAddTorrent = false
    @State private var showAddDownloader = false

    var body: some View {
        ScrollView {
            if model.isLoading { LoadingState() }
            else {
                LazyVStack(spacing: 16) {
                    if !model.downloaders.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) { ForEach(model.downloaders) { DownloaderCard(item: $0) } }
                            .padding(.horizontal, 16)
                        }
                    }

                    VStack(spacing: 12) {
                        Picker("状态", selection: $model.filter) { ForEach(["全部", "下载中", "做种", "暂停"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                        if model.filtered.isEmpty {
                            EmptyState(icon: "arrow.down.doc", title: "没有种子任务", detail: "推送磁力链接或种子地址后会显示在这里", actionTitle: "添加种子") { showAddTorrent = true }
                                .frame(minHeight: 260)
                        } else {
                            LazyVStack(spacing: 9) { ForEach(model.filtered) { torrent in TorrentRow(item: torrent, model: model) } }
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
    }
}

struct DownloaderCard: View {
    let item: DownloaderItem
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: item.category == "Tr" || item.category.lowercased().contains("trans") ? "point.3.connected.trianglepath.dotted" : "bolt.horizontal.circle").foregroundStyle(HarvestTheme.green); Spacer(); if item.main { Text("主下载器").font(.caption2.weight(.bold)).foregroundStyle(HarvestTheme.coral) } }
            Text(item.name).font(.headline).lineLimit(1)
            Text(item.host).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            HStack { Label(formatSpeed(item.downloadSpeed), systemImage: "arrow.down").foregroundStyle(HarvestTheme.blue); Label(formatSpeed(item.uploadSpeed), systemImage: "arrow.up").foregroundStyle(HarvestTheme.green) }.font(.caption.monospacedDigit())
        }
        .padding(14).frame(width: 250, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(item.enabled ? HarvestTheme.green.opacity(0.25) : Color.primary.opacity(0.08)))
    }
}

struct TorrentRow: View {
    @EnvironmentObject private var appState: AppState
    let item: TorrentItem
    @ObservedObject var model: DownloadsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) { Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(2); Text(item.category.isEmpty ? item.status : "\(item.status) · \(item.category)").font(.caption2).foregroundStyle(.secondary) }
                Spacer()
                Menu { Button { Task { await model.control(appState, torrent: item, command: "resume") } } label: { Label("开始", systemImage: "play") }; Button { Task { await model.control(appState, torrent: item, command: "pause") } } label: { Label("暂停", systemImage: "pause") }; Button(role: .destructive) { Task { await model.control(appState, torrent: item, command: "delete") } } label: { Label("删除", systemImage: "trash") } } label: { Image(systemName: "ellipsis").frame(width: 30, height: 30) }
            }
            ProgressView(value: item.progress).tint(progressColor)
            HStack { Text("\(Int(item.progress * 100))%").fontWeight(.semibold); Text(formatBytes(item.size)); Spacer(); Label(formatSpeed(item.downloadSpeed), systemImage: "arrow.down").foregroundStyle(HarvestTheme.blue); Label(formatSpeed(item.uploadSpeed), systemImage: "arrow.up").foregroundStyle(HarvestTheme.green) }.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }.cardSurface()
    }

    private var progressColor: Color { item.progress >= 1 ? HarvestTheme.green : item.downloadSpeed > 0 ? HarvestTheme.blue : HarvestTheme.amber }
}

struct AddTorrentSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let downloaders: [DownloaderItem]
    let onSaved: () async -> Void
    @State private var input = ""
    @State private var downloaderID = 0
    @State private var category = ""
    @State private var paused = false

    var body: some View {
        NavigationStack {
            Form {
                Section("种子来源") { TextField("磁力链接、种子 URL 或站点种子 ID", text: $input, axis: .vertical).lineLimit(4...8) }
                Section("下载设置") {
                    Picker("下载器", selection: $downloaderID) { ForEach(downloaders) { Text($0.name).tag($0.id) } }
                    TextField("分类（可选）", text: $category)
                    Toggle("添加后暂停", isOn: $paused)
                }
            }
            .navigationTitle("添加种子").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("推送") { Task {
                    var body: [String: Any] = ["urls": input, "is_paused": paused]
                    if !category.isEmpty { body["category"] = category }
                    if await appState.perform("\(APIPath.pushTorrent)/\(downloaderID)", method: .post, body: body) { await onSaved(); dismiss() }
                } }.disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || downloaderID == 0) }
            }
            .onAppear { if downloaderID == 0 { downloaderID = downloaders.first?.id ?? 0 } }
        }
    }
}

struct DownloaderEditorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onSaved: () async -> Void
    @State private var name = ""
    @State private var type = "Qb"
    @State private var networkProtocol = "http"
    @State private var host = ""
    @State private var port = "8080"
    @State private var username = ""
    @State private var password = ""
    @State private var enabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section("下载器") {
                    TextField("名称", text: $name)
                    Picker("类型", selection: $type) { Text("qBittorrent").tag("Qb"); Text("Transmission").tag("Tr") }
                    Picker("协议", selection: $networkProtocol) { Text("HTTP").tag("http"); Text("HTTPS").tag("https") }
                    TextField("主机地址", text: $host).textInputAutocapitalization(.never).keyboardType(.URL)
                    TextField("端口", text: $port).keyboardType(.numberPad)
                }
                Section("认证") { TextField("账号", text: $username); SecureField("密码", text: $password); Toggle("启用", isOn: $enabled) }
            }
            .navigationTitle("添加下载器").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task {
                    let body: [String: Any] = ["name": name, "category": type, "protocol": networkProtocol, "host": host, "port": Int(port) ?? 0, "username": username, "password": password, "is_active": enabled]
                    if await appState.perform(APIPath.downloaders, method: .post, body: body) { await onSaved(); dismiss() }
                } }.disabled(name.isEmpty || host.isEmpty) }
            }
        }
    }
}
