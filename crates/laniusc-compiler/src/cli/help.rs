use super::common::{
    LANIUS_DEFAULT_EMIT_TARGET,
    LANIUS_DISTRIBUTION_STATUS,
    LANIUS_EDITION_POLICY,
    LANIUS_EMIT_TARGETS,
    LANIUS_FORMATTER_CONTRACT,
    LANIUS_LANGUAGE_EDITION,
    LANIUS_LSP_CAPABILITIES_SCHEMA_NAME,
    LANIUS_LSP_CAPABILITIES_SCHEMA_VERSION,
    LANIUS_LSP_ERROR_DATA_SCHEMA_NAME,
    LANIUS_LSP_ERROR_DATA_SCHEMA_VERSION,
    LANIUS_LSP_EXPERIMENTAL_SCHEMA_NAME,
    LANIUS_LSP_EXPERIMENTAL_SCHEMA_VERSION,
    LANIUS_RELEASE_CHANNEL,
    LANIUS_TARGET_TRIPLES,
    LANIUS_X86_64_SUPPORT,
};
use crate::shader_artifacts;

/// Prints the full top-level CLI help text.
pub(crate) fn print_help() {
    eprintln!(
        "Usage: laniusc [-h|--help] [-V|--version] [--edition unstable-alpha] [--emit x86_64|wasm] [--target triple] [--diagnostic-format text|json|lsp-json] [--package-manifest path] [--package-lockfile path] [--stdlib path]... [--stdlib-root dir] [--source-root dir] [-o output] [--source-pack-descriptors] [--source-pack-manifest path] [--source-pack-library-manifest path] [--source-pack-artifact-root path] [--source-pack-metadata-only] [--source-pack-prepare-only] [--source-pack-metadata-max-libraries N] [--source-pack-metadata-max-source-files N] [--source-pack-build-from-metadata] [--source-pack-build-prepare-only] [--source-pack-build-max-items N] [--source-pack-max-items N] [--source-pack-max-ready-items N] <input.lani> [more-input.lani...]\n\
         Usage: laniusc check [--edition unstable-alpha] [--emit x86_64|wasm] [--target triple] [--diagnostic-format text|json|lsp-json] [--package-manifest path] [--package-lockfile path] [--stdlib-root dir] [--source-root dir] <input.lani>\n\
         Usage: laniusc package lock [--diagnostic-format text|json|lsp-json] --manifest path -o path\n\
         Usage: laniusc lsp [--diagnostic-format text|json|lsp-json] capabilities\n\
         Usage: laniusc lsp [--diagnostic-format text|json|lsp-json] serve --stdio\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] registry\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] codes\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] code CODE\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] categories\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] formats\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] formatter\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] version-policy\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] explain CODE\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-api API\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-apis\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-service SERVICE\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-service-apis SERVICE\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-services\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] commands\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] source-pack-progress --source-pack-artifact-root dir [--emit wasm|x86_64]\n\
         Usage: laniusc doctor [--skip-slangc-probe] [--diagnostic-format text|json|lsp-json]\n\
         Usage: laniusc fmt [--check] [--diagnostic-format text|json|lsp-json] (<input.lani> [more-input.lani...]|--stdin|-)\n\
         Emits the selected target using GPU lexing, GPU parsing, GPU type checking, and GPU emission.\n\
         check runs the same bounded GPU compiler path for diagnostics and exits without writing target bytes.\n\
         package lock generates a JSON package lockfile from a package manifest using control-plane package metadata only; semantic module identity still comes from parsed source records when the lockfile is used for compilation.\n\
         lsp capabilities prints no-run JSON metadata for editor experiments, including diagnostic codes, diagnostic format selectors, LSP source, severity, UTF-16 position encoding, full-document sync mode, explicit unsupported workspace scope, document formatting, and supported stdio methods. lsp serve --stdio handles initialize/shutdown without compiling source, accepts full-document didChange text only, formats opened documents with the lexical formatter without GPU work, and serves opened-document pull diagnostics through the GPU type-check path without target codegen.\n\
         diagnostics registry prints the stable diagnostic registry JSON directly for tools that do not need LSP capability metadata; diagnostics commands prints the no-run metadata command index and placeholder contract directly; diagnostics codes prints a compact diagnostic code index for wrappers and completion; diagnostics code prints one compact registry row or known:false for an unknown code; diagnostics categories groups codes by stable category for filter-building tools; diagnostics formats prints the accepted diagnostic render formats and payload contracts; diagnostics formatter prints the alpha formatter policy, CLI commands, LSP request options, diagnostic codes, and no-run guard contract; diagnostics version-policy prints no-run machine-readable compiler, edition, distribution, compatibility, target, tooling schema policy, metadata command discovery, and command-template placeholder metadata; diagnostics explain prints one code-specific JSON explanation; diagnostics runtime-api prints fail-closed runtime binding metadata for one qualified or service-qualified stdlib API; diagnostics runtime-apis prints the full fail-closed stdlib runtime-bound API index; diagnostics runtime-service prints one fail-closed runtime service boundary selected by id, service name, module path, capability constant, runtime probe, or qualified runtime-bound API; diagnostics runtime-service-apis prints the known-unbound API rows owned by one runtime service selected through the same runtime-service selectors; diagnostics runtime-services prints the fail-closed runtime service boundary table; diagnostics source-pack-progress prints persisted work-queue progress from source-pack artifact records without loading source.\n\
         doctor prints a compact no-run JSON toolchain/readiness report for installation checks, including compiler version, language edition, target surface, language-slice inventory metadata, diagnostic format metadata, Slang availability from SLANGC or PATH unless --skip-slangc-probe is passed, build metadata, Slang build timeout guardrails, readiness gate metadata, pass-contract/Pareas-shape metadata, stdlib boundary counts, links to detailed diagnostics commands, and guards proving it did not compile source, run shader loop audits, execute readiness gates, or create a GPU device.\n\
         fmt formats one or more source files in place using the alpha lexical formatter; --check verifies formatting without writing.\n\
         Current language edition: {edition}; {policy}.\n\
         --edition selects the language edition for this invocation; only {edition} is accepted today and unsupported editions are rejected before compilation.\n\
         Accepted emit targets: {targets}; default emit target: {default_target}.\n\
         Accepted target triples: {target_triples}; --target must match --emit and unsupported triples are rejected before compilation.\n\
         --diagnostic-format selects text, JSON, or LSP Diagnostic-shaped JSON rendering for compiler diagnostics and formatter check diagnostics; JSON diagnostics are emitted without the laniusc text prefix, and lsp-json is a single diagnostic object, not a language-server publishDiagnostics envelope.\n\
         --package-manifest loads a JSON package manifest with package, roots, optional stdlib_root, and entry fields; package names and paths are control-plane loading metadata only, while module identity still comes from parsed module/import records. It uses the in-memory source-root compiler path for compile/check, and can feed bounded source-pack metadata preparation with --source-pack-metadata-only.\n\
         --package-lockfile loads a JSON package lockfile with absolute resolved roots and entry path; package names and resolved paths remain control-plane loading metadata only, while module identity still comes from parsed module/import records. Lockfile replay metadata is validated before package lockfiles feed --source-pack-metadata-only.\n\
         Repeating --stdlib adds explicitly supplied source-pack files before positional user files; multi-file source-pack inputs compile only from an explicit prepared descriptor artifact root.\n\
         --source-root maps leading module-path imports from one entry file to files below a user source root, such as app::util -> src/app/util.lani; --stdlib-root can be combined with --source-root as a fallback for stdlib modules such as core::i32 -> stdlib/core/i32.lani. Root loading feeds discovered files to the module resolver without source rewriting; descriptor mode for source roots is not implemented yet.\n\
         --source-pack-manifest names a previously prepared JSON ExplicitSourcePackPathManifest artifact root; use --source-pack-library-manifest for bounded metadata preparation.\n\
         --source-pack-library-manifest reads newline-delimited JSON library records, each with library_id, source_file_count, path_list, and dependency_library_ids; each path_list is streamed line by line.\n\
         --source-pack-metadata-only stores source-pack metadata and exits; JSONL library manifests and package manifest/lockfile selectors store one bounded chunk by default, --source-pack-metadata-max-libraries overrides how many new libraries that metadata pass stores, and --source-pack-metadata-max-source-files bounds the source-file records consumed by that chunk; package selectors do not enable final source-pack descriptor, build, or link output. --source-pack-build-from-metadata builds and runs from persisted metadata.\n\
         --source-pack-prepare-only performs one bounded preparation chunk from source-pack inputs and exits: metadata first, then build preparation after metadata is complete.\n\
         --source-pack-build-prepare-only performs one bounded build-preparation chunk from persisted metadata and exits; --source-pack-build-max-items bounds that preparation chunk and defaults to 64.\n\
         --source-pack-descriptors is the default source-pack mode; descriptor builds currently write linked-output contract descriptors and require --emit-contract; --source-pack-artifact-root selects the persisted descriptor directory; --source-pack-max-items limits how many queued work items this invocation submits and is capped at 64.\n\
         x86_64 currently supports {x86_support}.\n\
         -h/--help prints this help and exits before compile argument validation.\n\
         -V/--version prints compiler, language-edition, release/distribution status, target, formatter, LSP schema, Slang, wgpu, build-profile, shader artifact digest, shader artifact size-guard details, and build-time Slang timeout guardrails.\n\
         Without an input file, compiles a tiny built-in sample to stdout using the default emit target.",
        edition = LANIUS_LANGUAGE_EDITION,
        policy = LANIUS_EDITION_POLICY,
        targets = LANIUS_EMIT_TARGETS,
        default_target = LANIUS_DEFAULT_EMIT_TARGET,
        target_triples = LANIUS_TARGET_TRIPLES,
        x86_support = LANIUS_X86_64_SUPPORT,
    );
}

