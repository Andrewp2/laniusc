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
    type_checker::program_retention::{ProgramRetention, counts},
};

const KEYS: [&str; 13] = [
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
];
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
const CFG_LANES: usize = 8;
const CFG_BASE: usize = 9;
const CFG_EPOCH: usize = 16;
const CFG_GENERATION: usize = 18;
const CFG_PHASE: usize = 19;
const CFG_TABLE: usize = 20;
const CFG_WORDS: usize = 40;
const REGIONS: usize = 7;
const COUNTERS: usize = 16;

// producer.slang rc_state words.
const S_FAILURES: usize = 0;
const S_FIRST: usize = 1;
const S_UNSUPPORTED_MEMBER_BOUNDS: usize = 2;
const S_FILL_FAULTS: usize = 3;
const S_UNIT_SLOTS_FULL: usize = 4;
const S_TOTALS: usize = 8;
const S_WORDS: usize = 24;

/// Solver table of each producer counter (producer.slang RC_C_*).
const COUNTER_TABLE: [usize; COUNTERS] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 14, 15, 11, 12, 16];

// Arena indexes of the retention store (retention_store.slang RT_A_*).
const A_DECLS: usize = 0;
const A_PARAMS: usize = 1;
const A_TERMS: usize = 2;
const A_DIR: usize = 4;
const A_USES: usize = 8;
const A_TRAITS: usize = 14;
const RT_FIRST_TERM: u32 = 32;

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
    state: LaniusBuffer<u32>,
    flags: LaniusBuffer<u32>,
    scan: LaniusBuffer<u32>,
    blocks: LaniusBuffer<u32>,
    entry: LaniusBuffer<u32>,
    snapshot: LaniusBuffer<u32>,
    unit_slot: LaniusBuffer<u32>,
    /// Bound as the arena of the other phase; never written.
    idle: LaniusBuffer<u32>,
}

struct Producer {
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    passes: Vec<PassData>,
    readback: PagedReadback,
    readback_bytes: u64,
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
    fn read(&mut self, buffer: &LaniusBuffer<u32>, words: usize, label: &str) -> Result<Vec<u32>> {
        let region = ReadbackRegion::from_buffer(buffer, 0, arena::byte_len(u32::try_from(words)?)?, label)?;
        let raw = self.readback.read_regions(&self.device, &self.queue, &[region], label)?;
        self.readback_bytes += raw[0].len() as u64;
        super::words(&raw[0])
    }

    #[allow(clippy::too_many_arguments)]
    fn record(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        pass: usize,
        lanes: u32,
        scratch: &Scratch,
        store: &BTreeMap<&'static str, wgpu::Buffer>,
        catalog: &LaniusBuffer<u32>,
        batch: &LaniusBuffer<u32>,
    ) -> Result<()> {
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
                "rc_catalog" => catalog.as_entire_binding(),
                "rc_batch" => batch.as_entire_binding(),
                other => store
                    .get(other)
                    .ok_or_else(|| anyhow!("retained trait producer binds unknown buffer {other}"))?
                    .as_entire_binding(),
            };
            entries.push((name.as_str(), resource));
        }
        let bind = passes_core::bind_group::create_bind_group_from_bindings(
            &self.device,
            Some(&data.shader_id),
            data,
            0,
            &entries,
        )?;
        let (x, y) = if pass == SCAN_BLOCKS { (1, 1) } else { groups(lanes) };
        let mut compute = passes_core::begin_counted_compute_pass(
            encoder,
            &wgpu::ComputePassDescriptor { label: Some("trait_solver.retained_producer"), timestamp_writes: None },
        );
        compute.set_pipeline(&data.pipeline);
        compute.set_bind_group(0, &bind, &[]);
        passes_core::record_compute_dispatch();
        compute.dispatch_workgroups(x, y, 1);
        Ok(())
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
/// the solver over the bound goals of the store's current build.
pub(in crate::compiler::gpu_compiler) fn check(
    workspace: WorkspaceLease,
    store: &ProgramRetention,
    options: &RetainedTraitOptions,
) -> Result<RetainedTraitCheck> {
    let dispatches_before = passes_core::recorded_compute_dispatch_count();
    let readbacks_before = passes_core::readback_round_trips();
    let mut report = store.with_store_buffers(|buffers, generation| run(workspace, buffers, generation, options))?;
    let readbacks = passes_core::readback_round_trips();
    report.dispatches = passes_core::recorded_compute_dispatch_count() - dispatches_before;
    report.readbacks = readbacks.0 - readbacks_before.0;
    report.readback_wait_ns = readbacks.1 - readbacks_before.1;
    Ok(report)
}

