//! The program trait catalog produced on the GPU from the build's retention
//! store, admitted and solved by the existing trait solver
//! (docs/compiler-retained-trait-catalog.md).
//!
//! The producer (shaders/type_checker/trait_solver/retained) counts and
//! checks every row on the GPU. The host reads the store's counters, the
//! producer's failure words and its 16 row totals, places the tables from
//! those counts, and dispatches. It builds no catalog or batch row, selects
//! nothing and accepts no result: the solver's catalog admission, coherence
//! and proof kernels consume the GPU-written rows unchanged.
mod closed;
pub use closed::{ClosedChainInputs, ClosedTraitCheck, ClosedTraitPublication};

use std::{collections::BTreeMap, sync::Arc};

use anyhow::{Result, anyhow, ensure};

use super::{
    BatchPlan,
    GpuPacket,
    GpuTraitSolver,
    OutputLayout,
    WaveReadback,
    arena::{self, Arena},
    ensure_retained_inputs_unchanged,
    one_status,
    workspace::WorkspaceLease,
};
use crate::{
    compiler::gpu_compiler::trait_solver::{
        abi::*,
        catalog::FrozenCatalog,
        packet::Submission,
    },
    gpu::{
        buffers::LaniusBuffer,
        passes_core::{self, PassData, make_pass_data_from_shader_key},
        readback::{PagedReadback, ReadbackRegion},
    },
    type_checker::program_retention::{ExportFollower, ProgramRetention, ProgramRetentionCapacity, counts},
};

const KEYS: [&str; 23] = [
    "type_checker/trait_solver/retained/entries/00_mark",
    "type_checker/trait_solver/retained/entries/01_units",
    "type_checker/trait_solver/retained/entries/02_count",
    "type_checker/trait_solver/retained/entries/03_scan_local",
    "type_checker/trait_solver/retained/entries/04_scan_blocks",
    "type_checker/trait_solver/retained/entries/05_scan_apply",
    "type_checker/trait_solver/retained/entries/06_fill_decls",
    "type_checker/trait_solver/retained/entries/06_fill_params",
    "type_checker/trait_solver/retained/entries/06_fill_terms",
    "type_checker/trait_solver/retained/entries/06_fill_dir",
    "type_checker/trait_solver/retained/entries/06_fill_traits",
    "type_checker/trait_solver/retained/entries/06_fill_uses",
    "type_checker/trait_solver/retained/entries/06_fill_jobs",
    "type_checker/trait_solver/retained/entries/02a_sort_init",
    "type_checker/trait_solver/retained/entries/02b_sort_step",
    "type_checker/trait_solver/retained/entries/02c_sort_finish",
    "type_checker/trait_solver/retained/entries/07_publish_routes",
    "type_checker/trait_solver/retained/entries/08_publish_finish",
    "type_checker/trait_solver/retained/entries/09_fill_words",
    "type_checker/trait_solver/retained/entries/02d_closure_roots",
    "type_checker/trait_solver/retained/entries/02e_closure_wave",
    "type_checker/trait_solver/retained/entries/02g_sort_block",
    "type_checker/trait_solver/retained/entries/00_configure",
];
const SORT_BLOCK: usize = 21;
const CONFIGURE: usize = 22;
/// Keys one workgroup sorts in shared memory (producer.slang RC_SORT_BLOCK).
const SORT_BLOCK_KEYS: u32 = 512;
const FILL_WORDS: usize = 18;
const CLOSURE_ROOTS: usize = 19;
const CLOSURE_WAVE: usize = 20;
/// First bound on closure waves, which one workgroup runs until a wave is
/// empty; doubled while the GPU reports an unexpanded frontier.
const CLOSURE_WAVES: u32 = 1 << 16;
const SORT_INIT: usize = 13;
const SORT_STEP: usize = 14;
const SORT_FINISH: usize = 15;
const PUBLISH_ROUTES: usize = 16;
const PUBLISH_FINISH: usize = 17;
const QUERY_KEY: &str = "tests/retained_route_query";
/// Byte stride of one bitonic step's (k, j) in the stage buffer: the
/// storage offset alignment of every supported device.
const STAGE_STRIDE: u64 = 256;
const MARK: usize = 0;
const UNITS: usize = 1;
const COUNT: usize = 2;
const SCAN_LOCAL: usize = 3;
const SCAN_BLOCKS: usize = 4;
const SCAN_APPLY: usize = 5;
/// Fill kernel of each lane region (producer.slang RC_R_*).
const FILL: [usize; REGIONS] = [6, 7, 8, 9, 10, 11, 12];
/// Regions whose fill writes batch rows (directory contexts, uses).
const BATCH_FILL_REGIONS: [usize; 2] = [3, 5];

// producer.slang rc_config words.
const CFG_EPOCH: usize = 16;
const CFG_GENERATION: usize = 18;
const CFG_PHASE: usize = 19;
const CFG_TABLE: usize = 20;
const CFG_SORT: usize = 37;
const CFG_ATOM_IDS: usize = 38;
const CFG_ROUTE_USES: usize = 39;
const CFG_CLOSURE_WAVES: usize = 40;
const CFG_REGION_CAP: usize = 41;
const CFG_UNIT_CAP: usize = 48;
const CFG_SORT_CAP: usize = 49;
const CFG_UNIT_REQUEST: usize = 50;
const CFG_STEPS: usize = 51;
const CFG_WORDS: usize = 52;
/// rc_dispatch entries (config_words.slang RC_D_*).
const D_LANES: u64 = 0;
const D_ROOTS: u64 = 1;
const D_SORT: u64 = 2;
const D_STEP: u64 = 3;
const REGIONS: usize = 7;
const COUNTERS: usize = 16;

// producer.slang rc_state words.
const S_FAILURES: usize = 0;
const S_FIRST: usize = 1;
const S_UNSUPPORTED_MEMBER_BOUNDS: usize = 2;
const S_FILL_FAULTS: usize = 3;
const S_UNIT_SLOTS_FULL: usize = 4;
const S_UNSUPPORTED_CALLEES: usize = 5;
const S_PLAIN_CALLS: usize = 6;
const S_TOTALS: usize = 8;
const S_CLOSURE_SHORT: usize = 24;
const S_CLOSURE_TERMS: usize = 25;
const S_CLOSURE_WAVES: usize = 26;
const S_CONFIG_FAULT: usize = 27;
const S_WORDS: usize = 28;

/// Solver table of each producer counter (producer.slang RC_C_*).
const COUNTER_TABLE: [usize; COUNTERS] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 14, 15, 11, 12, 16];

// Arena indexes of the retention store (retention_store.slang RT_A_*).
const A_DECLS: usize = 0;
const A_PARAMS: usize = 1;
const A_TERMS: usize = 2;
const A_DIR: usize = 4;
const A_USES: usize = 8;
const A_TRAITS: usize = 14;
const A_JOBS: usize = 15;
const RT_FIRST_TERM: u32 = 32;

// route_abi.slang header words.
const RP_MAGIC: u32 = 0x5254_5231;
const RP_HEADER_WORDS: u32 = 64;
const RP_H_STATUS: usize = 8;
/// The verdict words publish_finish requires (route_abi.slang): the
/// solver's stop word, the producer's fill faults and the native recipe
/// status, copied on the GPU.
const RP_H_SOLVE_STOP: u64 = 45;
pub(super) const RP_H_FILL_FAULTS: u64 = 46;
pub(super) const RP_H_RECIPE_STATUS: u64 = 47;
const RP_H_FIRST_FAILURE: usize = 10;
const RP_USE_WORDS: u32 = 4;
const RP_ROUTE_WORDS: u32 = 8;

/// Words written over every arena region the producer must fill when
/// `RetainedTraitOptions::poison_arenas` is set.
pub const RETAINED_POISON: u32 = 0xa5a5_a5a5;

/// Test and measurement controls of one retained trait check.
#[derive(Clone, Debug, Default)]
pub struct RetainedTraitOptions {
    /// First size of the producer's (library, unit) table; it doubles when
    /// the GPU reports it full. None sizes it from the job count.
    pub unit_slots: Option<u32>,
    /// Fill the catalog and batch arenas with `RETAINED_POISON` before the
    /// producer writes them, so an unwritten word cannot read as a row.
    pub poison_arenas: bool,
    /// Read every produced row back into `RetainedTraitCheck::tables` (for
    /// assertions only; the check itself reads none).
    pub read_rows: bool,
    /// First bound on term closure waves (default 65536). A smaller value
    /// forces the retry that raises it.
    pub closure_waves: Option<u32>,
    /// Run the solve without reading its state back. The publication's
    /// status then also says whether the solve finished in its first
    /// submit and the catalog's fill and admission held (header words 45
    /// to 47), and a consumer that finds it not valid checks again without
    /// this option for the exact report.
    pub defer_solve: bool,
    /// Fault injection for tests: a deferred solve publishes as if it had
    /// not finished in its first submit (header word 45 is not DONE).
    #[doc(hidden)]
    pub test_unfinished_solve: bool,
}

