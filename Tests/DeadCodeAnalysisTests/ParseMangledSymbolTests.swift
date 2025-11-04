import XCTest
@testable import DeadCodeAnalysis

final class ParseMangledSymbolTests: XCTestCase {
  func testParseMangledSymbolExtractsPrefixSegmentsAndSuffix() {
    let symbol = "$s21DeveloperToolsSupport13ImageResourceV15QuGame_DeadCodeE4MUMEACvgZ"
    let parts = parseMangledSymbol(symbol)
    XCTAssertEqual(parts.prefix, "$s")
    XCTAssertEqual(parts.segments, ["DeveloperToolsSupport", "ImageResource", "QuGame_DeadCode", "MUME"])
    XCTAssertEqual(parts.suffix, "VEACvgZ")
  }

  func testParseMangledSymbolHandlesExtensionAsyncAccessor() {
    let symbol = "$s21DeveloperToolsSupport13ImageResourceV15QuGame_DeadCodeE10pop200X273ACvau"
    let parts = parseMangledSymbol(symbol)
    XCTAssertEqual(parts.prefix, "$s")
    XCTAssertEqual(parts.segments, ["DeveloperToolsSupport", "ImageResource", "QuGame_DeadCode", "pop200X273"])
    XCTAssertEqual(parts.suffix, "VEACvau")
  }

  func testParseMangledSymbolWithoutTrailingSuffix() {
    let symbol = "$s4Test5ThingV"
    let parts = parseMangledSymbol(symbol)
    XCTAssertEqual(parts.prefix, "$s")
    XCTAssertEqual(parts.segments, ["Test", "Thing"])
    XCTAssertEqual(parts.suffix, "V")
  }

  func testExtractModuleNameForStdlibSymbol() {
    let symbol = "_$ss31_stdlib_isOSVersionAtLeast_AEICyBi1_Bw_BwBwtF"
    let module = extractModuleName(fromMangled: symbol)
    XCTAssertTrue(module?.hasPrefix("_stdlib") == true)
  }
}
