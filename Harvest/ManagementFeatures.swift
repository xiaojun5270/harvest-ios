import Foundation
import SwiftUI
import WebKit

struct NoticeItem: Identifiable, Hashable {
    let id: Int
    var title: String
    var content: String
    var category: String
    var createdAt: String
    var url: String
    var read: Bool

    init(_ json: [String: Any]) {
        id = json.int("id") ?? abs((json.string("title") ?? UUID().uuidString).hashValue)
        title = json.string("title", "subject", "name") ?? "系统消息"
        content = json.string("content", "message", "text", "body") ?? ""
        category = json.string("category", "type", "level") ?? "通知"
        createdAt = json.string("created_at", "create_time", "created", "time", "date") ?? ""
        url = json.string("url", "link") ?? ""
        read = json.bool("is_read", "isRead", "read", "readed", "has_read") ?? (json.string("read_at", "readAt", "read_time", "readTime") != nil)
    }
}

struct NoticeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var notices: [NoticeItem] = []
    @State private var isLoading = true
    @State private var selectedNotice: NoticeItem?
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading { LoadingState() }
                else if notices.isEmpty { EmptyState(icon: "bell.slash", title: "没有消息", detail: "站点公告、任务结果和系统提醒会出现在这里") }
                else {
                    List(notices) { notice in
                        Button { selectedNotice = notice } label: { NoticeRow(item: notice) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading) {
                                if !notice.read {
                                    Button { Task { await markRead(notice) } } label: { Label("已读", systemImage: "checkmark") }.tint(HarvestTheme.green)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { Task { await delete(notice) } } label: { Label("删除", systemImage: "trash") }
                            }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
            .navigationTitle("消息")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if !notices.isEmpty {
                        Menu {
                            if notices.contains(where: { !$0.read }) {
                                Button {
                                    Task {
                                        if await appState.perform(APIPath.noticesRead) {
                                            notices = notices.map {
                                                var item = $0
                                                item.read = true
                                                return item
                                            }
                                        }
                                    }
                                } label: { Label("全部已读", systemImage: "checkmark.circle") }
                            }
                            Button(role: .destructive) { confirmDeleteAll = true } label: { Label("删除全部", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("消息操作")
                    }
                }
            }
            .task { if isLoading { await load() } }
            .sheet(item: $selectedNotice) { notice in
                NoticeDetailSheet(
                    notice: notice,
                    onRead: { await markRead(notice) },
                    onDelete: { await delete(notice) }
                )
            }
            .confirmationDialog("确定删除全部消息？", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("删除全部", role: .destructive) { Task { await deleteAll() } }
            }
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

    private func delete(_ notice: NoticeItem) async {
        if await appState.perform("\(APIPath.notices)/\(notice.id)", method: .delete) {
            notices.removeAll { $0.id == notice.id }
        }
    }

    private func deleteAll() async {
        if await appState.perform(APIPath.notices, method: .delete) { notices = [] }
    }
}

struct NoticeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let notice: NoticeItem
    let onRead: () async -> Void
    let onDelete: () async -> Void
    @State private var isRead: Bool
    @State private var confirmDelete = false

    init(notice: NoticeItem, onRead: @escaping () async -> Void, onDelete: @escaping () async -> Void) {
        self.notice = notice
        self.onRead = onRead
        self.onDelete = onDelete
        _isRead = State(initialValue: notice.read)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(notice.title).font(.title3.weight(.semibold))
                    HStack {
                        Text(notice.category)
                        Spacer()
                        Text(notice.createdAt)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Section("内容") {
                    Text(notice.content.isEmpty ? "暂无内容" : notice.content)
                        .textSelection(.enabled)
                }
                if let url = URL(string: notice.url), !notice.url.isEmpty {
                    Section {
                        NavigationLink {
                            NativeBrowserView(urlString: url.absoluteString, title: notice.title)
                                .navigationTitle(notice.title)
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label("打开链接", systemImage: "safari")
                        }
                    }
                }
                Section {
                    if !isRead {
                        Button {
                            Task {
                                await onRead()
                                isRead = true
                            }
                        } label: { Label("标记已读", systemImage: "checkmark.circle") }
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("删除消息", systemImage: "trash") }
                }
            }
            .navigationTitle("消息详情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .confirmationDialog("确定删除这条消息？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除消息", role: .destructive) { Task { await onDelete(); dismiss() } }
            }
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
                    NavigationLink {
                        NativeBrowserView(urlString: appState.baseURL, title: "服务页面")
                            .navigationTitle("服务页面")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: { Label("服务页面", systemImage: "safari") }
                }

                Section("维护") {
                    Button { Task { _ = await appState.perform(APIPath.cacheClear, method: .get); } } label: { Label("清理站点缓存", systemImage: "trash.slash") }
                    Button { Task { _ = await appState.perform(APIPath.notifyTest, method: .get, query: ["title": "Harvest", "content": "原生客户端通知测试", "push_type": ""]); } } label: { Label("发送测试通知", systemImage: "bell.badge") }
                    if appState.profile?.isSuperuser == true { Button(role: .destructive) { confirmingRestart = true } label: { Label("重启服务", systemImage: "arrow.clockwise.circle") } }
                }

                Section("关于") {
                    LabeledContent("客户端", value: "iOS 原生版")
                    LabeledContent("版本", value: appVersionLabel)
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

    private var appVersionLabel: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String) ?? "--"
        let build = (info["CFBundleVersion"] as? String) ?? "--"
        return "\(version) (\(build))"
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
    var staff: Bool
    var admin: Bool
    var joined: String

    init(_ json: [String: Any]) {
        id = json.int("id", "user_id") ?? abs((json.string("username") ?? UUID().uuidString).hashValue)
        username = json.string("username", "name") ?? "用户"
        email = json.string("email") ?? ""
        active = json.bool("is_active", "active") ?? true
        staff = json.bool("is_staff", "staff") ?? false
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
    func toggle(_ appState: AppState, user: ManagedUser) async { let body: [String: Any] = ["id": user.id, "username": user.username, "email": user.email, "is_active": !user.active, "is_staff": user.staff, "is_superuser": user.admin]; if await appState.perform("\(endpoint)/\(user.id)", method: .put, body: body) { await load(appState) } }
    func delete(_ appState: AppState, user: ManagedUser) async { if await appState.perform("\(endpoint)/\(user.id)", method: .delete) { users.removeAll { $0.id == user.id } } }
}

struct UserManagementView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = UsersViewModel(endpoint: APIPath.users)
    @State private var showAdd = false
    @State private var editingUser: ManagedUser?

    var body: some View {
        Group { if model.isLoading { LoadingState() } else if model.users.isEmpty { EmptyState(icon: "person.2.slash", title: "没有其他用户") } else { List(model.users) { user in Button { editingUser = user } label: { UserRow(user: user) }.buttonStyle(.plain).swipeActions(edge: .leading, allowsFullSwipe: false) { Button { Task { await model.toggle(appState, user: user) } } label: { Label(user.active ? "停用" : "启用", systemImage: user.active ? "pause" : "play") }.tint(HarvestTheme.amber) }.swipeActions(edge: .trailing, allowsFullSwipe: false) { Button { editingUser = user } label: { Label("修改凭据", systemImage: "pencil") }.tint(HarvestTheme.blue); if appState.profile?.isSuperuser == true { Button(role: .destructive) { Task { await model.delete(appState, user: user) } } label: { Label("删除", systemImage: "trash") } } } }.listStyle(.plain).refreshable { await model.load(appState) } } }
        .navigationTitle("用户中心").navigationBarTitleDisplayMode(.inline)
        .toolbar { if appState.profile?.isSuperuser == true { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "person.badge.plus") } } } }
        .task { if model.isLoading { await model.load(appState) } }
        .sheet(isPresented: $showAdd) { UserEditorSheet(endpoint: APIPath.users) { await model.load(appState) }.environmentObject(appState) }
        .sheet(item: $editingUser) { user in UserEditorSheet(endpoint: APIPath.users, user: user) { await model.load(appState) }.environmentObject(appState) }
    }
}

