//! Desugaring in the token stream (docs/state-machines-design.md,
//! "Desugaring in the lexer").
//!
//! The desugaring is the last stage of the frontend lexer. It runs in rounds,
//! one per feature: closures, generators, then machines. Each round reads
//! the token rows the round before it left and writes the token rows of the
//! next stream. The text of the generated tokens goes into a region of the
//! lexer's byte buffer after the source bytes, so every later kernel reads
//! their names from token bytes as it reads source names.
//!
//! A round's own kernels read the stream into records, check the feature's
//! rules and write pieces: ranges of tokens to copy and generated words. The
//! shared kernels of shaders/desugar expand the ranges, place the text,
//! build its tokens and splice them in, the same way for every round.
//!
//! Every dispatch is recorded before any count is known. A plan kernel
//! (shaders/desugar/plan.slang) turns the counts of one stage into the
//! indirect dispatch sizes and kernel parameters of the next, so a round
//! whose feature the pack does not use runs every dispatch with zero
//! workgroups, and the host reads nothing back. A round is recorded only
//! once a build of the process used its feature. The host reads the outcome
//! with the token count it already reads: `DESUGAR_REGION_OVERFLOW` asks for
//! more room and a second run, `DESUGAR_RULE_ERROR` for the diagnostic of a
//! broken rule.

use std::{
    cell::Cell,
    num::NonZeroU64,
    path::Path,
    sync::{
        Mutex,
        PoisonError,
        atomic::{AtomicU32, AtomicU64, Ordering},
    },
};

use anyhow::{Context, Result};

use super::{
    CompileError,
    Diagnostic,
    DiagnosticSourceFile,
    diagnostic_label_from_source_span,
    source_pack_file_for_global_span,
};
use crate::{
    gpu::{buffers::LaniusBuffer, passes_core::PassContext},
    lexer::{
        buffers::GpuBuffers,
        debug::DebugOutput,
        features::{PARSER_FEATURE_CLOSURES, PARSER_FEATURE_GENERATORS, PARSER_FEATURE_MACHINES},
        tables::tokens::TokenKind,
    },
};

mod closures;
mod generators;
mod gpu;
mod machines;

use gpu::{Binding, Gpu};
pub(crate) use gpu::release_resident_buffers;

const MACHINE_CODE: &str = "LNC0076";
const MACHINE_TITLE: &str = "invalid machine";
const CLOSURE_CODE: &str = "LNC0078";
const CLOSURE_TITLE: &str = "invalid closure";

/// A broken rule of a desugared feature: a global byte span, its message and
/// the diagnostic it is reported as.
pub(in crate::compiler) struct RuleError {
    pub(in crate::compiler) start: usize,
    pub(in crate::compiler) len: usize,
    pub(in crate::compiler) message: String,
    pub(in crate::compiler) help: Option<String>,
    code: &'static str,
    title: &'static str,
}

impl RuleError {
    /// A broken rule of a machine or a generator (LNC0076).
    fn machine(start: usize, len: usize, message: String, help: Option<String>) -> Self {
        Self { start, len, message, help, code: MACHINE_CODE, title: MACHINE_TITLE }
    }

    /// A closure the desugaring rejects (LNC0078).
    fn closure(start: usize, len: usize, message: String) -> Self {
        Self { start, len, message, help: None, code: CLOSURE_CODE, title: CLOSURE_TITLE }
    }
}

/// The bit the lexer's feature word carries when a source name has the
/// prefix of generated names, `__lanius_` (R5).
pub(crate) const DESUGAR_RESERVED: u32 = 0x2000_0000;
/// The bit the lexer's feature word carries when the generated text did not
/// fit the region; the build runs again with a larger one.
pub(crate) const DESUGAR_REGION_OVERFLOW: u32 = 0x4000_0000;
/// The bit the lexer's feature word carries when a feature breaks a rule.
pub(crate) const DESUGAR_RULE_ERROR: u32 = 0x8000_0000;
/// The bits that stop a build: the host grows the floors or explains a rule.
const DESUGAR_STOPS: u32 = DESUGAR_RESERVED | DESUGAR_REGION_OVERFLOW | DESUGAR_RULE_ERROR;
/// The bits of the feature word that are not parser families.
pub(crate) const DESUGAR_BITS: u32 = DESUGAR_STOPS | PARSER_FEATURE_GENERATORS | PARSER_FEATURE_CLOSURES;

/// Bytes of the region after the source that the next lexer allocation
/// reserves for generated token text. It starts at zero, so a build without
/// a feature allocates and dispatches nothing for the desugaring. A build
/// whose generated text does not fit raises it and runs again; it does not
/// shrink, so later builds of the same program do not run twice.
static REGION_FLOOR: AtomicU32 = AtomicU32::new(0);
/// Rows of the per-token buffers, of the pieces and of the spliced tokens.
/// The plan kernel checks each against its count, and the floors grow like
/// the region.
static TOKEN_ROWS: AtomicU32 = AtomicU32::new(0);
static PIECE_ROWS: AtomicU32 = AtomicU32::new(0);
static OUT_ROWS: AtomicU32 = AtomicU32::new(0);
/// The feature bits of the rounds the lexer records: those a build of this
/// process has used.
static ROUNDS_USED: AtomicU32 = AtomicU32::new(0);
/// Numbers the recorded runs, so a diagnostic reads only the run of its own
/// build (`source_position`).
static RUNS: AtomicU64 = AtomicU64::new(0);

thread_local! {
    static SUSPENDED: Cell<bool> = const { Cell::new(false) };
    /// The run this thread's last lexer recording recorded.
    static RECORDED: Cell<u64> = const { Cell::new(0) };
}

/// The rounds, in the order they run: the feature bit each one desugars.
const ROUND_FEATURES: [u32; ROUNDS] = [PARSER_FEATURE_CLOSURES, PARSER_FEATURE_GENERATORS, PARSER_FEATURE_MACHINES];
const ROUNDS: usize = 3;

