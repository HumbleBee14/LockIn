import Foundation
import CommonCrypto

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

// .pinned requires an SPKI pin per host and fails closed without one; .systemTrust uses standard TLS.
enum TimeTrustPolicy { case pinned, systemTrust }

final class PinnedTrustedTimeSource: NSObject, TrustedTimeSource, URLSessionDelegate {
    private let hosts: [URL]
    private let pinnedSHA256: [String: [String]]
    private let policy: TimeTrustPolicy
    private let agreementTolerance: TimeInterval = 30
    private let perRequestTimeout: TimeInterval = 4

    init(hosts: [URL], pinnedSHA256: [String: [String]] = [:], policy: TimeTrustPolicy = .pinned) {
        self.hosts = hosts
        self.pinnedSHA256 = pinnedSHA256
        self.policy = policy
    }

    func fetch() -> Date? {
        let samples = hosts.compactMap { fetchDateHeader(from: $0) }
        guard samples.count >= 2 else { return nil }
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        let agreeing = samples.filter { abs($0.timeIntervalSince(median)) <= agreementTolerance }
        guard agreeing.count >= 2 else { return nil }
        return median
    }

    private func fetchDateHeader(from url: URL) -> Date? {
        if policy == .pinned, pinnedSHA256[url.host ?? ""]?.isEmpty != false { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = perRequestTimeout
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        var result: Date?
        let sem = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { _, response, _ in
            defer { sem.signal() }
            guard let http = response as? HTTPURLResponse,
                  let dateString = http.value(forHTTPHeaderField: "Date") else { return }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            result = formatter.date(from: dateString)
        }.resume()
        _ = sem.wait(timeout: .now() + perRequestTimeout + 1)
        session.invalidateAndCancel()
        return result
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let host = challenge.protectionSpace.host as String? else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        if let pins = pinnedSHA256[host], !pins.isEmpty {
            let ok = Self.trust(trust, matchesAnyPin: pins)
            completionHandler(ok ? .useCredential : .cancelAuthenticationChallenge,
                              ok ? URLCredential(trust: trust) : nil)
        } else if policy == .systemTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private static func trust(_ trust: SecTrust, matchesAnyPin pins: [String]) -> Bool {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first,
              let key = SecCertificateCopyKey(leaf),
              let spki = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            return false
        }
        let hash = SHA256.hash(of: spki)
        return pins.contains(hash)
    }
}

enum TrustedTime {
    static func system() -> PinnedTrustedTimeSource {
        PinnedTrustedTimeSource(
            hosts: [URL(string: "https://www.cloudflare.com")!,
                    URL(string: "https://www.apple.com")!],
            pinnedSHA256: [:],
            policy: .systemTrust)
    }
}

private enum SHA256 {
    static func hash(of data: Data) -> String {
        var ctx = CC_SHA256_CTX()
        CC_SHA256_Init(&ctx)
        data.withUnsafeBytes { _ = CC_SHA256_Update(&ctx, $0.baseAddress, CC_LONG(data.count)) }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &ctx)
        return Data(digest).base64EncodedString()
    }
}
