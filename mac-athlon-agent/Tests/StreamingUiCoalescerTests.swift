import XCTest
@testable import AthlonAgent

final class StreamingUiCoalescerTests: XCTestCase {
    func testScheduleFlush_coalescesBursts() async {
        let expectation = expectation(description: "flush")
        expectation.expectedFulfillmentCount = 1
        var flushCount = 0
        let coalescer = StreamingUiCoalescer(intervalMilliseconds: 40) {
            flushCount += 1
            expectation.fulfill()
        }

        coalescer.scheduleFlush()
        coalescer.scheduleFlush()
        coalescer.scheduleFlush()

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(flushCount, 1)
        coalescer.cancel()
    }

    func testFlushNow_firesImmediately() {
        var flushCount = 0
        let coalescer = StreamingUiCoalescer(intervalMilliseconds: 32) {
            flushCount += 1
        }

        coalescer.scheduleFlush()
        coalescer.flushNow()
        XCTAssertEqual(flushCount, 1)
        coalescer.cancel()
    }
}
