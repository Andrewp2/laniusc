mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn concrete_option_result_methods_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for suffix in ["i8", "u8", "i16", "u16", "i32", "u32"] {
        let fixture_path = root.join(format!(
            "tests/fixtures/stdlib_foundation/option_result_{suffix}.lani"
        ));
        let fixture = std::fs::read_to_string(&fixture_path).expect("read option/result fixture");
        for module in [format!("option_{suffix}"), format!("result_{suffix}")] {
            let source = std::fs::read_to_string(root.join(format!("stdlib/core/{module}.lani")))
                .expect("read option/result module");
            assert_eq!(
                source
                    .lines()
                    .filter(|line| line.starts_with("    pub fn "))
                    .count(),
                8,
                "{module}: receiver method count changed"
            );
        }
        for (receiver, method) in [
            ("present", "is_some"),
            ("absent", "is_none"),
            ("present", "contains"),
            ("present", "unwrap_or"),
            ("present", "or"),
            ("present", "and"),
            ("present", "xor"),
            ("present", "ok_or"),
            ("success", "is_ok"),
            ("failure", "is_err"),
            ("success", "contains"),
            ("failure", "contains_err"),
            ("success", "unwrap_or"),
            ("failure", "unwrap_err_or"),
            ("success", "or"),
            ("success", "and"),
        ] {
            assert!(
                fixture.contains(&format!("{receiver}.{method}(")),
                "{suffix}: {receiver}.{method} lacks a runtime call"
            );
        }
        let stdlib_root = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("option/result methods", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(
                &fixture_path,
                &stdlib_root,
            ))
        })
        .expect("compile option/result methods");
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                "option/result methods",
                &format!("option_result_methods_{suffix}"),
                &bytes,
            );
            assert_eq!(output.status.code(), Some(0), "{suffix}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn bool_char_float_option_result_methods_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (suffix, present, absent, option_ok, success, failure) in [
        (
            "bool",
            "yes",
            "absent",
            "no_value",
            "true_ok",
            "false_error",
        ),
        ("char", "present", "absent", "zero_present", "good", "bad"),
        (
            "f32",
            "present",
            "absent",
            "zero_value",
            "success",
            "failure",
        ),
    ] {
        let entry = root.join(format!(
            "tests/fixtures/stdlib_foundation/option_result_{suffix}.lani"
        ));
        let fixture = std::fs::read_to_string(&entry).expect("read option/result fixture");
        for module in [format!("option_{suffix}"), format!("result_{suffix}")] {
            let source = std::fs::read_to_string(root.join(format!("stdlib/core/{module}.lani")))
                .expect("read option/result module");
            assert_eq!(
                source
                    .lines()
                    .filter(|line| line.starts_with("    pub fn "))
                    .count(),
                8,
                "{module}: receiver method count changed"
            );
        }
        for call in [
            format!("{present}.is_some("),
            format!("{absent}.is_none("),
            format!("{present}.contains("),
            format!("{present}.unwrap_or("),
            format!("{absent}.or("),
            format!("{present}.and("),
            format!("{present}.xor("),
            format!("{option_ok}.ok_or("),
            format!("{success}.is_ok("),
            format!("{failure}.is_err("),
            format!("{success}.contains("),
            format!("{failure}.contains_err("),
            format!("{success}.unwrap_or("),
            format!("{failure}.unwrap_err_or("),
            format!("{success}.or("),
            format!("{success}.and("),
        ] {
            assert!(
                fixture.contains(&call),
                "{suffix}: {call} lacks a runtime call"
            );
        }
        let stdlib_root = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("option/result methods", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .expect("compile option/result methods");
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                "option/result methods",
                &format!("option_result_methods_{suffix}"),
                &bytes,
            );
            assert_eq!(output.status.code(), Some(0), "{suffix}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn option_result_program_uses_methods() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/option_result_helpers.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("option/result program", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile option/result program");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "option/result program",
            "option_result_methods_program",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"38\n");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_aggregate_method_chains_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_imported_method_chain.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("imported method chains", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile imported method chains");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported method chains",
            "imported_method_chains",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn mixed_option_result_methods_select_their_imported_types() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for name in ["narrow", "scalar"] {
        let entry = root.join(format!(
            "tests/fixtures/stdlib_foundation/option_result_{name}_method_matrix.lani"
        ));
        let stdlib_root = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("mixed method matrix", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .expect("compile mixed method matrix");
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(
                "mixed method matrix",
                &format!("option_result_{name}_method_matrix"),
                &bytes,
            );
            assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}
