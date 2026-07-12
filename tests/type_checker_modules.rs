mod common;

use laniusc_compiler::compiler::{
    CompileError,
    EntrySourceRoots,
    load_entry_path_manifest_with_source_root,
    load_entry_path_manifest_with_source_root_and_stdlib,
    load_entry_path_manifest_with_stdlib,
    load_entry_with_source_root,
    load_entry_with_source_roots,
    load_entry_with_stdlib,
    type_check_entry_with_source_root,
    type_check_entry_with_source_roots,
    type_check_entry_with_stdlib,
};

fn assert_gpu_type_check_rejects(src: &str) {
    match common::type_check_source_with_timeout(src) {
        Ok(()) => panic!("source should fail GPU type checking:\n{src}"),
        Err(CompileError::Diagnostic(_)) => {}
        Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU type check error, got {other:?}"),
    }
}

fn assert_gpu_type_check_accepts(src: &str) {
    common::type_check_source_with_timeout(src)
        .unwrap_or_else(|err| panic!("source should pass GPU type checking: {err:?}"));
}

fn assert_gpu_type_check_pack_rejects(sources: &[&str]) {
    match common::type_check_source_pack_with_timeout(sources) {
        Ok(()) => panic!(
            "source pack should fail GPU type checking:\n{}",
            sources.join("\n--- source split ---\n")
        ),
        Err(CompileError::Diagnostic(_)) => {}
        Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU type check error, got {other:?}"),
    }
}

fn assert_gpu_type_check_pack_accepts(sources: &[&str]) {
    common::type_check_source_pack_with_timeout(sources)
        .unwrap_or_else(|err| panic!("source pack should pass GPU type checking: {err:?}"));
}

fn assert_source_pack_case_accepts(sources: &'static [&'static str], app_source: &'static str) {
    let mut sources = sources.to_vec();
    if !app_source.is_empty() {
        sources.push(app_source);
    }
    assert_gpu_type_check_pack_accepts(&sources);
}

#[test]
fn resident_typechecker_always_records_hir_control_validation() {
    let resident = include_str!("../crates/laniusc-compiler/src/type_checker/resident.rs");
    let pass_loaders = include_str!("../crates/laniusc-compiler/src/type_checker/pass_loaders.rs");

    assert!(
        resident.contains("&self.passes.control_hir")
            && resident.contains("&self.passes.scope_hir"),
        "resident type checking should not select token-derived control/scope passes"
    );
    assert!(
        !resident.contains("uses_hir_control")
            && !resident.contains("&self.passes.control\n")
            && !resident.contains("&self.passes.scope\n"),
        "resident type checking must not fall back to lexer-token syntax validation"
    );
    assert!(
        !pass_loaders.contains("type_check_control\", \"type_checker/control\"")
            && !pass_loaders.contains("type_check_scope\", \"type_checker/scope\""),
        "token-derived control/scope shaders should not be loaded by resident type checking"
    );
}

#[test]
fn type_checker_accepts_leading_module_metadata() {
    assert_gpu_type_check_accepts("module app::main;");
    assert_gpu_type_check_accepts("module app::main; fn main() { return 0; }");
}

#[test]
fn type_checker_rejects_self_import_through_gpu_module_resolver() {
    match common::type_check_source_pack_with_timeout(&[r#"module app::main;
import app::main;
fn main() { return 0; }
"#])
    {
        Ok(()) => panic!("self-import should fail GPU type checking"),
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(
                diagnostic.code, "LNC0002",
                "direct self-import diagnostics should use the reserved cycle code"
            );
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!("self-import should report LNC0002, got raw GPU type-check error: {message}");
        }
        Err(other) => panic!("expected GPU resolver rejection, got {other:?}"),
    }
}

#[test]
fn type_checker_rejects_two_module_import_cycle_through_gpu_module_resolver() {
    match common::type_check_source_pack_with_timeout(&[
        r#"module app::main;
import app::helper;
fn main() { return 0; }
"#,
        r#"module app::helper;
import app::main;
"#,
    ]) {
        Ok(()) => panic!("two-module import cycle should fail GPU type checking"),
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(
                diagnostic.code, "LNC0002",
                "two-module import cycles should use the reserved cycle code"
            );
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!(
                "two-module import cycle should report LNC0002, got raw GPU type-check error: {message}"
            );
        }
        Err(other) => panic!("expected GPU resolver rejection, got {other:?}"),
    }
}

#[test]
#[ignore = "requires GPU SCC/topological import-cycle checkpoint beyond direct and two-module cycles"]
fn type_checker_rejects_three_module_import_cycle_through_gpu_topological_checkpoint() {
    match common::type_check_source_pack_with_timeout(&[
        r#"module app::main;
import app::middle;
fn main() { return 0; }
"#,
        r#"module app::middle;
import app::leaf;
"#,
        r#"module app::leaf;
import app::main;
"#,
    ]) {
        Ok(()) => panic!("three-module import cycle should fail GPU type checking"),
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(
                diagnostic.code, "LNC0002",
                "arbitrary import cycles should use the reserved cycle code"
            );
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!(
                "three-module import cycle should report LNC0002, got raw GPU type-check error: {message}"
            );
        }
        Err(other) => panic!("expected GPU resolver rejection, got {other:?}"),
    }
}

#[test]
fn type_checker_accepts_acyclic_three_module_import_chain() {
    assert_gpu_type_check_pack_accepts(&[
        r#"module app::main;
import app::middle;
fn main() { return 0; }
"#,
        r#"module app::middle;
import app::leaf;
"#,
        r#"module app::leaf;
"#,
    ]);
}

#[test]
fn type_checker_unresolved_source_pack_import_reports_stable_diagnostic() {
    let source = r#"module app::main;
import core::math;
fn main() { return 0; }
"#;

    match common::type_check_source_pack_with_timeout(&[source]) {
        Ok(()) => panic!("unresolved import should fail GPU type checking"),
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(diagnostic.code, "LNC0010");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("unresolved import diagnostic should point at the import path token");
            assert_eq!(label.path, std::path::PathBuf::from("<source pack file 0>"));
            assert_eq!(label.line, 2);
            assert_eq!(label.column, 8);
            assert_eq!(label.source_line, Some("import core::math;".to_string()));
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0010]: unresolved import"));
            assert!(rendered.contains("<source pack file 0>:2:8"));
            assert!(rendered.contains("import core::math;"));
            assert!(rendered.contains("imported module not found"));
            assert!(
                !rendered.contains("GPU type check rejected"),
                "diagnostic should not expose raw GPU rejection:\n{rendered}"
            );
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!("unresolved import should report LNC0010, got raw GPU error: {message}");
        }
        Err(other) => panic!("expected GPU resolver diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_source_pack_syntax_failure_reports_stable_diagnostic() {
    let sources = [
        "module app::main;\n",
        "module app::bad;\nfn fn bad() -> i32 { return 1; }\n",
    ];

    match common::type_check_source_pack_with_timeout(&sources) {
        Ok(()) => panic!("malformed source-pack file should fail GPU type checking"),
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(diagnostic.code, "LNC0016");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("syntax diagnostic should point at malformed source");
            assert_eq!(label.path, std::path::PathBuf::from("<source pack file 1>"));
            assert_eq!(label.line, 2);
            assert_eq!(
                label.source_line,
                Some("fn fn bad() -> i32 { return 1; }".to_string())
            );
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0016]: syntax error"));
            assert!(rendered.contains("<source pack file 1>:2:"));
            assert!(rendered.contains("fn fn bad() -> i32 { return 1; }"));
            assert!(
                !rendered.contains("GPU type check rejected"),
                "syntax diagnostic should not expose raw GPU rejection:\n{rendered}"
            );
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!(
                "malformed source-pack file should report LNC0016, got raw GPU error: {message}"
            );
        }
        Err(other) => panic!("expected GPU syntax diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_string_import_reports_stable_diagnostic() {
    let source = r#"module app::main;
import "stdlib/core/math.lani";
fn main() { return 0; }
"#;

    match common::type_check_source_pack_with_timeout(&[source]) {
        Ok(()) => panic!("quoted import should fail GPU type checking"),
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(diagnostic.code, "LNC0011");
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0011]: unsupported import form"));
            assert!(rendered.contains("<source pack file 0>:2:1"));
            assert!(rendered.contains("import \"stdlib/core/math.lani\";"));
            assert!(rendered.contains("only module-path imports are supported here"));
            assert!(!rendered.contains("GPU type check rejected"));
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!("quoted import should report LNC0011, got raw GPU error: {message}");
        }
        Err(other) => panic!("expected unsupported import diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_deep_import_path_reports_stable_diagnostic() {
    let source = r#"module app::main;
import a::b::c::d::e::f::g::h::i;
fn main() { return 0; }
"#;

    match common::type_check_source_pack_with_timeout(&[source]) {
        Ok(()) => panic!("over-deep import should fail GPU type checking"),
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(diagnostic.code, "LNC0012");
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0012]: import path too deep"));
            assert!(rendered.contains("<source pack file 0>:2:8"));
            assert!(rendered.contains("import a::b::c::d::e::f::g::h::i;"));
            assert!(rendered.contains("exceeds the current resolver depth limit"));
            assert!(!rendered.contains("GPU type check rejected"));
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!("over-deep import should report LNC0012, got raw GPU error: {message}");
        }
        Err(other) => panic!("expected import-depth diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_duplicate_source_pack_module_reports_stable_diagnostic() {
    let first = r#"module core::math;
pub fn one() -> i32 { return 1; }
"#;
    let duplicate = r#"module core::math;
pub fn two() -> i32 { return 2; }
"#;

    match common::type_check_source_pack_with_timeout(&[first, duplicate]) {
        Ok(()) => panic!("duplicate module declarations should fail GPU type checking"),
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(diagnostic.code, "LNC0013");
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0013]: duplicate module declaration"));
            assert!(rendered.contains("<source pack file 1>:1:8"));
            assert!(rendered.contains("module core::math;"));
            assert!(rendered.contains("already declared in the source pack"));
            assert!(!rendered.contains("GPU type check rejected"));
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!("duplicate module should report LNC0013, got raw GPU error: {message}");
        }
        Err(other) => panic!("expected duplicate-module diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_deep_module_path_reports_stable_diagnostic() {
    let source = r#"module a::b::c::d::e::f::g::h::i;
fn main() { return 0; }
"#;

    match common::type_check_source_pack_with_timeout(&[source]) {
        Ok(()) => panic!("over-deep module path should fail GPU type checking"),
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(diagnostic.code, "LNC0014");
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0014]: module path too deep"));
            assert!(rendered.contains("<source pack file 0>:1:8"));
            assert!(rendered.contains("module a::b::c::d::e::f::g::h::i;"));
            assert!(rendered.contains("exceeds the current resolver depth limit"));
            assert!(!rendered.contains("GPU type check rejected"));
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!("over-deep module path should report LNC0014, got raw GPU error: {message}");
        }
        Err(other) => panic!("expected module-depth diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_deep_qualified_type_path_reports_stable_diagnostic() {
    let source = r#"module app::main;
fn main() {
    let value: a::b::c::d::e::f::g::h::i::Thing = 0;
    return 0;
}
"#;

    match common::type_check_source_pack_with_timeout(&[source]) {
        Ok(()) => panic!("over-deep qualified type path should fail GPU type checking"),
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(diagnostic.code, "LNC0007");
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0007]: unknown type"));
            assert!(rendered.contains("let value: a::b::c::d::e::f::g::h::i::Thing = 0;"));
            assert!(rendered.contains("type path exceeds the current resolver depth limit"));
            assert!(
                rendered.contains("before the leaf type"),
                "diagnostic should explain the qualified-type path width:\n{rendered}"
            );
            assert!(!rendered.contains("GPU type check rejected"));
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!(
                "over-deep qualified type path should report LNC0007, got raw GPU error: {message}"
            );
        }
        Err(other) => panic!("expected qualified type-path depth diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_deep_qualified_value_path_reports_stable_diagnostic() {
    let source = r#"module app::main;
fn main() {
    return a::b::c::d::e::f::g::h::i::value;
}
"#;

    match common::type_check_source_pack_with_timeout(&[source]) {
        Ok(()) => panic!("over-deep qualified value path should fail GPU type checking"),
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(diagnostic.code, "LNC0005");
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0005]: unresolved identifier"));
            assert!(rendered.contains("return a::b::c::d::e::f::g::h::i::value;"));
            assert!(rendered.contains("value path exceeds the current resolver depth limit"));
            assert!(
                rendered.contains("before the leaf value"),
                "diagnostic should explain the qualified-value path width:\n{rendered}"
            );
            assert!(!rendered.contains("GPU type check rejected"));
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!(
                "over-deep qualified value path should report LNC0005, got raw GPU error: {message}"
            );
        }
        Err(other) => panic!("expected qualified value-path depth diagnostic, got {other:?}"),
    }
}

