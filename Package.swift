// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "markdown_swift",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .executable(name: "mdviewer", targets: ["mdviewer"]),
    ],
    dependencies: [
        // AST-based Markdown parsing (CommonMark + extensions where supported)
        .package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "mdviewer",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
            ]
        ),
    ]
)

