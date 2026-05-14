import SwiftUI

@main
struct PersonalSystemApp: App {
    @UIApplicationDelegateAdaptor(DailyStateReminderNotificationDelegate.self) private var notificationDelegate

    var body: some Scene {
        WindowGroup {
            SplashRootView()
        }
    }
}

private struct SplashRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var showingSplash = true
    @State private var updateInfo: AppUpdateInfo?
    @State private var didCheckUpdateThisSession = false

    var body: some View {
        Group {
            if showingSplash {
                RuntimeSplashView()
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation(.easeOut(duration: 0.28)) {
                            showingSplash = false
                        }
                    }
            } else {
                RootTabView()
            }
        }
        .dynamicTypeSize(.xSmall)
        .task {
            await checkForAvailableUpdateIfNeeded()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task {
                await checkForAvailableUpdateIfNeeded()
            }
        }
        .alert(item: $updateInfo) { info in
            Alert(
                title: Text("LifeOS 有新版本"),
                message: Text("App Store 上已经有 \(info.version) 版本。更新后可以使用最新修复和体验改进。"),
                primaryButton: .default(Text("去 App Store")) {
                    openURL(info.storeURL)
                },
                secondaryButton: .cancel(Text("稍后"))
            )
        }
    }

    private func checkForAvailableUpdateIfNeeded() async {
        guard !didCheckUpdateThisSession else { return }
        didCheckUpdateThisSession = true
        guard let info = await AppUpdateService.availableUpdate() else { return }
        await MainActor.run {
            updateInfo = info
        }
    }
}

private struct RuntimeSplashView: View {
    var body: some View {
        ZStack {
            Color(red: 0.984, green: 0.969, blue: 0.937)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Image("LaunchCatFlower")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 212, height: 249)

                Text("LifeOS")
                    .font(.custom("Georgia-Bold", size: 38))
                    .foregroundStyle(Color(red: 0.128, green: 0.165, blue: 0.115))

                Text("观察生活，记录生活")
                    .font(.system(size: 14))
                    .tracking(3.2)
                    .foregroundStyle(Color(red: 0.235, green: 0.651, blue: 0.361))
            }
            .offset(y: -32)
        }
    }
}
