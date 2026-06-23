import XCTest
@testable import LockInDaemonCore

final class EngineLinkTests: XCTestCase {
    func testCanInstantiatePacketFilter() {
        let pf = PacketFilter(asAllowlist: false)
        XCTAssertNotNil(pf)
    }
    func testCanInstantiateHostFileBlockerSet() {
        let set = HostFileBlockerSet()
        XCTAssertNotNil(set)
    }
}
