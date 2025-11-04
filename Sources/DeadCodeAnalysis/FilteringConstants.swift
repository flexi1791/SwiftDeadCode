import Foundation

// MARK: - Filtering Constants
let allowListSuffixes: Set<String> = [
  // Function-level usage
  "F",    // Function
  "FC",   // Initializer
  "FD",   // Deinitializer
  "FE",   // Convenience initializer
  "FG",   // Generic initializer
  "FH",   // Required initializer
  "FZ",   // Static/global function
  "FY",   // Async function
  "FYA",  // Async accessor or closure thunk
  "FYD",  // Async deinitializer variant
  "FYT",  // Async throwing function
  "FYTA", // Async throwing accessor
  "FYZ",  // Async static/global function
  "FQ",   // Generic function specialization
  "FT",   // Throwing function
  "FTZ",  // Throwing static/global function
  "FCY",  // Async initializer
  "FCZ",  // Static initializer
  "FCF",  // Factory initializer variant
  "FYQ",  // Async reabstraction function
  "FCQ",  // Constructor with context
  "TF",   // Top-level function
  "TFZ",  // Top-level static function
  "VP",   // Static property
  
  // Structural usage (safe additions)
  "TW",   // Type witness — confirms protocol conformance is linked
  "WL",   // Witness table — confirms protocol conformance is used
  "Wl",   // Witness table (lowercase L) — variant
  "MN",   // Metadata — emitted only when type is instantiated or referenced
  "MF",   // Metadata function — used for runtime type resolution
  "AAMA",  // Associated type metadata access — confirms protocol usage with associated types
  
  //
  "WXX",
  "WCPTM",
  "WCA",
]


/// Lowercased substrings that identify non-actionable Swift symbols.
let nonSwiftNoiseTokensLowercased: [String] = [
  "symbolic",
  "literal string",
  "___unnamed",
  "_reflection_descriptor",
  "__swift5",
  "__swift4",
  "__swift3",
  "_objc_protocol_$_",
  "_objc_$_protocol_refs_",
  "_objc_label_protocol_$_",
  "_objc_class_$_",
  "_objc_metaclass_$_",
  "get_witness_table",
  "get_underlying",
  "witness_table",
  ".str.",
  "l_.str",
  "previewfmf_",
  "previewregistry",
  "previewprovider",
  "l_keypath_get_arg_layout",
  "l_keypath_arg_init",
  "withmutation",
  "shouldnotifyobservers",
  "block_copy_helper",
  "block_destroy_helper",
  "block_descriptor",
  "keypath_get_selector",
  "swift_get_extra_inhabitant_index",
  "_swift_store_extra_inhabitant_index",
  "swift_store_extra_inhabitant_index",
  "associated conformance",
  "_resumecheckedthrowingcontinuation",
  "fmu_"
]

/// Prefixes that quickly eliminate well-known tool-generated symbols.
let nonSwiftNoisePrefixesLowercased: [String] = [
  "_objc_",
  "__swift_force_load",
  "__swift_runtime",
  "__swift_instantiate",
  "___swift_",
  "l_.str",
  "l_metadata",
  "l_objectdestroy",
  "l_get_witness_table",
  "l_get_underlying",
  "l_keypath",
  "l_objc"
]

/// Substrings that only appear in demangled output and should be filtered.
let demangledNoiseTokens: [String] = [
  "protocol witness",
  "dispatch thunk",
  "reabstraction thunk",
  "partial apply forwarder",
  "partial apply",
  "implicit closure #",
  "closure #",
  "value witness",
  "witness table",
  "suspend resume partial function",
  "outlined copy",
  "outlined consume",
  "outlined assign",
  "outlined init",
  "outlined destroy",
  "type metadata accessor",
  "type metadata completion",
  "associated conformance",
  "specialized globalinit",
  "one-time initialization function",
  "variable initialization expression",
  "materialize for set",
  "key path setter",
  "key path getter",
  "heap destroyer",
  "heap assignor",
  "destroyer",
  "assignor",
  "destructor",
  ".__derived_enum_equals",
  "metadata instantiation cache",
  "protocol conformance descriptor runtime record",
  "protocol conformance descriptor for",
  "property descriptor for",
  "type metadata for",
  "nominal type descriptor runtime record",
  "opaque type descriptor runtime record",
  "opaque type descriptor for",
  "lazy cache variable for type metadata",
  "demangling cache variable for",
  "reflection metadata",
  "anonymous descriptor",
  "associated type witness table accessor",
  "base witness table accessor",
  "method descriptor",
  ".modify :",
  "default argument",
  "defaultvalue",
  "default value",
  "async function pointer",
  "property wrapper backing initializer",
  "previewfmf_",
  "previewregistry",
  "previewprovider",
  "type metadata instantiation function",
  "l_keypath_get_arg_layout",
  "l_keypath_arg_init",
  "withmutation",
  "shouldnotifyobservers",
  "__allocating_init",
  "observation",
  "accessormetadata",
  "fmu_"
]

/// Frameworks that should never be reported as project-owned modules.
let systemModuleNames: Set<String> = [
  "Swift", "SwiftUI", "Combine", "Foundation", "UIKit", "AppKit", "CoreData", "CoreGraphics",
  "SpriteKit", "SceneKit", "Metal", "MetalKit", "CoreLocation", "CoreImage", "CoreMedia",
  "AVFoundation", "GameplayKit", "MapKit", "WidgetKit", "Contacts", "ContactsUI", "CloudKit",
  "Network", "AuthenticationServices", "UserNotifications", "ReplayKit", "GameKit", "CoreMotion",
  "CoreTelephony", "WebKit", "StoreKit", "Intents", "Vision", "RealityKit", "ARKit", "PDFKit",
  "DeveloperToolsSupport"
]

/// Characters that permit stripping a module prefix when encountered immediately prior to the module name.
let moduleStripPrecedingCharacters: Set<Character> = [
  " ", "\t", "\n", "\r", "(", "<", "[", "{", "=", ":", ",", "&", "@", "*", "+", "-",
  ">", ".", "?", "!", "'", "\"", "|", "/"
]
