//
//  SwiftSourceryTemplatesTests.swift
//  SwiftSourceryTemplatesTests
//
//  Created by Ivan Misuno on 18/07/2018.
//  Copyright © 2018 AlbumPrinter BV. All rights reserved.
//

import Foundation
import Quick
import Nimble
import RxSwift
@testable import ExampleProjectSpm

class SwiftSourceryTemplatesMocksSpec: QuickSpec {
  override static func spec() {
    describe("UploadProgressingMock") {
      var sut: UploadProgressingMock!
      beforeEach {
        sut = UploadProgressingMock()
      }
      it("progressGetCount == 0") {
        expect(sut.progressGetCount) == 0
      }
    } // describe("UploadProgressingMock")

    describe("InteractableMock") {
      var sut: InteractableMock!
      beforeEach {
        sut = InteractableMock()
      }
      it("activateCallCount == 0") {
        expect(sut.activateCallCount) == 0
      }
    } // describe("InteractableMock")

    describe("mock with AnyObserver") {
      var sut: SomeEntityBindableMock!
      beforeEach {
        sut = SomeEntityBindableMock()
      }
      describe("entityObserver() called on the mock") {
        beforeEach {
          _ = sut.entityObserver()
        }
        it("entityObserver call count increases") {
          expect(sut.entityObserverCallCount) == 1
        }
        context("entityObserver.on() called") {
          beforeEach {
            sut.entityObserver().onNext("next element")
          }
          it("entityObserverEvent call count increased") {
            expect(sut.entityObserverEventCallCount) == 1
          }
          // The count says an event arrived; the recorder says which one.
          // Asserting the value took a handler appending into a local array
          // before `<name>Events`, and no spec in the reference consumer did
          // that for any member (spec 004 §1.9, D13). `Event` declares no
          // `Equatable` conformance, so the value is read through
          // `compactMap(\.element)` rather than compared whole.
          it("entityObserverEvents records the element that was pushed in") {
            expect(sut.entityObserverEvents.compactMap(\.element)) == ["next element"]
          }
        } // context("entityObserver.on() called")
      }
    } // describe("mock with AnyObserver")

    // The transitive first-party case. `ProfilePersisting` refines `Persisting`,
    // which lives in ExampleProjectSpmCore — a module this test target reaches
    // only through ExampleProjectSpm, and which no SOURCERY_TARGET_* var names.
    // Before the plugin derived its own source closure the generated mock
    // carried `profileID` and not `save`, and this file did not compile.
    describe("mock of a protocol refining another module's protocol") {
      var sut: ProfilePersistingMock!
      beforeEach {
        sut = ProfilePersistingMock()
      }
      it("starts with no recorded calls") {
        expect(sut.saveCallCount) == 0
        expect(sut.saveArgs).to(beEmpty())
      }
      context("save() called with the inherited requirement's signature") {
        beforeEach {
          try? sut.save(Data([0x01, 0x02]), key: "profile")
        }
        it("records the call") {
          expect(sut.saveCallCount) == 1
        }
        it("records both arguments") {
          expect(sut.saveArgs.count) == 1
          expect(sut.saveArgs.first?.data) == Data([0x01, 0x02])
          expect(sut.saveArgs.first?.key) == "profile"
        }
      } // context("save() called")
      it("still carries the refining protocol's own requirement") {
        sut._profileID = "abc"
        expect(sut.profileID) == "abc"
      }
    } // describe("mock of a protocol refining another module's protocol")
  }
}
