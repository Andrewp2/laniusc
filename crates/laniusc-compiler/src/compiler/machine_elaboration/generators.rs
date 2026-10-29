//! `gen fn` (docs/state-machines-design.md, phase M5): a function that
//! suspends at each `yield` is sugar for a `machine`.
//!
//! `gen fn name(params) -> T { body }` elaborates, before machines do, to
//!
//! ```text
//! enum NameResume { Next }
//! machine Name on NameResume -> core::option::Option<T> {
//!     params...,                       // fields, read-only in the body
//!     start Start;
//!     state Start { NameResume::Next -> { body from the top } }
//!     state YieldK(locals in scope at the k-th yield) { NameResume::Next -> { body after it } }
//!     final state Done { NameResume::Next -> stay with core::option::None() }
//! }
//! fn name(params) -> Name { return name_start(params); }
//! impl Name { fn next(&mut self) -> core::option::Option<T> { return self.step(NameResume::Next); } }
//! ```
//!
//! In every arm `yield v;` is `goto YieldK(locals) with core::option::Some(v);`
//! and the end of the body, or `return;`, is `goto Done with
//! core::option::None();`. The arm of `YieldK` declares the locals from the
//! state's data, runs the rest of the yield's block, and then the rest of each
//! enclosing statement outward: a `while` around the yield runs again in
//! full. So each state's code is a copy of the body from its point to the
//! next yield, and the machine rules (R2-R5) and proofs apply unchanged.
//!
//! The subset, checked here: every local is declared once with a type
//! (`let x: T = e;`), parameters are not assigned, `return` has no value,
//! and a loop that contains a `yield` is a `while` with no `break` or
//! `continue` of its own (the rest of its body after a yield runs outside the
//! loop). `yield` and `return` are not allowed inside a `match` or a `for`.

use super::*;

const GEN_PREFIX: &str = "__lanius_gen_";

/// A statement of a generator body, by token indices.
enum Stmt {
    /// `let name: type = value;`: tokens `[first, end)`.
    Let { first: usize, end: usize, name: usize, ty: (usize, usize) },
    /// `if (cond) { then } else ...`; `cond` is the `(`.
    If { first: usize, cond: usize, then: Vec<Stmt>, otherwise: Option<Vec<Stmt>> },
    /// `while (cond) { body }`.
    While { first: usize, cond: usize, body: Vec<Stmt> },
    /// `yield value;`, the k-th of the body in source order.
    Yield { first: usize, value: (usize, usize), index: usize },
    /// `return;`
    Return { first: usize },
    /// Any other statement, copied: tokens `[first, end)`.
    Other { first: usize, end: usize },
}

struct Generator {
    public: bool,
    first: usize,
    close: usize,
    name: Token,
    params: Vec<(Token, (usize, usize))>,
    output: (usize, usize),
    body: Vec<Stmt>,
}

/// The token after the statement that starts at `token`: after its `;`, at
/// depth 0, before `close`.
fn statement_end(e: &Elaborator<'_>, mut token: usize, close: usize) -> Result<usize, CompileError> {
    let first = token;
    while token < close {
        if e.tokens[token].kind == Kind::Punct && matches!(e.text(token), "(" | "[" | "{") {
            token = e.partner[token] + 1;
            continue;
        }
        if e.is(token, ";") {
            return Ok(token + 1);
        }
        token += 1;
    }
    Err(e.fail(first, "expected `;` at the end of this statement"))
}

fn contains(e: &Elaborator<'_>, first: usize, end: usize, words: &[&str]) -> Option<usize> {
    (first..end).find(|&token| e.ident(token) && words.contains(&e.text(token)))
}

struct Parser<'g> {
    yields: usize,
    locals: Vec<&'g str>,
}

impl<'g> Parser<'g> {
    /// The statements of the block whose `{` is at `open`.
    fn block(&mut self, e: &Elaborator<'g>, open: usize) -> Result<Vec<Stmt>, CompileError> {
        let close = e.partner[open];
        let mut token = open + 1;
        let mut out = Vec::new();
        while token < close {
            let (stmt, next) = self.statement(e, token, close)?;
            out.push(stmt);
            token = next;
        }
        Ok(out)
    }

