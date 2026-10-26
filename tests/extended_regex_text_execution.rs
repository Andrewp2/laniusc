//! Borrowed regex splitting and bounded owned replacement through real source.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output, Stdio},
    sync::OnceLock,
    time::Duration,
};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn fixture(name: &str) -> PathBuf {
    root().join("tests/fixtures/extended/regex_text").join(name)
}
fn executable(name: &str) -> common::TempArtifact {
    executable_entry(fixture(name), name)
}
fn executable_entry(entry: PathBuf, name: &str) -> common::TempArtifact {
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("regex text", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("regex text {name}: {error}"));
    let file = common::TempArtifact::new("laniusc_regex_text", name, None);
    file.write_bytes(bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn protocol() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| executable("protocol.lani"))
}
fn program() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| {
        executable_entry(
            root().join("sample_programs/library/regex_replace.lani"),
            "regex_replace",
        )
    })
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("regex text execution", command, Duration::from_secs(10))
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn ledger(trace: &str) -> usize {
    let mut live = BTreeMap::new();
    let mut attempts = 0;
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            attempts += 1;
            let size: usize = line.split(',').nth(1).unwrap().trim().parse().unwrap();
            let address = line
                .rsplit_once(" = ")
                .unwrap()
                .1
                .split_whitespace()
                .next()
                .unwrap();
            if address.starts_with("0x") {
                assert!(live.insert(address.to_owned(), size).is_none(), "{trace}");
            } else {
                assert_eq!(address, "-1", "{trace}");
                assert!(line.contains("ENOMEM"), "{trace}");
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            let (address, tail) = tail.split_once(',').unwrap();
            let size: usize = tail.split_once(')').unwrap().0.trim().parse().unwrap();
            assert_eq!(live.remove(address), Some(size), "{trace}");
            assert!(line.ends_with(" = 0"), "{trace}");
        }
    }
    assert!(live.is_empty(), "unreleased owner: {trace}");
    attempts
}

#[test]
fn regex_split_replace_preserve_utf8_views_exact_progress_budgets_and_owned_output() {
    let file = executable("contracts.lani");
    let trace = common::TempArtifact::new("laniusc_regex_text", "contracts_trace", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"])
        .arg(file.path()));
    checked(&output, 0);
    assert!(output.stdout.is_empty(), "{output:?}");
    assert!(ledger(&std::fs::read_to_string(trace.path()).unwrap()) > 0);
}

#[derive(Clone, Debug)]
struct Case {
    mode: u32,
    pattern: Vec<u8>,
    text: Vec<u8>,
    replacement: Vec<u8>,
    layout: u32,
    matches: u32,
    calls: u32,
    work: u64,
    output: u32,
    replacement_limit: u32,
    per_search: u32,
    flags: u32,
}
impl Case {
    fn new(mode: u32, pattern: &str, text: &str, replacement: &str) -> Self {
        Self {
            mode,
            pattern: pattern.as_bytes().to_vec(),
            text: text.as_bytes().to_vec(),
            replacement: replacement.as_bytes().to_vec(),
            layout: 0,
            matches: 32,
            calls: 33,
            work: 3_300_000,
            output: 65_536,
            replacement_limit: 8192,
            per_search: 100_000,
            flags: 0,
        }
    }
    fn encode(&self, bytes: &mut Vec<u8>) {
        for word in [
            self.mode,
            self.pattern.len() as u32,
            self.text.len() as u32,
            self.replacement.len() as u32,
            self.layout,
            self.matches,
            self.calls,
            self.work as u32,
            (self.work >> 32) as u32,
            self.output,
            self.replacement_limit,
            self.per_search,
            self.flags,
            0,
        ] {
            bytes.extend_from_slice(&word.to_le_bytes());
        }
        bytes.extend_from_slice(&self.pattern);
        bytes.extend_from_slice(&self.text);
        bytes.extend_from_slice(&self.replacement);
    }
}
fn payload(cases: &[Case]) -> common::TempArtifact {
    let input = common::TempArtifact::new("laniusc_regex_text", "input", None);
    let mut bytes = Vec::new();
    for case in cases {
        case.encode(&mut bytes);
    }
    input.write_bytes(bytes);
    input
}
fn execute_cases(cases: &[Case]) -> Vec<String> {
    let input = payload(cases);
    let output = run(Command::new(protocol().path())
        .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
    checked(&output, 0);
    let lines: Vec<_> = String::from_utf8(output.stdout)
        .unwrap()
        .lines()
        .map(str::to_owned)
        .collect();
    assert_eq!(lines.len(), cases.len());
    lines
}
fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write;
    let mut result = String::new();
    for byte in bytes {
        write!(result, "{byte:02x}").unwrap();
    }
    result
}
fn success_line(mode: u32, parts: &[&str], matches: u32, calls: u32) -> String {
    let mut line = if mode == 0 { "S" } else { "R" }.to_owned();
    line.push_str(
        &parts
            .iter()
            .map(|part| hex(part.as_bytes()))
            .collect::<Vec<_>>()
            .join("/"),
    );
    line.push_str(&format!(";{matches},{calls},{}", calls * 100_000));
    line
}

