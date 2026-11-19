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
import SwiftParser
import SwiftSyntax
import Testing

/// Extracts every declaration, except that the types in `unextracted` aren't extracted
/// and members of extensions of unresolved types are extracted only if `extractsExtensionMembers`.
private struct ExtractionControlDecider: ExtractDecider {
  var unextracted: Set<String> = []
  var extractsExtensionMembers = true

  func shouldExtract(decl: DeclSyntax, in parent: ExtractedNominalType?) -> Bool {
    true
  }

  func shouldExtract(decl: DeclSyntax, in extensionDecl: ExtensionDeclSyntax) -> Bool {
    extractsExtensionMembers
  }

  func isExtracted(_ type: SwiftNominalTypeDeclaration) -> Bool {
    !unextracted.contains(type.name)
  }
}

@Suite("Extraction control")
struct ExtractionControlSuite {

  @Test func declarationsUsingUnextractedTypesAreSkipped() throws {
    let sink = CollectingDiagnosticsSink()
    let result = try SwiftAnalyzer.analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public struct Secret {}
          public struct Visible {}

          public func show(_ visible: Visible) {}
          public func reveal() -> Secret { fatalError() }
          public func hoard(_ secrets: [Secret]) {}
          public func whisper(_ listener: (Secret) -> Void) {}

          public enum Box {
            case plain(Int)
            case hidden(Secret)
          }

          public class Holder {
            public init() {}
            public init(secret: Secret) {}
            public var secret: Secret { fatalError() }
          }
          """
        )
      ],
      moduleName: "Aquarium",
      extractDecider: ExtractionControlDecider(unextracted: ["Secret"]),
      diagnosticsSink: sink
    )

    #expect(result.extractedGlobalFuncs.map(\.name) == ["show"])
    #expect(result.extractedTypes["Box"]?.cases.map(\.name) == ["plain"])
    let holder = try #require(result.extractedTypes["Holder"])
    #expect(holder.initializers.map(\.functionSignature.parameters.count) == [0])
    #expect(holder.variables.isEmpty)

    // reveal, hoard, whisper, Box.hidden, Holder.init(secret:), Holder.secret
    let reasons = sink.diagnostics.map { String(describing: $0.underlyingError!) }
    #expect(reasons.count == 6)
    #expect(reasons.allSatisfy { $0 == "uses 'Secret', which is not extracted" })
  }

  @Test func everythingExtractsWhenAllTypesAreExtracted() throws {
    let result = try SwiftAnalyzer.analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public struct Secret {}
          public func reveal() -> Secret { fatalError() }
          public func hoard(_ secrets: [Secret]) {}
          """
        )
      ],
      moduleName: "Aquarium",
      extractDecider: ExtractionControlDecider()
    )

    #expect(Set(result.extractedGlobalFuncs.map(\.name)) == ["reveal", "hoard"])
  }

  @Test(arguments: [true, false])
  func unresolvedExtensionIsReportedOnlyIfMembersShouldBeExtracted(extractsExtensionMembers: Bool) throws {
    let sink = CollectingDiagnosticsSink()
    _ = try SwiftAnalyzer.analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          extension Missing {
            public func swim() {}
          }
          """
        )
      ],
      moduleName: "Aquarium",
      extractDecider: ExtractionControlDecider(extractsExtensionMembers: extractsExtensionMembers),
      diagnosticsSink: sink
    )

    let skipped = sink.diagnostics.map(\.declarationName)
    #expect(skipped == (extractsExtensionMembers ? ["extension Missing"] : []))
  }

  @Test func knownModuleSourceIsRecognized() throws {
    let int = Syntax(fromProtocol: try #require(SwiftKnownModule.swift.symbolTable.lookupTopLevelNominalType("Int")).syntax)
    #expect(SwiftKnownModule.swift.contains(int))
    #expect(!SwiftKnownModule.foundation.contains(int))
    let url = Syntax(fromProtocol: try #require(SwiftKnownModule.foundation.symbolTable.lookupTopLevelNominalType("URL")).syntax)
    #expect(SwiftKnownModule.foundation.contains(url))
    #expect(!SwiftKnownModule.swift.contains(url))

    let source = Parser.parse(source: "public struct Int {}")
    #expect(!SwiftKnownModule.swift.contains(source))
    #expect(!SwiftKnownModule.swift.contains(source.statements.first!))
  }
}
