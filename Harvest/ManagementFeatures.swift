import SwiftUI
import WebKit

struct NoticeItem: Identifiable, Hashable {
    let id: Int
    var title: String
    var content: String
    var category: String
    var createdAt: String
    var read: Bool

    init(_ json: [String: Any]) {
        id = json.int("id") ?? abs((json.string("title") ?? UUID().uuidString).hashValue)
        title = json.string("title", "subject", "name") ?? "系统消息"
        content = json.string("content", "message", "text", "body") ?? ""
        category = json.string("category", "type", "level") ?? "通知"
        createdAt = json.string("created_at", "time", "date") ?? ""
        read = json.bool("read", "is_read") ?? false
    }
}

struct NoticeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var notices: [NoticeItem] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading { LoadingState() }
                else if notices.isEmpty { EmptyState(icon: "bell.slash", title: "没有消息", detail: "站点公告、任务结果和系统提醒会出现在这里") }
                else { List(notices) { notice in NoticeRow(item: notice).swipeActions(edge: .leading) { if !notice.read { Button { Task { await markRead(notice) } } label: { Label("已读", systemImage: "checkmark") }.tint(HarvestTheme.green) } } }.listStyle(.plain).refreshable { await load() } }
            }
            .navigationTitle("消息")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if notices.contains(where: { !$0.read }) {
                        Button("全部已读") {
                            Task {
                                if await appState.perform(APIPath.noticesRead) {
                                    notices = notices.map {
                                        var item = $0
                                        item.read = true
                                        return item
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .task { if isLoading { await load() } }
        }
    }

    private func load() async {
        defer { isLoading = false }
        do { notices = jsonRows(try await appState.api(APIPath.notices)).map(NoticeItem.init) }
        catch { appState.presentedError = error.localizedDescription }
    }

    private func markRead(_ notice: NoticeItem) async {
        if await appState.perform("\(APIPath.notices)/\(notice.id)/read", method: .put) {
            if let index = notices.firstIndex(where: { $0.id == notice.id }) { notices[index].read = true }
        }
    }
}

struct NoticeRow: View {
    let item: NoticeItem
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(item.read ? Color.secondary.opacity(0.10) : HarvestTheme.coral.opacity(0.14)).frame(width: 38, height: 38).overlay(Image(systemName: item.read ? "bell" : "bell.fill").foregroundStyle(item.read ? .secondary : HarvestTheme.coral))
            VStack(alignment: .leading, spacing: 5) { HStack { Text(item.title).font(.subheadline.weight(item.read ? .regular : .semibold)); Spacer(); Text(item.category).font(.caption2).foregroundStyle(.secondary) }; Text(item.content).font(.caption).foregroundStyle(.secondary).lineLimit(3); Text(item.createdAt).font(.caption2).foregroundStyle(.tertiary) }
        }.padding(.vertical, 5)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingLogout = false
    @State private var confirmingRestart = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 13) {
                        BrandMark(size: 48)
                        VStack(alignment: .leading, spacing: 3) { Text(appState.profile?.username ?? "Harvest 用户").font(.headline); Text(appState.profile?.email.isEmpty == false ? appState.profile!.email : appState.baseURL).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }.padding(.vertical, 5)
                }

                Section("外观与隐私") {
                    Picker("显示模式", selection: Binding(get: { appState.appearance }, set: appState.setAppearance)) { ForEach(AppAppearance.allCases) { Text($0.rawValue).tag($0) } }
                    Toggle(isOn: Binding(get: { appState.privacyMode }, set: appState.setPrivacyMode)) { Label("隐藏敏感数据", systemImage: "eye.slash") }
                }

                Section("管理") {
                    NavigationLink { BackendOptionsView().environmentObject(appState) } label: { Label("后端配置", systemImage: "slider.horizontal.3") }
                    NavigationLink { UserManagementView().environmentObject(appState) } label: { Label("用户中心", systemImage: "person.2") }
                    if appState.profile?.isSuperuser == true { NavigationLink { AdminView().environmentObject(appState) } label: { Label("授权管理", systemImage: "person.badge.key") } }
                    NavigationLink { LogView().environmentObject(appState) } label: { Label("日志中心", systemImage: "doc.text.magnifyingglass") }
                    NavigationLink { NativeBrowserView(urlString: appState.baseURL, title: "服务页面") } label: { Label("服务页面", systemImage: "safari") }
                }

                Section("维护") {
                    Button { Task { _ = await appState.perform(APIPath.cacheClear, method: .get); } } label: { Label("清理站点缓存", systemImage: "trash.slash") }
                    Button { Task { _ = await appState.perform(APIPath.notifyTest, method: .get, query: ["title": "Harvest", "content": "原生客户端通知测试", "push_type": ""]); } } label: { Label("发送测试通知", systemImage: "bell.badge") }
                    if appState.profile?.isSuperuser == true { Button(role: .destructive) { confirmingRestart = true } label: { Label("重启服务", systemImage: "arrow.clockwise.circle") } }
                }

                Section("关于") {
                    LabeledContent("客户端", value: "iOS 原生版")
                    LabeledContent("版本", value: "2026.0731.01 (290)")
                    LabeledContent("系统要求", value: "iOS 17+")
                }

                Section { Button(role: .destructive) { confirmingLogout = true } label: { Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity) } }
            }
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .confirmationDialog("确定退出当前账号？", isPresented: $confirmingLogout, titleVisibility: .visible) { Button("退出登录", role: .destructive) { dismiss(); appState.logout() } }
            .confirmationDialog("确定重启 Harvest 服务？", isPresented: $confirmingRestart, titleVisibility: .visible) { Button("重启服务", role: .destructive) { Task { _ = await appState.perform(APIPath.serverRestart, method: .get) } } }
        }
    }
}

