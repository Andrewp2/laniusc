mod common;
use laniusc_compiler::compiler::{compile_entry_to_x86_64_with_source_roots, EntrySourceRoots};
fn executable(name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/extended/{name}.lani"));
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let file = common::TempArtifact::new("laniusc_csv_stream", name, None);
    file.write_bytes(&bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn records(rows: &[Vec<String>]) -> Vec<u8> {
    let mut out = Vec::new();
    for row in rows {
        out.extend_from_slice(format!("R{}:", row.len()).as_bytes());
        for field in row {
            out.extend_from_slice(format!("{}:", field.len()).as_bytes());
            out.extend_from_slice(field.as_bytes());
        }
        out.push(b'\n');
    }
    out
}
fn success(rows: &[Vec<String>], length: usize) -> Vec<u8> {
    let mut out = records(rows);
    out.extend_from_slice(format!("E{}:{length}\n", rows.len()).as_bytes());
    out
}
#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn streaming_csv_handles_chunks_eof_errors_and_utf8_boundaries() {
    let exe = executable("csv_stream_input");
    let input = common::TempArtifact::new("laniusc_csv_stream", "input", None);
    let check = |source: &[u8], chunks: &[u8], options: [u8; 5], status: i32, expected: &[u8]| {
        assert!(chunks.len() <= 255);
        let mut payload = options.to_vec();
        payload.push(chunks.len() as u8);
        payload.extend_from_slice(chunks);
        payload.extend_from_slice(source);
        input.write_bytes(&payload);
        let output = common::short_process_output_with_timeout(
            "streaming CSV",
            std::process::Command::new(exe.path()).stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).unwrap(),
            )),
        );
        assert_eq!(
            output.status.code(),
            Some(status),
            "source={source:?} chunks={chunks:?} options={options:?}: {output:?}"
        );
        assert_eq!(
            output.stdout, expected,
            "source={source:?} chunks={chunks:?} options={options:?}"
        );
        assert!(output.stderr.is_empty(), "{output:?}");
    };
    let defaults = [3, 255, 255, 255, 255];
    let cases: Vec<(&str, Vec<Vec<&str>>)> = vec![
        ("", vec![]),
        ("\n", vec![vec![""]]),
        ("\r\n", vec![vec![""]]),
        (",", vec![vec!["", ""]]),
        ("a,\r\n", vec![vec!["a", ""]]),
        ("\"\"", vec![vec![""]]),
        ("\"\"\"\"", vec![vec!["\""]]),
        ("a,b\r\nc,d", vec![vec!["a", "b"], vec!["c", "d"]]),
        ("\"é\",\"🙂\"\r\n", vec![vec!["é", "🙂"]]),
        ("\"a\r\nb\",\"c\"\"d\"\n", vec![vec!["a\r\nb", "c\"d"]]),
        (
            "\u{80},\u{7ff},\u{800},\u{d7ff},\u{e000},\u{ffff},\u{10000},\u{10ffff}",
            vec![vec![
                "\u{80}",
                "\u{7ff}",
                "\u{800}",
                "\u{d7ff}",
                "\u{e000}",
                "\u{ffff}",
                "\u{10000}",
                "\u{10ffff}",
            ]],
        ),
    ];
    for (source, rows) in cases {
        let rows: Vec<Vec<String>> = rows
            .into_iter()
            .map(|row| row.into_iter().map(str::to_owned).collect())
            .collect();
        let expected = success(&rows, source.len());
        for split in 0..=source.len() {
            check(source.as_bytes(), &[split as u8, 0], defaults, 0, &expected);
        }
        check(
            source.as_bytes(),
            &vec![1; source.len()],
            defaults,
            0,
            &expected,
        );
    }
    let mut seed = 0xc5a5_2026_u32;
    let dictionary = ["", "a", "a,b", "\"", "a\r\nb", "é🙂", " ", "\r"];
    for case in 0..48 {
        let mut source = String::new();
        let mut rows = Vec::new();
        for r in 0..(case % 4 + 1) {
            let mut row = Vec::new();
            for column in 0..(case % 5 + 1) {
                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                let value = dictionary[(seed >> 8) as usize % dictionary.len()];
                if column > 0 {
                    source.push(',');
                }
                let quote =
                    case % 2 == 0 || value.is_empty() || value.contains([',', '"', '\r', '\n']);
                if quote {
                    source.push_str(&format!("\"{}\"", value.replace('"', "\"\"")));
                } else {
                    source.push_str(value);
                }
                row.push(value.to_owned());
            }
            rows.push(row);
            if r < case % 4 || case % 2 == 0 {
                source.push_str(if case % 3 == 0 { "\r\n" } else { "\n" });
            }
        }
        let expected = success(&rows, source.len());
        let chunks: Vec<u8> = (0..source.len().min(200))
            .map(|_| {
                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                ((seed >> 24) % 11) as u8
            })
            .collect();
        check(source.as_bytes(), &chunks, defaults, 0, &expected);
        check(source.as_bytes(), &[], defaults, 0, &expected);
    }
    let failures: Vec<(&[u8], [u8; 5], &[u8])> = vec![
        (b"a\"b", defaults, b"X1:1\n"),
        (b"\"a", defaults, b"X2:0\n"),
        (b"\"a\"x", defaults, b"X3:3\n"),
        (b"a\rb", defaults, b"X4:1\n"),
        (b"a\r", defaults, b"X4:1\n"),
        (b"a\n", [2, 255, 255, 255, 255], b"X4:1\n"),
        (b"a\t", defaults, b"X5:1\n"),
        (b"\"a\0\"", defaults, b"X5:2\n"),
        (b"\x7f", defaults, b"X5:0\n"),
        (b"\xff", defaults, b"X6:0\n"),
        (b"a\xed\xa0\x80", defaults, b"X6:1\n"),
        (b"\"\xf0\x9f", defaults, b"X6:1\n"),
        (b"\xf4\x90\x80\x80", defaults, b"X6:0\n"),
        (b"\xc0\x80", defaults, b"X6:0\n"),
        (b"\xe0\x9f\xbf", defaults, b"X6:0\n"),
        (b"\xc2x", defaults, b"X6:0\n"),
        (b"a,b\nc", defaults, b"R2:1:a1:b\nX7:1\n"),
        (b"a\nb\"c", defaults, b"R1:1:a\nX1:3\n"),
        (b"a", [3, 0, 255, 255, 255], b"X8:0\n"),
        (b"a,b", [3, 255, 1, 255, 255], b"X8:3\n"),
        (b"\"ab\"", [3, 255, 255, 1, 255], b"X8:2\n"),
        (b"a,b,c", [3, 255, 255, 255, 2], b"X8:4\n"),
        (b"a", [3, 255, 0, 255, 255], b"X15:0\n"),
    ];
    for (source, options, expected) in failures {
        for split in 0..=source.len() {
            check(source, &[split as u8, 0], options, 2, expected);
        }
        check(source, &vec![1; source.len()], options, 2, expected);
    }
    check(
        b"a\nb",
        &[2, 0],
        [3, 1, 255, 255, 255],
        2,
        b"R1:1:a\nX8:2\n",
    );
    check(
        b"a,b",
        &[1, 1],
        [3, 255, 255, 255, 2],
        0,
        b"R2:1:a1:b\nE1:3\n",
    );
    check(
        b"\"\"\"\"",
        &[1, 1, 1],
        [3, 255, 255, 1, 1],
        0,
        b"R1:1:\"\nE1:4\n",
    );
    check("é".as_bytes(), &[1], [3, 255, 255, 1, 255], 2, b"X8:1\n");
    check(
        "é".as_bytes(),
        &[1],
        [3, 255, 255, 2, 2],
        0,
        "R1:2:é\nE1:2\n".as_bytes(),
    );
    check(
        b"a\r\n",
        &[2],
        [2, 255, 255, 255, 255],
        0,
        b"R1:1:a\nE1:3\n",
    );
    check(b"", &[], [3, 0, 1, 0, 0], 0, b"E0:0\n");
    check(b",\n", &[1, 0, 1], [3, 1, 2, 0, 0], 0, b"R2:0:0:\nE1:2\n");
    check(
        b"a\nb,c",
        &[2, 1],
        [1, 255, 255, 255, 255],
        0,
        b"R1:1:a\nR2:1:b1:c\nE2:5\n",
    );
}

