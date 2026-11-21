use anyhow::{Result, anyhow, ensure};

use {crate::compiler::gpu_compiler::trait_solver::{abi::Span, catalog::FrozenCatalog}, super::{BatchPlan, arena::Arena}};
use crate::gpu::{
    buffers::LaniusBuffer,
    dispatch_capture,
    passes_core::{self, PassData},
};

// Ordinary literals are required by laniusc-shaders/build.rs artifact discovery.
const CATALOG_KEYS: [&str; 22] = [
    "type_checker/trait_solver/catalog/initialize_trait_catalog",
    "type_checker/trait_solver/catalog/clear_atom_index",
    "type_checker/trait_solver/catalog_admission/admit_catalog_snapshots",
    "type_checker/trait_solver/catalog_admission/admit_catalog_atoms",
    "type_checker/trait_solver/catalog_admission/admit_catalog_owners",
    "type_checker/trait_solver/catalog_admission/admit_catalog_parameters",
    "type_checker/trait_solver/catalog_admission/admit_catalog_callables",
    "type_checker/trait_solver/catalog_admission/admit_catalog_type_nodes",
    "type_checker/trait_solver/catalog_admission/admit_catalog_type_edges",
    "type_checker/trait_solver/catalog_admission/admit_catalog_type_roots",
    "type_checker/trait_solver/catalog_admission/admit_catalog_predicates",
    "type_checker/trait_solver/catalog_admission/admit_catalog_implementations",
    "type_checker/trait_solver/catalog_admission/admit_catalog_methods",
    "type_checker/trait_solver/catalog/build_atom_index",
    "type_checker/trait_solver/catalog/check_catalog_atom_identity",
    "type_checker/trait_solver/catalog/map_catalog_callables",
    "type_checker/trait_solver/catalog/map_catalog_definition_identities",
    "type_checker/trait_solver/catalog/check_catalog_method_targets",
    "type_checker/trait_solver/catalog/clear_implementation_index",
    "type_checker/trait_solver/catalog/build_implementation_index",
    "type_checker/trait_solver/catalog/check_implementation_coherence",
    "type_checker/trait_solver/catalog/freeze_trait_catalog",
];

pub(super) struct CatalogKernels {
    passes: Vec<PassData>,
}
impl CatalogKernels {
    pub fn load(device: &wgpu::Device) -> Result<Self> {
        let passes = CATALOG_KEYS
            .iter()
            .map(|key| passes_core::make_pass_data_from_shader_key_with_declared_dynamic_uniforms(device, key, "main", key, &PARAMS_BLOCKS))
            .collect::<Result<Vec<_>>>()?;
        Ok(Self { passes })
    }
    pub fn record(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        catalog: &FrozenCatalog,
        storage: &Arena,
        input: &Arena,
        output: &Arena,
    ) -> Result<()> {
        let count = |table: usize| catalog.slices[table].count;
        let work_rows = count(1).max(count(9));
        let buckets = crate::compiler::gpu_compiler::trait_solver::abi::buckets(work_rows)?;
        let clear_count = work_rows.max(buckets); // >=1, even for empty catalog.
        // Catalog admission runs one typed shader per table. Keep explicit phase
        // numbers: shader array index11 is an admission, not singleton freeze.
        let schedule: [(u32, u32); 22] = [
            (0, 1),
            (1, clear_count),
            (2, count(0)),
            (2, count(1)),
            (2, count(2)),
            (2, count(3)),
            (2, count(4)),
            (2, count(5)),
            (2, count(6)),
            (2, count(7)),
            (2, count(8)),
            (2, count(9)),
            // Publish implementation admission faults even without method rows.
            (2, count(10).max(u32::from(count(9) != 0))),
            (3, count(1)),
            (4, count(1)),
            (5, count(4)),
            (6, count(2).max(count(8)).max(count(9))),
            (7, count(10)),
            (8, clear_count),
            (9, count(9)),
            // One workgroup per implementation (catalog_index.slang).
            (10, count(9).checked_mul(256).ok_or_else(|| anyhow!("coherence rows overflow"))?),
            (11, 1),
        ];
        ensure!(
            self.passes.len() == schedule.len(),
            "catalog kernel/schedule inventory differs"
        );
        for (pass, (phase, count)) in self.passes.iter().zip(schedule) {
            let threads = if phase == 11 { 1 } else { 256 };
            record_phase(device, encoder, pass, phase, Span::new(0, count)?,
                threads, storage, input, output)?;
        }
        Ok(())
    }
}