struct AdminUserItem: Identifiable {
    let id: Int
    var username: String
    var email: String
    var pay: Int
    var invite: Int
    var tryUser: Bool
    var marked: String
    var expire: Int
    var expiresAt: String
    var updatedAt: String
    var raw: [String: Any]

    init(_ json: [String: Any]) {
        id = json.int("id") ?? 0
        username = json.string("username") ?? ""
        email = json.string("email") ?? ""
        pay = json.int("pay") ?? 168
        invite = json.int("invite") ?? 0
        tryUser = json.bool("try_user", "tryUser") ?? false
        marked = json.string("marked", "remark") ?? ""
        expire = json.int("expire", "expire_days") ?? 36600
        expiresAt = json.string("time_expire", "expires_at") ?? ""
        updatedAt = json.string("updated_at", "updatedAt", "update_time") ?? ""
        raw = json
    }
}

@MainActor
final class AdminUsersViewModel: ObservableObject {
    @Published var users: [AdminUserItem] = []
    @Published var isLoading = true

    func load(_ appState: AppState) async {
        defer { isLoading = false }
        do { users = jsonRows(try await appState.api(APIPath.adminUsers)).map(AdminUserItem.init) }
        catch { appState.presentedError = error.localizedDescription }
    }

    func update(_ appState: AppState, user: AdminUserItem, values: [String: Any]) async -> Bool {
        var body: [String: Any] = ["id": user.id]
        for (key, value) in values { body[key] = value }
        let saved = await appState.perform(APIPath.adminUsers, method: .put, body: body)
        if saved { await load(appState) }
        return saved
    }

