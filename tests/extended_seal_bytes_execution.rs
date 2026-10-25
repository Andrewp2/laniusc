//! Real authenticated binary envelopes; independent libsodium oracle and owner ledgers.
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
    let entry = root.join("sample_programs/library/seal_bytes.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("seal_bytes application", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("seal_bytes: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_seal_bytes", "executable", None);
    file.write_bytes(bytes);
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(build_executable)
}
fn key_file(bytes: &[u8]) -> common::TempArtifact {
    let file = common::TempArtifact::new("laniusc_seal_bytes", "key", None);
    file.write_bytes(bytes);
    file
}
fn pattern(length: usize) -> Vec<u8> {
    (0..length)
        .map(|index| ((index * 73 + index / 11) & 255) as u8)
        .collect()
}
fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}
fn unhex(value: &str) -> Vec<u8> {
    value
        .as_bytes()
        .chunks_exact(2)
        .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap())
        .collect()
}
fn args(mode: &str, key: &Path, nonce: &str, aad: &str) -> Vec<OsString> {
    let mut out = vec![mode.into(), key.as_os_str().to_owned()];
    if mode == "seal" {
        out.push(nonce.into());
    }
    out.push(aad.into());
    out
}
fn oracle(mode: &str, key: &Path, nonce: &str, aad: &str, input: &[u8]) -> Output {
    let file = common::TempArtifact::new("laniusc_seal_bytes", "oracle", None);
    file.write_bytes(input);
    Command::new("timeout").args(["--kill-after=1s","5s","python3","-c",r#"import ctypes as c,ctypes.util,sys
mode,keypath,noncehex,aadhex,path=sys.argv[1:]
s=c.CDLL(ctypes.util.find_library('sodium') or 'libsodium.so.23'); assert s.sodium_init()>=0
enc=s.crypto_aead_chacha20poly1305_ietf_encrypt; dec=s.crypto_aead_chacha20poly1305_ietf_decrypt
enc.argtypes=[c.c_void_p,c.POINTER(c.c_ulonglong),c.c_void_p,c.c_ulonglong,c.c_void_p,c.c_ulonglong,c.c_void_p,c.c_void_p,c.c_void_p]
dec.argtypes=[c.c_void_p,c.POINTER(c.c_ulonglong),c.c_void_p,c.c_void_p,c.c_ulonglong,c.c_void_p,c.c_ulonglong,c.c_void_p,c.c_void_p]
enc.restype=dec.restype=c.c_int
key=open(keypath,'rb').read(); assert len(key)==32
data=open(path,'rb').read(); caller=bytes.fromhex(aadhex)
buf=lambda b:c.create_string_buffer(b,max(1,len(b)))
if mode=='seal':
    nonce=bytes.fromhex(noncehex); assert len(nonce)==12
    header=b'LNC1'+nonce; aad=header+caller; out=c.create_string_buffer(len(data)+16); n=c.c_ulonglong()
    assert enc(out,c.byref(n),buf(data),len(data),buf(aad),len(aad),None,buf(nonce),buf(key))==0
    sys.stdout.buffer.write(header+out.raw[:n.value])
else:
    if len(data)<32 or data[:4]!=b'LNC1':sys.exit(2)
    header=data[:16]; nonce=header[4:]; aad=header+caller; encrypted=data[16:]; out=c.create_string_buffer(max(1,len(encrypted)-16));n=c.c_ulonglong()
    if dec(out,c.byref(n),None,buf(encrypted),len(encrypted),buf(aad),len(aad),buf(nonce),buf(key))!=0:sys.exit(5)
    sys.stdout.buffer.write(out.raw[:n.value])
"#,mode]).arg(key).args([nonce,aad]).arg(file.path()).output().unwrap()
}
fn expected(mode: &str, key: &Path, nonce: &str, aad: &str, input: &[u8]) -> Vec<u8> {
    let out = oracle(mode, key, nonce, aad, input);
    assert!(out.status.success(), "{out:?}");
    assert!(out.stderr.is_empty());
    out.stdout
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
    key_fd: Option<i32>,
}
fn run(
    exe: &common::TempArtifact,
    input: &[u8],
    args: &[OsString],
    inject: &[&str],
    closed: bool,
    seconds: &str,
) -> Run {
    let data = common::TempArtifact::new("laniusc_seal_bytes", "stdin", None);
    data.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_seal_bytes", "trace", None);
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
    let mut key_fd = None;
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
            assert!(owner.is_none());
            for flag in ["O_NOFOLLOW", "O_NONBLOCK", "O_CLOEXEC"] {
                assert!(line.contains(flag), "{events}");
            }
            let (_, v) = result(line, "openat");
            let value: i32 = v.split_whitespace().next().unwrap().parse().unwrap();
            if value >= 0 {
                assert_eq!(opened, 0);
                owner = Some(value);
                key_fd = Some(value);
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
                assert!(
                    owner.is_none(),
                    "key must be retired before stdin: {events}"
                );
            } else {
                assert_eq!(owner, Some(descriptor), "{events}");
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
        key_fd,
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
        assert!((1..=1024).contains(&request(line, "write")));
    }
    if status == 0 || !writes.is_empty() {
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
    if let Some(descriptor) = run.key_fd {
        assert_eq!(run.closed, 1);
        assert!(descriptor > 2);
    }
}
fn no_input(run: &Run) {
    assert!(stdin_reads(run).is_empty());
    assert!(calls(&run.events, "write").is_empty());
}

#[test]
fn seal_bytes_envelopes_oracle_tamper_and_argument_policy() {
    let exe = executable();
    let key = key_file(&(0..32).collect::<Vec<u8>>());
    let mut cases = 0;
    for (i, length) in [0, 1, 15, 16, 17, 63, 64, 65, 1023, 1024, 1025, 4097]
        .into_iter()
        .enumerate()
    {
        let data = pattern(length);
        let nonce = hex(&(0..12).map(|j| (i + j * 17) as u8).collect::<Vec<_>>());
        let aad = if i == 0 {
            String::new()
        } else if i == 1 {
            hex(&pattern(256))
        } else {
            String::from("000102030405060708090a0b")
        };
        let expected = expected("seal", key.path(), &nonce, &aad, &data);
        let shown_nonce = if i % 2 == 1 {
            nonce.to_uppercase()
        } else {
            nonce.clone()
        };
        let shown_aad = if i % 2 == 1 {
            aad.to_uppercase()
        } else {
            aad.clone()
        };
        let sealed = run(
            exe,
            &data,
            &args("seal", key.path(), &shown_nonce, &shown_aad),
            &[],
            false,
            "5s",
        );
        cases += 1;
        checked(&sealed, 0, &expected, true);
        assert_eq!(sealed.opened, 1);
        let opened = run(
            exe,
            &sealed.output.stdout,
            &args("open", key.path(), "", &aad),
            &[],
            false,
            "5s",
        );
        cases += 1;
        checked(&opened, 0, &data, true);
    }
    // RFC8439 section2.8.2 key/nonce/plaintext: header authentication changes
    // the tag, while the known ChaCha20 ciphertext remains the RFC vector.
    let rfc_key = key_file(&(128..160).collect::<Vec<u8>>());
    let nonce = "070000004041424344454647";
    let aad = "50515253c0c1c2c3c4c5c6c7";
    let plain=b"Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.";
    let envelope = expected("seal", rfc_key.path(), nonce, aad, plain);
    assert_eq!(&envelope[16..envelope.len()-16],unhex("d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b6116"));
    let observed = run(
        exe,
        plain,
        &args("seal", rfc_key.path(), nonce, aad),
        &[],
        false,
        "5s",
    );
    cases += 1;
    checked(&observed, 0, &envelope, true);
    let observed = run(
        exe,
        &envelope,
        &args("open", rfc_key.path(), "", aad),
        &[],
        false,
        "5s",
    );
    cases += 1;
    checked(&observed, 0, plain, true);
    let nonce = "000102030405060708090a0b";
    let aad = hex(&pattern(64));
    let data = pattern(33);
    let envelope = expected("seal", key.path(), nonce, &aad, &data);
    for index in
        (0..16)
            .chain(envelope.len() - 16..envelope.len())
            .chain([16, 32, envelope.len() - 17])
    {
        let mut bad = envelope.clone();
        bad[index] ^= 1;
        let status = if index < 4 { 2 } else { 5 };
        let answer = oracle("open", key.path(), "", &aad, &bad);
        assert_eq!(answer.status.code(), Some(status));
        assert!(answer.stdout.is_empty());
        let observed = run(
            exe,
            &bad,
            &args("open", key.path(), "", &aad),
            &[],
            false,
            "5s",
        );
        cases += 1;
        checked(&observed, status, b"", true);
    }
    for index in [0, 31, 63] {
        let mut altered = pattern(64);
        altered[index] ^= 1;
        let changed = hex(&altered);
        assert_eq!(
            oracle("open", key.path(), "", &changed, &envelope)
                .status
                .code(),
            Some(5)
        );
        let observed = run(
            exe,
            &envelope,
            &args("open", key.path(), "", &changed),
            &[],
            false,
            "5s",
        );
        cases += 1;
        checked(&observed, 5, b"", true);
    }
    let wrong = key_file(&pattern(32));
    let observed = run(
        exe,
        &envelope,
        &args("open", wrong.path(), "", &aad),
        &[],
        false,
        "5s",
    );
    cases += 1;
    checked(&observed, 5, b"", true);
    for length in [0, 1, 15, 16, 31] {
        let observed = run(
            exe,
            &envelope[..length],
            &args("open", key.path(), "", &aad),
            &[],
            false,
            "5s",
        );
        cases += 1;
        checked(&observed, 2, b"", true);
    }
    for bad in [
        envelope[..envelope.len() - 1].to_vec(),
        [envelope.clone(), vec![0]].concat(),
    ] {
        assert_eq!(
            oracle("open", key.path(), "", &aad, &bad).status.code(),
            Some(5)
        );
        let observed = run(
            exe,
            &bad,
            &args("open", key.path(), "", &aad),
            &[],
            false,
            "5s",
        );
        cases += 1;
        checked(&observed, 5, b"", true);
    }
    let mut invalid = vec![
        vec![],
        vec!["seal".into()],
        args("bad", key.path(), "", &aad),
        args("seal", key.path(), "00", &aad),
        args("seal", key.path(), "g00102030405060708090a0b", &aad),
        args("seal", key.path(), nonce, "0"),
        args("open", key.path(), "", "GG"),
        args("open", key.path(), "", &"00".repeat(257)),
        args("seal", Path::new(""), nonce, ""),
        args("seal", Path::new(&"x".repeat(4096)), nonce, ""),
    ];
    let mut extra = args("seal", key.path(), nonce, "");
    extra.push("extra".into());
    invalid.push(extra);
    invalid.push(vec!["x".repeat(5000).into()]);
    let mut raw = args("seal", key.path(), nonce, "");
    raw[2] = OsString::from_vec(vec![255; 24]);
    invalid.push(raw);
    for arguments in invalid {
        let observed = run(exe, &data, &arguments, &[], false, "5s");
        cases += 1;
        checked(&observed, 2, b"", true);
        no_input(&observed);
        assert_eq!(observed.opened, 0);
        assert!(calls(&observed.events, "openat").is_empty());
    }
    for length in [0, 31, 33] {
        let bad_key = key_file(&pattern(length));
        let observed = run(
            exe,
            &data,
            &args("seal", bad_key.path(), nonce, ""),
            &[],
            false,
            "5s",
        );
        cases += 1;
        checked(&observed, 2, b"", true);
        no_input(&observed);
        assert_eq!(observed.closed, 1);
    }
    let missing = common::TempArtifact::new("laniusc_seal_bytes", "missing", None);
    let observed = run(
        exe,
        &data,
        &args("seal", missing.path(), nonce, ""),
        &[],
        false,
        "5s",
    );
    cases += 1;
    checked(&observed, 3, b"", true);
    no_input(&observed);
    assert_eq!(observed.closed, 0);
    let link = common::TempArtifact::new("laniusc_seal_bytes", "key-link", None);
    symlink(key.path(), link.path()).unwrap();
    let observed = run(
        exe,
        &data,
        &args("seal", link.path(), nonce, ""),
        &[],
        false,
        "5s",
    );
    cases += 1;
    checked(&observed, 3, b"", true);
    no_input(&observed);
    assert_eq!(observed.closed, 0);
    let fifo = common::TempArtifact::new("laniusc_seal_bytes", "key-fifo", None);
    assert!(Command::new("timeout")
        .args(["--kill-after=1s", "2s", "mkfifo"])
        .arg(fifo.path())
        .status()
        .unwrap()
        .success());
    let observed = run(
        exe,
        &data,
        &args("seal", fifo.path(), nonce, ""),
        &[],
        false,
        "5s",
    );
    cases += 1;
    checked(&observed, 2, b"", true);
    no_input(&observed);
    assert_eq!(observed.closed, 1);
    let mut raw_path = key.path().as_os_str().as_encoded_bytes().to_vec();
    raw_path.extend_from_slice(b"-\xff");
    let raw_key = PathBuf::from(OsString::from_vec(raw_path));
    fs::write(&raw_key, (0..32).collect::<Vec<u8>>()).unwrap();
    let expected = expected("seal", &raw_key, nonce, "", b"");
    let observed = run(
        exe,
        b"",
        &args("seal", &raw_key, nonce, ""),
        &[],
        false,
        "5s",
    );
    cases += 1;
    checked(&observed, 0, &expected, true);
    fs::remove_file(raw_key).unwrap();
    assert_eq!(cases, 92);
    eprintln!("seal_bytes ordinary: one shared strictELF, {cases} native cases, libsodium interoperability and tamper/argument/key policy");
}

#[test]
fn seal_bytes_owned_cleanup_and_io_faults() {
    let exe = executable();
    let key = key_file(&(0..32).collect::<Vec<u8>>());
    let nonce = "000102030405060708090a0b";
    let aad = "001122aabbcc";
    let plain = pattern(1537);
    let envelope = expected("seal", key.path(), nonce, aad, &plain);
    let mut cases = 0;
    let mut positions = Vec::new();
    for (mode, input, wanted) in [
        ("seal", plain.as_slice(), envelope.as_slice()),
        ("open", envelope.as_slice(), plain.as_slice()),
    ] {
        let arguments = args(mode, key.path(), nonce, aad);
        let baseline = run(exe, input, &arguments, &[], false, "5s");
        cases += 1;
        checked(&baseline, 0, wanted, true);
        assert!(baseline.failures.is_empty());
        positions.push((mode, baseline.maps));
        for ordinal in 1..=baseline.maps {
            let injection = format!("mmap:error=ENOMEM:when={ordinal}");
            let observed = run(exe, input, &arguments, &[&injection], false, "5s");
            cases += 1;
            checked(&observed, 4, b"", true);
            assert_eq!(observed.maps, ordinal);
            assert_eq!(observed.failures, [ordinal]);
            if ordinal <= 2 {
                assert_eq!(observed.opened, 0);
            } else {
                assert_eq!(observed.closed, 1);
            }
        }
        for (injection, status, expected_writes) in [
            ("write:error=EIO:when=1", 3, 1),
            ("write:error=EIO:when=2", 3, 2),
            ("write:error=EAGAIN:when=1", 3, 1),
            ("write:retval=0:when=1", 3, 1),
            ("write:retval=1025:when=1", 3, 1),
            ("write:error=EINTR:when=1", 0, 3),
            ("write:retval=1:when=1", 0, 3),
        ] {
            let expected = if injection == "write:error=EIO:when=2" {
                &wanted[..1024]
            } else if injection.contains("retval=1:") {
                &wanted[1..]
            } else if status == 0 {
                wanted
            } else {
                b""
            };
            let observed = run(exe, input, &arguments, &[injection], false, "5s");
            cases += 1;
            checked(&observed, status, expected, true);
            assert_eq!(observed.maps, baseline.maps);
            assert_eq!(calls(&observed.events, "write").len(), expected_writes);
            if injection.contains("retval=1:") {
                assert_eq!(request(calls(&observed.events, "write")[1], "write"), 1024);
            }
        }
        let observed = run(exe, input, &arguments, &[], true, "5s");
        cases += 1;
        checked(&observed, 3, b"", true);
        assert!(calls(&observed.events, "write")[0].contains("EPIPE"));
    }
    let arguments = args("seal", key.path(), nonce, aad);
    for (injection, status, stdin) in [
        ("openat:error=EACCES:when=1", 3, 0),
        ("close:error=EIO:when=1", 3, 0),
        ("close:error=EINTR:when=1", 3, 0),
        ("read:error=EIO:when=1", 3, 0),
        ("read:error=EIO:when=2", 3, 0),
        ("read:retval=33:when=1", 3, 0),
        ("read:error=EIO:when=3", 3, 1),
        ("read:error=EIO:when=4", 3, 2),
        ("read:error=EAGAIN:when=3", 3, 1),
        ("read:retval=1025:when=3", 3, 1),
        ("read:error=EINTR:when=1", 0, 3),
        ("read:error=EINTR:when=3", 0, 4),
    ] {
        let observed = run(exe, &plain, &arguments, &[injection], false, "5s");
        cases += 1;
        checked(
            &observed,
            status,
            if status == 0 { &envelope } else { b"" },
            true,
        );
        assert_eq!(stdin_reads(&observed).len(), stdin);
        if status != 0 {
            assert!(calls(&observed.events, "write").is_empty());
        }
    }
    let observed = run(
        exe,
        &plain,
        &arguments,
        &["rt_sigaction:error=EINTR:when=1"],
        false,
        "5s",
    );
    cases += 1;
    checked(&observed, 3, b"", false);
    assert_eq!(observed.maps, 0);
    assert_eq!(observed.opened, 0);
    no_input(&observed);
    assert_eq!(cases, 31 + positions.iter().map(|(_, n)| n).sum::<usize>());
    eprintln!("seal_bytes cleanup: {positions:?} reached allocation positions, {cases} native cases; injected close checks attempt/invalidation, not actual host release");
}

#[test]
fn seal_bytes_payload_boundaries_and_scale() {
    let exe = executable();
    let key = key_file(&(0..32).collect::<Vec<u8>>());
    let nonce = "000102030405060708090a0b";
    let aad = hex(&pattern(256));
    let plain = pattern(MAX);
    let envelope = expected("seal", key.path(), nonce, &aad, &plain);
    for (mode, input, wanted) in [
        ("seal", plain.as_slice(), envelope.as_slice()),
        ("open", envelope.as_slice(), plain.as_slice()),
    ] {
        let started = Instant::now();
        let observed = run(
            exe,
            input,
            &args(mode, key.path(), nonce, &aad),
            &[],
            false,
            "20s",
        );
        eprintln!(
            "seal_bytes {mode} 1MiB case wall {:.3} ms (setup, strace, native startup and trace parsing; excludes compiler/oracle time; not isolated cipher throughput)",
            started.elapsed().as_secs_f64() * 1000.0
        );
        checked(&observed, 0, wanted, true);
        let reads = stdin_reads(&observed);
        assert_eq!(request(reads.last().unwrap(), "read"), 1);
        assert_eq!(result(reads.last().unwrap(), "read").1, "0");
    }
    for (mode, input) in [
        ("seal", [plain.clone(), vec![1]].concat()),
        ("open", [envelope, vec![1]].concat()),
    ] {
        let observed = run(
            exe,
            &input,
            &args(mode, key.path(), nonce, &aad),
            &[],
            false,
            "20s",
        );
        checked(&observed, 7, b"", true);
        let reads = stdin_reads(&observed);
        assert_eq!(request(reads.last().unwrap(), "read"), 1);
        assert_eq!(result(reads.last().unwrap(), "read").1, "1");
        assert!(calls(&observed.events, "write").is_empty());
    }
    eprintln!("seal_bytes scale: one shared strictELF,4 native cases,1MiB payload seal/open and exact-cap+1 input probes");
}

#[test]
fn seal_bytes_shared_call_budget_bounds_retries() {
    let exe = executable();
    let key = key_file(&(0..32).collect::<Vec<u8>>());
    let arguments = args("seal", key.path(), "000102030405060708090a0b", "");
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
    eprintln!("seal_bytes budget: one shared strictELF,2 native cases reaching131072 shared key/stdin/stdout attempts");
}