/// Dispatch-local thread slots in the shared thread-scratch table
/// (shaders/shared/buffers/thread_scratch.slang). A pass that declares `thread_scratch`
/// dispatches at most this many rows at a time; slot = row - dispatch_first.
/// INTERIM: the table holds per-thread walker stacks moved out of local
/// memory. Trait solver on canonical type IDs (plan P7) deletes them.
pub(super) const THREAD_SCRATCH_SLOTS: u32 = 4096;
/// Kernels whose workgroup takes COHERENCE_CHECKERS thread-scratch slots
/// (from its dispatch-local group index): coherence runs one workgroup per
/// implementation (catalog_index.slang TS_COHERENCE_CHECKERS).
const GROUP_SLOT_KERNELS: &[&str] = &["type_checker/trait_solver/catalog/check_implementation_coherence"];
const COHERENCE_CHECKERS: u32 = 8;
/// uint4 cells per slot; THREAD_SCRATCH_CELLS in shaders/shared/buffers/thread_scratch.slang.
pub(super) const THREAD_SCRATCH_CELLS: u32 = 1808;

/// Each dispatch has immutable parameters. A separate compute pass is a WGPU
/// synchronization boundary; no following phase can observe a partially built
/// index. Extra boundaries between large chunks are harmless.
pub(super) fn record_phase(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    phase: u32,
    span: Span,
    threads: u32,
    catalog: &Arena,
    input: &Arena,
    output: &Arena,
) -> Result<()> {
    record_phase_with_proof(
        device, encoder, pass, phase, span, threads, catalog, input, output, None,
    )
}

#[derive(Clone, Copy)]
pub(super) struct ProofResources<'a> {
    pub storage: &'a Arena,
    pub epoch: u64,
    pub arena_id: u64,
    pub serial: u32,
}

/// The per-dispatch parameter blocks. Every evidence pass binds the ones it
/// declares with a dynamic offset, so one bind group serves every dispatch of
/// a pass over the same arenas and params-ring page.
const PARAMS_BLOCKS: [&str; 2] = ["trait_solver_params", "proof_store_params"];

/// The dynamic offsets of a pass's parameter blocks in binding order (the
/// order WGPU applies them): `offsets[i]` belongs to `PARAMS_BLOCKS[i]`, and a
/// block the pass does not declare is skipped.
fn params_offsets(pass: &PassData, offsets: [u32; 2]) -> Vec<u32> {
    let mut declared = PARAMS_BLOCKS
        .iter()
        .zip(offsets)
        .filter_map(|(name, offset)| {
            passes_core::bind_group::binding_index(pass, 0, name).map(|index| (index, offset))
        })
        .collect::<Vec<_>>();
    declared.sort_unstable_by_key(|&(index, _)| index);
    declared.into_iter().map(|(_, offset)| offset).collect()
}

/// One parameter block's buffer and dynamic offset: a params-ring record.
fn params_block(catalog: &Arena, words: [u32; 8]) -> Result<(wgpu::Buffer, u32)> {
    catalog.workspace().push_params(&words)
}

fn params_binding(buffer: &wgpu::Buffer) -> wgpu::BindingResource<'_> {
    params_binding_at(buffer, 0)
}

fn params_binding_at(buffer: &wgpu::Buffer, offset: u64) -> wgpu::BindingResource<'_> {
    wgpu::BindingResource::Buffer(wgpu::BufferBinding {
        buffer,
        offset,
        size: Some(super::workspace::params_block_size()),
    })
}

pub(super) fn record_phase_with_proof(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    phase: u32,
    span: Span,
    threads: u32,
    catalog: &Arena,
    input: &Arena,
    output: &Arena,
    proof: Option<ProofResources<'_>>,
) -> Result<()> {
    record_phase_with_resources(
        device, encoder, pass, phase, span, threads, catalog, input, output, proof, None, None,
    )
}

