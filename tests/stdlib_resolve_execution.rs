//! Native glibc resolver conversion, validation and explicit ownership.
#![cfg(all(target_os = "linux", target_arch = "x86_64", target_env = "gnu"))]
mod common;
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output, Stdio},
    sync::OnceLock,
    time::{Duration, Instant},
};
fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn fixture(name: &str) -> PathBuf {
    root()
        .join("tests/fixtures/stdlib_foundation/resolve")
        .join(name)
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout(
        "system resolver execution",
        command,
        Duration::from_secs(30),
    )
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn native(name: &str) -> common::TempArtifact {
    let observer = common::TempArtifact::new("laniusc_resolve", "observer", Some("o"));
    checked(
        &run(Command::new("cc")
            .args(["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-c"])
            .arg(fixture("observer.c"))
            .arg("-o")
            .arg(observer.path())),
        0,
    );
    let entry = fixture(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: Vec::new(),
    };
    let options = laniusc_compiler::compiler::NativeLinkOptions {
        objects: vec![observer.path().to_path_buf()],
        libraries: vec!["dl".into()],
        ..Default::default()
    };
    let bytes = common::run_gpu_codegen_with_timeout("system resolver native link", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ),
        )
    })
    .unwrap_or_else(|error| panic!("resolver {name}: {error}"));
    let file = common::TempArtifact::new("laniusc_resolve", name, None);
    fs::write(file.path(), bytes).unwrap();
    checked(
        &run(Command::new("python3")
            .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
            .arg(file.path())),
        0,
    );
    let dynamic = run(Command::new("readelf").arg("-d").arg(file.path()));
    checked(&dynamic, 0);
    assert!(String::from_utf8_lossy(&dynamic.stdout).contains("libc.so.6"));
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn protocol() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| native("protocol.lani"))
}
fn oracle() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| {
        let file = common::TempArtifact::new("laniusc_resolve", "oracle", None);
        checked(
            &run(Command::new("cc")
                .args(["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror"])
                .arg(fixture("oracle.c"))
                .arg("-o")
                .arg(file.path())),
            0,
        );
        file
    })
}
#[derive(Clone, Debug)]
struct Case {
    mode: u32,
    parameter: u32,
    host_kind: u32,
    service_kind: u32,
    family: u32,
    kind: u32,
    addr_config: bool,
    mapping: u32,
    host_cap: u32,
    service_cap: u32,
    result_cap: u32,
    layout: u32,
    host: Vec<u8>,
    service: Vec<u8>,
    port: u16,
    host_start: i32,
    host_length: i32,
    service_start: i32,
    service_length: i32,
}
impl Case {
    fn numeric(host: &str, port: u16) -> Self {
        Self {
            mode: 0,
            parameter: 0,
            host_kind: 1,
            service_kind: 1,
            family: 0,
            kind: 0,
            addr_config: false,
            mapping: 0,
            host_cap: 4096,
            service_cap: 64,
            result_cap: 256,
            layout: 0,
            host: host.as_bytes().to_vec(),
            service: Vec::new(),
            port,
            host_start: 3,
            host_length: host.len() as i32,
            service_start: 3,
            service_length: 0,
        }
    }
    fn named(host: &str, service: &str) -> Self {
        let mut case = Self::numeric(host, 0);
        case.host_kind = 0;
        case.service_kind = 0;
        case.service = service.as_bytes().to_vec();
        case.service_length = service.len() as i32;
        case
    }
    fn set_host(&mut self, bytes: impl Into<Vec<u8>>) {
        self.host = bytes.into();
        self.host_length = self.host.len() as i32;
    }
    fn set_service(&mut self, bytes: impl Into<Vec<u8>>) {
        self.service = bytes.into();
        self.service_length = self.service.len() as i32;
    }
    fn flags(&self) -> u32 {
        (if self.host_kind == 3 {
            1
        } else if self.host_kind == 1 {
            4
        } else {
            0
        }) | (if self.service_kind == 1 { 1024 } else { 0 })
            | (if self.addr_config { 32 } else { 0 })
            | match self.mapping {
                0 => 0,
                1 => 8,
                _ => 24,
            }
    }
    fn selected_host(&self) -> Option<&[u8]> {
        if self.host_kind >= 2 {
            None
        } else {
            let start = (self.host_start - 3) as usize;
            Some(&self.host[start..start + self.host_length as usize])
        }
    }
    fn selected_service(&self) -> Option<Vec<u8>> {
        match self.service_kind {
            0 => {
                let start = (self.service_start - 3) as usize;
                Some(self.service[start..start + self.service_length as usize].to_vec())
            }
            1 => Some(self.port.to_string().into_bytes()),
            _ => None,
        }
    }
    fn encode(&self, bytes: &mut Vec<u8>) {
        for word in [
            self.mode,
            self.parameter,
            self.host_kind,
            self.service_kind,
            self.family,
            self.kind,
            self.addr_config as u32,
            self.mapping,
            self.host_cap,
            self.service_cap,
            self.result_cap,
            self.layout,
            self.host.len() as u32,
            self.service.len() as u32,
            self.port as u32,
            self.host_start as u32,
            self.host_length as u32,
            self.service_start as u32,
            self.service_length as u32,
            0,
        ] {
            bytes.extend_from_slice(&word.to_le_bytes());
        }
        bytes.extend_from_slice(&self.host);
        bytes.extend_from_slice(&self.service);
    }
}
#[derive(Debug)]
struct Reply {
    body: String,
    stats: Vec<i64>,
}
fn execute(cases: &[Case]) -> Vec<Reply> {
    let file = common::TempArtifact::new("laniusc_resolve", "input", None);
    let mut bytes = Vec::new();
    for case in cases {
        case.encode(&mut bytes);
    }
    file.write_bytes(bytes);
    let output =
        run(Command::new(protocol().path())
            .stdin(Stdio::from(fs::File::open(file.path()).unwrap())));
    checked(&output, 0);
    let replies: Vec<_> = String::from_utf8(output.stdout)
        .unwrap()
        .lines()
        .map(|line| {
            let (body, stats) = line.split_once(';').unwrap();
            Reply {
                body: body.to_owned(),
                stats: stats.split(',').map(|part| part.parse().unwrap()).collect(),
            }
        })
        .collect();
    assert_eq!(replies.len(), cases.len());
    replies
}
fn hash(bytes: Option<&[u8]>) -> i64 {
    bytes.map_or(0, |bytes| {
        bytes.iter().fold(2166136261u32, |value, byte| {
            (value ^ u32::from(*byte)).wrapping_mul(16777619)
        }) as i64
    })
}
fn check_native(case: &Case, reply: &Reply, queries: i64, frees: i64) {
    assert_eq!(reply.stats.len(), 15, "{case:?}: {reply:?}");
    assert_eq!(
        &reply.stats[..4],
        &[queries, frees, 0, 0],
        "{case:?}: {reply:?}"
    );
    if queries == 0 {
        assert!(
            reply.stats.iter().all(|value| *value == 0),
            "{case:?}: {reply:?}"
        );
        return;
    }
    let host = case.selected_host();
    let service = case.selected_service();
    let expected = [
        case.flags() as i64,
        match case.family {
            0 => 0,
            1 => 2,
            _ => 10,
        },
        if case.kind == 0 { 1 } else { 2 },
        if case.kind == 0 { 6 } else { 17 },
        host.map_or(0, |v| v.len()) as i64,
        service.as_ref().map_or(0, |v| v.len()) as i64,
        host.is_none() as i64,
        service.is_none() as i64,
        0,
        hash(host),
        hash(service.as_deref()),
    ];
    assert_eq!(&reply.stats[4..], &expected, "{case:?}: {reply:?}");
}
fn reference(case: &Case) -> String {
    let host = case.selected_host().map_or_else(
        || "-".into(),
        |value| String::from_utf8(value.to_vec()).unwrap(),
    );
    let service = case
        .selected_service()
        .map_or_else(|| "-".into(), |value| String::from_utf8(value).unwrap());
    let output = run(Command::new(oracle().path()).args([
        host,
        service,
        match case.family {
            0 => "0",
            1 => "2",
            _ => "10",
        }
        .into(),
        if case.kind == 0 { "1" } else { "2" }.into(),
        case.flags().to_string(),
    ]));
    checked(&output, 0);
    let line = String::from_utf8(output.stdout).unwrap();
    let line = line.trim();
    if let Some(native) = line.strip_prefix('N') {
        let (code, system) = native.split_once(':').unwrap();
        format!("E11:4:{code}:{system}:-1")
    } else {
        line.into()
    }
}

