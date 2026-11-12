// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BrewDesktop",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BrewDesktop",
            path: "Sources/BrewDesktop"
        ),
        .testTarget(
            name: "BrewDesktopTests",
            dependencies: ["BrewDesktop"],
            path: "Tests/BrewDesktopTests"
        ),
    ]
)
