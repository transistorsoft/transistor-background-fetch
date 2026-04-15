// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TSBackgroundFetch",
    platforms: [.iOS(.v12)],
    products: [.library(name: "TSBackgroundFetch", targets: ["TSBackgroundFetch"])],
    targets: [
        .binaryTarget(
            name: "TSBackgroundFetch",
            url: "https://github.com/transistorsoft/transistor-background-fetch/releases/download/4.1.0/TSBackgroundFetch.xcframework.zip",
            checksum: "4f7c13839330f5dec4ee763729efd9604a1e6e1b9e3c02cb42beadf590e4e75f"
        )
    ]
)
