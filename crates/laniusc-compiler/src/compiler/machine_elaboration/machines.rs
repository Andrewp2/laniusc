//! `machine` items, expanded on the GPU (docs/state-machines-design.md, M6).
//!
//! The GPU lexer and parser read the files of one load. The kernels in
//! shaders/machines then read each machine from the parse tree and write the
//! enum, struct, constructor and impl it stands for. The host records the
//! commands, sizes the buffers from the counts the kernels publish, and reads
//! back the expanded text and the piece table that maps it to the source.

use std::sync::OnceLock;

use anyhow::{Context, Result, anyhow};

use super::{
    Segment,
    closures::{Gpu, Rewritten},
};
use crate::{
    gpu::{
        buffers::{LaniusBuffer, storage_ro_from_bytes, storage_ro_from_u32s, uniform_from_val},
        passes_core::PassData,
    },
    lexer::{GpuToken, buffers::GpuBuffers, driver::try_global_lexer},
    parser::{buffers::ParserBuffers, driver::GpuParser, tables::PrecomputedParseTables},
};

/// The strings the kernels insert, in the order of the `C_*` ids in
/// shaders/machines/machine_common.slang.
const CONSTANTS: [&str; 77] = [
    "pub ",
    "enum ",
    "State { ",
    "struct ",
    " { ",
    "fn ",
    "_start(",
    "impl ",
    " {\n    ",
    "fn step(&mut self, __lanius_event: ",
    ")",
    " -> ",
    " {\n        ",
    "return match",
    "match",
    " (self.__lanius_state) {\n",
    "    ",
    "fn run(&mut self, __lanius_events: [",
    "], __lanius_count: i32) {\n        let __lanius_at: i32 = 0;\n        while (__lanius_at < __lanius_count) {\n            __lanius_at = match (self.__lanius_state) {\n",
    ": ",
    ", ",
    "(",
    " ",
    "            ",
    "State::",
    " -> { ",
    "return ",
    "self.__lanius_in_",
    "__lanius_event)",
    "; },\n",
    "; return; },\n",
    "    fn __lanius_in_",
    "(&mut self, ",
    "                ",
    " -> self.__lanius_run_",
    "__lanius_events, __lanius_at, __lanius_count),\n",
    "    fn __lanius_run_",
    "__lanius_data_",
    "__lanius_event: ",
    " (__lanius_event) {",
    "__lanius_events: [",
    "], __lanius_from: i32, __lanius_count: i32) -> i32 {\n",
    "        let ",
    " = __lanius_data_",
    ";\n",
    "        let __lanius_at: i32 = __lanius_from;\n        while (__lanius_at < __lanius_count) {\n            let __lanius_event: ",
    " = __lanius_events[__lanius_at];\n            __lanius_at += 1;\n            match (__lanius_event) {",
    "\n            ",
    "_ ",
    "{",
    " let ",
    " = __lanius_event;",
    " }",
    ",",
    "\n        ",
    "};\n    }\n",
    "};\n        }\n        self.__lanius_state = ",
    ";\n        return __lanius_at;\n    }\n",
    "}\n",
    "__lanius_state: ",
    "State }\n",
    ") -> ",
    " { return ",
    " }; }\n",
    "        };\n    }\n    ",
    "fn state(&self) -> ",
    "State { return self.__lanius_state; }\n",
    "            };\n        }\n    }\n",
    "self.__lanius_state = ",
    "; ",
    ";",
    "return;",
    "continue;",
    "; return __lanius_at;",
    " = ",
    "let __lanius_next_",
    " = __lanius_next_",
];

const RECORD_WORDS: usize = 6;
const PIECE_COPY: u32 = 0;
pub(super) const NO_ERROR: u32 = u32::MAX;
/// The status words of the machine rules. One more word follows them: the
/// first `gen` or `yield` token of the pack.
const STATUS_WORDS: usize = 4;
const DETAIL_WORDS: usize = 8;
const INFO_WORDS: usize = 3;
const STATE_ROW_WORDS: usize = 8;
/// A row of the transition graph has 256 bits, and 2^8 is 256.
const REACH_STEPS: usize = 8;

/// File flags: generators or the closure pass wrote the file, so it may use
/// the reserved names of that pass.
pub(super) const FILE_GENERATORS: u32 = 1;
pub(super) const FILE_CLOSURES: u32 = 2;

/// A machine the rules reject, as a byte span of one file.
pub(super) struct Invalid {
    pub(super) file: usize,
    pub(super) start: usize,
    pub(super) len: usize,
    pub(super) message: String,
    pub(super) help: Option<String>,
}

pub(super) enum Outcome {
    /// One entry per file: `None` for a file without machines.
    Expanded(Vec<Option<Rewritten>>),
    /// The pack has generators, and they are machines now: one entry per
    /// file, `None` for a file without generators. The machines of the
    /// rewritten pack are not expanded yet.
    Generators(Vec<Option<Rewritten>>),
    Invalid(Invalid),
}

#[derive(encase::ShaderType)]
pub(super) struct Params {
    a: u32,
    b: u32,
    c: u32,
    d: u32,
}

pub(super) fn params(gpu: &Gpu<'_>, label: &str, a: u32, b: u32) -> LaniusBuffer<Params> {
    uniform_from_val(gpu.device, label, &Params { a, b, c: 0, d: 0 })
}

/// The parameters of a kernel that checks rules. `explain` is the status
/// word and key of the error whose spans the kernel writes, or `NO_ERROR`
/// twice in the run that finds the errors.
pub(super) fn check_params(gpu: &Gpu<'_>, label: &str, a: u32, b: u32, explain: [u32; 2]) -> LaniusBuffer<Params> {
    uniform_from_val(gpu.device, label, &Params { a, b, c: explain[0], d: explain[1] })
}

struct Frontend {
    parser: GpuParser,
    tables: PrecomputedParseTables,
}

static FRONTEND: OnceLock<Result<Frontend, String>> = OnceLock::new();

/// The parser that reads machines. The compiler's own parser belongs to one
/// backend's compiler, and the expansion runs before any compiler exists.
fn frontend() -> Result<&'static Frontend> {
    FRONTEND
        .get_or_init(|| {
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/../../tables/parse_tables.bin"
            )))
            .map_err(|err| format!("load parser tables: {err}"))?;
            let parser = pollster::block_on(GpuParser::new()).map_err(|err| err.to_string())?;
            Ok(Frontend { parser, tables })
        })
        .as_ref()
        .map_err(|err| anyhow!("initialize the machine parser: {err}"))
}

