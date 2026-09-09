import XCTest
@testable import App

// `ProfilePersistingMock` is generated into `App` from the closure App reaches:
// `profileID` is App's, `cacheLimit` is Middle's, `save` is Leaf's and `report`
// is ExternalKit's. A mock missing any of them does not compile.
final class AppTests: XCTestCase {
  func testMockCarriesEveryInheritedRequirement() throws {
    let mock = ProfilePersistingMock()
    mock.profileID = "id"
    try mock.save("value", key: "key")
    mock.report("message")
    XCTAssertEqual(mock.saveCallCount, 1)
    XCTAssertEqual(mock.reportCallCount, 1)
    XCTAssertEqual(acceptProfilePersisting(mock), "id")
  }
}