#[test]
fn regex_text_shared_nonempty_semantics_match_independent_python_re_model() {
    let atoms = ["a", "b", "[ab]", "[^x]", "é", "🙂", "[0-9]", "."];
    let texts = [
        "",
        "a",
        "abaababa",
        "a\0b",
        "éé🙂",
        "x12\na!",
        "e\u{301}ab",
        "🙂a🙂b",
    ];
    let templates = ["$0", "${1}:$2", "$$$1", "[${01}-$0]", "\\$2"];
    let literals = ["", "$1\\", "é\0🙂", "X", "-"];
    let mut seed = 0x6ab1_7a31u32;
    let mut cases = Vec::new();
    let mut atom_caps = [[0u8; 4]; 8];
    let mut atom_branches = [[false; 2]; 8];
    let mut texts_seen = [false; 8];
    for axis in 0..32 {
        let mut next = || {
            seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
            (seed >> 16) as usize
        };
        // Independent checked axes avoid low-bit PRNG correlations. Each
        // atom visits every cap and both branches; all eight texts occur.
        let block = axis / 8;
        let atom_index = axis % 8;
        let branch = (block + atom_index / 4) % 2;
        let text_index = (atom_index * 3 + block) % 8;
        let cap_index = (block + atom_index) % 4;
        atom_caps[atom_index][cap_index] += 1;
        atom_branches[atom_index][branch] = true;
        texts_seen[text_index] = true;
        let atom = atoms[atom_index];
        let pattern = if branch == 0 {
            format!("({atom}+)(b)?")
        } else {
            format!("((?:{atom}|b)+)(a)?")
        };
        let text = texts[text_index];
        let cap = [0, 1, 2, 7][cap_index];
        let template = templates[next() % templates.len()];
        let literal = literals[next() % literals.len()];
        for layout in 0..3 {
            for mode in 0..3 {
                let mut case = Case::new(
                    mode,
                    &pattern,
                    text,
                    if mode == 2 { template } else { literal },
                );
                case.layout = layout;
                case.matches = cap;
                case.calls = cap + 1;
                case.work = (cap as u64 + 1) * case.per_search as u64;
                cases.push(case);
            }
        }
    }
    assert!(atom_caps.iter().all(|row| *row == [1; 4]), "{atom_caps:?}");
    assert!(
        atom_branches.iter().all(|row| *row == [true; 2]),
        "{atom_branches:?}"
    );
    assert!(texts_seen.iter().all(|seen| *seen), "{texts_seen:?}");
    let input = payload(&cases);
    let expected = run(Command::new("python3")
        .arg(fixture("reference.py"))
        .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
    checked(&expected, 0);
    let expected: Vec<_> = String::from_utf8(expected.stdout)
        .unwrap()
        .lines()
        .map(str::to_owned)
        .collect();
    let actual = execute_cases(&cases);
    assert_eq!(actual.len(), expected.len());
    for (index, case) in cases.iter().enumerate() {
        assert_eq!(
            actual[index], expected[index],
            "model seed=0x6ab17a31 case{index}: {case:?}"
        );
    }
    eprintln!(
        "regex text Python re shared-subset model: {} cases, seed=0x6ab17a31",
        cases.len()
    );
}

#[test]
fn regex_text_zero_width_tables_template_preflight_and_resource_edges_are_explicit() {
    let mut examples = Vec::<(Case, String)>::new();
    // Independent byte-result tables intentionally differ from Python's
    // default re.split/sub policy for alternatives following an empty match.
    for (pattern, text, fields, replaced, count, calls) in [
        ("", "é🙂", vec!["", "é", "🙂", ""], "XéX🙂X", 3, 3),
        ("", "", vec!["", ""], "X", 1, 1),
        ("|a", "a", vec!["", "a", ""], "XaX", 2, 2),
        ("a*", "a", vec!["", "", ""], "XX", 2, 2),
        ("a*", "ba", vec!["", "b", "", ""], "XbXX", 3, 3),
        ("^|$", "é\0🙂", vec!["", "é\0🙂", ""], "Xé\0🙂X", 2, 2),
        ("(,)", ",a,,", vec!["", "a", "", ""], "XaXX", 3, 4),
    ] {
        for layout in 0..3 {
            let mut split = Case::new(0, pattern, text, "X");
            split.layout = layout;
            examples.push((split, success_line(0, &fields, count, calls)));
            for mode in 1..3 {
                let mut case = Case::new(mode, pattern, text, "X");
                case.layout = layout;
                examples.push((case, success_line(mode, &[replaced], count, calls)));
            }
        }
    }
    for (template, expected) in [
        ("$$:$0:${01}:$2", "$:a:a:"),
        ("$00/${0001}/$02", "a/a/"),
        ("\\$0", "\\a"),
    ] {
        examples.push((
            Case::new(2, "(a)(b)?", "a", template),
            success_line(2, &[expected], 1, 2),
        ));
    }
    for (template, error) in [
        ("$", "E5:0:0"),
        ("$name", "E5:0:0"),
        ("${}", "E5:0:0"),
        ("${1", "E5:0:0"),
        ("${1:-x}", "E5:0:0"),
        ("$2147483648", "E5:0:0"),
        ("é$9", "E6:2:9"),
        ("$12", "E6:0:12"),
    ] {
        let mut case = Case::new(2, "(a)(b)?", "none", template);
        case.matches = 0;
        case.calls = 0;
        case.work = 0;
        examples.push((case, error.into()));
    }
    for mode in 0..3 {
        let mut case = Case::new(mode, "a", "a", "X");
        case.matches = 0;
        case.calls = 0;
        case.work = 0;
        examples.push((case.clone(), success_line(mode, &["a"], 0, 0)));
        case.text = vec![0xff];
        examples.push((case, "E4:0:0".into()));
    }
    for (field, expected) in [
        (0, "E7:0:0"),
        (1, "E8:0:0"),
        (2, "E9:0:0"),
        (3, "E10:0:0"),
        (4, "E1:0:0"),
    ] {
        let mut case = Case::new(2, "(a)", "za", "$1");
        match field {
            0 => case.calls = 0,
            1 => case.work = 99_999,
            2 => case.output = 1,
            3 => case.replacement_limit = 1,
            _ => case.matches = u32::MAX,
        }
        examples.push((case, expected.into()));
    }
    let mut exact = Case::new(2, "(a)", "a", "$1");
    exact.calls = 2;
    exact.work = 200_000;
    exact.output = 1;
    exact.replacement_limit = 2;
    examples.push((exact.clone(), success_line(2, &["a"], 1, 2)));
    exact.work -= 1;
    examples.push((exact, "E8:0:0".into()));
    let mut malformed = Case::new(1, "a", "a", "");
    malformed.matches = 0;
    malformed.replacement = vec![0xc3];
    examples.push((malformed, "E4:0:0".into()));
    let mut no_output = Case::new(2, "z", "", "");
    no_output.output = 0;
    no_output.replacement_limit = 0;
    examples.push((no_output, success_line(2, &[""], 0, 1)));
    let cases: Vec<_> = examples.iter().map(|(case, _)| case.clone()).collect();
    let actual = execute_cases(&cases);
    for (index, ((case, expected), actual)) in examples.iter().zip(actual).enumerate() {
        assert_eq!(&actual, expected, "explicit case{index}: {case:?}");
    }
    eprintln!(
        "regex text independent zero-width/template/budget table: {} cases",
        examples.len()
    );
}

#[test]
fn every_reached_regex_text_allocation_failure_releases_exact_owners_and_preserves_sources() {
    let file = executable("allocations.lani");
    let trace = common::TempArtifact::new("laniusc_regex_text", "allocation_trace", None);
    let execute = |failure: Option<usize>| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if let Some(index) = failure {
            command.args(["-e", &format!("inject=mmap:error=ENOMEM:when={index}")]);
        }
        command.arg(file.path());
        let output = run(&mut command);
        let events = std::fs::read_to_string(trace.path()).unwrap();
        (output, events)
    };
    let (output, events) = execute(None);
    checked(&output, 0);
    assert_eq!(output.stdout, b"0\n");
    let points = ledger(&events);
    assert!(
        points >= 30 && points < 256,
        "bounded fixture did not reach expected owners: {events}"
    );
    let mut stages = [0usize; 6];
    for index in 1..=points {
        let (output, events) = execute(Some(index));
        checked(&output, 4);
        let stage: usize = std::str::from_utf8(&output.stdout)
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        assert!((1..=5).contains(&stage), "allocation{index}: {output:?}");
        stages[stage] += 1;
        ledger(&events);
        assert_eq!(
            events.matches("INJECTED").count(),
            1,
            "allocation{index}: {events}"
        );
    }
    assert!(stages[1..].iter().all(|count| *count > 0), "{stages:?}");
    eprintln!(
        "regex text all {points} reached OOM positions passed, setup/compile/replace/split/probe stages={:?}",
        &stages[1..]
    );
}

