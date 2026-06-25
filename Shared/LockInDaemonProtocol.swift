import Foundation

@objc protocol LockInDaemonProtocol {
    func getVersion(reply: @escaping (String) -> Void)
    func registerSchedule(_ data: Data, reply: @escaping (Bool) -> Void)
    func getStatus(reply: @escaping (Data?) -> Void)
    func startQuickLock(blockSetIds: [String], durationSeconds: Double, reply: @escaping (Bool) -> Void)
    func appendDomainsToActiveBlock(_ domains: [String], reply: @escaping (Bool) -> Void)
    func resetHostsToDefault(reply: @escaping (Bool) -> Void)
    func prepareUninstall(reply: @escaping (Bool) -> Void)
}
