#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
    time::Duration,
};
fn executable() -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/uri_resolve.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("uri-resolve program", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("uri-resolve program: {e}"));
    let exe = common::TempArtifact::new("laniusc_uri_resolve_program", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("uri-resolve program", command, Duration::from_secs(5))
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn invoke(exe: &common::TempArtifact, args: &[&str], status: i32, expected: &[u8]) {
    let output = run(Command::new(exe.path()).args(args));
    checked(&output, status);
    assert_eq!(output.stdout, expected, "args={args:?}");
}
#[test]
fn uri_resolve_program_combines_cli_relative_resolution_and_encoded_output() {
    let exe = executable();
    invoke(
        &exe,
        &[
            "https://example.test/a/b?old",
            "",
            "../c",
            "?",
            "?q=x#f",
            "//other.test/x",
            "https:g",
            "%2e/%2f",
            "-x",
        ],
        2,
        b"",
    );
    invoke(&exe,&["--","https://example.test/a/b?old","","../c","?","?q=x#f","//other.test/x","https:g","%2e/%2f","-x"],0,
        b"https://example.test/a/b?old\nhttps://example.test/c\nhttps://example.test/a/b?\nhttps://example.test/a/b?q=x#f\nhttps://other.test/x\nhttps:g\nhttps://example.test/a/%2e/%2f\nhttps://example.test/a/-x\n");
    // Last numeric option applies to all references, including ones before it.
    invoke(
        &exe,
        &["--max-bytes=0", "s:/a/b", "c", "--max-bytes=6"],
        0,
        b"s:/a/c\n",
    );
    invoke(&exe, &["-n6", "s:/a/b", "c", "long"], 2, b"s:/a/c\n");
    invoke(&exe, &["--max-bytes=2", "s:", ""], 0, b"s:\n");
    invoke(&exe, &["--max-bytes=1", "s:", ""], 2, b"");
    let long = "a".repeat(64000);
    let expected = format!("https://example.test/a/{long}\n");
    invoke(
        &exe,
        &["https://example.test/a/b", &long],
        0,
        expected.as_bytes(),
    );
    let mut many = vec!["s:/a/b"];
    many.extend(vec!["c"; 1025]);
    invoke(&exe, &many, 0, "s:/a/c\n".repeat(1025).as_bytes());
}
#[test]
fn uri_resolve_program_validates_all_syntax_before_emitting_results() {
    let exe = executable();
    for args in [
        vec![],
        vec!["s:/a"],
        vec!["/relative", "x"],
        vec!["s:/a#", "x"],
        vec!["s:/a#frag", "x"],
        vec!["s:/a", "x", "%GG"],
        vec!["s:/a", "x", "--unknown"],
        vec!["s:/a", "x", "--max-bytes=-1"],
        vec!["--max-bytes=2147483648", "s:/a", "x"],
        vec!["--max-bytes"],
        vec!["--help", "--unknown"],
    ] {
        invoke(&exe, &args, 2, b"");
    }
    invoke(&exe,&["--help"],0,b"Usage: uri-resolve [--max-bytes N] [--] BASE REF...\nBASE must have a scheme and no fragment. Output is one encoded URI per line.\n");
    let mut many = vec!["s:/a"];
    many.extend(vec!["x"; 1026]);
    invoke(&exe, &many, 2, b"");
    let long = "a".repeat(65536);
    invoke(&exe, &["s:", &long], 2, b"");
}
fn allocations_without_leaks(events: &str) -> usize {
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
    assert!(live.is_empty(), "{events}");
    count
}
#[test]
fn uri_resolve_program_cleans_partial_results_on_allocation_and_output_failures() {
    let exe = executable();
    let trace = common::TempArtifact::new("laniusc_uri_resolve_program", "trace", None);
    let long = "a".repeat(2500);
    let expected =
        format!("http://example.test/a/c\nhttp://example.test/a/{long}\nhttp://example.test/a/b\n")
            .into_bytes();
    let execute = |injection: Option<&str>, status| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,write"]);
        if let Some(injection) = injection {
            command.arg("-e").arg(format!("inject={injection}"));
        }
        let output = run(command
            .arg(exe.path())
            .args(["http://example.test/a/b", "c", &long, ""]));
        checked(&output, status);
        assert!(expected.starts_with(&output.stdout), "{output:?}");
        let events = std::fs::read_to_string(trace.path()).unwrap();
        if injection.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        let count = allocations_without_leaks(&events);
        (output, count, events)
    };
    let (output, count, events) = execute(None, 0);
    assert_eq!(output.stdout, expected);
    assert!(count >= 3, "{events}");
    for when in 1..=count {
        execute(Some(&format!("mmap:error=ENOMEM:when={when}")), 4);
    }
    let writes = events.lines().filter(|s| s.starts_with("write(")).count();
    assert!(writes > 3, "{events}");
    for when in 1..=writes {
        execute(Some(&format!("write:error=EIO:when={when}")), 3);
    }
    for injection in ["write:error=EAGAIN:when=1", "write:retval=0:when=1"] {
        execute(Some(injection), 3);
    }
    let (output, _, _) = execute(Some("write:error=EINTR:when=1"), 0);
    assert_eq!(output.stdout, expected);
}
