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
    let file = common::TempArtifact::new("laniusc_numeric_migration", "exe", None);
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
    let data = common::TempArtifact::new("laniusc_numeric_migration", "input", None);
    data.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_numeric_migration", "trace", None);
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

fn failures(exe: &common::TempArtifact, input: &[u8], expected: &[u8]) {
    let allocations = check(exe, input, 0, expected);
    assert!(allocations > 0);
    for when in 1..=allocations {
        let (out, _) = traced(exe, input, Some(when), false);
        assert_eq!(out.status.code(), Some(4), "allocation {when}: {out:?}");
        assert!(out.stdout.is_empty() && out.stderr.is_empty(), "{out:?}");
    }
    let (out, _) = traced(exe, input, None, true);
    assert_eq!(out.status.code(), Some(5), "{out:?}");
    assert!(out.stderr.is_empty(), "{out:?}");
}

#[test]
fn migrated_numeric_policies_execute_with_explicit_checked_fallbacks() {
    for name in [
        "number_byte",
        "number_i8",
        "number_i16",
        "number_u16",
        "number_u32",
        "core_narrow",
    ] {
        let exe = executable(&format!("tests/fixtures/stdlib_foundation/{name}.lani"));
        assert_eq!(
            check(&exe, b"", 0, b""),
            0,
            "allocation-free arithmetic: {name}"
        );
    }
}

#[test]
fn canonical_helpers_compose_in_hash_text_hex_arrays_and_wide_controls() {
    for name in [
        "core_hash",
        "core_text",
        "core_hex",
        "core_array_i32_4_complete",
        "core_wide_u64_complete",
        "core_hex_wide_u64",
    ] {
        let exe = executable(&format!("tests/fixtures/stdlib_foundation/{name}.lani"));
        check(&exe, b"", 0, b"");
    }
}

#[test]
fn native_recent_values_preserve_ranges_grammar_and_cleanup() {
    for (name, low, high, signed) in [
        ("recent_i8_lines", "-128", "127", true),
        ("recent_i16_lines", "-32768", "32767", true),
        ("recent_i32_lines", "-2147483648", "2147483647", true),
        ("recent_u16_lines", "0", "65535", false),
        ("recent_u32_lines", "0", "4294967295", false),
        (
            "recent_wide_i64_lines",
            "-9223372036854775808",
            "9223372036854775807",
            true,
        ),
        ("recent_wide_u64_lines", "0", "18446744073709551615", false),
    ] {
        let exe = executable(&format!("sample_programs/{name}.lani"));
        let input = format!("{low}\n{high}\n0\n{low}\n");
        let expected = format!("{high} 0 {low}\n");
        failures(&exe, input.as_bytes(), expected.as_bytes());
        check(&exe, b"", 0, b"\n");
        check(&exe, b"1\n\n", 2, b"");
        for bad in [
            " 1\n",
            "1 \n",
            "1x\n",
            "1\r\n",
            "+\n",
            "-\n",
            "1\n18446744073709551616\n",
        ] {
            check(&exe, bad.as_bytes(), 3, b"");
        }
        let over = format!("{}\n", high.parse::<u128>().unwrap_or(i64::MAX as u128) + 1);
        check(&exe, over.as_bytes(), 3, b"");
        if signed {
            let under = format!("{}\n", low.parse::<i128>().unwrap() - 1);
            check(&exe, under.as_bytes(), 3, b"");
            check(&exe, b"+0001\n-0\n", 0, b"1 0\n");
        } else {
            check(&exe, b"+1\n", 3, b"");
            check(&exe, b"-0\n", 3, b"");
        }
        check(&exe, b"000000000000000000001\n", 2, b"");
    }
}

#[test]
fn native_medians_keep_signed_unsigned_order_and_checked_owner_errors() {
    for (name, low, high, signed) in [
        ("sorted_i32_median", "-2147483648", "2147483647", true),
        ("sorted_u32_median", "0", "4294967295", false),
        (
            "sorted_wide_signed_median",
            "-9223372036854775808",
            "9223372036854775807",
            true,
        ),
        (
            "sorted_wide_unsigned_median",
            "0",
            "18446744073709551615",
            false,
        ),
    ] {
        let exe = executable(&format!("sample_programs/{name}.lani"));
        let input = format!("{high}\n{low}\n1\n{high}\n1\n");
        failures(&exe, input.as_bytes(), b"1 2\n");
        let input = format!("{low}\n{high}\n");
        let expected = format!("{high} 1\n");
        check(&exe, input.as_bytes(), 0, expected.as_bytes());
        check(&exe, b"", 2, b"");
        check(&exe, b"1\n\n", 2, b"");
        for bad in ["1x\n", " 1\n", "1 \n", "1\r\n", "1\n18446744073709551616\n"] {
            check(&exe, bad.as_bytes(), 3, b"");
        }
        if signed {
            check(&exe, b"+0001\n-0\n", 0, b"1 1\n");
        } else {
            check(&exe, b"+1\n", 3, b"");
        }
    }
}

