#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    sync::OnceLock,
    time::Duration,
};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("openssl-hash", command, Duration::from_secs(20))
}
fn compile(entry: PathBuf) -> common::TempArtifact {
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let options = laniusc_compiler::compiler::NativeLinkOptions {
        libraries: vec!["crypto".into()],
        ..Default::default()
    };
    let bytes = common::run_gpu_codegen_with_timeout("openssl-hash", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ),
        )
    })
    .unwrap_or_else(|error| panic!("openssl-hash: {error}"));
    let executable = common::TempArtifact::new("laniusc_openssl_hash", "executable", None);
    // This profile has system CRT/PLT functions. Validate its generated local
    // function ranges with the linked-ELF checker before executing the bytes.
    std::fs::write(executable.path(), bytes).unwrap();
    let validation = run(Command::new("python3")
        .arg(root().join("tests/fixtures/native_c/validate_linked_elf.py"))
        .arg(executable.path()));
    assert!(validation.status.success(), "{validation:?}");
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn cli() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile(root().join("sample_programs/library/openssl_hash.lani")))
}
fn stream_fixture() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let sample =
            std::fs::read_to_string(root().join("sample_programs/library/openssl_hash.lani"))
                .unwrap();
        assert_eq!(sample.matches("fn main() -> i32 {").count(), 1);
        let mut source = sample.replace("fn main() -> i32 {", "fn command_main() -> i32 {");
        source.push('\n');
        source.push_str(
            &std::fs::read_to_string(
                root().join("tests/fixtures/extended/openssl_hash/stream_contracts.lani"),
            )
            .unwrap(),
        );
        let entry = common::TempArtifact::new("laniusc_openssl_hash", "streams", Some("lani"));
        entry.write_str(&source);
        compile(entry.path().to_path_buf())
    })
}
fn input(bytes: &[u8]) -> common::TempArtifact {
    let file = common::TempArtifact::new("laniusc_openssl_hash", "input", None);
    file.write_bytes(bytes);
    file
}
fn invoke(executable: &Path, args: &[&str], bytes: &[u8]) -> Output {
    let file = input(bytes);
    run(Command::new(executable)
        .args(args)
        .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())))
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    if status == 0 {
        assert!(output.stderr.is_empty(), "{output:?}");
    } else {
        assert!(
            output.stderr.starts_with(b"openssl-hash: ")
                && output.stderr.ends_with(b"\n")
                && !output.stderr.contains(&0),
            "{output:?}"
        );
    }
}
fn reference(algorithm: &str, bytes: &[u8]) -> Vec<u8> {
    let file = input(bytes);
    let output = run(Command::new("openssl")
        .args(["dgst", "-binary", &format!("-{algorithm}")])
        .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())));
    assert!(output.status.success(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let mut encoded = Vec::with_capacity(output.stdout.len() * 2 + 1);
    for byte in output.stdout {
        encoded.push(b"0123456789abcdef"[(byte >> 4) as usize]);
        encoded.push(b"0123456789abcdef"[(byte & 15) as usize]);
    }
    encoded.push(b'\n');
    encoded
}

#[test]
fn stdin_binary_empty_chunk_boundaries_and_multichunk_digests_match_openssl() {
    for algorithm in ["sha256", "sha512", "sha3-256", "sha3-512"] {
        for length in [0, 1, 7, 1023, 1024, 1025, 8193, 65537] {
            let bytes: Vec<u8> = (0..length).map(|i| ((i * 37) ^ (i / 256)) as u8).collect();
            let output = invoke(cli().path(), &[algorithm], &bytes);
            checked(&output, 0);
            assert_eq!(
                output.stdout,
                reference(algorithm, &bytes),
                "{algorithm} {length}"
            );
        }
    }
    let binary = b"leading\0NUL\xff\x80\ntrailing\0";
    let output = invoke(cli().path(), &["sha256"], binary);
    checked(&output, 0);
    assert_eq!(output.stdout, reference("sha256", binary));
}

#[test]
fn arguments_exact_input_and_io_bounds_fail_before_output() {
    for args in [
        vec![],
        vec!["sha1"],
        vec!["SHA256"],
        vec!["sha256", "sha512"],
        vec!["sha256", "--unknown"],
        vec!["sha256", "--max-input"],
        vec!["sha256", "--max-input=-1"],
        vec!["sha256", "--max-input=+1"],
        vec!["sha256", "--max-input=2147483648"],
        vec!["sha256", "--max-io-calls=abc"],
        vec!["--help=yes"],
        vec!["--help", "--unknown"],
    ] {
        let output = invoke(cli().path(), &args, b"unread");
        checked(&output, 2);
        assert!(output.stdout.is_empty(), "{output:?}");
    }
    for (args, bytes, status) in [
        (vec!["sha256", "--max-input=0"], b"".as_slice(), 0),
        (vec!["sha256", "--max-input=0"], b"x".as_slice(), 2),
        (vec!["sha256", "--max-input=3"], b"abc".as_slice(), 0),
        (vec!["sha256", "--max-input=2"], b"abc".as_slice(), 2),
        (vec!["sha256", "--max-io-calls=0"], b"".as_slice(), 2),
        (vec!["sha256", "--max-io-calls=1"], b"".as_slice(), 2),
        (vec!["sha256", "--max-io-calls=2"], b"".as_slice(), 0),
        (vec!["sha256", "--max-io-calls=2"], b"abc".as_slice(), 2),
        (vec!["sha256", "--max-io-calls=3"], b"abc".as_slice(), 0),
    ] {
        let output = invoke(cli().path(), &args, bytes);
        checked(&output, status);
        if status == 0 {
            assert_eq!(output.stdout, reference("sha256", bytes));
        } else {
            assert!(output.stdout.is_empty(), "{output:?}");
            assert!(String::from_utf8_lossy(&output.stderr).contains("limit"));
        }
    }
    let repeated = invoke(
        cli().path(),
        &["sha256", "--max-input=0", "--max-input", "3"],
        b"abc",
    );
    checked(&repeated, 0);
    assert_eq!(repeated.stdout, reference("sha256", b"abc"));
    let help = invoke(cli().path(), &["-h"], b"unread");
    checked(&help, 0);
    assert_eq!(
        help.stdout,
        b"Usage: openssl-hash sha256|sha512|sha3-256|sha3-512 [--max-input N] [--max-io-calls N]\n"
    );
    let count_limit = invoke(cli().path(), &vec!["-h"; 17], b"");
    checked(&count_limit, 2);
    assert!(count_limit.stdout.is_empty());
    let too_long = "x".repeat(4097);
    let byte_limit = invoke(cli().path(), &[&too_long], b"");
    checked(&byte_limit, 2);
    assert!(byte_limit.stdout.is_empty());
}

fn observer() -> &'static common::TempArtifact {
    static LIBRARY: OnceLock<common::TempArtifact> = OnceLock::new();
    LIBRARY.get_or_init(|| {
        let library = common::TempArtifact::new("laniusc_openssl_hash", "observer", Some("so"));
        let output = run(Command::new("cc")
            .args([
                "-std=c11", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC",
            ])
            .arg(root().join("tests/fixtures/extended/openssl_hash/native_trace.c"))
            .arg("-ldl")
            .arg("-o")
            .arg(library.path()));
        assert!(output.status.success(), "{output:?}");
        library
    })
}
fn observed(
    executable: &Path,
    args: &[&str],
    bytes: &[u8],
    stage: Option<&str>,
) -> (Output, String) {
    let file = input(bytes);
    let trace = common::TempArtifact::new("laniusc_openssl_hash", "trace", None);
    let mut command = Command::new(executable);
    command
        .args(args)
        .env("LD_PRELOAD", observer().path())
        .env("LANIUS_OPENSSL_HASH_TRACE", trace.path())
        .stdin(Stdio::from(std::fs::File::open(file.path()).unwrap()));
    if let Some(stage) = stage {
        command.env("LANIUS_OPENSSL_HASH_FAIL", stage);
    }
    let output = run(&mut command);
    let events = std::fs::read_to_string(trace.path()).unwrap_or_default();
    let mut method = 0;
    let mut context = 0;
    for event in events.lines() {
        match event {
            "method+" => {
                assert_eq!(method, 0, "{events}");
                method += 1;
            }
            "method-" => {
                assert_eq!(method, 1, "{events}");
                method -= 1;
            }
            "context+" => {
                assert_eq!(context, 0, "{events}");
                context += 1;
            }
            "context-" => {
                assert_eq!(context, 1, "{events}");
                context -= 1;
            }
            _ => panic!("unexpected native observation: {event}"),
        }
    }
    assert_eq!((method, context), (0, 0), "{events}");
    (output, events)
}

