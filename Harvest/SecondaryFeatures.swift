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

    private var normalizedStatus: String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isWaiting: Bool {
        ["pending", "queued", "received"].contains(normalizedStatus)
    }

    var isRunning: Bool {
        ["started", "running", "progress", "retry"].contains(normalizedStatus)
    }

    var isActive: Bool { isWaiting || isRunning }

    var isSuccess: Bool {
        ["success", "succeeded", "done"].contains(normalizedStatus)
    }

    var isFailure: Bool {
        ["failure", "failed", "error", "revoked"].contains(normalizedStatus)
    }

    var isCompleted: Bool { isSuccess || isFailure }

    var statusLabel: String {
        switch normalizedStatus {
        case "success", "succeeded", "done": "成功"
        case "failure", "failed", "error": "失败"
        case "revoked": "已撤销"
        case "started", "running", "progress", "retry": "执行中"
        case "pending", "queued", "received": "等待中"
        default: status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未知" : status
        }
    }
}

@MainActor
final class TasksViewModel: ObservableObject {
    @Published var tasks: [TaskItem] = []
    @Published var results: [TaskResultItem] = []
    @Published var taskTypes: [String] = []
    @Published var crontabs: [[String: Any]] = []
    @Published var isLoading = true
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingEditorSupport = false
    @Published var mode = "计划"
    @Published private(set) var cachedAt: Date?
    @Published private(set) var usingCachedData = false
    private var restoredCache = false
    private let sessionCacheKey = "tasks.snapshot.v1"
    private let requestTimeout: TimeInterval = 20

    func load(_ appState: AppState) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isLoading = false
            isRefreshing = false
        }
        await restoreCacheIfNeeded(appState)
        isLoading = tasks.isEmpty && results.isEmpty

        async let taskResult = loadEndpoint(appState, path: APIPath.schedules, label: "计划任务")
        async let resultResult = loadEndpoint(appState, path: APIPath.taskResults, label: "执行结果")

        let loadedTasks = await taskResult
        if let taskValue = loadedTasks.value {
            tasks = jsonRows(taskValue).map(TaskItem.init)
            if tasks.isEmpty, let root = jsonPayloadDictionary(taskValue) { tasks = root.rows("tasks", "schedules").map(TaskItem.init) }
        }
        isLoading = false

        let loadedResults = await resultResult
        if let resultValue = loadedResults.value {
            results = jsonRows(resultValue).map(TaskResultItem.init)
        }

        let errors = [loadedTasks.errorMessage, loadedResults.errorMessage].compactMap { $0 }
        usingCachedData = !errors.isEmpty && (!tasks.isEmpty || !results.isEmpty)
        if errors.isEmpty {
            cachedAt = nil
        } else if usingCachedData {
            recordAppLog(.warning, "任务中心部分刷新失败，继续显示缓存：\(errors.joined(separator: "；"))")
        } else {
            appState.presentedError = errors.joined(separator: "\n")
        }
        if errors.isEmpty { await persistCache(appState) }
    }

    func loadEditorSupport(_ appState: AppState) async {
        guard !isLoadingEditorSupport else { return }
        guard taskTypes.isEmpty || crontabs.isEmpty else { return }
        isLoadingEditorSupport = true
        defer { isLoadingEditorSupport = false }

        async let typeResult = taskTypes.isEmpty
            ? loadEndpoint(appState, path: APIPath.taskTypes, label: "任务类型")
            : (value: Optional<Any>.none, errorMessage: Optional<String>.none)
        async let crontabResult = crontabs.isEmpty
            ? loadEndpoint(appState, path: APIPath.crontabs, label: "Cron 配置")
            : (value: Optional<Any>.none, errorMessage: Optional<String>.none)
        let values = await (typeResult, crontabResult)
        if let typeValue = values.0.value { taskTypes = jsonStrings(typeValue) }
        if let crontabValue = values.1.value { crontabs = jsonRows(crontabValue) }

        let errors = [values.0.errorMessage, values.1.errorMessage].compactMap { $0 }
        if !errors.isEmpty { appState.presentedError = errors.joined(separator: "\n") }
        if errors.isEmpty { await persistCache(appState) }
    }

    private func restoreCacheIfNeeded(_ appState: AppState) async {
        guard !restoredCache else { return }
        restoredCache = true
        guard let cached = await appState.readSessionCache(sessionCacheKey),
              let root = cached.value as? [String: Any] else { return }
        tasks = (root["tasks"] as? [[String: Any]] ?? []).map(TaskItem.init)
        results = (root["results"] as? [[String: Any]] ?? []).map(TaskResultItem.init)
        taskTypes = root["task_types"] as? [String] ?? []
        crontabs = root["crontabs"] as? [[String: Any]] ?? []
        guard !tasks.isEmpty || !results.isEmpty else { return }
        cachedAt = cached.cachedAt
        usingCachedData = true
        isLoading = false
    }

    private func persistCache(_ appState: AppState) async {
        let taskRows: [[String: Any]] = tasks.map { task in
            [
                "id": task.id,
                "name": task.name,
                "task": task.taskType,
                "description": task.description,
                "enable": task.enabled,
                "crontab_id": task.crontabID,
                "crontab": [
                    "minute": task.minute,
                    "hour": task.hour,
                    "day_of_month": task.dayOfMonth,
                    "month_of_year": task.monthOfYear,
                    "day_of_week": task.dayOfWeek,
                    "schedule": task.schedule
                ]
            ]
        }
        let resultRows: [[String: Any]] = results.map { result in
            [
                "id": result.id,
                "task_id": result.taskID,
                "name": result.name,
                "status": result.status,
                "created_at": result.createdAt,
                "updated_at": result.finishedAt
            ]
        }
        await appState.writeSessionCache(
            ["tasks": taskRows, "results": resultRows, "task_types": taskTypes, "crontabs": crontabs],
            name: sessionCacheKey
        )
    }

    private func loadEndpoint(
        _ appState: AppState,
        path: String,
        label: String
    ) async -> (value: Any?, errorMessage: String?) {
        do { return (try await appState.api(path, timeoutInterval: requestTimeout), nil) }
        catch { return (nil, "\(label)：\(error.localizedDescription)") }
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
        if await appState.perform("\(APIPath.schedules)/\(task.id)", method: .delete) {
            tasks.removeAll { $0.id == task.id }
            await persistCache(appState)
        }
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
        ) {
            results.removeAll { $0.id == result.id }
            await persistCache(appState)
        }
    }

    func clearResults(_ appState: AppState) async {
        if await appState.perform(APIPath.taskResults, method: .delete) {
            results = []
            await persistCache(appState)
        }
    }
}