/// The byte extent of a lexer input of `n` source bytes, `aligned_len` of
/// them with word padding: the source alone when no region is reserved or
/// the desugaring is off, otherwise the padded source and the region.
pub(crate) fn byte_extent(n: u32, aligned_len: u32) -> u32 {
    if SUSPENDED.with(|s| s.get()) {
        return n;
    }
    match REGION_FLOOR.load(Ordering::Relaxed) {
        0 => n,
        region => aligned_len.saturating_add(region),
    }
}

/// A count with room for the next build of nearly the same program.
fn headroom(count: u32) -> u32 {
    count
        .saturating_add(count / 8)
        .saturating_add(64)
        .next_multiple_of(4)
}

fn raise(floor: &AtomicU32, value: u32) {
    floor.fetch_max(value, Ordering::Relaxed);
}

/// Raises the floors after a run that did not fit. `needs` holds what the
/// stage that stopped needed, zero for the stages it did not reach. A floor
/// that is still zero gets an estimate from the pack, so the next run most
/// likely fits.
fn grow(needs: [u32; 4], token_count: u32, source_bytes: u32) {
    let [tokens, pieces, region, out] = needs;
    let first = REGION_FLOOR.load(Ordering::Relaxed) == 0;
    let region_guess = if first {
        (source_bytes / 4).max(1 << 16)
    } else {
        0
    };
    raise(&TOKEN_ROWS, headroom(tokens.max(token_count + 1)));
    raise(&REGION_FLOOR, headroom(region).max(region_guess));
    raise(&PIECE_ROWS, headroom(pieces).max(region_guess / 4));
    raise(
        &OUT_ROWS,
        headroom(out).max(if first {
            headroom(token_count) + region_guess / 4
        } else {
            0
        }),
    );
    if crate::gpu::passes_core::host_timing_enabled() {
        eprintln!(
            "[gpu_compile_host_timer] desugar.grow: needs={needs:?} tokens={token_count} rows={} pieces={} region={} out={}",
            TOKEN_ROWS.load(Ordering::Relaxed),
            PIECE_ROWS.load(Ordering::Relaxed),
            REGION_FLOOR.load(Ordering::Relaxed),
            OUT_ROWS.load(Ordering::Relaxed),
        );
    }
}

/// Reads `words` words of each of `reads` (buffer, first word) in one
/// submission. The desugaring reads only on its error and retry paths, and
/// without the rewrite pool, so it can read while another thread holds it.
fn read_words(
    reads: &[(&LaniusBuffer<u8>, usize, usize)],
    encoder: Option<wgpu::CommandEncoder>,
) -> Result<Vec<Vec<u32>>> {
    let device = crate::gpu::device::global();
    let total: usize = reads.iter().map(|&(_, _, words)| words.max(1) * 4).sum();
    let staging = device.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("desugar.readback"),
        size: total as u64,
        usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    let mut encoder = encoder.unwrap_or_else(|| {
        device
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("desugar.readback"),
            })
    });
    let mut at = 0u64;
    for &(buffer, first, words) in reads {
        let len = (words.max(1) * 4) as u64;
        anyhow::ensure!(
            (first * 4) as u64 + len <= buffer.byte_size as u64,
            "desugar readback past its buffer"
        );
        encoder.copy_buffer_to_buffer(
            &buffer.buffer,
            buffer.byte_offset + (first * 4) as u64,
            &staging,
            at,
            len,
        );
        at += len;
    }
    crate::gpu::passes_core::submit_with_progress(
        &device.queue,
        "desugar.readback",
        encoder.finish(),
    );
    let slice = staging.slice(..);
    crate::gpu::passes_core::map_readback_blocking(&device.device, &slice, "desugar.readback")?;
    let mapped = slice.get_mapped_range();
    let mut out = Vec::with_capacity(reads.len());
    let mut at = 0usize;
    for &(_, _, words) in reads {
        out.push(
            mapped[at..at + words * 4]
                .chunks_exact(4)
                .map(|w| u32::from_le_bytes([w[0], w[1], w[2], w[3]]))
                .collect(),
        );
        at += words.max(1) * 4;
    }
    drop(mapped);
    staging.unmap();
    Ok(out)
}

/// The sizes of every round of the last run, read from the GPU.
fn last_sizes(last: &LastRun) -> Result<Vec<u32>> {
    let sizes = last.sizes.as_ref().context("the last run recorded no round")?;
    Ok(read_words(&[(sizes, 0, ROUNDS * SIZE_WORDS)], None)?.remove(0))
}

/// What the last run needed of each floor, read from the GPU after it
/// overflowed: the most any round needed.
fn last_needs() -> [u32; 4] {
    let Some(last) = last_run() else {
        return [0; 4];
    };
    let Ok(sizes) = last_sizes(&last) else {
        return [0; 4];
    };
    let mut needs = [0u32; 4];
    for round in 0..ROUNDS {
        for (k, need) in needs.iter_mut().enumerate() {
            *need = (*need).max(sizes[round * SIZE_WORDS + S_NEED_TOKENS + k]);
        }
    }
    needs
}

/// Runs `f` with the desugaring switched off for lexer recordings on this
/// thread, for the tests that lex the source tokens of a feature.
#[cfg(test)]
pub(crate) fn without_desugaring<T>(f: impl FnOnce() -> T) -> T {
    let previous = SUSPENDED.with(|s| s.replace(true));
    let out = f();
    SUSPENDED.with(|s| s.set(previous));
    out
}