#[test]
fn partial_transfers_retry_exhaustion_and_all_native_failure_stages_release_owners() {
    let (contracts, events) = observed(stream_fixture().path(), &[], b"", None);
    checked(&contracts, 0);
    assert!(contracts.stdout.is_empty());
    assert!(
        events.lines().filter(|line| *line == "context+").count() >= 25,
        "{events}"
    );
    for stage in ["fetch", "size", "context", "init", "update", "final"] {
        let (output, events) = observed(cli().path(), &["sha256"], b"binary\0input", Some(stage));
        checked(&output, 4);
        assert!(output.stdout.is_empty());
        assert_eq!(output.stderr, b"openssl-hash: OpenSSL digest failed\n");
        if stage != "fetch" {
            assert!(events.contains("method+"), "{events}");
        }
        if matches!(stage, "init" | "update" | "final") {
            assert!(events.contains("context+"), "{events}");
        }
    }
    for args in [
        vec!["sha256"],
        vec!["sha256", "--max-input=0"],
        vec!["sha256", "--max-io-calls=0"],
        vec!["sha256", "--max-io-calls=1"],
        vec!["sha256", "--max-io-calls=2"],
    ] {
        let (output, events) = observed(cli().path(), &args, b"binary\0input", None);
        checked(&output, if args.len() == 1 { 0 } else { 2 });
        assert!(events.contains("context+"), "{events}");
    }
    let directory = std::fs::File::open(root()).unwrap();
    let bad_input = run(Command::new(cli().path())
        .arg("sha256")
        .stdin(Stdio::from(directory)));
    checked(&bad_input, 3);
    assert!(bad_input.stdout.is_empty());
    let source = input(b"binary\0input");
    let bad_output = run(Command::new("sh")
        .args(["-c", "exec \"$1\" sha256 >/dev/full", "openssl-hash"])
        .arg(cli().path())
        .stdin(Stdio::from(std::fs::File::open(source.path()).unwrap())));
    checked(&bad_output, 3);
    assert!(bad_output.stdout.is_empty());
}
