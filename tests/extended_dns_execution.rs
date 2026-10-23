#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
    sync::OnceLock,
    time::Duration,
};
fn compile(path: &str) -> common::TempArtifact {
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
    let exe = common::TempArtifact::new("laniusc_dns", "executable", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn cli() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile("sample_programs/library/dns_message.lani"))
}
fn run(cmd: &mut Command) -> Output {
    common::process_output_with_timeout("DNS", cmd, Duration::from_secs(30))
}
fn check(out: &Output, status: i32) {
    assert_eq!(out.status.code(), Some(status), "{out:?}");
    if status == 0 {
        assert!(out.stderr.is_empty(), "{out:?}");
    }
}
fn input(bytes: &[u8]) -> common::TempArtifact {
    let file = common::TempArtifact::new("laniusc_dns", "input", None);
    file.write_bytes(bytes);
    file
}
fn python() -> std::path::PathBuf {
    let path = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("target/stdlib-work/dns-oracle-venv/bin/python");
    assert!(
        path.exists(),
        "install isolated oracle: python3 -m venv target/stdlib-work/dns-oracle-venv; target/stdlib-work/dns-oracle-venv/bin/python -m pip install dnspython==2.7.0"
    );
    path
}
fn oracle(mode: &str) -> Output {
    run(Command::new(python())
        .arg("tests/fixtures/extended/dns_oracle.py")
        .arg(mode)
        .arg(cli().path()))
}
#[test]
fn dns_native_binary_names_views_equality_typed_records_edns_and_all_section_writes() {
    let exe = compile("tests/fixtures/extended/dns_contracts.lani");
    let out = run(&mut Command::new(exe.path()));
    check(&out, 0);
    assert!(out.stdout.is_empty());
}
#[test]
fn dns_names_sections_compression_and_common_rdata_match_dnspython() {
    let out = oracle("matrix");
    check(&out, 0);
    let summary = String::from_utf8(out.stdout).unwrap();
    assert!(summary.contains("dnspython-matrix cases=33 "), "{summary}");
    eprintln!("{summary}");
}
#[test]
fn dns_query_cli_binary_labels_edns_arguments_and_name_limits_execute() {
    let out = oracle("query");
    check(&out, 0);
    let summary = String::from_utf8(out.stdout).unwrap();
    assert!(
        summary.contains("query-and-arguments cases=98 "),
        "{summary}"
    );
    eprintln!("{summary}");
}
#[test]
fn dns_malformed_compression_rdata_boundaries_edns_truncation_and_limits_are_rejected() {
    let out = oracle("failures");
    check(&out, 0);
    eprintln!("{}", String::from_utf8_lossy(&out.stdout));
}
#[test]
fn dns_edns_owner_accepts_a_valid_compressed_root_name() {
    let out = oracle("edns_root");
    check(&out, 0);
    assert!(String::from_utf8_lossy(&out.stdout).contains("compressed-edns-root cases=1 "));
}
#[test]
fn dns_large_compressed_section_runs_with_bounded_work() {
    let out = oracle("scale");
    check(&out, 0);
    let summary = String::from_utf8(out.stdout).unwrap();
    assert!(summary.contains("records=1600 cases=1 "), "{summary}");
    eprintln!("{summary}");
}
fn freed(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let tail = line.rsplit(" = ").next().unwrap();
            if tail.starts_with("0x") {
                assert!(
                    live.insert(tail.split_whitespace().next().unwrap().to_owned()),
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
fn dns_library_and_cli_cleanup_each_allocation_and_io_failure_without_partial_output() {
    let packet = run(Command::new(python())
        .arg("tests/fixtures/extended/dns_oracle.py")
        .arg("packet"));
    check(&packet, 0);
    let source = input(&packet.stdout);
    let lib = compile("tests/fixtures/extended/dns_failure.lani");
    let trace = common::TempArtifact::new("laniusc_dns", "trace", None);
    let mut cases = 0;
    for (exe, args) in [
        (lib.path(), &[][..]),
        (cli().path(), &["inspect"][..]),
        (
            cli().path(),
            &["query", "--wire-name", "--udp-size", "1232", "--dnssec"][..],
        ),
    ] {
        let wire_name = input(&[3, 0, 255, 46, 0]);
        let file = if args.contains(&"query") {
            wire_name.path()
        } else {
            source.path()
        };
        let execute = |fault: Option<String>, status| {
            let mut c = Command::new("strace");
            c.args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap,read,write,socket,connect"]);
            if let Some(fault) = fault {
                c.args(["-e", &fault]);
            }
            let out = run(c
                .arg(exe)
                .args(args)
                .stdin(std::fs::File::open(file).unwrap()));
            check(&out, status);
            if status != 0 {
                assert!(out.stdout.is_empty(), "{out:?}");
            }
            let events = std::fs::read_to_string(trace.path()).unwrap();
            assert!(!events.contains("socket(") && !events.contains("connect("));
            let count = freed(&events);
            (count, out)
        };
        let (count, baseline) = execute(None, 0);
        for at in 1..=count {
            execute(Some(format!("inject=mmap:error=ENOMEM:when={at}")), 4);
            cases += 1;
        }
        eprintln!("DNS {:?}: {count} allocation failure positions", args);
        if args.contains(&"inspect") {
            let (_, o) = execute(Some("inject=read:error=EINTR:when=1".into()), 0);
            assert_eq!(o.stdout, baseline.stdout);
            execute(Some("inject=read:error=EIO:when=1".into()), 5);
            let (_, o) = execute(Some("inject=write:error=EINTR:when=1".into()), 0);
            assert_eq!(o.stdout, baseline.stdout);
            execute(Some("inject=write:error=EIO:when=1".into()), 5);
            let (_, o) = execute(Some("inject=write:retval=7:when=1".into()), 0);
            assert_eq!(o.stdout, baseline.stdout[7..]);
        }
    }
    eprintln!("DNS allocation fault cases={cases}");
}
