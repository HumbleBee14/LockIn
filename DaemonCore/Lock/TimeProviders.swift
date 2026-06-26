import Foundation

protocol TrustedTimeSource { func fetch() -> Date? }

// current UTC: online when reachable (tamper cross-check), else system clock. injectable for tests.
protocol NowProvider { func now() -> Date }

struct SystemNowProvider: NowProvider {
    private let trusted: TrustedTimeSource?
    init(trusted: TrustedTimeSource? = nil) { self.trusted = trusted }
    func now() -> Date { trusted?.fetch() ?? Date() }
}