fn program_run(arguments: &[&str], bytes: &[u8], injection: Option<&str>) -> (Output, String) {
    let input = common::TempArtifact::new("laniusc_regex_text", "program_input", None);
    input.write_bytes(bytes);
    let trace = common::TempArtifact::new("laniusc_regex_text", "program_trace", None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap,read,write"]);
    if let Some(rule) = injection {
        command.args(["-e", rule]);
    }
    command
        .arg(program().path())
        .args(arguments)
        .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap()));
    let output = run(&mut command);
    let events = std::fs::read_to_string(trace.path()).unwrap();
    ledger(&events);
    (output, events)
}

#[test]
fn regex_replace_program_emits_exact_binary_and_handles_cli_input_output_and_search_caps() {
    let good: Vec<(Vec<&str>, Vec<u8>, Vec<u8>)> = vec![
        (
            vec!["literal", "a", "$1\\"],
            b"aba\0".to_vec(),
            b"$1\\b$1\\\0".to_vec(),
        ),
        (
            vec!["template", "(a)(b)?", "[$2:$1:$0]$$"],
            b"a ab".to_vec(),
            b"[:a:a]$ [b:a:ab]$".to_vec(),
        ),
        (
            vec!["template", "(.)", "<$1>"],
            "é\0🙂".as_bytes().to_vec(),
            "<é><\0><🙂>".as_bytes().to_vec(),
        ),
        (vec!["literal", "|a", "X"], b"a".to_vec(), b"XaX".to_vec()),
        (
            vec!["literal", "a", "X", "--max-matches", "1"],
            b"aaa".to_vec(),
            b"Xaa".to_vec(),
        ),
        (
            vec![
                "literal",
                "a",
                "X",
                "--max-matches=0",
                "--max-calls=0",
                "--max-work=0",
            ],
            b"a".to_vec(),
            b"a".to_vec(),
        ),
        (
            vec![
                "literal",
                "a",
                "X",
                "--max-input=1",
                "--max-output=1",
                "--max-calls=2",
                "--max-work=20000000",
            ],
            b"a".to_vec(),
            b"X".to_vec(),
        ),
        (
            vec!["literal", "z", "", "--max-input=0", "--max-output=0"],
            vec![],
            vec![],
        ),
        (
            vec!["literal", "--", "-", "X"],
            b"-a-".to_vec(),
            b"XaX".to_vec(),
        ),
    ];
    let good_count = good.len();
    for (arguments, input, expected) in good {
        let (output, _) = program_run(&arguments, &input, None);
        checked(&output, 0);
        assert_eq!(output.stdout, expected, "{arguments:?}");
    }
    let bad: Vec<(Vec<&str>, Vec<u8>)> = vec![
        (vec![], vec![]),
        (vec!["other", "a", "b"], vec![]),
        (vec!["literal", "(", "b"], vec![]),
        (vec!["template", "a", "$name"], b"a".to_vec()),
        (
            vec!["template", "a", "$9", "--max-matches=0"],
            b"a".to_vec(),
        ),
        (vec!["literal", "a", "b"], vec![0xff]),
        (vec!["literal", "a", "b", "--max-input=0"], b"a".to_vec()),
        (vec!["literal", "a", "bb", "--max-output=1"], b"a".to_vec()),
        (vec!["literal", "a", "b", "--max-calls=0"], b"a".to_vec()),
        (
            vec!["literal", "a", "b", "--max-work=9999999"],
            b"a".to_vec(),
        ),
        (
            vec!["literal", "a", "b", "--max-calls=2", "--max-work=19999999"],
            b"a".to_vec(),
        ),
        (vec!["literal", "a", "b", "--unknown"], vec![]),
        (
            vec!["literal", "a", "b", "--max-input=1", "--max-input=2"],
            vec![],
        ),
        (vec!["literal", "a", "b", "--max-calls=-1"], vec![]),
    ];
    let bad_count = bad.len();
    for (arguments, input) in bad {
        let (output, _) = program_run(&arguments, &input, None);
        assert_eq!(output.status.code(), Some(2), "{arguments:?}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.starts_with(b"regex-replace: stage="),
            "{arguments:?}: {output:?}"
        );
    }
    let (help, _) = program_run(&["--help"], b"", None);
    checked(&help, 0);
    assert!(
        help.stdout
            .starts_with(b"Usage: regex-replace literal|template")
    );
    eprintln!(
        "regex rewrite program: {good_count} exact binary cases, {bad_count} rejected cases and help"
    );
}

