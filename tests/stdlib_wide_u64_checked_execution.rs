mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn add_checked_case(
    source: &mut String,
    labels: &mut Vec<String>,
    expression: String,
    expected: Option<u64>,
    label: String,
) {
    let code = labels.len();
    assert!(code < 255);
    let predicate = match expected {
        Some(value) => format!(
            "core::option::contains({expression}, core::wide_u64::from_words({}, {}))",
            value >> 32,
            value as u32,
        ),
        None => format!("core::option::is_none({expression})"),
    };
    source.push_str(&format!("if (!{predicate}) {{ return {code}; }}\n"));
    labels.push(label);
}

fn add_saturating_case(
    source: &mut String,
    labels: &mut Vec<String>,
    expression: String,
    expected: u64,
    label: String,
) {
    let code = labels.len();
    assert!(code < 255);
    source.push_str(&format!(
        "if (!core::wide_u64::eq({expression}, core::wide_u64::from_words({}, {}))) {{ return {code}; }}\n",
        expected >> 32,
        expected as u32,
    ));
    labels.push(label);
}

#[test]
fn wide_u64_checked_operations_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/core_wide_u64_checked.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("wide_u64_checked", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile checked two-word unsigned arithmetic");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("wide_u64_checked", "complete", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn checked_factorial_program_runs_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/wide_checked_factorial.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("wide_checked_factorial", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile checked factorial program");

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;

        let executable = common::TempArtifact::new("laniusc_wide_checked", "factorial", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions).unwrap();
        for (input_bytes, expected_code, expected_stdout) in [
            (&b"0\n"[..], 0, &b"1\n"[..]),
            (&b"5\n"[..], 0, &b"120\n"[..]),
            (&b"20\n"[..], 0, &b"2432902008176640000\n"[..]),
            (&b"21\n"[..], 3, &b""[..]),
            (&b"x\n"[..], 2, &b""[..]),
            (&b""[..], 2, &b""[..]),
            (&b"                  5"[..], 2, &b""[..]),
        ] {
            let input = common::TempArtifact::new("laniusc_wide_checked", "input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "checked factorial",
                std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                    std::fs::File::open(input.path()).unwrap(),
                )),
            );
            assert_eq!(output.status.code(), Some(expected_code), "{output:?}");
            assert_eq!(output.stdout, expected_stdout, "{output:?}");
            assert!(output.stderr.is_empty(), "{output:?}");
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn every_public_wide_u64_checked_function_has_a_runtime_case() {
    let source = include_str!("../stdlib/core/wide_u64_checked.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/core_wide_u64_checked.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("public function has a name");
        let call = format!("core::wide_u64_checked::{name}(");
        assert!(fixture.contains(&call), "{call} lacks a runtime case");
        covered += 1;
    }
    assert_eq!(covered, 9);
}

#[test]
fn wide_u64_checked_matches_native_u64_across_word_patterns() {
    let cases: [(u64, u64); 8] = [
        (0, 1),
        (1, 0),
        (u64::MAX, 2),
        (1u64 << 63, 3),
        (0xffff_ffff_0000_0000, 0x0000_0001_ffff_ffff),
        (0x1234_5678_9abc_def0, 0xfedc_ba98_7654_3210),
        (0x8000_0000_0000_0001, 0x8000_0000_0000_0000),
        (0xdead_beef_cafe_babe, 0x0123_4567_89ab_cdef),
    ];
    let mut source = String::from(
        "module app::main;\nimport core::option;\nimport core::wide_u64;\n\
         import core::wide_u64_checked;\nfn main() -> i32 {\n",
    );
    let mut labels = vec![String::from("success")];
    for (index, (a, b)) in cases.into_iter().enumerate() {
        let left = format!("a{index}");
        let right = format!("b{index}");
        source.push_str(&format!(
            "let {left}: core::wide_u64::WideU64 = core::wide_u64::from_words({}, {});\n\
             let {right}: core::wide_u64::WideU64 = core::wide_u64::from_words({}, {});\n",
            a >> 32,
            a as u32,
            b >> 32,
            b as u32,
        ));
        for (operation, expected) in [
            ("checked_add", a.checked_add(b)),
            ("checked_sub", a.checked_sub(b)),
            ("checked_mul", a.checked_mul(b)),
            ("checked_div", a.checked_div(b)),
            ("checked_rem", a.checked_rem(b)),
        ] {
            add_checked_case(
                &mut source,
                &mut labels,
                format!("core::wide_u64_checked::{operation}({left}, {right})"),
                expected,
                format!("case {index}: {operation}"),
            );
        }
        for (operation, expected) in [
            ("saturating_add", a.saturating_add(b)),
            ("saturating_sub", a.saturating_sub(b)),
            ("saturating_mul", a.saturating_mul(b)),
        ] {
            add_saturating_case(
                &mut source,
                &mut labels,
                format!("core::wide_u64_checked::{operation}({left}, {right})"),
                expected,
                format!("case {index}: {operation}"),
            );
        }
    }
    for (index, (base, exponent)) in [
        (0u64, 0u32),
        (0, 17),
        (1, u32::MAX),
        (2, 63),
        (2, 64),
        (3, 13),
        (1u64 << 32, 2),
        (0xffff, 4),
    ]
    .into_iter()
    .enumerate()
    {
        add_checked_case(
            &mut source,
            &mut labels,
            format!(
                "core::wide_u64_checked::checked_pow(core::wide_u64::from_words({}, {}), {exponent})",
                base >> 32,
                base as u32,
            ),
            base.checked_pow(exponent),
            format!("power case {index}"),
        );
    }
    source.push_str("return 0;\n}\n");

    let entry = common::TempArtifact::new("laniusc_wide_u64_checked", "differential", Some("lani"));
    entry.write_str(&source);
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry_path = entry.path().to_owned();
    let bytes = common::run_gpu_codegen_with_timeout("wide_u64_checked_differential", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(
            &entry_path,
            &stdlib_root,
        ))
    })
    .expect("compile generated checked unsigned cases");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("wide_u64_checked", "differential", &bytes);
        let code = output.status.code().unwrap_or(-1);
        let label = labels.get(code.max(0) as usize);
        assert_eq!(code, 0, "{label:?}: {output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = (bytes, labels);
}
