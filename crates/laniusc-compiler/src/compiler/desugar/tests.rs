//! Tests of the desugaring in the token stream.

use std::{
    path::PathBuf,
    sync::{Mutex, PoisonError},
};

use super::*;
use crate::lexer::driver::GpuLexer;

/// Whether the machine rules accept `source`, and its machines are
/// desugared.
pub(crate) fn accepts(source: &str) -> bool {
    let _one = one_at_a_time();
    desugar_pack(&[source]).is_ok_and(|desugared| !desugared.region.is_empty())
}

/// The lexer of these tests. The compiler owns its lexer, and reads the
/// last run after the lexer is free; the process-global lexer serves the
/// text rewrites of other tests, which would overwrite its tokens.
fn test_lexer() -> &'static GpuLexer {
    static LEXER: std::sync::OnceLock<GpuLexer> = std::sync::OnceLock::new();
    LEXER.get_or_init(|| {
        pollster::block_on(GpuLexer::new_with_device(crate::gpu::device::global()))
            .expect("lexer")
    })
}

/// The token stream of a pack after the desugaring: per token its kind,
/// text and file, and the generated text of the region.
pub(super) struct Desugared {
    tokens: Vec<(u32, String, u32)>,
    pub(super) region: String,
    region_base: usize,
}

/// Lexes `sources` with the desugaring, running the pack again while the
/// floors grow. `Err` holds the verdict of a broken rule:
/// `` `text`: message [help] ``.
pub(super) fn desugar_pack(sources: &[&str]) -> Result<Desugared, String> {
    let pack: String = sources.concat();
    desugar_or_reject(sources).map_err(|rule| {
        format!(
            "`{}`: {}{}",
            source_text(&pack, rule.start, rule.len),
            rule.message,
            rule.help.map_or(String::new(), |help| format!(" [{help}]"))
        )
    })
}

/// The tests read the last run after the lexer is free, and every test lex
/// overwrites the lexer's tokens, so one test lexes at a time.
static TEST_RUNS: Mutex<()> = Mutex::new(());

pub(super) fn one_at_a_time() -> std::sync::MutexGuard<'static, ()> {
    TEST_RUNS.lock().unwrap_or_else(PoisonError::into_inner)
}

