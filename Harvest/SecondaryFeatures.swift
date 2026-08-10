import Foundation
import SwiftUI
import WebKit

struct TaskItem: Identifiable {
    let id: Int
    var name: String
    var taskType: String
    var description: String
    var enabled: Bool
    var schedule: String
    var crontabID: Int
    var minute: String
    var hour: String
    var dayOfMonth: String
    var monthOfYear: String
    var dayOfWeek: String
    var args: String
    var kwargs: String
    var raw: [String: Any]

    init(_ json: [String: Any]) {
        id = json.int("id", "task_id") ?? abs((json.string("name") ?? UUID().uuidString).hashValue)
        name = json.string("name", "task_name", "title") ?? "计划任务"
        taskType = json.string("task", "type", "task_type", "kind") ?? "自动化"
        description = json.string("description", "detail") ?? ""
        enabled = json.bool("enable", "enabled", "is_active") ?? true
        let crontab = json.dict("crontab")
        let cronMinute = crontab?.string("minute") ?? "1"
        let cronHour = crontab?.string("hour") ?? "*"
        let cronDayOfMonth = crontab?.string("day_of_month", "dayOfMonth") ?? "*"
        let cronMonthOfYear = crontab?.string("month_of_year", "monthOfYear") ?? "*"
        let cronDayOfWeek = crontab?.string("day_of_week", "dayOfWeek") ?? "*"
        minute = cronMinute
        hour = cronHour
        dayOfMonth = cronDayOfMonth
        monthOfYear = cronMonthOfYear
        dayOfWeek = cronDayOfWeek
        let expression = crontab?.string("express", "name", "schedule")
            ?? json.string("cron", "schedule", "period")
            ?? ""
        schedule = expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? [cronMinute, cronHour, cronDayOfMonth, cronMonthOfYear, cronDayOfWeek].joined(separator: " ")
            : expression
        crontabID = json.int("crontab_id", "crontabId") ?? crontab?.int("id") ?? 0
        args = json.string("args") ?? "[]"
        kwargs = json.string("kwargs") ?? "{}"
        raw = json
    }
}

struct TaskResultItem: Identifiable {
    let id: String
    var taskID: String
    var name: String
    var status: String
    var summary: String
    var createdAt: String
    var finishedAt: String
    var raw: [String: Any]

    init(_ json: [String: Any]) {
        let taskID = json.string("task_id", "taskId", "celery_task_id", "celeryTaskId", "uuid") ?? ""
        let resultID = json.string("id", "result_id", "resultId") ?? ""
        self.id = resultID.isEmpty ? (taskID.isEmpty ? UUID().uuidString : taskID) : resultID
        self.taskID = taskID.isEmpty ? self.id : taskID
        name = json.string("name", "task_name", "taskName", "task") ?? "未命名任务"
        status = json.string("status", "state", "result_status", "resultStatus") ?? "UNKNOWN"
        if let value = json["summary"] ?? json["message"] ?? json["result"] ?? json["retval"] ?? json["traceback"] ?? json["error"] {
            summary = (value as? String) ?? prettyJSON(value)
        } else {
            summary = ""
        }
        createdAt = json.string("created_at", "createdAt", "date_created", "dateCreated", "started_at", "startedAt", "timestamp") ?? ""
        finishedAt = json.string("updated_at", "updatedAt", "date_done", "dateDone", "finished_at", "finishedAt", "completed_at", "completedAt") ?? ""
        raw = json
    }

    var isActive: Bool {
        ["pending", "received", "started", "retry", "running", "progress"].contains(status.lowercased())
    }
}

