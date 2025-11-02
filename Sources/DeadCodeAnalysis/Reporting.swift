import Foundation

// MARK: - Reporting

/// Returns a human-friendly suffix describing notable debug-only symbols.
///
/// - Parameter symbol: The debug-only symbol being evaluated for annotations.
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

/// Resolves a filesystem path suitable for Xcode-style diagnostics using a source hint.
///
/// - Parameters:
///   - hint: The hint describing the source location associated with a symbol or object file.
///   - config: The runtime configuration containing path resolution preferences.
func diagnosticPath(for hint: SourceHint, config: Configuration) -> String? {
  if let url = hint.url {
    return url.path
  }
  let display = hint.display
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

/// Resolves a filesystem path suitable for Xcode-style diagnostics using symbol metadata.
///
/// - Parameters:
///   - symbol: The debug-only symbol whose hint should be resolved.
///   - config: The runtime configuration containing path resolution preferences.
func diagnosticPath(for symbol: DebugOnlySymbol, config: Configuration) -> String? {
  diagnosticPath(for: symbol.sourceHint, config: config)
}

/// Produces human-readable report lines describing the analysis results.
///
/// - Parameters:
///   - result: The aggregated analysis containing filtered symbols and file summaries.
///   - config: The runtime configuration controlling formatting and truncation.
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
  
  if !result.debugOnlyFiles.isEmpty {
    lines.append("")
    let debugOnlyEntries: [DebugOnlyFile]
    if config.groupLimit > 0 && config.groupLimit < result.debugOnlyFiles.count {
      lines.append("Files unique to debug build (showing first \(config.groupLimit) of \(result.debugOnlyFiles.count)):")
      debugOnlyEntries = Array(result.debugOnlyFiles.prefix(config.groupLimit))
    } else {
      lines.append("Files unique to debug build (no release symbols found):")
      debugOnlyEntries = result.debugOnlyFiles
    }
    for entry in debugOnlyEntries {
      let file = rightPad(entry.sourceHint.display, to: 36)
      let countText = leftPad("\(entry.symbolCount)", to: 5)
      lines.append("\(file)  \(countText) symbol(s)")
    }
  }
  
  let groupedSymbols = Dictionary(grouping: result.filteredSymbols, by: { $0.sourceHint.display })
  let allDisplays = Set(groupedSymbols.keys).union(result.debugOnlyFiles.map { $0.sourceHint.display })
  if !allDisplays.isEmpty {
    lines.append("")
    lines.append("Debug-only symbols grouped by file (\(allDisplays.count) total):")
    let sortedDisplays = allDisplays.sorted()
    let displaysToShow: [String]
    if config.groupLimit > 0 && config.groupLimit < sortedDisplays.count {
      lines.append("(showing first \(config.groupLimit) files)")
      displaysToShow = Array(sortedDisplays.prefix(config.groupLimit))
    } else {
      displaysToShow = sortedDisplays
    }
    for display in displaysToShow {
      let symbols = (groupedSymbols[display] ?? []).sorted { lhs, rhs in
        if lhs.symbol.size == rhs.symbol.size {
          let lhsName = lhs.demangled ?? lhs.symbol.name
          let rhsName = rhs.demangled ?? rhs.symbol.name
          return lhsName < rhsName
        }
        return lhs.symbol.size > rhs.symbol.size
      }
      let fallback = result.debugOnlyFiles.first { $0.sourceHint.display == display }
      let count = symbols.isEmpty ? (fallback?.symbolCount ?? 0) : symbols.count
      let file = rightPad(display, to: 36)
      let countText = leftPad("\(count)", to: 5)
      lines.append("\(file)  \(countText) symbol(s)")
      if symbols.isEmpty {
        if let hint = fallback?.sourceHint, let path = diagnosticPath(for: hint, config: config) {
          lines.append("\(path):1:1: warning: [dead-code] Debug-only object file")
        } else {
          lines.append("    Debug-only object file")
        }
        continue
      }
      for symbol in symbols {
        var name = symbol.demangled ?? symbol.symbol.name
        if symbol.demangled == nil, name.hasPrefix("_") {
          name.removeFirst()
        }
        if let note = symbolNote(symbol) {
          name += " \(note)"
        }
        if let path = diagnosticPath(for: symbol, config: config) {
          lines.append("\(path):1:1: warning: [dead-code] Debug-only symbol \(name)")
        } else {
          lines.append("    Debug-only symbol \(name)")
        }
      }
    }
  }
  
  return lines
}

/// Emits diagnostics and writes the textual report to standard output.
///
/// - Parameters:
///   - result: The aggregated analysis containing filtered symbols and file summaries.
///   - config: The runtime configuration controlling formatting and truncation.
func printReport(_ result: AnalysisResult, config: Configuration) {
  for line in reportLines(result, config: config) {
    print(line)
  }
}
