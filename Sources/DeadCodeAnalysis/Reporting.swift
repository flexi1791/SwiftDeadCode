import Foundation

// MARK: - Reporting

private func displayName(sourceURL: URL?, objectPath: String?, config: Configuration) -> String {
  if let sourceURL {
    let relative = relativePath(for: sourceURL, base: config.projectRoot).trimmingCharacters(in: .whitespacesAndNewlines)
    if !relative.isEmpty {
      if relative.contains("/") {
        return URL(fileURLWithPath: relative).lastPathComponent
      }
      return relative
    }
    return sourceURL.lastPathComponent
  }

  if let objectPath {
    let base = URL(fileURLWithPath: objectPath).lastPathComponent
    if !base.isEmpty { return base }
  }

  return "(unknown)"
}

private func contextPath(sourceURL: URL?, objectPath: String?, config: Configuration) -> String? {
  if let sourceURL {
    return relativePath(for: sourceURL, base: config.projectRoot)
  }

  if let objectPath {
    let url = URL(fileURLWithPath: objectPath)
    return relativePath(for: url, base: config.projectRoot)
  }

  return nil
}

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

/// Resolves a filesystem path suitable for Xcode-style diagnostics using available source metadata.
///
/// - Parameters:
///   - hint: The hint describing the source location associated with a symbol or object file.
///   - config: The runtime configuration containing path resolution preferences.
private func diagnosticPath(sourceURL: URL?, objectPath: String?, config: Configuration) -> String? {
  if let sourceURL {
    return sourceURL.path
  }

  guard let fallback = objectPath, !fallback.isEmpty else { return nil }

  if fallback.hasPrefix("/") {
    return fallback
  }

  guard let projectRoot = config.projectRoot else {
    return fallback
  }

  if fallback.contains("/") {
    return projectRoot.appendingPathComponent(fallback).path
  }

  let prefixes = config.sourcePrefixes.isEmpty ? [""] : config.sourcePrefixes
  for prefix in prefixes {
    let candidate = projectRoot.appendingPathComponent(prefix).appendingPathComponent(fallback)
    if FileManager.default.fileExists(atPath: candidate.path) {
      return candidate.path
    }
  }

  return projectRoot.appendingPathComponent(fallback).path
}

/// Resolves a filesystem path suitable for Xcode-style diagnostics using symbol metadata.
///
/// - Parameters:
///   - symbol: The debug-only symbol whose hint should be resolved.
///   - config: The runtime configuration containing path resolution preferences.
func diagnosticPath(for symbol: DebugOnlySymbol, config: Configuration) -> String? {
  diagnosticPath(sourceURL: symbol.object?.sourceURL, objectPath: symbol.object?.path, config: config)
}

/// Produces human-readable report lines describing the analysis results.
///
/// - Parameters:
///   - result: The aggregated analysis containing filtered symbols and file summaries.
///   - config: The runtime configuration controlling formatting and truncation.
func reportLines(_ result: AnalysisResult, config: Configuration) -> [String] {
  var lines: [String] = []
  if config.verbose {
    lines.append("Debug link map: \(config.debugURL.path)")
    lines.append("Release link map: \(config.releaseURL.path)")
    lines.append("Total debug symbols: \(result.totalDebugSymbols)")
    lines.append("Total release symbols: \(result.totalReleaseSymbols)")
    lines.append("Debug-only symbols (raw): \(result.rawDebugOnlyCount) (\(formatBytes(result.rawDebugOnlySize)))")
    lines.append("Debug-only symbols (filtered): \(result.filteredSymbols.count) (\(formatBytes(result.filteredSize)))")
  }
  
  if result.filteredSymbols.isEmpty {
    if !lines.isEmpty {
      lines.append("")
    }
    lines.append("No application-owned debug-only symbols were detected after filtering.")
    return lines
  }
  
  let groupedSymbols = Dictionary(grouping: result.filteredSymbols, by: { symbol in
    displayName(sourceURL: symbol.object?.sourceURL, objectPath: symbol.object?.path, config: config)
  })
  let debugOnlyGroups = Dictionary(grouping: result.debugOnlyFiles, by: { file in
    displayName(sourceURL: file.sourceURL, objectPath: file.objectPath, config: config)
  })
  let allDisplays = Set(groupedSymbols.keys).union(debugOnlyGroups.keys)
  if !allDisplays.isEmpty {
    if !lines.isEmpty {
      lines.append("")
    }
    lines.append("Debug-only symbols grouped by file (\(allDisplays.count) total):")
    let sortedDisplays = allDisplays.sorted { lhs, rhs in
      return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }
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
      let fallbackEntries = debugOnlyGroups[display] ?? []
      let fallback = fallbackEntries.first
      let displayName = display.isEmpty ? "(unknown)" : display
      let fallbackPath = fallback.flatMap { diagnosticPath(sourceURL: $0.sourceURL, objectPath: $0.objectPath, config: config) }
      let fallbackContext = fallback.flatMap { contextPath(sourceURL: $0.sourceURL, objectPath: $0.objectPath, config: config) }

      if symbols.isEmpty {
        let objectLine = "\(displayName) - unused in release"
        if fallbackEntries.count > 1 {
          for entry in fallbackEntries {
            let context = contextPath(sourceURL: entry.sourceURL, objectPath: entry.objectPath, config: config)
            let message = context != nil && context != displayName ? "\(objectLine) (\(context!))" : objectLine
            if let path = diagnosticPath(sourceURL: entry.sourceURL, objectPath: entry.objectPath, config: config) {
              lines.append("\(path):1:1: warning: \(message)")
            } else {
              lines.append(message)
            }
          }
          continue
        }
        let message = fallbackContext != nil && fallbackContext != displayName ? "\(objectLine) (\(fallbackContext!))" : objectLine
        if let path = fallbackPath {
          lines.append("\(path):1:1: warning: \(message)")
        } else {
          lines.append(message)
        }
        continue
      }

      let headerPath = symbols.compactMap { diagnosticPath(for: $0, config: config) }.first ?? fallbackPath
      let headerContext: String?
      if let resolvedPath = headerPath {
        if resolvedPath.hasPrefix("/") {
          headerContext = relativePath(for: URL(fileURLWithPath: resolvedPath), base: config.projectRoot)
        } else {
          headerContext = resolvedPath
        }
      } else if let symbolContext = symbols.compactMap({ contextPath(sourceURL: $0.object?.sourceURL, objectPath: $0.object?.path, config: config) }).first {
        headerContext = symbolContext
      } else {
        headerContext = fallbackContext
      }
      let summary: String
      if let context = headerContext, context != displayName {
        summary = "\(displayName) - \(context)"
      } else {
        summary = displayName
      }
      if let path = headerPath {
        lines.append("\(path):1:1: warning: \(summary)")
      } else {
        lines.append(summary)
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
          lines.append("\(path):1:1: warning:    \(name)")
        } else {
          lines.append("    \(name)")
        }
      }
    }
  }
  
  return lines
}

/// Writes the textual report, including grouped diagnostics, to standard output.
///
/// - Parameters:
///   - result: The aggregated analysis containing filtered symbols and file summaries.
///   - config: The runtime configuration controlling formatting and truncation.
func printReport(_ result: AnalysisResult, config: Configuration) {
  for line in reportLines(result, config: config) {
    print(line)
  }
}
