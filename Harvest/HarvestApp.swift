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

    var body: some View {
        Image("LaunchMark")
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .background(Color.white, in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityLabel("Harvest")
    }
}
