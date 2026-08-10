import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showHistory = false
    @State private var showSetup = false

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
                                if (await appState.requiresSetup(server: server)) == true {
                                    showSetup = true
                                } else {
                                    await appState.login(server: server, username: username, password: password)
                                }
                            }
                        } label: {
                            HStack {
                                if appState.isBusy { ProgressView().tint(.white) }
                                Text(appState.isBusy ? "连接中" : "连接 Harvest")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HarvestTheme.green)
                        .disabled(appState.isBusy)

                        if !appState.loginHistory.isEmpty {
                            Button {
                                showHistory = true
                            } label: {
                                Label("使用历史账号", systemImage: "clock.arrow.circlepath")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

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
            }
            .navigationTitle("登录")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showHistory) {
                LoginHistorySheet(server: $server, username: $username, password: $password)
                    .environmentObject(appState)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSetup) {
                SetupWizardView(server: server) { adminUser, adminPassword in
                    username = adminUser
                    password = adminPassword
                    Task { await appState.login(server: server, username: adminUser, password: adminPassword) }
                }
                .environmentObject(appState)
                .interactiveDismissDisabled()
            }
            .onAppear {
                server = UserDefaults.standard.string(forKey: "harvest.baseURL") ?? ""
                if let first = appState.loginHistory.first { username = first.username }
            }
        }
    }
}

struct SetupWizardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let server: String
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
                            TextField("数据库文件", text: $database).textInputAutocapitalization(.never)
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
            if databaseType == "sqlite" { database = "db/data.sqlite3" }
            step = 1
            return
        }
        if step == 1 {
            guard databaseType == "sqlite" || (!host.isEmpty && Int(port) != nil && !database.isEmpty && !databaseUser.isEmpty) else {
                errorMessage = "请填写有效的数据库连接信息"
                return
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
            try await appState.setupAdministrator(server: server, username: adminUser, password: adminPassword)
            dismiss()
            onComplete(adminUser, adminPassword)
        } catch { errorMessage = error.localizedDescription }
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

struct MainShellView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingSettings = false
    @State private var showingNotices = false

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
                NewsView().tabItem { Label("资讯", systemImage: "newspaper") }.tag(0)
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
                    Button { showingNotices = true } label: { Image(systemName: "bell") }
                        .accessibilityLabel("消息")
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("设置")
                }
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView().environmentObject(appState) }
        .sheet(isPresented: $showingNotices) { NoticeView().environmentObject(appState).presentationDetents([.medium, .large]) }
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