/// Where a retained trait check stopped.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RetainedTraitStage {
    /// The producer rejected the store (see `producer_failures`).
    Producer,
    /// The producer wrote a row it could not translate.
    Fill,
    /// The solver's catalog admission or coherence rejected the catalog.
    Admission,
    /// The solver ran the batch; read the result statuses.
    Solved,
}

/// The compact result of one retained trait check.
#[derive(Clone, Debug)]
pub struct RetainedTraitCheck {
    pub stage: RetainedTraitStage,
    /// Store build generation the check ran against.
    pub generation: u32,
    /// Producer runs: more than one when its unit table grew.
    pub attempts: u32,
    pub producer_failures: u32,
    /// First failure as (code, lane), producer.slang RC_E_*.
    pub first_failure: Option<(u32, u32)>,
    /// When the store is not ready: the export's first fault (reason, job,
    /// file, byte, length), from the store counters the count pass copies.
    pub store_fault: Option<[u32; 5]>,
    /// Required-member own bounds the solver cannot admit (no row).
    pub unsupported_member_bounds: u32,
    pub fill_faults: u32,
    /// Rows the producer wrote in each solver table.
    pub rows: [u32; TABLE_COUNT],
    pub catalog_status: Option<[u32; 8]>,
    pub recipe_status: Option<[u32; 8]>,
    pub batch_status: Option<[u32; 8]>,
    pub contexts: Vec<[u32; 8]>,
    pub calls: Vec<[u32; 8]>,
    pub obligations: Vec<[u32; 8]>,
    pub evidence: Vec<[u32; 8]>,
    /// Raw rows of each solver table when `read_rows` was set.
    pub tables: Vec<Vec<u32>>,
    /// Compute dispatches recorded by this check (producer and solver).
    pub dispatches: u64,
    /// Host readback round trips of the check (process-wide counter, so
    /// exact only when nothing else reads back meanwhile) and their wait.
    pub readbacks: u64,
    pub readback_wait_ns: u64,
    /// Bytes of the producer's own readbacks (store counters, producer
    /// state, admission receipts); the solver's wave readbacks are extra.
    pub producer_readback_bytes: u64,
    /// Width of the producer's binding sort (a power of two at least the
    /// trait record count) and the bitonic steps it dispatched.
    pub sort_width: u32,
    pub sort_steps: u32,
    /// Publication header words 8-10 (status, failures, first failure),
    /// read by `check` for the report; `publish` does not read them.
    pub publication_status: Option<[u32; 3]>,
    /// Direct and method uses that are not goals: the callee is not a
    /// committed store callable, or it has no applicable predicate.
    pub unsupported_callees: u32,
    pub plain_calls: u32,
    /// Stored terms in the catalog's term closure, closure waves dispatched
    /// in the last attempt, and the waves of those that had work.
    pub closure_terms: u32,
    pub closure_waves: u32,
    pub closure_active_waves: u32,
}

impl RetainedTraitCheck {
    /// The implementation row (table 9) the solver selected for obligation
    /// `index`, from its result row.
    pub fn selected_implementation(&self, index: usize) -> Option<u32> {
        self.obligations.get(index).and_then(|row| row[7].checked_sub(1))
    }
    /// Words of row `row` of solver table `table` (needs `read_rows`).
    pub fn row(&self, table: usize, row: u32) -> Option<&[u32]> {
        let width = WIDTHS[table] as usize;
        let first = row as usize * width;
        self.tables.get(table)?.get(first..first + width)
    }
}

struct Scratch {
    config: LaniusBuffer<u32>,
    /// Indirect dispatches of the count passes (00_configure).
    dispatch: LaniusBuffer<u32>,
    state: LaniusBuffer<u32>,
    flags: LaniusBuffer<u32>,
    scan: LaniusBuffer<u32>,
    blocks: LaniusBuffer<u32>,
    entry: LaniusBuffer<u32>,
    snapshot: LaniusBuffer<u32>,
    unit_slot: LaniusBuffer<u32>,
    sort: LaniusBuffer<u32>,
    bind_pos: LaniusBuffer<u32>,
    impl_first: LaniusBuffer<u32>,
    stages: LaniusBuffer<u32>,
    reach: LaniusBuffer<u32>,
    front: LaniusBuffer<u32>,
    cursor: LaniusBuffer<u32>,
    /// Bound as the arena of the other phase; never written.
    idle: LaniusBuffer<u32>,
}

/// Buffers a producer or publish pass binds besides the scratch.
#[derive(Clone, Copy)]
struct Bound<'a> {
    catalog: &'a LaniusBuffer<u32>,
    batch: &'a LaniusBuffer<u32>,
    routes: &'a LaniusBuffer<u32>,
    output: &'a LaniusBuffer<u32>,
    proof: &'a LaniusBuffer<u32>,
    /// rc_stage: one 16-byte record of `stages` at `stage` (a bitonic step
    /// of SORT_STEP, a range of FILL_WORDS).
    stages: &'a LaniusBuffer<u32>,
    stage: u32,
}

struct Producer {
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    passes: Vec<PassData>,
    readback: PagedReadback,
    readback_bytes: u64,
}

/// `words` rounded up to a power of two when that is representable.
fn pow2(words: u32) -> u32 {
    words.checked_next_power_of_two().unwrap_or(words)
}

fn groups(lanes: u32) -> (u32, u32) {
    let groups = lanes.div_ceil(256).max(1);
    (groups.min(65_535), groups.div_ceil(65_535))
}

fn reflected_names(pass: &PassData) -> Vec<String> {
    let layout = pass
        .reflection
        .entry_points
        .iter()
        .find(|entry| entry.stage.as_deref() == Some("compute"))
        .and_then(|entry| entry.program_layout.as_ref());
    let parameters = match layout {
        Some(layout) => layout.parameters.first().map(|set| set.parameters.as_slice()).unwrap_or_default(),
        None => pass.reflection.parameters.as_slice(),
    };
    parameters
        .iter()
        .filter(|p| p.binding.index.is_some() && p.ty.kind.is_some())
        .map(|p| p.name.clone())
        .collect()
}

impl Producer {
    /// Writes `value` over each (first word, words, value) range of
    /// `target` on the GPU, in order.
    fn fill_words(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        workspace: &WorkspaceLease,
        scratch: &Scratch,
        store: &BTreeMap<&'static str, wgpu::Buffer>,
        target: &LaniusBuffer<u32>,
        ranges: &[(u32, u32, u32)],
    ) -> Result<()> {
        if ranges.is_empty() {
            return Ok(());
        }
        let stride = (STAGE_STRIDE / 4) as usize;
        let mut words = vec![0u32; ranges.len() * stride];
        for (i, range) in ranges.iter().enumerate() {
            words[i * stride..i * stride + 3].copy_from_slice(&[range.0, range.1, range.2]);
        }
        let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST;
        let stages = workspace.initialized("trait_solver.retained_fill_ranges", u32::try_from(words.len())?, usage, Some(&words))?;
        for (i, range) in ranges.iter().enumerate() {
            let bound = Bound {
                catalog: target,
                batch: &scratch.idle,
                routes: &scratch.idle,
                output: &scratch.idle,
                proof: &scratch.idle,
                stages: &stages,
                stage: u32::try_from(i)?,
            };
            self.record(encoder, FILL_WORDS, range.1, scratch, store, bound)?;
        }
        Ok(())
    }

    fn read(&mut self, buffer: &LaniusBuffer<u32>, words: usize, label: crate::gpu::passes_core::ReadbackLabel) -> Result<Vec<u32>> {
        let region = ReadbackRegion::from_buffer(buffer, 0, arena::byte_len(u32::try_from(words)?)?, label.as_str())?;
        let raw = self.readback.read_regions(&self.device, &self.queue, &[region], label)?;
        self.readback_bytes += raw[0].len() as u64;
        super::words(&raw[0])
    }

    fn record(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        pass: usize,
        lanes: u32,
        scratch: &Scratch,
        store: &BTreeMap<&'static str, wgpu::Buffer>,
        bound: Bound<'_>,
    ) -> Result<()> {
        let bind = self.bind_group(pass, scratch, store, bound)?;
        self.dispatch(encoder, pass, lanes, &bind);
        Ok(())
    }

