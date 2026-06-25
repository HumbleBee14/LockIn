import Foundation
import os

enum LockInLog {
    private static let log = Logger(subsystem: "com.humblebee.lockin", category: "lockin")

    static func info(_ message: String) {
        log.info("\(message, privacy: .public)")
        FileHandle.standardError.write(Data("[LockIn] \(message)\n".utf8))
    }

    static func error(_ message: String, _ error: Error? = nil) {
        let detail = error.map { e -> String in
            let ns = e as NSError
            return " — \(ns.domain) \(ns.code): \(ns.localizedDescription)"
        } ?? ""
        log.error("\(message, privacy: .public)\(detail, privacy: .public)")
        FileHandle.standardError.write(Data("[LockIn] ERROR \(message)\(detail)\n".utf8))
    }
}
