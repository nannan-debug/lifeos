import SwiftUI

@main
struct PersonalSystemApp: App {
    var body: some Scene {
        WindowGroup {
            SplashRootView()
        }
    }
}

private struct SplashRootView: View {
    @State private var showingSplash = true

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
