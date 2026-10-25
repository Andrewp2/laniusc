#![cfg(all(target_os = "linux", target_arch = "x86_64"))]

mod common;

use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Command, Output},
    time::Duration,
};

use laniusc_compiler::compiler::{
    CompileError,
    EntrySourceRoots,
    NativeLinkOptions,
    compile_entry_to_x86_64_with_native_link,
};

fn repository() -> &'static Path {
    Path::new(env!("CARGO_MANIFEST_DIR"))
}

fn fixture(name: &str) -> PathBuf {
    repository().join("tests/fixtures/native_c").join(name)
}

fn compile_probe_objects() -> Vec<common::TempArtifact> {
    ["probes.c", "probes.S"]
        .into_iter()
        .map(|name| {
            let object = common::TempArtifact::new("laniusc_native_c", name, Some("o"));
            let mut command = Command::new("cc");
            command
                .args([
                    "-c",
                    "-O2",
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                    "-fno-stack-protector",
                ])
                .arg(fixture(name))
                .arg("-o")
                .arg(object.path());
            let output = common::process_output_with_timeout(
                format!("build independent native ABI probe {name}"),
                &mut command,
                Duration::from_secs(20),
            );
            common::assert_command_success(format!("compile C ABI fixture {name}"), &output);
            object
        })
        .collect()
}

fn compile_native(
    name: &str,
    entry: &Path,
    user_roots: Vec<PathBuf>,
    objects: &[common::TempArtifact],
) -> Result<Vec<u8>, CompileError> {
    let entry = entry.to_path_buf();
    let roots = EntrySourceRoots {
        stdlib_root: Some(repository().join("stdlib")),
        user_roots,
    };
    let options = NativeLinkOptions {
        objects: objects
            .iter()
            .map(|object| object.path().to_path_buf())
            .collect(),
        ..NativeLinkOptions::default()
    };
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_native_link(
            &entry, &roots, &options,
        ))
    })
}

fn validate_linked_elf(path: &Path) -> Output {
    let mut command = Command::new("python3");
    command.arg(fixture("validate_linked_elf.py")).arg(path);
    common::process_output_with_timeout(
        format!("validate system-linked ELF {}", path.display()),
        &mut command,
        Duration::from_secs(30),
    )
}

fn executable(name: &str, entry: &Path, user_roots: Vec<PathBuf>) -> common::TempArtifact {
    let probes = compile_probe_objects();
    let bytes = compile_native(name, entry, user_roots, &probes)
        .unwrap_or_else(|error| panic!("{name}: {error:?}"));
    let executable = common::TempArtifact::new("laniusc_native_c", name, None);
    // The raw-entry checker in TempArtifact::write_bytes assumes an ELF with
    // one compiler-owned code segment. CRT/PLT code has a different branch
    // contract, so validate the linked profile and its sized Lanius symbols.
    fs::write(executable.path(), bytes).expect("write native-linked ELF");
    let validation = validate_linked_elf(executable.path());
    common::assert_command_success(name, &validation);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700))
        .expect("make linked ELF executable");
    executable
}

fn assert_clean_execution(name: &str, command: &mut Command) {
    let output = common::process_output_with_timeout(name, command, Duration::from_secs(2));
    assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
    assert!(output.stdout.is_empty(), "{name}: {output:?}");
    assert!(output.stderr.is_empty(), "{name}: {output:?}");
}

#[test]
fn native_c_scalars_full_width_pointers_null_and_void_buffer_writes_execute() {
    let executable = executable("native_c_scalars", &fixture("scalars.lani"), vec![]);
    assert_clean_execution(
        "native C scalar and memory ABI",
        &mut Command::new(executable.path()),
    );
}

#[test]
fn native_c_register_and_stack_arguments_alignment_and_live_values_execute() {
    let executable = executable("native_c_arguments", &fixture("arguments.lani"), vec![]);
    assert_clean_execution(
        "native C argument and clobber ABI",
        &mut Command::new(executable.path()),
    );
}

#[test]
fn native_c_31_and_32_mixed_arguments_and_imported_generic_replay_execute() {
    let executable = executable(
        "native_c_boundary",
        &fixture("boundary/main.lani"),
        vec![fixture("boundary")],
    );
    assert_clean_execution(
        "native C argument boundary and imported generic replay",
        &mut Command::new(executable.path()),
    );
}

#[test]
fn native_c_crt_initializers_arguments_and_environment_execute() {
    let executable = executable("native_c_startup", &fixture("startup.lani"), vec![]);
    let mut command = Command::new(executable.path());
    command
        .args(["", "native-c argument"])
        .env_clear()
        .env("LANIUS_NATIVE_C_TEST", "linked-value");
    assert_clean_execution("native CRT startup and runtime process state", &mut command);
}

