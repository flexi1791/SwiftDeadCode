import Foundation

/// Parses command-line arguments and environment overrides to yield the analyzer configuration.
/// - Throws: A `CLIError` when arguments are missing or invalid.
/// - Returns: A populated `Configuration` struct.
func parseArguments() throws -> Configuration {
  var debugPath: String? = nil
  var releasePath: String? = nil
  var projectRootPath: String? = nil
  var includePods = false
  var demangle = true
  var limit = 0
  var groupLimit = 0
  var outputPath: String? = nil
  var verbose = false
  var sourcePrefixes: [String] = []

  var index = 1
  let args = CommandLine.arguments
  while index < args.count {
    let arg = args[index]
    switch arg {
    case "--debug", "-d":
      index += 1
      guard index < args.count else { throw CLIError.missingValue(arg) }
      debugPath = args[index]
    case "--release", "-r":
      index += 1
      guard index < args.count else { throw CLIError.missingValue(arg) }
      releasePath = args[index]
    case "--out", "-out":
      index += 1
      guard index < args.count else { throw CLIError.missingValue(arg) }
      outputPath = args[index]
    case "--project-root", "-p":
      index += 1
      guard index < args.count else { throw CLIError.missingValue(arg) }
      projectRootPath = args[index]
    case "--include-pods":
      includePods = true
    case "--demangle":
      demangle = true
    case "--no-demangle", "--no_demangle":
      demangle = false
    case "--verbose":
      verbose = true
    case "--limit":
      index += 1
      guard index < args.count else { throw CLIError.missingValue(arg) }
      guard let value = Int(args[index]), value > 0 else { throw CLIError.invalidNumber(arg, args[index]) }
      limit = value
    case "--group-limit":
      index += 1
      guard index < args.count else { throw CLIError.missingValue(arg) }
      guard let value = Int(args[index]), value > 0 else { throw CLIError.invalidNumber(arg, args[index]) }
      groupLimit = value
    case "--source-prefix":
      index += 1
      guard index < args.count else { throw CLIError.missingValue(arg) }
      let value = args[index]
      if !value.isEmpty {
        sourcePrefixes.append(value)
      }
    case "--help", "-h":
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
  if debugPath == nil {
    debugPath = env["DEBUG_LINKMAP"]
  }
  if releasePath == nil {
    releasePath = env["RELEASE_LINKMAP"]
  }
  if projectRootPath == nil {
    projectRootPath = env["PROJECT_DIR"]
  }
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
    includePods: includePods,
    demangle: demangle,
    limit: limit,
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
      --include-pods          Include Pods/ and other third-party objects in the analysis.
      --demangle              Demangle Swift symbols using swift-demangle.
      --limit <N>             Limit the number of symbol rows (default: 50).
      --group-limit <N>       Limit the number of file groups (default: 12).
      --out <path>            Write the report to the given file path.
      --source-prefix <path>  Additional relative path to prepend when locating sources (repeatable).
      --verbose               Emit additional diagnostic logging to stderr.
      --help                  Show this help message.

    Environment overrides:
      DEBUG_LINKMAP=/path/to/Debug.linkmap
      RELEASE_LINKMAP=/path/to/Release.linkmap
      DEAD_CODE_SOURCE_PREFIXES=prefix1:prefix2
    """
  print(message)
}
