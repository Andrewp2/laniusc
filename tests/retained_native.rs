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
        frontend_check_count,
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
        let before = frontend_check_count();
        let elf = pollster::block_on(
            compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
        )
        .unwrap_or_else(|error| panic!("retained build {run}: {error:?}"));
        let after = frontend_check_count();
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
            after - before,
            report.units as u64 + retries,
            "one frontend recording per unit plus observed retries: {retries_before:?} -> {retries_after:?}"
        );

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
    let output = directory.join("program");
    let bytes = pollster::block_on(compiler.compile_path_manifest_to_x86_64_retained_to_file(
        &manifest, &mut build, &output,
    )).expect("file-backed GPU link");

    assert_eq!(build.report.spilled_objects, build.report.units + build.report.instance_objects);
    assert_eq!(std::fs::metadata(&output).unwrap().len(), bytes);
    let result = common::process_output_with_timeout("retained file output",
        &mut std::process::Command::new(&output), std::time::Duration::from_secs(2));
    assert_eq!(result.status.code(), Some(13), "{result:?}");
    let previous = std::fs::read(&output).unwrap();
    build.test_caller_arg_fault = Some(2);
    let error = pollster::block_on(compiler.compile_path_manifest_to_x86_64_retained_to_file(
        &manifest, &mut build, &output,
    )).expect_err("reject before publishing a new file");
    assert!(format!("{error:?}").contains("root call ABI"));
    assert_eq!(std::fs::read(&output).unwrap(), previous);
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
            let before = frontend_check_count();
            let elf = pollster::block_on(
                compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
            )
            .unwrap();
            let after = frontend_check_count();
            let retries_after = compiler.frontend_retry_counts();
            let retries: u64 = retries_after
                .iter()
                .zip(retries_before)
                .map(|(a, b)| a - b)
                .sum();
            assert_eq!(
                after - before,
                1 + retries,
                "only the original unit and observed retries: {retries_before:?} -> {retries_after:?}"
            );

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
        let error = pollster::block_on(
            compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
        )
        .expect_err("uncalled overlapping impls must fail coherence");
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0017", "{error:?}");
        assert!(diagnostic.notes.iter().any(|note|
            note.contains("program catalog GPU admission/coherence failed: [5, 0,")), "{error:?}");
        assert_eq!(build.store().job_reports().len(), 3);

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
        let elf = pollster::block_on(
            compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
        )
        .unwrap();

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
        let compiled = pollster::block_on(
            compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
        );
        let elf = compiled.unwrap();

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
            let elf = pollster::block_on(
                compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
            )
            .unwrap_or_else(|e| panic!("strings ({length}): {e:?}"));

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
            let elf = pollster::block_on(
                compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
            )
            .unwrap_or_else(|e| panic!("intrinsics: {e:?}"));

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
            let elf = pollster::block_on(
                compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build),
            )
            .unwrap();

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
            let elf=pollster::block_on(compiler.compile_path_manifest_to_x86_64_retained(&manifest,&mut build)).unwrap();

            assert_eq!(build.report.discovery.instances,9);
            assert!(build.report.discovery.closed_trait_waves >= 3);
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
pub struct Empty {}
pub struct Zero<T> { items:[T;0] }
pub struct WithZero<T> { empty:T, value:i32 }
const ANSWER:i32=42;
pub fn size<T>()->isize {
    let view:[T]=slice_from_raw_parts(0,0); let stride:isize=slice_stride(view);
    if (stride<0) { return 0-stride; }
    return stride;
}
pub fn tail<T>(empty:T)->i32 { let v:WithZero<T> = WithZero{empty:empty,value:ANSWER}; return v.value; }
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
    let empty:Empty=Empty{};
    let zero:Zero<Pair> = Zero{items:[]};
    if (size<Empty>()!=0) { return 6; }
    if (size<Zero<Pair>>()!=0) { return 8; }
    if (size<WithZero<Empty>>()!=8) { return 9; }
    let again:Empty=round<Empty>([[empty,empty],[empty,empty]],empty);
    if (tail<Empty>(again)!=42 || tail<Zero<Pair>>(zero)!=42) { return 7; }
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
            let elf=pollster::block_on(compiler.compile_path_manifest_to_x86_64_retained(&manifest,&mut build)).unwrap();

            assert!(build.report.projection.schema.requests>0);
            let output=common::run_x86_64_elf_output("retained fields","retained_fields",&elf);
            assert_eq!(output.status.code(),Some(42),"{output:?}");
        }
        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn retained_native_enum_constructors_keep_payload_layouts() {
    common::run_with_timeout("retained enum constructors", || {
        let directory=std::env::temp_dir().join(format!("lanius-retained-enums-{}",std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let lib=directory.join("lib.lani"); let app=directory.join("app.lani");
        std::fs::write(&lib,r#"module enums::lib;
pub enum Choice<T> { Empty, One(T), Two(T,i32), Array([T;2]) }
pub fn one<T>(value:T)->Choice<T> { return One(value); }
pub fn two<T>(value:T, tail:i32)->Choice<T> { return Choice::Two(value,tail); }
pub fn array<T>(values:[T;2])->Choice<T> { return Array(values); }
pub fn empty<T>()->Choice<T> { return Empty; }
"#).unwrap();
        std::fs::write(&app,r#"module app::main;
import enums::lib;
struct Pair { x:i32, y:f64 }
fn main()->i32 {
    let a:Choice<i32> = one<i32>(11);
    if ((match (a) { One(v) -> v, _ -> 0 }) != 11) { return 1; }
    let b:Choice<f64> = two<f64>(2.5,9);
    if ((match (b) { Two(v,_) -> v, _ -> 0.0 }) != 2.5) { return 2; }
    if ((match (b) { Two(_,v) -> v, _ -> 0 }) != 9) { return 3; }
    let p:Pair=Pair{x:13,y:4.25};
    let c:Choice<Pair> = one<Pair>(p);
    let q:Pair=match (c) { One(v) -> v, _ -> Pair{x:0,y:0.0} };
    if (q.x != 13 || q.y != 4.25) { return 4; }
    let d:Choice<Pair> = array<Pair>([p,p]);
    let qs:[Pair;2]=match (d) { Array(v) -> v, _ -> [p,p] };
    if (qs[1].x != 13 || qs[0].y != 4.25) { return 5; }
    let e:Choice<Pair> = empty<Pair>();
    if (!(match (e) { Empty -> true, _ -> false })) { return 6; }
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
            let elf=pollster::block_on(compiler.compile_path_manifest_to_x86_64_retained(&manifest,&mut build)).unwrap();

            let output=common::run_x86_64_elf_output("retained enums","retained_enums",&elf);
            assert_eq!(output.status.code(),Some(42),"{output:?}");
        }
        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn retained_native_matches_realize_nested_payloads() {
    common::run_with_timeout("retained nested matches", || {
        let directory=std::env::temp_dir().join(format!("lanius-retained-matches-{}",std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let lib=directory.join("lib.lani"); let app=directory.join("app.lani");
        std::fs::write(&lib,r#"module matches::lib;
pub enum Choice<T> { Empty, One(T), Two(i32,T) }
pub enum Nest<T> { Nested(Choice<T>,bool), Absent }
pub fn extract<T>(value:Choice<T>, fallback:T)->T {
    return match (value) { One(v) -> v, Two(_,v) -> v, _ -> fallback };
}
pub fn nested<T>(value:Nest<T>, fallback:T)->T {
    return match (value) {
        Nested(Two(7,v),true) -> v,
        Nested(One(v),_) -> v,
        _ -> fallback
    };
}
pub fn borrowed<T>(value:&Choice<T>, fallback:T)->T {
    return match (value) { One(v) -> v, _ -> fallback };
}
pub fn scalar<T>(tag:T,value:i32)->i32 { return match (value) { 1 -> 11, 2 -> 22, _ -> 33 }; }
pub fn create<T>(v:T)->Nest<T> { return Nested(Two(7,v),true); }
"#).unwrap();
        std::fs::write(&app,r#"module app::main;
import matches::lib;
struct Pair { x:i32, y:f64 }
impl Choice<Pair> { fn borrow(&self)->&Choice<Pair> { return self; } }
fn main()->i32 {
    if (extract<i32>(One(11),0) != 11) { return 1; }
    if (extract<f64>(Two(2,3.25),0.0) != 3.25) { return 2; }
    if (extract<i32>(Empty,9) != 9) { return 3; }
    let p:Pair=Pair{x:17,y:4.5}; let z:Pair=Pair{x:0,y:0.0};
    let v:Nest<Pair> = create<Pair>(p);
    let q:Pair=nested<Pair>(v,z);
    if (q.x != 17 || q.y != 4.5) { return 4; }
    let other:Nest<Pair> = Nested(Two(8,p),true);
    let q2:Pair=nested<Pair>(other,z);
    if (q2.x != 0 || q2.y != 0.0) { return 5; }
    let other2:Nest<Pair> = Nested(One(p),false);
    let q3:Pair=nested<Pair>(other2,z);
    if (q3.x != 17 || q3.y != 4.5) { return 6; }
    let owned:Choice<Pair> = One(p);
    let q4:Pair=borrowed<Pair>(owned.borrow(),z);
    if (q4.x != 17 || q4.y != 4.5) { return 7; }
    if (scalar<i32>(9,1) != 11 || scalar<u8>(9,2) != 22 || scalar<i64>(9,4) != 33) { return 8; }
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
            let elf=pollster::block_on(compiler.compile_path_manifest_to_x86_64_retained(&manifest,&mut build)).unwrap();

            let output=common::run_x86_64_elf_output("retained matches","retained_matches",&elf);
            assert_eq!(output.status.code(),Some(42),"{output:?}");
        }
        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn retained_native_try_preserves_success_and_error_payloads() {
    common::run_with_timeout("retained try", || {
        let directory=std::env::temp_dir().join(format!("lanius-retained-try-{}",std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let result=directory.join("result.lani"); let option=directory.join("option.lani"); let app=directory.join("app.lani");
        std::fs::write(&result,r#"module core::result;
pub enum Result<T,E> { Ok(T), Err(E) }
pub fn echo<T,E>(value:Result<T,E>)->Result<T,E> { let v:T=value?; return Ok(v); }
pub fn number<T,E>(value:Result<T,E>)->Result<i32,E> { let v:T=echo<T,E>(value)?; return Ok(17); }
"#).unwrap();
        std::fs::write(&option,r#"module core::option;
import core::result;
pub struct Failure { code:i32 }
pub fn convert<T>(value:Result<T,i32>)->Result<T,Failure> {
    return match (value) { Ok(v) -> Ok(v), Err(e) -> Err(Failure{code:e}) };
}
pub enum Option<T> { Some(T), None }
pub fn count<T>(value:Option<T>)->Option<i32> { let v:T=value?; return Some(29); }
"#).unwrap();
        std::fs::write(&app,r#"module app::main;
import core::result;
import core::option;
struct Pair { x:i32, y:f64 }
fn main()->i32 {
    let p:Pair=Pair{x:11,y:2.5}; let z:Pair=Pair{x:0,y:0.0};
    let a:Result<Pair,i32> = echo<Pair,i32>(Ok(p));
    let q:Pair=match (a) { Ok(v) -> v, _ -> z };
    if (q.x != 11 || q.y != 2.5) { return 1; }
    let b:Result<i32,Pair> = number<i32,Pair>(Err(p));
    let e:Pair=match (b) { Err(v) -> v, _ -> z };
    if (e.x != 11 || e.y != 2.5) { return 2; }
    let c:Result<i32,Pair> = number<f64,Pair>(Ok(4.25));
    if ((match (c) { Ok(v) -> v, _ -> 0 }) != 17) { return 3; }
    let d:Result<i32,str> = number<Pair,str>(Err("held"));
    let text:str=match (d) { Err(v) -> v, _ -> "" };
    if (string_len(text) != 4) { return 4; }
    let present:Option<i32> = count<Pair>(Some(p));
    let missing:Option<i32> = count<f64>(None);
    if ((match (present) { Some(v) -> v, _ -> 0 }) != 29) { return 5; }
    if (!(match (missing) { None -> true, _ -> false })) { return 6; }
    let converted:Result<Pair,Failure> = convert<Pair>(Ok(p));
    let kept:Pair=match(converted) { Ok(v) -> v, _ -> z };
    if (kept.x!=11 || kept.y!=2.5) { return 7; }
    let rejected:Result<f64,Failure> = convert<f64>(Err(31));
    if ((match(rejected) { Err(e) -> e.code, _ -> 0 })!=31) { return 8; }
    return 42;
}
"#).unwrap();
        let manifest=ExplicitSourcePackPathManifest::from_libraries(vec![
            ExplicitSourceLibraryPaths{library_id:1,paths:vec![result],dependency_library_ids:vec![]},
            ExplicitSourceLibraryPaths{library_id:2,paths:vec![option],dependency_library_ids:vec![1]},
            ExplicitSourceLibraryPaths{library_id:3,paths:vec![app],dependency_library_ids:vec![1,2]},
        ]).unwrap();
        let compiler=pollster::block_on(GpuCompiler::new()).unwrap();
        let mut build=RetainedNativeBuild::new(DiscoveryCapacity::tiny()).unwrap();
        for batch_rows in [8,4096] {
            build.options.batch_rows=batch_rows;
            let elf=pollster::block_on(compiler.compile_path_manifest_to_x86_64_retained(&manifest,&mut build)).unwrap();

            let output=common::run_x86_64_elf_output("retained try","retained_try",&elf);
            assert_eq!(output.status.code(),Some(42),"{output:?}");
        }
        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn retained_native_methods_preserve_receivers_and_inherited_binders() {
    common::run_with_timeout("retained methods", || {
        let directory=std::env::temp_dir().join(format!("lanius-retained-methods-{}",std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let lib=directory.join("lib.lani"); let app=directory.join("app.lani");
        std::fs::write(&lib,r#"module lib::methods;
pub struct Cell<T> { value:T }
pub impl<T> Cell<T> {
    pub fn get(&self)->T { return self.value; }
    pub fn put(&self,value:T) { self.value=value; }
    pub fn take(self)->T { return self.value; }
    pub fn borrow(&self)->&Cell<T> { return self; }
    pub fn choose<U>(&self,other:U)->U { let kept:T=self.get(); return other; }
    pub fn shadow<T>(&self,other:T)->T { let kept=self.value; return other; }
}
pub fn fetch<T>(cell:&Cell<T>)->T { return cell.get(); }
pub fn change<T>(cell:&Cell<T>,value:T)->T { cell.put(value); return fetch<T>(cell); }
pub fn consume<T>(cell:Cell<T>)->T { return cell.take(); }
pub fn choose<T,U>(cell:Cell<T>,other:U)->U { return cell.choose<U>(other); }
"#).unwrap();
        std::fs::write(&app,r#"module app::main;
import lib::methods;
struct Pair { x:i32,y:f64 }
fn main()->i32 {
    let a:Cell<i32> = Cell{value:7};
    if (a.get()!=7 || change<i32>(a.borrow(),11)!=11 || a.get()!=11) { return 1; }
    let p:Pair=Pair{x:17,y:2.5}; let q:Pair=Pair{x:19,y:4.5};
    let b:Cell<Pair> = Cell{value:p};
    let r:Pair=change<Pair>(b.borrow(),q);
    if (r.x!=19 || r.y!=4.5 || b.get().x!=19) { return 2; }
    let v:Pair=consume<Pair>(b);
    if (v.x!=19 || v.y!=4.5) { return 3; }
    let z:Pair=choose<i32,Pair>(a,p);
    if (z.x!=17 || z.y!=2.5 || b.choose<i32>(23)!=23 || !a.shadow<bool>(true)) { return 4; }
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
            let elf=pollster::block_on(compiler.compile_path_manifest_to_x86_64_retained(&manifest,&mut build)).unwrap();

            let output=common::run_x86_64_elf_output("retained methods","retained_methods",&elf);
            assert_eq!(output.status.code(),Some(42),"{output:?}");
        }
        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn retained_native_bound_members_use_concrete_solver_routes() {
    common::run_with_timeout("retained bound method routes", || {
        let directory=std::env::temp_dir().join(format!("lanius-retained-bound-methods-{}",std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let lib=directory.join("lib.lani"); let app=directory.join("app.lani");
        std::fs::write(&lib,r#"module bound_methods::lib;
pub trait Mark { pub fn mark(&self)->i32; }
pub trait Mapper<A,B> { pub fn apply(&self,value:A)->B; }
pub trait Consume { pub fn consume(self)->i32; }
pub trait StaticCompare<A> { pub fn same(left:A,right:A)->bool; }
pub fn same<C,A>(left:A,right:A)->bool where C:StaticCompare<A> { return C::same(left,right); }
pub fn transform<F,A,B>(f:F,value:A)->B where F:Mapper<A,B> { return f.apply(value); }
pub fn consumed<T:Consume>(value:T)->i32 { return value.consume(); }
pub fn score<T:Mark>(value:T)->i32 { return value.mark(); }
pub fn forward<T:Mark>(value:T)->i32 { return score<T>(value); }
"#).unwrap();
        std::fs::write(&app,r#"module app::main;
import bound_methods::lib;
struct Local { value:i32 }
struct Wrap<T> { value:T }
struct Pair { first:i32, second:f64 }
pub impl Mapper<i32,Pair> for Local { pub fn apply(&self,value:i32)->Pair { return Pair{first:value+self.value,second:2.5}; } }
pub impl<T> Mapper<T,T> for Wrap<T> { pub fn apply(&self,value:T)->T { return value; } }
pub impl Consume for Local { pub fn consume(self)->i32 { return self.value; } }
pub impl StaticCompare<i32> for Local { pub fn same(left:i32,right:i32)->bool { return left+right==7; } }
pub impl<T> StaticCompare<T> for Wrap<T> { pub fn same(left:T,right:T)->bool { return false; } }
pub impl Mark for Local { pub fn mark(&self)->i32 { return self.value; } }
pub impl Mark for i32 { pub fn mark(&self)->i32 { return 15; } }
pub impl<T:Mark> Mark for Wrap<T> { pub fn mark(&self)->i32 { return self.value.mark()+3; } }
fn wrapped<T:Mark>(value:Wrap<T>)->i32 { return score<Wrap<T>>(value); }
fn main()->i32 {
    let p:Pair=transform<Local,i32,Pair>(Local{value:3},4);
    let n:i64=transform<Wrap<i64>,i64,i64>(Wrap{value:9},4294967298);
    if (p.first!=7 || p.second!=2.5 || n!=4294967298) { return 1; }
    if (consumed<Local>(Local{value:8})!=8) { return 2; }
    if (!same<Local,i32>(3,4) || same<Wrap<f64>,f64>(4.0,8.0)) { return 3; }
    let a=forward<Local>(Local{value:11});
    let b=wrapped<Local>(Wrap{value:Local{value:13}});
    let c=forward<i32>(7);
    return a+b+c;
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
            let elf=pollster::block_on(compiler.compile_path_manifest_to_x86_64_retained(&manifest,&mut build)).unwrap();

            assert!(build.report.discovery.method_route_waves>=2);
            let result=common::run_x86_64_elf_output("retained bound methods","retained_bound_methods",&elf);
            assert_eq!(result.status.code(),Some(42),"{result:?}");
        }
        std::fs::remove_dir_all(directory).ok();
    });
}


#[test]
fn retained_native_generic_bodies_call_private_c_declarations() {
    common::run_with_timeout("retained native C", || {
        let directory=std::env::temp_dir().join(format!("lanius-retained-native-c-{}",std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let lib=directory.join("lib.lani"); let app=directory.join("app.lani");
        std::fs::write(&lib,r#"module native_c::lib;
extern "C" fn abs(value:i32)->i32;
extern "C" fn labs(value:i64)->i64;
extern "C" fn fabs(value:f64)->f64;
pub fn through_c<T>(value:T)->i32 {
    let kept:T=value;
    if (labs(-4294967298)!=4294967298 || fabs(-2.5)!=2.5) { return 1; }
    return abs(-21);
}


"#).unwrap();
        std::fs::write(&app,r#"module app::main;
import native_c::lib;
fn main()->i32 { return through_c<i64>(4294967298)+through_c<f64>(2.5); }
"#).unwrap();
        let manifest=ExplicitSourcePackPathManifest::from_libraries(vec![
            ExplicitSourceLibraryPaths{library_id:1,paths:vec![lib],dependency_library_ids:vec![]},
            ExplicitSourceLibraryPaths{library_id:2,paths:vec![app],dependency_library_ids:vec![1]},
        ]).unwrap();
        let compiler=pollster::block_on(GpuCompiler::new()).unwrap();
        let mut build=RetainedNativeBuild::new(DiscoveryCapacity::tiny()).unwrap();
        build.native_link=Some(laniusc_compiler::compiler::NativeLinkOptions {
            libraries:vec!["m".into()], ..Default::default()
        });
        for batch_rows in [8,4096] {
            build.options.batch_rows=batch_rows;
            let elf=pollster::block_on(compiler.compile_path_manifest_to_x86_64_retained(&manifest,&mut build)).unwrap();

            let result=common::run_x86_64_elf_output("retained C","retained_c",&elf);
            assert_eq!(result.status.code(),Some(42),"{result:?}");
        }
        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn retained_native_host_calls_keep_local_and_imported_service_ids() {
    common::run_with_timeout("retained host services", || {
        let directory=std::env::temp_dir().join(format!("lanius-retained-host-{}",std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let lib=directory.join("lib.lani"); let app=directory.join("app.lani");
        std::fs::write(&lib,r#"module host::lib;
pub extern "lanius_alloc" fn alloc(size:usize,align:usize)->ptr;
pub extern "lanius_alloc" fn dealloc(memory:ptr,size:usize,align:usize);
pub extern "lanius_std" fn write_text(handle:i32,text:str)->i32;
pub fn local<T>(value:T)->T {
    let memory:ptr=alloc(64,8);
    let values:[T]=slice_from_raw_parts(memory+56,1);
    values[0]=value; let result:T=values[0];
    dealloc(memory,64,8); write_text(1,"local\n"); return result;
}
"#).unwrap();
        std::fs::write(&app,r#"module app::main;
import host::lib;
fn remote<T>(value:T)->T {
    let memory:ptr=alloc(64,8);
    let values:[T]=slice_from_raw_parts(memory+56,1);
    values[0]=value; let result:T=values[0];
    dealloc(memory,64,8); write_text(1,"remote\n"); return result;
}
fn main()->i32 {
    if (local<i64>(4294967298)!=4294967298 || local<f64>(4.25)!=4.25) { return 1; }
    if (remote<i64>(4294967299)!=4294967299 || remote<f64>(8.5)!=8.5) { return 2; }
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
            let elf=pollster::block_on(compiler.compile_path_manifest_to_x86_64_retained(&manifest,&mut build)).unwrap();

            let result=common::run_x86_64_elf_output("retained host services","retained_host",&elf);
            assert_eq!(result.status.code(),Some(42),"{result:?}");
            assert_eq!(result.stdout,b"local\nlocal\nremote\nremote\n");
        }
        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn retained_native_function_values_call_originals_across_batches() {
    common::run_with_timeout("retained function values", || {
        let directory = common::temp_artifact_path("retained_function_values", "sources", None);
        std::fs::create_dir_all(&directory).unwrap();
        let library = directory.join("library.lani");
        let app = directory.join("app.lani");
        std::fs::write(&library, r#"module callbacks::library;
extern "lanius_std" fn write_text(handle:i32,text:str)->i32;
fn callback(first:ptr,second:ptr,third:ptr) { write_text(1,"R"); }
fn narrow(first:u32,second:i64,third:ptr) {
    assert(first == 5 && second == 7); write_text(1,"N");
}
pub fn keep<T>(value:T)->T {
    let entry:ptr = callback;
    call_ptr(entry,0,0,0);
    let first:ptr = 0; let high:i64 = 4294967301; first += high;
    let second:ptr = 0; second += 7;
    let other:ptr = narrow;
    call_ptr(other,first,second,0);
    return value;
}
"#).unwrap();
        std::fs::write(&app, r#"module app::main;
import callbacks::library;
fn main()->i32 {
    let value:i32 = keep<i32>(42);
    if (keep<bool>(false)) { return 1; }
    return value;
}
"#).unwrap();
        let manifest = ExplicitSourcePackPathManifest::from_libraries(vec![
            ExplicitSourceLibraryPaths { library_id: 1, paths: vec![library], dependency_library_ids: vec![] },
            ExplicitSourceLibraryPaths { library_id: 2, paths: vec![app], dependency_library_ids: vec![1] },
        ]).unwrap();
        let compiler = pollster::block_on(GpuCompiler::new()).unwrap();
        let mut build = RetainedNativeBuild::new(DiscoveryCapacity::tiny()).unwrap();
        for native in [false, true] {
            build.native_link = native.then(laniusc_compiler::compiler::NativeLinkOptions::default);
            for batch_rows in [1, 65536] {
                build.options.batch_rows = batch_rows;
                let elf = pollster::block_on(compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build))
                    .unwrap_or_else(|e| panic!("function values native={native}, batch={batch_rows}: {e:?}"));

                assert_eq!(build.report.projection.instances, 2);
                assert_eq!(build.report.instance_objects, if batch_rows == 1 { 2 } else { 1 });
                let out = common::run_x86_64_elf_output("retained function values", "function_values", &elf);
                assert_eq!(out.status.code(), Some(42), "native={native}, batch={batch_rows}: {out:?}");
                assert_eq!(out.stdout, b"RNRN");
                assert!(out.stderr.is_empty(), "{out:?}");
            }
        }
        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn retained_native_variadic_calls_preserve_registers_and_stack_arguments() {
    common::run_with_timeout("retained variadic C", || {
        let directory = std::env::temp_dir().join(format!("lanius-retained-varargs-{}", std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let lib = directory.join("lib.lani");
        let app = directory.join("app.lani");
        let object = directory.join("probes.o");
        let result = common::process_output_with_timeout("variadic C probe", std::process::Command::new("cc")
            .args(["-c", "-O2", "tests/fixtures/native_c/probes.c", "-o"]).arg(&object), std::time::Duration::from_secs(20));
        common::assert_command_success("variadic C probe", &result);
        std::fs::write(&lib, r#"module varargs::lib;
pub extern "C" fn probe_variadic_doubles(count:i32, ...)->f64;
extern "C" fn probe_variadic_mix(count:u32, ...)->i64;
pub fn local<T>(v:T)->T {
    let half:f64=0.5; let one:f64=1.5; let two:f64=2.5;
    let ten:i64=10; let twenty:i64=20; let thirty:i64=30;
    let cell:[i32;1]=[1000]; let p:ptr=i32_array_data_ptr(cell);
    assert(probe_variadic_mix(0)==0);
    assert(probe_variadic_mix(12,1,half,ten,p,2,one,twenty,p,3,two,thirty,p)==3075);
    assert(probe_variadic_doubles(10,half,half,half,half,half,half,half,half,one,two)==56.5);
    return v;
}
"#).unwrap();
        std::fs::write(&app, r#"module app::main;
import varargs::lib;
fn remote<T>(v:T)->T {
    let one:f64=1.5; let two:f64=2.5;
    assert(probe_variadic_doubles(2,one,two)==6.5);
    return local(v);
}
fn main()->i32 { if (remote<bool>(false)) { return 1; } return remote<i32>(42); }
"#).unwrap();
        let manifest = ExplicitSourcePackPathManifest::from_libraries(vec![
            ExplicitSourceLibraryPaths { library_id:1, paths:vec![lib], dependency_library_ids:vec![] },
            ExplicitSourceLibraryPaths { library_id:2, paths:vec![app], dependency_library_ids:vec![1] },
        ]).unwrap();
        let compiler = pollster::block_on(GpuCompiler::new()).unwrap();
        let mut build = RetainedNativeBuild::new(DiscoveryCapacity::tiny()).unwrap();
        build.native_link = Some(laniusc_compiler::compiler::NativeLinkOptions { objects:vec![object], ..Default::default() });
        for batch_rows in [8, 4096] {
            build.options.batch_rows = batch_rows;
            let elf = pollster::block_on(compiler.compile_path_manifest_to_x86_64_retained(&manifest, &mut build)).unwrap();

            // The linked C probe contains legal tail calls between C functions,
            // outside the raw Lanius function-local jump validator's contract.
            use std::os::unix::fs::PermissionsExt;
            let executable = directory.join("varargs");
            std::fs::write(&executable, elf).unwrap();
            std::fs::set_permissions(&executable, std::fs::Permissions::from_mode(0o700)).unwrap();
            let result = common::process_output_with_timeout("retained variadic C",
                &mut std::process::Command::new(&executable), std::time::Duration::from_secs(20));
            assert_eq!(result.status.code(), Some(42), "{result:?}");
        }
        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn default_native_entry_points_monomorphize_without_replay() {
    common::run_with_timeout("default native monomorphization", || {
        let compiler = pollster::block_on(GpuCompiler::new()).unwrap();
        let source = r#"struct Wrap<A> { value:A }
impl<T> Wrap<T> { fn marker(&self)->i32 { return 1; } }
impl Wrap<[i32;2]> { fn marker(&self)->i32 { return 2; } }
fn probe<T>(v:Wrap<T>)->i32 { return v.marker(); }
fn main()->i32 {
    let a:Wrap<bool> = Wrap<bool>{value:true};
    let b:Wrap<[i32;2]> = Wrap<[i32;2]>{value:[7,9]};
    return 40+probe(a)+probe(b);
}"#;
        for run in 0..2 {
            let elf = pollster::block_on(compiler.compile_source_to_x86_64(source)).unwrap();

            let report = pollster::block_on(compiler.native_monomorphization_report()).unwrap();
            assert!(report.discovery.instances >= 2, "{report:?}");
            assert_eq!(report.units, 1);
            let result = common::run_x86_64_elf_output("default generic source", &format!("default_generic_{run}"), &elf);
            assert_eq!(result.status.code(), Some(42), "{result:?}");
        }
        let directory = std::env::temp_dir().join(format!("lanius-default-native-{}", std::process::id()));
        let manifest = manifest(&directory);
        for native in [false, true] {
            let elf = if native {
                pollster::block_on(compiler.compile_path_manifest_with_native_link(&manifest, &Default::default()))
            } else {
                pollster::block_on(compiler.compile_path_manifest_to_x86_64(&manifest))
            }.unwrap();

            let report = pollster::block_on(compiler.native_monomorphization_report()).unwrap();
            assert_eq!(report.units, 2);
            assert_eq!(report.discovery.instances, 5);
            let result = common::run_x86_64_elf_output("default generic manifest", "default_generic_manifest", &elf);
            assert_eq!(result.status.code(), Some(13), "{result:?}");
        }
        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn default_native_root_abi_grows_for_wide_calls_and_preserves_late_borrows() {
    common::run_with_timeout("wide native root ABI", || {
        let compiler = pollster::block_on(GpuCompiler::new()).unwrap();
        let params = (1..=12).map(|n| format!("p{n}:i32")).collect::<Vec<_>>().join(",");
        let args = (1..=12).map(|n| n.to_string()).collect::<Vec<_>>().join(",");
        let calls = (0..6).map(|n| format!("wide<{}>({}, {args}, a)",
            if n%2==0 {"bool"} else {"i32"}, if n%2==0 {"true"} else {"9"}))
            .collect::<Vec<_>>().join("+");
        let source = format!("fn wide<T>(tag:T,{params},tail:[i32])->i32 {{
            if (p1 != 1 || p12 != 12 || tail[0] != 13) {{ return 1; }} return 7;
        }} fn main()->i32 {{ let a:[i32;1]=[13]; return {calls}; }}");
        for _ in 0..2 {
            let elf = pollster::block_on(compiler.compile_source_to_x86_64(&source)).unwrap();

            let result = common::run_x86_64_elf_output("wide root ABI", "wide_root_abi", &elf);
            assert_eq!(result.status.code(), Some(42), "{result:?}");
        }
    });
}

#[test]
fn default_native_instance_diagnostics_keep_the_defining_source_span() {
    use laniusc_compiler::compiler::CompileError;
    common::run_with_timeout("default instance diagnostic", || {
        let directory = std::env::temp_dir().join(format!("lanius-default-diagnostic-{}", std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let lib = directory.join("lib.lani");
        let app = directory.join("app.lani");
        let source = "module lib::a; pub fn bump<T>(v:T)->T { return v+300; }";
        std::fs::write(&lib, source).unwrap();
        std::fs::write(&app, "module app::b; import lib::a; fn main()->i32 { let v:u8=bump<u8>(1); return 0; }").unwrap();
        let manifest = ExplicitSourcePackPathManifest::from_libraries(vec![
            ExplicitSourceLibraryPaths { library_id:1, paths:vec![lib.clone()], dependency_library_ids:vec![] },
            ExplicitSourceLibraryPaths { library_id:2, paths:vec![app.clone()], dependency_library_ids:vec![1] },
        ]).unwrap();
        let compiler = pollster::block_on(GpuCompiler::new()).unwrap();
        let error = pollster::block_on(compiler.compile_path_manifest_to_x86_64(&manifest)).unwrap_err();
        let CompileError::Diagnostic(diagnostic) = error else { panic!("{error:?}") };
        assert_eq!(diagnostic.code, "LNC0069", "{}", diagnostic.render());
        let label = diagnostic.primary_label.unwrap();
        assert_eq!(label.path, lib);
        assert_eq!(label.byte_start, Some(source.find("300").unwrap()));
        assert_eq!(label.byte_end, Some(source.find("300").unwrap()+3));
        std::fs::write(&app, "module app::b; import lib::a; fn main()->i32 { let v:u16=bump<u16>(1); if (v==301) { return 42; } return 1; }").unwrap();
        let manifest = ExplicitSourcePackPathManifest::from_libraries(vec![
            ExplicitSourceLibraryPaths { library_id:1, paths:vec![lib.clone()], dependency_library_ids:vec![] },
            ExplicitSourceLibraryPaths { library_id:2, paths:vec![app.clone()], dependency_library_ids:vec![1] },
        ]).unwrap();
        let elf = pollster::block_on(compiler.compile_path_manifest_to_x86_64(&manifest)).unwrap();

        let result = common::run_x86_64_elf_output("after rejected instance", "after_rejected_instance", &elf);
        assert_eq!(result.status.code(), Some(42), "{result:?}");
        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn default_wasm_monomorphizes_local_and_cross_unit_generics_without_replay() {
    common::run_with_timeout("default Wasm monomorphization", || {
        let compiler=pollster::block_on(GpuCompiler::new()).unwrap();
        let source="fn twice<T>(v:T)->T { return v+v; } fn main()->i32 { let a:i64=twice<i64>(20); return twice<i32>(1)+(a as i32); }";
        for _ in 0..2 {
            let wasm=pollster::block_on(compiler.compile_source_to_wasm(source)).unwrap();
            assert_eq!(common::run_wasm_main_return_with_node("GPU generic Wasm","gpu_generic_wasm",&wasm),42);

        }
        let directory=std::env::temp_dir().join(format!("lanius-default-wasm-{}",std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let lib=directory.join("lib.lani"); let app=directory.join("app.lani");
        std::fs::write(&lib,LIB).unwrap(); std::fs::write(&app,APP).unwrap();
        let manifest=ExplicitSourcePackPathManifest::from_libraries(vec![
            ExplicitSourceLibraryPaths{library_id:1,paths:vec![lib],dependency_library_ids:vec![]},
            ExplicitSourceLibraryPaths{library_id:2,paths:vec![app],dependency_library_ids:vec![1]},
        ]).unwrap();
        let wasm=pollster::block_on(compiler.compile_path_manifest_to_wasm(&manifest)).unwrap();
        assert_eq!(common::run_wasm_main_return_with_node("cross-unit GPU generic Wasm","cross_unit_gpu_wasm",&wasm),13);
        let report=pollster::block_on(compiler.native_monomorphization_report()).unwrap();
        assert_eq!(report.units,2); assert_eq!(report.discovery.instances,5);

        std::fs::remove_dir_all(directory).ok();
    });
}

#[test]
fn default_monomorphization_uses_the_compilers_device() {
    common::run_with_timeout("monomorphization device ownership", || {
        let gpu = laniusc_compiler::gpu::device::GpuDevice::new();
        assert_ne!(*gpu.device, *laniusc_compiler::gpu::device::global().device);
        let compiler = pollster::block_on(GpuCompiler::new_with_device(&gpu)).unwrap();
        let source = "fn twice<T>(x: T) -> T { return x + x; } fn main() -> i32 { if (twice<i64>(21) != 42) { return 1; } return twice<i32>(21); }";
        for _ in 0..2 {
            let elf = pollster::block_on(compiler.compile_source_to_x86_64(source)).unwrap();
            let run = common::run_x86_64_elf_output("custom device", "custom_device", &elf);
            assert_eq!(run.status.code(), Some(42));
        }
        let wasm = pollster::block_on(compiler.compile_source_to_wasm(source)).unwrap();
        let value = common::run_wasm_main_return_with_node("custom device Wasm", "custom_device_wasm", &wasm);
        assert_eq!(value, 42);
    });
}
