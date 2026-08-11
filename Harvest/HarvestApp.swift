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

struct LaunchView: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                BrandMark(size: 84)
                ProgressView()
                    .controlSize(.small)
                    .tint(HarvestTheme.green)
            }
        }
    }
}

struct BrandMark: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(HarvestTheme.ink)
            Path { path in
                path.move(to: CGPoint(x: size * 0.24, y: size * 0.26))
                path.addLine(to: CGPoint(x: size * 0.24, y: size * 0.73))
                path.move(to: CGPoint(x: size * 0.76, y: size * 0.26))
                path.addLine(to: CGPoint(x: size * 0.76, y: size * 0.73))
                path.move(to: CGPoint(x: size * 0.24, y: size * 0.50))
                path.addLine(to: CGPoint(x: size * 0.76, y: size * 0.50))
            }
            .stroke(HarvestTheme.mint, style: StrokeStyle(lineWidth: size * 0.095, lineCap: .round))
            Circle()
                .fill(HarvestTheme.coral)
                .frame(width: size * 0.14, height: size * 0.14)
                .offset(x: size * 0.26, y: -size * 0.24)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Harvest")
    }
}
