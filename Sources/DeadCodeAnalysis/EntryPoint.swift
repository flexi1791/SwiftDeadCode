import Foundation

/// Entry point used by the CLI wrapper as well as the standalone script variant.
public func runDeadCodeAnalysis() {
  do {
    let config = try parseArguments()
    let debugMap = try parseLinkMap(at: config.debugURL)
    DeadCodeAnalysis.Logger.logStatus("Parsed \(debugMap.path.lastPathComponent): \(debugMap.lineCount) lines")
    let releaseMap = try parseLinkMap(at: config.releaseURL)
    DeadCodeAnalysis.Logger.logStatus("Parsed \(releaseMap.path.lastPathComponent): \(releaseMap.lineCount) lines")
    let sourceIndex = buildSourceIndex(root: config.projectRoot, includePods: config.includePods)
    let analysis = analyze(debug: debugMap, release: releaseMap, config: config, sourceIndex: sourceIndex)
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