@MainActor
final class TasksViewModel: ObservableObject {
    @Published var tasks: [TaskItem] = []
    @Published var results: [TaskResultItem] = []
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
            results = jsonRows(resultValue).map(TaskResultItem.init)
            taskTypes = jsonStrings(typeValue)
            crontabs = jsonRows(crontabValue)
        } catch { appState.presentedError = error.localizedDescription }
    }

    func run(_ appState: AppState, task: TaskItem) async {
        if await appState.perform(APIPath.taskExecute, method: .get, query: ["task_id": task.id]) { await load(appState) }
    }

    func toggle(_ appState: AppState, task: TaskItem) async {
        if await appState.perform(
            APIPath.schedules,
            method: .put,
            body: ["id": task.id, "enabled": !task.enabled]
        ) { await load(appState) }
    }

    func remove(_ appState: AppState, task: TaskItem) async {
        if await appState.perform("\(APIPath.schedules)/\(task.id)", method: .delete) { tasks.removeAll { $0.id == task.id } }
    }

    func terminate(_ appState: AppState, result: TaskResultItem) async {
        guard !result.taskID.isEmpty else { return }
        if await appState.perform(
            APIPath.taskResults + urlPathSegment(result.taskID),
            method: .put,
            body: [String: Any]()
        ) { await load(appState) }
    }

    func removeResult(_ appState: AppState, result: TaskResultItem) async {
        guard !result.taskID.isEmpty else { return }
        if await appState.perform(
            APIPath.taskResults + urlPathSegment(result.taskID),
            method: .delete
        ) { results.removeAll { $0.id == result.id } }
    }

    func clearResults(_ appState: AppState) async {
        if await appState.perform(APIPath.taskResults, method: .delete) { results = [] }
    }
}