struct BackendOption: Identifiable {
    let id: Int
    var name: String
    var value: [String: Any]
    var active: Bool

    init(_ json: [String: Any]) {
        id = json.int("id") ?? abs((json.string("name") ?? UUID().uuidString).hashValue)
        name = json.string("name") ?? "未命名配置"
        value = json.dict("value") ?? [:]
        active = json.bool("is_active", "active") ?? true
    }
}

@MainActor
final class BackendOptionsViewModel: ObservableObject {
    @Published var options: [BackendOption] = []
    @Published var isLoading = true

    func load(_ appState: AppState) async {
        defer { isLoading = false }
        do { options = jsonRows(try await appState.api(APIPath.options)).map(BackendOption.init) }
        catch { appState.presentedError = error.localizedDescription }
    }

    func save(_ appState: AppState, option: BackendOption) async -> Bool {
        let body: [String: Any] = ["id": option.id, "name": option.name, "value": option.value, "is_active": option.active]
        let saved = await appState.perform("\(APIPath.options)/\(option.id)", method: .put, body: body)
        if saved { await load(appState) }
        return saved
    }
}

struct BackendOptionsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = BackendOptionsViewModel()
    @State private var selected: BackendOption?

    var body: some View {
        Group {
            if model.isLoading { LoadingState() }
            else if model.options.isEmpty { EmptyState(icon: "slider.horizontal.3", title: "没有配置项") }
            else {
                List(model.options) { option in
                    Button { selected = option } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8).fill(option.active ? HarvestTheme.green.opacity(0.14) : Color.secondary.opacity(0.12)).frame(width: 40, height: 40).overlay(Image(systemName: "switch.2").foregroundStyle(option.active ? HarvestTheme.green : .secondary))
                            VStack(alignment: .leading, spacing: 4) { Text(option.name).font(.headline).foregroundStyle(.primary); Text("\(option.value.count) 个参数").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            StatusPill(label: option.active ? "启用" : "停用", color: option.active ? HarvestTheme.green : .secondary)
                        }
                    }.buttonStyle(.plain)
                    .swipeActions(edge: .leading) { Button { Task { var updated = option; updated.active.toggle(); _ = await model.save(appState, option: updated) } } label: { Label(option.active ? "停用" : "启用", systemImage: option.active ? "pause" : "play") }.tint(HarvestTheme.amber) }
                }.listStyle(.plain).refreshable { await model.load(appState) }
            }
        }
        .navigationTitle("后端配置").navigationBarTitleDisplayMode(.inline)
        .task { if model.isLoading { await model.load(appState) } }
        .sheet(item: $selected) { option in OptionEditorSheet(option: option) { updated in await model.save(appState, option: updated) }.environmentObject(appState) }
    }
}

