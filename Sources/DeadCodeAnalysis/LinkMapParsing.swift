import Foundation

// MARK: - Link Map Parsing

/// Reads and parses the contents of a linker map file.
/// - Parameter url: The on-disk location of the `.linkmap` file to load.
/// - Returns: A `LinkMapData` bundle containing objects, symbols, and basic metadata.
/// - Throws: An error if the file is unreadable or malformed.
func parseLinkMap(at url: URL) throws -> LinkMapData {
  let content = try String(contentsOf: url, encoding: .utf8)
  enum Section { case header, objects, sections, symbols, done }
  var section: Section = .header
  var objects: [ObjectRecord?] = []
  var symbols: [SymbolRecord] = []
  let objectRegex = try NSRegularExpression(pattern: #"\[\s*(\d+)\]\s+(.+)"#)
  let symbolRegex = try NSRegularExpression(pattern: #"0x([0-9A-Fa-f]+)\s+0x([0-9A-Fa-f]+)\s+\[\s*(\d+)\]\s+(.+)"#)

  let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  for line in lines {
    if line.hasPrefix("# Object files:") { section = .objects; continue }
    if line.hasPrefix("# Sections:") { section = .sections; continue }
    if line.hasPrefix("# Symbols:") { section = .symbols; continue }
    if line.hasPrefix("# Dead Stripped Symbols:") { section = .done; break }

    switch section {
    case .objects:
      let ns = line as NSString
      if let match = objectRegex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: ns.length)) {
        let indexString = ns.substring(with: match.range(at: 1))
        let path = ns.substring(with: match.range(at: 2))
        if let idx = Int(indexString) {
          let record = ObjectRecord(index: idx, path: path, sourceURL: nil)
          if idx >= objects.count {
            objects.append(contentsOf: Array(repeating: nil, count: idx - objects.count + 1))
          }
          objects[idx] = record
        }
      }
    case .symbols:
      let ns = line as NSString
      if let match = symbolRegex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: ns.length)) {
        let addressString = ns.substring(with: match.range(at: 1))
        let sizeString = ns.substring(with: match.range(at: 2))
        let indexString = ns.substring(with: match.range(at: 3))
        let name = ns.substring(with: match.range(at: 4))
        guard
          let address = UInt64(addressString, radix: 16),
          let size = UInt64(sizeString, radix: 16),
          let objectIndex = Int(indexString)
        else { continue }
        symbols.append(SymbolRecord(address: address, size: size, objectIndex: objectIndex, name: name))
      }
    default:
      continue
    }
  }

  return LinkMapData(path: url, objects: objects, symbols: symbols, lineCount: lines.count)
}

// MARK: - Source Index Construction

/// Formats a URL relative to the provided base path when possible.
/// - Parameters:
///   - url: The URL to make relative.
///   - base: The optional base directory.
/// - Returns: A path string safe for diagnostics.
func relativePath(for url: URL, base: URL?) -> String {
  guard let base else { return url.path }
  let path = url.standardizedFileURL.path
  let basePath = base.standardizedFileURL.path
  if path.hasPrefix(basePath) {
    let index = path.index(path.startIndex, offsetBy: basePath.count)
    if index < path.endIndex && path[index] == "/" {
      return String(path[path.index(after: index)...])
    }
    if index < path.endIndex {
      return String(path[index...])
    }
    return url.lastPathComponent
  }
  return url.lastPathComponent
}
