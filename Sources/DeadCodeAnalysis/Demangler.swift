import Foundation
import Dispatch

// MARK: - Demangling

/// Demangles the provided collection of canonical names in manageable batches.
/// - Parameters:
///   - names: The symbol names to demangle.
///   - verbose: Whether progress logging should be emitted.
/// - Returns: A dictionary mapping original symbol names to their demangled forms.
func demangleSymbols(_ names: [String], verbose: Bool) -> [String: String] {
  var canonicalToOriginals: [String: [String]] = [:]
  for name in names {
    guard let canonical = canonicalMangledName(name) else { continue }
    canonicalToOriginals[canonical, default: []].append(name)
  }

  let canonicalNames = Array(canonicalToOriginals.keys)
  guard !canonicalNames.isEmpty else { return [:] }

  let chunkSize = 200
  let batchCount = Int(ceil(Double(canonicalNames.count) / Double(chunkSize)))
  DeadCodeAnalysis.Logger.logVerbose(verbose, "Demangling \(canonicalNames.count) symbol(s) across \(batchCount) batch(es)...")

  var mapping: [String: String] = [:]
  var canonicalMap: [String: String] = [:]
  for batchIndex in 0..<batchCount {
    let start = batchIndex * chunkSize
    let end = min(start + chunkSize, canonicalNames.count)
    let chunk = Array(canonicalNames[start..<end])
    let chunkResult = demangleChunk(chunk, verbose: verbose, batchIndex: batchIndex, totalBatches: batchCount)
    for (canonical, demangled) in chunkResult {
      if canonicalMap[canonical] == nil {
        canonicalMap[canonical] = demangled
      }
      guard let originals = canonicalToOriginals[canonical] else { continue }
      for original in originals where mapping[original] == nil {
        mapping[original] = demangled
      }
    }
  }

  if verbose {
    let missing = canonicalNames.filter { canonicalMap[$0] == nil }
    if !missing.isEmpty {
      DeadCodeAnalysis.Logger.logVerbose(verbose, "Demangle missing \(missing.count) canonical symbol(s)")
    }
  }

  return mapping
}

/// Demangles a single batch of canonical names using `swift-demangle`.
/// - Parameters:
///   - candidates: The chunk of mangled names to demangle.
///   - verbose: Whether verbose logging is enabled.
///   - batchIndex: The zero-based index of the chunk.
///   - totalBatches: Total number of batches in the run.
/// - Returns: A dictionary mapping canonical names to demangled output.
func demangleChunk(_ candidates: [String], verbose: Bool, batchIndex: Int, totalBatches: Int) -> [String: String] {
  guard !candidates.isEmpty else { return [:] }

  let start = CFAbsoluteTimeGetCurrent()

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
  process.arguments = ["swift-demangle"] + candidates

  let outputPipe = Pipe()
  let errorPipe = Pipe()
  process.standardOutput = outputPipe
  process.standardError = errorPipe

  do {
    DeadCodeAnalysis.Logger.logVerbose(verbose, "Launching swift-demangle batch \(batchIndex + 1)...")
    try process.run()
  } catch {
  DeadCodeAnalysis.Logger.logStatus("swift-demangle launch failed for batch \(batchIndex + 1): \(error.localizedDescription)")
    return [:]
  }

  var outputData = Data()
  var errorData = Data()
  let dispatchGroup = DispatchGroup()
  dispatchGroup.enter()
  DispatchQueue.global(qos: .userInitiated).async {
    outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    dispatchGroup.leave()
  }
  dispatchGroup.enter()
  DispatchQueue.global(qos: .utility).async {
    errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    dispatchGroup.leave()
  }

  process.waitUntilExit()
  dispatchGroup.wait()

  let elapsed = CFAbsoluteTimeGetCurrent() - start
  if process.terminationStatus != 0 {
    if let errorString = String(data: errorData, encoding: .utf8), !errorString.isEmpty {
  DeadCodeAnalysis.Logger.logStatus("swift-demangle batch \(batchIndex + 1) exited with status \(process.terminationStatus): \(errorString.trimmingCharacters(in: .whitespacesAndNewlines))")
    } else {
  DeadCodeAnalysis.Logger.logStatus(String(format: "swift-demangle batch %d exited with status %d in %.2fs", batchIndex + 1, process.terminationStatus, elapsed))
    }
    return [:]
  }

  guard let output = String(data: outputData, encoding: .utf8) else { return [:] }

  var mapping: [String: String] = [:]
  var currentMangled: String? = nil
  var currentParts: [String] = []

  func flushCurrent() {
    guard let mangled = currentMangled else { return }
    let joined = currentParts.joined()
    if !joined.isEmpty {
      mapping[mangled] = joined
    }
    currentMangled = nil
    currentParts = []
  }

  for segment in output.split(maxSplits: Int.max, omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
    let line = String(segment)
    if line.isEmpty {
      flushCurrent()
      continue
    }
    if let range = line.range(of: " ---> ") {
      flushCurrent()
      let mangled = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
      let demangledPart = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
      currentMangled = mangled.isEmpty ? nil : mangled
      currentParts = demangledPart.isEmpty ? [] : [demangledPart]
    } else if currentMangled != nil {
      let part = line.trimmingCharacters(in: .whitespaces)
      if !part.isEmpty {
        currentParts.append(part)
      }
    }
  }
  flushCurrent()

  DeadCodeAnalysis.Logger.logVerbose(verbose, String(format: "Batch %d demangled %d in %.2fs", batchIndex + 1, mapping.count, elapsed))
  return mapping
}
