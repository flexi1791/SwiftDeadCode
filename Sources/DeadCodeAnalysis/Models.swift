import Foundation

// MARK: - Data Models

/// Summary of an object-file listing extracted from the link map.
struct ObjectRecord {
  let index: Int
  let path: String

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

/// A best-effort mapping between a symbol/object and its human-readable source location.
struct SourceHint {
  let display: String
  let url: URL?
  let hasSource: Bool
}

/// Captures a debug-only symbol along with contextual metadata for reporting.
struct DebugOnlySymbol {
  let symbol: SymbolRecord
  let object: ObjectRecord?
  var demangled: String?
  let sourceHint: SourceHint
}

/// Candidate symbol awaiting allow-list filtering.
struct CandidateSymbol {
  let symbol: SymbolRecord
  let object: ObjectRecord?
  let sourceHint: SourceHint
}

/// Aggregated output of the debug-vs-release comparison.
struct AnalysisResult {
  let totalDebugSymbols: Int
  let totalReleaseSymbols: Int
  let rawDebugOnlyCount: Int
  let rawDebugOnlySize: UInt64
  let filteredSymbols: [DebugOnlySymbol]
  let filteredSize: UInt64
  let lowHangingFiles: [LowHangingFruit]
}

/// Grouped diagnostic entry pointing at files with debug-only symbols.
struct LowHangingFruit {
  let objectPath: String
  let sourceHint: SourceHint
  let debugOnlySize: UInt64
  let symbolCount: Int
}

// MARK: - CLI Configuration

/// Command-line configuration supplied to the analyzer.
struct Configuration {
  let debugURL: URL
  let releaseURL: URL
  let projectRoot: URL?
  let includePods: Bool
  let demangle: Bool
  let limit: Int
  let groupLimit: Int
  let outputURL: URL?
  let verbose: Bool
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
