// Retained native builds (docs/compiler-retained-projection.md, "Native
// compilation"): a normal source-pack compile whose original nongeneric
// `main` calls generics in another frontend unit, linked and executed with
// no source replay.
use laniusc_compiler::{
    compiler::{
        ExplicitSourceLibraryPaths,
        ExplicitSourcePackPathManifest,
        GpuCompiler,
        RetainedNativeBuild,
        fallback_counters,
    },
    type_checker::program_retention::discovery::DiscoveryCapacity,
};

use crate::common;

// `pick` calls the generic `keep` (nested) and the nongeneric `bump` (a
// native helper). `pick` returns one i32 word and `pack` a two-field struct.
const LIB: &str = r#"module lib::a;
struct Hidden<T> { inner: T }
fn keep<T>(v: T) -> T { let h: Hidden<T> = Hidden { inner: v }; return h.inner; }
pub struct Pair { first: i32, second: u32 }
pub fn bump(x: i32) -> i32 { return x + 1; }
pub fn pick<T>(v: T, n: i32) -> i32 { let w: T = keep(v); return bump(n); }
pub fn pack<T>(n: i32, tag: T) -> Pair { return Pair { first: keep(n), second: 9 }; }
"#;

const APP: &str = r#"module app::b;
import lib::a;
fn main() -> i32 {
    let p: Pair = pack<bool>(3, true);
    let a: i32 = pick<u8>(7, 4);
    let b: i32 = pick<i32>(-2, p.first);
    let r: i32 = a + b + p.first;
    if (p.second == 9) { return r + 1; }
    return r;
}
"#;

fn manifest(directory: &std::path::Path) -> ExplicitSourcePackPathManifest {
    std::fs::create_dir_all(directory).unwrap();
    let lib = directory.join("lib.lani");
    let app = directory.join("app.lani");
    std::fs::write(&lib, LIB).unwrap();
    std::fs::write(&app, APP).unwrap();
    ExplicitSourcePackPathManifest::from_libraries(vec![
        ExplicitSourceLibraryPaths {
            library_id: 1,
            paths: vec![lib],
            dependency_library_ids: Vec::new(),
        },
        ExplicitSourceLibraryPaths {
            library_id: 2,
            paths: vec![app],
            dependency_library_ids: vec![1],
        },
    ])
    .expect("manifest")
}

#[test]
fn retained_native_build_executes_original_main_without_replay() {
    common::run_with_timeout("retained native build", retained_native_program);
}

