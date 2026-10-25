#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    sync::OnceLock,
    time::{Duration, Instant},
};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn compile(entry: PathBuf) -> common::TempArtifact {
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("lex-scan", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("lex-scan: {error:?}"));
    let exe = common::TempArtifact::new("lex_scan", "executable", None);
    exe.write_bytes(bytes);
    fs::set_permissions(exe.path(), fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn cli() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| compile(root().join("sample_programs/library/lex_scan.lani")))
}
fn io_fixture() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let sample =
            fs::read_to_string(root().join("sample_programs/library/lex_scan.lani")).unwrap();
        assert_eq!(sample.matches("fn main() -> i32 {").count(), 1);
        let mut source = sample.replace("fn main() -> i32 {", "fn command_main() -> i32 {");
        source.push('\n');
        source.push_str(
            &fs::read_to_string(root().join("tests/fixtures/extended/lex_scan/io_contracts.lani"))
                .unwrap(),
        );
        let entry = common::TempArtifact::new("lex_scan", "io_contracts", Some("lani"));
        entry.write_str(&source);
        compile(entry.path().to_path_buf())
    })
}
fn file(name: &str, bytes: &[u8]) -> common::TempArtifact {
    let file = common::TempArtifact::new("lex_scan", name, None);
    file.write_bytes(bytes);
    file
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("lex-scan execution", command, Duration::from_secs(60))
}
fn invoke(rules: &[u8], input: &[u8], mode: &str, flags: &[&str]) -> Output {
    let rules = file("rules", rules);
    let input = file("input", input);
    run(Command::new(cli().path())
        .arg(mode)
        .arg(rules.path())
        .args(flags)
        .stdin(Stdio::from(fs::File::open(input.path()).unwrap())))
}
fn checked(output: &Output, code: i32) {
    assert_eq!(output.status.code(), Some(code), "{output:?}");
    if code == 0 {
        assert!(output.stderr.is_empty(), "{output:?}");
    } else {
        assert!(
            output.stderr.starts_with(b"lex-scan: ")
                && output.stderr.ends_with(b"\n")
                && !output.stderr.contains(&0),
            "{output:?}"
        );
    }
}
fn rules(rows: &[(i32, &str, bool)]) -> Vec<u8> {
    let mut bytes = String::from("id,pattern,skip\n");
    for &(id, pattern, skip) in rows {
        bytes.push_str(&format!(
            "{id},\"{}\",{}\n",
            pattern.replace('"', "\"\""),
            u8::from(skip)
        ));
    }
    bytes.into_bytes()
}
type Span = (i32, usize, usize);
fn reference(input: &str) -> Vec<Span> {
    // A small independent classifier for the example grammar. It derives
    // maximal lexemes from character classes, without a regex engine or NFA.
    let bytes = input.as_bytes();
    let mut at = 0;
    let mut result = Vec::new();
    while at < bytes.len() {
        let start = at;
        let id = if bytes[at].is_ascii_alphabetic() || bytes[at] == b'_' {
            at += 1;
            while at < bytes.len() && (bytes[at].is_ascii_alphanumeric() || bytes[at] == b'_') {
                at += 1;
            }
            if &bytes[start..at] == b"if" { 10 } else { 90 }
        } else if bytes[at].is_ascii_digit() {
            at += 1;
            while at < bytes.len() && bytes[at].is_ascii_digit() {
                at += 1;
            }
            30
        } else if bytes[at] == b'=' {
            at += 1;
            if at < bytes.len() && bytes[at] == b'=' {
                at += 1;
            }
            40
        } else if matches!(bytes[at], b' ' | b'\t' | b'\r' | b'\n') {
            at += 1;
            while at < bytes.len() && matches!(bytes[at], b' ' | b'\t' | b'\r' | b'\n') {
                at += 1;
            }
            continue;
        } else {
            assert!(input[at..].starts_with('λ'));
            at += 2;
            while input[at..].starts_with('λ') {
                at += 2;
            }
            20
        };
        result.push((id, start, at));
    }
    result
}
fn spans_output(tokens: &[Span]) -> Vec<u8> {
    let mut output = String::from("id,start,end\n");
    for &(id, start, end) in tokens {
        output.push_str(&format!("{id},{start},{end}\n"));
    }
    output.into_bytes()
}
fn counts_output(tokens: &[Span]) -> Vec<u8> {
    let mut counts = BTreeMap::new();
    for &(id, _, _) in tokens {
        *counts.entry(id).or_insert(0u64) += 1;
    }
    let mut output = String::from("id,count\n");
    for id in [10, 90, 30, 40, 20] {
        output.push_str(&format!("{id},{}\n", counts.get(&id).copied().unwrap_or(0)));
    }
    output.into_bytes()
}

