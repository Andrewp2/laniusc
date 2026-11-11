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

#[derive(encase::ShaderType)]
struct Params {
    a: u32,
    b: u32,
    c: u32,
    d: u32,
}

fn params(gpu: &Gpu<'_>, label: &str, a: u32, b: u32) -> LaniusBuffer<Params> {
    uniform_from_val(gpu.device, label, &Params { a, b, c: 0, d: 0 })
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
    frontend.parser.release_current_resident_buffers();
    outcome
}

/// What the first submission leaves for the later ones: the lexer's and
/// parser's buffers, the token records and the first prefix sums.
struct Marked {
    tokens: u32,
    tokens_out: LaniusBuffer<GpuToken>,
    token_file_id: LaniusBuffer<u32>,
    in_bytes: LaniusBuffer<u8>,
    source_file_start: LaniusBuffer<u32>,
    source_file_len: LaniusBuffer<u32>,
    semantic_token_kinds: LaniusBuffer<u32>,
    records: LaniusBuffer<u8>,
    marks: LaniusBuffer<u8>,
    scan: LaniusBuffer<u8>,
    /// The last row of `scan`: the number of machines, states and transitions.
    totals: LaniusBuffer<u8>,
}

/// Expands the machines of `sources`, one GPU run for all of them: one entry
/// per file, `None` for a file without machines. `None` when no file has a
/// machine, or when a file does not lex or parse: the frontend reports that.
pub(super) fn expand(sources: &[&str]) -> Result<Option<Vec<Option<Rewritten>>>> {
    if sources.iter().all(|source| source.is_empty()) {
        return Ok(None);
    }
    with_parse(sources, mark, |gpu, marked| match marked {
        Some(marked) => write(gpu, sources, &marked),
        None => Ok(None),
    })
}

/// Records the kernels that read the parse tree into token records and
/// number the machines.
fn mark(
    gpu: &Gpu<'_>,
    lexer: &GpuBuffers,
    parser: &ParserBuffers,
    encoder: &mut wgpu::CommandEncoder,
    parsed: &Parsed,
) -> Result<Option<Marked>> {
    let tokens = parsed.token_count;
    if tokens == 0 {
        return Ok(None);
    }
    let rows = tokens as usize;
    let records = gpu.rows("machines.records", rows * RECORD_WORDS, 1);
    let marks = gpu.rows("machines.marks", rows, 4);
    let work = [gpu.rows("machines.scan.a", rows, 4), gpu.rows("machines.scan.b", rows, 4)];
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
    let totals = gpu.read(encoder, &scan, (rows - 1) * 4, 4);
    Ok(Some(Marked {
        tokens,
        tokens_out: lexer.tokens_out.clone(),
        token_file_id: lexer.token_file_id.clone(),
        in_bytes: lexer.in_bytes.clone(),
        source_file_start: lexer.source_file_start.clone(),
        source_file_len: lexer.source_file_len.clone(),
        semantic_token_kinds: parser.semantic_token_kinds.clone(),
        records,
        marks,
        scan,
        totals,
    }))
}

/// Records the kernel that writes each marked token into its lists.
fn lists(
    gpu: &Gpu<'_>,
    encoder: &mut wgpu::CommandEncoder,
    kernel: &PassData,
    tokens: u32,
    marks: &LaniusBuffer<u8>,
    scan: &LaniusBuffer<u8>,
    label: &str,
) -> Result<[LaniusBuffer<u8>; 3]> {
    let rows = tokens as usize;
    let out = [gpu.rows(label, rows, 1), gpu.rows(label, rows, 1), gpu.rows(label, rows, 1)];
    let list_params = params(gpu, "machines.lists.params", tokens, 0);
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
        ],
        tokens,
    )?;
    Ok(out)
}