#[test]
fn type_checker_source_pack_accepts_module_metadata_and_resolved_path_imports() {
    assert_gpu_type_check_pack_accepts(&[
        "module core::math; pub fn one() -> i32 { return 1; } ",
        "module app::main; import core::math; fn main() { return one(); }",
    ]);
    assert_gpu_type_check_pack_accepts(&[
        "module core::math; pub const VALUE: i32 = 1;",
        r#"
module app::main;

import core::math;
import core::math;

fn main() {
    let value: i32 = VALUE;
    return value;
}
"#,
    ]);

    assert_gpu_type_check_pack_rejects(&[
        "module app::main; import core::math; fn main() { return 0; }",
    ]);
    assert_gpu_type_check_pack_rejects(&[
        "module app::main; import \"stdlib/core/math.lani\"; fn main() { return 0; }",
    ]);
    assert_gpu_type_check_pack_rejects(&[
        "module app::main; import app::main; fn main() { return 0; }",
    ]);
}

#[test]
fn type_checker_source_pack_resolves_public_type_aliases_on_gpu() {
    assert_gpu_type_check_pack_accepts(&[
        "module core::count; pub type Count = i32;",
        r#"
module app::main;

import core::count;

fn keep(value: Count) -> Count {
    return value;
}

fn main() {
    let imported: Count = keep(1);
    let qualified: core::count::Count = imported;
    return qualified;
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_private_cross_module_type_aliases_on_gpu() {
    assert_gpu_type_check_pack_accepts(&[r#"
module core::count;

type Count = i32;

fn keep(value: core::count::Count) -> Count {
    return value;
}

fn main() {
    let value: core::count::Count = keep(1);
    return value;
}
"#]);

    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::count;

type Count = i32;
"#,
        r#"
module app::main;

import core::count;

fn main() {
    let value: core::count::Count = 1;
    return value;
}
"#,
    ]);

    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::count;

type Count = i32;
"#,
        r#"
module app::main;

import core::count;

fn main() {
    let value: Count = 1;
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_entry_stdlib_root_loads_imported_module() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_source_root", "app", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::i32;
import core::i32;

fn main() {
    let min_value: i32 = core::i32::MIN;
    let max_value: i32 = MAX;
    let bits: u32 = core::i32::BITS;
    let bytes: u32 = BYTES;
    if (min_value != core::i32::MIN || max_value != core::i32::MAX || bits != 32 || bytes != 4) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("source-root path manifest should load imported stdlib module");
    let expected_stdlib_path = stdlib_root.join("core/i32.lani");
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == expected_stdlib_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry.path())
    );

    common::block_on_gpu_with_timeout(
        "GPU type check source-root stdlib import",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("source-root stdlib import should type check");
}

#[test]
fn type_checker_entry_stdlib_root_type_checks_unsigned_integer_metadata() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_source_root", "unsigned_ints", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::u32;
import core::u8;

fn main() {
    let u32_bits: u32 = core::u32::BITS;
    let u32_bytes: u32 = core::u32::BYTES;
    let u8_bits: u32 = core::u8::BITS;
    let u8_bytes: u32 = core::u8::BYTES;
    let u32_floor: u32 = core::u32::MIN;
    let byte_ceiling: u8 = core::u8::MAX;
    if (u32_bits != 32 || u32_bytes != 4 || u8_bits != 8 || u8_bytes != 1) {
        return 1;
    }
    if (u32_floor != 0 || byte_ceiling != 255) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("source-root path manifest should load unsigned integer stdlib modules");
    assert_eq!(manifest.files.len(), 3);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u32.lani"))
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/u8.lani"))
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry.path())
    );

    common::block_on_gpu_with_timeout(
        "GPU type check source-root unsigned integer metadata",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("unsigned integer metadata should type check when loaded through --stdlib-root");
}

#[test]
fn type_checker_entry_stdlib_root_type_checks_core_runtime_contract() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_source_root", "runtime_app", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::runtime;

fn main() {
    let allocator: core::runtime::Capability = core::runtime::HAS_ALLOCATOR;
    let clock: Capability = core::runtime::HAS_CLOCK;
    let panic_hook: Capability = core::runtime::HAS_PANIC_HOOK;
    let host: Capability = core::runtime::HAS_HOST_SERVICES;
    let threads: Capability = core::runtime::has_threads();
    let secure_rng: core::runtime::Capability = core::runtime::has_secure_rng();
    let gpu: Capability = core::runtime::has_gpu();
    let process: Capability = core::runtime::has_process();
    let env: core::runtime::Capability = has_env();
    let runtime_services: Capability = core::runtime::has_runtime_services();
    let contract_only: core::runtime::Capability =
        core::runtime::runtime_services_are_contract_only();
    let threads_status: RuntimeServiceStatus =
        core::runtime::service_status(core::runtime::SERVICE_THREADS_ID);
    let process_status: core::runtime::RuntimeServiceStatus =
        service_status(core::runtime::SERVICE_PROCESS_ID);
    let threads_unavailable: Capability =
        core::runtime::service_is_unavailable(core::runtime::SERVICE_THREADS_ID);
    let process_available: Capability =
        core::runtime::service_is_available(core::runtime::SERVICE_PROCESS_ID);
    let unknown_service_unknown: core::runtime::Capability = service_is_unknown(99);
    let secure_rng_needs_binding: Capability =
        service_requires_runtime_binding(SERVICE_SECURE_RNG_ID);
    let gpu_needs_binding: Capability =
        core::runtime::service_requires_runtime_binding(core::runtime::SERVICE_GPU_ID);
    let env_needs_binding: core::runtime::Capability =
        service_requires_runtime_binding(core::runtime::SERVICE_ENV_ID);
    if (allocator || clock || panic_hook || host || threads || secure_rng || gpu || process || env || runtime_services || !contract_only) {
        return 1;
    }
    if (threads_status != SERVICE_STATUS_UNAVAILABLE || process_status != SERVICE_STATUS_UNAVAILABLE) {
        return 1;
    }
    if (!threads_unavailable || process_available || !unknown_service_unknown) {
        return 1;
    }
    if (!secure_rng_needs_binding || !gpu_needs_binding || !env_needs_binding) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("source-root path manifest should load core::runtime from stdlib");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/runtime.lani"))
    );
    assert_eq!(manifest.files.len(), 2);
    common::block_on_gpu_with_timeout(
        "GPU type check source-root core::runtime import",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::runtime should type check when loaded through --stdlib-root");
}

#[test]
fn type_checker_entry_stdlib_root_type_checks_core_target_capability_contract() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_source_root", "target_app", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::target;

fn main() {
    let native: Capability = core::target::is_native();
    let wasm: core::target::Capability = is_wasm();
    let panic_hook: Capability = core::target::has_panic_hook();
    let host_services: core::target::Capability = has_host_services();
    let process: Capability = core::target::has_process();
    let env: core::target::Capability = has_env();
    let host_services_const: Capability = core::target::HAS_HOST_SERVICES;
    let process_const: core::target::Capability = HAS_PROCESS;
    let freestanding: Capability = core::target::is_freestanding();
    if (!native || wasm || panic_hook || host_services || process || env || host_services_const || process_const || !freestanding) {
        return 1;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("source-root path manifest should load core::target from stdlib");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/target.lani"))
    );
    assert_eq!(manifest.files.len(), 2);
    common::block_on_gpu_with_timeout(
        "GPU type check source-root core::target import",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::target capability contract should type check when loaded through --stdlib-root");
}

#[test]
fn type_checker_accepts_core_target_capability_contract_source_pack() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/core/target.lani"),
        r#"
module app::main;

import core::target;

fn main() {
    let native: Capability = core::target::is_native();
    let wasm: core::target::Capability = is_wasm();
    let panic_hook: Capability = core::target::has_panic_hook();
    let host_services: core::target::Capability = has_host_services();
    let process: Capability = core::target::has_process();
    let env: core::target::Capability = has_env();
    let host_services_const: Capability = core::target::HAS_HOST_SERVICES;
    let process_const: core::target::Capability = HAS_PROCESS;
    let freestanding: Capability = core::target::is_freestanding();
    if (!native || wasm || panic_hook || host_services || process || env || host_services_const || process_const || !freestanding) {
        return 1;
    }
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_entry_stdlib_root_type_checks_core_bool_contract() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_source_root", "bool_app", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::bool;

fn main() {
    let different: bool = core::bool::ne(true, false);
    let same: bool = core::bool::eq(different, true);
    let selected: i32 = core::bool::select_i32(different, 7, 99);
    let fallback: i32 = core::bool::choose_i32(false, 11, 42);
    if (same && selected == 7 && fallback == 42) {
        return 0;
    }
    return 1;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("source-root path manifest should load core::bool from stdlib");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/bool.lani"))
    );
    assert_eq!(manifest.files.len(), 2);
    common::block_on_gpu_with_timeout(
        "GPU type check source-root core::bool import",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::bool helpers should type check when loaded through --stdlib-root");
}

#[test]
fn type_checker_entry_stdlib_root_type_checks_core_mem_generics() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_source_root", "mem_app", Some("lani"));
    entry.write_str(
        r#"
module app::main;

import core::mem;

fn main() {
    let number: i32 = identity(7);
    let flag: bool = identity(false);
    let left: i32 = first(number, 11);
    let right: bool = second(flag, true);
    let selected_number: i32 = select(right, left, 0);
    let selected_flag: bool = select(false, right, flag);
    let qualified_number: i32 = core::mem::identity(selected_number);
    if (selected_flag) {
        return qualified_number;
    }
    return 0;
}
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("source-root path manifest should load core::mem from stdlib");
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/mem.lani"))
    );
    assert_eq!(manifest.files.len(), 2);
    common::block_on_gpu_with_timeout(
        "GPU type check source-root core::mem import",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    )
    .expect("core::mem generic helpers should type check when loaded through --stdlib-root");
}

#[test]
fn type_checker_entry_source_root_loads_user_module_imports() {
    let source_root = common::temp_artifact_path("laniusc_source_root", "user_root", None);
    let app_root = source_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create temp app source root");
    let helper_path = app_root.join("helper.lani");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn one() -> i32 {
    return 1;
}
"#,
    )
    .expect("write helper module");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::one();
}
"#,
    )
    .expect("write entry module");

    let manifest = load_entry_path_manifest_with_source_root(&entry_path, &source_root)
        .expect("source-root path manifest should load imported user module");
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == helper_path)
    );

    common::block_on_gpu_with_timeout(
        "GPU type check source-root user module import",
        type_check_entry_with_source_root(entry_path.clone(), source_root.clone()),
    )
    .expect("source-root user module import should type check");

    std::fs::remove_dir_all(&source_root).expect("remove temp user source root");
}

