import Foundation

protocol WallClock { var now: Date { get } }
protocol MonotonicClock { var seconds: Double { get } }
protocol BootSession { var uuid: String { get } }
protocol TrustedTimeSource { func fetch() -> Date? }
