//! General lexer through canonical source regex and native execution.
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

#[derive(Clone, Debug)]
struct Rule {
    id: i32,
    pattern: Vec<u8>,
    skip: bool,
}
impl Rule {
    fn new(id: i32, pattern: &str, skip: bool) -> Self {
        Self {
            id,
            pattern: pattern.as_bytes().to_vec(),
            skip,
        }
    }
}
#[derive(Clone, Debug)]
struct Case {
    mode: u32,
    rules: Vec<Rule>,
    text: Vec<u8>,
    layout: u32,
    start: u32,
    input_cap: u32,
    steps: u32,
    tokens: u32,
    calls: u32,
    work: u64,
    per: u32,
    flags: u32,
    rule_cap: u32,
    pattern_cap: u32,
    state_cap: u32,
}
impl Case {
    fn new(rules: Vec<Rule>, text: &str) -> Self {
        Self {
            mode: 0,
            rules,
            text: text.as_bytes().to_vec(),
            layout: 0,
            start: 0,
            input_cap: 8192,
            steps: 128,
            tokens: 128,
            calls: 1024,
            work: 102_400_000,
            per: 100_000,
            flags: 0,
            rule_cap: 128,
            pattern_cap: 1_048_576,
            state_cap: 65_536,
        }
    }
    fn prefix(pattern: &str, text: &str) -> Self {
        let mut case = Self::new(vec![Rule::new(0, pattern, false)], text);
        case.mode = 1;
        case
    }
    fn encode(&self, output: &mut Vec<u8>) {
        let payload = self
            .rules
            .iter()
            .map(|rule| 12 + rule.pattern.len())
            .sum::<usize>()
            + self.text.len();
        for word in [
            self.mode,
            self.rules.len() as u32,
            self.text.len() as u32,
            self.layout,
            self.start,
            self.input_cap,
            self.steps,
            self.tokens,
            self.calls,
            self.work as u32,
            (self.work >> 32) as u32,
            self.per,
            self.flags,
            self.rule_cap,
            self.pattern_cap,
            self.state_cap,
            payload as u32,
        ] {
            output.extend_from_slice(&word.to_le_bytes());
        }
        for rule in &self.rules {
            output.extend_from_slice(&rule.id.to_le_bytes());
            output.extend_from_slice(&(rule.skip as u32).to_le_bytes());
            output.extend_from_slice(&(rule.pattern.len() as u32).to_le_bytes());
            output.extend_from_slice(&rule.pattern);
        }
        output.extend_from_slice(&self.text);
    }
}
fn protocol() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| executable("protocol.lani"))
}
fn payload(cases: &[Case]) -> common::TempArtifact {
    let file = common::TempArtifact::new("laniusc_lexer", "input", None);
    let mut bytes = Vec::new();
    for case in cases {
        case.encode(&mut bytes);
    }
    file.write_bytes(bytes);
    file
}
fn execute(cases: &[Case], reference: bool) -> Vec<String> {
    let input = payload(cases);
    let mut command = if reference {
        let mut command = Command::new("python3");
        command.arg(fixture("reference.py"));
        command
    } else {
        Command::new(protocol().path())
    };
    command.stdin(Stdio::from(std::fs::File::open(input.path()).unwrap()));
    let output = run(&mut command);
    checked(&output, 0);
    let lines: Vec<_> = String::from_utf8(output.stdout)
        .unwrap()
        .lines()
        .map(str::to_owned)
        .collect();
    assert_eq!(lines.len(), cases.len(), "{lines:?}");
    lines
}
fn compare_reference(cases: &[Case]) {
    let expected = execute(cases, true);
    let actual = execute(cases, false);
    for (index, ((case, expected), actual)) in cases.iter().zip(expected).zip(actual).enumerate() {
        assert_eq!(actual, expected, "case{index}: {case:?}");
    }
}

