// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "XML",
    products: [.library(name: "XML", targets: ["XML"])],
    targets:  [.target(name: "XML", path: "swiftxml"), 
               .testTarget(name: "XMLTests", dependencies: ["XML"], path: "tests/swiftxml")
                ],
    swiftLanguageVersions: [4]
)