#[test]
fn source_root_imports_use_gpu_module_declarations_not_host_paths() {
    let source_root = common::temp_artifact_path("laniusc_source_root", "mismatched_module", None);
    let app_root = source_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create temp app source root");
    let helper_path = app_root.join("helper.lani");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::renamed;

pub fn one() -> i32 {
    return 1;
}
"#,
    )
    .expect("write mismatched helper module");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;

fn main() {
    return app::helper::one();
}
"#,
    )
    .expect("write entry module");

    let manifest = load_entry_path_manifest_with_source_root(&entry_path, &source_root)
        .expect("source-root loader should load the path candidate");
    assert_eq!(manifest.files.len(), 2);
    assert!(manifest.files.iter().any(|file| file.path == helper_path));

    match common::block_on_gpu_with_timeout(
        "GPU type check source-root module declaration mismatch",
        type_check_entry_with_source_root(entry_path.clone(), source_root.clone()),
    ) {
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(diagnostic.code, "LNC0010");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("module/path mismatch diagnostic should point at the import path");
            assert_eq!(label.path, entry_path);
            assert_eq!(label.line, 4);
            assert_eq!(label.column, 8);
            assert_eq!(label.source_line, Some("import app::helper;".to_string()));
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0010]: unresolved import"));
            assert!(rendered.contains("import app::helper;"));
            assert!(rendered.contains("imported module not found"));
            assert!(!rendered.contains("GPU type check rejected"));
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!("module/path mismatch should report LNC0010, got raw GPU error: {message}");
        }
        other => panic!(
            "expected GPU resolver diagnostic for module/path identity mismatch, got {other:?}"
        ),
    }

    std::fs::remove_dir_all(&source_root).expect("remove temp user source root");
}

#[test]
fn source_root_loader_can_combine_user_and_stdlib_roots() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let source_root = common::temp_artifact_path("laniusc_source_root", "user_and_stdlib", None);
    let app_root = source_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create temp app source root");
    let helper_path = app_root.join("helper.lani");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::helper;

pub fn id(value: i32) -> i32 {
    return value;
}
"#,
    )
    .expect("write helper module");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::helper;
import core::i32;

fn main() {
    let value: i32 = core::i32::MIN;
    return app::helper::id(value);
}
"#,
    )
    .expect("write entry module");

    let manifest = load_entry_path_manifest_with_source_root_and_stdlib(
        &entry_path,
        &source_root,
        &stdlib_root,
    )
    .expect("source-root path manifest should load user and stdlib imports");
    let expected_stdlib_path = stdlib_root.join("core/i32.lani");
    assert_eq!(manifest.files.len(), 3);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == expected_stdlib_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == helper_path)
    );

    let roots = EntrySourceRoots {
        stdlib_root: Some(stdlib_root),
        user_roots: vec![source_root.clone()],
    };
    common::block_on_gpu_with_timeout(
        "GPU type check combined source-root and stdlib imports",
        async move { type_check_entry_with_source_roots(entry_path, &roots).await },
    )
    .expect("combined source-root and stdlib imports should type check");

    std::fs::remove_dir_all(&source_root).expect("remove temp user/std source root");
}

#[test]
fn source_root_user_module_takes_precedence_over_stdlib_candidate() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let source_root = common::temp_artifact_path("laniusc_source_root", "user_stdlib_shadow", None);
    let app_root = source_root.join("app");
    let core_root = source_root.join("core");
    std::fs::create_dir_all(&app_root).expect("create temp app source root");
    std::fs::create_dir_all(&core_root).expect("create temp core source root");
    let user_core_i32_path = core_root.join("i32.lani");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &user_core_i32_path,
        r#"
module core::i32;

pub fn local_only() -> i32 {
    return 11;
}
"#,
    )
    .expect("write user core::i32 module");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import core::i32;

fn main() {
    let value: i32 = core::i32::local_only();
    return value;
}
"#,
    )
    .expect("write entry module");

    let manifest = load_entry_path_manifest_with_source_root_and_stdlib(
        &entry_path,
        &source_root,
        &stdlib_root,
    )
    .expect("source-root path manifest should prefer user module before stdlib fallback");
    assert_eq!(manifest.files.len(), 2);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == user_core_i32_path),
        "core::i32 should resolve to the user source-root candidate"
    );
    assert!(
        !manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/i32.lani")),
        "stdlib fallback must not be loaded when a user source root resolves the module"
    );

    let roots = EntrySourceRoots {
        stdlib_root: Some(stdlib_root),
        user_roots: vec![source_root.clone()],
    };
    common::block_on_gpu_with_timeout(
        "GPU type check source-root module precedence over stdlib fallback",
        async move { type_check_entry_with_source_roots(entry_path, &roots).await },
    )
    .expect("user source-root module should shadow the stdlib fallback during type checking");

    std::fs::remove_dir_all(&source_root).expect("remove temp user/std shadow source root");
}

