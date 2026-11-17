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

/// Extracts every declaration, except those using a type in `unavailable`, and extracts
/// an extension of an unresolved type only if `extractsExtensions`.
private struct ExtractionControlDecider: ExtractDecider {
  var unavailable: Set<String> = []
  var extractsExtensions = true

  func shouldExtract(decl: DeclSyntax, in parent: ExtractedNominalType?) -> Bool {
    true
  }

  func shouldExtract(extension extensionDecl: ExtensionDeclSyntax) -> Bool {
    extractsExtensions
  }

  func shouldExtract(declarationUsing type: SwiftNominalTypeDeclaration) -> Bool {
    !unavailable.contains(type.name)
  }
}

/// Records what it's asked about. Extracts every declaration, and an extension of an unresolved
/// type only if `extractsExtension` returns `true` for it.
private final class RecordingDecider: ExtractDecider {
  let extractsExtension: (ExtensionDeclSyntax) -> Bool
  private(set) var askedExtensions: [ExtensionDeclSyntax] = []
  private(set) var askedDecls: [DeclSyntax] = []

  init(extractsExtension: @escaping (ExtensionDeclSyntax) -> Bool) {
    self.extractsExtension = extractsExtension
  }

  func shouldExtract(decl: DeclSyntax, in parent: ExtractedNominalType?) -> Bool {
    askedDecls.append(decl)
    return true
  }

  func shouldExtract(decl: DeclSyntax, in extension: ExtensionDeclSyntax) -> Bool {
    askedDecls.append(decl)
    return true
  }

  func shouldExtract(extension extensionDecl: ExtensionDeclSyntax) -> Bool {
    askedExtensions.append(extensionDecl)
    return extractsExtension(extensionDecl)
  }
}

/// Extracts an unresolved extension, but only the members of it named in `members`.
private struct MemberFilteringDecider: ExtractDecider {
  var members: Set<String>

  func shouldExtract(decl: DeclSyntax, in parent: ExtractedNominalType?) -> Bool {
    true
  }

  func shouldExtract(decl: DeclSyntax, in extension: ExtensionDeclSyntax) -> Bool {
    guard let function = decl.as(FunctionDeclSyntax.self) else {
      return true
    }
    return members.contains(function.name.text)
  }
}

@Suite("Extraction control")
struct ExtractionControlSuite {

  @Test func declarationUsingUnavailableTypesAreSkipped() throws {
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
      extractDecider: ExtractionControlDecider(unavailable: ["Secret"]),
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
    #expect(reasons.allSatisfy { $0 == "uses 'Secret', which is not available to the generated code" })
  }

  @Test func everythingExtractsWhenAllTypesAreAvailable() throws {
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
  func unresolvedExtensionIsReportedOnlyIfItShouldBeExtracted(extractsExtensions: Bool) throws {
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
      extractDecider: ExtractionControlDecider(extractsExtensions: extractsExtensions),
      diagnosticsSink: sink
    )

    let skipped = sink.diagnostics.map(\.declarationName)
    #expect(skipped == (extractsExtensions ? ["extension Missing"] : []))
  }

