//! Real pure Ed25519 detached signatures; independent libsodium oracle and owner ledgers.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    ffi::OsString,
    fs,
    os::unix::{
        ffi::OsStringExt,
        fs::{symlink, PermissionsExt},
    },
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    sync::OnceLock,
    time::Instant,
};
const MAX: usize = 1_048_576;
const CALLS: usize = 131_072;
fn build_executable() -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/sign_bytes.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("sign_bytes application", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("sign_bytes: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_sign_bytes", "executable", None);
    file.write_bytes(bytes);
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(build_executable)
}
fn key_file(bytes: &[u8]) -> common::TempArtifact {
    let file = common::TempArtifact::new("laniusc_sign_bytes", "key", None);
    file.write_bytes(bytes);
    file
}
fn pattern(length: usize) -> Vec<u8> {
    (0..length)
        .map(|index| ((index * 73 + index / 11) & 255) as u8)
        .collect()
}
fn unhex(value: &str) -> Vec<u8> {
    assert_eq!(value.len() % 2, 0);
    value
        .as_bytes()
        .chunks_exact(2)
        .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap())
        .collect()
}
fn sign_args(seed: &Path) -> Vec<OsString> {
    vec!["sign".into(), seed.as_os_str().to_owned()]
}
fn verify_args(public: &Path, signature: &Path) -> Vec<OsString> {
    vec![
        "verify".into(),
        public.as_os_str().to_owned(),
        signature.as_os_str().to_owned(),
    ]
}
fn oracle(mode: &str, key: &Path, signature: &Path, input: &[u8]) -> Output {
    let file = common::TempArtifact::new("laniusc_sign_bytes", "oracle", None);
    file.write_bytes(input);
    Command::new("timeout").args(["--kill-after=1s","5s","python3","-c",r#"import ctypes as c,ctypes.util,sys
mode,keypath,sigpath,path=sys.argv[1:]
s=c.CDLL(ctypes.util.find_library('sodium') or 'libsodium.so.23'); assert s.sodium_init()>=0
pair=s.crypto_sign_seed_keypair; sign=s.crypto_sign_detached; verify=s.crypto_sign_verify_detached
pair.argtypes=[c.c_void_p,c.c_void_p,c.c_void_p]; pair.restype=c.c_int
sign.argtypes=[c.c_void_p,c.POINTER(c.c_ulonglong),c.c_void_p,c.c_ulonglong,c.c_void_p];sign.restype=c.c_int
verify.argtypes=[c.c_void_p,c.c_void_p,c.c_ulonglong,c.c_void_p];verify.restype=c.c_int
buf=lambda b:c.create_string_buffer(b,max(1,len(b)))
key=open(keypath,'rb').read();assert len(key)==32
data=open(path,'rb').read()
if mode=='sign':
    pk=c.create_string_buffer(32);sk=c.create_string_buffer(64);sig=c.create_string_buffer(64);n=c.c_ulonglong()
    assert pair(pk,sk,buf(key))==0
    assert sign(sig,c.byref(n),buf(data),len(data),sk)==0 and n.value==64
    sys.stdout.buffer.write(pk.raw+sig.raw)
else:
    sig=open(sigpath,'rb').read();assert len(sig)==64
    if verify(buf(sig),buf(data),len(data),buf(key))!=0:sys.exit(5)
"#,mode]).arg(key).arg(signature).arg(file.path()).output().unwrap()
}
fn reference(seed: &Path, input: &[u8]) -> (Vec<u8>, Vec<u8>) {
    let out = oracle("sign", seed, Path::new("-"), input);
    assert!(out.status.success(), "{out:?}");
    assert!(out.stderr.is_empty());
    assert_eq!(out.stdout.len(), 96);
    (out.stdout[..32].to_vec(), out.stdout[32..].to_vec())
}
fn oracle_valid(public: &Path, signature: &Path, input: &[u8]) -> bool {
    let out = oracle("verify", public, signature, input);
    assert!(out.stdout.is_empty() && out.stderr.is_empty(), "{out:?}");
    match out.status.code() {
        Some(0) => true,
        Some(5) => false,
        _ => panic!("{out:?}"),
    }
}
fn calls<'a>(events: &'a str, name: &str) -> Vec<&'a str> {
    let p = format!("{name}(");
    events.lines().filter(|line| line.starts_with(&p)).collect()
}
fn result<'a>(line: &'a str, name: &str) -> (&'a str, &'a str) {
    let body = line.strip_prefix(name).unwrap().strip_prefix('(').unwrap();
    let (a, v) = body.rsplit_once('=').unwrap();
    (a.trim_end().strip_suffix(')').unwrap(), v.trim())
}
fn request(line: &str, name: &str) -> usize {
    result(line, name)
        .0
        .rsplit_once(',')
        .unwrap()
        .1
        .trim()
        .parse()
        .unwrap()
}
fn fd(line: &str, name: &str) -> i32 {
    result(line, name)
        .0
        .split(',')
        .next()
        .unwrap()
        .trim()
        .parse()
        .unwrap()
}
struct Run {
    output: Output,
    events: String,
    maps: usize,
    failures: Vec<usize>,
    opened: usize,
    closed: usize,
    file_reads: Vec<Vec<String>>,
    verifying: bool,
}
fn run(
    exe: &common::TempArtifact,
    input: &[u8],
    args: &[OsString],
    inject: &[&str],
    closed: bool,
    seconds: &str,
) -> Run {
    let fixed_snapshots = args
        .iter()
        .skip(1)
        .filter_map(|path| {
            let path = PathBuf::from(path);
            fs::metadata(&path)
                .ok()
                .filter(|metadata| metadata.is_file())
                .map(|_| {
                    let bytes = fs::read(&path).unwrap();
                    (path, bytes)
                })
        })
        .collect::<Vec<_>>();
    let data = common::TempArtifact::new("laniusc_sign_bytes", "stdin", None);
    data.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_sign_bytes", "trace", None);
    let mut command = Command::new("timeout");
    command
        .args(["--kill-after=1s", seconds, "strace", "-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=rt_sigaction,openat,close,read,write,mmap,mremap,munmap",
            "-e",
            "signal=none",
        ]);
    for rule in inject {
        command.arg("-e").arg(format!("inject={rule}"));
    }
    command
        .arg(exe.path())
        .args(args)
        .stdin(Stdio::from(fs::File::open(data.path()).unwrap()));
    if closed {
        let (r, w) = std::io::pipe().unwrap();
        drop(r);
        command.stdout(w);
    }
    let output = command.output().unwrap();
    for (path, bytes) in fixed_snapshots {
        assert_eq!(fs::read(path).unwrap(), bytes, "fixed input file changed");
    }
    let events = fs::read_to_string(trace.path()).unwrap();
    for rule in inject {
        let name = rule.split(':').next().unwrap();
        let reached = calls(&events, name)
            .into_iter()
            .filter(|line| line.contains("INJECTED"))
            .collect::<Vec<_>>();
        if rule.ends_with('+') {
            assert!(!reached.is_empty() && reached.len() <= CALLS, "{events}");
        } else {
            assert_eq!(reached.len(), 1, "unreached/repeated {rule}: {events}");
        }
        if let Some(tail) = rule.split("error=").nth(1) {
            assert!(
                reached
                    .iter()
                    .all(|line| line.contains(tail.split(':').next().unwrap())),
                "{events}"
            );
        }
        if let Some(tail) = rule.split("retval=").nth(1) {
            assert_eq!(
                result(reached[0], name)
                    .1
                    .split_whitespace()
                    .next()
                    .unwrap(),
                tail.split(':').next().unwrap(),
                "{events}"
            );
        }
    }
    if inject.is_empty() {
        assert!(!events.contains("INJECTED"), "{events}");
    }
    let mut live = BTreeMap::<u64, (usize, usize)>::new();
    let mut maps = 0;
    let mut successful = 0;
    let mut releases = 0;
    let mut failures = Vec::new();
    let mut publishing = false;
    let mut owner = None;
    let mut opened = 0;
    let mut closed_count = 0;
    let mut file_reads = Vec::<Vec<String>>::new();
    let mut input_started = false;
    for line in events.lines() {
        if line.starts_with("write(") {
            publishing = true;
        }
        if line.starts_with("mmap(") {
            assert!(!publishing, "allocation during publication: {events}");
            let (a, v) = result(line, "mmap");
            let mut fields = a.split(',').map(str::trim);
            assert_eq!(fields.next(), Some("NULL"));
            let length = fields.next().unwrap().parse().unwrap();
            assert!(length > 0);
            maps += 1;
            if let Some(address) = v.split_whitespace().next().unwrap().strip_prefix("0x") {
                assert!(!v.contains("INJECTED"));
                let address = u64::from_str_radix(address, 16).unwrap();
                assert!(
                    live.insert(address, (successful, length)).is_none(),
                    "{events}"
                );
                successful += 1;
            } else {
                assert!(
                    v.starts_with("-1") && v.contains("ENOMEM") && v.contains("INJECTED"),
                    "{events}"
                );
                failures.push(maps);
            }
        } else if line.starts_with("munmap(") {
            let (a, v) = result(line, "munmap");
            assert_eq!(v, "0");
            let (address, length) = a.split_once(',').unwrap();
            let address =
                u64::from_str_radix(address.trim().strip_prefix("0x").unwrap(), 16).unwrap();
            let (_, owned) = live
                .remove(&address)
                .unwrap_or_else(|| panic!("unknown/double release: {events}"));
            assert_eq!(length.trim().parse::<usize>().unwrap(), owned, "{events}");
            releases += 1;
        } else if line.starts_with("mremap(") {
            panic!("unexpected raw relocation: {events}");
        } else if line.starts_with("openat(") {
            assert!(
                owner.is_none() && !input_started,
                "fixed files must precede stdin: {events}"
            );
            for flag in ["O_NOFOLLOW", "O_NONBLOCK", "O_CLOEXEC"] {
                assert!(line.contains(flag), "{events}");
            }
            assert!(line.contains("O_RDONLY"), "{events}");
            for forbidden in ["O_WRONLY", "O_RDWR", "O_CREAT", "O_TRUNC"] {
                assert!(!line.contains(forbidden), "{events}");
            }
            let (_, v) = result(line, "openat");
            let value: i32 = v.split_whitespace().next().unwrap().parse().unwrap();
            if value >= 0 {
                assert!(opened < 2);
                assert!(value > 2);
                owner = Some(value);
                file_reads.push(Vec::new());
                opened += 1;
            }
        } else if line.starts_with("close(") {
            let (a, v) = result(line, "close");
            let descriptor = a.trim().parse::<i32>().unwrap();
            assert_eq!(
                owner.take(),
                Some(descriptor),
                "unknown/double close: {events}"
            );
            assert!(
                v == "0" || (v.starts_with("-1") && v.contains("INJECTED")),
                "{events}"
            );
            closed_count += 1;
        } else if line.starts_with("read(") {
            let descriptor = fd(line, "read");
            if descriptor == 0 {
                input_started = true;
                assert!(
                    owner.is_none(),
                    "key must be retired before stdin: {events}"
                );
            } else {
                assert_eq!(owner, Some(descriptor), "{events}");
                file_reads.last_mut().unwrap().push(line.to_owned());
            }
        }
    }
    assert!(live.is_empty(), "leaked mappings: {live:?}\n{events}");
    assert_eq!(releases, successful);
    assert!(owner.is_none(), "unclosed key: {events}");
    assert_eq!(opened, closed_count);
    Run {
        output,
        events,
        maps,
        failures,
        opened,
        closed: closed_count,
        file_reads,
        verifying: args.first().is_some_and(|arg| arg == "verify"),
    }
}
fn stdin_reads(run: &Run) -> Vec<&str> {
    calls(&run.events, "read")
        .into_iter()
        .filter(|line| fd(line, "read") == 0)
        .collect()
}
fn checked(run: &Run, status: i32, stdout: &[u8], signal_ok: bool) {
    assert_eq!(
        run.output.status.code(),
        Some(status),
        "{:?}\n{}",
        run.output,
        run.events
    );
    assert_eq!(run.output.stdout, stdout, "{}", run.events);
    assert!(run.output.stderr.is_empty(), "{:?}", run.output);
    let actions = calls(&run.events, "rt_sigaction");
    assert_eq!(actions.len(), 1);
    assert!(actions[0].contains("SIGPIPE") && actions[0].contains("SIG_IGN"));
    if signal_ok {
        assert_eq!(result(actions[0], "rt_sigaction").1, "0");
    } else {
        assert!(actions[0].contains("EINTR") && actions[0].contains("INJECTED"));
    }
    let reads = calls(&run.events, "read");
    let writes = calls(&run.events, "write");
    assert!(reads.len() + writes.len() <= CALLS);
    for line in &reads {
        assert!((1..=1024).contains(&request(line, "read")));
    }
    for line in &writes {
        assert_eq!(fd(line, "write"), 1);
        assert!((1..=64).contains(&request(line, "write")));
    }
    if status == 0 || status == 5 || !writes.is_empty() {
        let stdin = stdin_reads(run);
        assert_eq!(
            result(stdin.last().unwrap(), "read").1,
            "0",
            "publication requires EOF: {}",
            run.events
        );
        let last_read = run
            .events
            .lines()
            .enumerate()
            .filter_map(|(i, line)| line.starts_with("read(").then_some(i))
            .last()
            .unwrap();
        if let Some(write) = run
            .events
            .lines()
            .position(|line| line.starts_with("write("))
        {
            assert!(last_read < write);
        }
    }
    if matches!(status, 2 | 4 | 5) {
        assert!(writes.is_empty(), "{events}", events = run.events);
    }
    assert_eq!(run.closed, run.opened);
    if run.verifying {
        assert!(writes.is_empty(), "verify never publishes: {}", run.events);
    }
    if status == 0 || status == 5 || !writes.is_empty() {
        for reads in &run.file_reads {
            assert_eq!(request(reads.last().unwrap(), "read"), 1);
            assert_eq!(result(reads.last().unwrap(), "read").1, "0");
        }
    }
}
fn no_input(run: &Run) {
    assert!(stdin_reads(run).is_empty());
    assert!(calls(&run.events, "write").is_empty());
}