#[test]
fn source_root_stdlib_nested_import_stays_inside_stdlib_boundary() {
    let root = common::temp_artifact_path("laniusc_source_root", "stdlib_nested_boundary", None);
    let source_root = root.join("src");
    let stdlib_root = root.join("stdlib");
    let app_root = source_root.join("app");
    let user_core_root = source_root.join("core");
    let stdlib_core_root = stdlib_root.join("core");
    let stdlib_std_root = stdlib_root.join("std");
    std::fs::create_dir_all(&app_root).expect("create temp app source root");
    std::fs::create_dir_all(&user_core_root).expect("create temp user core root");
    std::fs::create_dir_all(&stdlib_core_root).expect("create temp stdlib core root");
    std::fs::create_dir_all(&stdlib_std_root).expect("create temp stdlib std root");

    let user_shared_path = user_core_root.join("shared.lani");
    let stdlib_shared_path = stdlib_core_root.join("shared.lani");
    let shim_path = stdlib_std_root.join("shim.lani");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &user_shared_path,
        r#"
module core::shared;

pub fn value() -> bool {
    return false;
}
"#,
    )
    .expect("write user core::shared module");
    std::fs::write(
        &stdlib_shared_path,
        r#"
module core::shared;

pub fn value() -> i32 {
    return 7;
}
"#,
    )
    .expect("write stdlib core::shared module");
    std::fs::write(
        &shim_path,
        r#"
module std::shim;

import core::shared;

pub fn forwarded() -> i32 {
    return core::shared::value();
}
"#,
    )
    .expect("write stdlib shim module");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import std::shim;

fn main() {
    let value: i32 = std::shim::forwarded();
    return value;
}
"#,
    )
    .expect("write entry module");

    let manifest = load_entry_path_manifest_with_source_root_and_stdlib(
        &entry_path,
        &source_root,
        &stdlib_root,
    )
    .expect("source-root path manifest should keep stdlib nested imports inside stdlib");
    assert_eq!(manifest.files.len(), 3);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == shim_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_shared_path),
        "stdlib shim's nested core::shared import should resolve inside the stdlib root"
    );
    assert!(
        !manifest
            .files
            .iter()
            .any(|file| file.path == user_shared_path),
        "stdlib nested imports must not cross back into the user source root"
    );

    let roots = EntrySourceRoots {
        stdlib_root: Some(stdlib_root.clone()),
        user_roots: vec![source_root.clone()],
    };
    common::block_on_gpu_with_timeout("GPU type check stdlib nested import boundary", async move {
        type_check_entry_with_source_roots(entry_path, &roots).await
    })
    .expect("stdlib nested import should type check against the stdlib candidate");

    std::fs::remove_dir_all(&root).expect("remove temp stdlib nested boundary root");
}

#[test]
fn source_root_user_module_can_import_stdlib_dependency() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let source_root =
        common::temp_artifact_path("laniusc_source_root", "user_module_stdlib_dependency", None);
    let app_root = source_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create temp app source root");
    let helper_path = app_root.join("int_gate.lani");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &helper_path,
        r#"
module app::int_gate;

import core::i32;

pub fn min_value() -> i32 {
    return core::i32::MIN;
}
"#,
    )
    .expect("write helper module with stdlib dependency");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::int_gate;

fn main() {
    if (app::int_gate::min_value() < 0) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("write entry module");

    let manifest = load_entry_path_manifest_with_source_root_and_stdlib(
        &entry_path,
        &source_root,
        &stdlib_root,
    )
    .expect("source-root path manifest should load transitive stdlib imports");
    assert_eq!(manifest.files.len(), 3);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == stdlib_root.join("core/i32.lani")),
        "path manifest should include core::i32 imported by the source-root helper"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == helper_path)
    );

    let roots = EntrySourceRoots {
        stdlib_root: Some(stdlib_root),
        user_roots: vec![source_root.clone()],
    };
    common::block_on_gpu_with_timeout(
        "GPU type check source-root user module with stdlib dependency",
        async move { type_check_entry_with_source_roots(entry_path, &roots).await },
    )
    .expect("source-root user module stdlib dependency should type check");

    std::fs::remove_dir_all(&source_root).expect("remove temp source-root stdlib dependency dir");
}

#[test]
fn source_root_user_module_can_import_user_dependency() {
    let source_root =
        common::temp_artifact_path("laniusc_source_root", "user_module_user_dependency", None);
    let app_root = source_root.join("app");
    std::fs::create_dir_all(&app_root).expect("create temp app source root");
    let leaf_path = app_root.join("leaf.lani");
    let gate_path = app_root.join("gate.lani");
    let entry_path = app_root.join("main.lani");
    std::fs::write(
        &leaf_path,
        r#"
module app::leaf;

pub fn value() -> i32 {
    return 7;
}
"#,
    )
    .expect("write transitive leaf module");
    std::fs::write(
        &gate_path,
        r#"
module app::gate;

import app::leaf;

pub fn forwarded() -> i32 {
    return app::leaf::value();
}
"#,
    )
    .expect("write helper module with user dependency");
    std::fs::write(
        &entry_path,
        r#"
module app::main;

import app::gate;

fn main() {
    let value: i32 = app::gate::forwarded();
    return value;
}
"#,
    )
    .expect("write entry module");

    let manifest = load_entry_path_manifest_with_source_root(&entry_path, &source_root)
        .expect("source-root path manifest should load transitive user imports");
    assert_eq!(manifest.files.len(), 3);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == gate_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == leaf_path),
        "path manifest should include app::leaf imported by the source-root helper"
    );

    common::block_on_gpu_with_timeout(
        "GPU type check source-root user module with user dependency",
        type_check_entry_with_source_root(entry_path.clone(), source_root.clone()),
    )
    .expect("source-root user module dependency should type check");

    std::fs::remove_dir_all(&source_root).expect("remove temp source-root user dependency dir");
}

#[test]
fn source_root_loader_reports_missing_stdlib_module_path() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_source_root", "missing", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import core::missing;
fn main() { return 0; }
"#,
    );

    let err = load_entry_with_stdlib(entry.path(), &stdlib_root)
        .expect_err("missing imported stdlib module should fail before GPU");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0001");
            let message = diagnostic.render();
            assert!(message.contains("error[LNC0001]"));
            assert!(message.contains("core::missing"));
            assert!(message.contains(&entry.path().display().to_string()));
            assert!(message.contains("core/missing.lani"));
            assert!(message.contains("import core::missing;"));
            assert!(message.contains("imported here"));
        }
        other => panic!("expected frontend source-root error, got {other:?}"),
    }
}

#[test]
fn source_root_loader_rejects_ambiguous_user_module_path() {
    let root = common::temp_artifact_path("laniusc_source_root", "ambiguous", None);
    let left_root = root.join("left");
    let right_root = root.join("right");
    std::fs::create_dir_all(left_root.join("app")).expect("create left source root");
    std::fs::create_dir_all(right_root.join("app")).expect("create right source root");
    let left_helper = left_root.join("app/helper.lani");
    let right_helper = right_root.join("app/helper.lani");
    std::fs::write(
        &left_helper,
        "module app::helper;\npub const VALUE: i32 = 1;\n",
    )
    .expect("write left helper");
    std::fs::write(
        &right_helper,
        "module app::helper;\npub const VALUE: i32 = 2;\n",
    )
    .expect("write right helper");
    let entry = common::TempArtifact::new("laniusc_source_root", "ambiguous_entry", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import app::helper;
fn main() { return 0; }
"#,
    );

    let roots = EntrySourceRoots {
        stdlib_root: None,
        user_roots: vec![left_root.clone(), right_root.clone()],
    };
    let err = load_entry_with_source_roots(entry.path(), &roots)
        .expect_err("source-root loader should reject ambiguous modules before GPU");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0003");
            let message = diagnostic.render();
            assert!(message.contains("error[LNC0003]"));
            assert!(message.contains("app::helper"));
            assert!(message.contains(&left_helper.display().to_string()));
            assert!(message.contains(&right_helper.display().to_string()));
            assert!(message.contains("import app::helper;"));
            assert!(message.contains("ambiguous import"));
        }
        other => panic!("expected ambiguous source-root diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove temp ambiguous source roots");
}

#[test]
fn source_root_loader_leaves_quoted_imports_for_gpu_rejection() {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = common::TempArtifact::new("laniusc_source_root", "quoted", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import "stdlib/core/i32.lani";
fn main() { return 0; }
"#,
    );

    let source_pack = load_entry_with_stdlib(entry.path(), &stdlib_root)
        .expect("source-root loader should not host-include quoted imports");
    assert_eq!(source_pack.sources.len(), 1);
    let result = common::block_on_gpu_with_timeout(
        "GPU type check source-root quoted import",
        type_check_entry_with_stdlib(entry.path().to_path_buf(), stdlib_root),
    );
    match result {
        Err(CompileError::Diagnostic(diagnostic)) => {
            assert_eq!(diagnostic.code, "LNC0011");
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0011]: unsupported import form"));
            assert!(rendered.contains(&entry.path().display().to_string()));
            assert!(rendered.contains("import \"stdlib/core/i32.lani\";"));
            assert!(!rendered.contains("GPU type check rejected"));
        }
        Err(CompileError::GpuTypeCheck(message)) => {
            panic!("quoted import should report LNC0011, got raw GPU error: {message}");
        }
        other => panic!("expected GPU type check rejection for quoted import, got {other:?}"),
    }
}

