//! `machine` items (docs/state-machines-design.md, phase M1).
//!
//! A machine elaborates, when its file is read, into an enum of its states, a
//! struct of its fields and its state, a constructor and an impl with `step`,
//! `state` and one method per state. That is ordinary Lanius, which the GPU
//! frontend then checks like any other code: the arms' exhaustiveness (R3),
//! their types and that every path through an arm ends in a transition (R2,
//! through the block-arm check).
//!
//! Elaboration is mechanical, like import discovery: it splits the machine's
//! text at its delimiters, copies the pieces and adds fixed text around them.
//! It also checks what needs the machine's own shape: a `return` in an arm
//! (R2), a top-level `_` arm for an enum event (R3), reachability from `start`
//! and dead ends (R4), and the reserved `__lanius_` prefix that keeps the
//! state private (R5). A segment table maps each elaborated byte back to the
//! source, so diagnostics point at the machine.

use std::{
    collections::HashMap,
    path::Path,
    sync::{Arc, Mutex, OnceLock},
};

use super::{CompileError, Diagnostic, diagnostic_label_from_source_span};

/// Identifiers starting with this prefix are reserved for elaborated code.
pub(crate) const RESERVED_PREFIX: &str = "__lanius_";

const MACHINE_CODE: &str = "LNC0076";
const MACHINE_TITLE: &str = "invalid machine";
const MAX_STATES: usize = 256;

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

/// A source file with its machines elaborated.
#[derive(Debug)]
pub(crate) struct Elaborated {
    pub(crate) text: String,
    original: String,
    segments: Vec<Segment>,
}

impl Elaborated {
    /// The source span an elaborated span came from.
    fn original_span(&self, start: usize, len: usize) -> (usize, usize) {
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
        &self.original
    }
}