    fn statement(&mut self, e: &Elaborator<'g>, token: usize, close: usize) -> Result<(Stmt, usize), CompileError> {
        if e.is(token, "let") {
            let name = e.expect_ident(token + 1, "a local's name")?;
            if !e.is(token + 2, ":") {
                return Err(e.fail(token + 2, "a generator's locals declare their type: `let name: Type = value;`"));
            }
            let text = &e.source[name.start..name.end];
            if self.locals.contains(&text) {
                return Err(e.fail(token + 1, format!("a generator declares each local once; `{text}` is declared again here")));
            }
            self.locals.push(text);
            let ty_end = e.type_end(token + 3, close);
            let end = statement_end(e, token, close)?;
            if let Some(word) = contains(e, token, end, &["yield", "return"]) {
                return Err(e.fail(word, "`yield` and `return` are statements of their own here"));
            }
            return Ok((Stmt::Let { first: token, end, name: token + 1, ty: (token + 3, ty_end) }, end));
        }
        if e.is(token, "if") {
            e.expect(token + 1, "(")?;
            let cond = token + 1;
            let open = e.partner[cond] + 1;
            e.expect(open, "{")?;
            let then = self.block(e, open)?;
            let mut next = e.partner[open] + 1;
            let mut otherwise = None;
            if e.is(next, "else") {
                if e.is(next + 1, "if") {
                    let (inner, after) = self.statement(e, next + 1, close)?;
                    otherwise = Some(vec![inner]);
                    next = after;
                } else {
                    e.expect(next + 1, "{")?;
                    otherwise = Some(self.block(e, next + 1)?);
                    next = e.partner[next + 1] + 1;
                }
            }
            return Ok((Stmt::If { first: token, cond, then, otherwise }, next));
        }
        if e.is(token, "while") {
            e.expect(token + 1, "(")?;
            let cond = token + 1;
            let open = e.partner[cond] + 1;
            e.expect(open, "{")?;
            let before = self.yields;
            let body = self.block(e, open)?;
            if self.yields != before {
                if let Some(exit) = loop_exit(e, &body) {
                    return Err(e.fail(exit, "a loop that yields has no `break` or `continue`: the code after a yield runs outside the loop"));
                }
            }
            return Ok((Stmt::While { first: token, cond, body }, e.partner[open] + 1));
        }
        if e.is(token, "yield") {
            let end = statement_end(e, token, close)?;
            if end == token + 2 {
                return Err(e.fail(token, "expected the value after `yield`"));
            }
            let index = self.yields;
            self.yields += 1;
            return Ok((Stmt::Yield { first: token, value: (token + 1, end - 1), index }, end));
        }
        if e.is(token, "return") {
            if !e.is(token + 1, ";") {
                return Err(e.fail(token + 1, "a generator's `return` takes no value; it ends the sequence"));
            }
            return Ok((Stmt::Return { first: token }, token + 2));
        }
        // Any other statement; a bare block or a `for` ends at its `}`.
        let end = if e.is(token, "{") {
            e.partner[token] + 1
        } else if e.is(token, "for") {
            let mut at = token + 1;
            while at < close && !e.is(at, "{") {
                at += 1;
            }
            if at >= close { return Err(e.fail(token, "expected the body of this `for`")); }
            e.partner[at] + 1
        } else {
            statement_end(e, token, close)?
        };
        if let Some(word) = contains(e, token, end, &["yield", "return"]) {
            return Err(e.fail(word, "a generator yields and returns only in its body's own statements, `if` and `while`, not inside a `match`, `for` or plain block"));
        }
        Ok((Stmt::Other { first: token, end }, end))
    }
}

