import Foundation

/// Entry point used by the CLI wrapper as well as the standalone script variant.
public func runDeadCodeAnalysis() {
  do {
    let config = try parseArguments()
    let debugMap = try parseLinkMap(at: config.debugURL)
    DeadCodeAnalysis.Logger.logStatus("Parsed \(debugMap.path.lastPathComponent): \(debugMap.lineCount) lines")
    let releaseMap = try parseLinkMap(at: config.releaseURL)
    DeadCodeAnalysis.Logger.logStatus("Parsed \(releaseMap.path.lastPathComponent): \(releaseMap.lineCount) lines")
    let resolvedDebugObjects = resolveObjectSources(objects: debugMap.objects, projectRoot: config.projectRoot)
    let resolvedCount = resolvedDebugObjects.values.filter { $0.sourceURL != nil }.count
    DeadCodeAnalysis.Logger.logVerbose(config.verbose, "Resolved source paths for \(resolvedCount) of \(resolvedDebugObjects.count) objects")
    let debugWithSources = LinkMapData(path: debugMap.path, objects: resolvedDebugObjects, symbols: debugMap.symbols, lineCount: debugMap.lineCount)
    let analysis = analyze(debug: debugWithSources, release: releaseMap, config: config)
    printReport(analysis, config: config)
    if let outputURL = config.outputURL {
      let lines = reportLines(analysis, config: config)
      let text = lines.joined(separator: "\n") + "\n"
      let directory = outputURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
      try text.write(to: outputURL, atomically: true, encoding: .utf8)
    }
  } catch CLIError.helpRequested {
    printUsage()
    exit(EXIT_SUCCESS)
  } catch let error as CLIError {
    if !error.description.isEmpty {
      fputs("error: \(error.description)\n", stderr)
    }
    exit(EXIT_FAILURE)
  } catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
  }
}

#if !DEAD_CODE_ANALYSIS_PACKAGE
private let _deadCodeAnalysisAutoRun: Void = {
  runDeadCodeAnalysis()
  return ()
}()
#endif