#[test]
fn resolver_numeric_null_host_and_local_nss_records_match_independent_header_typed_libc() {
    let mut cases = Vec::new();
    for (host, family, mapping) in [
        ("127.0.0.1", 0, 0),
        ("192.0.2.227", 1, 0),
        ("255.255.255.255", 1, 0),
        ("127.1", 1, 0),
        ("::1", 2, 0),
        ("2001:db8::dead:beef", 0, 0),
        ("fe80::1%7", 2, 0),
        ("::ffff:192.0.2.123", 2, 0),
        ("192.0.2.1", 2, 1),
        ("192.0.2.1", 2, 2),
    ] {
        for kind in 0..2 {
            for layout in 0..3 {
                let mut case = Case::numeric(host, [0, 1, 32768, 65535][(cases.len() / 3) % 4]);
                case.family = family;
                case.mapping = mapping;
                case.kind = kind;
                case.layout = layout;
                cases.push(case);
            }
        }
    }
    for host_kind in [2, 3] {
        for family in [0, 1, 2] {
            for kind in 0..2 {
                let mut case = Case::numeric("", 80);
                case.host_kind = host_kind;
                case.host_length = 0;
                case.family = family;
                case.kind = kind;
                cases.push(case);
            }
        }
    }
    for host in ["127.0.0.1", "::1"] {
        let mut case = Case::numeric(host, 1);
        case.addr_config = true;
        cases.push(case);
        let mut unspecified = Case::numeric(host, 0);
        unspecified.service_kind = 2;
        cases.push(unspecified);
    }
    let hosts = fs::read_to_string("/etc/hosts").unwrap();
    let nss = fs::read_to_string("/etc/nsswitch.conf").unwrap();
    let host_policy = nss.lines().find(|line| line.starts_with("hosts:")).unwrap();
    assert!(
        hosts.lines().any(|line| {
            let mut fields = line.split('#').next().unwrap().split_whitespace();
            fields
                .next()
                .is_some_and(|address| address.parse::<std::net::Ipv4Addr>().is_ok())
                && fields.any(|name| name == "localhost")
        }) && host_policy.split_whitespace().nth(1) == Some("files")
            && !host_policy.contains("SUCCESS="),
        "local-only localhost gate requires a files-first local entry"
    );
    let service_policy = nss
        .lines()
        .find(|line| line.starts_with("services:"))
        .unwrap();
    let providers: Vec<_> = service_policy
        .split('#')
        .next()
        .unwrap()
        .split_whitespace()
        .skip(1)
        .collect();
    let files = providers
        .iter()
        .position(|provider| *provider == "files")
        .expect("local services file provider");
    assert!(
        providers[..=files]
            .iter()
            .all(|provider| matches!(*provider, "db" | "files"))
            && !service_policy.contains("SUCCESS="),
        "named services require only local providers through files and default success return: {service_policy}"
    );
    let services = fs::read_to_string("/etc/services").unwrap();
    for (service, kind, protocol) in [
        ("http", 0, "tcp"),
        ("domain", 0, "tcp"),
        ("domain", 1, "udp"),
    ] {
        assert!(
            services.lines().any(|line| {
                let fields: Vec<_> = line.split('#').next().unwrap().split_whitespace().collect();
                fields.len() >= 2
                    && (fields[0] == service || fields[2..].contains(&service))
                    && fields[1]
                        .split_once('/')
                        .is_some_and(|(port, kind)| kind == protocol && port.parse::<u16>().is_ok())
            }),
            "named service must match the requested protocol in the local file: {service}/{protocol}"
        );
        let mut case = Case::named("localhost", service);
        case.family = 1;
        case.kind = kind;
        cases.push(case);
    }
    let mut subset = Case::numeric("xx127.0.0.1yy", 443);
    subset.host_start = 5;
    subset.host_length = 9;
    subset.layout = 2;
    cases.push(subset);
    let start = Instant::now();
    let actual = execute(&cases);
    let elapsed = start.elapsed();
    for (index, (case, reply)) in cases.iter().zip(actual).enumerate() {
        let expected = reference(case);
        assert_eq!(reply.body, expected, "native case{index}: {case:?}");
        check_native(
            case,
            &reply,
            1,
            if expected.starts_with('O') { 1 } else { 0 },
        );
    }
    eprintln!(
        "resolver independent libc matrix: {} cases, native batch {:?} (includes first compile/link when uncached)",
        cases.len(),
        elapsed
    );
}

