#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
};
fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("{path}: {e}"));
    let exe = common::TempArtifact::new("laniusc_settings", "exe", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("settings", command, std::time::Duration::from_secs(50))
}
fn clean(command: &mut Command) -> &mut Command {
    command
        .env_remove("SETTINGS_HOST")
        .env_remove("SETTINGS_PORT")
        .env_remove("SETTINGS_ENABLED")
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    if status == 0 {
        assert!(output.stderr.is_empty(), "{output:?}");
    } else {
        assert!(output.stdout.is_empty(), "{output:?}");
        assert_eq!(output.stderr, b"settings_inspect: error\n");
    }
}
fn freed(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    let mut files = std::collections::BTreeSet::new();
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let v = line.rsplit(" = ").next().unwrap();
            if v.starts_with("0x") {
                assert!(
                    live.insert(v.split_whitespace().next().unwrap().to_owned()),
                    "{events}"
                );
                count += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{events}"
            );
        } else if line.starts_with("open(") || line.starts_with("openat(") {
            if let Ok(fd) = line.rsplit(" = ").next().unwrap().parse::<i32>() {
                if fd >= 0 {
                    assert!(files.insert(fd), "{events}");
                }
            }
        } else if let Some(tail) = line.strip_prefix("close(") {
            let fd = tail.split(')').next().unwrap().parse::<i32>().unwrap();
            assert!(files.remove(&fd), "{events}");
        }
    }
    assert!(live.is_empty(), "live allocations: {events}");
    assert!(files.is_empty(), "unclosed descriptors: {events}");
    count
}
#[test]
fn typed_facade_preserves_native_values_replacement_limits_and_borrows() {
    let exe = executable("tests/fixtures/extended/settings_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_settings", "contracts", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap,write"])
        .arg(exe.path()));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(output.stdout, b"QQ");
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(freed(&events) > 10);
    let from = events.find("write(1,").unwrap();
    let through = events[from + 1..].find("write(1,").unwrap() + from + 1;
    assert!(
        !events[from..through].contains("mmap(") && !events[from..through].contains("munmap("),
        "{events}"
    );
}
#[test]
fn settings_application_matches_independent_typed_precedence_model() {
    let exe = executable("sample_programs/library/settings_inspect.lani");
    let out = run(Command::new("python3")
        .arg("tests/fixtures/extended/settings_oracle.py")
        .arg(exe.path()));
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert!(out.stderr.is_empty(), "{out:?}");
    eprint!("{}", String::from_utf8_lossy(&out.stdout));
}
#[test]
fn settings_application_releases_every_allocation_and_acquired_file_on_failure() {
    let exe = executable("sample_programs/library/settings_inspect.lani");
    let json = common::TempArtifact::new("laniusc_settings", "json", None);
    let toml = common::TempArtifact::new("laniusc_settings", "toml", None);
    json.write_bytes(b"{\"host\":\"json\",\"port\":81,\"enabled\":false,\"extra\":[1,null]}");
    toml.write_bytes(b"host='toml'\nport=82\nenabled=true\n[nested]\nx='value'\n");
    let trace = common::TempArtifact::new("laniusc_settings", "faults", None);
    let execute = |injection: Option<String>, status| {
        let mut c = Command::new("strace");
        c.args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,open,openat,close,read,write"]);
        if let Some(ref rule) = injection {
            c.arg("-e").arg(format!("inject={rule}"));
        }
        let out = run(clean(c.arg(exe.path()))
            .arg("--json")
            .arg(json.path())
            .arg("--toml")
            .arg(toml.path())
            .args(["--port", "84"])
            .env("SETTINGS_HOST", "environment")
            .env("SETTINGS_ENABLED", "false"));
        checked(&out, status);
        let events = std::fs::read_to_string(trace.path()).unwrap();
        freed(&events);
        if injection.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        events
    };
    let base = execute(None, 0);
    let count = base.lines().filter(|l| l.starts_with("mmap(")).count();
    assert!(count > 25);
    for at in 1..=count {
        execute(Some(format!("mmap:error=ENOMEM:when={at}+")), 4);
    }
    eprintln!("settings allocation failures={count}");
    let open = if base.lines().any(|l| l.starts_with("openat(")) {
        "openat"
    } else {
        "open"
    };
    for call in [open, "read", "close"] {
        let count = base
            .lines()
            .filter(|l| l.starts_with(&format!("{call}(")))
            .count();
        assert!(count > 0);
        for at in 1..=count {
            execute(Some(format!("{call}:error=EIO:when={at}")), 5);
        }
    }
    execute(Some("read:error=EINTR:when=1".into()), 0);
    // Semantic and limit failures happen after earlier sources/values are owned.
    // Check cleanup at those boundaries, not only allocation-failure exits.
    for (extra, environment, status) in [
        (vec![], Some(("SETTINGS_PORT", "invalid")), 3),
        (vec![], Some(("SETTINGS_ENABLED", "TRUE")), 3),
        (vec!["--max-output", "0"], None, 6),
        (vec!["--max-input", "1"], None, 6),
        (vec!["--max-nodes", "1"], None, 6),
    ] {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,open,openat,close,read,write"])
            .arg(exe.path())
            .arg("--json")
            .arg(json.path())
            .arg("--toml")
            .arg(toml.path())
            .args(extra);
        clean(&mut command).env("SETTINGS_HOST", "owned-before-error");
        if let Some((key, value)) = environment {
            command.env(key, value);
        }
        checked(&run(&mut command), status);
        freed(&std::fs::read_to_string(trace.path()).unwrap());
    }
    toml.write_bytes(b"x=\n");
    let out = run(clean(
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,open,openat,close,read,write"])
            .arg(exe.path()),
    )
    .arg("--json")
    .arg(json.path())
    .arg("--toml")
    .arg(toml.path()));
    checked(&out, 3);
    freed(&std::fs::read_to_string(trace.path()).unwrap());
}
#[test]
fn settings_io_retries_interruption_and_partial_output_and_reports_host_failure() {
    let exe = executable("sample_programs/library/settings_inspect.lani");
    let trace = common::TempArtifact::new("laniusc_settings", "io", None);
    for (rule, status) in [
        ("write:error=EIO:when=1", 5),
        ("write:error=EINTR:when=1", 0),
        ("write:retval=1:when=1", 0),
    ] {
        let out = run(clean(
            Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap,write", "-e"])
                .arg(format!("inject={rule}"))
                .arg(exe.path()),
        ));
        assert_eq!(out.status.code(), Some(status), "{out:?}");
        let events = std::fs::read_to_string(trace.path()).unwrap();
        freed(&events);
        assert!(events.contains("INJECTED"));
        if status == 5 {
            assert!(out.stdout.is_empty());
            assert_eq!(out.stderr, b"settings_inspect: error\n");
        } else {
            assert!(out.stderr.is_empty());
            let expected =
                b"host 6c6f63616c686f7374 source 0\nport 8080 source 0\nenabled 1 source 0\n";
            assert_eq!(
                out.stdout,
                if rule.contains("retval=1") {
                    &expected[1..]
                } else {
                    &expected[..]
                }
            );
        }
    }
    // The bounded capture helper always pipes its child stdout. Redirect the
    // native program inside a shell so /dev/full reaches the actual writer.
    let out = run(clean(
        Command::new("sh")
            .args(["-c", "exec \"$1\" > /dev/full", "settings-full"])
            .arg(exe.path()),
    ));
    assert_eq!(out.status.code(), Some(5));
    assert_eq!(out.stderr, b"settings_inspect: error\n");
    let out = run(clean(
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap,write",
                "-e",
                "inject=write:error=EIO:when=1",
            ])
            .arg(exe.path()),
    )
    .arg("--unknown"));
    assert_eq!(out.status.code(), Some(5));
    assert!(out.stdout.is_empty() && out.stderr.is_empty());
    freed(&std::fs::read_to_string(trace.path()).unwrap());
}