fn record_phase_with_resources(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    phase: u32,
    span: Span,
    threads: u32,
    catalog: &Arena,
    input: &Arena,
    output: &Arena,
    proof: Option<ProofResources<'_>>,
    recipes: Option<&Arena>,
    layout_work: Option<&Arena>,
) -> Result<()> {
    ensure!(
        pass.thread_group_size == [threads, 1, 1],
        "evidence shader thread size differs from dispatch contract"
    );
    ensure!(
        matches!(threads, 1 | 256),
        "unsupported evidence dispatch width"
    );
    if span.count == 0 {
        return Ok(());
    }
    let limits = device.limits();
    ensure!(
        threads <= limits.max_compute_invocations_per_workgroup
            && threads <= limits.max_compute_workgroup_size_x,
        "evidence kernel exceeds device workgroup limit"
    );
    // Current shader 2D flattening has fixed x width 65_535*256. Use bounded
    // one-dimensional chunks, valid even on devices with a smaller group limit.
    let max_groups = limits.max_compute_workgroups_per_dimension.min(65_535);
    ensure!(max_groups != 0, "device exposes no compute dispatch groups");
    let max_rows = max_groups
        .checked_mul(threads)
        .expect("bounded group product");
    let scratch = if passes_core::bind_group::declares_binding(pass, 0, "thread_scratch") {
        Some(thread_scratch(catalog)?)
    } else {
        None
    };
    // A group-slot kernel takes one slot per workgroup.
    let max_rows = if scratch.is_some() && GROUP_SLOT_KERNELS.contains(&pass.shader_id.as_str()) {
        max_rows.min(THREAD_SCRATCH_SLOTS / COHERENCE_CHECKERS * threads)
    } else if scratch.is_some() {
        max_rows.min(THREAD_SCRATCH_SLOTS)
    } else {
        max_rows
    };
    let mut done = 0u32;
    while done < span.count {
        let count = (span.count - done).min(max_rows);
        let params = [
            span.first.checked_add(done).expect("checked span"),
            count,
            catalog.logical_words,
            input.logical_words,
            output.logical_words,
            phase,
            // The sidecar arenas bind their whole retained allocation (stable
            // bind-group identity across programs); kernels take each logical
            // extent from these words instead of the binding size.
            recipes.map_or(0, |recipes| recipes.logical_words),
            layout_work.map_or(0, |work| work.logical_words),
        ];
        let (uniform, uniform_offset) = params_block(catalog, params)?;
        // Some phases optimize an unused resource out. The existing reflected
        // constructor selects active names and rejects unknown required names.
        // These four resources are always distinct physical allocations.
        let proof_uniform = if let Some(proof) = proof {
            Some(params_block(catalog, proof_params_words(proof, phase))?)
        } else {
            None
        };
        let offsets = params_offsets(
            pass,
            [uniform_offset, proof_uniform.as_ref().map_or(0, |(_, offset)| *offset)],
        );
        let mut resources = vec![
            ("trait_solver_params", params_binding(&uniform)),
            (
                "trait_solver_catalog",
                catalog.buffer.as_entire_binding(),
            ),
            ("trait_solver_batch", input.buffer.as_entire_binding()),
            ("trait_solver_output", output.buffer.as_entire_binding()),
        ];
        if let Some(proof) = proof {
            resources.push((
                "trait_solver_proof_store",
                proof.storage.buffer.as_entire_binding(),
            ));
            resources.push((
                "proof_store_params",
                params_binding(&proof_uniform.as_ref().expect("proof parameters").0),
            ));
        }
        if let Some(recipes) = recipes {
            resources.push((
                "trait_solver_native_recipes",
                recipes.buffer.as_entire_binding(),
            ));
        }
        if let Some(work) = layout_work {
            resources.push(("trait_solver_native_layout_work", work.buffer.as_entire_binding()));
        }
        if let Some(scratch) = &scratch {
            resources.push(("thread_scratch", scratch.as_entire_binding()));
        }
        let bindings = passes_core::bind_group::create_bind_group_from_bindings(
            device,
            Some("trait_solver.bindings"),
            pass,
            0,
            &resources,
        )?;
        dispatch_pass(encoder, pass, &bindings, &offsets, Launch::Direct((count.div_ceil(threads), 1, 1)));
        done += count;
    }
    Ok(())
}

