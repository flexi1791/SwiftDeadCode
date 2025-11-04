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
    guard let object = debugData.objects[safe: symbol.objectIndex] ?? nil, !shouldIgnoreObject(object) else {
      return true
    }
    return !isUserSymbol(symbol.name)
  }
  
  releaseData.symbols.removeAll { symbol in
    guard let object = releaseData.objects[safe: symbol.objectIndex] ?? nil, !shouldIgnoreObject(object) else {
      return true
    }
    return !isUserSymbol(symbol.name)
  }
  
  // Step 3: attach the remaining debug and release symbols to their owning objects.
  for symbol in debugData.symbols {
    guard var object = debugData.objects[safe: symbol.objectIndex] ?? nil else { continue }
    object.debugSymbols.append(symbol)
    debugData.objects[symbol.objectIndex] = object
  }
  
  for symbol in releaseData.symbols {
    guard var object = releaseData.objects[safe: symbol.objectIndex] ?? nil else { continue }
    object.releaseSymbolNames.insert(symbol.name)
    releaseData.objects[symbol.objectIndex] = object
  }
  let objectIndicesInDebug = Set(
    debugData.objects.enumerated().compactMap { (offset, object) -> Int? in
      object != nil ? offset : nil
    }
  )
  let objectIndicesInRelease = Set(
    releaseData.objects.enumerated().compactMap { (offset, object) -> Int? in
      object != nil ? offset : nil
    }
  )
  let objectIndices = objectIndicesInDebug.union(objectIndicesInRelease)
  
  // Step 5: compute debug-only symbols by removing anything that also appears in release.
  var debugOnlySymbolsByObject: [Int: [SymbolRecord]] = [:]
  for index in objectIndices {
    let debugSymbols = debugData.objects[index]?.debugSymbols ?? []
    let releaseNames = releaseData.objects[index]?.releaseSymbolNames ?? []
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
  
  for symbols in debugOnlySymbolsByObject.values {
    for var symbol in symbols {
      if let demangled = demangledMap[symbol.name] {
        if shouldIgnoreDemangledSymbol(demangled) {
          continue
        }
        symbol.demangled = cleanDemangledName(demangled, modulesToStrip: [])
      }
      unusedSymbols.append(symbol)
    }
  }
  
  unusedSymbols.sort(by: SymbolRecord.reportComparator(using: debugData.objects))
  
  // Step 7: collect debug objects that ended up without any debug-only symbols.
  var unusedObjects: [ObjectRecord] = []
  for object in debugData.objects.compactMap({ $0 }) {
    let releaseObject = releaseData.objects[safe: object.index] ?? nil
    if releaseObject == nil {
      unusedObjects.append(object)
    }
  }
  
  unusedObjects.sort()
  
  return AnalysisResult(
    totalDebugSymbols: totalDebugSymbols,
    totalReleaseSymbols: totalReleaseSymbols,
    unusedSymbols: unusedSymbols,
    debugObjects: debugData.objects,
    unusedObjects: unusedObjects
  )
}
