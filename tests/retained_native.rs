// Retained native builds (docs/compiler-retained-projection.md, "Native
// compilation"): a normal source-pack compile whose original nongeneric
// `main` calls generics in another frontend unit, linked and executed with
// no source replay.
use laniusc_compiler::{
    compiler::{ExplicitSourceLibraryPaths, ExplicitSourcePackPathManifest, GpuCompiler, RetainedNativeBuild, fallback_counters},
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
        ExplicitSourceLibraryPaths { library_id: 1, paths: vec![lib], dependency_library_ids: Vec::new() },
        ExplicitSourceLibraryPaths { library_id: 2, paths: vec![app], dependency_library_ids: vec![1] },
    ])
    .expect("manifest")
}

#[test]
fn retained_native_build_executes_original_main_without_replay() {
    common::run_with_timeout("retained native build", retained_native_program);
}

fn retained_native_program() {
    let directory = std::env::temp_dir().join(format!("lanius-retained-native-{}", std::process::id()));
    let manifest = manifest(&directory);
    let compiler = pollster::block_on(GpuCompiler::new()).expect("compiler");
    let mut build = RetainedNativeBuild::new(DiscoveryCapacity::tiny()).expect("retained build");
    // Small lowering batches; the second build reruns in the same allocations.
    build.options.batch_rows = 8;
    for run in 0..2 {
        let before = fallback_counters();
        let elf = pollster::block_on(compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build))
            .unwrap_or_else(|error| panic!("retained build {run}: {error}"));
        let after = fallback_counters();
        let report = &build.report;
        eprintln!(
            "retained build {run}: {} units, {} instance objects, {} instances, discovery {:?}",
            report.units, report.instance_objects, report.projection.instances, report.discovery
        );
        assert_eq!(report.units, 2, "one original object per unit");
        assert_eq!(after.0 - before.0, report.units as u64, "one frontend check per unit");
        assert_eq!(after.1, before.1, "no replay lowering");
        assert!(report.instance_objects > 1, "small batches give several instance objects");
        let out = common::run_x86_64_elf_output("retained native", "retained_native", &elf);
        assert_eq!(out.status.code(), Some(13), "{out:?}");
    }
    std::fs::remove_dir_all(&directory).ok();
}
