# SwiftDeadCode

SwiftDeadCode compares the debug and release link maps produced by Xcode to highlight
symbols, objects, and source files that ship only in debug builds. The report is
formatted as Xcode-style warnings so you can jump directly to the files that are safe
to prune.

## Prerequisites

The tool inspects link map files emitted by the linker. Ensure both debug and release
configurations produce link maps by updating the build settings of the targets you care
about. The recommendations below assume an Xcode-based iOS or macOS project, but they
apply to any target that produces a `.linkmap` file.

### Configure LTO per build configuration

`LLVM_LTO` should be disabled for debug to keep builds fast and to expose the debug-only
symbols we want to catch, while remaining enabled for release to match your shipping
binary. In Xcode:

1. Select the target in the project navigator and open the **Build Settings** tab.
2. Filter for **“Link-Time Optimization”** or the `LLVM_LTO` setting.
3. Set **Debug** to **`No`**.
4. Set **Release** (and any other shipping configuration) to **`Yes`**.

This keeps the release configuration optimized while retaining debuggability in debug
builds.

### Emit link maps for each configuration

Add the following to the target’s build settings so the linker writes human-readable
link map files into `/tmp` for every configuration. Use the **Build Settings** tab,
search for **“Other Linker Flags”**, and append:

```
OTHER_LDFLAGS = (
  "-Xlinker",
  "-map",
  "-Xlinker",
  "/tmp/linkermap_$(CONFIGURATION).txt",
  "-Xlinker",
  "-dead_strip",
);
```

- `-map` requests a link map at the specified path.
- `-dead_strip` mirrors the default release behaviour so unused symbols are removed.
- The `$(CONFIGURATION)` substitution produces distinct files such as
  `/tmp/linkermap_Debug.txt` and `/tmp/linkermap_Release.txt`.

> Tip: Clean the derived data folder or delete old `/tmp/linkermap_*.txt` files when
> switching branches to avoid analysing stale data.

### Optional: Supply module hints to improve source resolution

If you run the analyzer from an Xcode Run Script phase, populate `SCRIPT_INPUT_FILE_*`
variables with module directories. SwiftDeadCode will automatically convert their parent
folders into `sourcePrefixes`, improving its ability to map object files back to source
paths.

## Installing and running the analyzer

Clone the repository and build with SwiftPM:

```bash
swift build
```

To analyse a pair of link maps:

```bash
swift run dead-code-analysis \
  --debug /tmp/linkermap_Debug.txt \
  --release /tmp/linkermap_Release.txt \
  --project-root /path/to/YourProject.xcodeproj/..
```

Key flags:

- `--project-root` helps relativize diagnostic paths. If omitted, the tool falls back to
  the `PROJECT_DIR` environment variable.
- `--group-limit <N>` limits the number of file groups printed when the report is long.
- `--source-prefix <path>` can be repeated to prepend additional directories when
  resolving source files. When not provided, the analyzer inspects `SCRIPT_INPUT_FILE_*`
  entries and `DEAD_CODE_SOURCE_PREFIXES` for defaults.
- `--out <path>` writes the report to disk in addition to `stdout`.
- `--verbose` prints the raw symbol counts and link map paths being analysed.

Environment variables can replace the flag counterparts:

```
DEBUG_LINKMAP=/tmp/linkermap_Debug.txt
RELEASE_LINKMAP=/tmp/linkermap_Release.txt
DEAD_CODE_SOURCE_PREFIXES=App:Features
```

## Xcode run script integration

Automate the analysis by adding a Run Script phase that executes after **Link Binary With Libraries**.

### 1. Create an input file list

The analyzer uses `SCRIPT_INPUT_FILE_*` values to seed `sourcePrefixes`. Populate
`$(SRCROOT)/BuildSupport/DeadCodeAnalysisInputs.xcfilelist` with one directory per
module whose sources you care about, for example:

```
# BuildSupport/DeadCodeAnalysisInputs.xcfilelist
$(SRCROOT)/App
```

### 2. Add the run script phase

Insert a new Run Script phase and paste the script below. Keep **Shell** set to
`/bin/sh` and check **“Show environment variables in build log”** for easier debugging.

