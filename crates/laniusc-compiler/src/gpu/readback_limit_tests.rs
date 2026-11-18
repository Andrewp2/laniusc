//! The limit on readbacks in the compile path.
//!
//! Every map of a buffer for reading goes through
//! `passes_core::begin_readback_map`, which takes a [`ReadbackLabel`] that only
//! the `readback_label!` (compile path) and `debug_readback_label!` (a tool or
//! an opt-in check) macros make, from a string literal. This test reads the
//! source for those literals and holds them to the lists below.
//!
//! - `Permanent` entries are the exceptions the compiler keeps: the final
//!   output of each target and the diagnostics of a failed build. There must
//!   be fewer than ten.
//! - `ToRemove` entries are readbacks that exist today and must go. Each names
//!   its row in `docs/compiler-host-work-audit.md`. An entry whose label no
//!   longer has a site fails the test, so the list shrinks as work lands.
//! - A new compile-path label fails the test until it is listed. Listing it as
//!   `ToRemove` needs an audit row; listing it as `Permanent` needs a reason
//!   it is the final output or a diagnostic.
//!
//! [`ReadbackLabel`]: crate::gpu::passes_core::ReadbackLabel

use std::{
    collections::{BTreeMap, BTreeSet},
    path::Path,
};

#[derive(Clone, Copy, Debug)]
enum Kind {
    Permanent,
    ToRemove { audit_row: &'static str },
}

use Kind::{Permanent, ToRemove};

struct Entry {
    label: &'static str,
    kind: Kind,
    reason: &'static str,
}

const fn keep(label: &'static str, reason: &'static str) -> Entry {
    Entry {
        label,
        kind: Permanent,
        reason,
    }
}

const fn remove(label: &'static str, audit_row: &'static str, reason: &'static str) -> Entry {
    Entry {
        label,
        kind: ToRemove { audit_row },
        reason,
    }
}

/// Fewer permanent readbacks than this, in total.
const PERMANENT_LIMIT: usize = 10;

/// Every readback label of the compile path.
const COMPILE_PATH: &[Entry] = &[
    // Permanent: final output and diagnostics.
    keep(
        "codegen.x86.link.resident.image",
        "final output: the linked native x86 executable and its status words",
    ),
    keep(
        "codegen.x86.link.page",
        "final output: the x86 executable the GPU linker writes without native inputs",
    ),
    keep(
        "codegen.x86.link.resident.sections",
        "final output for `--native-linker cc`: text and rodata the host linker takes",
    ),
    keep(
        "codegen.wasm.link.page.output",
        "final output: the linked WASM module",
    ),
    keep(
        "compiler.typecheck.diagnostic-token",
        "diagnostics of a failed build: the token of the first error",
    ),
    // The settings build (resident daemon, native x86), in order.
    remove(
        "semantic-interface artifact metadata",
        "R1",
        "length and status of the semantic interface the host keeps for dependents",
    ),
    remove(
        "semantic-interface artifact",
        "R2",
        "semantic interface bytes the host keeps for dependents",
    ),
    remove(
        "lexer.source-pack.fused.metadata",
        "R3",
        "token count and lexer status; sizes later buffers",
    ),
    remove(
        "parser.recorded-ll1-hir.status",
        "R4",
        "parser status and feature flags; mid-pipeline status check",
    ),
    remove(
        "type_check.call_inference",
        "R5",
        "call inference counters; mid-pipeline status and sizes",
    ),
    remove(
        "type_check.canonical.counts",
        "R6",
        "canonical type counters; decides a re-record",
    ),
    remove(
        "type_check.status",
        "R7",
        "type check status; mid-pipeline status check",
    ),
    remove(
        "lowering status readback",
        "R8",
        "lowering status and x86 object metadata; sizes the object payload read",
    ),
    remove(
        "x86 object payload readback",
        "R9",
        "x86 object bytes the host parses for retention and linking",
    ),
    remove(
        "program_retention.readback",
        "R10",
        "export status of a build with no object, such as check; settings no longer reaches it",
    ),
    remove(
        "retained_substitution.readback",
        "R11",
        "substitution status and counts; sizes the next stage",
    ),
    remove(
        "discovery.status",
        "R12",
        "discovery status and counts; sizes the projection",
    ),
    remove(
        "retained_projection.readback",
        "R13",
        "projection status and rows the host turns into instance inputs",
    ),
    remove(
        "codegen.x86.finalize.readback",
        "R17",
        "finalize status and sizes before the link",
    ),
    remove(
        "codegen.x86.link.resident.plan",
        "R18",
        "link plan status and image size; sizes the image read",
    ),
    // Reached by the other CLI modes.
    remove(
        "lex.source-pack.resident.count",
        "R20",
        "token count; sizes the parser buffers",
    ),
    remove(
        "parser.partial_parse_tree_capacity.status",
        "R21",
        "parse tree capacity; sizes the tree buffer",
    ),
    remove(
        "retained producer state",
        "R22",
        "trait producer counters; sizes the catalog",
    ),
    remove(
        "program proof wave progress",
        "R23",
        "proof wave state; decides another wave",
    ),
    remove(
        "retained catalog admission",
        "R24",
        "catalog admission receipts; status check",
    ),
    remove(
        "codegen.x86.link.symbol_partition.status",
        "R25",
        "symbol partition status; sizes the value read",
    ),
    remove(
        "codegen.x86.link.symbol_partition.values",
        "R26",
        "resolved symbol values the host lays out with",
    ),
    remove(
        "codegen.x86.link.layout_chunk",
        "R27",
        "layout chunk rows the host places sections with",
    ),
    remove(
        "Wasm object metadata readback",
        "R30",
        "WASM object status and lengths; sizes the payload read",
    ),
    remove(
        "Wasm object payload readback",
        "R31",
        "WASM object bytes the host links",
    ),
    remove(
        "codegen.wasm.link.resolve.status",
        "R32",
        "WASM symbol resolution status; sizes the target read",
    ),
    remove(
        "codegen.wasm.link.page.status",
        "R34",
        "WASM link status beside the output; fold into the output read",
    ),
    remove(
        "compiler.lowering.diagnostic-hir",
        "R36",
        "HIR row of a lowering error; fold into the one diagnostics read",
    ),
    remove(
        "desugar.readback",
        "R37",
        "desugar round sizes after an overflow; sizes a retry",
    ),
    // Not reached by the probed modes.
    remove("lex.count", "U1", "token count of the standalone lexer"),
    remove("lex.tokens", "U2", "tokens of the standalone lexer"),
    remove("lex.resident.count", "U3", "token count; sizes later buffers"),
    remove("lex.source-pack.count", "U4", "token count of a source pack"),
    remove("lex.source-pack.tokens", "U5", "tokens of a source pack"),
    remove("lexer.fused.metadata", "U6", "token count and lexer status"),
    remove("parser.readback", "U7", "parse results decoded on the host"),
    remove("parser.hir_item_readback", "U8", "HIR items decoded on the host"),
    remove(
        "parser.hir_fn_return_readback",
        "U9",
        "function return records decoded on the host",
    ),
    remove("parser.hir_semantic_count", "U10", "HIR counts; sizes later buffers"),
    remove("parser.resident-ll1.status", "U11", "parser status check"),
    remove("parser.resident-tree", "U12", "parse tree decoded on the host"),
    remove("parser.syntax.status_counters", "U13", "syntax check status"),
    remove(
        "compiler.syntax.diagnostic-token",
        "U14",
        "token of a syntax error; fold into the one diagnostics read",
    ),
    remove("type_check.canonical", "U15", "canonical type counters, synchronous mode"),
    remove(
        "type_check.preflight_capacities",
        "U16",
        "module record capacities; sizes buffers",
    ),
    remove("checked contract facts", "U17", "contract facts the host decodes"),
    remove("generic call counts", "U18", "generic call counts; sizes the row reads"),
    remove("generic call claims", "U19", "generic call claims the host decodes"),
    remove("generic call rows", "U20", "generic call rows the host decodes"),
    remove("checked type frontier", "U21", "type rows the host decodes"),
    remove("checked nominal frontier", "U22", "argument rows the host decodes"),
    remove("retained constant frontier", "U23", "constant atoms the host decodes"),
    remove("retained binder links", "U24", "binder links the host decodes"),
    remove("checked result constants", "U25", "result constants the host decodes"),
    remove(
        "checked contextual arguments",
        "U26",
        "contextual arguments the host decodes",
    ),
    remove("instance closure", "U27", "instance closure the host plans with"),
    remove("instance exec entries", "U28", "instance execution rows"),
    remove("method_routes.state", "U29", "method route state; decides another round"),
    remove("retained_schema.status", "U30", "projection schema status check"),
    remove("retained publication status", "U31", "trait publication status check"),
    remove("retained route query", "U32", "route view the host queries"),
    remove(
        "retained diagnostic",
        "U33",
        "span of a refuted call; fold into the one diagnostics read",
    ),
    remove("closed store counters", "U34", "closed solver counters; sizes"),
    remove("closed trait demand", "U35", "closed solver demand the host plans with"),
    remove("closed publication receipt", "U36", "closed solver status check"),
    remove("native layout completions", "U37", "layout completion rows"),
    remove("native semantic graph prefixes", "U38", "semantic graph prefixes"),
    remove(
        "implementation projection receipt",
        "U39",
        "implementation projection status and counts",
    ),
    remove("implementation application rows", "U40", "implementation rows"),
    remove(
        "semantic-interface validation",
        "U41",
        "validation status of stored dependency interfaces",
    ),
    remove("x86 artifact length readback", "U42", "unlinked x86 artifact length"),
    remove("x86 artifact byte readback", "U43", "unlinked x86 artifact bytes"),
    remove("Wasm artifact length readback", "U44", "unlinked WASM artifact length"),
    remove("Wasm artifact byte readback", "U45", "unlinked WASM artifact bytes"),
    remove(
        "codegen.wasm.link.resolve.targets",
        "U46",
        "WASM symbol targets the host links with",
    ),
];

/// Readbacks that a normal build does not run: debugging and profiling tools,
/// opt-in validation modes and test oracles. Each is held to its file.
const DEBUG: &[(&str, &str, &str)] = &[
    ("bin/shader_dispatch_replay.rs", "replay", "the shader replay tool"),
    (
        "codegen/lir/input_capture.rs",
        "lowering capture",
        "the lowering capture tool",
    ),
    (
        "compiler/gpu_compiler/trait_solver/dispatch/retained_catalog/mod.rs",
        "retained batch directory",
        "opt-in row assertions (`read_rows`)",
    ),
    (
        "compiler/gpu_compiler/trait_solver/dispatch/retained_catalog/mod.rs",
        "retained rows",
        "opt-in row assertions (`read_rows`)",
    ),
    (
        "compiler/gpu_compiler/trait_solver/dispatch/retained_catalog/mod.rs",
        "retained routes",
        "test oracle `read_routes_for_test`",
    ),
    (
        "gpu/dispatch_capture.rs",
        "lanius-debug-capture",
        "the dispatch capture tool",
    ),
    ("gpu/passes_core.rs", "lanius-debug-dump", "the buffer dump tool"),
    ("gpu/timer.rs", "gpu.timer.readback", "GPU timestamps under a timing report"),
    (
        "lexer/driver.rs",
        "lexer.parser_feature_flags.debug",
        "test oracle `debug_parser_feature_flags`",
    ),
    (
        "parser/driver/debug.rs",
        "parser.semantic_token_kinds.current.count",
        "parser debug dump",
    ),
    (
        "parser/driver/debug.rs",
        "parser.semantic_token_kinds.current",
        "parser debug dump",
    ),
    (
        "parser/driver/debug.rs",
        "parser.semantic_token_kinds.count",
        "parser debug dump",
    ),
    (
        "parser/driver/debug.rs",
        "parser.semantic_token_kinds",
        "parser debug dump",
    ),
    (
        "parser/driver/debug.rs",
        "parser.token_feature_flags",
        "parser debug dump",
    ),
    (
        "type_checker/generic_calls.rs",
        "instance table",
        "instance table validation mode",
    ),
    (
        "type_checker/generic_calls.rs",
        "instance table counts",
        "instance table validation mode",
    ),
    (
        "type_checker/generic_calls.rs",
        "instance table function tokens",
        "instance table validation mode",
    ),
    (
        "type_checker/program_retention/projection/mod.rs",
        "retained_projection.test_readback",
        "test oracle `read_test_buffer`",
    ),
    (
        "type_checker/resident.rs",
        "type_check.canonical.validation",
        "canonical type validation mode",
    ),
];

/// Where a raw `map_async` may stand: the one map of `begin_readback_map`,
/// and a test that models a failed map.
const MAP_ASYNC: &[(&str, usize)] = &[("gpu/passes_core.rs", 1), ("gpu/readback.rs", 1)];

fn visit(dir: &Path, root: &Path, out: &mut Vec<(String, String)>) {
    let mut entries: Vec<_> = std::fs::read_dir(dir)
        .expect("compiler source directory must be readable")
        .map(|entry| entry.expect("directory entry").path())
        .collect();
    entries.sort();
    for path in entries {
        if path.is_dir() {
            visit(&path, root, out);
        } else if path.extension().is_some_and(|ext| ext == "rs") {
            let relative = path
                .strip_prefix(root)
                .expect("below the source root")
                .to_string_lossy()
                .replace('\\', "/");
            let source = std::fs::read_to_string(&path).expect("readable source");
            out.push((relative, source));
        }
    }
}

/// `(file, line, literal)` of every `macro!("literal")` call.
fn sites(sources: &[(String, String)], name: &str) -> Vec<(String, usize, String)> {
    let call = format!("{name}!(");
    let mut out = Vec::new();
    for (file, source) in sources {
        let mut at = 0;
        while let Some(found) = source[at..].find(&call) {
            let start = at + found;
            at = start + call.len();
            let preceded = source[..start]
                .chars()
                .next_back()
                .is_some_and(|c| c.is_alphanumeric() || c == '_');
            if preceded {
                continue;
            }
            let rest = source[at..].trim_start();
            let Some(rest) = rest.strip_prefix('"') else {
                // The macro definitions pass `$label`.
                assert!(
                    rest.starts_with("$label"),
                    "{file}: `{name}!` takes a string literal"
                );
                continue;
            };
            let end = rest.find('"').expect("closed string literal");
            let line = source[..start].matches('\n').count() + 1;
            out.push((file.clone(), line, rest[..end].to_string()));
        }
    }
    out
}

#[test]
fn compile_path_readbacks_stay_within_the_allowlist() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut sources = Vec::new();
    visit(&root, &root, &mut sources);
    let mut failures = Vec::new();