// Layout of shaders/desugar/desugar_common.slang.
const S_LIVE: usize = 1;
const S_F0: usize = 2;
const S_F1: usize = 3;
const S_REGION: usize = 8;
const S_ANCHOR_BASE: usize = 14;
const S_NEED_TOKENS: usize = 15;
const SIZE_WORDS: usize = 64;
const A_EXPAND_SCAN: u32 = 0;
const A_EXPAND_SCAN_ONE: u32 = 1;
const A_PIECES: u32 = 2;
const A_PIECE_SCAN: u32 = 3;
const A_PIECE_SCAN_ONE: u32 = 4;
const A_REGION_WORDS: u32 = 5;
const A_REGION_BYTES: u32 = 6;
const A_REGION_SCAN: u32 = 7;
const A_REGION_SCAN_ONE: u32 = 8;
const A_SPLICE: u32 = 9;
const A_SPLICE_SCAN: u32 = 10;
const A_SPLICE_SCAN_ONE: u32 = 11;
const A_GENERATED: u32 = 12;
const A_KEPT: u32 = 13;
const A_OUT: u32 = 14;
const ARG_TRIPLES: u32 = 64;
const P_EXPAND_SCAN: u32 = 0;
const P_PIECE_SCAN: u32 = 3;
const P_REGION_SCAN: u32 = 6;
const P_SPLICE_SCAN: u32 = 9;
const BLOCKS: u32 = 48;
const BLOCK_BYTES: u64 = 256;
const SIZE_BYTES: u64 = SIZE_WORDS as u64 * 4;
const ARG_BYTES: u64 = ARG_TRIPLES as u64 * 12;
const SCAN_TILE_ROWS: usize = 2048;
const PLAN_START: u32 = 0;
const PLAN_PLACE: u32 = 1;
const PLAN_REGION: u32 = 2;
const PLAN_SPLICE: u32 = 3;
const PLAN_FINISH: u32 = 4;

/// Kernels of the desugaring, by shader artifact key.
const PLAN: &str = "desugar/plan";
const CLEAR: &str = "desugar/clear";
const SCAN: &str = "closures/scan";
const EXPAND: &str = "desugar/expand";
const EMIT: &str = "desugar/emit";
const TEXT_MARKS: &str = "desugar/text_marks";
const TEXT_TOKENS: &str = "desugar/text_tokens";
const SPLICE_MARKS: &str = "desugar/splice_marks";
const SPLICE_INSERTED: &str = "desugar/splice_inserted";
const SPLICE_KEPT: &str = "desugar/splice_kept";
const SPLICE_GENERATED: &str = "desugar/splice_generated";
const COPY_BACK: &str = "desugar/copy_back";
const RESERVED: &str = "machines/reserved";

#[derive(encase::ShaderType)]
struct PlanParams {
    mode: u32,
    feature: u32,
    first: u32,
    token_cap: u32,
    piece_cap: u32,
    out_cap: u32,
    slot: u32,
    previous: u32,
}

/// What a diagnostic or the explanation of a broken rule needs from the last
/// run: the lexer's buffers and, when a round was recorded, where the region
/// starts, the anchor of each of its bytes, the sizes of each round and the
/// buffers each round's rules read and wrote.
#[derive(Clone)]
struct LastRun {
    run: u64,
    first_base: u32,
    anchors: Option<LaniusBuffer<u8>>,
    sizes: Option<LaniusBuffer<u8>>,
    tokens_out: LaniusBuffer<u8>,
    token_file_id: LaniusBuffer<u8>,
    in_bytes: LaniusBuffer<u8>,
    closures: Option<closures::Run>,
    generators: Option<generators::Run>,
    machines: Option<machines::Run>,
}

static LAST_RUN: Mutex<Option<LastRun>> = Mutex::new(None);

/// The last run, when this thread recorded it. A compile reads the run of
/// its own lexer recording after the lexer is free; a run another thread
/// recorded since then would give wrong positions, so that is an error.
fn last_run() -> Option<LastRun> {
    let last = LAST_RUN
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .clone()?;
    let recorded = RECORDED.with(Cell::get);
    assert_eq!(
        last.run, recorded,
        "the desugaring's last run belongs to another compile on this lexer"
    );
    Some(last)
}

/// Per byte of `text`: bit 0 when it is part of a token, bit 1 when a token
/// starts at it, and from bit 8 the kind of that token. `keyword` gives the
/// kind of a word that is not a plain identifier.
fn token_info(text: &str, keyword: impl Fn(&str) -> Option<TokenKind>) -> Vec<u32> {
    let bytes = text.as_bytes();
    let mut info = vec![0u32; bytes.len()];
    let mut at = 0;
    while at < bytes.len() {
        let c = bytes[at];
        if c.is_ascii_whitespace() {
            at += 1;
            continue;
        }
        let name = |c: u8| c.is_ascii_alphanumeric() || c == b'_';
        let (len, kind) = if c.is_ascii_alphabetic() || c == b'_' {
            let len = bytes[at..].iter().take_while(|&&c| name(c)).count();
            let word = &text[at..at + len];
            let kind = keyword(word).unwrap_or(match word {
                "pub" => TokenKind::Pub,
                "enum" => TokenKind::Enum,
                "struct" => TokenKind::Struct,
                "fn" => TokenKind::Fn,
                "impl" => TokenKind::Impl,
                "match" => TokenKind::Match,
                "return" => TokenKind::Return,
                "while" => TokenKind::While,
                "let" => TokenKind::Let,
                "continue" => TokenKind::Continue,
                "self" => TokenKind::SelfValue,
                "mut" => TokenKind::Mut,
                "import" => TokenKind::Import,
                "for" => TokenKind::For,
                _ => TokenKind::Ident,
            });
            (len, kind)
        } else if c.is_ascii_digit() {
            (
                bytes[at..]
                    .iter()
                    .take_while(|c| c.is_ascii_digit())
                    .count(),
                TokenKind::Int,
            )
        } else if text[at..].starts_with("->") {
            (2, TokenKind::Arrow)
        } else if text[at..].starts_with("+=") {
            (2, TokenKind::PlusAssign)
        } else {
            let kind = match c {
                b'(' => TokenKind::LParen,
                b')' => TokenKind::RParen,
                b'[' => TokenKind::LBracket,
                b']' => TokenKind::RBracket,
                b'{' => TokenKind::LBrace,
                b'}' => TokenKind::RBrace,
                b':' => TokenKind::Colon,
                b';' => TokenKind::Semicolon,
                b',' => TokenKind::Comma,
                b'=' => TokenKind::Assign,
                b'<' => TokenKind::Lt,
                b'>' => TokenKind::Gt,
                b'&' => TokenKind::Ampersand,
                b'.' => TokenKind::Dot,
                other => panic!("constant string byte {:?} has no token kind", other as char),
            };
            (1, kind)
        };
        info[at] = 1 | 2 | ((kind as u32) << 8);
        for byte in &mut info[at + 1..at + len] {
            *byte = 1 | ((kind as u32) << 8);
        }
        at += len;
    }
    info
}

