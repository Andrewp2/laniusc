//! `machine` items are ordinary grammar: the GPU lexer and parser accept them
//! without a rewrite in front (docs/state-machines-design.md).

use crate::common;

use laniusc_compiler::{
    lexer::driver::GpuLexer,
    parser::{driver::GpuParser, tables::PrecomputedParseTables},
};

/// Lexes and parses each source on the GPU and returns the parser's verdicts.
fn parse_all(sources: Vec<(String, String)>) -> Vec<(String, Result<(), String>)> {
    common::block_on_gpu_with_timeout("machine syntax", async move {
        let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tables/parse_tables.bin"
        )))
        .expect("load precomputed parse tables");
        let lexer = GpuLexer::new().await.expect("create GPU lexer");
        let parser = GpuParser::new().await.expect("create GPU parser");
        let mut verdicts = Vec::new();
        for (name, source) in sources {
            let verdict = lexer
                .with_resident_tokens(&source, |_, _, buffers| {
                    parser.check_resident_tokens(
                        buffers.n,
                        &buffers.tokens_out,
                        &buffers.token_count,
                        &tables,
                    )
                })
                .await
                .expect("resident lex should succeed")
                .map_err(|error| error.to_string());
            verdicts.push((name, verdict));
        }
        verdicts
    })
}

fn fixture(name: &str) -> (String, String) {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/machines")
        .join(name);
    (name.to_string(), std::fs::read_to_string(path).expect(name))
}

fn inline(name: &str, source: &str) -> (String, String) {
    (name.to_string(), source.to_string())
}

#[test]
fn the_parser_accepts_machine_items() {
    let verdicts = parse_all(vec![
        fixture("door.lani"),
        fixture("sum_numbers.lani"),
        fixture("sum_numbers_run.lani"),
        fixture("run_matches_step.lani"),
        fixture("references_before_step.lani"),
        // The rules these break are not grammar rules.
        fixture("reject_dead_end.lani"),
        fixture("reject_falls_through.lani"),
        fixture("reject_missing_event.lani"),
        fixture("reject_reserved.lani"),
        fixture("reject_return.lani"),
        fixture("reject_unreachable.lani"),
        fixture("reject_wildcard.lani"),
        inline(
            "public machine with a generic output and a final state",
            r#"
module app::main;
import core::result;
enum Event { Byte(u8), End }
enum Error { Short }
pub machine Reader on Event -> core::result::Result<bool, Error> {
    seen: u32,
    limit: u32,
    start Reading;
    state Reading {
        Event::Byte(b) -> {
            self.seen += 1;
            if (self.seen == self.limit) { goto Done(b) with core::result::Result::Ok(true); }
            stay with core::result::Result::Ok(false);
        },
        Event::End -> goto Done(0) with core::result::Result::Err(Error::Short),
    }
    final state Done(last: u8) {
        _ -> stay with core::result::Result::Ok(true),
    }
}
fn main() -> i32 { return 0; }
"#,
        ),
        inline(
            "machine with no fields",
            r#"
machine Toggle on bool {
    start Off;
    state Off { true -> goto On, false -> stay }
    state On { true -> goto Off, false -> stay, }
}
fn main() -> i32 { return 0; }
"#,
        ),
    ]);
    for (name, verdict) in verdicts {
        assert!(verdict.is_ok(), "{name}: {}", verdict.unwrap_err());
    }
}

// The machine words are keywords only in a machine position.
#[test]
fn machine_words_stay_usable_as_names() {
    let verdicts = parse_all(vec![inline(
        "machine words as names",
        r#"
struct Flags { on: bool, final: bool, state: i32, start: i32 }
fn stay(with: i32) -> i32 { return with; }
fn goto(machine: i32) -> i32 { return machine; }
fn pick(state: i32, stay: i32) -> i32 {
    let start: i32 = state;
    let on: i32 = match (start) { 0 -> stay, 1 -> goto(start), _ -> stay };
    return on + stay(start);
}
fn main() -> i32 {
    let flags: Flags = Flags { on: true, final: false, state: 1, start: 2 };
    let final: i32 = flags.state + flags.start;
    return pick(final, 3);
}
"#,
    )]);
    for (name, verdict) in verdicts {
        assert!(verdict.is_ok(), "{name}: {}", verdict.unwrap_err());
    }
}

#[test]
fn the_parser_rejects_malformed_machines() {
    let verdicts = parse_all(vec![
        inline(
            "no start declaration",
            "enum E { A }\nmachine M on E { state S { E::A -> stay } }\nfn main() -> i32 { return 0; }\n",
        ),
        inline(
            "no event type",
            "machine M { start S; state S { _ -> stay } }\nfn main() -> i32 { return 0; }\n",
        ),
        inline(
            "state outside a machine",
            "state S { _ -> 1 }\nfn main() -> i32 { return 0; }\n",
        ),
        inline(
            "field after the states",
            "machine M on bool { start S; state S { _ -> stay } count: i32, }\nfn main() -> i32 { return 0; }\n",
        ),
    ]);
    for (name, verdict) in verdicts {
        assert!(verdict.is_err(), "{name}: the parser accepted it");
    }
}

fn machine_files(dir: &std::path::Path, files: &mut Vec<(String, String)>) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    let mut paths: Vec<_> = entries.flatten().map(|entry| entry.path()).collect();
    paths.sort();
    for path in paths {
        if path.is_dir() {
            machine_files(&path, files);
        } else if path.extension().is_some_and(|extension| extension == "lani") {
            let Ok(source) = std::fs::read_to_string(&path) else { continue };
            let declares = source.lines().any(|line| {
                let line = line.trim_start();
                let line = line.strip_prefix("pub ").unwrap_or(line);
                line.strip_prefix("machine ").is_some_and(|rest| rest.contains(" on "))
            });
            if declares {
                files.push((path.display().to_string(), source));
            }
        }
    }
}

// Every machine in the libraries. `LANIUS_MACHINE_SYNTAX_ROOT` names another
// checkout to read the libraries from.
#[test]
fn the_parser_accepts_the_library_machines() {
    let root = std::env::var("LANIUS_MACHINE_SYNTAX_ROOT")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")));
    let mut files = Vec::new();
    machine_files(&root.join("stdlib"), &mut files);
    machine_files(&root.join("extended"), &mut files);
    assert!(!files.is_empty(), "no library file declares a machine");
    let count = files.len();
    let rejected: Vec<String> = parse_all(files)
        .into_iter()
        .filter_map(|(name, verdict)| verdict.err().map(|error| format!("{name}: {error}")))
        .collect();
    assert!(rejected.is_empty(), "{} of {count} files rejected:\n{}", rejected.len(), rejected.join("\n"));
}
