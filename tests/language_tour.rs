//! Compiles and runs every example in `docs/language-tour.md` with the
//! `laniusc` binary, the way a reader of the tour does.
//!
//! The tour marks its examples with fenced blocks:
//!
//! - `lanius` is a source file. `file=PATH` names it; the default is
//!   `main.lani`. The last source block before a result block is the entry.
//! - `output` is the standard output of the compiled program. `exit=N` is its
//!   exit status; the default is 0.
//! - `stderr` follows an `output` block and is the program's standard error.
//!   Without it the program must write nothing there.
//! - `diagnostic` is what the compiler prints when it rejects the example.
//!
//! Blocks with any other tag are not examples.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]

use crate::common;

use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::Duration,
};

const TOUR: &str = include_str!("../docs/language-tour.md");

struct Block {
    tag: String,
    attributes: Vec<(String, String)>,
    body: String,
    line: usize,
}

impl Block {
    fn attribute(&self, name: &str) -> Option<&str> {
        self.attributes
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.as_str())
    }
}

fn fenced_blocks(document: &str) -> Vec<Block> {
    let mut blocks = Vec::new();
    let mut open: Option<Block> = None;
    for (index, line) in document.lines().enumerate() {
        match open.take() {
            Some(block) if line == "```" => blocks.push(block),
            Some(mut block) => {
                block.body.push_str(line);
                block.body.push('\n');
                open = Some(block);
            }
            None => {
                let Some(info) = line.strip_prefix("```") else {
                    continue;
                };
                let mut words = info.split_whitespace();
                let tag = words.next().unwrap_or("").to_string();
                let attributes = words
                    .map(|word| {
                        let (key, value) = word.split_once('=').unwrap_or_else(|| {
                            panic!("line {}: block attribute `{word}` is not key=value", index + 1)
                        });
                        (key.to_string(), value.to_string())
                    })
                    .collect();
                open = Some(Block { tag, attributes, body: String::new(), line: index + 1 });
            }
        }
    }
    assert!(open.is_none(), "the tour ends inside a fenced block");
    blocks
}

struct Directory(common::TempArtifact);

impl Directory {
    fn new() -> Self {
        let path = common::TempArtifact::new("laniusc_language_tour", "example", None);
        fs::create_dir(path.path()).unwrap();
        Self(path)
    }

    fn path(&self) -> &Path {
        self.0.path()
    }
}

impl Drop for Directory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(self.path());
    }
}

/// Writes the example's files below a new directory and compiles the entry
/// there with the command line the tour gives.
fn compile(files: &[(String, String)], line: usize) -> (Directory, std::process::Output) {
    let directory = Directory::new();
    for (path, source) in files {
        let path = directory.path().join(path);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, source).unwrap();
    }
    let (entry, _) = files.last().unwrap();
    let mut command = Command::new(env!("CARGO_BIN_EXE_laniusc"));
    command
        .current_dir(directory.path())
        .arg("--stdlib-root")
        .arg(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib"));
    if files.iter().any(|(path, _)| path.starts_with("src/")) {
        command.args(["--source-root", "src"]);
    }
    command.args(["-o", "program", entry]).stdin(Stdio::null());
    let output = common::process_output_with_timeout(
        format!("compile the tour example at line {line}"),
        &mut command,
        Duration::from_secs(300),
    );
    (directory, output)
}

fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

#[test]
fn every_example_in_the_tour_compiles_and_runs_as_written() {
    let blocks = fenced_blocks(TOUR);
    let mut files: Vec<(String, String)> = Vec::new();
    let mut first_line = 0;
    let mut ran = 0;
    let mut rejected = 0;
    let mut index = 0;
    while index < blocks.len() {
        let block = &blocks[index];
        index += 1;
        match block.tag.as_str() {
            "lanius" => {
                if files.is_empty() {
                    first_line = block.line;
                }
                let path = block.attribute("file").unwrap_or("main.lani");
                files.push((path.to_string(), block.body.clone()));
            }
            "output" => {
                assert!(!files.is_empty(), "line {}: output without a program", block.line);
                let exit: i32 = block
                    .attribute("exit")
                    .map_or(0, |value| value.parse().expect("exit status"));
                let stderr = match blocks.get(index) {
                    Some(next) if next.tag == "stderr" => {
                        index += 1;
                        next.body.as_str()
                    }
                    _ => "",
                };
                let (directory, compiled) = compile(&files, first_line);
                assert!(
                    compiled.status.success(),
                    "the example at line {first_line} does not compile:\n{}",
                    text(&compiled.stderr)
                );
                let run = common::short_process_output_with_timeout(
                    format!("run the tour example at line {first_line}"),
                    Command::new(directory.path().join("program")).stdin(Stdio::null()),
                );
                assert_eq!(
                    text(&run.stdout),
                    block.body,
                    "standard output of the example at line {first_line}"
                );
                assert_eq!(
                    text(&run.stderr),
                    stderr,
                    "standard error of the example at line {first_line}"
                );
                assert_eq!(
                    run.status.code(),
                    Some(exit),
                    "exit status of the example at line {first_line}: {run:?}"
                );
                files.clear();
                ran += 1;
            }
            "diagnostic" => {
                assert!(!files.is_empty(), "line {}: diagnostic without a program", block.line);
                let (_directory, compiled) = compile(&files, first_line);
                assert!(
                    !compiled.status.success(),
                    "the compiler accepts the example at line {first_line}"
                );
                assert_eq!(
                    text(&compiled.stderr),
                    block.body,
                    "diagnostic for the example at line {first_line}"
                );
                files.clear();
                rejected += 1;
            }
            "stderr" => panic!("line {}: stderr block without an output block", block.line),
            _ => {}
        }
    }
    assert!(
        files.is_empty(),
        "the example at line {first_line} has no output or diagnostic block"
    );
    assert!(ran >= 12 && rejected >= 1, "the tour lost examples: {ran} run, {rejected} rejected");
}
