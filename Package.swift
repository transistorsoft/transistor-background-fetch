// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TSBackgroundFetch",
    platforms: [.iOS(.v12)],
    products: [.library(name: "TSBackgroundFetch", targets: ["TSBackgroundFetch"])],
    targets: [
        .binaryTarget(
            name: "TSBackgroundFetch",
            url: "https://github.com/transistorsoft/transistor-background-fetch/releases/download/4.0.4/TSBackgroundFetch.xcframework.zip",
            checksum: "863e86a458776484b45af0d4a7079d667b7aa4930d09d5387e6fdabf54ff3743"
        )
    ]
)