fn desugar_or_reject(sources: &[&str]) -> Result<Desugared, RuleError> {
    let lexer = test_lexer();
    let pack: String = sources.concat();
    let text = |start: usize, len: usize| source_text(&pack, start, len);
    for _ in 0..8 {
        let (raw, count, words, file_ids, bytes, region) = pollster::block_on(
            lexer.with_resident_source_pack_tokens(sources, |device, queue, bufs| {
                let _ = (device, queue);
                let token_bytes = bufs
                    .tokens_out
                    .clone()
                    .reinterpret::<u8>(bufs.tokens_out.byte_size);
                let file_bytes = bufs
                    .token_file_id
                    .clone()
                    .reinterpret::<u8>(bufs.token_file_id.byte_size);
                let count_bytes = bufs
                    .token_count
                    .clone()
                    .reinterpret::<u8>(bufs.token_count.byte_size);
                let flag_bytes = bufs
                    .parser_feature_flags
                    .clone()
                    .reinterpret::<u8>(bufs.parser_feature_flags.byte_size);
                let last = LAST_RUN
                    .with(|last| last.borrow().clone())
                    .filter(|last| last.sizes.is_some());
                let mut reads = vec![
                    (&count_bytes, 0, 1),
                    (&flag_bytes, 0, 1),
                    (&token_bytes, 0, bufs.tokens_out.count * 3),
                    (&file_bytes, 0, bufs.token_file_id.count),
                    (&bufs.in_bytes, 0, bufs.in_bytes.byte_size / 4),
                ];
                if let Some(sizes) = last.as_ref().and_then(|last| last.sizes.as_ref()) {
                    reads.push((sizes, 0, ROUNDS * SIZE_WORDS));
                }
                let mut words = read_words(&lexer.desugaring().gpu(), &reads, None).expect("read the tokens");
                // The region of every round, from the first.
                let region = last.map(|last| {
                    let sizes = words.get(5).map(Vec::as_slice).unwrap_or(&[]);
                    let filled = sizes
                        .chunks(SIZE_WORDS)
                        .map(|row| (row[S_ANCHOR_BASE] + row[S_REGION]) as usize)
                        .max()
                        .unwrap_or(0);
                    (last.first_base as usize, filled)
                });
                let bytes: Vec<u8> = words[4]
                    .iter()
                    .flat_map(|word| word.to_le_bytes())
                    .collect();
                let files = std::mem::take(&mut words[3]);
                let tokens = std::mem::take(&mut words[2]);
                (words[1][0], words[0][0], tokens, files, bytes, region)
            }),
        )
        .expect("lex");
        match stop(raw, count, pack.len(), text) {
            Some(Stop::Retry) => continue,
            Some(Stop::Rejected(rule)) => return Err(rule),
            None => {}
        }
        let tokens = (0..count as usize)
            .map(|token| {
                let (kind, start, len) = (
                    words[token * 3],
                    words[token * 3 + 1] as usize,
                    words[token * 3 + 2] as usize,
                );
                (
                    kind,
                    String::from_utf8_lossy(&bytes[start..start + len]).into_owned(),
                    file_ids[token],
                )
            })
            .collect();
        let region_base = region.map_or(0, |(base, _)| base);
        let region = region
            .filter(|_| ROUND_FEATURES.iter().any(|&feature| raw & feature != 0))
            .map(|(base, len)| String::from_utf8_lossy(&bytes[base..base + len]).into_owned())
            .unwrap_or_default();
        return Ok(Desugared {
            tokens,
            region,
            region_base,
        });
    }
    panic!("the pack did not fit after eight runs");
}

fn region_text(source: &str) -> String {
    desugar_pack(&[source])
        .unwrap_or_else(|verdict| panic!("{verdict}"))
        .region
}

/// The tokens of `sources` lexed as they are.
fn lexed(sources: &[&str]) -> Vec<(u32, String, u32)> {
    let pack: String = sources.concat();
    let mut file_starts = Vec::new();
    let mut next = 0;
    for source in sources {
        file_starts.push(next);
        next += source.len();
    }
    let tokens =
        without_desugaring(|| pollster::block_on(test_lexer().lex_source_pack(sources)))
            .expect("lex");
    tokens
        .into_iter()
        .map(|token| {
            let file = file_starts.partition_point(|&start| start <= token.start) - 1;
            (
                token.kind as u32,
                pack[token.start..token.start + token.len].to_string(),
                file as u32,
            )
        })
        .collect()
}

fn lani_files(dir: &std::path::Path, files: &mut Vec<std::path::PathBuf>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            lani_files(&path, files);
        } else if path
            .extension()
            .is_some_and(|extension| extension == "lani")
        {
            files.push(path);
        }
    }
}

const DOOR: &str = "enum Input { Open, Close }
pub machine Door on Input -> Reply {
    opens: i32,
    start Closed;
    state Opened {
        Input::Close -> goto Closed with Reply::Done,
        Input::Open -> stay with Reply::Ignored,
    }
    state Closed {
        Input::Open -> { self.opens += 1; goto Opened with Reply::Done; },
        Input::Close -> stay with Reply::Ignored,
    }
}
";

/// A diagnostic at a byte of generated text labels the source byte it
/// came from: the copied text itself, or for inserted text the token
/// the expansion reads.
#[test]
fn generated_bytes_map_back_to_the_machine() {
    let _one = one_at_a_time();
    let desugared = desugar_pack(&[DOOR]).unwrap_or_else(|verdict| panic!("{verdict}"));
    let at = |text: &str| {
        desugared.region_base
            + desugared
                .region
                .find(text)
                .unwrap_or_else(|| panic!("{text}"))
    };
    let copied = source_position(at("Reply::Done")).expect("a region byte");
    assert_eq!(&DOOR[copied..copied + 11], "Reply::Done");
    let generated = source_position(at("= DoorState::Closed")).expect("a region byte");
    assert_eq!(&DOOR[generated..generated + 4], "goto");
    // The end of the source is not a region byte.
    assert_eq!(source_position(DOOR.len()), None);
}