    fn bind_group(
        &self,
        pass: usize,
        scratch: &Scratch,
        store: &BTreeMap<&'static str, wgpu::Buffer>,
        bound: Bound<'_>,
    ) -> Result<wgpu::BindGroup> {
        let data = &self.passes[pass];
        let names = reflected_names(data);
        let mut entries = Vec::with_capacity(names.len());
        for name in &names {
            let resource = match name.as_str() {
                "rc_config" => scratch.config.as_entire_binding(),
                "rc_state" => scratch.state.as_entire_binding(),
                "rc_flags" => scratch.flags.as_entire_binding(),
                "rc_scan" => scratch.scan.as_entire_binding(),
                "rc_blocks" => scratch.blocks.as_entire_binding(),
                "rc_entry" => scratch.entry.as_entire_binding(),
                "rc_snapshot" => scratch.snapshot.as_entire_binding(),
                "rc_unit_slot" => scratch.unit_slot.as_entire_binding(),
                "rc_sort" => scratch.sort.as_entire_binding(),
                "rc_bind_pos" => scratch.bind_pos.as_entire_binding(),
                "rc_impl_first" => scratch.impl_first.as_entire_binding(),
                "rc_reach" => scratch.reach.as_entire_binding(),
                "rc_front" => scratch.front.as_entire_binding(),
                "rc_cursor" => scratch.cursor.as_entire_binding(),
                "rc_dispatch" => scratch.dispatch.as_entire_binding(),
                "rc_stages" => scratch.stages.as_entire_binding(),
                "rc_stage" => wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                    buffer: &bound.stages.buffer,
                    offset: bound.stages.byte_offset + u64::from(bound.stage) * STAGE_STRIDE,
                    size: std::num::NonZeroU64::new(16),
                }),
                "rc_catalog" => bound.catalog.as_entire_binding(),
                "rc_batch" => bound.batch.as_entire_binding(),
                "rc_routes" => bound.routes.as_entire_binding(),
                "rp_catalog" => bound.catalog.as_entire_binding(),
                "rp_output" => bound.output.as_entire_binding(),
                "rp_proof" => bound.proof.as_entire_binding(),
                other => store
                    .get(other)
                    .ok_or_else(|| anyhow!("retained trait producer binds unknown buffer {other}"))?
                    .as_entire_binding(),
            };
            entries.push((name.as_str(), resource));
        }
        passes_core::bind_group::create_bind_group_from_bindings(
            &self.device,
            Some(&data.shader_id),
            data,
            0,
            &entries,
        )
    }

    /// Records `pass` with a bind group from `bind_group` for the same pass.
    fn dispatch(&self, encoder: &mut wgpu::CommandEncoder, pass: usize, lanes: u32, bind: &wgpu::BindGroup) {
        let data = &self.passes[pass];
        let (x, y) = if matches!(pass, SCAN_BLOCKS | PUBLISH_FINISH | CLOSURE_WAVE) { (1, 1) } else { groups(lanes) };
        // Inside a batch the dispatches of a submit share one compute pass;
        // the kernel key labels each dispatch's timestamp.
        passes_core::record_or_defer_compute_direct(encoder, data, bind, KEYS[pass], (x, y, 1));
    }
}

/// The lane regions of the current store: (first lane, lanes) per region.
fn regions(status: &[u32]) -> Result<[(u32, u32); REGIONS]> {
    let sizes = [
        status[A_DECLS].saturating_sub(1),
        status[A_PARAMS].saturating_sub(1),
        status[A_TERMS].saturating_sub(RT_FIRST_TERM),
        status[A_DIR],
        status[A_TRAITS],
        status[A_USES],
        status[counts::JOBS],
    ];
    let mut first = 0u32;
    let mut regions = [(0, 0); REGIONS];
    for (region, size) in sizes.into_iter().enumerate() {
        regions[region] = (first, size);
        first = add(first, size, "retained producer lanes")?;
    }
    // Failure words carry a 24-bit lane.
    ensure!(first < 1 << 24, "retained producer lanes exceed 2^24");
    Ok(regions)
}

/// Runs the producer, the solver's catalog admission and coherence, and
/// the solver over the bound goals of the store's current build, then
/// reads the publication status for the report and drops the publication.
pub(in crate::compiler::gpu_compiler) fn check(
    workspace: WorkspaceLease,
    store: &ProgramRetention,
    options: &RetainedTraitOptions,
) -> Result<RetainedTraitCheck> {
    let (mut report, publication) = publish(|| workspace, store, options)?;
    if let Some(publication) = &publication {
        report.publication_status = Some(publication.status()?);
    }
    Ok(report)
}

/// `check`, keeping the solved catalog, packet and proof store alive as a
/// GPU publication when the solver ran.
///
/// When the count passes ran behind the build's last export
/// ([`record_count_follower`]), the run continues from their state and
/// workspace and `workspace` is not called.
pub(in crate::compiler::gpu_compiler) fn publish(
    workspace: impl FnOnce() -> WorkspaceLease,
    store: &ProgramRetention,
    options: &RetainedTraitOptions,
) -> Result<(RetainedTraitCheck, Option<RetainedTraitPublication>)> {
    let dispatches_before = passes_core::recorded_compute_dispatch_count();
    let readbacks_before = passes_core::readback_round_trips();
    let committed = store.job_reports().len();
    let (capacity, _) = store.capacity();
    let followed = store.take_followed_words().and_then(|followed| {
        let count = followed.state.downcast::<CountPass>().ok()?;
        let state = followed.words.into_iter().next()?;
        (options.unit_slots.is_none() && options.closure_waves.is_none()).then_some((*count, state))
    });
    let workspace = match &followed {
        Some((count, _)) => count.workspace.clone(),
        None => workspace(),
    };
    let device = workspace.device().clone();
    let (mut report, mut publication) = gpu_errors_as_result(&device, "retained trait catalog", || {
        store.with_store_buffers(|buffers, generation| run(workspace, buffers, generation, &capacity, options, followed))
    })?;
    if let Some(publication) = &mut publication {
        publication.store_jobs = committed;
    }
    let readbacks = passes_core::readback_round_trips();
    report.dispatches = passes_core::recorded_compute_dispatch_count() - dispatches_before;
    report.readbacks = readbacks.0 - readbacks_before.0;
    report.readback_wait_ns = readbacks.1 - readbacks_before.1;
    Ok((report, publication))
}

/// Records the producer's count passes for the export the store is about to
/// commit, sized from the store's capacities: the native call rewrite
/// submits them behind itself, the producer state comes back in the job's
/// object readback, and [`publish`] continues from that state (default
/// options).
pub(in crate::compiler::gpu_compiler) fn record_count_follower(
    workspace: &WorkspaceLease,
    store: &ProgramRetention,
) -> Result<Option<ExportFollower>> {
    let (capacity, _) = store.capacity();
    let generation = store.generation();
    // Without a follower, `publish` runs the count passes itself and reports
    // an allocation failure there.
    let Ok(count) = gpu_errors_as_result(workspace.device(), "retained count passes", || {
        CountPass::new(workspace.clone(), generation, &capacity, CLOSURE_WAVES, 0)
    }) else {
        return Ok(None);
    };
    let mut encoder = workspace.device().create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("trait_solver.retained_count"),
    });
    let batch = passes_core::DeferredComputeBatchGuard::begin(
        passes_core::compute_pass_batching_allowed(false),
        "trait_solver.retained_count",
    );
    store.with_store_buffers(|buffers, _| count.record(&mut encoder, buffers))?;
    passes_core::flush_deferred_compute(&mut encoder);
    drop(batch);
    ensure!(count.scratch.state.byte_offset == 0, "retained producer state is not at the start of its buffer");
    let reads = vec![(count.scratch.state.buffer.clone(), COUNT_READ_WORDS)];
    Ok(Some(ExportFollower { commands: encoder.finish(), reads, state: Box::new(count) }))
}

/// `f`'s result, or the first out-of-memory or validation error this
/// thread's wgpu calls raised inside it (wgpu error scopes are per thread).
/// Without the scope such an error only reaches the uncaptured-error
/// handler: a buffer that failed to allocate makes its submit invalid, the
/// producer state then reads as zeros, and the run would report a catalog
/// with no jobs instead of an error.
fn gpu_errors_as_result<T>(device: &wgpu::Device, what: &str, f: impl FnOnce() -> Result<T>) -> Result<T> {
    let out_of_memory = device.push_error_scope(wgpu::ErrorFilter::OutOfMemory);
    let validation = device.push_error_scope(wgpu::ErrorFilter::Validation);
    let result = f();
    let validation = pollster::block_on(validation.pop());
    let out_of_memory = pollster::block_on(out_of_memory.pop());
    match out_of_memory.or(validation) {
        Some(err) => Err(anyhow!("{what}: GPU error: {err}")),
        None => result,
    }
}

/// The recorded steps of a bitonic sort over `width` keys: (k, j) is one
/// global compare-exchange step (j >= 256), (k, 0) a shared-memory block
/// pass over the steps j < 256 of stage k, and (0, 0) the block pass that
/// sorts each block completely.
fn bitonic_steps(width: u32) -> Vec<(u32, u32)> {
    let mut steps = vec![(0, 0)];
    let mut k = SORT_BLOCK_KEYS * 2;
    while k <= width {
        let mut j = k / 2;
        while j >= SORT_BLOCK_KEYS {
            steps.push((k, j));
            j /= 2;
        }
        steps.push((k, 0));
        k *= 2;
    }
    steps
}

/// The count passes of one run, recorded before the store's counters are
/// read: buffers are sized from the store's capacities, `00_configure`
/// writes the configuration that depends on the counters and the indirect
/// dispatches of the other passes, and the producer state carries the
/// counters (from word `S_WORDS`).
struct CountPass {
    workspace: WorkspaceLease,
    producer: Producer,
    scratch: Scratch,
    /// Host words of rc_config; 00_configure writes the others.
    config: Vec<u32>,
    /// The bitonic steps recorded for the sort capacity.
    steps: Vec<(u32, u32)>,
    closure_waves: u32,
    unit_request: u32,
}

