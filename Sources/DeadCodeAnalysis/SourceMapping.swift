import Foundation

extension DeadCodeAnalysis {
  enum SourceResolver {
    /// Caches resolved source file URLs per project root to avoid repeated filesystem scans.
    private static var cache: [String: [String: URL]] = [:]

    /// Locates a Swift file with the provided filename anywhere under the given root directory.
    /// - Parameters:
    ///   - filename: The filename (including extension) to search for.
    ///   - root: The directory to scan recursively.
    /// - Returns: The first URL that matches the filename, or `nil` if no match is found.
    static func findSwiftFile(named filename: String, in root: URL) -> URL? {
      let fileManager = FileManager.default
      guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
        return nil
      }

      for case let fileURL as URL in enumerator where fileURL.lastPathComponent == filename {
        return fileURL
      }

      return nil
    }

    /// Determines whether a file should be ignored because it is generated at runtime and not tracked in source control.
    /// - Parameter filename: The candidate filename to test.
    /// - Returns: `true` when the name matches a known generated-assets pattern.
    private static func isRuntimeGeneratedSource(_ filename: String) -> Bool {
      filename.lowercased().contains("generatedassetsymbols")
    }

    /// Resolves the on-disk location of a source file by consulting the cache and walking the filesystem as needed.
    /// - Parameters:
    ///   - filename: The name of the file to locate.
    ///   - root: The project root used as the search scope.
    /// - Returns: The URL to the source file, or `nil` when the file cannot be found or should be ignored.
    static func findSourceFile(named filename: String, in root: URL?) -> URL? {
      guard let root else { return nil }

      if isRuntimeGeneratedSource(filename) {
        return nil
      }

      let rootKey = root.standardizedFileURL.path
      if let cached = cache[rootKey]?[filename] {
        DeadCodeAnalysis.Logger.logVerbose(true, "cached match for \(filename): \(cached.path)")
        return cached
      }

      if let located = findSwiftFile(named: filename, in: root) {
        DeadCodeAnalysis.Logger.logVerbose(true, "found match for \(filename): \(located.path)")
        var inner = cache[rootKey] ?? [:]
        inner[filename] = located
        cache[rootKey] = inner
        return located
      }

      DeadCodeAnalysis.Logger.logVerbose(true, "no match for \(filename) under \(root.path)")
      return nil
    }
  }
}

/// Convenience passthrough to the shared source resolver for compatibility.
func findSwiftFile(named filename: String, in root: URL) -> URL? {
  DeadCodeAnalysis.SourceResolver.findSwiftFile(named: filename, in: root)
}

/// Convenience passthrough to the shared source resolver for compatibility.
func findSourceFile(named filename: String, in root: URL?) -> URL? {
  DeadCodeAnalysis.SourceResolver.findSourceFile(named: filename, in: root)
}