#[test]
fn real_cli_uses_csv_priority_maximal_spans_and_deterministic_kind_counts() {
    let grammar = fs::read(root().join("tests/fixtures/extended/lex_scan/example.csv")).unwrap();
    let atoms = [
        "if", "ifx", "_", "a1", "12", "=", "==", "λλ", " ", "\n", "\t",
    ];
    let mut inputs = vec![
        String::new(),
        String::from("if iffy == = 12 λλλ\n"),
        String::from("λx12"),
    ];
    for left in atoms {
        for right in atoms {
            inputs.push(format!("{left}{right}"));
        }
    }
    for input in &inputs {
        let tokens = reference(input);
        for (mode, expected) in [
            ("spans", spans_output(&tokens)),
            ("counts", counts_output(&tokens)),
        ] {
            let output = invoke(&grammar, input.as_bytes(), mode, &[]);
            checked(&output, 0);
            assert_eq!(output.stdout, expected, "{mode}: {input:?}");
        }
    }
    for (grammar, input, expected) in [
        (
            rules(&[(7, "a|ab", false), (8, "ab", false)]),
            b"ab".to_vec(),
            b"id,start,end\n7,0,2\n".to_vec(),
        ),
        (
            rules(&[(8, "ab", false), (7, "a|ab", false)]),
            b"ab".to_vec(),
            b"id,start,end\n8,0,2\n".to_vec(),
        ),
        (
            rules(&[(0, "[,]", false), (2, "\"", false)]),
            b",\"".to_vec(),
            b"id,start,end\n0,0,1\n2,1,2\n".to_vec(),
        ),
        (
            rules(&[(i32::MAX, ".", false)]),
            vec![0],
            b"id,start,end\n2147483647,0,1\n".to_vec(),
        ),
        (
            rules(&[(1, "a*", false)]),
            vec![],
            b"id,start,end\n".to_vec(),
        ),
    ] {
        let output = invoke(&grammar, &input, "spans", &[]);
        checked(&output, 0);
        assert_eq!(output.stdout, expected);
    }
    let eof = invoke(
        &grammar,
        b"if ",
        "spans",
        &[
            "--max-input=3",
            "--max-tokens=1",
            "--max-calls=12",
            "--max-work=12582912",
        ],
    );
    checked(&eof, 0);
    assert_eq!(eof.stdout, b"id,start,end\n10,0,2\n");
    let skip = invoke(&grammar, b" \n", "spans", &["--max-tokens=0"]);
    checked(&skip, 0);
    assert_eq!(skip.stdout, b"id,start,end\n");
    let empty = invoke(
        &grammar,
        b"",
        "spans",
        &[
            "--max-input=0",
            "--max-tokens=0",
            "--max-calls=0",
            "--max-work=0",
        ],
    );
    checked(&empty, 0);
    assert_eq!(empty.stdout, b"id,start,end\n");
    eprintln!(
        "lex-scan: {} grammar inputs in both modes plus longest/tie/Unicode/CSV/EOF boundaries",
        inputs.len()
    );
}

