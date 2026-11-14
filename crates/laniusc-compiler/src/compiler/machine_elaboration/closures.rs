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

use std::{
    collections::{HashMap, hash_map::Entry},
    sync::{Arc, LazyLock, Mutex, MutexGuard, PoisonError},
};

use anyhow::{Context, Result, anyhow};

use super::Segment;
use crate::{
    gpu::{
        buffers::{CapacityBufferCache, LaniusBuffer, live_tracked_allocation_ids, tracked_buffer_identity},
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

const RECORD_WORDS: usize = 12;
const PIECES_PER_FILE: u32 = 3;
const PIECES_PER_CLOSURE: u32 = 44;
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
    /// A file does not lex. The frontend reports that.
    Unlexed,
}

#[derive(encase::ShaderType)]
struct ScanParams {
    count: u32,
    mode: u32,
    tiles: u32,
    reserved0: u32,
}

#[derive(encase::ShaderType)]
struct SummaryParams {
    slot: u32,
    component: u32,
    reserved0: u32,
    reserved1: u32,
}

#[derive(encase::ShaderType)]
struct DepthTreeParams {
    n_blocks: u32,
    leaf_base: u32,
    start_node: u32,
    node_count: u32,
    mode: u32,
    levels: u32,
    reserved0: u32,
    reserved1: u32,
}

#[derive(encase::ShaderType)]
struct RoleParams {
    leaf_base: u32,
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

/// What a buffer the kernels read and write is used for.
const STORAGE: wgpu::BufferUsages =
    wgpu::BufferUsages::STORAGE.union(wgpu::BufferUsages::COPY_SRC).union(wgpu::BufferUsages::COPY_DST);
/// What a buffer the host maps is used for.
const READBACK: wgpu::BufferUsages = wgpu::BufferUsages::MAP_READ.union(wgpu::BufferUsages::COPY_DST);

pub(super) type Binding<'a> = (&'static str, wgpu::BindingResource<'a>);

pub(super) struct Gpu<'a> {
    pub(super) device: &'a wgpu::Device,
    pub(super) queue: &'a wgpu::Queue,
}

/// The bytes of one capacity step of a resident buffer: 4096 rows of four
/// words, the token granularity of the parser's resident workspace.
const BUCKET_BYTES: usize = 4 * 1024 * 16;
/// Lanes of one prefix-sum workgroup, and the rows one workgroup sums
/// (`WG_SIZE` and `TILE_ROWS` in closures/scan.slang).
const SCAN_WORKGROUP_LANES: u32 = 256;
const SCAN_TILE_ROWS: u32 = SCAN_WORKGROUP_LANES * 8;
/// The modes of closures/scan.slang.
const SCAN_TILE_TOTALS: u32 = 0;
const SCAN_TILE_OFFSETS: u32 = 1;
const SCAN_APPLY: u32 = 2;

/// The buffers and bind groups the rewrites keep between runs. A resident
/// compiler runs them again for every source text it has not seen, so a run
/// takes its storage from the run before it, as the compiler's stages do.
#[derive(Default)]
struct Resident {
    buffers: CapacityBufferCache,
    state: Mutex<ResidentState>,
    /// Held for one run: the keys of `ResidentState::taken` name one run's
    /// buffers.
    run: Mutex<()>,
}

#[derive(Default)]
struct ResidentState {
    /// The buffers this run took, per label. The next one of a label gets
    /// the next key, so a run finds the buffers of the run before it.
    taken: HashMap<String, u32>,
    /// The bytes each key holds.
    capacity: HashMap<String, usize>,
    /// Row buffers the next dispatch zeroes before it runs: a kernel reads a
    /// row no kernel wrote as zero.
    stale: Vec<LaniusBuffer<u8>>,
    /// Bind groups by kernel and by the name, allocation, offset and size of
    /// each binding.
    groups: HashMap<(String, Vec<(&'static str, [u64; 3])>), Arc<wgpu::BindGroup>>,
}

static RESIDENT: LazyLock<Resident> = LazyLock::new(Resident::default);

impl Resident {
    fn state(&self) -> MutexGuard<'_, ResidentState> {
        self.state.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

impl ResidentState {
    /// The key of the next buffer of `label` and the bytes it holds once it
    /// covers `bytes`. A buffer that grows gets 1/64 more than it needs,
    /// rounded up to `BUCKET_BYTES`, so the next text of nearly the same size
    /// fits.
    fn take(&mut self, label: &str, bytes: usize) -> (String, usize) {
        let taken = self.taken.entry(label.to_owned()).or_default();
        let key = format!("{label}#{taken}");
        *taken += 1;
        let bytes = bytes.max(4).next_multiple_of(4);
        let held = self.capacity.entry(key.clone()).or_default();
        if *held < bytes {
            *held = (bytes + bytes / 64).next_multiple_of(BUCKET_BYTES);
        }
        (key, *held)
    }
}

/// Starts one run of a rewrite. The guard keeps other runs out until it
/// drops.
pub(super) fn begin_run() -> MutexGuard<'static, ()> {
    let guard = RESIDENT.run.lock().unwrap_or_else(PoisonError::into_inner);
    let mut state = RESIDENT.state();
    state.taken.clear();
    // A bind group keeps its buffers alive. Drop the ones whose buffer the
    // lexer, the parser or this pool has replaced.
    let live = live_tracked_allocation_ids();
    state.groups.retain(|(_, bindings), _| bindings.iter().all(|(_, binding)| live.contains(&binding[0])));
    guard
}

/// Frees the buffers of the rewrites. The next run allocates them again.
pub(super) fn release_resident_buffers() {
    let _run = RESIDENT.run.lock().unwrap_or_else(PoisonError::into_inner);
    let mut state = RESIDENT.state();
    *state = ResidentState::default();
    RESIDENT.buffers.clear();
}

/// The allocation, offset and size a binding names, when it is a buffer the
/// compiler tracks.
fn binding_identity(resource: &wgpu::BindingResource<'_>) -> Option<[u64; 3]> {
    let wgpu::BindingResource::Buffer(binding) = resource else {
        return None;
    };
    let (allocation, _, _) = tracked_buffer_identity(binding.buffer)?;
    Some([allocation, binding.offset, binding.size.map_or(0, std::num::NonZeroU64::get)])
}

impl Gpu<'_> {
    pub(super) fn kernel(&self, key: &'static str) -> Result<PassData> {
        make_pass_data_from_shader_key(self.device, key, "main", key)
    }

    pub(super) fn encoder(&self, label: &str) -> wgpu::CommandEncoder {
        self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(label) })
    }

    /// The whole resident buffer of the next `label`, grown to cover `bytes`.
    /// A kernel reads the count of its rows from its parameters, so the bind
    /// group stays the same while the text fits.
    fn resident(&self, state: &mut ResidentState, label: &str, bytes: usize, usage: wgpu::BufferUsages) -> LaniusBuffer<u8> {
        let (key, capacity) = state.take(label, bytes);
        RESIDENT.buffers.binding_capacity(self.device, &key, capacity, usage)
    }

    /// A zeroed storage buffer of at least `rows` rows of `row_words` words.
    pub(super) fn rows(&self, label: &str, rows: usize, row_words: usize) -> LaniusBuffer<u8> {
        let mut state = RESIDENT.state();
        let buffer = self.resident(&mut state, label, rows.max(1) * row_words * 4, STORAGE);
        state.stale.push(buffer.clone());
        buffer
    }

    /// A storage buffer that starts with `words`.
    pub(super) fn words_from(&self, label: &str, words: &[u32]) -> LaniusBuffer<u32> {
        let bytes: Vec<u8> = words.iter().flat_map(|word| word.to_le_bytes()).collect();
        self.bytes_from(label, &bytes).reinterpret(words.len())
    }

    /// A storage buffer that starts with `bytes`, a whole number of words.
    pub(super) fn bytes_from(&self, label: &str, bytes: &[u8]) -> LaniusBuffer<u8> {
        let buffer = self.resident(&mut RESIDENT.state(), label, bytes.len(), STORAGE);
        buffer.write(self.queue, 0, bytes);
        buffer
    }

    /// The parameters of one dispatch.
    pub(super) fn uniform<T>(&self, label: &str, value: &T) -> LaniusBuffer<T>
    where
        T: encase::ShaderType + encase::internal::WriteInto,
    {
        // Every value of one label has the same size, so its buffer never
        // grows.
        let (key, _) = RESIDENT.state().take(label, 0);
        RESIDENT.buffers.uniform(self.device, self.queue, &key, value)
    }

    pub(super) fn dispatch(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        pass: &PassData,
        label: &str,
        bindings: &[Binding<'_>],
        elements: u32,
    ) -> Result<()> {
        passes_core::bind_group::validate_exact_binding_names(pass, 0, bindings)
            .with_context(|| format!("bind {label}"))?;
        let create = || {
            passes_core::bind_group::create_bind_group_from_bindings(self.device, Some(label), pass, 0, bindings)
                .map(Arc::new)
        };
        let group = {
            let mut state = RESIDENT.state();
            for buffer in state.stale.drain(..) {
                buffer.clear(encoder, 0, None);
            }
            let identity: Option<Vec<_>> =
                bindings.iter().map(|(name, resource)| Some((*name, binding_identity(resource)?))).collect();
            match identity {
                None => create()?,
                Some(identity) => match state.groups.entry((pass.shader_id.clone(), identity)) {
                    Entry::Occupied(group) => group.get().clone(),
                    Entry::Vacant(slot) => slot.insert(create()?).clone(),
                },
            }
        };
        let (x, y, z) =
            passes_core::plan_workgroups(DispatchDim::D1, InputElements::Elements1D(elements), pass.thread_group_size)?;
        let mut compute = passes_core::begin_counted_compute_pass(
            encoder,
            &wgpu::ComputePassDescriptor { label: Some(label), timestamp_writes: None },
        );
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, Some(group.as_ref()), &[]);
        passes_core::record_compute_dispatch();
        if !passes_core::debug_operation_skipped() {
            compute.dispatch_workgroups(x, y, z);
        }
        drop(compute);
        // A profiled job needs one timestamp per dispatch.
        crate::gpu::timer::stamp_active_operation(encoder, label.to_owned());
        Ok(())
    }

    /// Records an inclusive prefix sum of `input` and returns the buffer
    /// that holds it (closures/scan.slang): per tile of `SCAN_TILE_ROWS`
    /// rows, a total, then one workgroup's offsets for the tiles, then each
    /// tile's sum from its offset. A sum of one tile is one dispatch. The
    /// bindings do not depend on `count`, so neither does the bind group.
    pub(super) fn scan<'b>(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        pass: &PassData,
        input: &'b LaniusBuffer<u8>,
        work: &'b [LaniusBuffer<u8>; 2],
        count: u32,
    ) -> Result<&'b LaniusBuffer<u8>> {
        let tiles = count.max(1).div_ceil(SCAN_TILE_ROWS);
        let modes: &[u32] = if tiles > 1 { &[SCAN_TILE_TOTALS, SCAN_TILE_OFFSETS, SCAN_APPLY] } else { &[SCAN_APPLY] };
        for &mode in modes {
            let params = self.uniform("closures.scan.params", &ScanParams { count, mode, tiles, reserved0: 0 });
            // Mode 1 runs in one workgroup; the others in one per tile.
            let lanes = if mode == SCAN_TILE_OFFSETS { 1 } else { tiles * SCAN_WORKGROUP_LANES };
            self.dispatch(
                encoder,
                pass,
                "closures.scan",
                &[
                    ("gScan", params.as_entire_binding()),
                    ("scan_in", input.as_entire_binding()),
                    ("scan_tiles", work[1].as_entire_binding()),
                    ("scan_out", work[0].as_entire_binding()),
                ],
                lanes,
            )?;
        }
        Ok(&work[0])
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
        let params =
            self.uniform("closures.summary.params", &SummaryParams { slot, component, reserved0: 0, reserved1: 0 });
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
    pub(super) fn read<T>(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        source: &LaniusBuffer<T>,
        first_word: usize,
        words: usize,
    ) -> LaniusBuffer<u8> {
        let words = words.max(1);
        let readback = self
            .resident(&mut RESIDENT.state(), "closures.readback", words * 4, READBACK)
            .subrange(0, words as u64 * 4, words)
            .expect("the readback buffer covers the words it was sized for");
        source.copy_to(encoder, first_word as u64 * 4, &readback, 0, words as u64 * 4);
        readback
    }

    pub(super) fn submit(&self, label: &str, encoder: wgpu::CommandEncoder) {
        passes_core::submit_with_progress(self.queue, label, encoder.finish());
    }

    pub(super) fn words(&self, readback: &LaniusBuffer<u8>) -> Result<Vec<u32>> {
        let slice = readback.buffer.slice(readback.byte_offset..readback.byte_offset + readback.byte_size as u64);
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
/// when no file has a closure.
pub(super) fn rewrite(sources: &[&str]) -> Result<Option<Outcome>> {
    let total: usize = sources.iter().map(|source| source.len()).sum();
    if total == 0 {
        return Ok(None);
    }
    let _run = begin_run();
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

    // Depth changes and closure starts per token. The mark kernel counts
    // starts in the freshly cleared summary; the existing readback then
    // gates all depth/role work for packs without closures.
    let marks = gpu.rows("closures.marks", total, 4);
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
            ("in_bytes", bufs.in_bytes.as_entire_binding()),
            ("marks", marks.as_entire_binding()),
            ("summary", summary.as_entire_binding()),
        ],
        total_u32,
    )?;
    let summary_read = gpu.read(&mut encoder, &summary, 0, 4);
    let lex_error_read = gpu.read(&mut encoder, &bufs.lex_error_offset, 0, 1);
    gpu.submit("closures.mark", encoder);
    let counts = gpu.words(&summary_read)?;
    let closure_count = counts[1];
    if gpu.words(&lex_error_read)?[0] != 0 {
        return Ok(Some(Outcome::Unlexed));
    }
    if closure_count == 0 {
        return Ok(None);
    }

    // The parts of each closure and the locals it captures.
    let records = gpu.rows("closures.records", closure_count as usize * RECORD_WORDS, 1);
    let status = gpu.words_from("closures.status", &[NO_ERROR]);
    let capture_marks = gpu.rows("closures.capture_marks", total, 4);
    let capture_work = [gpu.rows("closures.capture.a", total, 4), gpu.rows("closures.capture.b", total, 4)];
    let mut encoder = gpu.encoder("closures.records");
    let depth_work = [gpu.rows("closures.depth.a", total, 4), gpu.rows("closures.depth.b", total, 4)];
    let depth_scan = gpu.scan(&mut encoder, &scan_kernel, &marks, &depth_work, total_u32)?;
    // Capture discovery needs binder roles only when a closure exists. Its
    // enclosing-bracket queries search minimum heaps over the depth scan,
    // keeping long parameter lists and struct literals parallel.
    let roles = gpu.rows("closures.roles", total, 1);
    let n_blocks = total_u32.div_ceil(256);
    let leaf_base = n_blocks.next_power_of_two();
    let depth_local_min = gpu.rows("closures.depth.local_min", n_blocks as usize * 256, 1);
    let depth_min_tree = gpu.rows("closures.depth.min_tree", leaf_base as usize * 2, 1);
    gpu.dispatch(
        &mut encoder,
        &gpu.kernel("closures/depth_blocks")?,
        "closures.depth.blocks",
        &[
            ("token_count", bufs.token_count.as_entire_binding()),
            ("depth_scan", depth_scan.as_entire_binding()),
            ("depth_local_min", depth_local_min.as_entire_binding()),
        ],
        total_u32,
    )?;
    let depth_tree_kernel = gpu.kernel("closures/depth_tree")?;
    for (mode, start_node, levels) in crate::gpu::scan::heap_build_levels(leaf_base) {
        let params = gpu.uniform(
            "closures.depth.tree.params",
            &DepthTreeParams {
                n_blocks,
                leaf_base,
                start_node,
                node_count: start_node,
                mode,
                levels,
                reserved0: 0,
                reserved1: 0,
            },
        );
        gpu.dispatch(
            &mut encoder,
            &depth_tree_kernel,
            "closures.depth.tree",
            &[
                ("gMinTree", params.as_entire_binding()),
                ("depth_local_min", depth_local_min.as_entire_binding()),
                ("depth_min_tree", depth_min_tree.as_entire_binding()),
            ],
            start_node,
        )?;
    }
    let role_params = gpu.uniform("closures.roles.params", &RoleParams { leaf_base });
    gpu.dispatch(
        &mut encoder,
        &gpu.kernel("closures/roles")?,
        "closures.roles",
        &[
            ("gRoles", role_params.as_entire_binding()),
            ("token_count", bufs.token_count.as_entire_binding()),
            ("tokens_out", bufs.tokens_out.as_entire_binding()),
            ("token_file_id", bufs.token_file_id.as_entire_binding()),
            ("depth_scan", depth_scan.as_entire_binding()),
            ("depth_local_min", depth_local_min.as_entire_binding()),
            ("depth_min_tree", depth_min_tree.as_entire_binding()),
            ("roles", roles.as_entire_binding()),
        ],
        total_u32,
    )?;
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
    let layout = gpu.uniform(
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
    let (const_index, const_bytes) = constant_table(gpu);
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
    let emit = gpu.uniform(
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

fn constant_table(gpu: &Gpu<'_>) -> (LaniusBuffer<u32>, LaniusBuffer<u8>) {
    let mut index = Vec::with_capacity(CONSTANTS.len() * 2);
    let mut bytes = Vec::new();
    for text in CONSTANTS {
        index.extend([bytes.len() as u32, text.len() as u32]);
        bytes.extend_from_slice(text.as_bytes());
    }
    bytes.resize(bytes.len().next_multiple_of(4), 0);
    (gpu.words_from("closures.const_index", &index), gpu.bytes_from("closures.const_bytes", &bytes))
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
