#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output, Stdio},
    time::Duration,
};

fn executable() -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/arena_words.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("arena-words", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("arena-words: {error}"));
    let file = common::TempArtifact::new("laniusc_arena_words", "executable", None);
    file.write_bytes(&bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("arena-words", command, Duration::from_secs(10))
}
fn input(bytes: &[u8]) -> common::TempArtifact {
    let file = common::TempArtifact::new("laniusc_arena_words", "input", None);
    file.write_bytes(bytes);
    file
}
fn invoke(exe: &common::TempArtifact, args: &[&str], bytes: &[u8]) -> Output {
    let data = input(bytes);
    run(Command::new(exe.path())
        .args(args)
        .stdin(Stdio::from(std::fs::File::open(data.path()).unwrap())))
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    if status == 0 {
        assert!(output.stderr.is_empty(), "{output:?}");
    } else {
        let expected = match status {
            2 => b"arena-words: invalid arguments or resource limit exceeded\n".as_slice(),
            3 => b"arena-words: I/O failed\n".as_slice(),
            4 => b"arena-words: allocation failed\n".as_slice(),
            _ => panic!("unexpected status"),
        };
        assert_eq!(output.stderr, expected, "{output:?}");
    }
}
fn python_model(bytes: &[u8]) -> Vec<u8> {
    let data = input(bytes);
    let source = "import collections,re,sys\nwords=collections.Counter(x for x in re.split(br'[\\x09-\\x0D\\x20]+',sys.stdin.buffer.read()) if x)\nfor word,count in sorted(words.items()): sys.stdout.buffer.write(str(count).encode()+b'\\t'+word+b'\\n')\n";
    let output = run(Command::new("python3")
        .args(["-c", source])
        .stdin(Stdio::from(std::fs::File::open(data.path()).unwrap())));
    assert!(
        output.status.success() && output.stderr.is_empty(),
        "{output:?}"
    );
    output.stdout
}

#[test]
fn arena_words_streams_binary_words_across_chunks_and_matches_python_on_large_input() {
    let exe = executable();
    for bytes in [
        b"".as_slice(),
        b" \t\n\r\x0b\x0c",
        b"beta alpha beta\nalpha z",
        b"\0 \xff \xc0\x80\0 \0 \xff a\0 a\0\t",
        b"a A a\x85A a\xa0A",
    ] {
        let output = invoke(&exe, &[], bytes);
        checked(&output, 0);
        assert_eq!(output.stdout, python_model(bytes));
    }
    let mut boundaries = Vec::new();
    for length in [1, 1022, 1023, 1024, 1025, 2047, 4096, 65536] {
        let mut word = vec![b'a'; length];
        word[length - 1] = b'z';
        boundaries.extend_from_slice(&word);
        boundaries.push(b'\t');
        boundaries.extend_from_slice(&word);
        boundaries.extend_from_slice(b"\r\n");
    }
    let output = invoke(&exe, &[], &boundaries);
    checked(&output, 0);
    assert_eq!(output.stdout, python_model(&boundaries));
    // Twenty thousand stable keys survive arena chunk creation and map
    // relocation; another pass overwrites the reusable scratch for each key.
    let mut large = Vec::new();
    for pass in 0..3 {
        for index in (0..20000).rev() {
            large.extend_from_slice(format!("word{index:05}").as_bytes());
            if index % 7 == 0 {
                large.extend_from_slice(&[0, 255]);
            }
            large.push([b' ', b'\t', b'\n', b'\r', 11, 12][(index + pass) % 6]);
        }
    }
    let output = invoke(&exe, &[], &large);
    checked(&output, 0);
    assert_eq!(output.stdout, python_model(&large));
}

