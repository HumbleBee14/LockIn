import Foundation

enum LockInVersion {
    // invariant: bump on any XPC protocol change so ping() rejects a stale daemon
    // (an older daemon is still kept while a lock is held — see DaemonClient.aliveForRegistration)
    static let current = "0.0.3"
}