/// A `break` or `continue` of the loop whose body is `stmts` (not of a loop
/// inside it).
fn loop_exit(e: &Elaborator<'_>, stmts: &[Stmt]) -> Option<usize> {
    for stmt in stmts {
        match stmt {
            Stmt::Other { first, end } => {
                if let Some(token) = (*first..*end).find(|&t| (e.is(t, "break") || e.is(t, "continue")) && !inside_loop(e, *first, t)) {
                    return Some(token);
                }
            }
            Stmt::If { then, otherwise, .. } => {
                if let Some(token) = loop_exit(e, then).or_else(|| otherwise.as_deref().and_then(|s| loop_exit(e, s))) {
                    return Some(token);
                }
            }
            _ => {}
        }
    }
    None
}

/// Whether `token` is inside a `while` or `for` body that starts in `[first, token)`.
fn inside_loop(e: &Elaborator<'_>, first: usize, token: usize) -> bool {
    (first..token).any(|t| {
        (e.is(t, "while") || e.is(t, "for")) && {
            let mut open = t + 1;
            while open < token && !e.is(open, "{") {
                if e.is(open, "(") { open = e.partner[open]; }
                open += 1;
            }
            open < token && e.partner[open] > token
        }
    })
}

/// The locals in scope at each yield, outermost first, and the path to it:
/// (statement list, index) frames from the body down to the yield.
fn yield_paths<'s>(stmts: &'s [Stmt], frames: &mut Vec<(&'s [Stmt], usize)>, out: &mut Vec<Vec<(&'s [Stmt], usize)>>) {
    for (index, stmt) in stmts.iter().enumerate() {
        frames.push((stmts, index));
        match stmt {
            Stmt::Yield { index: k, .. } => {
                if out.len() <= *k {
                    out.resize(*k + 1, Vec::new());
                }
                out[*k] = frames.clone();
            }
            Stmt::If { then, otherwise, .. } => {
                yield_paths(then, frames, out);
                if let Some(otherwise) = otherwise {
                    yield_paths(otherwise, frames, out);
                }
            }
            Stmt::While { body, .. } => yield_paths(body, frames, out),
            _ => {}
        }
        frames.pop();
    }
}

/// The locals a frame's statements declare before `index`: (name, type).
fn declared_before(stmts: &[Stmt], index: usize) -> impl Iterator<Item = (usize, (usize, usize))> + '_ {
    stmts[..index].iter().filter_map(|stmt| match stmt {
        Stmt::Let { name, ty, .. } => Some((*name, *ty)),
        _ => None,
    })
}

struct Emit<'p> {
    /// Each yield's locals in scope, as (name token, type span).
    scope: &'p [Vec<(usize, (usize, usize))>],
}

impl Emit<'_> {
    fn stmts(&self, e: &mut Elaborator<'_>, stmts: &[Stmt]) {
        for stmt in stmts {
            self.stmt(e, stmt);
        }
    }

    fn stmt(&self, e: &mut Elaborator<'_>, stmt: &Stmt) {
        match stmt {
            Stmt::Let { first, end, .. } | Stmt::Other { first, end } => {
                e.copy(e.tokens[*first].start, e.tokens[*end - 1].end);
                e.emit(" ", e.tokens[*end - 1]);
            }
            Stmt::Return { first } => e.emit("goto Done with core::option::None(); ", e.tokens[*first]),
            Stmt::Yield { first, value, index } => {
                let anchor = e.tokens[*first];
                let locals = &self.scope[*index];
                e.emit(&format!("goto Yield{index}{}", if locals.is_empty() { "" } else { "(" }), anchor);
                for (k, (name, _)) in locals.iter().enumerate() {
                    if k > 0 { e.emit(", ", anchor); }
                    let name = e.tokens[*name];
                    e.copy(name.start, name.end);
                }
                e.emit(&format!("{} with core::option::Some(", if locals.is_empty() { "" } else { ")" }), anchor);
                e.copy(e.tokens[value.0].start, e.tokens[value.1 - 1].end);
                e.emit("); ", anchor);
            }
            Stmt::If { first, cond, then, otherwise } => {
                let anchor = e.tokens[*first];
                e.emit("if ", anchor);
                e.copy(e.tokens[*cond].start, e.tokens[e.partner[*cond]].end);
                e.emit(" { ", anchor);
                self.stmts(e, then);
                e.emit("}", anchor);
                if let Some(otherwise) = otherwise {
                    e.emit(" else { ", anchor);
                    self.stmts(e, otherwise);
                    e.emit("}", anchor);
                }
                e.emit(" ", anchor);
            }
            Stmt::While { first, cond, body } => {
                let anchor = e.tokens[*first];
                e.emit("while ", anchor);
                e.copy(e.tokens[*cond].start, e.tokens[e.partner[*cond]].end);
                e.emit(" { ", anchor);
                self.stmts(e, body);
                e.emit("} ", anchor);
            }
        }
    }

    /// The code after the yield at the end of `frames`: from `level` out.
    fn continuation(&self, e: &mut Elaborator<'_>, frames: &[(&[Stmt], usize)], level: usize) {
        let (stmts, index) = frames[level];
        let anchor = e.tokens[first_token(&stmts[index])];
        if level > 0 {
            e.emit("{ ", anchor);
        }
        for (name, ty) in declared_before(stmts, index).collect::<Vec<_>>() {
            let name = e.tokens[name];
            e.emit("let ", name);
            e.copy(name.start, name.end);
            e.emit(": ", name);
            e.copy(e.tokens[ty.0].start, e.tokens[ty.1 - 1].end);
            e.emit(&format!(" = {GEN_PREFIX}{}; ", &e.source[name.start..name.end]), name);
        }
        if level + 1 < frames.len() {
            self.continuation(e, frames, level + 1);
            if let Stmt::While { .. } = stmts[index] {
                self.stmt(e, &stmts[index]);
            }
        }
        self.stmts(e, &stmts[index + 1..]);
        if level > 0 {
            e.emit("} ", anchor);
        }
    }
}

