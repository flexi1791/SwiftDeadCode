import Foundation

/// Derives a set of candidate project module names by scanning debug symbols.
/// - Parameters:
///   - debug: The parsed debug link-map data.
///   - config: The user-specified configuration influencing filtering.
/// - Returns: A set of module identifiers believed to belong to the project.
func determineProjectModules(debug: LinkMapData, config: Configuration) -> Set<String> {
  var modules: Set<String> = []
  for symbol in debug.symbols {
    guard let canonical = canonicalMangledName(symbol.name) else { continue }
    let parts = parseMangledSymbol(canonical)
    guard let module = moduleName(from: parts), !module.isEmpty else { continue }
    if systemModuleNames.contains(module) { continue }
  if let object = debug.objects[symbol.objectIndex], shouldIgnoreObject(object) {
      continue
    }
    modules.insert(module)
  }
  return modules
}

/// Estimates which project module names dominate the candidate set, allowing us to strip redundant prefixes.
/// - Parameter candidates: Candidate symbols awaiting demangling.
/// - Returns: A set of module names considered project-owned.
func inferProjectModules(from candidates: [CandidateSymbol]) -> Set<String> {
  if candidates.isEmpty { return [] }

  var counts: [String: Int] = [:]
  for candidate in candidates {
    if let module = extractModuleName(fromMangled: candidate.symbol.name) {
      counts[module, default: 0] += 1
    }
  }

  if counts.isEmpty { return [] }

  let total = candidates.count
  let minimumShare = max(10, Int(Double(total) * 0.05))
  var modulesToStrip: Set<String> = []
  for (module, count) in counts {
    if count < minimumShare { continue }
    if systemModuleNames.contains(module) { continue }
    if module.hasPrefix("__") { continue }
    if module.lowercased().hasPrefix("swift") { continue }
    modulesToStrip.insert(module)
  }

  return modulesToStrip
}