/// The text the GPU frontend reads for `source`: `source` itself unless it
/// declares a machine.
pub(crate) fn elaborate_source(path: &Path, source: String) -> Result<String, CompileError> {
    // Elaborated text names reserved identifiers; reading it again is a no-op.
    if source.contains(RESERVED_PREFIX)
        && registry().lock().is_ok_and(|registry| registry.contains_key(&blake3::hash(source.as_bytes())))
    {
        return Ok(source);
    }
    match elaborate(path, &source)? {
        None => Ok(source),
        Some(elaborated) => {
            let text = elaborated.text.clone();
            if let Ok(mut registry) = registry().lock() {
                registry.insert(blake3::hash(text.as_bytes()), Arc::new(elaborated));
            }
            Ok(text)
        }
    }
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

struct State {
    name: Token,
    is_final: bool,
    /// The data fields: (name, type span).
    fields: Vec<(Token, (usize, usize))>,
    /// Token indices of the arm block's `{` and `}`.
    open: usize,
    close: usize,
}

struct Machine {
    public: bool,
    /// Token index of the first token (`pub` or `machine`) and of the body's `}`.
    first: usize,
    close: usize,
    name: Token,
    event: (usize, usize),
    output: Option<(usize, usize)>,
    fields: Vec<(Token, (usize, usize))>,
    start: Token,
    states: Vec<State>,
}

struct Elaborator<'a> {
    path: &'a Path,
    source: &'a str,
    tokens: Vec<Token>,
    /// The index of each opening delimiter's closing one, and back.
    partner: Vec<usize>,
    out: String,
    segments: Vec<Segment>,
    /// The variants of each enum declared at the top level of this file.
    enums: HashMap<String, Vec<String>>,
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
    /// `;`, `)`, `{` or `->` outside its own `<>`, `()` and `[]`.
    fn type_end(&self, mut token: usize, limit: usize) -> usize {
        let mut angles = 0usize;
        while token < limit {
            let text = self.text(token);
            match text {
                "(" | "[" => token = self.partner[token],
                "<" => angles += 1,
                ">" if angles > 0 => angles -= 1,
                "," | ";" | ")" | "{" | "->" if angles == 0 => return token,
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

    fn parse(&self, first: usize, public: bool) -> Result<Machine, CompileError> {
        let at = if public { first + 1 } else { first };
        let name = self.expect_ident(at + 1, "the machine's name")?;
        self.expect(at + 2, "on")?;
        let mut token = at + 3;
        let event_end = self.type_end(token, self.tokens.len());
        if event_end == token {
            return Err(self.fail(token, "expected the event type here"));
        }
        let event = self.span(token, event_end);
        token = event_end;
        let mut output = None;
        if self.is(token, "->") {
            let output_end = self.type_end(token + 1, self.tokens.len());
            if output_end == token + 1 {
                return Err(self.fail(token + 1, "expected the output type here"));
            }
            let unit = output_end == token + 3 && self.is(token + 1, "(") && self.is(token + 2, ")");
            if !unit {
                output = Some(self.span(token + 1, output_end));
            }
            token = output_end;
        }
        self.expect(token, "{")?;
        let close = self.partner[token];
        token += 1;
        let mut fields = Vec::new();
        let mut start = None;
        let mut states = Vec::new();
        while token < close {
            if self.is(token, "start") && !self.is(token + 1, ":") {
                if start.is_some() {
                    return Err(self.fail(token, "a machine has one `start`"));
                }
                start = Some(self.expect_ident(token + 1, "the start state")?);
                self.expect(token + 2, ";")?;
                token += 3;
            } else if (self.is(token, "state") || self.is(token, "final")) && !self.is(token + 1, ":") {
                let is_final = self.is(token, "final");
                if is_final {
                    token += 1;
                    self.expect(token, "state")?;
                }
                let state_name = self.expect_ident(token + 1, "the state's name")?;
                token += 2;
                let mut data = Vec::new();
                if self.is(token, "(") {
                    let end = self.partner[token];
                    data = self.fields(token + 1, end)?;
                    token = end + 1;
                }
                self.expect(token, "{")?;
                let open = token;
                token = self.partner[open] + 1;
                states.push(State { name: state_name, is_final, fields: data, open, close: token - 1 });
            } else if self.ident(token) && self.is(token + 1, ":") {
                if start.is_some() || !states.is_empty() {
                    return Err(self.fail(token, "machine fields come before `start` and the states"));
                }
                let name = self.tokens[token];
                let end = self.type_end(token + 2, close);
                if end == token + 2 {
                    return Err(self.fail(token + 2, "expected a type here"));
                }
                fields.push((name, self.span(token + 2, end)));
                token = end;
                self.expect(token, ",")?;
                token += 1;
            } else {
                return Err(self.fail(token, "expected a field, `start` or a state here"));
            }
        }
        let start = start.ok_or_else(|| self.fail(at, "this machine has no `start` state"))?;
        Ok(Machine { public, first, close, name, event, output, fields, start, states })
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

    /// Records the variant names of the file's top-level enums.
    fn collect_enums(&mut self) {
        let mut depth = 0usize;
        let mut token = 0;
        while token < self.tokens.len() {
            if self.tokens[token].kind == Kind::Punct {
                match self.text(token) {
                    "(" | "[" | "{" => depth += 1,
                    ")" | "]" | "}" => depth = depth.saturating_sub(1),
                    _ => {}
                }
            }
            if depth == 0 && self.is(token, "enum") && self.ident(token + 1) {
                let mut open = token + 2;
                while open < self.tokens.len() && !self.is(open, "{") && !self.is(open, ";") {
                    open += 1;
                }
                if self.is(open, "{") {
                    let close = self.partner[open];
                    let mut variants = Vec::new();
                    let mut variant = open + 1;
                    while variant < close {
                        if self.ident(variant) {
                            variants.push(self.text(variant).to_string());
                        }
                        variant += 1;
                        if self.is(variant, "(") {
                            variant = self.partner[variant] + 1;
                        }
                        if self.is(variant, ",") {
                            variant += 1;
                        }
                    }
                    self.enums.insert(self.text(token + 1).to_string(), variants);
                    token = close + 1;
                    continue;
                }
            }
            token += 1;
        }
    }

    /// The event variant an arm's pattern `[first, arrow)` handles in full:
    /// `E::V`, `V`, or either with `_` or bindings as payload patterns. A
    /// payload pattern that is not a lower-case binding or `_` may refuse
    /// some values, so the arm does not cover its variant.
    fn covered_variant(&self, first: usize, arrow: usize) -> Option<&'a str> {
        let mut head = first;
        while head + 2 < arrow && self.ident(head) && self.is(head + 1, "::") {
            head += 2;
        }
        if !self.ident(head) {
            return None;
        }
        let variant = self.text(head);
        let after = head + 1;
        if after == arrow {
            return Some(variant);
        }
        if !self.is(after, "(") || self.partner[after] + 1 != arrow {
            return None;
        }
        let mut token = after + 1;
        while token < self.partner[after] {
            let irrefutable = self.ident(token)
                && self.text(token).starts_with(|c: char| c == '_' || c.is_ascii_lowercase());
            if !irrefutable || !(self.is(token + 1, ",") || token + 1 == self.partner[after]) {
                return None;
            }
            token += 2;
        }
        Some(variant)
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

fn integer_type(text: &str) -> bool {
    matches!(text, "i8" | "i16" | "i32" | "i64" | "u8" | "u16" | "u32" | "u64" | "isize" | "usize")
}

/// Elaborates `source`'s machines; `None` when it declares none.
fn elaborate(path: &Path, source: &str) -> Result<Option<Elaborated>, CompileError> {
    if !source.contains("machine") && !source.contains(RESERVED_PREFIX) {
        return Ok(None);
    }
    let tokens = tokenize(path, source)?;
    let mut elaborator = Elaborator {
        path,
        source,
        tokens,
        partner: Vec::new(),
        out: String::new(),
        segments: Vec::new(),
        enums: HashMap::new(),
    };
    let e = &mut elaborator;
    for index in 0..e.tokens.len() {
        // Generic instance copies (`__lanius_inst_`) are generated text too.
        if e.ident(index) && e.text(index).starts_with(RESERVED_PREFIX) && !e.text(index).starts_with("__lanius_inst_") {
            return Err(e.fail(index, format!("identifiers starting with `{RESERVED_PREFIX}` are reserved for the compiler")));
        }
    }
    // Machines are items: find `machine Name on` at the top level.
    let mut machines = Vec::new();
    let mut depth = 0usize;
    for index in 0..e.tokens.len() {
        match e.text(index) {
            "(" | "[" | "{" if e.tokens[index].kind == Kind::Punct => depth += 1,
            ")" | "]" | "}" if e.tokens[index].kind == Kind::Punct => depth = depth.saturating_sub(1),
            "machine" if depth == 0 && e.ident(index + 1) && e.is(index + 2, "on") => {
                let public = index > 0 && e.is(index - 1, "pub");
                machines.push((if public { index - 1 } else { index }, public));
            }
            _ => {}
        }
    }
    if machines.is_empty() {
        return Ok(None);
    }
    e.pair_delimiters()?;
    e.collect_enums();
    let mut copied_until = 0;
    for (first, public) in machines {
        let machine = e.parse(first, public)?;
        e.copy(copied_until, e.tokens[machine.first].start);
        elaborate_machine(e, &machine)?;
        copied_until = e.tokens[machine.close].end;
    }
    e.copy(copied_until, source.len());
    let Elaborator { out, segments, .. } = elaborator;
    Ok(Some(Elaborated { text: out, original: source.to_string(), segments }))
}

fn elaborate_machine(e: &mut Elaborator<'_>, m: &Machine) -> Result<(), CompileError> {
    let source = e.source;
    let name = &source[m.name.start..m.name.end];
    let anchor = m.name;
    let state_type = format!("{name}State");
    let public = if m.public { "pub " } else { "" };
    let event = e.src(m.event).to_string();
    let output = m.output.map(|span| e.src(span).to_string());
    let returns = output.as_ref().map_or(String::new(), |output| format!(" -> {output}"));
    if m.states.len() > MAX_STATES {
        return Err(e.fail(m.first, format!("a machine has at most {MAX_STATES} states")));
    }
    let state_name = |state: &State| source[state.name.start..state.name.end].to_string();
    let names: Vec<String> = m.states.iter().map(state_name).collect();
    for (index, name) in names.iter().enumerate() {
        if names[..index].contains(name) {
            let token = m.states[index].name;
            return Err(error(e.path, e.source, token.start, token.end - token.start, format!("state `{name}` is declared twice")));
        }
    }
    let start_name = &source[m.start.start..m.start.end];
    let Some(start_index) = names.iter().position(|state| state == start_name) else {
        return Err(error(e.path, e.source, m.start.start, m.start.end - m.start.start, format!("no state is named `{start_name}`")));
    };
    if !m.states[start_index].fields.is_empty() {
        return Err(error(e.path, e.source, m.start.start, m.start.end - m.start.start, "the start state takes no data, so construction never chooses a state"));
    }

    // enum MState { A, B(T, U) }
    e.emit(&format!("{public}enum {state_type} {{ "), anchor);
    for (index, state) in m.states.iter().enumerate() {
        e.copy(state.name.start, state.name.end);
        if !state.fields.is_empty() {
            e.emit("(", state.name);
            for (field, (_, ty)) in state.fields.iter().enumerate() {
                if field > 0 {
                    e.emit(", ", state.name);
                }
                e.copy(ty.0, ty.1);
            }
            e.emit(")", state.name);
        }
        e.emit(if index + 1 < m.states.len() { ", " } else { " " }, state.name);
    }
    e.emit("}\n", anchor);

    // struct M { fields, __lanius_state: MState }
    e.emit(&format!("{public}struct {name} {{ "), anchor);
    for (field, ty) in &m.fields {
        e.copy(field.start, field.end);
        e.emit(": ", *field);
        e.copy(ty.0, ty.1);
        e.emit(", ", *field);
    }
    e.emit(&format!("{RESERVED_PREFIX}state: {state_type} }}\n"), anchor);

    // fn m_start(fields) -> M
    e.emit(&format!("{public}fn {}_start(", snake_case(name)), anchor);
    for (index, (field, ty)) in m.fields.iter().enumerate() {
        if index > 0 {
            e.emit(", ", *field);
        }
        e.copy(field.start, field.end);
        e.emit(": ", *field);
        e.copy(ty.0, ty.1);
    }
    e.emit(&format!(") -> {name} {{ return {name} {{ "), anchor);
    for (field, _) in &m.fields {
        let field_name = &source[field.start..field.end];
        e.emit(&format!("{field_name}: {field_name}, "), *field);
    }
    e.emit(&format!("{RESERVED_PREFIX}state: {state_type}::"), anchor);
    e.copy(m.start.start, m.start.end);
    e.emit(" }; }\n", anchor);

    // impl M { step, state, one method per state }
    // With an output, `return match`: every arm is a returning block, so the
    // match never completes, and the block-arm check reports an arm that can.
    let match_head = if output.is_some() { "return match" } else { "match" };
    e.emit(&format!("{public}impl {name} {{\n    {public}fn step(&mut self, {RESERVED_PREFIX}event: {event}){returns} {{\n        {match_head} (self.{RESERVED_PREFIX}state) {{\n"), anchor);
    for (state, state_name) in m.states.iter().zip(&names) {
        let data: Vec<&str> = state.fields.iter().map(|(field, _)| &source[field.start..field.end]).collect();
        let pattern = if data.is_empty() { String::new() } else { format!("({})", data.join(", ")) };
        let mut arguments = data.join(", ");
        if !arguments.is_empty() {
            arguments.push_str(", ");
        }
        let call = format!("self.{RESERVED_PREFIX}in_{state_name}({arguments}{RESERVED_PREFIX}event)");
        let body = if output.is_some() { format!("return {call};") } else { format!("{call}; return;") };
        e.emit(&format!("            {state_type}::{state_name}{pattern} -> {{ {body} }},\n"), state.name);
    }
    e.emit(&format!("        }};\n    }}\n    {public}fn state(&self) -> {state_type} {{ return self.{RESERVED_PREFIX}state; }}\n"), anchor);

    let event_is_integer = integer_type(event.trim());
    let variants = if event_is_integer {
        None
    } else {
        match e.enums.get(event.trim()) {
            Some(variants) => Some(variants.clone()),
            None => return Err(error(e.path, source, m.event.0, m.event.1 - m.event.0,
                "a machine's event type is an integer type or an enum declared in the machine's file")),
        }
    };
    let mut edges: Vec<Vec<usize>> = vec![Vec::new(); m.states.len()];
    for (index, state) in m.states.iter().enumerate() {
        e.emit(&format!("    fn {RESERVED_PREFIX}in_{}(&mut self, ", names[index]), state.name);
        for (field, ty) in &state.fields {
            e.copy(field.start, field.end);
            e.emit(": ", *field);
            e.copy(ty.0, ty.1);
            e.emit(", ", *field);
        }
        e.emit(&format!("{RESERVED_PREFIX}event: {event}){returns} {{\n        {match_head} ({RESERVED_PREFIX}event) {{"), state.name);
        let mut ctx = Arms {
            machine: m,
            state_type: &state_type,
            names: &names,
            current: index,
            edges: &mut edges[index],
            event_is_integer,
            event_text: event.trim(),
            covered: Vec::new(),
            last_catch_all: false,
            run: false,
        };
        elaborate_arms(e, &mut ctx, state)?;
        // R3: every event is handled.
        if let Some(variants) = &variants {
            if let Some(missing) = variants.iter().find(|variant| !ctx.covered.iter().any(|covered| covered == *variant)) {
                let event = event.trim();
                return Err(CompileError::Diagnostic(
                    Diagnostic::error(MACHINE_CODE, MACHINE_TITLE)
                        .with_primary_label(diagnostic_label_from_source_span(e.path, source, state.name.start,
                            state.name.end - state.name.start,
                            format!("state `{}` does not handle `{event}::{missing}`", names[index])))
                        .with_help(format!("add an arm, e.g. `{event}::{missing} -> stay{}`",
                            if m.output.is_some() { " with ..." } else { "" })),
                ));
            }
        } else if !ctx.last_catch_all {
            return Err(error(e.path, source, state.name.start, state.name.end - state.name.start, format!(
                "state `{}` must end with a `_` or binding arm, since its events are integers", names[index]
            )));
        }
        e.emit("};\n    }\n", state.name);
    }
    if output.is_none() {
        elaborate_run(e, m, &state_type, &names, event.trim(), public, event_is_integer)?;
    }
    e.emit("}\n", anchor);
    check_graph(e, m, &names, start_index, &edges)
}

/// `run(events, count)` feeds `events[0..count)` through the machine
/// (docs/state-machines-design.md, M3 decisions): one loop per state, with
/// the state's data in locals. A transition to the same state continues its
/// loop; one to another state stores the state and returns to the dispatch.
/// Only a machine without an output has `run`, which would drop the outputs.
fn elaborate_run(e: &mut Elaborator<'_>, m: &Machine, state_type: &str, names: &[String], event: &str, public: &str,
    event_is_integer: bool) -> Result<(), CompileError> {
    let source = e.source;
    let anchor = m.name;
    let r = RESERVED_PREFIX;
    e.emit(&format!("    {public}fn run(&mut self, {r}events: [{event}], {r}count: i32) {{\n        let {r}at: i32 = 0;\n        while ({r}at < {r}count) {{\n            {r}at = match (self.{r}state) {{\n"), anchor);
    for (state, state_name) in m.states.iter().zip(names) {
        let data: Vec<&str> = state.fields.iter().map(|(field, _)| &source[field.start..field.end]).collect();
        let pattern = if data.is_empty() { String::new() } else { format!("({})", data.join(", ")) };
        let mut arguments = data.join(", ");
        if !arguments.is_empty() {
            arguments.push_str(", ");
        }
        e.emit(&format!("                {state_type}::{state_name}{pattern} -> self.{r}run_{state_name}({arguments}{r}events, {r}at, {r}count),\n"), state.name);
    }
    e.emit("            };\n        }\n    }\n", anchor);
    for (index, state) in m.states.iter().enumerate() {
        e.emit(&format!("    fn {r}run_{}(&mut self, ", names[index]), state.name);
        for (k, (field, ty)) in state.fields.iter().enumerate() {
            e.emit(&format!("{r}data_{k}: "), *field);
            e.copy(ty.0, ty.1);
            e.emit(", ", *field);
        }
        e.emit(&format!("{r}events: [{event}], {r}from: i32, {r}count: i32) -> i32 {{\n"), state.name);
        for (k, (field, ty)) in state.fields.iter().enumerate() {
            e.emit("        let ", *field);
            e.copy(field.start, field.end);
            e.emit(": ", *field);
            e.copy(ty.0, ty.1);
            e.emit(&format!(" = {r}data_{k};\n"), *field);
        }
        e.emit(&format!("        let {r}at: i32 = {r}from;\n        while ({r}at < {r}count) {{\n            let {r}event: {event} = {r}events[{r}at];\n            {r}at += 1;\n            match ({r}event) {{"), state.name);
        let mut edges = Vec::new();
        let mut ctx = Arms {
            machine: m,
            state_type,
            names,
            current: index,
            edges: &mut edges,
            event_is_integer,
            event_text: event,
            covered: Vec::new(),
            last_catch_all: false,
            run: true,
        };
        elaborate_arms(e, &mut ctx, state)?;
        let data: Vec<&str> = state.fields.iter().map(|(field, _)| &source[field.start..field.end]).collect();
        let payload = if data.is_empty() { String::new() } else { format!("({})", data.join(", ")) };
        e.emit(&format!("}};\n        }}\n        self.{r}state = {state_type}::{}{payload};\n        return {r}at;\n    }}\n", names[index]), state.name);
    }
    Ok(())
}

/// The token ranges `[start, end)` of the comma-separated arguments between
/// the `(` at `open` and its partner.
fn arguments(e: &Elaborator<'_>, open: usize) -> Vec<(usize, usize)> {
    let close = e.partner[open];
    let mut out = Vec::new();
    let mut start = open + 1;
    let mut token = open + 1;
    while token < close {
        if e.tokens[token].kind == Kind::Punct && matches!(e.text(token), "(" | "[" | "{") {
            token = e.partner[token] + 1;
            continue;
        }
        if e.is(token, ",") {
            out.push((start, token));
            start = token + 1;
        }
        token += 1;
    }
    if start < close {
        out.push((start, close));
    }
    out
}

struct Arms<'m, 'e> {
    machine: &'m Machine,
    state_type: &'m str,
    names: &'m [String],
    current: usize,
    edges: &'e mut Vec<usize>,
    event_is_integer: bool,
    event_text: &'m str,
    /// The event variants this state's arms handle in full.
    covered: Vec<String>,
    /// Whether the last arm is `_` or a binding (for integer events).
    last_catch_all: bool,
    /// Elaborating `run`'s loop for this state, not `step`'s handler: a
    /// transition to this state continues the loop, one to another state
    /// stores it and returns the position.
    run: bool,
}

/// The token after the arm that starts at `token` in a state block ending at
/// `close`: a block arm ends after its `}`, a transition arm at the next `,`
/// outside delimiters.
fn arm_end(e: &Elaborator<'_>, mut token: usize, close: usize) -> usize {
    while token < close {
        match e.text(token) {
            "(" | "[" | "{" if e.tokens[token].kind == Kind::Punct => token = e.partner[token],
            "," => return token,
            _ => {}
        }
        token += 1;
    }
    close
}

fn elaborate_arms(e: &mut Elaborator<'_>, ctx: &mut Arms<'_, '_>, state: &State) -> Result<(), CompileError> {
    let mut token = state.open + 1;
    while token < state.close {
        let end = arm_end(e, token, state.close);
        let mut arrow = token;
        while arrow < end && !e.is(arrow, "->") {
            if e.tokens[arrow].kind == Kind::Punct && matches!(e.text(arrow), "(" | "[" | "{") {
                arrow = e.partner[arrow];
            }
            arrow += 1;
        }
        if arrow >= end || arrow == token {
            return Err(e.fail(token, "expected an arm `pattern -> transition` here"));
        }
        if arrow == token + 1 && e.is(token, "_") && !ctx.event_is_integer {
            return Err(e.fail(token, format!(
                "state `{}` handles the remaining events with `_`; list each event, so adding one makes every state decide what it does",
                ctx.names[ctx.current]
            )));
        }
        if let Some(variant) = e.covered_variant(token, arrow) {
            ctx.covered.push(variant.to_string());
        }
        ctx.last_catch_all = arrow == token + 1 && e.ident(token)
            && e.text(token).starts_with(|c: char| c == '_' || c.is_ascii_lowercase());
        // Lanius patterns do not bind a whole value, so an integer event's
        // binding arm `c -> ...` is `_ -> { let c: E = event; ... }`.
        let binding = (ctx.last_catch_all && e.text(token) != "_").then(|| e.tokens[token]);
        e.emit("\n            ", e.tokens[token]);
        let event_text = ctx.event_text;
        let bind = |e: &mut Elaborator<'_>| {
            if let Some(name) = binding {
                e.emit(" let ", name);
                e.copy(name.start, name.end);
                e.emit(&format!(": {event_text} = {RESERVED_PREFIX}event;"), name);
            }
        };
        if binding.is_some() {
            e.emit("_ ", e.tokens[token]);
            e.copy(e.tokens[arrow].start, e.tokens[arrow].end);
        } else {
            e.copy(e.tokens[token].start, e.tokens[arrow].end);
        }
        e.emit(" ", e.tokens[arrow]);
        let body = arrow + 1;
        if e.is(body, "{") {
            let block_close = e.partner[body];
            if block_close + 1 != end {
                return Err(e.fail(block_close + 1, "expected `,` after this block arm"));
            }
            e.copy(e.tokens[body].start, e.tokens[body].end);
            bind(e);
            elaborate_block(e, ctx, body, block_close)?;
        } else if e.is(body, "goto") || e.is(body, "stay") {
            e.emit("{", e.tokens[body]);
            bind(e);
            e.emit(" ", e.tokens[body]);
            let after = transition(e, ctx, body, end)?;
            if after != end {
                return Err(e.fail(after, "expected `,` after this transition"));
            }
            e.emit(" }", e.tokens[body]);
        } else {
            return Err(e.fail(body, "a machine arm ends in a transition: `goto State` or `stay`, or a block whose every path does"));
        }
        e.emit(",", e.tokens[arrow]);
        token = if end < state.close { end + 1 } else { end };
    }
    e.emit("\n        ", state.name);
    Ok(())
}

/// Copies a block arm `{ ... }`, rewriting its `goto` and `stay` statements.
fn elaborate_block(e: &mut Elaborator<'_>, ctx: &mut Arms<'_, '_>, open: usize, close: usize) -> Result<(), CompileError> {
    let mut copied_until = e.tokens[open].end;
    let mut token = open + 1;
    while token < close {
        if e.is(token, "return") {
            return Err(e.fail(token, "a machine arm leaves through `goto` or `stay`, not `return`"));
        }
        if e.is(token, "goto") || e.is(token, "stay") {
            e.copy(copied_until, e.tokens[token].start);
            // A transition statement ends at the `;` before the end of its
            // enclosing block.
            let mut end = token;
            while end < close && !e.is(end, ";") {
                if e.tokens[end].kind == Kind::Punct && matches!(e.text(end), "(" | "[" | "{") {
                    end = e.partner[end];
                }
                if e.tokens[end].kind == Kind::Punct && e.text(end) == "}" {
                    break;
                }
                end += 1;
            }
            if !e.is(end, ";") {
                return Err(e.fail(token, "expected `;` after this transition"));
            }
            // Plain statements, not a nested block: the returns pass carries
            // a return out of the arm's own block and its `if` arms.
            let after = transition(e, ctx, token, end)?;
            if after != end {
                return Err(e.fail(after, "expected `;` after this transition"));
            }
            copied_until = e.tokens[end].end;
            token = end + 1;
            continue;
        }
        token += 1;
    }
    e.copy(copied_until, e.tokens[close].end);
    Ok(())
}

/// Elaborates `goto S(args) with out` or `stay with out` from `token` up to
/// `end` (exclusive); returns the token after the transition.
fn transition(e: &mut Elaborator<'_>, ctx: &mut Arms<'_, '_>, token: usize, end: usize) -> Result<usize, CompileError> {
    let keyword = e.tokens[token];
    let mut next = token + 1;
    if ctx.run {
        return run_transition(e, ctx, token);
    }
    if e.is(token, "goto") {
        let target = e.expect_ident(next, "the next state")?;
        let source = e.source;
        let target_name = &source[target.start..target.end];
        let Some(target_index) = ctx.names.iter().position(|state| state == target_name) else {
            return Err(e.fail(next, format!("no state is named `{target_name}`")));
        };
        ctx.edges.push(target_index);
        e.emit(&format!("self.{RESERVED_PREFIX}state = {}::", ctx.state_type), keyword);
        e.copy(target.start, target.end);
        next += 1;
        if e.is(next, "(") {
            let close = e.partner[next];
            e.copy(e.tokens[next].start, e.tokens[close].end);
            next = close + 1;
        }
        e.emit("; ", keyword);
    }
    let has_output = ctx.machine.output.is_some();
    if e.is(next, "with") {
        if !has_output {
            return Err(e.fail(next, "this machine has no output, so its transitions take no `with`"));
        }
        if next + 1 >= end {
            return Err(e.fail(next, "expected the output after `with`"));
        }
        e.emit("return ", e.tokens[next]);
        e.copy(e.tokens[next + 1].start, e.tokens[end - 1].end);
        e.emit(";", e.tokens[next]);
        return Ok(end);
    }
    if has_output {
        return Err(e.fail(token, "this machine has an output: end the transition with `with value`"));
    }
    e.emit("return;", keyword);
    Ok(next)
}

/// A transition in `run`'s loop for the current state: `stay` and `goto` the
/// same state continue the loop (assigning the data locals), `goto` another
/// state stores it and returns the position. Returns the token after it.
fn run_transition(e: &mut Elaborator<'_>, ctx: &mut Arms<'_, '_>, token: usize) -> Result<usize, CompileError> {
    let keyword = e.tokens[token];
    let r = RESERVED_PREFIX;
    if !e.is(token, "goto") {
        e.emit("continue;", keyword);
        return Ok(token + 1);
    }
    let mut next = token + 1;
    let target = e.expect_ident(next, "the next state")?;
    let source = e.source;
    let target_name = &source[target.start..target.end];
    let Some(target_index) = ctx.names.iter().position(|state| state == target_name) else {
        return Err(e.fail(next, format!("no state is named `{target_name}`")));
    };
    next += 1;
    let args = if e.is(next, "(") { Some(next) } else { None };
    if target_index != ctx.current {
        e.emit(&format!("self.{r}state = {}::", ctx.state_type), keyword);
        e.copy(target.start, target.end);
        if let Some(open) = args {
            let close = e.partner[open];
            e.copy(e.tokens[open].start, e.tokens[close].end);
            next = close + 1;
        }
        e.emit(&format!("; return {r}at;"), keyword);
        return Ok(next);
    }
    let fields = &ctx.machine.states[ctx.current].fields;
    if let Some(open) = args {
        let values = arguments(e, open);
        if values.len() != fields.len() {
            return Err(e.fail(open, format!("state `{target_name}` takes {} values", fields.len())));
        }
        // Each value is computed from the old data before any is assigned.
        let single = values.len() == 1;
        for (k, &(start, end)) in values.iter().enumerate() {
            if single {
                e.copy(fields[k].0.start, fields[k].0.end);
                e.emit(" = ", keyword);
            } else {
                e.emit(&format!("let {r}next_{k}: "), keyword);
                e.copy(fields[k].1.0, fields[k].1.1);
                e.emit(" = ", keyword);
            }
            e.copy(e.tokens[start].start, e.tokens[end - 1].end);
            e.emit("; ", keyword);
        }
        if !single {
            for k in 0..values.len() {
                e.copy(fields[k].0.start, fields[k].0.end);
                e.emit(&format!(" = {r}next_{k}; "), keyword);
            }
        }
        next = e.partner[open] + 1;
    }
    e.emit("continue;", keyword);
    Ok(next)
}

/// R4: every state is reachable from `start`, a state with no `goto` to
/// another state is `final`, and a `final` state has none.
fn check_graph(e: &Elaborator<'_>, m: &Machine, names: &[String], start: usize, edges: &[Vec<usize>]) -> Result<(), CompileError> {
    let mut reached = vec![false; names.len()];
    let mut pending = vec![start];
    reached[start] = true;
    while let Some(state) = pending.pop() {
        for &next in &edges[state] {
            if !reached[next] {
                reached[next] = true;
                pending.push(next);
            }
        }
    }
    for (index, state) in m.states.iter().enumerate() {
        let token = state.name;
        let len = token.end - token.start;
        if !reached[index] {
            return Err(error(e.path, e.source, token.start, len, format!(
                "state `{}` is unreachable from `start {}`", names[index], names[start]
            )));
        }
        let leaves = edges[index].iter().any(|&next| next != index);
        if !leaves && !state.is_final {
            return Err(CompileError::Diagnostic(
                Diagnostic::error(MACHINE_CODE, MACHINE_TITLE)
                    .with_primary_label(diagnostic_label_from_source_span(e.path, e.source, token.start, len,
                        format!("state `{}` has no `goto` to another state", names[index])))
                    .with_help(format!("mark it `final state {}` if the machine is meant to stop here", names[index])),
            ));
        }
        if leaves && state.is_final {
            return Err(error(e.path, e.source, token.start, len, format!(
                "`final` state `{}` has a `goto` to another state", names[index]
            )));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn elaborated(source: &str) -> String {
        elaborate(Path::new("door.lani"), source).unwrap().unwrap().text
    }

    fn rejected(source: &str) -> String {
        match elaborate(Path::new("door.lani"), source) {
            Err(CompileError::Diagnostic(diagnostic)) => format!("{diagnostic:?}"),
            other => panic!("expected a machine diagnostic, got {other:?}"),
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

    #[test]
    fn a_machine_elaborates_to_an_enum_a_struct_a_constructor_and_an_impl() {
        let text = elaborated(DOOR);
        assert!(text.starts_with("enum Input { Open, Close }\npub enum DoorState { Opened, Closed }\npub struct Door { opens: i32, __lanius_state: DoorState }\n"), "{text}");
        assert!(text.contains("pub fn door_start(opens: i32) -> Door { return Door { opens: opens, __lanius_state: DoorState::Closed }; }"), "{text}");
        assert!(text.contains("DoorState::Opened -> { return self.__lanius_in_Opened(__lanius_event); },"), "{text}");
        assert!(text.contains("Input::Close -> { self.__lanius_state = DoorState::Closed; return Reply::Done; },"), "{text}");
        assert!(text.contains("Input::Open -> { return Reply::Ignored; },"), "{text}");
        assert!(text.contains("Input::Open -> { self.opens += 1; self.__lanius_state = DoorState::Opened; return Reply::Done; },"), "{text}");
        assert!(text.contains("return match (self.__lanius_state) {"), "{text}");
    }

    #[test]
    fn run_has_one_loop_per_state() {
        let text = elaborated("enum Op { Push(i32), Drop }
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
");
        assert!(text.contains("fn run(&mut self, __lanius_events: [Op], __lanius_count: i32) {"), "{text}");
        assert!(text.contains("PairState::Holding(first, second) -> self.__lanius_run_Holding(first, second, __lanius_events, __lanius_at, __lanius_count),"), "{text}");
        // A transition to the same state continues its loop, reading the
        // old data before assigning the new.
        assert!(text.contains("Op::Push(x) -> { let __lanius_next_0: i32 = x; let __lanius_next_1: i32 = first; first = __lanius_next_0; second = __lanius_next_1; continue; },"), "{text}");
        assert!(text.contains("Op::Drop -> { continue; },"), "{text}");
        // One to another state stores it and returns the position.
        assert!(text.contains("Op::Drop -> { self.__lanius_state = PairState::Empty; return __lanius_at; },"), "{text}");
        assert!(text.contains("self.__lanius_state = PairState::Holding(first, second);\n        return __lanius_at;"), "{text}");
    }

    #[test]
    fn diagnostics_map_back_to_the_machine() {
        let elaborated = elaborate(Path::new("door.lani"), DOOR).unwrap().unwrap();
        let copied = elaborated.text.find("Reply::Done").unwrap();
        let (start, len) = elaborated.original_span(copied, 11);
        assert_eq!(&DOOR[start..start + len], "Reply::Done");
        let generated = elaborated.text.find("__lanius_state = DoorState::Closed").unwrap();
        let (start, len) = elaborated.original_span(generated, 5);
        assert_eq!(&DOOR[start..start + len], "goto");
    }

    #[test]
    fn files_without_machines_are_unchanged() {
        assert!(elaborate(Path::new("a.lani"), "fn machine() -> i32 { return 1; }").unwrap().is_none());
    }

    #[test]
    fn the_rules_reject_their_violations() {
        assert!(rejected("fn f() { let __lanius_state: i32 = 1; }").contains("reserved"));
        assert!(rejected(&DOOR.replace("stay with Reply::Ignored,\n    }\n    state Closed", "{ return Reply::Done; },\n    }\n    state Closed")).contains("not `return`"));
        assert!(rejected(&DOOR.replace("Input::Open -> stay", "_ -> stay")).contains("list each event"));
        assert!(rejected(&DOOR.replace("goto Closed with", "stay with")).contains("no `goto` to another state"));
        assert!(rejected(&DOOR.replace("goto Opened with", "stay with")).contains("unreachable"));
        assert!(rejected(&DOOR.replace("stay with Reply::Ignored,\n    }\n    state Closed", "stay,\n    }\n    state Closed")).contains("`with value`"));
        assert!(rejected(&DOOR.replace("goto Closed with", "goto Shut with")).contains("no state is named `Shut`"));
        assert!(rejected(&DOOR.replace("        Input::Close -> stay with Reply::Ignored,\n", "")).contains("does not handle `Input::Close`"));
        assert!(rejected(&DOOR.replace("enum Input", "enum Other")).contains("declared in the machine's file"));
    }

    #[test]
    fn integer_events_may_end_with_a_binding_arm() {
        let text = elaborated("machine Sum on u8 {
    total: i64,
    start Between;
    state Between {
        c -> { if (c == 48u8) { goto Zero; } stay; },
    }
    final state Zero {
        _ -> stay,
    }
}
");
        assert!(rejected("machine M on u8 {\n    start S;\n    final state S { 0 -> stay, }\n}\n").contains("binding arm"));
        assert!(text.contains("fn step(&mut self, __lanius_event: u8) {"), "{text}");
        assert!(text.contains("_ -> { return; },"), "{text}");
        assert!(text.contains("_ -> { let c: u8 = __lanius_event; if (c == 48u8) { self.__lanius_state = SumState::Zero; return; } return; },"), "{text}");
    }

    #[test]
    fn snake_case_splits_words() {
        assert_eq!(snake_case("Door"), "door");
        assert_eq!(snake_case("TlsSession"), "tls_session");
        assert_eq!(snake_case("HTTPServer"), "http_server");
    }
}
