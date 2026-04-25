// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CropEasy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CropEasy", targets: ["CropEasy"])
    ],
    targets: [
        .executableTarget(
            name: "CropEasy",
            path: "Sources"
        )
    ]
)
