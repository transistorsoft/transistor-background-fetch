// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TSBackgroundFetch",
    platforms: [.iOS(.v12)],
    products: [.library(name: "TSBackgroundFetch", targets: ["TSBackgroundFetch"])],
    targets: [
        .binaryTarget(
            name: "TSBackgroundFetch",
            url: "https://github.com/transistorsoft/transistor-background-fetch/releases/download/4.0.2/TSBackgroundFetch.xcframework.zip",
            checksum: "89252bce2a1945d37525f9d08d2dc22fd9d774d9dd51cc396be439b1e51f75cb"
        )
    ]
)
