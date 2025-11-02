import XCTest
@testable import DeadCodeAnalysis

final class AllowListFilterTests: XCTestCase {
  func testAllowsFunctionFromProjectModule() {
    let symbol = "$s15QuGame_DeadCode6WidgetV7doThingyyF"
    XCTAssertTrue(shouldKeepSymbol(symbol, allowedSuffixes: allowListSuffixes, allowedModules: ["QuGame_DeadCode"]))
  }

  func testFiltersDisallowedSuffix() {
    let symbol = "$s15QuGame_DeadCode16TrayView_PreviewVWOc"
    XCTAssertFalse(shouldKeepSymbol(symbol, allowedSuffixes: allowListSuffixes, allowedModules: ["QuGame_DeadCode"]))
  }

  func testFiltersAllowedSuffixFromOtherModule() {
    let symbol = "$s21DeveloperToolsSupport13ImageResourceV15QuGame_DeadCodeE4MUMEACvgZ"
    XCTAssertFalse(shouldKeepSymbol(symbol, allowedSuffixes: allowListSuffixes, allowedModules: ["QuGame_DeadCode"]))
  }
}
