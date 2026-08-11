import Foundation
import SwiftUI
import UIKit

private func setupValue(_ value: String?, fallback: String) -> String {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return normalized.isEmpty ? fallback : normalized
}

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showHistory = false
    @State private var showSetup = false
    @State private var showAppUpdate = false
    @State private var confirmClearAllData = false
    @State private var isClearingData = false
    @State private var showClearCompleted = false
    @State private var isCheckingServer = false
    @State private var setupStatus: HarvestSetupStatus?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 12) {
                            BrandMark(size: 68)
                            Text("Harvest")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                            Text("把站点、下载和自动化任务收进一个工作台")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 32)

                        VStack(spacing: 14) {
                            LabeledField(title: "服务器地址", icon: "server.rack", text: $server,
                                         prompt: "https://harvest.example.com", keyboard: .URL)
                            LabeledField(title: "账号", icon: "person", text: $username, prompt: "管理员账号")
                            SecureLabeledField(title: "密码", text: $password, visible: $showPassword)
                        }

                        Button {
                            Task {
                                guard !isCheckingServer else { return }
                                isCheckingServer = true
                                defer { isCheckingServer = false }
                                let status = await appState.fetchSetupStatus(server: server)
                                if status?.needsSetup == true {
                                    setupStatus = status
                                    showSetup = true
                                } else {
                                    await appState.login(server: server, username: username, password: password)
                                }
                            }
                        } label: {
                            HStack {
                                if appState.isBusy || isCheckingServer { ProgressView().tint(.white) }
                                Text(appState.isBusy || isCheckingServer ? "连接中" : "连接 Harvest")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HarvestTheme.green)
                        .disabled(appState.isBusy || isCheckingServer)

                        if !appState.loginHistory.isEmpty {
                            Button {
                                showHistory = true
                            } label: {
                                Label("使用历史账号", systemImage: "clock.arrow.circlepath")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        Button(role: .destructive) {
                            confirmClearAllData = true
                        } label: {
                            Label("清理所有持久化数据", systemImage: "trash.slash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(appState.isBusy || isClearingData)

                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield")
                            Text("令牌存储在本机钥匙串，密码不会上传到 Harvest 之外的服务。")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 28)
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 8) {
                        CurrentScreenShareButton()
                            .environmentObject(appState)
                            .buttonStyle(.bordered)
                        Button { showAppUpdate = true } label: {
                            Image(systemName: "arrow.up.circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(HarvestTheme.green)
                        .accessibilityLabel("APP 升级")
                    }
                        .padding(.top, 12)
                        .padding(.trailing, 16)
                }
            }
            .navigationTitle("登录")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showHistory) {
                LoginHistorySheet(server: $server, username: $username, password: $password)
                    .environmentObject(appState)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSetup) {
                SetupWizardView(server: server, setupStatus: setupStatus) { adminUser, adminPassword in
                    username = adminUser
                    password = adminPassword
                    Task { await appState.login(server: server, username: adminUser, password: adminPassword) }
                }
                .environmentObject(appState)
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showAppUpdate) {
                AppUpdatePromptView()
                    .environmentObject(appState)
                    .presentationDetents([.medium, .large])
            }
            .confirmationDialog(
                "清理所有持久化数据？",
                isPresented: $confirmClearAllData,
                titleVisibility: .visible
            ) {
                Button("清理", role: .destructive) {
                    Task {
                        isClearingData = true
                        await appState.clearAllPersistentData()
                        server = ""
                        username = ""
                        password = ""
                        showPassword = false
                        isClearingData = false
                        showClearCompleted = true
                    }
                }
            } message: {
                Text("将清除登录状态、历史账号、钥匙串令牌与密码、所有设置、APP 日志、网页 Cookie 和缓存。")
            }
            .alert("清理完成", isPresented: $showClearCompleted) {
                Button("好", role: .cancel) { }
            } message: {
                Text("本机持久化数据已全部清除。")
            }
            .onAppear {
                server = UserDefaults.standard.string(forKey: "harvest.baseURL") ?? ""
                let history = appState.loginHistory
                let record = history.first(where: { $0.server == server }) ?? history.first
                if let record {
                    if server.isEmpty { server = record.server }
                    username = record.username
                    password = appState.savedPassword(for: record) ?? ""
                }
            }
        }
    }
}

