mod common;

use laniusc::compiler::{
    CompileError,
    compile_source_pack_to_x86_64_with_gpu_codegen,
    compile_source_to_x86_64_with_gpu_codegen,
    compile_source_to_x86_64_with_gpu_codegen_from_path,
};

fn assert_x86_64_elf_header(bytes: &[u8]) {
    assert!(bytes.len() >= 20, "ELF output too small: {}", bytes.len());
    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[4], 2, "ELF64 class");
    assert_eq!(bytes[5], 1, "little-endian ELF");
    assert_eq!(u16::from_le_bytes(bytes[18..20].try_into().unwrap()), 62);
}

#[cfg(all(unix, target_arch = "x86_64"))]
fn assert_x86_exit_code(context: &str, artifact_stem: &str, bytes: &[u8], expected: i32) {
    let output = common::run_x86_64_elf_output(context, artifact_stem, bytes);
    assert_eq!(output.status.code(), Some(expected));
}

fn compile_source(context: &str, source: &str) -> Vec<u8> {
    let source = source.to_owned();
    common::run_gpu_codegen_with_timeout(context, move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .unwrap_or_else(|err| panic!("{context} should compile to x86_64: {err}"))
}

fn assert_source_exit(name: &str, source: &str, expected: i32) {
    let bytes = compile_source(&format!("x86 source {name}"), source);

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        &format!("x86 source {name}"),
        &format!("x86_source_{name}"),
        &bytes,
        expected,
    );
}

#[test]
fn x86_path_reports_missing_input() {
    let missing = common::temp_artifact_path("laniusc_missing_x86", "input", Some("lani"));
    let _ = std::fs::remove_file(&missing);

    let err = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen_from_path(
        &missing,
    ))
    .expect_err("missing source path should fail before codegen");
    let message = err.to_string();

    match err {
        CompileError::GpuFrontend(_) => {}
        other => panic!("expected source read error, got {other:?}: {message}"),
    }
    assert!(
        message.contains("read") && message.contains(&missing.display().to_string()),
        "missing input error should name the unreadable path: {message}"
    );
}

#[test]
fn x86_executes_representative_scalar_programs() {
    let cases = [
        (
            "integer_arithmetic",
            "fn main() {\n    return 1 + 2 + 3;\n}\n",
            6,
        ),
        (
            "bool_branch",
            "fn main() -> bool {\n    let value: i32 = 4;\n    return value > 3;\n}\n",
            1,
        ),
        (
            "function_call",
            "fn add(x: i32, y: i32) -> i32 {\n    return x + y;\n}\nfn main() {\n    return add(7, 5);\n}\n",
            12,
        ),
        (
            "live_local_after_call",
            "fn id(x: i32) -> i32 {\n    return x;\n}\nfn main() {\n    let left: i32 = 7 + 5;\n    let right: i32 = id(3);\n    return left + right;\n}\n",
            15,
        ),
        (
            "unsigned_compare",
            "fn main() -> bool {\n    let left: u32 = 4294967295;\n    let right: u32 = 1;\n    return left > right;\n}\n",
            1,
        ),
    ];

    for (name, source, expected) in cases {
        assert_source_exit(name, source, expected);
    }
}

#[test]
fn x86_executes_stdout_program() {
    let source = "fn main() {\n    let a: i32 = 1 + 2 * 3;\n    let b: i32 = (1 + 2) * 3;\n    if (a < b) {\n        print(a);\n    }\n    print(b);\n    return 0;\n}\n";
    let bytes = compile_source("x86 stdout program", source);

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let stdout = common::run_x86_64_elf("x86 stdout program", "x86_stdout_program", &bytes);
        assert_eq!(stdout, "7\n9\n");
    }
}

#[test]
fn x86_executes_source_pack_function_call() {
    let sources = [
        "module core::math;\npub fn abs(value: i32) -> i32 {\n    if (value < 0) {\n        return -value;\n    } else {\n        return value;\n    }\n}\n",
        "module app::main;\nimport core::math;\nfn main() {\n    return core::math::abs(-7);\n}\n",
    ];
    let bytes = common::run_gpu_codegen_with_timeout("x86 source pack function call", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("source pack should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack function call",
        "x86_source_pack_call",
        &bytes,
        7,
    );
}

#[test]
fn x86_executes_stdlib_helper_from_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::is_ascii_digit(53);\n}\n",
    ];
    let bytes = common::run_gpu_codegen_with_timeout("x86 source pack stdlib helper", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("stdlib helper should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack stdlib helper",
        "x86_stdlib_helper",
        &bytes,
        1,
    );
}

#[test]
fn x86_reads_source_from_path() {
    let src_path = common::TempArtifact::new("laniusc_gpu_x86", "input", Some("lani"));
    src_path.write_str("fn main() {\n    return 0;\n}\n");

    let path = src_path.path().to_path_buf();
    let bytes = common::run_gpu_codegen_with_timeout("x86 source path", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen_from_path(&path))
    })
    .expect("source path should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code("x86 source path", "x86_source_path", &bytes, 0);
}