#[test]
fn longest_and_lexer_match_independent_full_context_endpoint_model() {
    let patterns = [
        "a|ab",
        "a+?",
        "a??",
        "(?:|a)*",
        "(a|aa)(a?)",
        r"\Aa",
        r"\ba",
        r"a\z",
        "[a-z]+",
        "[0-9]{1,3}?",
        "é|é🙂",
        "(?:é|🙂)+?",
    ];
    let texts = ["", "a", "abaa", "aa\0b", "é🙂é", "12a99", "ba", "🙂\na"];
    let mut cases = Vec::new();
    let mut starts_seen = [false; 3];
    let mut modes_seen = [false; 2];
    for (p, pattern) in patterns.iter().enumerate() {
        for (t, text) in texts.iter().enumerate() {
            for layout in 0..3 {
                let boundaries: Vec<_> = text
                    .char_indices()
                    .map(|(i, _)| i)
                    .chain(std::iter::once(text.len()))
                    .collect();
                let axis = (p + t) % 3;
                let start = match axis {
                    0 => 0,
                    1 => boundaries[boundaries.len() / 2],
                    _ => text.len(),
                };
                starts_seen[axis] = true;
                let mut case = Case::prefix(pattern, text);
                case.layout = layout;
                case.start = start as u32;
                let mode = (p + t + layout as usize) % 2;
                case.mode = if mode == 0 { 1 } else { 3 };
                modes_seen[mode] = true;
                cases.push(case);
            }
        }
    }
    let rule_sets = vec![
        vec![
            Rule::new(1, "if", false),
            Rule::new(2, "[a-z]+", false),
            Rule::new(3, " +", true),
            Rule::new(4, "=|==", false),
        ],
        vec![
            Rule::new(5, "a|ab", false),
            Rule::new(6, "b+?", false),
            Rule::new(7, ".", false),
        ],
        vec![
            Rule::new(8, "é|é🙂", false),
            Rule::new(8, "(?:é|🙂)+?", false),
            Rule::new(-9, "[a-z]+", false),
        ],
        vec![
            Rule::new(10, "", false),
            Rule::new(11, "a??", false),
            Rule::new(12, " +", true),
        ],
        vec![
            Rule::new(13, "[0-9]{1,3}?", false),
            Rule::new(14, "[0-9]+", false),
            Rule::new(15, "[a-z]+", false),
        ],
        vec![
            Rule::new(16, r"\Aa", false),
            Rule::new(17, r"\ba", false),
            Rule::new(18, ".", false),
        ],
        vec![Rule::new(19, "(?:|a)*", true), Rule::new(20, "b", false)],
        vec![
            Rule::new(21, "a", true),
            Rule::new(22, "a", false),
            Rule::new(23, "\0+", false),
        ],
    ];
    let lex_texts = [
        "",
        "if iff==x",
        "abbb?",
        "é🙂é",
        "a a!",
        "12a9999",
        "a\0\0a",
        "ba",
        "aa",
        "  ",
        "🙂\na",
        "?a",
    ];
    for (r, rules) in rule_sets.iter().enumerate() {
        for (t, text) in lex_texts.iter().enumerate() {
            for layout in 0..3 {
                let mut case = Case::new(rules.clone(), text);
                case.layout = layout;
                let axis = (r + t) % 5;
                match axis {
                    0 => case.tokens = 0,
                    1 => case.steps = 1,
                    2 => case.calls = rules.len() as u32,
                    3 => case.work = (rules.len() as u64 * 100_000).saturating_sub(1),
                    _ => {}
                }
                cases.push(case);
            }
        }
    }
    assert!(starts_seen.into_iter().all(|v| v) && modes_seen.into_iter().all(|v| v));
    assert_eq!(cases.len(), 576);
    compare_reference(&cases);
    eprintln!(
        "lexer independent full-context model: 288 anchored-prefix +288 scan cases across three storage layouts"
    );
}

#[test]
fn lexer_explicit_assertion_nullable_capture_validation_and_limit_tables() {
    let mut examples: Vec<(Case, String)> = Vec::new();
    for (pattern, text, start, expected) in [
        ("a|ab", "ab", 0, "P0:2"),
        ("a+?", "aaa", 0, "P0:3"),
        ("a??", "a", 0, "P0:1"),
        ("(?:|a)*", "aa", 0, "P0:2"),
        ("(a|aa)(a?)", "aa", 0, "P0:2/0:1/1:2"),
        ("(a?)*", "aa", 0, "P0:2/1:2"),
        (r"\Aa", "ba", 1, "N"),
        (r"\ba", "ba", 1, "N"),
        ("a$", "a\n", 0, "N"),
        ("a$", "ba", 1, "P1:2"),
        (r"a\z", "ba", 1, "P1:2"),
        (r"\B", "aa", 1, "P1:1"),
        (r"\b", "é", 0, "N"),
        (r"\B", "é", 0, "P0:0"),
        ("\0+", "\0\0", 0, "P0:2"),
        (".", "é🙂", 1, "E9:-1:0:5"),
    ] {
        for layout in 0..3 {
            let mut case = Case::prefix(pattern, text);
            case.start = start;
            case.layout = layout;
            examples.push((case, expected.into()));
        }
    }
    let mut multiline = Case::prefix("^a$", "x\na\nz");
    multiline.start = 2;
    multiline.flags = 1;
    examples.push((multiline, "P2:3".into()));
    let mut case = Case::prefix("a|ab", "ab");
    case.mode = 2;
    examples.push((case, "P0:1".into()));
    let mut case = Case::prefix("a??", "a");
    case.mode = 2;
    examples.push((case, "P0:0".into()));
    let rules = vec![Rule::new(0, "a", false), Rule::new(1, "b", false)];
    let mut case = Case::new(rules.clone(), "a");
    case.rule_cap = 0;
    examples.push((case, "E3:-1:0:0".into()));
    let mut case = Case::new(Vec::new(), "");
    case.rule_cap = 0;
    examples.push((case, "E3:-1:0:0".into()));
    let mut case = Case::new(rules.clone(), "a");
    case.pattern_cap = 1;
    examples.push((case, "E4:1:0:0".into()));
    let mut case = Case::new(rules.clone(), "a");
    case.state_cap = 0;
    examples.push((case, "E5:0:0:0".into()));
    let mut case = Case::new(rules.clone(), "a");
    case.state_cap = u32::MAX;
    examples.push((case, "E2:-1:0:0".into()));
    let mut case = Case::new(rules.clone(), "a");
    case.text = vec![255];
    case.input_cap = 0;
    examples.push((case.clone(), "E6:-1:0:0".into()));
    case.input_cap = 1;
    examples.push((case, "E9:-1:0:6".into()));
    let mut case = Case::new(rules.clone(), "a");
    case.calls = u32::MAX;
    case.text = vec![255];
    examples.push((case, "E2:-1:0:0".into()));
    let mut case = Case::new(rules.clone(), "a");
    case.rules[1].pattern = vec![195];
    examples.push((case, "E8:1:0:6".into()));
    let mut case = Case::new(rules.clone(), "a");
    case.rules[1].pattern = b"(".to_vec();
    // Canonical atom() reports an unclosed group's opening byte, not EOF.
    examples.push((case, "E8:1:0:1".into()));
    let mut case = Case::new(rules.clone(), "a");
    case.per = 1;
    examples.push((case, "LE10:0:0:7;0,0,1,1,0".into()));
    let mut case = Case::new(
        vec![Rule::new(0, "a", false), Rule::new(1, "a|a|a|a|a|a", false)],
        "a",
    );
    case.per = 8;
    examples.push((case, "LE10:1:0:7;0,0,2,16,0".into()));
    let cases: Vec<_> = examples.iter().map(|(case, _)| case.clone()).collect();
    let actual = execute(&cases, false);
    for (index, ((case, expected), actual)) in examples.iter().zip(actual).enumerate() {
        assert_eq!(&actual, expected, "table{index}: {case:?}");
    }
    eprintln!(
        "lexer explicit assertions/captures/admission/error-order tables: {} cases",
        examples.len()
    );
}