fn first_token(stmt: &Stmt) -> usize {
    match stmt {
        Stmt::Let { first, .. } | Stmt::If { first, .. } | Stmt::While { first, .. } | Stmt::Yield { first, .. }
        | Stmt::Return { first } | Stmt::Other { first, .. } => *first,
    }
}

fn camel_case(name: &str) -> String {
    name.split('_').filter(|part| !part.is_empty()).map(|part| {
        let mut chars = part.chars();
        chars.next().map_or(String::new(), |c| c.to_ascii_uppercase().to_string() + chars.as_str())
    }).collect()
}

fn parse<'g>(e: &Elaborator<'g>, first: usize, public: bool) -> Result<Generator, CompileError> {
    let fn_token = if public { first + 2 } else { first + 1 };
    let name = e.expect_ident(fn_token + 1, "the generator's name")?;
    e.expect(fn_token + 2, "(")?;
    let params_close = e.partner[fn_token + 2];
    let params = e.fields(fn_token + 3, params_close)?;
    if !e.is(params_close + 1, "->") {
        return Err(e.fail(params_close + 1, "a generator declares the type it yields: `gen fn name(...) -> T`"));
    }
    let output_end = e.type_end(params_close + 2, e.tokens.len());
    if output_end == params_close + 2 {
        return Err(e.fail(params_close + 2, "expected the yielded type here"));
    }
    e.expect(output_end, "{")?;
    let close = e.partner[output_end];
    let mut parser = Parser { yields: 0, locals: Vec::new() };
    for (param, _) in &params {
        parser.locals.push(&e.source[param.start..param.end]);
    }
    // Parameters are machine fields, copied into each arm: assigning one
    // would be lost at the next yield.
    for token in output_end + 1..close {
        let is_param = params.iter().any(|(param, _)| e.text(token) == &e.source[param.start..param.end]);
        let assigned = matches!(e.text(token + 1), "=" if !e.is(token + 2, "=")) || (e.is(token + 2, "=") && matches!(e.text(token + 1), "+" | "-" | "*" | "/" | "%" | "&" | "|" | "^"));
        if is_param && e.ident(token) && assigned && !e.is(token - 1, ".") && !e.is(token - 1, "let") {
            return Err(e.fail(token, "a generator's parameters are read-only; copy one into a local to change it"));
        }
    }
    let body = parser.block(e, output_end)?;
    Ok(Generator {
        public,
        first,
        close,
        name,
        params,
        output: e.span(params_close + 2, output_end),
        body,
    })
}

