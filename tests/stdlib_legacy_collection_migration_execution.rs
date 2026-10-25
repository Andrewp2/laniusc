#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
};

use laniusc_compiler::compiler::{EntrySourceRoots, compile_entry_to_x86_64_with_source_roots};

fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let file = common::TempArtifact::new("laniusc_collection_migration", "exe", None);
    file.write_bytes(bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}

// Every native allocation in these freestanding programs belongs to the
// application. Check both the address and length of every successful release.
fn released(trace: &str) -> usize {
    let mut live = BTreeMap::new();
    let mut allocated = 0;
    for line in trace.lines() {
        if let Some(arguments) = line.strip_prefix("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                let address = result.split_whitespace().next().unwrap();
                let length = arguments.split(',').nth(1).unwrap().trim();
                assert!(live.insert(address, length).is_none(), "{line}");
                allocated += 1;
            }
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            assert!(line.ends_with(" = 0"), "{line}");
            let (address, tail) = arguments.split_once(',').unwrap();
            let length = tail.split(')').next().unwrap().trim();
            assert_eq!(live.remove(address), Some(length), "{line}");
        }
    }
    assert!(
        live.is_empty(),
        "leaked native allocations: {live:?}\n{trace}"
    );
    allocated
}

fn traced(
    exe: &common::TempArtifact,
    input: &[u8],
    deny_from: Option<usize>,
    full: bool,
) -> (Output, usize) {
    let data = common::TempArtifact::new("laniusc_collection_migration", "input", None);
    data.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_collection_migration", "trace", None);
    let mut command = Command::new("timeout");
    command.args(["3s", "strace"]);
    command
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"]);
    if let Some(when) = deny_from {
        command
            .arg("-e")
            .arg(format!("inject=mmap:error=ENOMEM:when={when}+"));
    }
    command
        .arg(exe.path())
        .stdin(std::fs::File::open(data.path()).unwrap());
    if full {
        command.stdout(
            std::fs::OpenOptions::new()
                .write(true)
                .open("/dev/full")
                .unwrap(),
        );
    }
    let output = command.output().expect("run bounded collection sample");
    assert_ne!(
        output.status.code(),
        Some(124),
        "native sample timed out: {output:?}"
    );
    let events = std::fs::read_to_string(trace.path()).unwrap();
    if deny_from.is_some() {
        assert!(
            events.contains("INJECTED") && events.contains("ENOMEM"),
            "{events}"
        );
    }
    let allocations = released(&events);
    (output, allocations)
}