#[test]
fn malformed_rules_context_failures_and_all_cli_resource_knobs_publish_nothing() {
    let grammar = fs::read(root().join("tests/fixtures/extended/lex_scan/example.csv")).unwrap();
    let bad_rules = vec![
        vec![],
        b"id,pattern,skip\n".to_vec(),
        b"kind,pattern,skip\n1,a,0\n".to_vec(),
        b"id,pattern,skip\n1,a,0,extra\n".to_vec(),
        b"id,pattern,skip\n1,a\n".to_vec(),
        b"id,pattern,skip\n1,\"a,0\n".to_vec(),
        b"id,pattern,skip\n-1,a,0\n".to_vec(),
        b"id,pattern,skip\n+1,a,0\n".to_vec(),
        b"id,pattern,skip\n2147483648,a,0\n".to_vec(),
        b"id,pattern,skip\n1,a,true\n".to_vec(),
        b"id,pattern,skip\n1,a,2\n".to_vec(),
        b"id,pattern,skip\n01,a,0\n1,b,0\n".to_vec(),
        b"id,pattern,skip\n1,\xff,0\n".to_vec(),
        b"id,pattern,skip\n1,\x00,0\n".to_vec(),
        rules(&[(1, "(", false)]),
        rules(&[(1, "a{300}", false)]),
        rules(&[(1, &"a".repeat(1025), false)]),
        format!(
            "id,pattern,skip\n{}",
            (0..65).map(|id| format!("{id},a,0\n")).collect::<String>()
        )
        .into_bytes(),
        vec![b'a'; 65537],
    ];
    for source in bad_rules {
        let output = invoke(&source, b"a", "spans", &[]);
        checked(&output, 2);
        assert!(output.stdout.is_empty(), "{output:?}");
    }
    for (source, input) in [
        (grammar.clone(), b"if?".to_vec()),
        (grammar.clone(), b"if\xff".to_vec()),
        (rules(&[(1, "a", false), (2, "^b", false)]), b"ab".to_vec()),
        (
            rules(&[(1, "a", false), (2, "\\bb", false)]),
            b"ab".to_vec(),
        ),
        (rules(&[(1, "a*", false)]), b"b".to_vec()),
        (rules(&[(1, "a*", true)]), b"b".to_vec()),
    ] {
        let output = invoke(&source, &input, "spans", &[]);
        checked(&output, 2);
        assert!(output.stdout.is_empty(), "{output:?}");
    }
    for flags in [
        vec!["--max-input=1"],
        vec!["--max-tokens=0"],
        vec!["--max-output=0"],
        vec!["--max-output=18"],
        vec!["--max-calls=5"],
        vec!["--max-work=6291455"],
        vec!["--max-call-work=1"],
        vec!["--max-input=4194305"],
        vec!["--max-tokens=1000001"],
        vec!["--max-output=16777217"],
        vec!["--max-calls=16777217"],
        vec!["--max-call-work=16777217"],
        vec!["--max-call-work=0"],
        vec!["--max-work=1125899906842625"],
        vec!["--max-input=-1"],
        vec!["--max-input=+1"],
        vec!["--max-input="],
        vec!["--max-input=1", "--max-input=2"],
        vec!["--unknown"],
        vec!["--help"],
    ] {
        let output = invoke(&grammar, b"if", "spans", &flags);
        checked(&output, 2);
        assert!(output.stdout.is_empty(), "{flags:?}: {output:?}");
    }
    let zero = file("empty", b"");
    let output = run(Command::new(cli().path())
        .arg("--help")
        .stdin(Stdio::from(fs::File::open(zero.path()).unwrap())));
    checked(&output, 0);
    assert!(
        output
            .stdout
            .starts_with(b"Usage: lex-scan spans|counts RULES.csv")
    );
    for args in [
        vec![],
        vec!["spans"],
        vec!["other", "unused"],
        vec!["spans", "unused", "extra"],
    ] {
        let output = run(Command::new(cli().path()).args(args));
        checked(&output, 2);
        assert!(output.stdout.is_empty());
    }
    let output =
        run(Command::new(cli().path()).args(["spans", "/this/lex-scan-rule-file-does-not-exist"]));
    checked(&output, 3);
    assert!(output.stdout.is_empty());
}

