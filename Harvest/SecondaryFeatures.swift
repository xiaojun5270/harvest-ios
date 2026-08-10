import SwiftUI
import WebKit

struct TaskItem: Identifiable, Hashable {
    let id: Int
    var name: String
    var taskType: String
    var enabled: Bool
    var schedule: String
    var lastRun: String
    var nextRun: String
    var status: String

    init(_ json: [String: Any]) {
        id = json.int("id", "task_id") ?? abs((json.string("name") ?? UUID().uuidString).hashValue)
        name = json.string("name", "task_name", "title") ?? "计划任务"
        taskType = json.string("task", "type", "task_type", "kind") ?? "自动化"
        enabled = json.bool("enable", "enabled", "is_active") ?? true
        let crontab = json.dict("crontab")
        schedule = crontab?.string("express", "name", "schedule") ?? json.string("cron", "schedule", "period") ?? "按计划执行"
        lastRun = json.string("last_run", "last_run_at", "last_executed") ?? "从未执行"
        nextRun = json.string("next_run", "next_run_at") ?? "--"
        status = json.string("status", "state") ?? (enabled ? "等待中" : "已停用")
    }
}

@MainActor
final class TasksViewModel: ObservableObject {
    @Published var tasks: [TaskItem] = []
    @Published var results: [[String: Any]] = []
    @Published var taskTypes: [String] = []
    @Published var crontabs: [[String: Any]] = []
    @Published var isLoading = true
    @Published var mode = "计划"

    func load(_ appState: AppState) async {
        isLoading = tasks.isEmpty && results.isEmpty
        defer { isLoading = false }
        do {
            async let taskRaw = appState.api(APIPath.schedules)
            async let resultRaw = appState.api(APIPath.taskResults)
            async let typeRaw = appState.api(APIPath.taskTypes)
            async let crontabRaw = appState.api(APIPath.crontabs)
            let (taskValue, resultValue, typeValue, crontabValue) = try await (taskRaw, resultRaw, typeRaw, crontabRaw)
            tasks = jsonRows(taskValue).map(TaskItem.init)
            if tasks.isEmpty, let root = jsonPayloadDictionary(taskValue) { tasks = root.rows("tasks", "schedules").map(TaskItem.init) }
            results = jsonRows(resultValue)
            taskTypes = jsonStrings(typeValue)
            crontabs = jsonRows(crontabValue)
        } catch { appState.presentedError = error.localizedDescription }
    }

    func run(_ appState: AppState, task: TaskItem) async {
        if await appState.perform(APIPath.taskExecute, method: .get, query: ["task_id": task.id]) { await load(appState) }
    }

    func remove(_ appState: AppState, task: TaskItem) async {
        if await appState.perform("\(APIPath.schedules)/\(task.id)", method: .delete) { tasks.removeAll { $0.id == task.id } }
    }
}

struct TasksView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = TasksViewModel()
    @State private var showEditor = false

    var body: some View {
        Group {
            if model.isLoading { LoadingState() }
            else if model.tasks.isEmpty { EmptyState(icon: "checklist", title: "没有计划任务", detail: "创建自动签到、站点更新或辅种任务", actionTitle: "新建任务") { showEditor = true } }
            else {
                List {
                    Section { Picker("视图", selection: $model.mode) { Text("计划").tag("计划"); Text("执行记录").tag("执行记录") }.pickerStyle(.segmented).listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)) }
                    if model.mode == "计划" {
                        ForEach(model.tasks) { task in
                            TaskRow(item: task) { Task { await model.run(appState, task: task) } }
                                .swipeActions(edge: .trailing) { Button(role: .destructive) { Task { await model.remove(appState, task: task) } } label: { Label("删除", systemImage: "trash") } }
                        }
                    } else {
                        ForEach(Array(model.results.enumerated()), id: \.offset) { _, result in ResultRow(result: result) }
                    }
                }.listStyle(.insetGrouped).refreshable { await model.load(appState) }
            }
        }
        .navigationTitle("任务中心").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showEditor = true } label: { Image(systemName: "plus") }.accessibilityLabel("新建任务") } }
        .task { if model.isLoading { await model.load(appState) } }
        .sheet(isPresented: $showEditor) { TaskEditorSheet(taskTypes: model.taskTypes, crontabs: model.crontabs) { await model.load(appState) }.environmentObject(appState) }
    }
}

