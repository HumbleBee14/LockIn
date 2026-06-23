import SwiftUI
import ServiceManagement

@main
struct LockInApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 820, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
    }
}
