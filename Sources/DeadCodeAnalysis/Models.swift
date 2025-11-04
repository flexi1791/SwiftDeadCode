import Foundation

// MARK: - Data Models

/// Summary of an object-file listing extracted from the link map.
struct ObjectRecord: Equatable, Comparable {
  let index: Int
  let path: String
  var sourceURL: URL?
  var debugSymbols: [SymbolRecord] = []
  var releaseSymbolNames: Set<String> = []

  var baseName: String {
    URL(fileURLWithPath: path).lastPathComponent
  }

  static func < (lhs: ObjectRecord, rhs: ObjectRecord) -> Bool {
    let ordering = lhs.path.localizedCaseInsensitiveCompare(rhs.path)
    if ordering != .orderedSame {
      return ordering == .orderedAscending
    }
    return lhs.index < rhs.index
  }
}

/// Represents an individual symbol entry inside the link map.
struct SymbolRecord: Equatable {
  let address: UInt64
  let size: UInt64
  let objectIndex: Int
  let name: String
  var demangled: String? = nil
}

extension SymbolRecord {
  static func reportComparator(using objects: [ObjectRecord?]) -> (SymbolRecord, SymbolRecord) -> Bool {
    { lhs, rhs in
      let lhsDisplay = displayPath(for: lhs, objects: objects)
      let rhsDisplay = displayPath(for: rhs, objects: objects)
      if lhsDisplay.caseInsensitiveCompare(rhsDisplay) != .orderedSame {
        return lhsDisplay.caseInsensitiveCompare(rhsDisplay) == .orderedAscending
      }
      if lhs.size != rhs.size {
        return lhs.size > rhs.size
      }
      let lhsName = lhs.demangled ?? lhs.name
      let rhsName = rhs.demangled ?? rhs.name
      return lhsName < rhsName
    }
  }

  private static func displayPath(for symbol: SymbolRecord, objects: [ObjectRecord?]) -> String {
    if let object = objects[safe: symbol.objectIndex] ?? nil {
      return object.path
    }
    return symbol.name
  }
}

/// Container for the parsed link-map information required by the analyzer.
struct LinkMapData: Equatable {
  let path: URL
  var objects: [ObjectRecord?]
  var symbols: [SymbolRecord]
  let lineCount: Int
}

/// Aggregated output of the debug-vs-release comparison.
struct AnalysisResult: Equatable {
  let totalDebugSymbols: Int
  let totalReleaseSymbols: Int
  let unusedSymbols: [SymbolRecord]
  /// User-owned debug objects keyed by original link-map indices.
  let debugObjects: [ObjectRecord?]
  /// User-owned objects that appear unused in the release map.
  let unusedObjects: [ObjectRecord]
}

// MARK: - CLI Configuration

/// Command-line configuration supplied to the analyzer.
struct Configuration {
  /// Debug build link-map URL.
  let debugURL: URL
  /// Release build link-map URL.
  let releaseURL: URL
  /// Optional project root used to relativize diagnostic paths and locate sources.
  let projectRoot: URL?
  let demangle: Bool
  let groupLimit: Int
  /// Optional destination for writing the final report to disk.
  let outputURL: URL?
  /// Enables verbose logging when true.
  let verbose: Bool
  /// Additional source path prefixes to probe when resolving object files. When left empty the analyzer attempts to
  /// infer useful defaults from `SCRIPT_INPUT_FILE_*` entries emitted by Xcode run-script build phases.
  let sourcePrefixes: [String]
}

/// Command-line parsing failures produced by `parseArguments()`.
enum CLIError: Error, CustomStringConvertible {
  case missingValue(String)
  case missingOption(String)
  case fileNotFound(String)
  case invalidNumber(String, String)
  case invalidValue(String, String)
  case unknownOption(String)
  case helpRequested

  var description: String {
    switch self {
    case .missingValue(let option):
      return "Missing value for \(option)."
    case .missingOption(let message):
      return message
    case .fileNotFound(let path):
      return "File not found: \(path)."
    case .invalidNumber(let option, let value):
      return "Invalid numeric value '\(value)' for \(option)."
    case .invalidValue(let option, let value):
      return "Invalid value '\(value)' for \(option)."
    case .unknownOption(let option):
      return "Unrecognized option \(option)."
    case .helpRequested:
      return ""
    }
  }
}
