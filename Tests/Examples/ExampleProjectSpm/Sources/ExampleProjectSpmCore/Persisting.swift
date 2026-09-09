//
//  Persisting.swift
//  ExampleProjectSpmCore
//
//  A module `ExampleProjectSpmTests` reaches only through `ExampleProjectSpm`.
//  Nothing here is annotated: the point is that a protocol *refining* this one,
//  one module away, generates a mock that has to carry these requirements too.
//  Before the plugin derived its own source closure there was no
//  `SOURCERY_TARGET_*` var naming this directory, so there was no way to write a
//  config that scanned it — the pitfall CONTRIBUTING describes as surfacing only
//  in a consumer's build.
//

import Foundation

public protocol Persisting {
    func save(_ data: Data, key: String) throws
}
