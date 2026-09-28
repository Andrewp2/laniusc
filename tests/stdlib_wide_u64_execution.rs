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
    expected: u64,
    label: String,
) {
    let code = labels.len();
    assert!(code < 255);
    source.push_str(&format!(
        "if (!same({expression}, {}, {})) {{ return {code}; }}\n",
        expected >> 32,
        expected as u32,
    ));
    labels.push(label);
}

#[test]
fn wide_u64_fixed_cases_execute_on_x86() {
    let entry = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/core_wide_u64_complete.lani");
    let bytes = compile_entry(&entry, "wide_u64_fixed");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("wide_u64", "fixed", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn every_public_wide_u64_function_has_a_runtime_case() {
    let source = include_str!("../stdlib/core/wide_u64.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/core_wide_u64_complete.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("wide u64 function has a name");
        let call = format!("core::wide_u64::{name}(");
        assert!(fixture.contains(&call), "{call} lacks a runtime case");
        covered += 1;
    }
    assert_eq!(covered, 20);
}

#[test]
fn wide_u64_arithmetic_matches_native_u64_across_word_patterns() {
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
        "module app::main;\nimport core::wide_u64;\n\
         fn same(value: core::wide_u64::WideU64, high: u32, low: u32) -> bool {\n\
         return core::wide_u64::high_word(value) == high && core::wide_u64::low_word(value) == low;\n}\n\
         fn main() -> i32 {\n",
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
            ("wrapping_add", a.wrapping_add(b)),
            ("wrapping_sub", a.wrapping_sub(b)),
            ("wrapping_mul", a.wrapping_mul(b)),
            ("bit_and", a & b),
            ("bit_or", a | b),
            ("bit_xor", a ^ b),
        ] {
            add_check(
                &mut source,
                &mut labels,
                format!("core::wide_u64::{operation}({left}, {right})"),
                expected,
                format!("case {index}: {operation}"),
            );
        }
        add_check(
            &mut source,
            &mut labels,
            format!("core::wide_u64::bit_not({left})"),
            !a,
            format!("case {index}: bit_not"),
        );
        if b != 0 {
            let fallback = "core::wide_u64::zero()";
            add_check(
                &mut source,
                &mut labels,
                format!("core::wide_u64::divide_or({left}, {right}, {fallback})"),
                a / b,
                format!("case {index}: divide"),
            );
            add_check(
                &mut source,
                &mut labels,
                format!("core::wide_u64::remainder_or({left}, {right}, {fallback})"),
                a % b,
                format!("case {index}: remainder"),
            );
        }
    }
    for (index, value) in [0u64, 1, u64::MAX, 0x1234_5678_9abc_def0]
        .into_iter()
        .enumerate()
    {
        let name = format!("s{index}");
        source.push_str(&format!(
            "let {name}: core::wide_u64::WideU64 = core::wide_u64::from_words({}, {});\n",
            value >> 32,
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
                format!("core::wide_u64::shift_left({name}, {count})"),
                left,
                format!("shift case {index}: left {count}"),
            );
            add_check(
                &mut source,
                &mut labels,
                format!("core::wide_u64::shift_right({name}, {count})"),
                right,
                format!("shift case {index}: right {count}"),
            );
        }
    }
    source.push_str("return 0;\n}\n");

    let entry = common::TempArtifact::new("laniusc_wide_u64", "differential", Some("lani"));
    entry.write_str(&source);
    let bytes = compile_entry(entry.path(), "wide_u64_differential");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("wide_u64", "differential", &bytes);
        let code = output.status.code().unwrap_or(-1);
        let label = labels.get(code.max(0) as usize);
        assert_eq!(code, 0, "{label:?}: {output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = (bytes, labels);
}