struct TasksView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = TasksViewModel()
    @State private var showEditor = false
    @State private var editingTask: TaskItem?
    @State private var selectedResult: TaskResultItem?
    @State private var confirmClearResults = false

    var body: some View {
        Group {
            if model.isLoading { LoadingState() }
            else {
                List {
                    Section { Picker("视图", selection: $model.mode) { Text("计划").tag("计划"); Text("执行记录").tag("执行记录") }.pickerStyle(.segmented).listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)) }
                    if model.mode == "计划" {
                        if model.tasks.isEmpty {
                            EmptyState(icon: "checklist", title: "没有计划任务", detail: "创建自动签到、站点更新或辅种任务", actionTitle: "新建任务") { showEditor = true }
                                .frame(minHeight: 320)
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(model.tasks) { task in
                                TaskRow(item: task) {
                                    Task { await model.run(appState, task: task) }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { editingTask = task }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button { Task { await model.toggle(appState, task: task) } } label: {
                                        Label(task.enabled ? "停用" : "启用", systemImage: task.enabled ? "pause" : "play")
                                    }
                                    .tint(HarvestTheme.amber)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button { editingTask = task } label: { Label("编辑", systemImage: "pencil") }.tint(HarvestTheme.blue)
                                    Button(role: .destructive) { Task { await model.remove(appState, task: task) } } label: { Label("删除", systemImage: "trash") }
                                }
                            }
                        }
                    } else {
                        if model.results.isEmpty {
                            EmptyState(icon: "clock.badge.questionmark", title: "没有执行记录", detail: "任务执行后可在此查看结果")
                                .frame(minHeight: 320)
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(model.results) { result in
                                Button { selectedResult = result } label: { ResultRow(result: result) }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        if result.isActive {
                                            Button { Task { await model.terminate(appState, result: result) } } label: { Label("终止", systemImage: "stop.fill") }.tint(HarvestTheme.amber)
                                        }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) { Task { await model.removeResult(appState, result: result) } } label: { Label("删除", systemImage: "trash") }
                                    }
                            }
                        }
                    }
                }.listStyle(.insetGrouped).refreshable { await model.load(appState) }
            }
        }
        .navigationTitle("任务中心").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.mode == "计划" {
                    Button { showEditor = true } label: { Image(systemName: "plus") }.accessibilityLabel("新建任务")
                } else if !model.results.isEmpty {
                    Button(role: .destructive) { confirmClearResults = true } label: { Image(systemName: "trash") }.accessibilityLabel("清空执行记录")
                }
            }
        }
        .task { if model.isLoading { await model.load(appState) } }
        .sheet(isPresented: $showEditor) { TaskEditorSheet(taskTypes: model.taskTypes, crontabs: model.crontabs) { await model.load(appState) }.environmentObject(appState) }
        .sheet(item: $editingTask) { task in TaskEditorSheet(task: task, taskTypes: model.taskTypes, crontabs: model.crontabs) { await model.load(appState) }.environmentObject(appState) }
        .sheet(item: $selectedResult) { result in
            TaskResultDetailSheet(
                result: result,
                onTerminate: { await model.terminate(appState, result: result) },
                onDelete: { await model.removeResult(appState, result: result) }
            )
        }
        .confirmationDialog("确定清空全部执行记录？", isPresented: $confirmClearResults, titleVisibility: .visible) {
            Button("清空执行记录", role: .destructive) { Task { await model.clearResults(appState) } }
        }
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
    let result: TaskResultItem
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.isActive ? "clock.arrow.circlepath" : result.status.lowercased().contains("success") ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(result.isActive ? HarvestTheme.amber : result.status.lowercased().contains("success") ? HarvestTheme.green : HarvestTheme.coral)
            VStack(alignment: .leading, spacing: 5) {
                Text(result.name).font(.subheadline.weight(.semibold))
                Text(result.status).font(.caption).foregroundStyle(.secondary)
                Text(result.createdAt).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

struct TaskEditorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem?
    let taskTypes: [String]
    let crontabs: [[String: Any]]
    let onSaved: () async -> Void
    @State private var name: String
    @State private var type: String
    @State private var description: String
    @State private var crontabID: Int
    @State private var minute: String
    @State private var hour: String
    @State private var dayOfMonth: String
    @State private var monthOfYear: String
    @State private var dayOfWeek: String
    @State private var args: String
    @State private var kwargs: String
    @State private var enabled: Bool
    @State private var validationError: String?

    init(task: TaskItem? = nil, taskTypes: [String], crontabs: [[String: Any]], onSaved: @escaping () async -> Void) {
        self.task = task
        self.taskTypes = taskTypes
        self.crontabs = crontabs
        self.onSaved = onSaved
        _name = State(initialValue: task?.name ?? "")
        _type = State(initialValue: task?.taskType ?? "")
        _description = State(initialValue: task?.description ?? "")
        _crontabID = State(initialValue: task?.crontabID ?? 0)
        let currentCrontabID = task?.crontabID ?? 0
        let configuredCrontab = currentCrontabID > 0
            ? crontabs.first { $0.int("id") == currentCrontabID }
            : nil
        let inlineCrontab = task?.raw.dict("crontab")
        _minute = State(initialValue: inlineCrontab?.string("minute") ?? configuredCrontab?.string("minute") ?? task?.minute ?? "1")
        _hour = State(initialValue: inlineCrontab?.string("hour") ?? configuredCrontab?.string("hour") ?? task?.hour ?? "*")
        _dayOfMonth = State(initialValue: inlineCrontab?.string("day_of_month", "dayOfMonth") ?? configuredCrontab?.string("day_of_month", "dayOfMonth") ?? task?.dayOfMonth ?? "*")
        _monthOfYear = State(initialValue: inlineCrontab?.string("month_of_year", "monthOfYear") ?? configuredCrontab?.string("month_of_year", "monthOfYear") ?? task?.monthOfYear ?? "*")
        _dayOfWeek = State(initialValue: inlineCrontab?.string("day_of_week", "dayOfWeek") ?? configuredCrontab?.string("day_of_week", "dayOfWeek") ?? task?.dayOfWeek ?? "*")
        _args = State(initialValue: task?.args ?? "[]")
        _kwargs = State(initialValue: task?.kwargs ?? "{}")
        _enabled = State(initialValue: task?.enabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("任务") {
                    TextField("任务名称", text: $name)
                    TextField("任务说明（可选）", text: $description)
                    Picker("类型", selection: $type) { ForEach(taskTypes, id: \.self) { Text($0).tag($0) } }
                    Picker("计划模板", selection: $crontabID) {
                        Text("自定义").tag(0)
                        ForEach(Array(crontabs.enumerated()), id: \.offset) { _, item in
                            Text(item.string("express") ?? "计划 \(item.int("id") ?? 0)").tag(item.int("id") ?? 0)
                        }
                    }
                    .onChange(of: crontabID) { _, value in applyCrontab(value) }
                    Toggle("启用任务", isOn: $enabled)
                }
                Section("执行计划") {
                    TextField("分钟", text: $minute).textInputAutocapitalization(.never)
                    TextField("小时", text: $hour).textInputAutocapitalization(.never)
                    TextField("每月日期", text: $dayOfMonth).textInputAutocapitalization(.never)
                    TextField("月份", text: $monthOfYear).textInputAutocapitalization(.never)
                    TextField("星期", text: $dayOfWeek).textInputAutocapitalization(.never)
                    Text("Cron 顺序：分钟、小时、日期、月份、星期").font(.caption).foregroundStyle(.secondary)
                }
                Section("参数 JSON") {
                    TextField("位置参数，例如 []", text: $args, axis: .vertical).font(.system(.caption, design: .monospaced))
                    TextField("关键字参数，例如 {}", text: $kwargs, axis: .vertical).font(.system(.caption, design: .monospaced))
                    if let validationError { Label(validationError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(HarvestTheme.coral) }
                }
            }
            .navigationTitle(task == nil ? "新建任务" : "编辑任务").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(name.isEmpty || type.isEmpty || minute.isEmpty || hour.isEmpty) } }
            .onAppear { if type.isEmpty { type = taskTypes.first ?? "" } }
        }
    }

    private func save() async {
        guard validJSON(args, expected: [Any].self), validJSON(kwargs, expected: [String: Any].self) else {
            validationError = "位置参数必须是数组，关键字参数必须是对象"
            return
        }
        validationError = nil
        let crontab: [String: Any] = [
            "id": crontabID,
            "express": "",
            "minute": minute.trimmingCharacters(in: .whitespacesAndNewlines),
            "hour": hour.trimmingCharacters(in: .whitespacesAndNewlines),
            "day_of_month": dayOfMonth.trimmingCharacters(in: .whitespacesAndNewlines),
            "month_of_year": monthOfYear.trimmingCharacters(in: .whitespacesAndNewlines),
            "day_of_week": dayOfWeek.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        let body: [String: Any] = [
            "id": task?.id ?? 0,
            "name": name,
            "task": type,
            "description": description,
            "crontab_id": NSNull(),
            "crontab": crontab,
            "args": args,
            "kwargs": kwargs,
            "enabled": enabled
        ]
        let method: HTTPMethod = task == nil ? .post : .put
        if await appState.perform(APIPath.schedules, method: method, body: body) {
            await onSaved()
            dismiss()
        }
    }

    private func applyCrontab(_ id: Int) {
        guard id != 0, let crontab = crontabs.first(where: { $0.int("id") == id }) else { return }
        minute = crontab.string("minute") ?? minute
        hour = crontab.string("hour") ?? hour
        dayOfMonth = crontab.string("day_of_month", "dayOfMonth") ?? dayOfMonth
        monthOfYear = crontab.string("month_of_year", "monthOfYear") ?? monthOfYear
        dayOfWeek = crontab.string("day_of_week", "dayOfWeek") ?? dayOfWeek
    }

    private func validJSON<T>(_ text: String, expected: T.Type) -> Bool {
        guard let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) else { return false }
        return value is T
    }
}

