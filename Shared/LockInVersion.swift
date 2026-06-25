import Foundation

enum LockInVersion {
    // invariant: bump on any XPC protocol change so ping() rejects a stale daemon
    static let current = "0.0.2"
}
