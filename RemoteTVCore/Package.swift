// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RemoteTVCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RemoteTVCore", targets: ["RemoteTVCore"]),
    ],
    targets: [
        .target(
            name: "RemoteTVCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
