//! The rewrites a source file passes through before the frontend reads it
//! (docs/state-machines-design.md, docs/language-ergonomics.md).
//!
//! Every rewrite runs on the GPU. Closures become structs and impls
//! (`closures`). A `gen fn` becomes a `machine` (`generators`), from the
//! parse tree of the machine pass. A `machine` item becomes an enum of its
//! states, a struct of its fields and its state, a constructor and an impl
//! with `step`, `state`, `run` and one method per state (`machines`). The
//! result is ordinary Lanius, which the frontend then checks like any other
//! code.
//!
//! The machine pass also checks what needs the machine's own shape: a
//! `return` in an arm (R2), a top-level `_` arm for an enum event (R3),
//! reachability from `start` and dead ends (R4), and the reserved `__lanius_`
//! prefix that keeps the state private (R5). A segment table maps each
//! rewritten byte back to the source, so diagnostics point at the source.

use std::{
    collections::{HashMap, HashSet},
    path::{Path, PathBuf},
    sync::{Arc, Mutex, OnceLock},
};

use super::{CompileError, Diagnostic, diagnostic_label_from_source_span};

mod closures;
mod generators;
mod machines;

/// Identifiers starting with this prefix are reserved for elaborated code.
pub(crate) const RESERVED_PREFIX: &str = "__lanius_";

const MACHINE_CODE: &str = "LNC0076";
const MACHINE_TITLE: &str = "invalid machine";
const CLOSURE_CODE: &str = "LNC0078";
const CLOSURE_TITLE: &str = "invalid closure";

/// Elaborated bytes `[out_start, out_start + out_len)` came from source bytes
/// `[src_start, src_start + src_len)`: copied when `copied` (so the lengths
/// are equal), otherwise generated text anchored at that source span.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Segment {
    out_start: usize,
    out_len: usize,
    src_start: usize,
    src_len: usize,
    copied: bool,
}

/// A source file with its machines elaborated. `inner` is the elaboration
/// of its generators (M5) when it has any: its text is this one's original.
#[derive(Debug)]
pub(crate) struct Elaborated {
    pub(crate) text: String,
    original: String,
    segments: Vec<Segment>,
    inner: Option<Box<Elaborated>>,
}

impl Elaborated {
    /// The source span an elaborated span came from.
    fn original_span(&self, start: usize, len: usize) -> (usize, usize) {
        let (start, len) = self.own_span(start, len);
        match &self.inner {
            Some(inner) => inner.original_span(start, len),
            None => (start, len),
        }
    }

    fn own_span(&self, start: usize, len: usize) -> (usize, usize) {
        let index = self.segments.partition_point(|segment| segment.out_start + segment.out_len <= start);
        let Some(segment) = self.segments.get(index) else {
            return (self.original.len(), 0);
        };
        if !segment.copied || start < segment.out_start {
            return (segment.src_start, segment.src_len);
        }
        let offset = start - segment.out_start;
        let end = (segment.out_start + segment.out_len).min(start + len);
        (segment.src_start + offset, end - start)
    }
}

fn registry() -> &'static Mutex<HashMap<blake3::Hash, Arc<Elaborated>>> {
    static REGISTRY: OnceLock<Mutex<HashMap<blake3::Hash, Arc<Elaborated>>>> = OnceLock::new();
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Texts the rewrites read and left as they were. A pack that reaches two
/// entry points is read once.
fn unchanged() -> &'static Mutex<HashSet<blake3::Hash>> {
    static UNCHANGED: OnceLock<Mutex<HashSet<blake3::Hash>>> = OnceLock::new();
    UNCHANGED.get_or_init(|| Mutex::new(HashSet::new()))
}

/// The original text and span behind a span of elaborated text, if `source`
/// is an elaborated file.
pub(crate) fn original_span(source: &str, start: usize, len: usize) -> Option<(Arc<Elaborated>, usize, usize)> {
    if !source.contains(RESERVED_PREFIX) {
        return None;
    }
    let elaborated = registry().lock().ok()?.get(&blake3::hash(source.as_bytes())).cloned()?;
    if elaborated.text != source {
        return None;
    }
    let (start, len) = elaborated.original_span(start, len);
    Some((elaborated, start, len))
}

impl Elaborated {
    pub(crate) fn original(&self) -> &str {
        match &self.inner {
            Some(inner) => inner.original(),
            None => &self.original,
        }
    }
}

/// The text the GPU frontend reads for `source`: `source` itself unless it
/// declares a machine or a generator, or contains a closure.
pub(crate) fn elaborate_source(path: &Path, source: String) -> Result<String, CompileError> {
    let mut texts = elaborate_sources(vec![(path.to_path_buf(), source)])?;
    Ok(texts.pop().expect("one text per source"))
}

/// One file on its way through the rewrites. `stages` is the chain of
/// rewrites so far, the last one outermost.
struct Pending {
    path: PathBuf,
    source: String,
    /// The text is already elaborated: it names reserved identifiers, and
    /// reading it again changes nothing.
    known: bool,
    stages: Option<Elaborated>,
    /// `machines::FILE_GENERATORS` and `machines::FILE_CLOSURES`.
    flags: u32,
}

