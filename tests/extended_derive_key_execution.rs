//! Real streaming HKDF consumer, independent standard-library oracle and I/O faults.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output, Stdio},
    time::Duration,
};
const INPUT_LIMIT: usize = 1_048_576;
const IO_LIMIT: usize = 131_072;
fn executable() -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/derive_key.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("derive_key application", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("derive_key: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_derive_key", "executable", None);
    file.write_bytes(bytes);
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}
struct Case {
    input: Vec<u8>,
    salt: Vec<u8>,
    info: Vec<u8>,
    length: usize,
}
impl Case {
    fn args(&self) -> Vec<String> {
        vec![self.length.to_string(), hex(&self.salt), hex(&self.info)]
    }
}
fn oracle(cases: &[Case]) -> Vec<Vec<u8>> {
    // RFC5869 recurrence expressed only in the test oracle. Hashing and HMAC
    // come from Python's standard library; production calls real Lanius APIs.
    let script = r#"import hashlib,hmac,struct,sys
data=sys.stdin.buffer
while True:
 header=data.read(16)
 if not header: break
 n,s,i,length=struct.unpack('<IIII',header)
 ikm,salt,info=data.read(n),data.read(s),data.read(i)
 prk=hmac.new(salt,ikm,hashlib.sha256).digest()
 previous=b''; output=b''
 for block in range(1,(length+31)//32+1):
  previous=hmac.new(prk,previous+info+bytes([block]),hashlib.sha256).digest()
  output+=previous
 print(output[:length].hex())
"#;
    let mut input = Vec::new();
    for case in cases {
        for count in [
            case.input.len(),
            case.salt.len(),
            case.info.len(),
            case.length,
        ] {
            input.extend((count as u32).to_le_bytes());
        }
        input.extend(&case.input);
        input.extend(&case.salt);
        input.extend(&case.info);
    }
    let file = common::TempArtifact::new("laniusc_derive_key", "oracle_input", None);
    file.write_bytes(input);
    let output = common::process_output_with_timeout(
        "standard HMAC/SHA256 HKDF oracle",
        Command::new("python3")
            .args(["-c", script])
            .stdin(fs::File::open(file.path()).unwrap()),
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let lines: Vec<_> = output
        .stdout
        .split_inclusive(|&byte| byte == b'\n')
        .map(<[u8]>::to_vec)
        .collect();
    assert_eq!(lines.len(), cases.len());
    lines
}
fn calls<'a>(events: &'a str, syscall: &str) -> Vec<&'a str> {
    let prefix = format!("{syscall}(");
    events
        .lines()
        .filter(|line| line.starts_with(&prefix))
        .collect()
}
fn result(line: &str) -> &str {
    line.rsplit_once(" = ")
        .unwrap()
        .1
        .split_whitespace()
        .next()
        .unwrap()
}
fn request(line: &str) -> usize {
    line.rsplit_once(" = ")
        .unwrap_or_else(|| panic!("missing syscall result delimiter: {line}"))
        .0
        .trim_end()
        .strip_suffix(')')
        .unwrap_or_else(|| panic!("missing syscall argument terminator: {line}"))
        .rsplit_once(',')
        .unwrap_or_else(|| panic!("missing syscall count argument: {line}"))
        .1
        .trim()
        .parse()
        .unwrap_or_else(|error| panic!("invalid syscall count ({error}): {line}"))
}
struct Run {
    output: Output,
    events: String,
}
fn run(
    executable: &common::TempArtifact,
    input: &[u8],
    args: &[String],
    fault: Option<&str>,
    seconds: u64,
    closed_stdout: bool,
) -> Run {
    let file = common::TempArtifact::new("laniusc_derive_key", "stdin", None);
    file.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_derive_key", "trace", None);
    let mut command = Command::new("timeout");
    command
        .args([
            "--kill-after=1s",
            &format!("{seconds}s"),
            "strace",
            "-qq",
            "-o",
        ])
        .arg(trace.path())
        .args([
            "-e",
            "trace=rt_sigaction,read,write,mmap,mremap,munmap,brk,close",
            "-e",
            "signal=none",
        ]);
    if let Some(fault) = fault {
        command.arg("-e").arg(format!("inject={fault}"));
    }
    command
        .arg(executable.path())
        .args(args)
        .stdin(fs::File::open(file.path()).unwrap());
    let output = if closed_stdout {
        let (reader, writer) = std::io::pipe().unwrap();
        drop(reader);
        command.stdout(writer);
        command.output().unwrap()
    } else {
        common::process_output_with_timeout(
            "bounded derive_key native case",
            &mut command,
            Duration::from_secs(seconds + 3),
        )
    };
    let events = fs::read_to_string(trace.path()).unwrap();
    if let Some(fault) = fault {
        let syscall = fault.split(':').next().unwrap();
        let injected = calls(&events, syscall)
            .iter()
            .filter(|line| line.contains("INJECTED"))
            .count();
        if fault.ends_with('+') {
            assert!(injected > 0 && injected <= IO_LIMIT, "{fault}: {events}");
        } else {
            assert_eq!(injected, 1, "{fault}: {events}");
        }
    } else {
        assert!(!events.contains("INJECTED"), "{events}");
    }
    Run { output, events }
}
fn checked(run: &Run, status: i32, bytes: &[u8]) {
    assert_eq!(
        run.output.status.code(),
        Some(status),
        "{:?}\n{}",
        run.output,
        run.events
    );
    assert_eq!(run.output.stdout, bytes, "{}", run.events);
    assert!(run.output.stderr.is_empty(), "{:?}", run.output);
    let actions = calls(&run.events, "rt_sigaction");
    assert_eq!(actions.len(), 1, "{}", run.events);
    assert!(
        actions[0].contains("SIGPIPE") && actions[0].contains("SIG_IGN"),
        "{}",
        run.events
    );
    for syscall in ["mmap", "mremap", "munmap", "brk", "close"] {
        assert!(
            calls(&run.events, syscall).is_empty(),
            "allocation/ownership-free program: {}",
            run.events
        );
    }
    for line in calls(&run.events, "read") {
        assert!(line.starts_with("read(0,"));
        assert!((1..=1024).contains(&request(line)));
    }
    for line in calls(&run.events, "write") {
        assert!(line.starts_with("write(1,"));
        assert!((1..=16_321).contains(&request(line)));
    }
    let attempts = calls(&run.events, "read").len() + calls(&run.events, "write").len();
    assert!(attempts <= IO_LIMIT);
    if let Some(first_io) = run
        .events
        .lines()
        .position(|line| line.starts_with("read(") || line.starts_with("write("))
    {
        assert!(
            run.events
                .lines()
                .position(|line| line.starts_with("rt_sigaction("))
                .unwrap()
                < first_io
        );
    }
}
fn real_short_write(
    executable: &common::TempArtifact,
    input: &[u8],
    args: &[String],
    expected: &[u8],
) {
    // A real filesystem limit, not an injected successful retval: the first
    // host write commits exactly three bytes, then the next write gets EFBIG.
    let source = common::TempArtifact::new("laniusc_derive_key", "short_input", None);
    source.write_bytes(input);
    let target = common::TempArtifact::new("laniusc_derive_key", "short_output", None);
    target.write_bytes(b"");
    let setup = "import os,resource,signal,sys; signal.signal(signal.SIGXFSZ,signal.SIG_IGN); resource.setrlimit(resource.RLIMIT_FSIZE,(3,3)); os.execvp('strace',['strace','-qq','-e','trace=write','-e','signal=none']+sys.argv[1:])";
    let output = Command::new("timeout")
        .args(["--kill-after=1s", "5s", "python3", "-c", setup])
        .arg(executable.path())
        .args(args)
        .stdin(fs::File::open(source.path()).unwrap())
        .stdout(fs::File::options().write(true).open(target.path()).unwrap())
        .stderr(Stdio::piped())
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(3), "{output:?}");
    assert!(output.stdout.is_empty());
    // The setup Python process is outside the trace. Its exec starts strace,
    // which reports only the native program's two real writes through stderr.
    let trace = String::from_utf8(output.stderr).unwrap();
    let writes = calls(&trace, "write");
    assert_eq!(
        writes.len(),
        2,
        "retry after the actual short write: {trace}"
    );
    assert_eq!(request(writes[0]), expected.len(), "{trace}");
    assert_eq!(result(writes[0]), "3", "{trace}");
    assert_eq!(request(writes[1]), expected.len() - 3, "{trace}");
    assert!(writes[1].contains("EFBIG"), "{trace}");
    assert_eq!(
        trace.lines().count(),
        writes.len(),
        "no application diagnostics: {trace}"
    );
    assert_eq!(fs::read(target.path()).unwrap(), expected[..3]);
}