struct TasksView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = TasksViewModel()
    @State private var showEditor = false
    @State private var editingTask: TaskItem?
    @State private var selectedResult: TaskResultItem?
    @State private var confirmClearResults = false
    @State private var deletingTask: TaskItem?
    @State private var deletingResult: TaskResultItem?

    var body: some View {
        Group {
            if model.isLoading { LoadingState() }
            else {
                List {
                    if model.usingCachedData {
                        SessionCacheBanner(cachedAt: model.cachedAt)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
                    Section { Picker("视图", selection: $model.mode) { Text("计划").tag("计划"); Text("执行记录").tag("执行记录") }.pickerStyle(.segmented).listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)) }
                    if model.mode == "计划" {
                        if model.tasks.isEmpty {
                            EmptyState(icon: "checklist", title: "没有计划任务", detail: "创建自动签到、站点更新或辅种任务", actionTitle: "新建任务") { openNewTaskEditor() }
                                .frame(minHeight: 320)
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(model.tasks) { task in
                                TaskRow(item: task) {
                                    Task { await model.run(appState, task: task) }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { openTaskEditor(task) }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button { Task { await model.toggle(appState, task: task) } } label: {
                                        Label(task.enabled ? "停用" : "启用", systemImage: task.enabled ? "pause" : "play")
                                    }
                                    .tint(HarvestTheme.amber)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button { openTaskEditor(task) } label: { Label("编辑", systemImage: "pencil") }.tint(HarvestTheme.blue)
                                    Button(role: .destructive) { deletingTask = task } label: { Label("删除", systemImage: "trash") }
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
                                        if result.isCompleted {
                                            Button(role: .destructive) { deletingResult = result } label: { Label("删除", systemImage: "trash") }
                                        }
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
                    if model.isLoadingEditorSupport {
                        ProgressView().controlSize(.small)
                    } else {
                        Button { openNewTaskEditor() } label: { Image(systemName: "plus") }.accessibilityLabel("新建任务")
                    }
                } else if !model.results.isEmpty {
                    Button(role: .destructive) { confirmClearResults = true } label: { Image(systemName: "trash") }.accessibilityLabel("清空执行记录")
                }
            }
        }
        .task { if model.isLoading { await model.load(appState) } }
        .onChange(of: appState.refreshGeneration) { _, _ in Task { await model.load(appState) } }
        .sheet(isPresented: $showEditor) { TaskEditorSheet(taskTypes: model.taskTypes, crontabs: model.crontabs) { await model.load(appState) }.environmentObject(appState) }
        .sheet(item: $editingTask) { task in TaskEditorSheet(task: task, taskTypes: model.taskTypes, crontabs: model.crontabs) { await model.load(appState) }.environmentObject(appState) }
        .sheet(item: $selectedResult) { result in
            TaskResultDetailSheet(
                result: result,
                onTerminate: { await model.terminate(appState, result: result) },
                onDelete: { await model.removeResult(appState, result: result) }
            )
            .environmentObject(appState)
        }
        .confirmationDialog("确定清空全部执行记录？", isPresented: $confirmClearResults, titleVisibility: .visible) {
            Button("清空执行记录", role: .destructive) { Task { await model.clearResults(appState) } }
        }
        .confirmationDialog(
            "确定删除任务「\(deletingTask?.name ?? "")」？",
            isPresented: Binding(get: { deletingTask != nil }, set: { if !$0 { deletingTask = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除任务", role: .destructive) {
                guard let task = deletingTask else { return }
                deletingTask = nil
                Task { await model.remove(appState, task: task) }
            }
            Button("取消", role: .cancel) { deletingTask = nil }
        }
        .confirmationDialog(
            "确定删除这条执行记录？",
            isPresented: Binding(get: { deletingResult != nil }, set: { if !$0 { deletingResult = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除记录", role: .destructive) {
                guard let result = deletingResult else { return }
                deletingResult = nil
                Task { await model.removeResult(appState, result: result) }
            }
            Button("取消", role: .cancel) { deletingResult = nil }
        }
    }

    private func openNewTaskEditor() {
        Task {
            await model.loadEditorSupport(appState)
            showEditor = true
        }
    }

    private func openTaskEditor(_ task: TaskItem) {
        Task {
            await model.loadEditorSupport(appState)
            editingTask = task
        }
    }
}

struct TaskRow: View {
    let item: TaskItem
    let run: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            SymbolBadge(
                icon: item.enabled ? "clock.badge.checkmark" : "pause.circle.fill",
                color: item.enabled ? HarvestTheme.green : .secondary,
                size: 44
            )
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
            Image(systemName: result.isRunning ? "clock.arrow.circlepath" : result.isWaiting ? "clock" : result.isSuccess ? "checkmark.circle.fill" : result.isFailure ? "exclamationmark.circle" : "questionmark.circle")
                .foregroundStyle(result.isRunning ? HarvestTheme.blue : result.isWaiting ? HarvestTheme.amber : result.isSuccess ? HarvestTheme.green : result.isFailure ? HarvestTheme.coral : Color.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(result.name).font(.subheadline.weight(.semibold))
                Text(result.statusLabel).font(.caption).foregroundStyle(.secondary)
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
    @State private var downloaders: [DownloaderItem] = []
    @State private var sourceDownloaderID: Int
    @State private var targetDownloaderID: Int
    @State private var folderMap: String
    @State private var skipChecking: Bool
    @State private var removeSourceTorrents: Bool
    @State private var loadingDownloaders = false

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
        let kwargsObject: [String: Any]
        if let data = (task?.kwargs ?? "{}").data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data),
           let value = decoded as? [String: Any] {
            kwargsObject = value
        } else {
            kwargsObject = [:]
        }
        _sourceDownloaderID = State(initialValue: kwargsObject.int("source_downloader_id") ?? 0)
        _targetDownloaderID = State(initialValue: kwargsObject.int("dist_downloader_id") ?? 0)
        let mappings = (kwargsObject["folder_map"] as? [Any])?.map { String(describing: $0) } ?? []
        _folderMap = State(initialValue: mappings.joined(separator: "\n"))
        _skipChecking = State(initialValue: kwargsObject.bool("skip_checking") ?? false)
        _removeSourceTorrents = State(initialValue: kwargsObject.bool("remove_source_torrents") ?? false)
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
                if isTorrentMoveTask {
                    Section("迁移下载器") {
                        if loadingDownloaders { ProgressView().frame(maxWidth: .infinity) }
                        Picker("源下载器", selection: $sourceDownloaderID) {
                            Text("请选择").tag(0)
                            ForEach(downloaders) { Text($0.name).tag($0.id) }
                        }
                        .onChange(of: sourceDownloaderID) { _, _ in
                            if !targetOptions.contains(where: { $0.id == targetDownloaderID }) { targetDownloaderID = targetOptions.first?.id ?? 0 }
                            Task { await fillFolderMap(updateSource: true, updateTarget: true) }
                        }
                        Picker("目标下载器", selection: $targetDownloaderID) {
                            Text("请选择").tag(0)
                            ForEach(targetOptions) { Text($0.name).tag($0.id) }
                        }
                        .onChange(of: targetDownloaderID) { _, _ in Task { await fillFolderMap(updateSource: false, updateTarget: true) } }
                        TextField("目录映射，每行 源目录->目标目录", text: $folderMap, axis: .vertical)
                            .lineLimit(3...8).textInputAutocapitalization(.never).font(.system(.caption, design: .monospaced))
                        Button { Task { await fillFolderMap(updateSource: true, updateTarget: true) } } label: { Label("读取下载器默认路径", systemImage: "folder.badge.gearshape") }
                        Toggle("跳过文件校验", isOn: $skipChecking)
                        Toggle("迁移后删除源种子", isOn: $removeSourceTorrents)
                    }
                } else {
                    Section("参数 JSON") {
                        TextField("位置参数，例如 []", text: $args, axis: .vertical).font(.system(.caption, design: .monospaced))
                        TextField("关键字参数，例如 {}", text: $kwargs, axis: .vertical).font(.system(.caption, design: .monospaced))
                    }
                }
                if let validationError { Section { Label(validationError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(HarvestTheme.coral) } }
            }
            .navigationTitle(task == nil ? "新建任务" : "编辑任务").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(name.isEmpty || type.isEmpty || minute.isEmpty || hour.isEmpty) } }
            .onAppear { if type.isEmpty { type = taskTypes.first ?? "" } }
            .task(id: type) { if isTorrentMoveTask { await loadDownloaders() } }
        }
    }

    private func save() async {
        var resolvedKwargs = kwargs
        if isTorrentMoveTask {
            guard sourceDownloaderID > 0, targetDownloaderID > 0, sourceDownloaderID != targetDownloaderID else {
                validationError = "请选择不同的源下载器和目标下载器"
                return
            }
            let mappings = folderMap.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            var object = decodedJSONObject(kwargs) ?? [:]
            object["source_downloader_id"] = sourceDownloaderID
            object["dist_downloader_id"] = targetDownloaderID
            object["folder_map"] = mappings
            object["remove_source_torrents"] = removeSourceTorrents
            object["skip_checking"] = skipChecking
            if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) {
                resolvedKwargs = text
            }
        }
        guard validJSON(args, expected: [Any].self), validJSON(resolvedKwargs, expected: [String: Any].self) else {
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
            "kwargs": resolvedKwargs,
            "enabled": enabled
        ]
        let method: HTTPMethod = task == nil ? .post : .put
        if await appState.perform(APIPath.schedules, method: method, body: body) {
            await onSaved()
            dismiss()
        }
    }

    private var isTorrentMoveTask: Bool {
        type == "种子迁移任务" || type.lowercased().contains("torrent move") || type.lowercased().contains("torrent_move")
    }

    private var targetOptions: [DownloaderItem] {
        guard let source = downloaders.first(where: { $0.id == sourceDownloaderID }) else { return downloaders.filter { $0.id != sourceDownloaderID } }
        return downloaders.filter { $0.id != source.id && $0.host == source.host }
    }

    @MainActor private func loadDownloaders() async {
        guard downloaders.isEmpty else { return }
        loadingDownloaders = true
        defer { loadingDownloaders = false }
        do {
            downloaders = jsonRows(try await appState.api(APIPath.downloaders))
                .map { DownloaderItem($0) }
                .filter { $0.enabled }
            if sourceDownloaderID == 0 { sourceDownloaderID = downloaders.first?.id ?? 0 }
            if targetDownloaderID == 0 { targetDownloaderID = targetOptions.first?.id ?? 0 }
            await fillFolderMap(updateSource: true, updateTarget: true, onlyWhenEmpty: true)
        } catch { appState.presentedError = error.localizedDescription }
    }

    @MainActor private func fillFolderMap(
        updateSource: Bool,
        updateTarget: Bool,
        onlyWhenEmpty: Bool = false
    ) async {
        guard !onlyWhenEmpty || folderMap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let source = downloaders.first(where: { $0.id == sourceDownloaderID })
        let target = downloaders.first(where: { $0.id == targetDownloaderID })
        guard source != nil || target != nil else { return }

        var resolvedSource = ""
        var resolvedTarget = ""
        if updateSource, let source { resolvedSource = await downloaderDefaultPath(source) }
        if updateTarget, let target { resolvedTarget = await downloaderDefaultPath(target) }

        var lines = folderMap.components(separatedBy: .newlines)
        if lines.isEmpty { lines = [""] }
        let first = lines[0]
        let parts = first.components(separatedBy: "->")
        let currentSource = parts.first ?? ""
        let currentTarget = parts.count > 1 ? parts.dropFirst().joined(separator: "->") : ""
        let nextSource = updateSource ? resolvedSource : currentSource
        let nextTarget = updateTarget ? resolvedTarget : currentTarget
        lines[0] = "\(nextSource)->\(nextTarget)"
        folderMap = lines.joined(separator: "\n")
    }

    @MainActor private func downloaderDefaultPath(_ downloader: DownloaderItem) async -> String {
        if let value = nestedDownloadPath(downloader.raw), !value.isEmpty { return value }
        do {
            let raw = try await appState.api(APIPath.downloaderPreferences + "\(downloader.id)", query: ["with_status": true])
            return nestedDownloadPath(jsonPayloadDictionary(raw) ?? [:]) ?? ""
        } catch { return "" }
    }

    private func nestedDownloadPath(_ dictionary: [String: Any]) -> String? {
        if let value = dictionary.string("save_path", "savePath", "download-dir", "download_dir", "downloadDir"), !value.isEmpty { return value }
        for key in ["preferences", "prefs", "data", "status"] {
            if let nested = dictionary[key] as? [String: Any], let value = nestedDownloadPath(nested), !value.isEmpty { return value }
        }
        return nil
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

    private func decodedJSONObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data),
              let value = decoded as? [String: Any] else { return nil }
        return value
    }
}

