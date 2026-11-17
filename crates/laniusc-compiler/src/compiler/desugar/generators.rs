//! The generator round of the desugaring (docs/state-machines-design.md,
//! phase M5): a function that suspends at each `yield` is sugar for a
//! `machine`, and the machine round after this one desugars that.
//!
//! `gen fn name(params) -> T { body }` becomes
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
//! The subset, checked by shaders/generators/check.slang: every local is
//! declared once with a type (`let x: T = e;`), parameters are not assigned,
//! `return` has no value, and a loop that contains a `yield` is a `while`
//! with no `break` or `continue` of its own (the rest of its body after a
//! yield runs outside the loop). `yield` and `return` are not allowed inside
//! a `match`, a `for` or a plain block.
//!
//! shaders/generators/read.slang reads each generator from the token stream.
//! Prefix sums over the tokens give each `yield` its number, its depth and
//! the locals in scope, and one thread per piece writes the pieces of the
//! machine's text, which the shared stages splice in where the generator
//! stood.

use anyhow::Result;

use super::{
    Constants,
    LastRun,
    PLAN_START,
    Round,
    RuleError,
    S_LIVE,
    SIZE_WORDS,
    constants,
    gpu::Gpu,
    last_sizes,
    machines::NO_ERROR,
    read_words,
    source_position,
};
use crate::{gpu::buffers::LaniusBuffer, lexer::tables::tokens::TokenKind};

/// The strings the kernels insert, in the order of the `GC_*` ids in
/// shaders/generators/generator_common.slang.
const CONSTANTS: [&str; 43] = [
    "",
    "pub ",
    "enum ",
    "Resume { Next }\n",
    "machine ",
    " on ",
    "Resume -> core::option::Option<",
    "> {\n",
    "    ",
    ",\n",
    "    start Start;\n    state Start {\n        ",
    "Resume::Next -> { ",
    "let ",
    " = self.",
    "; ",
    " goto Done with core::option::None(); },\n    }\n",
    "    state Yield",
    "(__lanius_gen_",
    ", __lanius_gen_",
    ") {\n        ",
    " {\n        ",
    "{ ",
    " = __lanius_gen_",
    " } ",
    "    final state Done {\n        ",
    "Resume::Next -> stay with core::option::None(),\n    }\n}\n",
    "fn ",
    "(",
    ", ",
    ") -> ",
    " { return ",
    "_start(",
    "); }\n",
    "impl ",
    " {\n    ",
    "fn next(&mut self) -> core::option::Option<",
    "> { return self.step(",
    "Resume::Next); }\n}\n",
    "goto Yield",
    ") with core::option::Some(",
    " with core::option::Some(",
    ")",
    "goto Done with core::option::None()",
];

/// The kind of a word of the constant strings that the lexer reads as a
/// machine keyword where the strings put it.
fn keyword(word: &str) -> Option<TokenKind> {
    Some(match word {
        "machine" => TokenKind::Machine,
        "on" => TokenKind::On,
        "start" => TokenKind::Start,
        "state" => TokenKind::State,
        "final" => TokenKind::Final,
        "goto" => TokenKind::Goto,
        "stay" => TokenKind::Stay,
        "with" => TokenKind::With,
        _ => return None,
    })
}

const RECORD_WORDS: usize = 7;
const DETAIL_WORDS: usize = 4;

const READ: &str = "generators/read";
const MARKS: &str = "generators/marks";
const LISTS: &str = "generators/lists";
const DIRECT: &str = "generators/direct";
const CONTEXT: &str = "generators/context";
const CHECK: &str = "generators/check";
const SCOPE: &str = "generators/scope";
const PIECES: &str = "generators/pieces";

// The plan mode and the generator layout of shaders/desugar/plan.slang.
const PLAN_PIECES: u32 = 10;
const A_TOKENS: u32 = 16;
const A_RECORD_WORDS: u32 = 17;
const A_SCAN: u32 = 18;
const A_SCAN_ONE: u32 = 19;
const A_FILES: u32 = 20;
const A_PAIRS: u32 = 21;
const A_WRITE: u32 = 22;
const P_TOKENS: u32 = 16;
const P_CLEAR_RECORDS: u32 = 17;
const P_SCAN: u32 = 18;
const P_CHECK: u32 = 21;
const P_FILES: u32 = 22;
const P_SCOPE: u32 = 23;
const P_WRITE: u32 = 24;