impl Pending {
    fn text(&self) -> &str {
        self.stages.as_ref().map_or(self.source.as_str(), |stages| stages.text.as_str())
    }

    /// Adds a rewrite of `text()`.
    fn push(&mut self, rewritten: closures::Rewritten) {
        let original = self.text().to_string();
        self.stages = Some(Elaborated {
            text: rewritten.text,
            original,
            segments: rewritten.segments,
            inner: self.stages.take().map(Box::new),
        });
    }

    /// The source text and span behind a span of `text()`.
    fn source_span(&self, start: usize, len: usize) -> (&str, usize, usize) {
        match &self.stages {
            Some(stages) => {
                let (start, len) = stages.original_span(start, len);
                (stages.original(), start, len)
            }
            None => (self.source.as_str(), start, len),
        }
    }
}

/// `elaborate_source` for the files of one load. Closures, then generators,
/// then machines are rewritten on the GPU, each in one run over all the
/// files.
pub(crate) fn elaborate_sources(sources: Vec<(PathBuf, String)>) -> Result<Vec<String>, CompileError> {
    let mut files = Vec::with_capacity(sources.len());
    for (path, source) in sources {
        let hash = blake3::hash(source.as_bytes());
        let known = unchanged().lock().is_ok_and(|unchanged| unchanged.contains(&hash))
            || (source.contains(RESERVED_PREFIX)
                && registry().lock().is_ok_and(|registry| registry.contains_key(&hash)));
        files.push(Pending { path, source, known, stages: None, flags: 0 });
    }

    // Closures, for the files that can hold one. The parser does not read a
    // closure, so they go before the machines.
    let candidates: Vec<usize> =
        (0..files.len()).filter(|&index| !files[index].known && files[index].text().contains('|')).collect();
    if !candidates.is_empty() {
        let texts: Vec<&str> = candidates.iter().map(|&index| files[index].text()).collect();
        let outcome = closures::rewrite(&texts).map_err(|err| {
            super::compiler_execution_failed_error(
                "the compiler stopped while rewriting closures",
                "rewrite closures",
                err,
            )
        })?;
        match outcome {
            None => {}
            Some(closures::Outcome::Invalid(invalid)) => {
                let file = &files[candidates[invalid.file]];
                let (text, start, len) = file.source_span(invalid.start, invalid.len);
                return Err(CompileError::Diagnostic(
                    Diagnostic::error(CLOSURE_CODE, CLOSURE_TITLE).with_primary_label(
                        diagnostic_label_from_source_span(&file.path, text, start, len, invalid.message),
                    ),
                ));
            }
            Some(closures::Outcome::Rewritten(outputs)) => {
                for (index, output) in candidates.iter().zip(outputs) {
                    if let Some(output) = output {
                        files[*index].flags |= machines::FILE_CLOSURES;
                        files[*index].push(output);
                    }
                }
            }
        }
    }

    // Machines, and the rules every file follows: the reserved names, and
    // no transition outside a machine. When a file declares a generator the
    // pass rewrites the generators into machines instead, and runs again on
    // the result.
    let candidates: Vec<usize> = (0..files.len()).filter(|&index| !files[index].known).collect();
    for round in 0..2 {
        let texts: Vec<&str> = candidates.iter().map(|&index| files[index].text()).collect();
        let flags: Vec<u32> = candidates.iter().map(|&index| files[index].flags).collect();
        let outcome = machines::expand(&texts, &flags).map_err(|err| {
            super::compiler_execution_failed_error(
                "the compiler stopped while expanding machines",
                "expand machines",
                err,
            )
        })?;
        let (outputs, flag) = match outcome {
            None => break,
            Some(machines::Outcome::Invalid(invalid)) => {
                let file = &files[candidates[invalid.file]];
                let (text, start, len) = file.source_span(invalid.start, invalid.len);
                return Err(machine_diagnostic(&file.path, text, start, len, invalid));
            }
            Some(machines::Outcome::Generators(outputs)) if round == 0 => (outputs, machines::FILE_GENERATORS),
            Some(machines::Outcome::Generators(_)) => {
                return Err(super::compiler_execution_failed_error(
                    "the compiler stopped while expanding machines",
                    "expand machines",
                    anyhow::anyhow!("a rewritten generator still holds a `gen` or `yield` token"),
                ));
            }
            Some(machines::Outcome::Expanded(outputs)) => (outputs, 0),
        };
        for (index, output) in candidates.iter().zip(outputs) {
            if let Some(output) = output {
                files[*index].flags |= flag;
                files[*index].push(output);
            }
        }
        if flag == 0 {
            break;
        }
    }

    let mut texts = Vec::with_capacity(files.len());
    for file in files {
        texts.push(match file.stages {
            None => {
                if !file.known && let Ok(mut unchanged) = unchanged().lock() {
                    unchanged.insert(blake3::hash(file.source.as_bytes()));
                }
                file.source
            }
            Some(elaborated) => {
                let text = elaborated.text.clone();
                if let Ok(mut registry) = registry().lock() {
                    registry.insert(blake3::hash(text.as_bytes()), Arc::new(elaborated));
                }
                text
            }
        });
    }
    Ok(texts)
}

