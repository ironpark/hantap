// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "hantap",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "hantap",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
            ]
        ),
    ]
)