/// The constant strings of one feature: where each starts, their bytes and
/// the token table of their bytes.
struct Constants {
    index: LaniusBuffer<u8>,
    bytes: LaniusBuffer<u8>,
    info: LaniusBuffer<u8>,
}

fn constants(
    gpu: &Gpu<'_>,
    label: &str,
    strings: &[&str],
    keyword: impl Fn(&str) -> Option<TokenKind>,
) -> Constants {
    let mut index = Vec::with_capacity(strings.len() * 2);
    let mut bytes = Vec::new();
    let mut info = Vec::new();
    for text in strings {
        index.extend([bytes.len() as u32, text.len() as u32]);
        bytes.extend_from_slice(text.as_bytes());
        info.extend(token_info(text, &keyword));
    }
    bytes.resize(bytes.len().next_multiple_of(4).max(4), 0);
    info.resize(info.len().max(1), 0);
    let words: Vec<u32> = bytes
        .chunks_exact(4)
        .map(|w| u32::from_le_bytes([w[0], w[1], w[2], w[3]]))
        .collect();
    Constants {
        index: gpu.fixed_words_from(&format!("{label}.const_index"), &index),
        bytes: gpu.fixed_words_from(&format!("{label}.const_bytes"), &words),
        info: gpu.fixed_words_from(&format!("{label}.const_info"), &info),
    }
}

/// The source byte of global position `at` when it lies in the region of the
/// last run, read from the GPU. A byte one round copied from an earlier
/// round's text names that text, so the chain is followed to the source.
/// Diagnostics call it for a span past the source; a build without a
/// desugared feature never makes one.
pub(crate) fn source_position(at: usize) -> Option<usize> {
    let last = last_run()?;
    let sizes = last_sizes(&last).ok()?;
    let filled = (0..ROUNDS)
        .map(|round| {
            let row = &sizes[round * SIZE_WORDS..];
            (row[S_ANCHOR_BASE] + row[S_REGION]) as usize
        })
        .max()
        .unwrap_or(0);
    let mut at = at;
    for step in 0..=ROUNDS {
        let Some(offset) = at.checked_sub(last.first_base as usize) else {
            // A source byte: the end of the chain, or not a region byte.
            return (step > 0).then_some(at);
        };
        let anchors = last.anchors.as_ref()?;
        if offset >= filled || (offset + 1) * 4 > anchors.byte_size {
            return None;
        }
        at = read_words(&[(anchors, offset, 1)], None).ok()?[0][0] as usize;
    }
    None
}

/// Why the lexer's run did not finish the desugaring.
pub(in crate::compiler) enum Stop {
    /// The generated text did not fit; the region is larger now.
    Retry,
    /// A feature breaks a rule.
    Rejected(RuleError),
}

/// The rounds the next recording needs for the features of `raw_features`
/// that it did not record.
fn unrecorded(raw_features: u32) -> u32 {
    let used = ROUNDS_USED.load(Ordering::Relaxed);
    let wanted = ROUND_FEATURES
        .iter()
        .fold(0, |bits, &feature| bits | (raw_features & feature));
    let missing = wanted & !used;
    if REGION_FLOOR.load(Ordering::Relaxed) == 0 {
        wanted
    } else {
        missing
    }
}

/// Whether the lexer's feature word says the desugaring did not finish. The
/// caller calls `stop` once the lexer's buffers are free.
pub(crate) fn stopped(raw_features: u32) -> bool {
    raw_features & DESUGAR_STOPS != 0 || unrecorded(raw_features) != 0
}

/// Reads the desugaring's bits of the lexer's feature word. `token_count` is
/// the count the lexer reported, `source_bytes` the size of its input and
/// `text` reads a global span of it.
pub(in crate::compiler) fn stop(
    raw_features: u32,
    token_count: u32,
    source_bytes: usize,
    text: impl Fn(usize, usize) -> String,
) -> Option<Stop> {
    if raw_features & DESUGAR_RESERVED != 0 {
        return Some(Stop::Rejected(reserved(token_count).unwrap_or_else(|err| {
            RuleError::machine(
                0,
                1,
                format!("the compiler stopped while finding a reserved name: {err:#}"),
                None,
            )
        })));
    }
    if raw_features & DESUGAR_RULE_ERROR != 0 {
        return Some(match explain(text) {
            Ok(rule) => Stop::Rejected(rule),
            Err(err) => Stop::Rejected(RuleError::machine(
                0,
                1,
                format!("the compiler stopped while explaining a broken rule: {err:#}"),
                None,
            )),
        });
    }
    // A build records only the rounds of the features earlier builds used.
    let missing = unrecorded(raw_features);
    if raw_features & DESUGAR_REGION_OVERFLOW != 0 || missing != 0 {
        let needs = if raw_features & DESUGAR_REGION_OVERFLOW != 0 {
            last_needs()
        } else {
            [0; 4]
        };
        ROUNDS_USED.fetch_or(missing, Ordering::Relaxed);
        grow(
            needs,
            token_count,
            u32::try_from(source_bytes).unwrap_or(u32::MAX),
        );
        return Some(Stop::Retry);
    }
    None
}

/// Runs the rules of the round that failed again to write the spans of its
/// first error, and builds the message.
fn explain(text: impl Fn(usize, usize) -> String) -> Result<RuleError> {
    let last = last_run().context("the desugaring kept no run to explain")?;
    let device = crate::gpu::device::global();
    let gpu = Gpu {
        device: &device.device,
        queue: &device.queue,
    };
    // A broken rule stops the rounds after it, so the first round with an
    // error has the error the run reports.
    if let Some(run) = &last.closures
        && let Some(rule) = closures::explain(&last, run)?
    {
        return Ok(rule);
    }
    if let Some(run) = &last.generators
        && let Some(rule) = generators::explain(&gpu, &last, run, &text)?
    {
        return Ok(rule);
    }
    if let Some(run) = &last.machines
        && let Some(rule) = machines::explain(&gpu, &last, run, &text)?
    {
        return Ok(rule);
    }
    anyhow::bail!("no rule of the desugaring failed")
}

