import Foundation

// MARK: - Data Models

/// Summary of an object-file listing extracted from the link map.
struct ObjectRecord {
  let index: Int
  let path: String
  var sourceURL: URL?

  var baseName: String {
    URL(fileURLWithPath: path).lastPathComponent
  }
}

/// Represents an individual symbol entry inside the link map.
struct SymbolRecord {
  let address: UInt64
  let size: UInt64
  let objectIndex: Int
  let name: String
}

/// Container for the parsed link-map information required by the analyzer.
struct LinkMapData {
  let path: URL
  let objects: [Int: ObjectRecord]
  let symbols: [SymbolRecord]
  let lineCount: Int
}

/// Captures a debug-only symbol along with contextual metadata for reporting.
struct DebugOnlySymbol {
  let symbol: SymbolRecord
  let object: ObjectRecord?
  var demangled: String?
}

/// Candidate symbol awaiting allow-list filtering.
struct CandidateSymbol {
  let symbol: SymbolRecord
  let object: ObjectRecord?
}

/// Aggregated output of the debug-vs-release comparison.
struct AnalysisResult {
  let totalDebugSymbols: Int
  let totalReleaseSymbols: Int
  let rawDebugOnlyCount: Int
  let rawDebugOnlySize: UInt64
  let filteredSymbols: [DebugOnlySymbol]
  let filteredSize: UInt64
  /// Files and object files that contribute exclusively to the debug build.
  let debugOnlyFiles: [DebugOnlyFile]
}

/// Summary of a file or object that only appears in the debug build.
struct DebugOnlyFile {
  let objectPath: String
  let sourceURL: URL?
  let debugOnlySize: UInt64
  let symbolCount: Int
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