/// A broken rule labels the line of the machine in its file.
#[test]
fn a_rejected_machine_names_its_file_and_line() {
    let _one = one_at_a_time();
    let source = DOOR.replace("goto Closed with", "goto Shut with");
    let rule = desugar_or_reject(&[&source])
        .err()
        .expect("the machine names a state it does not have");
    let text = format!(
        "{:?}",
        rejected_in_source(Path::new("door.lani"), &source, rule)
    );
    assert!(
        text.contains("no state is named `Shut`") && text.contains("line: 6"),
        "{text}"
    );

    let plain = "fn plain(a: i32, b: i32) -> i32 {\n    return a | b;\n}\n";
    let outside = "fn f() -> i32 {\n    goto Next;\n    return 0;\n}\n";
    let rule = desugar_or_reject(&[plain, outside])
        .err()
        .expect("a transition outside a machine");
    let paths = [
        Some(PathBuf::from("plain.lani")),
        Some(PathBuf::from("second.lani")),
    ];
    let files = crate::compiler::diagnostics::source_pack_diagnostic_files(
        &[plain, outside],
        Some(&paths),
    );
    let text = format!("{:?}", rejected_in_source_pack(&files, rule));
    assert!(
        text.contains("transitions of a machine")
            && text.contains("second.lani")
            && text.contains("line: 2"),
        "{text}"
    );
}

/// The token table of the constant strings is the GPU lexer's.
#[test]
fn the_constant_token_table_matches_the_lexer() {
    let _one = one_at_a_time();
    let lexer = test_lexer();
    for &text in machines::constant_strings() {
        let tokens =
            without_desugaring(|| pollster::block_on(lexer.lex(text))).expect("lex a constant");
        let mut expected = vec![0u32; text.len()];
        for token in tokens {
            expected[token.start] = 1 | 2 | ((token.kind as u32) << 8);
            for byte in &mut expected[token.start + 1..token.start + token.len] {
                *byte = 1 | ((token.kind as u32) << 8);
            }
        }
        assert_eq!(token_info(text, |_| None), expected, "{text:?}");
    }
}

#[test]
fn a_machine_expands_to_an_enum_a_struct_a_constructor_and_an_impl() {
    let _one = one_at_a_time();
    let text = region_text(DOOR);
    assert!(text.contains("pub enum DoorState { Opened, Closed }\npub struct Door { opens: i32, __lanius_state: DoorState }\n"), "{text}");
    assert!(text.contains("pub fn door_start(opens: i32) -> Door { return Door { opens: opens, __lanius_state: DoorState::Closed }; }"), "{text}");
    assert!(
        text.contains(
            "DoorState::Opened -> { return self.__lanius_in_Opened(__lanius_event); },"
        ),
        "{text}"
    );
    assert!(
        text.contains(
            "Input::Close -> { self.__lanius_state = DoorState::Closed; return Reply::Done; },"
        ),
        "{text}"
    );
    assert!(
        text.contains("Input::Open -> { return Reply::Ignored; },"),
        "{text}"
    );
    assert!(text.contains("Input::Open -> {self.opens += 1;self.__lanius_state = DoorState::Opened; return Reply::Done;},"), "{text}");
    assert!(
        text.contains("return match (self.__lanius_state) {"),
        "{text}"
    );
}

