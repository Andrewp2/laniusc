//! One graph-owned lowering pipeline from compact semantic HIR to the selected
//! target LIR and artifact boundary.

use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex, OnceLock},
};

use anyhow::{Context, Result};

use super::{
    lowering::{GpuSemanticHirInputs, GpuSemanticLoweringStage, semantic_input_views},
    lowering_ir::{
        LoweringArtifactKind,
        LoweringCapacities,
        LoweringStatus,
        LoweringTarget,
        lowering_compiler_graph_for_artifact,
        lowering_resource_bytes_for_artifact,
    },
    optimization::GpuOptimizationStage,
    wasm_lowering::GpuWasmLirStage,
    x86_lowering::GpuX86LirStage,
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
    ) -> Result<()> {
        match self {
            Self::X86_64(stage) => stage.record_after_target_pages(encoder, object),
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
    workspace: CompilerGraphWorkspace,
    semantic: GpuSemanticLoweringStage,
    optimizer: GpuOptimizationStage,
    target: TargetStage,
    status_readback: LaniusBuffer<u8>,
    status_readback_copy: crate::gpu::operations::CopyBufferOperation,
    /// The job's semantic and target row totals, copied with the status.
    job_totals_readback: LaniusBuffer<u8>,
    job_totals_copies: [crate::gpu::operations::CopyBufferOperation; 2],
    /// Phase resets of recent job capacities (`job_capacities`).
    phase_reset_plans: Mutex<Vec<(LoweringCapacities, Arc<PhaseResetPlan>)>>,
    /// Words written over the tails a job's phase reset leaves, when
    /// `LANIUS_LOWERING_PHASE_RESET_POISON` is set.
    phase_reset_poison: Mutex<Option<LaniusBuffer<u8>>>,
    /// The capacities the last recorded job could address. Its artifact must
    /// fit them, as it would in a fresh workspace for the job.
    recorded_job: Mutex<LoweringCapacities>,
}

/// Sets the capacity failure a GPU check against `job` would set for a job
/// with `semantic_rows` semantic and `target_rows` target rows.
fn flag_job_totals(
    status: &mut LoweringStatus,
    job: LoweringCapacities,
    semantic_rows: u32,
    target_rows: u32,
) {
    use super::lowering_ir::opcode::{
        LOWERING_STATUS_SEMANTIC_CAPACITY,
        LOWERING_STATUS_TARGET_CAPACITY,
    };
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

/// Job phase resets the pipeline keeps, most recent last.
const PHASE_RESET_PLAN_CACHE: usize = 8;
/// The largest copy source the phase-reset poison allocates.
const PHASE_RESET_POISON_BYTES: u64 = 16 << 20;

/// `LANIUS_LOWERING_FULL_CLEARS=1` resets and clears every job over this
/// workspace's whole capacities, as before job-bounded resets, for A/B runs.
fn full_clears() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| crate::gpu::env::env_bool_truthy("LANIUS_LOWERING_FULL_CLEARS", false))
}

/// `LANIUS_LOWERING_PHASE_RESET_POISON=<word>` (decimal or 0x hex) fills the
/// imported bytes a job's phase reset leaves with that word, so a reader that
/// looks past the job's rows changes the output. For validation only.
fn phase_reset_poison_word() -> Option<u32> {
    #[cfg(test)]
    {
        let word = TEST_PHASE_RESET_POISON.load(std::sync::atomic::Ordering::Relaxed);
        if word != u64::MAX {
            return Some(word as u32);
        }
    }
    static WORD: OnceLock<Option<u32>> = OnceLock::new();
    *WORD.get_or_init(|| {
        let value = std::env::var("LANIUS_LOWERING_PHASE_RESET_POISON").ok()?;
        let value = value.trim();
        match value.strip_prefix("0x").or_else(|| value.strip_prefix("0X")) {
            Some(hex) => u32::from_str_radix(hex, 16).ok(),
            None => value.parse().ok(),
        }
    })
}

/// A poison word tests set in place of `LANIUS_LOWERING_PHASE_RESET_POISON`
/// (`u64::MAX` for none), and the bytes poisoned so far.
#[cfg(test)]
pub(crate) static TEST_PHASE_RESET_POISON: std::sync::atomic::AtomicU64 =
    std::sync::atomic::AtomicU64::new(u64::MAX);
#[cfg(test)]
pub(crate) static TEST_PHASE_RESET_POISONED_BYTES: std::sync::atomic::AtomicU64 =
    std::sync::atomic::AtomicU64::new(0);