#[test]
fn hkdf_application_matches_rfc_and_independent_binary_models_and_bounds_io() {
    let executable = executable();
    let mut cases = vec![
        Case {
            input: vec![0x0b; 22],
            salt: (0..=12).collect(),
            info: (0xf0..=0xf9).collect(),
            length: 42,
        },
        Case {
            input: (0..80).collect(),
            salt: (0x60..=0xaf).collect(),
            info: (0xb0..=0xff).collect(),
            length: 82,
        },
        Case {
            input: vec![0x0b; 22],
            salt: vec![],
            info: vec![],
            length: 42,
        },
        Case {
            input: vec![],
            salt: vec![],
            info: vec![],
            length: 0,
        },
        Case {
            input: vec![0, 255, 128, 1],
            salt: vec![0],
            info: vec![0, 255],
            length: 0,
        },
        Case {
            input: (0..=255).collect(),
            salt: (0..=255).collect(),
            info: (0..=255).rev().collect(),
            length: 8160,
        },
    ];
    for length in [0, 1, 55, 56, 63, 64, 65, 1023, 1024, 1025, 4097] {
        cases.push(Case {
            input: (0..length).map(|at| ((at * 37) % 256) as u8).collect(),
            salt: vec![0, 255, 128, 1],
            info: b"binary\0context".to_vec(),
            length: 32 + length % 3,
        });
    }
    cases.push(Case {
        input: (0..INPUT_LIMIT).map(|at| at as u8).collect(),
        salt: b"salt".to_vec(),
        info: vec![],
        length: 32,
    });
    let expected = oracle(&cases);
    for (at, rfc) in [
        "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865",
        "b11e398dc80327a1c8e7f78c596a49344f012eda2d4efad8a050cc4c19afa97c59045a99cac7827271cb41c65e590e09da3275600c2f09b8367793a9aca3db71cc30c58179ec3e87c14c01d5c1f3434f1d87",
        "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8",
    ].iter().enumerate() { assert_eq!(expected[at], format!("{rfc}\n").as_bytes()); }
    let mut native_cases = 0;
    for (case, expected) in cases.iter().zip(&expected) {
        let observed = run(
            &executable,
            &case.input,
            &case.args(),
            None,
            if case.input.len() == INPUT_LIMIT {
                20
            } else {
                5
            },
            false,
        );
        native_cases += 1;
        checked(&observed, 0, expected);
        let reads = calls(&observed.events, "read");
        assert_eq!(result(reads.last().unwrap()), "0", "actual EOF required");
        let first_write = observed
            .events
            .lines()
            .position(|line| line.starts_with("write("))
            .unwrap();
        let eof = observed
            .events
            .lines()
            .enumerate()
            .filter(|(_, line)| line.starts_with("read("))
            .map(|(at, _)| at)
            .last()
            .unwrap();
        assert!(eof < first_write, "no publication before EOF");
        if case.input.len() == INPUT_LIMIT {
            assert_eq!(request(reads.last().unwrap()), 1, "one-byte quota probe");
            assert_eq!(reads.len(), 1025);
        }
    }
    let base = &cases[8];
    let args = base.args();
    let baseline = &expected[8];
    // A real short regular-file read is hashed as exactly its returned length.
    let short = run(
        &executable,
        &cases[8].input,
        &cases[8].args(),
        None,
        5,
        false,
    );
    native_cases += 1;
    checked(&short, 0, &expected[8]);
    assert_eq!(result(calls(&short.events, "read")[0]), "55");
    let mut upper_args = cases[5].args();
    upper_args[1] = upper_args[1].to_uppercase();
    upper_args[2] = upper_args[2].to_uppercase();
    let upper = run(&executable, &cases[5].input, &upper_args, None, 5, false);
    native_cases += 1;
    checked(&upper, 0, &expected[5]);
    let usage: Vec<Vec<String>> = [
        vec![],
        vec!["32"],
        vec!["32", ""],
        vec!["32", "", "", "extra"],
        vec!["", "", ""],
        vec!["-1", "", ""],
        vec!["+1", "", ""],
        vec!["1x", "", ""],
        vec!["8161", "", ""],
        vec!["999999999999999999999", "", ""],
        vec!["32", "0", ""],
        vec!["32", "gg", ""],
        vec!["32", "0x", ""],
        vec!["32", "", "f"],
        vec!["32", "", "zz"],
    ]
    .into_iter()
    .map(|args| args.into_iter().map(str::to_owned).collect())
    .chain([
        vec!["32".to_owned(), "00".repeat(257), String::new()],
        vec!["32".to_owned(), String::new(), "00".repeat(257)],
    ])
    .collect();
    for args in usage {
        let observed = run(&executable, b"unconsumed", &args, None, 5, false);
        native_cases += 1;
        checked(&observed, 2, b"");
        assert!(
            calls(&observed.events, "read").is_empty()
                && calls(&observed.events, "write").is_empty(),
            "bad CLI must not touch stdin: {}",
            observed.events
        );
    }
    let too_long = vec![0; INPUT_LIMIT + 1];
    let observed = run(&executable, &too_long, &args, None, 20, false);
    native_cases += 1;
    checked(&observed, 7, b"");
    let reads = calls(&observed.events, "read");
    assert_eq!(reads.len(), 1025);
    assert_eq!(request(reads.last().unwrap()), 1);
    assert_eq!(result(reads.last().unwrap()), "1");
    for (fault, status, bytes) in [
        ("read:error=EINTR:when=1", 0, baseline.as_slice()),
        ("read:error=EIO:when=1", 3, b""),
        ("read:error=EAGAIN:when=1", 3, b""),
        ("read:retval=1025:when=1", 3, b""),
        ("write:error=EINTR:when=1", 0, baseline.as_slice()),
        ("write:error=EIO:when=1", 3, b""),
        ("write:error=EAGAIN:when=1", 3, b""),
        ("write:retval=0:when=1", 3, b""),
        ("write:retval=16322:when=1", 3, b""),
        ("rt_sigaction:error=EINTR:when=1", 3, b""),
    ] {
        let observed = run(&executable, &base.input, &args, Some(fault), 5, false);
        native_cases += 1;
        checked(&observed, status, bytes);
        if fault == "read:error=EINTR:when=1" {
            let reads = calls(&observed.events, "read");
            assert_eq!(
                reads.len(),
                3,
                "Interrupted -> data -> EOF: {}",
                observed.events
            );
            assert!(reads[0].contains("EINTR") && reads[0].contains("INJECTED"));
            assert_eq!(result(reads[1]), "55", "{}", observed.events);
            assert_eq!(result(reads[2]), "0", "{}", observed.events);
        }
    }
    let limited = run(
        &executable,
        b"budget",
        &args,
        Some("write:error=EINTR:when=1+"),
        20,
        false,
    );
    native_cases += 1;
    checked(&limited, 7, b"");
    assert_eq!(calls(&limited.events, "read").len(), 2);
    assert_eq!(
        calls(&limited.events, "write").len(),
        IO_LIMIT - 2,
        "reads and Interrupted writes share one budget"
    );
    let broken = run(&executable, &base.input, &args, None, 5, true);
    native_cases += 1;
    checked(&broken, 3, b"");
    let writes = calls(&broken.events, "write");
    assert_eq!(writes.len(), 1);
    assert!(writes[0].contains("EPIPE"));
    real_short_write(&executable, &base.input, &args, baseline);
    native_cases += 1;
    eprintln!("{} once-compiled derive_key native cases; {} independent HKDF model inputs; real RLIMIT_FSIZE short-write wrapper startup is not allocation-traced", native_cases, cases.len());
}