/// Walker frames live in one retained table shared by every dispatch that
/// declares it: fixed size, so its binding never changes. Each chunk owns all
/// slots.
fn thread_scratch(catalog: &Arena) -> Result<LaniusBuffer<u32>> {
    catalog
        .workspace()
        .shared("trait_solver.thread_scratch")
        .buffer(THREAD_SCRATCH_SLOTS * THREAD_SCRATCH_CELLS * 4, wgpu::BufferUsages::STORAGE, None)
}

#[derive(Clone, Copy)]
enum Launch<'a> {
    Direct((u32, u32, u32)),
    Indirect(&'a wgpu::Buffer, u64),
}

/// One dispatch in its own compute pass.
fn dispatch_pass(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bindings: &wgpu::BindGroup,
    offsets: &[u32],
    launch: Launch<'_>,
) {
    // Inside a deferred batch (run_solver_attempt), the dispatch joins the
    // batch's one compute pass.
    let deferred = match launch {
        Launch::Direct(groups) => {
            passes_core::defer_compute_direct_with_offsets(pass, bindings, groups, offsets, &pass.shader_id)
        }
        Launch::Indirect(buffer, offset) => {
            passes_core::defer_compute_indirect(pass, bindings, buffer, offset, offsets, &pass.shader_id)
        }
    };
    if deferred {
        return;
    }
    passes_core::flush_deferred_compute(encoder);
    let capture_launch = match launch {
        Launch::Direct(groups) => dispatch_capture::CaptureLaunch::Direct(groups),
        Launch::Indirect(buffer, offset) => dispatch_capture::CaptureLaunch::Indirect(buffer, offset),
    };
    // `LANIUS_CAPTURE` support (tools/cpu_kernel_replay.py).
    let captured = dispatch_capture::debug_capture_begin(
        encoder,
        &pass.shader_id,
        pass,
        bindings,
        offsets,
        capture_launch,
    );
    {
        let mut compute = passes_core::begin_counted_compute_pass(
            encoder,
            &wgpu::ComputePassDescriptor {
                label: Some(&pass.shader_id),
                timestamp_writes: None,
            },
        );
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, Some(bindings), offsets);
        passes_core::record_compute_dispatch();
        if !crate::gpu::passes_core::debug_operation_skipped() {
            match launch {
                Launch::Direct(groups) => compute.dispatch_workgroups(groups.0, groups.1, groups.2),
                Launch::Indirect(buffer, offset) => compute.dispatch_workgroups_indirect(buffer, offset),
            }
        }
    }
    dispatch_capture::debug_capture_end(encoder, captured);
    // Profiled jobs need one timestamp per recorded dispatch.
    crate::gpu::timer::stamp_active_operation(encoder, pass.shader_id.clone());
}

fn proof_params_words(proof: ProofResources<'_>, phase: u32) -> [u32; 8] {
    [
        proof.storage.logical_words,
        proof.epoch as u32,
        (proof.epoch >> 32) as u32,
        proof.arena_id as u32,
        (proof.arena_id >> 32) as u32,
        proof.serial,
        phase,
        0,
    ]
}