#[test]
fn native_frequency_and_distinct_reports_keep_full_width_identity_and_wrapping() {
    for (word, input, frequency, sum) in [
        (
            "unsigned",
            "18446744073709551615\n1\n18446744073709551615\n4294967296\n9223372036854775808\n2\n",
            "18446744073709551615 2\n1 1\n4294967296 1\n9223372036854775808 1\n2 1\n",
            "9223372041149743106\n",
        ),
        (
            "signed",
            "-9223372036854775808\n9223372036854775807\n-9223372036854775808\n-1\n4294967296\n1\n",
            "-9223372036854775808 2\n9223372036854775807 1\n-1 1\n4294967296 1\n1 1\n",
            "4294967295\n",
        ),
    ] {
        for (suffix, expected) in [("frequency_report", frequency), ("distinct_sum", sum)] {
            let exe = executable(&format!("sample_programs/wide_{word}_{suffix}.lani"));
            failures(&exe, input.as_bytes(), expected.as_bytes());
            check(&exe, b"1\ninvalid\n", 3, b"");
            check(&exe, b"1\n\n", 2, b"");
            check(&exe, b"1\n18446744073709551616\n", 3, b"");
            check(&exe, b" 1\n", 3, b"");
            check(&exe, b"1\r\n", 3, b"");
            if word == "signed" {
                check(
                    &exe,
                    b"+0\n-0\n",
                    0,
                    if suffix == "frequency_report" {
                        b"0 2\n"
                    } else {
                        b"0\n"
                    },
                );
            } else {
                check(&exe, b"+0\n", 3, b"");
            }
        }
    }
}

#[test]
fn native_owned_numeric_stdout_pipe_failures_release_every_allocation() {
    for name in [
        "recent_i8_lines",
        "recent_i16_lines",
        "recent_i32_lines",
        "recent_u16_lines",
        "recent_u32_lines",
        "recent_wide_i64_lines",
        "recent_wide_u64_lines",
        "sorted_i32_median",
        "sorted_u32_median",
        "sorted_wide_signed_median",
        "sorted_wide_unsigned_median",
        "wide_signed_frequency_report",
        "wide_unsigned_frequency_report",
        "wide_signed_distinct_sum",
        "wide_unsigned_distinct_sum",
    ] {
        let exe = executable(&format!("sample_programs/{name}.lani"));
        for setup_failure in [false, true] {
            if setup_failure && name != "recent_i8_lines" {
                continue;
            }
            let input = common::TempArtifact::new("laniusc_numeric_pipe", "input", None);
            input.write_bytes(b"1\n2\n1\n");
            let trace = common::TempArtifact::new("laniusc_numeric_pipe", "trace", None);
            let mut command = Command::new("timeout");
            command
                .args(["--kill-after=1s", "3s", "strace", "-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=rt_sigaction,read,write,mmap,munmap"]);
            if setup_failure {
                command.args(["-e", "inject=rt_sigaction:error=EINTR:when=1"]);
            }
            let (reader, writer) = std::io::pipe().unwrap();
            drop(reader);
            command
                .arg(exe.path())
                .stdin(std::fs::File::open(input.path()).unwrap())
                .stdout(writer);
            // Preserve the actual closed-reader pipe rather than replacing it
            // with the generic helper's captured stdout pipe.
            let out = command
                .output()
                .expect("run bounded numeric closed-pipe gate");
            assert_eq!(out.status.code(), Some(5), "{name}: {out:?}");
            assert!(
                out.stdout.is_empty() && out.stderr.is_empty(),
                "{name}: {out:?}"
            );
            let events = std::fs::read_to_string(trace.path()).unwrap();
            let allocations = released(&events);
            assert!(events.contains("rt_sigaction(SIGPIPE"), "{name}: {events}");
            if setup_failure {
                assert!(
                    events.contains("INJECTED") && events.contains("EINTR"),
                    "{events}"
                );
                assert_eq!(allocations, 0, "{events}");
                assert!(
                    !events.contains("read(") && !events.contains("write("),
                    "{events}"
                );
            } else {
                assert!(
                    events.contains("SIG_IGN") && events.contains("EPIPE"),
                    "{name}: {events}"
                );
                assert!(
                    allocations > 0,
                    "{name}: workload did not allocate: {events}"
                );
            }
        }
    }
}