struct OptionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let option: BackendOption
    let save: (BackendOption) async -> Bool
    @State private var jsonText = ""
    @State private var active: Bool
    @State private var parseError: String?
    @State private var isSaving = false

    init(option: BackendOption, save: @escaping (BackendOption) async -> Bool) {
        self.option = option
        self.save = save
        _active = State(initialValue: option.active)
        let data = try? JSONSerialization.data(withJSONObject: option.value, options: [.prettyPrinted, .sortedKeys])
        _jsonText = State(initialValue: data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("状态") { Toggle("启用 \(option.name)", isOn: $active) }
                Section("配置 JSON") {
                    TextEditor(text: $jsonText).font(.system(.caption, design: .monospaced)).frame(minHeight: 280).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if let parseError { Label(parseError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(HarvestTheme.coral) }
                }
            }
            .navigationTitle(option.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await persist() } }.disabled(isSaving) }
            }
        }
    }

    private func persist() async {
        guard let data = jsonText.data(using: .utf8) else { return }
        do {
            guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { parseError = "配置必须是 JSON 对象"; return }
            parseError = nil
            isSaving = true
            var updated = option
            updated.value = value
            updated.active = active
            if await save(updated) { dismiss() }
            isSaving = false
        } catch { parseError = "JSON 格式错误：\(error.localizedDescription)" }
    }
}

struct ManagedUser: Identifiable, Hashable {
    let id: Int
    var username: String
    var email: String
    var active: Bool
    var admin: Bool
    var joined: String

    init(_ json: [String: Any]) {
        id = json.int("id", "user_id") ?? abs((json.string("username") ?? UUID().uuidString).hashValue)
        username = json.string("username", "name") ?? "用户"
        email = json.string("email") ?? ""
        active = json.bool("is_active", "active") ?? true
        admin = json.bool("is_superuser", "admin") ?? false
        joined = json.string("date_joined", "created_at", "joined") ?? ""
    }
}

@MainActor
final class UsersViewModel: ObservableObject {
    @Published var users: [ManagedUser] = []
    @Published var isLoading = true
    let endpoint: String
    init(endpoint: String) { self.endpoint = endpoint }
    func load(_ appState: AppState) async { defer { isLoading = false }; do { users = jsonRows(try await appState.api(endpoint)).map(ManagedUser.init) } catch { appState.presentedError = error.localizedDescription } }
    func toggle(_ appState: AppState, user: ManagedUser) async { let body: [String: Any] = ["id": user.id, "username": user.username, "email": user.email, "is_active": !user.active, "is_superuser": user.admin]; if await appState.perform("\(endpoint)/\(user.id)", method: .put, body: body) { await load(appState) } }
    func delete(_ appState: AppState, user: ManagedUser) async { if await appState.perform("\(endpoint)/\(user.id)", method: .delete) { users.removeAll { $0.id == user.id } } }
}

struct UserManagementView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = UsersViewModel(endpoint: APIPath.users)
    @State private var showAdd = false

    var body: some View {
        Group { if model.isLoading { LoadingState() } else if model.users.isEmpty { EmptyState(icon: "person.2.slash", title: "没有其他用户") } else { List(model.users) { user in UserRow(user: user).swipeActions(edge: .trailing, allowsFullSwipe: false) { Button { Task { await model.toggle(appState, user: user) } } label: { Label(user.active ? "停用" : "启用", systemImage: user.active ? "pause" : "play") }.tint(HarvestTheme.amber); if appState.profile?.isSuperuser == true { Button(role: .destructive) { Task { await model.delete(appState, user: user) } } label: { Label("删除", systemImage: "trash") } } } }.listStyle(.plain).refreshable { await model.load(appState) } } }
        .navigationTitle("用户中心").navigationBarTitleDisplayMode(.inline)
        .toolbar { if appState.profile?.isSuperuser == true { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "person.badge.plus") } } } }
        .task { if model.isLoading { await model.load(appState) } }
        .sheet(isPresented: $showAdd) { UserEditorSheet(endpoint: APIPath.users) { await model.load(appState) }.environmentObject(appState) }
    }
}

struct AdminView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = UsersViewModel(endpoint: APIPath.adminUsers)
    @State private var showInvite = false

    var body: some View {
        Group { if model.isLoading { LoadingState() } else { List { Section("授权用户") { ForEach(model.users) { UserRow(user: $0) } }; Section("系统操作") { Button { showInvite = true } label: { Label("邀请用户", systemImage: "envelope.badge.person.crop") }; Button { Task { _ = await appState.perform("/api/auth/admin/cache/clear") } } label: { Label("清理版本缓存", systemImage: "shippingbox.and.arrow.backward") } } }.refreshable { await model.load(appState) } } }
        .navigationTitle("授权管理").navigationBarTitleDisplayMode(.inline)
        .task { if model.isLoading { await model.load(appState) } }
        .sheet(isPresented: $showInvite) { InviteSheet { await model.load(appState) }.environmentObject(appState) }
    }
}