#[test]
fn imported_public_c_declarations_and_runtime_name_collisions_execute() {
    let imported = executable(
        "native_c_imported",
        &fixture("imported/main.lani"),
        vec![fixture("imported")],
    );
    assert_clean_execution(
        "imported public C declaration",
        &mut Command::new(imported.path()),
    );
    let collision = executable("native_c_collision", &fixture("collisions.lani"), vec![]);
    assert_clean_execution(
        "C/runtime close and read binding identity",
        &mut Command::new(collision.path()),
    );
}

fn reject_source(name: &str, source: &str) -> CompileError {
    let entry = common::TempArtifact::new("laniusc_native_c", name, Some("lani"));
    entry.write_str(source);
    compile_native(name, entry.path(), vec![], &[])
        .expect_err("unsupported C declarations must fail before producing an executable")
}

#[test]
fn native_c_rejects_unsupported_signatures_even_when_uncalled() {
    // Each row exercises a distinct incompatible ABI category. A body that
    // never calls the declaration must not make its signature acceptable.
    let cases = [
        (
            "bool_argument",
            "extern \"C\" fn invalid(value: bool) -> i32;",
        ),
        (
            "narrow_integer_argument",
            "extern \"C\" fn invalid(value: i16) -> i32;",
        ),
        (
            "string_argument",
            "extern \"C\" fn invalid(value: str) -> i32;",
        ),
        (
            "slice_argument",
            "extern \"C\" fn invalid(value: [i32]) -> i32;",
        ),
        (
            "record_argument",
            "struct Pair { a:i32,b:i32 } extern \"C\" fn invalid(value: Pair) -> i32;",
        ),
        ("bool_return", "extern \"C\" fn invalid() -> bool;"),
    ];
    for (name, declaration) in cases {
        let source = format!("module app::main; {declaration} fn main() -> i32 {{ return 0; }}");
        let error = reject_source(name, &source);
        let diagnostic = error.to_public_diagnostic();
        assert_eq!(diagnostic.code, "LNC0006", "{name}: {diagnostic:?}");
        assert!(
            diagnostic
                .message
                .contains("unsupported native C signature"),
            "{name}: rejection must come from the C signature gate: {diagnostic:?}"
        );
    }
}

#[test]
fn native_c_rejects_unknown_abis_unresolved_symbols_and_conflicting_imported_signatures() {
    let error = reject_source(
        "unknown_abi",
        "module app::main; extern \"unrecognized_native_abi\" fn foreign_call() -> i32; fn main() -> i32 { return foreign_call(); }",
    );
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, "LNC0017", "{diagnostic:?}");
    assert!(
        diagnostic.message.contains("unsupported x86 call ABI"),
        "{diagnostic:?}"
    );
    let error = reject_source(
        "unresolved_c_symbol",
        "module app::main; extern \"C\" fn lanius_native_c_missing_symbol_73() -> i32; fn main() -> i32 { return lanius_native_c_missing_symbol_73(); }",
    );
    assert!(
        format!("{error:?}").contains("lanius_native_c_missing_symbol_73"),
        "missing native symbol must be named: {error:?}"
    );
    let error = compile_native(
        "conflicting_c_signatures",
        &fixture("conflicting/main.lani"),
        vec![fixture("conflicting")],
        &[],
    )
    .expect_err("one C symbol cannot have conflicting checked signatures");
    assert!(format!("{error:?}").contains("probe_imported"), "{error:?}");
}

#[test]
fn linked_elf_profile_checker_detects_an_unreachable_cross_function_jump() {
    // Both files run successfully. Validation must still reject the bad edge
    // in an unreachable Lanius symbol, as the raw-entry checker also does.
    for bad_branch in [false, true] {
        let executable = common::TempArtifact::new("laniusc_native_c", "validator", None);
        let mut command = Command::new("cc");
        command.args(["-no-pie", "-x", "assembler-with-cpp"]);
        if bad_branch {
            command.arg("-DBAD_BRANCH");
        }
        command
            .arg(fixture("validator.S"))
            .arg("-o")
            .arg(executable.path());
        let output = common::process_output_with_timeout(
            "build linked ELF checker signal fixture",
            &mut command,
            Duration::from_secs(20),
        );
        common::assert_command_success("build linked ELF checker fixture", &output);
        let output = validate_linked_elf(executable.path());
        assert_eq!(output.status.success(), !bad_branch, "{output:?}");
        if bad_branch {
            assert!(
                String::from_utf8_lossy(&output.stderr).contains("leaves its function"),
                "{output:?}"
            );
        }
    }
}