/// Words of the count pass's state readback: the producer state, then the
/// store's counters.
const COUNT_READ_WORDS: usize = S_WORDS + counts::WORDS;

impl CountPass {
    /// Allocates the count pass for a store of `capacity` (records per
    /// arena). `unit_request` is the unit slots to use (0: twice the jobs).
    fn new(
        workspace: WorkspaceLease,
        generation: u32,
        capacity: &ProgramRetentionCapacity,
        closure_waves: u32,
        unit_request: u32,
    ) -> Result<Self> {
        let device = workspace.device().clone();
        let passes = KEYS
            .iter()
            .map(|&key| make_pass_data_from_shader_key(&device, key, "main", key))
            .collect::<Result<Vec<_>>>()?;
        let producer = Producer {
            readback: PagedReadback::from_staging(workspace.readback_staging("trait_solver.retained_readback", 4096)),
            device: device.clone(),
            queue: workspace.queue().clone(),
            passes,
            readback_bytes: 0,
        };
        let arenas = &capacity.arenas;
        let caps = [
            arenas[A_DECLS].saturating_sub(1),
            arenas[A_PARAMS].saturating_sub(1),
            arenas[A_TERMS].saturating_sub(RT_FIRST_TERM),
            arenas[A_DIR],
            arenas[A_TRAITS],
            arenas[A_USES],
            arenas[A_JOBS],
        ];
        let lanes = caps.iter().fold(0u32, |sum, &cap| sum.saturating_add(cap));
        let dir_entries = caps[3];
        let traits = caps[4];
        let jobs = caps[6];
        let unit_cap = if unit_request != 0 {
            unit_request
        } else {
            jobs.saturating_mul(2).max(1).checked_next_power_of_two().ok_or_else(|| anyhow!("retained unit table overflow"))?
        };
        let sort_cap = traits.max(1).checked_next_power_of_two().ok_or_else(|| anyhow!("retained binding sort overflow"))?;
        let steps = bitonic_steps(sort_cap);
        let stride_words = (STAGE_STRIDE / 4) as usize;
        let mut stage_words = vec![0u32; steps.len().max(1) * stride_words];
        for (i, &(k, j)) in steps.iter().enumerate() {
            stage_words[i * stride_words] = k;
            stage_words[i * stride_words + 1] = j;
        }
        let mut config = vec![0u32; CFG_WORDS];
        config[CFG_GENERATION] = generation;
        config[CFG_CLOSURE_WAVES] = closure_waves;
        config[CFG_REGION_CAP..CFG_REGION_CAP + REGIONS].copy_from_slice(&caps);
        config[CFG_UNIT_CAP] = unit_cap;
        config[CFG_SORT_CAP] = sort_cap;
        config[CFG_UNIT_REQUEST] = unit_request;
        config[CFG_STEPS] = u32::try_from(steps.len())?;
        let mut initial_state = vec![0u32; COUNT_READ_WORDS];
        initial_state[S_FIRST] = u32::MAX;
        let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST;
        let blocks = lanes.div_ceil(256).max(1);
        let terms = arenas[A_TERMS].max(1);
        let scratch = Scratch {
            config: workspace.initialized("trait_solver.retained_config", CFG_WORDS as u32, usage, Some(&config))?,
            dispatch: workspace.initialized(
                "trait_solver.retained_dispatch",
                u32::try_from((D_STEP as usize + steps.len()) * 3)?,
                usage | wgpu::BufferUsages::INDIRECT,
                None,
            )?,
            state: workspace.initialized("trait_solver.retained_state", COUNT_READ_WORDS as u32, usage, Some(&initial_state))?,
            // Term-sized buffers grow by powers of two: the term count grows
            // between builds, and a kept buffer keeps its bind groups.
            flags: workspace.initialized("trait_solver.retained_flags", pow2(lanes.max(1).saturating_mul(16)), usage, None)?,
            scan: workspace.initialized("trait_solver.retained_scan", pow2(lanes.max(1).saturating_mul(16)), usage, None)?,
            blocks: workspace.initialized("trait_solver.retained_blocks", pow2(blocks * 16), usage, None)?,
            entry: workspace.initialized("trait_solver.retained_entry", dir_entries.max(1) * 2, usage, None)?,
            snapshot: workspace.initialized(
                "trait_solver.retained_snapshot",
                jobs.max(1) * 2,
                usage,
                Some(&vec![u32::MAX; jobs.max(1) as usize * 2]),
            )?,
            unit_slot: workspace.initialized("trait_solver.retained_unit_slot", unit_cap, usage, None)?,
            sort: workspace.initialized("trait_solver.retained_sort", sort_cap * 4, usage, None)?,
            bind_pos: workspace.initialized("trait_solver.retained_bind_pos", traits.max(1), usage, None)?,
            impl_first: workspace.initialized("trait_solver.retained_impl_first", dir_entries.max(1), usage, None)?,
            stages: workspace.initialized(
                "trait_solver.retained_stages",
                u32::try_from(stage_words.len())?,
                usage,
                Some(&stage_words),
            )?,
            reach: workspace.initialized("trait_solver.retained_reach", pow2(terms), usage, None)?,
            front: workspace.initialized("trait_solver.retained_front", pow2(terms), usage, None)?,
            cursor: workspace.initialized("trait_solver.retained_cursor", 4, usage, None)?,
            idle: workspace.initialized("trait_solver.retained_idle", 4, usage, None)?,
        };
        Ok(Self { workspace, producer, scratch, config, steps, closure_waves, unit_request })
    }

    /// Records the count passes into `encoder`: 00_configure, mark, units,
    /// the term closure, the binding sort, count and scan, in one compute
    /// pass when the caller has no batch open.
    fn record(&self, encoder: &mut wgpu::CommandEncoder, store: &BTreeMap<&'static str, wgpu::Buffer>) -> Result<()> {
        let (producer, scratch) = (&self.producer, &self.scratch);
        scratch.entry.clear(encoder, 0, None);
        scratch.unit_slot.clear(encoder, 0, None);
        scratch.impl_first.clear(encoder, 0, None);
        scratch.reach.clear(encoder, 0, None);
        scratch.cursor.clear(encoder, 0, None);
        let idle = Bound {
            catalog: &scratch.idle,
            batch: &scratch.idle,
            routes: &scratch.idle,
            output: &scratch.idle,
            proof: &scratch.idle,
            stage: 0,
            stages: &scratch.stages,
        };
        let indirect = |encoder: &mut wgpu::CommandEncoder, pass: usize, entry: u64, bound: Bound<'_>| -> Result<()> {
            let bind = producer.bind_group(pass, scratch, store, bound)?;
            passes_core::record_or_defer_compute_indirect_offset(
                encoder, &producer.passes[pass], &bind, KEYS[pass], &scratch.dispatch, entry * 12,
            );
            Ok(())
        };
        producer.record(encoder, CONFIGURE, 1, scratch, store, idle)?;
        for pass in [MARK, UNITS] {
            indirect(encoder, pass, D_LANES, idle)?;
        }
        // Term closure: roots, then every frontier wave in one workgroup.
        indirect(encoder, CLOSURE_ROOTS, D_ROOTS, idle)?;
        producer.record(encoder, CLOSURE_WAVE, 1, scratch, store, idle)?;
        // The binding sort: steps beyond the store's sort width dispatch
        // no workgroups.
        indirect(encoder, SORT_INIT, D_SORT, idle)?;
        for (stage, &(_, j)) in self.steps.iter().enumerate() {
            let pass = if j == 0 { SORT_BLOCK } else { SORT_STEP };
            indirect(encoder, pass, D_STEP + stage as u64, Bound { stage: u32::try_from(stage)?, ..idle })?;
        }
        indirect(encoder, SORT_FINISH, D_SORT, idle)?;
        for pass in [COUNT, SCAN_LOCAL] {
            indirect(encoder, pass, D_LANES, idle)?;
        }
        producer.record(encoder, SCAN_BLOCKS, 1, scratch, store, idle)?;
        indirect(encoder, SCAN_APPLY, D_LANES, idle)
    }

    /// Records and submits the count passes and reads the state with the
    /// store's counters.
    fn run(&mut self, store: &BTreeMap<&'static str, wgpu::Buffer>) -> Result<Vec<u32>> {
        let mut encoder = self.producer.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("trait_solver.retained_count"),
        });
        // One compute pass for the count passes, flushed before the submit.
        let batch = passes_core::DeferredComputeBatchGuard::begin(
            passes_core::compute_pass_batching_allowed(false),
            "trait_solver.retained_count",
        );
        self.record(&mut encoder, store)?;
        passes_core::flush_deferred_compute(&mut encoder);
        drop(batch);
        self.producer.queue.submit(Some(encoder.finish()));
        let state = self.scratch.state.clone();
        self.producer.read(&state, COUNT_READ_WORDS, crate::readback_label!("retained producer state"))
    }
}