fn synthetic(case: &Case, count: usize) -> String {
    use std::fmt::Write;
    let port = match case.service_kind {
        0 => 43210,
        1 => case.port,
        _ => 0,
    };
    let mut result = "O".to_owned();
    for index in 0..count {
        let ipv6 = case.family == 2 || (case.family == 0 && index % 2 == 1);
        if !ipv6 {
            write!(result, "4:{port}:0:c63364e3/").unwrap();
        } else {
            let (scope, address) = if index % 4 == 3 {
                (4294967295u32, "00000000000000000000ffffc000027b")
            } else {
                (2309737967u32, "20010db81234ffff0000abcddeadbeef")
            };
            write!(result, "6:{port}:{scope}:{address}/").unwrap();
        }
    }
    result
}

#[test]
fn resolver_local_validation_is_ordered_allocation_free_and_preserves_all_view_layouts() {
    let base = Case::named("host", "service");
    let mut examples: Vec<(Case, String)> = Vec::new();
    for (field, value) in [
        (0, 0),
        (0, u32::MAX),
        (0, 65537),
        (1, 0),
        (1, u32::MAX),
        (1, 4097),
        (2, 0),
        (2, u32::MAX),
        (2, 4097),
    ] {
        let mut case = base.clone();
        match field {
            0 => case.host_cap = value,
            1 => case.service_cap = value,
            _ => case.result_cap = value,
        };
        examples.push((case, "E2:1:0:0:-1".into()));
    }
    for family in [0, 1] {
        for mapping in [1, 2] {
            let mut case = base.clone();
            case.family = family;
            case.mapping = mapping;
            examples.push((case, "E3:1:0:0:-1".into()));
        }
    }
    for host_kind in [0, 1] {
        for (bytes, cause, index) in [
            (Vec::new(), 4, 0),
            (b"*".to_vec(), 7, 0),
            (b"ab\0c".to_vec(), 5, 2),
            (b"a b".to_vec(), 6, 1),
            (b"a\tb".to_vec(), 6, 1),
            (vec![b'a', 127], 6, 1),
            (vec![b'a', 128], 6, 1),
            ("aé".as_bytes().to_vec(), 6, 1),
        ] {
            let mut case = base.clone();
            case.host_kind = host_kind;
            case.set_host(bytes);
            examples.push((case, format!("E{cause}:2:0:0:{index}")));
        }
    }
    for (bytes, cause, index) in [
        (Vec::new(), 4, 0),
        (b"*".to_vec(), 8, 0),
        (b"+name".to_vec(), 8, 0),
        (b"-name".to_vec(), 8, 0),
        (b"80".to_vec(), 8, 0),
        (b"00080".to_vec(), 8, 0),
        (b"65536".to_vec(), 8, 0),
        (b"ab\0c".to_vec(), 5, 2),
        (b"a b".to_vec(), 6, 1),
        (vec![b'a', 255], 6, 1),
    ] {
        let mut case = base.clone();
        case.set_service(bytes);
        examples.push((case, format!("E{cause}:3:0:0:{index}")));
    }
    for host in [true, false] {
        for (start, length) in [(-1, 1), (3, -1), (i32::MAX, 1)] {
            let mut case = base.clone();
            if host {
                case.host_start = start;
                case.host_length = length;
            } else {
                case.service_start = start;
                case.service_length = length;
            }
            examples.push((case, format!("E1:{}:0:0:-1", if host { 2 } else { 3 })));
        }
    }
    let mut short = base.clone();
    short.host_cap = 3;
    examples.push((short, "E1:2:0:0:-1".into()));
    let mut short = base.clone();
    short.service_cap = 6;
    examples.push((short, "E1:3:0:0:-1".into()));
    for port in [10, 100, 1000, 10000, 65535] {
        let mut case = Case::numeric("127.0.0.1", port);
        case.service_cap = port.to_string().len() as u32 - 1;
        examples.push((case, "E1:3:0:0:-1".into()));
    }
    for host_kind in [2, 3] {
        let mut case = base.clone();
        case.host_kind = host_kind;
        case.service_kind = 2;
        examples.push((case, "E9:1:0:0:-1".into()));
    }
    let mut case = base.clone();
    case.set_host(b"xxa\0yy".to_vec());
    case.host_start = 5;
    case.host_length = 2;
    examples.push((case, "E5:2:0:0:1".into()));
    let mut case = base.clone();
    case.set_service(b"xxa\0yy".to_vec());
    case.service_start = 5;
    case.service_length = 2;
    examples.push((case, "E5:3:0:0:1".into()));
    let mut case = base.clone();
    case.host_cap = 0;
    case.mapping = 1;
    case.set_host(vec![0]);
    examples.push((case, "E2:1:0:0:-1".into()));
    let mut case = base.clone();
    case.mapping = 1;
    case.set_host(vec![0]);
    examples.push((case, "E3:1:0:0:-1".into()));
    let mut case = base.clone();
    case.set_host(vec![0]);
    case.set_service(vec![0]);
    examples.push((case, "E5:2:0:0:0".into()));
    // The strided-only copy is also traced below: these local rejections must
    // not reach either resolver C function or any source-owned mmap.
    let local: Vec<_> = examples.iter().map(|(case, _)| case.clone()).collect();
    let mut expanded = Vec::new();
    for (case, expected) in &examples {
        for layout in 0..3 {
            let mut case = case.clone();
            case.layout = layout;
            expanded.push((case, expected.clone()));
        }
    }
    let cases: Vec<_> = expanded.iter().map(|(case, _)| case.clone()).collect();
    let actual = execute(&cases);
    for (index, ((case, expected), reply)) in expanded.iter().zip(actual).enumerate() {
        assert_eq!(&reply.body, expected, "local{index}: {case:?}");
        check_native(case, &reply, 0, 0);
    }
    let trace = common::TempArtifact::new("laniusc_resolve", "local_trace", None);
    let input = common::TempArtifact::new("laniusc_resolve", "local_input", None);
    let mut bytes = Vec::new();
    for case in &local {
        case.encode(&mut bytes);
    }
    input.write_bytes(bytes);
    let output = run(Command::new("strace")
        .args(["-qq", "-i", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"])
        .arg(protocol().path())
        .stdin(Stdio::from(fs::File::open(input.path()).unwrap())));
    checked(&output, 0);
    assert!(
        mapping_ledger(
            &fs::read_to_string(trace.path()).unwrap(),
            &allocation_sites(protocol().path())
        )
        .is_empty()
    );
    let mut accepted = Vec::new();
    for port in [0, 9, 10, 99, 100, 999, 1000, 9999, 10000, 65535] {
        let mut case = Case::numeric("127.0.0.1", port);
        case.mode = 1;
        case.service_cap = port.to_string().len() as u32;
        accepted.push(case);
    }
    let mut exact = base.clone();
    exact.mode = 1;
    exact.host_cap = 4;
    exact.service_cap = 7;
    exact.result_cap = 4;
    accepted.push(exact);
    let mut maximum = base.clone();
    maximum.mode = 1;
    maximum.layout = 1;
    maximum.set_host(vec![b'h'; 65536]);
    maximum.set_service(vec![b's'; 4096]);
    maximum.host_cap = 65536;
    maximum.service_cap = 4096;
    maximum.result_cap = 4096;
    accepted.push(maximum);
    let mut ignored = Case::numeric("ignored", 7);
    ignored.mode = 1;
    ignored.host_kind = 2;
    ignored.host_start = -1;
    ignored.host_length = -1;
    ignored.set_host(vec![255]);
    ignored.host_start = -1;
    ignored.host_length = -1;
    accepted.push(ignored);
    let mut ignored = base.clone();
    ignored.mode = 1;
    ignored.service_kind = 2;
    ignored.service_start = -1;
    ignored.service_length = -1;
    accepted.push(ignored);
    let mut punctuation = Case::named("[ASCII~]", "service9");
    punctuation.mode = 1;
    accepted.push(punctuation);
    let actual = execute(&accepted);
    for (case, reply) in accepted.iter().zip(actual) {
        assert_eq!(reply.body, synthetic(case, 4), "{case:?}");
        check_native(case, &reply, 1, 1);
    }
    eprintln!(
        "resolver validation: {} local rejection cases across3layouts, {} zero-allocation strided controls, {} accepted exact/maximum/ignored-view cases",
        cases.len(),
        local.len(),
        accepted.len()
    );
}

#[test]
fn resolver_native_lists_errors_scopes_caps_and_head_cleanup_are_atomic() {
    let mut examples: Vec<(Case, String, i64)> = Vec::new();
    for family in 0..3 {
        for kind in 0..2 {
            for layout in 0..3 {
                let mut case = Case::numeric(
                    "127.0.0.1",
                    [0, 1, 32768, 65535][(family + kind + layout) as usize % 4],
                );
                case.mode = 1;
                case.family = family;
                case.kind = kind;
                case.layout = layout;
                let expected = synthetic(&case, 4);
                examples.push((case, expected, 1));
            }
        }
    }
    for (mode, code, system) in [
        (3, -11, 13),
        (4, -2, 0),
        (5, -10, 0),
        (6, -3, 0),
        (7, -1234, 0),
        (21, -8, 0),
        (22, -4, 0),
    ] {
        for layout in 0..3 {
            let mut case = Case::numeric("127.0.0.1", 443);
            case.mode = mode;
            case.layout = layout;
            examples.push((case, format!("E11:4:{code}:{system}:-1"), 0));
        }
    }
    for layout in 0..3 {
        let mut case = Case::numeric("127.0.0.1", 443);
        case.mode = 2;
        case.layout = layout;
        examples.push((case, "E14:5:0:0:0".into(), 0));
    }
    for mode in 8..=15 {
        for bad in [0, 1] {
            if mode == 15 && bad == 0 {
                continue;
            }
            for layout in 0..3 {
                let mut case = Case::numeric("127.0.0.1", 443);
                case.mode = mode;
                case.parameter = bad;
                case.layout = layout;
                let cause = if matches!(mode, 8 | 9 | 10 | 15) {
                    13
                } else {
                    14
                };
                examples.push((case, format!("E{cause}:5:0:0:{bad}"), 1));
            }
        }
    }
    let mut mismatch = Case::numeric("127.0.0.1", 443);
    mismatch.mode = 20;
    mismatch.family = 1;
    mismatch.parameter = 1;
    examples.push((mismatch, "E14:5:0:0:1".into(), 1));
    let mut unspecified = Case::numeric("127.0.0.1", 0);
    unspecified.mode = 18;
    unspecified.service_kind = 2;
    unspecified.parameter = 1;
    examples.push((unspecified, "E14:5:0:0:1".into(), 1));
    let mut unused = Case::numeric("127.0.0.1", 443);
    unused.mode = 19;
    unused.parameter = 1;
    let expected = synthetic(&unused, 4);
    examples.push((unused, expected, 1));
    for (count, cap) in [(1, 1), (4, 4), (4096, 4096), (2, 1), (4097, 4096)] {
        let mut case = Case::numeric("127.0.0.1", 65535);
        case.mode = 16;
        case.parameter = count;
        case.result_cap = cap;
        let expected = if count > cap {
            format!("E12:5:0:0:{cap}")
        } else {
            synthetic(&case, count as usize)
        };
        examples.push((case, expected, 1));
    }
    for count in [1, 2] {
        let mut cycle = Case::numeric("127.0.0.1", 443);
        cycle.mode = 17;
        cycle.parameter = count;
        cycle.result_cap = 3;
        examples.push((cycle, "E12:5:0:0:3".into(), 1));
    }
    let cases: Vec<_> = examples.iter().map(|(case, _, _)| case.clone()).collect();
    let actual = execute(&cases);
    for (index, ((case, expected, frees), reply)) in examples.iter().zip(actual).enumerate() {
        assert_eq!(&reply.body, expected, "native fault{index}: {case:?}");
        check_native(case, &reply, 1, *frees);
    }
    eprintln!(
        "resolver synthetic native matrix: {} cases, backed mixed/duplicate/scoped lists, all22 observer modes, exact4096/overcap and bounded cycles",
        cases.len()
    );
}

#[derive(Debug)]
struct MappingAttempt {
    ordinal: usize,
    size: usize,
    failed: bool,
}
struct AllocationSites {
    allocate: BTreeSet<u64>,
    release: BTreeSet<u64>,
}
fn allocation_sites(path: &std::path::Path) -> AllocationSites {
    let output = run(Command::new("python3")
        .arg(fixture("allocation_sites.py"))
        .arg(path));
    checked(&output, 0);
    let mut sites = AllocationSites {
        allocate: BTreeSet::new(),
        release: BTreeSet::new(),
    };
    for line in String::from_utf8(output.stdout).unwrap().lines() {
        let (kind, address) = line.split_once(' ').unwrap();
        let address = u64::from_str_radix(address, 16).unwrap();
        match kind {
            "A" => {
                sites.allocate.insert(address);
            }
            "F" => {
                sites.release.insert(address);
            }
            "S" => {
                sites.allocate.insert(address);
                sites.release.insert(address);
            }
            _ => panic!("unknown allocation site {line}"),
        }
    }
    assert!(!sites.allocate.is_empty() && !sites.release.is_empty());
    sites
}
fn mapping_ledger(trace: &str, sites: &AllocationSites) -> Vec<MappingAttempt> {
    let mut live = BTreeMap::new();
    let mut attempts = Vec::new();
    let mut ordinal = 0;
    for line in trace.lines() {
        let Some((ip, call)) = line
            .strip_prefix('[')
            .and_then(|line| line.split_once("] "))
        else {
            continue;
        };
        let ip = u64::from_str_radix(ip, 16).unwrap();
        if call.starts_with("mmap(") {
            ordinal += 1;
            if !call.contains("MAP_32BIT") {
                continue;
            }
            assert!(
                sites.allocate.contains(&ip),
                "MAP_32BIT outside verified source/runtime syscall sites: {line}"
            );
            let size: usize = call.split(',').nth(1).unwrap().trim().parse().unwrap();
            let address = call
                .rsplit_once(" = ")
                .unwrap()
                .1
                .split_whitespace()
                .next()
                .unwrap();
            let failed = address == "-1";
            attempts.push(MappingAttempt {
                ordinal,
                size,
                failed,
            });
            if failed {
                assert!(call.contains("ENOMEM"), "{line}");
            } else {
                assert!(live.insert(address.to_owned(), size).is_none(), "{line}");
            }
        } else if call.starts_with("munmap(") {
            let rest = call.strip_prefix("munmap(").unwrap();
            let (address, tail) = rest.split_once(',').unwrap();
            let address_value = u64::from_str_radix(address.trim_start_matches("0x"), 16).unwrap();
            if address_value >= 0x80000000 {
                continue;
            }
            assert!(
                sites.release.contains(&ip),
                "low-address release outside verified source/runtime syscall sites: {line}"
            );
            let size: usize = tail.split_once(')').unwrap().0.trim().parse().unwrap();
            assert_eq!(
                live.remove(address),
                Some(size),
                "unowned/repeated/wrong-size source release: {line}"
            );
            assert!(call.ends_with(" = 0"), "{line}");
        }
    }
    assert!(
        live.is_empty(),
        "unreleased source owners: {live:?}\n{trace}"
    );
    attempts
}

#[test]
fn every_reached_resolver_source_allocation_failure_cleans_both_owner_domains_and_retries() {
    let file = native("allocations.lani");
    let sites = allocation_sites(file.path());
    let trace = common::TempArtifact::new("laniusc_resolve", "allocation_trace", None);
    let execute = |failure: Option<usize>| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-i", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if let Some(ordinal) = failure {
            command.args(["-e", &format!("inject=mmap:error=ENOMEM:when={ordinal}")]);
        }
        command.arg(file.path());
        let output = run(&mut command);
        let events = fs::read_to_string(trace.path()).unwrap();
        (output, events)
    };
    let (output, events) = execute(None);
    checked(&output, 0);
    assert_eq!(output.stdout, b"0\n");
    let baseline = mapping_ledger(&events, &sites);
    assert_eq!(baseline.len(), 4, "{baseline:?}");
    assert_eq!(
        baseline
            .iter()
            .take(3)
            .map(|point| point.size)
            .collect::<Vec<_>>(),
        [97, 17, 56]
    );
    assert!(baseline.iter().all(|point| !point.failed));
    for (index, point) in baseline.iter().enumerate() {
        let (output, events) = execute(Some(point.ordinal));
        checked(&output, 4);
        assert_eq!(
            std::str::from_utf8(&output.stdout).unwrap().trim(),
            (index + 2).to_string()
        );
        let points = mapping_ledger(&events, &sites);
        let failed: Vec<_> = points.iter().filter(|point| point.failed).collect();
        assert_eq!(failed.len(), 1);
        assert_eq!(
            (failed[0].ordinal, failed[0].size),
            (point.ordinal, point.size)
        );
        assert_eq!(events.matches("INJECTED").count(), 1);
    }
    eprintln!(
        "resolver all4 reached source OOM positions pass; requested sizes={:?}; native head released once on result allocation failure and successful recovery after every failure",
        baseline.iter().map(|point| point.size).collect::<Vec<_>>()
    );
}