  /// An extension that only adds a conformance has no members to decide on, so the decider decides
  /// for the extension itself: it can be reported, or ignored (as in a target that exports only
  /// annotated declarations).
  @Test(arguments: [true, false])
  func conformanceOnlyUnresolvedExtensionIsUpToTheDecider(extractsExtensions: Bool) throws {
    let sink = CollectingDiagnosticsSink()
    _ = try SwiftAnalyzer.analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol Labelable {}
          extension Missing: Labelable {}
          """
        )
      ],
      moduleName: "Aquarium",
      extractDecider: ExtractionControlDecider(extractsExtensions: extractsExtensions),
      diagnosticsSink: sink
    )

    let skipped = sink.diagnostics.map(\.declarationName)
    #expect(skipped == (extractsExtensions ? ["extension Missing"] : []))
  }

  /// The decider sees the conformances of an unresolved extension, so one whose members wouldn't be
  /// extracted can still be reported for the conformance it adds instead of dropping it silently.
  @Test func unresolvedExtensionCanBeReportedForItsConformance() throws {
    let sink = CollectingDiagnosticsSink()
    _ = try SwiftAnalyzer.analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol Labelable {}
          extension Missing: Labelable {
            func helper() {}
          }
          extension AlsoMissing {
            func helper() {}
          }
          """
        )
      ],
      moduleName: "Aquarium",
      extractDecider: RecordingDecider { $0.inheritanceClause != nil },
      diagnosticsSink: sink
    )

    #expect(sink.diagnostics.map(\.declarationName) == ["extension Missing"])
  }

  /// The decider is asked once, about the extension as written, including `#if` blocks and macro
  /// expansions, and not about its members one by one.
  @Test func deciderIsAskedOnceAboutTheWholeUnresolvedExtension() throws {
    let decider = RecordingDecider { _ in false }
    _ = try SwiftAnalyzer.analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          extension Missing {
            #if os(macOS)
            public func macOnly() {}
            #endif
            #fishFood()
            public func swim() {}
          }
          """
        )
      ],
      moduleName: "Aquarium",
      extractDecider: decider
    )

    #expect(decider.askedExtensions.count == 1)
    let memberKinds = decider.askedExtensions.first?.memberBlock.members.map(\.decl.kind)
    #expect(memberKinds == [.ifConfigDecl, .macroExpansionDecl, .functionDecl])
    let askedFunctions = decider.askedDecls.compactMap { $0.as(FunctionDeclSyntax.self)?.name.text }
    #expect(!askedFunctions.contains("macOnly"))
    #expect(!askedFunctions.contains("swim"))
  }

  /// The members of an accepted unresolved extension are decided one by one, and only the accepted
  /// ones are kept in the recorded extension.
  @Test func membersOfUnresolvedExtensionAreDecidedOneByOne() throws {
    let result = try SwiftAnalyzer.analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          extension Missing {
            public func swim() {}
            public func sink() {}
          }
          """
        )
      ],
      moduleName: "Aquarium",
      extractDecider: MemberFilteringDecider(members: ["swim"])
    )

    let recorded = try #require(result.crossModuleExtensions.unresolved.first)
    let kept = recorded.syntax.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self)?.name.text }
    #expect(kept == ["swim"])
  }

  /// A member of an unresolved extension inherits the access level of the extension unless it has its own.
  @Test func defaultDeciderUsesAccessLevelOfExtensionForItsMembers() throws {
    func extractedMembers(of source: String, accessLevel: AccessLevelMode) -> [String] {
      let decider = DefaultAccessLevelExtractDecider(accessLevel: accessLevel)
      let file = Parser.parse(source: source)
      let ext = file.statements.first!.item.cast(ExtensionDeclSyntax.self)
      return ext.memberBlock.members.map(\.decl).compactMap { decl in
        decider.shouldExtract(decl: decl, in: ext) ? decl.cast(FunctionDeclSyntax.self).name.text : nil
      }
    }

    let publicExtension = "public extension Missing { func a() {}; private func b() {}; public func c() {} }"
    #expect(extractedMembers(of: publicExtension, accessLevel: .public) == ["a", "c"])

    let internalExtension = "extension Missing { func d() {}; public func e() {}; static func f() {} }"
    #expect(extractedMembers(of: internalExtension, accessLevel: .public) == ["e"])
    #expect(extractedMembers(of: internalExtension, accessLevel: .internal) == ["d", "e", "f"])
  }

  /// Only an extension whose extended type doesn't resolve is asked about. The members of a resolved
  /// extension are decided one by one with `shouldExtract(decl:in:)`.
  @Test func resolvedExtensionIsNotAskedAbout() throws {
    let decider = RecordingDecider { _ in false }
    let result = try SwiftAnalyzer.analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public struct Fish {}
          extension Fish {
            public func swim() {}
          }
          """
        )
      ],
      moduleName: "Aquarium",
      extractDecider: decider
    )

    #expect(decider.askedExtensions.isEmpty)
    #expect(result.extractedTypes["Fish"]?.methods.map(\.name) == ["swim"])
  }

  @Test func knownModuleSourceIsRecognized() throws {
    let int = Syntax(fromProtocol: try #require(SwiftKnownModule.swift.symbolTable.lookupTopLevelNominalType("Int")).syntax)
    #expect(SwiftKnownModule.swift.contains(int))
    #expect(!SwiftKnownModule.foundation.contains(int))
    let url = Syntax(fromProtocol: try #require(SwiftKnownModule.foundation.symbolTable.lookupTopLevelNominalType("URL")).syntax)
    #expect(SwiftKnownModule.foundation.contains(url))
    #expect(SwiftKnownModule.foundationEssentials.contains(url))
    #expect(!SwiftKnownModule.swift.contains(url))

    // A decider usually holds a nominal type's `syntax`, an existential. Outside a macro such as
    // `#expect` it's opened implicitly, so `contains(_:)` takes it as is.
    let intDecl = try #require(SwiftKnownModule.swift.symbolTable.lookupTopLevelNominalType("Int"))
    let swiftContainsInt = SwiftKnownModule.swift.contains(intDecl.syntax)
    #expect(swiftContainsInt)

    let source = Parser.parse(source: "public struct Int {}")
    #expect(!SwiftKnownModule.swift.contains(source))
    #expect(!SwiftKnownModule.swift.contains(source.statements.first!))
  }
}
