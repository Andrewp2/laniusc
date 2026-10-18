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
    },
    optimization::GpuOptimizationStage,
    wasm_lowering::GpuWasmLirStage,
    x86_lowering::GpuX86LirStage,
};
use crate::{
    gpu::{
        buffers::{LaniusBuffer, TrackedBufferView, readback_bytes, with_uniform_buffer_arena},
        compiler_graph::CompilerGraphWorkspace,
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
    ) -> Result<()> {
        match self {
            Self::X86_64(stage) => stage.record_count_page(encoder, page_id, timer),
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
    ) -> Result<()> {
        match self {
            Self::X86_64(stage) => stage.record_between_target_pages(encoder, object),
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
        })
    }

    fn record_target_pages(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        object: bool,
        timer: &mut Option<&mut GpuTimer>,
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
        self.target.record_between_target_pages(encoder, object)?;
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
        self.workspace.record_phase_reset(encoder);
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "lowering.phase_reset.done");
        }
        self.semantic
            .record_timed(encoder, timer.as_deref_mut(), split, bounds)?;
        if let Some(split) = split {
            split.submit_prefix(
                encoder,
                "compile.lowering.semantic",
                "lowering.optimizer.submission.begin",
                timer.as_deref_mut(),
            );
        }
        self.optimizer.record(encoder, timer.as_deref_mut())?;
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
                .record_count_page(encoder, page_id, &mut timer)?;
        }
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "codegen.target.analysis_count.done");
        }
        self.record_target_pages(encoder, false, &mut timer)?;
        self.status_readback_copy.record(encoder);
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
        self.workspace.record_phase_reset(encoder);
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "lowering.phase_reset.done");
        }
        self.semantic
            .record_timed(encoder, timer.as_deref_mut(), split, bounds)?;
        if let Some(split) = split {
            split.submit_prefix(
                encoder,
                "compile.lowering.semantic",
                "lowering.optimizer.submission.begin",
                timer.as_deref_mut(),
            );
        }
        self.optimizer.record(encoder, timer.as_deref_mut())?;
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
                .record_count_page(encoder, page_id, &mut timer)?;
        }
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "codegen.target.analysis_count.done");
        }
        self.record_target_pages(encoder, true, &mut timer)?;
        self.status_readback_copy.record(encoder);
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
        match &self.target {
            TargetStage::X86_64(stage) => stage.finish_artifact(device, queue),
            TargetStage::Wasm(stage) => stage.finish_artifact(device, queue),
        }
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
        match &self.target {
            TargetStage::X86_64(stage) => stage.finish_object(device, queue, library_id, unit_id),
            TargetStage::Wasm(_) => {
                anyhow::bail!("the selected lowering pipeline does not produce an x86 object")
            }
        }
    }

    pub(crate) fn finish_status(&self, device: &wgpu::Device) -> Result<LoweringStatus> {
        let slice = self.status_readback.slice(..);
        map_readback_blocking(device, &slice, "lowering status readback")?;
        let mapped = slice.get_mapped_range();
        let word =
            |index: usize| u32::from_le_bytes(mapped[index * 4..index * 4 + 4].try_into().unwrap());
        let status = LoweringStatus {
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
