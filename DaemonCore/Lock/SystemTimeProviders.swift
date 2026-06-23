import Foundation

struct SystemWallClock: WallClock {
    var now: Date { Date() }
}

struct SystemMonotonicClock: MonotonicClock {
    var seconds: Double {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let t = mach_continuous_time()
        let nanos = Double(t) * Double(info.numer) / Double(info.denom)
        return nanos / 1_000_000_000.0
    }
}

struct SystemBootSession: BootSession {
    var uuid: String {
        var size = 0
        sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.bootsessionuuid", &buf, &size, nil, 0)
        return String(cString: buf)
    }
}

struct PinnedTrustedTimeSource: TrustedTimeSource {
    let hosts: [URL]
    func fetch() -> Date? {
        return nil
    }
}
