use anyhow::{Result, ensure};

use super::{
    super::{abi::Span, catalog::FrozenCatalog},
    BatchPlan,
    arena::Arena,
};
use crate::gpu::{
    dispatch_capture,
    passes_core::{self, PassData},
};

// Ordinary literals are required by laniusc-shaders/build.rs artifact discovery.
const CATALOG_KEYS: [&str; 22] = [
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
    "type_checker/program_evidence/entries/02_09_admit_implementations",
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
        for (pass, (phase, count)) in self.passes.iter().zip(schedule) {
            let threads = if matches!(phase, 0 | 11) { 1 } else { 256 };
            record_phase(
                device,
                encoder,
                pass,
                phase,
                Span::new(0, count)?,
                threads,
                storage,
                input,
                output,
            )?;
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
    // Walker frames live in one retained table shared by every such dispatch:
    // fixed size, so its binding never changes. Each chunk owns all slots.
    let scratch = if passes_core::bind_group::declares_binding(pass, 0, "thread_scratch") {
        Some(
            catalog
                .workspace()
                .shared("program_evidence.thread_scratch")
                .buffer(THREAD_SCRATCH_SLOTS * THREAD_SCRATCH_CELLS * 4, wgpu::BufferUsages::STORAGE, None)?,
        )
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
                Some(&[
                    proof.storage.logical_words,
                    proof.epoch as u32,
                    (proof.epoch >> 32) as u32,
                    proof.arena_id as u32,
                    (proof.arena_id >> 32) as u32,
                    proof.serial,
                    phase,
                    0,
                ]),
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
        let bindings = passes_core::bind_group::create_bind_group_from_bindings(
            device,
            Some("program_evidence.bindings"),
            pass,
            0,
            &resources,
        )?;
        passes_core::flush_deferred_compute(encoder);
        let groups = (count.div_ceil(threads), 1, 1);
        // LANIUS_DEBUG_CAPTURE_PASS support (tools/cpu_kernel_replay.py).
        let captured = dispatch_capture::debug_capture_begin(
            encoder,
            &pass.shader_id,
            pass,
            &bindings,
            &[],
            dispatch_capture::CaptureLaunch::Direct(groups),
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
            compute.set_bind_group(0, Some(&bindings), &[]);
            passes_core::record_compute_dispatch();
            if !crate::gpu::passes_core::debug_operation_skipped() {
                compute.dispatch_workgroups(groups.0, groups.1, groups.2);
            }
        }
        dispatch_capture::debug_capture_end(encoder, captured);
        done += count;
    }
    Ok(())
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
    (
        45,
        "type_checker/program_evidence/entries/45_commit_normalized_terms",
        1,
    ),
    (
        46,
        "type_checker/program_evidence/entries/46_hash_normalized_goals",
        256,
    ),
    (
        47,
        "type_checker/program_evidence/entries/47_commit_normalized_goals",
        1,
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
    (
        53,
        "type_checker/program_evidence/entries/53_select_implementations",
        256,
    ),
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
    (
        54,
        "type_checker/program_evidence/entries/54_admit_binding_rows",
        256,
    ),
    (
        55,
        "type_checker/program_evidence/entries/55_commit_substitutions",
        1,
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
    (
        59,
        "type_checker/program_evidence/entries/59_admit_assumption_proofs",
        256,
    ),
    (
        59,
        "type_checker/program_evidence/entries/59_admit_proof_edge_rows",
        256,
    ),
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
            !matches!(phase, SELECTION_PHASE | SUBSTITUTION_PHASE | IMPLEMENTATION_PROOF_PHASE),
            "proof stage {phase} records through its own recorder"
        );
        let index = PROOF_KEYS
            .iter()
            .position(|(entry, _, _)| *entry == phase)
            .ok_or_else(|| anyhow::anyhow!("unregistered proof stage {phase}"))?;
        self.record_index(device, encoder, index, span, catalog, input, output, proof)
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
        let implementations = "type_checker/program_evidence/entries/53_select_implementations";
        let steps = [
            (implementations, SELECTION_PHASE),
            ("type_checker/program_evidence/entries/53_select_assumptions", SELECTION_PHASE),
            (implementations, GENERIC_SELECTION_PHASE),
            ("type_checker/program_evidence/entries/53_select_work", SELECTION_PHASE),
        ];
        self.record_chunked(device, encoder, &steps, span, catalog, input, output, proof)
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
        let steps = [
            (WALK_GOALS, SUBSTITUTION_PHASE),
            (WALK_ROOTS, SUBSTITUTION_PHASE),
            (WALK_BINDINGS, SUBSTITUTION_PHASE),
        ];
        self.record_chunked(device, encoder, &steps, span, catalog, input, output, proof)
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
        let steps = [
            (WALK_GOALS, IMPLEMENTATION_PROOF_PHASE),
            (WALK_ROOTS, IMPLEMENTATION_PROOF_PHASE),
            (WALK_BINDINGS, IMPLEMENTATION_PROOF_PHASE),
            (WALK_ROOTS, PREREQUISITE_PHASE),
        ];
        self.record_chunked(device, encoder, &steps, span, catalog, input, output, proof)
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
        let key = "type_checker/program_evidence/entries/54_admit_binding_rows";
        let index = PROOF_KEYS
            .iter()
            .position(|(_, entry, _)| *entry == key)
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
        let key = "type_checker/program_evidence/entries/59_admit_assumption_proofs";
        let index = PROOF_KEYS
            .iter()
            .position(|(_, entry, _)| *entry == key)
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
        let key = "type_checker/program_evidence/entries/59_admit_proof_edge_rows";
        let index = PROOF_KEYS
            .iter()
            .position(|(_, entry, _)| *entry == key)
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
                threads, storage, input, output, None, Some(recipes), None)?;
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
            catalog, input, output, Some(proof), Some(recipes), Some(work))
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
