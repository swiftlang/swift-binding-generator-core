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

/// Extracts every declaration, except that the types in `unexported` aren't exported
/// and extensions of unresolved types have no extractable members unless `mayExtractExtensions`.
private struct ExportControlDecider: ExtractDecider {
  var unexported: Set<String> = []
  var mayExtractExtensions = true

  func shouldExtract(decl: DeclSyntax, in parent: ExtractedNominalType?) -> Bool {
    true
  }

  func isExported(_ type: SwiftNominalTypeDeclaration) -> Bool {
    !unexported.contains(type.name)
  }

  func mayExtractMembers(of extensionDecl: ExtensionDeclSyntax) -> Bool {
    mayExtractExtensions
  }
}

@Suite("Export control")
struct ExportControlSuite {

  @Test func declarationsUsingUnexportedTypesAreSkipped() throws {
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
      extractDecider: ExportControlDecider(unexported: ["Secret"]),
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
    #expect(reasons.allSatisfy { $0 == "uses 'Secret', which is not exported" })
  }

  @Test func everythingExtractsWhenAllTypesAreExported() throws {
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
      extractDecider: ExportControlDecider()
    )

    #expect(Set(result.extractedGlobalFuncs.map(\.name)) == ["reveal", "hoard"])
  }

  @Test(arguments: [true, false])
  func unresolvedExtensionIsReportedOnlyIfMembersMayBeExtracted(mayExtractExtensions: Bool) throws {
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
      extractDecider: ExportControlDecider(mayExtractExtensions: mayExtractExtensions),
      diagnosticsSink: sink
    )

    let skipped = sink.diagnostics.map(\.declarationName)
    #expect(skipped == (mayExtractExtensions ? ["extension Missing"] : []))
  }

  @Test func knownModuleSourceIsRecognized() throws {
    let int = try #require(SwiftKnownModule.swift.symbolTable.lookupTopLevelNominalType("Int"))
    #expect(int.syntax.isFromKnownModuleSource)
    let url = try #require(SwiftKnownModule.foundation.symbolTable.lookupTopLevelNominalType("URL"))
    #expect(url.syntax.isFromKnownModuleSource)

    let source = Parser.parse(source: "public struct Int {}")
    #expect(!source.isFromKnownModuleSource)
    #expect(!source.statements.first!.isFromKnownModuleSource)
  }
}