fn run(
    workspace: WorkspaceLease,
    store: &BTreeMap<&'static str, wgpu::Buffer>,
    generation: u32,
    capacity: &ProgramRetentionCapacity,
    options: &RetainedTraitOptions,
    followed: Option<(CountPass, Vec<u32>)>,
) -> Result<(RetainedTraitCheck, Option<RetainedTraitPublication>)> {
    let mut report = RetainedTraitCheck {
        stage: RetainedTraitStage::Producer,
        generation,
        attempts: 0,
        producer_failures: 0,
        first_failure: None,
        store_fault: None,
        unsupported_member_bounds: 0,
        fill_faults: 0,
        rows: [0; TABLE_COUNT],
        catalog_status: None,
        recipe_status: None,
        batch_status: None,
        contexts: Vec::new(),
        calls: Vec::new(),
        obligations: Vec::new(),
        evidence: Vec::new(),
        tables: Vec::new(),
        dispatches: 0,
        readbacks: 0,
        readback_wait_ns: 0,
        producer_readback_bytes: 0,
        sort_width: 0,
        sort_steps: 0,
        publication_status: None,
        unsupported_callees: 0,
        plain_calls: 0,
        closure_terms: 0,
        closure_waves: 0,
        closure_active_waves: 0,
    };
    let unit_request = match options.unit_slots {
        Some(slots) => slots.max(1).checked_next_power_of_two().ok_or_else(|| anyhow!("retained unit table overflow"))?,
        None => 0,
    };
    let closure_waves = options.closure_waves.unwrap_or(CLOSURE_WAVES).max(1);
    // Count: configure, mark, units, the closure, the binding sort, count,
    // scan. A count pass recorded behind the last export arrives with its
    // state; otherwise it runs now. Grown when the unit table is full or the
    // closure needs more waves.
    let (mut count, mut state, mut followed_fault) = match followed {
        Some((count, state)) => (count, state, true),
        None => {
            let mut count = CountPass::new(workspace.clone(), generation, capacity, closure_waves, unit_request)?;
            let state = count.run(store)?;
            (count, state, false)
        }
    };
    let (status, regions) = loop {
        report.attempts += 1;
        ensure!(state.len() >= COUNT_READ_WORDS, "retained producer state is short");
        if state[S_CONFIG_FAULT] != 0 {
            // The counters did not fit the capacities the pass was sized
            // with (a pass recorded behind an export, before a growth).
            ensure!(followed_fault, "retained producer lanes exceed 2^24 or the store's capacity");
            followed_fault = false;
            count = CountPass::new(workspace.clone(), generation, capacity, count.closure_waves, count.unit_request)?;
            state = count.run(store)?;
            continue;
        }
        followed_fault = false;
        let status = state[S_WORDS..COUNT_READ_WORDS].to_vec();
        let regions = regions(&status)?;
        if state[S_UNIT_SLOTS_FULL] != 0 || state[S_CLOSURE_SHORT] != 0 {
            let jobs = regions[6].1;
            let mut unit_request = if count.unit_request != 0 {
                count.unit_request
            } else {
                jobs.saturating_mul(2).max(1).checked_next_power_of_two().ok_or_else(|| anyhow!("retained unit table overflow"))?
            };
            let mut closure_waves = count.closure_waves;
            if state[S_UNIT_SLOTS_FULL] != 0 {
                unit_request = unit_request.checked_mul(2).ok_or_else(|| anyhow!("retained unit table overflow"))?;
            }
            if state[S_CLOSURE_SHORT] != 0 {
                closure_waves = closure_waves.checked_mul(2).filter(|&w| w <= 1 << 16)
                    .ok_or_else(|| anyhow!("retained term closure needs more than 65536 waves"))?;
            }
            count = CountPass::new(workspace.clone(), generation, capacity, closure_waves, unit_request)?;
            state = count.run(store)?;
            continue;
        }
        break (status, regions);
    };
    let CountPass { workspace, mut producer, scratch, mut config, closure_waves, .. } = count;
    let device = workspace.device().clone();
    let queue = workspace.queue().clone();
    let rt_counts = store.get("rt_counts").ok_or_else(|| anyhow!("retention store has no rt_counts"))?;
    let lanes = regions[REGIONS - 1].0 + regions[REGIONS - 1].1;
    let jobs = regions[6].1;
    let dir_entries = regions[3].1;
    let traits = regions[4].1;
    let uses = regions[5].1;
    let _ = lanes;
    let sort_width = traits.max(1).checked_next_power_of_two().ok_or_else(|| anyhow!("retained binding sort overflow"))?;
    report.sort_width = sort_width;
    report.sort_steps = u32::try_from(bitonic_steps(sort_width).len())?;
    report.producer_failures = state[S_FAILURES];
    report.unsupported_member_bounds = state[S_UNSUPPORTED_MEMBER_BOUNDS];
    report.unsupported_callees = state[S_UNSUPPORTED_CALLEES];
    report.plain_calls = state[S_PLAIN_CALLS];
    report.closure_terms = state[S_CLOSURE_TERMS];
    report.closure_waves = closure_waves;
    report.closure_active_waves = state[S_CLOSURE_WAVES];
    if state[S_FIRST] != u32::MAX {
        report.first_failure = Some((state[S_FIRST] >> 24, state[S_FIRST] & 0xff_ffff));
    }
    if status[counts::READY] == 0 && status[counts::FAULT] != 0 {
        report.store_fault = Some([
            status[counts::FAULT], status[counts::FAULT_JOB], status[counts::FAULT_FILE],
            status[counts::FAULT_BYTE], status[counts::FAULT_LEN],
        ]);
    }
    for counter in 0..COUNTERS {
        report.rows[COUNTER_TABLE[counter]] = state[S_TOTALS + counter];
    }
    report.rows[0] = jobs;
    if report.producer_failures != 0 || jobs == 0 {
        report.producer_readback_bytes = producer.readback_bytes;
        return Ok((report, None));
    }

    // The route arena (route_abi.slang): header, use map, routes, atom ids.
    let obligations = report.rows[16];
    let atoms = report.rows[1];
    let use_map = RP_HEADER_WORDS;
    let route_rows = add(use_map, mul(uses, RP_USE_WORDS, "retained use map")?, "retained routes")?;
    let atom_ids = add(route_rows, mul(obligations, RP_ROUTE_WORDS, "retained routes")?, "retained atom ids")?;
    let route_words = add(atom_ids, mul(atoms, 2, "retained atom ids")?, "retained route arena")?;
    let routes = Arena::uninitialized(&workspace, "trait_solver.retained_routes", route_words)?;
    config[CFG_ATOM_IDS] = atom_ids;
    config[CFG_ROUTE_USES] = use_map;

    // Catalog rows, then the solver's own admission and coherence.
    let layout = FrozenCatalog::retained_layout(std::array::from_fn(|table| report.rows[table]))?;
    let catalog = layout.catalog.clone();
    config[CFG_EPOCH] = catalog.epoch as u32;
    config[CFG_EPOCH + 1] = (catalog.epoch >> 32) as u32;
    config[CFG_PHASE] = 0;
    for table in 0..layout.table_offsets.len() {
        config[CFG_TABLE + table] = layout.table_offsets[table];
    }
    write_host_config(&queue, &scratch.config, &config);
    let catalog_words = catalog.word_count()?;
    let storage = Arena::uninitialized(&workspace, "trait_solver.catalog", catalog_words)?;
    let mut gpu = GpuTraitSolver::admit_storage(workspace.clone(), catalog.clone(), storage, |encoder, storage| {
        routes.buffer.clear(encoder, 0, Some(u64::from(route_words) * 4));
        // Poisoned or cleared, then the catalog-owned output regions as
        // `materialize` leaves them, all written by the GPU.
        let mut ranges = Vec::new();
        if options.poison_arenas {
            ranges.push((0, catalog_words, RETAINED_POISON));
        } else {
            storage.buffer.clear(encoder, 0, Some(u64::from(catalog_words) * 4));
        }
        for table in [6usize, 7, 11, 12] {
            let slice = catalog.outputs[table];
            if slice.count != 0 && (table == 7 || table == 12 || options.poison_arenas) {
                let fill = if table == 7 || table == 12 { INVALID } else { 0 };
                ranges.push((slice.offset, mul(slice.count, OUTPUT_WIDTHS[table], "retained catalog output")?, fill));
            }
        }
        producer.fill_words(encoder, &workspace, &scratch, store, &storage.buffer, &ranges)?;
        let bound = Bound {
            catalog: &storage.buffer,
            batch: &scratch.idle,
            routes: &routes.buffer,
            output: &scratch.idle,
            proof: &scratch.idle,
            stage: 0,
            stages: &scratch.stages,
        };
        for region in 0..REGIONS {
            producer.record(encoder, FILL[region], regions[region].1, &scratch, store, bound)?;
        }
        Ok(())
    })?;
    // Batch rows (bound goals of the retained uses), then the solver. The
    // GPU admits the catalog while the host records them: the admission
    // receipts and the producer state after the fill come with the solve's
    // first readback, which leaves their verdict to this function.
    // A deferred solve reads nothing back: the publication checks the
    // admission and the fill on the GPU (header words 45 to 47).
    if !options.defer_solve {
        *gpu.admission_state.lock().unwrap() = Some((scratch.state.clone(), S_WORDS));
    }
    let mut packet = gpu.new_packet()?;
    let mut batch_counts = [0; TABLE_COUNT];
    for table in 11..=16 {
        batch_counts[table] = report.rows[table];
    }
    let (submission, offsets) = packet.packet.prepare_retained_submission(batch_counts)?;
    config[CFG_PHASE] = 1;
    for table in 11..=16 {
        config[CFG_TABLE + table] = offsets[table];
    }
    write_host_config(&queue, &scratch.config, &config);
    let input_words = submission.plan.input_word_count;
    let solved = gpu.check_retained(&mut packet, &submission, options.read_rows, None, options.defer_solve, |encoder, input| {
        if options.poison_arenas && input_words > BATCH_FIXED_WORDS {
            let range = (BATCH_FIXED_WORDS, input_words - BATCH_FIXED_WORDS, RETAINED_POISON);
            producer.fill_words(encoder, &workspace, &scratch, store, &input.buffer, &[range])?;
        }
        let bound = Bound {
            catalog: &scratch.idle,
            batch: &input.buffer,
            routes: &routes.buffer,
            output: &scratch.idle,
            proof: &scratch.idle,
            stage: 0,
            stages: &scratch.stages,
        };
        for region in BATCH_FILL_REGIONS {
            producer.record(encoder, FILL[region], regions[region].1, &scratch, store, bound)?;
        }
        Ok(())
    });
    *gpu.admission_state.lock().unwrap() = None;
    let output_layout = if options.defer_solve {
        solved?.1
    } else {
        // A solve that failed before its readback read no receipts: they
        // decide whether the catalog or the solve failed.
        let admission = match &solved {
            Ok((Some(readback), _)) => readback.admission.clone().map(|(recipe, state)| (readback.catalog_status, recipe, state)),
            _ => None,
        };
        let (catalog_status, recipe_status, state) = match admission {
            Some(admission) => admission,
            None => gpu.readback_admission(&scratch.state, &mut producer)?,
        };
        report.catalog_status = Some(catalog_status);
        report.recipe_status = Some(recipe_status);
        report.fill_faults = state[S_FILL_FAULTS];
        if report.fill_faults != 0 {
            report.stage = RetainedTraitStage::Fill;
        } else if catalog_status[0] != 1 || recipe_status[0] != 1 {
            report.stage = RetainedTraitStage::Admission;
        }
        if report.stage != RetainedTraitStage::Producer {
            if options.read_rows {
                report.tables = gpu.read_tables(None)?;
            }
            report.producer_readback_bytes = producer.readback_bytes;
            return Ok((report, None));
        }
        let (readback, output_layout) = solved?;
        let readback = readback.ok_or_else(|| anyhow!("retained catalog solve deferred its readback"))?;
        report.batch_status = Some(readback.batch_status);
        report.contexts = readback.contexts;
        report.calls = readback.calls;
        report.obligations = readback.obligations;
        report.evidence = readback.evidence;
        output_layout
    };
    report.stage = RetainedTraitStage::Solved;

    // Publication: the host writes the identity and locations; the GPU
    // copies the solver's selections into routes and writes the status.
    let identity = RetainedTraitIdentity {
        epoch: catalog.epoch,
        arena_id: submission.arena_id,
        serial: submission.serial,
        generation,
    };
    let mut header = vec![0u32; RP_HEADER_WORDS as usize];
    header[0] = RP_MAGIC;
    header[1] = 1;
    header[2] = identity.epoch as u32;
    header[3] = (identity.epoch >> 32) as u32;
    header[4] = identity.arena_id as u32;
    header[5] = (identity.arena_id >> 32) as u32;
    header[6] = identity.serial;
    header[7] = generation;
    header[RP_H_FIRST_FAILURE] = u32::MAX;
    header[11] = uses;
    header[12] = obligations;
    header[13] = atoms;
    header[14] = use_map;
    header[15] = route_rows;
    header[16] = atom_ids;
    header[17] = catalog.slices[9].offset;
    header[18] = catalog.slices[10].offset;
    header[19] = catalog.slices[9].count;
    header[20] = catalog.slices[10].count;
    header[27] = catalog.slices[1].offset;
    header[28] = catalog.slices[5].offset;
    header[29] = catalog.slices[6].offset;
    header[30] = report.rows[15];
    for (word, table) in [(32, 3), (33, 4), (34, 5), (35, 10)] {
        header[word] = output_layout.slices[table].offset;
    }
    header[36] = catalog.outputs[0].offset;
    header[37] = packet.proof.logical_words;
    header[38] = catalog_words;
    header[39] = packet.output.logical_words;
    header[40] = dir_entries;
    header[41] = traits;
    header[42] = jobs;
    header[43] = status[A_DECLS];
    header[44] = u32::MAX;
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("trait_solver.retained_publish"),
    });
    routes.upload(&mut encoder, &[ArenaWrite { first_word: 0, words: header }])?;
    // The verdict publish_finish requires: the solve finished, the fill
    // wrote every row and the native recipes were admitted. A deferred
    // solve reads none of them back.
    gpu.copy_solve_stop(&mut encoder, &routes.buffer)?;
    scratch.state.copy_to(&mut encoder, S_FILL_FAULTS as u64 * 4, &routes.buffer, RP_H_FILL_FAULTS * 4, 4);
    let recipes = u64::from(gpu.catalog.native_layout.status.offset) * 4;
    gpu.native_recipes.buffer.copy_to(&mut encoder, recipes, &routes.buffer, RP_H_RECIPE_STATUS * 4, 4);
    if options.defer_solve && options.test_unfinished_solve {
        routes.upload(&mut encoder, &[ArenaWrite { first_word: RP_H_SOLVE_STOP as u32, words: vec![0] }])?;
    }
    let bound = Bound {
        catalog: &gpu.storage.buffer,
        batch: &packet.input.buffer,
        routes: &routes.buffer,
        output: &packet.output.buffer,
        proof: &packet.proof.buffer,
        stage: 0,
        stages: &scratch.stages,
    };
    producer.record(&mut encoder, PUBLISH_ROUTES, add(obligations, uses, "retained publish lanes")?, &scratch, store, bound)?;
    producer.record(&mut encoder, PUBLISH_FINISH, 1, &scratch, store, bound)?;
    passes_core::flush_deferred_compute(&mut encoder);
    queue.submit(Some(encoder.finish()));

    report.producer_readback_bytes = producer.readback_bytes;
    if options.read_rows {
        report.tables = gpu.read_tables(Some(&packet))?;
    }
    let publication = RetainedTraitPublication {
        gpu,
        packet,
        routes,
        route_words,
        identity,
        rt_counts: rt_counts.clone(),
        // The counters this check ran with; the producer does not write
        // the store.
        store_counts: std::sync::Mutex::new(Some(status)),
        store_jobs: 0,
        noted_status: std::sync::Mutex::new(None),
    };
    Ok((report, Some(publication)))
}