struct TaskResultDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let result: TaskResultItem
    let onTerminate: () async -> Void
    let onDelete: () async -> Void
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section("执行状态") {
                    LabeledContent("任务", value: result.name)
                    LabeledContent("状态", value: result.status)
                    LabeledContent("任务 ID", value: result.taskID)
                    if !result.createdAt.isEmpty { LabeledContent("开始", value: result.createdAt) }
                    if !result.finishedAt.isEmpty { LabeledContent("结束", value: result.finishedAt) }
                }
                if !result.summary.isEmpty {
                    Section("结果") { Text(result.summary).font(.callout.monospaced()).textSelection(.enabled) }
                }
                Section("原始记录") { Text(prettyJSON(result.raw)).font(.caption.monospaced()).textSelection(.enabled) }
                Section {
                    if result.isActive {
                        Button { Task { await onTerminate(); dismiss() } } label: { Label("终止任务", systemImage: "stop.fill") }.tint(HarvestTheme.amber)
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("删除记录", systemImage: "trash") }
                }
            }
            .navigationTitle("执行详情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .confirmationDialog("确定删除这条执行记录？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除记录", role: .destructive) { Task { await onDelete(); dismiss() } }
            }
        }
    }
}

struct MediaItem: Identifiable {
    let id: String
    var remoteID: String
    var title: String
    var subtitle: String
    var overview: String
    var poster: String
    var score: Double
    var year: String
    var source: String
    var mediaType: String
    var raw: [String: Any]

