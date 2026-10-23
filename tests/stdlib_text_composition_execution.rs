#![cfg(all(target_os = "linux", target_arch = "x86_64"))]

mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output, Stdio},
};

fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let exe = common::TempArtifact::new("laniusc_text_composition", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn fixture(name: &str) -> common::TempArtifact {
    executable(&format!("tests/fixtures/stdlib_foundation/{name}.lani"))
}
fn run(command: &mut Command) -> Output {
    common::short_process_output_with_timeout("text composition", command)
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn ascii_space(c: char) -> bool {
    matches!(c, ' ' | '\t' | '\n' | '\x0b' | '\x0c' | '\r')
}
fn next(seed: &mut u32) -> u32 {
    *seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
    *seed
}
fn text(seed: &mut u32) -> String {
    let pool = [
        'a', '\0', 'é', '🙂', '中', '\t', ' ', '\n', '\u{a0}', '\u{2003}', '\x0b', '\x0c', '\r',
    ];
    let length = next(seed) % 9;
    (0..length)
        .map(|_| pool[next(seed) as usize % pool.len()])
        .collect()
}

#[test]
fn composition_contracts_cover_aliases_overflow_and_cursor_exhaustion() {
    let exe = fixture("text_composition");
    let output = run(&mut Command::new(exe.path()));
    checked(&output, 0);
    assert!(output.stdout.is_empty());
}

#[test]
fn joins_repeats_and_whitespace_splits_match_independent_unicode_models() {
    let exe = fixture("text_composition_input");
    let input = common::TempArtifact::new("laniusc_text_composition", "input", None);
    let mut seed = 0x5eed_2026_u32;
    for case in 0..160 {
        let prefix = text(&mut seed);
        let separator = text(&mut seed);
        let count = next(&mut seed) as usize % 13;
        let parts: Vec<String> = (0..count).map(|_| text(&mut seed)).collect();
        for opcode in 0..5_u8 {
            let repetitions = next(&mut seed) as usize % 33;
            let amount = if matches!(opcode, 0 | 2) {
                count
            } else {
                repetitions
            };
            let mut request = vec![
                opcode,
                amount as u8,
                prefix.len() as u8,
                separator.len() as u8,
            ];
            request.extend_from_slice(prefix.as_bytes());
            request.extend_from_slice(separator.as_bytes());
            if matches!(opcode, 0 | 2) {
                for part in &parts {
                    request.push(part.len() as u8);
                    request.extend_from_slice(part.as_bytes());
                }
            }
            let expected = match opcode {
                0 => parts.join(&separator),
                1 => separator.repeat(repetitions),
                2 => format!("{prefix}{}", parts.join(&separator)),
                3 => format!("{prefix}{}", separator.repeat(repetitions)),
                4 => prefix
                    .split(ascii_space)
                    .filter(|part| !part.is_empty())
                    .collect::<Vec<_>>()
                    .join(&separator),
                _ => unreachable!(),
            };
            input.write_bytes(&request);
            let output = run(Command::new(exe.path())
                .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
            checked(&output, 0);
            assert_eq!(output.stdout, expected.as_bytes(), "seed=0x5eed2026 case={case} opcode={opcode} prefix={prefix:?} separator={separator:?} parts={parts:?}");
        }
    }
}

// Track successful allocations, not syscall count: fault injection can skip mmap.
fn freed(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let value = line.rsplit(" = ").next().unwrap();
            if value.starts_with("0x") {
                assert!(
                    live.insert(value.split_whitespace().next().unwrap().to_owned()),
                    "{events}"
                );
                count += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{events}"
            );
        }
    }
    assert!(live.is_empty(), "leaked allocations: {events}");
    count
}

#[test]
fn every_composition_allocation_failure_preserves_owners_and_frees_storage() {
    let exe = fixture("text_composition_failure");
    let trace = common::TempArtifact::new("laniusc_text_composition", "trace", None);
    let execute = |when: Option<usize>| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if let Some(when) = when {
            command
                .arg("-e")
                .arg(format!("inject=mmap:error=ENOMEM:when={when}+"));
        }
        let output = run(command.arg(exe.path()));
        checked(&output, 0);
        assert!(output.stdout.is_empty());
        let events = std::fs::read_to_string(trace.path()).unwrap();
        if when.is_some() {
            assert!(
                events.contains("INJECTED") && events.contains("ENOMEM"),
                "{events}"
            );
        }
        freed(&events)
    };
    let allocations = execute(None);
    assert!(
        allocations >= 6,
        "fixture must grow the aliased owner for each edit"
    );
    for when in 1..=allocations {
        execute(Some(when));
    }
}

