import Foundation

// MARK: - Mangled Name Utilities

/// Normalizes a mangled-name suffix by stripping counters and trailing markers.
/// - Parameter value: The raw suffix portion to normalize.
/// - Returns: A comparable suffix suitable for suffix allow-list checks.
func sanitizeSuffix(_ value: String) -> String {
  var trimmed = value
  if let dotRange = trimmed.range(of: #"\.\d+$"#, options: .regularExpression) {
    trimmed = String(trimmed[..<dotRange.lowerBound])
  }
  while trimmed.hasSuffix("Z") {
    trimmed.removeLast()
  }
  let uppercaseTail = trimmed.reversed().prefix { $0.isUppercase }
  if !uppercaseTail.isEmpty {
    return String(uppercaseTail.reversed())
  }
  return trimmed
}

/// Retrieves the preferred suffix for the provided mangled symbol components.
/// - Parameter parts: The parsed mangled symbol components.
/// - Returns: The suffix used for allow-list evaluation, or `nil` when unavailable.
func canonicalSuffixCandidate(from parts: MangledSymbolParts) -> String? {
  if let suffix = parts.suffix, !suffix.isEmpty {
    return suffix
  }
  return parts.segments.last
}

/// Finds the canonical Swift mangled prefix inside the provided symbol name.
/// - Parameter name: The raw symbol name.
/// - Returns: The substring beginning at `$s`/`$S`, or `nil` when the string does not contain a Swift symbol.
func canonicalMangledName(_ name: String) -> String? {
  if let range = name.range(of: "$s") {
    return String(name[range.lowerBound...])
  }
  if let range = name.range(of: "$S") {
    return String(name[range.lowerBound...])
  }
  return nil
}

/// Dissects a mangled symbol into segments for downstream analysis.
struct MangledSymbolParts {
  let prefix: String
  let segments: [String]
  let suffix: String?
}

/// Parses a mangled Swift symbol into discrete components.
/// - Parameter name: The canonical mangled symbol.
/// - Returns: A struct describing the symbol segments and suffix.
func parseMangledSymbol(_ name: String) -> MangledSymbolParts {
  let characters = Array(name)
  let end = characters.count
  var index = 0

  // Step 1: Extract prefix consisting of the leading non-digit characters.
  let prefixStart = index
  while index < end, !characters[index].isNumber {
    index += 1
  }
  let prefix = String(characters[prefixStart..<index])

  var segments: [String] = []
  var suffix = ""

  // Step 2: Parse segments and collect suffix fragments to match legacy behaviour.
  while index < end {
    if !characters[index].isNumber {
      let suffixStart = index
      while index < end, !characters[index].isNumber {
        index += 1
      }
      suffix += String(characters[suffixStart..<index])
      continue
    }

    let lengthStart = index
    while index < end, characters[index].isNumber {
      index += 1
    }

    guard let length = Int(String(characters[lengthStart..<index])), length > 0 else {
      break
    }

    if index + length <= end {
      let segment = String(characters[index..<(index + length)])
      segments.append(segment)
      index += length
    } else {
      break
    }
  }

  return MangledSymbolParts(
    prefix: prefix,
    segments: segments,
    suffix: suffix.isEmpty ? nil : suffix
  )
}

/// Returns the module component identified within the mangled parts.
/// - Parameter parts: Parsed mangled symbol components.
/// - Returns: The module name if available.
func moduleName(from parts: MangledSymbolParts) -> String? {
  if parts.prefix.contains("So"), parts.segments.count >= 2 {
    return parts.segments[1]
  }
  return parts.segments.first
}

/// Extracts the module name from a mangled symbol string.
/// - Parameter name: The raw symbol name.
/// - Returns: The module portion, if any.
func extractModuleName(fromMangled name: String) -> String? {
  guard let canonical = canonicalMangledName(name) else { return nil }
  let parts = parseMangledSymbol(canonical)
  guard let module = moduleName(from: parts), !module.isEmpty else { return nil }
  return module
}

/// Removes a specific module prefix from fully-qualified type or function names.
/// - Parameters:
///   - text: The demangled symbol text to rewrite.
///   - module: The module prefix to strip.
/// - Returns: The rewritten text without the module prefix.
func stripModulePrefixes(in text: String, module: String) -> String {
  guard !module.isEmpty else { return text }
  let target = module + "."
  if target.isEmpty || !text.contains(target) { return text }

  var output = String()
  output.reserveCapacity(text.count)
  var index = text.startIndex
  while index < text.endIndex {
    if text[index...].hasPrefix(target) {
      let shouldStrip: Bool
      if index == text.startIndex {
        shouldStrip = true
      } else {
        let previousIndex = text.index(before: index)
        let previous = text[previousIndex]
        shouldStrip = moduleStripPrecedingCharacters.contains(previous)
      }
      if shouldStrip {
        index = text.index(index, offsetBy: target.count)
        continue
      }
    }
    output.append(text[index])
    index = text.index(after: index)
  }
  return output
}

/// Removes unstable anonymous hash contexts from demangled names to improve diffability.
/// - Parameter text: The demangled text potentially containing hash contexts.
/// - Returns: Text without anonymous hash contexts or redundant spacing.
func stripAnonymousHashContexts(in text: String) -> String {
  guard let regex = try? NSRegularExpression(pattern: #"\s+in\s+_[A-Za-z0-9]+"#, options: []) else {
    return text
  }
  let range = NSRange(text.startIndex..<text.endIndex, in: text)
  let replaced = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
  return replaced.replacingOccurrences(of: "  ", with: " ")
}

/// Post-processes demangled symbol names for readability and stability.
/// - Parameters:
///   - name: The demangled symbol name to clean.
///   - modulesToStrip: Modules that should be removed from the presentation string.
/// - Returns: A cleaned symbol name suitable for reporting.
func cleanDemangledName(_ name: String, modulesToStrip: Set<String>) -> String {
  var result = name.replacingOccurrences(of: "__C.", with: "")

  for module in modulesToStrip {
    result = stripModulePrefixes(in: result, module: module)
    result = result.replacingOccurrences(of: "(extension in \(module))", with: "(extension)")
    result = result.replacingOccurrences(of: "extension in \(module)", with: "extension")
  }

  result = stripAnonymousHashContexts(in: result)

  while result.contains("  ") {
    result = result.replacingOccurrences(of: "  ", with: " ")
  }

  return result.trimmingCharacters(in: .whitespaces)
}