#[test]
fn lexer_build_and_input_admission_validate_bounds_exact_caps_and_cleanup() {
    let file = executable("admission.lani");
    let trace = common::TempArtifact::new("laniusc_lexer", "admission_trace", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"])
        .arg(file.path()));
    checked(&output, 0);
    assert!(output.stdout.is_empty(), "{output:?}");
    assert!(ledger(&std::fs::read_to_string(trace.path()).unwrap()) > 0);
}

#[test]
fn every_reached_lexer_allocation_failure_preserves_sources_and_releases_exact_owners() {
    let file = executable("allocations.lani");
    let trace = common::TempArtifact::new("laniusc_lexer", "allocation_trace", None);
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
        (output, std::fs::read_to_string(trace.path()).unwrap())
    };
    let (output, events) = execute(None);
    checked(&output, 0);
    assert_eq!(output.stdout, b"0\n");
    let points = ledger(&events);
    assert!(
        (64..256).contains(&points),
        "unexpected allocation scope: {points}: {events}"
    );
    let mut stages = [0usize; 6];
    let mut later_candidate = [false; 2];
    for index in 1..=points {
        let (output, events) = execute(Some(index));
        checked(&output, 4);
        let parts: Vec<usize> = std::str::from_utf8(&output.stdout)
            .unwrap()
            .trim()
            .split(':')
            .map(|part| part.parse().unwrap())
            .collect();
        assert!((1..=5).contains(&parts[0]), "allocation{index}: {output:?}");
        stages[parts[0]] += 1;
        if parts[0] >= 4 {
            assert_eq!(parts.len(), 3);
            assert!(parts[1] < 2 && parts[2] <= 2);
            if parts[1] == 1 && parts[2] == 0 {
                later_candidate[parts[0] - 4] = true;
            }
        } else {
            assert_eq!(parts.len(), 1);
        }
        ledger(&events);
        assert_eq!(
            events.matches("INJECTED").count(),
            1,
            "allocation{index}: {events}"
        );
    }
    assert!(stages[1..].iter().all(|count| *count > 0), "{stages:?}");
    assert!(
        later_candidate.into_iter().all(|v| v),
        "missing later-rule OOM after winning candidate"
    );
    eprintln!(
        "lexer all {points} reached OOM positions passed; input/pattern/build/scan/probe stages={:?}",
        &stages[1..]
    );
}
fn fixture(name: &str) -> PathBuf {
    root().join("tests/fixtures/extended/lexer").join(name)
}
fn executable(name: &str) -> common::TempArtifact {
    let entry = fixture(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("lexer", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("lexer {name}: {error}"));
    let file = common::TempArtifact::new("laniusc_lexer", name, None);
    file.write_bytes(bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn run(command: &mut Command) -> Output {
    common::process_output_with_timeout("lexer execution", command, Duration::from_secs(20))
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
fn longest_prefix_and_lexer_contracts_preserve_context_priority_progress_and_budgets() {
    let file = executable("contracts.lani");
    let trace = common::TempArtifact::new("laniusc_lexer", "contracts_trace", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,munmap"])
        .arg(file.path()));
    checked(&output, 0);
    assert!(output.stdout.is_empty(), "{output:?}");
    assert!(ledger(&std::fs::read_to_string(trace.path()).unwrap()) > 0);
}
