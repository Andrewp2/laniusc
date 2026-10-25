//! Real TLS exchange CLI with independent OpenSSL-backed peers and owner/I/O faults.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    ffi::OsString,
    fs,
    os::unix::{
        ffi::{OsStrExt, OsStringExt},
        fs::PermissionsExt,
    },
    path::{Path, PathBuf},
    process::Command,
    sync::OnceLock,
    time::Duration,
};

const MAX: usize = 1_048_576;
const CALLS: usize = 131_072;
fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("sample_programs/library/tls_exchange.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("tls_exchange application", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("tls_exchange: {error}"));
        let file = common::TempArtifact::new("laniusc_tls_exchange", "executable", None);
        file.write_bytes(bytes);
        fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
        file
    })
}
struct Fixtures {
    path: PathBuf,
    original: Vec<(PathBuf, Vec<u8>)>,
}
impl Drop for Fixtures {
    fn drop(&mut self) {
        if std::env::var_os("LANIUS_KEEP_TEMP_ARTIFACTS").is_none() {
            let _ = fs::remove_dir_all(&self.path);
        }
    }
}
fn fixtures() -> &'static Fixtures {
    static FIXTURES: OnceLock<Fixtures> = OnceLock::new();
    FIXTURES.get_or_init(|| {
        let location = common::TempArtifact::new("laniusc_tls_exchange", "fixtures", None);
        let path = location.path().to_owned();
        fs::create_dir(&path).unwrap();
        let output = common::process_output_with_timeout(
            "shared independent TLS certificates",
            Command::new("python3")
                .arg(root().join("tests/fixtures/extended/tls_tcp/peers.py"))
                .arg("fixtures")
                .arg(&path),
            Duration::from_secs(15),
        );
        assert!(output.status.success(), "{output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        let mut chain = fs::read(path.join("leaf.pem")).unwrap();
        chain.extend(fs::read(path.join("ca.pem")).unwrap());
        fs::write(path.join("server-chain.pem"), chain).unwrap();
        fs::write(path.join("seed-short.bin"), [1; 31]).unwrap();
        fs::write(path.join("seed-long.bin"), [1; 33]).unwrap();
        fs::write(path.join("chain-empty.der"), []).unwrap();
        fs::write(path.join("chain-junk.der"), [48, 0, 0]).unwrap();
        fs::write(path.join("chain-excess.der"), vec![0; MAX + 1]).unwrap();
        let leaf = fs::read(path.join("leaf.der")).unwrap();
        fs::write(path.join("chain-nine.der"), leaf.repeat(9)).unwrap();
        fs::write(path.join("anchor-excess.der"), vec![0; MAX + 1]).unwrap();
        // OpenSSL's documented system_default configuration controls TLS1.3
        // suites; Python set_ciphers only controls earlier protocol versions.
        for (name, suites) in [
            ("peer-sha256.cnf", "TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256"),
            ("peer-sha384.cnf", "TLS_AES_256_GCM_SHA384"),
        ] {
            fs::write(path.join(name), format!("openssl_conf = init\nconfig_diagnostics = 1\n[init]\nssl_conf = ssl\n[ssl]\nsystem_default = tls\n[tls]\nCipherSuites = {suites}\n")).unwrap();
        }
        let original = fs::read_dir(&path)
            .unwrap()
            .map(|entry| {
                let path = entry.unwrap().path();
                let data = fs::read(&path).unwrap();
                (path, data)
            })
            .collect();
        // The directory owns these artifacts; TempArtifact's file-only Drop
        // is not used for it. Static fixtures intentionally survive the gates.
        std::mem::forget(location);
        Fixtures { path, original }
    })
}
fn file(name: &str) -> PathBuf {
    fixtures().path.join(name)
}
fn client_arguments(endpoint: &str, identity: &str, anchor: &str) -> Vec<OsString> {
    vec![
        "client".into(),
        endpoint.into(),
        "dns".into(),
        identity.into(),
        file(anchor).into_os_string(),
    ]
}
fn server_arguments(endpoint: &str, seed: &str, chain: &str) -> Vec<OsString> {
    vec![
        "serve".into(),
        endpoint.into(),
        file(seed).into_os_string(),
        file(chain).into_os_string(),
    ]
}
fn payload(size: usize) -> Vec<u8> {
    (0..size)
        .map(|i| ((i * 37) ^ (i >> 7) ^ 0xa5) as u8)
        .collect()
}
fn calls<'a>(events: &'a str, name: &str) -> Vec<&'a str> {
    let prefix = format!("{name}(");
    events
        .lines()
        .filter(|line| line.starts_with(&prefix))
        .collect()
}
fn fields<'a>(line: &'a str, name: &str) -> (&'a str, &'a str) {
    let body = line.strip_prefix(name).unwrap().strip_prefix('(').unwrap();
    let (a, v) = body.rsplit_once(" = ").unwrap();
    (a.trim_end().strip_suffix(')').unwrap(), v)
}
fn result<'a>(line: &'a str, name: &str) -> &'a str {
    fields(line, name).1.split_whitespace().next().unwrap()
}
fn fd(line: &str, name: &str) -> i32 {
    fields(line, name)
        .0
        .split(',')
        .next()
        .unwrap()
        .trim()
        .parse()
        .unwrap()
}
fn request(line: &str, name: &str) -> usize {
    fields(line, name)
        .0
        .rsplit_once(',')
        .unwrap()
        .1
        .trim()
        .parse()
        .unwrap()
}
struct Spec<'a> {
    fixtures: &'a Path,
    input: &'a Path,
    trace: &'a Path,
    executable: &'a Path,
    role: &'a str,
    peer_mode: &'a str,
    arguments: &'a [OsString],
    inject: &'a [String],
    seconds: u32,
    closed_stdout: bool,
}
fn field(out: &mut Vec<u8>, bytes: &[u8]) {
    assert!(bytes.len() <= 8192);
    out.extend((bytes.len() as u32).to_le_bytes());
    out.extend(bytes);
}
impl Spec<'_> {
    fn encode(&self) -> Vec<u8> {
        let mut out = 1u32.to_le_bytes().to_vec();
        for path in [self.fixtures, self.input, self.trace, self.executable] {
            field(&mut out, path.as_os_str().as_bytes());
        }
        field(&mut out, self.role.as_bytes());
        field(&mut out, self.peer_mode.as_bytes());
        assert!(self.arguments.len() <= 16 && self.inject.len() <= 16);
        out.extend((self.arguments.len() as u32).to_le_bytes());
        for argument in self.arguments {
            field(&mut out, argument.as_bytes());
        }
        out.extend((self.inject.len() as u32).to_le_bytes());
        for rule in self.inject {
            field(&mut out, rule.as_bytes());
        }
        out.extend(self.seconds.to_le_bytes());
        out.extend(u32::from(self.closed_stdout).to_le_bytes());
        assert!(out.len() <= 65536);
        out
    }
}
struct Decoder<'a> {
    bytes: &'a [u8],
    at: usize,
}
impl<'a> Decoder<'a> {
    fn byte(&mut self) -> u8 {
        assert!(self.at < self.bytes.len());
        let out = self.bytes[self.at];
        self.at += 1;
        out
    }
    fn word(&mut self) -> u32 {
        assert!(self.bytes.len() - self.at >= 4);
        let out = u32::from_le_bytes(self.bytes[self.at..self.at + 4].try_into().unwrap());
        self.at += 4;
        out
    }
    fn field(&mut self, maximum: usize) -> Vec<u8> {
        let length = self.word() as usize;
        assert!(length <= maximum && length <= self.bytes.len() - self.at);
        let out = self.bytes[self.at..self.at + length].to_vec();
        self.at += length;
        out
    }
    fn text(&mut self) -> String {
        String::from_utf8(self.field(8192)).unwrap()
    }
}
struct Peer {
    openssl: String,
    version: String,
    cipher: String,
    reused: Option<bool>,
    error: Option<String>,
    clean_close: bool,
    received: Vec<u8>,
    sent: Vec<u8>,
}
fn receipt(bytes: &[u8]) -> (i32, Vec<u8>, Vec<u8>, Peer) {
    assert!(bytes.len() <= 4 * (MAX + 1024) + 32768);
    let mut input = Decoder { bytes, at: 0 };
    let status = input.word() as i32;
    let clean = input.byte();
    assert!(clean <= 1);
    let reused = match input.byte() {
        0 => None,
        1 => Some(false),
        2 => Some(true),
        _ => panic!("invalid reuse receipt"),
    };
    let has_error = input.byte();
    assert!(has_error <= 1);
    let openssl = input.text();
    let version = input.text();
    let cipher = input.text();
    let error_text = input.text();
    let error = if has_error == 1 {
        Some(error_text)
    } else {
        assert!(error_text.is_empty());
        None
    };
    let stdout = input.field(MAX + 1024);
    let stderr = input.field(1024);
    let received = input.field(MAX + 1024);
    let sent = input.field(MAX + 1024);
    assert_eq!(input.at, bytes.len());
    (
        status,
        stdout,
        stderr,
        Peer {
            openssl,
            version,
            cipher,
            reused,
            error,
            clean_close: clean == 1,
            received,
            sent,
        },
    )
}
struct Run {
    status: i32,
    stdout: Vec<u8>,
    stderr: Vec<u8>,
    events: String,
    peer: Option<Peer>,
    maps: usize,
    failures: Vec<usize>,
    open_attempts: usize,
    created_fds: usize,
    close_attempts: usize,
}
fn inspect(
    status: i32,
    stdout: Vec<u8>,
    stderr: Vec<u8>,
    events: String,
    peer: Option<Peer>,
    inject: &[String],
) -> Run {
    for (path, data) in &fixtures().original {
        assert_eq!(
            fs::read(path).unwrap(),
            *data,
            "credential file changed: {path:?}"
        );
    }
    for rule in inject {
        let name = rule.split(':').next().unwrap();
        let reached = calls(&events, name)
            .into_iter()
            .filter(|line| line.contains("INJECTED"))
            .collect::<Vec<_>>();
        if rule.ends_with('+') {
            assert!(
                !reached.is_empty() && reached.len() <= CALLS,
                "unreached {rule}: {events}"
            );
        } else {
            assert_eq!(reached.len(), 1, "unreached/repeated {rule}: {events}");
        }
        if let Some(error) = rule.split("error=").nth(1) {
            assert!(
                reached
                    .iter()
                    .all(|line| line.contains(error.split(':').next().unwrap())),
                "{events}"
            );
        }
        if let Some(value) = rule.split("retval=").nth(1) {
            assert!(
                reached
                    .iter()
                    .all(|line| result(line, name) == value.split(':').next().unwrap()),
                "{events}"
            );
        }
    }
    if inject.is_empty() {
        assert!(!events.contains("INJECTED"), "{events}");
    }
    let mut memory = BTreeMap::<u64, usize>::new();
    let mut descriptors = BTreeMap::<i32, &str>::new();
    let mut maps = 0;
    let mut frees = 0;
    let mut failures = Vec::new();
    let mut open_attempts = 0;
    let mut created_fds = 0;
    let mut close_attempts = 0;
    let mut entropy = false;
    for line in events.lines() {
        if line.starts_with("getrandom(") {
            entropy = true;
            assert!(line.contains("GRND_NONBLOCK"), "{events}");
        }
        if line.starts_with("mmap(") {
            assert!(!entropy, "allocation after ephemeral entropy: {events}");
            maps += 1;
            let (args, value) = fields(line, "mmap");
            let size = args.split(',').nth(1).unwrap().trim().parse().unwrap();
            if let Some(address) = value.split_whitespace().next().unwrap().strip_prefix("0x") {
                assert!(
                    memory
                        .insert(u64::from_str_radix(address, 16).unwrap(), size)
                        .is_none(),
                    "{events}"
                );
            } else {
                assert!(
                    value.contains("ENOMEM") && value.contains("INJECTED"),
                    "{events}"
                );
                failures.push(maps);
            }
        } else if line.starts_with("munmap(") {
            let (args, value) = fields(line, "munmap");
            assert_eq!(value, "0");
            let (address, size) = args.split_once(',').unwrap();
            let address =
                u64::from_str_radix(address.trim().strip_prefix("0x").unwrap(), 16).unwrap();
            assert_eq!(
                memory.remove(&address),
                Some(size.trim().parse().unwrap()),
                "wrong/unknown/double free: {events}"
            );
            frees += 1;
        } else if line.starts_with("openat(") {
            open_attempts += 1;
            for flag in ["O_RDONLY", "O_NOFOLLOW", "O_NONBLOCK", "O_CLOEXEC"] {
                assert!(line.contains(flag), "{events}");
            }
            for flag in ["O_WRONLY", "O_RDWR", "O_CREAT", "O_TRUNC"] {
                assert!(!line.contains(flag), "{events}");
            }
            let value = result(line, "openat").parse::<i32>().unwrap();
            if value >= 0 {
                assert!(
                    value > 2 && descriptors.insert(value, "file").is_none(),
                    "{events}"
                );
                created_fds += 1;
            }
        } else if line.starts_with("socket(") || line.starts_with("accept4(") {
            let name = if line.starts_with("socket(") {
                assert!(
                    line.contains("SOCK_NONBLOCK") && line.contains("SOCK_CLOEXEC"),
                    "{events}"
                );
                "socket"
            } else {
                assert!(
                    line.contains("SOCK_NONBLOCK") && line.contains("SOCK_CLOEXEC"),
                    "{events}"
                );
                "accept4"
            };
            let value = result(line, name).parse::<i32>().unwrap();
            if value >= 0 {
                assert!(
                    value > 2 && descriptors.insert(value, "socket").is_none(),
                    "{events}"
                );
                created_fds += 1;
            }
        } else if line.starts_with("close(") {
            let (args, value) = fields(line, "close");
            let descriptor = args.parse::<i32>().unwrap();
            assert!(
                descriptors.remove(&descriptor).is_some(),
                "unknown/double close: {events}"
            );
            assert!(
                value == "0" || (value.starts_with("-1") && value.contains("INJECTED")),
                "{events}"
            );
            close_attempts += 1;
        } else if line.starts_with("read(") {
            let descriptor = fd(line, "read");
            if descriptor != 0 {
                assert_eq!(descriptors.get(&descriptor), Some(&"file"), "{events}");
            } else {
                assert!(
                    !descriptors.values().any(|kind| *kind == "file"),
                    "files must close before stdin: {events}"
                );
            }
            assert!((1..=1024).contains(&request(line, "read")));
        } else if line.starts_with("write(") {
            assert!(matches!(fd(line, "write"), 1 | 2), "{events}");
            assert!((1..=1024).contains(&request(line, "write")));
        }
        for forbidden in ["mremap(", "brk("] {
            assert!(
                !line.starts_with(forbidden),
                "unexpected allocation family: {events}"
            );
        }
    }
    assert!(
        memory.is_empty() && descriptors.is_empty(),
        "unretired owners: {memory:?}/{descriptors:?}\n{events}"
    );
    assert_eq!(frees, maps - failures.len());
    assert_eq!(created_fds, close_attempts);
    let attempted = events.lines().filter(|line| line.contains('(')).count();
    assert!(
        attempted <= CALLS,
        "shared syscall allowance exceeded: {attempted}"
    );
    Run {
        status,
        stdout,
        stderr,
        events,
        peer,
        maps,
        failures,
        open_attempts,
        created_fds,
        close_attempts,
    }
}
fn run(
    input: &[u8],
    args: Vec<OsString>,
    inject: &[String],
    loopback: Option<&str>,
    closed_stdout: bool,
    seconds: u32,
    peer_mode: &str,
) -> Run {
    let data = common::TempArtifact::new("laniusc_tls_exchange", "stdin", None);
    data.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_tls_exchange", "trace", None);
    let (status, stdout, stderr, peer) = if let Some(role) = loopback {
        let spec = common::TempArtifact::new("laniusc_tls_exchange", "peer_spec", None);
        spec.write_bytes(
            Spec {
                fixtures: &fixtures().path,
                input: data.path(),
                trace: trace.path(),
                executable: executable().path(),
                role,
                peer_mode,
                arguments: &args,
                inject,
                seconds,
                closed_stdout,
            }
            .encode(),
        );
        let output = common::process_output_with_timeout(
            "TLS exchange CLI with independent OpenSSL peer",
            Command::new("python3")
                .env(
                    "OPENSSL_CONF",
                    file(if peer_mode.starts_with("aes256-") {
                        "peer-sha384.cnf"
                    } else {
                        "peer-sha256.cnf"
                    }),
                )
                .arg(root().join("tests/fixtures/extended/tls_exchange/peer.py"))
                .arg(spec.path()),
            Duration::from_secs((seconds + 10) as u64),
        );
        assert!(output.status.success(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
        let (status, stdout, stderr, peer) = receipt(&output.stdout);
        (status, stdout, stderr, Some(peer))
    } else {
        let mut command = Command::new("timeout");
        command.args(["--kill-after=1s",&format!("{seconds}s"),"strace","-qq","-o"]).arg(trace.path()).args(["-e","trace=rt_sigaction,openat,close,read,write,mmap,munmap,mremap,brk,socket,connect,bind,listen,accept4,poll,fcntl,getsockopt,getpeername,sendto,recvfrom,shutdown,getrandom,clock_gettime","-e","signal=none"]);
        for rule in inject {
            command.arg("-e").arg(format!("inject={rule}"));
        }
        command
            .arg(executable().path())
            .args(args)
            .stdin(fs::File::open(data.path()).unwrap());
        let output = common::process_output_with_timeout(
            "TLS exchange pre-network CLI case",
            &mut command,
            Duration::from_secs((seconds + 3) as u64),
        );
        (
            output.status.code().unwrap_or(-1),
            output.stdout,
            output.stderr,
            None,
        )
    };
    assert_eq!(fs::read(data.path()).unwrap(), input);
    inspect(
        status,
        stdout,
        stderr,
        fs::read_to_string(trace.path()).unwrap(),
        peer,
        inject,
    )
}
fn checked(run: &Run, status: i32, stdout: &[u8]) {
    assert_eq!(
        run.status,
        status,
        "stderr={}\n{}",
        String::from_utf8_lossy(&run.stderr),
        run.events
    );
    assert_eq!(run.stdout, stdout, "{}", run.events);
    if status == 0 {
        assert!(run.stderr.is_empty(), "{:?}", run.stderr);
    } else if !run.stderr.is_empty() {
        assert!(run.stderr.starts_with(b"tls-exchange primary="));
        assert!(run.stderr.windows(9).any(|window| window == b" cleanup="));
    }
}
fn independent_peer(run: &Run, input: &[u8]) {
    independent_peer_suites(
        run,
        input,
        &["TLS_AES_128_GCM_SHA256", "TLS_CHACHA20_POLY1305_SHA256"],
    );
}
fn independent_peer_suites(run: &Run, input: &[u8], suites: &[&str]) {
    let peer = run.peer.as_ref().unwrap();
    assert!(peer.openssl.starts_with("OpenSSL "));
    assert_eq!(peer.version, "TLSv1.3");
    assert!(
        suites.contains(&peer.cipher.as_str()),
        "unexpected negotiated suite: {}",
        peer.cipher
    );
    assert_eq!(peer.reused, Some(false));
    assert!(peer.error.is_none(), "{:?}", peer.error);
    assert!(peer.clean_close);
    assert_eq!(peer.received, input);
    assert_eq!(peer.sent, input);
}
#[test]
fn tls_exchange_cli_interoperates_with_openssl_in_both_directions() {
    let mut count = 0;
    for role in ["client", "serve"] {
        for size in [0, 257, MAX] {
            let input = payload(size);
            let args = if role == "client" {
                client_arguments("@ENDPOINT@", "path.example", "root.der")
            } else {
                server_arguments("@ENDPOINT@", "seed.bin", "chain.der")
            };
            let observed = run(&input, args, &[], Some(role), false, 12, "echo");
            checked(&observed, 0, &input);
            independent_peer(&observed, &input);
            assert!(!calls(&observed.events, "getrandom").is_empty());
            if role == "serve" {
                assert!(!calls(&observed.events, "read")
                    .iter()
                    .any(|line| fd(line, "read") == 0));
            }
            count += 1;
        }
    }
    let mut args = client_arguments("@ENDPOINT@", "127.0.0.1", "root.der");
    args[2] = "ip".into();
    let input = payload(29);
    let observed = run(&input, args, &[], Some("client"), false, 9, "echo");
    checked(&observed, 0, &input);
    independent_peer(&observed, &input);
    count += 1;
    for (identity, anchor, peer, wanted) in [
        ("wrong.example", "root.der", "echo", b"".as_slice()),
        ("path.example", "wrong-root.der", "echo", b""),
        ("path.example", "root.der", "raw", b""),
        (
            "path.example",
            "root.der",
            "truncate",
            b"authenticated-before-truncation",
        ),
    ] {
        let observed = run(
            &payload(31),
            client_arguments("@ENDPOINT@", identity, anchor),
            &[],
            Some("client"),
            false,
            9,
            peer,
        );
        checked(&observed, 5, wanted);
        count += 1;
    }
    eprintln!("tls_exchange interop:one shared strictELF,{count} native CLI cases,actual OpenSSL-backed TLS1.3 peers both directions including binary/empty/1MiB,explicit trust and close_notify; full protocol matrix belongs tls_tcp");
}
#[test]
fn tls_exchange_dual_policy_interoperates_with_p256_only_openssl_peers() {
    for role in ["client", "serve"] {
        let input = payload(1025);
        let args = if role == "client" {
            client_arguments("@ENDPOINT@", "path.example", "root.der")
        } else {
            server_arguments("@ENDPOINT@", "seed.bin", "chain.der")
        };
        let observed = run(&input, args, &[], Some(role), false, 12, "p256");
        checked(&observed, 0, &input);
        independent_peer(&observed, &input);
        let entropy = calls(&observed.events, "getrandom");
        assert!(!entropy.is_empty());
        let first: usize = fields(entropy[0], "getrandom")
            .0
            .rsplit(',')
            .nth(1)
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        assert_eq!(
            first, 96,
            "application dual policy uses independent canonical slots"
        );
    }
    eprintln!("tls_exchange P-256:2 real independent peers,default dual policy with initial X share,forced P fallback/requested-group retry,exact binary/authenticated publication and owner ledgers");
}

#[test]
fn tls_exchange_default_policy_interoperates_with_aes256_sha384_only_peers() {
    for role in ["client", "serve"] {
        for peer in ["aes256-x25519", "aes256-p256"] {
            let input = payload(1025);
            let args = if role == "client" {
                client_arguments("@ENDPOINT@", "path.example", "root.der")
            } else {
                server_arguments("@ENDPOINT@", "seed.bin", "chain.der")
            };
            let observed = run(&input, args, &[], Some(role), false, 12, peer);
            checked(&observed, 0, &input);
            independent_peer_suites(&observed, &input, &["TLS_AES_256_GCM_SHA384"]);
        }
    }
    eprintln!("tls_exchange AES256/SHA384:4 real peers force the third offered suite, both roles/groups, actual HRR from initial X share with P-only server, exact binary publication/trust/clean close and owner ledgers");
}

#[test]
fn tls_exchange_cli_preflight_files_caps_and_io_failures() {
    let mut count = 0;
    for args in [
        vec![],
        vec![OsString::from("client")],
        vec![
            "unknown".into(),
            "127.0.0.1:1".into(),
            "x".into(),
            "y".into(),
        ],
        vec![
            "client".into(),
            "not-numeric:443".into(),
            "dns".into(),
            "path.example".into(),
            file("root.der").into_os_string(),
        ],
        client_arguments("127.0.0.1:0", "path.example", "root.der"),
        client_arguments("127.0.0.1:1", "*.example", "root.der"),
        vec![
            "client".into(),
            "127.0.0.1:1".into(),
            "ip".into(),
            "fe80::1%1".into(),
            file("root.der").into_os_string(),
        ],
        vec![
            "client".into(),
            "127.0.0.1:1".into(),
            "dns".into(),
            OsString::from_vec(vec![255]),
            file("root.der").into_os_string(),
        ],
        vec![
            "serve".into(),
            "127.0.0.1:1".into(),
            "".into(),
            file("chain.der").into_os_string(),
        ],
    ] {
        let observed = run(b"not consumed", args, &[], None, false, 8, "echo");
        checked(&observed, 2, b"");
        assert!(
            calls(&observed.events, "read").is_empty()
                && calls(&observed.events, "socket").is_empty()
                && calls(&observed.events, "clock_gettime").is_empty()
        );
        assert_eq!(observed.open_attempts, 0);
        count += 1;
    }
    for (seed, chain, status) in [
        ("seed-short.bin", "chain.der", 2),
        ("seed-long.bin", "chain.der", 2),
        ("seed.bin", "chain-empty.der", 5),
        ("seed.bin", "chain-junk.der", 5),
        ("seed.bin", "chain-nine.der", 7),
        ("seed.bin", "chain-excess.der", 7),
    ] {
        let observed = run(
            b"unused",
            server_arguments("127.0.0.1:1", seed, chain),
            &[],
            None,
            false,
            8,
            "echo",
        );
        checked(&observed, status, b"");
        assert!(calls(&observed.events, "socket").is_empty());
        assert!(!calls(&observed.events, "read")
            .iter()
            .any(|line| fd(line, "read") == 0));
        if seed != "seed.bin" {
            assert_eq!(observed.open_attempts, 1);
        }
        count += 1;
    }
    for (input, anchor) in [
        (vec![0; MAX + 1], "root.der"),
        (vec![], "anchor-excess.der"),
    ] {
        let observed = run(
            &input,
            client_arguments("127.0.0.1:1", "path.example", anchor),
            &[],
            None,
            false,
            8,
            "echo",
        );
        checked(&observed, 7, b"");
        assert!(calls(&observed.events, "socket").is_empty());
        let reads = calls(&observed.events, "read");
        assert_eq!(request(reads.last().unwrap(), "read"), 1);
        assert_eq!(result(reads.last().unwrap(), "read"), "1");
        count += 1;
    }
    for rule in [
        "openat:error=EIO:when=1",
        "read:error=EIO:when=1",
        "read:retval=1025:when=1",
        "close:error=EIO:when=1",
    ] {
        let observed = run(
            b"",
            client_arguments("127.0.0.1:1", "path.example", "root.der"),
            &[rule.into()],
            None,
            false,
            8,
            "echo",
        );
        checked(&observed, 3, b"");
        assert!(calls(&observed.events, "socket").is_empty());
        assert!(!calls(&observed.events, "read")
            .iter()
            .any(|line| fd(line, "read") == 0));
        count += 1;
    }
    let input = payload(17);
    for rule in [
        "read:error=EINTR:when=1",
        "read:error=EINTR:when=2",
        "write:error=EINTR:when=1",
        "write:retval=1:when=1",
    ] {
        let observed = run(
            &input,
            client_arguments("@ENDPOINT@", "path.example", "root.der"),
            &[rule.into()],
            Some("client"),
            false,
            9,
            "echo",
        );
        let wanted = if rule.starts_with("write:retval") {
            &input[1..]
        } else {
            &input
        };
        checked(&observed, 0, wanted);
        independent_peer(&observed, &input);
        count += 1;
    }
    let observed = run(
        &input,
        client_arguments("@ENDPOINT@", "path.example", "root.der"),
        &[],
        Some("client"),
        true,
        9,
        "echo",
    );
    checked(&observed, 3, b"");
    assert!(calls(&observed.events, "write")
        .iter()
        .any(|line| fd(line, "write") == 1
            && line.contains("EPIPE")
            && !line.contains("INJECTED")));
    count += 1;
    eprintln!("tls_exchange preflight:{count} native cases,CLI before host clock/files/network,seed/chain/stdin caps and actual excess probes,host/close failures,retry/reported-short-write controls and real EPIPE");
}
#[test]
fn tls_exchange_cli_releases_owners_preserves_errors_and_bounds_host_attempts() {
    let input = payload(13);
    let mut count = 0;
    for role in ["client", "serve"] {
        let args = if role == "client" {
            client_arguments("@ENDPOINT@", "path.example", "root.der")
        } else {
            server_arguments("@ENDPOINT@", "seed.bin", "chain.der")
        };
        let baseline = run(&input, args.clone(), &[], Some(role), false, 9, "echo");
        checked(&baseline, 0, &input);
        independent_peer(&baseline, &input);
        count += 1;
        for ordinal in 1..=baseline.maps {
            let rule = format!("mmap:error=ENOMEM:when={ordinal}");
            let observed = run(&input, args.clone(), &[rule], Some(role), false, 9, "echo");
            checked(&observed, 4, b"");
            assert_eq!(observed.failures, vec![ordinal]);
            count += 1;
        }
    }
    let base = run(
        &input,
        client_arguments("@ENDPOINT@", "path.example", "root.der"),
        &[],
        Some("client"),
        false,
        9,
        "echo",
    );
    checked(&base, 0, &input);
    count += 1;
    let clocks = calls(&base.events, "clock_gettime");
    let realtime = clocks
        .iter()
        .enumerate()
        .filter_map(|(index, line)| line.contains("CLOCK_REALTIME").then_some(index + 1))
        .collect::<Vec<_>>();
    assert_eq!(realtime.len(), 1);
    for rule in [
        format!("clock_gettime:error=EIO:when={}", realtime[0]),
        "getrandom:error=EAGAIN:when=1".into(),
        "socket:error=EMFILE:when=1".into(),
    ] {
        let observed = run(
            &input,
            client_arguments("@ENDPOINT@", "path.example", "root.der"),
            &[rule],
            Some("client"),
            false,
            9,
            "echo",
        );
        checked(&observed, 3, b"");
        count += 1;
    }
    let expired = 1262304000i64
        .to_le_bytes()
        .into_iter()
        .chain(0i64.to_le_bytes())
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    let rule = format!(
        "clock_gettime:retval=0:poke_exit=@arg2={expired}:when={}",
        realtime[0]
    );
    let observed = run(
        &input,
        client_arguments("@ENDPOINT@", "path.example", "root.der"),
        &[rule],
        Some("client"),
        false,
        9,
        "echo",
    );
    checked(&observed, 5, b"");
    count += 1;
    let wrong = run(
        &input,
        client_arguments("@ENDPOINT@", "wrong.example", "root.der"),
        &[],
        Some("client"),
        false,
        9,
        "echo",
    );
    checked(&wrong, 5, b"");
    let close_count = calls(&wrong.events, "close").len();
    assert!(close_count >= 2);
    count += 1;
    let rule = format!("close:error=EIO:when={close_count}");
    let observed = run(
        &input,
        client_arguments("@ENDPOINT@", "wrong.example", "root.der"),
        &[rule],
        Some("client"),
        false,
        9,
        "echo",
    );
    checked(&observed, 3, b"");
    let diagnostic = String::from_utf8(observed.stderr.clone()).unwrap();
    assert!(
        diagnostic.contains("primary=5") && diagnostic.contains("cleanup=io errno=5"),
        "{diagnostic}"
    );
    count += 1;
    // Freeze the monotonic observations at zero, then repeatedly interrupt only
    // stdin. No wall-clock or network operation is reached; this isolates the
    // shared host-attempt cap from physical strace speed and the5s deadline.
    let reads = calls(&base.events, "read");
    let first_stdin = reads.iter().position(|line| fd(line, "read") == 0).unwrap() + 1;
    let rules = vec![
        "clock_gettime:retval=0:poke_exit=@arg2=00000000000000000000000000000000:when=1+".into(),
        format!("read:error=EINTR:when={first_stdin}+"),
    ];
    let observed = run(
        &input,
        client_arguments("127.0.0.1:1", "path.example", "root.der"),
        &rules,
        None,
        false,
        30,
        "echo",
    );
    checked(&observed, 7, b"");
    assert!(calls(&observed.events, "socket").is_empty());
    let diagnostic = String::from_utf8(observed.stderr.clone()).unwrap();
    assert!(diagnostic.contains("cause=call-limit"), "{diagnostic}");
    assert!(calls(&observed.events, "read").len() > 1000);
    count += 1;
    eprintln!("tls_exchange owners:{count} native cases,each observed setup allocation denied in both roles,exact memory/descriptor retirement,one explicit realtime sample,entropy/clock/socket failure,primary TLS plus cleanup error retained,and131072shared syscall credits");
}