struct TaskResultDetailSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let result: TaskResultItem
    let onTerminate: () async -> Void
    let onDelete: () async -> Void
    @State private var confirmDelete = false
    @State private var loadedResult: TaskResultItem?
    @State private var isLoading = true

    private var current: TaskResultItem { loadedResult ?? result }

    var body: some View {
        NavigationStack {
            List {
                Section("执行状态") {
                    LabeledContent("任务", value: current.name)
                    LabeledContent("状态", value: current.statusLabel)
                    LabeledContent("任务 ID", value: current.taskID)
                    if !current.createdAt.isEmpty { LabeledContent("开始", value: current.createdAt) }
                    if !current.finishedAt.isEmpty { LabeledContent("结束", value: current.finishedAt) }
                    if isLoading { ProgressView().frame(maxWidth: .infinity) }
                }
                if !current.summary.isEmpty {
                    Section("结果") { Text(markdownAttributedString(current.summary)).font(.callout).textSelection(.enabled) }
                }
                Section("原始记录") { Text(prettyJSON(current.raw)).font(.caption.monospaced()).textSelection(.enabled) }
                Section {
                    if current.isActive {
                        Button { Task { await onTerminate(); dismiss() } } label: { Label("终止任务", systemImage: "stop.fill") }.tint(HarvestTheme.amber)
                    }
                    if current.isCompleted {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("删除记录", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("执行详情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await loadDetail() }
            .confirmationDialog("确定删除这条执行记录？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除记录", role: .destructive) { Task { await onDelete(); dismiss() } }
            }
        }
    }

    @MainActor private func loadDetail() async {
        defer { isLoading = false }
        guard !result.taskID.isEmpty else { return }
        do {
            let raw = try await appState.api(APIPath.taskResults + urlPathSegment(result.taskID))
            guard let value = jsonPayloadDictionary(raw) ?? jsonDictionary(raw) else { return }
            var merged = result.raw
            for (key, item) in value { merged[key] = item }
            loadedResult = TaskResultItem(merged)
        } catch {
            // The list response remains a usable fallback, matching the Flutter detail flow.
        }
    }
}

private func isDoubanSource(_ source: String) -> Bool {
    let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.contains("豆瓣") || normalized.contains("douban")
}

private func mediaStringValue(_ value: Any?, depth: Int = 0) -> String? {
    guard depth < 4 else { return nil }
    if let value = value as? String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
    if let value = value as? NSNumber {
        return value.stringValue
    }
    if let dictionary = value as? [String: Any] {
        for key in ["url", "src", "href", "large", "normal", "medium", "small", "value"] {
            if let result = mediaStringValue(dictionary[key], depth: depth + 1) { return result }
        }
    }
    if let values = value as? [Any] {
        for item in values {
            if let result = mediaStringValue(item, depth: depth + 1) { return result }
        }
    }
    return nil
}

private func mediaImageValue(_ content: [String: Any]) -> String {
    let keys = [
        "poster_path", "profile_path", "poster_url", "posterUrl", "poster",
        "cover_url", "coverUrl", "cover", "pic", "image_url", "imageUrl",
        "image", "images", "img", "thumbnail", "thumb", "icon", "grey_icon", "logo",
        "large", "medium"
    ]
    for key in keys {
        if let value = mediaStringValue(content[key]) { return value }
    }
    return ""
}

private func isNumericMediaID(_ value: String) -> Bool {
    !value.isEmpty && value.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
}

private func doubanSubjectID(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if isNumericMediaID(trimmed) { return trimmed }

    let tokens = trimmed.split { character in
        !(character.isLetter || character.isNumber)
    }.map(String.init)
    if let subjectIndex = tokens.firstIndex(where: { $0.caseInsensitiveCompare("subject") == .orderedSame }),
       tokens.index(after: subjectIndex) < tokens.endIndex {
        let candidate = tokens[tokens.index(after: subjectIndex)]
        if isNumericMediaID(candidate) { return candidate }
    }
    if let idIndex = tokens.firstIndex(where: {
        ["id", "subjectid", "subject_id", "doubanid", "douban_id"].contains($0.lowercased())
    }), tokens.index(after: idIndex) < tokens.endIndex {
        let candidate = tokens[tokens.index(after: idIndex)]
        if isNumericMediaID(candidate) { return candidate }
    }
    return tokens.reversed().first(where: { isNumericMediaID($0) && $0.count >= 3 })
}

private func mediaRows(_ value: Any, depth: Int = 0) -> [[String: Any]] {
    guard depth < 6 else { return [] }
    if let rows = value as? [[String: Any]], !rows.isEmpty { return rows }
    if let values = value as? [Any] {
        let rows = values.compactMap { $0 as? [String: Any] }
        if !rows.isEmpty { return rows }
    }
    guard let dictionary = value as? [String: Any] else { return [] }
    for key in [
        "data", "results", "items", "list", "rows", "records", "subjects",
        "movies", "tv", "tv_shows", "targets", "hot", "entries"
    ] {
        if let nested = dictionary[key] {
            let rows = mediaRows(nested, depth: depth + 1)
            if !rows.isEmpty { return rows }
        }
    }
    if dictionary.dict("target") != nil || dictionary.string(
        "title", "name", "id", "target_id", "subject_id", "douban_url", "doubanUrl", "url",
        "poster", "cover", "cover_url", "poster_url"
    ) != nil {
        return [dictionary]
    }
    let rows = jsonRows(value)
    if !rows.isEmpty { return rows }
    return []
}

private func mediaPayloadDictionary(_ value: Any, depth: Int = 0) -> [String: Any]? {
    guard depth < 6, let dictionary = value as? [String: Any] else { return nil }
    let hasMediaFields = dictionary.string("title", "name", "id", "subject_id") != nil || !mediaImageValue(dictionary).isEmpty
    if hasMediaFields {
        return dictionary
    }
    for key in ["data", "result", "subject", "target", "movie"] {
        if let nested = dictionary[key],
           let payload = mediaPayloadDictionary(nested, depth: depth + 1) {
            return payload
        }
    }
    return dictionary
}

private func mediaCookie(_ raw: [String: Any]) -> String? {
    let content = raw.dict("target") ?? raw
    return mediaStringValue(content["cookie"])
        ?? mediaStringValue(content["cookies"])
        ?? mediaStringValue(content["douban_cookie"])
        ?? mediaStringValue(raw["cookie"])
        ?? mediaStringValue(raw["cookies"])
        ?? mediaStringValue(raw["douban_cookie"])
}

private func mediaImageHeaders(source: String, raw: [String: Any] = [:]) -> [String: String] {
    var headers: [String: String] = [:]
    if isDoubanSource(source) {
        headers["Referer"] = doubanImageReferer
        headers["User-Agent"] = doubanImageUserAgent
        if let cookie = mediaCookie(raw), !cookie.isEmpty {
            headers["Cookie"] = cookie
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
        }
    }
    return headers
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
        let rawRemoteID = content.string(
            "id", "subject_id", "subjectId", "douban_id", "doubanId", "tmdb_id",
            "douban_url", "doubanUrl", "subject_url", "subjectUrl", "url", "uri"
        ) ?? json.string(
            "target_id", "targetId", "subject_id", "subjectId",
            "douban_url", "doubanUrl", "subject_url", "subjectUrl", "url", "uri", "hash"
        )
        let normalizedRemoteID = isDoubanSource(source)
            ? rawRemoteID.flatMap(doubanSubjectID)
            : rawRemoteID
        remoteID = normalizedRemoteID ?? rawRemoteID ?? UUID().uuidString
        let resolvedType = mediaType.isEmpty ? (json.string("media_type", "target_type", "targetType") ?? content.string("media_type") ?? "") : mediaType
        id = "\(source):\(resolvedType):\(remoteID)"
        title = content.string("title", "name", "original_title")
            ?? json.string("title", "name", "original_title")
            ?? "未命名"
        subtitle = content.string("original_title", "original_name", "card_subtitle")
            ?? mediaStringValue(content["subtitle"])
            ?? json.string("original_title", "original_name", "card_subtitle")
            ?? mediaStringValue(json["subtitle"])
            ?? ""
        overview = content.string("overview", "abstract", "summary", "intro", "quote", "episodes_info")
            ?? json.string("overview", "abstract", "summary", "intro", "quote", "episodes_info")
            ?? ""
        let imageValue = mediaImageValue(content)
        poster = mediaPosterURL(imageValue.isEmpty ? mediaImageValue(json) : imageValue, source: source)
        score = content.double("vote_average", "score", "rate", "rating_num", "rating")
            ?? json.double("vote_average", "score", "rate", "rating_num", "rating")
            ?? content.dict("rating")?.double("value", "star_count")
            ?? json.dict("rating")?.double("value", "star_count")
            ?? 0
        year = (content.string("release_date", "first_air_date", "year")
            ?? json.string("release_date", "first_air_date", "year"))?.prefix(4).description ?? ""
        self.source = source
        self.mediaType = resolvedType
        raw = json
    }
}

private func mediaPosterURL(_ value: String, source: String) -> String {
    var normalized = normalizedRemoteImageURL(value)
    guard !normalized.isEmpty else { return "" }
    if source == "TMDB", normalized.hasPrefix("/") {
        normalized = "https://image.tmdb.org/t/p/w500\(normalized)"
    }
    if isDoubanSource(source), normalized.hasPrefix("/") {
        normalized = "https://movie.douban.com\(normalized)"
    }
    return normalized
}

enum ResourceSearchSortField: String, CaseIterable, Identifiable {
    case title = "标题"
    case subtitle = "副标题"
    case size = "大小"
    case seeders = "做种"
    case published = "发布时间"

    var id: String { rawValue }
    var defaultAscending: Bool { self == .title || self == .subtitle }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var mode = "影视"
    @Published var media: [MediaItem] = []
    @Published var resources: [[String: Any]] = []
    @Published var isLoading = false
    @Published var statusMessage = ""
    @Published var sites: [SiteItem] = []
    @Published var history: [String]
    @Published var maxCount: Int
    @Published var sitesEnabled: Bool
    @Published var selectedSiteIDs: Set<Int>
    @Published var resourceSortField: ResourceSearchSortField = .seeders
    @Published var resourceSortAscending = false
    @Published var resourceFilterSites: Set<String> = []
    @Published var resourceFilterSales: Set<String> = []
    @Published var resourceFilterCategories: Set<String> = []
    @Published var resourceFilterResolutions: Set<String> = []
    @Published var resourceFilterTags: Set<String> = []
    @Published var resourceFilterSeasons: Set<String> = []
    @Published var resourceFilterEpisodes: Set<String> = []
    @Published var resourceFilterExcludeHR = false
    @Published var resourceFilterSizeEnabled = false
    @Published var resourceFilterMinSizeGB = 0.0
    @Published var resourceFilterMaxSizeGB = 100.0
    private var searchGeneration = 0

    init() {
        let defaults = UserDefaults.standard
        history = defaults.stringArray(forKey: "search.history") ?? []
        maxCount = defaults.object(forKey: "search.maxCount") == nil ? 5 : defaults.integer(forKey: "search.maxCount")
        sitesEnabled = defaults.object(forKey: "search.sitesEnabled") == nil ? true : defaults.bool(forKey: "search.sitesEnabled")
        selectedSiteIDs = Set((defaults.stringArray(forKey: "search.siteIDs") ?? []).compactMap(Int.init))
    }

    var displayedResources: [[String: Any]] {
        resources.filter(matchesResourceFilters).sorted(by: resourceComesBefore)
    }

    var resourceSites: [String] {
        uniqueResourceValues { resourceSiteValue($0) }
    }

    var resourceSales: [String] {
        uniqueResourceValues { resourceSaleValue($0) }
    }

    var resourceCategories: [String] {
        uniqueResourceValues { resourceCategory($0) }
    }

    var resourceResolutions: [String] {
        let available = Set(resources.flatMap(resourceResolutionValues))
        return ["720P", "1080P", "2160P", "4K", "8K"].filter(available.contains)
    }

    var resourceTags: [String] {
        Array(Set(resources.flatMap(resourceTagValues))).sorted()
    }

    var resourceSeasons: [String] {
        Array(Set(resources.flatMap(resourceSeasonValues))).sorted(by: numberedLabelComesBefore)
    }

    var resourceEpisodes: [String] {
        Array(Set(resources.flatMap(resourceEpisodeValues))).sorted(by: numberedLabelComesBefore)
    }

    var resourceFilterCount: Int {
        resourceFilterSites.count
            + resourceFilterSales.count
            + resourceFilterCategories.count
            + resourceFilterResolutions.count
            + resourceFilterTags.count
            + resourceFilterSeasons.count
            + resourceFilterEpisodes.count
            + (resourceFilterExcludeHR ? 1 : 0)
            + (resourceFilterSizeEnabled ? 1 : 0)
    }

    func search(_ appState: AppState) async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        searchGeneration &+= 1
        let generation = searchGeneration
        let searchMode = mode
        addHistory(term)
        statusMessage = searchMode == "资源" ? "开始搜索「\(term)」" : "正在搜索影视信息"
        isLoading = true
        if searchMode == "影视" {
            media = []
        } else {
            resources = []
            resetResourceFilters()
        }
        defer {
            if searchGeneration == generation { isLoading = false }
        }
        do {
            if searchMode == "影视" {
                async let tmdbResult = fetchMedia(
                    appState,
                    path: "\(APIPath.tmdbSearch)/\(urlPathSegment(term))",
                    source: "TMDB"
                )
                async let doubanResult = fetchMedia(
                    appState,
                    path: APIPath.doubanSearch,
                    source: "豆瓣",
                    query: ["q": term]
                )
                let (tmdb, douban) = await (tmdbResult, doubanResult)
                guard searchGeneration == generation else { return }
                media = uniqueMediaItems(tmdb.items + douban.items)
                statusMessage = "找到 \(media.count) 条影视信息"
                if tmdb.errorMessage != nil, douban.errorMessage != nil {
                    appState.presentedError = [tmdb.errorMessage, douban.errorMessage]
                        .compactMap { $0 }
                        .joined(separator: "\n")
                } else if douban.errorMessage != nil {
                    statusMessage += " · 豆瓣搜索暂不可用"
                } else if tmdb.errorMessage != nil {
                    statusMessage += " · TMDB 搜索暂不可用"
                }
            } else {
                for try await event in APIClient.shared.streamSSE(
                    baseURL: appState.baseURL,
                    path: APIPath.siteSearch,
                    token: appState.accessToken,
                    body: [
                        "key": term,
                        "max_count": maxCount,
                        "sites": sitesEnabled ? selectedSiteIDs.sorted().map { String($0) } : []
                    ]
                ) {
                    guard searchGeneration == generation else { return }
                    if let message = jsonMessage(event), !message.isEmpty {
                        statusMessage = message
                    }
                    guard (event.bool("succeed") ?? (event.int("code") == 0)) else {
                        if let message = jsonMessage(event), !message.isEmpty { appState.presentedError = message }
                        continue
                    }
                    if let data = event["data"] {
                        let rows = jsonRows(data)
                        if rows.isEmpty, let row = jsonDictionary(data) { appendResourceRows([row]) }
                        else { appendResourceRows(rows) }
                    }
                }
            }
        } catch is CancellationError {
            return
        } catch {
            if searchGeneration == generation { appState.presentedError = error.localizedDescription }
        }
    }

    func cancelSearch(clearResults: Bool = false) {
        let wasLoading = isLoading
        searchGeneration &+= 1
        isLoading = false
        if clearResults {
            media = []
            resources = []
            statusMessage = ""
            resetResourceFilters()
        } else if wasLoading {
            statusMessage = "搜索已停止"
        }
    }

    private func fetchMedia(
        _ appState: AppState,
        path: String,
        source: String,
        query: [String: Any] = [:]
    ) async -> (items: [MediaItem], errorMessage: String?) {
        do {
            let raw = try await appState.api(path, query: query)
            let rows = mediaRows(raw)
            if rows.isEmpty {
                await AppLogStore.shared.append(.warning, "\(source) 返回空或未知的数据结构")
            } else {
                await AppLogStore.shared.append(.info, "\(source) 解析到 \(rows.count) 条影视数据")
            }
            return (rows.map { MediaItem($0, source: source) }, nil)
        } catch {
            await AppLogStore.shared.append(.error, "\(source) 影视接口失败：\(error.localizedDescription)")
            return ([], "\(source)：\(error.localizedDescription)")
        }
    }

    func loadSites(_ appState: AppState) async {
        do {
            sites = jsonRows(try await appState.api(APIPath.sites))
                .map(SiteItem.init)
                .filter { $0.enabled && $0.searchTorrents }
                .sorted {
                    if $0.sortID != $1.sortID { return $0.sortID < $1.sortID }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            let available = Set(sites.map(\.id))
            selectedSiteIDs = selectedSiteIDs.intersection(available)
        } catch {
            sites = []
        }
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(maxCount, forKey: "search.maxCount")
        defaults.set(sitesEnabled, forKey: "search.sitesEnabled")
        defaults.set(selectedSiteIDs.sorted().map { String($0) }, forKey: "search.siteIDs")
    }

    func resetLocalSettings() {
        query = ""
        mode = "影视"
        history = []
        maxCount = 5
        sitesEnabled = true
        selectedSiteIDs = []
        resourceSortField = .seeders
        resourceSortAscending = false
        resetResourceFilters()
    }

    func addHistory(_ keyword: String) {
        let value = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        history.removeAll { $0 == value }
        history.insert(value, at: 0)
        if history.count > 20 { history = Array(history.prefix(20)) }
        UserDefaults.standard.set(history, forKey: "search.history")
    }

    func removeHistory(_ keyword: String) {
        history.removeAll { $0 == keyword }
        UserDefaults.standard.set(history, forKey: "search.history")
    }

    func clearHistory() {
        history = []
        UserDefaults.standard.set(history, forKey: "search.history")
    }

    func selectResourceSort(_ field: ResourceSearchSortField) {
        if resourceSortField == field {
            resourceSortAscending.toggle()
        } else {
            resourceSortField = field
            resourceSortAscending = field.defaultAscending
        }
    }

    func resetResourceFilters() {
        resourceFilterSites = []
        resourceFilterSales = []
        resourceFilterCategories = []
        resourceFilterResolutions = []
        resourceFilterTags = []
        resourceFilterSeasons = []
        resourceFilterEpisodes = []
        resourceFilterExcludeHR = false
        resourceFilterSizeEnabled = false
        resourceFilterMinSizeGB = 0
        resourceFilterMaxSizeGB = 100
    }

    func siteLabel(_ value: String) -> String {
        sites.first {
            String($0.id) == value || $0.siteKey == value || $0.name == value
        }?.name ?? value
    }

    func resourceSiteValue(_ item: [String: Any]) -> String {
        item.string("site_id", "siteId", "site", "site_name", "siteName") ?? ""
    }

    func resourceTitle(_ item: [String: Any]) -> String {
        item.string("title", "name") ?? ""
    }

    func resourceSubtitle(_ item: [String: Any]) -> String {
        item.string("subtitle", "sub_title", "description") ?? ""
    }

    func resourceSaleValue(_ item: [String: Any]) -> String {
        let value = item.string("sale_status", "saleStatus", "promotion", "discount")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "无优惠" : value
    }

    func resourceCategory(_ item: [String: Any]) -> String {
        item.string("category", "category_name", "categoryName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func resourceTagValues(_ item: [String: Any]) -> [String] {
        let direct = item.strings("tags")
        if !direct.isEmpty {
            return direct.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        guard let text = item.string("tags"), !text.isEmpty else { return [] }
        return text.components(separatedBy: CharacterSet(charactersIn: ",，#"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func resourceIsHRSafe(_ item: [String: Any]) -> Bool {
        item.bool("hr") ?? false
    }

    func resourceSeeders(_ item: [String: Any]) -> Int {
        item.int("seeders", "seed", "seeder") ?? Int(item.string("seeders", "seed", "seeder") ?? "") ?? 0
    }

    func resourceLeechers(_ item: [String: Any]) -> Int {
        item.int("leechers", "leecher", "leech") ?? Int(item.string("leechers", "leecher", "leech") ?? "") ?? 0
    }

    func resourceCompleters(_ item: [String: Any]) -> Int {
        item.int("completers", "completed", "snatched") ?? Int(item.string("completers", "completed", "snatched") ?? "") ?? 0
    }

    func resourceSize(_ item: [String: Any]) -> Double {
        if let value = item.double("size", "length", "size_bytes", "sizeBytes") { return value }
        let text = item.string("size", "length")?.uppercased() ?? ""
        let number = Double(text.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).joined()) ?? 0
        if text.contains("T") { return number * 1_099_511_627_776 }
        if text.contains("G") { return number * 1_073_741_824 }
        if text.contains("M") { return number * 1_048_576 }
        if text.contains("K") { return number * 1024 }
        return number
    }

    func resourcePublished(_ item: [String: Any]) -> String {
        item.string("published", "pubdate", "created_at", "date") ?? ""
    }

    func resourceResolutionValues(_ item: [String: Any]) -> [String] {
        let text = "\(resourceTitle(item)) \(resourceSubtitle(item))".uppercased()
        return ["720P", "1080P", "2160P", "4K", "8K"].filter(text.contains)
    }

    func resourceSeasonValues(_ item: [String: Any]) -> [String] {
        let text = "\(resourceTitle(item)) \(resourceSubtitle(item))".uppercased()
        return Set(regexCaptureValues(#"(^|[^A-Z0-9])S(\d{1,2})(?=[^0-9]|$)"#, text: text, group: 2).compactMap {
            guard let number = Int($0), number >= 0 else { return nil }
            return String(format: "S%02d", number)
        }).sorted(by: numberedLabelComesBefore)
    }

    func resourceEpisodeValues(_ item: [String: Any]) -> [String] {
        let text = "\(resourceTitle(item)) \(resourceSubtitle(item))".uppercased()
        var values = Set<String>()
        let rangePattern = #"(^|[^A-Z0-9])(?:S\d{1,2})?E(?:P)?(\d{1,3})\s*[-~－–—]\s*(?:(?:S\d{1,2})?E(?:P)?)?(\d{1,3}|\*\*)(?=[^A-Z0-9]|$)"#
        for captures in regexCaptureRows(rangePattern, text: text, groups: [2, 3]) {
            guard captures.count == 2, let start = Int(captures[0]), start > 0 else { continue }
            guard let end = Int(captures[1]), end >= start, end - start <= 80 else {
                values.insert(String(format: "E%02d", start))
                continue
            }
            for number in start...end { values.insert(String(format: "E%02d", number)) }
        }
        let singlePattern = #"(^|[^A-Z0-9])(?:S\d{1,2})?E(?:P)?(\d{1,3})(?=[^0-9]|$)"#
        for raw in regexCaptureValues(singlePattern, text: text, group: 2) {
            if let number = Int(raw), number > 0 { values.insert(String(format: "E%02d", number)) }
        }
        return values.sorted(by: numberedLabelComesBefore)
    }

    private func matchesResourceFilters(_ item: [String: Any]) -> Bool {
        if !resourceFilterSites.isEmpty && !resourceFilterSites.contains(resourceSiteValue(item)) { return false }
        if !resourceFilterSales.isEmpty && !resourceFilterSales.contains(resourceSaleValue(item)) { return false }
        if !resourceFilterCategories.isEmpty && !resourceFilterCategories.contains(resourceCategory(item)) { return false }
        if !resourceFilterResolutions.isEmpty && Set(resourceResolutionValues(item)).isDisjoint(with: resourceFilterResolutions) { return false }
        if !resourceFilterTags.isEmpty && Set(resourceTagValues(item)).isDisjoint(with: resourceFilterTags) { return false }
        if !resourceFilterSeasons.isEmpty && Set(resourceSeasonValues(item)).isDisjoint(with: resourceFilterSeasons) { return false }
        if !resourceFilterEpisodes.isEmpty && Set(resourceEpisodeValues(item)).isDisjoint(with: resourceFilterEpisodes) { return false }
        if resourceFilterExcludeHR && !resourceIsHRSafe(item) { return false }
        if resourceFilterSizeEnabled {
            let bytes = resourceSize(item)
            guard bytes > 0 else { return false }
            let gigabytes = bytes / 1_073_741_824
            if gigabytes < resourceFilterMinSizeGB || gigabytes > resourceFilterMaxSizeGB { return false }
        }
        return true
    }

    private func resourceComesBefore(_ left: [String: Any], _ right: [String: Any]) -> Bool {
        let primary: Int
        switch resourceSortField {
        case .title: primary = compareText(resourceTitle(left), resourceTitle(right))
        case .subtitle: primary = compareText(resourceSubtitle(left), resourceSubtitle(right))
        case .size: primary = compareNumber(resourceSize(left), resourceSize(right))
        case .seeders: primary = compareNumber(Double(resourceSeeders(left)), Double(resourceSeeders(right)))
        case .published: primary = comparePublished(resourcePublished(left), resourcePublished(right))
        }
        if primary != 0 { return primary < 0 }
        let published = comparePublished(resourcePublished(left), resourcePublished(right))
        if published != 0 { return published < 0 }
        return compareText(resourceTitle(left), resourceTitle(right)) < 0
    }

    private func compareText(_ left: String, _ right: String) -> Int {
        let lhs = left.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rhs = right.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lhs.isEmpty != rhs.isEmpty { return lhs.isEmpty ? 1 : -1 }
        let comparison = lhs.localizedCompare(rhs)
        let result = comparison == .orderedAscending ? -1 : (comparison == .orderedDescending ? 1 : 0)
        return resourceSortAscending ? result : -result
    }

    private func compareNumber(_ left: Double, _ right: Double) -> Int {
        if (left == 0) != (right == 0) { return left == 0 ? 1 : -1 }
        let result = left == right ? 0 : (left < right ? -1 : 1)
        return resourceSortAscending ? result : -result
    }

    private func comparePublished(_ left: String, _ right: String) -> Int {
        let lhs = resourceDateValue(left)
        let rhs = resourceDateValue(right)
        if (lhs == nil) != (rhs == nil) { return lhs == nil ? 1 : -1 }
        guard let lhs, let rhs else { return 0 }
        let result = lhs == rhs ? 0 : (lhs < rhs ? -1 : 1)
        return resourceSortAscending ? result : -result
    }

    private func resourceDateValue(_ value: String) -> TimeInterval? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Double(text) {
            return number > 10_000_000_000 ? number / 1000 : number
        }
        return parseDate(text)?.timeIntervalSince1970
    }

    private func uniqueResourceValues(_ pick: ([String: Any]) -> String) -> [String] {
        Array(Set(resources.map(pick).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    private func uniqueMediaItems(_ items: [MediaItem]) -> [MediaItem] {
        var identifiers = Set<String>()
        return items.filter { identifiers.insert($0.id).inserted }
    }

    private func appendResourceRows(_ rows: [[String: Any]]) {
        var identifiers = Set(resources.map(resourceIdentifier))
        for row in rows {
            if identifiers.insert(resourceIdentifier(row)).inserted {
                resources.append(row)
            }
        }
    }

    private func resourceIdentifier(_ item: [String: Any]) -> String {
        let parts = [
            resourceSiteValue(item),
            item.string("id", "torrent_id", "torrentId", "tid", "hash", "info_hash", "infoHash") ?? "",
            item.string("download_url", "downloadUrl", "details_url", "detail_url", "url", "link") ?? "",
            resourceTitle(item),
            resourceSubtitle(item),
            item.string("size", "length", "size_bytes", "sizeBytes") ?? "",
            resourcePublished(item)
        ]
        let identifier = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "|")
        if identifier.replacingOccurrences(of: "|", with: "").isEmpty,
           JSONSerialization.isValidJSONObject(item),
           let data = try? JSONSerialization.data(withJSONObject: item, options: [.sortedKeys]),
           let fallback = String(data: data, encoding: .utf8) {
            return fallback
        }
        return identifier
    }

    private func numberedLabelComesBefore(_ left: String, _ right: String) -> Bool {
        let lhs = Int(left.filter(\.isNumber)) ?? 0
        let rhs = Int(right.filter(\.isNumber)) ?? 0
        return lhs == rhs ? left < right : lhs < rhs
    }

    private func regexCaptureValues(_ pattern: String, text: String, group: Int) -> [String] {
        regexCaptureRows(pattern, text: text, groups: [group]).compactMap(\.first)
    }

    private func regexCaptureRows(_ pattern: String, text: String, groups: [Int]) -> [[String]] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).map { match in
            groups.map { group in
                guard match.numberOfRanges > group,
                      let captureRange = Range(match.range(at: group), in: text) else { return "" }
                return String(text[captureRange])
            }
        }
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
    @State private var showSettings = false
    @State private var activeSearchTask: Task<Void, Never>?
    @FocusState private var searchFieldFocused: Bool
    let onClose: () -> Void
    let onVisibilityChanged: (Bool) -> Void

    init(
        onClose: @escaping () -> Void = {},
        onVisibilityChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.onClose = onClose
        self.onVisibilityChanged = onVisibilityChanged
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    stopSearch()
                    onClose()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 38, height: 44)
                }
                .accessibilityLabel("返回")

                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(searchPlaceholder, text: $model.query)
                        .focused($searchFieldFocused)
                        .submitLabel(.search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { startSearch() }
                    if !model.query.isEmpty {
                        Button {
                            model.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清空搜索")
                    }
                    if model.isLoading {
                        Button { stopSearch() } label: {
                            Image(systemName: "stop.circle")
                                .foregroundStyle(HarvestTheme.coral)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("停止搜索")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.10)))

                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 21, weight: .medium))
                        .frame(width: 38, height: 44)
                }
                .accessibilityLabel("搜索设置")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)

            HStack(spacing: 8) {
                ForEach(["影视", "资源"], id: \.self) { mode in
                    Button {
                        guard model.mode != mode else { return }
                        stopSearch()
                        model.mode = mode
                    } label: {
                        Text(mode)
                            .font(.system(size: 16, weight: model.mode == mode ? .semibold : .regular))
                            .foregroundStyle(model.mode == mode ? Color.white : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                model.mode == mode ? HarvestTheme.blue : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            Divider().opacity(0.45)

            if model.isLoading && currentResultsAreEmpty {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large).tint(HarvestTheme.blue)
                    Text(model.statusMessage.isEmpty ? "正在搜索" : model.statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if currentResultsAreEmpty {
                VStack(spacing: 18) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 64, weight: .ultraLight))
                        .foregroundStyle(Color.secondary.opacity(0.22))
                    Text(emptyMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if model.mode == "影视" {
                        ForEach(model.media) { item in
                            Button { selectedMedia = item } label: { MediaRow(item: item) }
                                .buttonStyle(.plain)
                        }
                    } else {
                        ForEach(Array(model.displayedResources.enumerated()), id: \.offset) { _, item in
                            Button { selectedResource = ResourceSelection(value: item) } label: {
                                ResourceRowItem(item: item, siteLabel: model.siteLabel(model.resourceSiteValue(item)))
                            }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedMedia) { item in MediaDetailSheet(item: item).environmentObject(appState) }
        .sheet(item: $selectedResource) { selection in ResourcePushSheet(item: selection.value).environmentObject(appState) }
        .sheet(isPresented: $showSettings) {
            SearchSettingsSheet(model: model) {
                await model.loadSites(appState)
            }
            .presentationDetents([.large])
        }
        .task { await model.loadSites(appState); consumePendingResourceSearch() }
        .onChange(of: appState.pendingResourceSearch) { _, _ in consumePendingResourceSearch() }
        .onChange(of: model.query) { _, value in
            if value.isEmpty { stopSearch(clearResults: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .harvestLocalUIReset)) { _ in
            stopSearch(clearResults: true)
            model.resetLocalSettings()
        }
        .onAppear { onVisibilityChanged(true) }
        .onDisappear {
            onVisibilityChanged(false)
            stopSearch()
        }
    }

    private var searchPlaceholder: String {
        model.mode == "影视" ? "搜索电影、剧集..." : "搜索种子资源..."
    }

    private var currentResultsAreEmpty: Bool {
        model.mode == "影视" ? model.media.isEmpty : model.resources.isEmpty
    }

    private var emptyMessage: String {
        model.mode == "影视" ? "输入影视名称开始搜索" : "输入资源关键词开始搜索"
    }

    private func consumePendingResourceSearch() {
        guard let query = appState.pendingResourceSearch else { return }
        stopSearch()
        model.mode = "资源"
        model.query = query
        appState.pendingResourceSearch = nil
        startSearch()
    }

    private func startSearch() {
        activeSearchTask?.cancel()
        model.cancelSearch()
        activeSearchTask = Task { await model.search(appState) }
    }

    private func stopSearch(clearResults: Bool = false) {
        activeSearchTask?.cancel()
        activeSearchTask = nil
        model.cancelSearch(clearResults: clearResults)
    }
}

struct ResourceFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: SearchViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("限制") {
                    Toggle("不看 HR", isOn: $model.resourceFilterExcludeHR)
                    Toggle("限制大小", isOn: $model.resourceFilterSizeEnabled)
                    if model.resourceFilterSizeEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("大小范围", value: sizeRangeLabel)
                            Slider(value: $model.resourceFilterMinSizeGB, in: 0...100, step: 1)
                                .accessibilityLabel("最小大小")
                            Slider(value: $model.resourceFilterMaxSizeGB, in: 0...100, step: 1)
                                .accessibilityLabel("最大大小")
                        }
                        .onChange(of: model.resourceFilterMinSizeGB) { _, value in
                            if value > model.resourceFilterMaxSizeGB { model.resourceFilterMaxSizeGB = value }
                        }
                        .onChange(of: model.resourceFilterMaxSizeGB) { _, value in
                            if value < model.resourceFilterMinSizeGB { model.resourceFilterMinSizeGB = value }
                        }
                    }
                }
                ResourceFilterValuesSection(title: "站点", values: model.resourceSites, selected: $model.resourceFilterSites, label: model.siteLabel)
                ResourceFilterValuesSection(title: "优惠", values: model.resourceSales, selected: $model.resourceFilterSales)
                ResourceFilterValuesSection(title: "分类", values: model.resourceCategories, selected: $model.resourceFilterCategories)
                ResourceFilterValuesSection(title: "分辨率", values: model.resourceResolutions, selected: $model.resourceFilterResolutions)
                ResourceFilterValuesSection(title: "季", values: model.resourceSeasons, selected: $model.resourceFilterSeasons)
                ResourceFilterValuesSection(title: "集", values: model.resourceEpisodes, selected: $model.resourceFilterEpisodes)
                ResourceFilterValuesSection(title: "标签", values: model.resourceTags, selected: $model.resourceFilterTags) { "#\($0)" }
            }
            .navigationTitle("筛选资源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("清除") { model.resetResourceFilters() }
                        .disabled(model.resourceFilterCount == 0)
                }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }

    private var sizeRangeLabel: String {
        String(format: "%.0f - %.0f GB", model.resourceFilterMinSizeGB, model.resourceFilterMaxSizeGB)
    }
}

private struct ResourceFilterValuesSection: View {
    let title: String
    let values: [String]
    @Binding var selected: Set<String>
    var label: (String) -> String = { $0 }

    var body: some View {
        if !values.isEmpty {
            Section(title) {
                ForEach(values, id: \.self) { value in
                    Button {
                        if selected.contains(value) { selected.remove(value) }
                        else { selected.insert(value) }
                    } label: {
                        HStack {
                            Text(label(value)).foregroundStyle(.primary)
                            Spacer()
                            if selected.contains(value) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(HarvestTheme.green)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct SearchSettingsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: SearchViewModel
    let onReload: () async -> Void
    @State private var maxCount: Int
    @State private var sitesEnabled: Bool
    @State private var selectedSiteIDs: Set<Int>
    @State private var isReloading = false
    @State private var didSave = false

    init(model: SearchViewModel, onReload: @escaping () async -> Void) {
        self.model = model
        self.onReload = onReload
        _maxCount = State(initialValue: model.maxCount)
        _sitesEnabled = State(initialValue: model.sitesEnabled)
        _selectedSiteIDs = State(initialValue: model.selectedSiteIDs)
    }

    private var allSitesSelected: Bool {
        !model.sites.isEmpty && selectedSiteIDs.count == model.sites.count
    }

    private let siteColumns = [
        GridItem(.adaptive(minimum: 86, maximum: 150), spacing: 8, alignment: .leading)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最大站点数").font(.headline)
                            Text("从多少个站点搜索，默认 5，0 表示全部")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button("不限") { maxCount = 0 }
                            .buttonStyle(.bordered)
                            .tint(HarvestTheme.green)
                        HStack(spacing: 4) {
                            Button { maxCount = max(0, maxCount - 1) } label: {
                                Image(systemName: "minus").frame(width: 30, height: 34)
                            }
                            .disabled(maxCount == 0)
                            Text(maxCount == 0 ? "全部" : "\(maxCount)")
                                .font(.headline.monospacedDigit())
                                .frame(minWidth: 36)
                            Button { maxCount = min(50, maxCount + 1) } label: {
                                Image(systemName: "plus").frame(width: 30, height: 34)
                            }
                            .disabled(maxCount >= 50)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 5)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.10)))
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("指定站点").font(.headline)
                                Text(sitesEnabled ? "仅显示存活且可搜索的站点" : "已关闭，搜索时不指定站点")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(sitesEnabled ? "\(selectedSiteIDs.count) 个站点" : "关闭")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(HarvestTheme.blue)
                            Toggle("", isOn: $sitesEnabled).labelsHidden()
                        }

                        HStack(spacing: 8) {
                            SearchSettingsActionButton(
                                title: "加载",
                                icon: "arrow.clockwise",
                                color: HarvestTheme.amber,
                                isLoading: isReloading
                            ) { reloadSites() }
                            SearchSettingsActionButton(
                                title: allSitesSelected ? "取消" : "全部",
                                icon: allSitesSelected ? "square" : "checkmark.square",
                                color: HarvestTheme.green
                            ) { toggleAllSites() }
                            SearchSettingsActionButton(
                                title: "随机",
                                icon: "dice",
                                color: HarvestTheme.green
                            ) { selectRandomSites() }
                            SearchSettingsActionButton(
                                title: didSave ? "已保存" : "保存",
                                icon: didSave ? "checkmark" : "square.and.arrow.down",
                                color: HarvestTheme.blue
                            ) { persistDraft() }
                        }

                        if model.sites.isEmpty {
                            Text(isReloading ? "正在加载站点" : "没有可搜索的存活站点")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 100)
                        } else {
                            LazyVGrid(columns: siteColumns, alignment: .leading, spacing: 8) {
                                ForEach(model.sites) { site in
                                    Button {
                                        sitesEnabled = true
                                        if selectedSiteIDs.contains(site.id) {
                                            selectedSiteIDs.remove(site.id)
                                        } else {
                                            selectedSiteIDs.insert(site.id)
                                        }
                                        didSave = false
                                    } label: {
                                        HStack(spacing: 5) {
                                            Text(privacyMaskedText(site.name, enabled: appState.privacyMode))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.75)
                                            if selectedSiteIDs.contains(site.id) {
                                                Image(systemName: "checkmark")
                                                    .font(.caption2.weight(.bold))
                                            }
                                        }
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(selectedSiteIDs.contains(site.id) ? HarvestTheme.blue : Color.primary)
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .padding(.horizontal, 8)
                                        .background(
                                            selectedSiteIDs.contains(site.id)
                                                ? HarvestTheme.blue.opacity(0.10)
                                                : Color(uiColor: .systemBackground),
                                            in: RoundedRectangle(cornerRadius: 7)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7)
                                                .stroke(selectedSiteIDs.contains(site.id) ? HarvestTheme.blue.opacity(0.45) : Color.primary.opacity(0.08))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemBackground).opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(16)
            }
            .navigationTitle("搜索设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        persistDraft()
                        dismiss()
                    }
                }
            }
            .onChange(of: maxCount) { _, _ in didSave = false }
            .onChange(of: sitesEnabled) { _, _ in didSave = false }
        }
    }

    private func reloadSites() {
        guard !isReloading else { return }
        isReloading = true
        Task {
            await onReload()
            selectedSiteIDs = model.selectedSiteIDs
            sitesEnabled = model.sitesEnabled
            isReloading = false
            didSave = false
        }
    }

    private func toggleAllSites() {
        sitesEnabled = true
        selectedSiteIDs = allSitesSelected ? [] : Set(model.sites.map(\.id))
        didSave = false
    }

    private func selectRandomSites() {
        sitesEnabled = true
        let count = maxCount == 0 ? model.sites.count : min(maxCount, model.sites.count)
        selectedSiteIDs = Set(model.sites.shuffled().prefix(count).map(\.id))
        didSave = false
    }

    private func persistDraft() {
        model.maxCount = maxCount
        model.sitesEnabled = sitesEnabled
        model.selectedSiteIDs = selectedSiteIDs
        model.saveSettings()
        didSave = true
    }
}

private struct SearchSettingsActionButton: View {
    let title: String
    let icon: String
    let color: Color
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isLoading { ProgressView().controlSize(.small).tint(color) }
                else { Image(systemName: icon) }
                Text(title).lineLimit(1).minimumScaleFactor(0.75)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.30)))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