fn elaborate_generator(e: &mut Elaborator<'_>, g: &Generator) {
    let source = e.source;
    let fn_name = &source[g.name.start..g.name.end];
    let machine = camel_case(fn_name);
    let resume = format!("{machine}Resume");
    let public = if g.public { "pub " } else { "" };
    let output = e.src(g.output).to_string();
    let anchor = g.name;
    let mut frames = Vec::new();
    let mut paths = Vec::new();
    yield_paths(&g.body, &mut frames, &mut paths);
    let scope: Vec<Vec<(usize, (usize, usize))>> = paths.iter()
        .map(|path| path.iter().flat_map(|&(stmts, index)| declared_before(stmts, index)).collect())
        .collect();
    let emit = Emit { scope: &scope };
    let copy_params = |e: &mut Elaborator<'_>| {
        for (param, ty) in &g.params {
            e.emit("let ", *param);
            e.copy(param.start, param.end);
            e.emit(": ", *param);
            e.copy(ty.0, ty.1);
            e.emit(" = self.", *param);
            e.copy(param.start, param.end);
            e.emit("; ", *param);
        }
    };

    e.emit(&format!("{public}enum {resume} {{ Next }}\n{public}machine {machine} on {resume} -> core::option::Option<{output}> {{\n"), anchor);
    for (param, ty) in &g.params {
        e.emit("    ", *param);
        e.copy(param.start, param.end);
        e.emit(": ", *param);
        e.copy(ty.0, ty.1);
        e.emit(",\n", *param);
    }
    e.emit(&format!("    start Start;\n    state Start {{\n        {resume}::Next -> {{ "), anchor);
    copy_params(e);
    emit.stmts(e, &g.body);
    e.emit("goto Done with core::option::None(); },\n    }\n", anchor);
    for (k, path) in paths.iter().enumerate() {
        e.emit(&format!("    state Yield{k}{}", if scope[k].is_empty() { "" } else { "(" }), anchor);
        for (index, (name, ty)) in scope[k].iter().enumerate() {
            if index > 0 { e.emit(", ", anchor); }
            let name = e.tokens[*name];
            e.emit(&format!("{GEN_PREFIX}{}: ", &source[name.start..name.end]), name);
            e.copy(e.tokens[ty.0].start, e.tokens[ty.1 - 1].end);
        }
        e.emit(&format!("{} {{\n        {resume}::Next -> {{ ", if scope[k].is_empty() { "" } else { ")" }), anchor);
        copy_params(e);
        emit.continuation(e, path, 0);
        e.emit("goto Done with core::option::None(); },\n    }\n", anchor);
    }
    e.emit(&format!("    final state Done {{\n        {resume}::Next -> stay with core::option::None(),\n    }}\n}}\n"), anchor);
    let snake = snake_case(&machine);
    e.emit(&format!("{public}fn {fn_name}("), anchor);
    for (index, (param, ty)) in g.params.iter().enumerate() {
        if index > 0 { e.emit(", ", *param); }
        e.copy(param.start, param.end);
        e.emit(": ", *param);
        e.copy(ty.0, ty.1);
    }
    let names: Vec<&str> = g.params.iter().map(|(param, _)| &source[param.start..param.end]).collect();
    e.emit(&format!(") -> {machine} {{ return {snake}_start({}); }}\n", names.join(", ")), anchor);
    e.emit(&format!("{public}impl {machine} {{\n    {public}fn next(&mut self) -> core::option::Option<{output}> {{ return self.step({resume}::Next); }}\n}}\n"), anchor);
}

