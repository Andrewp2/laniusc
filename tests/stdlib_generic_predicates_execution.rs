mod common;

use laniusc_compiler::compiler::{
    compile_entry_to_x86_64_with_stdlib,
    compile_source_to_x86_64_with_gpu_codegen,
};

#[test]
fn imported_option_predicates_execute_across_scalar_payloads() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    // Recompile through the same resident compiler after the larger fixture.
    // Cleared use metadata must not retain references from the previous job.
    for relative in [
        "tests/fixtures/stdlib_foundation/option_generic_scalar_predicates.lani",
        "sample_programs/boolean_window_checksum.lani",
        "tests/fixtures/stdlib_foundation/option_generic_scalar_predicates.lani",
    ] {
        let entry = root.join(relative);
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(relative, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
        })
        .expect("compile imported generic Option predicates");
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output =
                common::run_x86_64_elf_output(relative, "generic_option_predicates", &bytes);
            assert_eq!(output.status.code(), Some(0), "{relative}: {output:?}");
            let expected = if relative.starts_with("sample_programs/") {
                "3\n"
            } else {
                ""
            };
            assert_eq!(output.stdout, expected.as_bytes(), "{relative}: {output:?}");
            assert!(output.stderr.is_empty(), "{relative}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn option_predicate_bodies_execute_with_multiword_payloads() {
    // Use the actual stdlib free and method predicates in one compilation unit.
    let definitions = include_str!("../stdlib/core/option.lani")
        .split("pub fn contains_i32")
        .next()
        .unwrap()
        .replace("module core::option;", "module app::main;")
        .replace("import core::result_bool;", "");
    let entry = include_str!("fixtures/stdlib_foundation/option_generic_predicates.lani")
        .replace("module app::main;", "")
        .replace("import core::option;", "")
        .replace("core::option::", "");
    let source = format!("{definitions}\n{entry}");
    let bytes = common::run_gpu_codegen_with_timeout("multiword Option predicates", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect("compile the stdlib's generic predicates with multiword payloads");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "multiword Option predicates",
            "multiword_option_predicates",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn result_predicate_bodies_execute_with_two_generic_payloads() {
    // The complete result module still has unresolved generic payload bodies;
    // this isolates its actual two tag predicates without changing that claim.
    let definitions = include_str!("../stdlib/core/result.lani")
        .split("pub fn contains_i32")
        .next()
        .unwrap()
        .replace("module core::result;", "module app::main;");
    let source = format!(
        r#"{definitions}
struct Pair {{ first: i32, second: i32 }}
struct Quad {{ first: i32, second: i32, third: i32, fourth: i32 }}
fn main() -> i32 {{
    let success: Result<bool, bool> = Ok(false);
    let failure: Result<bool, bool> = Err(false);
    if (!is_ok(success) || is_err(success)) {{ return 1; }}
    if (is_ok(failure) || !is_err(failure)) {{ return 2; }}
    let pair: Pair = Pair {{ first: -7, second: 999 }};
    let quad: Quad = Quad {{ first: 0, second: 9, third: -7, fourth: 999 }};
    let wide_success: Result<Pair, Quad> = Ok(pair);
    let wide_failure: Result<Pair, Quad> = Err(quad);
    if (!is_ok(wide_success) || is_err(wide_success)) {{ return 3; }}
    if (is_ok(wide_failure) || !is_err(wide_failure)) {{ return 4; }}
    let signed_success: Result<i32, Pair> = Ok(-7);
    let signed_failure: Result<i32, Pair> = Err(pair);
    if (!is_ok(signed_success) || is_err(signed_success)) {{ return 5; }}
    if (is_ok(signed_failure) || !is_err(signed_failure)) {{ return 6; }}
    if (!is_ok(success) || !is_err(failure)) {{ return 7; }}
    return 0;
}}
"#
    );
    let bytes = common::run_gpu_codegen_with_timeout("generic Result predicates", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect("compile Result predicates with distinct payload layouts");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "generic Result predicates",
            "generic_result_predicates",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_option_predicates_with_local_nominal_payloads_execute() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let bytes = common::run_gpu_codegen_with_timeout("imported nominal Option", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(
            &root.join("tests/fixtures/stdlib_foundation/option_generic_predicates.lani"),
            &root.join("stdlib"),
        ))
    })
    .expect("compile imported generic Option with caller-local nominal payloads");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported nominal Option",
            "imported_nominal_option",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
    assert_imported_generic_constructor_rejects_an_unrelated_local_nominal();
}

#[test]
fn imported_option_recovers_multiword_payloads_and_fallbacks() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let bytes = common::run_gpu_codegen_with_timeout("imported Option payloads", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(
            &root.join("tests/fixtures/stdlib_foundation/option_imported_nominal_payloads.lani"),
            &root.join("stdlib"),
        ))
    })
    .expect("compile payload extraction and concrete Option fallbacks");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported Option payloads",
            "imported_option_payloads",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_option_preserves_string_and_slice_descriptors() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let bytes = common::run_gpu_codegen_with_timeout("Option descriptors", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(
            &root.join("tests/fixtures/stdlib_foundation/option_imported_descriptor_payloads.lani"),
            &root.join("stdlib"),
        ))
    })
    .expect("compile Option descriptors and borrowed payloads");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("Option descriptors", "option_descriptors", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(
            output.stdout, b"Option<T>\npayload\nfallback\n\n",
            "{output:?}"
        );
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_option_payload_boundaries_and_summary_execute() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, relative, expected_code, expected_stdout) in [
        (
            "scalar_payloads",
            "tests/fixtures/stdlib_foundation/option_imported_scalar_payloads.lani",
            0,
            "",
        ),
        (
            "slice_payload_bounds",
            "tests/fixtures/stdlib_foundation/option_imported_slice_payload_bounds.lani",
            101,
            "",
        ),
        (
            "optional_reading_summary",
            "sample_programs/optional_reading_summary.lani",
            0,
            "4\n20\n",
        ),
        (
            "reused_payload_binding",
            "tests/fixtures/stdlib_foundation/repro_option_reused_payload_binding.lani",
            0,
            "",
        ),
        (
            "local_nominal_return",
            "tests/fixtures/stdlib_foundation/repro_imported_option_local_nominal_return.lani",
            0,
            "",
        ),
    ] {
        let entry = root.join(relative);
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
        })
        .unwrap_or_else(|error| panic!("{name}: compile: {error}"));
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(expected_code),
                "{name}: {output:?}"
            );
            assert_eq!(
                output.stdout,
                expected_stdout.as_bytes(),
                "{name}: {output:?}"
            );
            assert!(output.stderr.is_empty(), "{name}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = (bytes, expected_code, expected_stdout);
    }
    // Reusing a declaration spelling must not make it escape its arm.
    let result = common::run_gpu_codegen_with_timeout("payload scope", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(
            "enum Maybe { Some(i32), None } fn choose(value: Maybe) -> i32 { return match (value) { Some(inner) -> inner, None -> inner }; } fn main() -> i32 { return 0; }",
        ))
    });
    let error = match result {
        Err(error) => error,
        Ok(_) => panic!("match payload escaped its arm"),
    };
    assert_eq!(error.to_public_diagnostic().code, "LNC0005", "{error:?}");
}

