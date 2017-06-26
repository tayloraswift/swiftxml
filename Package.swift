// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "XML",
    products:  [.library(name: "XML", targets: ["XML"]),
                .executable(name: "tests", targets: ["XMLTests"])],
    targets:   [.target(name: "XML", path: "swiftxml"),
                .target(name: "XMLTests", dependencies: ["XML"], path: "tests/swiftxml")
               ],
    swiftLanguageVersions: [4]
)