struct TaskRow: View {
    let item: TaskItem
    let run: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8).fill(item.enabled ? HarvestTheme.green.opacity(0.14) : Color.secondary.opacity(0.12)).frame(width: 44, height: 44).overlay(Image(systemName: item.enabled ? "clock.badge.checkmark" : "pause.circle").foregroundStyle(item.enabled ? HarvestTheme.green : .secondary))
            VStack(alignment: .leading, spacing: 5) { Text(item.name).font(.headline); Text(item.taskType).font(.caption).foregroundStyle(.secondary); Text(item.schedule).font(.caption2).foregroundStyle(.tertiary) }
            Spacer()
            Button(action: run) { Image(systemName: "play.fill").frame(width: 34, height: 34).background(HarvestTheme.green.opacity(0.12), in: Circle()).foregroundStyle(HarvestTheme.green) }.buttonStyle(.plain).accessibilityLabel("立即执行")
        }.padding(.vertical, 4)
    }
}

struct ResultRow: View {
    let result: [String: Any]
    var body: some View {
        VStack(alignment: .leading, spacing: 5) { Text(result.string("task", "name", "task_name") ?? "任务执行").font(.subheadline.weight(.semibold)); Text(result.string("status", "state", "result") ?? "已完成").font(.caption).foregroundStyle(.secondary); Text(result.string("created_at", "date", "time") ?? "").font(.caption2).foregroundStyle(.tertiary) }
    }
}

struct TaskEditorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let taskTypes: [String]
    let crontabs: [[String: Any]]
    let onSaved: () async -> Void
    @State private var name = ""
    @State private var type = ""
    @State private var crontabID = 0
    @State private var enabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section("任务") {
                    TextField("任务名称", text: $name)
                    Picker("类型", selection: $type) { ForEach(taskTypes, id: \.self) { Text($0).tag($0) } }
                    Picker("执行计划", selection: $crontabID) {
                        ForEach(Array(crontabs.enumerated()), id: \.offset) { _, item in
                            Text(item.string("express") ?? "计划 \(item.int("id") ?? 0)").tag(item.int("id") ?? 0)
                        }
                    }
                    Toggle("启用任务", isOn: $enabled)
                }
                Section { Text("执行计划由 Harvest 服务端统一维护。").font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle("新建任务").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { let body: [String: Any] = ["id": 0, "name": name, "task": type, "crontab_id": crontabID, "args": "[]", "kwargs": "{}", "enabled": enabled]; if await appState.perform(APIPath.schedules, method: .post, body: body) { await onSaved(); dismiss() } } }.disabled(name.isEmpty || type.isEmpty || crontabID == 0) } }
            .onAppear { if type.isEmpty { type = taskTypes.first ?? "" }; if crontabID == 0 { crontabID = crontabs.first?.int("id") ?? 0 } }
        }
    }
}

struct MediaItem: Identifiable, Hashable {
    let id: String
    var title: String
    var subtitle: String
    var overview: String
    var poster: String
    var score: Double
    var year: String
    var source: String

    init(_ json: [String: Any], source: String) {
        id = json.string("id", "subject_id", "tmdb_id") ?? UUID().uuidString
        title = json.string("title", "name", "original_title") ?? "未命名"
        subtitle = json.string("original_title", "original_name", "card_subtitle") ?? ""
        overview = json.string("overview", "abstract", "summary") ?? ""
        poster = json.string("poster_path", "poster", "cover_url", "cover") ?? ""
        score = json.double("vote_average", "rating", "score") ?? 0
        year = json.string("release_date", "first_air_date", "year")?.prefix(4).description ?? ""
        self.source = source
    }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var mode = "影视"
    @Published var media: [MediaItem] = []
    @Published var resources: [[String: Any]] = []
    @Published var isLoading = false

    func search(_ appState: AppState) async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if mode == "影视" {
                async let tmdb = appState.api(APIPath.tmdbSearch, method: .get, query: ["query": term])
                async let douban = appState.api(APIPath.doubanSearch, method: .get, query: ["q": term, "query": term])
                let (tmdbRaw, doubanRaw) = try await (tmdb, douban)
                media = jsonRows(tmdbRaw).map { MediaItem($0, source: "TMDB") } + jsonRows(doubanRaw).map { MediaItem($0, source: "豆瓣") }
            } else {
                resources = []
                for try await event in APIClient.shared.streamSSE(
                    baseURL: appState.baseURL,
                    path: APIPath.siteSearch,
                    token: appState.accessToken,
                    body: ["key": term, "max_count": 5, "sites": []]
                ) {
                    guard (event.bool("succeed") ?? (event.int("code") == 0)) else { continue }
                    if let data = event["data"] {
                        let rows = jsonRows(data)
                        if rows.isEmpty, let row = jsonDictionary(data) { resources.append(row) }
                        else { resources.append(contentsOf: rows) }
                    }
                }
            }
        } catch { appState.presentedError = error.localizedDescription }
    }
}

struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = SearchViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Picker("搜索类型", selection: $model.mode) { Text("影视").tag("影视"); Text("资源").tag("资源") }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.top, 12)
            if model.isLoading { LoadingState() }
            else if model.mode == "影视" && model.media.isEmpty { EmptyState(icon: "magnifyingglass", title: "搜索影视信息", detail: "同时搜索 TMDB 与豆瓣，查看评分和简介") }
            else if model.mode == "资源" && model.resources.isEmpty { EmptyState(icon: "rectangle.stack", title: "搜索站点资源", detail: "输入关键词获取可推送的种子资源") }
            else {
                List {
                    if model.mode == "影视" { ForEach(model.media) { MediaRow(item: $0) } }
                    else { ForEach(Array(model.resources.enumerated()), id: \.offset) { _, item in ResourceRowItem(item: item) } }
                }.listStyle(.plain)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .searchable(text: $model.query, prompt: model.mode == "影视" ? "电影、剧集、演员" : "片名、发布组、站点")
        .onSubmit(of: .search) { Task { await model.search(appState) } }
        .navigationTitle("搜索").navigationBarTitleDisplayMode(.inline)
    }
}

struct MediaRow: View {
    let item: MediaItem
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: item.poster)) { phase in
                switch phase { case .success(let image): image.resizable().scaledToFill(); default: RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)).overlay(Image(systemName: "film").foregroundStyle(.secondary)) }
            }.frame(width: 62, height: 88).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 6) { Text(item.title).font(.headline); if !item.subtitle.isEmpty { Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Text(item.overview).font(.caption).foregroundStyle(.secondary).lineLimit(2); HStack { if item.score > 0 { Label(String(format: "%.1f", item.score), systemImage: "star.fill").foregroundStyle(HarvestTheme.amber) }; if !item.year.isEmpty { Text(item.year) }; Text(item.source).foregroundStyle(HarvestTheme.green) }.font(.caption2) }
        }.padding(.vertical, 5)
    }
}

struct ResourceRowItem: View {
    let item: [String: Any]
    var body: some View {
        VStack(alignment: .leading, spacing: 7) { Text(item.string("title", "name") ?? "未命名资源").font(.subheadline.weight(.semibold)).lineLimit(2); HStack { Text(item.string("site", "site_name") ?? "未知站点"); Spacer(); Text(item.string("size", "length") ?? ""); Text(item.string("seeders", "seed", "seeder") ?? "").foregroundStyle(HarvestTheme.green) }.font(.caption).foregroundStyle(.secondary); if let tags = item.string("tags", "description") { Text(tags).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) } }.padding(.vertical, 5)
    }
}

struct NewsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var movies: [MediaItem] = []
    @State private var tvs: [MediaItem] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            if isLoading { LoadingState() }
            else { LazyVStack(alignment: .leading, spacing: 20) { MediaCarousel(title: "热门电影", items: movies); MediaCarousel(title: "热门剧集", items: tvs); NewsLinkRow(title: "站点动态", subtitle: "查看签到、公告和数据同步记录", icon: "antenna.radiowaves.left.and.right", color: HarvestTheme.green) } .padding(16) }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable { await load() }
        .navigationTitle("资讯").navigationBarTitleDisplayMode(.inline)
        .task { if isLoading { await load() } }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            async let movieRaw = appState.api(APIPath.tmdbPopularMovies)
            async let tvRaw = appState.api(APIPath.tmdbPopularTV)
            movies = jsonRows(try await movieRaw).map { MediaItem($0, source: "TMDB") }
            tvs = jsonRows(try await tvRaw).map { MediaItem($0, source: "TMDB") }
        } catch { appState.presentedError = error.localizedDescription }
    }
}

struct MediaCarousel: View {
    let title: String
    let items: [MediaItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { SectionHeader(title: title, actionTitle: "查看全部") {}; ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 11) { ForEach(items.prefix(12)) { item in VStack(alignment: .leading, spacing: 6) { AsyncImage(url: URL(string: item.poster)) { phase in switch phase { case .success(let image): image.resizable().scaledToFill(); default: Color.secondary.opacity(0.12).overlay(Image(systemName: "film").foregroundStyle(.secondary)) } }.frame(width: 112, height: 156).clipShape(RoundedRectangle(cornerRadius: 7)); Text(item.title).font(.caption.weight(.semibold)).lineLimit(1); if item.score > 0 { Text(String(format: "★ %.1f", item.score)).font(.caption2).foregroundStyle(HarvestTheme.amber) } }.frame(width: 112, alignment: .leading) } } } }
    }
}

struct NewsLinkRow: View {
    let title: String; let subtitle: String; let icon: String; let color: Color
    var body: some View { HStack(spacing: 12) { Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 42, height: 42).background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 8)); VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }.cardSurface() }
}
