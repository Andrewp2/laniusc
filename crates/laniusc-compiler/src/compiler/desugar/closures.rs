//! The closure round of the desugaring (docs/language-ergonomics.md).
//!
//! A closure `|x: T| body` becomes a struct of the locals it captures, a
//! `borrow` method and an impl of `core::function::Mapper` (or `Producer`
//! for `|| body`, `Consumer` and `Runnable` for a block body without a
//! result type). The site becomes a literal of that struct, borrowed; the
//! struct and its impls go after the last token of the closure's file, and
//! the file imports `core::function`.
//!
//! The round runs first, so its kernels (shaders/closures) read the lexer's
//! own tokens. A prefix sum of the bracket depth and the closure starts
//! gives every token its depth and its closure, a heap of minimum depths
//! finds the bracket around a binder, and the captures are the first uses of
//! the enclosing function's typed locals in a body. shaders/closures/
//! pieces.slang writes the pieces that the shared stages splice in.

use anyhow::Result;

use super::{
    Constants,
    LastRun,
    PLAN_START,
    Round,
    RuleError,
    constants,
    gpu::Gpu,
    read_words,
};
use crate::{gpu::buffers::LaniusBuffer, lexer::tables::tokens::TokenKind};

/// The strings the kernels insert, in the order of the `C_*` ids in
/// shaders/closures/closure_common.slang.
/// A string that follows a copied type starts with a space, so a type that
/// ends in `>` does not join it into `>=` or `>>`.
const CONSTANTS: [&str; 40] = [
    "__lanius_closure_",
    "{",
    ":",
    ",",
    "}.borrow()",
    "\nstruct __lanius_closure_",
    "}\nimpl __lanius_closure_",
    "{fn borrow(&self)->&__lanius_closure_",
    "{return self;}}\npub impl",
    "<__lanius_r>",
    " core::function::Mapper<",
    " core::function::Producer<",
    "__lanius_r",
    " > for __lanius_closure_",
    "{pub fn apply(&self,",
    "{pub fn produce(&self",
    ")->",
    "let ",
    " =self.",
    ";",
    "return ",
    ";}}\n",
    "}}\n",
    "import core::function;",
    "}",
    " core::function::Consumer<",
    " core::function::Runnable",
    " for __lanius_closure_",
    "{pub fn accept(&self,",
    "{pub fn run(&self",
    ")",
    "fn __lanius_closure_",
    "_entry(e:ptr,i:ptr,o:ptr){core::function::enter_",
    "mapper<__lanius_closure_",
    "producer<__lanius_closure_",
    "consumer<__lanius_closure_",
    "runnable<__lanius_closure_",
    " >(e,i,o);}\npub impl core::function::Stored for __lanius_closure_",
    "{pub fn entry(&self)->ptr{return __lanius_closure_",
    "_entry;}}\n",
];

/// The constant strings have no word the lexer reads as anything but a
/// plain identifier or a keyword `token_info` knows.
fn keyword(_word: &str) -> Option<TokenKind> {
    None
}

const MARK: &str = "closures/mark";
const DEPTH_BLOCKS: &str = "closures/depth_blocks";
const DEPTH_TREE: &str = "closures/depth_tree";
const ROLES: &str = "closures/roles";
const RECORDS: &str = "closures/records";
const CAPTURES: &str = "closures/captures";
const PIECES: &str = "closures/pieces";

const RECORD_WORDS: usize = 12;
const NO_ERROR: u32 = u32::MAX;

// The plan mode and the closure layout of shaders/desugar/plan.slang.
const PLAN_PIECES: u32 = 11;
const A_TOKENS: u32 = 16;
const A_SCAN: u32 = 17;
const A_SCAN_ONE: u32 = 18;
const A_TREE: u32 = 19;
const A_WRITE: u32 = 22;
const P_TOKENS: u32 = 16;
const P_SCAN: u32 = 17;
const P_TREE: u32 = 20;
const P_WRITE: u32 = 23;
/// The steps of the depth heap the plan sizes: enough for 2^24 blocks.
const TREE_STEPS: usize = 3;
/// The bytes of one step's `HeapTreeParams`.
const TREE_PARAM_BYTES: u64 = 32;