#[test]
fn run_has_one_loop_per_state() {
    let _one = one_at_a_time();
    let text = region_text(
        "enum Op { Push(i32), Drop }
machine Pair on Op {
    start Empty;
    state Empty {
        Op::Push(x) -> goto Holding(x, 0),
        Op::Drop -> stay,
    }
    state Holding(first: i32, second: i32) {
        Op::Push(x) -> goto Holding(x, first),
        Op::Drop -> goto Empty,
    }
}
",
    );
    assert!(
        text.contains("fn run(&mut self, __lanius_events: [Op], __lanius_count: i32) {"),
        "{text}"
    );
    assert!(text.contains("PairState::Holding(first, second) -> self.__lanius_run_Holding(first, second, __lanius_events, __lanius_at, __lanius_count),"), "{text}");
    // A transition to the same state continues its loop, reading the
    // old data before assigning the new.
    assert!(text.contains("Op::Push(x) -> { let __lanius_next_0: i32 = x; let __lanius_next_1: i32 = first; first = __lanius_next_0; second = __lanius_next_1; continue; },"), "{text}");
    assert!(text.contains("Op::Drop -> { continue; },"), "{text}");
    // One to another state stores it and returns the position.
    assert!(
        text.contains(
            "Op::Drop -> { self.__lanius_state = PairState::Empty; return __lanius_at; },"
        ),
        "{text}"
    );
    assert!(text.contains("self.__lanius_state = PairState::Holding(first, second);\n        return __lanius_at;"), "{text}");
}

#[test]
fn integer_events_may_end_with_a_binding_arm() {
    let _one = one_at_a_time();
    let text = region_text(
        "machine Sum on u8 {
    total: i64,
    start Between;
    state Between {
        c -> { if (c == 48) { goto Zero; } stay; },
    }
    final state Zero {
        _ -> stay,
    }
}
",
    );
    assert!(
        text.contains("fn step(&mut self, __lanius_event: u8) {"),
        "{text}"
    );
    assert!(text.contains("_ -> { return; },"), "{text}");
    assert!(text.contains("_ -> { let c: u8 = __lanius_event;if (c == 48) {self.__lanius_state = SumState::Zero; return;}return;},"), "{text}");
}

#[test]
fn files_without_machines_are_unchanged() {
    let _one = one_at_a_time();
    let plain = ["fn plain() -> i32 { return 1; }\n", "struct S { a: i32 }\n"];
    let desugared = desugar_pack(&plain).expect("no rule applies");
    assert_eq!(desugared.tokens, lexed(&plain));
    assert!(desugared.region.is_empty());
}

/// Shapes the fixtures do not have: a public machine, state data, a
/// transition to the same state with one and with several values, a
/// binding arm, block arms, two machines in one file and text after the
/// last one. The recorded texts are the ones the host elaborator wrote
/// before the expansion moved to the GPU: the desugared token stream is
/// the stream of the recorded text, token by token, with each token in
/// its file.
#[test]
fn the_desugared_tokens_match_the_recorded_text() {
    let _one = one_at_a_time();
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../tests/fixtures/machines/expansion");
    let read = |name: String| {
        std::fs::read_to_string(dir.join(&name)).unwrap_or_else(|err| panic!("{name}: {err}"))
    };
    let shapes: Vec<(String, String)> = (0..3)
        .map(|index| {
            (
                read(format!("shape_{index}.source.txt")),
                read(format!("shape_{index}.expanded.txt")),
            )
        })
        .collect();
    let plain = "fn plain() -> i32 { return 1; }\n";
    let mut sources = vec![plain];
    sources.extend(shapes.iter().map(|(source, _)| source.as_str()));
    let mut expected_sources = vec![plain];
    expected_sources.extend(shapes.iter().map(|(_, expanded)| expanded.as_str()));
    let actual = desugar_pack(&sources)
        .unwrap_or_else(|verdict| panic!("{verdict}"))
        .tokens;
    let expected = lexed(&expected_sources);
    if let Some(at) =
        (0..actual.len().max(expected.len())).find(|&at| actual.get(at) != expected.get(at))
    {
        let window = |tokens: &[(u32, String, u32)]| {
            tokens[at.saturating_sub(8)..(at + 8).min(tokens.len())]
                .iter()
                .map(|(kind, text, file)| format!("{text}:{kind}@{file}"))
                .collect::<Vec<_>>()
                .join(" ")
        };
        panic!(
            "token {at} differs ({} and {} tokens)\n--- recorded ---\n{}\n--- gpu ---\n{}",
            expected.len(),
            actual.len(),
            window(&expected),
            window(&actual)
        );
    }
}