#[derive(encase::ShaderType)]
struct ReservedParams {
    token_count: u32,
    reserved0: u32,
    reserved1: u32,
    reserved2: u32,
}

/// The first name with the reserved prefix, which the lexer's token build
/// found. No round ran, so the lexer's tokens are the source's.
fn reserved(token_count: u32) -> Result<RuleError> {
    let last = last_run().context("the desugaring kept no run to explain")?;
    let device = crate::gpu::device::global();
    let gpu = Gpu { device: &device.device, queue: &device.queue };
    let status = gpu.fixed_words_from("desugar.reserved.status", &[u32::MAX]);
    let params = gpu.fixed_uniform(
        "desugar.reserved.params",
        &ReservedParams { token_count, reserved0: 0, reserved1: 0, reserved2: 0 },
    );
    let mut encoder = gpu.encoder("desugar.reserved");
    gpu.fixed_dispatch(
        &mut encoder,
        &gpu.kernel(RESERVED)?,
        RESERVED,
        &[
            ("gReserved", params.as_entire_binding()),
            ("tokens_out", last.tokens_out.as_entire_binding()),
            ("in_bytes", last.in_bytes.as_entire_binding()),
            ("status", status.as_entire_binding()),
        ],
        token_count,
    )?;
    let token = read_words(&[(&status, 0, 1)], Some(encoder))?[0][0] as usize;
    anyhow::ensure!(token < token_count as usize, "the lexer found a reserved name the check does not");
    let row = read_words(&[(&last.tokens_out, token * 3, 3)], None)?.remove(0);
    Ok(RuleError::machine(
        row[1] as usize,
        (row[2] as usize).max(1),
        "identifiers starting with `__lanius_` are reserved for the compiler".to_string(),
        None,
    ))
}

/// The text of global span `[start, start + len)` of a single source.
pub(crate) fn source_text(source: &str, start: usize, len: usize) -> String {
    source
        .get(start..start.saturating_add(len))
        .unwrap_or("")
        .to_string()
}

/// The text of global span `[start, start + len)` of a source pack.
pub(in crate::compiler) fn source_pack_text(
    files: &[DiagnosticSourceFile],
    start: usize,
    len: usize,
) -> String {
    source_pack_file_for_global_span(files, start)
        .map(|file| source_text(&file.source, start - file.global_start, len))
        .unwrap_or_default()
}

/// The diagnostic of a broken rule in a single source.
pub(in crate::compiler) fn rejected_in_source(
    path: &Path,
    source: &str,
    rule: RuleError,
) -> CompileError {
    rule_diagnostic(path, source, rule.start, rule)
}

/// The diagnostic of a broken rule in a source pack.
pub(in crate::compiler) fn rejected_in_source_pack(
    files: &[DiagnosticSourceFile],
    rule: RuleError,
) -> CompileError {
    match source_pack_file_for_global_span(files, rule.start).or_else(|| files.first()) {
        Some(file) => rule_diagnostic(
            &file.path,
            &file.source,
            file.local_start_for_global(rule.start),
            rule,
        ),
        None => rule_diagnostic(Path::new("<source>"), "", 0, rule),
    }
}

fn rule_diagnostic(path: &Path, source: &str, start: usize, rule: RuleError) -> CompileError {
    let diagnostic = Diagnostic::error(rule.code, rule.title).with_primary_label(
        diagnostic_label_from_source_span(path, source, start, rule.len, rule.message),
    );
    CompileError::Diagnostic(match rule.help {
        Some(help) => diagnostic.with_help(help),
        None => diagnostic,
    })
}

/// The buffers every round shares. The rounds run one after another, so
/// each round reuses them.
struct Shared {
    sizes: LaniusBuffer<u8>,
    args: LaniusBuffer<u8>,
    blocks: LaniusBuffer<u8>,
    fpieces: LaniusBuffer<u8>,
    fpiece_owner: LaniusBuffer<u8>,
    fpiece_work: [LaniusBuffer<u8>; 2],
    pieces: LaniusBuffer<u8>,
    piece_owner: LaniusBuffer<u8>,
    piece_work: [LaniusBuffer<u8>; 2],
    drop: LaniusBuffer<u8>,
    anchors: LaniusBuffer<u8>,
    byte_piece: LaniusBuffer<u8>,
    byte_info: LaniusBuffer<u8>,
    text_marks: LaniusBuffer<u8>,
    text_work: [LaniusBuffer<u8>; 2],
    generated: LaniusBuffer<u8>,
    generated_file: LaniusBuffer<u8>,
    generated_owner: LaniusBuffer<u8>,
    splice_marks: LaniusBuffer<u8>,
    splice_work: [LaniusBuffer<u8>; 2],
    spliced: LaniusBuffer<u8>,
    spliced_file: LaniusBuffer<u8>,
}

/// The row counts the buffers of this recording hold.
#[derive(Clone, Copy)]
struct Caps {
    tokens: usize,
    pieces: usize,
    out: usize,
}

/// One round being recorded: its slices of the shared buffers and the
/// helpers its kernels record with.
struct Round<'a> {
    gpu: &'a Gpu<'a>,
    bufs: &'a GpuBuffers,
    shared: &'a Shared,
    caps: Caps,
    /// The round's slot in the slices of `sizes`, `args` and `blocks`.
    slot: usize,
    /// The slot of the round recorded before it, if any.
    previous: Option<usize>,
    feature: u32,
}

/// A slice of `buffer` as a binding.
fn slice(buffer: &LaniusBuffer<u8>, offset: u64, size: u64) -> wgpu::BindingResource<'_> {
    wgpu::BindingResource::Buffer(wgpu::BufferBinding {
        buffer: &buffer.buffer,
        offset: buffer.byte_offset + offset,
        size: NonZeroU64::new(size),
    })
}