struct UserRow: View {
    let user: ManagedUser
    var body: some View { HStack(spacing: 12) { Circle().fill(user.active ? HarvestTheme.green.opacity(0.14) : Color.secondary.opacity(0.12)).frame(width: 42, height: 42).overlay(Text(String(user.username.prefix(1)).uppercased()).font(.headline).foregroundStyle(user.active ? HarvestTheme.green : .secondary)); VStack(alignment: .leading, spacing: 4) { HStack { Text(user.username).font(.headline); if user.admin { Image(systemName: "checkmark.shield.fill").foregroundStyle(HarvestTheme.coral).font(.caption) } }; Text(user.email.isEmpty ? "未设置邮箱" : user.email).font(.caption).foregroundStyle(.secondary) }; Spacer(); StatusPill(label: user.active ? "启用" : "停用", color: user.active ? HarvestTheme.green : .secondary) }.padding(.vertical, 4) }
}

struct UserEditorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let endpoint: String
    let onSaved: () async -> Void
    @State private var username = ""; @State private var email = ""; @State private var password = ""; @State private var admin = false
    var body: some View { NavigationStack { Form { TextField("用户名", text: $username); TextField("邮箱", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never); SecureField("初始密码", text: $password); Toggle("管理员", isOn: $admin) }.navigationTitle("添加用户").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { let body: [String: Any] = ["username": username, "email": email, "password": password, "is_superuser": admin, "is_active": true]; if await appState.perform(endpoint, method: .post, body: body) { await onSaved(); dismiss() } } }.disabled(username.isEmpty || password.isEmpty) } } } }
}

struct InviteSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onSaved: () async -> Void
    @State private var email = ""
    var body: some View { NavigationStack { Form { TextField("邀请邮箱", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never) }.navigationTitle("邀请用户").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("发送") { Task { if await appState.perform(APIPath.adminUsers, method: .post, query: ["invite_email": email]) { await onSaved(); dismiss() } } }.disabled(email.isEmpty) } } } }
}

struct LogView: View {
    @EnvironmentObject private var appState: AppState
    @State private var entries: [[String: Any]] = []
    @State private var query = ""
    @State private var isLoading = true

    var filtered: [[String: Any]] { guard !query.isEmpty else { return entries }; return entries.filter { ($0.string("message", "text", "detail") ?? "").localizedCaseInsensitiveContains(query) } }
    var body: some View {
        Group { if isLoading { LoadingState() } else if entries.isEmpty { EmptyState(icon: "doc.text", title: "没有日志") } else { List { ForEach(Array(filtered.enumerated()), id: \.offset) { _, entry in VStack(alignment: .leading, spacing: 5) { HStack { Text(entry.string("level", "type") ?? "INFO").font(.caption2.weight(.bold)).foregroundStyle(logColor(entry.string("level", "type"))); Spacer(); Text(entry.string("time", "created_at", "date") ?? "").font(.caption2).foregroundStyle(.tertiary) }; Text(entry.string("message", "text", "detail") ?? String(describing: entry)).font(.caption.monospaced()).textSelection(.enabled) } } }.listStyle(.plain).refreshable { await load() } } }
        .searchable(text: $query, prompt: "筛选日志")
        .navigationTitle("日志中心").navigationBarTitleDisplayMode(.inline)
        .task { if isLoading { await load() } }
    }
    private func load() async { defer { isLoading = false }; do { entries = jsonRows(try await appState.api(APIPath.logs)) } catch { appState.presentedError = error.localizedDescription } }
    private func logColor(_ level: String?) -> Color { let text = level?.lowercased() ?? ""; return text.contains("error") ? HarvestTheme.coral : text.contains("warn") ? HarvestTheme.amber : HarvestTheme.green }
}

struct NativeBrowserView: UIViewRepresentable {
    let urlString: String
    let title: String
    func makeUIView(context: Context) -> WKWebView { let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .default(); let view = WKWebView(frame: .zero, configuration: configuration); if let url = URL(string: urlString) { view.load(URLRequest(url: url)) }; return view }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
