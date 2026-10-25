#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
    time::Duration,
};
fn executable() -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/address_filter.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout("address-filter", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("{e}"));
    let exe = common::TempArtifact::new("laniusc_address_filter", "exe", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(exe: &common::TempArtifact, args: &[&str], input: &[u8], injection: Option<&str>) -> Output {
    let data = common::TempArtifact::new("laniusc_address_filter", "stdin", None);
    data.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_address_filter", "trace", None);
    let mut c = Command::new("strace");
    c.args(["-qq", "-o"]).arg(trace.path()).args([
        "-e",
        if injection.is_some() {
            "trace=mmap,munmap,read,write"
        } else {
            "trace=mmap,munmap"
        },
        "-e",
        "inject=mmap:error=ENOMEM:when=1+",
    ]);
    if let Some(injection) = injection {
        c.args(["-e", injection]);
    }
    c.arg(exe.path())
        .args(args)
        .stdin(std::fs::File::open(data.path()).unwrap());
    let out = common::process_output_with_timeout(
        "address-filter native runtime",
        &mut c,
        Duration::from_secs(15),
    );
    let traced = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        !traced.contains("mmap(") && !traced.contains("munmap("),
        "{traced}"
    );
    if injection.is_some() {
        assert!(
            traced.contains("INJECTED"),
            "fault must actually execute: {traced}"
        );
    } else {
        assert!(traced.is_empty());
    }
    out
}
fn good(exe: &common::TempArtifact, args: &[&str], input: &[u8], expected: &[u8]) {
    let out = run(exe, args, input, None);
    assert_eq!(out.status.code(), Some(0), "args{args:?}: {out:?}");
    assert!(out.stderr.is_empty(), "{out:?}");
    assert_eq!(out.stdout, expected, "args{args:?}");
}
#[test]
fn address_filter_canonicalizes_ip_socket_scoped_and_prefix_records_and_filters_whole_networks() {
    let exe = executable();
    good(
        &exe,
        &[],
        b"192.0.2.1\r\n2001:0DB8:0000:0:0:0:0:1\n::FFFF:C000:201",
        b"192.0.2.1\n2001:db8::1\n::ffff:192.0.2.1\n",
    );
    good(
        &exe,
        &["--network", "192.0.2.0/24"],
        b"192.0.2.1\n198.51.100.2\n::ffff:192.0.2.1\n",
        b"192.0.2.1\n",
    );
    good(
        &exe,
        &["--network", "192.0.2.0/24", "--invert"],
        b"192.0.2.1\n198.51.100.2\n::ffff:192.0.2.1\n",
        b"198.51.100.2\n::ffff:192.0.2.1\n",
    );
    good(
        &exe,
        &["--socket", "--network", "fe80::/10"],
        b"[fe80:0:0:0:0:0:0:1%00042]:00080\n192.0.2.1:80\n[2001:db8::1]:443\n",
        b"[fe80::1%42]:80\n",
    );
    good(
        &exe,
        &["--scoped"],
        b"FE80:0:0:0:0:0:0:1%00042\n::1%0\n",
        b"fe80::1%42\n::1\n",
    );
    good(
        &exe,
        &["--prefix", "--truncate", "--network", "2001:db8::/32"],
        b"2001:db8:1::ffff/64\n2001:db9::/32\n2001:db8::/31\n",
        b"2001:db8:1::/64\n",
    );
    good(
        &exe,
        &["--prefix"],
        b"0.0.0.0/0\n::/0\n255.255.255.255/32\nffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff/128\n",
        b"0.0.0.0/0\n::/0\n255.255.255.255/32\nffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff/128\n",
    );
    good(&exe, &[], b"", b"");
    let help = run(&exe, &["--help"], b"", None);
    assert_eq!(help.status.code(), Some(0));
    assert!(help.stdout.starts_with(b"Usage: address-filter ") && help.stdout.ends_with(b"\n"));
}
#[test]
fn address_filter_handles_large_chunked_input_final_records_limits_invalid_options_and_late_failures()
 {
    let exe = executable();
    let mut input = Vec::new();
    let mut expected = Vec::new();
    for i in 0..20000 {
        let line = format!(
            "2001:0DB8:0000:0000:0000:0000:{:04X}:{:04X}\r\n",
            i / 65536,
            i % 65536
        );
        input.extend_from_slice(line.as_bytes());
        if i == 0 {
            expected.extend_from_slice(b"2001:db8::\n");
        } else {
            expected.extend_from_slice(format!("2001:db8::{i:x}\n").as_bytes());
        }
    }
    let out = run(&exe, &[], &input, None);
    assert_eq!(out.status.code(), Some(0), "{out:?}");
    assert_eq!(out.stdout, expected);
    assert!(out.stderr.is_empty());
    for args in [
        vec!["--bad"],
        vec!["--truncate"],
        vec!["--invert"],
        vec!["--network"],
        vec!["--network", "192.0.2.1/24"],
        vec!["--socket", "--prefix"],
        vec!["--prefix", "--prefix"],
        vec!["--help", "extra"],
        vec!["--network", "::/0", "--network", "::/0"],
    ] {
        let out = run(&exe, &args, b"192.0.2.1\n", None);
        assert_eq!(out.status.code(), Some(2), "{args:?}: {out:?}");
        assert!(out.stdout.is_empty() && !out.stderr.is_empty());
    }
    for bad in [
        b"\n".as_slice(),
        b"01.2.3.4\n",
        b"localhost\n",
        b"::1%eth0\n",
        b"::1\0\n",
        b"::1 ",
        b"::1\r",
    ] {
        let out = run(&exe, &[], bad, None);
        assert_eq!(out.status.code(), Some(2), "{bad:?}: {out:?}");
        assert!(out.stdout.is_empty() && !out.stderr.is_empty());
    }
    let out = run(&exe, &[], b"::1\ninvalid\n", None);
    assert_eq!(out.status.code(), Some(2));
    assert_eq!(out.stdout, b"::1\n");
    let out = run(&exe, &[], &vec![b'1'; 65], None);
    assert_eq!(out.status.code(), Some(2));
    assert!(out.stdout.is_empty());
    let maximal = b"[ffff:ffff:ffff:ffff:ffff:ffff:255.255.255.255%4294967295]:65535\r\n";
    good(
        &exe,
        &["--socket"],
        maximal,
        b"[ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff%4294967295]:65535\n",
    );
}
#[test]
fn address_filter_retries_interruptions_and_reports_read_write_and_zero_progress_failures_without_heap()
 {
    let exe = executable();
    let input = b"2001:0db8::0001\n192.0.2.1\n";
    let expected = b"2001:db8::1\n192.0.2.1\n";
    for injection in [
        "inject=read:error=EINTR:when=1",
        "inject=write:error=EINTR:when=1",
    ] {
        let out = run(&exe, &[], input, Some(injection));
        assert_eq!(out.status.code(), Some(0), "{injection}: {out:?}");
        assert_eq!(out.stdout, expected);
        assert!(out.stderr.is_empty());
    }
    for injection in [
        "inject=read:error=EIO:when=1",
        "inject=read:error=EAGAIN:when=1",
        "inject=write:error=EIO:when=1",
        "inject=write:retval=0:when=1",
    ] {
        let out = run(&exe, &[], input, Some(injection));
        assert_eq!(out.status.code(), Some(3), "{injection}: {out:?}");
        assert!(out.stdout.is_empty() && !out.stderr.is_empty());
    }
}
