// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "AppleTrace",
    platforms: [
        .iOS(.v13),
        .macOS(.v11),
    ],
    products: [
        .library(name: "AppleTrace", targets: ["AppleTrace"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        // The existing Objective-C++ trace core, reused from the Xcode tree.
        .target(
            name: "CAppleTrace"
        ),

        // Swift surface: idiomatic wrappers + the @Traced / @TraceAll macros.
        .target(
            name: "AppleTrace",
            dependencies: ["CAppleTrace", "AppleTraceMacrosPlugin"]
        ),

        // SwiftSyntax compiler plugin implementing the macros.
        .macro(
            name: "AppleTraceMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),

        .testTarget(
            name: "AppleTraceTests",
            dependencies: [
                "AppleTrace",
                "AppleTraceMacrosPlugin",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
