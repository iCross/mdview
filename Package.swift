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
        // Syntax highlighting (highlight.js via JavaScriptCore)
        .package(url: "https://github.com/raspu/Highlightr.git", branch: "master"),
    ],
    targets: [
        .executableTarget(
            name: "mdviewer",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Highlightr", package: "Highlightr"),
            ],
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
    ]
)

