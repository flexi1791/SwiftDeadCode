import Foundation

// MARK: - Analysis Pipeline

/// Produces the final analysis by contrasting debug-only symbols with release data.
/// - Parameters:
///   - debug: Parsed link-map information from the debug build.
///   - release: Parsed link-map information from the release build.
///   - config: Runtime configuration influencing filtering and reporting.
/// - Returns: The computed `AnalysisResult` containing unused symbols and debug-only file entries.
func analyze(debug: LinkMapData, release: LinkMapData, config: Configuration) -> AnalysisResult {
  var debugData = debug
  var releaseData = release

  let totalDebugSymbols = debugData.symbols.count
  let totalReleaseSymbols = releaseData.symbols.count

  func userObject(at index: Int, in objects: [ObjectRecord?]) -> ObjectRecord? {
    guard index >= 0, index < objects.count else { return nil }
    return objects[index]
  }

  func isUserSymbol(_ name: String) -> Bool {
    shouldKeepSymbol(name, allowedSuffixes: allowListSuffixes)
  }

  // Step 1: drop ignored objects directly from the parsed link-map listings.
  for index in debugData.objects.indices {
    if let object = debugData.objects[index], shouldIgnoreObject(object) {
      debugData.objects[index] = nil
    }
  }

  for index in releaseData.objects.indices {
    if let object = releaseData.objects[index], shouldIgnoreObject(object) {
      releaseData.objects[index] = nil
    }
  }

  // Step 2: discard symbols that do not belong to user-owned objects or fail the allow list.
  debugData.symbols.removeAll { symbol in
    guard let object = userObject(at: symbol.objectIndex, in: debugData.objects), !shouldIgnoreObject(object) else {
      return true
    }
    return !isUserSymbol(symbol.name)
  }

  releaseData.symbols.removeAll { symbol in
    guard let object = userObject(at: symbol.objectIndex, in: releaseData.objects), !shouldIgnoreObject(object) else {
      return true
    }
    return !isUserSymbol(symbol.name)
  }

  // Step 3: group remaining debug symbols by object for the release comparison.
  var debugSymbolsByObject: [Int: [SymbolRecord]] = [:]
  for symbol in debugData.symbols {
    debugSymbolsByObject[symbol.objectIndex, default: []].append(symbol)
  }

  // Step 4: catalog release symbols to subtract from the debug set.
  var releaseSymbolsByObject: [Int: Set<String>] = [:]
  for symbol in releaseData.symbols {
    releaseSymbolsByObject[symbol.objectIndex, default: []].insert(symbol.name)
  }

  let objectIndicesInDebug = Set(debugSymbolsByObject.keys)
  let objectIndicesInRelease = Set(
    releaseData.objects.enumerated().compactMap { (offset, object) -> Int? in
      object != nil ? offset : nil
    }
  )
  let objectIndices = objectIndicesInDebug.union(objectIndicesInRelease)

  // Step 5: compute debug-only symbols by removing anything that also appears in release.
  var debugOnlySymbolsByObject: [Int: [SymbolRecord]] = [:]
  for index in objectIndices {
    let debugSymbols = debugSymbolsByObject[index] ?? []
    let releaseNames = releaseSymbolsByObject[index] ?? []
    let unmatched = debugSymbols.filter { !releaseNames.contains($0.name) }
    if !unmatched.isEmpty {
      debugOnlySymbolsByObject[index] = unmatched
    }
  }

  let demangledMap: [String: String]
  if config.demangle {
    let symbolsToDemangle = debugOnlySymbolsByObject.values.flatMap { $0.map(\.name) }
    demangledMap = demangleSymbols(symbolsToDemangle, verbose: config.verbose)
  } else {
    demangledMap = [:]
  }

  // Step 6: finalize the per-symbol list after demangled noise filtering.
  var unusedSymbols: [SymbolRecord] = []
  var unusedSize: UInt64 = 0

  for symbols in debugOnlySymbolsByObject.values {
    for var symbol in symbols {
      if let demangled = demangledMap[symbol.name] {
        if shouldIgnoreDemangledSymbol(demangled) {
          continue
        }
        symbol.demangled = cleanDemangledName(demangled, modulesToStrip: [])
      }
  unusedSymbols.append(symbol)
  unusedSize &+= symbol.size
    }
  }

  unusedSymbols.sort { lhs, rhs in
    let lhsObject = userObject(at: lhs.objectIndex, in: debugData.objects)
    let rhsObject = userObject(at: rhs.objectIndex, in: debugData.objects)
    let lhsDisplay = lhsObject?.path ?? lhs.name
    let rhsDisplay = rhsObject?.path ?? rhs.name
    if lhsDisplay.caseInsensitiveCompare(rhsDisplay) != .orderedSame {
      return lhsDisplay.caseInsensitiveCompare(rhsDisplay) == .orderedAscending
    }
    if lhs.size != rhs.size {
      return lhs.size > rhs.size
    }
    let lhsName = lhs.demangled ?? lhs.name
    let rhsName = rhs.demangled ?? rhs.name
    return lhsName < rhsName
  }

  // Step 7: collect objects that appear unused in the release build.
  var unusedObjects: [ObjectRecord] = []
  for index in objectIndices {
    guard let releaseObject = userObject(at: index, in: releaseData.objects) else { continue }
    let releaseHasSymbols = !(releaseSymbolsByObject[index]?.isEmpty ?? true)
    let hasDebugOnlySymbols = !(debugOnlySymbolsByObject[index]?.isEmpty ?? true)
    if !hasDebugOnlySymbols, !releaseHasSymbols {
      unusedObjects.append(releaseObject)
    }
  }

  unusedObjects.sort { lhs, rhs in
    lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
  }

  DeadCodeAnalysis.Logger.logVerbose(
    config.verbose,
    "Unused debug-only symbols: \(unusedSymbols.count) (\(formatBytes(unusedSize)))"
  )

  return AnalysisResult(
    totalDebugSymbols: totalDebugSymbols,
    totalReleaseSymbols: totalReleaseSymbols,
    unusedSymbols: unusedSymbols,
    unusedSize: unusedSize,
    debugObjects: debugData.objects,
    unusedObjects: unusedObjects
  )
}