// These literal keys also register the batch entry artifacts with the build.
// Call reduction (18) and the batch receipt (19) run at the solver's finish
// (PROOF_KEYS).
const BATCH_KEYS: [&str; 4] = [
    "type_checker/trait_solver/batches/initialize_trait_batch",
    "type_checker/trait_solver/batches/validate_retained_evidence",
    "type_checker/trait_solver/batches/validate_batch_contexts",
    "type_checker/trait_solver/batches/build_batch_assumption_index",
];
// Table IDs are paired with literal keys. The order puts predicate backlink
// checks after both sides of their ownership relation have been admitted.
const BATCH_ADMISSION_KEYS: [(&[usize], &str); 7] = [
    // The value graph's batch rows in one dispatch (phase 33).
    (&[1, 5, 6, 7], "type_checker/trait_solver/batches/admit_batch_value_rows"),
    (&[11], "type_checker/trait_solver/batches/admit_batch_environments"),
    (&[12], "type_checker/trait_solver/batches/admit_batch_bindings"),
    (&[13], "type_checker/trait_solver/batches/admit_batch_contexts"),
    (&[15], "type_checker/trait_solver/batches/admit_batch_calls"),
    (&[14, 16], "type_checker/trait_solver/batches/check_batch_predicate_backlinks"),
    (&[17], "type_checker/trait_solver/batches/admit_batch_evidence"),
];
pub(super) struct BatchKernels {
    passes: Vec<PassData>,
    admit_rows: Vec<PassData>,
}
impl BatchKernels {
    pub fn load(device: &wgpu::Device) -> Result<Self> {
        let mut tables = BATCH_ADMISSION_KEYS.iter()
            .flat_map(|(tables, _)| tables.iter().copied())
            .collect::<Vec<_>>();
        tables.sort_unstable();
        ensure!(tables == super::BATCH_INPUT_TABLES,
            "batch shader tables differ from the retained input plan");
        let passes = BATCH_KEYS
            .iter()
            .map(|key| passes_core::make_pass_data_from_shader_key_with_declared_dynamic_uniforms(device, key, "main", key, &PARAMS_BLOCKS))
            .collect::<Result<Vec<_>>>()?;
        let admit_rows = BATCH_ADMISSION_KEYS
            .iter()
            .map(|(_, key)| passes_core::make_pass_data_from_shader_key_with_declared_dynamic_uniforms(device, key, "main", key, &PARAMS_BLOCKS))
            .collect::<Result<Vec<_>>>()?;
        Ok(Self { passes, admit_rows })
    }
    pub fn record_initialize(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        catalog: &Arena,
        input: &Arena,
        output: &Arena,
        proof: ProofResources<'_>,
    ) -> Result<()> {
        record_phase_with_proof(
            device,
            encoder,
            &self.passes[0],
            12,
            Span::new(0, 1)?,
            // One workgroup (admission_group.slang).
            256,
            catalog,
            input,
            output,
            Some(proof),
        )
    }

    pub fn record_before_solver(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        plan: &BatchPlan,
        catalog: &Arena,
        input: &Arena,
        output: &Arena,
        proof: ProofResources<'_>,
    ) -> Result<()> {
        ensure!(
            self.passes.len() == BATCH_KEYS.len()
                && self.admit_rows.len() == BATCH_ADMISSION_KEYS.len(),
            "batch kernel/schedule inventory differs"
        );
        // Complete admission of every new input row precedes any consumer.
        // dispatch_first includes the immutable catalog prefix for mixed tables.
        // Preserved old suffix rows were admitted in earlier successful receipts.
        // A kernel of several tables runs over their whole batch suffixes, in
        // table order, when any of them has new rows.
        for ((tables, _), pass) in BATCH_ADMISSION_KEYS.iter().zip(&self.admit_rows) {
            let span = match tables {
                [table] => plan.input_spans[*table],
                _ if tables.iter().all(|&t| plan.input_spans[t].count == 0) => Span::default(),
                _ => Span::new(0, tables.iter().try_fold(0u32, |sum, &t| sum.checked_add(plan.suffix_rows[t]))
                    .ok_or_else(|| anyhow::anyhow!("combined batch rows overflow"))?)?,
            };
            record_phase_with_proof(
                device,
                encoder,
                pass,
                32 + tables[0] as u32,
                span,
                256,
                catalog,
                input,
                output,
                Some(proof),
            )?;
        }
        let spans = [plan.input_spans[17], plan.contexts, plan.assumption_index];
        for (offset, span) in spans.into_iter().enumerate() {
            let phase = 13 + offset as u32;
            record_phase_with_proof(
                device,
                encoder,
                &self.passes[offset + 1],
                phase,
                span,
                256,
                catalog,
                input,
                output,
                Some(proof),
            )?;
        }
        Ok(())
    }
}

