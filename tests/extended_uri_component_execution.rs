#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    ffi::OsString,
    os::unix::{ffi::OsStringExt, fs::PermissionsExt},
    process::{Command, Output},
    time::Duration,
};
fn executable() -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/uri_component.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("uri-component", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("uri-component: {e}"));
    let exe = common::TempArtifact::new("laniusc_uri_component", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("uri-component", command, Duration::from_secs(5))
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
fn uri_component_extracts_encoded_fields_absence_and_arbitrary_decoded_bytes() {
    let exe = executable();
    let uri = "sChEmE://u:p@Example.COM:65536/a%20b/%2F?q=hello+world%00#%252F";
    for (field, raw, decoded) in [
        ("scheme", "sChEmE".as_bytes(), "sChEmE".as_bytes()),
        (
            "authority",
            b"u:p@Example.COM:65536".as_slice(),
            b"u:p@Example.COM:65536".as_slice(),
        ),
        ("userinfo", b"u:p".as_slice(), b"u:p".as_slice()),
        ("host", b"Example.COM".as_slice(), b"Example.COM".as_slice()),
        ("port", b"65536".as_slice(), b"65536".as_slice()),
        ("path", b"/a%20b/%2F".as_slice(), b"/a b//".as_slice()),
        (
            "query",
            b"q=hello+world%00".as_slice(),
            b"q=hello+world\0".as_slice(),
        ),
        ("fragment", b"%252F".as_slice(), b"%2F".as_slice()),
    ] {
        invoke(&exe, &[field, uri], 0, raw);
        invoke(&exe, &["--decode", field, uri], 0, decoded);
    }
    for (field, uri, status, expected) in [
        ("path", "", 0, b"".as_slice()),
        ("scheme", "a/b", 1, b"".as_slice()),
        ("authority", "/", 1, b"".as_slice()),
        ("query", "/", 1, b"".as_slice()),
        ("query", "?", 0, b"".as_slice()),
        ("fragment", "#", 0, b"".as_slice()),
        ("authority", "//", 0, b"".as_slice()),
        ("host", "//", 0, b"".as_slice()),
        ("userinfo", "//", 1, b"".as_slice()),
        ("userinfo", "//@:", 0, b"".as_slice()),
        ("port", "//@:", 0, b"".as_slice()),
        ("path", "../a/./b", 0, b"../a/./b".as_slice()),
        ("host", "//[2001:db8::1]:80", 0, b"[2001:db8::1]".as_slice()),
        ("host", "//[v1.Foo:bar]", 0, b"[v1.Foo:bar]".as_slice()),
    ] {
        invoke(&exe, &[field, uri], status, expected);
    }
    invoke(&exe, &["path", "--", "-a"], 0, b"-a");
    let all: String = (0..256).map(|b| format!("%{b:02X}")).collect();
    let expected: Vec<u8> = (0..=255).collect();
    invoke(&exe, &["-d", "path", &all], 0, &expected);
    invoke(
        &exe,
        &["-d", "query", "?literal+plus=%2b"],
        0,
        b"literal+plus=+",
    );
    // Count field bytes as well as URI bytes at the snapshot's exact limit.
    // Native writes and decoded storage must handle many descriptor chunks.
    for length in [255, 1023, 1024, 1025, 16384, 65532] {
        let path = "a".repeat(length);
        invoke(&exe, &["path", &path], 0, path.as_bytes());
        let decoded_input_length = length.min(65530);
        let encoded = format!("{}%2F", "a".repeat(decoded_input_length - 3));
        let decoded = format!("{}/", "a".repeat(decoded_input_length - 3));
        invoke(&exe, &["-d", "path", &encoded], 0, decoded.as_bytes());
    }
}

#[test]
fn uri_component_rejects_invalid_arguments_and_references_before_output() {
    let exe = executable();
    for args in [
        vec![],
        vec!["path"],
        vec!["unknown", "/"],
        vec!["path", "/", "/"],
        vec!["--bad", "path", "/"],
        vec!["--decode=yes", "path", "/"],
        vec!["path", "http://h:port"],
        vec!["path", "a%"],
        vec!["path", "%GG"],
        vec!["path", "a b"],
        vec!["path", "a\\b"],
        vec!["path", "//[fe80::1%25eth0]"],
        vec!["path", "//[:::]"],
        vec!["path", "1:a"],
        vec!["--help", "--bad"],
    ] {
        invoke(&exe, &args, 2, b"");
    }
    invoke(&exe,&["--help"],0,b"Usage: uri-component [--decode] [--] FIELD URI\nFields: scheme authority userinfo host port path query fragment\n");
    let output = run(Command::new(exe.path())
        .arg("path")
        .arg(OsString::from_vec(vec![255])));
    checked(&output, 2);
    assert!(output.stdout.is_empty());
    let too_big = "a".repeat(65536);
    invoke(&exe, &["path", &too_big], 2, b"");
    let too_many = vec!["-d"; 17];
    invoke(&exe, &too_many, 2, b"");
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
fn uri_component_releases_all_owners_on_allocation_and_output_failures() {
    let exe = executable();
    let trace = common::TempArtifact::new("laniusc_uri_component", "trace", None);
    let text = "%41".repeat(2500);
    let expected = vec![b'A'; 2500];
    let execute = |injection: Option<&str>, status| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,write"]);
        if let Some(injection) = injection {
            command.arg("-e").arg(format!("inject={injection}"));
        }
        let output = run(command.arg(exe.path()).args(["--decode", "path", &text]));
        checked(&output, status);
        assert!(expected.starts_with(&output.stdout));
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
    assert_eq!(writes, 3, "{events}");
    for when in 1..=writes {
        execute(Some(&format!("write:error=EIO:when={when}")), 3);
    }
    for injection in ["write:error=EAGAIN:when=1", "write:retval=0:when=1"] {
        execute(Some(injection), 3);
    }
    let (output, _, _) = execute(Some("write:error=EINTR:when=1"), 0);
    assert_eq!(output.stdout, expected);
}
