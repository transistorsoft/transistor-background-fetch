// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TSBackgroundFetch",
    platforms: [.iOS(.v12)],
    products: [.library(name: "TSBackgroundFetch", targets: ["TSBackgroundFetch"])],
    targets: [
        .binaryTarget(
            name: "TSBackgroundFetch",
            url: "https://github.com/transistorsoft/transistor-background-fetch/releases/download/4.0.0/TSBackgroundFetch.xcframework.zip",
            checksum: "9fc330e01bcd837f773f21267aebf8d3bc58c7b0599e53e9b2fe94d44e76ec35"
        )
    ]
)
