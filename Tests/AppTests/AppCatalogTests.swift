import XCTest
@testable import LockIn

final class AppCatalogTests: XCTestCase {
    func testMergeDedupesByBundleId() {
        let installed = [AppInfo(bundleId: "com.a", name: "A"), AppInfo(bundleId: "com.b", name: "B")]
        let running = [AppInfo(bundleId: "com.b", name: "B running"), AppInfo(bundleId: "com.c", name: "C")]
        let merged = AppCatalog.merge(installed: installed, running: running)
        XCTAssertEqual(merged.map { $0.bundleId }, ["com.a", "com.b", "com.c"])
    }

    func testMergeDropsEmptyBundleIds() {
        let merged = AppCatalog.merge(installed: [AppInfo(bundleId: "", name: "Ghost"),
                                                  AppInfo(bundleId: "com.real", name: "Real")], running: [])
        XCTAssertEqual(merged.map { $0.bundleId }, ["com.real"])
    }

    func testMergeSortsByNameCaseInsensitive() {
        let merged = AppCatalog.merge(installed: [AppInfo(bundleId: "com.z", name: "zebra"),
                                                  AppInfo(bundleId: "com.a", name: "Apple")], running: [])
        XCTAssertEqual(merged.map { $0.name }, ["Apple", "zebra"])
    }
}