#[test]
fn imported_option_rejects_unresolved_payload_layouts() {
    for (name, declaration) in [
        ("empty", "struct Payload {}"),
        ("cyclic", "struct Payload { next: Payload }"),
        ("inline_array", "struct Payload { values: [i32; 3] }"),
        ("nested_array", "struct Payload { values: [[i32; 2]; 2] }"),
        ("string_array", "struct Payload { values: [str; 2] }"),
    ] {
        let entry = common::TempArtifact::new("laniusc_option_layout", name, Some("lani"));
        entry.write_str(&format!(
            "module app::main; import core::option; {declaration} fn main() -> i32 {{ let value: core::option::Option<Payload> = core::option::None(); return 0; }}"
        ));
        let path = entry.path().to_path_buf();
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let result = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(
                &path,
                &root.join("stdlib"),
            ))
        });
        let error = match result {
            Err(error) => error,
            Ok(_) => panic!("unsupported {name} payload layout compiled"),
        };
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{name}: {error:?}"
        );
    }
}

#[test]
fn unused_earlier_payload_keeps_the_used_payload_offset() {
    let source = r#"
pub struct Pair { first: i32, second: i32 }
pub enum Choice<T> { Item(T, i32), Empty }
fn main() -> i32 {
    let pair: Pair = Pair { first: -7, second: 99 };
    let choice: Choice<Pair> = Item(pair, 42);
    let selected: i32 = match (choice) { Item(ignored, used) -> used, Empty -> -1 };
    if (selected != 42) { return 1; }
    return 0;
}
"#;
    let bytes = common::run_gpu_codegen_with_timeout("used later payload", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source))
    })
    .expect("compile a used scalar after an unused multiword payload");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("used later payload", "used_later_payload", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn unresolved_payload_reads_and_offsets_fail_explicitly() {
    // No scalar width can safely be assumed for T, including when T itself
    // is ignored and a later scalar payload is used.
    for (body, entry) in [
        (
            "fn read<T>(value: Maybe<T>, fallback: T) -> T { return match (value) { Some(inner) -> inner, None -> fallback }; }",
            "let value: Maybe<i32> = Some(-7); return read(value, 99);",
        ),
        (
            "fn read<T>(value: Choice<T>) -> i32 { return match (value) { Item(ignored, used) -> used, Empty -> 0 }; }",
            "let value: Choice<i32> = Item(-7, 99); return read(value);",
        ),
    ] {
        let source = format!(
            "pub enum Maybe<T> {{ Some(T), None }} pub enum Choice<T> {{ Item(T, i32), Empty }} {body} fn main() -> i32 {{ {entry} }}"
        );
        let result = common::run_gpu_codegen_with_timeout("unresolved payload", move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
        });
        let error = match result {
            Err(error) => error,
            Ok(_) => panic!("unresolved payload operation compiled: {body}"),
        };
        assert_eq!(error.to_public_diagnostic().code, "LNC0017", "{error:?}");
    }
}

fn assert_imported_generic_constructor_rejects_an_unrelated_local_nominal() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        common::TempArtifact::new("laniusc_generic_option", "unrelated_nominal", Some("lani"));
    entry.write_str(
        r#"
module app::main;
import core::option;
struct Pair { first: i32, second: i32 }
struct Other { first: i32, second: i32 }
fn main() -> i32 {
    let other: Other = Other { first: 4, second: 9 };
    let value: core::option::Option<Pair> = core::option::Some(other);
    return 0;
}
"#,
    );
    let path = entry.path().to_path_buf();
    let result = common::run_gpu_codegen_with_timeout("unrelated generic nominal", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(
            &path,
            &root.join("stdlib"),
        ))
    });
    let error = match result {
        Err(error) => error,
        Ok(_) => panic!("unrelated generic nominal compiled"),
    };
    assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
}
