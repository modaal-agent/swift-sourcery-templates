//
//  EscapingClosureMocksSpec.swift
//
//  Tests that verify @escaping attribute preservation in generated mocks.
//  These tests will FAIL TO COMPILE if the mock template strips @escaping
//  from closure parameters, because:
//  - Capturing a non-escaping closure in a stored property is a compile error
//  - Dispatching a non-escaping closure to another queue is a compile error
//

import Foundation
import Quick
import Nimble
@testable import ExampleProjectSpm

class EscapingClosureMocksSpec: QuickSpec {
  override static func spec() {

    // MARK: - Completion handler: store and call later

    describe("EscapingClosureServiceMock — fetchData(completion:)") {
      var sut: EscapingClosureServiceMock!
      beforeEach {
        sut = EscapingClosureServiceMock()
      }

      it("completion can be stored and called asynchronously") {
        // The handler captures `completion` and dispatches it async.
        // This is a compile error if `completion` is not @escaping.
        sut.fetchDataHandler = { completion in
          DispatchQueue.main.async {
            completion("async result", nil)
          }
        }

        var receivedValue: String?
        sut.fetchData { value, _ in
          receivedValue = value
        }

        expect(receivedValue).toEventually(equal("async result"))
        expect(sut.fetchDataCallCount) == 1
      }

      it("completion can be stored in a property for later invocation") {
        var storedCompletion: ((_ value: String?, _ error: Error?) -> Void)?

        // Storing `completion` in an outer variable requires @escaping.
        sut.fetchDataHandler = { completion in
          storedCompletion = completion
        }

        sut.fetchData { _, _ in }

        expect(storedCompletion).toNot(beNil())
      }
    } // describe fetchData

    // MARK: - Listener pattern: capture and call multiple times

    describe("EscapingClosureServiceMock — addListener(_:)") {
      var sut: EscapingClosureServiceMock!
      beforeEach {
        sut = EscapingClosureServiceMock()
      }

      it("listener can be captured and called multiple times") {
        var capturedListener: ((String) -> Void)?

        // Capturing `listener` requires @escaping.
        sut.addListenerHandler = { listener in
          capturedListener = listener
          return NSObject()
        }

        var receivedValues: [String] = []
        _ = sut.addListener { value in
          receivedValues.append(value)
        }

        expect(capturedListener).toNot(beNil())

        capturedListener?("update-1")
        capturedListener?("update-2")
        capturedListener?("update-3")

        expect(receivedValues) == ["update-1", "update-2", "update-3"]
        expect(sut.addListenerCallCount) == 1
      }
    } // describe addListener

    // MARK: - Typealias'd closure: @escaping preserved

    describe("EscapingClosureServiceMock — observe(_:)") {
      var sut: EscapingClosureServiceMock!
      beforeEach {
        sut = EscapingClosureServiceMock()
      }

      it("typealias'd @escaping closure can be captured") {
        var capturedBlock: EscapingNotificationBlock?

        // Capturing `block` requires @escaping on the typealias'd parameter.
        sut.observeHandler = { block in
          capturedBlock = block
          return NSObject()
        }

        var receivedValue: String?
        _ = sut.observe { value in
          receivedValue = value
        }

        capturedBlock?("notification-payload")
        expect(receivedValue) == "notification-payload"
      }
    } // describe observe

    // MARK: - Mixed escaping/non-escaping parameters

    describe("EscapingClosureServiceMock — transform(input:using:completion:)") {
      var sut: EscapingClosureServiceMock!
      beforeEach {
        sut = EscapingClosureServiceMock()
      }

      it("@escaping completion can be dispatched async while non-escaping transformer is called sync") {
        // `transformer` is NOT @escaping — must be called synchronously.
        // `completion` IS @escaping — can be stored and called later.
        sut.transformHandler = { input, transformer, completion in
          let transformed = transformer(input)
          DispatchQueue.main.async {
            completion(transformed)
          }
        }

        var receivedValue: String?
        sut.transform(
          input: "hello",
          using: { $0.uppercased() },
          completion: { output in
            receivedValue = output
          }
        )

        expect(receivedValue).toEventually(equal("HELLO"))
        expect(sut.transformCallCount) == 1
      }
    } // describe transform

  }
}