/// Prints help for `laniusc package`.
pub(crate) fn print_package_help() {
    eprintln!(
        "Usage: laniusc package lock [--diagnostic-format text|json|lsp-json] --manifest path -o path\n\
         Generates package tooling artifacts.\n\
         lock resolves a package manifest and writes a JSON package lockfile.\n\
         --diagnostic-format selects text, JSON, or LSP Diagnostic-shaped JSON for package invocation diagnostics."
    );
}

/// Prints help for `laniusc package lock`.
pub(crate) fn print_package_lock_help() {
    eprintln!(
        "Usage: laniusc package lock [--diagnostic-format text|json|lsp-json] --manifest path -o path\n\
         Resolves a package manifest and writes a JSON package lockfile. Package roots and paths are control-plane loading metadata only; semantic module identity remains parsed from source.\n\
         --diagnostic-format selects text, JSON, or LSP Diagnostic-shaped JSON for package invocation diagnostics."
    );
}

/// Prints help for `laniusc lsp`.
pub(crate) fn print_lsp_help() {
    eprintln!(
        "Usage: laniusc lsp [--diagnostic-format text|json|lsp-json] capabilities\n\
         Usage: laniusc lsp [--diagnostic-format text|json|lsp-json] serve --stdio\n\
         capabilities prints no-run JSON metadata for editor experiments: diagnostic registry, diagnostic format registry, LSP source, severity, UTF-16 position encoding, full-document sync mode, explicit unsupported workspace scope, formatter metadata, and the supported stdio methods.\n\
         --diagnostic-format selects text, JSON, or LSP Diagnostic-shaped JSON for command-line invocation diagnostics before the stdio server starts.\n\
         serve --stdio starts a minimal JSON-RPC LSP server that handles initialize/shutdown without compiling source, tracks opened documents, rejects ranged incremental changes, returns full-document textDocument/formatting edits without GPU work, and returns pull diagnostics through textDocument/diagnostic without target codegen."
    );
}