#[test]
fn source_root_loader_deduplicates_import_cycles_without_semantic_rejection() {
    let root = common::temp_artifact_path("laniusc_source_root", "cycle", None);
    let stdlib_root = root.join("stdlib");
    let core_root = stdlib_root.join("core");
    std::fs::create_dir_all(&core_root).expect("create temp stdlib core root");
    let a_path = core_root.join("a.lani");
    let b_path = core_root.join("b.lani");
    std::fs::write(
        &a_path,
        r#"
module core::a;
import core::b;
pub const A: i32 = 1;
"#,
    )
    .expect("write core::a");
    std::fs::write(
        &b_path,
        r#"
module core::b;
import core::a;
pub const B: i32 = 2;
"#,
    )
    .expect("write core::b");
    let entry = common::TempArtifact::new("laniusc_source_root", "cycle_entry", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import core::a;
fn main() { return 0; }
"#,
    );

    let manifest = load_entry_path_manifest_with_stdlib(entry.path(), &stdlib_root)
        .expect("source-root loader should use import cycles only as recursion guards");
    assert_eq!(
        manifest.files.len(),
        3,
        "entry plus two cyclic imports should be loaded once each"
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == a_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 0 && file.path == b_path)
    );
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.library_id == 1 && file.path == entry.path())
    );

    std::fs::remove_dir_all(&root).expect("remove temp source-root cycle test dir");
}

#[cfg(unix)]
#[test]
fn source_root_loader_rejects_stdlib_symlink_escape() {
    let root = common::temp_artifact_path("laniusc_source_root", "symlink", None);
    let stdlib_root = root.join("stdlib");
    let outside_root = root.join("outside");
    std::fs::create_dir_all(stdlib_root.join("core")).expect("create temp stdlib root");
    std::fs::create_dir_all(&outside_root).expect("create outside root");
    let outside_module = outside_root.join("escape.lani");
    std::fs::write(&outside_module, "module core::escape;\n").expect("write outside module");
    std::os::unix::fs::symlink(&outside_module, stdlib_root.join("core/escape.lani"))
        .expect("create stdlib symlink escape");
    let entry = common::TempArtifact::new("laniusc_source_root", "symlink_entry", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import core::escape;
fn main() { return 0; }
"#,
    );

    let err = load_entry_with_stdlib(entry.path(), &stdlib_root)
        .expect_err("stdlib-root loader should reject symlink escapes");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0004");
            let message = diagnostic.render();
            assert!(message.contains("core::escape"));
            assert!(message.contains("outside stdlib root"));
            assert!(message.contains("import core::escape;"));
        }
        other => panic!("expected frontend symlink escape error, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove temp source-root symlink test dir");
}

#[cfg(unix)]
#[test]
fn source_root_loader_rejects_stdlib_symlink_to_non_source_file() {
    let root = common::temp_artifact_path("laniusc_source_root", "stdlib_non_source", None);
    let stdlib_root = root.join("stdlib");
    let core_root = stdlib_root.join("core");
    std::fs::create_dir_all(&core_root).expect("create temp stdlib root");
    let non_source_module = core_root.join("helper.txt");
    std::fs::write(&non_source_module, "module core::helper;\n")
        .expect("write non-source stdlib module target");
    std::os::unix::fs::symlink(&non_source_module, core_root.join("helper.lani"))
        .expect("create stdlib symlink to non-source file");
    let canonical_non_source =
        std::fs::canonicalize(&non_source_module).expect("canonicalize non-source target");
    let entry = common::TempArtifact::new(
        "laniusc_source_root",
        "stdlib_non_source_entry",
        Some("lani"),
    );
    entry.write_str(
        r#"
module app::main;
import core::helper;
fn main() { return 0; }
"#,
    );

    let err = load_entry_with_stdlib(entry.path(), &stdlib_root)
        .expect_err("stdlib-root loader should reject non-source canonical import targets");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0030");
            let message = diagnostic.render();
            assert!(message.contains("core::helper"));
            assert!(message.contains("stdlib root"));
            assert!(message.contains(&canonical_non_source.display().to_string()));
            assert!(message.contains("import core::helper;"));
            assert!(message.contains("canonical .lani source files"));
            assert!(!message.contains("GPU frontend error"));
        }
        other => panic!("expected frontend stdlib non-source diagnostic, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove temp stdlib non-source test dir");
}

#[cfg(unix)]
#[test]
fn source_root_loader_rejects_user_symlink_escape() {
    let root = common::temp_artifact_path("laniusc_source_root", "user_symlink", None);
    let source_root = root.join("src");
    let outside_root = root.join("outside");
    std::fs::create_dir_all(source_root.join("app")).expect("create temp source root");
    std::fs::create_dir_all(&outside_root).expect("create outside root");
    let outside_module = outside_root.join("escape.lani");
    std::fs::write(&outside_module, "module app::escape;\n").expect("write outside module");
    std::os::unix::fs::symlink(&outside_module, source_root.join("app/escape.lani"))
        .expect("create user source-root symlink escape");
    let entry =
        common::TempArtifact::new("laniusc_source_root", "user_symlink_entry", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import app::escape;
fn main() { return 0; }
"#,
    );

    let err = load_entry_with_source_root(entry.path(), &source_root)
        .expect_err("source-root loader should reject user symlink escapes");
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0004");
            let message = diagnostic.render();
            assert!(message.contains("app::escape"));
            assert!(message.contains("outside source root"));
            assert!(message.contains("import app::escape;"));
        }
        other => panic!("expected frontend user symlink escape error, got {other:?}"),
    }

    std::fs::remove_dir_all(&root).expect("remove temp user source-root symlink test dir");
}