/// The parse of one source pack, as far as the host needs it.
struct Parsed {
    token_count: u32,
    /// Read by the tree dump of the tests.
    #[cfg_attr(not(test), allow(dead_code))]
    token_capacity: u32,
    tree_capacity: u32,
}

/// Lexes and parses `sources`. `record` adds commands that read the parser's
/// buffers; `finish` runs after they are submitted, while the lexer's buffers
/// still hold this pack. `None` when a file does not lex or parse: the
/// frontend reports that.
fn with_parse<A, R>(
    sources: &[&str],
    record: impl FnOnce(&Gpu<'_>, &GpuBuffers, &ParserBuffers, &mut wgpu::CommandEncoder, &Parsed) -> Result<A>,
    finish: impl FnOnce(&Gpu<'_>, A) -> Result<Option<R>>,
) -> Result<Option<R>> {
    let lexer = try_global_lexer()?;
    let frontend = frontend()?;
    let outcome = pollster::block_on(lexer.with_recorded_resident_source_pack_tokens_after_count(
        sources,
        |device, queue, buffers, token_count, encoder, mut timer| {
            let token_capacity = token_count.max(1);
            let tree_capacity = frontend.parser.read_resident_partial_parse_tree_capacity(
                token_capacity,
                &buffers.tokens_out,
                &buffers.token_count,
                Some(&buffers.token_file_id),
                &frontend.tables,
            )?;
            let parsed = Parsed { token_count, token_capacity, tree_capacity };
            let gpu = Gpu { device, queue };
            let (check, recorded) = frontend.parser.record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                encoder,
                token_capacity,
                &buffers.tokens_out,
                &buffers.token_count,
                Some(&buffers.token_file_id),
                buffers.n,
                &buffers.in_bytes,
                &frontend.tables,
                Some(tree_capacity),
                &mut timer,
                |parse_buffers, encoder, _| record(&gpu, buffers, parse_buffers, encoder, &parsed),
            )?;
            Ok::<_, anyhow::Error>((check, recorded?))
        },
        |device, queue, (check, recorded)| {
            if frontend.parser.finish_recorded_resident_ll1_hir_check(&check).is_err() {
                return Ok::<_, anyhow::Error>(None);
            }
            finish(&Gpu { device, queue }, recorded)
        },
    ))?;
    // The compiler replaces the lexer's buffers between runs. The parser's
    // own buffers bind none of them and stay for the next run.
    frontend.parser.release_lexer_bindings();
    outcome
}

/// What the first submission leaves for the later ones: the lexer's and
/// parser's buffers, the token records, the first prefix sums and the status
/// words of the rules.
pub(super) struct Marked {
    pub(super) tokens: u32,
    pub(super) tokens_out: LaniusBuffer<GpuToken>,
    pub(super) token_file_id: LaniusBuffer<u32>,
    pub(super) in_bytes: LaniusBuffer<u8>,
    pub(super) source_file_start: LaniusBuffer<u32>,
    pub(super) source_file_len: LaniusBuffer<u32>,
    pub(super) semantic_token_kinds: LaniusBuffer<u32>,
    pub(super) tree: Tree,
    file_flags: LaniusBuffer<u32>,
    records: LaniusBuffer<u8>,
    marks: LaniusBuffer<u8>,
    /// Inclusive prefix sums: machines, states, transitions, bracket depth.
    pub(super) scan: LaniusBuffer<u8>,
    status: LaniusBuffer<u32>,
    detail: LaniusBuffer<u8>,
    /// The last row of `scan`: the number of machines, states and transitions.
    totals: LaniusBuffer<u8>,
    /// The first status word: the reserved names.
    reserved: LaniusBuffer<u8>,
    /// The word after the status words: the first `gen` or `yield` token.
    generators: LaniusBuffer<u8>,
}

/// The parse tree of the pack, for the generator kernels.
pub(super) struct Tree {
    pub(super) capacity: u32,
    pub(super) status: LaniusBuffer<u32>,
    pub(super) node_kind: LaniusBuffer<u32>,
    pub(super) parent: LaniusBuffer<u32>,
    pub(super) first_child: LaniusBuffer<u32>,
    pub(super) next_sibling: LaniusBuffer<u32>,
    pub(super) hir_token_pos: LaniusBuffer<u32>,
    pub(super) hir_token_end: LaniusBuffer<u32>,
}

/// Expands the machines of `sources`, one GPU run for all of them. `flags`
/// holds `FILE_GENERATORS` and `FILE_CLOSURES` per file. `None` when no file
/// has a machine, or when a file does not lex or parse: the frontend reports
/// that.
pub(super) fn expand(sources: &[&str], flags: &[u32]) -> Result<Option<Outcome>> {
    if sources.iter().all(|source| source.is_empty()) {
        return Ok(None);
    }
    with_parse(
        sources,
        |gpu, lexer, parser, encoder, parsed| mark(gpu, lexer, parser, encoder, parsed, flags),
        |gpu, marked| match marked {
            Some(marked) => write(gpu, sources, &marked),
            None => Ok(None),
        },
    )
}

/// Records the kernels that read the parse tree into token records, number
/// the machines and check the reserved names.
fn mark(
    gpu: &Gpu<'_>,
    lexer: &GpuBuffers,
    parser: &ParserBuffers,
    encoder: &mut wgpu::CommandEncoder,
    parsed: &Parsed,
    flags: &[u32],
) -> Result<Option<Marked>> {
    let tokens = parsed.token_count;
    if tokens == 0 {
        return Ok(None);
    }
    let rows = tokens as usize;
    let records = gpu.rows("machines.records", rows * RECORD_WORDS, 1);
    let marks = gpu.rows("machines.marks", rows, 4);
    let work = [gpu.rows("machines.scan.a", rows, 4), gpu.rows("machines.scan.b", rows, 4)];
    let status = storage_ro_from_u32s(gpu.device, "machines.status", &[NO_ERROR; STATUS_WORDS + 1]);
    let detail = gpu.rows("machines.detail", DETAIL_WORDS, 1);
    let file_flags = storage_ro_from_u32s(gpu.device, "machines.file_flags", flags);
    let node_params = params(gpu, "machines.nodes.params", parsed.tree_capacity, tokens);
    gpu.dispatch(
        encoder,
        &gpu.kernel("machines/nodes")?,
        "machines.nodes",
        &[
            ("gNodes", node_params.as_entire_binding()),
            ("tree_count_status", parser.ll1_status.as_entire_binding()),
            ("node_kind", parser.node_kind.as_entire_binding()),
            ("parent", parser.parent.as_entire_binding()),
            ("first_child", parser.first_child.as_entire_binding()),
            ("next_sibling", parser.next_sibling.as_entire_binding()),
            ("hir_token_pos", parser.hir_token_pos.as_entire_binding()),
            ("hir_token_end", parser.hir_token_end.as_entire_binding()),
            ("semantic_token_kinds", parser.semantic_token_kinds.as_entire_binding()),
            ("records", records.as_entire_binding()),
        ],
        parsed.tree_capacity,
    )?;
    let token_params = params(gpu, "machines.marks.params", tokens, 0);
    gpu.dispatch(
        encoder,
        &gpu.kernel("machines/marks")?,
        "machines.marks",
        &[
            ("gMarks", token_params.as_entire_binding()),
            ("tokens_out", lexer.tokens_out.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("marks", marks.as_entire_binding()),
        ],
        tokens,
    )?;
    let scan = gpu.scan(encoder, &gpu.kernel("closures/scan")?, &marks, &work, tokens)?.clone();
    let marked = Marked {
        tokens,
        tokens_out: lexer.tokens_out.clone(),
        token_file_id: lexer.token_file_id.clone(),
        in_bytes: lexer.in_bytes.clone(),
        source_file_start: lexer.source_file_start.clone(),
        source_file_len: lexer.source_file_len.clone(),
        semantic_token_kinds: parser.semantic_token_kinds.clone(),
        tree: Tree {
            capacity: parsed.tree_capacity,
            status: parser.ll1_status.clone(),
            node_kind: parser.node_kind.clone(),
            parent: parser.parent.clone(),
            first_child: parser.first_child.clone(),
            next_sibling: parser.next_sibling.clone(),
            hir_token_pos: parser.hir_token_pos.clone(),
            hir_token_end: parser.hir_token_end.clone(),
        },
        file_flags,
        records,
        marks,
        totals: gpu.read(encoder, &scan, (rows - 1) * 4, 4),
        scan,
        reserved: gpu.rows("machines.reserved", 1, 1),
        generators: gpu.rows("machines.generators", 1, 1),
        status,
        detail,
    };
    record_reserved(gpu, encoder, &marked, [NO_ERROR; 2])?;
    let reserved = gpu.read(encoder, &marked.status, 0, 1);
    let generators = gpu.read(encoder, &marked.status, STATUS_WORDS, 1);
    Ok(Some(Marked { reserved, generators, ..marked }))
}

/// Records the kernel that checks the reserved names.
fn record_reserved(gpu: &Gpu<'_>, encoder: &mut wgpu::CommandEncoder, marked: &Marked, explain: [u32; 2]) -> Result<()> {
    let reserved_params = check_params(gpu, "machines.reserved.params", marked.tokens, 0, explain);
    gpu.dispatch(
        encoder,
        &gpu.kernel("machines/reserved")?,
        "machines.reserved",
        &[
            ("gReserved", reserved_params.as_entire_binding()),
            ("tokens_out", marked.tokens_out.as_entire_binding()),
            ("token_file_id", marked.token_file_id.as_entire_binding()),
            ("in_bytes", marked.in_bytes.as_entire_binding()),
            ("file_flags", marked.file_flags.as_entire_binding()),
            ("status", marked.status.as_entire_binding()),
            ("detail", marked.detail.as_entire_binding()),
        ],
        marked.tokens,
    )
}

/// Records the kernel that writes each marked token into its lists. The
/// fourth component of the marks is a list only when `fourth` is set.
fn lists(
    gpu: &Gpu<'_>,
    encoder: &mut wgpu::CommandEncoder,
    kernel: &PassData,
    tokens: u32,
    marks: &LaniusBuffer<u8>,
    scan: &LaniusBuffer<u8>,
    label: &str,
    fourth: bool,
) -> Result<[LaniusBuffer<u8>; 4]> {
    let rows = tokens as usize;
    let out = [
        gpu.rows(label, rows, 1),
        gpu.rows(label, rows, 1),
        gpu.rows(label, rows, 1),
        gpu.rows(label, if fourth { rows } else { 1 }, 1),
    ];
    let list_params = params(gpu, "machines.lists.params", tokens, u32::from(fourth));
    gpu.dispatch(
        encoder,
        kernel,
        "machines.lists",
        &[
            ("gLists", list_params.as_entire_binding()),
            ("marks", marks.as_entire_binding()),
            ("scan", scan.as_entire_binding()),
            ("list_x", out[0].as_entire_binding()),
            ("list_y", out[1].as_entire_binding()),
            ("list_z", out[2].as_entire_binding()),
            ("list_w", out[3].as_entire_binding()),
        ],
        tokens,
    )?;
    Ok(out)
}

/// Checks the rules, then writes the pieces of every machine and the
/// expanded bytes.
fn write(gpu: &Gpu<'_>, sources: &[&str], marked: &Marked) -> Result<Option<Outcome>> {
    let reserved = gpu.words(&marked.reserved)?[0];
    if reserved != NO_ERROR {
        let mut encoder = gpu.encoder("machines.explain");
        record_reserved(gpu, &mut encoder, marked, [0, reserved])?;
        return explain(gpu, encoder, sources, marked, 0, reserved).map(Some);
    }
    // Generators become machines first. The caller runs the pack again.
    if gpu.words(&marked.generators)?[0] != NO_ERROR {
        return super::generators::expand(gpu, sources, marked);
    }
    let totals = gpu.words(&marked.totals)?;
    let (machine_count, state_count, transition_count) = (totals[0], totals[1], totals[2]);
    // A transition outside a machine is an error the rules report.
    if machine_count == 0 && transition_count == 0 {
        return Ok(None);
    }
    let tokens = marked.tokens;
    let rows = tokens as usize;
    let scan_kernel = gpu.kernel("closures/scan")?;
    let list_kernel = gpu.kernel("machines/lists")?;
    let piece_kernel = gpu.kernel("machines/pieces")?;
    let resolve_kernel = gpu.kernel("machines/resolve")?;
    let arm_kernel = gpu.kernel("machines/arms")?;
    let reach_kernel = gpu.kernel("machines/reach")?;
    let state_kernel = gpu.kernel("machines/states")?;
    let (const_index, const_bytes) = constant_table(gpu.device);

    // The arms, fields, arguments and enum variants, then the rules and the
    // piece count of every token.
    let marks_b = gpu.rows("machines.context", rows, 4);
    let work_b = [gpu.rows("machines.context.a", rows, 4), gpu.rows("machines.context.b", rows, 4)];
    let counts = [gpu.rows("machines.counts0", rows, 4), gpu.rows("machines.counts1", rows, 4)];
    let count_work = [
        [gpu.rows("machines.counts0.a", rows, 4), gpu.rows("machines.counts0.b", rows, 4)],
        [gpu.rows("machines.counts1.a", rows, 4), gpu.rows("machines.counts1.b", rows, 4)],
    ];
    let no_pieces = [gpu.rows("machines.no_pieces", 1, 4), gpu.rows("machines.no_sources", 1, 4)];
    let machine_info = gpu.rows("machines.info", machine_count as usize * INFO_WORDS, 1);
    let arm_event = gpu.rows("machines.arm_event", rows, 1);
    let adjacency = gpu.rows("machines.adjacency", state_count as usize * STATE_ROW_WORDS, 1);
    let reach_work = [
        gpu.rows("machines.reach.a", state_count as usize * STATE_ROW_WORDS, 1),
        gpu.rows("machines.reach.b", state_count as usize * STATE_ROW_WORDS, 1),
    ];
    let mut encoder = gpu.encoder("machines.count");
    let [machines, states, transitions, _] =
        lists(gpu, &mut encoder, &list_kernel, tokens, &marked.marks, &marked.scan, "machines.lists.a", false)?;
    let token_params = params(gpu, "machines.context.params", tokens, 0);
    gpu.dispatch(
        &mut encoder,
        &gpu.kernel("machines/context")?,
        "machines.context",
        &[
            ("gContext", token_params.as_entire_binding()),
            ("records", marked.records.as_entire_binding()),
            ("scan_a", marked.scan.as_entire_binding()),
            ("states", states.as_entire_binding()),
            ("transitions", transitions.as_entire_binding()),
            ("marks", marks_b.as_entire_binding()),
        ],
        tokens,
    )?;
    let scan_b = gpu.scan(&mut encoder, &scan_kernel, &marks_b, &work_b, tokens)?;
    let [arms, fields, arguments, variants] =
        lists(gpu, &mut encoder, &list_kernel, tokens, &marks_b, scan_b, "machines.lists.b", true)?;

    // The rules. The kernels run again to explain an error, with the same
    // buffers: every write of the first run repeats its value.
    let record_checks = |encoder: &mut wgpu::CommandEncoder, explain: [u32; 2]| -> Result<()> {
        let resolve_params = check_params(gpu, "machines.resolve.params", tokens, machine_count, explain);
        gpu.dispatch(
            encoder,
            &resolve_kernel,
            "machines.resolve",
            &[
                ("gResolve", resolve_params.as_entire_binding()),
                ("tokens_out", marked.tokens_out.as_entire_binding()),
                ("token_file_id", marked.token_file_id.as_entire_binding()),
                ("in_bytes", marked.in_bytes.as_entire_binding()),
                ("semantic_token_kinds", marked.semantic_token_kinds.as_entire_binding()),
                ("records", marked.records.as_entire_binding()),
                ("scan_a", marked.scan.as_entire_binding()),
                ("scan_b", scan_b.as_entire_binding()),
                ("machines", machines.as_entire_binding()),
                ("states", states.as_entire_binding()),
                ("arms", arms.as_entire_binding()),
                ("machine_info", machine_info.as_entire_binding()),
                ("adjacency", adjacency.as_entire_binding()),
                ("status", marked.status.as_entire_binding()),
                ("detail", marked.detail.as_entire_binding()),
            ],
            tokens,
        )?;
        let arm_params = check_params(gpu, "machines.arms.params", tokens, 0, explain);
        gpu.dispatch(
            encoder,
            &arm_kernel,
            "machines.arms",
            &[
                ("gArms", arm_params.as_entire_binding()),
                ("tokens_out", marked.tokens_out.as_entire_binding()),
                ("in_bytes", marked.in_bytes.as_entire_binding()),
                ("records", marked.records.as_entire_binding()),
                ("scan_a", marked.scan.as_entire_binding()),
                ("scan_b", scan_b.as_entire_binding()),
                ("machines", machines.as_entire_binding()),
                ("states", states.as_entire_binding()),
                ("arms", arms.as_entire_binding()),
                ("variants", variants.as_entire_binding()),
                ("machine_info", machine_info.as_entire_binding()),
                ("arm_event", arm_event.as_entire_binding()),
                ("status", marked.status.as_entire_binding()),
                ("detail", marked.detail.as_entire_binding()),
            ],
            tokens,
        )?;
        if state_count == 0 {
            return Ok(());
        }
        let reach_params = params(gpu, "machines.reach.params", state_count, 0);
        let mut reach = &adjacency;
        for step in 0..REACH_STEPS {
            let next = &reach_work[step % 2];
            gpu.dispatch(
                encoder,
                &reach_kernel,
                "machines.reach",
                &[
                    ("gReach", reach_params.as_entire_binding()),
                    ("records", marked.records.as_entire_binding()),
                    ("scan_a", marked.scan.as_entire_binding()),
                    ("machines", machines.as_entire_binding()),
                    ("states", states.as_entire_binding()),
                    ("rows_in", reach.as_entire_binding()),
                    ("rows_out", next.as_entire_binding()),
                ],
                state_count,
            )?;
            reach = next;
        }
        let state_params = check_params(gpu, "machines.states.params", state_count, 0, explain);
        gpu.dispatch(
            encoder,
            &state_kernel,
            "machines.states",
            &[
                ("gStates", state_params.as_entire_binding()),
                ("tokens_out", marked.tokens_out.as_entire_binding()),
                ("records", marked.records.as_entire_binding()),
                ("scan_a", marked.scan.as_entire_binding()),
                ("scan_b", scan_b.as_entire_binding()),
                ("machines", machines.as_entire_binding()),
                ("states", states.as_entire_binding()),
                ("variants", variants.as_entire_binding()),
                ("machine_info", machine_info.as_entire_binding()),
                ("arm_event", arm_event.as_entire_binding()),
                ("adjacency", adjacency.as_entire_binding()),
                ("reach", reach.as_entire_binding()),
                ("status", marked.status.as_entire_binding()),
                ("detail", marked.detail.as_entire_binding()),
            ],
            state_count,
        )
    };
    record_checks(&mut encoder, [NO_ERROR; 2])?;
    let status_read = gpu.read(&mut encoder, &marked.status, 0, STATUS_WORDS);

    let record_pieces = |encoder: &mut wgpu::CommandEncoder,
                         write: u32,
                         count_scans: [&LaniusBuffer<u8>; 2],
                         pieces: &LaniusBuffer<u8>,
                         piece_sources: &LaniusBuffer<u8>| {
        let piece_params = params(gpu, "machines.pieces.params", tokens, write);
        gpu.dispatch(
            encoder,
            &piece_kernel,
            "machines.pieces",
            &[
                ("gPieces", piece_params.as_entire_binding()),
                ("tokens_out", marked.tokens_out.as_entire_binding()),
                ("token_file_id", marked.token_file_id.as_entire_binding()),
                ("in_bytes", marked.in_bytes.as_entire_binding()),
                ("source_file_start", marked.source_file_start.as_entire_binding()),
                ("source_file_len", marked.source_file_len.as_entire_binding()),
                ("semantic_token_kinds", marked.semantic_token_kinds.as_entire_binding()),
                ("records", marked.records.as_entire_binding()),
                ("scan_a", marked.scan.as_entire_binding()),
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
            tokens,
        )
    };
    // The counting run reads no prefix sums of the counts: it binds the
    // buffers the sums are written to afterwards.
    record_pieces(&mut encoder, 0, [&count_work[0][0], &count_work[1][0]], &no_pieces[0], &no_pieces[1])?;
    let count_scan0 = gpu.scan(&mut encoder, &scan_kernel, &counts[0], &count_work[0], tokens)?;
    let count_scan1 = gpu.scan(&mut encoder, &scan_kernel, &counts[1], &count_work[1], tokens)?;
    let total0 = gpu.read(&mut encoder, count_scan0, (rows - 1) * 4, 4);
    let total1 = gpu.read(&mut encoder, count_scan1, (rows - 1) * 4, 4);
    gpu.submit("machines.count", encoder);
    let failures = gpu.words(&status_read)?;
    if let Some(word) = failures.iter().position(|&key| key != NO_ERROR) {
        let mut encoder = gpu.encoder("machines.explain");
        record_checks(&mut encoder, [word as u32, failures[word]])?;
        return explain(gpu, encoder, sources, marked, word, failures[word]).map(Some);
    }
    let piece_count = gpu
        .words(&total0)?
        .into_iter()
        .chain(gpu.words(&total1)?)
        .try_fold(0u32, u32::checked_add)
        .context("too many machine pieces")?;
    if piece_count == 0 {
        return Ok(None);
    }

    // The pieces and their lengths.
    let pieces_len = piece_count as usize;
    let pieces = gpu.rows("machines.pieces", pieces_len, 4);
    let piece_sources = gpu.rows("machines.piece_sources", pieces_len, 4);
    let piece_work = [gpu.rows("machines.pieces.a", pieces_len, 4), gpu.rows("machines.pieces.b", pieces_len, 4)];
    let mut encoder = gpu.encoder("machines.pieces");
    record_pieces(&mut encoder, 1, [count_scan0, count_scan1], &pieces, &piece_sources)?;
    let piece_scan = gpu.scan(&mut encoder, &scan_kernel, &pieces, &piece_work, piece_count)?;
    let pieces_read = gpu.read(&mut encoder, &pieces, 0, pieces_len * 4);
    let piece_scan_read = gpu.read(&mut encoder, piece_scan, 0, pieces_len * 4);
    let piece_sources_read = gpu.read(&mut encoder, &piece_sources, 0, pieces_len * 4);
    gpu.submit("machines.pieces", encoder);
    let piece_rows = gpu.words(&pieces_read)?;
    let piece_ends = gpu.words(&piece_scan_read)?;
    let piece_anchors = gpu.words(&piece_sources_read)?;
    let out_len = piece_ends[(pieces_len - 1) * 4];

    // The expanded bytes.
    let out_words = (out_len as usize).div_ceil(4);
    let output = gpu.rows("machines.output", out_words, 1);
    let emit_params = params(gpu, "machines.emit.params", out_len, piece_count);
    let mut encoder = gpu.encoder("machines.emit");
    gpu.dispatch(
        &mut encoder,
        &gpu.kernel("machines/emit")?,
        "machines.emit",
        &[
            ("gEmit", emit_params.as_entire_binding()),
            ("in_bytes", marked.in_bytes.as_entire_binding()),
            ("tokens_out", marked.tokens_out.as_entire_binding()),
            ("pieces", pieces.as_entire_binding()),
            ("piece_scan", piece_scan.as_entire_binding()),
            ("const_index", const_index.as_entire_binding()),
            ("const_bytes", const_bytes.as_entire_binding()),
            ("out_words", output.as_entire_binding()),
        ],
        u32::try_from(out_words.max(1)).context("expanded source is too large")?,
    )?;
    let output_read = gpu.read(&mut encoder, &output, 0, out_words);
    gpu.submit("machines.emit", encoder);
    let mut bytes: Vec<u8> = gpu.words(&output_read)?.into_iter().flat_map(u32::to_le_bytes).collect();
    bytes.truncate(out_len as usize);

    split_files(sources, &piece_rows, &piece_ends, &piece_anchors, &bytes).map(|files| Some(Outcome::Expanded(files)))
}

/// Submits the run that explains the error `key` of status word `word` and
/// builds its message. The kernels wrote the spans the message names: the
/// token of the error, two more tokens and a number.
fn explain(
    gpu: &Gpu<'_>,
    mut encoder: wgpu::CommandEncoder,
    sources: &[&str],
    marked: &Marked,
    word: usize,
    key: u32,
) -> Result<Outcome> {
    let detail_read = gpu.read(&mut encoder, &marked.detail, 0, DETAIL_WORDS);
    gpu.submit("machines.explain", encoder);
    let detail = gpu.words(&detail_read)?;

    let mut file_starts = Vec::with_capacity(sources.len());
    let mut next = 0usize;
    for source in sources {
        file_starts.push(next);
        next += source.len();
    }
    let file_of = |offset: usize| file_starts.partition_point(|&start| start <= offset).saturating_sub(1);
    let text = |start: u32, len: u32| {
        let file = file_of(start as usize);
        let from = start as usize - file_starts[file];
        sources[file].get(from..from + len as usize).unwrap_or("")
    };
    let label = text(detail[0], detail[1]);
    let a = text(detail[2], detail[3]);
    let b = text(detail[4], detail[5]);
    let number = detail[6];
    let mut len = detail[1] as usize;
    let mut help = None;
    let message = match (word, key & 31) {
        (0, _) => "identifiers starting with `__lanius_` are reserved for the compiler".to_string(),
        (1, 1) => "a machine has at most 256 states".to_string(),
        (1, 2) => "expected `{` here".to_string(),
        (1, 3) => format!("state `{label}` is declared twice"),
        (1, 4) => format!("no state is named `{label}`"),
        (1, 5) => "the start state takes no data, so construction never chooses a state".to_string(),
        (1, 6) => {
            // The event type runs to the end of token `a`.
            len = (detail[2] + detail[3] - detail[0]) as usize;
            "a machine's event type is an integer type or an enum declared in the machine's file".to_string()
        }
        (1, 7) => format!(
            "state `{a}` handles the remaining events with `_`; list each event, so adding one makes every state decide what it does"
        ),
        (1, 8) => {
            "a machine arm ends in a transition: `goto State` or `stay`, or a block whose every path does".to_string()
        }
        (1, 9) => "expected `,` after this block arm".to_string(),
        (1, 10) => "a machine arm leaves through `goto` or `stay`, not `return`".to_string(),
        (1, 11) => "expected `;` after this transition".to_string(),
        (1, 12) => "this machine has no output, so its transitions take no `with`".to_string(),
        (1, 13) => "this machine has an output: end the transition with `with value`".to_string(),
        (1, 14) => format!("state `{a}` takes {number} values"),
        (1, 15) => "`goto` and `stay` are the transitions of a machine: write them in the arms of a state".to_string(),
        (1, 16) => "a transition is a statement or the whole body of an arm, and it has no value".to_string(),
        (1, 17) => "expected a field name here".to_string(),
        (2, code @ (1 | 2)) => {
            help = Some(format!("add an arm, e.g. `{a}::{b} -> stay{}`", if code == 2 { " with ..." } else { "" }));
            format!("state `{label}` does not handle `{a}::{b}`")
        }
        (2, _) => format!("state `{label}` must end with a `_` or binding arm, since its events are integers"),
        (3, 1) => format!("state `{label}` is unreachable from `start {a}`"),
        (3, 2) => {
            help = Some(format!("mark it `final state {label}` if the machine is meant to stop here"));
            format!("state `{label}` has no `goto` to another state")
        }
        _ => format!("`final` state `{label}` has a `goto` to another state"),
    };
    let file = file_of(detail[0] as usize);
    Ok(Outcome::Invalid(Invalid {
        file,
        start: detail[0] as usize - file_starts[file],
        len: len.max(1),
        message,
        help,
    }))
}

fn constant_table(device: &wgpu::Device) -> (LaniusBuffer<u32>, LaniusBuffer<u8>) {
    let mut index = Vec::with_capacity(CONSTANTS.len() * 2);
    let mut bytes = Vec::new();
    for text in CONSTANTS {
        index.extend([bytes.len() as u32, text.len() as u32]);
        bytes.extend_from_slice(text.as_bytes());
    }
    bytes.resize(bytes.len().next_multiple_of(4), 0);
    let count = bytes.len();
    (
        storage_ro_from_u32s(device, "machines.const_index", &index),
        storage_ro_from_bytes(device, "machines.const_bytes", &bytes, count),
    )
}

/// Cuts the expanded pack into its files and builds the map from each
/// expanded byte to the source. A piece row is `(len, kind, value, anchor
/// token)`; an anchor row is `(file, start, len)` of the anchor token. The
/// pieces of one file are adjacent, and a file without machines has none.
pub(super) fn split_files(
    sources: &[&str],
    piece_rows: &[u32],
    piece_ends: &[u32],
    piece_anchors: &[u32],
    bytes: &[u8],
) -> Result<Vec<Option<Rewritten>>> {
    let mut file_starts = Vec::with_capacity(sources.len());
    let mut next = 0usize;
    for source in sources {
        file_starts.push(next);
        next += source.len();
    }
    let mut files: Vec<Option<Rewritten>> = sources.iter().map(|_| None).collect();
    let mut open: Option<(usize, usize, Vec<Segment>)> = None;
    let mut close = |open: &mut Option<(usize, usize, Vec<Segment>)>, end: usize| -> Result<()> {
        if let Some((file, start, segments)) = open.take() {
            let text = String::from_utf8(bytes[start..end].to_vec())
                .map_err(|_| anyhow!("the machine expansion produced text that is not UTF-8"))?;
            files[file] = Some(Rewritten { text, segments });
        }
        Ok(())
    };
    let mut out_at = 0usize;
    for index in 0..piece_rows.len() / 4 {
        let (len, kind, value) = (piece_rows[index * 4] as usize, piece_rows[index * 4 + 1], piece_rows[index * 4 + 2] as usize);
        let anchor = &piece_anchors[index * 4..index * 4 + 3];
        let file = anchor[0] as usize;
        let file_start = *file_starts.get(file).context("a machine piece names a file outside the pack")?;
        if open.as_ref().is_none_or(|(current, ..)| *current != file) {
            close(&mut open, out_at)?;
            open = Some((file, out_at, Vec::new()));
        }
        let (_, start, segments) = open.as_mut().expect("a file is open");
        if len > 0 {
            let copied = kind == PIECE_COPY;
            let (src_start, src_len) = if copied { (value, len) } else { (anchor[1] as usize, anchor[2] as usize) };
            segments.push(Segment {
                out_start: out_at - *start,
                out_len: len,
                src_start: src_start.saturating_sub(file_start),
                src_len,
                copied,
            });
        }
        out_at = piece_ends[index * 4] as usize;
    }
    close(&mut open, out_at)?;
    Ok(files)
}

#[cfg(test)]
fn read_all(gpu: &Gpu<'_>, encoder: &mut wgpu::CommandEncoder, buffer: &LaniusBuffer<u32>, words: u32) -> LaniusBuffer<u8> {
    gpu.read(encoder, buffer, 0, words as usize)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The production names by id, from the generated shader constants.
    fn production_names() -> Vec<String> {
        let text = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../shaders/parser/generated_parse_production_ids.slang"
        ));
        let mut names = Vec::new();
        for line in text.lines() {
            let Some(rest) = line.strip_prefix("static const uint PROD_") else { continue };
            let Some((name, id)) = rest.split_once(" = ") else { continue };
            let id: usize = id.trim_end_matches("u;").parse().expect("production id");
            if names.len() <= id {
                names.resize(id + 1, String::new());
            }
            names[id] = name.to_string();
        }
        names
    }

    fn lani_files(dir: &std::path::Path, files: &mut Vec<std::path::PathBuf>) {
        let Ok(entries) = std::fs::read_dir(dir) else { return };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                lani_files(&path, files);
            } else if path.extension().is_some_and(|extension| extension == "lani") {
                files.push(path);
            }
        }
    }

    /// The expansion of sources the rules accept.
    fn expanded(sources: &[&str]) -> Option<Vec<Option<Rewritten>>> {
        match expand(sources, &vec![0; sources.len()]).expect("expand") {
            Some(Outcome::Expanded(files)) => Some(files),
            Some(Outcome::Invalid(invalid)) => panic!(
                "file {} at byte {}: {} ({:?})",
                invalid.file, invalid.start, invalid.message, invalid.help
            ),
            Some(Outcome::Generators(_)) => panic!("the sources declare a generator"),
            None => None,
        }
    }

    fn expanded_text(source: &str) -> String {
        let mut files = expanded(&[source]).expect("the source has a machine");
        files[0].take().expect("the source has a machine").text
    }

    /// What the rules say about `source`: the labeled text, the message and
    /// the help of a rejection.
    fn verdict(source: &str, flags: u32) -> String {
        match expand(&[source], &[flags]).expect("expand") {
            Some(Outcome::Invalid(invalid)) => format!(
                "`{}`: {}{}",
                &source[invalid.start..invalid.start + invalid.len],
                invalid.message,
                invalid.help.map_or(String::new(), |help| format!(" [{help}]"))
            ),
            Some(Outcome::Expanded(_)) => "expanded".to_string(),
            Some(Outcome::Generators(_)) => "generators".to_string(),
            None => "no machine, or the file does not parse".to_string(),
        }
    }

    fn first_difference(name: &str, expected: &str, actual: &str) -> String {
        let at = expected.bytes().zip(actual.bytes()).position(|(a, b)| a != b).unwrap_or(expected.len().min(actual.len()));
        let from = at.saturating_sub(120);
        let window = |text: &str| {
            let bytes = &text.as_bytes()[from.min(text.len())..(at + 120).min(text.len())];
            String::from_utf8_lossy(bytes).into_owned()
        };
        format!(
            "{name}: the texts differ at byte {at} (lengths {} and {})\n--- recorded ---\n{}\n--- gpu ---\n{}\n",
            expected.len(),
            actual.len(),
            window(expected),
            window(actual)
        )
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
    fn a_machine_expands_to_an_enum_a_struct_a_constructor_and_an_impl() {
        let text = expanded_text(DOOR);
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
        let text = expanded_text("enum Op { Push(i32), Drop }
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
    fn integer_events_may_end_with_a_binding_arm() {
        let text = expanded_text("machine Sum on u8 {
    total: i64,
    start Between;
    state Between {
        c -> { if (c == 48) { goto Zero; } stay; },
    }
    final state Zero {
        _ -> stay,
    }
}
");
        assert!(text.contains("fn step(&mut self, __lanius_event: u8) {"), "{text}");
        assert!(text.contains("_ -> { return; },"), "{text}");
        assert!(text.contains("_ -> { let c: u8 = __lanius_event; if (c == 48) { self.__lanius_state = SumState::Zero; return; } return; },"), "{text}");
    }

    #[test]
    fn files_without_machines_are_unchanged() {
        assert!(expanded(&["fn plain() -> i32 { return 1; }\n"]).is_none());
        assert!(expanded(&[""]).is_none());
    }

    /// Shapes the fixtures do not have: a public machine, state data, a
    /// transition to the same state with one and with several values, a
    /// binding arm, block arms, two machines in one file and text after the
    /// last one. The recorded texts are the ones the host elaborator wrote
    /// before the expansion moved to the GPU. One run expands the pack.
    #[test]
    fn the_expansion_matches_the_recorded_text() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/machines/expansion");
        let read = |name: String| std::fs::read_to_string(dir.join(&name)).unwrap_or_else(|err| panic!("{name}: {err}"));
        let shapes: Vec<(String, String)> =
            (0..3).map(|index| (read(format!("shape_{index}.source.txt")), read(format!("shape_{index}.expanded.txt")))).collect();
        let mut sources: Vec<&str> = vec!["fn plain() -> i32 { return 1; }\n"];
        sources.extend(shapes.iter().map(|(source, _)| source.as_str()));
        let files = expanded(&sources).expect("the pack has machines");
        assert!(files[0].is_none(), "a file without machines is not rewritten");
        let mut failures = String::new();
        for (index, ((_, expected), file)) in shapes.iter().zip(&files[1..]).enumerate() {
            match file {
                Some(file) if file.text == *expected => {}
                Some(file) => failures.push_str(&first_difference(&format!("shape_{index}"), expected, &file.text)),
                None => failures.push_str(&format!("shape_{index}: no machine found\n")),
            }
        }
        assert!(failures.is_empty(), "{failures}");
    }

    /// The rules accept every machine of the library and the fixtures.
    #[test]
    fn the_rules_accept_every_library_machine() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let mut files = Vec::new();
        for dir in ["tests/fixtures/machines", "stdlib", "extended"] {
            lani_files(&root.join(dir), &mut files);
        }
        files.sort();
        let mut paths = Vec::new();
        let mut sources = Vec::new();
        for path in files {
            let name = path.file_name().unwrap().to_string_lossy().into_owned();
            let source = std::fs::read_to_string(&path).expect("read a source file");
            // Generators and closures are rewritten before machines.
            let machine = source.lines().any(|line| line.starts_with("machine ") || line.starts_with("pub machine "));
            let rejected = ["reserved", "unreachable", "dead_end", "wildcard", "return", "missing_event"]
                .iter()
                .any(|rule| name == format!("reject_{rule}.lani"));
            if machine && !rejected && !source.contains("gen fn") && !source.contains('|') {
                paths.push(path);
                sources.push(source);
            }
        }
        assert!(paths.len() >= 5, "found {} files with machines", paths.len());
        let texts: Vec<&str> = sources.iter().map(String::as_str).collect();
        let files = expanded(&texts).expect("the pack has machines");
        let missing: Vec<_> = paths.iter().zip(&files).filter(|(_, file)| file.is_none()).map(|(path, _)| path).collect();
        assert!(missing.is_empty(), "no machine expanded in {missing:?}");
    }

    #[test]
    fn the_rules_reject_their_violations() {
        let fixture = |name: &str| {
            let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/machines").join(name);
            std::fs::read_to_string(path).expect("read a fixture")
        };
        let mut many = String::from("enum E { A }\nmachine M on E {\n    start S0;\n");
        for index in 0..257 {
            many.push_str(&format!("    state S{index} {{ E::A -> goto S{}, }}\n", (index + 1) % 257));
        }
        many.push_str("}\n");
        let one = |body: &str| format!("enum E {{ A }}\nmachine M on E {{\n    start S;\n{body}}}\n");
        let cases: Vec<(String, &str)> = vec![
            ("fn f() { let __lanius_state: i32 = 1; }".to_string(), "`__lanius_state`: identifiers starting with `__lanius_` are reserved for the compiler"),
            (fixture("reject_reserved.lani"), "`__lanius_state`: identifiers starting with `__lanius_` are reserved for the compiler"),
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
            // The parser rejects these, and the frontend reports them.
            (one("    final state S { E::A -> { stay; } E::A -> stay, }\n"), "no machine, or the file does not parse"),
            (one("    final state S { E::A -> { stay } }\n"), "no machine, or the file does not parse"),
        ];
        let mut failures = String::new();
        for (index, (source, expected)) in cases.iter().enumerate() {
            let verdict = verdict(source, 0);
            if verdict != *expected {
                failures.push_str(&format!("case {index}:\n  expected {expected}\n  found    {verdict}\n"));
            }
        }
        assert!(failures.is_empty(), "{failures}");
    }

    /// A name with the reserved prefix is accepted in a file a rewrite wrote,
    /// when it is one of the names of that rewrite.
    #[test]
    fn the_names_of_a_rewrite_are_reserved_for_its_files() {
        let reserved = "identifiers starting with `__lanius_` are reserved for the compiler";
        let uses = |name: &str| format!("fn f() -> i32 {{ let {name}: i32 = 1; return {name}; }}\n");
        for (name, flags) in [
            ("__lanius_gen_i", FILE_GENERATORS),
            ("__lanius_closure_3", FILE_CLOSURES),
            ("__lanius_r", FILE_CLOSURES),
            ("__lanius_inst_7", 0),
        ] {
            assert_eq!(verdict(&uses(name), flags), "no machine, or the file does not parse", "{name}");
        }
        for (name, flags) in [
            ("__lanius_gen_i", 0),
            ("__lanius_gen_i", FILE_CLOSURES),
            ("__lanius_closure_3", FILE_GENERATORS),
            ("__lanius_r", 0),
            ("__lanius_rest", FILE_CLOSURES),
            ("__lanius_state", FILE_GENERATORS | FILE_CLOSURES),
        ] {
            assert_eq!(verdict(&uses(name), flags), format!("`{name}`: {reserved}"), "{name}");
        }
    }

    /// Prints the parse tree of a machine, to see what the kernels read.
    #[test]
    #[ignore = "a debugging aid: prints the parse tree of a machine"]
    fn print_the_parse_tree_of_a_machine() {
        // `LANIUS_DUMP_FILE` names another source to print.
        let source = std::env::var("LANIUS_DUMP_FILE")
            .map(|path| std::fs::read_to_string(path).expect("read LANIUS_DUMP_FILE"))
            .unwrap_or_else(|_| "pub enum E { A, B(i32, u8), }\nmachine M on E -> i32 {\n    n: i32,\n    start S;\n    state S { E::A -> goto T(1) with 1, E::B(x, _) -> { if (x > 1) { stay with 2; } let y: i32 = __lanius_q; return 3; }, _ -> stay with 0, }\n    final state T(k: i32) { E::A -> stay with k, c -> stay with 0 }\n}\n".to_string());
        let source = source.as_str();
        let gpu_words = with_parse(&[source], |gpu, lexer, parser, encoder, parsed| {
            let nodes = parsed.tree_capacity;
            Ok((
                parsed.tree_capacity,
                parsed.token_capacity,
                read_all(gpu, encoder, &parser.node_kind, nodes),
                read_all(gpu, encoder, &parser.parent, nodes),
                read_all(gpu, encoder, &parser.out_emit_pos, nodes),
                read_all(gpu, encoder, &parser.hir_token_pos, nodes),
                read_all(gpu, encoder, &parser.hir_token_end, nodes),
                read_all(gpu, encoder, &parser.semantic_token_kinds, parsed.token_capacity + 2),
                gpu.read(encoder, &lexer.tokens_out, 0, parsed.token_capacity as usize * 3),
            ))
        }, |_, read| Ok(Some(read)))
        .expect("parse")
        .expect("the parser accepts the machine");
        let lexer = try_global_lexer().unwrap();
        let _ = lexer;
        let device = &crate::gpu::device::global().device;
        let queue = &crate::gpu::device::global().queue;
        let gpu = Gpu { device, queue };
        let (nodes, tokens, kind, parent, emit_pos, pos, end, semantic, raw) = gpu_words;
        let kind = gpu.words(&kind).unwrap();
        let parent = gpu.words(&parent).unwrap();
        let emit_pos = gpu.words(&emit_pos).unwrap();
        let pos = gpu.words(&pos).unwrap();
        let end = gpu.words(&end).unwrap();
        let semantic = gpu.words(&semantic).unwrap();
        let raw = gpu.words(&raw).unwrap();
        let names = production_names();
        println!("tokens: {tokens}");
        for token in 0..tokens as usize {
            let start = raw[token * 3 + 1] as usize;
            let len = raw[token * 3 + 2] as usize;
            println!(
                "  token {token}: raw={} sem[{token}]={} sem[{}]={} `{}`",
                raw[token * 3],
                semantic[token],
                token + 1,
                semantic[token + 1],
                &source[start..start + len]
            );
        }
        println!("nodes: {nodes}");
        for node in 0..nodes as usize {
            println!(
                "  node {node}: {} parent={} emit_pos={} pos={} end={}",
                names.get(kind[node] as usize).map_or("?", String::as_str),
                parent[node] as i32,
                emit_pos[node] as i32,
                pos[node] as i32,
                end[node] as i32
            );
        }
    }
}