/// The planner of the recorded steps (plan_proof_wave.slang). Its
/// dispatch_first selects the step plan (0) or the finish (1).
const PLAN_PHASE: u32 = 80;
/// One thread-scratch slot per lane: PSW_LANE_GROUP in proof_work.slang.
const LANE_THREADS: u32 = 64;
// Literal artifact inventory, in the order of one step and then the finish:
// phase, key, workgroup threads.
const PROOF_KEYS: [(u32, &str, u32); 8] = [
    (PLAN_PHASE, "type_checker/trait_solver/proof_frontier/plan_proof_wave", 1),
    (82, "type_checker/trait_solver/proof_frontier/build_proof_goals", LANE_THREADS),
    (83, "type_checker/trait_solver/proof_frontier/select_proof_assumptions", LANE_THREADS),
    (84, "type_checker/trait_solver/proof_frontier/select_proof_implementations", LANE_THREADS),
    (85, "type_checker/trait_solver/proof_frontier/write_proof_rows", LANE_THREADS),
    (86, "type_checker/trait_solver/proof_frontier/publish_proof_roots", 256),
    // The finish's batch stages: call reduction, then the receipt.
    (18, "type_checker/trait_solver/batches/reduce_batch_calls", 256),
    (19, "type_checker/trait_solver/batches/finalize_trait_batch", 256),
];
const PLANNER: usize = 0;
const LANES: std::ops::Range<usize> = 1..5;
const FINISH: std::ops::Range<usize> = 5..8;

/// State words and values of the recorded steps (proof_work.slang, PSW_*).
pub(super) mod wave {
    pub const STOP: usize = 0;
    pub const ROOTS: usize = 3;
    pub const OBLIGATIONS_FIRST: usize = 6;
    /// Indirect arguments, three words each: the lanes of a step, then the
    /// finish's root publication, call reduction and receipt.
    pub const LANE_ARGS: u64 = 8;
    pub const FINISH_ARGS: [u64; 3] = [12, 20, 24];
    pub const CALLS_FIRST: usize = 17;
    pub const CALLS_COUNT: usize = 18;
    /// Words the host reads back.
    pub const READ_WORDS: u32 = 32;
    pub const RUNNING: u32 = 0;
    pub const STOPPED: u32 = 1;
    /// Every Work ran, and the finish published the roots and the receipt.
    pub const DONE: u32 = 2;
}

/// The solver state of one attempt. The planner writes it and the host reads
/// it back after the recorded steps. One shared role: an attempt reads its
/// state back before the next attempt rewrites it.
pub(super) fn wave_state(catalog: &Arena, obligations: Span, calls: Span) -> Result<LaniusBuffer<u32>> {
    let mut words = [0u32; wave::READ_WORDS as usize];
    words[wave::ROOTS] = obligations.count;
    words[wave::OBLIGATIONS_FIRST] = obligations.first;
    words[wave::CALLS_FIRST] = calls.first;
    words[wave::CALLS_COUNT] = calls.count;
    catalog.workspace().shared("trait_solver.solver_wave").buffer(
        wave::READ_WORDS,
        wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::INDIRECT | wgpu::BufferUsages::COPY_SRC,
        Some(&words),
    )
}

/// One dispatch of an attempt with its bindings and parameter offsets. Every
/// step records the same dispatches: the planner chooses their rows.
struct WaveDispatch {
    pass: usize,
    bindings: wgpu::BindGroup,
    offsets: Vec<u32>,
    /// Byte offset of the indirect arguments in the wave state, or None for
    /// one direct workgroup.
    indirect: Option<u64>,
}
/// The dispatches of one attempt over one packet's arenas.
pub(super) struct WaveProgram {
    state: LaniusBuffer<u32>,
    /// The planner, then the four lane kernels.
    step: Vec<WaveDispatch>,
    /// The planner's finish, the root publication and the batch stages.
    finish: Vec<WaveDispatch>,
}

pub(super) struct ProofKernels {
    passes: Vec<PassData>,
}
impl ProofKernels {
    pub fn load(device: &wgpu::Device) -> Result<Self> {
        let passes = PROOF_KEYS
            .iter()
            .map(|(_, key, _)| {
                passes_core::make_pass_data_from_shader_key_with_declared_dynamic_uniforms(
                    device, key, "main", key, &PARAMS_BLOCKS,
                )
            })
            .collect::<Result<Vec<_>>>()?;
        for (pass, (_, key, threads)) in passes.iter().zip(PROOF_KEYS) {
            ensure!(
                pass.thread_group_size == [threads, 1, 1],
                "proof kernel {key} thread size differs from dispatch contract"
            );
        }
        Ok(Self { passes })
    }