fn retained_native_program() {
    let directory =
        std::env::temp_dir().join(format!("lanius-retained-native-{}", std::process::id()));
    let manifest = manifest(&directory);
    let compiler = pollster::block_on(GpuCompiler::new()).expect("compiler");
    let mut build = RetainedNativeBuild::new(DiscoveryCapacity::tiny()).expect("retained build");
    // Small lowering batches; the second build reruns in the same allocations.
    build.options.batch_rows = 8;
    for run in 0..2 {
        let retries_before = compiler.frontend_retry_counts();
        let before = fallback_counters();
        let elf = pollster::block_on(
            compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
        )
        .unwrap_or_else(|error| panic!("retained build {run}: {error:?}"));
        let after = fallback_counters();
        let retries_after = compiler.frontend_retry_counts();
        let retries: u64 = retries_after
            .iter()
            .zip(retries_before)
            .map(|(a, b)| a - b)
            .sum();
        let report = &build.report;
        eprintln!(
            "frontend retries (lexer, tree, typecheck, output): {:?}",
            std::array::from_fn::<_, 4, _>(|i| retries_after[i] - retries_before[i])
        );
        eprintln!(
            "retained build {run}: {} units, {} instance objects, {} instances, discovery {:?}",
            report.units, report.instance_objects, report.projection.instances, report.discovery
        );
        assert_eq!(report.units, 2, "one original object per unit");
        assert_eq!(
            build.store().job_reports().len(),
            report.units,
            "one committed export per unit"
        );
        assert_eq!(
            after.0 - before.0,
            report.units as u64 + retries,
            "one frontend recording per unit plus observed retries: {retries_before:?} -> {retries_after:?}"
        );
        assert_eq!(after.1, before.1, "no replay lowering");
        let catalog = report.catalog.as_ref().expect("GPU catalog was checked");
        assert_eq!(catalog.publication_status, Some([1, 0, u32::MAX]));
        assert!(catalog.tables.is_empty(), "no semantic row readback");
        assert!(
            report.instance_objects > 1,
            "small batches give several instance objects"
        );
        let out = common::run_x86_64_elf_output("retained native", "retained_native", &elf);
        assert_eq!(out.status.code(), Some(13), "{out:?}");
    }
    // Certification compares the recorded caller facts: with every caller
    // argument recorded as `bool`, `pick<u8>(7, 4)` no longer matches its
    // instance, the build fails before finalization, and a clean build then
    // succeeds in the same allocations.
    build.test_caller_arg_fault = Some(2);
    let error = pollster::block_on(
        compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
    )
    .expect_err("a caller ABI mismatch must fail the build");
    let message = format!("{error:?}");
    assert!(message.contains("root call ABI"), "{message}");
    build.test_caller_arg_fault = None;
    let elf = pollster::block_on(
        compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
    )
    .expect("clean build after the rejected one");
    let out = common::run_x86_64_elf_output("retained native", "retained_native", &elf);
    assert_eq!(out.status.code(), Some(13));
    std::fs::remove_dir_all(&directory).ok();
}

