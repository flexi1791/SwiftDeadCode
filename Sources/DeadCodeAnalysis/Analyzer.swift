import Foundation

// MARK: - Analysis Pipeline

/// Produces the final analysis by contrasting debug-only symbols with release data.
/// - Parameters:
///   - debug: Parsed link-map information from the debug build.
///   - release: Parsed link-map information from the release build.
///   - config: Runtime configuration influencing filtering and reporting.
///   - sourceIndex: Lookup index for resolving source hints.
/// - Returns: The computed `AnalysisResult` containing filtered symbols and debug-only file entries.
func analyze(debug: LinkMapData, release: LinkMapData, config: Configuration, sourceIndex: [String: URL]) -> AnalysisResult {
  let releaseSet = Set(release.symbols.map { $0.name })
  var rawCount = 0
  var rawSize: UInt64 = 0
  var seen: Set<String> = []
  var objectHasReleaseSymbol: Set<String> = []
  var pendingCandidates: [CandidateSymbol] = []
  let requireSourceMatch = sourceIndex.count > 8
  DeadCodeAnalysis.Logger.logVerbose(config.verbose, "Source index entries: \(sourceIndex.count); requireSourceMatch=\(requireSourceMatch)")
  var skippedDuplicates = 0
  var skippedIgnoredObjects = 0
  var skippedNoSource = 0
  var skippedByFilter = 0
  var skippedDemangled = 0
  var missingSourceSamples: [String] = []
  var literalHintsByObject: [Int: SourceHint] = [:]
  var debugFootprint: [String: (size: UInt64, count: Int)] = [:]
  let releaseObjectPaths: Set<String> = Set(release.objects.values.map { normalizeObjectPath($0.path) })
  let projectModules = determineProjectModules(debug: debug, config: config)
  if config.verbose, !projectModules.isEmpty {
    DeadCodeAnalysis.Logger.logVerbose(config.verbose, "Detected project modules: \(projectModules.sorted().joined(separator: ", "))")
  }

  for symbol in debug.symbols {
    if literalHintsByObject[symbol.objectIndex] == nil {
      if let literalHint = literalSourceHint(from: symbol.name, projectRoot: config.projectRoot, sourceIndex: sourceIndex) {
        literalHintsByObject[symbol.objectIndex] = literalHint
      }
    }
    if !projectModules.isEmpty, let canonical = canonicalMangledName(symbol.name) {
      let moduleParts = parseMangledSymbol(canonical)
      if let module = moduleParts.segments.first, !module.isEmpty, !projectModules.contains(module) {
        continue
      }
    }

    let object = debug.objects[symbol.objectIndex]
    if let object {
      let key = normalizeObjectPath(object.path)
      let footprint = debugFootprint[key] ?? (0, 0)
      debugFootprint[key] = (footprint.size &+ symbol.size, footprint.count + 1)
      if releaseSet.contains(symbol.name) {
        objectHasReleaseSymbol.insert(key)
        continue
      }
    } else if releaseSet.contains(symbol.name) {
      continue
    }

    rawCount += 1
    rawSize &+= symbol.size

    if !seen.insert(symbol.name).inserted {
      skippedDuplicates += 1
      continue
    }

    if let object, shouldIgnoreObject(object, includePods: config.includePods) {
      skippedIgnoredObjects += 1
      continue
    }

    let hintInfo = makeSourceHint(
      for: object,
      projectRoot: config.projectRoot,
      sourceIndex: sourceIndex,
      literalHint: object.flatMap { literalHintsByObject[$0.index] } ?? literalHintsByObject[symbol.objectIndex]
    )
    if requireSourceMatch && !hintInfo.hasSource {
      skippedNoSource += 1
      if missingSourceSamples.count < 6 {
        if let object {
          missingSourceSamples.append(relativePath(for: URL(fileURLWithPath: object.path), base: config.projectRoot))
        } else {
          missingSourceSamples.append(symbol.name)
        }
      }
      continue
    }

    pendingCandidates.append(CandidateSymbol(symbol: symbol, object: object, sourceHint: hintInfo))
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
  var interestingByObject: [String: (size: UInt64, count: Int, hint: SourceHint)] = [:]

  for candidate in filteredCandidates {
    let demangledValue = demangledMap[candidate.symbol.name]
    if let demangledValue, shouldIgnoreDemangledSymbol(demangledValue) {
      skippedDemangled += 1
      continue
    }

    filteredSize &+= candidate.symbol.size
    var record = DebugOnlySymbol(symbol: candidate.symbol, object: candidate.object, demangled: nil, sourceHint: candidate.sourceHint)
    if config.demangle, let demangledValue {
      record.demangled = cleanDemangledName(demangledValue, modulesToStrip: modulesToStrip)
    }
    filteredSymbols.append(record)

    if let object = candidate.object {
      let key = normalizeObjectPath(object.path)
      let entry = interestingByObject[key] ?? (0, 0, candidate.sourceHint)
      let chosenHint: SourceHint
      if entry.hint.hasSource {
        chosenHint = entry.hint
      } else if candidate.sourceHint.hasSource {
        chosenHint = candidate.sourceHint
      } else {
        chosenHint = entry.hint
      }
      interestingByObject[key] = (
        entry.size &+ candidate.symbol.size,
        entry.count + 1,
        chosenHint
      )
    }
  }

  DeadCodeAnalysis.Logger.logVerbose(config.verbose, "Retained debug-only symbols: \(filteredSymbols.count) (filteredSize=\(formatBytes(filteredSize)), demangleFiltered=\(skippedDemangled))")

  filteredSymbols.sort { lhs, rhs in
    if lhs.sourceHint.display != rhs.sourceHint.display {
      return lhs.sourceHint.display < rhs.sourceHint.display
    }
    if lhs.symbol.size != rhs.symbol.size {
      return lhs.symbol.size > rhs.symbol.size
    }
    let lhsName = lhs.demangled ?? lhs.symbol.name
    let rhsName = rhs.demangled ?? rhs.symbol.name
    return lhsName < rhsName
  }

  var normalizedDebugObjects: [String: ObjectRecord] = [:]
  for object in debug.objects.values {
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
    debugOnlyFiles.append(DebugOnlyFile(objectPath: path, sourceHint: info.hint, debugOnlySize: info.size, symbolCount: info.count))
    seenDebugOnlyPaths.insert(path)
  }

  for (path, object) in normalizedDebugObjects {
    if seenDebugOnlyPaths.contains(path) { continue }
    if releaseObjectPaths.contains(path) { continue }
    if objectHasReleaseSymbol.contains(path) { continue }
    if shouldIgnoreObject(object, includePods: config.includePods) { continue }
    let hint = makeSourceHint(
      for: object,
      projectRoot: config.projectRoot,
      sourceIndex: sourceIndex,
      literalHint: literalHintsByObject[object.index]
    )
    var effectiveHint = hint
    if requireSourceMatch && !hint.hasSource {
      if missingSourceSamples.count < 6 {
        missingSourceSamples.append(relativePath(for: URL(fileURLWithPath: object.path), base: config.projectRoot))
      }
      if effectiveHint.display.isEmpty {
        let fallbackDisplay = relativePath(for: URL(fileURLWithPath: object.path), base: config.projectRoot)
        effectiveHint = SourceHint(display: fallbackDisplay, url: nil, hasSource: false)
      }
    }
    let footprint = debugFootprint[path] ?? (0, 0)
    debugOnlyFiles.append(DebugOnlyFile(objectPath: path, sourceHint: effectiveHint, debugOnlySize: footprint.size, symbolCount: footprint.count))
    seenDebugOnlyPaths.insert(path)
  }
  var releaseSymbolNameCache: [String: Bool] = [:]
  debugOnlyFiles = debugOnlyFiles.filter { entry in
    let baseName = URL(fileURLWithPath: entry.objectPath).deletingPathExtension().lastPathComponent
    return !releaseSymbolsContain(baseName, releaseSymbols: release.symbols, cache: &releaseSymbolNameCache)
  }
  debugOnlyFiles.sort {
    if $0.debugOnlySize == $1.debugOnlySize {
      return $0.sourceHint.display < $1.sourceHint.display
    }
    return $0.debugOnlySize > $1.debugOnlySize
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
