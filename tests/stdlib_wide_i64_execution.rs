mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_entry(entry: &std::path::Path, context: &str) -> Vec<u8> {
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry = entry.to_owned();
    common::run_gpu_codegen_with_timeout(context, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("{context}: compile: {error}"))
}

fn add_check(
    source: &mut String,
    labels: &mut Vec<String>,
    expression: String,
    expected: i64,
    label: String,
) {
    let code = labels.len();
    assert!(code < 255);
    let bits = expected as u64;
    source.push_str(&format!(
        "if (!same({expression}, {}, {})) {{ return {code}; }}\n",
        bits >> 32,
        bits as u32,
    ));
    labels.push(label);
}

#[test]
fn wide_i64_fixed_cases_execute_on_x86() {
    let entry = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/core_wide_i64_complete.lani");
    let bytes = compile_entry(&entry, "wide_i64_fixed");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("wide_i64", "fixed", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn every_public_wide_i64_function_has_a_runtime_case() {
    let source = include_str!("../stdlib/core/wide_i64.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/core_wide_i64_complete.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("wide i64 function has a name");
        let call = format!("core::wide_i64::{name}(");
        assert!(fixture.contains(&call), "{call} lacks a runtime case");
        covered += 1;
    }
    assert_eq!(covered, 29);
}

#[test]
fn decimal_double_program_runs_full_width_signed_input_on_x86() {
    let entry = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/wide_i64_decimal_double.lani");
    let bytes = compile_entry(&entry, "wide_i64_decimal_double");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::fs::PermissionsExt;

        let executable = common::TempArtifact::new("laniusc_wide_i64", "decimal_double", None);
        executable.write_bytes(&bytes);
        let mut permissions = std::fs::metadata(executable.path()).unwrap().permissions();
        permissions.set_mode(0o700);
        std::fs::set_permissions(executable.path(), permissions).unwrap();

        for (input_bytes, expected_code, expected_stdout) in [
            (&b"0\n"[..], 0, &b"0\n"[..]),
            (&b"-0\n"[..], 0, &b"0\n"[..]),
            (&b"-42\n"[..], 0, &b"-84\n"[..]),
            (&b"4294967296\n"[..], 0, &b"8589934592\n"[..]),
            (&b"-4294967296\n"[..], 0, &b"-8589934592\n"[..]),
            (&b"-9223372036854775808\n"[..], 0, &b"0\n"[..]),
            (&b"9223372036854775807\n"[..], 0, &b"-2\n"[..]),
            (&b"9223372036854775808\n"[..], 3, &b""[..]),
            (&b"-9223372036854775809\n"[..], 3, &b""[..]),
            (&b"-\n"[..], 3, &b""[..]),
            (&b"12x\n"[..], 3, &b""[..]),
            (&b""[..], 2, &b""[..]),
            (&b"123456789012345678901\n"[..], 2, &b""[..]),
        ] {
            let input = common::TempArtifact::new("laniusc_wide_i64", "decimal_input", None);
            input.write_bytes(input_bytes);
            let output = common::short_process_output_with_timeout(
                "wide i64 decimal double",
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
fn wide_i64_arithmetic_matches_native_i64_across_word_patterns() {
    let cases: [(i64, i64); 8] = [
        (0, 1),
        (1, -1),
        (i64::MAX, 1),
        (i64::MIN, -1),
        (i64::MIN, 2),
        (-7, 3),
        (7, -3),
        (0x1234_5678_9abc_def0, -0x1234_5678_7654_3210),
    ];
    let mut source = String::from(
        "module app::main;\nimport core::wide_i64;\n\
         fn same(value: core::wide_i64::WideI64, high: u32, low: u32) -> bool {\n\
         return core::wide_i64::high_word(value) == high && core::wide_i64::low_word(value) == low;\n}\n\
         fn main() -> i32 {\n",
    );
    let mut labels = vec![String::from("success")];
    for (index, (a, b)) in cases.into_iter().enumerate() {
        let left = format!("a{index}");
        let right = format!("b{index}");
        source.push_str(&format!(
            "let {left}: core::wide_i64::WideI64 = core::wide_i64::from_words({}, {});\n\
             let {right}: core::wide_i64::WideI64 = core::wide_i64::from_words({}, {});\n",
            (a as u64) >> 32,
            a as u32,
            (b as u64) >> 32,
            b as u32,
        ));
        for (operation, expected) in [
            ("wrapping_add", a.wrapping_add(b)),
            ("wrapping_sub", a.wrapping_sub(b)),
            ("wrapping_mul", a.wrapping_mul(b)),
            ("saturating_add", a.saturating_add(b)),
            ("saturating_sub", a.saturating_sub(b)),
            ("bit_and", a & b),
            ("bit_or", a | b),
            ("bit_xor", a ^ b),
        ] {
            add_check(
                &mut source,
                &mut labels,
                format!("core::wide_i64::{operation}({left}, {right})"),
                expected,
                format!("case {index}: {operation}"),
            );
        }
        add_check(
            &mut source,
            &mut labels,
            format!("core::wide_i64::wrapping_neg({left})"),
            a.wrapping_neg(),
            format!("case {index}: wrapping_neg"),
        );
        add_check(
            &mut source,
            &mut labels,
            format!("core::wide_i64::bit_not({left})"),
            !a,
            format!("case {index}: bit_not"),
        );
        if b != 0 && !(a == i64::MIN && b == -1) {
            let fallback = "core::wide_i64::zero()";
            add_check(
                &mut source,
                &mut labels,
                format!("core::wide_i64::divide_or({left}, {right}, {fallback})"),
                a / b,
                format!("case {index}: divide"),
            );
            add_check(
                &mut source,
                &mut labels,
                format!("core::wide_i64::remainder_or({left}, {right}, {fallback})"),
                a % b,
                format!("case {index}: remainder"),
            );
        }
    }
    for (index, value) in [0i64, -1, i64::MIN, 0x1234_5678_9abc_def0]
        .into_iter()
        .enumerate()
    {
        let name = format!("s{index}");
        source.push_str(&format!(
            "let {name}: core::wide_i64::WideI64 = core::wide_i64::from_words({}, {});\n",
            (value as u64) >> 32,
            value as u32,
        ));
        for count in [0, 1, 31, 32, 33, 63, 64, -1] {
            let left = if (0..64).contains(&count) {
                value.wrapping_shl(count as u32)
            } else {
                0
            };
            let right = if (0..64).contains(&count) {
                value.wrapping_shr(count as u32)
            } else {
                0
            };
            add_check(
                &mut source,
                &mut labels,
                format!("core::wide_i64::shift_left({name}, {count})"),
                left,
                format!("shift case {index}: left {count}"),
            );
            add_check(
                &mut source,
                &mut labels,
                format!("core::wide_i64::shift_right({name}, {count})"),
                right,
                format!("shift case {index}: right {count}"),
            );
        }
    }
    source.push_str("return 0;\n}\n");

    let entry = common::TempArtifact::new("laniusc_wide_i64", "differential", Some("lani"));
    entry.write_str(&source);
    let bytes = compile_entry(entry.path(), "wide_i64_differential");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("wide_i64", "differential", &bytes);
        let code = output.status.code().unwrap_or(-1);
        let label = labels.get(code.max(0) as usize);
        assert_eq!(code, 0, "{label:?}: {output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = (bytes, labels);
}