#[test]
fn regex_replace_program_all_reached_allocations_and_io_failures_clean_owners() {
    let arguments = ["template", "(a)(b)?", "[$1/$2/$0]$$"];
    let input = b"a\0ab";
    let (baseline, events) = program_run(&arguments, input, None);
    checked(&baseline, 0);
    assert_eq!(baseline.stdout, b"[a//a]$\0[a/b/ab]$");
    let points = events
        .lines()
        .filter(|line| line.starts_with("mmap("))
        .count();
    assert!(points >= 20 && points < 256);
    for index in 1..=points {
        let (output, events) = program_run(
            &arguments,
            input,
            Some(&format!("inject=mmap:error=ENOMEM:when={index}")),
        );
        assert_eq!(
            output.status.code(),
            Some(4),
            "allocation{index}: {output:?}"
        );
        assert!(
            output.stdout.is_empty() && output.stderr.starts_with(b"regex-replace: stage="),
            "allocation{index}: {output:?}"
        );
        assert_eq!(events.matches("INJECTED").count(), 1, "{events}");
    }
    for rule in [
        "inject=read:error=EINTR:when=1",
        "inject=write:error=EINTR:when=1",
    ] {
        let (output, _) = program_run(&arguments, input, Some(rule));
        checked(&output, 0);
        assert_eq!(output.stdout, baseline.stdout);
    }
    for rule in [
        "inject=read:error=EIO:when=1",
        "inject=write:error=EIO:when=1",
    ] {
        let (output, _) = program_run(&arguments, input, Some(rule));
        assert_eq!(output.status.code(), Some(3), "{rule}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.starts_with(b"regex-replace: stage="),
            "{rule}: {output:?}"
        );
    }
    eprintln!(
        "regex rewrite program: all {points} reached OOMs and single read/write EINTR/EIO schedules passed"
    );
}
