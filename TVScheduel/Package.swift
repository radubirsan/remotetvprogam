// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TVScheduel",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "tvepg", targets: ["TVScheduelCLI"]),
        .library(name: "TVScheduel", targets: ["TVScheduel"])
    ],
    targets: [
        .target(
            name: "TVScheduel",
            path: "Sources/TVScheduel"
        ),
        .executableTarget(
            name: "TVScheduelCLI",
            dependencies: ["TVScheduel"],
            path: "Sources/TVScheduelCLI"
        ),
        .testTarget(
            name: "TVScheduelTests",
            dependencies: ["TVScheduel"],
            path: "Tests/TVScheduelTests"
        )
    ]
)
