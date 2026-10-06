// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hankki",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "hankki", targets: ["Hankki"])],
    targets: [.executableTarget(name: "Hankki")]
)
