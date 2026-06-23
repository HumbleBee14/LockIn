import Foundation

@objc protocol LockInAgentProtocol {
    func updateSnapshot(_ data: Data, reply: @escaping (Bool) -> Void)
}
