// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TSBackgroundFetch",
    platforms: [.iOS(.v12)],
    products: [.library(name: "TSBackgroundFetch", targets: ["TSBackgroundFetch"])],
    targets: [
        .binaryTarget(
            name: "TSBackgroundFetch",
            url: "https://github.com/transistorsoft/transistor-background-fetch/releases/download/4.0.6/TSBackgroundFetch.xcframework.zip",
            checksum: "06a120bb1183218d2c02e4286d2d8943dd29555dc2b22d733427e17f6ecaba74"
        )
    ]
)
