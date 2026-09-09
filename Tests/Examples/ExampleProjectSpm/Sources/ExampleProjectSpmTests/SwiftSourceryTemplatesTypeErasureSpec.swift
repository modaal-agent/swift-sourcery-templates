//
//  File.swift
//  
//
//  Created by Ivan Misuno on 18/11/2023.
//

import Quick
import Nimble
import UIKit
import RxSwift
@testable import ExampleProjectSpm

enum ErrorEvent {
  case typeA
  case typeB
}

class MyErrorPresenter: ErrorPopoverPresentable {
  typealias EventType = ErrorEvent

  let subject = PublishSubject<EventType>()

  func show(relativeTo positioningRect: CGRect, of positioningView: UIView, preferredEdge: CGRectEdge) -> Observable<ErrorEvent> {
    return subject.asObservable()
  }
  
  func setActionSink(_ actionSink: AnyObject?) {
  }
}

class SwiftSourceryTemplatesTypeErasureSpec: QuickSpec {
  override static func spec() {
    var sut: AnyErrorPopoverPresentable<ErrorEvent>!
    beforeEach {
      sut = AnyErrorPopoverPresentable<ErrorEvent>(MyErrorPresenter())
    }
    it("") {
      //_ = sut.show(relativeTo: .zero, of: UIView(), preferredEdge: .maxXEdge)
    }
  }
}
