//! One graph-owned lowering pipeline from compact semantic HIR to the selected
//! target LIR and artifact boundary.

use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};

use anyhow::{Context, Result};

use super::{
    lowering_ir::{
        LOWERING_PROGRAM_FAILURE_BYTES, LOWERING_PROGRAM_SLOTS,
        LoweringArtifactKind,
        LoweringCapacities,
        LoweringStatus,
        LoweringTarget,
        lowering_compiler_graph_for_artifact,
        lowering_resource_bytes_for_artifact,
    },
    optimization::GpuOptimizationStage,
    semantics::{
        GpuSemanticHirInputs,
        GpuSemanticLoweringStage,
        LoweringOutputDemand,
        semantic_input_views,
    },
    wasm::instructions::GpuWasmLirStage,
    x86::instructions::GpuX86LirStage,
};
use crate::{
    gpu::{
        buffers::{LaniusBuffer, TrackedBufferView, readback_bytes, with_uniform_buffer_arena},
        compiler_graph::{CompilerGraphWorkspace, PhaseResetPlan},
        passes_core::{SubmissionSplit, map_readback_blocking},
        timer::GpuTimer,
    },
    type_checker::GpuSemanticArtifactView,
};

/// A lowering job's status and its x86 object's metadata words.
pub(crate) struct X86ObjectStatus {
    status: LoweringStatus,
    metadata: Vec<u32>,
}

#[derive(Debug)]
pub(crate) struct LoweringFailure {
    pub(crate) status: LoweringStatus,
}

impl std::fmt::Display for LoweringFailure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let status = self.status;
        write!(
            formatter,
            "GPU lowering failed (flags=0x{:x}, semantic row={}, OptIR row={}, source HIR={}, target opcode={}, required capacity={}, available capacity={}, diagnostic reason={}, diagnostic detail kind={}, diagnostic detail={})",
            status.flags,
            status.first_unsupported_semantic_row,
            status.first_unsupported_opt_row,
            status.first_unsupported_hir,
            status.first_unsupported_target_op,
            status.required_capacity,
            status.available_capacity,
            status.diagnostic_reason,
            status.diagnostic_detail_kind,
            status.diagnostic_detail,
        )
    }
}

impl std::error::Error for LoweringFailure {}

enum TargetStage {
    X86_64(GpuX86LirStage),
    Wasm(GpuWasmLirStage),
}

impl TargetStage {
    fn lowering_target(&self) -> LoweringTarget {
        match self {
            Self::X86_64(_) => LoweringTarget::X86_64,
            Self::Wasm(_) => LoweringTarget::Wasm,
        }
    }

    fn compiler_phase(&self) -> crate::gpu::timer::GpuCompilerPhase {
        match self {
            Self::X86_64(_) => crate::gpu::timer::GpuCompilerPhase::X86Emission,
            Self::Wasm(_) => crate::gpu::timer::GpuCompilerPhase::WasmEmission,
        }
    }

    fn lowering_timer_label(&self) -> &'static str {
        match self {
            Self::X86_64(_) => "codegen.x86.lowering.done",
            Self::Wasm(_) => "codegen.wasm.lowering.done",
        }
    }

    fn emission_timer_label(&self) -> &'static str {
        match self {
            Self::X86_64(_) => "codegen.x86.emission.done",
            Self::Wasm(_) => "codegen.wasm.emission.done",
        }
    }

    fn record_count_page(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        page_id: usize,
        timer: &mut Option<&mut GpuTimer>,
        job: Option<LoweringCapacities>,
    ) -> Result<()> {
        match self {
            Self::X86_64(stage) => stage.record_count_page(encoder, page_id, timer, job),
            Self::Wasm(stage) => stage.record_count_page(encoder, page_id),
        }
    }

    fn count_page_count(&self) -> usize {
        match self {
            Self::X86_64(stage) => stage.count_page_count(),
            Self::Wasm(stage) => stage.count_page_count(),
        }
    }

    fn target_page_count(&self) -> usize {
        match self {
            Self::X86_64(stage) => stage.target_page_count(),
            Self::Wasm(stage) => stage.target_page_count(),
        }
    }

    fn record_before_target_pages(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        match self {
            Self::X86_64(stage) => stage.record_before_target_pages(encoder),
            Self::Wasm(stage) => stage.record_before_target_pages(encoder),
        }
    }

    fn record_measure_page(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        page_id: usize,
    ) -> Result<()> {
        match self {
            Self::X86_64(stage) => stage.record_measure_page(encoder, page_id),
            Self::Wasm(stage) => stage.record_measure_page(encoder, page_id),
        }
    }

    fn record_between_target_pages(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        object: bool,
        job: Option<LoweringCapacities>,
    ) -> Result<()> {
        match self {
            Self::X86_64(stage) => stage.record_between_target_pages(encoder, object, job),
            Self::Wasm(stage) => stage.record_between_target_pages(encoder, object),
        }
    }

    fn record_emit_page(&self, encoder: &mut wgpu::CommandEncoder, page_id: usize) -> Result<()> {
        match self {
            Self::X86_64(stage) => stage.record_emit_page(encoder, page_id),
            Self::Wasm(stage) => stage.record_emit_page(encoder, page_id),
        }
    }

    fn record_after_target_pages(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        object: bool,
        sized_job: Option<LoweringCapacities>,
    ) -> Result<()> {
        match self {
            Self::X86_64(stage) => stage.record_after_target_pages(encoder, object, sized_job),
            Self::Wasm(stage) => stage.record_after_target_pages(encoder, object),
        }
    }

    fn set_object_identity(
        &self,
        queue: &wgpu::Queue,
        library_id: u32,
        unit_id: u32,
    ) -> Result<()> {
        match self {
            Self::X86_64(stage) => stage.set_object_identity(queue, library_id, unit_id),
            Self::Wasm(stage) => stage.set_object_identity(queue, library_id, unit_id),
        }
    }
}

/// Daemon-resident ownership root for both lowering levels. The graph assigns
/// all phase-local aliases in one workspace, while the target enum guarantees
/// that an inactive backend consumes no resident slots.
///
/// Target and semantic bind groups are derived from reflected resource
/// identities and reused while their graph-owned inputs remain resident.
pub(crate) struct GpuLoweringPipeline {
    capacities: LoweringCapacities,
    artifact_kind: LoweringArtifactKind,
    upstream_signature: Vec<(u64, u64, u64)>,
    semantic_input_signature: Vec<(u64, u64, u64)>,
    /// The arena; a projected variant shares its frontend pipeline's.
    workspace: Arc<CompilerGraphWorkspace>,
    semantic: GpuSemanticLoweringStage,
    optimizer: GpuOptimizationStage,
    target: TargetStage,
    /// The status, then the job's semantic and target row totals: one map.
    /// An x86 object job's is its object metadata readback, with the status
    /// at `status_base` after the metadata.
    status_readback: LaniusBuffer<u8>,
    status_base: usize,
    status_readback_copy: crate::gpu::operations::CopyBufferOperation,
    program_failed_copies: Vec<crate::gpu::operations::CopyBufferOperation>,
    job_totals_copies: [crate::gpu::operations::CopyBufferOperation; 2],
    /// Phase resets of recent job capacities (`job_capacities`).
    phase_reset_plans: Mutex<Vec<(LoweringCapacities, Arc<PhaseResetPlan>)>>,
    /// The capacities the last recorded job could address. Its artifact must
    /// fit them, as it would in a fresh workspace for the job.
    recorded_job: Mutex<LoweringCapacities>,
    /// The semantic rows the last finished job counted on the GPU
    /// (read with the status).
    measured_semantic_rows: std::sync::atomic::AtomicU32,
    // Per-workspace fault injection: exercise output retries without making
    // unrelated concurrent tests run with artificially small capacities.
    #[cfg(test)]
    next_test_artifact_limit: std::sync::atomic::AtomicU32,
    #[cfg(test)]
    test_output_retries: std::sync::atomic::AtomicUsize,
}

/// Sets the capacity failure a GPU check against `job` would set for a job
/// with `semantic_rows` semantic and `target_rows` target rows.
fn flag_job_totals(
    status: &mut LoweringStatus,
    job: LoweringCapacities,
    semantic_rows: u32,
    target_rows: u32,
) {
    use super::lowering_ir::opcode::{LOWERING_STATUS_SEMANTIC_CAPACITY, LOWERING_STATUS_TARGET_CAPACITY};
    for (flag, required, available) in [
        (LOWERING_STATUS_SEMANTIC_CAPACITY, semantic_rows, job.semantic_instructions),
        (LOWERING_STATUS_TARGET_CAPACITY, target_rows, job.target_instructions),
    ] {
        if required > available {
            status.flags |= flag;
            status.required_capacity = status.required_capacity.max(required);
            status.available_capacity = status.available_capacity.min(available);
        }
    }
}