    // One entry per label, each with a reason.
    let mut listed = BTreeMap::new();
    for entry in COMPILE_PATH {
        assert!(!entry.reason.is_empty(), "{} needs a reason", entry.label);
        if let ToRemove { audit_row } = entry.kind {
            assert!(!audit_row.is_empty(), "{} needs an audit row", entry.label);
        }
        if listed.insert(entry.label, entry.kind).is_some() {
            failures.push(format!("`{}` is listed twice", entry.label));
        }
    }
    let permanent = COMPILE_PATH
        .iter()
        .filter(|entry| matches!(entry.kind, Permanent))
        .count();
    if permanent >= PERMANENT_LIMIT {
        failures.push(format!(
            "{permanent} permanent readbacks; the limit is fewer than {PERMANENT_LIMIT}"
        ));
    }

    // Every compile-path site is listed, and every entry still has a site.
    let compile_sites = sites(&sources, "readback_label");
    let mut seen = BTreeSet::new();
    for (file, line, label) in &compile_sites {
        if !listed.contains_key(label.as_str()) {
            failures.push(format!(
                "{file}:{line}: readback `{label}` is not in COMPILE_PATH; do the work on \
                 the GPU, or list it with its audit row"
            ));
        }
        seen.insert(label.as_str());
    }
    for entry in COMPILE_PATH {
        if !seen.contains(entry.label) {
            let note = match entry.kind {
                ToRemove { audit_row } => format!("removed (audit row {audit_row})"),
                Permanent => "gone".to_string(),
            };
            failures.push(format!(
                "`{}` has no site: it was {note}; delete its entry",
                entry.label
            ));
        }
    }