/// Tests set this to lower every job with `LoweringJobBounds::CONSERVATIVE`
/// in place of the bounds it passes, so a test can compare both through the
/// production entry points.
#[cfg(test)]
pub(crate) static TEST_CONSERVATIVE_LOWERING_BOUNDS: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);

/// The bounds a job lowers with: its own, unless a test asks for the
/// conservative ones (`TEST_CONSERVATIVE_LOWERING_BOUNDS`).
fn job_bounds(bounds: super::lowering::LoweringJobBounds) -> super::lowering::LoweringJobBounds {
    #[cfg(test)]
    {
        if TEST_CONSERVATIVE_LOWERING_BOUNDS.load(std::sync::atomic::Ordering::Relaxed) {
            return super::lowering::LoweringJobBounds::CONSERVATIVE;
        }
    }
    bounds
}

/// `LANIUS_LOWERING_PHASE_RESET_TRACE=1` prints each job's phase reset.
fn phase_reset_trace() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| {
        crate::gpu::env::env_bool_truthy("LANIUS_LOWERING_PHASE_RESET_TRACE", false)
    })
}

/// Lazily materialized, capacity-covering workspace for one target.
///
/// Shader pipelines are prepared before the daemon reports ready. This cache
/// owns only capacity-dependent buffers, uniforms, bind groups, and readback
/// storage, so an idle trim can return job memory without invalidating kernel
/// readiness.
pub(crate) struct GpuLoweringWorkspaceCache {
    target: LoweringTarget,
    current: Mutex<Option<Arc<GpuLoweringPipeline>>>,
}

