//! The rewrites a source file passes through before the frontend reads it
//! (docs/state-machines-design.md, docs/language-ergonomics.md).
//!
//! A `gen fn` becomes a `machine` on the host (`generators`). Closures become
//! structs and impls on the GPU (`closures`). A `machine` item becomes an
//! enum of its states, a struct of its fields and its state, a constructor
//! and an impl with `step`, `state`, `run` and one method per state, on the
//! GPU from the parse tree (`machines`). The result is ordinary Lanius, which
//! the frontend then checks like any other code.
//!
//! The machine pass also checks what needs the machine's own shape: a
//! `return` in an arm (R2), a top-level `_` arm for an enum event (R3),
//! reachability from `start` and dead ends (R4), and the reserved `__lanius_`
//! prefix that keeps the state private (R5). A segment table maps each
//! rewritten byte back to the source, so diagnostics point at the source.

use std::{
    collections::HashMap,
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

/// `elaborate_source` for the files of one load. Generators are rewritten
/// per file on the host. Closures and then machines are rewritten on the
/// GPU, each in one run over all the files.
pub(crate) fn elaborate_sources(sources: Vec<(PathBuf, String)>) -> Result<Vec<String>, CompileError> {
    let mut files = Vec::with_capacity(sources.len());
    for (path, source) in sources {
        let known = source.contains(RESERVED_PREFIX)
            && registry().lock().is_ok_and(|registry| registry.contains_key(&blake3::hash(source.as_bytes())));
        let stages = if known { None } else { generators::elaborate(&path, &source)? };
        let flags = if stages.is_some() { machines::FILE_GENERATORS } else { 0 };
        files.push(Pending { path, source, known, stages, flags });
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
    // no transition outside a machine.
    let candidates: Vec<usize> = (0..files.len()).filter(|&index| !files[index].known).collect();
    let texts: Vec<&str> = candidates.iter().map(|&index| files[index].text()).collect();
    let flags: Vec<u32> = candidates.iter().map(|&index| files[index].flags).collect();
    let outcome = machines::expand(&texts, &flags).map_err(|err| {
        super::compiler_execution_failed_error("the compiler stopped while expanding machines", "expand machines", err)
    })?;
    match outcome {
        None => {}
        Some(machines::Outcome::Invalid(invalid)) => {
            let file = &files[candidates[invalid.file]];
            let (text, start, len) = file.source_span(invalid.start, invalid.len);
            return Err(machine_diagnostic(&file.path, text, start, len, invalid));
        }
        Some(machines::Outcome::Expanded(outputs)) => {
            for (index, output) in candidates.iter().zip(outputs) {
                if let Some(output) = output {
                    files[*index].push(output);
                }
            }
        }
    }

    let mut texts = Vec::with_capacity(files.len());
    for file in files {
        texts.push(match file.stages {
            None => file.source,
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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Kind {
    Ident,
    Number,
    Text,
    Punct,
}

#[derive(Clone, Copy, Debug)]
struct Token {
    kind: Kind,
    start: usize,
    end: usize,
}

fn error(path: &Path, source: &str, start: usize, len: usize, label: impl Into<String>) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error(MACHINE_CODE, MACHINE_TITLE)
            .with_primary_label(diagnostic_label_from_source_span(path, source, start, len, label)),
    )
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

fn tokenize(path: &Path, source: &str) -> Result<Vec<Token>, CompileError> {
    let bytes = source.as_bytes();
    let mut tokens = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        let byte = bytes[i];
        if byte.is_ascii_whitespace() {
            i += 1;
        } else if bytes[i..].starts_with(b"//") {
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
        } else if bytes[i..].starts_with(b"/*") {
            let Some(end) = source[i + 2..].find("*/") else {
                return Err(error(path, source, i, 2, "this comment is not closed"));
            };
            i += end + 4;
        } else if byte.is_ascii_alphabetic() || byte == b'_' {
            let start = i;
            while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') {
                i += 1;
            }
            tokens.push(Token { kind: Kind::Ident, start, end: i });
        } else if byte.is_ascii_digit() {
            let start = i;
            while i < bytes.len()
                && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_'
                    || (bytes[i] == b'.' && bytes.get(i + 1).is_some_and(u8::is_ascii_digit)))
            {
                i += 1;
            }
            tokens.push(Token { kind: Kind::Number, start, end: i });
        } else if byte == b'"' || byte == b'\'' {
            let start = i;
            i += 1;
            while i < bytes.len() && bytes[i] != byte {
                i += if bytes[i] == b'\\' { 2 } else { 1 };
            }
            if i >= bytes.len() {
                return Err(error(path, source, start, 1, "this literal is not closed"));
            }
            i += 1;
            tokens.push(Token { kind: Kind::Text, start, end: i });
        } else {
            let start = i;
            let width = if bytes[i..].starts_with(b"->") || bytes[i..].starts_with(b"::") {
                2
            } else {
                source[i..].chars().next().map_or(1, char::len_utf8)
            };
            i += width;
            tokens.push(Token { kind: Kind::Punct, start, end: i });
        }
    }
    Ok(tokens)
}

struct Elaborator<'a> {
    path: &'a Path,
    source: &'a str,
    tokens: Vec<Token>,
    /// The index of each opening delimiter's closing one, and back.
    partner: Vec<usize>,
    out: String,
    segments: Vec<Segment>,
}

const NONE: usize = usize::MAX;

impl<'a> Elaborator<'a> {
    fn text(&self, token: usize) -> &'a str {
        let token = self.tokens[token];
        &self.source[token.start..token.end]
    }

    fn is(&self, token: usize, text: &str) -> bool {
        token < self.tokens.len() && self.text(token) == text
    }

    fn ident(&self, token: usize) -> bool {
        token < self.tokens.len() && self.tokens[token].kind == Kind::Ident
    }

    fn fail(&self, token: usize, label: impl Into<String>) -> CompileError {
        let token = self.tokens.get(token).copied().unwrap_or(Token {
            kind: Kind::Punct,
            start: self.source.len(),
            end: self.source.len(),
        });
        error(self.path, self.source, token.start, (token.end - token.start).max(1), label)
    }

    fn expect(&self, token: usize, text: &str) -> Result<(), CompileError> {
        if self.is(token, text) { Ok(()) } else { Err(self.fail(token, format!("expected `{text}` here"))) }
    }

    fn expect_ident(&self, token: usize, what: &str) -> Result<Token, CompileError> {
        if self.ident(token) { Ok(self.tokens[token]) } else { Err(self.fail(token, format!("expected {what} here"))) }
    }

    /// Pairs `(`/`)`, `[`/`]` and `{`/`}`.
    fn pair_delimiters(&mut self) -> Result<(), CompileError> {
        let mut open = Vec::new();
        self.partner = vec![NONE; self.tokens.len()];
        for index in 0..self.tokens.len() {
            if self.tokens[index].kind != Kind::Punct {
                continue;
            }
            match self.text(index) {
                "(" | "[" | "{" => open.push(index),
                closer @ (")" | "]" | "}") => {
                    let expected = match closer { ")" => "(", "]" => "[", _ => "{" };
                    match open.pop() {
                        Some(opener) if self.text(opener) == expected => {
                            self.partner[opener] = index;
                            self.partner[index] = opener;
                        }
                        // The frontend reports unbalanced delimiters; a
                        // machine needs balanced ones to be found at all.
                        _ => return Err(self.fail(index, "this delimiter is not balanced")),
                    }
                }
                _ => {}
            }
        }
        if let Some(&opener) = open.last() {
            return Err(self.fail(opener, "this delimiter is not closed"));
        }
        Ok(())
    }

    /// The token after a type that starts at `token`: a type ends at a `,`,
    /// `;`, `)`, `{`, `=` or `->` outside its own `<>`, `()` and `[]`.
    fn type_end(&self, mut token: usize, limit: usize) -> usize {
        let mut angles = 0usize;
        while token < limit {
            let text = self.text(token);
            match text {
                "(" | "[" => token = self.partner[token],
                "<" => angles += 1,
                ">" if angles > 0 => angles -= 1,
                "," | ";" | ")" | "{" | "=" | "->" if angles == 0 => return token,
                _ => {}
            }
            token += 1;
        }
        limit
    }

    fn span(&self, first: usize, end: usize) -> (usize, usize) {
        let start = self.tokens[first].start;
        (start, self.tokens[end - 1].end)
    }

    /// `name: Type, ...` up to `limit`, for state data.
    fn fields(&self, mut token: usize, limit: usize) -> Result<Vec<(Token, (usize, usize))>, CompileError> {
        let mut fields = Vec::new();
        while token < limit {
            let name = self.expect_ident(token, "a field name")?;
            self.expect(token + 1, ":")?;
            let end = self.type_end(token + 2, limit);
            if end == token + 2 {
                return Err(self.fail(token + 2, "expected a type here"));
            }
            fields.push((name, self.span(token + 2, end)));
            token = end;
            if token < limit {
                self.expect(token, ",")?;
                token += 1;
            }
        }
        Ok(fields)
    }

    fn copy(&mut self, start: usize, end: usize) {
        if start >= end {
            return;
        }
        self.segments.push(Segment {
            out_start: self.out.len(),
            out_len: end - start,
            src_start: start,
            src_len: end - start,
            copied: true,
        });
        self.out.push_str(&self.source[start..end]);
    }

    /// Generated text, anchored at source token `anchor` for diagnostics.
    fn emit(&mut self, text: &str, anchor: Token) {
        if text.is_empty() {
            return;
        }
        self.segments.push(Segment {
            out_start: self.out.len(),
            out_len: text.len(),
            src_start: anchor.start,
            src_len: anchor.end - anchor.start,
            copied: false,
        });
        self.out.push_str(text);
    }

    fn src(&self, span: (usize, usize)) -> &'a str {
        &self.source[span.0..span.1]
    }
}

fn snake_case(name: &str) -> String {
    let chars: Vec<char> = name.chars().collect();
    let mut out = String::new();
    for (index, &c) in chars.iter().enumerate() {
        if c.is_ascii_uppercase() {
            let previous = index.checked_sub(1).map(|i| chars[i]);
            let next = chars.get(index + 1);
            let boundary = previous.is_some_and(|p| p.is_ascii_lowercase() || p.is_ascii_digit())
                || (previous.is_some_and(|p| p.is_ascii_uppercase()) && next.is_some_and(|n| n.is_ascii_lowercase()));
            if boundary {
                out.push('_');
            }
            out.push(c.to_ascii_lowercase());
        } else {
            out.push(c);
        }
    }
    out
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

    /// A generator becomes a machine on the host, and the GPU expands that
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

    #[test]
    fn snake_case_splits_words() {
        assert_eq!(snake_case("Door"), "door");
        assert_eq!(snake_case("TlsSession"), "tls_session");
        assert_eq!(snake_case("HTTPServer"), "http_server");
    }
}
