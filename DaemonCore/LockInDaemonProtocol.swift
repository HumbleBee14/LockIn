import Foundation

@objc protocol LockInDaemonProtocol {
    func getVersion(reply: @escaping (String) -> Void)
    func registerSchedule(_ data: Data, reply: @escaping (Bool) -> Void)
    func getStatus(reply: @escaping (Data?) -> Void)
    func startAdHocBlock(blockSetId: String, durationSeconds: Double, reply: @escaping (Bool) -> Void)
}