struct SetupWizardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let server: String
    let setupStatus: HarvestSetupStatus?
    let onComplete: (String, String) -> Void

    @State private var step = 0
    @State private var databaseType = "pgsql"
    @State private var host = "go-harvest-postgres"
    @State private var port = "5432"
    @State private var database = "goharvest"
    @State private var databaseUser = "goharvest"
    @State private var databasePassword = ""
    @State private var debug = false
    @State private var adminUser = "admin"
    @State private var adminPassword = ""
    @State private var confirmPassword = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(
        server: String,
        setupStatus: HarvestSetupStatus? = nil,
        onComplete: @escaping (String, String) -> Void
    ) {
        self.server = server
        self.setupStatus = setupStatus
        self.onComplete = onComplete
        let defaults = setupStatus?.defaults(for: "pgsql")
        _host = State(initialValue: setupValue(defaults?.host, fallback: "go-harvest-postgres"))
        _port = State(initialValue: setupValue(defaults?.port, fallback: "5432"))
        _database = State(initialValue: setupValue(defaults?.name, fallback: "goharvest"))
        _databaseUser = State(initialValue: setupValue(defaults?.user, fallback: "goharvest"))
        _databasePassword = State(initialValue: defaults?.password ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule().fill(index <= step ? HarvestTheme.green : Color.secondary.opacity(0.2)).frame(height: 5)
                        }
                    }
                    Text(["选择数据库", "同步数据库", "创建管理员"][step]).font(.headline)
                }

                if step == 0 {
                    Section("数据库类型") {
                        Picker("类型", selection: $databaseType) { Text("PostgreSQL").tag("pgsql"); Text("SQLite").tag("sqlite") }.pickerStyle(.segmented)
                            .onChange(of: databaseType) { _, value in applyDatabaseDefaults(value) }
                        Text(databaseType == "pgsql" ? "适合长期运行与多用户部署" : "适合轻量部署，数据保存在服务端文件中")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if step == 1 {
                    Section(databaseType == "pgsql" ? "PostgreSQL" : "SQLite") {
                        if databaseType == "pgsql" {
                            TextField("数据库地址", text: $host).textInputAutocapitalization(.never)
                            TextField("端口", text: $port).keyboardType(.numberPad)
                            TextField("数据库名称", text: $database).textInputAutocapitalization(.never)
                            TextField("数据库账号", text: $databaseUser).textInputAutocapitalization(.never)
                            SecureField("数据库密码", text: $databasePassword)
                        } else {
                            LabeledContent("数据库文件", value: database)
                        }
                        Toggle("调试模式", isOn: $debug)
                    }
                } else {
                    Section("管理员账号") {
                        TextField("用户名", text: $adminUser).textInputAutocapitalization(.never)
                        SecureField("密码（至少 6 位）", text: $adminPassword)
                        SecureField("确认密码", text: $confirmPassword)
                    }
                }

                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(HarvestTheme.coral).font(.caption) }
                }
            }
            .navigationTitle("初始化 Harvest").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == 0 ? "取消" : "上一步") { if step == 0 { dismiss() } else { step -= 1; errorMessage = nil } }.disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(step == 2 ? "完成" : "下一步") { Task { await advance() } }.disabled(isSubmitting)
                }
            }
            .overlay { if isSubmitting { ZStack { Color.black.opacity(0.12).ignoresSafeArea(); ProgressView().controlSize(.large).padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)) } } }
        }
    }

    private func advance() async {
        errorMessage = nil
        if step == 0 {
            applyDatabaseDefaults(databaseType)
            step = 1
            return
        }
        if step == 1 {
            if databaseType == "pgsql" {
                guard let databasePort = Int(port),
                      (1...65_535).contains(databasePort),
                      !host.isEmpty,
                      !database.isEmpty,
                      !databaseUser.isEmpty else {
                    errorMessage = "请填写有效的数据库连接信息"
                    return
                }
            }
            isSubmitting = true
            defer { isSubmitting = false }
            var payload: [String: Any] = ["database_type": databaseType, "debug": debug, "name": database]
            if databaseType == "pgsql" {
                payload["host"] = host
                payload["port"] = port
                payload["user"] = databaseUser
                payload["pass"] = databasePassword
            }
            do { try await appState.setupDatabase(server: server, payload: payload); step = 2 }
            catch { errorMessage = error.localizedDescription }
            return
        }
        guard adminPassword.count >= 6 else { errorMessage = "管理员密码至少需要 6 位"; return }
        guard adminPassword == confirmPassword else { errorMessage = "两次输入的密码不一致"; return }
        guard !adminUser.isEmpty else { errorMessage = "管理员用户名不能为空"; return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await appState.setupAdministrator(
                server: server,
                username: adminUser,
                password: adminPassword
            )
            dismiss()
            onComplete(adminUser, adminPassword)
        } catch { errorMessage = error.localizedDescription }
    }

    private func applyDatabaseDefaults(_ type: String) {
        let defaults = setupStatus?.defaults(for: type)
        if type == "sqlite" {
            database = setupValue(defaults?.name, fallback: "db/data.sqlite3")
            return
        }
        host = setupValue(defaults?.host, fallback: "go-harvest-postgres")
        port = setupValue(defaults?.port, fallback: "5432")
        database = setupValue(defaults?.name, fallback: "goharvest")
        databaseUser = setupValue(defaults?.user, fallback: "goharvest")
        databasePassword = defaults?.password ?? ""
    }
}