/// The rules accept every machine of the library and the fixtures, and
/// no machine token is left.
#[test]
fn the_rules_accept_every_library_machine() {
    let _one = one_at_a_time();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let mut files = Vec::new();
    for dir in ["tests/fixtures/machines", "stdlib", "extended"] {
        lani_files(&root.join(dir), &mut files);
    }
    files.sort();
    let mut sources = Vec::new();
    for path in files {
        let name = path.file_name().unwrap().to_string_lossy().into_owned();
        let source = std::fs::read_to_string(&path).expect("read a source file");
        // Generators and closures are rewritten before the frontend.
        let machine = source
            .lines()
            .any(|line| line.starts_with("machine ") || line.starts_with("pub machine "));
        let rejected = name.starts_with("reject_");
        if machine && !rejected && !source.contains("gen fn") && !source.contains('|') {
            sources.push(source);
        }
    }
    assert!(
        sources.len() >= 5,
        "found {} files with machines",
        sources.len()
    );
    let texts: Vec<&str> = sources.iter().map(String::as_str).collect();
    let desugared = desugar_pack(&texts).unwrap_or_else(|verdict| panic!("{verdict}"));
    let machine = TokenKind::Machine as u32;
    assert!(
        desugared.tokens.iter().all(|(kind, ..)| *kind != machine),
        "a machine token is left"
    );
}

#[test]
fn the_rules_reject_their_violations() {
    let _one = one_at_a_time();
    let fixture = |name: &str| {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../tests/fixtures/machines")
            .join(name);
        std::fs::read_to_string(path).expect("read a fixture")
    };
    let mut many = String::from("enum E { A }\nmachine M on E {\n    start S0;\n");
    for index in 0..257 {
        many.push_str(&format!(
            "    state S{index} {{ E::A -> goto S{}, }}\n",
            (index + 1) % 257
        ));
    }
    many.push_str("}\n");
    let one =
        |body: &str| format!("enum E {{ A }}\nmachine M on E {{\n    start S;\n{body}}}\n");
    let cases: Vec<(String, &str)> = vec![
        (fixture("reject_unreachable.lani"), "`Draining`: state `Draining` is unreachable from `start S`"),
        (fixture("reject_dead_end.lani"), "`Closed`: state `Closed` has no `goto` to another state [mark it `final state Closed` if the machine is meant to stop here]"),
        (fixture("reject_wildcard.lani"), "`_`: state `S` handles the remaining events with `_`; list each event, so adding one makes every state decide what it does"),
        (fixture("reject_return.lani"), "`return`: a machine arm leaves through `goto` or `stay`, not `return`"),
        (fixture("reject_missing_event.lani"), "`S`: state `S` does not handle `E::B` [add an arm, e.g. `E::B -> stay with ...`]"),
        (DOOR.replace("stay with Reply::Ignored,\n    }\n    state Closed", "stay,\n    }\n    state Closed"), "`stay`: this machine has an output: end the transition with `with value`"),
        (DOOR.replace("goto Closed with", "goto Shut with"), "`Shut`: no state is named `Shut`"),
        (DOOR.replace("start Closed", "start Shut"), "`Shut`: no state is named `Shut`"),
        (DOOR.replace("enum Input", "enum Other"), "`Input`: a machine's event type is an integer type or an enum declared in the machine's file"),
        ("machine M on u8 {\n    start S;\n    final state S { 0 -> stay, }\n}\n".to_string(), "`S`: state `S` must end with a `_` or binding arm, since its events are integers"),
        (one("    state S { E::A -> goto T, }\n    final state T { E::A -> stay, }\n    final state T { E::A -> stay, }\n"), "`T`: state `T` is declared twice"),
        (one("    final state S(n: i32) { E::A -> stay, }\n"), "`S`: the start state takes no data, so construction never chooses a state"),
        (one("    state S { E::A -> goto T(1), }\n    final state T(n: i32) { E::A -> goto T(1, 2), }\n"), "`(`: state `T` takes 1 values"),
        (one("    state S { E::A -> goto T(1), }\n    final state T(self) { E::A -> stay, }\n"), "`self`: expected a field name here"),
        (one("    final state S { E::A -> stay with 1, }\n"), "`with`: this machine has no output, so its transitions take no `with`"),
        (one("    final state S { E::A -> goto T, }\n    final state T { E::A -> stay, }\n"), "`S`: `final` state `S` has a `goto` to another state"),
        (one("    final state S { E::A -> 1, }\n"), "`1`: a machine arm ends in a transition: `goto State` or `stay`, or a block whose every path does"),
        ("enum E { A }\nmachine M on E -> i32 -> i32 {\n    start S;\n    final state S { E::A -> stay with 1, }\n}\n".to_string(), "`->`: expected `{` here"),
        (many, "`machine`: a machine has at most 256 states"),
        ("fn f() -> i32 {\n    goto Next;\n    return 0;\n}\n".to_string(), "`goto`: `goto` and `stay` are the transitions of a machine: write them in the arms of a state"),
    ];
    let mut failures = String::new();
    for (index, (source, expected)) in cases.iter().enumerate() {
        let verdict = match desugar_pack(&[source.as_str()]) {
            Ok(_) => "accepted".to_string(),
            Err(verdict) => verdict,
        };
        if verdict != *expected {
            failures.push_str(&format!(
                "case {index}:\n  expected {expected}\n  found    {verdict}\n"
            ));
        }
    }
    assert!(failures.is_empty(), "{failures}");
}

