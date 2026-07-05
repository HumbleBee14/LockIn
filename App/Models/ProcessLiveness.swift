import Foundation
import Darwin

enum ProcessLiveness {
    private static let maxPathSize = 4096

    static func isRunning(executableSuffix: String) -> Bool {
        var count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.size)
        count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let n = Int(count) / MemoryLayout<pid_t>.size
        var buf = [CChar](repeating: 0, count: maxPathSize)
        for i in 0..<n where pids[i] != 0 {
            let len = proc_pidpath(pids[i], &buf, UInt32(buf.count))
            guard len > 0 else { continue }
            let path = String(decoding: buf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) },
                              as: UTF8.self)
            if path.hasSuffix(executableSuffix) { return true }
        }
        return false
    }
}
