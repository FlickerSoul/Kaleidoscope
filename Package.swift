// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "Kaleidoscope",
    platforms: [.macOS(.v13), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .macCatalyst(.v13)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Kaleidoscope",
            targets: ["Kaleidoscope"]
        ),
        .executable(
            name: "KaleidoscopeClient",
            targets: ["KaleidoscopeClient"]
        ),
    ],
    dependencies: [
        // Depend on the Swift 5.9 release of SwiftSyntax
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0"),
        .package(url: "https://github.com/apple/swift-collections.git", .upToNextMajor(from: "1.0.5")),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        // Macro implementation that performs the source transformation of a macro.
        .macro(
            name: "KaleidoscopeMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                "KaleidoscopeLexer",
            ],
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-enable-experimental-string-processing"])]
        ),
        .target(name: "KaleidoscopeLexer"),
        // Library that exposes a macro as part of its API, which is used in client programs.
        .target(name: "Kaleidoscope", dependencies: ["KaleidoscopeMacros", "KaleidoscopeLexer"]),
        // A client of the library, which is able to use the macro in its own code.
        .executableTarget(name: "KaleidoscopeClient", dependencies: ["Kaleidoscope"]),

        // A test target used to develop the macro implementation.
        .testTarget(
            name: "KaleidoscopeTests",
            dependencies: [
                "KaleidoscopeMacros",
                "Kaleidoscope",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
