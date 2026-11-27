//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import SwiftExtract
import Testing

/// Properties without a type annotation are extracted when their initial value decides the type
/// without type checking, and skipped otherwise (https://github.com/swiftlang/swift-java/issues/539).
@Suite("Inferred property types")
struct InferredPropertyTypeSuite {
  let source = """
    public enum Style {
      case linear
      case custom(Int)
    }
    public struct Metadata {
      public var count: Int = 0
    }
    public struct Token {
      public init(raw: String) {}
      public init?(checked: String) {}
      public init(validating: String) throws {}
    }
    public class Box {
      public init(size: Int = 1) {}
    }

    public struct Event {
      public struct Payload {}

      // Inferred
      public let integer = 1
      public let negative = -1
      public let double = 1.5
      public let text = "text"
      public let flag = true
      public let style = Style.linear
      public let customStyle = Style.custom(2)
      public let metadata = Metadata()
      public let memberwise = Metadata(count: 2)
      public let token = Token(raw: "a")
      public let box = Box()
      public let sizedBox = Box(size: 2)
      public let payload = Payload()
      public static let empty = Self()

      // Not inferred
      public let failable = Token(checked: "a")
      public let throwing = Token(validating: "a")
      public let parsed = Int("1")
      public let url = URL(string: "https://swift.org")
      public let computed = makeValue()
      public let unknownCase = Style.missing
    }
    """

  func getterTypes() throws -> [String: String] {
    let result = try analyze(sources: [("/fake/Source.swift", source)], moduleName: "Events")
    let event = try #require(result.extractedTypes["Event"])
    var types: [String: String] = [:]
    for variable in event.variables where variable.apiKind == .getter {
      types[variable.name] = "\(variable.functionSignature.result.type)"
    }
    return types
  }

  @Test func unambiguousInitialValuesAreInferred() throws {
    let types = try getterTypes()
    #expect(types["integer"] == "Int")
    #expect(types["negative"] == "Int")
    #expect(types["double"] == "Double")
    #expect(types["text"] == "String")
    #expect(types["flag"] == "Bool")
    #expect(types["style"] == "Style")
    #expect(types["customStyle"] == "Style")
    #expect(types["metadata"] == "Metadata")
    #expect(types["memberwise"] == "Metadata")
    #expect(types["token"] == "Token")
    #expect(types["box"] == "Box")
    #expect(types["sizedBox"] == "Box")
    #expect(types["payload"] == "Event.Payload")
    #expect(types["empty"] == "Event")
  }

  @Test func initialValuesThatMayHaveAnotherTypeAreSkipped() throws {
    let types = try getterTypes()
    for name in ["failable", "throwing", "parsed", "url", "computed", "unknownCase"] {
      #expect(types[name] == nil, "\(name) was inferred as \(types[name] ?? "")")
    }
  }
}