fn assert_freed(trace: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut allocations = 0;
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                assert!(
                    live.insert(result.split_whitespace().next().unwrap().to_owned()),
                    "{line}"
                );
                allocations += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{line}"
            );
        }
    }
    assert!(live.is_empty(), "leaked {live:?}\n{trace}");
    allocations
}
#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn streaming_csv_transfers_records_and_reuses_buffers_without_allocating() {
    let contracts = executable("csv_stream_contracts");
    let contract_trace = common::TempArtifact::new("laniusc_csv_stream", "contract_trace", None);
    let output = common::short_process_output_with_timeout(
        "CSV stream ownership",
        std::process::Command::new("strace")
            .args(["-qq", "-o"])
            .arg(contract_trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(contracts.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    assert_freed(&std::fs::read_to_string(contract_trace.path()).unwrap());
    let exe = executable("csv_stream_reuse");
    let trace = common::TempArtifact::new("laniusc_csv_stream", "reuse_trace", None);
    let output = common::process_output_with_timeout(
        "CSV reuse",
        std::process::Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,write"])
            .arg(exe.path()),
        std::time::Duration::from_secs(2),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(output.stderr, b"warm\n");
    assert!(output.stdout.is_empty());
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(assert_freed(&events) > 0);
    let (_, after) = events
        .split_once("warm\\n")
        .expect("fixture emits warm-up marker");
    assert!(
        !after.contains("mmap("),
        "repeated records allocated after warm-up: {events}"
    );
}
#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn streaming_csv_cleans_up_and_resets_after_every_failed_allocation() {
    let exe = executable("csv_stream_allocation_failure");
    let trace = common::TempArtifact::new("laniusc_csv_stream", "fault_trace", None);
    let run = |when: Option<usize>| {
        let mut command = std::process::Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if let Some(n) = when {
            command
                .arg("-e")
                .arg(format!("inject=mmap:error=ENOMEM:when={n}+"));
        }
        command.arg(exe.path());
        let output =
            common::short_process_output_with_timeout("CSV stream allocation", &mut command);
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert_eq!(
            output.status.code(),
            Some(if when.is_some() { 0 } else { 1 }),
            "{when:?}: {output:?}\n{events}"
        );
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        if when.is_some() {
            assert!(events.contains("INJECTED"));
        }
        assert_freed(&events)
    };
    let count = run(None);
    assert!(count > 0);
    for when in 1..=count {
        run(Some(when));
    }
}