    init(_ json: [String: Any], source: String, mediaType: String = "") {
        let content = json.dict("target") ?? json
        remoteID = content.string("id", "subject_id", "tmdb_id") ?? json.string("target_id", "targetId") ?? UUID().uuidString
        let resolvedType = mediaType.isEmpty ? (json.string("media_type", "target_type", "targetType") ?? content.string("media_type") ?? "") : mediaType
        id = "\(source):\(resolvedType):\(remoteID)"
        title = content.string("title", "name", "original_title") ?? "未命名"
        subtitle = content.string("original_title", "original_name", "card_subtitle") ?? ""
        overview = content.string("overview", "abstract", "summary") ?? ""
        poster = mediaPosterURL(content.string("poster_path", "profile_path", "poster", "cover_url", "cover") ?? "", source: source)
        score = content.double("vote_average", "score") ?? content.dict("rating")?.double("value", "star_count") ?? 0
        year = content.string("release_date", "first_air_date", "year")?.prefix(4).description ?? ""
        self.source = source
        self.mediaType = resolvedType
        raw = json
    }
}

private func mediaPosterURL(_ value: String, source: String) -> String {
    guard !value.isEmpty else { return "" }
    if source == "TMDB", value.hasPrefix("/") {
        return "https://image.tmdb.org/t/p/w500\(value)"
    }
    return value
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
                async let tmdb = appState.api("\(APIPath.tmdbSearch)/\(urlPathSegment(term))")
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
                    guard (event.bool("succeed") ?? (event.int("code") == 0)) else {
                        if let message = jsonMessage(event), !message.isEmpty { appState.presentedError = message }
                        continue
                    }
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

private struct ResourceSelection: Identifiable {
    let id = UUID()
    let value: [String: Any]
}

struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = SearchViewModel()
    @State private var selectedMedia: MediaItem?
    @State private var selectedResource: ResourceSelection?

    var body: some View {
        VStack(spacing: 0) {
            Picker("搜索类型", selection: $model.mode) { Text("影视").tag("影视"); Text("资源").tag("资源") }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.top, 12)
            if model.isLoading { LoadingState() }
            else if model.mode == "影视" && model.media.isEmpty { EmptyState(icon: "magnifyingglass", title: "搜索影视信息", detail: "同时搜索 TMDB 与豆瓣，查看评分和简介") }
            else if model.mode == "资源" && model.resources.isEmpty { EmptyState(icon: "rectangle.stack", title: "搜索站点资源", detail: "输入关键词获取可推送的种子资源") }
            else {
                List {
                    if model.mode == "影视" {
                        ForEach(model.media) { item in
                            Button { selectedMedia = item } label: { MediaRow(item: item) }
                                .buttonStyle(.plain)
                        }
                    } else {
                        ForEach(Array(model.resources.enumerated()), id: \.offset) { _, item in
                            Button { selectedResource = ResourceSelection(value: item) } label: { ResourceRowItem(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                }.listStyle(.plain)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .searchable(text: $model.query, prompt: model.mode == "影视" ? "电影、剧集、演员" : "片名、发布组、站点")
        .onSubmit(of: .search) { Task { await model.search(appState) } }
        .navigationTitle("搜索").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedMedia) { item in MediaDetailSheet(item: item).environmentObject(appState) }
        .sheet(item: $selectedResource) { selection in ResourcePushSheet(item: selection.value).environmentObject(appState) }
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(item.string("title", "name") ?? "未命名资源").font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack {
                    Text(item.string("site", "site_name") ?? "未知站点")
                    Spacer()
                    Text(item.string("size", "length") ?? "")
                    Text(item.string("seeders", "seed", "seeder") ?? "").foregroundStyle(HarvestTheme.green)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let tags = item.string("tags", "description") { Text(tags).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
            }
            Image(systemName: "arrow.down.circle").foregroundStyle(HarvestTheme.green)
        }
        .padding(.vertical, 5)
    }
}

struct MediaDetailSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem
    @State private var detail: [String: Any]?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        AsyncImage(url: URL(string: poster)) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFill()
                            default: Color.secondary.opacity(0.12).overlay(Image(systemName: "film").foregroundStyle(.secondary))
                            }
                        }
                        .frame(width: 104, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title).font(.title3.weight(.semibold))
                            if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                            HStack(spacing: 10) {
                                if score > 0 { Label(String(format: "%.1f", score), systemImage: "star.fill").foregroundStyle(HarvestTheme.amber) }
                                if !year.isEmpty { Text(year) }
                                Text(item.source).foregroundStyle(HarvestTheme.green)
                            }
                            .font(.caption)
                            if !genres.isEmpty { Text(genres).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if isLoading {
                    Section { ProgressView().frame(maxWidth: .infinity) }
                }
                if !overview.isEmpty {
                    Section("简介") { Text(overview).textSelection(.enabled) }
                }
                Section("信息") {
                    if let status = resolved.string("status", "type"), !status.isEmpty { LabeledContent("状态", value: status) }
                    if let language = resolved.string("original_language", "language"), !language.isEmpty { LabeledContent("语言", value: language) }
                    if let runtime = resolved.int("runtime", "number_of_episodes"), runtime > 0 { LabeledContent(item.mediaType == "tv" ? "集数" : "片长", value: item.mediaType == "tv" ? "\(runtime)" : "\(runtime) 分钟") }
                    LabeledContent("条目 ID", value: item.remoteID)
                }
                if let homepage = resolved.string("homepage", "url"), let url = URL(string: homepage) {
                    Section { Link(destination: url) { Label("打开官方页面", systemImage: "safari") } }
                }
            }
            .navigationTitle("影视详情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await load() }
        }
    }

    private var resolved: [String: Any] { detail ?? item.raw.dict("target") ?? item.raw }
    private var title: String { resolved.string("title", "name") ?? item.title }
    private var subtitle: String { resolved.string("original_title", "original_name", "card_subtitle") ?? item.subtitle }
    private var overview: String { resolved.string("overview", "summary", "abstract", "intro", "biography") ?? item.overview }
    private var poster: String { mediaPosterURL(resolved.string("poster_path", "profile_path", "cover_url", "cover") ?? item.poster, source: item.source) }
    private var score: Double { resolved.double("vote_average", "score") ?? resolved.dict("rating")?.double("value") ?? item.score }
    private var year: String { (resolved.string("release_date", "first_air_date", "year") ?? item.year).prefix(4).description }
    private var genres: String {
        guard let value = resolved["genres"] else { return "" }
        return jsonRows(value).compactMap { $0.string("name") }.joined(separator: " / ")
    }

    private func load() async {
        defer { isLoading = false }
        let path: String
        if item.source == "豆瓣" {
            path = APIPath.doubanSubject + urlPathSegment(item.remoteID)
        } else {
            switch item.mediaType.lowercased() {
            case "tv": path = APIPath.tmdbTV + urlPathSegment(item.remoteID)
            case "person": path = APIPath.tmdbPerson + urlPathSegment(item.remoteID)
            default: path = APIPath.tmdbMovie + urlPathSegment(item.remoteID)
            }
        }
        do { detail = jsonPayloadDictionary(try await appState.api(path)) }
        catch { appState.presentedError = error.localizedDescription }
    }
}

