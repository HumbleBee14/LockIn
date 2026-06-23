import SwiftUI
import ServiceManagement

@main
struct LockInApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 760, minHeight: 520)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
    }
}
