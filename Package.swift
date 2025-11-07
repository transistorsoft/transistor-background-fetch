// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TSBackgroundFetch",
    platforms: [.iOS(.v12)],
    products: [.library(name: "TSBackgroundFetch", targets: ["TSBackgroundFetch"])],
    targets: [
        .binaryTarget(
            name: "TSBackgroundFetch",
            url: "https://github.com/transistorsoft/transistor-background-fetch/releases/download/4.0.3/TSBackgroundFetch.xcframework.zip",
            checksum: "e0eb7583ef32cf1e8b5e1463751ce1d2ef437561b5a21125487240708ad3c6e2"
        )
    ]
)
