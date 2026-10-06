// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "LunchDraw", platforms: [.macOS(.v14)], products: [.executable(name: "lunch-draw", targets: ["LunchDraw"])], targets: [.executableTarget(name: "LunchDraw")], swiftLanguageModes: [.v5])
