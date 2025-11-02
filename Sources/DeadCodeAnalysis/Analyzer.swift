import Foundation

// MARK: - Analysis Pipeline

/// Produces the final analysis by contrasting debug-only symbols with release data.
/// - Parameters:
///   - debug: Parsed link-map information from the debug build.
///   - release: Parsed link-map information from the release build.
///   - config: Runtime configuration influencing filtering and reporting.
/// - Returns: The computed `AnalysisResult` containing filtered symbols and debug-only file entries.
func analyze(debug: LinkMapData, release: LinkMapData, config: Configuration) -> AnalysisResult {
  var rawCount = 0
  var rawSize: UInt64 = 0
  var seen: Set<String> = []
  var objectHasReleaseSymbol: Set<String> = []
  var pendingCandidates: [CandidateSymbol] = []
  let resolvedSourceCount = debug.objects.values.reduce(into: 0) { count, object in
    if object.sourceURL != nil { count += 1 }
  }
  let requireSourceMatch = resolvedSourceCount > 8
  DeadCodeAnalysis.Logger.logVerbose(config.verbose, "Resolved object sources: \(resolvedSourceCount); requireSourceMatch=\(requireSourceMatch)")
  var skippedDuplicates = 0
  var skippedIgnoredObjects = 0
  var skippedNoSource = 0
  var skippedByFilter = 0
  var skippedDemangled = 0
  var missingSourceSamples: [String] = []
  var debugFootprint: [String: (size: UInt64, count: Int)] = [:]
  let projectModules = determineProjectModules(debug: debug, config: config)
  if config.verbose, !projectModules.isEmpty {
    DeadCodeAnalysis.Logger.logVerbose(config.verbose, "Detected project modules: \(projectModules.sorted().joined(separator: ", "))")
  }

  let debugObjects = debug.objects

  var releaseKeepableSymbols: Set<String> = []
  var releaseFootprintByPath: [String: (size: UInt64, count: Int)] = [:]
  var releaseFootprintByBaseName: [String: (size: UInt64, count: Int)] = [:]
  for symbol in release.symbols {
    if let object = release.objects[symbol.objectIndex] {
      let key = normalizeObjectPath(object.path)
      let pathFootprint = releaseFootprintByPath[key] ?? (0, 0)
      releaseFootprintByPath[key] = (pathFootprint.size &+ symbol.size, pathFootprint.count + 1)
      let baseKey = object.baseName
      let baseFootprint = releaseFootprintByBaseName[baseKey] ?? (0, 0)
      releaseFootprintByBaseName[baseKey] = (baseFootprint.size &+ symbol.size, baseFootprint.count + 1)
    }
    if shouldKeepSymbol(
      symbol.name,
      allowedSuffixes: allowListSuffixes,
      allowedModules: projectModules
    ) {
      releaseKeepableSymbols.insert(symbol.name)
    }
  }

  for symbol in debug.symbols {
    if !projectModules.isEmpty, let canonical = canonicalMangledName(symbol.name) {
      let moduleParts = parseMangledSymbol(canonical)
      if let module = moduleParts.segments.first, !module.isEmpty, !projectModules.contains(module) {
        continue
      }
    }

    let object = debugObjects[symbol.objectIndex]
    if let object {
      let key = normalizeObjectPath(object.path)
      let footprint = debugFootprint[key] ?? (0, 0)
      debugFootprint[key] = (footprint.size &+ symbol.size, footprint.count + 1)
      if releaseKeepableSymbols.contains(symbol.name) {
        objectHasReleaseSymbol.insert(key)
        continue
      }
    } else if releaseKeepableSymbols.contains(symbol.name) {
      continue
    }

    rawCount += 1
    rawSize &+= symbol.size

    if !seen.insert(symbol.name).inserted {
      skippedDuplicates += 1
      continue
    }

  if let object, shouldIgnoreObject(object) {
      skippedIgnoredObjects += 1
      continue
    }

    let hasSourceURL = object?.sourceURL != nil
    if requireSourceMatch && !hasSourceURL {
      skippedNoSource += 1
      if missingSourceSamples.count < 6 {
        if let objectPath = object?.path {
          missingSourceSamples.append(relativePath(for: URL(fileURLWithPath: objectPath), base: config.projectRoot))
        } else {
          missingSourceSamples.append(symbol.name)
        }
      }
      continue
    }

    pendingCandidates.append(CandidateSymbol(symbol: symbol, object: object))
  }

  DeadCodeAnalysis.Logger.logVerbose(config.verbose, "Candidate symbols after preliminary screening: \(pendingCandidates.count) (dup=\(skippedDuplicates), ignoredObject=\(skippedIgnoredObjects), noSource=\(skippedNoSource))")

  let modulesToStrip = inferProjectModules(from: pendingCandidates)
  var filteredCandidates: [CandidateSymbol] = []
  filteredCandidates.reserveCapacity(pendingCandidates.count)
  for candidate in pendingCandidates {
    if shouldKeepSymbol(
      candidate.symbol.name,
      allowedSuffixes: allowListSuffixes,
      allowedModules: projectModules
    ) {
      filteredCandidates.append(candidate)
    } else {
      skippedByFilter += 1
    }
  }

  DeadCodeAnalysis.Logger.logVerbose(config.verbose, "Candidates after allow-list filtering: \(filteredCandidates.count) (filteredOut=\(skippedByFilter))")
  if requireSourceMatch && !missingSourceSamples.isEmpty {
    DeadCodeAnalysis.Logger.logVerbose(config.verbose, "Sample objects with no source match: \(missingSourceSamples.joined(separator: ", "))")
  }

  if config.verbose, !modulesToStrip.isEmpty {
    DeadCodeAnalysis.Logger.logVerbose(config.verbose, "Stripping module prefixes: \(modulesToStrip.sorted().joined(separator: ", "))")
  }

  let demangledMap = demangleSymbols(filteredCandidates.map { $0.symbol.name }, verbose: config.verbose)
  DeadCodeAnalysis.Logger.logVerbose(config.verbose, "Demangled entries returned: \(demangledMap.count)")

  var filteredSymbols: [DebugOnlySymbol] = []
  var filteredSize: UInt64 = 0
  var interestingByObject: [String: (size: UInt64, count: Int, sourceURL: URL?)] = [:]

  for candidate in filteredCandidates {
    let demangledValue = demangledMap[candidate.symbol.name]
    if let demangledValue, shouldIgnoreDemangledSymbol(demangledValue) {
      skippedDemangled += 1
      continue
    }

    filteredSize &+= candidate.symbol.size
  var record = DebugOnlySymbol(symbol: candidate.symbol, object: candidate.object, demangled: nil)
    if config.demangle, let demangledValue {
      record.demangled = cleanDemangledName(demangledValue, modulesToStrip: modulesToStrip)
    }
    filteredSymbols.append(record)

    if let object = candidate.object {
      let key = normalizeObjectPath(object.path)
      let entry = interestingByObject[key] ?? (0, 0, candidate.object?.sourceURL)
      let chosenURL: URL?
      if let existing = entry.sourceURL {
        chosenURL = existing
      } else {
        chosenURL = candidate.object?.sourceURL
      }
      interestingByObject[key] = (
        entry.size &+ candidate.symbol.size,
        entry.count + 1,
        chosenURL
      )
    }
  }

  DeadCodeAnalysis.Logger.logVerbose(config.verbose, "Retained debug-only symbols: \(filteredSymbols.count) (filteredSize=\(formatBytes(filteredSize)), demangleFiltered=\(skippedDemangled))")

  filteredSymbols.sort { lhs, rhs in
    let lhsDisplay = lhs.object?.path ?? lhs.symbol.name
    let rhsDisplay = rhs.object?.path ?? rhs.symbol.name
    if lhsDisplay != rhsDisplay {
      return lhsDisplay < rhsDisplay
    }
    if lhs.symbol.size != rhs.symbol.size {
      return lhs.symbol.size > rhs.symbol.size
    }
    let lhsName = lhs.demangled ?? lhs.symbol.name
    let rhsName = rhs.demangled ?? rhs.symbol.name
    return lhsName < rhsName
  }

  var normalizedDebugObjects: [String: ObjectRecord] = [:]
  for object in debugObjects.values {
    let path = normalizeObjectPath(object.path)
    if normalizedDebugObjects[path] == nil {
      normalizedDebugObjects[path] = object
    }
    if debugFootprint[path] == nil {
      debugFootprint[path] = (0, 0)
    }
  }

  var debugOnlyFiles: [DebugOnlyFile] = []
  debugOnlyFiles.reserveCapacity(interestingByObject.count + normalizedDebugObjects.count)
  var seenDebugOnlyPaths: Set<String> = []
  for (path, info) in interestingByObject {
    if objectHasReleaseSymbol.contains(path) { continue }
    let resolvedURL = info.sourceURL ?? normalizedDebugObjects[path]?.sourceURL
    debugOnlyFiles.append(DebugOnlyFile(objectPath: path, sourceURL: resolvedURL, debugOnlySize: info.size, symbolCount: info.count))
    seenDebugOnlyPaths.insert(path)
  }

  for (path, object) in normalizedDebugObjects {
    if seenDebugOnlyPaths.contains(path) { continue }
    if let releaseInfo = releaseFootprintByPath[path], releaseInfo.count > 0 { continue }
    if let releaseBaseInfo = releaseFootprintByBaseName[object.baseName], releaseBaseInfo.count > 0 { continue }
    if objectHasReleaseSymbol.contains(path) { continue }
  if shouldIgnoreObject(object) { continue }

    let effectiveURL = object.sourceURL

    if requireSourceMatch && effectiveURL == nil {
      if missingSourceSamples.count < 6 {
        missingSourceSamples.append(relativePath(for: URL(fileURLWithPath: object.path), base: config.projectRoot))
      }
      continue
    }
    let footprint = debugFootprint[path] ?? (0, 0)
    let reportedCount = interestingByObject[path]?.count ?? 0
    debugOnlyFiles.append(DebugOnlyFile(objectPath: path, sourceURL: effectiveURL, debugOnlySize: footprint.size, symbolCount: reportedCount))
    seenDebugOnlyPaths.insert(path)
  }
  var releaseSymbolNameCache: [String: Bool] = [:]
  debugOnlyFiles = debugOnlyFiles.filter { entry in
    let baseName = URL(fileURLWithPath: entry.objectPath).deletingPathExtension().lastPathComponent
    return !releaseSymbolsContain(baseName, releaseSymbols: release.symbols, cache: &releaseSymbolNameCache)
  }
  debugOnlyFiles.sort { lhs, rhs in
    if lhs.debugOnlySize == rhs.debugOnlySize {
      return lhs.objectPath < rhs.objectPath
    }
    return lhs.debugOnlySize > rhs.debugOnlySize
  }

  DeadCodeAnalysis.Logger.logVerbose(config.verbose, "Debug-only files retained: \(debugOnlyFiles.count)")

  return AnalysisResult(
    totalDebugSymbols: debug.symbols.count,
    totalReleaseSymbols: release.symbols.count,
    rawDebugOnlyCount: rawCount,
    rawDebugOnlySize: rawSize,
    filteredSymbols: filteredSymbols,
    filteredSize: filteredSize,
    debugOnlyFiles: debugOnlyFiles
  )
}