struct MediaRow: View {
    let item: MediaItem
    var body: some View {
        HStack(spacing: 12) {
            CachedRemoteImage(
                url: URL(string: item.poster),
                headers: mediaImageHeaders(source: item.source, raw: item.raw)
            ) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(Image(systemName: "film").foregroundStyle(.secondary))
            }
            .frame(width: 62, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 6) { Text(item.title).font(.headline); if !item.subtitle.isEmpty { Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Text(item.overview).font(.caption).foregroundStyle(.secondary).lineLimit(2); HStack { if item.score > 0 { Label(String(format: "%.1f", item.score), systemImage: "star.fill").foregroundStyle(HarvestTheme.amber) }; if !item.year.isEmpty { Text(item.year) }; Text(item.source).foregroundStyle(HarvestTheme.green) }.font(.caption2) }
        }.padding(.vertical, 5)
    }
}

struct ResourceRowItem: View {
    let item: [String: Any]
    let siteLabel: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(item.string("title", "name") ?? "未命名资源")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let subtitle = item.string("subtitle", "sub_title"), !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack {
                    Text(sizeLabel).fontWeight(.semibold)
                    Label("\(seeders)", systemImage: "arrow.up.circle.fill").foregroundStyle(HarvestTheme.green)
                    Label("\(leechers)", systemImage: "arrow.down.circle.fill").foregroundStyle(HarvestTheme.coral)
                    Label("\(completers)", systemImage: "checkmark.circle.fill")
                    Spacer(minLength: 6)
                    Text(siteLabel.isEmpty ? "未知站点" : siteLabel).lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !detailLabels.isEmpty {
                    Text(detailLabels.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            Image(systemName: "arrow.down.circle").foregroundStyle(HarvestTheme.green)
        }
        .padding(.vertical, 5)
    }

    private var sizeLabel: String {
        guard let bytes = item.double("size", "length", "size_bytes", "sizeBytes"), bytes > 0 else {
            return item.string("size", "length") ?? "未知大小"
        }
        return formatBytes(bytes)
    }

    private var seeders: Int { item.int("seeders", "seed", "seeder") ?? 0 }
    private var leechers: Int { item.int("leechers", "leecher", "leech") ?? 0 }
    private var completers: Int { item.int("completers", "completed", "snatched") ?? 0 }
    private var detailLabels: [String] {
        var values: [String] = []
        if let category = item.string("category", "category_name"), !category.isEmpty, category != "无分类" { values.append(category) }
        let sale = item.string("sale_status", "saleStatus", "promotion") ?? ""
        if !sale.isEmpty, sale != "无优惠" { values.append(sale) }
        if !(item.bool("hr") ?? false) { values.append("HR") }
        if let published = item.string("published", "pubdate", "created_at", "date"), !published.isEmpty { values.append(published) }
        return values
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
                        CachedRemoteImage(
                            url: URL(string: poster),
                            headers: imageHeaders
                        ) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.secondary.opacity(0.12)
                                .overlay(Image(systemName: "film").foregroundStyle(.secondary))
                        }
                        .frame(width: 104, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title).font(.title3.weight(.semibold))
                            if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                            HStack(spacing: 8) {
                                if score > 0 {
                                    Label(String(format: "%.1f", score), systemImage: "star.fill")
                                        .foregroundStyle(HarvestTheme.amber)
                                    if ratingCount > 0 {
                                        Text("(\(ratingCount) 票)").foregroundStyle(.secondary)
                                    }
                                } else if !ratingUnavailableReason.isEmpty {
                                    Text(ratingUnavailableReason).foregroundStyle(.secondary)
                                }
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
                if !honors.isEmpty {
                    Section("实时热度") {
                        ForEach(Array(honors.enumerated()), id: \.offset) { _, honor in
                            HStack {
                                Label(honor.string("title") ?? "榜单", systemImage: "flame.fill")
                                Spacer()
                                if let rank = honor.int("rank"), rank > 0 {
                                    Text("#\(rank)").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if !directors.isEmpty || !actors.isEmpty || !creators.isEmpty {
                    Section("演职员") {
                        if !directors.isEmpty { LabeledContent("导演", value: directors.joined(separator: "、")) }
                        if !creators.isEmpty { LabeledContent("主创", value: creators.joined(separator: "、")) }
                        if !actors.isEmpty { LabeledContent("主演", value: actors.prefix(12).joined(separator: "、")) }
                    }
                }
                Section("信息") {
                    if let status = resolved.string("status"), !status.isEmpty { LabeledContent("状态", value: status) }
                    if !countries.isEmpty { LabeledContent("国家", value: countries.joined(separator: " / ")) }
                    if !languages.isEmpty { LabeledContent("语言", value: languages.joined(separator: " / ")) }
                    if !durations.isEmpty {
                        LabeledContent("时长", value: durations.joined(separator: " / "))
                    } else if let runtime = resolved.int("runtime"), runtime > 0 {
                        LabeledContent("片长", value: "\(runtime) 分钟")
                    }
                    if !releaseDates.isEmpty { LabeledContent("上映", value: releaseDates.joined(separator: " / ")) }
                    if !aliases.isEmpty { LabeledContent("别名", value: aliases.joined(separator: " / ")) }
                    if isTV {
                        if let seasons = resolved.int("number_of_seasons"), seasons > 0 { LabeledContent("季数", value: "\(seasons)") }
                        if let episodes = resolved.int("number_of_episodes", "episodes_count"), episodes > 0 { LabeledContent("集数", value: "\(episodes)") }
                        if let progress = resolved.string("episodes_info"), !progress.isEmpty { LabeledContent("进度", value: progress) }
                    }
                    if let budget = resolved.int("budget"), budget > 0 { LabeledContent("预算", value: currency(budget)) }
                    if let revenue = resolved.int("revenue"), revenue > 0 { LabeledContent("票房", value: currency(revenue)) }
                    if !networks.isEmpty { LabeledContent("网络", value: networks.prefix(6).joined(separator: "、")) }
                    if !companies.isEmpty { LabeledContent("制作", value: companies.prefix(6).joined(separator: "、")) }
                    LabeledContent("条目 ID", value: item.remoteID)
                }
                if !vendors.isEmpty {
                    Section("播放源") {
                        ForEach(Array(vendors.enumerated()), id: \.offset) { _, vendor in
                            mediaLink(destination: vendor.string("url")) {
                                MediaVendorRow(vendor: vendor)
                            }
                        }
                    }
                }
                if !trailers.isEmpty {
                    Section("预告片") {
                        ForEach(Array(trailers.enumerated()), id: \.offset) { _, trailer in
                            mediaLink(destination: trailer.string("video_url", "url")) {
                                MediaTrailerCard(
                                    trailer: trailer,
                                    source: item.source,
                                    headers: imageHeaders
                                )
                            }
                        }
                    }
                }
                if commentCount > 0 || reviewCount > 0 || discussionCount > 0 {
                    Section("互动") {
                        HStack(spacing: 16) {
                            if commentCount > 0 { Label("\(commentCount) 短评", systemImage: "text.bubble") }
                            if reviewCount > 0 { Label("\(reviewCount) 影评", systemImage: "doc.text") }
                            if discussionCount > 0 { Label("\(discussionCount) 讨论", systemImage: "bubble.left.and.bubble.right") }
                        }
                        .font(.caption)
                    }
                }
                if !externalLinks.isEmpty {
                    Section {
                        ForEach(Array(externalLinks.enumerated()), id: \.offset) { index, link in
                            Link(destination: link.url) {
                                Label(index == 0 ? "打开官方页面" : "打开分享页面", systemImage: "safari")
                            }
                        }
                    }
                }
                if item.mediaType.lowercased() != "person" {
                    Section {
                        Button {
                            appState.openResourceSearch(searchQuery)
                            dismiss()
                        } label: {
                            Label("搜索资源", systemImage: "magnifyingglass")
                        }
                    }
                }
            }
            .navigationTitle("影视详情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await load() }
        }
    }

    private var resolved: [String: Any] { detail ?? item.raw.dict("target") ?? item.raw }
    private var imageHeaders: [String: String] {
        var headers = mediaImageHeaders(source: item.source, raw: item.raw)
        for (key, value) in mediaImageHeaders(source: item.source, raw: resolved) {
            headers[key] = value
        }
        return headers
    }
    private var title: String { resolved.string("title", "name") ?? item.title }
    private var subtitle: String { resolved.string("original_title", "original_name", "card_subtitle") ?? item.subtitle }
    private var overview: String { resolved.string("overview", "summary", "abstract", "intro", "biography") ?? item.overview }
    private var poster: String {
        let value = mediaImageValue(resolved)
        return mediaPosterURL(value.isEmpty ? item.poster : value, source: item.source)
    }
    private var score: Double { resolved.double("vote_average", "score") ?? resolved.dict("rating")?.double("value") ?? item.score }
    private var ratingCount: Int { resolved.int("vote_count") ?? resolved.dict("rating")?.int("count") ?? 0 }
    private var ratingUnavailableReason: String { resolved.string("null_rating_reason") ?? "" }
    private var year: String { (resolved.string("release_date", "first_air_date", "year") ?? item.year).prefix(4).description }
    private var genres: String {
        guard let value = resolved["genres"] else { return "" }
        if let values = value as? [String] { return values.joined(separator: " / ") }
        return jsonRows(value).compactMap { $0.string("name") }.joined(separator: " / ")
    }
    private var directors: [String] { personNames("directors", "director") }
    private var actors: [String] {
        let direct = personNames("actors", "casts", "cast")
        if !direct.isEmpty { return direct }
        return resolved.dict("credits")?.rows("cast").compactMap { $0.string("name") } ?? []
    }
    private var creators: [String] { personNames("created_by", "creators", "writers") }
    private var companies: [String] { personNames("production_companies") }
    private var networks: [String] { personNames("networks") }
    private var countries: [String] { stringValues("countries", "origin_country") }
    private var languages: [String] {
        let values = stringValues("languages")
        if !values.isEmpty { return values }
        return resolved.string("original_language", "language").map { [$0] } ?? []
    }
    private var durations: [String] { stringValues("durations") }
    private var releaseDates: [String] { stringValues("pubdate") }
    private var aliases: [String] { stringValues("aka") }
    private var honors: [[String: Any]] { resolved.rows("realtime_hot_honor_infos") }
    private var vendors: [[String: Any]] { resolved.rows("vendors") }
    private var trailers: [[String: Any]] { resolved.rows("trailers") }
    private var commentCount: Int { resolved.int("comment_count") ?? 0 }
    private var reviewCount: Int { resolved.int("review_count") ?? 0 }
    private var discussionCount: Int { resolved.int("forum_topic_count") ?? 0 }
    private var isTV: Bool { resolved.bool("is_tv") ?? (item.mediaType.lowercased() == "tv") }
    private var externalLinks: [(url: URL, value: String)] {
        var result: [(url: URL, value: String)] = []
        for key in ["homepage", "url", "sharing_url"] {
            guard let value = resolved.string(key), let url = externalURL(value) else { continue }
            if !result.contains(where: { $0.0.absoluteString == url.absoluteString }) { result.append((url, value)) }
        }
        return result
    }
    private var searchQuery: String {
        let externalID = resolved.string("imdb_id", "imdbId") ?? ""
        return externalID.isEmpty ? title : "\(externalID)||\(title)"
    }

    private func personNames(_ keys: String...) -> [String] {
        for key in keys {
            guard let value = resolved[key] else { continue }
            if let values = value as? [String], !values.isEmpty { return values }
            let names = jsonRows(value).compactMap { $0.string("name", "title") }
            if !names.isEmpty { return names }
        }
        return []
    }

    private func stringValues(_ keys: String...) -> [String] {
        for key in keys {
            let values = resolved.strings(key)
            if !values.isEmpty { return values }
        }
        return []
    }

    private func currency(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    private func externalURL(_ value: String) -> URL? {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        return url
    }

    @ViewBuilder
    private func mediaLink<Content: View>(destination: String?, @ViewBuilder content: () -> Content) -> some View {
        if let destination, let url = externalURL(destination) {
            Link(destination: url) { content() }
        } else {
            content()
        }
    }

    private func load() async {
        defer { isLoading = false }
        let path: String
        if isDoubanSource(item.source) {
            path = APIPath.doubanSubject + urlPathSegment(item.remoteID)
        } else {
            switch item.mediaType.lowercased() {
            case "tv": path = APIPath.tmdbTV + urlPathSegment(item.remoteID)
            case "person": path = APIPath.tmdbPerson + urlPathSegment(item.remoteID)
            default: path = APIPath.tmdbMovie + urlPathSegment(item.remoteID)
            }
        }
        do { detail = mediaPayloadDictionary(try await appState.api(path)) }
        catch { appState.presentedError = error.localizedDescription }
    }
}

private struct MediaVendorRow: View {
    let vendor: [String: Any]

    var body: some View {
        HStack(spacing: 12) {
            CachedRemoteImage(
                url: URL(string: normalizedRemoteImageURL(mediaImageValue(vendor)))
            ) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "play.tv").foregroundStyle(.secondary)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(vendor.string("title", "name") ?? "播放源").font(.subheadline.weight(.medium))
                let detail = [vendor.string("payment_desc"), vendor.string("episodes_info")]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if vendor.string("url") != nil { Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary) }
        }
        .foregroundStyle(.primary)
    }
}

private struct MediaTrailerCard: View {
    let trailer: [String: Any]
    let source: String
    let headers: [String: String]

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedRemoteImage(
                url: URL(string: mediaPosterURL(mediaImageValue(trailer), source: source)),
                headers: headers
            ) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.12)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)

            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(trailer.string("title") ?? "预告片").font(.subheadline.weight(.semibold))
                    let metadata = [trailer.string("type_name"), trailer.string("runtime")]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                    if !metadata.isEmpty { Text(metadata).font(.caption) }
                }
                Spacer()
                if trailer.string("video_url", "url") != nil { Image(systemName: "arrow.up.right").font(.caption) }
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous))
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
    @State private var sites: [SiteItem] = []
    @State private var siteIdentifier: String
    @State private var cookie: String
    @State private var generateTorrentURL: Bool
    @State private var category = ""
    @State private var tags: String
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
    @State private var isLoading = true
    @State private var isSaving = false

    init(item: [String: Any]) {
        self.item = item
        let initialURL = item.string("magnet_url", "magnetUrl", "detail_url", "detailUrl", "download_url", "url") ?? ""
        let initialSite = item.string("site_id", "siteId", "site") ?? ""
        _url = State(initialValue: initialURL)
        _siteIdentifier = State(initialValue: initialSite)
        _cookie = State(initialValue: item.string("cookie") ?? "")
        let lowercasedURL = initialURL.lowercased()
        _generateTorrentURL = State(initialValue: !initialSite.isEmpty && !lowercasedURL.contains("passkey") && !lowercasedURL.contains("sign"))
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
                Section("下载链接") {
                    Toggle(
                        "自动生成下载链接",
                        isOn: Binding(
                            get: { effectiveGenerateTorrentURL },
                            set: { if !mustGenerateTorrentURL { generateTorrentURL = $0 } }
                        )
                    )
                    .disabled(mustGenerateTorrentURL)
                    TextField("站点标识", text: $siteIdentifier).textInputAutocapitalization(.never)
                    if !sites.isEmpty {
                        Menu("从站点选择") {
                            ForEach(sites) { site in
                                Button(privacyMaskedText(site.name, enabled: appState.privacyMode)) {
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
                Section("选项") {
                    Toggle("添加后暂停", isOn: $paused)
                    Toggle("跳过文件校验", isOn: $skipChecking)
                    Toggle("高级设置", isOn: $showAdvanced)
                }
                if showAdvanced {
                    Section("高级推送") {
                        TextField("任务名称（可选）", text: $rename)
                        TextField("上传限制（KB/s）", text: $uploadLimit).keyboardType(.numberPad)
                        TextField("下载限制（KB/s）", text: $downloadLimit).keyboardType(.numberPad)
                        TextField("分享率限制", text: $ratioLimit).keyboardType(.decimalPad)
                        if isQBittorrent {
                            TextField("做种时间限制（分钟）", text: $seedingTimeLimit).keyboardType(.numberPad)
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
            .navigationTitle("推送资源").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("推送") { Task { await push() } }.disabled(isLoading || isSaving || downloaderID == 0 || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .task { await load() }
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
            do {
                sites = jsonRows(try await appState.api(APIPath.sites)).map(SiteItem.init)
                let rawSite = siteIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                if let site = sites.first(where: {
                    String($0.id) == rawSite
                        || $0.siteKey.caseInsensitiveCompare(rawSite) == .orderedSame
                        || $0.name.caseInsensitiveCompare(rawSite) == .orderedSame
                }) {
                    siteIdentifier = site.siteKey.isEmpty ? String(site.id) : site.siteKey
                    if cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        cookie = site.cookie
                    }
                }
            } catch {
                sites = []
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
        let trimmedSiteIdentifier = siteIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCookie = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if effectiveGenerateTorrentURL && !trimmedSiteIdentifier.isEmpty { body["site_id"] = trimmedSiteIdentifier }
        if !trimmedCookie.isEmpty { body["cookie"] = trimmedCookie }
        if !savePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["save_path"] = savePath.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["category"] = category.trimmingCharacters(in: .whitespacesAndNewlines) }
        let tagValues = tags.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !tagValues.isEmpty { body["tags"] = tagValues }
        if !rename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["rename"] = rename.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = Int(uploadLimit), value > 0 { body["upload_limit"] = value }
        if let value = Int(downloadLimit), value > 0 { body["download_limit"] = value }
        if let value = Double(ratioLimit) { body["ratio_limit"] = value }
        if let value = Int(seedingTimeLimit) { body["seeding_time_limit"] = value }
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
        if await appState.perform("\(APIPath.pushTorrent)/\(downloaderID)", method: .post, body: body) { dismiss() }
    }
}

private struct MediaCollection: Identifiable {
    let cacheKey: String
    let title: String
    let source: String
    let items: [MediaItem]
    var id: String { cacheKey }
}

private enum NewsMediaSource: String, CaseIterable, Identifiable {
    case tmdb = "TMDB"
    case douban = "豆瓣"

    var id: String { rawValue }
}

private struct MediaCatalogDefinition {
    let title: String
    let path: String
    let source: String
    let mediaType: String
    var query: [String: Any] = [:]

    var cacheKey: String {
        let queryValue = query.keys.sorted().map { key in
            "\(key)=\(query[key].map { String(describing: $0) } ?? "")"
        }.joined(separator: "&")
        return "news.catalog|\(source)|\(mediaType)|\(path)|\(queryValue)"
    }
}

struct NewsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var collections: [MediaCollection] = []
    @State private var doubanTags = ["热门"]
    @State private var selectedDoubanTag = "热门"
    @State private var isLoading = true
    @State private var usingCachedData = false
    @State private var cachedAt: Date?
    @State private var catalogSignature = ""
    @State private var selectedMedia: MediaItem?
    @State private var selectedCollection: MediaCollection?
    @State private var showNotices = false
    @State private var selectedSource: NewsMediaSource = .tmdb

    private var enabledSources: [NewsMediaSource] {
        var sources: [NewsMediaSource] = []
        if appState.mediaTMDBEnabled { sources.append(.tmdb) }
        if appState.mediaDoubanEnabled { sources.append(.douban) }
        return sources
    }

    private var activeSource: NewsMediaSource? {
        enabledSources.contains(selectedSource) ? selectedSource : enabledSources.first
    }

    private var visibleCollections: [MediaCollection] {
        guard let activeSource else { return [] }
        return collections.filter { collection in
            activeSource == .douban
                ? isDoubanSource(collection.source)
                : collection.source.caseInsensitiveCompare(NewsMediaSource.tmdb.rawValue) == .orderedSame
        }
    }

    var body: some View {
        ScrollView {
            if isLoading { LoadingState() }
            else {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if enabledSources.count > 1 {
                        HStack {
                            Picker("影视来源", selection: $selectedSource) {
                                ForEach(enabledSources) { source in
                                    Text(source.rawValue).tag(source)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 148)
                            Spacer(minLength: 0)
                        }
                    }
                    if usingCachedData {
                        SessionCacheBanner(cachedAt: cachedAt)
                    }
                    if !appState.mediaTMDBEnabled && !appState.mediaDoubanEnabled {
                        EmptyState(
                            icon: "film.stack",
                            title: "影视资讯未显示",
                            actionTitle: "搜索影视"
                        ) {
                            appState.selectedTab = 5
                        }
                        .frame(maxWidth: .infinity, minHeight: 240)
                    }
                    ForEach(visibleCollections) { collection in
                        MediaCarousel(
                            title: collection.title,
                            items: collection.items,
                            onSelect: { selectedMedia = $0 },
                            onShowAll: { selectedCollection = collection }
                        )
                    }
                    .animation(.easeInOut(duration: 0.2), value: selectedSource)
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
        .toolbar {
            if activeSource == .douban && doubanTags.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("豆瓣标签", selection: $selectedDoubanTag) {
                            ForEach(doubanTags, id: \.self) { Text($0).tag($0) }
                        }
                    } label: {
                        Image(systemName: "tag")
                    }
                    .accessibilityLabel("豆瓣标签")
                }
            }
        }
        .task {
            selectOnlyEnabledSource()
            if isLoading { await load() }
        }
        .onChange(of: appState.refreshGeneration) { _, _ in Task { await load() } }
        .onChange(of: selectedDoubanTag) { _, _ in Task { await load() } }
        .onChange(of: appState.mediaTMDBEnabled) { _, _ in
            selectOnlyEnabledSource()
            Task { await load() }
        }
        .onChange(of: appState.mediaDoubanEnabled) { _, _ in
            selectOnlyEnabledSource()
            Task { await load() }
        }
        .sheet(item: $selectedMedia) { item in MediaDetailSheet(item: item).environmentObject(appState) }
        .sheet(item: $selectedCollection) { collection in MediaCollectionSheet(collection: collection).environmentObject(appState) }
        .sheet(isPresented: $showNotices) { NoticeView().environmentObject(appState).presentationDetents([.large]) }
    }

    private func load() async {
        let tag = selectedDoubanTag
        var definitions: [MediaCatalogDefinition] = []
        if appState.mediaTMDBEnabled {
            definitions.append(contentsOf: [
                MediaCatalogDefinition(title: "正在上映", path: APIPath.tmdbPlayingMovies, source: "TMDB", mediaType: "movie"),
                MediaCatalogDefinition(title: "即将上映", path: APIPath.tmdbUpcomingMovies, source: "TMDB", mediaType: "movie"),
                MediaCatalogDefinition(title: "TMDB 热门电影", path: APIPath.tmdbPopularMovies, source: "TMDB", mediaType: "movie"),
                MediaCatalogDefinition(title: "TMDB 高分电影", path: APIPath.tmdbTopMovies, source: "TMDB", mediaType: "movie"),
                MediaCatalogDefinition(title: "今日播出", path: APIPath.tmdbAiringTodayTV, source: "TMDB", mediaType: "tv"),
                MediaCatalogDefinition(title: "正在播出", path: APIPath.tmdbOnTheAirTV, source: "TMDB", mediaType: "tv"),
                MediaCatalogDefinition(title: "TMDB 热门剧集", path: APIPath.tmdbPopularTV, source: "TMDB", mediaType: "tv"),
                MediaCatalogDefinition(title: "TMDB 高分剧集", path: APIPath.tmdbTopTV, source: "TMDB", mediaType: "tv")
            ])
        }
        if appState.mediaDoubanEnabled {
            definitions.append(contentsOf: [
                MediaCatalogDefinition(title: "豆瓣热门电影 · \(tag)", path: APIPath.doubanHot, source: "豆瓣", mediaType: "movie", query: ["category": "movie", "tag": tag, "page_start": 0, "page_limit": 20]),
                MediaCatalogDefinition(title: "豆瓣热门剧集 · \(tag)", path: APIPath.doubanHot, source: "豆瓣", mediaType: "tv", query: ["category": "tv", "tag": tag, "page_start": 0, "page_limit": 20]),
                MediaCatalogDefinition(title: "豆瓣 Top250", path: APIPath.doubanTop250, source: "豆瓣", mediaType: "movie"),
                MediaCatalogDefinition(title: "豆瓣电影榜", path: APIPath.doubanRank, source: "豆瓣", mediaType: "movie", query: ["type_id": 1, "start": 0, "limit": 100]),
                MediaCatalogDefinition(title: "豆瓣剧集榜", path: APIPath.doubanRank, source: "豆瓣", mediaType: "tv", query: ["type_id": 2, "start": 0, "limit": 100])
            ])
        }

        let nextSignature = definitions.map(\.cacheKey).joined(separator: "\n")
        if catalogSignature != nextSignature {
            catalogSignature = nextSignature
            var restored: [MediaCollection] = []
            var newestCacheDate: Date?
            for definition in definitions {
                guard let cached = await cachedCollection(definition) else { continue }
                if !cached.collection.items.isEmpty { restored.append(cached.collection) }
                if cached.cachedAt > (newestCacheDate ?? .distantPast) {
                    newestCacheDate = cached.cachedAt
                }
            }
            collections = restored
            cachedAt = newestCacheDate
            usingCachedData = !restored.isEmpty
        }

        isLoading = collections.isEmpty && !definitions.isEmpty
        defer { isLoading = false }
        let previous = Dictionary(uniqueKeysWithValues: collections.map { ($0.cacheKey, $0) })
        let fetchOrder = definitions.enumerated()
            .sorted { left, right in
                let leftDouban = isDoubanSource(left.element.source)
                let rightDouban = isDoubanSource(right.element.source)
                if leftDouban != rightDouban { return leftDouban }
                return left.offset < right.offset
            }
            .map { $0.element }
        var loadedByKey: [String: MediaCollection] = [:]
        var usedCachedFallback = false
        var loadedDoubanCatalog = false
        for definition in fetchOrder {
            if let result = await fetchCollection(definition) {
                await appState.writeSessionCache(result.raw, name: definition.cacheKey)
                if !result.collection.items.isEmpty {
                    loadedByKey[definition.cacheKey] = result.collection
                    if isDoubanSource(definition.source) { loadedDoubanCatalog = true }
                }
            } else if let fallback = previous[definition.cacheKey] {
                loadedByKey[definition.cacheKey] = fallback
                usedCachedFallback = true
                if isDoubanSource(definition.source), !fallback.items.isEmpty {
                    loadedDoubanCatalog = true
                }
            }
            collections = definitions.compactMap { loadedByKey[$0.cacheKey] ?? previous[$0.cacheKey] }
            if !collections.isEmpty { isLoading = false }
        }
        let loaded = definitions.compactMap { loadedByKey[$0.cacheKey] }
        collections = loaded
        usingCachedData = usedCachedFallback
        if !usedCachedFallback { cachedAt = nil }
        if appState.mediaDoubanEnabled && !loadedDoubanCatalog {
            appState.presentedError = "豆瓣影视暂时无法获取，请检查后端豆瓣 Cookie 与外网连接"
        } else if loaded.isEmpty && !definitions.isEmpty {
            appState.presentedError = "影视资讯暂时不可用，请检查 TMDB/豆瓣配置"
        }
        isLoading = false

        // 标签接口不是目录数据的前置依赖，放到首屏目录之后读取，避免它阻塞影视内容。
        if appState.mediaDoubanEnabled && doubanTags.count == 1 {
            do {
                let raw = try await appState.api(APIPath.doubanTags, query: ["category": "movie"])
                let values = jsonStrings(raw)
                if !values.isEmpty {
                    doubanTags = Array(Set(["热门"] + values)).sorted()
                }
            } catch {
                await AppLogStore.shared.append(.warning, "豆瓣标签接口不可用：\(error.localizedDescription)")
            }
        }
    }

    private func selectOnlyEnabledSource() {
        if appState.mediaTMDBEnabled && !appState.mediaDoubanEnabled {
            selectedSource = .tmdb
        } else if appState.mediaDoubanEnabled && !appState.mediaTMDBEnabled {
            selectedSource = .douban
        }
    }

    private func cachedCollection(
        _ definition: MediaCatalogDefinition
    ) async -> (collection: MediaCollection, cachedAt: Date)? {
        guard let cached = await appState.readSessionCache(definition.cacheKey) else { return nil }
        let items = mediaRows(cached.value).map {
            MediaItem($0, source: definition.source, mediaType: definition.mediaType)
        }
        return (
            MediaCollection(cacheKey: definition.cacheKey, title: definition.title, source: definition.source, items: items),
            cached.cachedAt
        )
    }

    private func fetchCollection(
        _ definition: MediaCatalogDefinition
    ) async -> (collection: MediaCollection, raw: Any)? {
        do {
            let raw = try await appState.api(definition.path, query: definition.query)
            let rows = mediaRows(raw)
            if rows.isEmpty {
                await AppLogStore.shared.append(.warning, "\(definition.source) \(definition.title) 返回空数据")
                return nil
            }
            await AppLogStore.shared.append(.info, "\(definition.source) \(definition.title) 解析到 \(rows.count) 条数据")
            let items = rows.map {
                MediaItem($0, source: definition.source, mediaType: definition.mediaType)
            }
            return (
                MediaCollection(cacheKey: definition.cacheKey, title: definition.title, source: definition.source, items: items),
                raw
            )
        } catch {
            await AppLogStore.shared.append(.error, "\(definition.source) \(definition.title) 加载失败：\(error.localizedDescription)")
            return nil
        }
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
                                    CachedRemoteImage(
                                        url: URL(string: item.poster),
                                        headers: mediaImageHeaders(source: item.source, raw: item.raw)
                                    ) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Color.secondary.opacity(0.12)
                                            .overlay(Image(systemName: "film").foregroundStyle(.secondary))
                                    }
                                    .frame(width: 112, height: 156)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    var body: some View { HStack(spacing: 12) { SymbolBadge(icon: icon, color: color, size: 42); VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }.cardSurface() }
}
