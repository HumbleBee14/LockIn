import SwiftUI
import ServiceManagement

@main
struct LockInApp: App {
    @StateObject private var installer = InstallerService()

    var body: some Scene {
        WindowGroup {
            Group {
                if installer.daemonStatus == .enabled {
                    RootView()
                } else {
                    OnboardingView()
                }
            }
            .frame(minWidth: 760, minHeight: 520)
            .preferredColorScheme(.dark)
            .onAppear { installer.refreshStatus() }
        }
        .windowStyle(.titleBar)
    }
}
