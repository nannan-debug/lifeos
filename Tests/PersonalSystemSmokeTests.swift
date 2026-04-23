import XCTest
@testable import PersonalSystem

final class PersonalSystemSmokeTests: XCTestCase {
    func testAppStoreInitialStateLoads() {
        let store = AppStore()

        XCTAssertNotNil(store.selectedDate)
        XCTAssertGreaterThanOrEqual(store.checkItems.count, 0)
    }
}
