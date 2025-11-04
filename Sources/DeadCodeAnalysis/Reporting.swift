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
func symbolNote(_ symbol: SymbolRecord) -> String? {
  let lowered = (symbol.demangled ?? symbol.name).lowercased()
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

  guard let projectRoot = config.projectRoot else { return objectPath }
  guard let objectPath, !objectPath.isEmpty else { return nil }

  if objectPath.hasPrefix("/") {
    return objectPath
  }

  if objectPath.contains("/") {
    return projectRoot.appendingPathComponent(objectPath).path
  }

  let prefixes = config.sourcePrefixes.isEmpty ? [""] : config.sourcePrefixes
  for prefix in prefixes {
    let candidate = projectRoot.appendingPathComponent(prefix).appendingPathComponent(objectPath)
    if FileManager.default.fileExists(atPath: candidate.path) {
      return candidate.path
    }
  }

  return projectRoot.appendingPathComponent(objectPath).path
}

/// Resolves a filesystem path suitable for Xcode-style diagnostics using symbol metadata.
///
/// - Parameters:
///   - symbol: The debug-only symbol whose hint should be resolved.
///   - config: The runtime configuration containing path resolution preferences.
func diagnosticPath(for symbol: SymbolRecord, config: Configuration, debugObjects: [ObjectRecord?]) -> String? {
  let object = symbol.objectIndex >= 0 && symbol.objectIndex < debugObjects.count ? debugObjects[symbol.objectIndex] : nil
  return diagnosticPath(sourceURL: object?.sourceURL, objectPath: object?.path, config: config)
}

/// Produces human-readable report lines describing the analysis results.
///
/// - Parameters:
///   - result: The aggregated analysis containing unused symbols and file summaries.
///   - config: The runtime configuration controlling formatting and truncation.
func reportLines(_ result: AnalysisResult, config: Configuration) -> [String] {
  var lines: [String] = []
  if config.verbose {
    lines.append("Debug link map: \(config.debugURL.path)")
    lines.append("Release link map: \(config.releaseURL.path)")
    lines.append("Total debug symbols: \(result.totalDebugSymbols)")
    lines.append("Total release symbols: \(result.totalReleaseSymbols)")
  lines.append("Debug-only symbols (unused): \(result.unusedSymbols.count) (\(formatBytes(result.unusedSize)))")
  }
  
  if result.unusedSymbols.isEmpty {
    if !lines.isEmpty {
      lines.append("")
    }
    lines.append("No application-owned debug-only symbols were detected after filtering.")
    return lines
  }
  
  func object(for index: Int) -> ObjectRecord? {
    guard index >= 0, index < result.debugObjects.count else { return nil }
    return result.debugObjects[index]
  }

  let groupedSymbols = Dictionary(grouping: result.unusedSymbols, by: { symbol in
    let object = object(for: symbol.objectIndex)
    return displayName(sourceURL: object?.sourceURL, objectPath: object?.path, config: config)
  })
  let unusedObjectsByDisplay = Dictionary(grouping: result.unusedObjects, by: { object in
    displayName(sourceURL: object.sourceURL, objectPath: object.path, config: config)
  })
  let allDisplays = Set(groupedSymbols.keys).union(unusedObjectsByDisplay.keys)
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
        if lhs.size == rhs.size {
          let lhsName = lhs.demangled ?? lhs.name
          let rhsName = rhs.demangled ?? rhs.name
          return lhsName < rhsName
        }
        return lhs.size > rhs.size
      }
      let unusedObjects = unusedObjectsByDisplay[display] ?? []
      let displayName = display.isEmpty ? "(unknown)" : display
      let fallbackPath = unusedObjects.compactMap {
        diagnosticPath(sourceURL: $0.sourceURL, objectPath: $0.path, config: config)
      }.first
      let fallbackContext = unusedObjects.compactMap {
        contextPath(sourceURL: $0.sourceURL, objectPath: $0.path, config: config)
      }.first

      if symbols.isEmpty {
        let objectLine = "\(displayName) - unused in release"
        if unusedObjects.count > 1 {
          for object in unusedObjects {
            let context = contextPath(sourceURL: object.sourceURL, objectPath: object.path, config: config)
            let message = context != nil && context != displayName ? "\(objectLine) (\(context!))" : objectLine
            if let path = diagnosticPath(sourceURL: object.sourceURL, objectPath: object.path, config: config) {
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

  let headerPath = symbols.compactMap { diagnosticPath(for: $0, config: config, debugObjects: result.debugObjects) }.first ?? fallbackPath
      let headerContext: String?
      if let resolvedPath = headerPath {
        if resolvedPath.hasPrefix("/") {
          headerContext = relativePath(for: URL(fileURLWithPath: resolvedPath), base: config.projectRoot)
        } else {
          headerContext = resolvedPath
        }
      } else if let symbolContext = symbols.compactMap({ symbol -> String? in
        let object = object(for: symbol.objectIndex)
        return contextPath(sourceURL: object?.sourceURL, objectPath: object?.path, config: config)
      }).first {
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
        var name = symbol.demangled ?? symbol.name
        if symbol.demangled == nil, name.hasPrefix("_") {
          name.removeFirst()
        }
        if let note = symbolNote(symbol) {
          name += " \(note)"
        }
        if let path = diagnosticPath(for: symbol, config: config, debugObjects: result.debugObjects) {
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
///   - result: The aggregated analysis containing unused symbols and file summaries.
///   - config: The runtime configuration controlling formatting and truncation.
func printReport(_ result: AnalysisResult, config: Configuration) {
  for line in reportLines(result, config: config) {
    print(line)
  }
}
