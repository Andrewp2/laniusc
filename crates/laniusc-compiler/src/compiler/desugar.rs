//! Desugaring of machines in the token stream (docs/state-machines-design.md,
//! "Desugaring in the lexer").
//!
//! The desugaring is the last stage of the frontend lexer. It reads the token
//! rows the lexer built and writes the token rows of the desugared program.
//! The text of the generated tokens goes into a region of the lexer's byte
//! buffer after the source bytes, so every later kernel reads their names
//! from token bytes as it reads source names.
//!
//! Every dispatch is recorded before any count is known. A plan kernel
//! (shaders/desugar/plan.slang) turns the counts of one stage into the
//! indirect dispatch sizes and kernel parameters of the next, so a pack
//! without a machine runs every dispatch with zero workgroups and the host
//! reads nothing back. The host reads the outcome with the token count it
//! already reads: `DESUGAR_REGION_OVERFLOW` asks for a larger region and a
//! second run, `DESUGAR_RULE_ERROR` for the diagnostic of a broken rule.

use std::{
    num::NonZeroU64,
    path::Path,
    sync::{
        Mutex,
        PoisonError,
        atomic::{AtomicU32, Ordering},
    },
};

use anyhow::{Context, Result};

use super::{
    CompileError,
    Diagnostic,
    DiagnosticSourceFile,
    diagnostic_label_from_source_span,
    machine_elaboration::{
        MACHINE_CODE,
        MACHINE_TITLE,
        closures::{Binding, Gpu},
        machines::{
            CONSTANTS,
            DETAIL_WORDS,
            INFO_WORDS,
            NO_ERROR,
            REACH_STEPS,
            RECORD_WORDS,
            RuleError,
            STATE_ROW_WORDS,
            STATUS_WORDS,
            rule_error,
        },
    },
    source_pack_file_for_global_span,
};
use crate::{
    gpu::{buffers::LaniusBuffer, passes_core::PassContext},
    lexer::{
        buffers::GpuBuffers,
        debug::DebugOutput,
        features::PARSER_FEATURE_MACHINES,
        tables::tokens::TokenKind,
    },
};

/// The bit the lexer's feature word carries when the generated text did not
/// fit the region; the build runs again with a larger one.
pub(crate) const DESUGAR_REGION_OVERFLOW: u32 = 0x4000_0000;
/// The bit the lexer's feature word carries when a machine breaks a rule.
pub(crate) const DESUGAR_RULE_ERROR: u32 = 0x8000_0000;
/// The bits of the feature word that are not parser families.
pub(crate) const DESUGAR_BITS: u32 = DESUGAR_REGION_OVERFLOW | DESUGAR_RULE_ERROR;

/// Bytes of the region after the source that the next lexer allocation
/// reserves for generated token text. It starts at zero, so a build without
/// a machine allocates and dispatches nothing for the desugaring. A build
/// whose generated text does not fit raises it and runs again; it does not
/// shrink, so later builds of the same program do not run twice.
static REGION_FLOOR: AtomicU32 = AtomicU32::new(0);
/// Rows of the per-token buffers, of the pieces and of the spliced tokens.
/// The plan kernel checks each against its count, and the floors grow like
/// the region.
static TOKEN_ROWS: AtomicU32 = AtomicU32::new(0);
static PIECE_ROWS: AtomicU32 = AtomicU32::new(0);
static OUT_ROWS: AtomicU32 = AtomicU32::new(0);

