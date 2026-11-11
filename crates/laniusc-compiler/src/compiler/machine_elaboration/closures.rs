//! Closures (docs/language-ergonomics.md).
//!
//! A closure `|x: T| body` becomes a struct of the locals it captures, a
//! `borrow` method and an impl of `core::function::Mapper` (or `Producer`
//! for `|| body`). The site becomes a literal of that struct, borrowed.
//!
//! The rewrite runs on the GPU over the raw lexer tokens of all the files of
//! one load (shaders/closures). The host records the commands, sizes the
//! buffers from the counts the kernels publish, and reads back the rewritten
//! text and the piece table that maps it to the source.

use anyhow::{Context, Result, anyhow};

use super::Segment;
use crate::{
    gpu::{
        buffers::{
            LaniusBuffer,
            readback_bytes,
            storage_ro_from_bytes,
            storage_ro_from_u32s,
            storage_rw_uninit_bytes,
            uniform_from_val,
        },
        passes_core::{
            self,
            DispatchDim,
            InputElements,
            PassData,
            make_pass_data_from_shader_key,
            map_readback_blocking,
        },
    },
    lexer::{buffers::GpuBuffers, driver::try_global_lexer},
};

/// The strings the kernels insert, in the order of the `C_*` ids in
/// shaders/closures/closure_common.slang.
/// A string that follows a copied type starts with a space, so a type that
/// ends in `>` does not join it into `>=` or `>>`.
const CONSTANTS: [&str; 24] = [
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
];

const RECORD_WORDS: usize = 12;
const PIECES_PER_FILE: u32 = 3;
const PIECES_PER_CLOSURE: u32 = 30;
const PIECES_PER_CAPTURE: u32 = 15;
const PIECE_COPY: u32 = 0;
const PIECE_ID: u32 = 2;
const NO_CLOSURE: u32 = u32::MAX;
const NO_ERROR: u32 = u32::MAX;

/// One file with its closures rewritten.
pub(super) struct Rewritten {
    pub(super) text: String,
    pub(super) segments: Vec<Segment>,
}

/// A closure the rewrite rejects, as a byte span of one file.
pub(super) struct Invalid {
    pub(super) file: usize,
    pub(super) start: usize,
    pub(super) len: usize,
    pub(super) message: &'static str,
}

pub(super) enum Outcome {
    /// One entry per file: `None` for a file without closures.
    Rewritten(Vec<Option<Rewritten>>),
    Invalid(Invalid),
}

#[derive(encase::ShaderType)]
struct ScanParams {
    count: u32,
    step: u32,
    reserved0: u32,
    reserved1: u32,
}

#[derive(encase::ShaderType)]
struct SummaryParams {
    slot: u32,
    component: u32,
    reserved0: u32,
    reserved1: u32,
}

#[derive(encase::ShaderType)]
struct LayoutParams {
    file_count: u32,
    closure_count: u32,
    capture_count: u32,
    piece_count: u32,
    byte_count: u32,
    reserved0: u32,
    reserved1: u32,
    reserved2: u32,
}

#[derive(encase::ShaderType)]
struct EmitParams {
    out_len: u32,
    piece_count: u32,
    reserved0: u32,
    reserved1: u32,
}

type Binding<'a> = (&'static str, wgpu::BindingResource<'a>);

struct Gpu<'a> {
    device: &'a wgpu::Device,
    queue: &'a wgpu::Queue,
}