    /// The bindings of one attempt's dispatches.
    #[allow(clippy::too_many_arguments)]
    pub fn wave_program(
        &self,
        device: &wgpu::Device,
        state: &LaniusBuffer<u32>,
        obligations: Span,
        calls: Span,
        catalog: &Arena,
        input: &Arena,
        output: &Arena,
        proof: ProofResources<'_>,
    ) -> Result<WaveProgram> {
        let scratch = thread_scratch(catalog)?;
        let dispatch = |pass: usize, span: Span, indirect: Option<u64>| -> Result<WaveDispatch> {
            let phase = PROOF_KEYS[pass].0;
            let params = [
                span.first,
                span.count,
                catalog.logical_words,
                input.logical_words,
                output.logical_words,
                phase,
                0,
                0,
            ];
            let (uniform, uniform_offset) = params_block(catalog, params)?;
            let (proof_uniform, proof_offset) = params_block(catalog, proof_params_words(proof, phase))?;
            let resources = [
                ("trait_solver_params", params_binding(&uniform)),
                ("trait_solver_catalog", catalog.buffer.as_entire_binding()),
                ("trait_solver_batch", input.buffer.as_entire_binding()),
                ("trait_solver_output", output.buffer.as_entire_binding()),
                ("trait_solver_proof_store", proof.storage.buffer.as_entire_binding()),
                ("proof_store_params", params_binding(&proof_uniform)),
                ("thread_scratch", scratch.as_entire_binding()),
                // The planner writes the state and the lanes read it.
                ("trait_solver_wave_plan", state.as_entire_binding()),
                ("trait_solver_wave", state.as_entire_binding()),
            ];
            let bindings = passes_core::bind_group::create_bind_group_from_bindings(
                device,
                Some("trait_solver.wave_bindings"),
                &self.passes[pass],
                0,
                &resources,
            )?;
            Ok(WaveDispatch {
                pass,
                bindings,
                offsets: params_offsets(&self.passes[pass], [uniform_offset, proof_offset]),
                indirect: indirect.map(|word| word * 4),
            })
        };
        let lanes = Span::new(0, THREAD_SCRATCH_SLOTS)?;
        let mut step = vec![dispatch(PLANNER, Span::new(0, 1)?, None)?];
        for pass in LANES {
            step.push(dispatch(pass, lanes, Some(wave::LANE_ARGS))?);
        }
        let mut finish = vec![dispatch(PLANNER, Span::new(1, 1)?, None)?];
        let spans = [obligations, calls, Span::new(0, 1)?];
        for ((pass, span), args) in FINISH.zip(spans).zip(wave::FINISH_ARGS) {
            finish.push(dispatch(pass, span, Some(args))?);
        }
        Ok(WaveProgram { state: state.clone(), step, finish })
    }

    /// Records `steps` steps and the finish in one compute pass.
    pub fn record_wave(&self, encoder: &mut wgpu::CommandEncoder, program: &WaveProgram, steps: u32) {
        let batch = passes_core::DeferredComputeBatchGuard::begin(
            passes_core::compute_pass_batching_allowed(crate::gpu::timer::operation_capture_active())
                && !passes_core::debug_operation_limited()
                && crate::gpu::dispatch_capture::capture_pass().is_none(),
            "trait_solver.solver_wave",
        );
        let recorded = std::iter::repeat_n(&program.step, steps as usize).chain(std::iter::once(&program.finish));
        for dispatch in recorded.flatten() {
            let launch = match dispatch.indirect {
                Some(offset) => Launch::Indirect(&program.state, program.state.byte_offset + offset),
                None => Launch::Direct((1, 1, 1)),
            };
            dispatch_pass(encoder, &self.passes[dispatch.pass], &dispatch.bindings, &dispatch.offsets, launch);
        }
        passes_core::flush_deferred_compute(encoder);
        drop(batch);
    }
}

