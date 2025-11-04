import Foundation

/// Determines whether an object file should be excluded from the analysis.
/// - Parameters:
///   - object: The object record under review.
/// - Returns: `true` when the object should be ignored.
func shouldIgnoreObject(_ object: ObjectRecord) -> Bool {
  let path = object.path
  let lowered = path.lowercased()
  if path.contains(".framework/") { return true }
  if path.contains("/Toolchains/") { return true }
  if path.contains("/Platforms/") { return true }
  if path.contains("SourcePackages/checkouts") { return true }
  if lowered.contains(".dylib") { return true }
  if lowered.contains("linker synthesized") { return true }
  if path.contains("/Pods/") { return true }
  return false
}

/// Decides whether a mangled symbol survives initial filtering.
/// - Parameters:
///   - name: The symbol name to evaluate.
///   - allowedSuffixes: The suffixes that the symbol must match.
///   - allowedModules: Project module names that should be retained.
/// - Returns: `true` when the symbol remains a candidate.
func shouldKeepSymbol(
  _ name: String,
  allowedSuffixes: Set<String>,
  allowedModules: Set<String> = []
) -> Bool {
  let lower = name.lowercased()
  if nonSwiftNoiseTokensLowercased.contains(where: { lower.contains($0) }) {
    return false
  }
  if nonSwiftNoisePrefixesLowercased.contains(where: { lower.hasPrefix($0) }) {
    return false
  }
  if lower.contains("$deferl_") {
    return false
  }
  if lower.hasSuffix(".resume") || lower.contains("mn.resume") {
    return false
  }
  if name.contains("SwiftUI15ModifiedContent") || name.contains("SwiftUI17_ConditionalContent") {
    return false
  }
  if name.contains("33_") {
    return false
  }
  if name.contains(".eh_frame") {
    let upper = name.uppercased()
    if upper.contains("FDE") || upper.contains("CFI") {
      return false
    }
  }
  let gotIndicators = ["$got", "@got", ".got", " got", "got[", "got_"]
  if gotIndicators.contains(where: { lower.contains($0) }) {
    return false
  }

  if isObjectiveCMethodSymbol(name) {
    return true
  }

  guard let canonical = canonicalMangledName(name) else {
    return false
  }
  let parts = parseMangledSymbol(canonical)
  guard let suffix = canonicalSuffixCandidate(from: parts) else {
    return false
  }
  let normalizedSuffix = sanitizeSuffix(suffix).uppercased()
  if normalizedSuffix.isEmpty || !allowedSuffixes.contains(normalizedSuffix) {
    return false
  }
  guard !allowedModules.isEmpty else { return true }
  if let module = moduleName(from: parts) {
    return allowedModules.contains(module)
  }
  return false
}

/// Detects Objective-C style method symbols such as `-[Class method:]`.
private func isObjectiveCMethodSymbol(_ name: String) -> Bool {
  guard let first = name.first, (first == "-" || first == "+") else { return false }
  guard name.dropFirst().first == "[" else { return false }
  guard let closingBracket = name.firstIndex(of: "]") else { return false }
  let classPortion = name[name.index(name.startIndex, offsetBy: 2)..<closingBracket]
  return !classPortion.isEmpty
}

/// Filters demangled names that we know are tooling noise.
/// - Parameter name: The demangled symbol name.
/// - Returns: `true` when the symbol should be discarded.
func shouldIgnoreDemangledSymbol(_ name: String) -> Bool {
  let lower = name.lowercased()

  for token in demangledNoiseTokens {
    if lower.contains(token) { return true }
  }

  if name.contains("(extension in SwiftUI)") { return true }
  if name.contains("SwiftUI.ModifiedContent") { return true }
  if name.contains("SwiftUI.ViewBuilder") { return true }
  if name.contains("SwiftUI.TupleView") { return true }

  return false
}

/// Canonicalizes an object-file path for set membership lookups.
/// - Parameter path: Original path string from the link map.
/// - Returns: A standardized absolute path.
func normalizeObjectPath(_ path: String) -> String {
  URL(fileURLWithPath: path).standardizedFileURL.path
}
