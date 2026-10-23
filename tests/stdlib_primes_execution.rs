#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::{ffi::OsStrExt, fs::PermissionsExt},
    process::{Command, Output},
    time::{Duration, Instant},
};

fn executable() -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/primes.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("primes", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("primes: {e}"));
    let exe = common::TempArtifact::new("laniusc_primes", "executable", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("primes", command, Duration::from_secs(20))
}

fn invoke(exe: &common::TempArtifact, args: &[&str]) -> Output {
    run(Command::new(exe.path()).args(args))
}

fn success(output: &Output, expected: &[u8]) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(output.stdout, expected, "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

fn failure(output: &Output, status: i32, reason: &str) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stdout.is_empty(), "{output:?}");
    assert_eq!(output.stderr, format!("primes: {reason}\n").as_bytes());
}

// Deliberately use trial division, independently of the program's sieve.
fn primes(limit: u32) -> Vec<u32> {
    (2..=limit)
        .filter(|n| (2..).take_while(|d| d * d <= *n).all(|d| n % d != 0))
        .collect()
}

#[test]
fn primes_matches_trial_division_and_checks_cli_output_boundaries() {
    let exe = executable();
    let mut limits = vec![
        0, 1, 2, 3, 4, 8, 9, 15, 16, 24, 25, 31, 32, 33, 48, 49, 63, 64, 65, 120, 121, 127, 128,
        129, 255, 256, 257, 1023, 1024, 1025, 10_000,
    ];
    let mut state = 0x719e_ae91u32;
    for _ in 0..32 {
        state = state.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        limits.push(state % 2048);
    }
    for limit in limits {
        let number = limit.to_string();
        let wanted = primes(limit);
        let listing: String = wanted.iter().map(|n| format!("{n}\n")).collect();
        success(
            &invoke(&exe, &[&number]),
            format!("{}\n", wanted.len()).as_bytes(),
        );
        success(&invoke(&exe, &["--list", &number]), listing.as_bytes());
        success(
            &invoke(
                &exe,
                &[
                    &number,
                    "-l",
                    "--max-output-bytes",
                    &listing.len().to_string(),
                ],
            ),
            listing.as_bytes(),
        );
        if !listing.is_empty() {
            failure(
                &invoke(
                    &exe,
                    &[
                        "--list",
                        &number,
                        "--max-output-bytes",
                        &(listing.len() - 1).to_string(),
                    ],
                ),
                2,
                "output-limit",
            );
        }
    }
    success(&invoke(&exe, &["0", "--max-output-bytes=2"]), b"0\n");
    failure(
        &invoke(&exe, &["0", "--max-output-bytes=1"]),
        2,
        "output-limit",
    );
    success(&invoke(&exe, &["--list", "1", "--max-output-bytes=0"]), b"");
    for args in [
        vec![],
        vec!["-1"],
        vec!["--", "-1"],
        vec!["+1"],
        vec!["1.0"],
        vec![""],
        vec!["20000001"],
        vec!["18446744073709551616"],
        vec!["2", "3"],
        vec!["--list=yes", "2"],
        vec!["--bad", "2"],
        vec!["--max-output-bytes"],
        vec!["--max-output-bytes=-1", "2"],
        vec!["--max-output-bytes=67108865", "2"],
        vec!["--max-output-bytes=+1", "2"],
        vec!["--help=yes"],
    ] {
        failure(&invoke(&exe, &args), 2, "invalid-arguments");
    }
    failure(&invoke(&exe, &vec!["--list"; 17]), 2, "invalid-arguments");
    failure(&invoke(&exe, &[&"0".repeat(4097)]), 2, "invalid-arguments");
    failure(
        &run(Command::new(exe.path()).arg(std::ffi::OsStr::from_bytes(b"\xff"))),
        2,
        "invalid-arguments",
    );
    success(
        &invoke(&exe, &["-h"]),
        b"Usage: primes [-l|--list] [--max-output-bytes N] LIMIT\n",
    );
    success(&invoke(&exe, &["--", "2"]), b"1\n");
}

#[test]
fn primes_executes_at_million_bit_scale_and_at_the_supported_limit() {
    let exe = executable();
    for (limit, count) in [(1_000_000, 78_498), (20_000_000, 1_270_607)] {
        let started = Instant::now();
        success(
            &invoke(&exe, &[&limit.to_string()]),
            format!("{count}\n").as_bytes(),
        );
        eprintln!(
            "primes: limit={limit}, count={count}, {:.3}ms native process and I/O, compilation excluded",
            started.elapsed().as_secs_f64() * 1000.0
        );
    }
}

fn no_leaks(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut allocations = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                assert!(
                    live.insert(result.split_whitespace().next().unwrap().to_owned()),
                    "{events}"
                );
                allocations += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{events}"
            );
        }
    }
    assert!(live.is_empty(), "unreleased owners: {events}");
    allocations
}

#[test]
fn primes_releases_owners_on_all_observed_allocation_and_write_failures() {
    let exe = executable();
    let trace = common::TempArtifact::new("laniusc_primes", "trace", None);
    let expected = b"2\n3\n5\n7\n11\n13\n17\n19\n23\n29\n31\n";
    let execute = |fault: Option<&str>| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,read,write"]);
        if let Some(fault) = fault {
            command.arg("-e").arg(format!("inject={fault}"));
        }
        let output = run(command.arg(exe.path()).args(["--list", "33"]));
        let events = std::fs::read_to_string(trace.path()).unwrap();
        no_leaks(&events);
        if fault.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        (output, events)
    };
    let (baseline, events) = execute(None);
    success(&baseline, expected);
    assert!(!events.lines().any(|l| l.starts_with("read(")), "{events}");
    let allocations = no_leaks(&events);
    assert!(allocations >= 3, "{events}");
    for when in 1..=allocations {
        failure(
            &execute(Some(&format!("mmap:error=ENOMEM:when={when}"))).0,
            4,
            "allocation-failure",
        );
    }
    let writes = events.lines().filter(|l| l.starts_with("write(")).count();
    assert_eq!(writes, 11);
    for when in 1..=writes {
        for fault in [
            format!("write:error=EIO:when={when}"),
            format!("write:retval=0:when={when}"),
        ] {
            let (output, _) = execute(Some(&fault));
            assert_eq!(output.status.code(), Some(3), "{output:?}");
            assert_eq!(output.stderr, b"primes: io-failure\n");
            assert!(expected.starts_with(&output.stdout));
        }
    }
    success(&execute(Some("write:error=EINTR:when=1")).0, expected);
    // strace retval injection reports a positive short write without actually
    // transmitting that byte. The writer must resume after the reported byte.
    success(&execute(Some("write:retval=1:when=1")).0, &expected[1..]);
    failure(
        &run(Command::new("sh")
            .args(["-c", "exec \"$1\" 100 >/dev/full", "primes"])
            .arg(exe.path())),
        3,
        "io-failure",
    );
    let diagnostic = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=mmap,munmap,write",
            "-e",
            "inject=write:error=EIO:when=1",
        ])
        .arg(exe.path())
        .arg("--bad"));
    assert_eq!(diagnostic.status.code(), Some(3));
    assert!(diagnostic.stdout.is_empty() && diagnostic.stderr.is_empty());
    no_leaks(&std::fs::read_to_string(trace.path()).unwrap());
}
