use anyhow::{Result, anyhow, ensure};

use super::{
    super::{abi::Span, catalog::FrozenCatalog, proof_store::PROOF_STORE_TABLES},
    BatchPlan,
    arena::Arena,
};
use crate::gpu::{
    buffers::LaniusBuffer,
    dispatch_capture,
    passes_core::{self, PassData},
};

// Ordinary literals are required by laniusc-shaders/build.rs artifact discovery.
const CATALOG_KEYS: [&str; 23] = [
    "type_checker/trait_solver/entries/00_initialize",
    "type_checker/trait_solver/entries/01_clear_atom_index",
    "type_checker/trait_solver/entries/02_00_admit_snapshots",
    "type_checker/trait_solver/entries/02_01_admit_atoms",
    "type_checker/trait_solver/entries/02_02_admit_owners",
    "type_checker/trait_solver/entries/02_03_admit_parameters",
    "type_checker/trait_solver/entries/02_04_admit_callables",
    "type_checker/trait_solver/entries/02_05_admit_nodes",
    "type_checker/trait_solver/entries/02_06_admit_edges",
    "type_checker/trait_solver/entries/02_07_admit_roots",
    "type_checker/trait_solver/entries/02_08_admit_predicates",
    "type_checker/trait_solver/entries/02_09_admit_implementation_heads",
    "type_checker/trait_solver/entries/02_09_admit_implementation_members",
    "type_checker/trait_solver/entries/02_10_admit_methods",
    "type_checker/trait_solver/entries/03_build_atom_index",
    "type_checker/trait_solver/entries/04_check_atom_identity",
    "type_checker/trait_solver/entries/05_map_callables",
    "type_checker/trait_solver/entries/06_map_definition_identities",
    "type_checker/trait_solver/entries/07_check_method_targets",
    "type_checker/trait_solver/entries/08_clear_implementation_index",
    "type_checker/trait_solver/entries/09_build_implementation_index",
    "type_checker/trait_solver/entries/10_check_coherence",
    "type_checker/trait_solver/entries/11_freeze_catalog",
];

// 02_09 admits implementations in two kernels split at head coverage. The
// members kernel runs only while the catalog is still building, so every row
// it sees has passed its head; the two run chunk by chunk, in the one-kernel
// order (a failure in one chunk stops every later chunk).
const IMPLEMENTATION_HEADS: usize = 11;

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
        let buckets = super::super::abi::buckets(work_rows)?;
        let clear_count = work_rows.max(buckets); // >=1, even for empty catalog.
        // Phase02 is one typed shader per catalog table. Keep explicit phase
        // numbers: shader array index11 is an admission, not singleton freeze.
        let schedule: [(u32, u32); 23] = [
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
            (2, count(9)),
            (2, count(10)),
            (3, count(1)),
            (4, count(1)),
            (5, count(4)),
            (6, count(2).max(count(8)).max(count(9))),
            (7, count(10)),
            (8, clear_count),
            (9, count(9)),
            (10, count(9)),
            (11, 1),
        ];
        ensure!(
            self.passes.len() == schedule.len(),
            "catalog kernel/schedule inventory differs"
        );
        ensure!(
            CATALOG_KEYS[IMPLEMENTATION_HEADS].ends_with("02_09_admit_implementation_heads")
                && CATALOG_KEYS[IMPLEMENTATION_HEADS + 1].ends_with("02_09_admit_implementation_members"),
            "implementation admission kernels moved in the catalog inventory"
        );
        for (index, (pass, (phase, count))) in self.passes.iter().zip(schedule).enumerate() {
            if index == IMPLEMENTATION_HEADS + 1 {
                continue; // recorded with its heads below
            }
            let threads = if matches!(phase, 0 | 11) { 1 } else { 256 };
            let (steps, chunk) = if index == IMPLEMENTATION_HEADS {
                (&self.passes[index..index + 2], THREAD_SCRATCH_SLOTS)
            } else {
                (std::slice::from_ref(pass), count.max(1))
            };
            let mut done = 0u32;
            while done < count {
                let rows = (count - done).min(chunk);
                for step in steps {
                    record_phase(
                        device,
                        encoder,
                        step,
                        phase,
                        Span::new(done, rows)?,
                        threads,
                        storage,
                        input,
                        output,
                    )?;
                }
                done += rows;
            }
        }
        Ok(())
    }
}