/// The identity of one retained trait publication: the solver catalog
/// epoch, the batch arena id and serial, and the store build generation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RetainedTraitIdentity {
    pub epoch: u64,
    pub arena_id: u64,
    pub serial: u32,
    pub generation: u32,
}

/// An exact byte range of one publication buffer.
#[derive(Clone, Copy, Debug)]
pub struct RetainedBufferRange<'a> {
    pub buffer: &'a wgpu::Buffer,
    pub offset: u64,
    pub size: u64,
    /// Bytes of the whole allocation behind the range, from `offset`.
    pub capacity: u64,
}
impl<'a> RetainedBufferRange<'a> {
    fn of(buffer: &'a LaniusBuffer<u32>, words: u32) -> Self {
        Self {
            buffer: &buffer.buffer,
            offset: buffer.byte_offset,
            size: u64::from(words) * 4,
            capacity: buffer.byte_size as u64,
        }
    }
    /// The whole allocation behind the range: the same binding for every
    /// logical size it holds, so a consumer that never reads past the
    /// logical words keeps its cached bind groups as the size changes.
    pub fn whole_binding(&self) -> wgpu::BindingResource<'a> {
        wgpu::BindingResource::Buffer(wgpu::BufferBinding {
            buffer: self.buffer,
            offset: self.offset,
            size: std::num::NonZeroU64::new(self.capacity.max(self.size)),
        })
    }
    pub fn binding(&self) -> wgpu::BindingResource<'a> {
        wgpu::BindingResource::Buffer(wgpu::BufferBinding {
            buffer: self.buffer,
            offset: self.offset,
            size: std::num::NonZeroU64::new(self.size),
        })
    }
}

