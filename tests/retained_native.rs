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

#[test]
fn retained_native_strings_keep_decoded_bytes_across_batches_and_rebuilds() {
    common::run_with_timeout("retained native strings", || {
        let directory = std::env::temp_dir().join(format!(
            "lanius-retained-native-strings-{}",
            std::process::id()
        ));
        std::fs::create_dir_all(&directory).unwrap();
        let lib = directory.join("lib.lani");
        let app = directory.join("main.lani");
        std::fs::write(
            &app,
            r#"module app::main;
import text::lib;
extern "lanius_std" fn write_text(handle:i32, text:str)->i32;
fn main()->i32 {
    write_text(1, message<bool>(true, 0));
    write_text(1, empty<i32>(0));
    write_text(1, keep<str>(message<i32>(1, 1)));
    write_text(1, long_text<u8>(2));
    return 42;
}
"#,
        )
        .unwrap();
        let compiler = pollster::block_on(GpuCompiler::new()).unwrap();
        let mut build = RetainedNativeBuild::new(DiscoveryCapacity::tiny()).unwrap();
        // Independent pools and relocations in several native objects. Shrinking
        // and then growing the pool on later builds must not retain old bytes.
        build.options.batch_rows = 8;
        for (length, batch_rows) in [(8193, 8), (3, 4096), (16385, 8)] {
            build.options.batch_rows = batch_rows;
            let long = "abcλ".repeat(length);
            std::fs::write(
                &lib,
                format!(
                    r#"module text::lib;
pub fn keep<T>(v:T)->T {{ return v; }}
pub fn message<T>(tag:T, which:i32)->str {{
    if (which == 0) {{ return "hello\n\"λ\"\\\t"; }}
    return "second\n";
}}
pub fn empty<T>(tag:T)->str {{ return ""; }}
pub fn long_text<T>(tag:T)->str {{ return "{long}"; }}
"#
                ),
            )
            .unwrap();
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
            let before = fallback_counters();
            let elf = pollster::block_on(
                compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
            )
            .unwrap_or_else(|e| panic!("strings ({length}): {e:?}"));
            assert_eq!(fallback_counters().1, before.1, "no replay lowering");
            assert_eq!(build.report.instance_objects > 1, batch_rows == 8);
            let output =
                common::run_x86_64_elf_output("retained strings", "retained_strings", &elf);
            assert_eq!(output.status.code(), Some(42), "{output:?}");
            assert_eq!(
                output.stdout,
                format!("hello\n\"λ\"\\\tsecond\n{long}").as_bytes()
            );
            assert!(output.stderr.is_empty(), "{output:?}");
        }
        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn retained_native_intrinsics_execute_inside_generic_bodies() {
    common::run_with_timeout("retained native intrinsics", || {
        let directory = std::env::temp_dir().join(format!(
            "lanius-retained-native-intrinsics-{}",
            std::process::id()
        ));
        std::fs::create_dir_all(&directory).unwrap();
        let lib = directory.join("lib.lani");
        let app = directory.join("app.lani");
        std::fs::write(
            &lib,
            r#"module intrinsic::lib;
pub fn inspect<T>(values:[T], text:str)->usize {
    assert(string_len(text) == 5);
    assert(string_data_ptr(text) != 0);
    assert(i32_slice_data_ptr(values) != 0);
    assert(slice_stride(values) != 0);
    return slice_len(values);
}
pub fn native_view<T>(values:[T;3])->usize {
    let data:ptr = i32_array_data_ptr(values);
    let view:[T] = slice_from_storage(data,3);
    assert(slice_len(view) == 3);
    assert(slice_stride(view) != 0);
    return slice_len(values);
}
pub fn math<T>(tag:T, value:f64)->f64 {
    print(42);
    let bits:u64 = f64_to_bits(value);
    let single:f32 = 1.25;
    assert(f32_from_bits(f32_to_bits(single)) == single);
    return f64_from_bits(bits);
}
pub fn storage<T>(tag:T)->i32 {
    let values:[i32;3] = [10,20,30];
    let data:ptr = i32_array_data_ptr(values);
    let view:[i32] = slice_from_storage(data,3);
    return view[2];
}
pub fn empty<T>()->usize {
    let view:[T] = slice_from_raw_parts(0,0);
    return slice_len(view);
}
pub fn trap<T>(tag:T) { assert(false); }
"#,
        )
        .unwrap();
        let success = r#"module app::main;
import intrinsic::lib;
struct Pair { first:i32, second:f64 }
fn main()->i32 {
    let ints:[i32;3] = [1,2,3];
    let pairs:[Pair;3] = [Pair{first:1,second:1.0}, Pair{first:2,second:2.0}, Pair{first:3,second:3.0}];
    if (inspect<i32>(ints,"hello") != 3) { return 1; }
    if (inspect<Pair>(pairs,"hello") != 3) { return 2; }
    if (native_view<i32>(ints) != 3) { return 3; }
    if (native_view<Pair>(pairs) != 3) { return 4; }
    if (math<bool>(true,4.5) != 4.5) { return 5; }
    if (math<i32>(7,-2.25) != -2.25) { return 6; }
    if (storage<bool>(true) != 30) { return 7; }
    if (empty<Pair>() != 0) { return 8; }
    return 42;
}
"#;
        let compiler = pollster::block_on(GpuCompiler::new()).unwrap();
        let mut build = RetainedNativeBuild::new(DiscoveryCapacity::tiny()).unwrap();
        build.options.batch_rows = 8;
        for (source, code, stdout) in [
            (success, 42, "42\n42\n"),
            (
                "module app::main; import intrinsic::lib; fn main()->i32 { trap<u8>(1); return 0; }",
                101,
                "",
            ),
        ] {
            std::fs::write(&app, source).unwrap();
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
            let before = fallback_counters();
            let elf = pollster::block_on(
                compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
            )
            .unwrap_or_else(|e| panic!("intrinsics: {e:?}"));
            assert_eq!(fallback_counters().1, before.1);
            let output =
                common::run_x86_64_elf_output("retained intrinsics", "retained_intrinsics", &elf);
            if code == 101 {
                // The assert intrinsic traps with UD2; bounds failures have
                // a separate exit-101 runtime path.
                #[cfg(unix)]
                {
                    use std::os::unix::process::ExitStatusExt;
                    assert_eq!(output.status.signal(), Some(4), "{output:?}");
                }
                assert_eq!(output.stderr, b"lanius: assertion failed\n");
            } else {
                assert_eq!(output.status.code(), Some(code), "{output:?}");
                assert!(output.stderr.is_empty(), "{output:?}");
            }
            assert_eq!(output.stdout, stdout.as_bytes());
        }
        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn retained_native_for_loops_keep_binding_types_and_control_flow() {
    common::run_with_timeout("retained native for", || {
        let directory =
            std::env::temp_dir().join(format!("lanius-retained-native-for-{}", std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let lib = directory.join("lib.lani");
        let app = directory.join("app.lani");
        std::fs::write(
            &lib,
            r#"module loops::lib;
pub fn sum<T>(values:[T;3])->T {
    let total:T = values[0];
    for value in values { total += value; }
    return total;
}
pub fn last<T>(values:[T], fallback:T)->T {
    let result:T = fallback;
    for value in values { result = value; }
    return result;
}
fn keep<T>(value:T)->T { return value; }
pub fn ranges<T>(tag:T, end:i32)->i32 {
    let total:i32 = 0;
    for value in 0..end {
        if (value == 2) { continue; }
        if (value == 5) { break; }
        total += keep(value);
    }
    for value in ..=2 { total += value; }
    for value in 7.. {
        total += value;
        if (value == 8) { break; }
    }
    for outer in 0..2 {
        for inner in 0..3 { total += 1; }
    }
    return total;
}
pub fn maximum<T>(tag:T)->i32 {
    let last:i32=2147483647;
    let count:i32=0;
    for value in 2147483646 ..= last { count += 1; }
    return count;
}
"#,
        )
        .unwrap();
        std::fs::write(
            &app,
            r#"module app::main;
import loops::lib;
struct Pair { x:i32, y:f64 }
fn main()->i32 {
    let ints:[i32;3]=[1,2,3];
    let floats:[f64;3]=[1.25,2.5,3.75];
    if (sum<i32>(ints) != 7) { return 1; }
    if (sum<f64>(floats) != 8.75) { return 2; }
    let a:Pair=Pair{x:5,y:1.25};
    let b:Pair=Pair{x:9,y:4.5};
    let pairs:[Pair;2]=[a,b];
    let found:Pair=last<Pair>(pairs,a);
    if (found.x != 9 || found.y != 4.5) { return 3; }
    let empty:[Pair;0]=[];
    let fallback:Pair=last<Pair>(empty,a);
    if (fallback.x != 5 || fallback.y != 1.25) { return 4; }
    if (ranges<bool>(true,6) != 32) { return 5; }
    if (ranges<i32>(7,6) != 32) { return 6; }
    if (maximum<u8>(1) != 2) { return 7; }
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
        for rows in [8, 4096] {
            build.options.batch_rows = rows;
            let before = fallback_counters();
            let elf = pollster::block_on(
                compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
            )
            .unwrap();
            assert_eq!(fallback_counters().1, before.1);
            let output = common::run_x86_64_elf_output("retained for", "retained_for", &elf);
            assert_eq!(output.status.code(), Some(42), "{output:?}");
        }
        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn retained_native_bounded_direct_calls_consume_gpu_proofs() {
    common::run_with_timeout("retained bounded direct calls", || {
        let directory = std::env::temp_dir().join(format!("lanius-retained-bounds-{}", std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let lib = directory.join("lib.lani");
        let app = directory.join("app.lani");
        std::fs::write(&lib, r#"module bounds::lib;
pub trait Mark { pub fn mark(&self)->i32; }
pub fn keep<T: Mark>(value:T)->T { return value; }
pub fn middle<T: Mark>(value:T)->T { return keep<T>(value); }
pub fn outer<T: Mark>(value:T)->T { return middle<T>(value); }
"#).unwrap();
        std::fs::write(&app, r#"module app::main;
import bounds::lib;
struct Local { value:i32 }
struct Wrap<T> { value:T }
pub impl Mark for Local { pub fn mark(&self)->i32 { return 1; } }
pub impl Mark for i32 { pub fn mark(&self)->i32 { return 2; } }
pub impl<T: Mark> Mark for Wrap<T> { pub fn mark(&self)->i32 { return 3; } }
fn main()->i32 {
    let a:Local=outer<Local>(Local{value:11});
    let b:Wrap<Local> = outer<Wrap<Local>>(Wrap{value:Local{value:13}});
    let c:i32=outer<i32>(18);
    return a.value+b.value.value+c;
}
"#).unwrap();
        let manifest = ExplicitSourcePackPathManifest::from_libraries(vec![
            ExplicitSourceLibraryPaths { library_id:1, paths:vec![lib], dependency_library_ids:vec![] },
            ExplicitSourceLibraryPaths { library_id:2, paths:vec![app], dependency_library_ids:vec![1] },
        ]).unwrap();
        let compiler = pollster::block_on(GpuCompiler::new()).unwrap();
        let mut build=RetainedNativeBuild::new(DiscoveryCapacity::tiny()).unwrap();
        for batch_rows in [8,4096] {
            build.options.batch_rows=batch_rows;
            let before=fallback_counters();
            let elf=pollster::block_on(compiler.compile_path_manifest_to_x86_64_retained(&manifest,&mut build)).unwrap();
            assert_eq!(fallback_counters().1,before.1);
            assert_eq!(build.report.discovery.instances,9);
            assert_eq!(build.report.catalog.as_ref().unwrap().publication_status,Some([1,0,u32::MAX]));
            let output=common::run_x86_64_elf_output("retained bounds","retained_bounds",&elf);
            assert_eq!(output.status.code(),Some(42),"{output:?}");
        }
        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn retained_native_compound_generic_fields_have_exact_layouts() {
    common::run_with_timeout("retained compound fields", || {
        let directory=std::env::temp_dir().join(format!("lanius-retained-fields-{}",std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let lib=directory.join("lib.lani"); let app=directory.join("app.lani");
        std::fs::write(&lib,r#"module fields::lib;
pub struct Inner<T> { items:[T;2] }
pub struct Outer<T> { nested:Inner<[T;2]>, tail:T }
pub struct View<T> { items:[T] }
pub struct Counted<T,const N:usize> { items:[T;N], tail:T }
pub fn wrap<T>(values:[[T;2];2], tail:T)->Outer<T> {
    return Outer { nested:Inner{items:values}, tail:tail };
}
fn pick<T>(value:Outer<T>)->T { return value.nested.items[1][0]; }
pub fn round<T>(values:[[T;2];2], tail:T)->T { return pick<T>(wrap<T>(values,tail)); }
pub fn view<T>(values:[T])->View<T> { return View{items:values}; }
pub fn first<T>(value:View<T>)->T { return value.items[0]; }
pub fn counted<T,const N:usize>(value:Counted<T,N>)->T { return value.items[N-1]; }
"#).unwrap();
        std::fs::write(&app,r#"module app::main;
import fields::lib;
struct Pair { x:i32, y:f64 }
fn main()->i32 {
    let ints:[[i32;2];2]=[[1,2],[11,4]];
    let floats:[[f64;2];2]=[[1.5,2.5],[4.25,5.5]];
    if (round<i32>(ints,0) != 11) { return 1; }
    if (round<f64>(floats,0.0) != 4.25) { return 2; }
    let a:Pair=Pair{x:3,y:1.5}; let b:Pair=Pair{x:7,y:2.5};
    let pairs:[[Pair;2];2]=[[a,a],[b,a]];
    let chosen:Pair=round<Pair>(pairs,a);
    if (chosen.x != 7 || chosen.y != 2.5) { return 3; }
    let values:[Pair;2]=[b,a];
    let v:View<Pair> = view<Pair>(values);
    let chosen2:Pair=first<Pair>(v);
    if (chosen2.x != 7 || chosen2.y != 2.5) { return 4; }
    let c:Counted<i32,3> = Counted{items:[5,6,9],tail:1};
    if (counted<i32,3>(c) != 9) { return 5; }
    return 42;
}
"#).unwrap();
        let manifest=ExplicitSourcePackPathManifest::from_libraries(vec![
            ExplicitSourceLibraryPaths{library_id:1,paths:vec![lib],dependency_library_ids:vec![]},
            ExplicitSourceLibraryPaths{library_id:2,paths:vec![app],dependency_library_ids:vec![1]},
        ]).unwrap();
        let compiler=pollster::block_on(GpuCompiler::new()).unwrap();
        let mut build=RetainedNativeBuild::new(DiscoveryCapacity::tiny()).unwrap();
        for batch_rows in [8,4096] {
            build.options.batch_rows=batch_rows;
            let before=fallback_counters();
            let elf=pollster::block_on(compiler.compile_path_manifest_to_x86_64_retained(&manifest,&mut build)).unwrap();
            assert_eq!(fallback_counters().1,before.1);
            assert!(build.report.projection.schema.requests>0);
            let output=common::run_x86_64_elf_output("retained fields","retained_fields",&elf);
            assert_eq!(output.status.code(),Some(42),"{output:?}");
        }
        std::fs::remove_dir_all(directory).ok();
    });
}