    // Debug readbacks stay in their files.
    let debug_sites = sites(&sources, "debug_readback_label");
    let debug: BTreeSet<_> = DEBUG.iter().map(|&(file, label, _)| (file, label)).collect();
    let mut debug_seen = BTreeSet::new();
    for (file, line, label) in &debug_sites {
        if !debug.contains(&(file.as_str(), label.as_str())) {
            failures.push(format!(
                "{file}:{line}: debug readback `{label}` is not in DEBUG"
            ));
        }
        debug_seen.insert((file.as_str(), label.as_str()));
    }
    for &(file, label, _) in DEBUG {
        if !debug_seen.contains(&(file, label)) {
            failures.push(format!("DEBUG entry {file} `{label}` has no site"));
        }
    }

    // Nothing maps a buffer except through `begin_readback_map`, and nothing
    // makes a label except the two macros.
    let raw_map = format!(".{}_{}(", "map", "async");
    let raw_label = format!("{}(", "__site");
    for (file, source) in &sources {
        let maps = source.matches(&raw_map).count();
        let allowed = MAP_ASYNC
            .iter()
            .find(|&&(allowed, _)| allowed == file)
            .map_or(0, |&(_, count)| count);
        if maps > allowed {
            failures.push(format!(
                "{file}: {maps} raw buffer maps (allowed {allowed}); map through \
                 `begin_readback_map` with a readback label"
            ));
        }
        let labels = source.matches(&raw_label).count();
        let allowed = if file == "gpu/passes_core.rs" { 3 } else { 0 };
        if labels > allowed {
            failures.push(format!(
                "{file}: makes a readback label without `readback_label!`"
            ));
        }
    }

    assert!(
        failures.is_empty(),
        "readback limit:\n{}",
        failures.join("\n")
    );
}
