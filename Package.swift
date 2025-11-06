// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TSBackgroundFetch",
    platforms: [.iOS(.v12)],
    products: [.library(name: "TSBackgroundFetch", targets: ["TSBackgroundFetch"])],
    targets: [
        .binaryTarget(
            name: "TSBackgroundFetch",
            url: "https://github.com/transistorsoft/transistor-background-fetch/releases/download/4.0.1/TSBackgroundFetch.xcframework.zip",
            checksum: "b997559920a894f8993ef23f84fec6ccaf19de641678d337f0e0d5057c56fe99"
        )
    ]
)
