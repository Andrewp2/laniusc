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

#[test]
fn retained_native_arrays_keep_element_layout_and_value_semantics() {
    common::run_with_timeout("retained array projection", || {
        let directory =
            std::env::temp_dir().join(format!("lanius-retained-arrays-{}", std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let lib = directory.join("lib.lani");
        let app = directory.join("app.lani");
        std::fs::write(
            &lib,
            r#"module arrays::lib;
pub fn copy<T>(value:T)->T { return value; }
pub fn pair<T>(a:T,b:T)->[T;2] { return [a,b]; }
pub fn pick<T>(values:[T;2], index:i32)->T { return values[index]; }
"#,
        )
        .unwrap();
        std::fs::write(
            &app,
            r#"module arrays::app;
import arrays::lib;
struct Pair { a:i32, b:i32 }
fn main()->i32 {
    let original:[i32;2]=[19,23];
    let a:[i32;2]=copy(original);
    a[0]=7;
    if (original[0]!=19 || a[1]!=23) { return 1; }
    let b:[u8;2]=pair<u8>(5,9);
    if (pick(b,1)!=9) { return 2; }
    let c:[f64;2]=pair<f64>(1.5,2.5);
    if (pick(c,0)!=1.5 || pick(c,1)!=2.5) { return 3; }
    let d:[Pair;2]=pair(Pair{a:11,b:12},Pair{a:21,b:22});
    let q:Pair=pick(d,1);
    if (q.a!=21 || q.b!=22) { return 4; }
    let e:[[i32;2];2]=pair(original,a);
    let f:[i32;2]=pick(e,1);
    if (f[0]!=7 || f[1]!=23) { return 5; }
    let flags:[bool;2]=copy([false,true]);
    if (pick(flags,0) || !pick(flags,1)) { return 6; }
    return 42;
}
"#,
        )
        .unwrap();
        let manifest = ExplicitSourcePackPathManifest::from_libraries(vec![
            ExplicitSourceLibraryPaths {
                library_id: 1,
                paths: vec![lib],
                dependency_library_ids: vec![],
            },
            ExplicitSourceLibraryPaths {
                library_id: 2,
                paths: vec![app],
                dependency_library_ids: vec![1],
            },
        ])
        .unwrap();
        let compiler = pollster::block_on(GpuCompiler::new()).unwrap();
        let mut build = RetainedNativeBuild::new(DiscoveryCapacity::tiny()).unwrap();
        build.options.batch_rows = 16;
        let before = fallback_counters();
        let elf = pollster::block_on(
            compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
        )
        .unwrap();
        assert_eq!(
            fallback_counters().1,
            before.1,
            "array instances never replay"
        );
        assert!(build.report.instance_objects > 1);
        let out = common::run_x86_64_elf_output("retained arrays", "retained_arrays", &elf);
        assert_eq!(out.status.code(), Some(42), "{out:?}");
        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn retained_native_borrowed_values_keep_aliases_stride_and_bounds() {
    common::run_with_timeout("retained borrowed projection", || {
        let directory =
            std::env::temp_dir().join(format!("lanius-retained-borrows-{}", std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let lib = directory.join("lib.lani");
        let app = directory.join("app.lani");
        std::fs::write(
            &lib,
            r#"module borrowed::lib;
pub fn keep<T>(v:T)->T { return v; }
pub fn read<T>(v:&[T;3], index:i32)->T { return v[index]; }
pub fn read_twice<T>(v:& &[T;3], index:i32)->T { return v[index]; }
pub fn read_slice<T>(v:[T], index:i32)->T { return v[index]; }
pub fn pick_view<T>(v:[T;3], index:i32)->T { return read_slice<T>(v,index); }
pub fn write<T>(v:&[T;3], index:i32, value:T) { v[index]=value; }
"#,
        )
        .unwrap();
        let source = r#"module borrowed::app;
import borrowed::lib;
impl [i32;3] { fn borrow(&self)->&[i32;3] { return self; } }
impl &[i32;3] { fn outer(&self)->& &[i32;3] { return self; } }
impl [f64;3] { fn borrow(&self)->&[f64;3] { return self; } }
fn view(v:[i32])->[i32] { return v; }
fn main()->i32 {
    let data:[i32;3]=[11,13,17];
    let first:&[i32;3]=keep(data.borrow());
    let second:& &[i32;3]=keep(first.outer());
    if (read(first,0)!=11 || read_twice(second,2)!=17) { return 1; }
    write(first,1,19);
    if (data[1]!=19 || read_twice(second,1)!=19) { return 2; }
    data=[23,29,31];
    if (read(first,0)!=23 || read_twice(second,2)!=31) { return 3; }
    let slice:[i32]=keep(view(data));
    if (read_slice(slice,1)!=29) { return 4; }
    slice[1]=37;
    if (data[1]!=37 || read(first,1)!=37) { return 5; }
    if (read_slice<i32>(data,2)!=31 || pick_view(data,1)!=37) { return 7; }
    let floating:[f64;3]=[1.5,2.5,3.5];
    if (read(floating.borrow(),2)!=3.5) { return 6; }
    return 42;
}
"#;
        let compiler = pollster::block_on(GpuCompiler::new()).unwrap();
        let mut build = RetainedNativeBuild::new(DiscoveryCapacity::tiny()).unwrap();
        build.options.batch_rows = 16;
        let before = fallback_counters();
        for (tail, expected) in [
            ("return 42;", 42),
            ("return read(first,-1);", 101),
            ("return read_slice(slice,3);", 101),
        ] {
            std::fs::write(&app, source.replace("return 42;", tail)).unwrap();
            let manifest = ExplicitSourcePackPathManifest::from_libraries(vec![
                ExplicitSourceLibraryPaths {
                    library_id: 1,
                    paths: vec![lib.clone()],
                    dependency_library_ids: vec![],
                },
                ExplicitSourceLibraryPaths {
                    library_id: 2,
                    paths: vec![app.clone()],
                    dependency_library_ids: vec![1],
                },
            ])
            .unwrap();
            let elf = pollster::block_on(
                compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
            )
            .unwrap();
            assert_eq!(
                fallback_counters().1,
                before.1,
                "borrowed instances never replay"
            );
            let out = common::run_x86_64_elf_output("retained borrows", "retained_borrows", &elf);
            assert_eq!(out.status.code(), Some(expected), "{tail}: {out:?}");
        }
        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn retained_native_constant_values_and_array_extents_execute() {
    common::run_with_timeout("retained constant projection", || {
        let directory =
            std::env::temp_dir().join(format!("lanius-retained-constants-{}", std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let lib = directory.join("lib.lani");
        let app = directory.join("app.lani");
        std::fs::write(
            &lib,
            r#"module constants::lib;
pub fn copy<T,const N:usize>(v:[T;N])->[T;N] { return v; }
pub fn fill<T>(v:T)->[T;3] { return [v;3]; }
pub fn zero<const N:usize>()->[i32;3] { return [0;3]; }
pub fn sum<const N:usize>(v:[i32;N])->i32 {
    let total:i32=0; let i:usize=0;
    while (i<N) { total=total+v[i]; i=i+1; }
    return total;
}
pub fn forward<const N:usize>(v:[i32;N])->i32 { return sum(copy(v)); }
pub fn flag<const B:bool>()->bool { return B; }
pub fn scalar<const N:u8>()->u8 { return N; }
"#,
        )
        .unwrap();
        std::fs::write(
            &app,
            r#"module constants::app;
import constants::lib;
fn main()->i32 {
    let empty:[i32;0]=[];
    let single:[i32;1]=[-7];
    let values:[i32;3]=[11,22,33];
    if (forward(empty)!=0 || forward(single)!=-7 || forward(values)!=66) { return 1; }
    let repeated:[i32;3]=fill<i32>(7);
    let flags:[bool;3]=fill<bool>(true);
    if (sum(repeated)!=21 || !flags[2]) { return 2; }
    let blank:[i32;3]=zero<3>();
    if (sum(blank)!=0) { return 3; }
    if (!flag<true>() || flag<false>() || scalar<255>()!=255 || scalar<3>()!=3) { return 4; }
    return 42;
}
"#,
        )
        .unwrap();
        let manifest = ExplicitSourcePackPathManifest::from_libraries(vec![
            ExplicitSourceLibraryPaths {
                library_id: 1,
                paths: vec![lib],
                dependency_library_ids: vec![],
            },
            ExplicitSourceLibraryPaths {
                library_id: 2,
                paths: vec![app],
                dependency_library_ids: vec![1],
            },
        ])
        .unwrap();
        let compiler = pollster::block_on(GpuCompiler::new()).unwrap();
        let mut build = RetainedNativeBuild::new(DiscoveryCapacity::tiny()).unwrap();
        build.options.batch_rows = 16;
        let before = fallback_counters();
        let compiled = pollster::block_on(
            compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
        );
        let elf = compiled.unwrap();
        assert_eq!(
            fallback_counters().1,
            before.1,
            "constant instances never replay"
        );
        let out = common::run_x86_64_elf_output("retained constants", "retained_constants", &elf);
        assert_eq!(out.status.code(), Some(42), "{out:?}");
        std::fs::remove_dir_all(directory).ok();
    });
}