/// Elaborates `source`'s generators into machines; `None` when it has none.
pub(super) fn elaborate(path: &Path, source: &str) -> Result<Option<Elaborated>, CompileError> {
    // Most files have no generator; only those with `gen` and `fn` are tokenized.
    let maybe = source.match_indices("gen").any(|(at, _)| source[at + 3..].trim_start().starts_with("fn"));
    if !maybe {
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
    let mut generators = Vec::new();
    let mut depth = 0usize;
    for index in 0..e.tokens.len() {
        match e.text(index) {
            "(" | "[" | "{" if e.tokens[index].kind == Kind::Punct => depth += 1,
            ")" | "]" | "}" if e.tokens[index].kind == Kind::Punct => depth = depth.saturating_sub(1),
            "gen" if depth == 0 && e.ident(index) && e.is(index + 1, "fn") => {
                let public = index > 0 && e.is(index - 1, "pub");
                generators.push((if public { index - 1 } else { index }, public));
            }
            _ => {}
        }
    }
    if generators.is_empty() {
        return Ok(None);
    }
    for index in 0..e.tokens.len() {
        if e.ident(index) && e.text(index).starts_with(RESERVED_PREFIX) && !e.text(index).starts_with("__lanius_inst_") {
            return Err(e.fail(index, format!("identifiers starting with `{RESERVED_PREFIX}` are reserved for the compiler")));
        }
    }
    let imports_option = (0..e.tokens.len().saturating_sub(4)).any(|index| {
        e.is(index, "import") && e.is(index + 1, "core") && e.is(index + 2, "::") && e.is(index + 3, "option")
    });
    if !imports_option {
        let (first, _) = generators[0];
        return Err(e.fail(first, "a file with a `gen fn` imports `core::option`: its `next` returns `core::option::Option`"));
    }
    e.pair_delimiters()?;
    let mut copied_until = 0;
    for (first, public) in generators {
        let generator = parse(e, first, public)?;
        e.copy(copied_until, e.tokens[generator.first].start);
        elaborate_generator(e, &generator);
        copied_until = e.tokens[generator.close].end;
    }
    e.copy(copied_until, source.len());
    let Elaborator { out, segments, .. } = elaborator;
    Ok(Some(Elaborated { text: out, original: source.to_string(), segments, inner: None }))
}

#[cfg(test)]
mod tests {
    use super::*;

    const EVENS: &str = "import core::option;
gen fn evens(limit: i32) -> i32 {
    let i: i32 = 0;
    while (i < limit) {
        yield i;
        i += 2;
    }
}
";

    fn rejected(source: &str) -> String {
        match elaborate(Path::new("evens.lani"), source) {
            Err(CompileError::Diagnostic(diagnostic)) => format!("{diagnostic:?}"),
            other => panic!("expected a generator diagnostic, got {other:?}"),
        }
    }

    #[test]
    fn a_generator_is_a_machine_with_one_state_per_yield() {
        let generated = elaborate(Path::new("evens.lani"), EVENS).unwrap().unwrap();
        let text = &generated.text;
        assert!(text.contains("enum EvensResume { Next }"), "{text}");
        assert!(text.contains("machine Evens on EvensResume -> core::option::Option<i32> {"), "{text}");
        assert!(text.contains("goto Yield0(i) with core::option::Some(i);"), "{text}");
        assert!(text.contains("state Yield0(__lanius_gen_i: i32) {"), "{text}");
        assert!(text.contains("let i: i32 = __lanius_gen_i; { i += 2; } while (i < limit) {"), "{text}");
        assert!(text.contains("fn evens(limit: i32) -> Evens { return evens_start(limit); }"), "{text}");
        assert!(text.contains("fn next(&mut self) -> core::option::Option<i32> { return self.step(EvensResume::Next); }"), "{text}");
        // The machine rules accept the result.
        assert!(super::super::elaborate(Path::new("evens.lani"), text, true).unwrap().is_some());
    }

    #[test]
    fn generators_stay_in_their_subset() {
        assert!(rejected(&EVENS.replace("i += 2;", "limit = 1;")).contains("parameters are read-only"));
        assert!(rejected(&EVENS.replace("i += 2;", "i += 2; break;")).contains("no `break` or `continue`"));
        assert!(rejected(&EVENS.replace("let i: i32 = 0;", "let i = 0;")).contains("declare their type"));
        assert!(rejected(&EVENS.replace("yield i;", "{ yield i; }")).contains("not inside a `match`, `for` or plain block"));
        assert!(rejected(&EVENS.replace("import core::option;\n", "")).contains("imports `core::option`"));
    }
}
