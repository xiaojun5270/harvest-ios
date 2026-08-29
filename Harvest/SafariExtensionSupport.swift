import SwiftUI
import UIKit

private struct BundledSafariExtension: Identifiable {
    let productName: String
    let title: String
    let version: String
    let icon: String
    let color: Color
    let detail: String

    var id: String { productName }

    var isBundled: Bool {
        guard let plugInsURL = Bundle.main.builtInPlugInsURL else { return false }
        return FileManager.default.fileExists(
            atPath: plugInsURL.appendingPathComponent("\(productName).appex").path
        )
    }
}

private enum HarvestSafariExtensions {
    static let all = [
        BundledSafariExtension(
            productName: "HarvestSafariExtension",
            title: "收割机助手",
            version: "0.3.6",
            icon: "safari.fill",
            color: HarvestTheme.blue,
            detail: "在支持的 PT 站点中提供同步、搜索和下载器操作"
        ),
        BundledSafariExtension(
            productName: "CookieCloudSafariExtension",
            title: "CookieCloud",
            version: "1.0.3",
            icon: "icloud.fill",
            color: HarvestTheme.purple,
            detail: "端到端加密同步 Safari Cookie 与 Local Storage"
        )
    ]

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
            Section("内置扩展") {
                ForEach(HarvestSafariExtensions.all) { item in
                    HStack(spacing: 14) {
                        Image(systemName: item.icon)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(item.color.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(item.title).font(.headline)
                                Text("v\(item.version)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: item.isBundled ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(item.isBundled ? HarvestTheme.green : HarvestTheme.amber)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("启用扩展") {
                Button {
                    Task {
                        let opened = await HarvestSafariExtensions.openSettings()
                        statusMessage = opened ? "已打开系统设置" : "无法打开设置，请手动进入 Safari 扩展设置"
                    }
                } label: {
                    Label("打开 Safari 扩展设置", systemImage: "gearshape.fill")
                }
                VStack(alignment: .leading, spacing: 7) {
                    setupStep(1, "打开“设置”并进入 Safari 浏览器")
                    setupStep(2, "进入“扩展”，开启需要使用的扩展")
                    setupStep(3, "将对应网站访问权限设置为“允许”")
                }
                .padding(.vertical, 3)
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Label("收割机助手读取站点信息并调用 Harvest 功能", systemImage: "arrow.triangle.2.circlepath")
                Label("CookieCloud 读取与写入 Cookie、Local Storage", systemImage: "key.horizontal.fill")
                Label("CookieCloud 使用端到端加密连接自建同步服务", systemImage: "lock.shield.fill")
            } header: {
                Text("扩展权限")
            } footer: {
                Text("扩展安装后不会自动启用，必须由你在系统设置中授权。CookieCloud 的服务器地址、UUID、密码和同步模式在 Safari 工具栏的 CookieCloud 弹窗中配置。")
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