/// The first token where two streams differ, with the tokens around it.
fn first_difference(actual: &[(u32, String, u32)], expected: &[(u32, String, u32)]) -> Option<String> {
    let at = (0..actual.len().max(expected.len())).find(|&at| actual.get(at) != expected.get(at))?;
    let window = |tokens: &[(u32, String, u32)]| {
        tokens[at.saturating_sub(8).min(tokens.len())..(at + 8).min(tokens.len())]
            .iter()
            .map(|(kind, text, file)| format!("{text}:{kind}@{file}"))
            .collect::<Vec<_>>()
            .join(" ")
    };
    Some(format!(
        "token {at} differs ({} and {} tokens)\n--- recorded ---\n{}\n--- gpu ---\n{}",
        expected.len(),
        actual.len(),
        window(expected),
        window(actual)
    ))
}

/// Generators in one file and in several, with text around them, a public
/// one, yields in `if` and nested `while` blocks, and the library's
/// iterator. The recorded texts are the ones the text rewrite before the
/// frontend wrote before generators moved to the token stream: the
/// desugared stream of each pack is the desugared stream of its recorded
/// text, token by token, with each token in its file.
#[test]
fn generators_desugar_to_the_recorded_machines() {
    let _one = one_at_a_time();
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/machines/expansion");
    let mut failures = String::new();
    for pack in 0..4 {
        let mut sources = Vec::new();
        let mut expected = Vec::new();
        for file in 0.. {
            let read = |kind: &str| std::fs::read_to_string(dir.join(format!("generator_{pack}_{file}.{kind}.txt")));
            let Ok(source) = read("source") else { break };
            sources.push(source);
            expected.push(read("expanded").expect("a recorded text"));
        }
        // The recorded text names the generator's locals with the reserved
        // prefix, which a source may not use: both sides spell it another
        // way of the same length.
        let renamed = |text: &str| text.replace("__lanius_gen_", "zzlanius_gen_");
        let texts: Vec<&str> = sources.iter().map(String::as_str).collect();
        let actual: Vec<_> = desugar_pack(&texts)
            .unwrap_or_else(|verdict| panic!("pack {pack}: {verdict}"))
            .tokens
            .into_iter()
            .map(|(kind, text, file)| (kind, renamed(&text), file))
            .collect();
        let expected: Vec<String> = expected.iter().map(|text| renamed(text)).collect();
        let texts: Vec<&str> = expected.iter().map(String::as_str).collect();
        let expected = desugar_pack(&texts).unwrap_or_else(|verdict| panic!("recorded pack {pack}: {verdict}")).tokens;
        if let Some(difference) = first_difference(&actual, &expected) {
            failures.push_str(&format!("pack {pack}: {difference}\n"));
        }
    }
    assert!(failures.is_empty(), "{failures}");
}