#[test]
fn retained_native_build_handles_one_library_and_no_instances() {
    common::run_with_timeout("retained native single library", || {
        let directory = std::env::temp_dir().join(format!(
            "lanius-retained-native-single-{}",
            std::process::id()
        ));
        std::fs::create_dir_all(&directory).unwrap();
        let path = directory.join("main.lani");
        let compiler = pollster::block_on(GpuCompiler::new()).unwrap();
        let mut build = RetainedNativeBuild::new(DiscoveryCapacity::tiny()).unwrap();
        let generic = "fn id<T>(v:T)->T { return v; }\nfn add<T>(a:T,b:T)->T { return a+b; }\nfn marker<T>()->i32 { return 1; }\nfn main()->i32 { return id(add<i32>(19,23))+marker<bool>(); }";
        for (source, expected, instances) in [
            (generic, 43, 3),
            (
                "fn value()->i32 { return 9; } fn main()->i32 { return value(); }",
                9,
                0,
            ),
            (generic, 43, 3),
        ] {
            std::fs::write(&path, source).unwrap();
            let manifest =
                ExplicitSourcePackPathManifest::from_libraries(vec![ExplicitSourceLibraryPaths {
                    library_id: 1,
                    paths: vec![path.clone()],
                    dependency_library_ids: Vec::new(),
                }])
                .unwrap();
            let retries_before = compiler.frontend_retry_counts();
            let before = fallback_counters();
            let elf = pollster::block_on(
                compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
            )
            .unwrap();
            let after = fallback_counters();
            let retries_after = compiler.frontend_retry_counts();
            let retries: u64 = retries_after
                .iter()
                .zip(retries_before)
                .map(|(a, b)| a - b)
                .sum();
            assert_eq!(
                after.0 - before.0,
                1 + retries,
                "only the original unit and observed retries: {retries_before:?} -> {retries_after:?}"
            );
            assert_eq!(after.1, before.1);
            assert_eq!(build.report.units, 1);
            assert_eq!(build.store().job_reports().len(), 1);
            assert_eq!(build.report.discovery.instances, instances);
            let out = common::run_x86_64_elf_output("retained single", "retained_single", &elf);
            assert_eq!(out.status.code(), Some(expected));
        }
        // Attaching an export-only store does not select the native retained
        // object mode. The existing source-pack API must keep its definitions.
        use laniusc_compiler::type_checker::program_retention::{
            ProgramRetention,
            ProgramRetentionCapacity,
        };
        let export = ProgramRetention::new(ProgramRetentionCapacity::default()).unwrap();
        compiler.attach_program_retention(Some(export));
        let elf = pollster::block_on(compiler.compile_source_pack_to_x86_64(&[generic])).unwrap();
        compiler.attach_program_retention(None);
        let out =
            common::run_x86_64_elf_output("retained export only", "retained_export_only", &elf);
        assert_eq!(out.status.code(), Some(43));
        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn retained_native_build_rejects_uncalled_conflicting_impls() {
    common::run_with_timeout("retained native coherence", || {
        let directory = std::env::temp_dir().join(format!(
            "lanius-retained-native-coherence-{}",
            std::process::id()
        ));
        std::fs::create_dir_all(&directory).unwrap();
        let defs = directory.join("defs.lani");
        let left = directory.join("left.lani");
        let right = directory.join("right.lani");
        std::fs::write(&defs, "module coh::defs;\npub trait Mark { pub fn mark(&self)->i32; }\npub struct Item { v:i32 }\npub struct Other { v:i32 }\n").unwrap();
        std::fs::write(&left, "module coh::left;\nimport coh::defs;\npub impl Mark for Item { pub fn mark(&self)->i32 { return 1; } }\n").unwrap();
        let source = |subject| {
            format!(
                "module coh::right;\nimport coh::defs;\npub impl Mark for {subject} {{ pub fn mark(&self)->i32 {{ return 2; }} }}\nfn main()->i32 {{ return 17; }}\n"
            )
        };
        std::fs::write(&right, source("Item")).unwrap();
        // Sibling units see only the shared declarations, never each other's
        // impls. No source job can decide this whole-program conflict.
        let make_manifest = || {
            ExplicitSourcePackPathManifest::from_libraries(vec![
                ExplicitSourceLibraryPaths {
                    library_id: 1,
                    paths: vec![defs.clone()],
                    dependency_library_ids: vec![],
                },
                ExplicitSourceLibraryPaths {
                    library_id: 2,
                    paths: vec![left.clone()],
                    dependency_library_ids: vec![1],
                },
                ExplicitSourceLibraryPaths {
                    library_id: 3,
                    paths: vec![right.clone()],
                    dependency_library_ids: vec![1],
                },
            ])
            .unwrap()
        };
        let compiler = pollster::block_on(GpuCompiler::new()).unwrap();
        let mut build = RetainedNativeBuild::new(DiscoveryCapacity::tiny()).unwrap();
        let manifest = make_manifest();
        let before = fallback_counters();
        let error = pollster::block_on(
            compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
        )
        .expect_err("uncalled overlapping impls must fail coherence");
        let message = format!("{error:?}");
        assert!(
            message.contains("trait catalog rejected")
                && message.contains("stage Admission")
                && message.contains("admission Some([5, 0,"),
            "{message}"
        );
        assert_eq!(build.store().job_reports().len(), 3);
        assert_eq!(fallback_counters().1, before.1, "no replay on rejection");
        // A non-overlapping impl is valid, and the rejected build leaves no
        // semantic state in the next build using the same allocations.
        std::fs::write(&right, source("Other")).unwrap();
        let manifest = make_manifest();
        let elf = pollster::block_on(
            compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
        )
        .unwrap();
        assert_eq!(build.report.units, 3);
        assert_eq!(build.report.discovery.instances, 0);
        assert_eq!(fallback_counters().1, before.1, "no replay after recovery");
        let out = common::run_x86_64_elf_output("retained coherence", "retained_coherence", &elf);
        assert_eq!(out.status.code(), Some(17));
        std::fs::remove_dir_all(directory).ok();
    });
}
