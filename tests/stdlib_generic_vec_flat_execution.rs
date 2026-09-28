mod common;

use laniusc_compiler::compiler::{
    compile_entry_to_x86_64_with_stdlib,
    compile_source_pack_to_x86_64_with_gpu_codegen,
};

#[test]
fn imported_generic_free_constructor_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_vec_generic_free_new_only.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("imported generic free new", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile imported generic free constructor");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported generic free new",
            "imported_generic_free_new",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "unexpected stdout: {output:?}");
        assert!(output.stderr.is_empty(), "unexpected stderr: {output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_generic_free_constructor_rejects_unrelated_result_type() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_vec_generic_free_wrong_result.lani");
    let stdlib_root = root.join("stdlib");
    let result =
        common::run_gpu_codegen_with_timeout("wrong imported generic free result", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        });
    let error = result.expect_err("Vec<T> must not match OptionI32");
    assert!(error.to_string().contains("LNC0006"), "{error}");
}

#[test]
fn imported_generic_free_arguments_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_vec_generic_free_len_only.lani");
    let stdlib_root = root.join("stdlib");
    let bytes =
        common::run_gpu_codegen_with_timeout("imported generic free arguments", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .expect("compile imported generic free len and is_empty");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported generic free arguments",
            "imported_generic_free_arguments",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "unexpected stdout: {output:?}");
        assert!(output.stderr.is_empty(), "unexpected stderr: {output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_generic_vec_free_api_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_vec_generic_free_new.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("imported generic Vec free API", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile imported generic Vec free API");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported generic Vec free API",
            "imported_generic_vec_free_api",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "unexpected stdout: {output:?}");
        assert!(output.stderr.is_empty(), "unexpected stderr: {output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_generic_free_arguments_reject_unrelated_nominal_type() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_vec_generic_free_wrong_argument.lani");
    let stdlib_root = root.join("stdlib");
    let result =
        common::run_gpu_codegen_with_timeout("wrong imported generic argument", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        });
    let error = result.expect_err("OptionI32 must not match Vec<T>");
    assert!(error.to_string().contains("LNC0006"), "{error}");
}

#[test]
fn imported_generic_free_direct_arguments_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_vec_generic_free_direct_argument.lani");
    let stdlib_root = root.join("stdlib");
    let bytes =
        common::run_gpu_codegen_with_timeout("direct imported generic arguments", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .expect("compile direct imported generic arguments");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "direct imported generic arguments",
            "direct_imported_generic_arguments",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "unexpected stdout: {output:?}");
        assert!(output.stderr.is_empty(), "unexpected stderr: {output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_generic_free_direct_arguments_reject_unrelated_type() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/repro_vec_generic_free_direct_wrong_argument.lani");
    let stdlib_root = root.join("stdlib");
    let result = common::run_gpu_codegen_with_timeout("wrong direct generic argument", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    });
    let error = result.expect_err("OptionI32 must not match Vec<T>");
    assert!(error.to_string().contains("LNC0006"), "{error}");
}

#[test]
fn imported_generic_vec_empty_operations_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_vec_generic_associated_new.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("imported generic Vec", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile imported generic Vec operations");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported generic Vec",
            "imported_generic_vec_empty",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "unexpected stdout: {output:?}");
        assert!(output.stderr.is_empty(), "unexpected stderr: {output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_generic_method_receiver_and_return_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_imported_generic_method.lani");
    let stdlib_root =
        root.join("tests/fixtures/stdlib_foundation/repro_imported_generic_method_root");
    let bytes = common::run_gpu_codegen_with_timeout("imported generic methods", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile imported generic methods");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported generic methods",
            "repro_imported_generic_method",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "unexpected stdout: {output:?}");
        assert!(output.stderr.is_empty(), "unexpected stderr: {output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_generic_method_does_not_substitute_an_unrelated_return() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_imported_generic_wrong_return.lani");
    let stdlib_root =
        root.join("tests/fixtures/stdlib_foundation/repro_imported_generic_method_root");
    let result = common::run_gpu_codegen_with_timeout("wrong generic method return", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    });
    let error = result.expect_err("Other<i32> must not be accepted as Bucket<i32>");
    assert!(error.to_string().contains("LNC0006"), "{error}");
}

#[test]
fn generic_vec_empty_from_flat_source_pack_executes() {
    let sources = [
        include_str!("../stdlib/std/vec.lani"),
        include_str!("fixtures/stdlib_foundation/repro_vec_generic_associated_new.lani"),
    ];
    let bytes = common::run_gpu_codegen_with_timeout("generic vec empty", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("compile generic vec empty");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("generic vec empty", "generic_vec_empty", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn generic_vec_free_new_from_flat_source_pack_executes() {
    let sources = [
        include_str!("../stdlib/std/vec.lani"),
        include_str!("fixtures/stdlib_foundation/repro_vec_generic_free_new.lani"),
    ];
    let bytes = common::run_gpu_codegen_with_timeout("generic vec free", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("compile generic vec free new");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("generic vec free", "generic_vec_free", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn generic_vector_empty_functions_have_flat_runtime_calls() {
    let source = include_str!("../stdlib/std/vec.lani");
    let free = include_str!("fixtures/stdlib_foundation/repro_vec_generic_free_new.lani");
    let associated =
        include_str!("fixtures/stdlib_foundation/repro_vec_generic_associated_new.lani");
    for name in ["new", "len", "is_empty"] {
        assert!(source.contains(&format!("pub fn {name}")));
        assert!(free.contains(&format!("std::vec::{name}(")));
        if name == "new" {
            assert!(associated.contains("Vec<i32>::new("));
        } else {
            assert!(associated.contains(&format!("value.{name}(")));
        }
    }
}