/// Prints help for `laniusc diagnostics`.
pub(crate) fn print_diagnostics_help() {
    eprintln!(
        "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] registry\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] codes\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] code CODE\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] categories\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] formats\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] formatter\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] version-policy\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] explain CODE\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-api API\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-apis\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-service SERVICE\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-service-apis SERVICE\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-services\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] commands\n\
         Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] source-pack-progress --source-pack-artifact-root dir [--emit wasm|x86_64]\n\
         registry prints the combined diagnostic registry JSON: schema version, codes, categories, and unsupported-feature boundaries.\n\
         commands prints the no-run metadata command index with schema names, command templates, and placeholder examples for wrapper discovery.\n\
         codes prints a compact diagnostic code index with stable titles, categories, severity, LSP source/severity, and no-run guards.\n\
         code prints one compact diagnostic code row with stable title, category, severity, LSP source/severity, explain command, and no-run guards, or known:false for an unknown code.\n\
         categories prints stable diagnostic categories with grouped code metadata and unsupported-feature code markers.\n\
         formats prints accepted --diagnostic-format values with output stream, payload, position, and envelope metadata.\n\
         formatter prints the alpha formatter policy, CLI commands, LSP request options, diagnostic codes, and no-run guards.\n\
         version-policy prints compiler package version, language edition, release/distribution status, compatibility policy, target surface, tooling schema versions, and no-run metadata command discovery with placeholder metadata for focused lookup commands, without compiling source.\n\
         explain prints one code-specific JSON explanation without compiling source.\n\
         runtime-api prints one qualified or service-qualified stdlib API's known-unbound runtime binding row and owning service boundary without compiling or scanning source.\n\
         runtime-apis prints all known stdlib runtime-bound API rows and owning service-boundary rows without compiling or scanning source.\n\
         runtime-service prints one runtime service boundary selected by service id, service name, module path, capability constant, status probe, binding probe, or qualified runtime-bound API without compiling or scanning source.\n\
         runtime-service-apis prints the known-unbound runtime-bound API rows owned by one runtime service selected by service id, service name, module path, capability constant, status probe, binding probe, or qualified runtime-bound API without compiling or scanning source.\n\
         runtime-services prints all known runtime service boundary rows without compiling or scanning source.\n\
         source-pack-progress prints the persisted source-pack work-queue progress index for the selected emit target without loading source, creating a GPU device, or running target codegen.\n\
         Examples: laniusc diagnostics code LNC0018 looks up one stable diagnostic code; laniusc diagnostics code 'error[LNC0018]: unsupported CLI option value' accepts a copied diagnostic heading; laniusc diagnostics formats lists JSON and LSP diagnostic payload contracts; laniusc diagnostics formatter lists formatter/editor-wrapper policy; laniusc diagnostics version-policy lists machine-readable command discovery.\n\
         --diagnostic-format selects text, JSON, or LSP Diagnostic-shaped JSON for invocation diagnostics on this no-run tooling surface."
    );
}

