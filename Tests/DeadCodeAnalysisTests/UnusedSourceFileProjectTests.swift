import Foundation
import XCTest
@testable import DeadCodeAnalysis

final class UnusedSourceFileProjectTests: XCTestCase {
  func testAnalyzesUnusedSourceFileProject() throws {
    let debugURL = try XCTUnwrap(
      Bundle.module.url(
        forResource: "DCD_UnusedSourceFile_Debug",
        withExtension: "linkermap",
        subdirectory: "Projects/DCD_UnusedSourceFile/linkermap"
      ),
      "Missing debug link map fixture"
    )
    let releaseURL = try XCTUnwrap(
      Bundle.module.url(
        forResource: "DCD_UnusedSourceFile_Release",
        withExtension: "linkermap",
        subdirectory: "Projects/DCD_UnusedSourceFile/linkermap"
      ),
      "Missing release link map fixture"
    )

    let debugMap = try parseLinkMap(at: debugURL)
    let releaseMap = try parseLinkMap(at: releaseURL)
    let config = Configuration(
      debugURL: debugURL,
      releaseURL: releaseURL,
      projectRoot: nil,
      demangle: false,
      groupLimit: 0,
      outputURL: nil,
      verbose: false,
      sourcePrefixes: []
    )

    let result = analyze(debug: debugMap, release: releaseMap, config: config)

    XCTAssertEqual(result.unusedSymbols.count, 1)
    XCTAssertEqual(result.unusedSymbols.first?.name, "_$ss31_stdlib_isOSVersionAtLeast_AEICyBi1_Bw_BwBwtF")
    XCTAssertEqual(result.unusedObjects.map(\.baseName), ["GeneratedAssetSymbols.o"])
  }
}