/// The buffers a GPU consumer binds (docs/compiler-retained-trait-catalog.md,
/// "Publication"). Word offsets inside them are in the route header.
#[derive(Clone, Copy, Debug)]
pub struct RetainedTraitView<'a> {
    pub identity: RetainedTraitIdentity,
    /// Route arena: header, use map, routes, atom identities.
    pub routes: RetainedBufferRange<'a>,
    /// Solver catalog arena: impl, method, atom and term node tables.
    pub catalog: RetainedBufferRange<'a>,
    /// Solver output arena of the packet.
    pub output: RetainedBufferRange<'a>,
    /// Proof store: bindings and proof term nodes.
    pub proof: RetainedBufferRange<'a>,
    /// The store's counters (READY, GENERATION), for the consumer's check.
    pub rt_counts: &'a wgpu::Buffer,
}

/// A solved retained trait check whose catalog, packet, proof store and
/// routes stay allocated, and their workspace slots reserved, until it is
/// dropped. Production consumers bind `view` and read nothing back.
pub struct RetainedTraitPublication {
    gpu: GpuTraitSolver,
    packet: GpuPacket,
    routes: Arena,
    route_words: u32,
    identity: RetainedTraitIdentity,
    rt_counts: wgpu::Buffer,
    /// The store's counters, read with the last `status`.
    store_counts: std::sync::Mutex<Option<Vec<u32>>>,
    /// Committed exports of the store's build when the check ran.
    store_jobs: usize,
    /// Header words 8-10 as a consumer's readback returned them.
    noted_status: std::sync::Mutex<Option<[u32; 3]>>,
}

impl RetainedTraitPublication {
    pub fn identity(&self) -> RetainedTraitIdentity {
        self.identity
    }

    /// The buffers to bind, after a host check that `store` is the store and
    /// build this publication came from. The GPU consumer still checks the
    /// header status and the live READY and GENERATION counters.
    pub fn view<'a>(&'a self, store: &ProgramRetention) -> Result<RetainedTraitView<'a>> {
        let same_store = store.with_store_buffers(|buffers, generation| {
            Ok(buffers.get("rt_counts") == Some(&self.rt_counts) && generation == self.identity.generation)
        })?;
        ensure!(same_store, "retained trait publication belongs to another store or build");
        Ok(RetainedTraitView {
            identity: self.identity,
            routes: RetainedBufferRange::of(&self.routes.buffer, self.route_words),
            catalog: RetainedBufferRange::of(&self.gpu.storage.buffer, self.gpu.storage.logical_words),
            output: RetainedBufferRange::of(&self.packet.output.buffer, self.packet.output.logical_words),
            proof: RetainedBufferRange::of(&self.packet.proof.buffer, self.packet.proof.logical_words),
            rt_counts: &self.rt_counts,
        })
    }

    /// Header words 8-10: status (0 building, 1 valid, 2 failed), route
    /// failures, first failure. The same readback returns the store's
    /// counters, which `take_store_counts` hands to the next consumer.
    pub fn status(&self) -> Result<[u32; 3]> {
        let bytes = counts::WORDS as u64 * 4;
        let counters = LaniusBuffer::<u32>::new((self.rt_counts.clone(), bytes), counts::WORDS);
        let regions = [
            ReadbackRegion::from_buffer(&self.routes.buffer, RP_H_STATUS as u64 * 4, 12, "retained publication status")?,
            ReadbackRegion::from_buffer(&counters, 0, bytes as usize, "retained publication store counters")?,
        ];
        let raw = self.gpu.readback.read_regions(&self.gpu.device, &self.gpu.queue, &regions, crate::readback_label!("retained publication status"))?;
        let words = super::words(&raw[0])?;
        *self.store_counts.lock().unwrap_or_else(std::sync::PoisonError::into_inner) = Some(super::words(&raw[1])?);
        let status = [words[0], words[1], words[2]];
        self.note_status(status);
        Ok(status)
    }

    /// Header words 8-10 that a consumer copied on the GPU and read back
    /// with its own readback (discovery's root resolution).
    pub fn note_status(&self, status: [u32; 3]) {
        *self.noted_status.lock().unwrap_or_else(std::sync::PoisonError::into_inner) = Some(status);
    }

    /// The status a consumer noted, or `status` when none did.
    pub fn checked_status(&self) -> Result<[u32; 3]> {
        let noted = *self.noted_status.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        match noted {
            Some(status) => Ok(status),
            None => self.status(),
        }
    }

    /// The store counters the check ran with, or those read with the last
    /// `status`, once, while `store` is in the same build with the same
    /// committed exports. A consumer that checked `view` against the same
    /// store may size its work with them; a later export changes the
    /// extent the GPU checks.
    pub fn take_store_counts(&self, store: &ProgramRetention) -> Option<Vec<u32>> {
        let counts = self.store_counts.lock().unwrap_or_else(std::sync::PoisonError::into_inner).take()?;
        (store.generation() == self.identity.generation && store.job_reports().len() == self.store_jobs).then_some(counts)
    }

    /// GPU-selected source span of the first hard-refuted call. No proof,
    /// environment or semantic table is read back to choose a diagnostic.
    pub fn diagnostic_span(&self) -> Result<Option<[u32; 4]>> {
        let region = ReadbackRegion::from_buffer(&self.routes.buffer, 48 * 4, 16, "retained diagnostic")?;
        let raw = self.gpu.readback.read_regions(&self.gpu.device, &self.gpu.queue, &[region], crate::readback_label!("retained diagnostic"))?;
        let words = super::words(&raw[0])?;
        Ok((words[0] != u32::MAX).then(|| [words[0], words[1], words[2], words[3]]))
    }

    /// Words of the route arena. For assertions only.
    #[doc(hidden)]
    pub fn read_routes_for_test(&self) -> Result<Vec<u32>> {
        let region = ReadbackRegion::from_buffer(&self.routes.buffer, 0, arena::byte_len(self.route_words)?, "retained routes")?;
        super::words(&self.gpu.readback.read_regions(&self.gpu.device, &self.gpu.queue, &[region], crate::debug_readback_label!("retained routes"))?[0])
    }

    /// Runs the GPU consumer shaders/tests/retained_route_query.slang over
    /// `requests` (use, obligation ordinal, required symbol) against
    /// `identity`, and reads its 16-word answers back for assertions.
    #[doc(hidden)]
    pub fn query_for_test(
        &self,
        store: &ProgramRetention,
        identity: RetainedTraitIdentity,
        requests: &[[u32; 3]],
    ) -> Result<Vec<[u32; 16]>> {
        let view = RetainedTraitView {
            identity: self.identity,
            routes: RetainedBufferRange::of(&self.routes.buffer, self.route_words),
            catalog: RetainedBufferRange::of(&self.gpu.storage.buffer, self.gpu.storage.logical_words),
            output: RetainedBufferRange::of(&self.packet.output.buffer, self.packet.output.logical_words),
            proof: RetainedBufferRange::of(&self.packet.proof.buffer, self.packet.proof.logical_words),
            rt_counts: &self.rt_counts,
        };
        query_view(&self.gpu, store, view, identity, requests)
    }
}

fn query_view(gpu: &GpuTraitSolver, store: &ProgramRetention, view: RetainedTraitView<'_>, identity: RetainedTraitIdentity, requests: &[[u32; 3]]) -> Result<Vec<[u32; 16]>> {
    let device = &gpu.device;
    let queue = &gpu.queue;
    let mut input = vec![
        u32::try_from(requests.len())?,
        identity.epoch as u32,
        (identity.epoch >> 32) as u32,
        identity.arena_id as u32,
        (identity.arena_id >> 32) as u32,
        identity.serial,
        identity.generation,
        0,
    ];
    for request in requests {
        input.extend_from_slice(&[request[0], request[1], request[2], 0]);
    }
    let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST;
    let workspace = &gpu.workspace;
    let input = workspace.initialized("trait_solver.retained_query_in", u32::try_from(input.len())?, usage, Some(&input))?;
    let out_words = u32::try_from(requests.len().max(1) * 16)?;
    let output = workspace.initialized("trait_solver.retained_query_out", out_words, usage, Some(&vec![u32::MAX; out_words as usize]))?;
    let data = make_pass_data_from_shader_key(device, QUERY_KEY, "main", QUERY_KEY)?;
    store.with_store_buffers(|_, _| {
        let mut entries = Vec::new();
        for name in reflected_names(&data) {
            let resource = match name.as_str() {
                "rc_routes" => view.routes.binding(),
                "rp_catalog" => view.catalog.binding(),
                "rp_proof" => view.proof.binding(),
                "rt_counts" => view.rt_counts.as_entire_binding(),
                "rq_requests" => input.as_entire_binding(),
                "rq_out" => output.as_entire_binding(),
                other => return Err(anyhow!("retained route query binds unknown buffer {other}")),
            };
            entries.push((name, resource));
        }
        let entries = entries.iter().map(|(n, r)| (n.as_str(), r.clone())).collect::<Vec<_>>();
        let bind = passes_core::bind_group::create_bind_group_from_bindings(device, Some(&data.shader_id), &data, 0, &entries)?;
        let mut encoder = device.create_command_encoder(&Default::default());
        {
            let mut compute = passes_core::begin_counted_compute_pass(
                &mut encoder,
                &wgpu::ComputePassDescriptor { label: Some("tests.retained_route_query"), timestamp_writes: None },
            );
            compute.set_pipeline(&data.pipeline);
            compute.set_bind_group(0, &bind, &[]);
            passes_core::record_compute_dispatch();
            compute.dispatch_workgroups(u32::try_from(requests.len().div_ceil(64).max(1))?, 1, 1);
        }
        crate::gpu::timer::stamp_active_operation(&mut encoder, data.shader_id.clone());
        passes_core::flush_deferred_compute(&mut encoder);
        queue.submit(Some(encoder.finish()));
        Ok(())
    })?;
    let region = ReadbackRegion::from_buffer(&output, 0, arena::byte_len(out_words)?, "retained route query")?;
    let words = super::words(&gpu.readback.read_regions(device, queue, &[region], crate::readback_label!("retained route query"))?[0])?;
    Ok(words.chunks_exact(16).take(requests.len()).map(|c| c.try_into().unwrap()).collect())
}

