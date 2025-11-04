import Foundation

extension DeadCodeAnalysis {
  enum SourceResolver {
    private static var cache: [String: [String: URL]] = [:]

    static func findSwiftFile(named filename: String, in root: URL) -> URL? {
      let fileManager = FileManager.default
      guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
        return nil
      }

      for case let fileURL as URL in enumerator {
        if fileURL.lastPathComponent.caseInsensitiveCompare(filename) == .orderedSame {
          return fileURL
        }
      }

      return nil
    }

    private static func isRuntimeGeneratedSource(_ filename: String) -> Bool {
      filename.lowercased().contains("generatedassetsymbols")
    }

    static func findSourceFile(named filename: String, in root: URL?, allowExtensions: Set<String> = []) -> URL? {
      guard let root, !isRuntimeGeneratedSource(filename) else { return nil }

      let rootKey = root.standardizedFileURL.path
      if let cached = cache[rootKey]?[filename] {
        DeadCodeAnalysis.Logger.logVerbose(true, "cached match for \(filename): \(cached.path)")
        return cached
      }

      // Try direct match first
      if let located = findSwiftFile(named: filename, in: root) {
        cache[rootKey, default: [:]][filename] = located
        DeadCodeAnalysis.Logger.logVerbose(true, "found match for \(filename): \(located.path)")
        return located
      }

      // Try alternate extensions
      guard !allowExtensions.isEmpty else { return nil }

      let baseName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent

      for ext in allowExtensions {
        let candidateName = baseName + "." + ext
        if candidateName.caseInsensitiveCompare(filename) == .orderedSame { continue }

        if let located = findSwiftFile(named: candidateName, in: root) {
          cache[rootKey, default: [:]][filename] = located
          return located
        }
      }

      return nil
    }
  }
}

private let preferredSourceExtensions: Set<String> = [
  "swift",
  "m",
  "mm",
  "c",
  "cc",
  "cpp",
  "metal",
  "h",
  "hpp"
]

func resolveSourceURL(forObjectPath objectPath: String, projectRoot: URL?) -> URL? {
  let baseName = URL(fileURLWithPath: objectPath).deletingPathExtension().lastPathComponent
  guard !baseName.isEmpty else { return nil }

  guard let projectRoot else { return nil }

  if let located = DeadCodeAnalysis.SourceResolver.findSourceFile(named: baseName, in: projectRoot, allowExtensions: preferredSourceExtensions) {
    return located
  }

  return nil
}

func resolveObjectSources(objects: [ObjectRecord?], projectRoot: URL?) -> [ObjectRecord?] {
  var resolved = objects
  for index in objects.indices {
    guard var object = objects[index] else { continue }
    let sourceURL = resolveSourceURL(forObjectPath: object.path, projectRoot: projectRoot)
    object.sourceURL = sourceURL
    resolved[index] = object
  }
  return resolved
}