    func resetToken(_ appState: AppState, user: AdminUserItem, expire: Int, pay: Int, tryUser: Bool) async -> Bool {
        let saved = await appState.perform(
            APIPath.adminResetToken,
            method: .post,
            query: ["user_id": user.id],
            body: ["expire": expire, "pay": pay, "try_user": tryUser]
        )
        if saved { await load(appState) }
        return saved
    }

    func sendToken(_ appState: AppState, user: AdminUserItem) async {
        _ = await appState.perform(APIPath.adminSendToken, method: .get, query: ["user_id": user.id])
    }

    func remove(_ appState: AppState, user: AdminUserItem) async {
        if await appState.perform("\(APIPath.adminUsers)/\(user.id)", method: .delete) {
            users.removeAll { $0.id == user.id }
        }
    }

    func resetInvites(_ appState: AppState, count: Int) async -> Bool {
        let saved = await appState.perform(APIPath.adminResetInvite, method: .get, query: ["count": count])
        if saved { await load(appState) }
        return saved
    }
}

struct AdminView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = AdminUsersViewModel()
    @State private var showInvite = false
    @State private var editingUser: AdminUserItem?
    @State private var resettingUser: AdminUserItem?
    @State private var showResetInvites = false

    var body: some View {
        Group {
            if model.isLoading { LoadingState() }
            else {
                List {
                    Section("授权用户") {
                        if model.users.isEmpty { Text("没有授权记录").foregroundStyle(.secondary) }
                        ForEach(model.users) { user in
                            Button { editingUser = user } label: { AdminUserRow(user: user) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { editingUser = user } label: { Label("编辑授权", systemImage: "pencil") }
                                    Button { resettingUser = user } label: { Label("重置令牌", systemImage: "key.horizontal") }
                                    Button { Task { await model.sendToken(appState, user: user) } } label: { Label("发送令牌邮件", systemImage: "envelope") }
                                    Button(role: .destructive) { Task { await model.remove(appState, user: user) } } label: { Label("删除授权", systemImage: "trash") }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button { resettingUser = user } label: { Label("重置令牌", systemImage: "key.horizontal") }.tint(HarvestTheme.amber)
                                    Button { Task { await model.sendToken(appState, user: user) } } label: { Label("发送邮件", systemImage: "envelope") }.tint(HarvestTheme.blue)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { Task { await model.remove(appState, user: user) } } label: { Label("删除", systemImage: "trash") }
                                }
                        }
                    }
                    Section("系统操作") {
                        Button { showInvite = true } label: { Label("邀请用户", systemImage: "envelope.badge.person.crop") }
                        Button { showResetInvites = true } label: { Label("重置邀请码", systemImage: "ticket") }
                        Button { Task { _ = await appState.perform(APIPath.adminCacheClear, method: .get) } } label: { Label("清理版本缓存", systemImage: "shippingbox.and.arrow.backward") }
                    }
                }
                .refreshable { await model.load(appState) }
            }
        }
        .navigationTitle("授权管理").navigationBarTitleDisplayMode(.inline)
        .task { if model.isLoading { await model.load(appState) } }
        .sheet(isPresented: $showInvite) { InviteSheet { await model.load(appState) }.environmentObject(appState) }
        .sheet(item: $editingUser) { user in AdminUserEditorSheet(user: user) { values in await model.update(appState, user: user, values: values) } }
        .sheet(item: $resettingUser) { user in AdminTokenResetSheet(user: user) { expire, pay, tryUser in await model.resetToken(appState, user: user, expire: expire, pay: pay, tryUser: tryUser) } }
        .sheet(isPresented: $showResetInvites) { ResetInvitesSheet { count in await model.resetInvites(appState, count: count) } }
    }
}