#[test]
fn type_checker_rejects_duplicate_declarations_in_same_module_on_gpu() {
    assert_gpu_type_check_pack_rejects(&[r#"
module app::main;

fn duplicate() -> i32 { return 1; }
fn duplicate() -> i32 { return 2; }

fn main() { return duplicate(); }
"#]);

    assert_gpu_type_check_pack_rejects(&[r#"
module app::main;

type Duplicate = i32;
type Duplicate = bool;

fn main() { return 0; }
"#]);
}

#[test]
fn type_checker_enforces_stdlib_trait_where_obligations_from_source_pack() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/core/cmp.lani"),
        include_str!("../stdlib/core/hash.lani"),
        r#"
module app::main;

import core::cmp;
import core::hash;

fn keep_cmp<T>(value: T) -> T where T: core::cmp::Eq<T> {
    return value;
}

fn keep_hash<T>(value: T) -> T where T: core::hash::Hash<T> {
    return value;
}

fn keep_both<T>(value: T) -> T where T: core::cmp::Eq<T> + core::hash::Hash<T> {
    return value;
}

fn main() {
    let left: i32 = keep_cmp(7);
    let middle: i32 = keep_hash(left);
    let right: i32 = keep_both(middle);
    return right;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        include_str!("../stdlib/core/cmp.lani"),
        include_str!("../stdlib/core/hash.lani"),
        r#"
module app::main;

import core::cmp;
import core::hash;

fn keep_both<T>(value: T) -> T where T: core::cmp::Eq<T> + core::hash::Hash<T> {
    return value;
}

fn main() {
    let value: bool = keep_both(true);
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_core_stdlib_module_calls() {
    let cases = [
        (
            "core::bool",
            &[include_str!("../stdlib/core/bool.lani")][..],
            r#"
module app::main;

import core::bool;

fn main() {
    let inverted: bool = core::bool::not(false);
    let both: bool = core::bool::and(inverted, true);
    let either: bool = core::bool::or(false, both);
    let changed: bool = core::bool::xor(either, false);
    let same: bool = core::bool::eq(changed, true);
    let numeric: bool = core::bool::from_i32(1);
    if (same && numeric) {
        return 0;
    }
    return 1;
}
"#,
        ),
        (
            "core::i32",
            &[include_str!("../stdlib/core/i32.lani")][..],
            r#"
module app::main;

import core::i32;

fn main() {
    let magnitude: i32 = core::i32::saturating_abs(-7);
    let lower: i32 = core::i32::min(magnitude, core::i32::MAX);
    let signed: i32 = core::i32::signum(-3);
    let powered: bool = core::i32::is_power_of_two(8);
    if (powered && signed == -1 && lower == 7) {
        return core::i32::clamp(lower, 0, 7);
    }
    return 1;
}
"#,
        ),
        (
            "core::char+u32",
            &[
                include_str!("../stdlib/core/char.lani"),
                include_str!("../stdlib/core/u32.lani"),
            ][..],
            r#"
module app::main;

import core::char;
import core::u32;

fn main() {
    let digit: bool = core::char::is_ascii_digit('7');
    let alpha: bool = core::char::is_ascii_alphabetic('Q');
    let clamped: u32 = core::u32::clamp(9, core::u32::MIN, 7);
    let wrapped: u32 = core::u32::wrapping_add(core::u32::MAX, 1);
    if (digit && alpha && clamped == 7 && wrapped == 0) {
        return 0;
    }
    return 1;
}
"#,
        ),
        (
            "core::u8+i64",
            &[
                include_str!("../stdlib/core/u8.lani"),
                include_str!("../stdlib/core/i64.lani"),
            ][..],
            r#"
module app::main;

import core::u8;
import core::i64;

fn main() {
    let ascii: bool = core::u8::is_ascii_digit(57);
    let low: u8 = core::u8::min(9, 4);
    let magnitude: i64 = core::i64::abs(-7);
    let bounded: i64 = core::i64::clamp(magnitude, 0, 5);
    if (ascii && low == 4 && bounded == 5) {
        return 0;
    }
    return 1;
}
"#,
        ),
        (
            "core::f32",
            &[include_str!("../stdlib/core/f32.lani")][..],
            r#"
module app::main;

import core::f32;

fn choose(value: f32) -> f32 {
    let magnitude: f32 = core::f32::abs(value);
    let low: f32 = core::f32::min(magnitude, core::f32::ONE);
    let bounded: f32 = core::f32::clamp(low, core::f32::ZERO, 1.0);
    if (bounded > 0.5) {
        return bounded;
    }
    return core::f32::max(bounded, 0.5);
}

fn main() {
    let value: f32 = choose(-2.0);
    if (value > 0.5) {
        return 0;
    }
    return 1;
}
"#,
        ),
    ];

    for (label, sources, app_source) in cases {
        let mut sources = sources.to_vec();
        if !app_source.is_empty() {
            sources.push(app_source);
        }
        common::type_check_source_pack_with_timeout(&sources).unwrap_or_else(|err| {
            panic!("{label} source pack should pass GPU type checking: {err:?}")
        });
    }
}

#[test]
fn type_checker_keeps_f32_arithmetic_results_as_f32() {
    assert_gpu_type_check_accepts(
        r#"
module app::main;

struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn new(x: f32, y: f32, z: f32) -> Vec3 {
        return Vec3 { x: x, y: y, z: z };
    }

    fn add(self, right: Vec3) -> Vec3 {
        return Vec3::new(self.x + right.x, self.y - right.y, self.z * right.z);
    }

    fn scale(self, factor: f32) -> Vec3 {
        return Vec3::new(self.x / factor, -self.y, self.z + 1.0);
    }
}

fn take(value: f32) -> f32 {
    return value;
}

fn main() {
    let left: Vec3 = Vec3::new(1.0, 2.0, 3.0);
    let right: Vec3 = Vec3::new(4.0, 5.0, 6.0);
    let sum: Vec3 = left.add(right);
    let scaled: Vec3 = sum.scale(2.0);
    let value: f32 = take(scaled.x + 0.5);
    if (value > 0.0) {
        return 0;
    }
    return 1;
}
"#,
    );
}

#[test]
fn type_checker_accepts_qualified_generic_type_associated_call() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/std/vec.lani"),
        r#"
module app::main;

import std::vec;

struct Sphere {
    radius: f32,
}

fn main() {
    let world: std::vec::Vec<Sphere> = std::vec::Vec<Sphere>::new();
    let count: i32 = world.len();
    return count;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_core_range_module_calls() {
    let cases = [
        (
            &[include_str!("../stdlib/core/range.lani")][..],
            r#"
module app::main;

import core::range;

fn main() {
    let range: core::range::Range<i32> = core::range::range_i32(1, 4);
    let start: i32 = core::range::start_i32(range);
    let end: i32 = core::range::end_i32(range);
    if (core::range::contains_i32(range, 2)) {
        return start;
    }
    return end;
}
"#,
        ),
        (
            &[include_str!("../stdlib/core/range.lani")][..],
            r#"
module app::main;

import core::range;

fn main() {
    let range: core::range::Range<i32> = core::range::range_i32(1, 4);
    let start: i32 = range.start();
    let end: i32 = range.end();
    let direct_start: i32 = core::range::range_i32(1, 4).start();
    let direct_contains: bool = core::range::range_i32(1, 4).contains(2);
    if (range.contains(2) && direct_contains) {
        return start + direct_start;
    }
    return end;
}
"#,
        ),
        (
            &[include_str!("../stdlib/core/range.lani")][..],
            r#"
module app::main;

import core::range;

fn main() {
    let range: core::range::RangeInclusive<i32> = core::range::range_inclusive_i32(1, 4);
    let start: i32 = range.start();
    let end: i32 = range.end();
    let empty: bool = range.is_empty();
    let direct_end: i32 = core::range::range_inclusive_i32(1, 4).end();
    let direct_contains: bool = core::range::range_inclusive_i32(1, 4).contains(4);
    let direct_empty: bool = core::range::range_inclusive_i32(5, 4).is_empty();
    if (range.contains(4) && !empty && !direct_empty) {
        return direct_end;
    }
    return start + end;
}
"#,
        ),
    ];

    for (sources, app_source) in cases {
        assert_source_pack_case_accepts(sources, app_source);
    }
}

#[test]
fn type_checker_rejects_private_cross_module_method_call() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::private_methods;

pub struct Thing {
    value: i32,
}

pub fn make(value: i32) -> Thing {
    return Thing { value: value };
}

impl Thing {
    fn hidden(self) -> i32 {
        return self.value;
    }
}
"#,
        r#"
module app::main;

import core::private_methods;

fn main() {
    let thing: core::private_methods::Thing = core::private_methods::make(1);
    return thing.hidden();
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_duplicate_inherent_methods_in_same_module_on_gpu() {
    assert_gpu_type_check_pack_rejects(&[r#"
module app::main;

struct Thing {
    value: i32,
}

impl Thing {
    fn read(self) -> i32 {
        return self.value;
    }

    fn read(self) -> i32 {
        return 0;
    }
}

fn main() {
    let thing: Thing = Thing { value: 1 };
    return thing.read();
}
"#]);
}

#[test]
fn type_checker_accepts_core_ordering_module_calls() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/core/ordering.lani"),
        r#"
module app::main;

import core::ordering;

fn main() {
    let ordering: core::ordering::Ordering = core::ordering::compare_i32(1, 2);
    let less: core::ordering::Ordering = core::ordering::Less;
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_qualified_generic_option_and_result_calls() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/core/option.lani"),
        include_str!("../stdlib/core/result.lani"),
        r#"
module app::main;

import core::option;
import core::result;

fn option_value() -> i32 {
    let value: core::option::Option<i32> = core::option::Some(1);
    let fallback: i32 = 2;
    let is_some: bool = core::option::is_some(value);
    if (is_some) {
        return core::option::unwrap_or(value, fallback);
    }
    return fallback;
}

fn result_value() -> i32 {
    let value: core::result::Result<i32, bool> = core::result::Ok(1);
    let is_ok: bool = core::result::is_ok(value);
    if (is_ok) {
        return core::result::unwrap_or(value, 3);
    }
    return 3;
}

fn main() {
    let left: i32 = option_value();
    let right: i32 = result_value();
    return left + right;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_qualified_generic_enum_instance_returns() {
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/core/result.lani"),
        include_str!("../stdlib/core/option.lani"),
        r#"
module app::main;

import core::option;

fn main() {
    let none: core::option::Option<i32> = core::option::None;
    let replaced: core::option::Option<i32> = core::option::replace(none, 11);
    return core::option::unwrap_or(replaced, 0);
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_qualified_generic_option_and_result_call_mismatches() {
    assert_gpu_type_check_pack_rejects(&[
        include_str!("../stdlib/core/result.lani"),
        include_str!("../stdlib/core/option.lani"),
        r#"
module app::main;

import core::option;

fn main() {
    let value: core::option::Option<i32> = core::option::Some(1);
    return core::option::unwrap_or(value, true);
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        include_str!("../stdlib/core/result.lani"),
        r#"
module app::main;

import core::result;

fn main() {
    let value: core::result::Result<i32, bool> = core::result::Ok(1);
    return core::result::unwrap_or(value, false);
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        include_str!("../stdlib/core/result.lani"),
        include_str!("../stdlib/core/option.lani"),
        r#"
module app::main;

import core::option;

fn main() {
    let value: core::option::Option<i32> = core::option::None;
    let wrong: core::option::Option<bool> = core::option::replace(value, 11);
    return 0;
}
"#,
    ]);
}

#[test]
fn accepts_bounded_generic_callees_rejects_conflicts() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::id;

pub fn keep<T>(value: T) -> T {
    return value;
}
"#,
        r#"
module app::main;

import core::id;

fn main() {
    return core::id::keep(1);
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::id;

pub fn keep<T>(value: T) -> T {
    return value;
}
"#,
        r#"
module app::main;

import core::id;

fn main() {
    let flag: bool = core::id::keep(1);
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::id;

pub fn choose<T>(left: T, right: T) -> T {
    return left;
}
"#,
        r#"
module app::main;

import core::id;

fn main() {
    return core::id::choose(1, 2);
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::id;

pub fn choose<T>(left: T, right: T) -> T {
    return left;
}
"#,
        r#"
module app::main;

import core::id;

fn main() {
    return core::id::choose(1, true);
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_source_pack_generic_callee_at_two_concrete_types() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::id;

pub fn identity<T>(value: T) -> T {
    return value;
}
"#,
        r#"
module other::id;

pub fn identity(value: bool) -> bool {
    return value;
}
"#,
        r#"
module app::main;

import core::id;
import other::id;

fn main() {
    let number: i32 = core::id::identity(7);
    let flag: bool = core::id::identity(false);
    let decoy: bool = other::id::identity(flag);
    if (decoy) {
        return number;
    }
    return 0;
}
"#,
    ]);
}

#[test]
fn rejects_non_constructor_symbolic_enum_returns() {
    assert_gpu_type_check_pack_rejects(&[
        include_str!("../stdlib/core/result.lani"),
        include_str!("../stdlib/core/option.lani"),
        r#"
module app::main;

import core::option;

fn wrong<T>(value: T) -> core::option::Option<T> {
    return value;
}

fn main() {
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_resolves_same_module_qualified_type_paths() {
    assert_gpu_type_check_accepts(
        r#"
module app::main;

struct Point {
    x: i32,
}

enum Choice {
    Yes,
    No,
}

fn take(point: app::main::Point, choice: app::main::Choice) {
    return;
}

fn main() {
    return 0;
}
"#,
    );

    assert_gpu_type_check_accepts(
        r#"
module app::main;

struct Point {
    x: i32,
}

fn x_of(point: app::main::Point) -> i32 {
    return point.x;
}

fn copy(point: app::main::Point) -> app::main::Point {
    return point;
}

fn main() {
    return 0;
}
"#,
    );

    assert_gpu_type_check_accepts(
        r#"
module app::main;

struct Point {
    x: i32,
}

fn copy(point: app::main::Point) -> app::main::Point {
    let local: app::main::Point = point;
    return local;
}

fn main() {
    return 0;
}
"#,
    );

    assert_gpu_type_check_rejects(
        r#"
module app::main;

struct Point {
    x: i32,
}

fn copy(point: app::main::Point) -> app::main::Point {
    let local: app::other::Point = point;
    return local;
}

fn main() {
    return 0;
}
"#,
    );

    assert_gpu_type_check_rejects(
        r#"
fn take(value: core::option::Option<i32>) {
    return;
}

fn main() {
    return 0;
}
"#,
    );
}

#[test]
fn type_checker_resolves_qualified_function_calls() {
    assert_gpu_type_check_accepts(
        r#"
module app;

fn helper() -> i32 {
    return 1;
}

fn main() {
    let value: i32 = app::helper();
    return value;
}
"#,
    );
    assert_gpu_type_check_accepts(
        r#"
module app::main;

fn helper() -> i32 {
    return 1;
}

fn main() {
    return app::main::helper();
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
module app;

fn helper() -> i32 {
    return 1;
}

fn main() {
    let flag: bool = app::helper();
    return 0;
}
"#,
    );
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::math;

pub fn one() -> i32 {
    return 1;
}
"#,
        r#"
module app::main;

import core::math;

fn main() {
    return core::math::one();
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import std::io;

fn main() {
    let code: i32 = std::io::flush_stdout();
    std::io::print_i32(code);
    return code;
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[
        include_str!("../stdlib/alloc/allocator.lani"),
        r#"
module app::main;

import alloc::allocator;

fn main() {
    let ptr: u32 = alloc::allocator::alloc(16, 4);
    alloc::allocator::dealloc(ptr, 16, 4);
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_rejects(
        r#"
module app::main;

fn helper() -> i32 {
    return 1;
}

fn main() {
    return app::other::helper();
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
module app;

fn helper() -> i32 {
    return 1;
}

fn main() {
    return other::helper();
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
module app;

fn main() {
    return app::missing();
}
"#,
    );
}

#[test]
fn type_checker_resolves_qualified_generic_call_arguments_by_ordinal() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module math::generic;

pub fn same<T>(left: T, right: T) -> T {
    return left;
}
"#,
        r#"
module app::main;

import math::generic;

fn main() {
    let value: i32 = math::generic::same(1, 2);
    return value;
}
"#,
    ]);

    assert_gpu_type_check_pack_rejects(&[
        r#"
module math::generic;

pub fn same<T>(left: T, right: T) -> T {
    return left;
}
"#,
        r#"
module app::main;

import math::generic;

fn main() {
    let value: i32 = math::generic::same(1, false);
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_stdlib_host_module_calls() {
    let cases = [
        (
            &[
                include_str!("../stdlib/std/env.lani"),
                include_str!("../stdlib/std/fs.lani"),
                include_str!("../stdlib/std/net.lani"),
                include_str!("../stdlib/std/process.lani"),
                include_str!("../stdlib/std/time.lani"),
            ][..],
            r#"
module app::main;

import std::env;
import std::fs;
import std::net;
import std::process;
import std::time;

fn main() {
    let zero_ptr: u32 = 0;
    let zero_len: usize = 0;
    let sleep_zero: i64 = 0;
    let args: i32 = std::process::argc();
    let first_arg_len: i32 = std::process::arg_len(0);
    let vars: i32 = std::env::var_count();
    let first_var_len: i32 = std::env::var_key_len(0);
    let file: i32 = std::fs::open_read(zero_ptr, zero_len);
    let bytes: i32 = std::fs::read(file, zero_ptr, zero_len);
    let now: i64 = std::time::monotonic_now_ns();
    let slept: i32 = std::time::sleep_ms(sleep_zero);
    let tcp: i32 = std::net::tcp_connect(zero_ptr, zero_len, 80);
    let udp: i32 = std::net::udp_bind(zero_ptr, zero_len, 53);
    std::process::set_exit_code(0);
    return args + first_arg_len + vars + first_var_len + file + bytes + slept + tcp + udp;
}
"#,
        ),
        (
            &[
                include_str!("../stdlib/alloc/allocator.lani"),
                include_str!("../stdlib/std/io.lani"),
            ][..],
            r#"
module app::main;

import alloc::allocator;
import std::io;

fn main() {
    let size: usize = 16;
    let grown_size: usize = 32;
    let align: usize = 4;
    let ptr: u32 = alloc::allocator::alloc(size, align);
    let grown: u32 = alloc::allocator::realloc(ptr, size, grown_size, align);
    let stdin_count: i32 = std::io::read_stdin(grown, grown_size);
    let stdout_count: i32 = std::io::write_stdout(grown, grown_size);
    let stderr_count: i32 = std::io::write_stderr(grown, grown_size);
    let flushed: i32 = std::io::flush_stderr();
    std::io::print_i32(stdin_count + stdout_count + stderr_count + flushed);
    alloc::allocator::dealloc(grown, grown_size, align);
    alloc::allocator::alloc_failed(grown_size, align);
    return std::io::flush_stdout();
}
"#,
        ),
        (
            &[include_str!("../stdlib/core/target.lani")][..],
            r#"
module app::main;

import core::target;

fn main() {
    let native: Capability = core::target::is_native();
    let has_stdio: core::target::Capability = core::target::HAS_STDIO;
    let threaded: Capability = core::target::has_threads();
    if (native && has_stdio && !threaded) {
        return 0;
    }
    return 1;
}
"#,
        ),
        (
            &[include_str!("../stdlib/core/panic.lani")][..],
            r#"
module app::main;

import core::panic;

fn main() {
    core::panic::unreachable();
    return 0;
}
"#,
        ),
        (
            &[include_str!("../stdlib/test/assert.lani")][..],
            r#"
module app::main;

import test::assert;

fn main() {
    let value: i32 = 7;
    test::assert::eq_i32(value, 7);
    test::assert::is_true(value == 7);
    return value;
}
"#,
        ),
    ];

    for (sources, app_source) in cases {
        assert_source_pack_case_accepts(sources, app_source);
    }
}

#[test]
fn type_checker_accepts_direct_host_abi_extern_calls() {
    let cases = [
        (
            "lanius_std",
            r#"
extern "lanius_std" fn argc() -> i32;
extern "lanius_std" fn var_count() -> i32;
extern "lanius_std" fn open_read(path_ptr: u32, path_len: usize) -> i32;
extern "lanius_std" fn monotonic_now_ns() -> i64;
extern "lanius_std" fn tcp_connect(addr_ptr: u32, addr_len: usize, port: i32) -> i32;
extern "lanius_std" fn print_i32(value: i32);

fn main() {
    let args: i32 = argc();
    let vars: i32 = var_count();
    let file: i32 = open_read(0, 0);
    let sock: i32 = tcp_connect(0, 0, 80);
    let now: i64 = monotonic_now_ns();
    print_i32(args + vars + file + sock);
    return 0;
}
"#,
        ),
        (
            "lanius_alloc",
            r#"
extern "lanius_alloc" fn alloc(size: usize, align: usize) -> u32;
extern "lanius_alloc" fn realloc(ptr: u32, old_size: usize, new_size: usize, align: usize) -> u32;
extern "lanius_alloc" fn dealloc(ptr: u32, size: usize, align: usize);
extern "lanius_alloc" fn alloc_failed(size: usize, align: usize);

fn main() {
    let ptr: u32 = alloc(16, 4);
    let grown: u32 = realloc(ptr, 16, 32, 4);
    dealloc(grown, 32, 4);
    alloc_failed(64, 8);
    return 0;
}
"#,
        ),
    ];

    for (label, source) in cases {
        common::type_check_source_with_timeout(source).unwrap_or_else(|err| {
            panic!("{label} extern declarations should pass GPU type checking: {err:?}")
        });
    }
}

#[test]
fn type_checker_resolves_qualified_trait_bounds() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::cmp;

pub trait Eq<T> {
    pub fn check(value: T) -> bool;
}

pub impl Eq<i32> for i32 {
    pub fn check(value: i32) -> bool {
        return value > 0;
    }
}
"#,
        r#"
module app;

import core::cmp;

fn keep<T>(value: T) -> T where T: core::cmp::Eq<T> {
    return value;
}

fn main() {
    let value: i32 = keep(7);
    return value;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::cmp;

pub trait Eq<T> {
    pub fn check(value: T) -> bool;
}
"#,
        r#"
module app;

fn keep<T>(value: T) -> T where T: core::missing::Eq<T> {
    return value;
}

fn main() {
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::cmp;

pub struct Eq<T> {
    value: T,
}
"#,
        r#"
module app;

fn keep<T>(value: T) -> T where T: core::cmp::Eq<T> {
    return value;
}

fn main() {
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_leaf_name_trait_impl_for_different_qualified_bound() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::cmp;

pub trait Eq<T> {
    pub fn check(value: T) -> bool;
}
"#,
        r#"
module other::cmp;

pub trait Eq<T> {
    pub fn check(value: T) -> bool;
}

pub impl other::cmp::Eq<i32> for i32 {
    pub fn check(value: i32) -> bool {
        return value > 0;
    }
}
"#,
        r#"
module app;

fn keep<T>(value: T) -> T where T: core::cmp::Eq<T> {
    return value;
}

fn main() {
    let value: i32 = keep(7);
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_unqualified_trait_impl_for_different_module_bound() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::cmp;

pub trait Eq<T> {
    pub fn check(value: T) -> bool;
}
"#,
        r#"
module other::cmp;

pub trait Eq<T> {
    pub fn check(value: T) -> bool;
}

pub impl Eq<i32> for i32 {
    pub fn check(value: i32) -> bool {
        return value > 0;
    }
}
"#,
        r#"
module app;

fn keep<T>(value: T) -> T where T: core::cmp::Eq<T> {
    return value;
}

fn main() {
    let value: i32 = keep(7);
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_resolves_qualified_constants() {
    assert_gpu_type_check_accepts(
        r#"
module app;

pub const LIMIT: i32 = 7;

fn main() {
    let value: i32 = app::LIMIT;
    return value;
}
"#,
    );
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::i32;

pub const MIN: i32 = -2147483648;
"#,
        r#"
module app::main;

import core::i32;

fn main() {
    let value: i32 = core::i32::MIN;
    return value;
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::limits;

pub const MIN: i32 = -2147483648;
"#,
        r#"
module app::main;

import core::limits;

fn main() {
    let value: i32 = MIN;
    return value;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::limits;

pub const MIN: i32 = -2147483648;
"#,
        r#"
module app::main;

fn main() {
    let value: i32 = MIN;
    return value;
}
"#,
    ]);
    assert_gpu_type_check_rejects(
        r#"
module app;

pub const LIMIT: i32 = 7;

fn main() {
    let flag: bool = app::LIMIT;
    return 0;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
module app;

pub const LIMIT: i32 = 7;

fn main() {
    return app::MISSING;
}
"#,
    );
    assert_gpu_type_check_rejects(
        r#"
module app;

fn helper() -> i32 {
    return 1;
}

fn main() {
    let value: i32 = app::helper;
    return value;
}
"#,
    );
}

#[test]
fn type_checker_rejects_private_cross_module_constants() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::limits;

const SECRET: i32 = 7;
"#,
        r#"
module app::main;

import core::limits;

fn main() {
    let value: i32 = core::limits::SECRET;
    return value;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::limits;

const SECRET: i32 = 7;
"#,
        r#"
module app::main;

import core::limits;

fn main() {
    let value: i32 = SECRET;
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_resolves_public_import_despite_private_imported_name_collision() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::private_limits;

const VALUE: bool = false;
"#,
        r#"
module core::public_limits;

pub const VALUE: i32 = 7;
"#,
        r#"
module app::main;

import core::private_limits;
import core::public_limits;

fn main() {
    let value: i32 = VALUE;
    return value;
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::private_math;

fn choose() -> bool {
    return false;
}
"#,
        r#"
module core::public_math;

pub fn choose() -> i32 {
    return 7;
}
"#,
        r#"
module app::main;

import core::private_math;
import core::public_math;

fn main() {
    let value: i32 = choose();
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_resolves_public_type_import_despite_private_imported_name_collision() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::private_types;

struct Token {
    hidden: bool,
}
"#,
        r#"
module core::public_types;

pub struct Token {
    value: i32,
}
"#,
        r#"
module app::main;

import core::private_types;
import core::public_types;

fn take(value: Token) -> i32 {
    return value.value;
}

fn main() {
    let item: Token = Token { value: 9 };
    return take(item);
}
"#,
    ]);
}

#[test]
fn type_checker_accepts_same_module_private_qualified_values() {
    assert_gpu_type_check_accepts(
        r#"
module app;

const SECRET: i32 = 7;

fn helper() -> i32 {
    return app::SECRET;
}

fn main() {
    return app::helper();
}
"#,
    );
}

#[test]
fn type_checker_rejects_private_cross_module_qualified_paths() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::secret;

fn hidden() -> i32 {
    return 7;
}
"#,
        r#"
module app::main;

fn main() {
    return core::secret::hidden();
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::secret;

struct Hidden {
    value: i32,
}
"#,
        r#"
module app::main;

fn accept(value: core::secret::Hidden) -> i32 {
    return 0;
}

fn main() {
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_ambiguous_imported_names() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::left;

pub const VALUE: i32 = 1;
"#,
        r#"
module core::right;

pub const VALUE: i32 = 2;
"#,
        r#"
module app::main;

import core::left;
import core::right;

fn main() {
    let value: i32 = VALUE;
    return value;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::left;

pub struct Item {
    value: i32,
}
"#,
        r#"
module core::right;

pub struct Item {
    value: i32,
}
"#,
        r#"
module app::main;

import core::left;
import core::right;

fn accept(value: Item) -> i32 {
    return 0;
}

fn main() {
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_ambiguous_imported_name_after_duplicate_reimport_prefix() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::left;

pub const VALUE: i32 = 1;
"#,
        r#"
module core::right;

pub const VALUE: i32 = 2;
"#,
        r#"
module app::main;

import core::left;
import core::left;
import core::right;

fn main() {
    let value: i32 = VALUE;
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_rejects_ambiguous_imported_names_independent_of_source_and_import_order() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::right;

pub const VALUE: i32 = 2;
"#,
        r#"
module core::left;

pub const VALUE: i32 = 1;
"#,
        r#"
module app::main;

import core::right;
import core::left;

fn main() {
    let value: i32 = VALUE;
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_keeps_imported_type_and_value_namespaces_separate() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::types;

pub struct Shared {
    value: i32,
}
"#,
        r#"
module core::values;

pub const Shared: i32 = 7;
"#,
        r#"
module app::main;

import core::types;
import core::values;

fn take(value: Shared) -> i32 {
    return value.value;
}

fn main() {
    let item: Shared = Shared { value: Shared };
    return take(item);
}
"#,
    ]);
}

#[test]
fn type_checker_prefers_local_declarations_over_imported_names() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::shadowed;

pub struct Item {
    flag: bool,
}

pub const VALUE: bool = false;
"#,
        r#"
module app::main;

import core::shadowed;

struct Item {
    value: i32,
}

const VALUE: i32 = 7;

fn take(item: Item) -> i32 {
    return item.value;
}

fn main() {
    let item: Item = Item { value: VALUE };
    return take(item);
}
"#,
    ]);
}

#[test]
fn type_checker_does_not_make_imported_names_transitively_visible() {
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::leaf;

pub const VALUE: i32 = 7;
"#,
        r#"
module core::mid;

import core::leaf;

pub fn forwarded() -> i32 {
    return core::leaf::VALUE;
}
"#,
        r#"
module app::main;

import core::mid;

fn main() {
    let value: i32 = VALUE;
    return value;
}
"#,
    ]);
}

#[test]
fn type_checker_resolves_qualified_unit_enum_variants() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::ordering;

pub enum Ordering {
    Less,
    Equal,
    Greater,
}
"#,
        r#"
module app::main;

import core::ordering;

fn accept(value: core::ordering::Ordering) -> i32 {
    return 0;
}

fn main() {
    let value: core::ordering::Ordering = core::ordering::Less;
    return accept(value);
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::ordering;

pub enum Ordering {
    Less,
    Equal,
    Greater,
}
"#,
        r#"
module app::main;

import core::ordering;

fn main() {
    let value: bool = core::ordering::Less;
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::maybe;

pub enum MaybeI32 {
    Some(i32),
    None,
}
"#,
        r#"
module app::main;

import core::maybe;

fn main() {
    let value: core::maybe::MaybeI32 = core::maybe::Some;
    return 0;
}
"#,
    ]);
}

#[test]
fn type_checker_resolves_generic_enum_constructors() {
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}
"#,
        r#"
module app::main;

import core::maybe;

fn accept(value: core::maybe::Maybe<i32>) -> i32 {
    return 0;
}

fn main() {
    let value: core::maybe::Maybe<i32> = core::maybe::Some(1);
    return accept(value);
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[
        r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}
"#,
        r#"
module app::main;

import core::maybe;

fn accept(value: core::maybe::Maybe<i32>) -> i32 {
    return 0;
}

fn main() {
    let value: core::maybe::Maybe<i32> = Some(1);
    return accept(value);
}
"#,
    ]);
    assert_gpu_type_check_pack_accepts(&[r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}

fn accept(value: Maybe<i32>) -> i32 {
    return 0;
}

fn main() {
    let value: Maybe<i32> = Some(1);
    return accept(value);
}
"#]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}
"#,
        r#"
module app::main;

import core::maybe;

fn main() {
    let value: core::maybe::Maybe<i32> = core::maybe::Some(true);
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}
"#,
        r#"
module app::main;

import core::maybe;

fn main() {
    let value: core::maybe::Maybe<i32> = core::maybe::Some();
    return 0;
}
"#,
    ]);
    assert_gpu_type_check_pack_rejects(&[
        r#"
module core::maybe;

pub enum Maybe<T> {
    Some(T),
    None,
}
"#,
        r#"
module app::main;

import core::maybe;

fn main() {
    let value: core::maybe::Maybe<i32> = core::maybe::None(1);
    return 0;
}
"#,
    ]);
}