fn normalize(source: &str, indent: usize) -> Vec<u8> {
    let words: Vec<_> = source
        .split(ascii_space)
        .filter(|word| !word.is_empty())
        .collect();
    if words.is_empty() {
        vec![]
    } else {
        format!("{}{}\n", " ".repeat(indent), words.join(" ")).into_bytes()
    }
}

#[test]
fn normalizer_executes_limits_validation_allocation_and_partial_io_failures() {
    let exe = executable("sample_programs/normalize_words.lani");
    let input = common::TempArtifact::new("laniusc_text_composition", "stdin", None);
    let execute = |data: &[u8], args: &[&str]| {
        input.write_bytes(data);
        run(Command::new(exe.path())
            .args(args)
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())))
    };
    for source in [
        "",
        " \t\n\r\x0b\x0c ",
        "hello",
        " \t hello  world \r\n",
        "é\x0b🙂 \0\u{a0}\u{2003}中",
        "\n\n a \n b \n",
    ] {
        for indent in [0, 1, 8, 256] {
            let output = execute(source.as_bytes(), &[&indent.to_string()]);
            checked(&output, 0);
            assert_eq!(
                output.stdout,
                normalize(source, indent),
                "{source:?}, {indent}"
            );
        }
    }
    let output = execute(b" a   b ", &[]);
    checked(&output, 0);
    assert_eq!(output.stdout, b"a b\n");
    for args in [
        vec!["-1"],
        vec!["257"],
        vec![""],
        vec!["1a"],
        vec!["1000"],
        vec!["1", "2"],
    ] {
        let output = execute(b"valid", &args);
        checked(&output, 2);
        assert!(output.stdout.is_empty());
    }
    for data in [
        vec![0xff],
        vec![0xed, 0xa0, 0x80],
        vec![0xc3],
        vec![b'a'; 1_048_577],
    ] {
        let output = execute(&data, &[]);
        checked(&output, 2);
        assert!(output.stdout.is_empty());
    }
    let source = "a".repeat(1_048_576);
    let output = execute(source.as_bytes(), &["256"]);
    checked(&output, 0);
    assert_eq!(output.stdout, normalize(&source, 256));
    for (words, status) in [(65536, 0), (65537, 2)] {
        let source = " a ".repeat(words);
        let output = execute(source.as_bytes(), &[]);
        checked(&output, status);
        if status == 0 {
            assert_eq!(output.stdout, normalize(&source, 0));
        } else {
            assert!(output.stdout.is_empty());
        }
    }
    let source = " α  beta \t\0🙂\n".repeat(200);
    let expected = normalize(&source, 3);
    input.write_bytes(source.as_bytes());
    let trace = common::TempArtifact::new("laniusc_text_composition", "normalizer_trace", None);
    let traced = |injection: Option<String>, status: i32, prefix: usize| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,read,write"]);
        if let Some(injection) = &injection {
            command.arg("-e").arg(format!("inject={injection}"));
        }
        let output = run(command
            .arg(exe.path())
            .arg("3")
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
        checked(&output, status);
        assert_eq!(output.stdout, expected[..prefix]);
        let events = std::fs::read_to_string(trace.path()).unwrap();
        if injection.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        freed(&events)
    };
    let allocations = traced(None, 0, expected.len());
    for when in 1..=allocations {
        traced(Some(format!("mmap:error=ENOMEM:when={when}+")), 4, 0);
    }
    for (injection, status, prefix) in [
        ("read:error=EINTR:when=2", 0, expected.len()),
        ("write:error=EINTR:when=2", 0, expected.len()),
        ("read:error=EIO:when=2", 3, 0),
        ("read:error=EAGAIN:when=1", 3, 0),
        ("write:error=EIO:when=2", 3, 1024),
        ("write:retval=0:when=2", 3, 1024),
    ] {
        traced(Some(injection.to_owned()), status, prefix);
    }
}