const EVENS: &str = "import core::option;
gen fn evens(limit: i32) -> i32 {
    let i: i32 = 0;
    while (i < limit) {
        yield i;
        i += 2;
    }
}
";

#[test]
fn generators_stay_in_their_subset() {
    let _one = one_at_a_time();
    let rejected = |source: String| desugar_pack(&[source.as_str()]).err().unwrap_or_else(|| format!("accepted: {source}"));
    let cases = [
        (EVENS.replace("i += 2;", "limit = 1;"), "parameters are read-only"),
        (EVENS.replace("i += 2;", "i += 2; break;"), "no `break` or `continue`"),
        (EVENS.replace("let i: i32 = 0;", "let i = 0;"), "declare their type"),
        (EVENS.replace("yield i;", "{ yield i; }"), "not inside a `match`, `for` or plain block"),
        (EVENS.replace("import core::option;\n", ""), "imports `core::option`"),
        (EVENS.replace("i += 2;", "let i: i32 = 1;"), "`i` is declared again"),
        (EVENS.replace("i += 2;", "return 3;"), "takes no value"),
        (EVENS.replace("-> i32 {", "{"), "declares the type it yields"),
        (EVENS.replace("gen fn evens(", "gen fn evens<T>("), "no type parameters"),
    ];
    let mut failures = String::new();
    for (index, (source, expected)) in cases.iter().enumerate() {
        let verdict = rejected(source.clone());
        if !verdict.contains(expected) {
            failures.push_str(&format!("case {index}: expected {expected}\n  found {verdict}\n"));
        }
    }
    assert!(failures.is_empty(), "{failures}");

    let outside = "fn main() -> i32 {\n    yield 1;\n    return 0;\n}\n";
    let rule = desugar_or_reject(&[outside]).err().expect("a yield outside a generator");
    let text = format!("{:?}", rejected_in_source(Path::new("main.lani"), outside, rule));
    assert!(text.contains("write it in a `gen fn`") && text.contains("line: 2"), "{text}");
}

/// The token table of the generator strings is the GPU lexer's, with the
/// machine keywords the lexer reads where the strings put them.
#[test]
fn the_generator_and_closure_token_tables_match_the_lexer() {
    let _one = one_at_a_time();
    let lexer = test_lexer();
    for (strings, keyword) in [generators::constant_strings(), closures::constant_strings()] {
    for &text in strings {
        let tokens = without_desugaring(|| pollster::block_on(lexer.lex(text))).expect("lex a constant");
        let mut expected = vec![0u32; text.len()];
        for token in tokens {
            let word = &text[token.start..token.start + token.len];
            let kind = keyword(word).map_or(token.kind as u32, |kind| kind as u32);
            expected[token.start] = 1 | 2 | (kind << 8);
            for byte in &mut expected[token.start + 1..token.start + token.len] {
                *byte = 1 | (kind << 8);
            }
        }
        assert_eq!(token_info(text, keyword), expected, "{text:?}");
    }
}
}

