// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TSBackgroundFetch",
    platforms: [.iOS(.v12)],
    products: [.library(name: "TSBackgroundFetch", targets: ["TSBackgroundFetch"])],
    targets: [
        .binaryTarget(
            name: "TSBackgroundFetch",
            url: "https://github.com/transistorsoft/transistor-background-fetch/releases/download/4.1.1/TSBackgroundFetch.xcframework.zip",
            checksum: "05702e657d4f307082ade707d8d0ae1eda55e112f42bf38febcb0230034c4860"
        )
    ]
)