impl Gpu<'_> {
    fn kernel(&self, key: &'static str) -> Result<PassData> {
        make_pass_data_from_shader_key(self.device, key, "main", key)
    }

    fn encoder(&self, label: &str) -> wgpu::CommandEncoder {
        self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(label) })
    }

    /// A zeroed storage buffer of `rows` rows of `row_words` words.
    fn rows(&self, label: &str, rows: usize, row_words: usize) -> LaniusBuffer<u8> {
        let rows = rows.max(1);
        storage_rw_uninit_bytes(self.device, label, rows * row_words * 4, rows)
    }

    fn dispatch(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        pass: &PassData,
        label: &str,
        bindings: &[Binding<'_>],
        elements: u32,
    ) -> Result<()> {
        passes_core::bind_group::validate_exact_binding_names(pass, 0, bindings)
            .with_context(|| format!("bind {label}"))?;
        let group =
            passes_core::bind_group::create_bind_group_from_bindings(self.device, Some(label), pass, 0, bindings)?;
        let (x, y, z) =
            passes_core::plan_workgroups(DispatchDim::D1, InputElements::Elements1D(elements), pass.thread_group_size)?;
        let mut compute = passes_core::begin_counted_compute_pass(
            encoder,
            &wgpu::ComputePassDescriptor { label: Some(label), timestamp_writes: None },
        );
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, Some(&group), &[]);
        passes_core::record_compute_dispatch();
        if !passes_core::debug_operation_skipped() {
            compute.dispatch_workgroups(x, y, z);
        }
        Ok(())
    }

    /// Records an inclusive prefix sum of `input` and returns the buffer
    /// that holds it: one doubling step per power of two below `count`.
    fn scan<'b>(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        pass: &PassData,
        input: &'b LaniusBuffer<u8>,
        work: &'b [LaniusBuffer<u8>; 2],
        count: u32,
    ) -> Result<&'b LaniusBuffer<u8>> {
        let mut source = input;
        let mut target = 0;
        let mut step = 1u32;
        loop {
            let params = uniform_from_val(
                self.device,
                "closures.scan.params",
                &ScanParams { count, step, reserved0: 0, reserved1: 0 },
            );
            self.dispatch(
                encoder,
                pass,
                "closures.scan",
                &[
                    ("gScan", params.as_entire_binding()),
                    ("scan_in", source.as_entire_binding()),
                    ("scan_out", work[target].as_entire_binding()),
                ],
                count,
            )?;
            source = &work[target];
            target = 1 - target;
            step = match step.checked_mul(2) {
                Some(next) if next < count => next,
                _ => return Ok(source),
            };
        }
    }

    fn summary(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        pass: &PassData,
        bufs: &GpuBuffers,
        scan_result: &LaniusBuffer<u8>,
        summary: &LaniusBuffer<u8>,
        slot: u32,
        component: u32,
    ) -> Result<()> {
        let params = uniform_from_val(
            self.device,
            "closures.summary.params",
            &SummaryParams { slot, component, reserved0: 0, reserved1: 0 },
        );
        self.dispatch(
            encoder,
            pass,
            "closures.summary",
            &[
                ("gSummary", params.as_entire_binding()),
                ("token_count", bufs.token_count.as_entire_binding()),
                ("scan_result", scan_result.as_entire_binding()),
                ("summary", summary.as_entire_binding()),
            ],
            1,
        )
    }

    /// Records a copy of `words` words of `source` for the host to read.
    fn read<T>(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        source: &LaniusBuffer<T>,
        first_word: usize,
        words: usize,
    ) -> LaniusBuffer<u8> {
        let words = words.max(1);
        let readback = readback_bytes(self.device, "closures.readback", words * 4, words);
        source.copy_to(encoder, first_word as u64 * 4, &readback, 0, words as u64 * 4);
        readback
    }

    fn submit(&self, label: &str, encoder: wgpu::CommandEncoder) {
        passes_core::submit_with_progress(self.queue, label, encoder.finish());
    }

    fn words(&self, readback: &LaniusBuffer<u8>) -> Result<Vec<u32>> {
        let slice = readback.slice(..);
        map_readback_blocking(self.device, &slice, "closures.readback")?;
        let mapped = slice.get_mapped_range();
        let words = mapped
            .chunks_exact(4)
            .map(|word| u32::from_le_bytes([word[0], word[1], word[2], word[3]]))
            .collect();
        drop(mapped);
        readback.unmap();
        Ok(words)
    }
}

/// Rewrites the closures of `sources`, one GPU run for all of them. `None`
/// when no file has a closure, or when a file does not lex: the frontend
/// reports that.
pub(super) fn rewrite(sources: &[&str]) -> Result<Option<Outcome>> {
    let total: usize = sources.iter().map(|source| source.len()).sum();
    if total == 0 {
        return Ok(None);
    }
    let lexer = try_global_lexer()?;
    pollster::block_on(lexer.with_resident_source_pack_tokens(sources, |device, queue, bufs| {
        run(&Gpu { device, queue }, bufs, sources, total)
    }))?
}