/// Writes the host's rc_config words (from the epoch on, except the sort
/// width), leaving those 00_configure wrote.
fn write_host_config(queue: &wgpu::Queue, buffer: &LaniusBuffer<u32>, config: &[u32]) {
    buffer.write(queue, (CFG_EPOCH * 4) as u64, &words_bytes(&config[CFG_EPOCH..CFG_SORT]));
    buffer.write(queue, (CFG_ATOM_IDS * 4) as u64, &words_bytes(&config[CFG_ATOM_IDS..]));
}

fn words_bytes(words: &[u32]) -> Vec<u8> {
    words.iter().flat_map(|word| word.to_le_bytes()).collect()
}

impl GpuTraitSolver {
    /// Copies the last solve's stop word (kernels::wave::STOP) into the
    /// publication header, where publish_finish requires it to be DONE.
    fn copy_solve_stop(&self, encoder: &mut wgpu::CommandEncoder, routes: &LaniusBuffer<u32>) -> Result<()> {
        let state = self.last_wave_state.lock().unwrap().clone().ok_or_else(|| anyhow!("the publication's solve has no wave state"))?;
        state.copy_to(encoder, super::kernels::wave::STOP as u64 * 4, routes, RP_H_SOLVE_STOP * 4, 4);
        Ok(())
    }

    /// The catalog and native recipe receipts of the admission submit, with
    /// the producer state after its catalog fill: one readback.
    fn readback_admission(
        &self,
        state: &LaniusBuffer<u32>,
        producer: &mut Producer,
    ) -> Result<([u32; 8], [u32; 8], Vec<u32>)> {
        let catalog = self.catalog.outputs[0];
        let recipes = self.catalog.native_layout.status;
        let regions = [
            ReadbackRegion::from_buffer(&self.storage.buffer, u64::from(catalog.offset) * 4, 32, "catalog receipt")?,
            ReadbackRegion::from_buffer(&self.native_recipes.buffer, u64::from(recipes.offset) * 4, 32, "native recipe receipt")?,
            ReadbackRegion::from_buffer(state, 0, S_WORDS * 4, "retained producer state")?,
        ];
        let raw = self.readback.read_regions(&self.device, &self.queue, &regions, crate::readback_label!("retained catalog admission"))?;
        producer.readback_bytes += raw.iter().map(|r| r.len() as u64).sum::<u64>();
        // This readback is the admission's: the solve does not read it again.
        self.admission_pending.store(false, std::sync::atomic::Ordering::Relaxed);
        Ok((one_status(&raw[0])?, one_status(&raw[1])?, super::words(&raw[2])?))
    }

    /// Every produced row: catalog tables 0-10 and, with a packet, its batch
    /// tables 11-16. For assertions only.
    fn read_tables(&self, packet: Option<&GpuPacket>) -> Result<Vec<Vec<u32>>> {
        let mut tables = vec![Vec::new(); TABLE_COUNT];
        let mut regions = Vec::new();
        let mut which = Vec::new();
        for table in 0..=10 {
            let slice = self.catalog.slices[table];
            if slice.count != 0 {
                let words = mul(slice.count, WIDTHS[table], "retained table readback")?;
                regions.push(ReadbackRegion::from_buffer(&self.storage.buffer, u64::from(slice.offset) * 4, arena::byte_len(words)?, "retained catalog rows")?);
                which.push(table);
            }
        }
        let directory;
        if let Some(packet) = packet {
            let header = ReadbackRegion::from_buffer(&packet.input.buffer, 0, arena::byte_len(BATCH_FIXED_WORDS)?, "retained batch directory")?;
            directory = super::words(&self.readback.read_regions(&self.device, &self.queue, &[header], crate::debug_readback_label!("retained batch directory"))?[0])?;
            for table in 11..=16 {
                let row = &directory[DIRECTORY_WORD as usize + table * 6..][..6];
                if row[3] != 0 {
                    let words = mul(row[3], WIDTHS[table], "retained table readback")?;
                    regions.push(ReadbackRegion::from_buffer(&packet.input.buffer, u64::from(row[2]) * 4, arena::byte_len(words)?, "retained batch rows")?);
                    which.push(table);
                }
            }
        }
        let raw = self.readback.read_regions(&self.device, &self.queue, &regions, crate::debug_readback_label!("retained rows"))?;
        for (table, bytes) in which.into_iter().zip(raw) {
            tables[table] = super::words(&bytes)?;
        }
        Ok(tables)
    }

    /// The one submission of a retained packet: the directory upload and
    /// `fill` (the producer's batch rows) in one submit, then the solver's
    /// batch admission and proof waves. No host acceptance follows: the
    /// selected evidence stays in the GPU output arena.
    ///
    /// With `gpu_counts` = (buffer, first word), the submission was prepared
    /// from bounds of the batch's counts, and the counts are in `buffer`
    /// at `first word + table` when `fill` returns: they are copied into the
    /// batch directory (`record_gpu_batch_counts`), and the solve is
    /// deferred, its progress read by the caller's later readback. Without
    /// it the submission holds the exact counts and the solve reads its
    /// progress back.
    fn check_retained(
        &mut self,
        packet: &mut GpuPacket,
        submission: &Submission,
        semantic_rows: bool,
        gpu_counts: Option<(&LaniusBuffer<u32>, u64)>,
        defer: bool,
        fill: impl FnOnce(&mut wgpu::CommandEncoder, &Arena) -> Result<()>,
    ) -> Result<(Option<WaveReadback>, OutputLayout)> {
        ensure!(
            Arc::ptr_eq(&packet.gpu_owner, &self.gpu_owner) && Arc::ptr_eq(&packet.packet.catalog, &self.catalog),
            "retained packet belongs to another solver"
        );
        if self.batch_kernels.is_none() {
            self.batch_kernels = Some(super::kernels::BatchKernels::load(&self.device)?);
        }
        if self.proof_kernels.is_none() {
            self.proof_kernels = Some(super::kernels::ProofKernels::load(&self.device)?);
        }
        // A retained packet is single-use.
        packet.poisoned = true;
        packet.arena_id = Some(submission.arena_id);
        let layout = OutputLayout::from_submission(&self.catalog, submission)?;
        let plan = BatchPlan::new(&self.catalog, &layout, packet.completed_suffix_counts, submission)?;
        ensure_retained_inputs_unchanged(
            &layout,
            packet.completed_suffix_counts,
            packet.completed_input_offsets,
            &submission.plan,
        )?;
        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("trait_solver.retained_batch"),
        });
        packet.input.prepare(&mut encoder, submission.plan.input_word_count, &submission.plan.copies)?;
        packet.output.prepare(&mut encoder, submission.plan.output_word_count, &submission.plan.output_copies)?;
        packet.input.upload(&mut encoder, &submission.plan.writes)?;
        fill(&mut encoder, &packet.input)?;
        if let Some((counts, first_word)) = gpu_counts {
            super::record_gpu_batch_counts(&mut encoder, &packet.input, counts, first_word)?;
        }
        passes_core::flush_deferred_compute(&mut encoder);
        self.queue.submit(Some(encoder.finish()));
        let mut templates = std::mem::take(&mut self.wave_templates);
        // Production publication reads no semantic rows; diagnostics opt in.
        self.semantic_rows = semantic_rows;
        let solved = if defer {
            self.solve_deferred(&mut templates, packet, &layout, &plan, submission).map(|()| None)
        } else {
            self.solve(&mut templates, packet, &layout, &plan, submission).map(Some)
        };
        self.semantic_rows = true;
        self.wave_templates = templates;
        let readback = solved?;
        let proof_layout = packet.packet.proof_store.layout();
        self.workspace
            .raise_proof_capacity_floor(&std::array::from_fn(|table| proof_layout.slices[table].capacity));
        Ok((readback, layout))
    }
}