struct AdminUserRow: View {
    let user: AdminUserItem
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(user.tryUser ? HarvestTheme.amber.opacity(0.14) : HarvestTheme.green.opacity(0.14)).frame(width: 42, height: 42)
                .overlay(Image(systemName: user.tryUser ? "hourglass" : "key.fill").foregroundStyle(user.tryUser ? HarvestTheme.amber : HarvestTheme.green))
            VStack(alignment: .leading, spacing: 4) {
                Text(user.username.isEmpty ? user.email : user.username).font(.headline)
                if !user.username.isEmpty { Text(user.email).font(.caption).foregroundStyle(.secondary) }
                Text(user.expiresAt.isEmpty ? "有效期 \(user.expire) 天" : "到期 \(user.expiresAt)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(user.invite) 邀请").font(.caption)
                Text(user.tryUser ? "试用" : "正式").font(.caption2).foregroundStyle(user.tryUser ? HarvestTheme.amber : HarvestTheme.green)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AdminUserEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let user: AdminUserItem
    let save: ([String: Any]) async -> Bool
    @State private var username: String
    @State private var email: String
    @State private var pay: String
    @State private var invite: String
    @State private var tryUser: Bool
    @State private var marked: String
    @State private var expire: String

    init(user: AdminUserItem, save: @escaping ([String: Any]) async -> Bool) {
        self.user = user
        self.save = save
        _username = State(initialValue: user.username)
        _email = State(initialValue: user.email)
        _pay = State(initialValue: String(user.pay))
        _invite = State(initialValue: String(user.invite))
        _tryUser = State(initialValue: user.tryUser)
        _marked = State(initialValue: user.marked)
        _expire = State(initialValue: String(user.expire))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("账号") { TextField("用户名", text: $username); TextField("邮箱", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never); TextField("备注", text: $marked) }
                Section("授权") { TextField("付费次数", text: $pay).keyboardType(.numberPad); TextField("邀请码数量", text: $invite).keyboardType(.numberPad); TextField("有效天数", text: $expire).keyboardType(.numberPad); Toggle("试用用户", isOn: $tryUser) }
            }
            .navigationTitle("编辑授权").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { if await save(["id": user.id, "username": username, "email": email, "pay": Int(pay) ?? 0, "invite": Int(invite) ?? 0, "try_user": tryUser, "marked": marked, "expire": Int(expire) ?? 0]) { dismiss() } } }.disabled(email.isEmpty)
                }
            }
        }
    }
}

