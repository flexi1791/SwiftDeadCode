// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "DeadCodeAnalysis",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(
      name: "DeadCodeAnalysis",
      targets: ["DeadCodeAnalysis"]
    ),
    .executable(
      name: "dead-code-analysis",
      targets: ["DeadCodeAnalysisCLI"]
    )
  ],
  targets: [
    .target(
      name: "DeadCodeAnalysis",
      path: "Sources/DeadCodeAnalysis",
      exclude: [],
      swiftSettings: [
        .define("DEAD_CODE_ANALYSIS_PACKAGE")
      ]
    ),
    .executableTarget(
      name: "DeadCodeAnalysisCLI",
      dependencies: ["DeadCodeAnalysis"],
      path: "Sources/DeadCodeAnalysisCLI"
    ),
    .testTarget(
      name: "DeadCodeAnalysisTests",
      dependencies: ["DeadCodeAnalysis"],
      path: "Tests",
      sources: ["DeadCodeAnalysisTests"],
      resources: [
        .copy("Projects")
      ]
    )
  ]
)
