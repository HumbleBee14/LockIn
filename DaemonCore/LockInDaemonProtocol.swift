import Foundation

@objc protocol LockInDaemonProtocol {
    func getVersion(reply: @escaping (String) -> Void)
}