/// Writes the pieces of every machine and the expanded bytes.
fn write(gpu: &Gpu<'_>, sources: &[&str], marked: &Marked) -> Result<Option<Vec<Option<Rewritten>>>> {
    if gpu.words(&marked.totals)?[0] == 0 {
        return Ok(None);
    }
    let tokens = marked.tokens;
    let rows = tokens as usize;
    let scan_kernel = gpu.kernel("closures/scan")?;
    let list_kernel = gpu.kernel("machines/lists")?;
    let piece_kernel = gpu.kernel("machines/pieces")?;
    let (const_index, const_bytes) = constant_table(gpu.device);

    // The arms, fields and arguments, then the piece count of every token.
    let marks_b = gpu.rows("machines.context", rows, 4);
    let work_b = [gpu.rows("machines.context.a", rows, 4), gpu.rows("machines.context.b", rows, 4)];
    let counts = [gpu.rows("machines.counts0", rows, 4), gpu.rows("machines.counts1", rows, 4)];
    let count_work = [
        [gpu.rows("machines.counts0.a", rows, 4), gpu.rows("machines.counts0.b", rows, 4)],
        [gpu.rows("machines.counts1.a", rows, 4), gpu.rows("machines.counts1.b", rows, 4)],
    ];
    let no_pieces = [gpu.rows("machines.no_pieces", 1, 4), gpu.rows("machines.no_sources", 1, 4)];
    let mut encoder = gpu.encoder("machines.count");
    let [machines, states, transitions] =
        lists(gpu, &mut encoder, &list_kernel, tokens, &marked.marks, &marked.scan, "machines.lists.a")?;
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
    let [arms, fields, arguments] = lists(gpu, &mut encoder, &list_kernel, tokens, &marks_b, scan_b, "machines.lists.b")?;
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

    split_files(sources, &piece_rows, &piece_ends, &piece_anchors, &bytes).map(Some)
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
fn split_files(
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

    /// The files with machines that the host elaborator accepts, with the
    /// text it writes for each.
    fn host_expansions() -> Vec<(std::path::PathBuf, String, String)> {
        // LANIUS_MACHINE_ROOT names another checkout whose library to read.
        let root = std::env::var_os("LANIUS_MACHINE_ROOT")
            .map(std::path::PathBuf::from)
            .unwrap_or_else(|| std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../.."));
        let mut files = Vec::new();
        for dir in ["tests/fixtures/machines", "stdlib", "extended"] {
            lani_files(&root.join(dir), &mut files);
        }
        files.sort();
        let mut out = Vec::new();
        for path in files {
            let source = std::fs::read_to_string(&path).expect("read a source file");
            // Generators are rewritten before machines.
            if source.contains("gen fn") {
                continue;
            }
            if let Ok(Some(host)) = super::super::elaborate(&path, &source, false) {
                out.push((path, source, host.text));
            }
        }
        out
    }

    fn first_difference(path: &std::path::Path, expected: &str, actual: &str) -> String {
        let at = expected.bytes().zip(actual.bytes()).position(|(a, b)| a != b).unwrap_or(expected.len().min(actual.len()));
        let from = at.saturating_sub(120);
        let window = |text: &str| {
            let bytes = &text.as_bytes()[from.min(text.len())..(at + 120).min(text.len())];
            String::from_utf8_lossy(bytes).into_owned()
        };
        format!(
            "{}: the texts differ at byte {at} (lengths {} and {})\n--- host ---\n{}\n--- gpu ---\n{}\n",
            path.display(),
            expected.len(),
            actual.len(),
            window(expected),
            window(actual)
        )
    }

    #[test]
    fn the_gpu_writes_the_text_the_host_elaborator_writes() {
        let cases = host_expansions();
        assert!(cases.len() >= 5, "found {} files with machines", cases.len());
        println!("{} files with machines", cases.len());
        let mut failures = String::new();
        for (path, source, expected) in &cases {
            match expand(&[source]).expect("expand") {
                Some(files) => match &files[0] {
                    Some(file) if file.text == *expected => {}
                    Some(file) => failures.push_str(&first_difference(path, expected, &file.text)),
                    None => failures.push_str(&format!("{}: no machine found\n", path.display())),
                },
                // A closure is rewritten before machines: the parser does
                // not read one.
                None if source.contains('|') => {}
                None => failures.push_str(&format!("{}: not expanded\n", path.display())),
            }
        }
        assert!(failures.is_empty(), "{failures}");
    }

    /// Shapes the fixtures do not have: a public machine, state data, a
    /// transition to the same state with one and with several values, a
    /// binding arm, block arms, two machines in one file and text after the
    /// last one.
    #[test]
    fn the_gpu_matches_the_host_on_every_shape() {
        let sources = [
            "// before\npub machine Counter on i32 {\n    limit: i32,\n    scale: i64,\n    start Idle;\n    state Idle {\n        0 -> stay,\n        n -> goto Counting(n, 0),\n    }\n    state Counting(total: i32, seen: i32) {\n        0 -> goto Done(total),\n        n -> { if (n > self.limit) { goto Done(total); } goto Counting(total + n, seen + 1); },\n    }\n    final state Done(total: i32) {\n        _ -> stay,\n    }\n}\n// after\n",
            "enum Key { Up, Down(i32), Stop }\nmachine HTTPServer2 on Key -> i32 {\n    start A;\n    state A {\n        Key::Up -> goto B(1) with 1,\n        Key::Down(by) -> { let twice: i32 = by * 2; goto B(twice) with twice; },\n        Key::Stop -> stay with 0,\n    }\n    state B(level: i32) {\n        Key::Up -> goto B(level + 1) with level,\n        Key::Down(_) -> goto A with level,\n        Key::Stop -> goto C with 0\n    }\n    final state C { Key::Up -> stay with 0, Key::Down(_) -> stay with 0, Key::Stop -> stay with 0 }\n}\n\nfn between() -> i32 { return 2; }\n\nmachine Skip on u8 {\n    start Text;\n    state Text {\n        47 -> goto Slash,\n        c -> stay,\n    }\n    state Slash {\n        47 -> goto Text,\n        _other -> { goto Text; }\n    }\n}\nfn main() -> i32 { return between(); }\n",
            "machine One on i32 {\n    start First;\n    state First {\n        n -> goto Only(n),\n    }\n    final state Only(value: i32) {\n        0 -> goto Only(0),\n        n -> goto Only(value + n),\n    }\n}",
        ];
        let files = expand(&sources).expect("expand").expect("the pack has machines");
        let mut failures = String::new();
        for (index, source) in sources.iter().enumerate() {
            let path = std::path::PathBuf::from(format!("shape_{index}.lani"));
            let host = super::super::elaborate(&path, source, false)
                .unwrap_or_else(|err| panic!("the host rejects shape {index}: {err:?}"))
                .expect("the shape has a machine");
            match &files[index] {
                Some(file) if file.text == host.text => {}
                Some(file) => failures.push_str(&first_difference(&path, &host.text, &file.text)),
                None => failures.push_str(&format!("{}: no machine found\n", path.display())),
            }
        }
        assert!(failures.is_empty(), "{failures}");
    }

    #[test]
    fn one_run_expands_every_file_of_a_pack() {
        let cases = host_expansions();
        let cases: Vec<_> = cases.into_iter().filter(|(_, source, _)| !source.contains('|')).collect();
        let mut sources: Vec<&str> = vec!["fn plain() -> i32 { return 1; }\n"];
        sources.extend(cases.iter().map(|(_, source, _)| source.as_str()));
        let files = expand(&sources).expect("expand").expect("the pack has machines");
        assert!(files[0].is_none(), "a file without machines is not rewritten");
        let mut failures = String::new();
        for ((path, _, expected), file) in cases.iter().zip(&files[1..]) {
            match file {
                Some(file) if file.text == *expected => {}
                Some(file) => failures.push_str(&first_difference(path, expected, &file.text)),
                None => failures.push_str(&format!("{}: no machine found\n", path.display())),
            }
        }
        assert!(failures.is_empty(), "{failures}");
    }

    /// Prints the parse tree of a machine, to see what the kernels read.
    #[test]
    #[ignore = "a debugging aid: prints the parse tree of a machine"]
    fn print_the_parse_tree_of_a_machine() {
        let source = "enum E { A, B }\nmachine M on E -> i32 {\n    n: i32,\n    start S;\n    state S { E::A -> goto T(1) with 1, E::B -> { stay with 2; }, }\n    final state T(k: i32) { E::A -> stay with k, E::B -> stay with 0 }\n}\n";
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