#[derive(Debug)]
struct MemoryEvent {
    allocation: bool,
    address: String,
    size: usize,
    ordinal: usize,
}
struct Ledger {
    attempts: Vec<usize>,
    failed: usize,
    opens: usize,
    closes: usize,
    memory: Vec<MemoryEvent>,
}
fn ledger(trace: &str) -> Ledger {
    let mut mappings = BTreeMap::<String, usize>::new();
    let mut handles = BTreeSet::new();
    let mut attempts = Vec::new();
    let mut failed = 0;
    let mut opens = 0;
    let mut closes = 0;
    let mut memory = Vec::new();
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            let size = line.split(',').nth(1).unwrap().trim().parse().unwrap();
            attempts.push(size);
            let address = line
                .rsplit_once(" = ")
                .unwrap()
                .1
                .split_whitespace()
                .next()
                .unwrap();
            memory.push(MemoryEvent {
                allocation: true,
                address: address.to_owned(),
                size,
                ordinal: attempts.len(),
            });
            if address.starts_with("0x") {
                assert!(
                    mappings.insert(address.to_owned(), size).is_none(),
                    "{trace}"
                );
            } else {
                assert_eq!(address, "-1", "{trace}");
                assert!(line.contains("ENOMEM"), "{trace}");
                failed += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            let (args, result) = tail.split_once(')').unwrap();
            let (address, size) = args.split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            memory.push(MemoryEvent {
                allocation: false,
                address: address.trim().to_owned(),
                size,
                ordinal: 0,
            });
            assert_eq!(mappings.remove(address.trim()), Some(size), "{trace}");
            assert_eq!(result.trim(), "= 0", "{trace}");
        } else if line.starts_with("open(") || line.starts_with("openat(") {
            let result = line
                .rsplit_once(" = ")
                .unwrap()
                .1
                .split_whitespace()
                .next()
                .unwrap();
            if result != "-1" {
                let fd: i32 = result.parse().unwrap();
                assert!(handles.insert(fd), "{trace}");
                opens += 1;
            }
        } else if let Some(tail) = line.strip_prefix("close(") {
            let fd: i32 = tail.split_once(')').unwrap().0.parse().unwrap();
            assert!(handles.remove(&fd), "double/unowned close: {trace}");
            closes += 1;
        } else {
            assert!(
                line.starts_with("read(") || line.starts_with("write("),
                "unexpected trace: {line}"
            );
        }
    }
    assert!(mappings.is_empty(), "unreleased mappings: {trace}");
    assert!(handles.is_empty(), "unretired rule descriptor: {trace}");
    Ledger {
        attempts,
        failed,
        opens,
        closes,
        memory,
    }
}
fn eager_frame_episode(baseline: &Ledger) -> (usize, usize) {
    // The one-literal regex constructor's initial code/frame allocations
    // form a unique adjacent owner episode: allocate parent, allocate frame,
    // immediately release that same frame. Derive its ordinal/request from
    // observed lifetimes, without native record widths or a fixed ordinal.
    let candidates = baseline
        .memory
        .windows(3)
        .filter_map(|events| {
            let [parent, temporary, released] = events else {
                unreachable!()
            };
            (parent.allocation
                && temporary.allocation
                && !released.allocation
                && temporary.address == released.address
                && temporary.size == released.size)
                .then_some((parent.ordinal, temporary.size))
        })
        .collect::<Vec<_>>();
    assert_eq!(candidates.len(), 1, "{:?}", baseline.memory);
    candidates[0]
}
fn allocation_failure_path(
    actual: &Ledger,
    baseline: &Ledger,
    point: usize,
    eager_frame: (usize, usize),
) {
    assert_eq!(
        actual.attempts.get(..point),
        Some(&baseline.attempts[..point])
    );
    let continuation = &actual.attempts[point..];
    if continuation.is_empty() {
        return;
    }
    assert_eq!(point, eager_frame.0, "{:?}", actual.memory);
    assert_eq!(continuation, [eager_frame.1], "{:?}", actual.memory);
    let failed = actual
        .memory
        .iter()
        .position(|event| event.allocation && event.ordinal == point)
        .unwrap();
    let temporary = &actual.memory[failed + 1];
    let released = &actual.memory[failed + 2];
    assert!(temporary.allocation && !released.allocation);
    assert_eq!(temporary.size, eager_frame.1);
    assert_eq!(temporary.address, released.address);
    assert_eq!(temporary.size, released.size);
}
fn injected(trace: &str, syscall: &str, errno: &str, ordinal: usize) {
    let marked = trace
        .lines()
        .filter(|line| line.contains("INJECTED"))
        .collect::<Vec<_>>();
    assert_eq!(marked.len(), 1, "{trace}");
    let calls = trace
        .lines()
        .filter(|line| line.starts_with(&format!("{syscall}(")))
        .collect::<Vec<_>>();
    assert_eq!(calls.get(ordinal - 1), marked.first(), "{trace}");
    let result = marked[0].rsplit_once(" = ").unwrap().1;
    assert_eq!(
        result.split_whitespace().take(2).collect::<Vec<_>>(),
        ["-1", errno],
        "{trace}"
    );
}
fn traced(
    rules: &[u8],
    input: &[u8],
    mode: &str,
    fault: Option<&str>,
    io: bool,
) -> (Output, String) {
    let grammar = file("rules", rules);
    let source = file("input", input);
    trace_paths(grammar.path(), source.path(), mode, fault, io)
}
fn trace_paths(
    grammar: &Path,
    source: &Path,
    mode: &str,
    fault: Option<&str>,
    io: bool,
) -> (Output, String) {
    let trace = common::TempArtifact::new("lex_scan", "trace", None);
    let mut command = Command::new("strace");
    command.args(["-qq", "-o"]).arg(trace.path()).args([
        "-e",
        if io {
            "trace=mmap,munmap,read,write,open,openat,close"
        } else {
            "trace=mmap,munmap"
        },
    ]);
    if let Some(fault) = fault {
        command.args(["-e", fault]);
    }
    command
        .arg(cli().path())
        .arg(mode)
        .arg(grammar)
        .stdin(Stdio::from(fs::File::open(source).unwrap()));
    let output = run(&mut command);
    (output, fs::read_to_string(trace.path()).unwrap())
}