#[test]
fn arena_words_validates_arguments_and_exact_resource_boundaries_before_output() {
    let exe = executable();
    for args in [
        vec!["operand"],
        vec!["--bad"],
        vec!["--max-input-bytes"],
        vec!["--max-word-bytes=-1"],
        vec!["--max-word-bytes=1048577"],
        vec!["--max-unique=1000001"],
        vec!["--arena-bytes=1073741825"],
        vec!["--max-output-bytes=+1"],
        vec!["--max-output-bytes=18446744073709551616"],
        vec!["--help=yes"],
        vec!["--help", "operand"],
    ] {
        let output = invoke(&exe, &args, b"a a");
        checked(&output, 2);
        assert!(output.stdout.is_empty(), "{args:?}");
    }
    let output = invoke(&exe, &["--help"], b"ignored");
    checked(&output, 0);
    assert_eq!(output.stdout,b"Usage: arena-words [--max-input-bytes N] [--max-word-bytes N] [--max-unique N] [--arena-bytes N] [--max-output-bytes N]\n");
    for (args, bytes) in [
        (vec!["--max-input-bytes=0"], b"".as_slice()),
        (vec!["--max-input-bytes=3"], b"a a".as_slice()),
        (vec!["--max-word-bytes=0"], b" \t\n".as_slice()),
        (vec!["--max-word-bytes=3"], b"abc abc".as_slice()),
        (vec!["--max-unique=0"], b" \t\n".as_slice()),
        (vec!["--max-unique=2"], b"a b a b".as_slice()),
        (vec!["--arena-bytes=0"], b"\t".as_slice()),
        (vec!["--max-output-bytes=0"], b"\n".as_slice()),
        (vec!["--max-output-bytes=8"], b"a b a".as_slice()),
    ] {
        let output = invoke(&exe, &args, bytes);
        checked(&output, 0);
        assert_eq!(output.stdout, python_model(bytes));
    }
    for (args, bytes) in [
        (vec!["--max-input-bytes=0"], b" ".as_slice()),
        (vec!["--max-input-bytes=3"], b"a a ".as_slice()),
        (vec!["--max-word-bytes=0"], b"x".as_slice()),
        (vec!["--max-word-bytes=3"], b"abc abcd".as_slice()),
        (vec!["--max-unique=0"], b"x".as_slice()),
        (vec!["--max-unique=2"], b"a b a c".as_slice()),
        (vec!["--arena-bytes=0"], b"x".as_slice()),
        (vec!["--max-output-bytes=7"], b"a b a".as_slice()),
    ] {
        let output = invoke(&exe, &args, bytes);
        checked(&output, 2);
        assert!(output.stdout.is_empty(), "{args:?}");
    }
    // A tiny arena holds one key; repeated occurrences do not request more
    // arena storage. Two distinct bytes force a resource failure.
    let once = invoke(&exe, &["--arena-bytes=33"], b"x");
    checked(&once, 0);
    assert_eq!(once.stdout, b"1\tx\n");
    let output = invoke(&exe, &["--arena-bytes=33"], &b"x ".repeat(20000));
    checked(&output, 0);
    assert_eq!(output.stdout, b"20000\tx\n");
    let output = invoke(&exe, &["--arena-bytes=33"], b"x y");
    checked(&output, 2);
    assert!(output.stdout.is_empty());
}

fn no_leaks(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                assert!(
                    live.insert(result.split_whitespace().next().unwrap().to_owned()),
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
    assert!(live.is_empty(), "leaked owners: {events}");
    count
}

#[test]
fn arena_words_releases_all_owners_on_every_observed_allocation_read_and_write_failure() {
    let exe = executable();
    let trace = common::TempArtifact::new("laniusc_arena_words", "trace", None);
    let mut bytes = Vec::new();
    for index in 0..80 {
        bytes.extend_from_slice(format!("word{index:03}").as_bytes());
        bytes.extend(vec![b'x'; 100]);
        bytes.push(b' ');
    }
    bytes.extend(vec![b'z'; 1500]);
    bytes.extend_from_slice(b" tail tail ");
    let expected = python_model(&bytes);
    let data = input(&bytes);
    let execute = |injection: Option<&str>, status| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,read,write"]);
        if let Some(value) = injection {
            command.arg("-e").arg(format!("inject={value}"));
        }
        let output = run(command
            .arg(exe.path())
            .stdin(Stdio::from(std::fs::File::open(data.path()).unwrap())));
        checked(&output, status);
        let events = std::fs::read_to_string(trace.path()).unwrap();
        let allocations = no_leaks(&events);
        if injection.is_some_and(|s| !s.ends_with('+')) {
            assert!(events.contains("INJECTED"), "{events}");
        }
        (output, allocations, events)
    };
    let (output, allocations, events) = execute(None, 0);
    assert_eq!(output.stdout, expected);
    assert!(allocations >= 12, "{events}");
    for when in 1..=allocations {
        let (output, _, _) = execute(Some(&format!("mmap:error=ENOMEM:when={when}")), 4);
        assert!(output.stdout.is_empty());
    }
    let reads = events
        .lines()
        .filter(|line| line.starts_with("read("))
        .count();
    let writes = events
        .lines()
        .filter(|line| line.starts_with("write("))
        .count();
    for when in 1..=reads {
        let (output, _, _) = execute(Some(&format!("read:error=EIO:when={when}")), 3);
        assert!(output.stdout.is_empty());
    }
    for when in 1..=writes {
        execute(Some(&format!("write:error=EIO:when={when}")), 3);
    }
    for fault in ["read:error=EINTR:when=1", "write:error=EINTR:when=1"] {
        let (output, _, _) = execute(Some(fault), 0);
        assert_eq!(output.stdout, expected);
    }
    for fault in [
        "read:error=EAGAIN:when=1",
        "write:error=EAGAIN:when=1",
        "write:retval=0:when=1",
    ] {
        execute(Some(fault), 3);
    }
    let repeated = bytes.repeat(16);
    data.write_bytes(&repeated);
    let (output, actual, events) = execute(
        Some(&format!("mmap:error=ENOMEM:when={}+", allocations + 1)),
        0,
    );
    assert_eq!(actual, allocations);
    assert!(!events.contains("INJECTED"), "{events}");
    assert_eq!(output.stdout, python_model(&repeated));
}
