mod common;

use laniusc_compiler::compiler::{compile_entry_to_x86_64_with_source_roots, EntrySourceRoots};

fn compile(path: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"))
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn csv_tables_enforce_limits_and_return_independent_fields() {
    let bytes = compile("tests/fixtures/extended/csv_contracts.lani");
    let output = common::run_x86_64_elf_output("CSV contracts", "contracts", &bytes);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn csv_normalizer_executes_quoting_unicode_and_error_cases() {
    use std::os::unix::fs::PermissionsExt;
    let bytes = compile("sample_programs/csv_normalize.lani");
    let executable = common::TempArtifact::new("laniusc_csv", "normalizer", None);
    executable.write_bytes(&bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    for (source, expected) in [
        ("", ""),
        ("a", "\"a\"\r\n"),
        ("a,b\r\nc,d", "\"a\",\"b\"\r\n\"c\",\"d\"\r\n"),
        ("a,b\nc,d\n", "\"a\",\"b\"\r\n\"c\",\"d\"\r\n"),
        ("\"a,b\",\"c\"\"d\"", "\"a,b\",\"c\"\"d\"\r\n"),
        ("\"a\r\nb\",c", "\"a\r\nb\",\"c\"\r\n"),
        ("\"a\nb\",c", "\"a\nb\",\"c\"\r\n"),
        (",", "\"\",\"\"\r\n"),
        ("\"\"", "\"\"\r\n"),
        ("\n", "\"\"\r\n"),
        ("a,\n", "\"a\",\"\"\r\n"),
        (" a , b ", "\" a \",\" b \"\r\n"),
        ("é,🙂", "\"é\",\"🙂\"\r\n"),
        ("\"\"\"\"", "\"\"\"\"\r\n"),
    ] {
        let input = common::TempArtifact::new("laniusc_csv", "stdin", None);
        input.write_bytes(source.as_bytes());
        let output = common::short_process_output_with_timeout(
            "CSV normalize",
            std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).unwrap(),
            )),
        );
        assert_eq!(output.status.code(), Some(0), "{source:?}: {output:?}");
        assert_eq!(output.stdout, expected.as_bytes(), "{source:?}: {output:?}");
        assert!(output.stderr.is_empty(), "{source:?}: {output:?}");
    }
    for source in [
        "a\rb",
        "a\"b",
        "\"a",
        "\"a\"x",
        "a,b\nc",
        "a\0",
        "a\tb",
        "\"\u{7f}\"",
    ] {
        let input = common::TempArtifact::new("laniusc_csv", "invalid", None);
        input.write_bytes(source.as_bytes());
        let output = common::short_process_output_with_timeout(
            "invalid CSV",
            std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).unwrap(),
            )),
        );
        assert_eq!(output.status.code(), Some(2), "{source:?}: {output:?}");
        assert!(output.stdout.is_empty(), "{source:?}: {output:?}");
        assert_eq!(
            output.stderr, b"invalid CSV input\n",
            "{source:?}: {output:?}"
        );
    }

    // Generate logical tables first, then vary their valid source spelling.
    // The expected output comes directly from the logical fields, independently
    // of the parser's state machine. All cases use a fixed reproducible seed.
    let dictionary = ["", "a", "a,b", "\"", "a\r\nb", "é", "🙂", " ", "\r"];
    let mut seed = 0x37a1_u32;
    for case in 0..48 {
        let columns = case % 4 + 1;
        let rows = case % 3 + 1;
        let mut source = String::new();
        let mut expected = String::new();
        for row in 0..rows {
            for column in 0..columns {
                if column > 0 {
                    source.push(',');
                    expected.push(',');
                }
                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                let field = dictionary[seed as usize % dictionary.len()];
                let quoted = format!("\"{}\"", field.replace('"', "\"\""));
                expected.push_str(&quoted);
                if case % 2 == 0 || field.is_empty() || field.contains([',', '"', '\r', '\n']) {
                    source.push_str(&quoted);
                } else {
                    source.push_str(field);
                }
            }
            expected.push_str("\r\n");
            if row + 1 < rows || case % 2 == 0 {
                source.push_str(if case % 3 == 0 { "\r\n" } else { "\n" });
            }
        }
        for spelling in [&source, &expected] {
            let input = common::TempArtifact::new("laniusc_csv", "generated", None);
            input.write_bytes(spelling.as_bytes());
            let output = common::short_process_output_with_timeout(
                "generated CSV table",
                std::process::Command::new(executable.path()).stdin(std::process::Stdio::from(
                    std::fs::File::open(input.path()).unwrap(),
                )),
            );
            assert_eq!(
                output.status.code(),
                Some(0),
                "case {case}, {spelling:?}: {output:?}"
            );
            assert_eq!(
                output.stdout,
                expected.as_bytes(),
                "case {case}, {spelling:?}: {output:?}"
            );
            assert!(output.stderr.is_empty(), "case {case}: {output:?}");
        }
    }
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn assert_all_allocations_freed(trace: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut allocations = 0;
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                let address = result.split_whitespace().next().unwrap().to_owned();
                assert!(live.insert(address), "duplicate live allocation: {line}");
                allocations += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            let address = tail.split(',').next().unwrap();
            assert!(line.ends_with(" = 0"), "deallocation failed: {line}");
            assert!(live.remove(address), "unknown/double deallocation: {line}");
        }
    }
    assert!(live.is_empty(), "allocations leaked: {live:?}\n{trace}");
    allocations
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn csv_frees_partial_results_at_every_allocation_failure() {
    use std::os::unix::fs::PermissionsExt;
    let bytes = compile("tests/fixtures/extended/csv_allocation_failure.lani");
    let executable = common::TempArtifact::new("laniusc_csv", "allocation_failure", None);
    executable.write_bytes(&bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let trace = common::TempArtifact::new("laniusc_csv", "allocations", None);
    let baseline = common::short_process_output_with_timeout(
        "CSV allocations",
        std::process::Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(executable.path()),
    );
    assert_eq!(baseline.status.code(), Some(1), "{baseline:?}");
    let events = std::fs::read_to_string(trace.path()).unwrap();
    let allocation_count = assert_all_allocations_freed(&events);
    assert!(
        allocation_count > 5,
        "fixture must exercise nested allocations: {events}"
    );
    for when in 2..=allocation_count {
        let failed = common::short_process_output_with_timeout(
            "CSV injected allocation failure",
            std::process::Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap", "-e"])
                .arg(format!("inject=mmap:error=ENOMEM:when={when}+"))
                .arg(executable.path()),
        );
        assert_eq!(
            failed.status.code(),
            Some(0),
            "allocation {when}: {failed:?}"
        );
        assert!(
            failed.stdout.is_empty() && failed.stderr.is_empty(),
            "allocation {when}: {failed:?}"
        );
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(
            events.contains("INJECTED") && events.contains("ENOMEM"),
            "{events}"
        );
        assert_all_allocations_freed(&events);
    }
}