fn run(gpu: &Gpu<'_>, bufs: &GpuBuffers, sources: &[&str], total: usize) -> Result<Option<Outcome>> {
    let total_u32 = u32::try_from(total).context("source pack is too large")?;
    let file_count = u32::try_from(sources.len()).context("too many source files")?;
    let scan_kernel = gpu.kernel("closures/scan")?;
    let summary_kernel = gpu.kernel("closures/summary")?;

    // Depth and closure starts per token.
    let marks = gpu.rows("closures.marks", total, 4);
    let roles = gpu.rows("closures.roles", total, 1);
    let depth_work = [gpu.rows("closures.depth.a", total, 4), gpu.rows("closures.depth.b", total, 4)];
    let summary = gpu.rows("closures.summary", 4, 1);
    let mut encoder = gpu.encoder("closures.mark");
    gpu.dispatch(
        &mut encoder,
        &gpu.kernel("closures/mark")?,
        "closures.mark",
        &[
            ("token_count", bufs.token_count.as_entire_binding()),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("token_file_id", bufs.token_file_id.as_entire_binding()),
            ("marks", marks.as_entire_binding()),
            ("roles", roles.as_entire_binding()),
        ],
        total_u32,
    )?;
    let depth_scan = gpu.scan(&mut encoder, &scan_kernel, &marks, &depth_work, total_u32)?;
    gpu.summary(&mut encoder, &summary_kernel, bufs, depth_scan, &summary, 1, 1)?;
    let summary_read = gpu.read(&mut encoder, &summary, 0, 4);
    let lex_error_read = gpu.read(&mut encoder, &bufs.lex_error_offset, 0, 1);
    gpu.submit("closures.mark", encoder);
    let counts = gpu.words(&summary_read)?;
    let closure_count = counts[1];
    if gpu.words(&lex_error_read)?[0] != 0 || closure_count == 0 {
        return Ok(None);
    }

    // The parts of each closure and the locals it captures.
    let records = gpu.rows("closures.records", closure_count as usize * RECORD_WORDS, 1);
    let status = storage_ro_from_u32s(gpu.device, "closures.status", &[NO_ERROR]);
    let capture_marks = gpu.rows("closures.capture_marks", total, 4);
    let capture_work = [gpu.rows("closures.capture.a", total, 4), gpu.rows("closures.capture.b", total, 4)];
    let mut encoder = gpu.encoder("closures.records");
    gpu.dispatch(
        &mut encoder,
        &gpu.kernel("closures/records")?,
        "closures.records",
        &[
            ("token_count", bufs.token_count.as_entire_binding()),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("token_file_id", bufs.token_file_id.as_entire_binding()),
            ("depth_scan", depth_scan.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("status", status.as_entire_binding()),
        ],
        total_u32,
    )?;
    gpu.dispatch(
        &mut encoder,
        &gpu.kernel("closures/captures")?,
        "closures.captures",
        &[
            ("token_count", bufs.token_count.as_entire_binding()),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("token_file_id", bufs.token_file_id.as_entire_binding()),
            ("in_bytes", bufs.in_bytes.as_entire_binding()),
            ("roles", roles.as_entire_binding()),
            ("depth_scan", depth_scan.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("summary", summary.as_entire_binding()),
            ("capture_marks", capture_marks.as_entire_binding()),
            ("status", status.as_entire_binding()),
        ],
        total_u32,
    )?;
    let capture_scan = gpu.scan(&mut encoder, &scan_kernel, &capture_marks, &capture_work, total_u32)?;
    gpu.summary(&mut encoder, &summary_kernel, bufs, capture_scan, &summary, 2, 0)?;
    let summary_read = gpu.read(&mut encoder, &summary, 0, 4);
    let status_read = gpu.read(&mut encoder, &status, 0, 1);
    gpu.submit("closures.records", encoder);
    let capture_count = gpu.words(&summary_read)?[2];
    let failure = gpu.words(&status_read)?[0];
    if failure != NO_ERROR {
        return invalid(gpu, bufs, sources, failure).map(|invalid| Some(Outcome::Invalid(invalid)));
    }

    // The pieces of the rewritten pack and their lengths.
    let piece_count = file_count
        .checked_mul(PIECES_PER_FILE)
        .zip(closure_count.checked_mul(PIECES_PER_CLOSURE))
        .zip(capture_count.checked_mul(PIECES_PER_CAPTURE))
        .and_then(|((files, closures), captures)| files.checked_add(closures)?.checked_add(captures))
        .context("too many closures")?;
    let pieces_len = piece_count as usize;
    let captures = gpu.rows("closures.captures", capture_count as usize, 4);
    let file_info = gpu.rows("closures.file_info", sources.len() + 1, 4);
    let pieces = gpu.rows("closures.pieces", pieces_len, 4);
    let piece_work = [gpu.rows("closures.pieces.a", pieces_len, 4), gpu.rows("closures.pieces.b", pieces_len, 4)];
    let layout = uniform_from_val(
        gpu.device,
        "closures.layout.params",
        &LayoutParams {
            file_count,
            closure_count,
            capture_count,
            piece_count,
            byte_count: total_u32,
            reserved0: 0,
            reserved1: 0,
            reserved2: 0,
        },
    );
    let (const_index, const_bytes) = constant_table(gpu.device);
    let mut encoder = gpu.encoder("closures.pieces");
    gpu.dispatch(
        &mut encoder,
        &gpu.kernel("closures/layout")?,
        "closures.layout",
        &[
            ("token_count", bufs.token_count.as_entire_binding()),
            ("depth_scan", depth_scan.as_entire_binding()),
            ("capture_marks", capture_marks.as_entire_binding()),
            ("capture_scan", capture_scan.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("captures", captures.as_entire_binding()),
        ],
        total_u32,
    )?;
    gpu.dispatch(
        &mut encoder,
        &gpu.kernel("closures/files")?,
        "closures.files",
        &[
            ("gLayout", layout.as_entire_binding()),
            ("token_count", bufs.token_count.as_entire_binding()),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("token_file_id", bufs.token_file_id.as_entire_binding()),
            ("depth_scan", depth_scan.as_entire_binding()),
            ("capture_scan", capture_scan.as_entire_binding()),
            ("source_file_start", bufs.source_file_start.as_entire_binding()),
            ("file_info", file_info.as_entire_binding()),
        ],
        file_count + 1,
    )?;
    gpu.dispatch(
        &mut encoder,
        &gpu.kernel("closures/pieces")?,
        "closures.pieces",
        &[
            ("gLayout", layout.as_entire_binding()),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("source_file_start", bufs.source_file_start.as_entire_binding()),
            ("source_file_len", bufs.source_file_len.as_entire_binding()),
            ("records", records.as_entire_binding()),
            ("captures", captures.as_entire_binding()),
            ("file_info", file_info.as_entire_binding()),
            ("const_index", const_index.as_entire_binding()),
            ("pieces", pieces.as_entire_binding()),
        ],
        piece_count,
    )?;
    let piece_scan = gpu.scan(&mut encoder, &scan_kernel, &pieces, &piece_work, piece_count)?;
    let pieces_read = gpu.read(&mut encoder, &pieces, 0, pieces_len * 4);
    let piece_scan_read = gpu.read(&mut encoder, piece_scan, 0, pieces_len * 4);
    let file_info_read = gpu.read(&mut encoder, &file_info, 0, (sources.len() + 1) * 4);
    gpu.submit("closures.pieces", encoder);
    let piece_rows = gpu.words(&pieces_read)?;
    let piece_ends = gpu.words(&piece_scan_read)?;
    let file_rows = gpu.words(&file_info_read)?;
    let out_len = piece_ends[(pieces_len - 1) * 4];

    // The rewritten bytes.
    let out_words = (out_len as usize).div_ceil(4);
    let output = gpu.rows("closures.output", out_words, 1);
    let emit = uniform_from_val(
        gpu.device,
        "closures.emit.params",
        &EmitParams { out_len, piece_count, reserved0: 0, reserved1: 0 },
    );
    let mut encoder = gpu.encoder("closures.emit");
    gpu.dispatch(
        &mut encoder,
        &gpu.kernel("closures/emit")?,
        "closures.emit",
        &[
            ("gEmit", emit.as_entire_binding()),
            ("in_bytes", bufs.in_bytes.as_entire_binding()),
            ("pieces", pieces.as_entire_binding()),
            ("piece_scan", piece_scan.as_entire_binding()),
            ("const_index", const_index.as_entire_binding()),
            ("const_bytes", const_bytes.as_entire_binding()),
            ("out_words", output.as_entire_binding()),
        ],
        u32::try_from(out_words).context("rewritten source is too large")?,
    )?;
    let output_read = gpu.read(&mut encoder, &output, 0, out_words);
    gpu.submit("closures.emit", encoder);
    let mut bytes: Vec<u8> = gpu.words(&output_read)?.into_iter().flat_map(u32::to_le_bytes).collect();
    bytes.truncate(out_len as usize);

    split_files(sources, &file_rows, &piece_rows, &piece_ends, &bytes).map(|files| Some(Outcome::Rewritten(files)))
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
        storage_ro_from_u32s(device, "closures.const_index", &index),
        storage_ro_from_bytes(device, "closures.const_bytes", &bytes, count),
    )
}

/// Cuts the rewritten pack into its files and builds the map from each
/// rewritten byte to the source. A piece row is `(len, kind, source,
/// closure)`; a file row is `(first token, closures before, captures before,
/// import offset)`.
fn split_files(
    sources: &[&str],
    file_rows: &[u32],
    piece_rows: &[u32],
    piece_ends: &[u32],
    bytes: &[u8],
) -> Result<Vec<Option<Rewritten>>> {
    let piece_base = |file: usize| {
        file * PIECES_PER_FILE as usize
            + file_rows[file * 4 + 1] as usize * PIECES_PER_CLOSURE as usize
            + file_rows[file * 4 + 2] as usize * PIECES_PER_CAPTURE as usize
    };
    let end_before = |piece: usize| if piece == 0 { 0 } else { piece_ends[(piece - 1) * 4] as usize };
    let mut files = Vec::with_capacity(sources.len());
    let mut file_start = 0usize;
    for (file, source) in sources.iter().enumerate() {
        let first_closure = file_rows[file * 4 + 1];
        let closures = (file_rows[(file + 1) * 4 + 1] - first_closure) as usize;
        let (first, last) = (piece_base(file), piece_base(file + 1));
        let out_start = end_before(first);
        let piece = |index: usize| {
            let row = &piece_rows[index * 4..index * 4 + 4];
            (row[0] as usize, row[1], row[2] as usize, row[3])
        };
        if closures == 0 {
            files.push(None);
            file_start += source.len();
            continue;
        }

        // The source span of each closure: from its `|` to the end of its
        // body, which is the last text any of its pieces copies.
        let mut spans = vec![(usize::MAX, 0usize); closures];
        for index in first..last {
            let (len, kind, src, closure) = piece(index);
            if closure == NO_CLOSURE {
                continue;
            }
            let span = &mut spans[(closure - first_closure) as usize];
            if kind == PIECE_COPY {
                span.1 = span.1.max(src + len - file_start);
            } else if kind == PIECE_ID {
                span.0 = src;
            }
        }
        let import_at = file_rows[file * 4 + 3] as usize - file_start;
        let mut segments = Vec::with_capacity(last - first);
        for index in first..last {
            let (len, kind, src, closure) = piece(index);
            if len == 0 {
                continue;
            }
            let (src_start, src_len) = if kind == PIECE_COPY {
                (src - file_start, len)
            } else if closure == NO_CLOSURE {
                (import_at, 0)
            } else {
                let (start, end) = spans[(closure - first_closure) as usize];
                (start, end.saturating_sub(start))
            };
            segments.push(Segment {
                out_start: end_before(index) - out_start,
                out_len: len,
                src_start,
                src_len,
                copied: kind == PIECE_COPY,
            });
        }
        let text = String::from_utf8(bytes[out_start..end_before(last)].to_vec())
            .map_err(|_| anyhow!("the closure rewrite produced text that is not UTF-8"))?;
        files.push(Some(Rewritten { text, segments }));
        file_start += source.len();
    }
    Ok(files)
}

/// The span and message of the first rejected closure. `failure` is
/// `token << 4 | code`.
fn invalid(gpu: &Gpu<'_>, bufs: &GpuBuffers, sources: &[&str], failure: u32) -> Result<Invalid> {
    let token = (failure >> 4) as usize;
    let mut encoder = gpu.encoder("closures.invalid");
    let token_read = gpu.read(&mut encoder, &bufs.tokens_out, token * 3, 3);
    let file_read = gpu.read(&mut encoder, &bufs.token_file_id, token, 1);
    gpu.submit("closures.invalid", encoder);
    let row = gpu.words(&token_read)?;
    let file = gpu.words(&file_read)?[0] as usize;
    let file_start: usize = sources.iter().take(file).map(|source| source.len()).sum();
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
    Ok(Invalid {
        file,
        start: (row[1] as usize).saturating_sub(file_start),
        len: row[2] as usize,
        message,
    })
}
