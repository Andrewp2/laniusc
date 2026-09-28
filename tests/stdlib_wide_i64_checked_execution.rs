mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn add_checked_case(
    source: &mut String,
    labels: &mut Vec<String>,
    expression: String,
    expected: Option<i64>,
    label: String,
) {
    let code = labels.len();
    assert!(code < 255);
    let predicate = match expected {
        Some(value) => {
            let bits = value as u64;
            format!(
                "core::option_wide_i64::contains({expression}, core::wide_i64::from_words({}, {}))",
                bits >> 32,
                bits as u32,
            )
        }
        None => format!("core::option_wide_i64::is_none({expression})"),
    };
    source.push_str(&format!("if (!{predicate}) {{ return {code}; }}\n"));
    labels.push(label);
}

fn add_saturating_case(
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
        "if (!core::wide_i64::eq({expression}, core::wide_i64::from_words({}, {}))) {{ return {code}; }}\n",
        bits >> 32,
        bits as u32,
    ));
    labels.push(label);
}

#[test]
fn wide_i64_checked_operations_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/core_wide_i64_checked.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("wide_i64_checked", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile checked two-word signed arithmetic");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("wide_i64_checked", "complete", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn every_public_wide_i64_checked_function_has_a_runtime_case() {
    let source = include_str!("../stdlib/core/wide_i64_checked.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/core_wide_i64_checked.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("public function has a name");
        let call = format!("core::wide_i64_checked::{name}(");
        assert!(fixture.contains(&call), "{call} lacks a runtime case");
        covered += 1;
    }
    assert_eq!(covered, 11);
}

#[test]
fn wide_i64_checked_matches_native_i64_across_word_patterns() {
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
        "module app::main;\nimport core::option_wide_i64;\nimport core::wide_i64;\n\
         import core::wide_i64_checked;\nfn main() -> i32 {\n",
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
            ("checked_add", a.checked_add(b)),
            ("checked_sub", a.checked_sub(b)),
            ("checked_mul", a.checked_mul(b)),
            ("checked_div", a.checked_div(b)),
            ("checked_rem", a.checked_rem(b)),
        ] {
            add_checked_case(
                &mut source,
                &mut labels,
                format!("core::wide_i64_checked::{operation}({left}, {right})"),
                expected,
                format!("case {index}: {operation}"),
            );
        }
        for (operation, expected) in [
            ("checked_neg", a.checked_neg()),
            ("checked_abs", a.checked_abs()),
        ] {
            add_checked_case(
                &mut source,
                &mut labels,
                format!("core::wide_i64_checked::{operation}({left})"),
                expected,
                format!("case {index}: {operation}"),
            );
        }
        add_saturating_case(
            &mut source,
            &mut labels,
            format!("core::wide_i64_checked::saturating_mul({left}, {right})"),
            a.saturating_mul(b),
            format!("case {index}: saturating_mul"),
        );
        for (operation, expected) in [
            ("saturating_neg", if a == i64::MIN { i64::MAX } else { -a }),
            (
                "saturating_abs",
                if a == i64::MIN { i64::MAX } else { a.abs() },
            ),
        ] {
            add_saturating_case(
                &mut source,
                &mut labels,
                format!("core::wide_i64_checked::{operation}({left})"),
                expected,
                format!("case {index}: {operation}"),
            );
        }
    }
    for (index, (base, exponent)) in [
        (0i64, 0u32),
        (0, 17),
        (1, u32::MAX),
        (-1, u32::MAX),
        (-2, 63),
        (-2, 64),
        (2, 62),
        (2, 63),
        (3, 40),
        (-3, 39),
    ]
    .into_iter()
    .enumerate()
    {
        let bits = base as u64;
        add_checked_case(
            &mut source,
            &mut labels,
            format!(
                "core::wide_i64_checked::checked_pow(core::wide_i64::from_words({}, {}), {exponent})",
                bits >> 32,
                bits as u32,
            ),
            base.checked_pow(exponent),
            format!("power case {index}"),
        );
    }
    source.push_str("return 0;\n}\n");

    let entry = common::TempArtifact::new("laniusc_wide_i64_checked", "differential", Some("lani"));
    entry.write_str(&source);
    let stdlib_root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let entry_path = entry.path().to_owned();
    let bytes = common::run_gpu_codegen_with_timeout("wide_i64_checked_differential", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(
            &entry_path,
            &stdlib_root,
        ))
    })
    .expect("compile generated checked signed cases");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("wide_i64_checked", "differential", &bytes);
        let code = output.status.code().unwrap_or(-1);
        let label = labels.get(code.max(0) as usize);
        assert_eq!(code, 0, "{label:?}: {output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = (bytes, labels);
}
