import Foundation

/// Attempts to infer a source location from a symbol that encodes file information as a literal string.
/// - Parameters:
///   - symbolName: The raw symbol name containing the literal hint.
///   - projectRoot: The project root used for relative path resolution.
///   - sourceIndex: A precomputed index of known source files.
/// - Returns: A `SourceHint` when the literal value maps cleanly to a location.
func literalSourceHint(from symbolName: String, projectRoot: URL?, sourceIndex: [String: URL]) -> SourceHint? {
  let lower = symbolName.lowercased()
  guard lower.contains("literal string:") else { return nil }
  guard let range = lower.range(of: "literal string:") else { return nil }
  let originalSuffix = symbolName[range.upperBound...]
  let trimmed = originalSuffix.trimmingCharacters(in: .whitespaces)
  if trimmed.isEmpty { return nil }
  let baseName = URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
  if let sourceURL = sourceIndex[baseName] {
    return SourceHint(
      display: relativePath(for: sourceURL, base: projectRoot),
      url: sourceURL,
      hasSource: true
    )
  }
  if let projectRoot {
    // Some literals encode module separators with underscores; try replacing underscores with slashes.
    let underscored = trimmed.replacingOccurrences(of: "_", with: "/")
    let candidate = projectRoot.appendingPathComponent(underscored)
    if FileManager.default.fileExists(atPath: candidate.path) {
      return SourceHint(
        display: relativePath(for: candidate, base: projectRoot),
        url: candidate,
        hasSource: true
      )
    }
  }
  let pathExtension = URL(fileURLWithPath: trimmed).pathExtension
  let looksPathLike = trimmed.contains("/") || !pathExtension.isEmpty
  guard looksPathLike else { return nil }

  if trimmed.hasPrefix("/") {
    let resolved = URL(fileURLWithPath: trimmed)
    if FileManager.default.fileExists(atPath: resolved.path) {
      return SourceHint(
        display: relativePath(for: resolved, base: projectRoot),
        url: resolved,
        hasSource: true
      )
    }
  }

  if let projectRoot {
    let candidate = projectRoot.appendingPathComponent(trimmed)
    if FileManager.default.fileExists(atPath: candidate.path) {
      return SourceHint(
        display: relativePath(for: candidate, base: projectRoot),
        url: candidate,
        hasSource: true
      )
    }
  }

  return nil
}

/// Derives the best available source hint for a debug-only symbol.
/// - Parameters:
///   - object: The originating object record, if any.
///   - projectRoot: The resolved project root.
///   - sourceIndex: Lookup table for known sources.
///   - literalHint: Optional literal hint produced by `literalSourceHint`.
/// - Returns: A resolved source hint favoring direct source matches when possible.
func makeSourceHint(for object: ObjectRecord?, projectRoot: URL?, sourceIndex: [String: URL], literalHint: SourceHint?) -> SourceHint {
  guard let object else {
    return literalHint ?? SourceHint(display: "(unknown.o)", url: nil, hasSource: false)
  }
  let objectURL = URL(fileURLWithPath: object.path)
  var candidates: [String] = []
  let first = objectURL.deletingPathExtension()
  candidates.append(first.lastPathComponent)
  let second = first.deletingPathExtension()
  if second.lastPathComponent != candidates.last {
    candidates.append(second.lastPathComponent)
  }
  let third = second.deletingPathExtension()
  if third.lastPathComponent != candidates.last {
    candidates.append(third.lastPathComponent)
  }

  for key in candidates where !key.isEmpty {
    if let sourceURL = sourceIndex[key] {
      return SourceHint(
        display: relativePath(for: sourceURL, base: projectRoot),
        url: sourceURL,
        hasSource: true
      )
    }
  }

  let swiftFallback = objectURL.deletingPathExtension().appendingPathExtension("swift")

  if let projectRoot {
    var filenameCandidates: [String] = []
    for key in candidates where !key.isEmpty {
      filenameCandidates.append(key + ".swift")
      filenameCandidates.append(key + ".m")
    }
    filenameCandidates.append(swiftFallback.lastPathComponent)
    filenameCandidates.append(objectURL.deletingPathExtension().appendingPathExtension("m").lastPathComponent)
    let firstCandidate = objectURL.deletingPathExtension().lastPathComponent
    var seen: Set<String> = []
    let resolutionOrder = [firstCandidate + ".swift", firstCandidate + ".m"] + filenameCandidates
    for name in resolutionOrder where !name.isEmpty {
      if !seen.insert(name).inserted { continue }
      if let located = findSourceFile(named: name, in: projectRoot) {
        return SourceHint(
          display: relativePath(for: located, base: projectRoot),
          url: located,
          hasSource: true
        )
      }
    }
  }

  for (_, candidateURL) in sourceIndex {
    if candidateURL.lastPathComponent == swiftFallback.lastPathComponent {
      return SourceHint(
        display: relativePath(for: candidateURL, base: projectRoot),
        url: candidateURL,
        hasSource: true
      )
    }
  }

  if let literalHint = literalHint { return literalHint }

  let displayFallback: String
  if let projectRoot {
    displayFallback = relativePath(for: swiftFallback, base: projectRoot)
  } else {
    displayFallback = swiftFallback.lastPathComponent
  }
  return SourceHint(
    display: displayFallback,
    url: FileManager.default.fileExists(atPath: swiftFallback.path) ? swiftFallback : nil,
    hasSource: false
  )
}
