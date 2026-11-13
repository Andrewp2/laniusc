#![cfg(all(target_os = "linux", target_arch = "x86_64"))]

//! The GPU linker writes a dynamically linked ELF when every native input is
//! a shared library. These tests run such executables and read their dynamic
//! sections.

use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    time::Duration,
};

use laniusc_compiler::compiler::{
    CompileError,
    EntrySourceRoots,
    NativeLinkOptions,
    compile_entry_to_x86_64_with_native_link,
};

use crate::common;

fn repository() -> &'static Path {
    Path::new(env!("CARGO_MANIFEST_DIR"))
}

fn fixture(name: &str) -> PathBuf {
    repository().join("tests/fixtures/native_c").join(name)
}

fn compile(name: &str, file: &str, libraries: &[&str]) -> Result<Vec<u8>, CompileError> {
    let entry = fixture(file);
    let roots = EntrySourceRoots {
        stdlib_root: Some(repository().join("stdlib")),
        user_roots: vec![],
    };
    let options = NativeLinkOptions {
        libraries: libraries
            .iter()
            .map(|library| library.to_string())
            .collect(),
        ..NativeLinkOptions::default()
    };
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_native_link(
            &entry, &roots, &options,
        ))
    })
}

fn tool(context: &str, program: &str, args: &[&str], path: &Path) -> String {
    let mut command = Command::new(program);
    command.args(args).arg(path);
    let output =
        common::process_output_with_timeout(context, &mut command, Duration::from_secs(20));
    common::assert_command_success(context, &output);
    String::from_utf8(output.stdout).expect("tool output is UTF-8")
}

fn executable(name: &str, file: &str, libraries: &[&str]) -> common::TempArtifact {
    let bytes = compile(name, file, libraries).unwrap_or_else(|error| panic!("{name}: {error:?}"));
    let executable = common::TempArtifact::new("laniusc_native_dynamic", name, None);
    fs::write(executable.path(), bytes).expect("write dynamic ELF");
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700))
        .expect("make dynamic ELF executable");
    let mut validate = Command::new("python3");
    validate
        .arg(fixture("validate_linked_elf.py"))
        .arg(executable.path());
    let validation = common::process_output_with_timeout(
        format!("validate dynamic ELF {name}"),
        &mut validate,
        Duration::from_secs(30),
    );
    common::assert_command_success(name, &validation);
    executable
}

fn run(name: &str, command: &mut Command) -> Output {
    command.stdin(Stdio::null());
    common::process_output_with_timeout(name, command, Duration::from_secs(5))
}

fn needed(dynamic: &str) -> Vec<String> {
    dynamic
        .lines()
        .filter(|line| line.contains("(NEEDED)"))
        .map(|line| {
            let start = line.find('[').expect("NEEDED value") + 1;
            let end = line.rfind(']').expect("NEEDED value");
            line[start..end].to_string()
        })
        .collect()
}

#[test]
fn gpu_dynamic_link_calls_libc_and_libm_and_propagates_argv_exit_and_stdio() {
    let executable = executable("libc_libm", "dynamic/libc_libm.lani", &["m"]);
    let path = executable.path();

    let header = tool("readelf header", "readelf", &["-h", "-l", "-W"], path);
    assert!(header.contains("EXEC (Executable file)"), "{header}");
    assert!(
        header.contains("[Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]"),
        "{header}"
    );
    let dynamic = tool("readelf dynamic", "readelf", &["-d", "-r", "-W"], path);
    assert_eq!(needed(&dynamic), ["libm.so.6", "libc.so.6"], "{dynamic}");
    assert!(
        dynamic.contains("(FLAGS)") && dynamic.contains("BIND_NOW"),
        "{dynamic}"
    );
    for symbol in [
        "__libc_start_main@GLIBC_2.34",
        "strlen@GLIBC_2.2.5",
        "sqrt@GLIBC_2.2.5",
    ] {
        assert!(
            dynamic
                .lines()
                .any(|line| line.contains("R_X86_64_GLOB_DAT") && line.contains(symbol)),
            "missing GLOB_DAT for {symbol}\n{dynamic}"
        );
    }
    assert!(!dynamic.contains("R_X86_64_JUMP_SLOT"), "{dynamic}");
    // A C driver adds CRT sections; the GPU writer has none.
    let sections = tool("readelf sections", "readelf", &["-S", "-W"], path);
    assert!(sections.contains(" .got "), "{sections}");
    for crt in [" .init ", " .plt ", " .fini "] {
        assert!(!sections.contains(crt), "{crt} present\n{sections}");
    }
    let libraries = tool("ldd", "ldd", &[], path);
    assert!(!libraries.contains("not found"), "{libraries}");
    assert!(libraries.contains("libm.so.6 =>"), "{libraries}");

    let output = run("libc_libm without arguments", &mut Command::new(path));
    assert_eq!(output.status.code(), Some(40), "{output:?}");
    assert_eq!(output.stdout, b"lani\n", "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");

    let output = run(
        "libc_libm with arguments",
        Command::new(path).args(["first", "seven77"]),
    );
    assert_eq!(output.status.code(), Some(40 + 30 + 7), "{output:?}");
    assert_eq!(output.stdout, b"lani\n", "{output:?}");
}

#[test]
fn gpu_dynamic_link_resolves_non_libc_libraries_by_soname() {
    let executable = executable("zlib_x11", "dynamic/zlib_x11.lani", &["X11", "z"]);
    let dynamic = tool(
        "readelf dynamic",
        "readelf",
        &["-d", "-r", "-W"],
        executable.path(),
    );
    assert_eq!(
        needed(&dynamic),
        ["libX11.so.6", "libz.so.1", "libc.so.6"],
        "{dynamic}"
    );
    for symbol in ["XInitThreads", "compressBound@ZLIB_1.2.0"] {
        assert!(
            dynamic
                .lines()
                .any(|line| line.contains("R_X86_64_GLOB_DAT") && line.contains(symbol)),
            "missing GLOB_DAT for {symbol}\n{dynamic}"
        );
    }
    let output = run("zlib_x11", &mut Command::new(executable.path()));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
}

#[test]
fn gpu_dynamic_link_reports_unresolved_symbols() {
    let error = compile("unresolved", "dynamic/unresolved.lani", &["m"])
        .expect_err("an undefined C symbol must not link");
    let text = format!("{error:?}");
    assert!(text.contains("LNC0017"), "{text}");
    assert!(
        text.contains("undefined symbol: lanius_absent_native_symbol"),
        "{text}"
    );
}