fn check(exe: &common::TempArtifact, input: &[u8], code: i32, stdout: &[u8]) -> usize {
    let (output, allocations) = traced(exe, input, None, false);
    assert_eq!(output.status.code(), Some(code), "{input:?}: {output:?}");
    assert_eq!(output.stdout, stdout, "{input:?}: {output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    allocations
}

fn failures(
    exe: &common::TempArtifact,
    input: &[u8],
    expected: &[u8],
    allocation_codes: &[i32],
    output_code: i32,
) {
    let allocations = check(exe, input, 0, expected);
    assert!(allocations > 0, "the failure sweep must actually allocate");
    for when in 1..=allocations {
        let (output, _) = traced(exe, input, Some(when), false);
        assert!(
            allocation_codes.contains(&output.status.code().unwrap()),
            "allocation {when}: {output:?}"
        );
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
    }
    let (output, _) = traced(exe, input, None, true);
    assert_eq!(output.status.code(), Some(output_code), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
fn bounded_byte_consumers_cover_every_byte_without_allocating() {
    let all = (0..=255).collect::<Vec<u8>>();
    for (name, empty, binary, complete) in [
        (
            "count_digit_bytes",
            b"0\n0\n".as_slice(),
            b"2\n3\n".as_slice(),
            b"10\n246\n".as_slice(),
        ),
        (
            "count_distinct_bytes",
            b"0\n0\n".as_slice(),
            b"4\n1\n".as_slice(),
            b"256\n10\n".as_slice(),
        ),
        (
            "byte_frequency_report",
            b"-1\n0\n".as_slice(),
            b"48\n2\n".as_slice(),
            b"0\n1\n".as_slice(),
        ),
        (
            "signed_byte_frequency_report",
            b"-129\n0\n0\n".as_slice(),
            b"48\n2\n4\n".as_slice(),
            b"-128\n1\n256\n".as_slice(),
        ),
    ] {
        let exe = executable(&format!("sample_programs/{name}.lani"));
        for (input, expected) in [
            (b"".as_slice(), empty),
            (b"\xff\0\x8000".as_slice(), binary),
            (all.as_slice(), complete),
        ] {
            assert_eq!(
                check(&exe, input, 0, expected),
                0,
                "{name} must not allocate"
            );
        }
        let (output, allocations) = traced(&exe, b"", None, true);
        assert_eq!(output.status.code(), Some(4), "{name}: {output:?}");
        assert_eq!(allocations, 0);
    }
}

#[test]
fn frequency_reports_preserve_order_full_width_values_and_explicit_errors() {
    let exe = executable("sample_programs/unsigned_frequency_report.lani");
    failures(&exe, b"", b"3 2 1\n", &[2], 3);
    let exe = executable("sample_programs/unicode_frequency_report.lani");
    check(&exe, b"", 0, b"");
    check(&exe, b"\0a\0", 0, b"\0:2\na:1\n");
    check(&exe, b"a\xff", 2, b"");
    check(&exe, b"a\xf0\x9f", 2, b"");
    let unicode = "Ω😀Ωa\0𐀀é中\u{10ffff}";
    failures(
        &exe,
        unicode.as_bytes(),
        "Ω:2\n😀:1\na:1\n\0:1\n𐀀:1\né:1\n中:1\n\u{10ffff}:1\n".as_bytes(),
        &[4],
        5,
    );
    for (name, input, expected) in [
        (
            "wide_unsigned_frequency_report",
            "18446744073709551615\n0\n4294967296\n18446744073709551615\n1\n9223372036854775808\n",
            "18446744073709551615 2\n0 1\n4294967296 1\n1 1\n9223372036854775808 1\n",
        ),
        (
            "wide_signed_frequency_report",
            "-9223372036854775808\n0\n9223372036854775807\n-9223372036854775808\n-1\n4294967296\n",
            "-9223372036854775808 2\n0 1\n9223372036854775807 1\n-1 1\n4294967296 1\n",
        ),
    ] {
        let exe = executable(&format!("sample_programs/{name}.lani"));
        check(&exe, b"", 0, b"");
        check(&exe, b"1\ninvalid\n", 3, b"");
        check(&exe, b"1\n\n", 2, b"");
        failures(&exe, input.as_bytes(), expected.as_bytes(), &[4], 5);
    }
    let exe = executable("tests/fixtures/stdlib_foundation/collection_byte_histogram.lani");
    check(&exe, b"", 0, b"0 0\n");
    check(&exe, b"abbccc", 0, b"3 590\n");
    failures(&exe, &[0, 255, 255, 128], b"3 638\n", &[3], 5);
}

#[test]
fn distinct_consumers_keep_unicode_and_wide_identity_on_checked_sets() {
    let exe = executable("sample_programs/unique_unsigned_total.lani");
    failures(&exe, b"", b"2147483648\n", &[1], 2);
    let exe = executable("sample_programs/unique_unicode_count.lani");
    check(&exe, b"", 0, b"0\n");
    check(&exe, b"a\xff", 2, b"");
    failures(&exe, "Ω😀Ωa\0𐀀é中\u{10ffff}".as_bytes(), b"8\n", &[4], 5);
    for (name, input, expected) in [
        (
            "wide_unsigned_distinct_sum",
            "18446744073709551615\n1\n18446744073709551615\n4294967296\n9223372036854775808\n2\n",
            "9223372041149743106\n",
        ),
        (
            "wide_signed_distinct_sum",
            "-9223372036854775808\n9223372036854775807\n-9223372036854775808\n-1\n4294967296\n1\n",
            "4294967295\n",
        ),
    ] {
        let exe = executable(&format!("sample_programs/{name}.lani"));
        check(&exe, b"", 0, b"0\n");
        check(&exe, b"1\ninvalid\n", 3, b"");
        check(&exe, b"1\n\n", 2, b"");
        failures(&exe, input.as_bytes(), expected.as_bytes(), &[4], 5);
    }
}

#[test]
fn packed_byte_and_utf8_consumers_report_denial_and_release_every_owner() {
    let exe = executable("sample_programs/vector_byte_checksum.lani");
    failures(&exe, b"", b"4\n", &[1], 2);
    let exe = executable("sample_programs/utf8_text_report.lani");
    failures(&exe, b"", "A¢A¢B5\n".as_bytes(), &[1], 2);
    let exe = executable("sample_programs/utf8_owned_line.lani");
    check(&exe, b"", 2, b"");
    check(&exe, b"\xff\n", 3, b"");
    check(&exe, b"\n", 0, "🙂 1\n".as_bytes());
    check(&exe, b"1234567890123\n", 2, b"");
    failures(
        &exe,
        "é😀\0A\n".as_bytes(),
        "é😀\0A🙂 5\n".as_bytes(),
        &[4, 5],
        7,
    );
    for name in ["alloc_string_edits", "comparison_collections"] {
        let exe = executable(&format!("tests/fixtures/stdlib_foundation/{name}.lani"));
        check(&exe, b"", 0, b"");
    }
}