#[test]
fn explicit_environment_adapter_preserves_types_absence_and_limits() {
    let exe = executable("tests/fixtures/extended/settings_env_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_settings", "environment", None);
    let out = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"])
        .arg(exe.path())
        .env("SETTINGS_TEST_TEXT", "")
        .env("SETTINGS_TEST_DECIMAL", "1.2300e4")
        .env("SETTINGS_TEST_INTEGER", "-12")
        .env("SETTINGS_TEST_BOOLEAN", "false")
        .env_remove("SETTINGS_TEST_ABSENT"));
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert_eq!(out.stdout, b"E");
    assert!(out.stderr.is_empty(), "{out:?}");
    freed(&std::fs::read_to_string(trace.path()).unwrap());
}

#[test]
fn closed_output_pipes_and_signal_setup_failure_preserve_cleanup_and_status() {
    let exe = executable("sample_programs/library/settings_inspect.lani");
    let trace = common::TempArtifact::new("laniusc_settings", "broken_pipe", None);
    for closed_stderr in [false, true] {
        let (reader, writer) = std::io::pipe().unwrap();
        drop(reader);
        let mut command = Command::new("timeout");
        command
            .args(["--kill-after=1s", "5s", "strace", "-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=rt_sigaction,mmap,munmap,write"])
            .arg(exe.path());
        clean(&mut command);
        if closed_stderr {
            command.args(["--port", "0"]).stderr(writer);
        } else {
            command.stdout(writer);
        }
        // Keep the explicitly supplied anonymous pipe: the generic capture
        // helper replaces configured stdout/stderr. timeout bounds this child.
        let out = command.output().unwrap();
        assert_eq!(out.status.code(), Some(5), "{out:?}");
        assert!(out.stdout.is_empty());
        if closed_stderr {
            assert!(out.stderr.is_empty());
        } else {
            assert_eq!(out.stderr, b"settings_inspect: error\n");
        }
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(
            events.contains("EPIPE") && events.contains("SIG_IGN"),
            "{events}"
        );
        assert!(!events.contains("killed by SIGPIPE"), "{events}");
        assert!(freed(&events) > 0);
        assert!(events.find("rt_sigaction(").unwrap() < events.find("mmap(").unwrap());
    }
    let out = run(clean(
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=rt_sigaction,mmap,munmap,write",
                "-e",
                "inject=rt_sigaction:error=EPERM:when=1",
            ])
            .arg(exe.path()),
    ));
    assert_eq!(out.status.code(), Some(5), "{out:?}");
    assert!(out.stdout.is_empty() && out.stderr.is_empty());
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(events.contains("INJECTED"));
    assert_eq!(freed(&events), 0);
}