#[derive(encase::ShaderType)]
struct RoleParams {
    leaf_base: u32,
}

/// The status word of the closure rules, kept for the explanation of a
/// rejected closure.
#[derive(Clone)]
pub(super) struct Run {
    status: LaniusBuffer<u8>,
}

pub(super) fn closure_constants(gpu: &Gpu<'_>) -> Constants {
    constants(gpu, "desugar.closures", &CONSTANTS, keyword)
}

/// The constant strings and the kinds of their keywords, for the test of the
/// token table.
#[cfg(test)]
pub(super) fn constant_strings() -> (&'static [&'static str], fn(&str) -> Option<TokenKind>) {
    (&CONSTANTS, keyword)
}

/// The leaves of the heap of minimum depths over blocks of 256 tokens, for
/// `rows` token rows (`closure_leaf_base` in shaders/desugar/plan.slang).
fn leaf_base(rows: usize) -> u32 {
    (rows.div_ceil(256).max(1) as u32).next_power_of_two()
}

/// Records the closure round: the depths and closure starts, the records of
/// each closure, its captures, its pieces and the shared stages.
pub(super) fn record(round: &Round<'_>, encoder: &mut wgpu::CommandEncoder) -> Result<Run> {
    let gpu = round.gpu;
    let bufs = round.bufs;
    let shared = round.shared;
    let rows = round.caps.tokens;
    let label = |name: &str| format!("desugar.closures.{name}");
    let storage = |name: &str, rows: usize, words: usize| round.storage(&label(name), rows, words);

    let leaf_base = leaf_base(rows);
    let steps = crate::gpu::scan::heap_build_levels(leaf_base);
    anyhow::ensure!(steps.len() <= TREE_STEPS, "the closure depth heap has {} steps", steps.len());
    // Per token: the depth change and the closure start, then the piece count.
    let marks = storage("marks", rows, 4);
    let depth_work = round.scan_work(&label("depth"), rows);
    let local_min = storage("depth.local_min", rows.div_ceil(256).max(1) * 256, 1);
    let min_tree = storage("depth.min_tree", leaf_base as usize * 2, 1);
    let roles = storage("roles", rows, 1);
    // A closure takes three tokens at least: the one before it, its `|` or
    // `||` and its body.
    let records = storage("records", rows / 2 + 1, RECORD_WORDS);
    let capture_marks = storage("capture_marks", rows, 4);
    let capture_work = round.scan_work(&label("captures.scan"), rows);
    let captures = storage("captures", rows, 4);
    let count_work = round.scan_work(&label("counts"), rows);
    let status = gpu.fixed_words_from(&label("status"), &[NO_ERROR]);
    let role_params = gpu.fixed_uniform(&label("roles.params"), &RoleParams { leaf_base });
    let constants = closure_constants(gpu);
    let none = &shared.fpieces;
    let depth_scan = &depth_work[0];
    let capture_scan = &capture_work[0];
    let count_scan = &count_work[0];
    let scan = |encoder: &mut wgpu::CommandEncoder, input: &LaniusBuffer<u8>, work: &[LaniusBuffer<u8>; 2]| {
        round.scan(encoder, input, work, P_SCAN, A_SCAN, A_SCAN_ONE)
    };

    round.plan(encoder, PLAN_START, [none; 4])?;
    round.indirect(
        encoder,
        MARK,
        &[
            ("token_count", round.sizes()),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("token_file_id", bufs.token_file_id.as_entire_binding()),
            ("in_bytes", bufs.in_bytes.as_entire_binding()),
            ("marks", marks.as_entire_binding()),
        ],
        A_TOKENS,
    )?;
    scan(encoder, &marks, &depth_work)?;

    // The heap of minimum depths, then the binders of the tokens.
    round.indirect(
        encoder,
        DEPTH_BLOCKS,
        &[
            ("token_count", round.sizes()),
            ("depth_scan", depth_scan.as_entire_binding()),
            ("depth_local_min", local_min.as_entire_binding()),
        ],
        A_TOKENS,
    )?;
    for step in 0..steps.len() as u32 {
        round.indirect(
            encoder,
            DEPTH_TREE,
            &[
                ("gMinTree", round.block_of(P_TREE + step, TREE_PARAM_BYTES)),
                ("depth_local_min", local_min.as_entire_binding()),
                ("depth_min_tree", min_tree.as_entire_binding()),
            ],
            A_TREE + step,
        )?;
    }
    round.indirect(
        encoder,
        ROLES,
        &[
            ("gRoles", role_params.as_entire_binding()),
            ("token_count", round.sizes()),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("token_file_id", bufs.token_file_id.as_entire_binding()),
            ("depth_scan", depth_scan.as_entire_binding()),
            ("depth_local_min", local_min.as_entire_binding()),
            ("depth_min_tree", min_tree.as_entire_binding()),
            ("roles", roles.as_entire_binding()),
        ],
        A_TOKENS,
    )?;

    // The records and the rules, then the captures.
    round.indirect(
        encoder,
        RECORDS,
        &[
            ("token_count", round.sizes()),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("token_file_id", bufs.token_file_id.as_entire_binding()),
            ("depth_scan", depth_scan.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("status", status.as_entire_binding()),
        ],
        A_TOKENS,
    )?;
    round.indirect(
        encoder,
        CAPTURES,
        &[
            ("token_count", round.sizes()),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("token_file_id", bufs.token_file_id.as_entire_binding()),
            ("in_bytes", bufs.in_bytes.as_entire_binding()),
            ("roles", roles.as_entire_binding()),
            ("depth_scan", depth_scan.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("capture_marks", capture_marks.as_entire_binding()),
            ("status", status.as_entire_binding()),
        ],
        A_TOKENS,
    )?;
    scan(encoder, &capture_marks, &capture_work)?;

    // The pieces: counted per token, then written per piece.
    let record_pieces = |encoder: &mut wgpu::CommandEncoder, block: u32, triple: u32| {
        round.indirect(
            encoder,
            PIECES,
            &[
                ("gPieces", round.block(block)),
                ("tokens_out", bufs.tokens_out.as_entire_binding()),
                ("token_file_id", bufs.token_file_id.as_entire_binding()),
                ("source_file_start", bufs.source_file_start.as_entire_binding()),
                ("depth_scan", depth_scan.as_entire_binding()),
                ("capture_marks", capture_marks.as_entire_binding()),
                ("capture_scan", capture_scan.as_entire_binding()),
                ("count_scan", count_scan.as_entire_binding()),
                ("records", records.as_entire_binding()),
                ("captures", captures.as_entire_binding()),
                ("counts", marks.as_entire_binding()),
                ("pieces", shared.fpieces.as_entire_binding()),
                ("piece_owner", shared.fpiece_owner.as_entire_binding()),
                ("drop", shared.drop.as_entire_binding()),
            ],
            triple,
        )
    };
    record_pieces(encoder, P_TOKENS, A_TOKENS)?;
    scan(encoder, &marks, &count_work)?;
    round.plan(encoder, PLAN_PIECES, [depth_scan, count_scan, none, &status])?;
    record_pieces(encoder, P_WRITE, A_WRITE)?;
    round.finish(encoder, &constants)?;
    Ok(Run { status })
}

/// The closure the rules rejected first, if any. The status word holds
/// `token << 4 | code`; a broken rule stops the round before its splice, so
/// the token is a source token.
pub(super) fn explain(last: &LastRun, run: &Run) -> Result<Option<RuleError>> {
    let failure = read_words(&last.gpu(), &[(&run.status, 0, 1)], None)?[0][0];
    if failure == NO_ERROR {
        return Ok(None);
    }
    let token = (failure >> 4) as usize;
    let row = read_words(&last.gpu(), &[(&last.tokens_out, token * 3, 3)], None)?.remove(0);
    let message = match failure & 15 {
        1 => "a closure parameter needs a type: write `|name: Type|`",
        2 => "a closure takes one parameter with a type, `|name: Type|`, or none, `||`",
        3 => "this closure has no body",
        4 => "a closure cannot contain another closure",
        5 => "a closure cannot use `self`: bind the value to a local with a declared type first",
        6 => "a closure captures this local, which has no declared type: declare it as `let name: Type = ...`",
        7 => "a closure with a result type needs a body in braces",
        _ => "this closure is not valid",
    };
    Ok(Some(RuleError::closure(row[1] as usize, (row[2] as usize).max(1), message.to_string())))
}