/// Prints help for `laniusc diagnostics code`.
pub(crate) fn print_diagnostics_code_help() {
    eprintln!(
        "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] code CODE\n\
         Looks up one stable diagnostic code and prints a compact no-run JSON row, or known:false for an unknown code.\n\
         Accepted CODE selectors: LNC0018, lnc0018, or copied text containing one LNCdddd token.\n\
         Examples: laniusc diagnostics code LNC0018; laniusc diagnostics code 'error[LNC0018]: unsupported CLI option value'.\n\
         Use laniusc diagnostics codes for the compact code index, or laniusc diagnostics registry for the full registry."
    );
}

/// Prints help for `laniusc diagnostics explain`.
pub(crate) fn print_diagnostics_explain_help() {
    eprintln!(
        "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] explain CODE\n\
         Explains one stable diagnostic code and prints a no-run JSON document, or known:false for an unknown code.\n\
         Accepted CODE selectors: LNC0018, lnc0018, or copied text containing one LNCdddd token.\n\
         Examples: laniusc diagnostics explain LNC0018; laniusc diagnostics explain 'error[LNC0018]: unsupported CLI option value'.\n\
         Use laniusc diagnostics codes for the compact code index, or laniusc diagnostics code CODE for the compact row."
    );
}

/// Prints help for `laniusc doctor`.
pub(crate) fn print_doctor_help() {
    eprintln!(
        "Usage: laniusc doctor [--skip-slangc-probe] [--diagnostic-format text|json|lsp-json]\n\
         Prints a compact no-run JSON toolchain report for installation checks.\n\
         The report includes compiler version, language edition, target surface, language-slice inventory metadata, diagnostic format metadata, readiness gate metadata, pass-contract/Pareas-shape metadata, stdlib root/import contract counts plus links to detailed diagnostics commands, Slang availability from SLANGC or PATH unless --skip-slangc-probe is passed, shader artifact build metadata, build-time Slang timeout guardrails, and explicit no-run guards; it does not validate the inventory, scan stdlib source, run shader loop audits, compile source, create a GPU device, execute readiness gates, run generated gates, or invoke Pareas."
    );
}