```sh
#!/bin/sh
set -eo pipefail

DEBUG_MAP="/tmp/linkermap_Debug.txt"
RELEASE_MAP="/tmp/linkermap_Release.txt"
OUTPUT="/tmp/dead_symbols_report.txt"

# Reconstruct the DerivedData root from TARGET_BUILD_DIR
DERIVED_DATA_DIR="${TARGET_BUILD_DIR%/Build/*}"
PACKAGES_DIR="${DERIVED_DATA_DIR}/SourcePackages"
REMOTE_PACKAGE_SRC="${PACKAGES_DIR}/checkouts/SwiftDeadCode"

# Optional local override (adjust path if needed)
LOCAL_PACKAGE_SRC="${SRCROOT}/../SwiftDeadCode"

# Default to remote
PACKAGE_SRC="${REMOTE_PACKAGE_SRC}"

# If remote doesn't exist, try local
if [ ! -d "${REMOTE_PACKAGE_SRC}" ]; then
  if [ -d "${LOCAL_PACKAGE_SRC}" ]; then
    echo "warning: Remote SwiftDeadCode not found, using local package at ${LOCAL_PACKAGE_SRC}" >&2
    PACKAGE_SRC="${LOCAL_PACKAGE_SRC}"
  else
    echo "error: SwiftDeadCode checkout not found at ${REMOTE_PACKAGE_SRC}" >&2
    echo "error: Run “xcodebuild -resolvePackageDependencies” (or use File ▸ Packages ▸ Resolve Package Dependencies in Xcode) and retry." >&2
    exit 1
  fi
fi

echo "Using SwiftDeadCode at: ${PACKAGE_SRC}"

BUILD_DIR_OVERRIDE="$(mktemp -d /tmp/dead-code-analysis-build.XXXXXX)"

cleanup() {
  /bin/rm -rf "${BUILD_DIR_OVERRIDE}"
}
trap cleanup EXIT

export DEAD_CODE_ANALYSIS_BUILD_DIR="${BUILD_DIR_OVERRIDE}"

exec /usr/bin/xcrun --sdk macosx swift run --disable-sandbox \
  --package-path "${PACKAGE_SRC}" \
  --build-path "${BUILD_DIR_OVERRIDE}" \
  dead-code-analysis \
  --debug "${DEBUG_MAP}" \
  --release "${RELEASE_MAP}" \
  --out "${OUTPUT}" \
  --demangle
```

Place this phase **after** the linking step so both link maps exist. The script prefers
the Swift Package Manager checkout under DerivedData but can fall back to a sibling clone
(`../SwiftDeadCode`) if you want to iterate locally.

### 3. Configure file lists

- **Input File Lists**: add `$(SRCROOT)/BuildSupport/DeadCodeAnalysisInputs.xcfilelist` so
  Xcode tracks the directories that seed `SCRIPT_INPUT_FILE_*`.
- **Output Files**: specify
  `$(TEMP_DIR)/DeadCodeAnalysisPackage` and `$(TEMP_DIR)/dead-code-analysis-build`. Touching
  these paths keeps Xcode from re-running the script unnecessarily; the SwiftPM build
  directory is already created via the `--build-path` flag, so Xcode treats the script as
  up to date unless inputs change.

The analyzer writes `/tmp/dead_symbols_report.txt`. Open it directly or surface it in the
build log with `cat "${OUTPUT}"` if you prefer inline diagnostics.

## Example output

```
/Users/acme/App/Sources/Feature/HomeView.swift:1:1: warning: HomeView.swift - Home/Screens/HomeView.swift
/Users/acme/App/Sources/Feature/HomeView.swift:1:1: warning:     HomeView.previewProvider [Preview]
/Users/acme/App/Sources/Diagnostics/DebugLogger.swift:1:1: warning: DebugLogger.swift - Diagnostics/DebugLogger.swift
```

Each warning points at a file or symbol that exists only in the debug build after all
filters (such as test bundles and third-party pods) have been applied.

## Next steps

1. Delete or wrap the flagged code with `#if DEBUG` guards if it should not ship.
2. Rerun `swift run dead-code-analysis …` after the cleanup to confirm the warnings are
   gone.
3. Integrate the tool into CI by running it as part of a “Release” verification job.