struct LoginHistorySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Binding var server: String
    @Binding var username: String
    @Binding var password: String

    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.loginHistory) { record in
                    Button {
                        server = record.server
                        username = record.username
                        password = appState.savedPassword(for: record) ?? ""
                        dismiss()
                        Task { await appState.quickLogin(record) }
                    } label: {
                        HStack(spacing: 12) {
                            Circle().fill(HarvestTheme.green.opacity(0.15)).frame(width: 40, height: 40)
                                .overlay(Image(systemName: "person.fill").foregroundStyle(HarvestTheme.green))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.username).font(.headline).foregroundStyle(.primary)
                                Text(record.server).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { appState.removeLoginRecord(record) } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("历史账号")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}

struct AccountSwitcherView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var switchingID: String?

    var body: some View {
        List {
            Section {
                ForEach(appState.loginHistory) { record in
                    let isCurrent = record.server == appState.baseURL
                        && record.username == appState.profile?.username
                    Button {
                        guard !isCurrent else { return }
                        switchingID = record.id
                        Task {
                            await appState.quickLogin(record)
                            switchingID = nil
                            if appState.baseURL == record.server,
                               appState.profile?.username == record.username {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill((isCurrent ? HarvestTheme.green : HarvestTheme.blue).opacity(0.14))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: isCurrent ? "checkmark" : "person.fill")
                                        .foregroundStyle(isCurrent ? HarvestTheme.green : HarvestTheme.blue)
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(record.username).font(.headline)
                                    if isCurrent { Text("当前").font(.caption2).foregroundStyle(HarvestTheme.green) }
                                }
                                Text(record.server).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if switchingID == record.id { ProgressView().controlSize(.small) }
                        }
                        .foregroundStyle(.primary)
                    }
                    .disabled(isCurrent || switchingID != nil)
                }
            } header: {
                Text("已保存账号")
            }

            Section {
                Button(role: .destructive) {
                    appState.logout()
                } label: {
                    Label("登录其他账号", systemImage: "person.badge.plus")
                }
            }
        }
        .navigationTitle("切换账号")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MainShellView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false
    @State private var showingNotices = false
    @State private var showingAppUpdate = false
    @State private var availableAppUpdate: String?
    @State private var handledNoticePresentation = 0

    private let tabTitles = [
        0: "资讯",
        1: "站点",
        2: "仪表盘",
        3: "下载",
        4: "任务",
        5: "搜索"
    ]

    var body: some View {
        NavigationStack {
            TabView(selection: $appState.selectedTab) {
                if appState.mediaTMDBEnabled || appState.mediaDoubanEnabled {
                    NewsView().tabItem { Label("资讯", systemImage: "newspaper") }.tag(0)
                }
                if appState.profile?.isSuperuser == true {
                    SitesView().tabItem { Label("站点", systemImage: "globe.americas") }.tag(1)
                    DashboardView().tabItem { Label("仪表盘", systemImage: "rectangle.3.group") }.tag(2)
                }
                DownloadsView().tabItem { Label("下载", systemImage: "arrow.down.circle") }.tag(3)
                if appState.profile?.isSuperuser == true {
                    TasksView().tabItem { Label("任务", systemImage: "checklist") }.tag(4)
                }
                SearchView().tabItem { Label("搜索", systemImage: "magnifyingglass") }.tag(5)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        BrandMark(size: 28)
                        Text(tabTitles[appState.selectedTab] ?? "Harvest")
                            .font(.headline)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    CurrentScreenShareButton()
                        .environmentObject(appState)
                    if availableAppUpdate != nil {
                        Button {
                            showingAppUpdate = true
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(HarvestTheme.coral)
                        }
                        .accessibilityLabel("发现 APP 新版本")
                    }
                    Button { showingNotices = true } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: appState.unreadNoticeCount > 0 ? "bell.fill" : "bell")
                                .frame(width: 26, height: 26)
                            if appState.unreadNoticeCount > 0 {
                                Text(appState.unreadNoticeCount > 99 ? "99+" : "\(appState.unreadNoticeCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, appState.unreadNoticeCount > 9 ? 4 : 3)
                                    .frame(minWidth: 15, minHeight: 15)
                                    .background(HarvestTheme.coral, in: Capsule())
                                    .offset(x: 7, y: -5)
                            }
                        }
                        .frame(width: 34, height: 30)
                    }
                        .accessibilityLabel("消息")
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("设置")
                }
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView().environmentObject(appState) }
        .sheet(isPresented: $showingNotices) { NoticeView().environmentObject(appState).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showingAppUpdate) {
            AppUpdatePromptView().environmentObject(appState).presentationDetents([.medium, .large])
        }
        .task(id: appState.autoRefreshMinutes) {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(appState.autoRefreshMinutes * 60)) }
                catch { return }
                guard !Task.isCancelled else { return }
                appState.requestAutomaticRefresh(force: true)
            }
        }
        .task(id: appState.isAuthenticated) {
            guard appState.isAuthenticated else { return }
            await appState.requestNotificationAuthorization()
            await appState.refreshNoticeState()
            presentPendingNoticeIfNeeded()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
                guard !Task.isCancelled else { return }
                await appState.refreshNoticeState()
            }
        }
        .task(id: appState.isAuthenticated) {
            guard appState.isAuthenticated else {
                availableAppUpdate = nil
                return
            }
            let version = await availableAppUpdateVersion(appState)
            guard !Task.isCancelled else { return }
            availableAppUpdate = version
            guard let version, !isAppUpdateVersionIgnored(version) else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, !showingSettings, !showingNotices else { return }
            showingAppUpdate = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appState.requestAutomaticRefresh()
                Task { await appState.refreshNoticeState() }
            }
        }
        .onChange(of: appState.noticePresentationGeneration) { _, _ in
            presentPendingNoticeIfNeeded()
        }
        .onChange(of: appState.mediaTMDBEnabled || appState.mediaDoubanEnabled) { _, enabled in
            if !enabled && appState.selectedTab == 0 {
                appState.selectedTab = appState.profile?.isSuperuser == true ? 2 : 3
            }
        }
    }

    private func presentPendingNoticeIfNeeded() {
        guard appState.noticePresentationGeneration != handledNoticePresentation else { return }
        handledNoticePresentation = appState.noticePresentationGeneration
        showingNotices = true
    }
}

