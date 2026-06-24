import Foundation

@MainActor
final class QuickLockDraft: ObservableObject {
    @Published var selectedBlockSetIds: Set<String> = []
    @Published var durationMinutes: Int = 10
    @Published var customMode = true
    @Published var customMinutes: Double = 10

    var effectiveMinutes: Int {
        customMode ? Int(customMinutes.rounded()) : durationMinutes
    }
}