impl<'a> Round<'a> {
    fn storage(&self, label: &str, rows: usize, words: usize) -> LaniusBuffer<u8> {
        self.gpu
            .fixed_storage(label, rows.max(1) * words * 4, wgpu::BufferUsages::empty())
    }

    /// The pair of a prefix sum: the sums, and the totals of its tiles.
    fn scan_work(&self, label: &str, rows: usize) -> [LaniusBuffer<u8>; 2] {
        scan_work(self.gpu, label, rows)
    }

    fn sizes(&self) -> wgpu::BindingResource<'a> {
        slice(&self.shared.sizes, self.slot as u64 * SIZE_BYTES, SIZE_BYTES)
    }

    fn block(&self, index: u32) -> wgpu::BindingResource<'a> {
        self.block_of(index, 16)
    }

    /// Parameter block `index` as a uniform of `bytes` bytes.
    fn block_of(&self, index: u32, bytes: u64) -> wgpu::BindingResource<'a> {
        slice(
            &self.shared.blocks,
            (self.slot as u64 * u64::from(BLOCKS) + u64::from(index)) * BLOCK_BYTES,
            bytes,
        )
    }

    fn triple(&self, triple: u32) -> u32 {
        self.slot as u32 * ARG_TRIPLES + triple
    }

    fn indirect(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        key: &'static str,
        bindings: &[Binding<'_>],
        triple: u32,
    ) -> Result<()> {
        self.gpu.dispatch_indirect(
            encoder,
            &self.gpu.kernel(key)?,
            key,
            bindings,
            &self.shared.args,
            self.triple(triple),
        )
    }

    fn clear(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        target: &LaniusBuffer<u8>,
        params: u32,
        triple: u32,
    ) -> Result<()> {
        self.indirect(
            encoder,
            CLEAR,
            &[
                ("gClear", self.block(params)),
                ("target", target.as_entire_binding()),
            ],
            triple,
        )
    }

    /// The three dispatches of an inclusive prefix sum whose parameters
    /// start at block `first_block`.
    fn scan(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        input: &LaniusBuffer<u8>,
        work: &[LaniusBuffer<u8>; 2],
        first_block: u32,
        tiles: u32,
        one: u32,
    ) -> Result<()> {
        let kernel = self.gpu.kernel(SCAN)?;
        for (mode, triple) in [(0, tiles), (1, one), (2, tiles)] {
            self.gpu.dispatch_indirect(
                encoder,
                &kernel,
                SCAN,
                &[
                    ("gScan", self.block(first_block + mode)),
                    ("scan_in", input.as_entire_binding()),
                    ("scan_tiles", work[1].as_entire_binding()),
                    ("scan_out", work[0].as_entire_binding()),
                ],
                &self.shared.args,
                self.triple(triple),
            )?;
        }
        Ok(())
    }

    /// One mode of the plan kernel. `feature` binds the prefix sums of the
    /// round's own kernels that the mode reads, then its status words.
    fn plan(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        mode: u32,
        feature: [&LaniusBuffer<u8>; 4],
    ) -> Result<()> {
        let params = self.gpu.fixed_uniform(
            &format!("desugar.plan.{}.{mode}", self.slot),
            &PlanParams {
                mode,
                feature: self.feature,
                first: u32::from(self.previous.is_none()),
                token_cap: self.caps.tokens as u32,
                piece_cap: self.caps.pieces as u32,
                out_cap: self.caps.out as u32,
                slot: self.slot as u32,
                previous: self.previous.unwrap_or(ROUNDS) as u32,
            },
        );
        let shared = self.shared;
        self.gpu.fixed_dispatch(
            encoder,
            &self.gpu.kernel(PLAN)?,
            "desugar.plan",
            &[
                ("gPlan", params.as_entire_binding()),
                ("gLex", self.bufs.params.as_entire_binding()),
                ("token_count", self.bufs.token_count.as_entire_binding()),
                (
                    "parser_feature_flags",
                    self.bufs.parser_feature_flags.as_entire_binding(),
                ),
                (
                    "lex_error_offset",
                    self.bufs.lex_error_offset.as_entire_binding(),
                ),
                (
                    "source_file_count",
                    self.bufs.source_file_count.as_entire_binding(),
                ),
                ("sizes", shared.sizes.as_entire_binding()),
                (
                    "args",
                    slice(&shared.args, self.slot as u64 * ARG_BYTES, ARG_BYTES),
                ),
                (
                    "blocks",
                    slice(
                        &shared.blocks,
                        self.slot as u64 * u64::from(BLOCKS) * BLOCK_BYTES,
                        u64::from(BLOCKS) * BLOCK_BYTES,
                    ),
                ),
                ("feat_a", feature[0].as_entire_binding()),
                ("feat_b", feature[1].as_entire_binding()),
                ("feat_c", feature[2].as_entire_binding()),
                ("fpiece_scan", shared.fpiece_work[0].as_entire_binding()),
                ("piece_scan", shared.piece_work[0].as_entire_binding()),
                ("region_scan", shared.text_work[0].as_entire_binding()),
                ("splice_scan", shared.splice_work[0].as_entire_binding()),
                ("status", feature[3].as_entire_binding()),
            ],
            1,
        )
    }

    /// The shared stages after a feature wrote its pieces: the expansion of
    /// token ranges, the text in the region, its tokens and the splice.
    fn finish(&self, encoder: &mut wgpu::CommandEncoder, constants: &Constants) -> Result<()> {
        let (shared, bufs) = (self.shared, self.bufs);
        let none = [&shared.fpieces; 4];
        self.scan(
            encoder,
            &shared.fpieces,
            &shared.fpiece_work,
            P_EXPAND_SCAN,
            A_EXPAND_SCAN,
            A_EXPAND_SCAN_ONE,
        )?;
        self.plan(encoder, PLAN_PLACE, none)?;
        self.indirect(
            encoder,
            EXPAND,
            &[
                ("sizes", self.sizes()),
                ("tokens_out", bufs.tokens_out.as_entire_binding()),
                ("in_bytes", bufs.in_bytes.as_entire_binding()),
                ("fpieces", shared.fpieces.as_entire_binding()),
                ("fpiece_owner", shared.fpiece_owner.as_entire_binding()),
                ("fpiece_scan", shared.fpiece_work[0].as_entire_binding()),
                ("const_index", constants.index.as_entire_binding()),
                ("pieces", shared.pieces.as_entire_binding()),
                ("piece_owner", shared.piece_owner.as_entire_binding()),
            ],
            A_PIECES,
        )?;
        self.scan(
            encoder,
            &shared.pieces,
            &shared.piece_work,
            P_PIECE_SCAN,
            A_PIECE_SCAN,
            A_PIECE_SCAN_ONE,
        )?;

        // The text in the region, then its tokens.
        self.plan(encoder, PLAN_REGION, none)?;
        self.indirect(
            encoder,
            EMIT,
            &[
                ("sizes", self.sizes()),
                ("in_bytes", bufs.in_bytes.as_entire_binding()),
                ("tokens_out", bufs.tokens_out.as_entire_binding()),
                ("pieces", shared.pieces.as_entire_binding()),
                ("piece_scan", shared.piece_work[0].as_entire_binding()),
                ("const_index", constants.index.as_entire_binding()),
                ("const_bytes", constants.bytes.as_entire_binding()),
                ("anchors", shared.anchors.as_entire_binding()),
                ("byte_piece", shared.byte_piece.as_entire_binding()),
            ],
            A_REGION_WORDS,
        )?;
        self.indirect(
            encoder,
            TEXT_MARKS,
            &[
                ("sizes", self.sizes()),
                ("in_bytes", bufs.in_bytes.as_entire_binding()),
                ("tokens_out", bufs.tokens_out.as_entire_binding()),
                ("pieces", shared.pieces.as_entire_binding()),
                ("piece_scan", shared.piece_work[0].as_entire_binding()),
                ("const_index", constants.index.as_entire_binding()),
                ("const_info", constants.info.as_entire_binding()),
                ("byte_piece", shared.byte_piece.as_entire_binding()),
                ("byte_info", shared.byte_info.as_entire_binding()),
                ("text_marks", shared.text_marks.as_entire_binding()),
            ],
            A_REGION_BYTES,
        )?;
        self.scan(
            encoder,
            &shared.text_marks,
            &shared.text_work,
            P_REGION_SCAN,
            A_REGION_SCAN,
            A_REGION_SCAN_ONE,
        )?;

        // The splice.
        self.plan(encoder, PLAN_SPLICE, none)?;
        self.indirect(
            encoder,
            SPLICE_MARKS,
            &[
                ("sizes", self.sizes()),
                ("drop", shared.drop.as_entire_binding()),
                ("splice_marks", shared.splice_marks.as_entire_binding()),
            ],
            A_SPLICE,
        )?;
        self.indirect(
            encoder,
            TEXT_TOKENS,
            &[
                ("sizes", self.sizes()),
                ("token_file_id", bufs.token_file_id.as_entire_binding()),
                ("pieces", shared.pieces.as_entire_binding()),
                ("piece_owner", shared.piece_owner.as_entire_binding()),
                ("byte_piece", shared.byte_piece.as_entire_binding()),
                ("byte_info", shared.byte_info.as_entire_binding()),
                ("text_scan", shared.text_work[0].as_entire_binding()),
                ("generated", shared.generated.as_entire_binding()),
                ("generated_file", shared.generated_file.as_entire_binding()),
                ("generated_owner", shared.generated_owner.as_entire_binding()),
            ],
            A_REGION_BYTES,
        )?;
        self.indirect(
            encoder,
            SPLICE_INSERTED,
            &[
                ("sizes", self.sizes()),
                ("generated_owner", shared.generated_owner.as_entire_binding()),
                ("splice_marks", shared.splice_marks.as_entire_binding()),
            ],
            A_GENERATED,
        )?;
        self.scan(
            encoder,
            &shared.splice_marks,
            &shared.splice_work,
            P_SPLICE_SCAN,
            A_SPLICE_SCAN,
            A_SPLICE_SCAN_ONE,
        )?;
        self.plan(encoder, PLAN_FINISH, none)?;
        self.indirect(
            encoder,
            SPLICE_KEPT,
            &[
                ("sizes", self.sizes()),
                ("tokens_out", bufs.tokens_out.as_entire_binding()),
                ("token_file_id", bufs.token_file_id.as_entire_binding()),
                ("splice_marks", shared.splice_marks.as_entire_binding()),
                ("splice_scan", shared.splice_work[0].as_entire_binding()),
                ("spliced", shared.spliced.as_entire_binding()),
                ("spliced_file", shared.spliced_file.as_entire_binding()),
            ],
            A_KEPT,
        )?;
        self.indirect(
            encoder,
            SPLICE_GENERATED,
            &[
                ("sizes", self.sizes()),
                ("generated", shared.generated.as_entire_binding()),
                ("generated_file", shared.generated_file.as_entire_binding()),
                ("generated_owner", shared.generated_owner.as_entire_binding()),
                ("splice_marks", shared.splice_marks.as_entire_binding()),
                ("splice_scan", shared.splice_work[0].as_entire_binding()),
                ("spliced", shared.spliced.as_entire_binding()),
                ("spliced_file", shared.spliced_file.as_entire_binding()),
            ],
            A_GENERATED,
        )?;
        self.indirect(
            encoder,
            COPY_BACK,
            &[
                ("sizes", self.sizes()),
                ("spliced", shared.spliced.as_entire_binding()),
                ("spliced_file", shared.spliced_file.as_entire_binding()),
                ("tokens_out", bufs.tokens_out.as_entire_binding()),
                ("token_file_id", bufs.token_file_id.as_entire_binding()),
            ],
            A_OUT,
        )
    }
}

