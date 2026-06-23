import SwiftUI

@main
struct LockInApp: App {
    var body: some Scene {
        WindowGroup {
            OnboardingView()
                .frame(width: 360, height: 220)
        }
    }
}
