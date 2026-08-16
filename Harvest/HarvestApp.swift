import SwiftUI
import UIKit
import UserNotifications

final class HarvestAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        UserDefaults.standard.set(true, forKey: "notifications.openPending")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .harvestOpenNotices, object: nil)
        }
        completionHandler()
    }
}

@main
struct HarvestApp: App {
    @UIApplicationDelegateAdaptor(HarvestAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .tint(appState.accent.color)
                .preferredColorScheme(appState.colorScheme)
                .controlSize(appState.interfaceDensity.controlSize)
                .environment(\.defaultMinListRowHeight, appState.interfaceDensity.minimumRowHeight)
                .appInterfaceScale(appState.interfaceScale)
        }
    }
}

private extension View {
    @ViewBuilder
    func appInterfaceScale(_ scale: AppInterfaceScale) -> some View {
        switch scale {
        case .compact:
            dynamicTypeSize(.medium)
        case .system:
            self
        case .large:
            dynamicTypeSize(.xLarge)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.isRestoringSession {
                LaunchView()
            } else if appState.isAuthenticated {
                MainShellView()
                    .id(appState.sessionGeneration)
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isAuthenticated)
        .onAppear {
            if UserDefaults.standard.bool(forKey: "notifications.openPending") {
                UserDefaults.standard.removeObject(forKey: "notifications.openPending")
                appState.noticePresentationGeneration &+= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .harvestOpenNotices)) { _ in
            UserDefaults.standard.removeObject(forKey: "notifications.openPending")
            appState.noticePresentationGeneration &+= 1
        }
        .onAppear {
            ManualTaskFeedbackWindow.shared.update(appState.manualTaskFeedback)
        }
        .onChange(of: appState.manualTaskFeedback) { _, feedback in
            ManualTaskFeedbackWindow.shared.update(feedback)
        }
        .alert("请求失败", isPresented: Binding(
            get: { appState.presentedError != nil },
            set: { if !$0 { appState.presentedError = nil } }
        )) {
            Button("好", role: .cancel) { appState.presentedError = nil }
        } message: {
            Text(appState.presentedError ?? "未知错误")
        }
    }
}

@MainActor
private final class ManualTaskFeedbackWindow {
    static let shared = ManualTaskFeedbackWindow()

    private var window: UIWindow?
    private var hostingController: UIHostingController<ManualTaskFeedbackOverlay>?

    func update(_ feedback: ManualTaskFeedback?) {
        guard let feedback, feedback.phase != .failure else {
            window?.isHidden = true
            hostingController = nil
            window = nil
            return
        }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return
        }

        let controller = UIHostingController(rootView: ManualTaskFeedbackOverlay(feedback: feedback))
        controller.view.backgroundColor = .clear
        if window?.windowScene !== scene {
            let overlayWindow = UIWindow(windowScene: scene)
            overlayWindow.windowLevel = .alert + 1
            overlayWindow.backgroundColor = .clear
            window = overlayWindow
        }
        hostingController = controller
        window?.rootViewController = controller
        window?.isUserInteractionEnabled = feedback.phase == .running
        window?.isHidden = false
    }
}

struct LaunchView: View {
    var body: some View {
        ZStack {
            // Keep the in-app restore screen visually identical to the native launch screen.
            Color.white.ignoresSafeArea()
            VStack(spacing: 16) {
                BrandMark(size: 84)
                ProgressView()
                    .controlSize(.small)
                    .tint(HarvestTheme.amber)
            }
        }
    }
}

struct BrandMark: View {
    var size: CGFloat = 72
    @State private var revision = 0

    var body: some View {
        Group {
            if let image = BrandMarkStore.customImage {
                Image(uiImage: image)
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
            } else {
                Image("LaunchMark")
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
            }
        }
            .scaledToFit()
            .frame(width: size, height: size)
            .background(Color.white, in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityLabel("Harvest")
            .id(revision)
            .onReceive(NotificationCenter.default.publisher(for: .harvestBrandMarkChanged)) { _ in
                revision &+= 1
            }
    }
}

extension Notification.Name {
    static let harvestBrandMarkChanged = Notification.Name("harvest.brandMark.changed")
}

@MainActor
enum BrandMarkStore {
    private static let maximumSourceBytes = 24 * 1_024 * 1_024
    private static let maximumPixelSize: CGFloat = 1_024
    private static var cachedImage: UIImage?
    private static var didLoadImage = false

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("Harvest", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("custom-brand-mark.png")
    }

    static var customImage: UIImage? {
        if didLoadImage { return cachedImage }
        defer { didLoadImage = true }
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        cachedImage = UIImage(data: data)
        return cachedImage
    }

    static var hasCustomImage: Bool {
        if didLoadImage { return cachedImage != nil }
        guard let fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    static func save(_ sourceData: Data) -> Bool {
        guard !sourceData.isEmpty, sourceData.count <= maximumSourceBytes,
              let sourceImage = UIImage(data: sourceData) else { return false }
        let sourceSize = sourceImage.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return false }
        let scale = min(1, maximumPixelSize / max(sourceSize.width, sourceSize.height))
        let targetSize = CGSize(
            width: max(1, floor(sourceSize.width * scale)),
            height: max(1, floor(sourceSize.height * scale))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let normalized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let data = normalized.pngData(), data.count <= 8 * 1_024 * 1_024 else { return false }
        guard let fileURL else { return false }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return false
        }
        cachedImage = normalized
        didLoadImage = true
        NotificationCenter.default.post(name: .harvestBrandMarkChanged, object: nil)
        return true
    }

    static func restoreDefault() {
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        cachedImage = nil
        didLoadImage = true
        NotificationCenter.default.post(name: .harvestBrandMarkChanged, object: nil)
    }
}
