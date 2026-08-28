import SwiftUI
import UIKit

enum HarvestSafariExtension {
    static let bundledVersion = "0.2.6"

    static var isBundled: Bool {
        guard let plugInsURL = Bundle.main.builtInPlugInsURL else { return false }
        return FileManager.default.fileExists(
            atPath: plugInsURL.appendingPathComponent("HarvestSafariExtension.appex").path
        )
    }

    @MainActor
    static func openSettings() async -> Bool {
        if let safariSettings = URL(string: "App-prefs:SAFARI&path=EXTENSIONS"),
           await UIApplication.shared.open(safariSettings) {
            return true
        }
        return await UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    }
}

struct SafariExtensionSettingsView: View {
    @State private var statusMessage = ""

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "safari.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(HarvestTheme.blue.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("收割机助手")
                            .font(.headline)
                        Text("Safari Web Extension · v\(HarvestSafariExtension.bundledVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: HarvestSafariExtension.isBundled ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(HarvestSafariExtension.isBundled ? HarvestTheme.green : HarvestTheme.amber)
                }
                .padding(.vertical, 4)
            }

            Section("启用扩展") {
                Button {
                    Task {
                        let opened = await HarvestSafariExtension.openSettings()
                        statusMessage = opened ? "已打开系统设置" : "无法打开设置，请手动进入 Safari 扩展设置"
                    }
                } label: {
                    Label("打开 Safari 扩展设置", systemImage: "gearshape.fill")
                }
                VStack(alignment: .leading, spacing: 7) {
                    setupStep(1, "打开“设置”并进入 Safari 浏览器")
                    setupStep(2, "进入“扩展”，开启“收割机助手”")
                    setupStep(3, "将网站访问权限设置为“允许”")
                }
                .padding(.vertical, 3)
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Label("读取和修改访问站点的网页内容", systemImage: "doc.text.magnifyingglass")
                Label("读取与写入站点 Cookie，用于同步登录信息", systemImage: "key.horizontal.fill")
                Label("调用 Harvest 的站点同步、搜索和下载器功能", systemImage: "arrow.triangle.2.circlepath")
            } header: {
                Text("扩展权限")
            } footer: {
                Text("扩展默认不会自动启用。安装 App 后仍需由你在系统设置中授权；服务器地址和令牌在扩展弹窗内单独配置。")
            }
        }
        .navigationTitle("Safari 扩展")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setupStep(_ number: Int, _ title: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(HarvestTheme.blue, in: Circle())
            Text(title)
                .font(.subheadline)
                .padding(.top, 1)
        }
    }
}