#[test]
fn sign_bytes_vectors_tamper_and_fixed_file_policy() {
    let exe = executable();
    let seed = key_file(&(0..32).collect::<Vec<u8>>());
    let mut cases = 0;
    for length in [0, 1, 2, 63, 64, 65, 1023, 1024, 1025, 4097] {
        let data = pattern(length);
        let (public, signature) = reference(seed.path(), &data);
        let public = key_file(&public);
        let signature_file = key_file(&signature);
        let observed = run(exe, &data, &sign_args(seed.path()), &[], false, "5s");
        checked(&observed, 0, &signature, true);
        assert_eq!(observed.closed, 1);
        cases += 1;
        assert!(oracle_valid(public.path(), signature_file.path(), &data));
        let observed = run(
            exe,
            &data,
            &verify_args(public.path(), signature_file.path()),
            &[],
            false,
            "5s",
        );
        checked(&observed, 0, b"", true);
        assert_eq!(observed.closed, 2);
        cases += 1;
    }
    // RFC 8032 section 7.1, tests 1, 2 and 3: complete detached signatures.
    for (seed_hex, public_hex, message_hex, signature_hex) in [
        ("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60", "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "", "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"),
        ("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb", "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "72", "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"),
        ("c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7", "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025", "af82", "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"),
    ] {
        let seed = key_file(&unhex(seed_hex));
        let public_bytes = unhex(public_hex);
        let wanted = unhex(signature_hex);
        let data = unhex(message_hex);
        assert_eq!(reference(seed.path(), &data), (public_bytes.clone(), wanted.clone()));
        let public = key_file(&public_bytes);
        let signature = key_file(&wanted);
        let observed = run(exe, &data, &sign_args(seed.path()), &[], false, "5s");
        checked(&observed, 0, &wanted, true);
        cases += 1;
        let observed = run(exe, &data, &verify_args(public.path(), signature.path()), &[], false, "5s");
        checked(&observed, 0, b"", true);
        cases += 1;
    }
    let data = pattern(1537);
    let (public_bytes, signature_bytes) = reference(seed.path(), &data);
    let public = key_file(&public_bytes);
    let signature = key_file(&signature_bytes);
    for index in [0, 15, 31, 32, 47, 63] {
        let mut bad = signature_bytes.clone();
        bad[index] ^= 1;
        let bad = key_file(&bad);
        assert!(!oracle_valid(public.path(), bad.path(), &data));
        let observed = run(
            exe,
            &data,
            &verify_args(public.path(), bad.path()),
            &[],
            false,
            "5s",
        );
        checked(&observed, 5, b"", true);
        cases += 1;
    }
    for index in [0, 15, 31] {
        let mut bad = public_bytes.clone();
        bad[index] ^= 1;
        let bad = key_file(&bad);
        assert!(!oracle_valid(bad.path(), signature.path(), &data));
        let observed = run(
            exe,
            &data,
            &verify_args(bad.path(), signature.path()),
            &[],
            false,
            "5s",
        );
        checked(&observed, 5, b"", true);
        cases += 1;
    }
    for index in [0, 768, 1536] {
        let mut bad = data.clone();
        bad[index] ^= 1;
        assert!(!oracle_valid(public.path(), signature.path(), &bad));
        let observed = run(
            exe,
            &bad,
            &verify_args(public.path(), signature.path()),
            &[],
            false,
            "5s",
        );
        checked(&observed, 5, b"", true);
        cases += 1;
    }
    let mut invalid_crypto = vec![
        (vec![0; 32], signature_bytes.clone()),
        ([vec![1], vec![0; 31]].concat(), signature_bytes.clone()),
        (vec![255; 32], signature_bytes.clone()),
    ];
    for r in [vec![0; 32], [vec![1], vec![0; 31]].concat(), vec![255; 32]] {
        invalid_crypto.push((
            public_bytes.clone(),
            [r, signature_bytes[32..].to_vec()].concat(),
        ));
    }
    for s in [
        unhex("edd3f55c1a631258d69cf7a2def9de1400000000000000000000000000000010"),
        vec![255; 32],
    ] {
        invalid_crypto.push((
            public_bytes.clone(),
            [signature_bytes[..32].to_vec(), s].concat(),
        ));
    }
    for (p, s) in invalid_crypto {
        let p = key_file(&p);
        let s = key_file(&s);
        assert!(!oracle_valid(p.path(), s.path(), &data));
        let observed = run(
            exe,
            &data,
            &verify_args(p.path(), s.path()),
            &[],
            false,
            "5s",
        );
        checked(&observed, 5, b"", true);
        cases += 1;
    }
    let mut invalid = vec![
        vec![],
        vec!["sign".into()],
        vec!["verify".into()],
        vec!["verify".into(), public.path().as_os_str().to_owned()],
        vec!["bad".into(), seed.path().as_os_str().to_owned()],
        sign_args(Path::new("")),
        sign_args(Path::new(&"x".repeat(4096))),
        verify_args(Path::new(""), signature.path()),
        verify_args(public.path(), Path::new("")),
        verify_args(public.path(), Path::new(&"x".repeat(4096))),
    ];
    let mut extra = sign_args(seed.path());
    extra.push("extra".into());
    invalid.push(extra);
    let mut extra = verify_args(public.path(), signature.path());
    extra.push("extra".into());
    invalid.push(extra);
    invalid.push(vec![
        "verify".into(),
        "x".repeat(4095).into(),
        "y".repeat(4096).into(),
    ]);
    assert_eq!(invalid.len(), 13);
    for arguments in invalid {
        let observed = run(exe, &data, &arguments, &[], false, "5s");
        cases += 1;
        checked(&observed, 2, b"", true);
        no_input(&observed);
        assert!(calls(&observed.events, "openat").is_empty());
    }
    for length in [0, 31, 33] {
        let bad = key_file(&pattern(length));
        for arguments in [
            sign_args(bad.path()),
            verify_args(bad.path(), signature.path()),
        ] {
            let observed = run(exe, &data, &arguments, &[], false, "5s");
            cases += 1;
            checked(&observed, 2, b"", true);
            no_input(&observed);
            assert_eq!(observed.closed, 1);
        }
    }
    for length in [0, 63, 65] {
        let bad = key_file(&pattern(length));
        let observed = run(
            exe,
            &data,
            &verify_args(public.path(), bad.path()),
            &[],
            false,
            "5s",
        );
        cases += 1;
        checked(&observed, 2, b"", true);
        no_input(&observed);
        assert_eq!(observed.closed, 2);
    }
    let missing = common::TempArtifact::new("laniusc_sign_bytes", "missing", None);
    for (arguments, closed) in [
        (sign_args(missing.path()), 0),
        (verify_args(missing.path(), signature.path()), 0),
        (verify_args(public.path(), missing.path()), 1),
    ] {
        let observed = run(exe, &data, &arguments, &[], false, "5s");
        cases += 1;
        checked(&observed, 3, b"", true);
        no_input(&observed);
        assert_eq!(observed.closed, closed);
    }
    let link = common::TempArtifact::new("laniusc_sign_bytes", "link", None);
    symlink(seed.path(), link.path()).unwrap();
    for (arguments, closed) in [
        (sign_args(link.path()), 0),
        (verify_args(link.path(), signature.path()), 0),
        (verify_args(public.path(), link.path()), 1),
    ] {
        let observed = run(exe, &data, &arguments, &[], false, "5s");
        cases += 1;
        checked(&observed, 3, b"", true);
        no_input(&observed);
        assert_eq!(observed.closed, closed);
    }
    let fifo = common::TempArtifact::new("laniusc_sign_bytes", "fifo", None);
    assert!(Command::new("timeout")
        .args(["--kill-after=1s", "2s", "mkfifo"])
        .arg(fifo.path())
        .status()
        .unwrap()
        .success());
    for (arguments, closed) in [
        (sign_args(fifo.path()), 1),
        (verify_args(fifo.path(), signature.path()), 1),
        (verify_args(public.path(), fifo.path()), 2),
    ] {
        let observed = run(exe, &data, &arguments, &[], false, "5s");
        cases += 1;
        checked(&observed, 2, b"", true);
        no_input(&observed);
        assert_eq!(observed.closed, closed);
    }
    let mut raw_seed = seed.path().as_os_str().as_encoded_bytes().to_vec();
    raw_seed.extend_from_slice(b"-\xff");
    let raw_seed = PathBuf::from(OsString::from_vec(raw_seed));
    fs::write(&raw_seed, (0..32).collect::<Vec<u8>>()).unwrap();
    let observed = run(exe, &data, &sign_args(&raw_seed), &[], false, "5s");
    cases += 1;
    checked(&observed, 0, &signature_bytes, true);
    fs::remove_file(raw_seed).unwrap();
    let mut raw_public = public.path().as_os_str().as_encoded_bytes().to_vec();
    raw_public.extend_from_slice(b"-\xfe");
    let raw_public = PathBuf::from(OsString::from_vec(raw_public));
    fs::write(&raw_public, &public_bytes).unwrap();
    let mut raw_signature = signature.path().as_os_str().as_encoded_bytes().to_vec();
    raw_signature.extend_from_slice(b"-\xff");
    let raw_signature = PathBuf::from(OsString::from_vec(raw_signature));
    fs::write(&raw_signature, &signature_bytes).unwrap();
    let observed = run(
        exe,
        &data,
        &verify_args(&raw_public, &raw_signature),
        &[],
        false,
        "5s",
    );
    cases += 1;
    checked(&observed, 0, b"", true);
    fs::remove_file(raw_public).unwrap();
    fs::remove_file(raw_signature).unwrap();
    let directory_link = common::TempArtifact::new("laniusc_sign_bytes", "directory-link", None);
    symlink(seed.path().parent().unwrap(), directory_link.path()).unwrap();
    let through_link = directory_link.path().join(seed.path().file_name().unwrap());
    let observed = run(exe, &data, &sign_args(&through_link), &[], false, "5s");
    cases += 1;
    checked(&observed, 0, &signature_bytes, true);
    assert_eq!(cases, 80);
    eprintln!("sign_bytes ordinary: one shared strictELF,{cases} native cases,libsodium/RFC8032 detached signatures and tamper/argument/fixed-file policy");
}

#[test]
fn sign_bytes_owned_cleanup_and_io_faults() {
    let exe = executable();
    let seed = key_file(&(0..32).collect::<Vec<u8>>());
    let data = pattern(1537);
    let (public, signature) = reference(seed.path(), &data);
    let public = key_file(&public);
    let signature_file = key_file(&signature);
    let signing = sign_args(seed.path());
    let verifying = verify_args(public.path(), signature_file.path());
    let mut cases = 0;
    let mut positions = Vec::new();
    for (mode, arguments, wanted, files) in [
        ("sign", &signing, signature.as_slice(), 1),
        ("verify", &verifying, b"".as_slice(), 2),
    ] {
        let observed = run(exe, &data, arguments, &[], false, "5s");
        cases += 1;
        checked(&observed, 0, wanted, true);
        assert_eq!(observed.closed, files);
        positions.push((mode, observed.maps));
        for ordinal in 1..=observed.maps {
            let injection = format!("mmap:error=ENOMEM:when={ordinal}");
            let observed = run(exe, &data, arguments, &[&injection], false, "5s");
            cases += 1;
            checked(&observed, 4, b"", true);
            assert_eq!(observed.failures, vec![ordinal]);
            assert_eq!(observed.maps, ordinal);
            if ordinal <= 2 {
                assert_eq!(observed.opened, 0);
            } else {
                assert_eq!(observed.closed, files);
            }
            no_input(&observed);
        }
    }
    for (injection, status, wanted, writes) in [
        ("write:error=EIO:when=1", 3, b"".as_slice(), 1),
        ("write:error=EAGAIN:when=1", 3, b"".as_slice(), 1),
        ("write:retval=0:when=1", 3, b"".as_slice(), 1),
        ("write:retval=65:when=1", 3, b"".as_slice(), 1),
        ("write:error=EINTR:when=1", 0, signature.as_slice(), 2),
        ("write:retval=1:when=1", 0, &signature[1..], 2),
    ] {
        let observed = run(exe, &data, &signing, &[injection], false, "5s");
        cases += 1;
        checked(&observed, status, wanted, true);
        let calls = calls(&observed.events, "write");
        assert_eq!(calls.len(), writes);
        if injection.contains("retval=1:") {
            assert_eq!(request(calls[1], "write"), 63);
        }
    }
    let observed = run(exe, &data, &signing, &[], true, "5s");
    cases += 1;
    checked(&observed, 3, b"", true);
    let writes = calls(&observed.events, "write");
    assert_eq!(writes.len(), 1);
    assert!(writes[0].contains("EPIPE"));
    for (arguments, injection, status, closed, no_stdin) in [
        (&signing, "openat:error=EACCES:when=1", 3, 0, true),
        (&verifying, "openat:error=EACCES:when=1", 3, 0, true),
        (&verifying, "openat:error=EACCES:when=2", 3, 1, true),
        (&signing, "close:error=EIO:when=1", 3, 1, true),
        (&signing, "close:error=EINTR:when=1", 3, 1, true),
        (&verifying, "close:error=EIO:when=1", 3, 1, true),
        (&verifying, "close:error=EIO:when=2", 3, 2, true),
        (&verifying, "close:error=EINTR:when=2", 3, 2, true),
        (&signing, "read:error=EIO:when=1", 3, 1, true),
        (&signing, "read:error=EIO:when=2", 3, 1, true),
        (&signing, "read:retval=33:when=1", 3, 1, true),
        (&verifying, "read:error=EIO:when=3", 3, 2, true),
        (&verifying, "read:error=EIO:when=4", 3, 2, true),
        (&verifying, "read:retval=65:when=3", 3, 2, true),
        (&signing, "read:error=EINTR:when=1", 0, 1, false),
        (&verifying, "read:error=EINTR:when=3", 0, 2, false),
        (&signing, "read:error=EIO:when=3", 3, 1, false),
        (&signing, "read:error=EIO:when=4", 3, 1, false),
        (&verifying, "read:error=EIO:when=5", 3, 2, false),
        (&verifying, "read:error=EIO:when=6", 3, 2, false),
        (&signing, "read:error=EAGAIN:when=3", 3, 1, false),
        (&signing, "read:retval=1025:when=3", 3, 1, false),
        (&signing, "read:error=EINTR:when=3", 0, 1, false),
    ] {
        let wanted = if status == 0 && arguments == &signing {
            signature.as_slice()
        } else {
            b""
        };
        let observed = run(exe, &data, arguments, &[injection], false, "5s");
        cases += 1;
        checked(&observed, status, wanted, true);
        assert_eq!(observed.closed, closed);
        if no_stdin {
            no_input(&observed);
        } else {
            assert!(!stdin_reads(&observed).is_empty());
        }
        if injection == "read:error=EINTR:when=1" || injection == "read:error=EINTR:when=3" {
            let fixed = observed.file_reads.iter().map(Vec::len).sum::<usize>();
            if arguments == &verifying {
                assert_eq!(fixed, 5);
            } else if injection.ends_with("when=1") {
                assert_eq!(fixed, 3);
            } else {
                assert_eq!(stdin_reads(&observed).len(), 4);
            }
        }
    }
    for (injection, closed) in [("close:error=EIO:when=1", 1), ("close:error=EIO:when=2", 2)] {
        let bad = key_file(&pattern(if closed == 1 { 31 } else { 63 }));
        let arguments = if closed == 1 {
            sign_args(bad.path())
        } else {
            verify_args(public.path(), bad.path())
        };
        let observed = run(exe, &data, &arguments, &[injection], false, "5s");
        cases += 1;
        checked(&observed, 3, b"", true);
        assert_eq!(observed.closed, closed);
        no_input(&observed);
    }
    let observed = run(
        exe,
        &data,
        &signing,
        &["rt_sigaction:error=EINTR:when=1"],
        false,
        "5s",
    );
    cases += 1;
    checked(&observed, 3, b"", false);
    assert_eq!(observed.maps, 0);
    assert_eq!(observed.opened, 0);
    no_input(&observed);
    assert_eq!(cases, 35 + positions.iter().map(|(_, n)| n).sum::<usize>());
    eprintln!("sign_bytes cleanup: {positions:?} reached allocation positions,{cases} native cases; injected close checks attempt/invalidation,not actual host release");
}

#[test]
fn sign_bytes_message_boundaries_and_scale() {
    let exe = executable();
    let seed = key_file(&(0..32).collect::<Vec<u8>>());
    let data = pattern(MAX);
    let (public, signature) = reference(seed.path(), &data);
    let public = key_file(&public);
    let signature_file = key_file(&signature);
    for (mode, arguments, wanted) in [
        ("sign", sign_args(seed.path()), signature.as_slice()),
        (
            "verify",
            verify_args(public.path(), signature_file.path()),
            b"".as_slice(),
        ),
    ] {
        let started = Instant::now();
        let observed = run(exe, &data, &arguments, &[], false, "20s");
        eprintln!("sign_bytes {mode} 1MiB case wall {:.3} ms (setup,strace,native startup and trace parsing; excludes compiler/oracle time; not isolated signature throughput)",started.elapsed().as_secs_f64()*1000.0);
        checked(&observed, 0, wanted, true);
        let reads = stdin_reads(&observed);
        assert_eq!(request(reads.last().unwrap(), "read"), 1);
        assert_eq!(result(reads.last().unwrap(), "read").1, "0");
    }
    let excess = [data, vec![1]].concat();
    for arguments in [
        sign_args(seed.path()),
        verify_args(public.path(), signature_file.path()),
    ] {
        let observed = run(exe, &excess, &arguments, &[], false, "20s");
        checked(&observed, 7, b"", true);
        let reads = stdin_reads(&observed);
        assert_eq!(request(reads.last().unwrap(), "read"), 1);
        assert_eq!(result(reads.last().unwrap(), "read").1, "1");
        assert!(calls(&observed.events, "write").is_empty());
    }
    eprintln!("sign_bytes scale: one shared strictELF,4 native cases,1MiB sign/verify and exact-cap+1 probes");
}

#[test]
fn sign_bytes_shared_call_budget_and_close_precedence() {
    let exe = executable();
    let seed = key_file(&(0..32).collect::<Vec<u8>>());
    let arguments = sign_args(seed.path());
    let observed = run(
        exe,
        b"abc",
        &arguments,
        &["read:error=EINTR:when=3+"],
        false,
        "20s",
    );
    checked(&observed, 7, b"", true);
    assert_eq!(calls(&observed.events, "read").len(), CALLS);
    assert_eq!(observed.closed, 1);
    assert!(calls(&observed.events, "write").is_empty());
    let observed = run(
        exe,
        b"abc",
        &arguments,
        &["write:error=EINTR:when=1+"],
        false,
        "20s",
    );
    checked(&observed, 7, b"", true);
    assert_eq!(calls(&observed.events, "read").len(), 4);
    assert_eq!(calls(&observed.events, "write").len(), CALLS - 4);
    let observed = run(
        exe,
        b"abc",
        &arguments,
        &["read:error=EINTR:when=1+", "close:error=EIO:when=1"],
        false,
        "20s",
    );
    checked(&observed, 3, b"", true);
    assert_eq!(calls(&observed.events, "read").len(), CALLS);
    assert_eq!(observed.closed, 1);
    no_input(&observed);
    eprintln!("sign_bytes budget: one shared strictELF,3 native cases reaching131072 shared attempts; failed close overrides exhausted fixed-file budget");
}
