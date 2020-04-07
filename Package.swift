// swift-tools-version:5.1

import PackageDescription

let package = Package(name: "Reactor",
                      platforms: [.macOS(.v10_12),
                                  .iOS(.v10),
                                  .tvOS(.v10),
                                  .watchOS(.v3)],
                      products: [.library(name: "Reactor",
                                          targets: ["Reactor"]),
                                          ],
                      targets: [.target(name: "Reactor",
                                        path: "Sources"),
                                .testTarget(name: "ReactorTests",
                                            dependencies: ["Reactor"],
                                            path: "Tests")],
                      swiftLanguageVersions: [.v5])