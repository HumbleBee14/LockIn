import Foundation
import CommonCrypto

// .pinned requires an SPKI pin per host and fails closed without one; .systemTrust uses standard TLS.
enum TimeTrustPolicy { case pinned, systemTrust }

// @unchecked Sendable: the mutable cache below is guarded by `lock`, so cross-thread access is safe
final class PinnedTrustedTimeSource: NSObject, TrustedTimeSource, URLSessionDelegate, @unchecked Sendable {
    private let hosts: [URL]
    private let pinnedSHA256: [String: [String]]
    private let policy: TimeTrustPolicy
    private let agreementTolerance: TimeInterval = 30
    private let perRequestTimeout: TimeInterval = 4
    private let cacheValidity: TimeInterval = 120

    // fetch() never blocks: reads come from a cache a background task refreshes. cache age uses the local
    // clock — fine, it only decides freshness of the sample, not the expiry decision.
    private let lock = NSLock()
    private var cachedSample: (date: Date, takenAt: Date)?
    private var refreshing = false

    init(hosts: [URL], pinnedSHA256: [String: [String]] = [:], policy: TimeTrustPolicy = .pinned) {
        self.hosts = hosts
        self.pinnedSHA256 = pinnedSHA256
        self.policy = policy
    }

    func fetch() -> Date? {
        refreshInBackgroundIfNeeded()
        lock.lock(); defer { lock.unlock() }
        guard let s = cachedSample else { return nil }
        let elapsed = Date().timeIntervalSince(s.takenAt)
        guard elapsed >= 0, elapsed <= cacheValidity else { return nil }
        return s.date.addingTimeInterval(elapsed)
    }

    private func refreshInBackgroundIfNeeded() {
        lock.lock()
        if refreshing { lock.unlock(); return }
        refreshing = true
        lock.unlock()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let sample = self.fetchConsensus()
            let takenAt = Date()
            self.lock.lock()
            if let sample { self.cachedSample = (sample, takenAt) }
            self.refreshing = false
            self.lock.unlock()
        }
    }

    private func fetchConsensus() -> Date? {
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
    // .pinned rejects admin-installed-root-CA MITM (the threat actor is the local admin). If every host's
    // pin is stale we simply get no online sample and fall back to the system clock (offline behavior).
    static func system() -> PinnedTrustedTimeSource {
        PinnedTrustedTimeSource(
            hosts: [URL(string: "https://www.cloudflare.com")!,
                    URL(string: "https://www.apple.com")!],
            pinnedSHA256: [
                "www.cloudflare.com": ["InW7U3grEKRuwhErwsI/XULSUbEWmteQprf4vp8Oo7Y="],
                "www.apple.com": ["tkhcoCq9fS0kxe9haZp9eTXk4I3DHivWzpKuZ20xLL8="]
            ],
            policy: .pinned)
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