/// Prints help for `laniusc fmt`.
pub(crate) fn print_fmt_help() {
    eprintln!(
        "Usage: laniusc fmt [--check] [--diagnostic-format text|json|lsp-json] (<input.lani> [more-input.lani...]|--stdin|-)\n\
         Formats one or more source files in place, or formats stdin to stdout with --stdin or -.\n\
         --check verifies formatting without writing.\n\
         --diagnostic-format selects text, JSON, or LSP Diagnostic-shaped JSON for check failures."
    );
}

/// Prints compiler and tooling version metadata.
pub(crate) fn print_version() {
    println!(
        "laniusc {}\n\
         language-edition: {}\n\
         edition-policy: {}\n\
         targets: {}\n\
         default-target: {}\n\
         target-triples: {}\n\
         x86_64: {}\n\
         formatter: {}\n\
         release-channel: {}\n\
         distribution-status: {}\n\
         lsp-capabilities-schema-name: {}\n\
         lsp-capabilities-schema: {}\n\
         lsp-experimental-schema-name: {}\n\
         lsp-experimental-schema: {}\n\
         lsp-error-data-schema-name: {}\n\
         lsp-error-data-schema: {}\n\
         slangc: {}\n\
         wgpu: {}\n\
         build-profile: {}\n\
         shader-artifact-digest: {}\n\
         shader-artifact-count: {}\n\
         shader-artifact-max-bytes: {}\n\
         shader-artifact-max-name: {}\n\
         shader-artifact-size-guard: {}\n\
         shader-artifact-max-spv-bytes: {}\n\
         slangc-version-timeout-ms: {}\n\
         shader-compile-timeout-ms: {}",
        env!("CARGO_PKG_VERSION"),
        LANIUS_LANGUAGE_EDITION,
        LANIUS_EDITION_POLICY,
        LANIUS_EMIT_TARGETS,
        LANIUS_DEFAULT_EMIT_TARGET,
        LANIUS_TARGET_TRIPLES,
        LANIUS_X86_64_SUPPORT,
        LANIUS_FORMATTER_CONTRACT,
        LANIUS_RELEASE_CHANNEL,
        LANIUS_DISTRIBUTION_STATUS,
        LANIUS_LSP_CAPABILITIES_SCHEMA_NAME,
        LANIUS_LSP_CAPABILITIES_SCHEMA_VERSION,
        LANIUS_LSP_EXPERIMENTAL_SCHEMA_NAME,
        LANIUS_LSP_EXPERIMENTAL_SCHEMA_VERSION,
        LANIUS_LSP_ERROR_DATA_SCHEMA_NAME,
        LANIUS_LSP_ERROR_DATA_SCHEMA_VERSION,
        option_env!("LANIUS_SLANGC_VERSION").unwrap_or("unknown"),
        option_env!("LANIUS_WGPU_VERSION").unwrap_or("unknown"),
        option_env!("LANIUS_BUILD_PROFILE").unwrap_or("unknown"),
        shader_artifacts::digest(),
        shader_artifacts::count_text(),
        shader_artifacts::max_spv_bytes_text(),
        shader_artifacts::max_spv_name(),
        shader_artifacts::size_guard_status(),
        shader_artifacts::size_guard_max_bytes_text(),
        option_env!("LANIUS_SLANGC_VERSION_TIMEOUT_MS").unwrap_or("unknown"),
        option_env!("LANIUS_SHADER_COMPILE_TIMEOUT_MS").unwrap_or("unknown"),
    );
}
