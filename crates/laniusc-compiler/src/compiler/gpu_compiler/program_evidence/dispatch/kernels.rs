use std::num::NonZeroU64;

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
    "type_checker/program_evidence/entries/00_initialize",
    "type_checker/program_evidence/entries/01_clear_atom_index",
    "type_checker/program_evidence/entries/02_00_admit_snapshots",
    "type_checker/program_evidence/entries/02_01_admit_atoms",
    "type_checker/program_evidence/entries/02_02_admit_owners",
    "type_checker/program_evidence/entries/02_03_admit_parameters",
    "type_checker/program_evidence/entries/02_04_admit_callables",
    "type_checker/program_evidence/entries/02_05_admit_nodes",
    "type_checker/program_evidence/entries/02_06_admit_edges",
    "type_checker/program_evidence/entries/02_07_admit_roots",
    "type_checker/program_evidence/entries/02_08_admit_predicates",
    "type_checker/program_evidence/entries/02_09_admit_implementation_heads",
    "type_checker/program_evidence/entries/02_09_admit_implementation_members",
    "type_checker/program_evidence/entries/02_10_admit_methods",
    "type_checker/program_evidence/entries/03_build_atom_index",
    "type_checker/program_evidence/entries/04_check_atom_identity",
    "type_checker/program_evidence/entries/05_map_callables",
    "type_checker/program_evidence/entries/06_map_definition_identities",
    "type_checker/program_evidence/entries/07_check_method_targets",
    "type_checker/program_evidence/entries/08_clear_implementation_index",
    "type_checker/program_evidence/entries/09_build_implementation_index",
    "type_checker/program_evidence/entries/10_check_coherence",
    "type_checker/program_evidence/entries/11_freeze_catalog",
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
            .map(|key| passes_core::make_pass_data_from_shader_key(device, key, "main", key))
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
/// memory. Program evidence on canonical type IDs (plan P7) deletes them.
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
    let max_rows = if scratch.is_some() {
        max_rows.min(THREAD_SCRATCH_SLOTS)
    } else {
        max_rows
    };
    // LANIUS_DEBUG_EVIDENCE_DISPATCHES=1 logs each requested span, for sizing
    // the scratch chunk against real row counts.
    if crate::gpu::env::env_bool_truthy("LANIUS_DEBUG_EVIDENCE_DISPATCHES", false) {
        eprintln!(
            "[lanius-pev] {} rows={} chunk={} scratch={}",
            pass.shader_id,
            span.count,
            max_rows,
            scratch.is_some()
        );
    }
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
        let uniform = catalog.workspace().initialized(
            "program_evidence.params",
            8,
            wgpu::BufferUsages::UNIFORM,
            Some(&params),
        )?;
        // Some phases optimize an unused resource out. The existing reflected
        // constructor selects active names and rejects unknown required names.
        // These four resources are always distinct physical allocations.
        let proof_uniform = if let Some(proof) = proof {
            Some(catalog.workspace().initialized(
                "program_evidence.proof_params",
                8,
                wgpu::BufferUsages::UNIFORM,
                Some(&proof_params_words(proof, phase)),
            )?)
        } else {
            None
        };
        let mut resources = vec![
            ("program_evidence_params", uniform.as_entire_binding()),
            (
                "program_evidence_catalog",
                catalog.buffer.as_entire_binding(),
            ),
            ("program_evidence_batch", input.buffer.as_entire_binding()),
            ("program_evidence_output", output.buffer.as_entire_binding()),
        ];
        if let Some(proof) = proof {
            resources.push((
                "program_evidence_proof_store",
                proof.storage.buffer.as_entire_binding(),
            ));
            resources.push((
                "proof_store_params",
                proof_uniform
                    .as_ref()
                    .expect("proof parameters")
                    .as_entire_binding(),
            ));
        }
        if let Some(recipes) = recipes {
            resources.push((
                "program_evidence_native_recipes",
                recipes.buffer.as_entire_binding(),
            ));
        }
        if let Some(work) = layout_work {
            resources.push(("program_evidence_native_layout_work", work.buffer.as_entire_binding()));
        }
        if let Some(scratch) = &scratch {
            resources.push(("thread_scratch", scratch.as_entire_binding()));
        }
        if let Some(demand) = demand {
            resources.push(("program_evidence_proof_demand", demand.as_entire_binding()));
        }
        let bindings = passes_core::bind_group::create_bind_group_from_bindings(
            device,
            Some("program_evidence.bindings"),
            pass,
            0,
            &resources,
        )?;
        dispatch_pass(encoder, pass, &bindings, Launch::Direct((count.div_ceil(threads), 1, 1)));
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
        .shared("program_evidence.thread_scratch")
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
    launch: Launch<'_>,
) {
    passes_core::flush_deferred_compute(encoder);
    let capture_launch = match launch {
        Launch::Direct(groups) => dispatch_capture::CaptureLaunch::Direct(groups),
        Launch::Indirect(buffer, offset) => dispatch_capture::CaptureLaunch::Indirect(buffer, offset),
    };
    // LANIUS_DEBUG_CAPTURE_PASS support (tools/cpu_kernel_replay.py).
    let captured = dispatch_capture::debug_capture_begin(
        encoder,
        &pass.shader_id,
        pass,
        bindings,
        &[],
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
        compute.set_bind_group(0, Some(bindings), &[]);
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
const BATCH_KEYS: [&str; 6] = [
    "type_checker/program_evidence/entries/12_initialize_batch",
    "type_checker/program_evidence/entries/13_validate_retained_evidence",
    "type_checker/program_evidence/entries/14_validate_contexts",
    "type_checker/program_evidence/entries/15_build_assumption_index",
    "type_checker/program_evidence/entries/18_reduce_calls",
    "type_checker/program_evidence/entries/19_finish_batch",
];
// Table IDs are paired with literal keys so the phase contract is checked
// against BatchPlan's ordered input inventory before loading any batch shader.
const BATCH_ADMISSION_KEYS: [(usize, &str); 11] = [
    (1, "type_checker/program_evidence/entries/32_01_admit_atoms"),
    (5, "type_checker/program_evidence/entries/32_05_admit_nodes"),
    (6, "type_checker/program_evidence/entries/32_06_admit_edges"),
    (7, "type_checker/program_evidence/entries/32_07_admit_roots"),
    (
        11,
        "type_checker/program_evidence/entries/32_11_admit_environments",
    ),
    (
        12,
        "type_checker/program_evidence/entries/32_12_admit_bindings",
    ),
    (
        13,
        "type_checker/program_evidence/entries/32_13_admit_contexts",
    ),
    (
        14,
        "type_checker/program_evidence/entries/32_14_admit_assumptions",
    ),
    (
        15,
        "type_checker/program_evidence/entries/32_15_admit_calls",
    ),
    (
        16,
        "type_checker/program_evidence/entries/32_16_admit_obligations",
    ),
    (
        17,
        "type_checker/program_evidence/entries/32_17_admit_evidence",
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
            .map(|key| passes_core::make_pass_data_from_shader_key(device, key, "main", key))
            .collect::<Result<Vec<_>>>()?;
        let admit_rows = BATCH_ADMISSION_KEYS
            .iter()
            .map(|(_, key)| passes_core::make_pass_data_from_shader_key(device, key, "main", key))
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

    pub fn record_after_solver(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        plan: &BatchPlan,
        catalog: &Arena,
        input: &Arena,
        output: &Arena,
        proof: ProofResources<'_>,
    ) -> Result<()> {
        // Proof closure and every source root have passed their independent GPU
        // admission before ordinary call reduction and the joint final receipt.
        for (index, phase, span, threads) in
            [(4, 18, plan.calls, 256), (5, 19, Span::new(0, 1)?, 1)]
        {
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
            )?;
        }
        // An empty delta still publishes one fresh serial after proof finalization.
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
const WALK_GOALS: &str = "type_checker/program_evidence/entries/54_walk_substitution_goals";
const WALK_ROOTS: &str = "type_checker/program_evidence/entries/54_walk_substitution_roots";
const WALK_BINDINGS: &str = "type_checker/program_evidence/entries/54_walk_substitution_bindings";
const SELECT_IMPLEMENTATIONS: &str = "type_checker/program_evidence/entries/53_select_implementations";
/// Exact implementation match, caller assumption search, generic
/// implementation match (the first kernel again, as phase 65), then the
/// finish (proof_frontier_selection.slang).
const SELECTION_STEPS: [(&str, u32); 4] = [
    (SELECT_IMPLEMENTATIONS, SELECTION_PHASE),
    ("type_checker/program_evidence/entries/53_select_assumptions", SELECTION_PHASE),
    (SELECT_IMPLEMENTATIONS, GENERIC_SELECTION_PHASE),
    ("type_checker/program_evidence/entries/53_select_work", SELECTION_PHASE),
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
const BINDING_ROWS: &str = "type_checker/program_evidence/entries/54_admit_binding_rows";
const ASSUMPTION_PROOFS: &str = "type_checker/program_evidence/entries/59_admit_assumption_proofs";
const PROOF_EDGE_ROWS: &str = "type_checker/program_evidence/entries/59_admit_proof_edge_rows";
/// The GPU planner of recorded solver rounds (proof_solver_wave.slang).
const WAVE_PLAN_PHASE: u32 = 70;
/// Normalization row counts (proof_demand.slang): original Works (phase 41)
/// and prerequisite Works (phase 42).
pub(super) const COUNT_ORIGINAL_NORMALIZATION: u32 = 67;
pub(super) const COUNT_PREREQUISITE_NORMALIZATION: u32 = 68;
/// Commit stages that run as one 256-lane workgroup: the lanes audit
/// together, then lane 0 publishes (or reruns the serial stage). Like the
/// one-thread stages, they take only the one-row span (0, 1).
const GROUP_STAGES: &[u32] = &[45, 47, 55];
fn single_dispatch(phase: u32, threads: u32) -> bool {
    threads == 1 || GROUP_STAGES.contains(&phase)
}
const PROOF_KEYS: &[(u32, &str, u32)] = &[
    (
        40,
        "type_checker/program_evidence/entries/40_initialize_proof_store",
        1,
    ),
    (
        41,
        "type_checker/program_evidence/entries/41_normalize_original",
        256,
    ),
    (
        42,
        "type_checker/program_evidence/entries/42_normalize_prerequisite",
        256,
    ),
    (
        43,
        "type_checker/program_evidence/entries/43_validate_original_normalization",
        256,
    ),
    (
        44,
        "type_checker/program_evidence/entries/44_validate_prerequisite_normalization",
        256,
    ),
    // One 256-lane workgroup over the one-row span (0, 1).
    (
        45,
        "type_checker/program_evidence/entries/45_commit_normalized_terms",
        256,
    ),
    (
        46,
        "type_checker/program_evidence/entries/46_hash_normalized_goals",
        256,
    ),
    // One 256-lane workgroup over the one-row span (0, 1).
    (
        47,
        "type_checker/program_evidence/entries/47_commit_normalized_goals",
        256,
    ),
    (
        48,
        "type_checker/program_evidence/entries/48_initialize_work",
        256,
    ),
    (
        49,
        "type_checker/program_evidence/entries/49_admit_work",
        256,
    ),
    (
        50,
        "type_checker/program_evidence/entries/50_commit_work",
        1,
    ),
    (
        51,
        "type_checker/program_evidence/entries/51_index_work",
        256,
    ),
    (
        52,
        "type_checker/program_evidence/entries/52_resolve_work",
        256,
    ),
    // Work selection: see ProofKernels::record_selection.
    (53, SELECT_IMPLEMENTATIONS, 256),
    (
        53,
        "type_checker/program_evidence/entries/53_select_assumptions",
        256,
    ),
    (
        53,
        "type_checker/program_evidence/entries/53_select_work",
        256,
    ),
    // Substitution walk (phases 54, 59 and 66): see
    // ProofKernels::record_substitutions.
    (54, WALK_GOALS, 256),
    (54, WALK_ROOTS, 256),
    (54, WALK_BINDINGS, 256),
    (54, BINDING_ROWS, 256),
    // One 256-lane workgroup over the one-row span (0, 1).
    (
        55,
        "type_checker/program_evidence/entries/55_commit_substitutions",
        256,
    ),
    (
        56,
        "type_checker/program_evidence/entries/56_expand_work",
        256,
    ),
    (
        57,
        "type_checker/program_evidence/entries/57_link_requirements",
        256,
    ),
    (
        58,
        "type_checker/program_evidence/entries/58_emit_ready_proofs",
        256,
    ),
    (59, ASSUMPTION_PROOFS, 256),
    (59, PROOF_EDGE_ROWS, 256),
    (
        60,
        "type_checker/program_evidence/entries/60_commit_proofs",
        1,
    ),
    (
        61,
        "type_checker/program_evidence/entries/61_publish_work_proofs",
        256,
    ),
    (
        62,
        "type_checker/program_evidence/entries/62_notify_work",
        256,
    ),
    (
        63,
        "type_checker/program_evidence/entries/63_commit_queue",
        1,
    ),
    (
        64,
        "type_checker/program_evidence/entries/64_publish_roots",
        256,
    ),
    (
        COUNT_ORIGINAL_NORMALIZATION,
        "type_checker/program_evidence/entries/67_count_original_normalization",
        256,
    ),
    (
        COUNT_PREREQUISITE_NORMALIZATION,
        "type_checker/program_evidence/entries/68_count_prerequisite_normalization",
        256,
    ),
    (
        WAVE_PLAN_PHASE,
        "type_checker/program_evidence/entries/70_plan_solver_wave",
        1,
    ),
];

pub(super) struct ProofKernels {
    passes: Vec<PassData>,
}
impl ProofKernels {
    pub fn load(device: &wgpu::Device) -> Result<Self> {
        let passes = PROOF_KEYS
            .iter()
            .map(|(_, key, _)| {
                passes_core::make_pass_data_from_shader_key(device, key, "main", key)
            })
            .collect::<Result<Vec<_>>>()?;
        Ok(Self { passes })
    }
    pub fn record_normalization(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        work: Span,
        catalog: &Arena,
        input: &Arena,
        output: &Arena,
        proof: ProofResources<'_>,
    ) -> Result<()> {
        for phase in 41..=47 {
            let span = if matches!(phase, 45 | 47) {
                Span::new(0, 1)?
            } else {
                work
            };
            self.record(device, encoder, phase, span, catalog, input, output, proof)?;
        }
        Ok(())
    }
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
        ensure!(
            !matches!(phase, SELECTION_PHASE | SUBSTITUTION_PHASE | IMPLEMENTATION_PROOF_PHASE
                | WAVE_PLAN_PHASE | COUNT_ORIGINAL_NORMALIZATION | COUNT_PREREQUISITE_NORMALIZATION),
            "proof stage {phase} records through its own recorder"
        );
        let index = PROOF_KEYS
            .iter()
            .position(|(entry, _, _)| *entry == phase)
            .ok_or_else(|| anyhow::anyhow!("unregistered proof stage {phase}"))?;
        self.record_index(device, encoder, index, span, catalog, input, output, proof)
    }
    /// Counts the rows the next normalization of `span` reserves (phase 67
    /// for original Works, 68 for prerequisite Works) into a zeroed demand
    /// table, one word per proof-store table, which it returns.
    pub fn record_normalization_count(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        phase: u32,
        span: Span,
        catalog: &Arena,
        input: &Arena,
        output: &Arena,
        proof: ProofResources<'_>,
    ) -> Result<LaniusBuffer<u32>> {
        ensure!(
            matches!(phase, COUNT_ORIGINAL_NORMALIZATION | COUNT_PREREQUISITE_NORMALIZATION),
            "proof stage {phase} is not a normalization count"
        );
        // One shared role: the solver reads each count back before it
        // records the next one, so the queued zero write never races a use.
        let demand = catalog.workspace().shared("program_evidence.proof_demand").buffer(
            PROOF_STORE_TABLES as u32,
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            Some(&[0; PROOF_STORE_TABLES]),
        )?;
        let index = PROOF_KEYS
            .iter()
            .position(|(entry, _, _)| *entry == phase)
            .ok_or_else(|| anyhow::anyhow!("unregistered proof stage {phase}"))?;
        record_phase_with_resources(device, encoder, &self.passes[index], phase, span,
            PROOF_KEYS[index].2, catalog, input, output, Some(proof), None, None, Some(&demand))?;
        Ok(demand)
    }
    /// INTERIM (P7): work selection runs as four dispatches per chunk of at
    /// most THREAD_SCRATCH_SLOTS work rows, so no kernel inlines more than
    /// one search: exact implementation match, caller assumption search,
    /// generic implementation match (the first kernel again, as phase 65),
    /// then the finish (proof_frontier_selection.slang).
    pub fn record_selection(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        span: Span,
        catalog: &Arena,
        input: &Arena,
        output: &Arena,
        proof: ProofResources<'_>,
    ) -> Result<()> {
        self.record_chunked(device, encoder, &SELECTION_STEPS, span, catalog, input, output, proof)
    }
    /// INTERIM (P7): substitution admission walks each selected work's
    /// substitution as three dispatches per chunk of at most
    /// THREAD_SCRATCH_SLOTS work rows: up to the head match, the head's root
    /// unification, then the bindings (proof_substitution_walk.slang).
    pub fn record_substitutions(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        span: Span,
        catalog: &Arena,
        input: &Arena,
        output: &Arena,
        proof: ProofResources<'_>,
    ) -> Result<()> {
        self.record_chunked(device, encoder, &SUBSTITUTION_STEPS, span, catalog, input, output, proof)
    }
    /// INTERIM (P7): implementation proof admission over ready proof events:
    /// the same three walk dispatches per chunk as record_substitutions, then
    /// the root unification kernel again (phase 66) for the proof's fixed
    /// prerequisite checks.
    pub fn record_implementation_proofs(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        span: Span,
        catalog: &Arena,
        input: &Arena,
        output: &Arena,
        proof: ProofResources<'_>,
    ) -> Result<()> {
        self.record_chunked(device, encoder, &IMPLEMENTATION_PROOF_STEPS, span, catalog, input,
            output, proof)
    }
    /// A proof stage split over several dispatches per chunk of at most
    /// THREAD_SCRATCH_SLOTS rows. Each step hands its rows' progress on to
    /// the next in the row's thread-scratch slot (proof_scratch_handoff.slang),
    /// so all steps of one chunk run before the next chunk's.
    fn record_chunked(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        steps: &[(&str, u32)],
        span: Span,
        catalog: &Arena,
        input: &Arena,
        output: &Arena,
        proof: ProofResources<'_>,
    ) -> Result<()> {
        let steps = steps
            .iter()
            .map(|&(key, phase)| {
                PROOF_KEYS
                    .iter()
                    .position(|(_, entry, _)| *entry == key)
                    .map(|index| (index, phase))
                    .ok_or_else(|| anyhow::anyhow!("unregistered proof kernel {key}"))
            })
            .collect::<Result<Vec<_>>>()?;
        let mut done = 0u32;
        while done < span.count {
            let count = (span.count - done).min(THREAD_SCRATCH_SLOTS);
            let chunk = Span::new(span.first.checked_add(done).expect("checked span"), count)?;
            for &(index, phase) in &steps {
                record_phase_with_proof(device, encoder, &self.passes[index], phase, chunk,
                    PROOF_KEYS[index].2, catalog, input, output, Some(proof))?;
            }
            done += count;
        }
        Ok(())
    }
    pub fn record_binding_rows(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        span: Span,
        catalog: &Arena,
        input: &Arena,
        output: &Arena,
        proof: ProofResources<'_>,
    ) -> Result<()> {
        let index = PROOF_KEYS
            .iter()
            .position(|(_, entry, _)| *entry == BINDING_ROWS)
            .expect("binding admission is a required proof kernel");
        self.record_index(device, encoder, index, span, catalog, input, output, proof)
    }
    pub fn record_assumption_proofs(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        span: Span,
        catalog: &Arena,
        input: &Arena,
        output: &Arena,
        proof: ProofResources<'_>,
    ) -> Result<()> {
        let index = PROOF_KEYS
            .iter()
            .position(|(_, entry, _)| *entry == ASSUMPTION_PROOFS)
            .expect("assumption admission is a required proof kernel");
        self.record_index(device, encoder, index, span, catalog, input, output, proof)
    }
    pub fn record_proof_edge_rows(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        span: Span,
        catalog: &Arena,
        input: &Arena,
        output: &Arena,
        proof: ProofResources<'_>,
    ) -> Result<()> {
        let index = PROOF_KEYS
            .iter()
            .position(|(_, entry, _)| *entry == PROOF_EDGE_ROWS)
            .expect("proof-edge admission is a required proof kernel");
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
            !single_dispatch(phase, threads) || (span.first == 0 && span.count == 1),
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
    pub const WORK_CURSOR: usize = 2;
    pub const REQUIREMENT_CURSOR: usize = 3;
    pub const QUEUE_CURSOR: usize = 4;
    pub const ROUNDS: usize = 12;
    pub const OVERFLOW_POINT: usize = 13;
    pub const OVERFLOW_ROWS: usize = 14;
    pub const CHUNK_ROWS: usize = 15;
    pub const SLOT_WORDS: usize = 16;
    /// Words the host reads back: the scalar state, not the span records.
    pub const READ_WORDS: u32 = 32;
    pub const STATE_WORDS: u32 = 64;
    pub const RUNNING: u32 = 0;
    pub const STOPPED: u32 = 1;
    pub const DONE: u32 = 2;
    pub const FAULT: u32 = 3;
    pub const OVERFLOW: u32 = 4;
    pub const FAULT_IDENTITY: u32 = 1;
    pub const FAULT_LAYOUT: u32 = 2;
    pub const FAULT_RECEIPT: u32 = 3;
    pub const FAULT_CURSOR: u32 = 4;
    pub const FAULT_REQUIREMENTS: u32 = 5;
}
// Slot words (proof_solver_wave.slang): ProgramEvidenceParams, indirect
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

/// Planning points, in recording order: where the host loop read the
/// counters back (dispatch/mod.rs, run_solver_attempt).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum WavePoint {
    FirstWork = 0,
    Round = 1,
    Selected = 2,
    Expanded = 3,
    Queue = 4,
    Emitted = 5,
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
        [WavePoint::FirstWork].into_iter().chain(Self::ROUND).find(|point| *point as u32 == word)
    }
    /// This point and the rest of its round; the first-work point is alone.
    pub fn remainder(self) -> &'static [WavePoint] {
        match self {
            WavePoint::FirstWork => &[WavePoint::FirstWork],
            point => &Self::ROUND[point as usize - 1..],
        }
    }
}

/// Row spans the planner computes (proof_solver_wave.slang, PSW_SPAN_*).
#[derive(Clone, Copy, PartialEq, Eq)]
enum WaveSpan {
    FirstWork = 0,
    FirstOne = 1,
    Work = 2,
    WorkOne = 3,
    Requirements = 4,
    SelectedWork = 5,
    Bindings = 6,
    SelectedOne = 7,
    ExpandedWork = 8,
    ExpandedOne = 9,
    Queue = 10,
    EmittedQueue = 11,
    ProofEdges = 12,
    EmittedOne = 13,
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
        )
    }
}