/// The tokens build sets the closure bit only where a closure starts. The
/// library was written before closures existed, so no `|` or `||` in it
/// starts one, and a build of the library records no closure round.
#[test]
fn library_sources_start_no_closure() {
    let _one = one_at_a_time();
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let mut files = Vec::new();
    lani_files(&root.join("stdlib"), &mut files);
    lani_files(&root.join("extended"), &mut files);
    files.sort();
    let sources: Vec<String> = files
        .iter()
        .map(|path| std::fs::read_to_string(path).unwrap())
        .filter(|source| source.contains('|'))
        .collect();
    assert!(sources.len() > 100, "found {} library files with a `|`", sources.len());
    let features = |sources: &[&str]| {
        without_desugaring(|| {
            pollster::block_on(test_lexer().with_resident_source_pack_tokens(sources, |_, _, bufs| {
                let flags = bufs.parser_feature_flags.clone().reinterpret::<u8>(bufs.parser_feature_flags.byte_size);
                read_words(&test_lexer().desugaring().gpu(), &[(&flags, 0, 1)], None).expect("read the feature word")[0][0]
            }))
        })
        .expect("lex")
    };
    let texts: Vec<&str> = sources.iter().map(String::as_str).collect();
    assert_eq!(features(&texts) & PARSER_FEATURE_CLOSURES, 0);
    let control = "fn main() -> i32 {\n    let f: i32 = 2;\n    return call(move |x: i32| x * f);\n}\n";
    assert_ne!(features(&[control]) & PARSER_FEATURE_CLOSURES, 0);
    assert_eq!(features(&["fn f(a: bool, b: bool) -> bool {\n    return (a || b) | a;\n}\n"]) & PARSER_FEATURE_CLOSURES, 0);
}

/// A closure becomes a literal of a struct of its captures where it stands,
/// and the struct and its impls after the last token of its file. The file
/// imports nothing: the type checker resolves `core::function` as a
/// language item.
#[test]
fn a_closure_becomes_a_struct_and_impls() {
    let _one = one_at_a_time();
    let source = "module app::main;\nfn main() -> i32 {\n    let f: i32 = 2;\n    return call(|x: i32| x * f);\n}\n";
    let id = format!("{:010}", source.find("|x").unwrap());
    let expected = format!(
        "module app::main;\nfn main() -> i32 {{\n    let f: i32 = 2;\n    return call(__lanius_closure_{id}{{f:f,}}.borrow());\n}}\n\
         struct __lanius_closure_{id}{{f:i32,}}\nimpl __lanius_closure_{id}{{fn borrow(&self)->&__lanius_closure_{id}{{return self;}}}}\n\
         pub impl<__lanius_r> core::function::Mapper<i32,__lanius_r > for __lanius_closure_{id}\
         {{pub fn apply(&self,x:i32)->__lanius_r{{let f:i32 =self.f;return x * f;}}}}\n"
    );
    let desugared = desugar_pack(&[source]).unwrap_or_else(|verdict| panic!("{verdict}"));
    let expected = lexed(&[&expected]);
    if let Some(difference) = first_difference(&desugared.tokens, &expected) {
        panic!("{difference}");
    }
}

/// A source name may not have the prefix of generated names; the closure
/// round's own names are not source names.
#[test]
fn the_reserved_names_are_rejected() {
    let _one = one_at_a_time();
    let fixture = std::fs::read_to_string(
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/machines/reject_reserved.lani"),
    )
    .expect("read a fixture");
    let reserved = "identifiers starting with `__lanius_` are reserved for the compiler";
    for (source, name) in [
        (fixture.as_str(), "__lanius_state"),
        ("fn f() -> i32 { let __lanius_closure_3: i32 = 1; return __lanius_closure_3; }\n", "__lanius_closure_3"),
        ("fn f() -> i32 { let __lanius_r: i32 = 1; return __lanius_r; }\n", "__lanius_r"),
    ] {
        assert_eq!(desugar_pack(&[source]).err(), Some(format!("`{name}`: {reserved}")), "{source}");
    }
    let closure = "fn main() -> i32 {\n    let f: i32 = 2;\n    return call(|x: i32| x * f);\n}\n";
    assert!(desugar_pack(&[closure]).is_ok());
}