fn run(
    workspace: WorkspaceLease,
    store: &BTreeMap<&'static str, wgpu::Buffer>,
    generation: u32,
    options: &RetainedTraitOptions,
) -> Result<RetainedTraitCheck> {
    let device = workspace.device().clone();
    let queue = workspace.queue().clone();
    let passes = KEYS
        .iter()
        .map(|&key| make_pass_data_from_shader_key(&device, key, "main", key))
        .collect::<Result<Vec<_>>>()?;
    let mut producer = Producer {
        readback: PagedReadback::new(&device, "trait_solver.retained_readback", 4096),
        device: device.clone(),
        queue: queue.clone(),
        passes,
        readback_bytes: 0,
    };
    let mut report = RetainedTraitCheck {
        stage: RetainedTraitStage::Producer,
        generation,
        attempts: 0,
        producer_failures: 0,
        first_failure: None,
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
    };

    // The store's counters size the lane regions.
    let rt_counts = store.get("rt_counts").ok_or_else(|| anyhow!("retention store has no rt_counts"))?;
    let status = {
        let staging = workspace.initialized(
            "trait_solver.retained_counts",
            counts::WORDS as u32,
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
            None,
        )?;
        let mut encoder = device.create_command_encoder(&Default::default());
        encoder.copy_buffer_to_buffer(rt_counts, 0, &staging.buffer, staging.byte_offset, counts::WORDS as u64 * 4);
        queue.submit(Some(encoder.finish()));
        producer.read(&staging, counts::WORDS, "retention store counters")?
    };
    let regions = regions(&status)?;
    let lanes = regions[REGIONS - 1].0 + regions[REGIONS - 1].1;
    let jobs = regions[6].1;
    let dir_entries = regions[3].1;
    let blocks = lanes.div_ceil(256).max(1);
    let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST;
    let mut config = vec![0u32; CFG_WORDS];
    for (word, arena) in [(0, A_DECLS), (1, A_PARAMS), (2, A_TERMS), (3, A_DIR), (4, A_TRAITS), (5, A_USES)] {
        config[word] = status[arena];
    }
    config[6] = jobs;
    config[CFG_LANES] = lanes;
    for region in 0..REGIONS {
        config[CFG_BASE + region] = regions[region].0;
    }
    config[CFG_GENERATION] = generation;
    let mut unit_slots = options
        .unit_slots
        .unwrap_or_else(|| jobs.saturating_mul(2))
        .max(1)
        .checked_next_power_of_two()
        .ok_or_else(|| anyhow!("retained unit table overflow"))?;

    // Count: mark, units, count, scan. Grown only when the unit table is full.
    let (scratch, state) = loop {
        report.attempts += 1;
        config[7] = unit_slots;
        let mut initial_state = vec![0u32; S_WORDS];
        initial_state[S_FIRST] = u32::MAX;
        let scratch = Scratch {
            config: workspace.initialized("trait_solver.retained_config", CFG_WORDS as u32, usage, Some(&config))?,
            state: workspace.initialized("trait_solver.retained_state", S_WORDS as u32, usage, Some(&initial_state))?,
            flags: workspace.initialized("trait_solver.retained_flags", lanes.max(1) * 16, usage, None)?,
            scan: workspace.initialized("trait_solver.retained_scan", lanes.max(1) * 16, usage, None)?,
            blocks: workspace.initialized("trait_solver.retained_blocks", blocks * 16, usage, None)?,
            entry: workspace.initialized("trait_solver.retained_entry", dir_entries.max(1) * 2, usage, None)?,
            snapshot: workspace.initialized(
                "trait_solver.retained_snapshot",
                jobs.max(1) * 2,
                usage,
                Some(&vec![u32::MAX; jobs.max(1) as usize * 2]),
            )?,
            unit_slot: workspace.initialized("trait_solver.retained_unit_slot", unit_slots, usage, None)?,
            idle: workspace.initialized("trait_solver.retained_idle", 4, usage, None)?,
        };
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("trait_solver.retained_count"),
        });
        scratch.entry.clear(&mut encoder, 0, None);
        scratch.unit_slot.clear(&mut encoder, 0, None);
        for pass in [MARK, UNITS, COUNT, SCAN_LOCAL, SCAN_BLOCKS, SCAN_APPLY] {
            producer.record(&mut encoder, pass, lanes, &scratch, store, &scratch.idle, &scratch.idle)?;
        }
        passes_core::flush_deferred_compute(&mut encoder);
        queue.submit(Some(encoder.finish()));
        let state = producer.read(&scratch.state, S_WORDS, "retained producer state")?;
        if state[S_UNIT_SLOTS_FULL] != 0 {
            unit_slots = unit_slots.checked_mul(2).ok_or_else(|| anyhow!("retained unit table overflow"))?;
            continue;
        }
        break (scratch, state);
    };
    report.producer_failures = state[S_FAILURES];
    report.unsupported_member_bounds = state[S_UNSUPPORTED_MEMBER_BOUNDS];
    if state[S_FIRST] != u32::MAX {
        report.first_failure = Some((state[S_FIRST] >> 24, state[S_FIRST] & 0xff_ffff));
    }
    for counter in 0..COUNTERS {
        report.rows[COUNTER_TABLE[counter]] = state[S_TOTALS + counter];
    }
    report.rows[0] = jobs;
    if report.producer_failures != 0 || jobs == 0 {
        report.producer_readback_bytes = producer.readback_bytes;
        return Ok(report);
    }

    // Catalog rows, then the solver's own admission and coherence.
    let layout = FrozenCatalog::retained_layout(std::array::from_fn(|table| report.rows[table]))?;
    let catalog = layout.catalog.clone();
    config[CFG_EPOCH] = catalog.epoch as u32;
    config[CFG_EPOCH + 1] = (catalog.epoch >> 32) as u32;
    config[CFG_PHASE] = 0;
    for table in 0..layout.table_offsets.len() {
        config[CFG_TABLE + table] = layout.table_offsets[table];
    }
    scratch.config.write(&queue, 0, &words_bytes(&config));
    let catalog_words = catalog.word_count()?;
    let storage = Arena::uninitialized(&workspace, "trait_solver.catalog", catalog_words)?;
    let mut gpu = GpuTraitSolver::admit_storage(workspace.clone(), catalog.clone(), storage, |encoder, storage| {
        if options.poison_arenas {
            storage.upload(encoder, &[ArenaWrite { first_word: 0, words: vec![RETAINED_POISON; catalog_words as usize] }])?;
        } else {
            storage.buffer.clear(encoder, 0, Some(u64::from(catalog_words) * 4));
        }
        // Catalog-owned output regions start as `materialize` leaves them.
        let mut writes = Vec::new();
        for table in [6usize, 7, 11, 12] {
            let slice = catalog.outputs[table];
            if slice.count != 0 {
                let fill = if table == 7 || table == 12 { INVALID } else { 0 };
                let words = mul(slice.count, OUTPUT_WIDTHS[table], "retained catalog output")?;
                writes.push(ArenaWrite { first_word: slice.offset, words: vec![fill; words as usize] });
            }
        }
        storage.upload(encoder, &writes)?;
        for region in 0..REGIONS {
            producer.record(encoder, FILL[region], regions[region].1, &scratch, store, &storage.buffer, &scratch.idle)?;
        }
        Ok(())
    })?;
    let readback = gpu.readback_admission(&scratch.state, &mut producer)?;
    report.catalog_status = Some(readback.0);
    report.recipe_status = Some(readback.1);
    report.fill_faults = readback.2[S_FILL_FAULTS];
    if report.fill_faults != 0 {
        report.stage = RetainedTraitStage::Fill;
    } else if readback.0[0] != 1 || readback.1[0] != 1 {
        report.stage = RetainedTraitStage::Admission;
    }
    if report.stage != RetainedTraitStage::Producer {
        if options.read_rows {
            report.tables = gpu.read_tables(None)?;
        }
        report.producer_readback_bytes = producer.readback_bytes;
        return Ok(report);
    }

    // Batch rows (bound goals of the retained uses), then the solver.
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
    scratch.config.write(&queue, 0, &words_bytes(&config));
    let input_words = submission.plan.input_word_count;
    let result = gpu.check_retained(&mut packet, &submission, |encoder, input| {
        if options.poison_arenas && input_words > BATCH_FIXED_WORDS {
            input.upload(encoder, &[ArenaWrite {
                first_word: BATCH_FIXED_WORDS,
                words: vec![RETAINED_POISON; (input_words - BATCH_FIXED_WORDS) as usize],
            }])?;
        }
        for region in BATCH_FILL_REGIONS {
            producer.record(encoder, FILL[region], regions[region].1, &scratch, store, &scratch.idle, &input.buffer)?;
        }
        Ok(())
    })?;
    let readback = result;
    report.stage = RetainedTraitStage::Solved;
    report.batch_status = Some(readback.batch_status);
    report.contexts = readback.contexts;
    report.calls = readback.calls;
    report.obligations = readback.obligations;
    report.evidence = readback.evidence;
    report.producer_readback_bytes = producer.readback_bytes;
    if options.read_rows {
        report.tables = gpu.read_tables(Some(&packet))?;
    }
    Ok(report)
}