/// The split the lowering submits its semantic stage and optimizer with,
/// unless `LANIUS_SPLIT_LOWERING=0` keeps the whole lowering in its caller's
/// submission (for timing comparisons). `LANIUS_SPLIT_SUBMISSIONS=0` turns
/// off every split, this one included.
fn lowering_split<'a>(device: &'a wgpu::Device, queue: &'a wgpu::Queue) -> Option<SubmissionSplit<'a>> {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    ENABLED
        .get_or_init(|| crate::gpu::env::env_bool_truthy("LANIUS_SPLIT_LOWERING", true))
        .then_some(SubmissionSplit { device, queue })
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
        }
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
            LoweringCapacities::from_frontend_unit(source_bytes, tokens, hir_nodes, self.target)?
                .bucketed();
        let mut current = self
            .current
            .lock()
            .expect("lowering workspace cache poisoned");
        let upstream_signature = upstream_storage_signature(upstream);
        let semantic_input_signature = exact_buffer_signature(&semantic_input_views(hir, semantic));
        if let Some(pipeline) = current.as_ref()
            && pipeline.capacities.covers(required)
            && pipeline.artifact_kind == artifact_kind
            && pipeline.upstream_signature == upstream_signature
            && pipeline.semantic_input_signature == semantic_input_signature
        {
            return Ok(Arc::clone(pipeline));
        }
        let capacities = current.as_ref().map_or(required, |pipeline| {
            pipeline.capacities.grow_to_cover(required)
        });
        // Reflected bind groups in the old pipeline own every lowering arena.
        // Destroy that complete identity graph before allocating its
        // replacement; otherwise a small capacity increase transiently makes
        // both multi-gigabyte workspaces resident.
        let old = current.take();
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

    pub(crate) fn release(&self) {
        *self
            .current
            .lock()
            .expect("lowering workspace cache poisoned") = None;
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
        let target_total_name = match target {
            LoweringTarget::X86_64 => "lir.x86.total",
            LoweringTarget::Wasm => "lir.wasm.total",
        };
        let graph = lowering_compiler_graph_for_artifact(capacities, target, artifact_kind)
            .map_err(anyhow::Error::msg)?;
        let workspace = CompilerGraphWorkspace::new_with_upstream_storage(
            device,
            "codegen.lowering",
            &graph,
            upstream,
        )
        .map_err(anyhow::Error::msg)?;
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
                    artifact_kind == LoweringArtifactKind::Object,
                    kernels,
                )
                .context("construct Wasm lowering stage")?,
            ),
        };
        let status_bytes = std::mem::size_of::<LoweringStatus>();
        let status_readback = readback_bytes(
            device,
            "lowering.status.readback",
            status_bytes,
            status_bytes,
        );
        let status_allocations = workspace.allocations();
        let status_readback_copy = crate::gpu::operations::CopyBufferOperation::new(
            &(&graph, &status_allocations),
            "lowering.status.readback",
            "lowering_status",
            semantic.status(),
            0,
            "status_readback",
            &status_readback,
            0,
            status_bytes as u64,
        )?;
        let job_totals_readback = readback_bytes(device, "lowering.job_totals.readback", 8, 8);
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
                "job_totals_readback",
                &job_totals_readback,
                0,
                4,
            )?,
            crate::gpu::operations::CopyBufferOperation::new(
                &(&graph, &status_allocations),
                "lowering.target_total.readback",
                "target_total",
                &target_total,
                0,
                "job_totals_readback",
                &job_totals_readback,
                4,
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
            status_readback_copy,
            job_totals_readback,
            job_totals_copies,
            phase_reset_plans: Mutex::new(Vec::new()),
            phase_reset_poison: Mutex::new(None),
            recorded_job: Mutex::new(capacities),
        })
    }

    /// The capacities bounding what the job can address in this workspace
    /// (`LoweringCapacities::for_job`), or this workspace's under
    /// `LANIUS_LOWERING_FULL_CLEARS=1`.
    fn job_capacities(&self, bounds: super::lowering::LoweringJobBounds) -> LoweringCapacities {
        if full_clears() {
            return self.capacities;
        }
        self.capacities
            .for_job(bounds.source_bytes, bounds.hir_rows, self.target.lowering_target())
    }

    /// The job's capacities when they are below this workspace's, for the
    /// stages whose capacity-wide clears they bound.
    fn smaller_job(&self, job: LoweringCapacities) -> Option<LoweringCapacities> {
        (job != self.capacities).then_some(job)
    }

    /// Clears the storage imported from the type checker up to the bytes the
    /// job's resources can address: each resource's size in a graph built
    /// for `job`. A job at this workspace's capacities clears whole slots.
    fn record_job_phase_reset(
        &self,
        device: &wgpu::Device,
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
        let started = std::time::Instant::now();
        let (plan, cached) = match self.phase_reset_plan(job) {
            Ok(planned) => planned,
            Err(error) => {
                eprintln!("[lowering.phase_reset] job plan failed, clearing whole slots: {error}");
                self.workspace.record_phase_reset(encoder);
                return;
            }
        };
        plan.record(encoder);
        if let Some(word) = phase_reset_poison_word() {
            self.poison_phase_reset_tails(device, encoder, &plan, word);
        }
        if phase_reset_trace() {
            eprintln!(
                "lowering_phase_reset hir={}/{} semantic={}/{} cleared_bytes={} imported_bytes={} tails={} cached={cached} plan_us={}",
                job.hir_nodes,
                self.capacities.hir_nodes,
                job.semantic_instructions,
                self.capacities.semantic_instructions,
                plan.cleared_bytes(),
                plan.imported_bytes(),
                plan.tails().len(),
                started.elapsed().as_micros(),
            );
        }
    }

    fn phase_reset_plan(
        &self,
        job: LoweringCapacities,
    ) -> Result<(Arc<PhaseResetPlan>, bool), String> {
        let mut plans = self
            .phase_reset_plans
            .lock()
            .expect("lowering phase-reset plans poisoned");
        if let Some((_, plan)) = plans.iter().find(|(capacities, _)| *capacities == job) {
            return Ok((Arc::clone(plan), true));
        }
        let bytes =
            lowering_resource_bytes_for_artifact(job, self.target.lowering_target(), self.artifact_kind)?;
        let plan = Arc::new(self.workspace.phase_reset_plan(|name| bytes.get(name).copied())?);
        if plans.len() == PHASE_RESET_PLAN_CACHE {
            plans.remove(0);
        }
        plans.push((job, Arc::clone(&plan)));
        Ok((plan, false))
    }

    fn poison_phase_reset_tails(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        plan: &PhaseResetPlan,
        word: u32,
    ) {
        let Some(largest) = plan.tails().iter().map(|tail| tail.byte_size as u64).max() else {
            return;
        };
        let mut source = self
            .phase_reset_poison
            .lock()
            .expect("lowering phase-reset poison poisoned");
        let wanted = largest
            .min(PHASE_RESET_POISON_BYTES)
            .next_multiple_of(wgpu::COPY_BUFFER_ALIGNMENT);
        if source.as_ref().is_none_or(|buffer| (buffer.byte_size as u64) < wanted) {
            let raw = device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("lowering.phase_reset.poison"),
                size: wanted,
                usage: wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: true,
            });
            {
                let pattern = word.to_le_bytes().repeat((wanted / 4) as usize);
                let mut mapped = raw.slice(..).get_mapped_range_mut();
                mapped.slice(..).copy_from_slice(&pattern);
            }
            raw.unmap();
            *source = Some(LaniusBuffer::new_labeled(
                (raw, wanted),
                wanted as usize,
                "lowering.phase_reset.poison",
            ));
        }
        let source = source.as_ref().expect("phase-reset poison was just allocated");
        let chunk = source.byte_size as u64;
        for tail in plan.tails() {
            let bytes = tail.byte_size as u64;
            let mut offset = 0;
            while offset < bytes {
                let size = chunk.min(bytes - offset);
                source.copy_to(encoder, 0, tail, offset, size);
                offset += size;
            }
            #[cfg(test)]
            TEST_PHASE_RESET_POISONED_BYTES
                .fetch_add(bytes, std::sync::atomic::Ordering::Relaxed);
        }
    }

    fn record_status_readback(&self, encoder: &mut wgpu::CommandEncoder) {
        self.status_readback_copy.record(encoder);
        for copy in &self.job_totals_copies {
            copy.record(encoder);
        }
    }

    /// Flags a job whose semantic or target rows exceed the job's
    /// capacities, as the GPU checks of a fresh workspace for the job would
    /// (optimization/project.slang, x86 and Wasm validate.slang). A job at
    /// this workspace's capacities was checked on the GPU. The job's phase
    /// reset and x86 clears covered only its capacities, so its rows past
    /// them could read stale words; `from_frontend_unit` bounds both totals
    /// by eight rows per HIR row, and this enforces that bound.
    fn check_job_totals(&self, device: &wgpu::Device, status: &mut LoweringStatus) -> Result<()> {
        let job = *self
            .recorded_job
            .lock()
            .expect("lowering recorded job poisoned");
        let slice = self.job_totals_readback.slice(..);
        map_readback_blocking(device, &slice, "lowering job totals readback")?;
        let mapped = slice.get_mapped_range();
        let word =
            |index: usize| u32::from_le_bytes(mapped[index * 4..index * 4 + 4].try_into().unwrap());
        let (semantic_rows, target_rows) = (word(0), word(1));
        drop(mapped);
        self.job_totals_readback.unmap();
        if job != self.capacities {
            flag_job_totals(status, job, semantic_rows, target_rows);
        }
        Ok(())
    }

    /// Fails an artifact the job's capacities could not hold, as a fresh
    /// workspace for the job would: its x86 clears and phase reset covered
    /// only those capacities.
    fn check_job_artifact_bytes(&self, what: &str, bytes: usize) -> Result<()> {
        let job = *self
            .recorded_job
            .lock()
            .expect("lowering recorded job poisoned");
        let limit = job.artifact_bytes.max(4).next_multiple_of(4) as usize;
        if job != self.capacities && bytes > limit {
            anyhow::bail!(
                "GPU {what} requires {bytes} bytes but the job's lowering capacities provide {limit}"
            );
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
        self.target.record_after_target_pages(encoder, object)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, self.target.emission_timer_label());
        }
        Ok(())
    }

    /// Records the lowering into `encoder`, which the caller submits. The
    /// semantic stage and the optimizer are submitted as they are recorded
    /// (`SubmissionSplit`), so the GPU starts on them while the host records
    /// and finishes the rest; finishing costs several microseconds per
    /// dispatch, and a lowering records several hundred.
    pub(crate) fn record(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        mut timer: Option<&mut GpuTimer>,
        bounds: super::lowering::LoweringJobBounds,
    ) -> Result<()> {
        let bounds = job_bounds(bounds);
        let split = lowering_split(device, queue);
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
        self.record_job_phase_reset(device, encoder, job);
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "lowering.phase_reset.done");
        }
        // A workspace retained from a larger job would record that job's
        // pointer-jump pairs; the job's HIR bound gives its own.
        let jump_pairs = self
            .capacities
            .job_jump_pairs(bounds.hir_rows, self.target.lowering_target());
        self.semantic.record_timed(
            encoder,
            timer.as_deref_mut(),
            split,
            bounds,
            jump_pairs.execution_rank,
        )?;
        if let Some(split) = split {
            split.submit_prefix(
                encoder,
                "compile.lowering.semantic",
                "lowering.optimizer.submission.begin",
                timer.as_deref_mut(),
            );
        }
        self.optimizer
            .record_with_jump_pairs(encoder, timer.as_deref_mut(), jump_pairs)?;
        if let Some(split) = split {
            split.submit_prefix(
                encoder,
                "compile.lowering.optimizer",
                "lowering.target.submission.begin",
                timer.as_deref_mut(),
            );
        }
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
        selection: super::lowering::ReplaySelection<'_>,
        mut timer: Option<&mut GpuTimer>,
        bounds: super::lowering::LoweringJobBounds,
    ) -> Result<()> {
        let bounds = job_bounds(bounds);
        let split = lowering_split(device, queue);
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
        self.semantic.set_replay_functions(queue, selection)?;
        self.target
            .set_object_identity(queue, library_id, unit_id)?;
        let job = self.job_capacities(bounds);
        self.record_job_phase_reset(device, encoder, job);
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "lowering.phase_reset.done");
        }
        // A workspace retained from a larger job would record that job's
        // pointer-jump pairs; the job's HIR bound gives its own.
        let jump_pairs = self
            .capacities
            .job_jump_pairs(bounds.hir_rows, self.target.lowering_target());
        self.semantic.record_timed(
            encoder,
            timer.as_deref_mut(),
            split,
            bounds,
            jump_pairs.execution_rank,
        )?;
        if let Some(split) = split {
            split.submit_prefix(
                encoder,
                "compile.lowering.semantic",
                "lowering.optimizer.submission.begin",
                timer.as_deref_mut(),
            );
        }
        self.optimizer
            .record_with_jump_pairs(encoder, timer.as_deref_mut(), jump_pairs)?;
        if let Some(split) = split {
            split.submit_prefix(
                encoder,
                "compile.lowering.optimizer",
                "lowering.target.submission.begin",
                timer.as_deref_mut(),
            );
        }
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
    ) -> Result<super::wasm::GpuWasmRelocatableObject> {
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
    ) -> Result<(super::x86::GpuX86RelocatableObject, Vec<u32>)> {
        self.ensure_success(device)?;
        let finished = match &self.target {
            TargetStage::X86_64(stage) => stage.finish_object(device, queue, library_id, unit_id),
            TargetStage::Wasm(_) => {
                anyhow::bail!("the selected lowering pipeline does not produce an x86 object")
            }
        }?;
        // The object's artifact words hold its text and rodata together.
        self.check_job_artifact_bytes(
            "x86 object text and rodata",
            finished.0.text.len() + finished.0.rodata.len(),
        )?;
        Ok(finished)
    }

    pub(crate) fn finish_status(&self, device: &wgpu::Device) -> Result<LoweringStatus> {
        let slice = self.status_readback.slice(..);
        map_readback_blocking(device, &slice, "lowering status readback")?;
        let mapped = slice.get_mapped_range();
        let word =
            |index: usize| u32::from_le_bytes(mapped[index * 4..index * 4 + 4].try_into().unwrap());
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
        drop(mapped);
        self.status_readback.unmap();
        self.check_job_totals(device, &mut status)?;
        if status.flags != 0 {
            if let Err(error) = self.optimizer.report_failure_trace(device) {
                eprintln!("[optimization.failure.trace] readback failed: {error:#}");
            }
        }
        Ok(status)
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
    use crate::gpu::{device, passes_core::pipeline_creation_count};

    #[test]
    fn job_totals_past_the_jobs_capacities_fail_as_the_gpu_checks_would() {
        use crate::codegen::lowering_ir::opcode::{
            LOWERING_STATUS_SEMANTIC_CAPACITY,
            LOWERING_STATUS_TARGET_CAPACITY,
        };
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
    fn physical_gpu_constructs_one_workspace_pipeline_for_each_target() {
        std::thread::Builder::new()
            .name("lowering pipeline construction".into())
            .stack_size(64 * 1024 * 1024)
            .spawn(run_physical_gpu_constructs_one_workspace_pipeline_for_each_target)
            .unwrap()
            .join()
            .unwrap();
    }

    fn run_physical_gpu_constructs_one_workspace_pipeline_for_each_target() {
        let gpu = device::global();
        let compiler =
            pollster::block_on(crate::compiler::GpuCompiler::new_with_device_and_backends(
                gpu,
                crate::compiler::GpuCompilerBackends::all(),
            ))
            .unwrap();
        let pipelines_after_prepare = pipeline_creation_count();
        let source = "fn main() -> i32 { return 42; }";
        pollster::block_on(compiler.compile_source_to_x86_64(source)).unwrap();
        pollster::block_on(compiler.compile_source_to_wasm(source)).unwrap();
        assert_eq!(pipeline_creation_count(), pipelines_after_prepare);
    }
}