/// The steps between one point and the next, as the host loop recorded them:
/// groups of kernels over one span, each group dispatched chunk by chunk.
fn wave_segment(point: WavePoint) -> Result<Vec<(WaveSpan, Vec<(&'static str, u32)>)>> {
    let stage = |phase: u32| -> Result<(&'static str, u32)> {
        PROOF_KEYS
            .iter()
            .find(|(entry, _, _)| *entry == phase)
            .map(|(_, key, _)| (*key, phase))
            .ok_or_else(|| anyhow!("unregistered proof stage {phase}"))
    };
    use WaveSpan::*;
    Ok(match point {
        WavePoint::FirstWork => vec![(FirstWork, vec![stage(49)?]), (FirstOne, vec![stage(50)?])],
        WavePoint::Round => {
            // ProofKernels::record_normalization, 51, 52, 57, record_selection.
            let mut groups = Vec::new();
            for phase in 41..=47 {
                let span = if matches!(phase, 45 | 47) { WorkOne } else { Work };
                groups.push((span, vec![stage(phase)?]));
            }
            groups.push((Work, vec![stage(51)?]));
            groups.push((Work, vec![stage(52)?]));
            groups.push((Requirements, vec![stage(57)?]));
            groups.push((Work, SELECTION_STEPS.to_vec()));
            groups
        }
        WavePoint::Selected => vec![
            (SelectedWork, SUBSTITUTION_STEPS.to_vec()),
            (Bindings, vec![(BINDING_ROWS, SUBSTITUTION_PHASE)]),
            (SelectedOne, vec![stage(55)?]),
            (SelectedWork, vec![stage(56)?]),
        ],
        WavePoint::Expanded => vec![(ExpandedWork, vec![stage(49)?]), (ExpandedOne, vec![stage(50)?])],
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
    })
}

/// Words per step slot: whole uniform-offset alignments, at least the slot.
pub(super) fn wave_slot_words(device: &wgpu::Device) -> u32 {
    (device.limits().min_uniform_buffer_offset_alignment / 4).max(SLOT_MIN_WORDS)
}

/// The solver state of one attempt, planned and read only by the GPU
/// planner until the host reads it back.
pub(super) fn wave_state(device: &wgpu::Device, catalog: &Arena) -> Result<LaniusBuffer<u32>> {
    let mut words = [0u32; wave::STATE_WORDS as usize];
    words[wave::CHUNK_ROWS] = THREAD_SCRATCH_SLOTS;
    words[wave::SLOT_WORDS] = wave_slot_words(device);
    catalog.workspace().initialized(
        "program_evidence.solver_wave",
        wave::STATE_WORDS,
        wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        Some(&words),
    )
}

struct WaveStep {
    pass: usize,
    bindings: wgpu::BindGroup,
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

/// Recorded steps of some planning points with bind groups built once: each
/// step reads its parameters and indirect arguments from its slot, which the
/// point's planner rewrites every time it runs.
pub(super) struct WaveTemplate {
    slots: LaniusBuffer<u32>,
    steps: Vec<WaveStep>,
    pub chunks: u32,
    pub dispatches: usize,
}

impl ProofKernels {
    /// Whether every kernel of the recorded rounds chunks by thread-scratch
    /// slots, as the stepped recorder chunks it.
    pub fn waves_supported(&self) -> Result<bool> {
        for point in [WavePoint::FirstWork].into_iter().chain(WavePoint::ROUND) {
            for (_, steps) in wave_segment(point)? {
                for (key, _) in steps {
                    let index = proof_key_index(key)?;
                    if !passes_core::bind_group::declares_binding(&self.passes[index], 0, "thread_scratch") {
                        return Ok(false);
                    }
                }
            }
        }
        Ok(true)
    }

    /// Builds the steps of `points` with `chunks` chunk steps for every span
    /// that is not a single row.
    pub fn wave_template(
        &self,
        device: &wgpu::Device,
        points: &[WavePoint],
        chunks: u32,
        state: &LaniusBuffer<u32>,
        catalog: &Arena,
        input: &Arena,
        output: &Arena,
        proof: ProofResources<'_>,
    ) -> Result<WaveTemplate> {
        ensure!((1..=WAVE_MAX_CHUNKS).contains(&chunks), "solver wave chunk count {chunks}");
        let stride = wave_slot_words(device);
        // (pass, phase, span, chunk, recorded rows of the span) per slot.
        let mut slots: Vec<(usize, u32, WaveSpan, u32, u32)> = Vec::new();
        let mut segments = Vec::new();
        for &point in points {
            let first = slots.len();
            for (span, steps) in wave_segment(point)? {
                let span_chunks = if span.is_one() { 1 } else { chunks };
                let limit = span_chunks.saturating_mul(THREAD_SCRATCH_SLOTS);
                let steps = steps
                    .into_iter()
                    .map(|(key, phase)| proof_key_index(key).map(|index| (index, phase)))
                    .collect::<Result<Vec<_>>>()?;
                for chunk in 1..=span_chunks {
                    for &(index, phase) in &steps {
                        ensure!(
                            !single_dispatch(phase, PROOF_KEYS[index].2) || span.is_one(),
                            "singleton proof stage needs exactly one dispatch"
                        );
                        slots.push((index, phase, span, chunk, limit));
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
        let mut words = vec![0u32; total_words as usize];
        for (slot, &(index, phase, span, chunk, limit)) in slots.iter().enumerate() {
            let base = slot * stride as usize;
            let row = &mut words[base..base + stride as usize];
            row[2] = catalog.logical_words;
            row[3] = input.logical_words;
            row[4] = output.logical_words;
            row[5] = phase;
            row[SLOT_ARGS as usize + 1] = 1;
            row[SLOT_ARGS as usize + 2] = 1;
            row[SLOT_SPAN] = span as u32;
            row[SLOT_CHUNK] = chunk;
            row[SLOT_THREADS] = PROOF_KEYS[index].2;
            row[SLOT_LIMIT] = limit;
        }
        let workspace = catalog.workspace();
        let slot_buffer = workspace.initialized(
            "program_evidence.solver_wave_slots",
            total_words,
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::INDIRECT,
            Some(&words),
        )?;
        let scratch = thread_scratch(catalog)?;
        // One proof-store parameter block per phase.
        let mut phases = vec![WAVE_PLAN_PHASE];
        for &(_, phase, _, _, _) in &slots {
            if !phases.contains(&phase) {
                phases.push(phase);
            }
        }
        let proof_uniforms = phases
            .iter()
            .map(|&phase| workspace.initialized(
                "program_evidence.proof_params",
                8,
                wgpu::BufferUsages::UNIFORM,
                Some(&proof_params_words(proof, phase)),
            ))
            .collect::<Result<Vec<_>>>()?;
        let proof_uniform = |phase: u32| {
            &proof_uniforms[phases.iter().position(|entry| *entry == phase).expect("phase block")]
        };
        let plan = proof_key_index("type_checker/program_evidence/entries/70_plan_solver_wave")?;
        let slot_bytes = u64::from(stride) * 4;
        let params_size = NonZeroU64::new(32).expect("nonzero parameter block");
        let mut steps = Vec::with_capacity(slots.len() + segments.len());
        for (point, first, end) in segments {
            let params = workspace.initialized(
                "program_evidence.params",
                8,
                wgpu::BufferUsages::UNIFORM,
                Some(&[0, 1, catalog.logical_words, input.logical_words, output.logical_words,
                    WAVE_PLAN_PHASE, 0, 0]),
            )?;
            let plan_params = workspace.initialized(
                "program_evidence.solver_wave_plan",
                4,
                wgpu::BufferUsages::UNIFORM,
                Some(&[point as u32, u32::try_from(first)?, u32::try_from(end)?, 0]),
            )?;
            let resources = [
                ("program_evidence_params", params.as_entire_binding()),
                ("program_evidence_catalog", catalog.buffer.as_entire_binding()),
                ("program_evidence_batch", input.buffer.as_entire_binding()),
                ("program_evidence_output", output.buffer.as_entire_binding()),
                ("program_evidence_proof_store", proof.storage.buffer.as_entire_binding()),
                ("proof_store_params", proof_uniform(WAVE_PLAN_PHASE).as_entire_binding()),
                ("thread_scratch", scratch.as_entire_binding()),
                ("program_evidence_wave", state.as_entire_binding()),
                ("program_evidence_wave_slots", slot_buffer.as_entire_binding()),
                ("program_evidence_wave_plan", plan_params.as_entire_binding()),
            ];
            let bindings = passes_core::bind_group::create_bind_group_from_bindings(
                device,
                Some("program_evidence.solver_wave_plan"),
                &self.passes[plan],
                0,
                &resources,
            )?;
            steps.push(WaveStep { pass: plan, bindings, indirect: None });
            for slot in first..end {
                let (index, phase, _, _, _) = slots[slot];
                let offset = slot_buffer.absolute_offset(slot as u64 * slot_bytes);
                let resources = [
                    (
                        "program_evidence_params",
                        wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                            buffer: &slot_buffer.buffer,
                            offset,
                            size: Some(params_size),
                        }),
                    ),
                    ("program_evidence_catalog", catalog.buffer.as_entire_binding()),
                    ("program_evidence_batch", input.buffer.as_entire_binding()),
                    ("program_evidence_output", output.buffer.as_entire_binding()),
                    ("program_evidence_proof_store", proof.storage.buffer.as_entire_binding()),
                    ("proof_store_params", proof_uniform(phase).as_entire_binding()),
                    ("thread_scratch", scratch.as_entire_binding()),
                ];
                let bindings = passes_core::bind_group::create_bind_group_from_bindings(
                    device,
                    Some("program_evidence.bindings"),
                    &self.passes[index],
                    0,
                    &resources,
                )?;
                steps.push(WaveStep {
                    pass: index,
                    bindings,
                    indirect: Some(offset + u64::from(SLOT_ARGS) * 4),
                });
            }
        }
        let dispatches = steps.len();
        Ok(WaveTemplate { slots: slot_buffer, steps, chunks, dispatches })
    }

    /// Records every step of each template, in order, in one compute pass:
    /// most steps of a recorded round dispatch no workgroups, and a pass per
    /// step cost more than the steps. Operation limits and timers that cannot
    /// stamp inside a pass keep a pass per step.
    pub fn record_waves(&self, encoder: &mut wgpu::CommandEncoder, templates: &[&WaveTemplate]) {
        if crate::gpu::timer::operation_capture_requires_split_passes()
            || passes_core::debug_operation_limited()
        {
            for template in templates {
                for step in &template.steps {
                    dispatch_pass(encoder, &self.passes[step.pass], &step.bindings, step.launch(template));
                }
            }
            return;
        }
        passes_core::flush_deferred_compute(encoder);
        let timed = crate::gpu::timer::operation_capture_active();
        let mut compute = passes_core::begin_counted_compute_pass(
            encoder,
            &wgpu::ComputePassDescriptor {
                label: Some("program_evidence.solver_wave"),
                timestamp_writes: None,
            },
        );
        for template in templates {
            for step in &template.steps {
                let pass = &self.passes[step.pass];
                compute.set_pipeline(&pass.pipeline);
                compute.set_bind_group(0, Some(&step.bindings), &[]);
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
    "type_checker/program_evidence/native_layout/entries/00_initialize_recipes",
    "type_checker/program_evidence/native_layout/entries/01_clear_recipe_map",
    "type_checker/program_evidence/native_layout/entries/02_admit_recipes",
    "type_checker/program_evidence/native_layout/entries/03_admit_recipe_groups",
    "type_checker/program_evidence/native_layout/entries/04_freeze_recipes",
];

pub(super) struct RecipeKernels {
    passes: Vec<PassData>,
}
impl RecipeKernels {
    pub fn load(device: &wgpu::Device) -> Result<Self> {
        let passes = RECIPE_KEYS.iter()
            .map(|key| passes_core::make_pass_data_from_shader_key(device, key, "main", key))
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
        let key = "type_checker/program_evidence/native_layout/entries/05_materialize_proof_value";
        Ok(Self { pass: passes_core::make_pass_data_from_shader_key(device, key, "main", key)? })
    }
    pub fn record(&self, device: &wgpu::Device, encoder: &mut wgpu::CommandEncoder,
        catalog: &Arena, input: &Arena, output: &Arena, proof: ProofResources<'_>,
        recipes: &Arena, work: &Arena) -> Result<()> {
        record_phase_with_resources(device, encoder, &self.pass, 5, Span::new(0, 1)?, 1,
            catalog, input, output, Some(proof), Some(recipes), Some(work), None)
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
