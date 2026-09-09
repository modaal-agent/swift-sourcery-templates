//
//  ReturnTypeOverloadMocksSpec.swift
//
//  Tests that verify mock generation for refining protocols that override an
//  inherited method with a different return type. Without the return-type
//  discriminator in MockMethod, generation fails with
//  "Mock generator: not all duplicates resolved" because the long-name
//  disambiguation cannot tell the two `data()` overloads apart (same name,
//  same empty parameter list).
//
//  Mirrors the Firebase iOS SDK's `QueryDocumentSnapshot : DocumentSnapshot`
//  shape — the canonical real-world use case driving this template feature.
//

import Foundation
import Quick
import Nimble
@testable import ExampleProjectSpm

class ReturnTypeOverloadMocksSpec: QuickSpec {
  override static func spec() {

    // MARK: - DocumentSnapshotting (parent — no overload, no discriminator)

    describe("DocumentSnapshottingMock") {
      var sut: DocumentSnapshottingMock!
      beforeEach {
        sut = DocumentSnapshottingMock()
      }

      it("mocks the optional data() with a single (undecorated) handler") {
        sut.dataHandler = { ["name": "Alice"] }
        let result = sut.data()
        expect(result?["name"] as? String) == "Alice"
        expect(sut.dataCallCount) == 1
      }

      it("returns nil by default when no handler is set") {
        let result = sut.data()
        expect(result).to(beNil())
      }
    } // describe DocumentSnapshottingMock

    // MARK: - QueryDocumentSnapshotting (refining — both overloads must be mocked)

    describe("QueryDocumentSnapshottingMock") {
      var sut: QueryDocumentSnapshottingMock!
      beforeEach {
        sut = QueryDocumentSnapshottingMock()
      }

      it("mocks both data() overloads with distinct return-type-discriminated handlers") {
        // Optional override (inherited from parent).
        sut.dataStringAnyOptionalHandler = { ["from": "optional"] }
        // Non-optional override (declared on the refining protocol).
        sut.dataStringAnyHandler = { ["from": "non-optional"] }

        // The non-optional `data()` resolves under the refining-protocol typing.
        let typed: QueryDocumentSnapshotting = sut
        let nonOptional: [String: Any] = typed.data()
        expect(nonOptional["from"] as? String) == "non-optional"

        // The optional `data()` resolves under the parent-protocol upcast.
        let upcast: DocumentSnapshotting = sut
        let optional: [String: Any]? = upcast.data()
        expect(optional?["from"] as? String) == "optional"

        expect(sut.dataStringAnyCallCount) == 1
        expect(sut.dataStringAnyOptionalCallCount) == 1
      }

      it("call counts track each overload independently") {
        sut.dataStringAnyHandler = { [:] }
        sut.dataStringAnyOptionalHandler = { nil }

        let typed: QueryDocumentSnapshotting = sut
        _ = typed.data() as [String: Any]
        _ = typed.data() as [String: Any]

        let upcast: DocumentSnapshotting = sut
        _ = upcast.data()

        expect(sut.dataStringAnyCallCount) == 2
        expect(sut.dataStringAnyOptionalCallCount) == 1
      }
    } // describe QueryDocumentSnapshottingMock

    // MARK: - RequiredIDProviding (refining with primitive return type)

    describe("RequiredIDProvidingMock") {
      var sut: RequiredIDProvidingMock!
      beforeEach {
        sut = RequiredIDProvidingMock()
      }

      it("mocks both id() overloads with distinct discriminated handlers") {
        sut.idStringOptionalHandler = { "optional-id" }
        sut.idStringHandler = { "required-id" }

        let typed: RequiredIDProviding = sut
        let nonOptional: String = typed.id()
        expect(nonOptional) == "required-id"

        let upcast: OptionalIDProviding = sut
        let optional: String? = upcast.id()
        expect(optional) == "optional-id"

        expect(sut.idStringCallCount) == 1
        expect(sut.idStringOptionalCallCount) == 1
      }
    } // describe RequiredIDProvidingMock

  }
}
