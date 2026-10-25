//! Real loopback OpenSSL peers for the production owned nonblocking adapter.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::HashMap,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn executable() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("tests/fixtures/extended/tls_tcp/peer.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("owned TLS TCP adapter", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("TLS TCP fixture: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let file = common::TempArtifact::new("laniusc_tls_tcp", "peer", None);
        file.write_bytes(bytes);
        std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        file
    })
}
struct Directory(PathBuf);
impl Directory {
    fn new() -> Self {
        let marker = common::TempArtifact::new("laniusc_tls_tcp", "peers", None);
        let path = marker.path().with_extension("dir");
        std::fs::create_dir(&path).unwrap();
        let output = common::process_output_with_timeout(
            "independent signed OpenSSL peer credentials",
            Command::new("python3")
                .arg(helper("peers.py"))
                .arg("fixtures")
                .arg(&path),
            Duration::from_secs(10),
        );
        assert!(
            output.status.success() && output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        Self(path)
    }
}
impl Drop for Directory {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
fn helper(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/extended/tls_tcp")
        .join(name)
}
#[derive(Clone, Debug)]
struct Case {
    role: u32,
    suite: u32,
    length: usize,
    mode: u32,
    fault: String,
    fragment: usize,
    transport: &'static str,
    expected: u64,
    root: &'static str,
    exporter: bool,
    group: u32,
    peer_groups: &'static str,
    calls: u64,
}
fn case(role: u32, suite: u32, length: usize) -> Case {
    Case {
        role,
        suite,
        length,
        mode: 0,
        fault: "-".into(),
        fragment: 0,
        transport: "tcp",
        expected: 0,
        root: "root.der",
        exporter: false,
        group: 0,
        peer_groups: "X25519",
        calls: 1_000_000,
    }
}
struct Actual {
    peer_status: i64,
    bytes: Vec<u8>,
    report: Vec<u64>,
    peer_bytes: Vec<u8>,
    peer_error: Vec<u8>,
    trace: String,
}
fn blob(bytes: &[u8], at: &mut usize) -> Vec<u8> {
    assert!(*at + 8 <= bytes.len());
    let n = u64::from_le_bytes(bytes[*at..*at + 8].try_into().unwrap()) as usize;
    *at += 8;
    assert!(n <= 16 * 1048576 && *at + n <= bytes.len());
    let result = bytes[*at..*at + n].to_vec();
    *at += n;
    result
}
fn run(directory: &Directory, c: &Case) -> Actual {
    let output = common::process_output_with_timeout(
        "bounded real TLS TCP/OpenSSL peer",
        Command::new("python3")
            .arg(helper("run.py"))
            .arg(executable().path())
            .arg(&directory.0)
            .arg(c.role.to_string())
            .arg(c.suite.to_string())
            .arg(c.length.to_string())
            .arg(c.mode.to_string())
            .arg(&c.fault)
            .arg(c.fragment.to_string())
            .arg(c.transport)
            .arg(u32::from(c.expected != 0).to_string())
            .arg(c.root)
            .arg(u32::from(c.exporter).to_string())
            .arg(c.group.to_string())
            .arg(c.peer_groups)
            .arg(c.calls.to_string()),
        Duration::from_secs(30),
    );
    assert!(
        output.status.success() && output.stderr.is_empty(),
        "{c:?}: {output:?}"
    );
    let mut at = 0;
    let peer_status = i64::from_le_bytes(blob(&output.stdout, &mut at).try_into().unwrap());
    let bytes = blob(&output.stdout, &mut at);
    let raw_report = blob(&output.stdout, &mut at);
    assert_eq!(raw_report.len(), 328, "{c:?}: {raw_report:?}");
    let report = raw_report
        .chunks_exact(8)
        .map(|b| u64::from_le_bytes(b.try_into().unwrap()))
        .collect();
    let peer_bytes = blob(&output.stdout, &mut at);
    let peer_error = blob(&output.stdout, &mut at);
    let trace = String::from_utf8(blob(&output.stdout, &mut at)).unwrap();
    assert_eq!(at, output.stdout.len());
    Actual {
        peer_status,
        bytes,
        report,
        peer_bytes,
        peer_error,
        trace,
    }
}
fn result(line: &str) -> i64 {
    let text = line
        .rsplit_once(" = ")
        .unwrap_or_else(|| panic!("syscall result: {line}"))
        .1
        .trim();
    text.split_whitespace()
        .next()
        .unwrap()
        .parse()
        .unwrap_or(-1)
}
fn requested(line: &str) -> i64 {
    let call = line
        .rsplit_once(" = ")
        .unwrap_or_else(|| panic!("syscall result: {line}"))
        .0
        .trim_end()
        .strip_suffix(')')
        .unwrap_or_else(|| panic!("syscall close: {line}"));
    // Last three arguments are flags, address and address length; quoted
    // payload may contain commas and must never be split from the front.
    call.rsplit(',')
        .nth(3)
        .unwrap()
        .trim()
        .parse()
        .unwrap_or_else(|_| panic!("syscall count: {line}"))
}
fn ledger(a: &Actual) -> (usize, u64, u64) {
    let mut live = HashMap::new();
    let (mut maps, mut sent, mut received, mut shorts, mut blocked) = (0, 0, 0, 0, 0);
    let mut entropy_started = false;
    for line in a.trace.lines() {
        if line.starts_with("mmap(") {
            assert!(
                !entropy_started,
                "no allocation after entropy/handshake: {}",
                a.trace
            );
            let (args, returned) = line.split_once(')').unwrap();
            if returned.trim_start().starts_with("= -1") {
                continue;
            }
            let address = returned
                .split('=')
                .nth(1)
                .unwrap()
                .split_whitespace()
                .next()
                .unwrap()
                .to_owned();
            let size: usize = args.split(',').nth(1).unwrap().trim().parse().unwrap();
            assert!(
                live.insert(address, size).is_none(),
                "one live mapping identity"
            );
            maps += 1;
        } else if line.starts_with("munmap(") {
            let (args, returned) = line
                .strip_prefix("munmap(")
                .unwrap()
                .split_once(')')
                .unwrap();
            assert_eq!(returned.trim(), "= 0", "{}", a.trace);
            let (address, size) = args.split_once(',').unwrap();
            assert_eq!(
                live.remove(address.trim()),
                Some(size.trim().parse::<usize>().unwrap()),
                "matching mapping/address/size"
            );
        } else if line.starts_with("mremap(") || line.starts_with("brk(") {
            panic!("unexpected allocation: {line}");
        } else if line.starts_with("getrandom(") {
            entropy_started = true;
            assert!(line.contains("GRND_NONBLOCK"));
        } else if line.starts_with("fcntl(") {
            assert!(line.contains("F_GETFL"), "no flag mutation: {line}");
        }
        if line.starts_with("sendto(0,") || line.starts_with("recvfrom(0,") {
            if line.contains("EAGAIN") {
                blocked += 1;
            }
            if line.contains("INJECTED") {
                continue;
            }
            let n = result(line);
            if n > 0 {
                assert!(n <= requested(line), "actual valid count: {line}");
                if line.starts_with("sendto(") {
                    sent += n as u64;
                    if n < requested(line) {
                        shorts += 1;
                    }
                } else {
                    received += n as u64;
                }
            }
        }
    }
    assert!(
        live.is_empty(),
        "every successful allocation released: {}",
        a.trace
    );
    assert_eq!(
        a.trace
            .lines()
            .filter(|line| line.starts_with("close(0)"))
            .count(),
        1,
        "one invalidating close attempt: {}",
        a.trace
    );
    assert_eq!(a.report[3], sent, "actual confirmed sent prefix");
    assert_eq!(
        a.report[4], received,
        "actual received bytes including retained late input"
    );
    assert!(
        a.report[5] <= received,
        "engine consumes only actual received prefix"
    );
    eprintln!("observed TCP positive short sends={shorts}, EAGAIN={blocked}");
    (maps, shorts, blocked)
}
fn pattern(n: usize, multiplier: usize, increment: usize) -> Vec<u8> {
    (0..n)
        .map(|i| ((i * multiplier + increment) % 256) as u8)
        .collect()
}
fn check(c: &Case, a: &Actual) {
    assert_eq!(
        a.report[0],
        c.expected,
        "{c:?}; peer stderr={}",
        String::from_utf8_lossy(&a.peer_error)
    );
    let (maps, _, _) = ledger(a);
    if c.expected == 0 {
        assert_eq!(maps, 10, "fixed owned resources");
        assert_eq!(&a.report[6..8], &[10, 11]);
        if c.mode != 1 {
            assert_eq!(
                a.peer_status,
                0,
                "peer verification/close: {}",
                String::from_utf8_lossy(&a.peer_error)
            );
            assert_eq!(&a.report[1..3], &[c.length as u64, c.length as u64]);
            if c.mode != 12 {
                assert_eq!(
                    a.bytes,
                    if c.role == 0 {
                        pattern(c.length, 53, 193)
                    } else {
                        pattern(c.length, 37, 11)
                    }
                );
            }
            if c.exporter {
                let text = format!(
                    "{}\n{}",
                    String::from_utf8_lossy(&a.peer_bytes),
                    String::from_utf8_lossy(&a.peer_error)
                );
                let values: Vec<_> = text
                    .lines()
                    .filter_map(|line| {
                        line.split_once("Keying material: ")
                            .map(|(_, value)| value.trim())
                    })
                    .collect();
                assert!(!values.is_empty(), "OpenSSL exporter output: {text}");
                for hex in values {
                    let length = if c.mode == 12 { 12240 } else { 32 };
                    assert_eq!(hex.len(), length * 2);
                    let bytes: Vec<u64> = hex
                        .as_bytes()
                        .chunks_exact(2)
                        .map(|b| {
                            u8::from_str_radix(std::str::from_utf8(b).unwrap(), 16).unwrap() as u64
                        })
                        .collect();
                    assert_eq!(&a.report[9..], &bytes[..32]);
                    if c.mode == 12 {
                        assert_eq!(a.bytes, bytes.iter().map(|n| *n as u8).collect::<Vec<_>>());
                    }
                }
            } else {
                assert_eq!(a.peer_bytes, pattern(c.length, 37, 11));
            }
        } else {
            assert!(a.bytes.is_empty());
        }
    } else {
        assert!(
            a.bytes.is_empty(),
            "failed handshake publishes no app bytes"
        );
    }
}

#[test]
fn openssl_peers_exchange_binary_data_both_suites_key_updates_exporters_and_close() {
    let directory = Directory::new();
    let mut count = 0;
    for role in 0..2 {
        for suite in 0..2 {
            for length in [0, 1, 4097] {
                let mut c = case(role, suite, length);
                c.fragment = if length == 4097 { 7 } else { length };
                check(&c, &run(&directory, &c));
                count += 1;
            }
            let mut c = case(role, suite, 8193);
            c.mode = 8;
            check(&c, &run(&directory, &c));
            count += 1;
        }
        let mut c = case(role, 0, 0);
        c.exporter = true;
        check(&c, &run(&directory, &c));
        count += 1;
    }
    eprintln!("TLS TCP real OpenSSL cases: {count}");
}

#[test]
fn real_tcp_pressure_preserves_bounded_one_megabyte_streams_in_both_roles() {
    let directory = Directory::new();
    for role in 0..2 {
        let c = case(role, 0, 1048576);
        check(&c, &run(&directory, &c));
    }
    eprintln!("TLS TCP real pressure cases: 2");
}

#[test]
fn tcp_constructor_faults_retryable_calls_and_terminal_cleanup_preserve_owners() {
    let directory = Directory::new();
    let mut cases = Vec::new();
    let mut c = case(0, 0, 0);
    c.mode = 1;
    cases.push(c);
    for (transport, expected) in [("blocking", 4), ("udp", 3), ("unconnected", 11)] {
        let mut c = case(0, 0, 0);
        c.transport = transport;
        c.expected = expected;
        cases.push(c);
    }
    for n in 1..=10 {
        let mut c = case(0, 0, 0);
        c.fault = format!("mmap:error=ENOMEM:when={n}");
        c.expected = if n <= 8 { 2 } else { 12 };
        cases.push(c);
    }
    for fault in [
        "getrandom:error=EAGAIN:when=1",
        "getrandom:retval=0:when=1",
        "getrandom:retval=65:when=1",
    ] {
        let mut c = case(0, 0, 0);
        c.fault = fault.into();
        c.expected = 13;
        cases.push(c);
    }
    for fault in [
        "getrandom:error=EINTR:when=1",
        "sendto:error=EINTR:when=1",
        "sendto:error=EAGAIN:when=1",
        "recvfrom:error=EINTR:when=1",
        "recvfrom:error=EAGAIN:when=1",
    ] {
        let mut c = case(0, 0, 7);
        c.fault = fault.into();
        cases.push(c);
    }
    for (fault, expected) in [
        ("sendto:retval=0:when=1", 11),
        ("sendto:retval=1025:when=1", 11),
        ("recvfrom:error=EIO:when=1", 11),
        ("recvfrom:retval=0:when=1", 14),
        ("clock_gettime:error=EIO:when=2", 10),
        ("clock_gettime:retval=0:when=2", 10),
    ] {
        let mut c = case(0, 0, 0);
        c.fault = fault.into();
        c.expected = expected;
        cases.push(c);
    }
    let mut c = case(0, 0, 0);
    c.mode = 1;
    c.fault = "close:error=EIO:when=1".into();
    cases.push(c);
    let mut c = case(0, 0, 0);
    c.root = "wrong-root.der";
    c.expected = 14;
    cases.push(c);
    let mut c = case(0, 0, 0);
    c.root = "wrong-root.der";
    c.fault = "close:error=EIO:when=1".into();
    c.expected = 14;
    cases.push(c);
    for mode in [6, 7] {
        let mut c = case(0, 0, 0);
        c.mode = mode;
        c.expected = 14;
        cases.push(c);
    }
    for transport in ["eof", "partial_eof"] {
        let mut c = case(0, 0, 0);
        c.transport = transport;
        c.expected = 14;
        cases.push(c);
    }
    let mut c = case(0, 0, 0);
    c.mode = 4;
    c.expected = 7;
    cases.push(c);
    let mut c = case(0, 0, 0);
    c.mode = 9;
    c.expected = 14;
    cases.push(c);
    for c in &cases {
        let a = run(&directory, c);
        check(c, &a);
        if c.fault.starts_with("close:") {
            assert_eq!(a.report[8], 1, "close cause separately observable");
        } else {
            assert_eq!(a.report[8], 0);
        }
    }
    eprintln!("TLS TCP owner/fault cases: {}", cases.len());
}

#[test]
fn established_deadline_and_budget_stops_resume_actual_wire_and_pending_input() {
    let directory = Directory::new();
    let mut count = 0;
    for suite in 0..2 {
        for mode in [2, 3, 5] {
            let mut c = case(0, suite, 8193);
            c.mode = mode;
            check(&c, &run(&directory, &c));
            count += 1;
        }
    }
    eprintln!("TLS TCP resume cases: {count}");
}

fn entropy_requests(trace: &str) -> Vec<usize> {
    trace
        .lines()
        .filter(|line| line.starts_with("getrandom("))
        .map(|line| {
            line.rsplit_once(" = ")
                .unwrap()
                .0
                .trim_end()
                .strip_suffix(')')
                .unwrap()
                .rsplit(',')
                .nth(1)
                .unwrap()
                .trim()
                .parse()
                .unwrap()
        })
        .collect()
}

#[test]
fn p256_openssl_peers_cover_single_dual_requested_groups_and_entropy_retry() {
    let directory = Directory::new();
    let mut count = 0;
    for role in 0..2 {
        for suite in 0..2 {
            for group in [1, 2] {
                let mut c = case(role, suite, 257);
                c.group = group;
                c.peer_groups = "P-256";
                c.fragment = 7;
                check(&c, &run(&directory, &c));
                count += 1;
            }
        }
    }
    // The server prefers P although the independent client initially shares X.
    // The dual-policy client/P-only-server cases above force the opposite HRR.
    for suite in 0..2 {
        let mut c = case(1, suite, 33);
        c.group = 3;
        c.peer_groups = "X25519:P-256";
        check(&c, &run(&directory, &c));
        count += 1;
    }
    for role in 0..2 {
        for group in [1, 2] {
            let layout = if group == 1 { 64 } else { 96 };
            let mut c = case(role, 0, 17);
            c.group = group;
            c.peer_groups = "P-256";
            // A suppressed first entropy call leaves the std entropy staging
            // buffer zero. This deliberately supplies an invalid P scalar;
            // its positive injected count is never claimed as real OS entropy.
            c.fault = format!("getrandom:retval={layout}:when=1");
            let a = run(&directory, &c);
            check(&c, &a);
            let requests = entropy_requests(&a.trace);
            assert_eq!(requests[0], layout);
            assert!(requests.len() >= 2 && requests[1..].iter().all(|n| *n <= 32));
            let fresh: i64 = a
                .trace
                .lines()
                .filter(|line| line.starts_with("getrandom(") && !line.contains("INJECTED"))
                .map(result)
                .filter(|n| *n > 0)
                .sum();
            assert!(fresh >= 32 && fresh <= 7 * 32 && fresh % 32 == 0);
            count += 1;
        }
    }
    assert_eq!(count, 14);
    eprintln!("P-256 TCP:{count} real peer cases; P-only/dual/both suites, requested-group HRR both directions, scalar rejection followed only by fresh OS P-slot bytes");
}

#[test]
fn p256_entropy_rejection_cap_refill_failure_and_shared_budget_preserve_socket() {
    let directory = Directory::new();
    let mut count = 0;
    for role in 0..2 {
        for group in [1, 2] {
            let layout = if group == 1 { 64 } else { 96 };
            let initial = layout / 32;
            let mut c = case(role, 0, 0);
            c.group = group;
            c.peer_groups = "P-256";
            c.mode = 11;
            c.expected = 14;
            c.fault = "getrandom:retval=32:when=1+".into();
            let a = run(&directory, &c);
            check(&c, &a);
            let requests = entropy_requests(&a.trace);
            let mut expected: Vec<_> = (0..initial).map(|i| layout - i * 32).collect();
            expected.extend([32; 7]);
            assert_eq!(
                requests, expected,
                "initial candidate plus exactly seven refills"
            );
            assert_eq!(
                &a.report[6..8],
                &[10, 10],
                "input socket retained until caller closes it"
            );
            count += 1;

            // Derive a stop immediately after the first actual refill attempt
            // from the observed charged host prefix, including the initial
            // clock and the adapter's documented21 prepaid acquisition credits.
            let mut charged = 21;
            let mut random_calls = 0;
            for line in a.trace.lines() {
                if [
                    "clock_gettime(",
                    "getsockopt(",
                    "fcntl(",
                    "getpeername(",
                    "getrandom(",
                ]
                .iter()
                .any(|name| line.starts_with(name))
                {
                    charged += 1;
                }
                if line.starts_with("getrandom(") {
                    random_calls += 1;
                    if random_calls == initial + 1 {
                        break;
                    }
                }
            }
            c.mode = 0;
            c.expected = 8;
            c.calls = charged;
            let stopped = run(&directory, &c);
            check(&c, &stopped);
            assert_eq!(entropy_requests(&stopped.trace), expected[..initial + 1]);
            assert_eq!(&stopped.report[6..8], &[10, 10]);
            assert!(!stopped
                .trace
                .lines()
                .any(|line| line.starts_with("sendto(")));
            count += 1;

            c.calls = 1_000_000;
            c.expected = 13;
            c.fault = format!("getrandom:retval={layout}:when=1+");
            let failed = run(&directory, &c);
            check(&c, &failed);
            assert_eq!(entropy_requests(&failed.trace), [layout, 32]);
            assert_eq!(&failed.report[6..8], &[10, 10]);
            count += 1;
        }
        let mut c = case(role, 0, 0);
        c.group = 1;
        c.peer_groups = "P-256";
        c.mode = 10;
        c.expected = 14;
        c.fault = "getrandom:retval=64:when=1".into();
        let a = run(&directory, &c);
        check(&c, &a);
        assert_eq!(
            entropy_requests(&a.trace),
            [64],
            "non-scalar constructor error never retries"
        );
        count += 1;
    }
    assert_eq!(count, 14);
    eprintln!("P-256 entropy:{count} cases; eight-candidate cap, only P-slot32 refills, invalid-refill count stops, original shared budget stops and caller socket retained");
}

fn sha384_case(role: u32, group: u32, length: usize) -> Case {
    let mut c = case(role, 2, length);
    c.group = group;
    c.peer_groups = if group == 0 { "X25519" } else { "P-256" };
    c
}

#[test]
fn aes256_sha384_openssl_peers_cover_groups_hrr_key_updates_and_exporters() {
    let directory = Directory::new();
    let mut count = 0;
    for role in 0..2 {
        for group in [0, 1] {
            let mut c = sha384_case(role, group, 4097);
            c.fragment = 7;
            check(&c, &run(&directory, &c));
            count += 1;
            c = sha384_case(role, group, 8193);
            c.mode = 8;
            check(&c, &run(&directory, &c));
            count += 1;
            c = sha384_case(role, group, 0);
            c.exporter = true;
            check(&c, &run(&directory, &c));
            count += 1;
        }
    }
    for role in 0..2 {
        let mut c = sha384_case(role, if role == 0 { 2 } else { 3 }, 33);
        if role == 1 {
            c.peer_groups = "X25519:P-256";
        }
        check(&c, &run(&directory, &c));
        count += 1;
    }
    assert_eq!(count, 14);
    eprintln!("AES256/SHA384 TCP:{count} real OpenSSL cases; singleton suite, both roles/groups, fragmented app records, requested-group HRR both directions, confirmed KU generations and exporter agreement");
}

#[test]
fn aes256_sha384_tcp_limits_faults_prefixes_and_full_exporter_cap() {
    let directory = Directory::new();
    let mut count = 0;
    for role in 0..2 {
        let mut c = sha384_case(role, role, 0);
        c.exporter = true;
        c.mode = 12;
        let a = run(&directory, &c);
        check(&c, &a);
        assert_eq!(a.bytes.len(), 12240);
        count += 1;
    }
    for group in [0, 1] {
        for mode in [2, 3, 5] {
            let mut c = sha384_case(0, group, 8193);
            c.mode = mode;
            check(&c, &run(&directory, &c));
            count += 1;
        }
    }
    for (mode, group, root) in [
        (0, 0, "wrong-root.der"),
        (6, 1, "root.der"),
        (7, 0, "root.der"),
    ] {
        let mut c = sha384_case(0, group, 0);
        c.mode = mode;
        c.root = root;
        c.expected = 14;
        check(&c, &run(&directory, &c));
        count += 1;
    }
    let mut c = sha384_case(0, 0, 0);
    c.fault = "sendto:error=EPIPE:when=1".into();
    c.expected = 11;
    check(&c, &run(&directory, &c));
    count += 1;
    c = sha384_case(0, 0, 0);
    c.mode = 9;
    c.expected = 14;
    check(&c, &run(&directory, &c));
    count += 1;
    for role in 0..2 {
        let mut c = sha384_case(role, 0, 0);
        c.mode = 13;
        c.expected = 14;
        let a = run(&directory, &c);
        check(&c, &a);
        assert!(entropy_requests(&a.trace).is_empty());
        assert!(!a
            .trace
            .lines()
            .any(|line| ["fcntl(", "getsockopt(", "getpeername(", "mmap("]
                .iter()
                .any(|name| line.starts_with(name))));
        count += 1;
    }
    assert_eq!(count, 15);
    eprintln!("AES256/SHA384 TCP:{count} limit/failure cases; real12240-byte exporter agrees in full,12241 leaves guards intact, actual send/receive prefix resumption, trust/name/time/host/work errors and suite policy preflight preserve owners");
}