#[test]
fn all_reached_application_ooms_close_rules_and_release_every_mapping_before_publication() {
    let grammar = rules(&[(7, "a", false)]);
    // Hold argv paths fixed across each allocation-failure campaign: the
    // owned argument snapshot's allocation size includes the rule path bytes.
    let grammar_file = file("rules", &grammar);
    let source_file = file("input", b"a");
    for mode in ["spans", "counts"] {
        let (baseline, events) =
            trace_paths(grammar_file.path(), source_file.path(), mode, None, true);
        checked(&baseline, 0);
        let original = ledger(&events);
        let eager_frame = eager_frame_episode(&original);
        assert!(original.attempts.len() > 10 && original.attempts.len() <= 256);
        assert_eq!((original.opens, original.closes), (1, 1));
        for point in 1..=original.attempts.len() {
            let (output, events) = trace_paths(
                grammar_file.path(),
                source_file.path(),
                mode,
                Some(&format!("inject=mmap:error=ENOMEM:when={point}")),
                true,
            );
            injected(&events, "mmap", "ENOMEM", point);
            checked(&output, 4);
            assert!(output.stdout.is_empty(), "{mode} OOM{point}: {output:?}");
            let actual = ledger(&events);
            assert_eq!(actual.failed, 1, "{events}");
            allocation_failure_path(&actual, &original, point, eager_frame);
        }
        eprintln!(
            "lex-scan {mode}: all {} reached application mmap failures cleaned",
            original.attempts.len()
        );
    }
    for (fault, syscall) in [
        ("inject=read:error=EINTR:when=1", "read"),
        ("inject=write:error=EINTR:when=1", "write"),
    ] {
        let (output, events) = traced(&grammar, b"a", "spans", Some(fault), true);
        injected(&events, syscall, "EINTR", 1);
        checked(&output, 0);
        assert_eq!(output.stdout, b"id,start,end\n7,0,1\n");
        ledger(&events);
    }
    for (fault, syscall) in [
        ("inject=read:error=EIO:when=1", "read"),
        ("inject=write:error=EIO:when=1", "write"),
        ("inject=close:error=EIO:when=1", "close"),
    ] {
        let (output, events) = traced(&grammar, b"a", "spans", Some(fault), true);
        injected(&events, syscall, "EIO", 1);
        checked(&output, 3);
        assert!(output.stdout.is_empty());
        ledger(&events);
    }
    let input = vec![b'a'; 256];
    let (output, events) = traced(
        &grammar,
        &input,
        "spans",
        Some("inject=write:error=EIO:when=2"),
        true,
    );
    injected(&events, "write", "EIO", 2);
    checked(&output, 3);
    let tokens = (0..256).map(|at| (7, at, at + 1)).collect::<Vec<_>>();
    let expected = spans_output(&tokens);
    assert_eq!(output.stdout, expected[..1024]);
    ledger(&events);
    let grammar = file("rules", &grammar);
    let input = file("input", b"a");
    let output = run(Command::new("sh")
        .args(["-c", "exec \"$@\" >/dev/full", "sh"])
        .arg(cli().path())
        .arg("spans")
        .arg(grammar.path())
        .stdin(Stdio::from(fs::File::open(input.path()).unwrap())));
    checked(&output, 3);
    assert!(output.stdout.is_empty());
    let output = run(Command::new("sh")
        .args(["-c", "exec 0<&-; exec \"$@\"", "sh"])
        .arg(cli().path())
        .arg("spans")
        .arg(grammar.path()));
    checked(&output, 3);
    assert!(output.stdout.is_empty());
}

#[test]
fn scripted_production_io_helpers_bound_partial_progress_interruptions_and_eof_probes() {
    let trace = common::TempArtifact::new("lex_scan", "io_trace", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"])
        .arg(io_fixture().path()));
    checked(&output, 0);
    assert!(output.stdout.is_empty());
    ledger(&fs::read_to_string(trace.path()).unwrap());
}

#[test]
fn four_thousand_tokens_report_real_allocation_cost_with_exact_counts() {
    let input = vec![b'a'; 4096];
    let grammar = rules(&[(7, "a", false)]);
    let started = Instant::now();
    let (output, events) = traced(&grammar, &input, "counts", None, false);
    checked(&output, 0);
    assert_eq!(output.stdout, b"id,count\n7,4096\n");
    let allocations = ledger(&events);
    assert_eq!(allocations.failed, 0);
    eprintln!(
        "lex-scan 4096-token resource receipt: {} mmap requests, balanced releases, {:?} traced wall time; correctness/cost observation only",
        allocations.attempts.len(),
        started.elapsed()
    );
}