struct ResourcePushSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let item: [String: Any]
    @State private var downloaders: [DownloaderItem] = []
    @State private var downloaderID = 0
    @State private var url: String
    @State private var savePath = ""
    @State private var suggestedPaths: [String] = []
    @State private var category = ""
    @State private var tags: String
    @State private var paused = false
    @State private var skipChecking = false
    @State private var isLoading = true
    @State private var isSaving = false

    init(item: [String: Any]) {
        self.item = item
        _url = State(initialValue: item.string("magnet_url", "magnetUrl", "detail_url", "detailUrl", "download_url", "url") ?? "")
        let values = item.strings("tags")
        _tags = State(initialValue: values.isEmpty ? (item.string("tags") ?? "") : values.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("资源") {
                    Text(item.string("title", "name") ?? "未命名资源").font(.headline)
                    TextField("磁力链接或种子地址", text: $url, axis: .vertical).lineLimit(3...6).textInputAutocapitalization(.never)
                }
                Section("下载器") {
                    if isLoading { ProgressView().frame(maxWidth: .infinity) }
                    else if downloaders.isEmpty { Text("没有可用下载器").foregroundStyle(.secondary) }
                    else { Picker("目标下载器", selection: $downloaderID) { ForEach(downloaders) { Text($0.name).tag($0.id) } } }
                    if !suggestedPaths.isEmpty { Picker("常用路径", selection: $savePath) { Text("不指定").tag(""); ForEach(suggestedPaths, id: \.self) { Text($0).tag($0) } } }
                    TextField("保存路径（可选）", text: $savePath)
                    TextField("分类（可选）", text: $category)
                    TextField("标签，使用逗号分隔", text: $tags)
                }
                Section("选项") {
                    Toggle("添加后暂停", isOn: $paused)
                    Toggle("跳过文件校验", isOn: $skipChecking)
                }
            }
            .navigationTitle("推送资源").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("推送") { Task { await push() } }.disabled(isLoading || isSaving || downloaderID == 0 || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .task { await load() }
        }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            let downloaderValue = try await appState.api(APIPath.downloaders)
            downloaders = jsonRows(downloaderValue).map(DownloaderItem.init).filter { $0.enabled }
            do {
                suggestedPaths = jsonPathStrings(try await appState.api(APIPath.downloaderPaths))
            } catch {
                suggestedPaths = []
            }
            downloaderID = downloaders.first?.id ?? 0
        } catch { appState.presentedError = error.localizedDescription }
    }

    private func push() async {
        isSaving = true
        defer { isSaving = false }
        var body: [String: Any] = [
            "urls": url.trimmingCharacters(in: .whitespacesAndNewlines),
            "is_paused": paused,
            "is_skip_checking": skipChecking
        ]
        if let tid = item.string("tid", "torrent_id", "id"), !tid.isEmpty { body["tid"] = tid; body["ids"] = tid }
        if let siteID = item.string("site_id", "siteId"), !siteID.isEmpty { body["site_id"] = siteID }
        if let cookie = item.string("cookie"), !cookie.isEmpty { body["cookie"] = cookie }
        if !savePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["save_path"] = savePath.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["category"] = category.trimmingCharacters(in: .whitespacesAndNewlines) }
        let tagValues = tags.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !tagValues.isEmpty { body["tags"] = tagValues }
        if await appState.perform("\(APIPath.pushTorrent)/\(downloaderID)", method: .post, body: body) { dismiss() }
    }
}