/// The buffers the rules of the generator round read and wrote, kept for
/// the explanation of a broken rule.
#[derive(Clone)]
pub(super) struct Run {
    slot: usize,
    records: LaniusBuffer<u8>,
    file_option: LaniusBuffer<u8>,
    scan1: LaniusBuffer<u8>,
    scan2: LaniusBuffer<u8>,
    gens: LaniusBuffer<u8>,
    params: LaniusBuffer<u8>,
    lets: LaniusBuffer<u8>,
    marks3: LaniusBuffer<u8>,
    status: LaniusBuffer<u8>,
    detail: LaniusBuffer<u8>,
}

pub(super) fn generator_constants(gpu: &Gpu<'_>) -> Constants {
    constants(gpu, "desugar.generators", &CONSTANTS, keyword)
}

/// The constant strings and the kinds of their machine keywords, for the
/// test of the token table.
#[cfg(test)]
pub(super) fn constant_strings() -> (&'static [&'static str], fn(&str) -> Option<TokenKind>) {
    (&CONSTANTS, keyword)
}

/// Records the generator round: the records of every generator, the rules,
/// the pieces of each machine's text and the shared stages.
pub(super) fn record(round: &Round<'_>, encoder: &mut wgpu::CommandEncoder) -> Result<Run> {
    let gpu = round.gpu;
    let bufs = round.bufs;
    let shared = round.shared;
    let rows = round.caps.tokens;
    let label = |name: &str| format!("desugar.generators.{name}");
    let storage = |name: &str, rows: usize, words: usize| round.storage(&label(name), rows, words);
    let list = |name: &str| storage(name, rows, 1);

    let records = storage("records", rows, RECORD_WORDS);
    let file_option = storage("file_option", bufs.source_file_start.count, 1);
    let marks1 = storage("marks1", rows, 4);
    let work1 = round.scan_work(&label("scan1"), rows);
    let marks2 = storage("marks2", rows, 4);
    let work2 = round.scan_work(&label("scan2"), rows);
    let marks3 = storage("marks3", rows, 4);
    let work3 = round.scan_work(&label("scan3"), rows);
    let counts = storage("counts", rows, 4);
    let count_work = round.scan_work(&label("counts"), rows);
    let (gens, yields, params, lets) = (list("gens"), list("yields"), list("params"), list("lets"));
    let direct = list("direct");
    let scope = list("scope");
    let status = gpu.fixed_words_from(&label("status"), &[NO_ERROR]);
    let detail = storage("detail", DETAIL_WORDS, 1);
    let constants = generator_constants(gpu);
    let (scan1, scan2, scan3, count_scan) = (&work1[0], &work2[0], &work3[0], &count_work[0]);
    let none = &shared.fpieces;

    let per_token = |encoder: &mut wgpu::CommandEncoder,
                     key: &'static str,
                     params_name: &'static str,
                     block: u32,
                     bindings: &[(&'static str, &LaniusBuffer<u8>)]|
     -> Result<()> {
        let mut all = vec![(params_name, round.block(block))];
        all.extend(
            bindings
                .iter()
                .map(|&(name, buffer)| (name, buffer.as_entire_binding())),
        );
        round.indirect(encoder, key, &all, A_TOKENS)
    };
    let lists = |encoder: &mut wgpu::CommandEncoder,
                 marks: &LaniusBuffer<u8>,
                 scan: &LaniusBuffer<u8>,
                 out: [&LaniusBuffer<u8>; 2]| {
        per_token(
            encoder,
            LISTS,
            "gLists",
            P_TOKENS,
            &[
                ("marks", marks),
                ("scan", scan),
                ("list_x", out[0]),
                ("list_y", out[1]),
            ],
        )
    };
    let scan = |encoder: &mut wgpu::CommandEncoder,
                input: &LaniusBuffer<u8>,
                work: &[LaniusBuffer<u8>; 2]| {
        round.scan(encoder, input, work, P_SCAN, A_SCAN, A_SCAN_ONE)
    };
    let tokens_out = bufs
        .tokens_out
        .clone()
        .reinterpret::<u8>(bufs.tokens_out.byte_size);
    let token_file_id = bufs
        .token_file_id
        .clone()
        .reinterpret::<u8>(bufs.token_file_id.byte_size);

    // The records, then the generators and yields with their depths.
    round.plan(encoder, PLAN_START, [none; 4])?;
    round.clear(encoder, &records, P_CLEAR_RECORDS, A_RECORD_WORDS)?;
    round.clear(encoder, &direct, P_TOKENS, A_TOKENS)?;
    round.clear(encoder, &file_option, P_FILES, A_FILES)?;
    per_token(
        encoder,
        READ,
        "gRead",
        P_TOKENS,
        &[
            ("tokens_out", &tokens_out),
            ("token_file_id", &token_file_id),
            ("records", &records),
        ],
    )?;
    per_token(
        encoder,
        MARKS,
        "gMarks",
        P_TOKENS,
        &[
            ("tokens_out", &tokens_out),
            ("token_file_id", &token_file_id),
            ("in_bytes", &bufs.in_bytes),
            ("records", &records),
            ("marks", &marks1),
            ("file_option", &file_option),
        ],
    )?;
    scan(encoder, &marks1, &work1)?;
    lists(encoder, &marks1, scan1, [&gens, &yields])?;

    // The parameters and locals, and the locals in scope at each token.
    per_token(
        encoder,
        DIRECT,
        "gDirect",
        P_TOKENS,
        &[("records", &records), ("direct", &direct)],
    )?;
    per_token(
        encoder,
        CONTEXT,
        "gContext",
        P_TOKENS,
        &[
            ("records", &records),
            ("scan1", scan1),
            ("direct", &direct),
            ("marks", &marks2),
        ],
    )?;
    scan(encoder, &marks2, &work2)?;
    lists(encoder, &marks2, scan2, [&params, &lets])?;

    // The rules, then the pieces.
    let run = Run {
        slot: round.slot,
        records: records.clone(),
        file_option: file_option.clone(),
        scan1: scan1.clone(),
        scan2: scan2.clone(),
        gens: gens.clone(),
        params: params.clone(),
        lets: lets.clone(),
        marks3: marks3.clone(),
        status: status.clone(),
        detail: detail.clone(),
    };
    per_token(
        encoder,
        CHECK,
        "gCheck",
        P_CHECK,
        &check_bindings(&run, &tokens_out, &token_file_id, &bufs.in_bytes),
    )?;
    scan(encoder, &marks3, &work3)?;
    let record_pieces = |encoder: &mut wgpu::CommandEncoder, block: u32, triple: u32| {
        round.indirect(
            encoder,
            PIECES,
            &[
                ("gPieces", round.block(block)),
                ("records", records.as_entire_binding()),
                ("scan1", scan1.as_entire_binding()),
                ("scan2", scan2.as_entire_binding()),
                ("scan3", scan3.as_entire_binding()),
                ("gens", gens.as_entire_binding()),
                ("params", params.as_entire_binding()),
                ("scope", scope.as_entire_binding()),
                ("count_scan", count_scan.as_entire_binding()),
                ("counts", counts.as_entire_binding()),
                ("pieces", shared.fpieces.as_entire_binding()),
                ("piece_owner", shared.fpiece_owner.as_entire_binding()),
                ("drop", shared.drop.as_entire_binding()),
            ],
            triple,
        )
    };
    record_pieces(encoder, P_TOKENS, A_TOKENS)?;
    scan(encoder, &counts, &count_work)?;
    round.plan(encoder, PLAN_PIECES, [scan1, scan3, count_scan, &status])?;
    round.indirect(
        encoder,
        SCOPE,
        &[
            ("gScope", round.block(P_SCOPE)),
            ("scan1", scan1.as_entire_binding()),
            ("scan2", scan2.as_entire_binding()),
            ("scan3", scan3.as_entire_binding()),
            ("yields", yields.as_entire_binding()),
            ("scope", scope.as_entire_binding()),
        ],
        A_PAIRS,
    )?;
    record_pieces(encoder, P_WRITE, A_WRITE)?;
    round.finish(encoder, &constants)?;
    Ok(run)
}

fn check_bindings<'a>(
    run: &'a Run,
    tokens_out: &'a LaniusBuffer<u8>,
    token_file_id: &'a LaniusBuffer<u8>,
    in_bytes: &'a LaniusBuffer<u8>,
) -> [(&'static str, &'a LaniusBuffer<u8>); 13] {
    [
        ("tokens_out", tokens_out),
        ("token_file_id", token_file_id),
        ("in_bytes", in_bytes),
        ("records", &run.records),
        ("scan1", &run.scan1),
        ("scan2", &run.scan2),
        ("gens", &run.gens),
        ("params", &run.params),
        ("lets", &run.lets),
        ("file_option", &run.file_option),
        ("marks", &run.marks3),
        ("status", &run.status),
        ("detail", &run.detail),
    ]
}

#[derive(encase::ShaderType)]
struct CheckParams {
    token_count: u32,
    reserved0: u32,
    explain_word: u32,
    explain_key: u32,
}

/// Runs the rules of the generator round again to write the spans of its
/// first error, and builds the message. `None` when no generator rule
/// failed.
pub(super) fn explain(
    gpu: &Gpu<'_>,
    last: &LastRun,
    run: &Run,
    text: &impl Fn(usize, usize) -> String,
) -> Result<Option<RuleError>> {
    let key = read_words(&[(&run.status, 0, 1)], None)?[0][0];
    if key == NO_ERROR {
        return Ok(None);
    }
    let tokens = last_sizes(last)?[run.slot * SIZE_WORDS + S_LIVE];
    let mut encoder = gpu.encoder("desugar.explain.generators");
    let params = gpu.fixed_uniform(
        "desugar.explain.generators",
        &CheckParams {
            token_count: tokens,
            reserved0: 0,
            explain_word: 0,
            explain_key: key,
        },
    );
    let bindings = check_bindings(run, &last.tokens_out, &last.token_file_id, &last.in_bytes);
    let mut all = vec![("gCheck", params.as_entire_binding())];
    all.extend(
        bindings
            .iter()
            .map(|&(name, buffer)| (name, buffer.as_entire_binding())),
    );
    gpu.fixed_dispatch(&mut encoder, &gpu.kernel(CHECK)?, CHECK, &all, tokens)?;
    let detail = read_words(&[(&run.detail, 0, DETAIL_WORDS)], Some(encoder))?.remove(0);
    // A token of an earlier round's text names the source byte it came from.
    let at = detail[0] as usize;
    let start = source_position(at).unwrap_or(at);
    let len = (detail[1] as usize).max(1);
    let label = text(start, len);
    Ok(Some(RuleError::machine(start, len, message(key, &label), None)))
}

/// The message of the error `key`, whose token has the text `label`.
fn message(key: u32, label: &str) -> String {
    match key & 31 {
        1 => "`yield` is a statement of a generator: write it in a `gen fn`".to_string(),
        2 => "a generator yields and returns only in its body's own statements, `if` and `while`, not inside a `match`, `for` or plain block".to_string(),
        3 => "a generator's locals declare their type: `let name: Type = value;`".to_string(),
        4 => format!("a generator declares each local once; `{label}` is declared again here"),
        5 => "a loop that yields has no `break` or `continue`: the code after a yield runs outside the loop".to_string(),
        6 => "a generator's `return` takes no value; it ends the sequence".to_string(),
        7 => "a generator declares the type it yields: `gen fn name(...) -> T`".to_string(),
        8 => "a generator's parameters are read-only; copy one into a local to change it".to_string(),
        9 => "a file with a `gen fn` imports `core::option`: its `next` returns `core::option::Option`".to_string(),
        _ => "a generator has no type parameters, `where` clause or contracts".to_string(),
    }
}