struct CurrentScreenShareButton: View {
    @EnvironmentObject private var appState: AppState
    @State private var shareImage: UIImage?
    @State private var showingShare = false
    @State private var isCapturing = false

    var body: some View {
        Button {
            Task { await captureAndShare() }
        } label: {
            if isCapturing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "camera.viewfinder")
            }
        }
        .disabled(isCapturing)
        .accessibilityLabel("截图分享当前页面")
        .sheet(isPresented: $showingShare) {
            if let shareImage { ActivityShareSheet(items: [shareImage]) }
        }
    }

    @MainActor private func captureAndShare() async {
        guard !isCapturing else { return }
        isCapturing = true
        let restorePrivacy = !appState.privacyMode
        if restorePrivacy { appState.setPrivacyMode(true) }
        try? await Task.sleep(for: .milliseconds(180))

        defer {
            if restorePrivacy { appState.setPrivacyMode(false) }
            isCapturing = false
        }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else {
            appState.presentedError = "无法获取当前页面截图"
            return
        }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { context in
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }
        shareImage = image
        showingShare = true
    }
}

struct LabeledField: View {
    let title: String
    let icon: String
    @Binding var text: String
    var prompt: String = ""
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(HarvestTheme.green).frame(width: 20)
                TextField(prompt, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(keyboard)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 13)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08)))
        }
    }
}

struct SecureLabeledField: View {
    let title: String
    @Binding var text: String
    @Binding var visible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: "key").foregroundStyle(HarvestTheme.green).frame(width: 20)
                Group { if visible { TextField("密码", text: $text) } else { SecureField("密码", text: $text) } }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button { visible.toggle() } label: { Image(systemName: visible ? "eye.slash" : "eye") }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(visible ? "隐藏密码" : "显示密码")
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 13)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08)))
        }
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.weight(.bold))
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let actionTitle, let action { Button(actionTitle, action: action).font(.subheadline.weight(.semibold)) }
        }
    }
}

struct MetricCard: View {
    let label: String
    let value: String
    let detail: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Spacer()
            }
            Text(value).font(.title2.weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.06))
        )
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    var detail: String = ""
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            if !detail.isEmpty { Text(detail) }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).tint(HarvestTheme.green)
            }
        }
    }
}

struct LoadingState: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().tint(HarvestTheme.green)
            Text("正在同步").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

struct SessionCacheBanner: View {
    let cachedAt: Date?

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "externaldrive.badge.clock")
                .foregroundStyle(HarvestTheme.green)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(HarvestTheme.green)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            HarvestTheme.green.opacity(0.09),
            in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
                .stroke(HarvestTheme.green.opacity(0.20))
        )
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        guard let cachedAt else { return "当前页面使用上次缓存数据" }
        return "当前页面使用上次缓存数据 · \(cachedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

extension View {
    func cardSurface() -> some View {
        self.padding(16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HarvestTheme.cardCornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.06))
            )
    }
}
