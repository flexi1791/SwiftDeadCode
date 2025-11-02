import Foundation

// MARK: - Reporting

func symbolNote(_ symbol: DebugOnlySymbol) -> String? {
  let lowered = (symbol.demangled ?? symbol.symbol.name).lowercased()
  if lowered.contains("previewprovider") || lowered.contains(".previews") {
    return "[Preview]"
  }
  if lowered.contains("widget") && lowered.contains("timelineentry") {
    return "[Widget]"
  }
  return nil
}

func diagnosticPath(for symbol: DebugOnlySymbol, config: Configuration) -> String? {
  if let url = symbol.sourceHint.url {
    return url.path
  }
  let display = symbol.sourceHint.display
  if display.isEmpty { return nil }
  if display.hasPrefix("/") {
    return display
  }
  guard let projectRoot = config.projectRoot else {
    return display
  }
  
  if display.contains("/") {
    let candidate = projectRoot.appendingPathComponent(display)
    return candidate.path
  }
  
  let prefixes = config.sourcePrefixes.isEmpty ? [""] : config.sourcePrefixes
  for prefix in prefixes {
    let candidate = projectRoot.appendingPathComponent(prefix).appendingPathComponent(display)
    if FileManager.default.fileExists(atPath: candidate.path) {
      return candidate.path
    }
  }
  
  return projectRoot.appendingPathComponent(display).path
}

func emitDiagnostics(for symbols: [DebugOnlySymbol], config: Configuration) {
  func writeWarning(_ text: String) {
    guard let data = (text + "\n").data(using: .utf8) else { return }
    FileHandle.standardError.write(data)
  }
  
  let groupedByDisplay = Dictionary(grouping: symbols, by: { $0.sourceHint.display })
  let orderedDisplays = groupedByDisplay.keys.sorted()
  
  for display in orderedDisplays {
    guard let bucket = groupedByDisplay[display] else { continue }
    let sortedSymbols = bucket.sorted { lhs, rhs in
      if lhs.symbol.size == rhs.symbol.size {
        let lhsName = lhs.demangled ?? lhs.symbol.name
        let rhsName = rhs.demangled ?? rhs.symbol.name
        return lhsName < rhsName
      }
      return lhs.symbol.size > rhs.symbol.size
    }
    
    for symbol in sortedSymbols {
      guard let path = diagnosticPath(for: symbol, config: config) else { continue }
      let name = symbol.demangled ?? symbol.symbol.name
      writeWarning("\(path):1:1: warning: [dead-code] Debug-only symbol \(name)")
    }
  }
}

func reportLines(_ result: AnalysisResult, config: Configuration) -> [String] {
  var lines: [String] = []
  lines.append("Debug link map: \(config.debugURL.path)")
  lines.append("Release link map: \(config.releaseURL.path)")
  lines.append("Total debug symbols: \(result.totalDebugSymbols)")
  lines.append("Total release symbols: \(result.totalReleaseSymbols)")
  lines.append("Debug-only symbols (raw): \(result.rawDebugOnlyCount) (\(formatBytes(result.rawDebugOnlySize)))")
  lines.append("Debug-only symbols (filtered): \(result.filteredSymbols.count) (\(formatBytes(result.filteredSize)))")
  
  if result.filteredSymbols.isEmpty {
    lines.append("")
    lines.append("No application-owned debug-only symbols were detected after filtering.")
    return lines
  }
  
  if !result.lowHangingFiles.isEmpty {
    lines.append("")
    let lowHangingEntries: [LowHangingFruit]
    if config.groupLimit > 0 && config.groupLimit < result.lowHangingFiles.count {
      lines.append("Files with debug-only symbols (showing first \(config.groupLimit) of \(result.lowHangingFiles.count)):")
      lowHangingEntries = Array(result.lowHangingFiles.prefix(config.groupLimit))
    } else {
      lines.append("Files with debug-only symbols (no release symbols found):")
      lowHangingEntries = result.lowHangingFiles
    }
    for entry in lowHangingEntries {
      let file = rightPad(entry.sourceHint.display, to: 36)
      let countText = leftPad("\(entry.symbolCount)", to: 5)
      lines.append("\(file)  \(countText) symbol(s)")
    }
  }
  
  lines.append("")
  lines.append("Debug-only symbols: \(result.filteredSymbols.count)")
  
  var aggregatedCounts: [String: Int] = [:]
  for symbol in result.filteredSymbols {
    let display = symbol.sourceHint.display
    aggregatedCounts[display, default: 0] += 1
  }
  for entry in result.lowHangingFiles {
    let display = entry.sourceHint.display
    let existing = aggregatedCounts[display] ?? 0
    let candidate = max(existing, entry.symbolCount)
    aggregatedCounts[display] = candidate
  }
  let ranked = aggregatedCounts.map { (key: String, value: Int) -> (String, Int) in
    (key, value)
  }.sorted { lhs, rhs in
    lhs.0 < rhs.0
  }
  
  if !ranked.isEmpty {
    lines.append("")
    let groupsToShow: [(String, Int)]
    if config.groupLimit > 0 && config.groupLimit < ranked.count {
      lines.append("Files by symbol count (showing first \(config.groupLimit) of \(ranked.count)):")
      groupsToShow = Array(ranked.prefix(config.groupLimit))
    } else {
      lines.append("Files by symbol count (\(ranked.count) total):")
      groupsToShow = ranked
    }
    for entry in groupsToShow {
      let file = rightPad(entry.0, to: 36)
      let countText = leftPad("\(entry.1)", to: 5)
      lines.append("\(file)  \(countText) symbol(s)")
    }
  }
  
  return lines
}

func printReport(_ result: AnalysisResult, config: Configuration) {
  emitDiagnostics(for: result.filteredSymbols, config: config)
  for line in reportLines(result, config: config) {
    print(line)
  }
}