/// Dispatch-local thread slots in the shared thread-scratch table
/// (shaders/thread_scratch.slang). A pass that declares `thread_scratch`
/// dispatches at most this many rows at a time; slot = row - dispatch_first.
/// INTERIM: the table holds per-thread walker stacks moved out of local
/// memory. Trait solver on canonical type IDs (plan P7) deletes them.
pub(super) const THREAD_SCRATCH_SLOTS: u32 = 4096;
/// uint4 cells per slot; THREAD_SCRATCH_CELLS in shaders/thread_scratch.slang.
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
    wgpu::BindingResource::Buffer(wgpu::BufferBinding {
        buffer,
        offset: 0,
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
        device, encoder, pass, phase, span, threads, catalog, input, output, proof, None, None, None,
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
    demand: Option<&LaniusBuffer<u32>>,
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
    // Audit lanes take no scratch slot, so they run over their whole span.
    let max_rows = if scratch.is_some() && !WHOLE_SPAN_KERNELS.contains(&pass.shader_id.as_str()) {
        max_rows.min(THREAD_SCRATCH_SLOTS)
    } else {
        max_rows
    };
    let audit = match proof {
        Some(proof) if passes_core::bind_group::declares_binding(pass, 0, COMMIT_AUDIT) => {
            Some(commit_audit(catalog, proof.storage)?)
        }
        _ => None,
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
        if let Some(demand) = demand {
            resources.push(("trait_solver_proof_demand", demand.as_entire_binding()));
        }
        if let Some(audit) = &audit {
            resources.push((COMMIT_AUDIT, audit.as_entire_binding()));
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

/// The commit audits' shared words (proof_commit_audit.slang): a header, then
/// one claim word per two words of the proof arena. The role is shared: a
/// stage's audit lanes and committing thread are recorded together, and
/// the thread retires the lanes' claim tag.
const COMMIT_AUDIT: &str = "trait_solver_commit_audit";
const COMMIT_AUDIT_HEADER_WORDS: u32 = 16;
pub(super) fn commit_audit(catalog: &Arena, proof: &Arena) -> Result<LaniusBuffer<u32>> {
    let claims = u32::try_from(proof.buffer.byte_size / 8)?;
    let words = claims
        .checked_add(COMMIT_AUDIT_HEADER_WORDS + 1)
        .ok_or_else(|| anyhow!("commit audit table overflow"))?;
    catalog.workspace().shared("trait_solver.commit_audit").buffer(
        words,
        wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
        None,
    )
}
/// Zeroes the audit header for a solver attempt, keeping its epoch word:
/// claim words of earlier attempts carry tags up to that epoch.
pub(super) fn reset_commit_audit(catalog: &Arena, proof: ProofResources<'_>) -> Result<()> {
    let audit = commit_audit(catalog, proof.storage)?;
    let zeros = [0u8; (COMMIT_AUDIT_HEADER_WORDS as usize - 1) * 4];
    audit.write(catalog.workspace().queue(), 4, &zeros);
    Ok(())
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
// point (PROOF_KEYS).
const BATCH_KEYS: [&str; 4] = [
    "type_checker/trait_solver/entries/12_initialize_batch",
    "type_checker/trait_solver/entries/13_validate_retained_evidence",
    "type_checker/trait_solver/entries/14_validate_contexts",
    "type_checker/trait_solver/entries/15_build_assumption_index",
];
// Table IDs are paired with literal keys so the phase contract is checked
// against BatchPlan's ordered input inventory before loading any batch shader.
const BATCH_ADMISSION_KEYS: [(usize, &str); 11] = [
    (1, "type_checker/trait_solver/entries/32_01_admit_atoms"),
    (5, "type_checker/trait_solver/entries/32_05_admit_nodes"),
    (6, "type_checker/trait_solver/entries/32_06_admit_edges"),
    (7, "type_checker/trait_solver/entries/32_07_admit_roots"),
    (
        11,
        "type_checker/trait_solver/entries/32_11_admit_environments",
    ),
    (
        12,
        "type_checker/trait_solver/entries/32_12_admit_bindings",
    ),
    (
        13,
        "type_checker/trait_solver/entries/32_13_admit_contexts",
    ),
    (
        14,
        "type_checker/trait_solver/entries/32_14_admit_assumptions",
    ),
    (
        15,
        "type_checker/trait_solver/entries/32_15_admit_calls",
    ),
    (
        16,
        "type_checker/trait_solver/entries/32_16_admit_obligations",
    ),
    (
        17,
        "type_checker/trait_solver/entries/32_17_admit_evidence",
    ),
];
pub(super) struct BatchKernels {
    passes: Vec<PassData>,
    admit_rows: Vec<PassData>,
}
impl BatchKernels {
    pub fn load(device: &wgpu::Device) -> Result<Self> {
        ensure!(
            BATCH_ADMISSION_KEYS
                .iter()
                .map(|(table, _)| *table)
                .eq(super::BATCH_INPUT_TABLES),
            "batch shader table order differs from the retained input plan"
        );
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
            1,
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
        for ((table, _), pass) in BATCH_ADMISSION_KEYS.iter().zip(&self.admit_rows) {
            record_phase_with_proof(
                device,
                encoder,
                pass,
                32 + *table as u32,
                plan.input_spans[*table],
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

// Literal artifact inventory. Stage numbers are independent of chronological
// order: original Work initialization precedes its normalization stages.
/// PPS_SELECT_PHASE_EXACT and PPS_SELECT_PHASE_GENERIC in
/// proof_frontier_selection.slang.
const SELECTION_PHASE: u32 = 53;
const GENERIC_SELECTION_PHASE: u32 = 65;
/// PPS_WALK_PHASE_WORK, PPS_WALK_PHASE_PROOFS and
/// PPS_WALK_PHASE_PREREQUISITES in proof_substitution_walk.slang.
const SUBSTITUTION_PHASE: u32 = 54;
const IMPLEMENTATION_PROOF_PHASE: u32 = 59;
const PREREQUISITE_PHASE: u32 = 66;
const WALK_GOALS: &str = "type_checker/trait_solver/entries/54_walk_substitution_goals";
const WALK_ROOTS: &str = "type_checker/trait_solver/entries/54_walk_substitution_roots";
const WALK_BINDINGS: &str = "type_checker/trait_solver/entries/54_walk_substitution_bindings";
const SELECT_IMPLEMENTATIONS: &str = "type_checker/trait_solver/entries/53_select_implementations";
/// Exact implementation match, caller assumption search, generic
/// implementation match (the first kernel again, as phase 65), then the
/// finish (proof_frontier_selection.slang).
const SELECTION_STEPS: [(&str, u32); 4] = [
    (SELECT_IMPLEMENTATIONS, SELECTION_PHASE),
    ("type_checker/trait_solver/entries/53_select_assumptions", SELECTION_PHASE),
    (SELECT_IMPLEMENTATIONS, GENERIC_SELECTION_PHASE),
    ("type_checker/trait_solver/entries/53_select_work", SELECTION_PHASE),
];
/// Up to the head match, the head's root unification, then the bindings
/// (proof_substitution_walk.slang).
const SUBSTITUTION_STEPS: [(&str, u32); 3] = [
    (WALK_GOALS, SUBSTITUTION_PHASE),
    (WALK_ROOTS, SUBSTITUTION_PHASE),
    (WALK_BINDINGS, SUBSTITUTION_PHASE),
];
/// The substitution walk's three dispatches, then the root unification kernel
/// again (phase 66) for the proof's fixed prerequisite checks.
const IMPLEMENTATION_PROOF_STEPS: [(&str, u32); 4] = [
    (WALK_GOALS, IMPLEMENTATION_PROOF_PHASE),
    (WALK_ROOTS, IMPLEMENTATION_PROOF_PHASE),
    (WALK_BINDINGS, IMPLEMENTATION_PROOF_PHASE),
    (WALK_ROOTS, PREREQUISITE_PHASE),
];
const BINDING_ROWS: &str = "type_checker/trait_solver/entries/54_admit_binding_rows";
const ASSUMPTION_PROOFS: &str = "type_checker/trait_solver/entries/59_admit_assumption_proofs";
const PROOF_EDGE_ROWS: &str = "type_checker/trait_solver/entries/59_admit_proof_edge_rows";
/// The GPU planner of recorded solver rounds (proof_solver_wave.slang).
const WAVE_PLAN_PHASE: u32 = 70;
/// Normalization row counts (proof_demand.slang): original Works (phase 41)
/// and prerequisite Works (phase 42).
pub(super) const COUNT_ORIGINAL_NORMALIZATION: u32 = 67;
pub(super) const COUNT_PREREQUISITE_NORMALIZATION: u32 = 68;
const AUDIT_TERMS: &str = "type_checker/trait_solver/entries/45_audit_normalized_terms";
const COMMIT_TERMS: &str = "type_checker/trait_solver/entries/45_commit_normalized_terms";
const AUDIT_GOALS: &str = "type_checker/trait_solver/entries/47_audit_normalized_goals";
const COMMIT_GOALS: &str = "type_checker/trait_solver/entries/47_commit_normalized_goals";
const MARK_GOALS: &str = "type_checker/trait_solver/entries/47_mark_normalized_goals";
const AUDIT_WORK: &str = "type_checker/trait_solver/entries/50_audit_work";
const RESERVE_GOAL_INDEX: &str = "type_checker/trait_solver/entries/50_reserve_goal_index";
const WRITE_GOAL_INDEX: &str = "type_checker/trait_solver/entries/50_write_goal_index";
const COMMIT_WORK: &str = "type_checker/trait_solver/entries/50_commit_work";
const AUDIT_SUBSTITUTIONS: &str = "type_checker/trait_solver/entries/55_audit_substitutions";
const COMMIT_SUBSTITUTIONS: &str = "type_checker/trait_solver/entries/55_commit_substitutions";
/// Commit stages over the whole grid (proof_commit_audit.slang): audit lanes
/// over the owner rows, then one committing thread; 47 and 50 go on with the
/// lanes, and for 50 the thread, that finish what the commit let through.
/// The lanes of 45, 47 and 55 take every admitted Work, those of 50 the
/// pending Work rows; each thread takes the one-row span (0, 1).
const COMMIT_STAGES: [(u32, &[&str]); 4] = [
    (45, &[AUDIT_TERMS, COMMIT_TERMS]),
    (47, &[AUDIT_GOALS, COMMIT_GOALS, MARK_GOALS]),
    (50, &[AUDIT_WORK, RESERVE_GOAL_INDEX, WRITE_GOAL_INDEX, COMMIT_WORK]),
    (55, &[AUDIT_SUBSTITUTIONS, COMMIT_SUBSTITUTIONS]),
];
/// Lanes that use no thread-scratch slot: one dispatch over the whole span.
const WHOLE_SPAN_KERNELS: [&str; 6] = [
    AUDIT_TERMS,
    AUDIT_GOALS,
    MARK_GOALS,
    AUDIT_WORK,
    WRITE_GOAL_INDEX,
    AUDIT_SUBSTITUTIONS,
];
fn commit_stage(phase: u32) -> Option<&'static [&'static str]> {
    COMMIT_STAGES.iter().find(|(entry, _)| *entry == phase).map(|(_, keys)| *keys)
}
const PROOF_KEYS: &[(u32, &str, u32)] = &[
    (
        40,
        "type_checker/trait_solver/entries/40_initialize_proof_store",
        1,
    ),
    (
        41,
        "type_checker/trait_solver/entries/41_normalize_original",
        256,
    ),
    (
        42,
        "type_checker/trait_solver/entries/42_normalize_prerequisite",
        256,
    ),
    (
        43,
        "type_checker/trait_solver/entries/43_validate_original_normalization",
        256,
    ),
    (
        44,
        "type_checker/trait_solver/entries/44_validate_prerequisite_normalization",
        256,
    ),
    // Commit stages 45, 47, 50 and 55: see COMMIT_STAGES.
    (45, AUDIT_TERMS, 256),
    (45, COMMIT_TERMS, 1),
    (
        46,
        "type_checker/trait_solver/entries/46_hash_normalized_goals",
        256,
    ),
    (47, AUDIT_GOALS, 256),
    (47, COMMIT_GOALS, 1),
    (47, MARK_GOALS, 256),
    (
        48,
        "type_checker/trait_solver/entries/48_initialize_work",
        256,
    ),
    (
        49,
        "type_checker/trait_solver/entries/49_admit_work",
        256,
    ),
    (50, AUDIT_WORK, 256),
    (50, RESERVE_GOAL_INDEX, 1),
    (50, WRITE_GOAL_INDEX, 256),
    (50, COMMIT_WORK, 1),
    (
        51,
        "type_checker/trait_solver/entries/51_index_work",
        256,
    ),
    (
        52,
        "type_checker/trait_solver/entries/52_resolve_work",
        256,
    ),
    // Work selection: see SELECTION_STEPS.
    (53, SELECT_IMPLEMENTATIONS, 256),
    (
        53,
        "type_checker/trait_solver/entries/53_select_assumptions",
        256,
    ),
    (
        53,
        "type_checker/trait_solver/entries/53_select_work",
        256,
    ),
    // Substitution walk (phases 54, 59 and 66): see SUBSTITUTION_STEPS and
    // IMPLEMENTATION_PROOF_STEPS.
    (54, WALK_GOALS, 256),
    (54, WALK_ROOTS, 256),
    (54, WALK_BINDINGS, 256),
    (54, BINDING_ROWS, 256),
    (55, AUDIT_SUBSTITUTIONS, 256),
    (55, COMMIT_SUBSTITUTIONS, 1),
    (
        56,
        "type_checker/trait_solver/entries/56_expand_work",
        256,
    ),
    (
        57,
        "type_checker/trait_solver/entries/57_link_requirements",
        256,
    ),
    (
        58,
        "type_checker/trait_solver/entries/58_emit_ready_proofs",
        256,
    ),
    (59, ASSUMPTION_PROOFS, 256),
    (59, PROOF_EDGE_ROWS, 256),
    (
        60,
        "type_checker/trait_solver/entries/60_commit_proofs",
        1,
    ),
    (
        61,
        "type_checker/trait_solver/entries/61_publish_work_proofs",
        256,
    ),
    (
        62,
        "type_checker/trait_solver/entries/62_notify_work",
        256,
    ),
    (
        63,
        "type_checker/trait_solver/entries/63_commit_queue",
        1,
    ),
    (
        64,
        "type_checker/trait_solver/entries/64_publish_roots",
        256,
    ),
    (
        COUNT_ORIGINAL_NORMALIZATION,
        "type_checker/trait_solver/entries/67_count_original_normalization",
        256,
    ),
    (
        COUNT_PREREQUISITE_NORMALIZATION,
        "type_checker/trait_solver/entries/68_count_prerequisite_normalization",
        256,
    ),
    (
        WAVE_PLAN_PHASE,
        "type_checker/trait_solver/entries/70_plan_solver_wave",
        1,
    ),
    // The finish point's batch stages: call reduction, then the receipt.
    (18, "type_checker/trait_solver/entries/18_reduce_calls", 256),
    (19, "type_checker/trait_solver/entries/19_finish_batch", 1),
];

pub(super) struct ProofKernels {
    passes: Vec<PassData>,
}
impl ProofKernels {
    pub fn load(device: &wgpu::Device) -> Result<Self> {
        let passes = PROOF_KEYS
            .iter()
            .map(|(_, key, _)| {
                passes_core::make_pass_data_from_shader_key_with_declared_dynamic_uniforms(device, key, "main", key, &PARAMS_BLOCKS)
            })
            .collect::<Result<Vec<_>>>()?;
        Ok(Self { passes })
    }
    /// Records one stage outside the solver rounds over `span`: store
    /// initialization (40) or Work initialization (48). The rounds' stages
    /// and the finish record through wave templates.
    pub fn record(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        phase: u32,
        span: Span,
        catalog: &Arena,
        input: &Arena,
        output: &Arena,
        proof: ProofResources<'_>,
    ) -> Result<()> {
        ensure!(matches!(phase, 40 | 48), "proof stage {phase} records through a wave template");
        let index = PROOF_KEYS
            .iter()
            .position(|(entry, _, _)| *entry == phase)
            .ok_or_else(|| anyhow::anyhow!("unregistered proof stage {phase}"))?;
        self.record_index(device, encoder, index, span, catalog, input, output, proof)
    }
    fn record_index(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        index: usize,
        span: Span,
        catalog: &Arena,
        input: &Arena,
        output: &Arena,
        proof: ProofResources<'_>,
    ) -> Result<()> {
        let (phase, _, threads) = PROOF_KEYS[index];
        ensure!(
            threads != 1 || (span.first == 0 && span.count == 1),
            "singleton proof stage needs exactly one dispatch"
        );
        record_phase_with_proof(
            device,
            encoder,
            &self.passes[index],
            phase,
            span,
            threads,
            catalog,
            input,
            output,
            Some(proof),
        )
    }
}

/// State words and values of the recorded solver rounds
/// (proof_solver_wave.slang).
pub(super) mod wave {
    pub const STOP: usize = 0;
    pub const FAULT_DETAIL: usize = 1;
    #[cfg(test)]
    pub const WORK_ACTIVE: usize = 5;
    #[cfg(test)]
    pub const QUEUE_ACTIVE: usize = 6;
    #[cfg(test)]
    pub const WORK_FIRST: usize = 7;
    #[cfg(test)]
    pub const WORK_COUNT: usize = 8;
    pub const OVERFLOW_POINT: usize = 13;
    pub const OVERFLOW_ROWS: usize = 14;
    pub const CHUNK_ROWS: usize = 15;
    pub const SLOT_WORDS: usize = 16;
    pub const CALLS_FIRST: usize = 17;
    pub const CALLS_COUNT: usize = 18;
    /// Words the host reads back: the scalar state, not the span records.
    pub const READ_WORDS: u32 = 32;
    pub const STATE_WORDS: u32 = 80;
    pub const RUNNING: u32 = 0;
    pub const STOPPED: u32 = 1;
    /// Quiescent, and the finish point published the roots and receipt.
    pub const DONE: u32 = 2;
    pub const FAULT: u32 = 3;
    pub const OVERFLOW: u32 = 4;
    pub const GROW: u32 = 5;
    pub const FAULT_IDENTITY: u32 = 1;
    pub const FAULT_LAYOUT: u32 = 2;
    pub const FAULT_RECEIPT: u32 = 3;
    pub const FAULT_CURSOR: u32 = 4;
    pub const FAULT_REQUIREMENTS: u32 = 5;
}
// Slot words (proof_solver_wave.slang): TraitSolverParams, indirect
// arguments, then the step's static description.
const SLOT_ARGS: u32 = 8;
const SLOT_SPAN: usize = 11;
const SLOT_CHUNK: usize = 12;
const SLOT_THREADS: usize = 13;
const SLOT_LIMIT: usize = 14;
const SLOT_MIN_WORDS: u32 = 64;
/// Chunk steps per span at most; with 4096-row chunks this is any span a
/// 32-bit row count allows.
pub(super) const WAVE_MAX_CHUNKS: u32 = 1 << 20;

/// Planning points, in recording order: where the planner reads the
/// counters and computes the spans of the steps up to the next point.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum WavePoint {
    FirstWork = 0,
    Round = 1,
    Selected = 2,
    Expanded = 3,
    Queue = 4,
    Emitted = 5,
    /// After the recorded rounds: the quiescence test, then the finish.
    Finish = 6,
}
impl WavePoint {
    pub const ROUND: [WavePoint; 5] = [
        WavePoint::Round,
        WavePoint::Selected,
        WavePoint::Expanded,
        WavePoint::Queue,
        WavePoint::Emitted,
    ];
    pub fn from_word(word: u32) -> Option<Self> {
        [WavePoint::FirstWork, WavePoint::Finish]
            .into_iter()
            .chain(Self::ROUND)
            .find(|point| *point as u32 == word)
    }
    /// This point and the rest of its round; the first-work and finish
    /// points are alone.
    pub fn remainder(self) -> &'static [WavePoint] {
        match self {
            WavePoint::FirstWork => &[WavePoint::FirstWork],
            WavePoint::Finish => &[WavePoint::Finish],
            point => &Self::ROUND[point as usize - 1..],
        }
    }
}

/// Some consecutive step groups of one point (`wave_segment`). The point's
/// planner runs before them.
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) struct WavePiece {
    pub point: WavePoint,
    first: usize,
    end: usize,
}
impl WavePiece {
    pub fn whole(point: WavePoint) -> Self {
        Self { point, first: 0, end: usize::MAX }
    }
    /// Groups `first..end` of the point, for a test pause inside it.
    #[cfg(test)]
    pub fn groups(point: WavePoint, first: usize, end: usize) -> Self {
        Self { point, first, end }
    }
}
/// How many leading groups of a round's first point run stages up to `phase`.
#[cfg(test)]
pub(super) fn round_groups_through(phase: u32) -> Result<usize> {
    Ok(wave_segment(WavePoint::Round)?
        .iter()
        .take_while(|(_, steps)| steps.iter().all(|(_, entry)| *entry <= phase))
        .count())
}

/// Row spans the planner computes (proof_solver_wave.slang, PSW_SPAN_*).
#[derive(Clone, Copy, PartialEq, Eq)]
enum WaveSpan {
    FirstWork = 0,
    FirstOne = 1,
    Work = 2,
    WorkOne = 3,
    Requirements = 4,
    AllWork = 5,
    SelectedWork = 6,
    Bindings = 7,
    SelectedOne = 8,
    SelectedAllWork = 9,
    ExpandedWork = 10,
    ExpandedOne = 11,
    Queue = 12,
    EmittedQueue = 13,
    ProofEdges = 14,
    EmittedOne = 15,
    FinishRoots = 16,
    FinishCalls = 17,
    FinishOne = 18,
}
impl WaveSpan {
    fn is_one(self) -> bool {
        matches!(
            self,
            WaveSpan::FirstOne
                | WaveSpan::WorkOne
                | WaveSpan::SelectedOne
                | WaveSpan::ExpandedOne
                | WaveSpan::EmittedOne
                | WaveSpan::FinishOne
        )
    }
    /// Every admitted Work, for the commit audits: one step over the whole
    /// span, however long.
    fn is_whole(self) -> bool {
        matches!(self, WaveSpan::AllWork | WaveSpan::SelectedAllWork)
    }
}

/// The steps between one point and the next: groups of kernels over one
/// span, each group dispatched chunk by chunk. This is the solver's stage
/// order.
fn wave_segment(point: WavePoint) -> Result<Vec<(WaveSpan, Vec<(&'static str, u32)>)>> {
    let stage = |phase: u32| -> Result<(&'static str, u32)> {
        PROOF_KEYS
            .iter()
            .find(|(entry, _, _)| *entry == phase)
            .map(|(_, key, _)| (*key, phase))
            .ok_or_else(|| anyhow!("unregistered proof stage {phase}"))
    };
    // A commit stage (COMMIT_STAGES): its lanes over `rows`, its threads once.
    let commit = |phase: u32, rows: WaveSpan, one: WaveSpan| -> Result<Vec<(WaveSpan, Vec<(&'static str, u32)>)>> {
        let keys = commit_stage(phase).ok_or_else(|| anyhow!("proof stage {phase} is not a commit"))?;
        keys.iter()
            .map(|&key| {
                let threads = PROOF_KEYS[proof_key_index(key)?].2;
                Ok((if threads == 1 { one } else { rows }, vec![(key, phase)]))
            })
            .collect()
    };
    use WaveSpan::*;
    Ok(match point {
        // Each Work admission counts the rows the next normalization
        // reserves, so the store can grow in place before it runs.
        WavePoint::FirstWork => {
            let mut groups = vec![(FirstWork, vec![stage(49)?])];
            groups.extend(commit(50, FirstWork, FirstOne)?);
            groups.push((FirstWork, vec![stage(COUNT_ORIGINAL_NORMALIZATION)?]));
            groups
        }
        WavePoint::Round => {
            // Normalization (41 to 47), 51, 52, 57, then selection.
            let mut groups = Vec::new();
            for phase in 41..=47 {
                if matches!(phase, 45 | 47) {
                    groups.extend(commit(phase, AllWork, WorkOne)?);
                } else {
                    groups.push((Work, vec![stage(phase)?]));
                }
            }
            groups.push((Work, vec![stage(51)?]));
            groups.push((Work, vec![stage(52)?]));
            groups.push((Requirements, vec![stage(57)?]));
            groups.push((Work, SELECTION_STEPS.to_vec()));
            groups
        }
        WavePoint::Selected => {
            let mut groups = vec![
                (SelectedWork, SUBSTITUTION_STEPS.to_vec()),
                (Bindings, vec![(BINDING_ROWS, SUBSTITUTION_PHASE)]),
            ];
            groups.extend(commit(55, SelectedAllWork, SelectedOne)?);
            groups.push((SelectedWork, vec![stage(56)?]));
            groups
        }
        WavePoint::Expanded => {
            let mut groups = vec![(ExpandedWork, vec![stage(49)?])];
            groups.extend(commit(50, ExpandedWork, ExpandedOne)?);
            groups.push((ExpandedWork, vec![stage(COUNT_PREREQUISITE_NORMALIZATION)?]));
            groups
        }
        WavePoint::Queue => vec![(Queue, vec![stage(58)?])],
        WavePoint::Emitted => vec![
            (EmittedQueue, IMPLEMENTATION_PROOF_STEPS.to_vec()),
            (EmittedQueue, vec![(ASSUMPTION_PROOFS, IMPLEMENTATION_PROOF_PHASE)]),
            (ProofEdges, vec![(PROOF_EDGE_ROWS, IMPLEMENTATION_PROOF_PHASE)]),
            (EmittedOne, vec![stage(60)?]),
            (EmittedQueue, vec![stage(61)?]),
            (EmittedQueue, vec![stage(62)?]),
            (EmittedOne, vec![stage(63)?]),
        ],
        // Root publication, call reduction and the batch receipt.
        WavePoint::Finish => vec![
            (FinishRoots, vec![stage(64)?]),
            (FinishCalls, vec![stage(18)?]),
            (FinishOne, vec![stage(19)?]),
        ],
    })
}

/// Words per step slot: whole uniform-offset alignments, at least the slot.
pub(super) fn wave_slot_words(device: &wgpu::Device) -> u32 {
    (device.limits().min_uniform_buffer_offset_alignment / 4).max(SLOT_MIN_WORDS)
}

/// The zeroed normalization demand table (proof_demand.slang). One shared
/// role: the solver reads each count back before the next zeroing is
/// queued, so the queued write never races a use.
pub(super) fn proof_demand(catalog: &Arena) -> Result<LaniusBuffer<u32>> {
    catalog.workspace().shared("trait_solver.proof_demand").buffer(
        PROOF_STORE_TABLES as u32,
        wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        Some(&[0; PROOF_STORE_TABLES]),
    )
}

/// The solver state of one attempt, planned and read only by the GPU
/// planner until the host reads it back. One shared role: an attempt reads
/// its state back before the next attempt rewrites it, and the templates
/// that bind it stay valid across checks.
pub(super) fn wave_state(device: &wgpu::Device, catalog: &Arena, calls: Span) -> Result<LaniusBuffer<u32>> {
    let mut words = [0u32; wave::STATE_WORDS as usize];
    words[wave::CHUNK_ROWS] = THREAD_SCRATCH_SLOTS;
    words[wave::SLOT_WORDS] = wave_slot_words(device);
    words[wave::CALLS_FIRST] = calls.first;
    words[wave::CALLS_COUNT] = calls.count;
    catalog.workspace().shared("trait_solver.solver_wave").buffer(
        wave::STATE_WORDS,
        wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        Some(&words),
    )
}

struct WaveStep {
    pass: usize,
    bindings: wgpu::BindGroup,
    /// Dynamic offsets of its parameter blocks (`params_offsets`).
    offsets: Vec<u32>,
    /// None: the planner, one thread. Some: the byte offset of the step's
    /// indirect arguments in the slot buffer.
    indirect: Option<u64>,
}

impl WaveStep {
    fn launch<'a>(&self, template: &'a WaveTemplate) -> Launch<'a> {
        match self.indirect {
            None => Launch::Direct((1, 1, 1)),
            Some(offset) => Launch::Indirect(&template.slots.buffer, offset),
        }
    }
}

/// One bound buffer view: a bind group built over it stays valid while a
/// check binds the same view.
type BoundView = (wgpu::Buffer, u64, usize);
fn bound_view(buffer: &LaniusBuffer<u32>) -> BoundView {
    (buffer.buffer.clone(), buffer.byte_offset, buffer.byte_size)
}

/// The words of a template that change between checks: the arenas' logical
/// sizes and the proof submission's identity.
#[derive(Clone, Copy, PartialEq, Eq)]
struct WaveInputs {
    catalog_words: u32,
    input_words: u32,
    output_words: u32,
    proof_words: u32,
    epoch: u64,
    arena_id: u64,
    serial: u32,
}

/// The static description of one step slot.
#[derive(Clone, Copy)]
struct WaveSlot {
    pass: usize,
    phase: u32,
    span: WaveSpan,
    /// 0: the whole span; c: its chunk c - 1.
    chunk: u32,
    /// Rows the template recorded for the span.
    limit: u32,
}

/// Recorded steps of some planning points with bind groups built once per
/// job: each step reads its parameters and indirect arguments from its slot,
/// which the point's planner rewrites every time it runs. A later check
/// reuses the template while it binds the same buffer views, and rewrites
/// only its parameter words (`WaveInputs`).
pub(super) struct WaveTemplate {
    pieces: Vec<WavePiece>,
    chunks: u32,
    bound: Vec<BoundView>,
    slots: LaniusBuffer<u32>,
    slot_rows: Vec<WaveSlot>,
    /// The planner's dispatch block, then one proof-store block per phase
    /// in `phases`. A separate buffer: the planner writes the slot buffer.
    params: LaniusBuffer<u32>,
    phases: Vec<u32>,
    stride: u32,
    written: WaveInputs,
    steps: Vec<WaveStep>,
}

impl WaveTemplate {
    fn slot_words(&self, inputs: WaveInputs) -> Vec<u32> {
        let stride = self.stride as usize;
        let mut words = vec![0u32; self.slot_rows.len().max(1) * stride];
        for (row, slot) in words.chunks_exact_mut(stride).zip(&self.slot_rows) {
            row[2] = inputs.catalog_words;
            row[3] = inputs.input_words;
            row[4] = inputs.output_words;
            row[5] = slot.phase;
            row[SLOT_ARGS as usize + 1] = 1;
            row[SLOT_ARGS as usize + 2] = 1;
            row[SLOT_SPAN] = slot.span as u32;
            row[SLOT_CHUNK] = slot.chunk;
            row[SLOT_THREADS] = PROOF_KEYS[slot.pass].2;
            row[SLOT_LIMIT] = slot.limit;
        }
        words
    }

    fn params_words(&self, inputs: WaveInputs) -> Vec<u32> {
        let stride = self.stride as usize;
        let mut words = vec![0u32; (self.phases.len() + 1) * stride];
        words[..8].copy_from_slice(&[
            0,
            1,
            inputs.catalog_words,
            inputs.input_words,
            inputs.output_words,
            WAVE_PLAN_PHASE,
            0,
            0,
        ]);
        for (index, &phase) in self.phases.iter().enumerate() {
            let base = (index + 1) * stride;
            words[base..base + 8].copy_from_slice(&[
                inputs.proof_words,
                inputs.epoch as u32,
                (inputs.epoch >> 32) as u32,
                inputs.arena_id as u32,
                (inputs.arena_id >> 32) as u32,
                inputs.serial,
                phase,
                0,
            ]);
        }
        words
    }

    /// Byte offset of the proof-store block of `phase` in the params buffer.
    fn proof_block(&self, phase: u32) -> u64 {
        let index = self.phases.iter().position(|entry| *entry == phase).expect("phase block");
        self.params.absolute_offset((index as u64 + 1) * u64::from(self.stride) * 4)
    }

    /// Rewrites the parameter words when this check's differ. The writes
    /// apply at the next submit, after every earlier submit that read them.
    fn refresh(&mut self, queue: &wgpu::Queue, inputs: WaveInputs) {
        if self.written == inputs {
            return;
        }
        let bytes = |words: Vec<u32>| words.iter().flat_map(|word| word.to_le_bytes()).collect::<Vec<u8>>();
        self.slots.write(queue, 0, &bytes(self.slot_words(inputs)));
        self.params.write(queue, 0, &bytes(self.params_words(inputs)));
        self.written = inputs;
    }
}

impl ProofKernels {
    /// The index in `cache` of the template of `pieces` with `chunks` chunk
    /// steps for every span that is not a single row, refreshed for this
    /// check. A template is built when none binds these buffer views; it
    /// replaces a template of the same pieces over views no check binds now.
    pub fn wave_template(
        &self,
        cache: &mut Vec<WaveTemplate>,
        device: &wgpu::Device,
        pieces: &[WavePiece],
        chunks: u32,
        state: &LaniusBuffer<u32>,
        demand: &LaniusBuffer<u32>,
        catalog: &Arena,
        input: &Arena,
        output: &Arena,
        proof: ProofResources<'_>,
    ) -> Result<usize> {
        ensure!((1..=WAVE_MAX_CHUNKS).contains(&chunks), "solver wave chunk count {chunks}");
        let scratch = thread_scratch(catalog)?;
        let audit = commit_audit(catalog, proof.storage)?;
        let bound = [
            &catalog.buffer,
            &input.buffer,
            &output.buffer,
            &proof.storage.buffer,
            &scratch,
            &audit,
            state,
            demand,
        ]
        .map(bound_view)
        .to_vec();
        let inputs = WaveInputs {
            catalog_words: catalog.logical_words,
            input_words: input.logical_words,
            output_words: output.logical_words,
            proof_words: proof.storage.logical_words,
            epoch: proof.epoch,
            arena_id: proof.arena_id,
            serial: proof.serial,
        };
        let queue = catalog.workspace().queue().clone();
        let same = |template: &WaveTemplate| template.pieces == pieces && template.chunks == chunks;
        if let Some(index) = cache.iter().position(|template| same(template) && template.bound == bound) {
            cache[index].refresh(&queue, inputs);
            return Ok(index);
        }
        let template = self.build_wave_template(
            device, pieces, chunks, bound, inputs, &scratch, &audit, state, demand, catalog, input,
            output, proof,
        )?;
        Ok(match cache.iter().position(same) {
            Some(index) => {
                cache[index] = template;
                index
            }
            None => {
                cache.push(template);
                cache.len() - 1
            }
        })
    }

    #[allow(clippy::too_many_arguments)]
    fn build_wave_template(
        &self,
        device: &wgpu::Device,
        pieces: &[WavePiece],
        chunks: u32,
        bound: Vec<BoundView>,
        inputs: WaveInputs,
        scratch: &LaniusBuffer<u32>,
        audit: &LaniusBuffer<u32>,
        state: &LaniusBuffer<u32>,
        demand: &LaniusBuffer<u32>,
        catalog: &Arena,
        input: &Arena,
        output: &Arena,
        proof: ProofResources<'_>,
    ) -> Result<WaveTemplate> {
        let stride = wave_slot_words(device);
        let mut slots: Vec<WaveSlot> = Vec::new();
        let mut segments = Vec::new();
        for piece in pieces {
            let point = piece.point;
            let first = slots.len();
            let groups = wave_segment(point)?;
            let end = piece.end.min(groups.len());
            for (span, steps) in groups.into_iter().take(end).skip(piece.first) {
                let span_chunks = if span.is_one() || span.is_whole() { 1 } else { chunks };
                let limit = if span.is_whole() {
                    u32::MAX
                } else {
                    span_chunks.saturating_mul(THREAD_SCRATCH_SLOTS)
                };
                let steps = steps
                    .into_iter()
                    .map(|(key, phase)| proof_key_index(key).map(|index| (index, phase)))
                    .collect::<Result<Vec<_>>>()?;
                for chunk in 1..=span_chunks {
                    for &(pass, phase) in &steps {
                        ensure!(
                            PROOF_KEYS[pass].2 != 1 || span.is_one(),
                            "singleton proof stage needs exactly one dispatch"
                        );
                        ensure!(
                            !span.is_whole() || WHOLE_SPAN_KERNELS.contains(&PROOF_KEYS[pass].1),
                            "a whole-span step needs a kernel without scratch slots"
                        );
                        slots.push(WaveSlot {
                            pass,
                            phase,
                            span,
                            chunk: if span.is_whole() { 0 } else { chunk },
                            limit,
                        });
                    }
                }
            }
            segments.push((point, first, slots.len()));
        }
        let slot_count = u32::try_from(slots.len())?;
        let total_words = slot_count
            .max(1)
            .checked_mul(stride)
            .ok_or_else(|| anyhow!("solver wave slot table overflow"))?;
        // One proof-store parameter block per phase, the planner's first.
        let mut phases = vec![WAVE_PLAN_PHASE];
        for slot in &slots {
            if !phases.contains(&slot.phase) {
                phases.push(slot.phase);
            }
        }
        let workspace = catalog.workspace();
        let params_words = u32::try_from(phases.len() + 1)?
            .checked_mul(stride)
            .ok_or_else(|| anyhow!("solver wave parameter table overflow"))?;
        let mut template = WaveTemplate {
            pieces: pieces.to_vec(),
            chunks,
            bound,
            slots: workspace.initialized(
                "trait_solver.solver_wave_slots",
                total_words,
                wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::UNIFORM
                    | wgpu::BufferUsages::INDIRECT
                    | wgpu::BufferUsages::COPY_DST,
                None,
            )?,
            slot_rows: slots,
            params: workspace.initialized(
                "trait_solver.solver_wave_params",
                params_words,
                wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
                None,
            )?,
            phases,
            stride,
            written: inputs,
            steps: Vec::new(),
        };
        let words = |words: Vec<u32>| words.iter().flat_map(|word| word.to_le_bytes()).collect::<Vec<u8>>();
        template.slots.write(workspace.queue(), 0, &words(template.slot_words(inputs)));
        template.params.write(workspace.queue(), 0, &words(template.params_words(inputs)));
        let plan = proof_key_index("type_checker/trait_solver/entries/70_plan_solver_wave")?;
        let slot_bytes = u64::from(stride) * 4;
        let plan_block = u32::try_from(template.params.absolute_offset(0))?;
        let mut steps = Vec::with_capacity(template.slot_rows.len() + segments.len());
        // A slot step's bindings depend only on its kernel and phase: its slot
        // parameters are a dynamic offset into the one slot buffer. So the
        // steps of one (kernel, phase) share a bind group.
        let mut slot_bindings: Vec<((usize, u32), wgpu::BindGroup)> = Vec::new();
        for (point, first, end) in segments {
            let plan_params = workspace.initialized(
                "trait_solver.solver_wave_plan",
                4,
                wgpu::BufferUsages::UNIFORM,
                Some(&[point as u32, u32::try_from(first)?, u32::try_from(end)?, 0]),
            )?;
            let resources = [
                ("trait_solver_params", params_binding(&template.params.buffer)),
                ("trait_solver_catalog", catalog.buffer.as_entire_binding()),
                ("trait_solver_batch", input.buffer.as_entire_binding()),
                ("trait_solver_output", output.buffer.as_entire_binding()),
                ("trait_solver_proof_store", proof.storage.buffer.as_entire_binding()),
                ("proof_store_params", params_binding(&template.params.buffer)),
                ("thread_scratch", scratch.as_entire_binding()),
                ("trait_solver_wave", state.as_entire_binding()),
                ("trait_solver_wave_slots", template.slots.as_entire_binding()),
                ("trait_solver_wave_plan", plan_params.as_entire_binding()),
                ("trait_solver_proof_demand", demand.as_entire_binding()),
            ];
            let bindings = passes_core::bind_group::create_bind_group_from_bindings(
                device,
                Some("trait_solver.solver_wave_plan"),
                &self.passes[plan],
                0,
                &resources,
            )?;
            let offsets = params_offsets(
                &self.passes[plan],
                [plan_block, u32::try_from(template.proof_block(WAVE_PLAN_PHASE))?],
            );
            steps.push(WaveStep { pass: plan, bindings, offsets, indirect: None });
            for slot in first..end {
                let WaveSlot { pass, phase, .. } = template.slot_rows[slot];
                let offset = template.slots.absolute_offset(slot as u64 * slot_bytes);
                let shared = slot_bindings
                    .iter()
                    .find(|(key, _)| *key == (pass, phase))
                    .map(|(_, bindings)| bindings.clone());
                let bindings = match shared {
                    Some(bindings) => bindings,
                    None => {
                        let resources = [
                            ("trait_solver_params", params_binding(&template.slots.buffer)),
                            ("trait_solver_catalog", catalog.buffer.as_entire_binding()),
                            ("trait_solver_batch", input.buffer.as_entire_binding()),
                            ("trait_solver_output", output.buffer.as_entire_binding()),
                            ("trait_solver_proof_store", proof.storage.buffer.as_entire_binding()),
                            ("proof_store_params", params_binding(&template.params.buffer)),
                            ("thread_scratch", scratch.as_entire_binding()),
                            ("trait_solver_proof_demand", demand.as_entire_binding()),
                            (COMMIT_AUDIT, audit.as_entire_binding()),
                        ];
                        let bindings = passes_core::bind_group::create_bind_group_from_bindings(
                            device,
                            Some("trait_solver.bindings"),
                            &self.passes[pass],
                            0,
                            &resources,
                        )?;
                        slot_bindings.push(((pass, phase), bindings.clone()));
                        bindings
                    }
                };
                let offsets = params_offsets(
                    &self.passes[pass],
                    [u32::try_from(offset)?, u32::try_from(template.proof_block(phase))?],
                );
                steps.push(WaveStep {
                    pass,
                    bindings,
                    offsets,
                    indirect: Some(offset + u64::from(SLOT_ARGS) * 4),
                });
            }
        }
        template.steps = steps;
        Ok(template)
    }

    /// Records every step of each template, in order, in one compute pass:
    /// most steps of a recorded round dispatch no workgroups, and a pass per
    /// step cost more than the steps. Operation limits and timers that cannot
    /// stamp inside a pass keep a pass per step.
    pub fn record_waves(&self, encoder: &mut wgpu::CommandEncoder, templates: &[&WaveTemplate]) {
        // A dispatch capture (`LANIUS_CAPTURE`) copies buffers
        // around its dispatch, which needs a pass per step too.
        if crate::gpu::timer::operation_capture_requires_split_passes()
            || passes_core::debug_operation_limited()
            || crate::gpu::dispatch_capture::capture_pass().is_some()
        {
            for template in templates {
                for step in &template.steps {
                    dispatch_pass(encoder, &self.passes[step.pass], &step.bindings, &step.offsets, step.launch(template));
                }
            }
            return;
        }
        passes_core::flush_deferred_compute(encoder);
        let timed = crate::gpu::timer::operation_capture_active();
        let mut compute = passes_core::begin_counted_compute_pass(
            encoder,
            &wgpu::ComputePassDescriptor {
                label: Some("trait_solver.solver_wave"),
                timestamp_writes: None,
            },
        );
        for template in templates {
            for step in &template.steps {
                let pass = &self.passes[step.pass];
                compute.set_pipeline(&pass.pipeline);
                compute.set_bind_group(0, Some(&step.bindings), &step.offsets);
                passes_core::record_compute_dispatch();
                match step.launch(template) {
                    Launch::Direct(groups) => compute.dispatch_workgroups(groups.0, groups.1, groups.2),
                    Launch::Indirect(buffer, offset) => compute.dispatch_workgroups_indirect(buffer, offset),
                }
                // Profiled jobs need one timestamp per recorded dispatch.
                if timed {
                    crate::gpu::timer::stamp_active_operation_in_pass(&mut compute, pass.shader_id.clone());
                }
            }
        }
    }
}

fn proof_key_index(key: &str) -> Result<usize> {
    PROOF_KEYS
        .iter()
        .position(|(_, entry, _)| *entry == key)
        .ok_or_else(|| anyhow!("unregistered proof kernel {key}"))
}

// Recipe roots are admitted with the catalog graph before this sidecar is
// frozen. There is one load and one complete admission per program owner.
const RECIPE_KEYS: [&str; 5] = [
    "type_checker/trait_solver/native_layout/entries/00_initialize_recipes",
    "type_checker/trait_solver/native_layout/entries/01_clear_recipe_map",
    "type_checker/trait_solver/native_layout/entries/02_admit_recipes",
    "type_checker/trait_solver/native_layout/entries/03_admit_recipe_groups",
    "type_checker/trait_solver/native_layout/entries/04_freeze_recipes",
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
                threads, storage, input, output, None, Some(recipes), None, None)?;
        }
        Ok(())
    }
}

/// Retained lazily by the program owner; body replay never reloads the pipeline.
pub(super) struct NativeLayoutKernel { pass: PassData }
impl NativeLayoutKernel {
    pub fn load(device: &wgpu::Device) -> Result<Self> {
        let key = "type_checker/trait_solver/native_layout/entries/05_materialize_proof_value";
        Ok(Self { pass: passes_core::make_pass_data_from_shader_key_with_declared_dynamic_uniforms(device, key, "main", key, &PARAMS_BLOCKS)? })
    }
    pub fn record(&self, device: &wgpu::Device, encoder: &mut wgpu::CommandEncoder,
        catalog: &Arena, input: &Arena, output: &Arena, proof: ProofResources<'_>,
        recipes: &Arena, work: &Arena) -> Result<()> {
        record_phase_with_resources(device, encoder, &self.pass, 5, Span::new(0, 1)?, 1,
            catalog, input, output, Some(proof), Some(recipes), Some(work), None)
    }
}

/// Read-only accepted-proof projection. The exclusive temporary work arena
/// shares the existing reflected work binding; native-layout recipes are not
/// bound or consulted by this kernel.
pub(super) struct ImplementationApplicationKernel { pass: PassData }
impl ImplementationApplicationKernel {
    pub fn load(device: &wgpu::Device) -> Result<Self> {
        let key = "type_checker/trait_solver/implementation_application/entries/00_project";
        Ok(Self { pass: passes_core::make_pass_data_from_shader_key_with_declared_dynamic_uniforms(
            device, key, "main", key, &PARAMS_BLOCKS)? })
    }
    pub fn record(&self, device: &wgpu::Device, encoder: &mut wgpu::CommandEncoder,
        catalog: &Arena, input: &Arena, output: &Arena, proof: ProofResources<'_>, work: &Arena,
    ) -> Result<()> {
        record_phase_with_resources(device, encoder, &self.pass, 6, Span::new(0, 1)?, 1,
            catalog, input, output, Some(proof), None, Some(work), None)
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn thread_scratch_layout_matches_shader() {
        let shader = include_str!("../../../../../../../shaders/thread_scratch.slang");
        let cells = format!("THREAD_SCRATCH_CELLS = {}u;", super::THREAD_SCRATCH_CELLS);
        assert!(shader.contains(&cells), "host and shader disagree on {cells}");
        assert!(shader.contains("THREAD_SCRATCH_GROUP = 32u;"));
        assert_eq!(super::THREAD_SCRATCH_SLOTS % 32, 0, "slots are whole groups");
    }
}
