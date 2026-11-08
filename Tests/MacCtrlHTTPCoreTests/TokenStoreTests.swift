import Foundation
import XCTest
@testable import MacCtrlHTTPCore

final class TokenStoreTests: XCTestCase {
    func testTokenPersistsAcrossStoreInstancesAndCanBeCleared() throws {
        let suiteName = "MacCtrlHTTPTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstLaunchStore = UserDefaultsTokenStore(defaults: defaults)
        try firstLaunchStore.save("unit-test-token")

        let nextLaunchStore = UserDefaultsTokenStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        XCTAssertEqual(try nextLaunchStore.load(), "unit-test-token")

        try nextLaunchStore.save("")
        XCTAssertNil(try firstLaunchStore.load())
    }

    func testDeviceAddressPersistsAcrossStoreInstances() throws {
        let suiteName = "MacCtrlHTTPAddressTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstLaunchStore = UserDefaultsDeviceAddressStore(defaults: defaults)
        try firstLaunchStore.save("cubic.local")

        let nextLaunchStore = UserDefaultsDeviceAddressStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        XCTAssertEqual(try nextLaunchStore.load(), "cubic.local")
    }
}