struct AdminTokenResetSheet: View {
    @Environment(\.dismiss) private var dismiss
    let user: AdminUserItem
    let reset: (Int, Int, Bool) async -> Bool
    @State private var expire: String
    @State private var pay: String
    @State private var tryUser: Bool

    init(user: AdminUserItem, reset: @escaping (Int, Int, Bool) async -> Bool) {
        self.user = user
        self.reset = reset
        _expire = State(initialValue: String(user.expire))
        _pay = State(initialValue: String(user.pay))
        _tryUser = State(initialValue: user.tryUser)
    }

    var body: some View {
        NavigationStack {
            Form { TextField("有效天数", text: $expire).keyboardType(.numberPad); TextField("付费次数", text: $pay).keyboardType(.numberPad); Toggle("试用用户", isOn: $tryUser) }
                .navigationTitle("重置令牌").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("重置") { Task { if await reset(Int(expire) ?? 0, Int(pay) ?? 0, tryUser) { dismiss() } } } } }
        }
    }
}

struct ResetInvitesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let reset: (Int) async -> Bool
    @State private var count = "1"
    var body: some View {
        NavigationStack {
            Form { TextField("邀请码数量", text: $count).keyboardType(.numberPad) }
                .navigationTitle("重置邀请码").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("重置") { Task { if await reset(Int(count) ?? 0) { dismiss() } } }.disabled((Int(count) ?? 0) <= 0) } }
        }
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
    let user: ManagedUser?
    let onSaved: () async -> Void
    @State private var username: String
    @State private var password = ""

    init(endpoint: String, user: ManagedUser? = nil, onSaved: @escaping () async -> Void) {
        self.endpoint = endpoint
        self.user = user
        self.onSaved = onSaved
        _username = State(initialValue: user?.username ?? "")
    }

    var body: some View { NavigationStack { Form { TextField("用户名", text: $username); SecureField(user == nil ? "初始密码" : "新密码", text: $password) }.navigationTitle(user == nil ? "添加用户" : "修改凭据").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { let body: [String: Any] = ["username": username, "password": password]; let path = user.map { "\(endpoint)/\($0.id)" } ?? endpoint; let method: HTTPMethod = user == nil ? .post : .put; if await appState.perform(path, method: method, body: body) { await onSaved(); dismiss() } } }.disabled(username.isEmpty || password.isEmpty) } } } }
}

struct InviteSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onSaved: () async -> Void
    @State private var email = ""
    var body: some View { NavigationStack { Form { TextField("邀请邮箱", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never) }.navigationTitle("邀请用户").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("发送") { Task { if await appState.perform(APIPath.adminUsers, method: .post, query: ["invite_email": email, "notify": false]) { await onSaved(); dismiss() } } }.disabled(email.isEmpty) } } } }
}

struct LogView: View {
    @EnvironmentObject private var appState: AppState
    @State private var entries: [[String: Any]] = []
    @State private var query = ""
    @State private var isLoading = true