fn words_bytes(words: &[u32]) -> Vec<u8> {
    words.iter().flat_map(|word| word.to_le_bytes()).collect()
}

impl GpuTraitSolver {
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
        let raw = self.readback.read_regions(&self.device, &self.queue, &regions, "retained catalog admission")?;
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
            directory = super::words(&self.readback.read_regions(&self.device, &self.queue, &[header], "retained batch directory")?[0])?;
            for table in 11..=16 {
                let row = &directory[DIRECTORY_WORD as usize + table * 6..][..6];
                if row[3] != 0 {
                    let words = mul(row[3], WIDTHS[table], "retained table readback")?;
                    regions.push(ReadbackRegion::from_buffer(&packet.input.buffer, u64::from(row[2]) * 4, arena::byte_len(words)?, "retained batch rows")?);
                    which.push(table);
                }
            }
        }
        let raw = self.readback.read_regions(&self.device, &self.queue, &regions, "retained rows")?;
        for (table, bytes) in which.into_iter().zip(raw) {
            tables[table] = super::words(&bytes)?;
        }
        Ok(tables)
    }

    /// The one submission of a retained packet: the directory upload and
    /// `fill` (the producer's batch rows) in one submit, then the solver's
    /// batch admission and proof waves. No host acceptance follows: the
    /// selected evidence stays in the GPU output arena.
    fn check_retained(
        &mut self,
        packet: &mut GpuPacket,
        submission: &Submission,
        fill: impl FnOnce(&mut wgpu::CommandEncoder, &Arena) -> Result<()>,
    ) -> Result<WaveReadback> {
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
        passes_core::flush_deferred_compute(&mut encoder);
        self.queue.submit(Some(encoder.finish()));
        let mut templates = std::mem::take(&mut self.wave_templates);
        let solved = self.solve(&mut templates, packet, &layout, &plan, submission);
        self.wave_templates = templates;
        let readback = solved?;
        let proof_layout = packet.packet.proof_store.layout();
        self.workspace
            .raise_proof_capacity_floor(&std::array::from_fn(|table| proof_layout.slices[table].capacity));
        Ok(readback)
    }
}
