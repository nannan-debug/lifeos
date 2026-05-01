import SwiftUI

@main
struct PersonalSystemApp: App {
    var body: some Scene {
        WindowGroup {
            FirstRunLaunchGate {
                RootTabView()
            }
        }
    }
}
