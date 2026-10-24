//! Streaming-format preflight atomicity, leaf failures and I/O budget bounds.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Stdio},
    sync::OnceLock,
    time::Duration,
};

fn entry(name: &str) -> (PathBuf, PathBuf) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    (
        root.join("tests/fixtures/stdlib_foundation/format_write_failures")
            .join(name),
        root.join("stdlib"),
    )
}
fn executable(name: &str) -> common::TempArtifact {
    let (source, stdlib) = entry(name);
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&source, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_format_write_failure", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn preflight() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| executable("preflight.lani"))
}
fn memory_command(exe: &common::TempArtifact, trace: &common::TempArtifact) -> Command {
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap,mremap,brk"])
        .arg(exe.path());
    command
}
fn success(output: &std::process::Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[derive(Debug)]
struct Case {
    scratch: usize,
    budget: usize,
    empty: bool,
    actions: Vec<i32>,
    otherwise: i32,
}
fn cases() -> Vec<Case> {
    let mut cases = Vec::new();
    let mut add = |scratch, budget, empty, actions: &[i32], otherwise| {
        cases.push(Case {
            scratch,
            budget,
            empty,
            actions: actions.to_vec(),
            otherwise,
        });
    };
    for scratch in [1, 3, 7] {
        let exact = 17_usize.div_ceil(scratch);
        for budget in [0, exact - 1, exact, exact + 1] {
            add(scratch, budget, false, &[], 99);
        }
    }
    for scratch in [3, 7] {
        let exact = 17_usize.div_ceil(scratch);
        for budget in [exact, exact + 1] {
            add(scratch, budget, false, &[-1], 99);
        }
        for actions in [&[1, 0][..], &[1, -4], &[1, -5], &[1, -2], &[-3], &[-1, 0]] {
            add(scratch, 64, false, actions, 99);
        }
    }
    for scratch in [1, 3, 7] {
        add(scratch, 64, false, &[1, -1, 2, -1, -3], 99);
    }
    for budget in [0, 1, 3, 64] {
        add(3, budget, false, &[], -1);
    }
    for budget in [1, 2, 4] {
        add(7, budget, false, &[1], -1);
    }
    for budget in [0, 1] {
        add(1, budget, true, &[], -1);
    }
    cases
}

#[derive(Debug, PartialEq)]
struct Observation {
    status: u64,
    completed: u64,
    filled: u64,
    calls: u64,
    flushes: u64,
    requests: Vec<(u64, u64)>,
}
fn reference(case: &Case) -> Observation {
    // The expected bytes are independently fixed by the single Text argument:
    // b"headA\0\xc3\xa9\xf0\x9f\x99\x82Ztail". This model only drives the
    // public full-chunk/short-write protocol; it never parses format syntax.
    let total = if case.empty { 0 } else { 17 };
    let mut result = Observation {
        status: 0,
        completed: 0,
        filled: 0,
        calls: 0,
        flushes: 0,
        requests: Vec::new(),
    };
    while (result.completed as usize) < total {
        let chunk = case.scratch.min(total - result.completed as usize);
        let mut sent = 0;
        while sent < chunk {
            if result.calls as usize == case.budget {
                result.status = 1;
                return result;
            }
            let requested = chunk - sent;
            result.requests.push(((2 + sent) as u64, requested as u64));
            let action = case
                .actions
                .get(result.calls as usize)
                .copied()
                .unwrap_or(case.otherwise);
            result.calls += 1;
            match action {
                -1 => continue,
                -2 => result.status = 4,
                -3 => result.status = 5,
                -4 | -5 => result.status = 3,
                0 => result.status = 2,
                positive => {
                    assert!(positive > 0);
                    let accepted = requested.min(positive as usize);
                    sent += accepted;
                    result.completed += accepted as u64;
                    result.filled += accepted as u64;
                }
            }
            if result.status != 0 {
                return result;
            }
        }
    }
    result
}
fn encoded(cases: &[Case]) -> Vec<u8> {
    let mut bytes = (cases.len() as u64).to_le_bytes().to_vec();
    for case in cases {
        for word in [
            case.scratch as u64,
            case.budget as u64,
            u64::from(case.empty),
            case.actions.len() as u64,
            case.otherwise as i64 as u64,
        ] {
            bytes.extend(word.to_le_bytes());
        }
        for index in 0..8 {
            bytes.extend(
                (case.actions.get(index).copied().unwrap_or(0) as i64 as u64).to_le_bytes(),
            );
        }
    }
    bytes
}
#[test]
fn scripted_write_failures_retries_and_exact_budgets_match_confirmed_prefix_model() {
    let exe = executable("scripted.lani");
    let cases = cases();
    assert_eq!(cases.len(), 40);
    let input = common::TempArtifact::new("laniusc_format_write_failure", "input", None);
    input.write_bytes(encoded(&cases));
    let trace = common::TempArtifact::new("laniusc_format_write_failure", "model_memory", None);
    let mut command = memory_command(&exe, &trace);
    command.stdin(Stdio::from(std::fs::File::open(input.path()).unwrap()));
    let output = common::process_output_with_timeout(
        "scripted streaming-format failures",
        &mut command,
        Duration::from_secs(10),
    );
    success(&output);
    assert!(
        std::fs::read_to_string(trace.path()).unwrap().is_empty(),
        "core formatting and its scripted writer must not allocate"
    );
    assert_eq!(output.stdout.len() % 8, 0);
    let words: Vec<u64> = output
        .stdout
        .chunks_exact(8)
        .map(|word| u64::from_le_bytes(word.try_into().unwrap()))
        .collect();
    let mut words = words.into_iter();
    for (index, case) in cases.iter().enumerate() {
        let status = words.next().expect("status");
        let completed = words.next().expect("completed");
        let filled = words.next().expect("confirmed writer prefix");
        let calls = words.next().expect("leaf attempts");
        let flushes = words.next().expect("flushes");
        let requests = (0..calls)
            .map(|_| (words.next().expect("offset"), words.next().expect("count")))
            .collect();
        assert_eq!(
            Observation {
                status,
                completed,
                filled,
                calls,
                flushes,
                requests
            },
            reference(case),
            "case={index}: {case:?}"
        );
    }
    assert_eq!(words.next(), None, "no trailing diagnostic record");
}

#[test]
fn invalid_format_limits_and_scratch_preflight_leave_sources_and_writer_untouched() {
    let trace = common::TempArtifact::new("laniusc_format_write_failure", "preflight_memory", None);
    let output = common::process_output_with_timeout(
        "streaming format atomic preflight",
        &mut memory_command(preflight(), &trace),
        Duration::from_secs(10),
    );
    success(&output);
    assert!(output.stdout.is_empty(), "{output:?}");
    assert!(
        std::fs::read_to_string(trace.path()).unwrap().is_empty(),
        "preflight must not allocate"
    );
}

#[test]
fn io_limit_aborts_maximum_width_padding_after_zero_or_one_confirmed_byte() {
    let output = common::process_output_with_timeout(
        "maximum-width streaming format bounded abort",
        Command::new(preflight().path()).arg("bounded-abort"),
        Duration::from_secs(2),
    );
    success(&output);
    assert!(output.stdout.is_empty(), "{output:?}");
}

#[test]
fn owned_buffered_writer_constructor_oom_and_explicit_finish_retry_release_once() {
    let exe = executable("buffered_oom.lani");
    for when in [None, Some(1), Some(2)] {
        let trace =
            common::TempArtifact::new("laniusc_format_write_failure", "buffer_memory", None);
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,mremap,brk"]);
        if let Some(index) = when {
            command
                .arg("-e")
                .arg(format!("inject=mmap:error=ENOMEM:when={index}"));
        }
        let output = common::process_output_with_timeout(
            "streaming format buffered owner failures",
            command.arg(exe.path()),
            Duration::from_secs(10),
        );
        assert_eq!(
            output.status.code(),
            Some(if when == Some(1) { 2 } else { 0 }),
            "{output:?}"
        );
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        let events = std::fs::read_to_string(trace.path()).unwrap();
        let mut live = BTreeMap::new();
        let mut attempts = 0;
        let mut denied = 0;
        for line in events.lines() {
            if let Some(args) = line.strip_prefix("mmap(") {
                attempts += 1;
                let size: usize = args.split(',').nth(1).unwrap().trim().parse().unwrap();
                let result = line.rsplit_once(" = ").unwrap().1;
                if result.starts_with("0x") {
                    assert!(live.insert(result.to_owned(), size).is_none(), "{events}");
                } else {
                    assert!(
                        line.contains("INJECTED") && result.starts_with("-1 ENOMEM"),
                        "{events}"
                    );
                    denied += 1;
                }
            } else if let Some(args) = line.strip_prefix("munmap(") {
                let (fields, result) = args.split_once(')').unwrap();
                let (address, size) = fields.split_once(',').unwrap();
                assert_eq!(result.trim(), "= 0", "{events}");
                assert_eq!(
                    live.remove(address.trim()),
                    Some(size.trim().parse::<usize>().unwrap()),
                    "{events}"
                );
            } else {
                panic!("unexpected allocation event: {events}");
            }
        }
        assert_eq!(
            attempts, 1,
            "only the owned buffered Writer allocates: {events}"
        );
        assert_eq!(denied, usize::from(when == Some(1)), "constructor denial reached; post-construction denial intentionally unreached: {events}");
        assert!(
            live.is_empty(),
            "all allocated owners released exactly once: {events}"
        );
    }
}

#[test]
fn streaming_format_requires_the_write_trait_at_the_source_call() {
    let name = "reject_read_only_writer.lani";
    let (source, stdlib) = entry(name);
    let result = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&source, &stdlib),
        )
    });
    let error = match result {
        Err(error) => error,
        Ok(bytes) => panic!("missing Write produced {} ELF bytes", bytes.len()),
    };
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, "LNC0008", "{error}");
    let label = diagnostic
        .primary_label
        .expect("source-local writer trait rejection");
    assert!(label.path.ends_with(name), "{label:?}");
    assert!(
        label
            .source_line
            .as_deref()
            .unwrap_or("")
            .contains("core::format::write<ReadOnly>"),
        "{label:?}"
    );
}