    var filtered: [[String: Any]] {
        guard !query.isEmpty else { return entries }
        return entries.filter {
            ($0.string("display", "raw", "message", "text", "detail") ?? "")
                .localizedCaseInsensitiveContains(query)
        }
    }
    var body: some View {
        Group { if isLoading { LoadingState() } else if entries.isEmpty { EmptyState(icon: "doc.text", title: "没有日志") } else { List { ForEach(Array(filtered.enumerated()), id: \.offset) { _, entry in VStack(alignment: .leading, spacing: 5) { HStack { Text(entry.string("level", "type") ?? "INFO").font(.caption2.weight(.bold)).foregroundStyle(logColor(entry.string("level", "type"))); Spacer(); Text(entry.string("timestamp", "logged_at", "time", "created_at", "date") ?? "").font(.caption2).foregroundStyle(.tertiary) }; Text(entry.string("display", "raw", "message", "text", "detail") ?? String(describing: entry)).font(.caption.monospaced()).textSelection(.enabled) } } }.listStyle(.plain).refreshable { await load() } } }
        .searchable(text: $query, prompt: "筛选日志")
        .navigationTitle("日志中心").navigationBarTitleDisplayMode(.inline)
        .task { if isLoading { await load() } }
    }
    private func load() async {
        defer { isLoading = false }
        do { entries = jsonRows(try await appState.api(APIPath.logs, query: ["limit": 500, "offset": 0])) }
        catch { appState.presentedError = error.localizedDescription }
    }
    private func logColor(_ level: String?) -> Color { let text = level?.lowercased() ?? ""; return text.contains("error") ? HarvestTheme.coral : text.contains("warn") ? HarvestTheme.amber : HarvestTheme.green }
}

struct NativeBrowserView: UIViewRepresentable {
    let urlString: String
    let title: String
    let cookie: String
    let localStorage: String
    let userAgent: String

    init(
        urlString: String,
        title: String,
        cookie: String = "",
        localStorage: String = "",
        userAgent: String = ""
    ) {
        self.urlString = urlString
        self.title = title
        self.cookie = cookie
        self.localStorage = localStorage
        self.userAgent = userAgent
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        if let script = localStorageScript() {
            configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
        }

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        if !userAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            view.customUserAgent = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let url = URL(string: urlString), let host = url.host else { return view }

        let request = URLRequest(url: url)
        let cookies = browserCookies(host: host, secure: url.scheme?.lowercased() == "https")
        guard !cookies.isEmpty else {
            view.load(request)
            return view
        }

        let group = DispatchGroup()
        let store = configuration.websiteDataStore.httpCookieStore
        for cookie in cookies {
            group.enter()
            store.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) { [weak view] in view?.load(request) }
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private func browserCookies(host: String, secure: Bool) -> [HTTPCookie] {
        cookie.split(separator: ";").compactMap { pair in
            let text = String(pair).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = text.firstIndex(of: "=") else { return nil }
            let name = String(text[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(text[text.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: host,
                .path: "/",
                .name: name,
                .value: value
            ]
            if secure { properties[.secure] = "TRUE" }
            return HTTPCookie(properties: properties)
        }
    }

    private func localStorageScript() -> String? {
        let storage = localStorage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !storage.isEmpty,
              let host = URL(string: urlString)?.host,
              let hostLiteral = javaScriptLiteral(host.lowercased()),
              let storageLiteral = javaScriptLiteral(storage) else { return nil }
        return """
        (() => {
          if (window.location.hostname.toLowerCase() !== \(hostLiteral)) return;
          const raw = \(storageLiteral);
          const setItem = (key, value) => {
            if (key === undefined || key === null || String(key).length === 0) return;
            const text = typeof value === 'object' && value !== null ? JSON.stringify(value) : String(value ?? '');
            window.localStorage.setItem(String(key), text);
          };
          const applyObject = (data) => {
            if (Array.isArray(data)) {
              data.forEach((item) => { if (Array.isArray(item) && item.length >= 2) setItem(item[0], item[1]); });
            } else if (data && typeof data === 'object') {
              Object.keys(data).forEach((key) => setItem(key, data[key]));
            }
          };
          const applyText = (text) => text.split(';').forEach((part) => {
            const index = part.indexOf('=');
            if (index > 0) setItem(part.slice(0, index).trim(), part.slice(index + 1).trim());
          });
          const text = String(raw).trim();
          if (text.startsWith('{') || text.startsWith('[')) {
            try { applyObject(JSON.parse(text)); } catch (_) { applyText(text); }
          } else {
            applyText(text);
          }
        })();
        """
    }

    private func javaScriptLiteral(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