thread_local! {
    static SUSPENDED: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

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
    raise(&TOKEN_ROWS, headroom(tokens.max(token_count)));
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

/// What the last run needed of each floor, read from the GPU after it
/// overflowed.
fn last_needs() -> [u32; 4] {
    let Some(last) = LAST_RUN
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .clone()
    else {
        return [0; 4];
    };
    read_words(&[(&last.sizes, S_NEED_TOKENS, 4)], None)
        .ok()
        .and_then(|mut reads| reads.pop()?.try_into().ok())
        .unwrap_or([0; 4])
}

/// Runs `f` with the desugaring switched off for lexer recordings on this
/// thread. The text rewrites of generators and closures lex the source for
/// their own selection and parse; those lexes must see the source tokens.
pub(crate) fn without_desugaring<T>(f: impl FnOnce() -> T) -> T {
    let previous = SUSPENDED.with(|s| s.replace(true));
    let out = f();
    SUSPENDED.with(|s| s.set(previous));
    out
}

// Layout of shaders/desugar/desugar_common.slang.
const S_MACHINES: usize = 1;
const S_STATES: usize = 2;
const S_LIVE: usize = 4;
const S_REGION: usize = 6;
const S_NEED_TOKENS: usize = 13;
const SIZE_WORDS: usize = 20;
const A_TOKENS: u32 = 0;
const A_TOKEN_SCAN: u32 = 1;
const A_TOKEN_SCAN_ONE: u32 = 2;
const A_RECORD_WORDS: u32 = 3;
const A_LIVE: u32 = 4;
const A_LIVE_SCAN: u32 = 5;
const A_LIVE_SCAN_ONE: u32 = 6;
const A_INFO_WORDS: u32 = 7;
const A_STATES: u32 = 8;
const A_STATE_WORDS: u32 = 9;
const A_WRITE: u32 = 10;
const A_PIECE_SCAN: u32 = 11;
const A_PIECE_SCAN_ONE: u32 = 12;
const A_REGION_WORDS: u32 = 13;
const A_REGION_BYTES: u32 = 14;
const A_REGION_SCAN: u32 = 15;
const A_REGION_SCAN_ONE: u32 = 16;
const A_SPLICE: u32 = 17;
const A_SPLICE_SCAN: u32 = 18;
const A_SPLICE_SCAN_ONE: u32 = 19;
const A_GENERATED: u32 = 20;
const A_OUT: u32 = 21;
const ARG_TRIPLES: usize = 22;
const BLOCK_BYTES: u64 = 256;
const SCAN_TILE_ROWS: usize = 2048;
const P_TOKENS: u32 = 0;
const P_CLEAR_RECORDS: u32 = 1;
const P_SCAN_TOKENS: u32 = 2;
const P_LIVE: u32 = 5;
const P_LISTS_A: u32 = 6;
const P_LISTS_B: u32 = 7;
const P_SCAN_LIVE: u32 = 8;
const P_CLEAR_INFO: u32 = 11;
const P_CLEAR_STATES: u32 = 12;
const P_RESOLVE: u32 = 13;
const P_CHECK: u32 = 14;
const P_STATES: u32 = 15;
const P_STATE_CHECK: u32 = 16;
const P_COUNT: u32 = 17;
const P_WRITE: u32 = 18;
const P_SCAN_PIECES: u32 = 19;
const P_EMIT: u32 = 22;
const P_SCAN_REGION: u32 = 23;
const P_SCAN_SPLICE: u32 = 26;
const BLOCKS: usize = 29;
const PLAN_TOKENS: u32 = 0;
const PLAN_MACHINES: u32 = 1;
const PLAN_PIECES: u32 = 2;
const PLAN_REGION: u32 = 3;
const PLAN_SPLICE: u32 = 4;
const PLAN_FINISH: u32 = 5;

/// Kernels of the desugaring, by shader artifact key.
const PLAN: &str = "desugar/plan";
const CLEAR: &str = "desugar/clear";
const READ: &str = "machines/read";
const MARKS: &str = "machines/marks";
const SCAN: &str = "closures/scan";
const LISTS: &str = "machines/lists";
const CONTEXT: &str = "machines/context";
const RESOLVE: &str = "machines/resolve";
const ARMS: &str = "machines/arms";
const REACH: &str = "machines/reach";
const STATES: &str = "machines/states";
const PIECES: &str = "machines/pieces";
const EMIT: &str = "machines/emit";
const TEXT_MARKS: &str = "desugar/text_marks";
const TEXT_TOKENS: &str = "desugar/text_tokens";
const SPLICE_MARKS: &str = "desugar/splice_marks";
const SPLICE_KEPT: &str = "desugar/splice_kept";
const SPLICE_GENERATED: &str = "desugar/splice_generated";
const COPY_BACK: &str = "desugar/copy_back";

#[derive(encase::ShaderType)]
struct PlanParams {
    mode: u32,
    piece_cap: u32,
    token_cap: u32,
    out_cap: u32,
}

/// What a diagnostic or the explanation of a broken rule needs from the last
/// run: where the region starts, the anchor of each of its bytes and the
/// buffers the rules read and wrote.
#[derive(Clone)]
struct LastRun {
    region_base: u32,
    anchors: LaniusBuffer<u8>,
    sizes: LaniusBuffer<u8>,
    status: LaniusBuffer<u8>,
    detail: LaniusBuffer<u8>,
    tokens_out: LaniusBuffer<u8>,
    token_file_id: LaniusBuffer<u8>,
    in_bytes: LaniusBuffer<u8>,
    records: LaniusBuffer<u8>,
    scan_a: LaniusBuffer<u8>,
    scan_b: LaniusBuffer<u8>,
    machines: LaniusBuffer<u8>,
    states: LaniusBuffer<u8>,
    arms: LaniusBuffer<u8>,
    variants: LaniusBuffer<u8>,
    machine_info: LaniusBuffer<u8>,
    arm_event: LaniusBuffer<u8>,
    adjacency: LaniusBuffer<u8>,
    reach: LaniusBuffer<u8>,
}

static LAST_RUN: Mutex<Option<LastRun>> = Mutex::new(None);

/// Per byte of the constant strings: bit 0 when it is part of a token, bit 1
/// when a token starts at it, and from bit 8 the kind of that token. The
/// strings are fixed, so the table is too; a test checks it against the GPU
/// lexer.
pub(crate) fn constant_token_info() -> Vec<u32> {
    let mut info = Vec::new();
    for text in CONSTANTS {
        info.extend(token_info(text));
    }
    info.resize(info.len().next_multiple_of(4).max(4), 0);
    info
}

fn token_info(text: &str) -> Vec<u32> {
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
            let kind = match &text[at..at + len] {
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
                _ => TokenKind::Ident,
            };
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

/// The source byte of global position `at` when it lies in the region of the
/// last run, read from the GPU. Diagnostics call it for a span past the
/// source; a build without a machine never makes one.
pub(crate) fn source_position(at: usize) -> Option<usize> {
    let last = LAST_RUN
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .clone()?;
    let offset = at.checked_sub(last.region_base as usize)?;
    if (offset + 1) * 4 > last.anchors.byte_size {
        return None;
    }
    let reads = read_words(
        &[(&last.sizes, S_REGION, 1), (&last.anchors, offset, 1)],
        None,
    )
    .ok()?;
    (offset < reads[0][0] as usize).then(|| reads[1][0] as usize)
}

/// Why the lexer's run did not finish the desugaring.
pub(in crate::compiler) enum Stop {
    /// The generated text did not fit; the region is larger now.
    Retry,
    /// A machine breaks a rule.
    Rejected(RuleError),
}

/// Whether the lexer's feature word says the desugaring did not finish. The
/// caller calls `stop` once the lexer's buffers are free.
pub(crate) fn stopped(raw_features: u32) -> bool {
    raw_features & DESUGAR_BITS != 0
        || (raw_features & PARSER_FEATURE_MACHINES != 0
            && REGION_FLOOR.load(Ordering::Relaxed) == 0)
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
    if raw_features & DESUGAR_RULE_ERROR != 0 {
        return Some(match explain(text) {
            Ok(rule) => Stop::Rejected(rule),
            Err(err) => Stop::Rejected(RuleError {
                start: 0,
                len: 1,
                message: format!(
                    "the compiler stopped while explaining an invalid machine: {err:#}"
                ),
                help: None,
            }),
        });
    }
    // A build without a region records no desugaring.
    let unrecorded =
        raw_features & PARSER_FEATURE_MACHINES != 0 && REGION_FLOOR.load(Ordering::Relaxed) == 0;
    if raw_features & DESUGAR_REGION_OVERFLOW != 0 || unrecorded {
        let needs = if unrecorded { [0; 4] } else { last_needs() };
        grow(
            needs,
            token_count,
            u32::try_from(source_bytes).unwrap_or(u32::MAX),
        );
        return Some(Stop::Retry);
    }
    None
}

/// Runs the rules of the last run again to write the spans of its first
/// error, and builds the message.
fn explain(text: impl Fn(usize, usize) -> String) -> Result<RuleError> {
    let last = LAST_RUN
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .clone();
    let last = last
        .as_ref()
        .context("the desugaring kept no run to explain")?;
    let device = crate::gpu::device::global();
    let gpu = Gpu {
        device: &device.device,
        queue: &device.queue,
    };
    let reads = read_words(
        &[
            (&last.sizes, 0, SIZE_WORDS),
            (&last.status, 0, STATUS_WORDS),
        ],
        None,
    )?;
    let (sizes, status) = (&reads[0], &reads[1]);
    let word = status
        .iter()
        .position(|&key| key != NO_ERROR)
        .context("no machine rule failed")?;
    let key = status[word];
    let (live, machine_count, state_count) = (sizes[S_LIVE], sizes[S_MACHINES], sizes[S_STATES]);

    let mut encoder = gpu.encoder("desugar.explain");
    let explain = [word as u32, key];
    let params = |label: &str, a: u32, b: u32| {
        gpu.fixed_uniform(
            label,
            &ExplainParams {
                a,
                b,
                word: explain[0],
                key: explain[1],
            },
        )
    };
    let resolve_params = params("desugar.explain.resolve", live, machine_count);
    gpu.fixed_dispatch(
        &mut encoder,
        &gpu.kernel(RESOLVE)?,
        RESOLVE,
        &[
            ("gResolve", resolve_params.as_entire_binding()),
            ("tokens_out", last.tokens_out.as_entire_binding()),
            ("token_file_id", last.token_file_id.as_entire_binding()),
            ("in_bytes", last.in_bytes.as_entire_binding()),
            ("records", last.records.as_entire_binding()),
            ("scan_a", last.scan_a.as_entire_binding()),
            ("scan_b", last.scan_b.as_entire_binding()),
            ("machines", last.machines.as_entire_binding()),
            ("states", last.states.as_entire_binding()),
            ("arms", last.arms.as_entire_binding()),
            ("machine_info", last.machine_info.as_entire_binding()),
            ("adjacency", last.adjacency.as_entire_binding()),
            ("status", last.status.as_entire_binding()),
            ("detail", last.detail.as_entire_binding()),
        ],
        live,
    )?;
    let arm_params = params("desugar.explain.arms", live, 0);
    gpu.fixed_dispatch(
        &mut encoder,
        &gpu.kernel(ARMS)?,
        ARMS,
        &[
            ("gArms", arm_params.as_entire_binding()),
            ("tokens_out", last.tokens_out.as_entire_binding()),
            ("in_bytes", last.in_bytes.as_entire_binding()),
            ("records", last.records.as_entire_binding()),
            ("scan_a", last.scan_a.as_entire_binding()),
            ("scan_b", last.scan_b.as_entire_binding()),
            ("machines", last.machines.as_entire_binding()),
            ("states", last.states.as_entire_binding()),
            ("arms", last.arms.as_entire_binding()),
            ("variants", last.variants.as_entire_binding()),
            ("machine_info", last.machine_info.as_entire_binding()),
            ("arm_event", last.arm_event.as_entire_binding()),
            ("status", last.status.as_entire_binding()),
            ("detail", last.detail.as_entire_binding()),
        ],
        live,
    )?;
    if state_count > 0 {
        let state_params = params("desugar.explain.states", state_count, 0);
        gpu.fixed_dispatch(
            &mut encoder,
            &gpu.kernel(STATES)?,
            STATES,
            &[
                ("gStates", state_params.as_entire_binding()),
                ("tokens_out", last.tokens_out.as_entire_binding()),
                ("records", last.records.as_entire_binding()),
                ("scan_a", last.scan_a.as_entire_binding()),
                ("scan_b", last.scan_b.as_entire_binding()),
                ("machines", last.machines.as_entire_binding()),
                ("states", last.states.as_entire_binding()),
                ("variants", last.variants.as_entire_binding()),
                ("machine_info", last.machine_info.as_entire_binding()),
                ("arm_event", last.arm_event.as_entire_binding()),
                ("adjacency", last.adjacency.as_entire_binding()),
                ("reach", last.reach.as_entire_binding()),
                ("status", last.status.as_entire_binding()),
                ("detail", last.detail.as_entire_binding()),
            ],
            state_count,
        )?;
    }
    let detail = read_words(&[(&last.detail, 0, DETAIL_WORDS)], Some(encoder))?.remove(0);
    Ok(rule_error(word, key, &detail, |start, len| {
        text(start as usize, len as usize)
    }))
}

#[derive(encase::ShaderType)]
struct ExplainParams {
    a: u32,
    b: u32,
    word: u32,
    key: u32,
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

/// The diagnostic of a broken machine rule in a single source.
pub(in crate::compiler) fn rejected_in_source(
    path: &Path,
    source: &str,
    rule: RuleError,
) -> CompileError {
    rule_diagnostic(path, source, rule.start, rule)
}

/// The diagnostic of a broken machine rule in a source pack.
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
    let diagnostic = Diagnostic::error(MACHINE_CODE, MACHINE_TITLE).with_primary_label(
        diagnostic_label_from_source_span(path, source, start, rule.len, rule.message),
    );
    CompileError::Diagnostic(match rule.help {
        Some(help) => diagnostic.with_help(help),
        None => diagnostic,
    })
}

/// The constant strings the pieces insert, and where each one starts.
fn constant_table(gpu: &Gpu<'_>) -> (LaniusBuffer<u8>, LaniusBuffer<u8>) {
    let mut index = Vec::with_capacity(CONSTANTS.len() * 2);
    let mut bytes = Vec::new();
    for text in CONSTANTS {
        index.extend([bytes.len() as u32, text.len() as u32]);
        bytes.extend_from_slice(text.as_bytes());
    }
    bytes.resize(bytes.len().next_multiple_of(4), 0);
    let words: Vec<u32> = bytes
        .chunks_exact(4)
        .map(|w| u32::from_le_bytes([w[0], w[1], w[2], w[3]]))
        .collect();
    (
        gpu.fixed_words_from("desugar.const_index", &index),
        gpu.fixed_words_from("desugar.const_bytes", &words),
    )
}

/// One parameter buffer per plan mode.
const PLAN_PARAMS: [&str; 6] = [
    "desugar.plan.0",
    "desugar.plan.1",
    "desugar.plan.2",
    "desugar.plan.3",
    "desugar.plan.4",
    "desugar.plan.5",
];

fn block(blocks: &LaniusBuffer<u8>, index: u32) -> wgpu::BindingResource<'_> {
    wgpu::BindingResource::Buffer(wgpu::BufferBinding {
        buffer: &blocks.buffer,
        offset: blocks.byte_offset + u64::from(index) * BLOCK_BYTES,
        size: NonZeroU64::new(16),
    })
}

/// Records the desugaring after the lexer's token build.
pub(crate) fn record(ctx: &mut PassContext<'_, GpuBuffers, DebugOutput>) -> Result<()> {
    if SUSPENDED.with(|s| s.get()) {
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
    let region_base = bufs.lexed_n.next_multiple_of(4) + 4;
    let region_cap = bufs.n.saturating_sub(region_base) as usize;
    // Without a region nothing is recorded: the host sees a machine in the
    // feature word and runs the build again with a region (`stop`).
    if region_cap == 0 {
        *LAST_RUN.lock().unwrap_or_else(PoisonError::into_inner) = None;
        return Ok(());
    }
    let token_cap = TOKEN_ROWS.load(Ordering::Relaxed) as usize;
    let out_cap = (OUT_ROWS.load(Ordering::Relaxed) as usize).min(bufs.tokens_out.count);
    let piece_cap = PIECE_ROWS.load(Ordering::Relaxed) as usize;
    let rows = token_cap.max(1);
    // A machine or a state takes at least four tokens; the plan checks it.
    let machine_rows = rows / 4 + 1;
    let region_rows = region_cap.max(1);
    let piece_rows = piece_cap.max(1);
    let out_rows = out_cap.max(1);
    let storage = |label: &str, rows: usize, words: usize| {
        gpu.fixed_storage(label, rows * words * 4, wgpu::BufferUsages::empty())
    };
    // The pair of a prefix sum: the sums, and the totals of its tiles.
    let scan_work = |label: &str, rows: usize| {
        [
            storage(&format!("{label}.0"), rows, 4),
            storage(&format!("{label}.1"), rows.div_ceil(SCAN_TILE_ROWS) + 1, 4),
        ]
    };

    let sizes = storage("desugar.sizes", SIZE_WORDS, 1);
    let args = gpu.fixed_storage(
        "desugar.args",
        ARG_TRIPLES * 12,
        wgpu::BufferUsages::INDIRECT,
    );
    let blocks = gpu.fixed_storage(
        "desugar.blocks",
        BLOCKS * BLOCK_BYTES as usize,
        wgpu::BufferUsages::UNIFORM,
    );
    let records = storage("desugar.records", rows, RECORD_WORDS);
    let marks = storage("desugar.marks", rows, 4);
    let work_a = scan_work("desugar.scan_a", rows);
    let marks_b = storage("desugar.marks_b", rows, 4);
    let work_b = scan_work("desugar.scan_b", rows);
    let list = |label: &str| storage(label, rows, 1);
    let (machines, states, transitions, unused) = (
        list("desugar.machines"),
        list("desugar.states"),
        list("desugar.transitions"),
        storage("desugar.unused", 1, 1),
    );
    let (arms, fields, arguments, variants) = (
        list("desugar.arms"),
        list("desugar.fields"),
        list("desugar.arguments"),
        list("desugar.variants"),
    );
    let status = gpu.fixed_words_from("desugar.status", &[NO_ERROR; STATUS_WORDS + 1]);
    let detail = storage("desugar.detail", DETAIL_WORDS, 1);
    let machine_info = storage("desugar.machine_info", machine_rows, INFO_WORDS);
    let arm_event = list("desugar.arm_event");
    let adjacency = storage("desugar.adjacency", machine_rows, STATE_ROW_WORDS);
    let reach_work = [
        storage("desugar.reach.0", machine_rows, STATE_ROW_WORDS),
        storage("desugar.reach.1", machine_rows, STATE_ROW_WORDS),
    ];
    let counts = [
        storage("desugar.counts0", rows, 4),
        storage("desugar.counts1", rows, 4),
    ];
    let count_work = [
        scan_work("desugar.counts0", rows),
        scan_work("desugar.counts1", rows),
    ];
    let pieces = storage("desugar.pieces", piece_rows, 4);
    let piece_sources = storage("desugar.piece_sources", piece_rows, 4);
    let piece_work = scan_work("desugar.piece_scan", piece_rows);
    let anchors = storage("desugar.anchors", region_rows, 1);
    let byte_piece = storage("desugar.byte_piece", region_rows, 1);
    let byte_info = storage("desugar.byte_info", region_rows, 1);
    let text_marks = storage("desugar.text_marks", region_rows, 4);
    let text_work = scan_work("desugar.text_scan", region_rows);
    let generated = storage("desugar.generated", region_rows, 3);
    let generated_file = storage("desugar.generated_file", region_rows, 1);
    let generated_machine = storage("desugar.generated_machine", region_rows, 1);
    let machine_tokens = storage("desugar.machine_tokens", machine_rows, 4);
    let splice_marks = storage("desugar.splice_marks", rows, 4);
    let splice_work = scan_work("desugar.splice_scan", rows);
    let spliced = storage("desugar.spliced", out_rows, 3);
    let spliced_file = storage("desugar.spliced_file", out_rows, 1);
    if crate::gpu::passes_core::host_timing_enabled() {
        eprintln!(
            "[gpu_compile_host_timer] desugar.buffers: token_cap={token_cap} piece_cap={piece_cap} region_cap={region_cap} out_cap={out_cap} lexed={} extent={}",
            bufs.lexed_n, bufs.n
        );
    }
    let (const_index, const_bytes) = constant_table(&gpu);
    let const_info = gpu.fixed_words_from("desugar.const_info", &constant_token_info());

    let plan_kernel = gpu.kernel(PLAN)?;
    let clear_kernel = gpu.kernel(CLEAR)?;
    let scan_kernel = gpu.kernel(SCAN)?;
    let list_kernel = gpu.kernel(LISTS)?;
    let piece_kernel = gpu.kernel(PIECES)?;
    let scan_a = &work_a[0];
    let scan_b = &work_b[0];
    let count_scans = [&count_work[0][0], &count_work[1][0]];
    let piece_scan = &piece_work[0];
    let text_scan = &text_work[0];
    let splice_scan = &splice_work[0];

    let plan = |encoder: &mut wgpu::CommandEncoder, mode: u32| -> Result<()> {
        let params = gpu.fixed_uniform(
            PLAN_PARAMS[mode as usize],
            &PlanParams {
                mode,
                piece_cap: piece_cap as u32,
                token_cap: token_cap as u32,
                out_cap: out_cap as u32,
            },
        );
        gpu.fixed_dispatch(
            encoder,
            &plan_kernel,
            "desugar.plan",
            &[
                ("gPlan", params.as_entire_binding()),
                ("gLex", bufs.params.as_entire_binding()),
                ("token_count", bufs.token_count.as_entire_binding()),
                (
                    "parser_feature_flags",
                    bufs.parser_feature_flags.as_entire_binding(),
                ),
                (
                    "lex_error_offset",
                    bufs.lex_error_offset.as_entire_binding(),
                ),
                ("sizes", sizes.as_entire_binding()),
                ("args", args.as_entire_binding()),
                ("blocks", blocks.as_entire_binding()),
                ("scan_a", scan_a.as_entire_binding()),
                ("count_scan0", count_scans[0].as_entire_binding()),
                ("count_scan1", count_scans[1].as_entire_binding()),
                ("status", status.as_entire_binding()),
                ("piece_scan", piece_scan.as_entire_binding()),
                ("region_scan", text_scan.as_entire_binding()),
                ("splice_scan", splice_scan.as_entire_binding()),
            ],
            1,
        )
    };
    let indirect = |encoder: &mut wgpu::CommandEncoder,
                    key: &'static str,
                    bindings: &[Binding<'_>],
                    triple: u32| {
        gpu.dispatch_indirect(encoder, &gpu.kernel(key)?, key, bindings, &args, triple)
    };
    let clear = |encoder: &mut wgpu::CommandEncoder,
                 target: &LaniusBuffer<u8>,
                 params: u32,
                 triple: u32| {
        gpu.dispatch_indirect(
            encoder,
            &clear_kernel,
            CLEAR,
            &[
                ("gClear", block(&blocks, params)),
                ("target", target.as_entire_binding()),
            ],
            &args,
            triple,
        )
    };
    let scan = |encoder: &mut wgpu::CommandEncoder,
                input: &LaniusBuffer<u8>,
                work: &[LaniusBuffer<u8>; 2],
                first_block: u32,
                tiles: u32,
                one: u32|
     -> Result<()> {
        for (mode, triple) in [(0, tiles), (1, one), (2, tiles)] {
            gpu.dispatch_indirect(
                encoder,
                &scan_kernel,
                SCAN,
                &[
                    ("gScan", block(&blocks, first_block + mode)),
                    ("scan_in", input.as_entire_binding()),
                    ("scan_tiles", work[1].as_entire_binding()),
                    ("scan_out", work[0].as_entire_binding()),
                ],
                &args,
                triple,
            )?;
        }
        Ok(())
    };
    let lists = |encoder: &mut wgpu::CommandEncoder,
                 params: u32,
                 marks: &LaniusBuffer<u8>,
                 scan: &LaniusBuffer<u8>,
                 out: [&LaniusBuffer<u8>; 4]|
     -> Result<()> {
        gpu.dispatch_indirect(
            encoder,
            &list_kernel,
            LISTS,
            &[
                ("gLists", block(&blocks, params)),
                ("marks", marks.as_entire_binding()),
                ("scan", scan.as_entire_binding()),
                ("list_x", out[0].as_entire_binding()),
                ("list_y", out[1].as_entire_binding()),
                ("list_z", out[2].as_entire_binding()),
                ("list_w", out[3].as_entire_binding()),
            ],
            &args,
            A_LIVE,
        )
    };

    // Records and the numbering of machines, states and transitions.
    plan(encoder, PLAN_TOKENS)?;
    clear(encoder, &records, P_CLEAR_RECORDS, A_RECORD_WORDS)?;
    indirect(
        encoder,
        READ,
        &[
            ("gRead", block(&blocks, P_TOKENS)),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("token_file_id", bufs.token_file_id.as_entire_binding()),
            ("records", records.as_entire_binding()),
        ],
        A_TOKENS,
    )?;
    indirect(
        encoder,
        MARKS,
        &[
            ("gMarks", block(&blocks, P_TOKENS)),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("marks", marks.as_entire_binding()),
        ],
        A_TOKENS,
    )?;
    scan(
        encoder,
        &marks,
        &work_a,
        P_SCAN_TOKENS,
        A_TOKEN_SCAN,
        A_TOKEN_SCAN_ONE,
    )?;

    // The lists, then the rules.
    plan(encoder, PLAN_MACHINES)?;
    clear(encoder, &machine_info, P_CLEAR_INFO, A_INFO_WORDS)?;
    clear(encoder, &adjacency, P_CLEAR_STATES, A_STATE_WORDS)?;
    clear(encoder, &arm_event, P_LIVE, A_LIVE)?;
    lists(
        encoder,
        P_LISTS_A,
        &marks,
        scan_a,
        [&machines, &states, &transitions, &unused],
    )?;
    indirect(
        encoder,
        CONTEXT,
        &[
            ("gContext", block(&blocks, P_LIVE)),
            ("records", records.as_entire_binding()),
            ("scan_a", scan_a.as_entire_binding()),
            ("states", states.as_entire_binding()),
            ("transitions", transitions.as_entire_binding()),
            ("marks", marks_b.as_entire_binding()),
        ],
        A_LIVE,
    )?;
    scan(
        encoder,
        &marks_b,
        &work_b,
        P_SCAN_LIVE,
        A_LIVE_SCAN,
        A_LIVE_SCAN_ONE,
    )?;
    lists(
        encoder,
        P_LISTS_B,
        &marks_b,
        scan_b,
        [&arms, &fields, &arguments, &variants],
    )?;
    indirect(
        encoder,
        RESOLVE,
        &[
            ("gResolve", block(&blocks, P_RESOLVE)),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("token_file_id", bufs.token_file_id.as_entire_binding()),
            ("in_bytes", bufs.in_bytes.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("scan_a", scan_a.as_entire_binding()),
            ("scan_b", scan_b.as_entire_binding()),
            ("machines", machines.as_entire_binding()),
            ("states", states.as_entire_binding()),
            ("arms", arms.as_entire_binding()),
            ("machine_info", machine_info.as_entire_binding()),
            ("adjacency", adjacency.as_entire_binding()),
            ("status", status.as_entire_binding()),
            ("detail", detail.as_entire_binding()),
        ],
        A_LIVE,
    )?;
    indirect(
        encoder,
        ARMS,
        &[
            ("gArms", block(&blocks, P_CHECK)),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("in_bytes", bufs.in_bytes.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("scan_a", scan_a.as_entire_binding()),
            ("scan_b", scan_b.as_entire_binding()),
            ("machines", machines.as_entire_binding()),
            ("states", states.as_entire_binding()),
            ("arms", arms.as_entire_binding()),
            ("variants", variants.as_entire_binding()),
            ("machine_info", machine_info.as_entire_binding()),
            ("arm_event", arm_event.as_entire_binding()),
            ("status", status.as_entire_binding()),
            ("detail", detail.as_entire_binding()),
        ],
        A_LIVE,
    )?;
    let reach_kernel = gpu.kernel(REACH)?;
    let mut reach = &adjacency;
    for step in 0..REACH_STEPS {
        let next = &reach_work[step % 2];
        gpu.dispatch_indirect(
            encoder,
            &reach_kernel,
            REACH,
            &[
                ("gReach", block(&blocks, P_STATES)),
                ("records", records.as_entire_binding()),
                ("scan_a", scan_a.as_entire_binding()),
                ("machines", machines.as_entire_binding()),
                ("states", states.as_entire_binding()),
                ("rows_in", reach.as_entire_binding()),
                ("rows_out", next.as_entire_binding()),
            ],
            &args,
            A_STATES,
        )?;
        reach = next;
    }
    indirect(
        encoder,
        STATES,
        &[
            ("gStates", block(&blocks, P_STATE_CHECK)),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("scan_a", scan_a.as_entire_binding()),
            ("scan_b", scan_b.as_entire_binding()),
            ("machines", machines.as_entire_binding()),
            ("states", states.as_entire_binding()),
            ("variants", variants.as_entire_binding()),
            ("machine_info", machine_info.as_entire_binding()),
            ("arm_event", arm_event.as_entire_binding()),
            ("adjacency", adjacency.as_entire_binding()),
            ("reach", reach.as_entire_binding()),
            ("status", status.as_entire_binding()),
            ("detail", detail.as_entire_binding()),
        ],
        A_STATES,
    )?;

    // The pieces of every machine's text.
    let record_pieces = |encoder: &mut wgpu::CommandEncoder, params: u32, triple: u32| {
        gpu.dispatch_indirect(
            encoder,
            &piece_kernel,
            PIECES,
            &[
                ("gPieces", block(&blocks, params)),
                ("tokens_out", bufs.tokens_out.as_entire_binding()),
                ("token_file_id", bufs.token_file_id.as_entire_binding()),
                ("in_bytes", bufs.in_bytes.as_entire_binding()),
                ("records", records.as_entire_binding()),
                ("scan_a", scan_a.as_entire_binding()),
                ("scan_b", scan_b.as_entire_binding()),
                ("machines", machines.as_entire_binding()),
                ("states", states.as_entire_binding()),
                ("transitions", transitions.as_entire_binding()),
                ("arms", arms.as_entire_binding()),
                ("fields", fields.as_entire_binding()),
                ("arguments", arguments.as_entire_binding()),
                ("const_index", const_index.as_entire_binding()),
                ("count_scan0", count_scans[0].as_entire_binding()),
                ("count_scan1", count_scans[1].as_entire_binding()),
                ("counts0", counts[0].as_entire_binding()),
                ("counts1", counts[1].as_entire_binding()),
                ("pieces", pieces.as_entire_binding()),
                ("piece_sources", piece_sources.as_entire_binding()),
            ],
            &args,
            triple,
        )
    };
    record_pieces(encoder, P_COUNT, A_LIVE)?;
    scan(
        encoder,
        &counts[0],
        &count_work[0],
        P_SCAN_LIVE,
        A_LIVE_SCAN,
        A_LIVE_SCAN_ONE,
    )?;
    scan(
        encoder,
        &counts[1],
        &count_work[1],
        P_SCAN_LIVE,
        A_LIVE_SCAN,
        A_LIVE_SCAN_ONE,
    )?;
    plan(encoder, PLAN_PIECES)?;
    record_pieces(encoder, P_WRITE, A_WRITE)?;
    scan(
        encoder,
        &pieces,
        &piece_work,
        P_SCAN_PIECES,
        A_PIECE_SCAN,
        A_PIECE_SCAN_ONE,
    )?;

    // The text in the region, then its tokens.
    plan(encoder, PLAN_REGION)?;
    indirect(
        encoder,
        EMIT,
        &[
            ("gEmit", block(&blocks, P_EMIT)),
            ("in_bytes", bufs.in_bytes.as_entire_binding()),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("pieces", pieces.as_entire_binding()),
            ("piece_scan", piece_scan.as_entire_binding()),
            ("const_index", const_index.as_entire_binding()),
            ("const_bytes", const_bytes.as_entire_binding()),
            ("anchors", anchors.as_entire_binding()),
            ("byte_piece", byte_piece.as_entire_binding()),
        ],
        A_REGION_WORDS,
    )?;
    indirect(
        encoder,
        TEXT_MARKS,
        &[
            ("sizes", sizes.as_entire_binding()),
            ("in_bytes", bufs.in_bytes.as_entire_binding()),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("pieces", pieces.as_entire_binding()),
            ("piece_scan", piece_scan.as_entire_binding()),
            ("const_index", const_index.as_entire_binding()),
            ("const_info", const_info.as_entire_binding()),
            ("byte_piece", byte_piece.as_entire_binding()),
            ("byte_info", byte_info.as_entire_binding()),
            ("text_marks", text_marks.as_entire_binding()),
        ],
        A_REGION_BYTES,
    )?;
    scan(
        encoder,
        &text_marks,
        &text_work,
        P_SCAN_REGION,
        A_REGION_SCAN,
        A_REGION_SCAN_ONE,
    )?;
    plan(encoder, PLAN_SPLICE)?;
    indirect(
        encoder,
        TEXT_TOKENS,
        &[
            ("sizes", sizes.as_entire_binding()),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("token_file_id", bufs.token_file_id.as_entire_binding()),
            ("pieces", pieces.as_entire_binding()),
            ("byte_piece", byte_piece.as_entire_binding()),
            ("byte_info", byte_info.as_entire_binding()),
            ("text_scan", text_scan.as_entire_binding()),
            ("scan_a", scan_a.as_entire_binding()),
            ("generated", generated.as_entire_binding()),
            ("generated_file", generated_file.as_entire_binding()),
            ("generated_machine", generated_machine.as_entire_binding()),
        ],
        A_REGION_BYTES,
    )?;

    // The splice.
    indirect(
        encoder,
        SPLICE_MARKS,
        &[
            ("sizes", sizes.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("scan_a", scan_a.as_entire_binding()),
            ("machines", machines.as_entire_binding()),
            ("count_scan0", count_scans[0].as_entire_binding()),
            ("count_scan1", count_scans[1].as_entire_binding()),
            ("piece_scan", piece_scan.as_entire_binding()),
            ("text_scan", text_scan.as_entire_binding()),
            ("machine_tokens", machine_tokens.as_entire_binding()),
            ("splice_marks", splice_marks.as_entire_binding()),
        ],
        A_SPLICE,
    )?;
    scan(
        encoder,
        &splice_marks,
        &splice_work,
        P_SCAN_SPLICE,
        A_SPLICE_SCAN,
        A_SPLICE_SCAN_ONE,
    )?;
    plan(encoder, PLAN_FINISH)?;
    indirect(
        encoder,
        SPLICE_KEPT,
        &[
            ("sizes", sizes.as_entire_binding()),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("token_file_id", bufs.token_file_id.as_entire_binding()),
            ("splice_marks", splice_marks.as_entire_binding()),
            ("splice_scan", splice_scan.as_entire_binding()),
            ("spliced", spliced.as_entire_binding()),
            ("spliced_file", spliced_file.as_entire_binding()),
        ],
        A_SPLICE,
    )?;
    indirect(
        encoder,
        SPLICE_GENERATED,
        &[
            ("sizes", sizes.as_entire_binding()),
            ("generated", generated.as_entire_binding()),
            ("generated_file", generated_file.as_entire_binding()),
            ("generated_machine", generated_machine.as_entire_binding()),
            ("machine_tokens", machine_tokens.as_entire_binding()),
            ("splice_scan", splice_scan.as_entire_binding()),
            ("spliced", spliced.as_entire_binding()),
            ("spliced_file", spliced_file.as_entire_binding()),
        ],
        A_GENERATED,
    )?;
    indirect(
        encoder,
        COPY_BACK,
        &[
            ("sizes", sizes.as_entire_binding()),
            ("spliced", spliced.as_entire_binding()),
            ("spliced_file", spliced_file.as_entire_binding()),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("token_file_id", bufs.token_file_id.as_entire_binding()),
        ],
        A_OUT,
    )?;

    let reach = reach.clone();
    *LAST_RUN.lock().unwrap_or_else(PoisonError::into_inner) = Some(LastRun {
        region_base,
        anchors,
        sizes,
        status,
        detail,
        tokens_out: bufs
            .tokens_out
            .clone()
            .reinterpret::<u8>(bufs.tokens_out.byte_size),
        token_file_id: bufs
            .token_file_id
            .clone()
            .reinterpret::<u8>(bufs.token_file_id.byte_size),
        in_bytes: bufs.in_bytes.clone(),
        records,
        scan_a: scan_a.clone(),
        scan_b: scan_b.clone(),
        machines,
        states,
        arms,
        variants,
        machine_info,
        arm_event,
        adjacency,
        reach,
    });
    Ok(())
}

/// Whether the machine rules accept `source`, and its machines are
/// desugared.
#[cfg(test)]
pub(crate) fn accepts(source: &str) -> bool {
    let _one = tests::one_at_a_time();
    tests::desugar_pack(&[source]).is_ok_and(|desugared| !desugared.region.is_empty())
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;
    use crate::lexer::driver::GpuLexer;

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

    /// The tests read the last run after the lexer is free, so one test
    /// desugars at a time.
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
                        .lock()
                        .unwrap_or_else(PoisonError::into_inner)
                        .clone();
                    let mut reads = vec![
                        (&count_bytes, 0, 1),
                        (&flag_bytes, 0, 1),
                        (&token_bytes, 0, bufs.tokens_out.count * 3),
                        (&file_bytes, 0, bufs.token_file_id.count),
                        (&bufs.in_bytes, 0, bufs.in_bytes.byte_size / 4),
                    ];
                    if let Some(last) = &last {
                        reads.push((&last.sizes, S_REGION, 1));
                    }
                    let mut words = read_words(&reads, None).expect("read the tokens");
                    let region = last.map(|last| {
                        (
                            last.region_base as usize,
                            words.get(5).map_or(0, |len| len[0] as usize),
                        )
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
                .filter(|_| raw & PARSER_FEATURE_MACHINES != 0)
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
        let lexer = test_lexer();
        for text in CONSTANTS {
            let tokens =
                without_desugaring(|| pollster::block_on(lexer.lex(text))).expect("lex a constant");
            let mut expected = vec![0u32; text.len()];
            for token in tokens {
                expected[token.start] = 1 | 2 | ((token.kind as u32) << 8);
                for byte in &mut expected[token.start + 1..token.start + token.len] {
                    *byte = 1 | ((token.kind as u32) << 8);
                }
            }
            assert_eq!(token_info(text), expected, "{text:?}");
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
        assert!(text.contains("Input::Open -> { self.opens += 1; self.__lanius_state = DoorState::Opened; return Reply::Done; },"), "{text}");
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
        assert!(text.contains("_ -> { let c: u8 = __lanius_event; if (c == 48) { self.__lanius_state = SumState::Zero; return; } return; },"), "{text}");
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
}