/// Capacity growth follows the GPU's measured requirement. Bucket rounding and
/// artifact arithmetic must fail rather than saturating into a smaller arena.
fn checked_output_bucket(value: u32) -> Result<u32, String> {
    value
        .checked_add(4095)
        .map(|value| value / 4096 * 4096)
        .ok_or_else(|| "lowering output capacity bucket overflows u32".to_string())
}

fn output_demand_for_status(
    status: LoweringStatus,
    job: LoweringCapacities,
    target: LoweringTarget,
    semantic_rows: u32,
) -> Result<Option<LoweringOutputDemand>, String> {
    use super::lowering_ir::opcode::{
        LOWERING_STATUS_ARTIFACT_CAPACITY,
        LOWERING_STATUS_SEMANTIC_CAPACITY,
        LOWERING_STATUS_TARGET_CAPACITY,
    };
    // A job past its semantic capacity lowered only a prefix of its rows,
    // so its other flags may come from the cut. The GPU counted every row
    // (`semantic_lir_total`), so the retry grows to that count and the
    // other failures, if real, recur in the retry.
    if status.flags & LOWERING_STATUS_SEMANTIC_CAPACITY != 0
        && semantic_rows > job.semantic_instructions
    {
        return Ok(Some(LoweringOutputDemand {
            semantic_instructions: checked_output_bucket(semantic_rows)?,
            target_instructions: job.target_instructions,
            artifact_bytes: job.artifact_bytes,
        }));
    }
    // Other flags share the capacity words. Mixed failures have no unambiguous
    // row/byte requirement and must retain their original diagnostics.
    if !matches!(
        status.flags,
        LOWERING_STATUS_TARGET_CAPACITY | LOWERING_STATUS_ARTIFACT_CAPACITY
    ) || status.diagnostic_reason != 0
    {
        return Ok(None);
    }
    let mut demand = LoweringOutputDemand {
        semantic_instructions: job.semantic_instructions,
        target_instructions: job.target_instructions,
        artifact_bytes: job.artifact_bytes,
    };
    if status.required_capacity <= status.available_capacity {
        return Err(
            "GPU lowering capacity failure did not report a larger requirement".to_string(),
        );
    }
    if status.flags == LOWERING_STATUS_TARGET_CAPACITY {
        if status.required_capacity <= job.target_instructions {
            return Err("GPU target demand does not exceed the recorded job capacity".to_string());
        }
        demand.target_instructions = checked_output_bucket(status.required_capacity)?;
        let artifact = LoweringCapacities::artifact_bytes_for(
            job.source_bytes,
            job.hir_nodes,
            demand.target_instructions,
            target,
        )
        .ok_or_else(|| "lowering target artifact capacity overflows u32".to_string())?;
        demand.artifact_bytes = checked_output_bucket(artifact.max(job.artifact_bytes))?;
    } else {
        if status.required_capacity <= job.artifact_bytes {
            return Err(
                "GPU artifact demand does not exceed the recorded job capacity".to_string(),
            );
        }
        demand.artifact_bytes = checked_output_bucket(status.required_capacity)?;
    }
    Ok(Some(demand))
}

fn artifact_capacity_status(required: u32, available: u32) -> LoweringStatus {
    LoweringStatus {
        flags: super::lowering_ir::opcode::LOWERING_STATUS_ARTIFACT_CAPACITY,
        required_capacity: required,
        available_capacity: available,
        first_unsupported_hir: u32::MAX,
        first_unsupported_semantic_row: u32::MAX,
        first_unsupported_opt_row: u32::MAX,
        first_unsupported_target_op: u32::MAX,
        diagnostic_detail: u32::MAX,
        ..LoweringStatus::default()
    }
}

fn apply_output_demand(
    mut job: LoweringCapacities,
    demand: LoweringOutputDemand,
    built: LoweringCapacities,
) -> LoweringCapacities {
    job.semantic_instructions = job
        .semantic_instructions
        .max(demand.semantic_instructions)
        .min(built.semantic_instructions);
    job.target_instructions = job
        .target_instructions
        .max(demand.target_instructions)
        .min(built.target_instructions);
    job.artifact_bytes = job
        .artifact_bytes
        .max(demand.artifact_bytes)
        .min(built.artifact_bytes);
    job
}

/// Job phase resets the pipeline keeps, most recent last.
const PHASE_RESET_PLAN_CACHE: usize = 8;


/// Whether the job-sized direct lowering operations (`JobSized`) record the
/// job's grid. A test can keep every workspace's built grid with
/// `TEST_JOB_SIZED_DIRECT_OPS`.
fn job_sized_direct_ops() -> bool {
    #[cfg(test)]
    {
        if TEST_JOB_SIZED_DIRECT_OPS.load(std::sync::atomic::Ordering::Relaxed) == 0 {
            return false;
        }
    }
    true
}

/// Test override of `job_sized_direct_ops`: 0 turns the job grids off,
/// anything else leaves them on.
#[cfg(test)]
pub(crate) static TEST_JOB_SIZED_DIRECT_OPS: std::sync::atomic::AtomicU8 =
    std::sync::atomic::AtomicU8::new(u8::MAX);

/// Tests set this to lower every job with `LoweringJobBounds::CONSERVATIVE`
/// in place of the bounds it passes, so a test can compare both through the
/// production entry points.
#[cfg(test)]
pub(crate) static TEST_CONSERVATIVE_LOWERING_BOUNDS: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);

/// The bounds a job lowers with: its own, unless a test asks for the
/// conservative ones (`TEST_CONSERVATIVE_LOWERING_BOUNDS`).
fn job_bounds(bounds: super::semantics::LoweringJobBounds) -> super::semantics::LoweringJobBounds {
    #[cfg(test)]
    {
        if TEST_CONSERVATIVE_LOWERING_BOUNDS.load(std::sync::atomic::Ordering::Relaxed) {
            return super::semantics::LoweringJobBounds::CONSERVATIVE;
        }
    }
    bounds
}

/// Lazily materialized, capacity-covering workspace for one target.
///
/// Shader pipelines are prepared before the daemon reports ready. This cache
/// owns only capacity-dependent buffers, uniforms, bind groups, and readback
/// storage, so an idle trim can return job memory without invalidating kernel
/// readiness.
///
/// One arena (`CompilerGraphWorkspace`) is resident per target. A pipeline
/// binds that arena and one set of HIR and semantic input buffers. Two input
/// sets alternate in every retained native build: the frontend units'
/// type-check outputs (`current`) and the retained projection's batch
/// columns (`projected`). The projected pipeline is a variant over the
/// frontend pipeline's arena: it builds its own stages (uniforms and bind
/// groups) and allocates no arena. Rebuilding the arena for each input set
/// cost 52 to 62 ms of host time twice per warm settings build.
pub(crate) struct GpuLoweringWorkspaceCache {
    target: LoweringTarget,
    /// Lowering of a frontend unit; its arena aliases the dead type-check
    /// tails and is the one resident arena.
    current: Mutex<Option<Arc<GpuLoweringPipeline>>>,
    /// The capacities of the workspace `release` dropped. The next workspace
    /// covers them, as the lexer and type-check workspaces keep their floors
    /// across a frontend replacement. Without it a job whose units have
    /// different shapes (a template replay is a few tokens beside a 1.4 MB
    /// original) reallocates the multi-gigabyte workspace on the next job.
    floor: Mutex<Option<LoweringCapacities>>,
    /// Lowering of retained-projection batches
    /// (docs/compiler-retained-projection.md), over `current`'s arena.
    projected: Mutex<Option<Arc<GpuLoweringPipeline>>>,
    /// The capacities projected object batches asked for. The next frontend
    /// object arena covers them, so the projection's variant fits it.
    projected_demand: Mutex<Option<LoweringCapacities>>,
}

