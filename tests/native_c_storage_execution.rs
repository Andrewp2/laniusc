#![cfg(all(target_os = "linux", target_arch = "x86_64", target_env = "gnu"))]

mod common;

use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

use laniusc_compiler::{
    codegen::unit::{CompilationUnitLimits, DEFAULT_CODEGEN_UNIT_MAX_SOURCE_BYTES},
    compiler::{
        EntrySourceRoots,
        GpuCompiler,
        GpuCompilerBackends,
        NativeLinkOptions,
        load_entry_path_manifest_with_source_roots,
    },
};

struct SourceDirectory(PathBuf);
impl Drop for SourceDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn fixture() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/native_c_storage")
}

fn write_padded_source(destination: &Path, source: &Path) {
    let mut file = fs::File::create(destination).expect("create bounded source file");
    file.write_all(&fs::read(source).expect("read storage fixture"))
        .unwrap();
    file.write_all(b"\n/*").unwrap();
    // Each file fits a frontend unit, while their combined source pack exceeds
    // the resident path's old admission threshold. The comment adds no code.
    let block = [b'x'; 64 * 1024];
    for _ in 0..48 {
        file.write_all(&block).unwrap();
    }
    file.write_all(b"*/\n").unwrap();
}

#[test]
fn native_large_pack_spills_originals_and_generic_replays_and_writes_atomically() {
    let directory = SourceDirectory(common::temp_artifact_path(
        "laniusc_native_storage",
        "source pack 'quoted'",
        None,
    ));
    fs::create_dir_all(directory.0.join("ffi")).expect("create storage source root");
    for relative in ["main.lani", "ffi/replay.lani"] {
        write_padded_source(&directory.0.join(relative), &fixture().join(relative));
    }
    // The C driver's response grammar must preserve spaces, quotes and slashes
    // in explicitly supplied input paths.
    let probe = directory.0.join("native probe 'quoted' \\ .o");
    let mut command = Command::new("cc");
    command
        .args(["-c", "-O2", "-Wall", "-Wextra", "-Werror"])
        .arg(fixture().join("probe.c"))
        .arg("-o")
        .arg(&probe);
    let output = common::process_output_with_timeout(
        "compile native storage probe",
        &mut command,
        Duration::from_secs(20),
    );
    common::assert_command_success("native storage probe", &output);

    let roots = EntrySourceRoots {
        stdlib_root: None,
        user_roots: vec![directory.0.clone()],
    };
    let manifest =
        load_entry_path_manifest_with_source_roots(directory.0.join("main.lani"), &roots)
            .expect("load bounded native source pack");
    assert!(
        manifest.requires_bounded_compilation_with_limits(CompilationUnitLimits {
            max_source_bytes: DEFAULT_CODEGEN_UNIT_MAX_SOURCE_BYTES,
            max_source_files: 16 * 1024,
        })
    );
    assert!(
        manifest
            .files
            .iter()
            .all(|file| file.byte_len < DEFAULT_CODEGEN_UNIT_MAX_SOURCE_BYTES)
    );
    let small_root = fixture();
    let small_manifest = load_entry_path_manifest_with_source_roots(
        small_root.join("main.lani"),
        &EntrySourceRoots {
            stdlib_root: None,
            user_roots: vec![small_root],
        },
    )
    .expect("load small native source pack for output rejection");
    let executable = directory.0.join("program");
    let output_path = executable.clone();
    let options = NativeLinkOptions {
        objects: vec![probe],
        ..NativeLinkOptions::default()
    };
    let byte_len = common::run_gpu_codegen_with_timeout("bounded native storage", move || {
        pollster::block_on(async move {
            let compiler = GpuCompiler::new_with_backends(GpuCompilerBackends::x86_only()).await?;
            let byte_len = compiler
                .compile_path_manifest_with_native_link_to_file(&manifest, &options, &output_path)
                .await?;
            let original = fs::read(&output_path).expect("read completed native executable");
            let limited = NativeLinkOptions {
                max_output_bytes: 1,
                ..options
            };
            let error = compiler
                .compile_path_manifest_with_native_link_to_file(
                    &small_manifest,
                    &limited,
                    &output_path,
                )
                .await
                .expect_err("reject excessive native output");
            assert!(
                format!("{error:?}").contains("output") || format!("{error:?}").contains("size"),
                "{error:?}"
            );
            assert_eq!(
                fs::read(&output_path).unwrap(),
                original,
                "failed bounded link must preserve the previous executable"
            );
            Ok::<_, laniusc_compiler::compiler::CompileError>(byte_len)
        })
    })
    .unwrap_or_else(|error| panic!("bounded native storage: {error:?}"));
    assert_eq!(fs::metadata(&executable).unwrap().len(), byte_len);
    let output = common::process_output_with_timeout(
        "execute private C calls in spilled generic replay",
        &mut Command::new(&executable),
        Duration::from_secs(2),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}
