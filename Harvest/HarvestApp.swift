import SwiftUI

@main
struct HarvestApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .tint(HarvestTheme.green)
                .preferredColorScheme(appState.colorScheme)
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
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isAuthenticated)
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