/// `LANIUS_REPORT=buffers`: a new lowering arena's capacities, its storage
/// slot bytes, the dead upstream bytes it may reuse, and its largest
/// resources.
fn report_lowering_graph_bytes(
    graph: &crate::gpu::compiler_graph::CompilerGraph,
    capacities: LoweringCapacities,
    upstream: &[TrackedBufferView<'_>],
) {
    let slot_bytes = graph.workspace_plan().slots.iter().map(|slot| slot.bytes).sum::<u64>();
    let upstream_bytes = upstream_storage_signature(upstream)
        .iter()
        .map(|(_, _, bytes)| bytes)
        .sum::<u64>();
    eprintln!(
        "lowering_arena capacities={capacities:?} slots={} slot_bytes={slot_bytes} upstream_bytes={upstream_bytes}",
        graph.workspace_plan().slots.len(),
    );
    let mut resources = graph
        .resources()
        .iter()
        .map(|resource| (resource.bytes, resource.name, resource.class))
        .collect::<Vec<_>>();
    resources.sort_unstable_by(|left, right| right.0.cmp(&left.0));
    for (bytes, name, class) in resources.iter().take(16) {
        eprintln!("lowering_resource bytes={bytes} class={class:?} name={name}");
    }
}

fn upstream_storage_signature(upstream: &[TrackedBufferView<'_>]) -> Vec<(u64, u64, u64)> {
    let mut unique = BTreeMap::<u64, (u64, u64)>::new();
    for buffer in upstream {
        let Some(allocation) = buffer.allocation_id() else {
            continue;
        };
        unique
            .entry(allocation)
            .and_modify(|range| {
                if buffer.byte_size > range.1 {
                    *range = (buffer.byte_offset, buffer.byte_size);
                }
            })
            .or_insert((buffer.byte_offset, buffer.byte_size));
    }
    unique
        .into_iter()
        .map(|(allocation, (offset, bytes))| (allocation, offset, bytes))
        .collect()
}

fn exact_buffer_signature(buffers: &[TrackedBufferView<'_>]) -> Vec<(u64, u64, u64)> {
    buffers
        .iter()
        .map(|buffer| {
            (
                buffer.allocation_id().unwrap_or(0),
                buffer.byte_offset,
                buffer.byte_size,
            )
        })
        .collect()
}

impl GpuLoweringWorkspaceCache {
    pub(crate) fn new(target: LoweringTarget) -> Self {
        Self {
            target,
            current: Mutex::new(None),
            floor: Mutex::new(None),
            projected: Mutex::new(None),
            projected_demand: Mutex::new(None),
        }
    }

    /// The projection's capacities an arena for `artifact_kind` must cover.
    fn projected_demand(&self, artifact_kind: LoweringArtifactKind) -> Option<LoweringCapacities> {
        if artifact_kind != LoweringArtifactKind::Object {
            return None;
        }
        *self
            .projected_demand
            .lock()
            .expect("projected lowering demand poisoned")
    }

    pub(crate) fn ensure(
        &self,
        device: &wgpu::Device,
        kernels: &crate::gpu::kernels::KernelRegistry,
        source_bytes: u32,
        tokens: u32,
        hir_nodes: u32,
        artifact_kind: LoweringArtifactKind,
        upstream: &[TrackedBufferView<'_>],
        hir: GpuSemanticHirInputs<'_>,
        semantic: GpuSemanticArtifactView<'_>,
    ) -> Result<Arc<GpuLoweringPipeline>, String> {
        let required =
            LoweringCapacities::initial_for_frontend_unit(source_bytes, tokens, hir_nodes, self.target)?
                .bucketed();
        let demand = self.projected_demand(artifact_kind);
        let mut current = self
            .current
            .lock()
            .expect("lowering workspace cache poisoned");
        let upstream_signature = upstream_storage_signature(upstream);
        let semantic_input_signature = exact_buffer_signature(&semantic_input_views(hir, semantic));
        if let Some(pipeline) = current.as_ref()
            && pipeline.capacities.covers(required)
            && demand.is_none_or(|demand| pipeline.capacities.covers(demand))
            && pipeline.artifact_kind == artifact_kind
            && pipeline.upstream_signature == upstream_signature
            && pipeline.semantic_input_signature == semantic_input_signature
        {
            return Ok(Arc::clone(pipeline));
        }
        let floor = *self.floor.lock().expect("lowering workspace floor poisoned");
        let capacities = current.as_ref().map(|pipeline| pipeline.capacities).or(floor)
            .map_or(required, |previous| previous.grow_to_cover(required));
        let capacities = demand.map_or(capacities, |demand| capacities.grow_to_cover(demand));
        // Reflected bind groups in the old pipelines own every lowering
        // arena. Destroy that complete identity graph (the projected variant
        // shares the arena) before allocating its replacement; otherwise a
        // small capacity increase transiently makes both multi-gigabyte
        // workspaces resident.
        let old = (
            current.take(),
            self.projected
                .lock()
                .expect("projected lowering workspace cache poisoned")
                .take(),
        );
        drop(old);
        let _ = device.poll(wgpu::PollType::wait_indefinitely());
        let pipeline = Arc::new(
            GpuLoweringPipeline::new_with_upstream(
                device,
                kernels,
                capacities,
                self.target,
                artifact_kind,
                upstream,
                upstream_signature,
                semantic_input_signature,
                hir,
                semantic,
            )
            .map_err(|err| format!("{err:#}"))?,
        );
        *current = Some(Arc::clone(&pipeline));
        Ok(pipeline)
    }

    /// `ensure` for a retained-projection batch. It binds the frontend
    /// pipeline's arena, whose type-check upstream is dead while instances
    /// lower, and builds only the stages over the batch columns. Without a
    /// covering frontend arena it builds a standalone one; the next frontend
    /// arena then grows to cover the batch (`projected_demand`).
    pub(crate) fn ensure_projected(
        &self,
        device: &wgpu::Device,
        kernels: &crate::gpu::kernels::KernelRegistry,
        source_bytes: u32,
        tokens: u32,
        hir_nodes: u32,
        artifact_kind: LoweringArtifactKind,
        hir: GpuSemanticHirInputs<'_>,
        semantic: GpuSemanticArtifactView<'_>,
    ) -> Result<Arc<GpuLoweringPipeline>, String> {
        let required =
            LoweringCapacities::initial_for_frontend_unit(source_bytes, tokens, hir_nodes, self.target)?
                .bucketed();
        let current = self
            .current
            .lock()
            .expect("lowering workspace cache poisoned");
        let mut projected = self
            .projected
            .lock()
            .expect("projected lowering workspace cache poisoned");
        let required = {
            let mut demand = self
                .projected_demand
                .lock()
                .expect("projected lowering demand poisoned");
            let grown = demand.map_or(required, |demand| demand.grow_to_cover(required));
            *demand = Some(grown);
            grown
        };
        let semantic_input_signature = exact_buffer_signature(&semantic_input_views(hir, semantic));
        if let Some(pipeline) = projected.as_ref()
            && pipeline.capacities.covers(required)
            && pipeline.artifact_kind == artifact_kind
            && pipeline.semantic_input_signature == semantic_input_signature
        {
            return Ok(Arc::clone(pipeline));
        }
        // Drop the old variant (or standalone arena) before building.
        let old = projected.take();
        drop(old);
        let pipeline = match current.as_ref() {
            Some(base)
                if base.capacities.covers(required) && base.artifact_kind == artifact_kind =>
            {
                GpuLoweringPipeline::new_variant(device, kernels, base, semantic_input_signature, hir, semantic)
            }
            _ => {
                let _ = device.poll(wgpu::PollType::wait_indefinitely());
                GpuLoweringPipeline::new_with_upstream(
                    device,
                    kernels,
                    required,
                    self.target,
                    artifact_kind,
                    &[],
                    Vec::new(),
                    semantic_input_signature,
                    hir,
                    semantic,
                )
            }
        }
        .map_err(|err| format!("{err:#}"))?;
        let pipeline = Arc::new(pipeline);
        *projected = Some(Arc::clone(&pipeline));
        Ok(pipeline)
    }

    /// `grow_output` for a projected batch: the batch's next pipeline, and
    /// the next frontend arena, cover `demand`.
    pub(crate) fn grow_projected_output(
        &self,
        device: &wgpu::Device,
        demand: LoweringOutputDemand,
    ) -> Result<(), String> {
        let mut projected = self
            .projected
            .lock()
            .expect("projected lowering workspace cache poisoned");
        let pipeline = projected
            .as_ref()
            .ok_or_else(|| "projected lowering workspace is not initialized".to_string())?;
        let mut required = pipeline.capacities;
        required.semantic_instructions = checked_output_bucket(
            required.semantic_instructions.max(demand.semantic_instructions),
        )?;
        required.target_instructions =
            checked_output_bucket(required.target_instructions.max(demand.target_instructions))?;
        required.artifact_bytes =
            checked_output_bucket(required.artifact_bytes.max(demand.artifact_bytes))?;
        if pipeline.capacities.covers(required) {
            return Ok(());
        }
        lowering_compiler_graph_for_artifact(required, self.target, pipeline.artifact_kind)?
            .workspace_arena_layout(&device.limits())?;
        let mut stored = self
            .projected_demand
            .lock()
            .expect("projected lowering demand poisoned");
        *stored = Some(stored.map_or(required, |stored| stored.grow_to_cover(required)));
        let old = projected.take();
        drop(old);
        let _ = device.poll(wgpu::PollType::wait_indefinitely());
        Ok(())
    }

    /// Plan measured output growth before retiring the old graph. The caller
    /// replays the full frontend because lowering aliases dead upstream tails.
    pub(crate) fn grow_output(
        &self,
        device: &wgpu::Device,
        demand: LoweringOutputDemand,
    ) -> Result<(), String> {
        let mut current = self
            .current
            .lock()
            .expect("lowering workspace cache poisoned");
        let pipeline = current
            .as_ref()
            .ok_or_else(|| "lowering workspace is not initialized".to_string())?;
        let mut required = pipeline.capacities;
        required.semantic_instructions = checked_output_bucket(
            required.semantic_instructions.max(demand.semantic_instructions),
        )?;
        required.target_instructions =
            checked_output_bucket(required.target_instructions.max(demand.target_instructions))?;
        required.artifact_bytes =
            checked_output_bucket(required.artifact_bytes.max(demand.artifact_bytes))?;
        if pipeline.capacities.covers(required) {
            return Ok(());
        }
        // Reuse the graph's device-limit/arena planning before retiring the old
        // workspace. This plans host metadata and allocates no GPU buffers.
        lowering_compiler_graph_for_artifact(required, self.target, pipeline.artifact_kind)?
            .workspace_arena_layout(&device.limits())?;
        let mut floor = self
            .floor
            .lock()
            .expect("lowering workspace floor poisoned");
        *floor = Some(floor.map_or(required, |floor| floor.grow_to_cover(required)));
        let old = (
            current.take(),
            self.projected
                .lock()
                .expect("projected lowering workspace cache poisoned")
                .take(),
        );
        drop(old);
        let _ = device.poll(wgpu::PollType::wait_indefinitely());
        Ok(())
    }

    pub(crate) fn current(&self) -> Result<Arc<GpuLoweringPipeline>, String> {
        let target = match self.target {
            LoweringTarget::X86_64 => "x86_64",
            LoweringTarget::Wasm => "Wasm",
        };
        self.current
            .lock()
            .expect("lowering workspace cache poisoned")
            .as_ref()
            .cloned()
            .ok_or_else(|| format!("{target} lowering workspace is not initialized"))
    }

    /// Drops the workspace for a frontend replacement; the next one keeps
    /// at least its capacities. The projected variant shares its arena.
    pub(crate) fn release(&self) {
        let mut current = self
            .current
            .lock()
            .expect("lowering workspace cache poisoned");
        let released = current.take();
        self.projected
            .lock()
            .expect("projected lowering workspace cache poisoned")
            .take();
        drop(current);
        if let Some(released) = released {
            let mut floor = self.floor.lock().expect("lowering workspace floor poisoned");
            *floor = Some(floor.map_or(released.capacities, |floor| floor.grow_to_cover(released.capacities)));
        }
    }

    /// Drops the workspace, its floor and the projection's demand (the
    /// daemon's memory-pressure trim).
    pub(crate) fn trim(&self) {
        self.release();
        *self
            .projected_demand
            .lock()
            .expect("projected lowering demand poisoned") = None;
        *self.floor.lock().expect("lowering workspace floor poisoned") = None;
    }

    #[cfg(test)]
    pub(crate) fn retained_capacities(&self) -> Option<LoweringCapacities> {
        self.current
            .lock()
            .expect("lowering workspace cache poisoned")
            .as_ref()
            .map(|pipeline| pipeline.capacities)
    }
}

impl GpuLoweringPipeline {
    fn new_with_upstream(
        device: &wgpu::Device,
        kernels: &crate::gpu::kernels::KernelRegistry,
        capacities: LoweringCapacities,
        target: LoweringTarget,
        artifact_kind: LoweringArtifactKind,
        upstream: &[TrackedBufferView<'_>],
        upstream_signature: Vec<(u64, u64, u64)>,
        semantic_input_signature: Vec<(u64, u64, u64)>,
        hir: GpuSemanticHirInputs<'_>,
        semantic_inputs: GpuSemanticArtifactView<'_>,
    ) -> Result<Self> {
        let label = match target {
            LoweringTarget::X86_64 => "codegen.x86.lowering.uniform_arena",
            LoweringTarget::Wasm => "codegen.wasm.lowering.uniform_arena",
        };
        with_uniform_buffer_arena(device, label, || {
            Self::new_with_uniform_arena(
                device,
                kernels,
                capacities,
                target,
                artifact_kind,
                upstream,
                upstream_signature,
                semantic_input_signature,
                hir,
                semantic_inputs,
            )
        })
    }

    fn new_with_uniform_arena(
        device: &wgpu::Device,
        kernels: &crate::gpu::kernels::KernelRegistry,
        capacities: LoweringCapacities,
        target: LoweringTarget,
        artifact_kind: LoweringArtifactKind,
        upstream: &[TrackedBufferView<'_>],
        upstream_signature: Vec<(u64, u64, u64)>,
        semantic_input_signature: Vec<(u64, u64, u64)>,
        hir: GpuSemanticHirInputs<'_>,
        semantic_inputs: GpuSemanticArtifactView<'_>,
    ) -> Result<Self> {
        let graph = lowering_compiler_graph_for_artifact(capacities, target, artifact_kind)
            .map_err(anyhow::Error::msg)?;
        if crate::options::get().report.buffers {
            report_lowering_graph_bytes(&graph, capacities, upstream);
        }
        let workspace = Arc::new(
            CompilerGraphWorkspace::new_with_upstream_storage(
                device,
                "codegen.lowering",
                &graph,
                upstream,
            )
            .map_err(anyhow::Error::msg)?,
        );
        Self::with_workspace(
            device,
            kernels,
            capacities,
            target,
            artifact_kind,
            graph,
            workspace,
            upstream_signature,
            semantic_input_signature,
            hir,
            semantic_inputs,
        )
    }

    /// A pipeline over `base`'s arena and other input buffers. It creates
    /// stages, uniforms and bind groups, and no arena storage.
    fn new_variant(
        device: &wgpu::Device,
        kernels: &crate::gpu::kernels::KernelRegistry,
        base: &GpuLoweringPipeline,
        semantic_input_signature: Vec<(u64, u64, u64)>,
        hir: GpuSemanticHirInputs<'_>,
        semantic_inputs: GpuSemanticArtifactView<'_>,
    ) -> Result<Self> {
        let target = base.target.lowering_target();
        let label = match target {
            LoweringTarget::X86_64 => "codegen.x86.lowering.uniform_arena",
            LoweringTarget::Wasm => "codegen.wasm.lowering.uniform_arena",
        };
        with_uniform_buffer_arena(device, label, || {
            let graph = lowering_compiler_graph_for_artifact(base.capacities, target, base.artifact_kind)
                .map_err(anyhow::Error::msg)?;
            Self::with_workspace(
                device,
                kernels,
                base.capacities,
                target,
                base.artifact_kind,
                graph,
                Arc::clone(&base.workspace),
                base.upstream_signature.clone(),
                semantic_input_signature,
                hir,
                semantic_inputs,
            )
        })
    }

    #[allow(clippy::too_many_arguments)]
    fn with_workspace(
        device: &wgpu::Device,
        kernels: &crate::gpu::kernels::KernelRegistry,
        capacities: LoweringCapacities,
        target: LoweringTarget,
        artifact_kind: LoweringArtifactKind,
        graph: crate::gpu::compiler_graph::CompilerGraph,
        workspace: Arc<CompilerGraphWorkspace>,
        upstream_signature: Vec<(u64, u64, u64)>,
        semantic_input_signature: Vec<(u64, u64, u64)>,
        hir: GpuSemanticHirInputs<'_>,
        semantic_inputs: GpuSemanticArtifactView<'_>,
    ) -> Result<Self> {
        let target_total_name = match target {
            LoweringTarget::X86_64 => "lir.x86.total",
            LoweringTarget::Wasm => "lir.wasm.total",
        };
        let hir_core = hir.core;
        let semantic = GpuSemanticLoweringStage::from_workspace(
            device,
            capacities,
            graph.clone(),
            &workspace,
            kernels,
            hir,
            semantic_inputs,
        )?;
        let optimizer = GpuOptimizationStage::new(
            device,
            &graph,
            &workspace,
            capacities,
            semantic.output(),
            kernels,
        )
        .context("construct GPU optimization stage")?;
        let target = match target {
            LoweringTarget::X86_64 => TargetStage::X86_64(
                GpuX86LirStage::new(
                    device,
                    &graph,
                    &workspace,
                    capacities,
                    optimizer.output(semantic.output()),
                    hir_core,
                    artifact_kind == LoweringArtifactKind::Object,
                    kernels,
                )
                .context("construct x86 lowering stage")?,
            ),
            LoweringTarget::Wasm => TargetStage::Wasm(
                GpuWasmLirStage::new(
                    device,
                    &graph,
                    &workspace,
                    capacities,
                    optimizer.output(semantic.output()),
                    hir_core,
                    artifact_kind == LoweringArtifactKind::Object,
                    kernels,
                )
                .context("construct Wasm lowering stage")?,
            ),
        };
        let status_bytes = std::mem::size_of::<LoweringStatus>();
        // An x86 object job copies its status after the object metadata,
        // so one map reads both.
        let object_readback = match &target {
            TargetStage::X86_64(stage) => stage.object_metadata_readback().cloned(),
            TargetStage::Wasm(_) => None,
        };
        let status_readback_bytes = status_bytes + 8 + LOWERING_PROGRAM_FAILURE_BYTES;
        let (status_readback, status_binding, status_base) = match object_readback {
            Some(buffer) => (
                buffer,
                "metadata_readback",
                super::lowering_ir::X86_OBJECT_METADATA_BYTES as usize,
            ),
            None => (
                readback_bytes(device, "lowering.status.readback", status_readback_bytes, status_readback_bytes),
                "status_readback",
                0,
            ),
        };
        let status_allocations = workspace.allocations();
        let status_readback_copy = crate::gpu::operations::CopyBufferOperation::new(
            &(&graph, &status_allocations),
            "lowering.status.readback",
            "lowering_status",
            semantic.status(),
            0,
            status_binding,
            &status_readback,
            status_base as u64,
            status_bytes as u64,
        )?;
        let program_failed_copies = (0..LOWERING_PROGRAM_SLOTS)
            .map(|slot| {
                crate::gpu::operations::CopyBufferOperation::new(
                    &(&graph, &status_allocations),
                    "lowering.step_program_failed.readback",
                    "step_program_sync",
                    optimizer.program_sync(),
                    crate::gpu::operations::StepProgramOperation::failed_offset(slot as u32),
                    status_binding,
                    &status_readback,
                    (status_base + status_bytes + 8 + slot * 4) as u64,
                    4,
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let target_total = workspace
            .alias::<u32>(
                &graph,
                graph
                    .resource_id(target_total_name)
                    .with_context(|| format!("lowering graph is missing {target_total_name}"))?,
                1,
            )
            .map_err(anyhow::Error::msg)?;
        let job_totals_copies = [
            crate::gpu::operations::CopyBufferOperation::new(
                &(&graph, &status_allocations),
                "lowering.semantic_total.readback",
                "semantic_total",
                semantic.output().count,
                0,
                status_binding,
                &status_readback,
                (status_base + status_bytes) as u64,
                4,
            )?,
            crate::gpu::operations::CopyBufferOperation::new(
                &(&graph, &status_allocations),
                "lowering.target_total.readback",
                "target_total",
                &target_total,
                0,
                status_binding,
                &status_readback,
                (status_base + status_bytes) as u64 + 4,
                4,
            )?,
        ];
        Ok(Self {
            capacities,
            artifact_kind,
            upstream_signature,
            semantic_input_signature,
            workspace,
            semantic,
            optimizer,
            target,
            status_readback,
            status_base,
            status_readback_copy,
            program_failed_copies,
            job_totals_copies,
            phase_reset_plans: Mutex::new(Vec::new()),
            recorded_job: Mutex::new(capacities),
            measured_semantic_rows: std::sync::atomic::AtomicU32::new(0),
            #[cfg(test)]
            next_test_artifact_limit: std::sync::atomic::AtomicU32::new(0),
            #[cfg(test)]
            test_output_retries: std::sync::atomic::AtomicUsize::new(0),
        })
    }

    /// The capacities bounding what the job can address in this workspace
    /// (`LoweringCapacities::for_job`).
    fn job_capacities(&self, bounds: super::semantics::LoweringJobBounds) -> LoweringCapacities {
        let job = self.capacities.for_job(
            bounds.source_bytes,
            bounds.hir_rows,
            self.target.lowering_target(),
        );
        let job = apply_output_demand(job, bounds.output_demand, self.capacities);
        #[cfg(test)]
        let job = {
            let limit = self.next_test_artifact_limit.swap(0, std::sync::atomic::Ordering::Relaxed);
            LoweringCapacities {
                artifact_bytes: if limit == 0 { job.artifact_bytes } else { job.artifact_bytes.min(limit) },
                ..job
            }
        };
        job
    }

    #[cfg(test)]
    pub(crate) fn test_limit_next_artifact_capacity(&self, bytes: u32) {
        assert!(bytes > 0);
        self.next_test_artifact_limit.store(bytes, std::sync::atomic::Ordering::Relaxed);
    }

    #[cfg(test)]
    pub(crate) fn test_output_retry_count(&self) -> usize {
        self.test_output_retries.load(std::sync::atomic::Ordering::Relaxed)
    }

    /// The job's capacities when they are below this workspace's, for the
    /// stages whose capacity-wide clears they bound.
    fn smaller_job(&self, job: LoweringCapacities) -> Option<LoweringCapacities> {
        (job != self.capacities).then_some(job)
    }

    /// The job's capacities when they are below this workspace's, for the
    /// direct operations whose grids they bound (`JobSized`).
    // Launch sizing uses the job's bounds before the workspace rounds them
    // up for reuse. The shaders still clamp counts to allocated capacities.
    fn optimizer_job_capacities(
        &self,
        bounds: super::semantics::LoweringJobBounds,
    ) -> Option<LoweringCapacities> {
        if !job_sized_direct_ops() || bounds.source_bytes == u32::MAX || bounds.hir_rows == u32::MAX {
            return None;
        }
        let capacities = LoweringCapacities::from_frontend_unit(
            bounds.source_bytes,
            self.capacities.tokens,
            bounds.hir_rows,
            self.target.lowering_target(),
        ).ok()?;
        Some(LoweringCapacities {
            semantic_instructions: capacities.semantic_instructions
                .max(bounds.output_demand.semantic_instructions),
            ..capacities
        })
    }

    fn sized_job(&self, job: LoweringCapacities) -> Option<LoweringCapacities> {
        self.smaller_job(job).filter(|_| job_sized_direct_ops())
    }

    /// Clears the storage imported from the type checker that the job's
    /// zero-initialized resources can address: each one's size in a graph
    /// built for `job` (`CompilerGraphWorkspace::phase_reset_plan`). A job at
    /// this workspace's capacities clears their whole slots.
    fn record_job_phase_reset(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        job: LoweringCapacities,
    ) {
        *self
            .recorded_job
            .lock()
            .expect("lowering recorded job poisoned") = job;
        if job == self.capacities {
            self.workspace.record_phase_reset(encoder);
            return;
        }
        let plan = match self.phase_reset_plan(job) {
            Ok(planned) => planned,
            Err(error) => {
                eprintln!("[lowering.phase_reset] job plan failed, clearing whole slots: {error}");
                self.workspace.record_phase_reset(encoder);
                return;
            }
        };
        plan.record(encoder);
        plan.record_test_poison(encoder);
    }

    fn phase_reset_plan(
        &self,
        job: LoweringCapacities,
    ) -> Result<Arc<PhaseResetPlan>, String> {
        let mut plans = self
            .phase_reset_plans
            .lock()
            .expect("lowering phase-reset plans poisoned");
        if let Some((_, plan)) = plans.iter().find(|(capacities, _)| *capacities == job) {
            return Ok(Arc::clone(plan));
        }
        let bytes =
            lowering_resource_bytes_for_artifact(job, self.target.lowering_target(), self.artifact_kind)?;
        let plan = Arc::new(self.workspace.phase_reset_plan(|name| bytes.get(name).copied())?);
        if plans.len() == PHASE_RESET_PLAN_CACHE {
            plans.remove(0);
        }
        plans.push((job, Arc::clone(&plan)));
        Ok(plan)
    }

    fn record_status_readback(&self, encoder: &mut wgpu::CommandEncoder) {
        self.status_readback_copy.record(encoder);
        for copy in &self.program_failed_copies {
            copy.record(encoder);
        }
        for copy in &self.job_totals_copies {
            copy.record(encoder);
        }
    }

    /// Flags a job whose semantic or target rows exceed the job's
    /// capacities, as the GPU checks of a fresh workspace for the job would
    /// (build_control_flow.slang, validate_x86_instruction_counts.slang,
    /// and validate_wasm_instruction_counts.slang). A job at this workspace's
    /// capacities was checked on the GPU. The job's x86
    /// analysis clears cover only its capacities; rows past them could read
    /// stale words. Target rows use an initial frontend estimate
    /// plus explicit GPU demand from this compilation's earlier attempt.
    fn check_job_totals(&self, status: &mut LoweringStatus, semantic_rows: u32, target_rows: u32) {
        let job = *self
            .recorded_job
            .lock()
            .expect("lowering recorded job poisoned");
        self.measured_semantic_rows
            .store(semantic_rows, std::sync::atomic::Ordering::Relaxed);
        if crate::options::get().report.buffers {
            eprintln!(
                "lowering_job semantic_rows={semantic_rows} target_rows={target_rows} job={job:?}"
            );
        }
        if job != self.capacities {
            flag_job_totals(status, job, semantic_rows, target_rows);
        }
    }

    /// Fails an artifact the job's capacities could not hold, as a fresh
    /// workspace for the job would: its artifact clear covers only those
    /// capacities.
    fn check_job_artifact_bytes(&self, what: &str, bytes: usize) -> Result<()> {
        let job = *self
            .recorded_job
            .lock()
            .expect("lowering recorded job poisoned");
        let limit = job.artifact_bytes.max(4).next_multiple_of(4) as usize;
        if job != self.capacities && bytes > limit {
            let required_capacity = u32::try_from(bytes)
                .map_err(|_| anyhow::anyhow!("GPU {what} byte demand exceeds u32"))?;
            return Err(LoweringFailure {
                status: artifact_capacity_status(required_capacity, job.artifact_bytes),
            }.into());
        }
        Ok(())
    }

    fn record_target_pages(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        object: bool,
        timer: &mut Option<&mut GpuTimer>,
        job: Option<LoweringCapacities>,
    ) -> Result<()> {
        let _operation_capture = timer.as_deref().map(GpuTimer::capture_operations);
        if let Some(timer) = timer.as_deref_mut() {
            timer.set_phase(self.target.compiler_phase());
        }
        self.target.record_before_target_pages(encoder)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "codegen.target.layout.done");
        }
        for page_id in 0..self.target.target_page_count() {
            self.target.record_measure_page(encoder, page_id)?;
        }
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, self.target.lowering_timer_label());
        }
        self.target.record_between_target_pages(encoder, object, job)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "codegen.target.artifact_layout.done");
        }
        for page_id in 0..self.target.target_page_count() {
            self.target.record_emit_page(encoder, page_id)?;
        }
        self.target.record_after_target_pages(
            encoder,
            object,
            job.filter(|_| job_sized_direct_ops()),
        )?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, self.target.emission_timer_label());
        }
        Ok(())
    }

    /// Records the lowering into `encoder`, which the caller submits. The
    /// semantic stage submits work while the host records lowering
    /// (`SubmissionSplit`). The optimizer's program dispatches stay in one
    /// submission with the final semantic passes.
    pub(crate) fn record(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        mut timer: Option<&mut GpuTimer>,
        bounds: super::semantics::LoweringJobBounds,
    ) -> Result<()> {
        let bounds = job_bounds(bounds);
        let split = SubmissionSplit { device, queue };
        let _operation_capture = timer.as_deref().map(GpuTimer::capture_operations);
        if let Some(timer) = timer.as_deref_mut() {
            timer.set_phase(crate::gpu::timer::GpuCompilerPhase::Lowering);
            timer.stamp(encoder, "lowering.submission.begin");
        }
        let _compute_batch = crate::gpu::passes_core::DeferredComputeBatchGuard::begin(
            crate::gpu::passes_core::compute_pass_batching_allowed(timer.is_some()),
            "lowering.executable.batch",
        );
        let job = self.job_capacities(bounds);
        self.record_job_phase_reset(encoder, job);
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "lowering.phase_reset.done");
        }
        // A workspace retained from a larger job would record that job's
        // pointer-jump pairs; the job's HIR bound gives its own.
        let execution_rank_pairs = self
            .capacities
            .job_execution_rank_jump_pairs(bounds.hir_rows, self.target.lowering_target());
        self.semantic.record_timed(
            encoder,
            timer.as_deref_mut(),
            Some(split),
            execution_rank_pairs,
            self.sized_job(job),
        )?;
        self.optimizer.record_for_job(
            encoder,
            timer.as_deref_mut(),
            self.optimizer_job_capacities(bounds),
            true,
        )?;
        split.submit_prefix(
            encoder,
            "compile.lowering.optimizer",
            "lowering.target.submission.begin",
            timer.as_deref_mut(),
        );
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "lowering.optimization.identity.done");
            timer.set_phase(self.target.compiler_phase());
        }
        for page_id in 0..self.target.count_page_count() {
            self.target
                .record_count_page(encoder, page_id, &mut timer, self.smaller_job(job))?;
        }
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "codegen.target.analysis_count.done");
        }
        self.record_target_pages(encoder, false, &mut timer, self.smaller_job(job))?;
        self.record_status_readback(encoder);
        if let Some(timer) = timer.as_deref_mut() {
            timer.set_phase(crate::gpu::timer::GpuCompilerPhase::ArtifactEmission);
            timer.stamp(encoder, "artifact.status_readback.done");
        }
        Ok(())
    }

    /// Records an object lowering into `encoder`, which the caller submits.
    /// Like `record`, it submits the semantic stage and the optimizer as they
    /// are recorded.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn record_object(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        library_id: u32,
        unit_id: u32,
        functions: super::semantics::ObjectFunctions,
        mut timer: Option<&mut GpuTimer>,
        bounds: super::semantics::LoweringJobBounds,
    ) -> Result<()> {
        let bounds = job_bounds(bounds);
        let split = SubmissionSplit { device, queue };
        // Like `record`, time every lowering operation; without this scope
        // the semantic, optimizer and count-page kernels have no timestamps
        // and their time shows up under the first stamped target pass.
        let _operation_capture = timer.as_deref().map(GpuTimer::capture_operations);
        if let Some(timer) = timer.as_deref_mut() {
            timer.set_phase(crate::gpu::timer::GpuCompilerPhase::Lowering);
            timer.stamp(encoder, "lowering.submission.begin");
        }
        let _compute_batch = crate::gpu::passes_core::DeferredComputeBatchGuard::begin(
            crate::gpu::passes_core::compute_pass_batching_allowed(timer.is_some()),
            "lowering.object.batch",
        );
        // Each object job overwrites its scope and its object identity,
        // including ordinary/strict jobs. These uploads belong to this
        // compiler job's commands and are not cached by workspace identity.
        // A queue write reaches only the submissions after it, so both
        // precede the first split below.
        self.semantic.set_object_functions(queue, functions);
        self.target
            .set_object_identity(queue, library_id, unit_id)?;
        let job = self.job_capacities(bounds);
        self.record_job_phase_reset(encoder, job);
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "lowering.phase_reset.done");
        }
        // A workspace retained from a larger job would record that job's
        // pointer-jump pairs; the job's HIR bound gives its own.
        let execution_rank_pairs = self
            .capacities
            .job_execution_rank_jump_pairs(bounds.hir_rows, self.target.lowering_target());
        self.semantic.record_timed(
            encoder,
            timer.as_deref_mut(),
            Some(split),
            execution_rank_pairs,
            self.sized_job(job),
        )?;
        self.optimizer.record_for_job(
            encoder,
            timer.as_deref_mut(),
            self.optimizer_job_capacities(bounds),
            true,
        )?;
        split.submit_prefix(
            encoder,
            "compile.lowering.optimizer",
            "lowering.target.submission.begin",
            timer.as_deref_mut(),
        );
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "lowering.optimization.identity.done");
            timer.set_phase(self.target.compiler_phase());
        }
        for page_id in 0..self.target.count_page_count() {
            self.target
                .record_count_page(encoder, page_id, &mut timer, self.smaller_job(job))?;
        }
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "codegen.target.analysis_count.done");
        }
        self.record_target_pages(encoder, true, &mut timer, self.smaller_job(job))?;
        self.record_status_readback(encoder);
        if let Some(timer) = timer.as_deref_mut() {
            timer.set_phase(crate::gpu::timer::GpuCompilerPhase::ArtifactEmission);
            timer.stamp(encoder, "artifact.status_readback.done");
        }
        Ok(())
    }

    /// Completes a previously submitted target job from daemon-resident
    /// readback storage.
    pub(crate) fn finish_artifact(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
    ) -> Result<Vec<u8>> {
        self.ensure_success(device)?;
        let artifact = match &self.target {
            TargetStage::X86_64(stage) => stage.finish_artifact(device, queue),
            TargetStage::Wasm(stage) => stage.finish_artifact(device, queue),
        }?;
        self.check_job_artifact_bytes("artifact", artifact.len())?;
        Ok(artifact)
    }

    pub(crate) fn finish_wasm_object(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        library_id: u32,
        unit_id: u32,
    ) -> Result<(crate::codegen::wasm::GpuWasmRelocatableObject, Vec<u32>)> {
        self.ensure_success(device)?;
        match &self.target {
            TargetStage::Wasm(stage) => stage.finish_object(device, queue, library_id, unit_id),
            TargetStage::X86_64(_) => {
                anyhow::bail!("the selected lowering pipeline does not produce a Wasm object")
            }
        }
    }

    pub(crate) fn finish_x86_object(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        library_id: u32,
        unit_id: u32,
        keep: Option<&std::sync::Arc<crate::codegen::x86::GpuX86LinkStore>>,
    ) -> Result<(super::x86::objects::GpuX86FinishedObject, Vec<u32>)> {
        let status = self.read_x86_object_status(device)?;
        self.finish_x86_object_then(device, queue, library_id, unit_id, status, keep, || {})
    }

    /// The job's status and its x86 object's metadata, read once for
    /// [`Self::check_x86_object`] and [`Self::finish_x86_object_then`].
    pub(crate) fn read_x86_object_status(&self, device: &wgpu::Device) -> Result<X86ObjectStatus> {
        if !matches!(self.target, TargetStage::X86_64(_)) {
            anyhow::bail!("the selected lowering pipeline does not produce an x86 object")
        }
        let (status, metadata) = self.read_status(device)?;
        Ok(X86ObjectStatus { status, metadata })
    }

    /// Whether the object passed every retry point: the status, and the
    /// object's bytes against the job's capacities.
    pub(crate) fn check_x86_object(&self, read: &X86ObjectStatus) -> Result<()> {
        let TargetStage::X86_64(stage) = &self.target else {
            anyhow::bail!("the selected lowering pipeline does not produce an x86 object")
        };
        if read.status.flags != 0 {
            return Err(LoweringFailure { status: read.status }.into());
        }
        // The object's artifact words hold its text and rodata together.
        let bytes = stage.object_section_bytes(&read.metadata)?;
        self.check_job_artifact_bytes("x86 object text and rodata", bytes)
    }

    /// Reads the object `status` describes, running `checked` once every
    /// retry point has passed ([`Self::check_x86_object`]) and before the
    /// payload is read and decoded. An object parked in `keep` keeps its
    /// sections on the GPU.
    pub(crate) fn finish_x86_object_then(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        library_id: u32,
        unit_id: u32,
        status: X86ObjectStatus,
        keep: Option<&std::sync::Arc<crate::codegen::x86::GpuX86LinkStore>>,
        checked: impl FnOnce(),
    ) -> Result<(super::x86::objects::GpuX86FinishedObject, Vec<u32>)> {
        let TargetStage::X86_64(stage) = &self.target else {
            anyhow::bail!("the selected lowering pipeline does not produce an x86 object")
        };
        self.check_x86_object(&status)?;
        checked();
        stage.finish_object(device, queue, library_id, unit_id, &status.metadata, keep)
    }

    /// [`Self::finish_x86_object_then`] without a callback, reading `extra`
    /// in the object's own readback; their bytes come third.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn finish_x86_object_with_reads(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        library_id: u32,
        unit_id: u32,
        status: X86ObjectStatus,
        keep: Option<&std::sync::Arc<crate::codegen::x86::GpuX86LinkStore>>,
        extra: &[crate::gpu::readback::ReadbackRegion<'_>],
    ) -> Result<(super::x86::objects::GpuX86FinishedObject, Vec<u32>, Vec<Vec<u8>>)> {
        let TargetStage::X86_64(stage) = &self.target else {
            anyhow::bail!("the selected lowering pipeline does not produce an x86 object")
        };
        self.check_x86_object(&status)?;
        stage.finish_with_reads(device, queue, library_id, unit_id, &status.metadata, keep, extra)
    }

    /// [`Self::finish_wasm_object`], reading `extra` in the object's own
    /// readback; their bytes come third.
    pub(crate) fn finish_wasm_object_with_reads(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        library_id: u32,
        unit_id: u32,
        extra: &[crate::gpu::readback::ReadbackRegion<'_>],
    ) -> Result<(crate::codegen::wasm::GpuWasmRelocatableObject, Vec<u32>, Vec<Vec<u8>>)> {
        self.ensure_success(device)?;
        match &self.target {
            TargetStage::Wasm(stage) => stage.finish_with_reads(device, queue, library_id, unit_id, extra),
            TargetStage::X86_64(_) => {
                anyhow::bail!("the selected lowering pipeline does not produce a Wasm object")
            }
        }
    }

    /// The rows of the recorded object that a retained build's call
    /// rewrite updates in place before the object is read: mode 0 (x86) or
    /// 1 (Wasm), the rows, the x86 call HIRs, the word that counts the rows
    /// and the rows the buffers hold.
    pub(crate) fn object_call_rows(&self) -> Option<(
        u32,
        crate::type_checker::program_retention::JobTable,
        Option<crate::type_checker::program_retention::JobTable>,
        (wgpu::Buffer, u64),
        u32,
    )> {
        Some(match &self.target {
            TargetStage::X86_64(stage) => {
                let (rows, call_hirs, count, lanes) = stage.call_rows()?;
                (0, rows, Some(call_hirs), count, lanes)
            }
            TargetStage::Wasm(stage) => {
                let (rows, count, lanes) = stage.call_rows()?;
                (1, rows, None, count, lanes)
            }
        })
    }

    /// The slot the recorded x86 object parked in for the resident link,
    /// before its readback.
    pub(crate) fn parked_x86_slot(&self) -> Option<crate::codegen::x86::ParkedSlot> {
        match &self.target {
            TargetStage::X86_64(stage) => stage.parked_slot(),
            TargetStage::Wasm(_) => None,
        }
    }

    pub(crate) fn finish_status(&self, device: &wgpu::Device) -> Result<LoweringStatus> {
        Ok(self.read_status(device)?.0)
    }

    /// The status, and the words before it in its readback (an x86 object's
    /// metadata, otherwise none).
    fn read_status(&self, device: &wgpu::Device) -> Result<(LoweringStatus, Vec<u32>)> {
        let slice = self.status_readback.slice(..);
        map_readback_blocking(device, &slice, crate::readback_label!("lowering status readback"))?;
        let mapped = slice.get_mapped_range();
        let words = mapped
            .chunks_exact(4)
            .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
            .collect::<Vec<_>>();
        drop(mapped);
        self.status_readback.unmap();
        let base = self.status_base / 4;
        let word = |index: usize| words[base + index];
        let mut status = LoweringStatus {
            flags: word(0),
            first_unsupported_hir: word(1),
            first_unsupported_semantic_row: word(2),
            first_unsupported_opt_row: word(3),
            required_capacity: word(4),
            available_capacity: word(5),
            diagnostic_reason: word(6),
            diagnostic_detail_kind: word(7),
            diagnostic_detail: word(8),
            first_unsupported_target_op: word(9),
        };
        let totals = std::mem::size_of::<LoweringStatus>() / 4;
        for slot in 0..LOWERING_PROGRAM_SLOTS {
            anyhow::ensure!(
                word(totals + 2 + slot) == 0,
                "lowering step program {slot} synchronization failed",
            );
        }
        let (semantic_rows, target_rows) = (word(totals), word(totals + 1));
        self.check_job_totals(&mut status, semantic_rows, target_rows);
        let mut prefix = words;
        prefix.truncate(base);
        Ok((status, prefix))
    }

    pub(crate) fn output_demand_for_retry(
        &self,
        error: &anyhow::Error,
    ) -> Result<Option<LoweringOutputDemand>, String> {
        let Some(failure) = error.downcast_ref::<LoweringFailure>() else {
            return Ok(None);
        };
        let job = *self
            .recorded_job
            .lock()
            .expect("lowering recorded job poisoned");
        let demand = output_demand_for_status(
            failure.status,
            job,
            self.target.lowering_target(),
            self.measured_semantic_rows.load(std::sync::atomic::Ordering::Relaxed),
        );
        #[cfg(test)]
        if matches!(&demand, Ok(Some(_))) {
            self.test_output_retries.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        }
        demand
    }

    fn ensure_success(&self, device: &wgpu::Device) -> Result<()> {
        let status = self.finish_status(device)?;
        if status.flags != 0 {
            return Err(LoweringFailure { status }.into());
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::gpu::device;

    #[test]
    fn measured_target_output_demand_survives_job_clamping_without_enlarging_other_jobs() {
        use crate::codegen::lir::lowering_ir::opcode::LOWERING_STATUS_TARGET_CAPACITY;
        let job = LoweringCapacities::from_frontend_unit(1000, 100, 100, LoweringTarget::X86_64)
            .unwrap()
            .bucketed();
        let status = LoweringStatus {
            flags: LOWERING_STATUS_TARGET_CAPACITY,
            required_capacity: 187055,
            available_capacity: job.target_instructions,
            ..LoweringStatus::default()
        };
        let demand = output_demand_for_status(status, job, LoweringTarget::X86_64, 0)
            .unwrap()
            .unwrap();
        assert_eq!(demand.target_instructions, 188416);
        assert!(
            demand.artifact_bytes >= 188416 * 16 + job.hir_nodes * 32 + job.source_bytes + 4096
        );
        let built = LoweringCapacities {
            target_instructions: demand.target_instructions,
            artifact_bytes: demand.artifact_bytes,
            ..job
        };
        let small = built.for_job(1000, 100, LoweringTarget::X86_64);
        assert!(small.target_instructions < demand.target_instructions);
        let retry = apply_output_demand(small, demand, built);
        assert_eq!(retry.target_instructions, demand.target_instructions);
        assert_eq!(retry.artifact_bytes, demand.artifact_bytes);
        assert_eq!(retry.semantic_instructions, small.semantic_instructions);
        assert_eq!(
            apply_output_demand(small, LoweringOutputDemand::default(), built),
            small
        );
    }

    #[test]
    fn measured_artifact_output_demand_uses_the_same_typed_status_for_warm_jobs() {
        let job = LoweringCapacities::from_frontend_unit(1000, 100, 100, LoweringTarget::X86_64)
            .unwrap()
            .bucketed();
        let error: anyhow::Error = LoweringFailure {
            status: artifact_capacity_status(job.artifact_bytes + 1, job.artifact_bytes),
        }
        .into();
        let status = error.downcast_ref::<LoweringFailure>().unwrap().status;
        let demand = output_demand_for_status(status, job, LoweringTarget::X86_64, 0)
            .unwrap()
            .unwrap();
        assert_eq!(demand.target_instructions, job.target_instructions);
        assert_eq!(demand.artifact_bytes, job.artifact_bytes + 4096);
    }

    #[test]
    fn semantic_overflow_grows_to_the_counted_rows_whatever_the_cut_flagged() {
        use crate::codegen::lir::lowering_ir::opcode::{
            LOWERING_STATUS_OPTIMIZATION_STRUCTURE,
            LOWERING_STATUS_SEMANTIC_CAPACITY,
            LOWERING_STATUS_TARGET_CAPACITY,
        };
        let job = LoweringCapacities::initial_for_frontend_unit(1000, 100, 100, LoweringTarget::X86_64)
            .unwrap()
            .bucketed();
        let rows = job.semantic_instructions + 5000;
        for flags in [
            LOWERING_STATUS_SEMANTIC_CAPACITY,
            LOWERING_STATUS_SEMANTIC_CAPACITY | LOWERING_STATUS_OPTIMIZATION_STRUCTURE,
            LOWERING_STATUS_SEMANTIC_CAPACITY | LOWERING_STATUS_TARGET_CAPACITY,
        ] {
            let status = LoweringStatus {
                flags,
                required_capacity: rows,
                available_capacity: job.semantic_instructions,
                diagnostic_reason: 3,
                ..LoweringStatus::default()
            };
            let demand = output_demand_for_status(status, job, LoweringTarget::X86_64, rows)
                .unwrap()
                .unwrap();
            assert_eq!(demand.semantic_instructions, checked_output_bucket(rows).unwrap());
            assert_eq!(demand.target_instructions, job.target_instructions);
            assert_eq!(demand.artifact_bytes, job.artifact_bytes);
            let built = LoweringCapacities {
                semantic_instructions: demand.semantic_instructions,
                ..job
            };
            assert_eq!(
                apply_output_demand(job, demand, built).semantic_instructions,
                demand.semantic_instructions
            );
        }
        // Without a larger GPU count the semantic failure stays a diagnostic.
        let status = LoweringStatus {
            flags: LOWERING_STATUS_SEMANTIC_CAPACITY,
            required_capacity: rows,
            available_capacity: job.semantic_instructions,
            ..LoweringStatus::default()
        };
        assert!(
            output_demand_for_status(status, job, LoweringTarget::X86_64, job.semantic_instructions)
                .unwrap()
                .is_none()
        );
    }

    #[test]
    fn initial_arena_estimate_stays_below_the_structural_job_bound() {
        let initial = LoweringCapacities::initial_for_frontend_unit(1 << 20, 1 << 16, 1 << 16, LoweringTarget::X86_64)
            .unwrap()
            .bucketed();
        let structural = LoweringCapacities::from_frontend_unit(1 << 20, 1 << 16, 1 << 16, LoweringTarget::X86_64)
            .unwrap()
            .bucketed();
        assert!(structural.covers(initial));
        assert_eq!(initial.semantic_instructions, 1 << 16);
        assert_eq!(initial.target_instructions, 2 << 16);
        // A warm job in the arena is bounded by the arena, not by the estimate.
        assert_eq!(initial.for_job(1 << 20, 1 << 16, LoweringTarget::X86_64), initial);
    }

    #[test]
    fn output_demand_rejects_overflow_and_preserves_other_failure_domains() {
        use crate::codegen::lir::lowering_ir::opcode::{
            LOWERING_STATUS_ARTIFACT_CAPACITY,
            LOWERING_STATUS_SEMANTIC_CAPACITY,
            LOWERING_STATUS_TARGET_CAPACITY,
            LOWERING_STATUS_UNSUPPORTED_TARGET,
        };
        let job = LoweringCapacities::from_frontend_unit(1000, 100, 100, LoweringTarget::X86_64)
            .unwrap()
            .bucketed();
        let base = LoweringStatus {
            flags: LOWERING_STATUS_TARGET_CAPACITY,
            required_capacity: job.target_instructions + 1,
            available_capacity: job.target_instructions,
            ..LoweringStatus::default()
        };
        for flags in [
            0,
            LOWERING_STATUS_SEMANTIC_CAPACITY,
            LOWERING_STATUS_UNSUPPORTED_TARGET,
            LOWERING_STATUS_TARGET_CAPACITY | LOWERING_STATUS_ARTIFACT_CAPACITY,
        ] {
            assert!(
                output_demand_for_status(
                    LoweringStatus { flags, ..base },
                    job,
                    LoweringTarget::X86_64,
                    0,
                )
                .unwrap()
                .is_none()
            );
        }
        assert!(
            output_demand_for_status(
                LoweringStatus {
                    diagnostic_reason: 1,
                    ..base
                },
                job,
                LoweringTarget::X86_64,
                    0,
            )
            .unwrap()
            .is_none()
        );
        for required_capacity in [0, job.target_instructions, u32::MAX, 1 << 28] {
            assert!(
                output_demand_for_status(
                    LoweringStatus {
                        required_capacity,
                        ..base
                    },
                    job,
                    LoweringTarget::X86_64,
                    0,
                )
                .is_err()
            );
        }
        assert!(
            output_demand_for_status(
                artifact_capacity_status(u32::MAX, job.artifact_bytes),
                job,
                LoweringTarget::X86_64,
                    0,
            )
            .is_err()
        );
        assert_eq!(
            checked_output_bucket(u32::MAX - 4095).unwrap(),
            u32::MAX - 4095
        );
        assert!(checked_output_bucket(u32::MAX - 4094).is_err());
    }

    #[test]
    fn job_totals_past_the_jobs_capacities_fail_as_the_gpu_checks_would() {
        use crate::codegen::lir::lowering_ir::opcode::{LOWERING_STATUS_SEMANTIC_CAPACITY, LOWERING_STATUS_TARGET_CAPACITY};
        let job = LoweringCapacities::from_frontend_unit(1000, 100, 100, LoweringTarget::X86_64)
            .unwrap();
        let fresh = LoweringStatus {
            available_capacity: u32::MAX,
            ..LoweringStatus::default()
        };
        let mut within = fresh;
        flag_job_totals(&mut within, job, job.semantic_instructions, job.target_instructions);
        assert_eq!(within, fresh);

        let mut semantic = fresh;
        flag_job_totals(&mut semantic, job, job.semantic_instructions + 1, 0);
        assert_eq!(semantic.flags, LOWERING_STATUS_SEMANTIC_CAPACITY);
        assert_eq!(semantic.required_capacity, job.semantic_instructions + 1);
        assert_eq!(semantic.available_capacity, job.semantic_instructions);

        let mut target = fresh;
        flag_job_totals(&mut target, job, 0, job.target_instructions + 7);
        assert_eq!(target.flags, LOWERING_STATUS_TARGET_CAPACITY);
        assert_eq!(target.required_capacity, job.target_instructions + 7);
        assert_eq!(target.available_capacity, job.target_instructions);
    }

    #[test]
    fn lowering_workspace_cache_starts_without_job_storage() {
        for target in [LoweringTarget::X86_64, LoweringTarget::Wasm] {
            let cache = GpuLoweringWorkspaceCache::new(target);
            assert_eq!(cache.retained_capacities(), None);
        }
    }

    #[test]
    fn physical_gpu_warm_compiles_reuse_pipelines_for_both_targets() {
        std::thread::Builder::new()
            .name("lowering pipeline construction".into())
            .stack_size(64 * 1024 * 1024)
            .spawn(run_physical_gpu_warm_compiles_reuse_pipelines_for_both_targets)
            .unwrap()
            .join()
            .unwrap();
    }

    fn run_physical_gpu_warm_compiles_reuse_pipelines_for_both_targets() {
        let gpu = device::global();
        let compiler =
            pollster::block_on(crate::compiler::GpuCompiler::new_with_device_and_backends(
                gpu,
                crate::compiler::GpuCompilerBackends::all(),
            ))
            .unwrap();
        // The first request of each target may create pipelines that are
        // prepared lazily; a repeated request reuses every one of them.
        let source = "fn main() -> i32 { return 42; }";
        let compile_both = || {
            pollster::block_on(compiler.compile_source_to_x86_64(source)).unwrap();
            pollster::block_on(compiler.compile_source_to_wasm(source)).unwrap();
        };
        compile_both();
        let warm = crate::gpu::passes_core::this_thread_gpu_activity();
        compile_both();
        assert_eq!(crate::gpu::passes_core::this_thread_gpu_activity().since(warm).pipelines, 0);
    }
}
