// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VCAMNEXTPRO",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .executable(
            name: "VCAMNEXTPRO",
            targets: ["VCAMNEXTPRO"]
        )
    ],
    targets: [
        .executableTarget(
            name: "VCAMNEXTPRO",
            path: "VCAMNEXTPRO"
        )
    ]
)