/// The diagnostic of a machine the GPU rules reject. `source` is the text of
/// the span.
fn machine_diagnostic(path: &Path, source: &str, start: usize, len: usize, invalid: machines::Invalid) -> CompileError {
    let diagnostic = Diagnostic::error(MACHINE_CODE, MACHINE_TITLE)
        .with_primary_label(diagnostic_label_from_source_span(path, source, start, len, invalid.message));
    CompileError::Diagnostic(match invalid.help {
        Some(help) => diagnostic.with_help(help),
        None => diagnostic,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

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

    #[test]
    fn diagnostics_map_back_to_the_machine() {
        let text = elaborate_source(Path::new("door.lani"), DOOR.to_string()).unwrap();
        let copied = text.find("Reply::Done").unwrap();
        let (elaborated, start, len) = original_span(&text, copied, 11).expect("the text is registered");
        assert_eq!(elaborated.original(), DOOR);
        assert_eq!(&DOOR[start..start + len], "Reply::Done");
        let generated = text.find("__lanius_state = DoorState::Closed").unwrap();
        let (_, start, len) = original_span(&text, generated, 5).unwrap();
        assert_eq!(&DOOR[start..start + len], "goto");
    }

    #[test]
    fn a_rejected_machine_names_its_source_line() {
        let source = DOOR.replace("goto Closed with", "goto Shut with");
        let Err(CompileError::Diagnostic(diagnostic)) = elaborate_source(Path::new("door.lani"), source) else {
            panic!("the machine names a state it does not have");
        };
        let text = format!("{diagnostic:?}");
        assert!(text.contains("no state is named `Shut`"), "{text}");
        assert!(text.contains("line: 6"), "{text}");
    }

    /// A generator becomes a machine, and the machine pass expands that
    /// machine: the file passes through both rewrites.
    #[test]
    fn a_generator_passes_through_both_rewrites() {
        let source = "import core::option;\ngen fn evens(limit: i32) -> i32 {\n    let i: i32 = 0;\n    while (i < limit) {\n        yield i;\n        i += 2;\n    }\n}\n";
        let text = elaborate_source(Path::new("evens.lani"), source.to_string()).unwrap();
        assert!(text.contains("enum EvensState {"), "{text}");
        assert!(text.contains("fn next(&mut self) -> core::option::Option<i32> { return self.step(EvensResume::Next); }"), "{text}");
        let at = text.find("__lanius_gen_i").unwrap();
        let (elaborated, start, _) = original_span(&text, at, 14).unwrap();
        assert_eq!(elaborated.original(), source);
        assert!(start < source.len());
    }

    fn lani_files(dir: &Path, files: &mut Vec<PathBuf>) {
        for entry in std::fs::read_dir(dir).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                lani_files(&path, files);
            } else if path.extension().is_some_and(|extension| extension == "lani") {
                files.push(path);
            }
        }
    }

    /// The library was written before closures existed, so no `|` or `||`
    /// in it starts a closure. The last source holds one closure: it shows
    /// that the pass read the whole pack.
    #[test]
    fn the_closure_pass_leaves_library_sources_unchanged() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let mut files = Vec::new();
        lani_files(&root.join("stdlib"), &mut files);
        lani_files(&root.join("extended"), &mut files);
        files.sort();
        let mut sources = Vec::new();
        let mut paths = Vec::new();
        for path in files {
            let source = std::fs::read_to_string(&path).unwrap();
            if source.contains('|') {
                sources.push(source);
                paths.push(path);
            }
        }
        assert!(paths.len() > 100, "found {} library files with a `|`", paths.len());
        sources.push("fn main() -> i32 {\n    let f: i32 = 2;\n    return call(|x: i32| x * f);\n}\n".to_string());

        let texts: Vec<&str> = sources.iter().map(String::as_str).collect();
        let outputs = match closures::rewrite(&texts).unwrap() {
            Some(closures::Outcome::Rewritten(outputs)) => outputs,
            Some(closures::Outcome::Invalid(invalid)) => panic!(
                "{}: {} at byte {}",
                paths.get(invalid.file).map_or("the control source".into(), |path| path.display().to_string()),
                invalid.message,
                invalid.start
            ),
            None => panic!("the pass found no closure in the control source"),
        };
        assert_eq!(outputs.len(), sources.len());
        let changed: Vec<&PathBuf> =
            paths.iter().zip(&outputs).filter(|(_, output)| output.is_some()).map(|(path, _)| path).collect();
        assert!(changed.is_empty(), "the closure pass rewrote {changed:?}");
        assert!(outputs[paths.len()].as_ref().is_some_and(|output| output.text.contains("__lanius_closure_")));
    }
}
