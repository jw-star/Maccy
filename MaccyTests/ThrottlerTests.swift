import XCTest
@testable import Maccy

class ThrottlerTests: XCTestCase {
  func testRunsImmediatelyWhenMinimumDelayHasPassed() {
    let throttler = Throttler(minimumDelay: 10)
    let runExpectation = expectation(description: "Block is run")

    throttler.throttle {
      runExpectation.fulfill()
    }

    waitForExpectations(timeout: 1)
  }

  func testDelaysRunWithinMinimumDelay() {
    let throttler = Throttler(minimumDelay: 10)
    let firstRunExpectation = expectation(description: "First block is run")
    throttler.throttle {
      firstRunExpectation.fulfill()
    }
    wait(for: [firstRunExpectation], timeout: 1)

    let secondRunExpectation = expectation(description: "Second block is run")
    secondRunExpectation.isInverted = true
    throttler.throttle {
      secondRunExpectation.fulfill()
    }
    wait(for: [secondRunExpectation], timeout: 1)
    throttler.cancel()
  }

  func testCancelsPendingRun() {
    let throttler = Throttler(minimumDelay: 0.5)
    let firstRunExpectation = expectation(description: "First block is run")
    throttler.throttle {
      firstRunExpectation.fulfill()
    }
    wait(for: [firstRunExpectation], timeout: 1)

    let replacedRunExpectation = expectation(description: "Replaced block is run")
    replacedRunExpectation.isInverted = true
    let lastRunExpectation = expectation(description: "Last block is run")
    throttler.throttle {
      replacedRunExpectation.fulfill()
    }
    throttler.throttle {
      lastRunExpectation.fulfill()
    }
    wait(for: [replacedRunExpectation, lastRunExpectation], timeout: 2)
  }
}
