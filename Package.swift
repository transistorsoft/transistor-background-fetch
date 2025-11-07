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
            checksum: "a2e1ae30a096d91429ac1691f8a6a4b4676172cc481157822a87c3eaff97a830"
        )
    ]
)
