import XCTest
@testable import InventorySupport

final class InventoryOperationTrackerTests: XCTestCase {
    func testAdjustmentIdempotence() {
        var tracker = InventoryOperationTracker()
        let id = UUID()

        XCTAssertTrue(tracker.markAdjustment(id: id))
        XCTAssertFalse(tracker.markAdjustment(id: id))
    }

    func testMergeIdempotence() {
        var tracker = InventoryOperationTracker()
        let id = UUID()

        XCTAssertTrue(tracker.markMerge(id: id))
        XCTAssertFalse(tracker.markMerge(id: id))
    }

    func testResetAllowsReprocessing() {
        var tracker = InventoryOperationTracker()
        let id = UUID()

        XCTAssertTrue(tracker.markAdjustment(id: id))
        tracker.reset()
        XCTAssertTrue(tracker.markAdjustment(id: id))
    }
}
