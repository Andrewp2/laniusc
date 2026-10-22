mod common;
use laniusc_compiler::compiler::{compile_entry_to_x86_64_with_source_roots, EntrySourceRoots};

fn compile(path: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"))
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn decimal_formatting_and_both_input_representations_execute() {
    let bytes = compile("tests/fixtures/stdlib_foundation/core_decimal.lani");
    let output = common::run_x86_64_elf_output("decimal contracts", "decimal", &bytes);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn packed_decimal_parsers_cover_widths_signs_overflow_and_exact_errors() {
    use std::os::unix::fs::PermissionsExt;
    let exe = common::TempArtifact::new("laniusc_decimal", "parse", None);
    exe.write_bytes(&compile(
        "tests/fixtures/stdlib_foundation/decimal_parse_input.lani",
    ));
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let input = common::TempArtifact::new("laniusc_decimal", "input", None);
    let check = |kind: u8, spelling: &[u8], status: i32, expected: String| {
        let mut source = vec![b'0' + kind];
        source.extend_from_slice(spelling);
        input.write_bytes(&source);
        let output = common::short_process_output_with_timeout(
            "decimal parse",
            std::process::Command::new(exe.path()).stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).unwrap(),
            )),
        );
        assert_eq!(
            output.status.code(),
            Some(status),
            "type {kind}, {spelling:?}: {output:?}"
        );
        assert_eq!(
            output.stdout,
            expected.as_bytes(),
            "type {kind}, {spelling:?}"
        );
        assert!(output.stderr.is_empty(), "{output:?}");
    };
    let ranges: [(i64, i64); 6] = [
        (0, 255),
        (0, 65535),
        (0, 4294967295),
        (-128, 127),
        (-32768, 32767),
        (-2147483648, 2147483647),
    ];
    let mut seed = 0xdec1_a132_u32;
    for (kind, (minimum, maximum)) in ranges.into_iter().enumerate() {
        let kind = kind as u8;
        let signed = kind >= 3;
        let mut values = vec![minimum, minimum + 1, 0, 1, maximum - 1, maximum];
        for _ in 0..32 {
            seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
            values.push(minimum + i64::from(seed) % (maximum - minimum + 1));
        }
        for value in values {
            let normalized = value.to_string();
            check(kind, normalized.as_bytes(), 0, normalized.clone());
            let padded = if value < 0 {
                format!("-000{}", -value)
            } else if signed {
                format!("+000{value}")
            } else {
                format!("000{value}")
            };
            check(kind, padded.as_bytes(), 0, normalized);
        }
        let over = (maximum + 1).to_string();
        check(kind, over.as_bytes(), 5, (over.len() - 1).to_string());
        if signed {
            let under = (minimum - 1).to_string();
            check(kind, under.as_bytes(), 5, (under.len() - 1).to_string());
            check(kind, b"-0", 0, "0".into());
            check(kind, b"+", 3, "1".into());
            check(kind, b"-", 3, "1".into());
            check(kind, b"++1", 4, "1".into());
            check(kind, b"--1", 4, "1".into());
            check(kind, b"-+1", 4, "1".into());
        } else {
            check(kind, b"+1", 4, "0".into());
            check(kind, b"-0", 4, "0".into());
        }
        for (spelling, status, offset) in [
            (&b""[..], 2, 0),
            (b" ", 4, 0),
            (b"1 ", 4, 1),
            (b"1\n", 4, 1),
            (b"1.0", 4, 1),
            (b"0x1", 4, 1),
            (b"1e2", 4, 1),
            (b"1_0", 4, 1),
            (b"1\0", 4, 1),
            (b"\xff", 4, 0),
            ("١".as_bytes(), 4, 0),
        ] {
            check(kind, spelling, status, offset.to_string());
        }
    }
}
