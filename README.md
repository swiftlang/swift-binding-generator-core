# swift-binding-generator-core

Language-neutral core libraries for building Swift binding generators: tools that analyze Swift sources and generate bindings for calling Swift from other languages.

This package was split out of [swift-java](https://github.com/swiftlang/swift-java), where the `SwiftExtract` library powers the `jextract-swift` tool. It is consumed by swift-java and other language binding generators (e.g. swift-python) that need to analyze Swift sources in order to generate foreign language bindings calling into the analyzed Swift code.

## Products

- `SwiftExtract`: analyzes Swift source files and extracts the declarations (types, functions, global variables) that should be exposed to another language, along with a symbol table and type lookup facilities. Built on [swift-syntax](https://github.com/swiftlang/swift-syntax).
- `SwiftExtractConfigurationShared`: small shared configuration enums (`AccessLevelMode`, `LogLevel`) used by binding generator plugins and tools.

## Depending on this package

Add the dependency to your `Package.swift`:

```swift
.package(url: "https://github.com/swiftlang/swift-binding-generator-core", from: "0.1.0"),
```

and depend on the product you need:

```swift
.product(name: "SwiftExtract", package: "swift-binding-generator-core"),
```

### Local development override

Downstream packages (such as swift-java) support overriding this dependency with a local checkout by setting the `SWIFT_BINDING_GENERATOR_CORE_PATH` environment variable to a local path:

```bash
SWIFT_BINDING_GENERATOR_CORE_PATH=~/code/swift-binding-generator-core swift build
```

## Development

This repository is developed alongside [swift-java](https://github.com/swiftlang/swift-java), its primary consumer. A non-blocking CI job builds and tests the latest swift-java against every pull request to catch source breaks early; it can also be triggered manually with `workflow_dispatch` against a specific swift-java branch.

## License

Copyright (c) 2024-2026 Apple Inc. and the Swift project authors. Licensed under Apache License v2.0 with Runtime Library Exception. See [LICENSE.txt](LICENSE.txt) for more information.