// Recipe roots are admitted with the catalog graph before this sidecar is
// frozen. There is one load and one complete admission per program owner.
const RECIPE_KEYS: [&str; 5] = [
    "type_checker/trait_solver/native_layout/initialize_recipes",
    "type_checker/trait_solver/native_layout/clear_recipe_map",
    "type_checker/trait_solver/native_layout/admit_native_layout_recipes",
    "type_checker/trait_solver/native_layout/admit_native_layout_recipe_groups",
    "type_checker/trait_solver/native_layout/freeze_native_layout_recipes",
];

pub(super) struct RecipeKernels {
    passes: Vec<PassData>,
}
impl RecipeKernels {
    pub fn load(device: &wgpu::Device) -> Result<Self> {
        let passes = RECIPE_KEYS.iter()
            .map(|key| passes_core::make_pass_data_from_shader_key_with_declared_dynamic_uniforms(device, key, "main", key, &PARAMS_BLOCKS))
            .collect::<Result<Vec<_>>>()?;
        Ok(Self { passes })
    }
    pub fn record(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        catalog: &FrozenCatalog,
        storage: &Arena,
        input: &Arena,
        output: &Arena,
        recipes: &Arena,
    ) -> Result<()> {
        let sidecar = &catalog.native_layout;
        let schedule = [
            (0u32, 1u32, 1u32),
            (1, sidecar.atom_map.count, 256),
            (2, sidecar.recipes.count, 256),
            (3, sidecar.groups.count, 256),
            (4, 1, 1),
        ];
        ensure!(self.passes.len() == schedule.len(), "recipe kernel/schedule inventory differs");
        for (pass, (phase, count, threads)) in self.passes.iter().zip(schedule) {
            record_phase_with_resources(device, encoder, pass, phase, Span::new(0, count)?,
                threads, storage, input, output, None, Some(recipes), None)?;
        }
        Ok(())
    }
}

/// Retained lazily by the program owner; body replay never reloads the pipeline.
pub(super) struct NativeLayoutKernel { pass: PassData }
impl NativeLayoutKernel {
    pub fn load(device: &wgpu::Device) -> Result<Self> {
        let key = "type_checker/trait_solver/native_layout/materialize_proof_value";
        Ok(Self { pass: passes_core::make_pass_data_from_shader_key_with_declared_dynamic_uniforms(device, key, "main", key, &PARAMS_BLOCKS)? })
    }
    pub fn record(&self, device: &wgpu::Device, encoder: &mut wgpu::CommandEncoder,
        catalog: &Arena, input: &Arena, output: &Arena, proof: ProofResources<'_>,
        recipes: &Arena, work: &Arena) -> Result<()> {
        record_phase_with_resources(device, encoder, &self.pass, 5, Span::new(0, 1)?, 1,
            catalog, input, output, Some(proof), Some(recipes), Some(work))
    }
}

/// Read-only accepted-proof projection. The exclusive temporary work arena
/// shares the existing reflected work binding; native-layout recipes are not
/// bound or consulted by this kernel.
pub(super) struct ImplementationApplicationKernel { pass: PassData }
impl ImplementationApplicationKernel {
    pub fn load(device: &wgpu::Device) -> Result<Self> {
        let key = "type_checker/trait_solver/implementation_application/project_proof_implementation_application";
        Ok(Self { pass: passes_core::make_pass_data_from_shader_key_with_declared_dynamic_uniforms(
            device, key, "main", key, &PARAMS_BLOCKS)? })
    }
    pub fn record(&self, device: &wgpu::Device, encoder: &mut wgpu::CommandEncoder,
        catalog: &Arena, input: &Arena, output: &Arena, proof: ProofResources<'_>, work: &Arena,
    ) -> Result<()> {
        record_phase_with_resources(device, encoder, &self.pass, 6, Span::new(0, 1)?, 1,
            catalog, input, output, Some(proof), None, Some(work))
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn thread_scratch_layout_matches_shader() {
        let shader = include_str!("../../../../../../../shaders/shared/buffers/thread_scratch.slang");
        let cells = format!("THREAD_SCRATCH_CELLS = {}u;", super::THREAD_SCRATCH_CELLS);
        assert!(shader.contains(&cells), "host and shader disagree on {cells}");
        assert!(shader.contains("THREAD_SCRATCH_GROUP = 32u;"));
        assert_eq!(super::THREAD_SCRATCH_SLOTS % 32, 0, "slots are whole groups");
    }
}
