import Foundation

/// Parses command-line arguments and environment overrides to yield the analyzer configuration.
/// - Throws: A `CLIError` when arguments are missing or invalid.
/// - Returns: A populated `Configuration` struct.
func parseArguments() throws -> Configuration {
  /// Absolute or relative path to the debug build link map supplied via CLI or environment.
  var debugPath: String? = nil
  /// Absolute or relative path to the release build link map supplied via CLI or environment.
  var releasePath: String? = nil
  /// Optional project root used to resolve source files on disk.
  var projectRootPath: String? = nil
  /// Whether symbol names should be demangled using `swift-demangle`.
  var demangle = true
  /// Maximum number of grouped file entries to report (0 = unlimited).
  var groupLimit = 0
  /// Optional filesystem path where the report should be written.
  var outputPath: String? = nil
  /// Enables verbose status output when true.
  var verbose = false
  /// Additional relative prefixes to search beneath the project root when resolving sources. When omitted the tool
  /// attempts to infer reasonable defaults from `SCRIPT_INPUT_FILE_*` entries provided by an Xcode Run Script phase.
  var sourcePrefixes: [String] = []

  var index = 1
  let args = CommandLine.arguments
  while index < args.count {
    let arg = args[index]
    switch arg {
  case "--debug", "-d": // Path to the debug build .linkmap
      index += 1
      guard index < args.count else { throw CLIError.missingValue(arg) }
      debugPath = args[index]
  case "--release", "-r": // Path to the release build .linkmap
      index += 1
      guard index < args.count else { throw CLIError.missingValue(arg) }
      releasePath = args[index]
  case "--out", "-out": // Destination file for the textual report
      index += 1
      guard index < args.count else { throw CLIError.missingValue(arg) }
      outputPath = args[index]
  case "--project-root", "-p": // Project root used for source resolution
      index += 1
      guard index < args.count else { throw CLIError.missingValue(arg) }
      projectRootPath = args[index]
  case "--demangle": // Explicitly enable demangling (default)
      demangle = true
  case "--no-demangle", "--no_demangle": // Disable demangling for faster runs
      demangle = false
  case "--verbose": // Emit verbose logging to stderr
      verbose = true
  case "--group-limit": // Maximum number of grouped files to report
      index += 1
      guard index < args.count else { throw CLIError.missingValue(arg) }
      guard let value = Int(args[index]), value > 0 else { throw CLIError.invalidNumber(arg, args[index]) }
      groupLimit = value
  case "--source-prefix": // Additional relative path to consider when resolving sources
      index += 1
      guard index < args.count else { throw CLIError.missingValue(arg) }
      let value = args[index]
      if !value.isEmpty {
        sourcePrefixes.append(value)
      }
  case "--help", "-h": // Print usage and exit
      throw CLIError.helpRequested
    default:
      if arg.hasPrefix("-") {
        throw CLIError.unknownOption(arg)
      } else {
        if debugPath == nil {
          debugPath = arg
        } else if releasePath == nil {
          releasePath = arg
        } else {
          throw CLIError.unknownOption(arg)
        }
      }
    }
    index += 1
  }

  let env = ProcessInfo.processInfo.environment
  // Allow DEBUG_LINKMAP/RELEASE_LINKMAP overrides when CLI flags are omitted.
  if debugPath == nil {
    debugPath = env["DEBUG_LINKMAP"]
  }
  if releasePath == nil {
    releasePath = env["RELEASE_LINKMAP"]
  }
  if projectRootPath == nil {
    projectRootPath = env["PROJECT_DIR"]
  }
  // Allow multiple prefixes to be supplied via DEAD_CODE_SOURCE_PREFIXES (colon separated).
  if sourcePrefixes.isEmpty, let envPrefixes = env["DEAD_CODE_SOURCE_PREFIXES"], !envPrefixes.isEmpty {
    sourcePrefixes = envPrefixes.split(separator: ":").map(String.init)
  }

  guard let debugPath else {
    throw CLIError.missingOption("Missing debug link map path")
  }
  guard let releasePath else {
    throw CLIError.missingOption("Missing release link map path")
  }

  let debugURL = URL(fileURLWithPath: debugPath)
  let releaseURL = URL(fileURLWithPath: releasePath)
  var projectRootURL: URL? = nil
  if let projectRootPath {
    projectRootURL = URL(fileURLWithPath: projectRootPath)
  }

  if sourcePrefixes.isEmpty {
    // When invoked via an Xcode build script, SCRIPT_INPUT_FILE_* entries often capture module roots.
    if let scriptInputCountString = env["SCRIPT_INPUT_FILE_COUNT"], let count = Int(scriptInputCountString), count > 0 {
      var discovered: [String] = []
      for idx in 0..<count {
        let key = "SCRIPT_INPUT_FILE_\(idx)"
        if let value = env[key], !value.isEmpty {
          let url = URL(fileURLWithPath: value)
          let parent = url.deletingLastPathComponent().lastPathComponent
          if !parent.isEmpty {
            discovered.append(parent)
          }
        }
      }
      if !discovered.isEmpty {
        sourcePrefixes = Array(Set(discovered))
      }
    }
  }

  return Configuration(
    debugURL: debugURL,
    releaseURL: releaseURL,
    projectRoot: projectRootURL,
    demangle: demangle,
    groupLimit: groupLimit,
    outputURL: outputPath.map { URL(fileURLWithPath: $0) },
    verbose: verbose,
    sourcePrefixes: sourcePrefixes
  )
}

/// Prints the command-line usage help text.
func printUsage() {
  let toolName = URL(fileURLWithPath: CommandLine.arguments.first ?? "dead_code_analysis.swift").lastPathComponent
  let message = """
    Usage: \(toolName) --debug <Debug.linkmap> --release <Release.linkmap> [options]

    Options:
      --project-root <path>   Root of the project for source mapping (defaults to PROJECT_DIR).
      --demangle              Demangle Swift symbols using swift-demangle.
      --group-limit <N>       Limit the number of file groups (default: 12).
      --out <path>            Write the report to the given file path.
      --source-prefix <path>  Additional relative path to prepend when locating sources (repeatable; defaults to
                              Xcode SCRIPT_INPUT_FILE_* parents when available).
      --verbose               Emit additional diagnostic logging to stderr.
      --help                  Show this help message.

    Environment overrides:
      DEBUG_LINKMAP=/path/to/Debug.linkmap
      RELEASE_LINKMAP=/path/to/Release.linkmap
      DEAD_CODE_SOURCE_PREFIXES=prefix1:prefix2
    When no source prefixes are supplied explicitly the tool inspects SCRIPT_INPUT_FILE_* entries to seed defaults.
    """
  print(message)
}