fn scan_work(gpu: &Gpu<'_>, label: &str, rows: usize) -> [LaniusBuffer<u8>; 2] {
    let storage = |label: String, rows: usize| {
        gpu.fixed_storage(&label, rows.max(1) * 16, wgpu::BufferUsages::empty())
    };
    [
        storage(format!("{label}.0"), rows),
        storage(format!("{label}.1"), rows.div_ceil(SCAN_TILE_ROWS) + 1),
    ]
}

/// Records the desugaring after the lexer's token build.
pub(crate) fn record(ctx: &mut PassContext<'_, GpuBuffers, DebugOutput>) -> Result<()> {
    if SUSPENDED.with(|s| s.get()) {
        // This recording overwrites the lexer's tokens, so the last run can
        // no longer be explained from them.
        *LAST_RUN.lock().unwrap_or_else(PoisonError::into_inner) = None;
        return Ok(());
    }
    let device = crate::gpu::device::global();
    let gpu = Gpu {
        device: ctx.device,
        queue: &device.queue,
    };
    let bufs = ctx.buffers;
    let encoder = &mut *ctx.encoder;

    // Four bytes past the padded source, so a span at the end of the source
    // is never a region byte.
    let first_base = bufs.lexed_n.next_multiple_of(4) + 4;
    let region_cap = bufs.n.saturating_sub(first_base) as usize;
    let used = ROUNDS_USED.load(Ordering::Relaxed);
    let run = RUNS.fetch_add(1, Ordering::Relaxed) + 1;
    let mut last = LastRun {
        run,
        first_base,
        anchors: None,
        sizes: None,
        tokens_out: bufs
            .tokens_out
            .clone()
            .reinterpret::<u8>(bufs.tokens_out.byte_size),
        token_file_id: bufs
            .token_file_id
            .clone()
            .reinterpret::<u8>(bufs.token_file_id.byte_size),
        in_bytes: bufs.in_bytes.clone(),
        closures: None,
        generators: None,
        machines: None,
    };
    // Without a region nothing is recorded: the host sees a feature in the
    // feature word and runs the build again with a region (`stop`). The
    // lexer's buffers are kept for the reserved names (`reserved`).
    if region_cap == 0 || used == 0 {
        RECORDED.with(|recorded| recorded.set(run));
        *LAST_RUN.lock().unwrap_or_else(PoisonError::into_inner) = Some(last);
        return Ok(());
    }
    gpu::drop_stale_bind_groups();
    let caps = Caps {
        tokens: (TOKEN_ROWS.load(Ordering::Relaxed) as usize).max(1),
        pieces: (PIECE_ROWS.load(Ordering::Relaxed) as usize).max(1),
        out: (OUT_ROWS.load(Ordering::Relaxed) as usize)
            .min(bufs.tokens_out.count)
            .max(1),
    };
    let rows = caps.tokens;
    let region_rows = region_cap.max(1);
    let storage = |label: &str, rows: usize, words: usize| {
        gpu.fixed_storage(label, rows.max(1) * words * 4, wgpu::BufferUsages::empty())
    };
    let shared = Shared {
        sizes: storage("desugar.sizes", (ROUNDS + 1) * SIZE_WORDS, 1),
        args: gpu.fixed_storage(
            "desugar.args",
            ROUNDS * ARG_BYTES as usize,
            wgpu::BufferUsages::INDIRECT,
        ),
        blocks: gpu.fixed_storage(
            "desugar.blocks",
            ROUNDS * (BLOCKS as u64 * BLOCK_BYTES) as usize,
            wgpu::BufferUsages::UNIFORM,
        ),
        fpieces: storage("desugar.fpieces", caps.pieces, 4),
        fpiece_owner: storage("desugar.fpiece_owner", caps.pieces, 1),
        fpiece_work: scan_work(&gpu, "desugar.fpiece_scan", caps.pieces),
        pieces: storage("desugar.pieces", caps.pieces, 4),
        piece_owner: storage("desugar.piece_owner", caps.pieces, 1),
        piece_work: scan_work(&gpu, "desugar.piece_scan", caps.pieces),
        drop: storage("desugar.drop", rows, 1),
        anchors: storage("desugar.anchors", region_rows, 1),
        byte_piece: storage("desugar.byte_piece", region_rows, 1),
        byte_info: storage("desugar.byte_info", region_rows, 1),
        text_marks: storage("desugar.text_marks", region_rows, 4),
        text_work: scan_work(&gpu, "desugar.text_scan", region_rows),
        generated: storage("desugar.generated", region_rows, 3),
        generated_file: storage("desugar.generated_file", region_rows, 1),
        generated_owner: storage("desugar.generated_owner", region_rows, 1),
        splice_marks: storage("desugar.splice_marks", rows, 4),
        splice_work: scan_work(&gpu, "desugar.splice_scan", rows),
        spliced: storage("desugar.spliced", caps.out, 3),
        spliced_file: storage("desugar.spliced_file", caps.out, 1),
    };
    if crate::gpu::passes_core::host_timing_enabled() {
        eprintln!(
            "[gpu_compile_host_timer] desugar.buffers: rounds={used:#x} token_cap={} piece_cap={} region_cap={region_cap} out_cap={} lexed={} extent={}",
            caps.tokens, caps.pieces, caps.out, bufs.lexed_n, bufs.n
        );
    }

    last.anchors = Some(shared.anchors.clone());
    last.sizes = Some(shared.sizes.clone());
    let mut previous = None;
    for (slot, &feature) in ROUND_FEATURES.iter().enumerate() {
        if used & feature == 0 {
            continue;
        }
        let round = Round {
            gpu: &gpu,
            bufs,
            shared: &shared,
            caps,
            slot,
            previous,
            feature,
        };
        if feature == PARSER_FEATURE_CLOSURES {
            last.closures = Some(closures::record(&round, encoder)?);
        } else if feature == PARSER_FEATURE_GENERATORS {
            last.generators = Some(generators::record(&round, encoder)?);
        } else if feature == PARSER_FEATURE_MACHINES {
            last.machines = Some(machines::record(&round, encoder)?);
        }
        previous = Some(slot);
    }
    RECORDED.with(|recorded| recorded.set(run));
    *LAST_RUN.lock().unwrap_or_else(PoisonError::into_inner) = Some(last);
    Ok(())
}

#[cfg(test)]
pub(crate) use tests::accepts;

#[cfg(test)]
mod tests;
