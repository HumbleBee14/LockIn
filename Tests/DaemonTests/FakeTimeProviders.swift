import Foundation
@testable import LockInDaemonCore

final class FakeWallClock: WallClock { var now: Date; init(_ d: Date) { now = d } }
final class FakeMonotonicClock: MonotonicClock { var seconds: Double; init(_ s: Double) { seconds = s } }
final class FakeBootSession: BootSession { var uuid: String; init(_ u: String) { uuid = u } }
final class FakeTrustedTimeSource: TrustedTimeSource {
    var value: Date?
    init(_ d: Date?) { value = d }
    func fetch() -> Date? { value }
}
