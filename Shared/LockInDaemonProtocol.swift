import Foundation

@objc protocol LockInDaemonProtocol {
    func getVersion(reply: @escaping (String) -> Void)
    func registerSchedule(_ data: Data, reply: @escaping (Bool) -> Void)
    func getStatus(reply: @escaping (Data?) -> Void)
    func startQuickLock(blockSetIds: [String], durationSeconds: Double, reply: @escaping (String?) -> Void)
    func appendDomainsToActiveBlock(_ domains: [String], reply: @escaping (Bool) -> Void)
    func appendDomainsReturningReason(_ domains: [String], reply: @escaping (String?) -> Void)
    func appendDomains(_ domains: [String], toBlockSetId blockSetId: String, reply: @escaping (String?, Date?) -> Void)
    func resetHostsToDefault(reply: @escaping (Bool) -> Void)
    func prepareUninstall(reply: @escaping (Bool) -> Void)
}