private struct MediaCollection: Identifiable {
    let id = UUID()
    let title: String
    let items: [MediaItem]
}

struct NewsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var movies: [MediaItem] = []
    @State private var tvs: [MediaItem] = []
    @State private var isLoading = true
    @State private var selectedMedia: MediaItem?
    @State private var selectedCollection: MediaCollection?
    @State private var showNotices = false

    var body: some View {
        ScrollView {
            if isLoading { LoadingState() }
            else {
                LazyVStack(alignment: .leading, spacing: 20) {
                    MediaCarousel(
                        title: "热门电影",
                        items: movies,
                        onSelect: { selectedMedia = $0 },
                        onShowAll: { selectedCollection = MediaCollection(title: "热门电影", items: movies) }
                    )
                    MediaCarousel(
                        title: "热门剧集",
                        items: tvs,
                        onSelect: { selectedMedia = $0 },
                        onShowAll: { selectedCollection = MediaCollection(title: "热门剧集", items: tvs) }
                    )
                    Button { showNotices = true } label: {
                        NewsLinkRow(title: "消息动态", subtitle: "查看站点公告、任务结果和系统提醒", icon: "antenna.radiowaves.left.and.right", color: HarvestTheme.green)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable { await load() }
        .navigationTitle("资讯").navigationBarTitleDisplayMode(.inline)
        .task { if isLoading { await load() } }
        .sheet(item: $selectedMedia) { item in MediaDetailSheet(item: item).environmentObject(appState) }
        .sheet(item: $selectedCollection) { collection in MediaCollectionSheet(collection: collection).environmentObject(appState) }
        .sheet(isPresented: $showNotices) { NoticeView().environmentObject(appState).presentationDetents([.medium, .large]) }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            async let movieRaw = appState.api(APIPath.tmdbPopularMovies)
            async let tvRaw = appState.api(APIPath.tmdbPopularTV)
            movies = jsonRows(try await movieRaw).map { MediaItem($0, source: "TMDB", mediaType: "movie") }
            tvs = jsonRows(try await tvRaw).map { MediaItem($0, source: "TMDB", mediaType: "tv") }
        } catch { appState.presentedError = error.localizedDescription }
    }
}

struct MediaCarousel: View {
    let title: String
    let items: [MediaItem]
    let onSelect: (MediaItem) -> Void
    let onShowAll: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, actionTitle: items.isEmpty ? nil : "查看全部", action: onShowAll)
            if items.isEmpty {
                Text("暂无内容").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 11) {
                        ForEach(items.prefix(12)) { item in
                            Button { onSelect(item) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    AsyncImage(url: URL(string: item.poster)) { phase in
                                        switch phase {
                                        case .success(let image): image.resizable().scaledToFill()
                                        default: Color.secondary.opacity(0.12).overlay(Image(systemName: "film").foregroundStyle(.secondary))
                                        }
                                    }
                                    .frame(width: 112, height: 156)
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                    Text(item.title).font(.caption.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
                                    if item.score > 0 { Text(String(format: "★ %.1f", item.score)).font(.caption2).foregroundStyle(HarvestTheme.amber) }
                                }
                                .frame(width: 112, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

private struct MediaCollectionSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let collection: MediaCollection
    @State private var selectedMedia: MediaItem?

    var body: some View {
        NavigationStack {
            List(collection.items) { item in
                Button { selectedMedia = item } label: { MediaRow(item: item) }.buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle(collection.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $selectedMedia) { item in MediaDetailSheet(item: item).environmentObject(appState) }
        }
    }
}

struct NewsLinkRow: View {
    let title: String; let subtitle: String; let icon: String; let color: Color
    var body: some View { HStack(spacing: 12) { Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 42, height: 42).background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 8)); VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }.cardSurface() }
}
