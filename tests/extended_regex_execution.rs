mod common;

use std::path::PathBuf;

use laniusc_compiler::compiler::{EntrySourceRoots, compile_entry_to_x86_64_with_source_roots};

#[derive(Clone, Debug)]
struct Case {
    pattern: Vec<u8>,
    text: Vec<u8>,
    flags: u32,
    states: u32,
    captures: u32,
    work: u32,
    depth: u32,
    repeat: u32,
    pattern_limit: u32,
}
impl Case {
    fn new(pattern: &str, text: &str) -> Self {
        Self {
            pattern: pattern.as_bytes().to_vec(),
            text: text.as_bytes().to_vec(),
            flags: 0,
            states: 4096,
            captures: 16,
            work: 10_000_000,
            depth: 64,
            repeat: 1000,
            pattern_limit: 65536,
        }
    }
    fn encode(&self, bytes: &mut Vec<u8>) {
        for word in [
            self.pattern.len() as u32,
            self.text.len() as u32,
            self.flags,
            self.states,
            self.captures,
            self.work,
            self.depth,
            self.repeat,
            self.pattern_limit,
        ] {
            bytes.extend_from_slice(&word.to_le_bytes());
        }
        bytes.extend_from_slice(&self.pattern);
        bytes.extend_from_slice(&self.text);
    }
}
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn executable(name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/extended_library/{name}.lani"));
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_regex", name, None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn payload(cases: &[Case]) -> common::TempArtifact {
    let input = common::TempArtifact::new("laniusc_regex", "input", None);
    let mut bytes = Vec::new();
    for case in cases {
        case.encode(&mut bytes);
    }
    input.write_bytes(&bytes);
    input
}
fn run(exe: &common::TempArtifact, input: &common::TempArtifact) -> String {
    let output = common::short_process_output_with_timeout(
        "regex cases",
        std::process::Command::new(exe.path()).stdin(std::process::Stdio::from(
            std::fs::File::open(input.path()).unwrap(),
        )),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    String::from_utf8(output.stdout).unwrap()
}
const PYTHON_REFERENCE: &str = r#"
import sys,struct,re
b=sys.stdin.buffer.read(); at=0
while at<len(b):
 p,t,f,states,groups,work,depth,repeat,limit=struct.unpack_from('<9I',b,at);at+=36
 pattern=b[at:at+p].decode();at+=p
 text=b[at:at+t].decode();at+=t
 # Shared subset uses ASCII shorthands and strict end-of-text; dollar cases
 # ending in LF are checked separately because Python's dollar differs.
 pattern=re.sub(r'\\x\{([0-9a-fA-F]+)\}',lambda m:chr(int(m[1],16)),pattern)
 q=re.compile(pattern,re.ASCII|(re.MULTILINE if f&1 else 0)|(re.DOTALL if f&2 else 0))
 position=0;out=''
 while position<=len(text):
  m=q.search(text,position)
  if m is None:break
  spans=[]
  for group in range(q.groups+1):
   s,e=m.span(group)
   spans.append('-' if s<0 else str(len(text[:s].encode()))+','+str(len(text[:e].encode())))
  out+='M'+'/'.join(spans)+';'
  position=m.end()+(m.start()==m.end())
 print(out or 'N')
"#;
#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn regex_native_views_borrowed_owners_capture_lifetimes_bounds_and_fused_iteration() {
    let exe = executable("regex_contracts");
    let output = common::short_process_output_with_timeout(
        "regex ownership and views",
        &mut std::process::Command::new(exe.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}
#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn regex_matches_independent_python_reference_and_documents_unicode_and_limits() {
    let exe = executable("regex_input");
    let patterns = [
        "",
        "a",
        "ab",
        "a|ab",
        "ab|a",
        "a*",
        "a*?",
        "a+",
        "a+?",
        "a??",
        "a?b",
        "(a+)(b+?)",
        "(a|ab)*b",
        "(ab|a)*?b",
        "(?:a|b)+",
        "(a)?b",
        "(a(b)?)+",
        "a{0}",
        "(ab){2,3}",
        "(a|b){1,3}?",
        "a{2,}",
        "[a-z\\d]+",
        "[^a-c]+",
        "[a-]+",
        "[-a]+",
        "[\\D]+",
        "[a-z\\W]+",
        "\\b[a-z]+\\b",
        "\\A(a|b)+",
        "(a|b)+$",
        ".+?",
        "(.)(.)?",
        "é+",
        "[é-ê]+",
        "[😀-🙏]+",
        "(é|🙂)+",
        "\\x{1f642}+",
        "\\x00",
        "\\n",
        "\\t",
        "\\v",
        "\\a",
        "\\f",
        "\\r",
        "\\.\\+\\?",
        "|a",
    ];
    let texts = [
        "",
        "a",
        "ab",
        "abaabb",
        "aaabbb",
        "!a b_9",
        "zzz",
        "ééêx",
        "x🙂🙏!",
        "a\nb",
        "é🙂",
        "\0",
        "\t\r\u{b}\u{c}\u{7}",
        ".+?",
    ];
    let mut cases = Vec::new();
    for pattern in patterns {
        for text in texts {
            cases.push(Case::new(pattern, text));
        }
    }
    // Deterministic grammar-generated patterns cover compositions rather than
    // treating hand-selected examples as the full state space.
    let atoms = ["a", "b", "[ab]", "[^a]", ".", "é", "(?:ab|b)"];
    let repeats = ["", "?", "*", "+", "??", "*?", "{0,2}", "{1,3}?", "{2,}"];
    let mut seed = 0x4172_9a11u32;
    for _ in 0..400 {
        let mut next = || {
            seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
            seed as usize
        };
        let a = atoms[next() % atoms.len()];
        let ar = repeats[next() % repeats.len()];
        let b = atoms[next() % atoms.len()];
        let br = repeats[next() % repeats.len()];
        let pattern = if next() % 2 == 0 {
            format!("({a}{ar})({b}{br})")
        } else {
            format!("({a}{ar}|{b}{br})c?")
        };
        let text = texts[next() % texts.len()];
        cases.push(Case::new(&pattern, text));
    }
    for flags in [1, 2, 3] {
        for pattern in ["^a", "b$", ".*", "(.+)"] {
            let mut case = Case::new(pattern, "a\nb\nc");
            case.flags = flags;
            cases.push(case);
        }
    }
    let input = payload(&cases);
    let reference = common::short_process_output_with_timeout(
        "independent Python re oracle",
        std::process::Command::new("python3")
            .args(["-c", PYTHON_REFERENCE])
            .stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).unwrap(),
            )),
    );
    assert!(reference.status.success(), "{reference:?}");
    let expected = String::from_utf8(reference.stdout).unwrap();
    let actual = run(&exe, &input);
    let actual_lines: Vec<_> = actual.lines().collect();
    let expected_lines: Vec<_> = expected.lines().collect();
    assert_eq!(actual_lines.len(), cases.len());
    assert_eq!(expected_lines.len(), cases.len());
    for (index, case) in cases.iter().enumerate() {
        assert_eq!(
            actual_lines[index], expected_lines[index],
            "case {index}: {case:?}"
        );
    }
    let mut special: Vec<(Case, String)> = Vec::new();
    for (pattern, text, expected) in [
        (r"\p{Alphabetic}+", "!Σé中!", "M1,8;"),
        (r"\p{White_Space}+", "x\u{85}\u{2003}\t", "M1,7;"),
        (r"\p{XID_Start}\p{XID_Continue}*", "1α\u{301}_9!", "M1,7;"),
        (r"[\p{Lu}\p{Nd}]+", "aΣ９!", "M1,6;"),
        (r"\P{L}+", "é9🙂", "M2,7;"),
        (r"[^\P{Alphabetic}]+", "1é中!", "M1,6;"),
        (r"\pL+", "中α1", "M0,5;"),
        ("$", "a\n", "M2,2;"),
        (r"\z", "a\n", "M2,2;"),
        (r"\b", "é", "N"),
        (r"\B", "", "M0,0;"),
        ("(?:|a)*", "a", "M0,0;M1,1;"),
        ("(?:|a)+", "a", "M0,0;M1,1;"),
        ("(?:a?|b)*", "ab", "M0,2;M2,2;"),
        ("(a*)*", "aa", "M0,2/0,2;M2,2/2,2;"),
        ("(?:a?)*b", "aaab", "M0,4;"),
        ("|a", "a", "M0,0;M1,1;"),
        (r"[\x{0}-\x{10ffff}]+", "\0é🙂\u{10ffff}", "M0,11;"),
    ] {
        special.push((Case::new(pattern, text), expected.to_owned()));
    }
    // Every supported general-category identifier selects its stable scalar.
    for (category, scalar) in [
        ("Cn", '\u{378}'),
        ("Lu", 'A'),
        ("Ll", 'a'),
        ("Lt", 'ǅ'),
        ("Lm", 'ʰ'),
        ("Lo", '中'),
        ("Mn", '\u{301}'),
        ("Mc", 'ा'),
        ("Me", '\u{20e3}'),
        ("Nd", '९'),
        ("Nl", 'Ⅻ'),
        ("No", '²'),
        ("Pc", '_'),
        ("Pd", '-'),
        ("Ps", '('),
        ("Pe", ')'),
        ("Pi", '«'),
        ("Pf", '»'),
        ("Po", '!'),
        ("Sm", '+'),
        ("Sc", '$'),
        ("Sk", '^'),
        ("So", '🙂'),
        ("Zs", '\u{a0}'),
        ("Zl", '\u{2028}'),
        ("Zp", '\u{2029}'),
        ("Cc", '\0'),
        ("Cf", '\u{200d}'),
        ("Co", '\u{e000}'),
    ] {
        let text = scalar.to_string();
        special.push((
            Case::new(&format!("\\p{{{category}}}"), &text),
            format!("M0,{};", text.len()),
        ));
        special.push((Case::new(&format!("\\P{{{category}}}"), &text), "N".into()));
    }
    special.push((Case::new(r"\p{Cs}", "a🙂"), "N".into()));
    for (pattern, kind) in [
        ("(", 1),
        ("[", 1),
        ("[]", 1),
        ("[z-a]", 1),
        ("a{2,1}", 1),
        ("a**", 1),
        ("a{", 1),
        ("\\", 1),
        (r"\x{}", 1),
        (r"\x{d800}", 1),
        (r"\x{110000}", 1),
        (r"\xGG", 1),
        ("a)", 1),
        (r"(a)\1", 2),
        ("(?=a)", 2),
        ("(?<=a)", 2),
        ("(?!a)", 2),
        ("(?P<x>a)", 2),
        ("(?i)a", 2),
        ("a++", 2),
        (r"\k<x>", 2),
        (r"\Qx\E", 2),
        (r"\p{Greek}", 2),
        ("[[:alpha:]]", 2),
        (r"\C", 2),
        (r"\Z", 2),
    ] {
        special.push((Case::new(pattern, "a"), format!("E{kind}:")));
    }
    let mut bad_pattern = Case::new("a", "");
    bad_pattern.pattern = vec![0xff];
    special.push((bad_pattern, "E6:0".into()));
    let mut bad_input = Case::new("a", "");
    bad_input.text = vec![b'a', 0xc3];
    special.push((bad_input, "E6:1".into()));
    let mut state = Case::new("(a{1000}){1000}", "a");
    state.states = 100;
    special.push((state, "E3:".into()));
    let mut depth = Case::new("((((a))))", "a");
    depth.depth = 3;
    special.push((depth, "E3:".into()));
    let mut groups = Case::new("(a)", "a");
    groups.captures = 0;
    special.push((groups, "E3:".into()));
    let mut repeats = Case::new("a{11}", "a");
    repeats.repeat = 10;
    special.push((repeats, "E3:".into()));
    let mut length = Case::new("ab", "a");
    length.pattern_limit = 1;
    special.push((length, "E3:".into()));
    let mut work = Case::new("a", "a");
    work.work = 1;
    special.push((work, "E7:0".into()));
    for invalid in 0..7 {
        let mut case = Case::new("a", "a");
        match invalid {
            0 => case.states = 3,
            1 => case.states = 65537,
            2 => case.captures = 129,
            3 => case.work = 0,
            4 => case.depth = 0,
            5 => case.depth = 257,
            _ => case.repeat = 1000001,
        }
        special.push((case, "E3:0".into()));
    }
    let mut minimum = Case::new("a", "a");
    minimum.states = 4;
    minimum.captures = 0;
    special.push((minimum, "M0,1;".into()));
    let mut empty_limit = Case::new("", "");
    empty_limit.pattern_limit = 0;
    special.push((empty_limit, "M0,0;".into()));
    let mut zero_repeat = Case::new("a{0}", "");
    zero_repeat.repeat = 0;
    special.push((zero_repeat, "M0,0;".into()));
    let nested = format!("{}a{}", "(?:".repeat(64), ")".repeat(64));
    special.push((Case::new(&nested, "a"), "M0,1;".into()));
    let too_nested = format!("{}a{}", "(?:".repeat(65), ")".repeat(65));
    special.push((Case::new(&too_nested, "a"), "E3:".into()));
    // Empty expansions must hit a compile bound despite producing few states.
    special.push((Case::new("(?:(?:){1000}){1000}", ""), "E3:".into()));
    // Nested repeats remain linear and cannot trigger exponential backtracking.
    special.push((Case::new("(a+)+b", &"a".repeat(16000)), "N".into()));
    special.push((Case::new("(a|aa)*b", &"a".repeat(16000)), "N".into()));
    let input = payload(&special.iter().map(|(c, _)| c.clone()).collect::<Vec<_>>());
    let actual = run(&exe, &input);
    assert_eq!(
        actual.lines().count(),
        special.len(),
        "missing regex response"
    );
    for ((case, expected), actual) in special.iter().zip(actual.lines()) {
        if expected.ends_with(':') {
            assert!(
                actual.starts_with(expected),
                "{case:?}: {actual} expected {expected}"
            );
        } else {
            assert_eq!(actual, expected, "{case:?}");
        }
    }
    // Every successful mmap has a corresponding release on ordinary and all
    // injected allocation-failure paths, including partially built scratch.
    let input = payload(&[Case::new("(a|[b-c]){1,3}", "")]);
    let baseline_trace = common::TempArtifact::new("laniusc_regex", "allocation_baseline", None);
    let baseline = common::short_process_output_with_timeout(
        "observe regex allocation points",
        std::process::Command::new("strace")
            .args(["-qq", "-o"])
            .arg(baseline_trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(exe.path())
            .stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).unwrap(),
            )),
    );
    assert_eq!(baseline.status.code(), Some(0), "{baseline:?}");
    assert_eq!(baseline.stdout, b"N\n");
    let baseline_events = std::fs::read_to_string(baseline_trace.path()).unwrap();
    let points = baseline_events
        .lines()
        .filter(|l| l.starts_with("mmap("))
        .count();
    assert!(
        points >= 9,
        "scratch allocation paths were not observed: {baseline_events}"
    );
    assert_eq!(
        points,
        baseline_events
            .lines()
            .filter(|l| l.starts_with("munmap("))
            .count(),
        "{baseline_events}"
    );
    for failure in 1..=points {
        let trace = common::TempArtifact::new("laniusc_regex", "allocations", None);
        let output = common::short_process_output_with_timeout(
            "regex allocation failure cleanup",
            std::process::Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap", "-e"])
                .arg(format!("inject=mmap:error=ENOMEM:when={failure}"))
                .arg(exe.path())
                .stdin(std::process::Stdio::from(
                    std::fs::File::open(input.path()).unwrap(),
                )),
        );
        assert_eq!(
            output.status.code(),
            Some(0),
            "allocation {failure}: {output:?}"
        );
        let response = String::from_utf8(output.stdout).unwrap();
        assert_eq!(response, "E4:0\n", "allocation {failure}: {response:?}");
        let events = std::fs::read_to_string(trace.path()).unwrap();
        let allocated = events
            .lines()
            .filter(|l| l.starts_with("mmap(") && !l.contains("ENOMEM"))
            .count();
        let released = events.lines().filter(|l| l.starts_with("munmap(")).count();
        assert_eq!(allocated, released, "allocation {failure} leaked: {events}");
    }
}
