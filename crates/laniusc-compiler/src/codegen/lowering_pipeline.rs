//! One graph-owned lowering pipeline from compact semantic HIR to the selected
//! target LIR and artifact boundary.

use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};

use anyhow::Result;

use super::{
    lowering::{GpuSemanticHirInputs, GpuSemanticLoweringStage, semantic_input_views},
    lowering_ir::{
        LoweringArtifactKind,
        LoweringCapacities,
        LoweringStatus,
        LoweringTarget,
        lowering_compiler_graph_for_artifact,
    },
    wasm_lowering::GpuWasmLirStage,
    x86_lowering::GpuX86LirStage,
};
use crate::{
    gpu::{
        buffers::{LaniusBuffer, TrackedBufferView, readback_bytes, with_uniform_buffer_arena},
        compiler_graph::CompilerGraphWorkspace,
        passes_core::map_readback_blocking,
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
            "GPU lowering failed (flags=0x{:x}, first HIR={}, required capacity={}, available capacity={})",
            status.flags,
            status.first_unsupported_hir,
            status.required_capacity,
            status.available_capacity,
        )
    }
}

impl std::error::Error for LoweringFailure {}

enum TargetStage {
    X86_64(GpuX86LirStage),
    Wasm(GpuWasmLirStage),
}

impl TargetStage {
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

    fn record_count_page(&self, encoder: &mut wgpu::CommandEncoder, page_id: usize) -> Result<()> {
        match self {
            Self::X86_64(stage) => stage.record_count_page(encoder, page_id),
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
    _workspace: CompilerGraphWorkspace,
    semantic: GpuSemanticLoweringStage,
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
            .map_err(|err| err.to_string())?,
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
        let target = match target {
            LoweringTarget::X86_64 => TargetStage::X86_64(GpuX86LirStage::new(
                device,
                &graph,
                &workspace,
                capacities,
                semantic.output(),
                artifact_kind == LoweringArtifactKind::Object,
                kernels,
            )?),
            LoweringTarget::Wasm => TargetStage::Wasm(GpuWasmLirStage::new(
                device,
                &graph,
                &workspace,
                capacities,
                semantic.output(),
                artifact_kind == LoweringArtifactKind::Object,
                kernels,
            )?),
        };
        let status_readback = readback_bytes(device, "lowering.status.readback", 32, 32);
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
            32,
        )?;
        Ok(Self {
            capacities,
            artifact_kind,
            upstream_signature,
            semantic_input_signature,
            _workspace: workspace,
            semantic,
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
        self.target.record_before_target_pages(encoder)?;
        for page_id in 0..self.target.target_page_count() {
            self.target.record_measure_page(encoder, page_id)?;
        }
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, self.target.lowering_timer_label());
        }
        self.target.record_between_target_pages(encoder, object)?;
        for page_id in 0..self.target.target_page_count() {
            self.target.record_emit_page(encoder, page_id)?;
        }
        self.target.record_after_target_pages(encoder, object)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, self.target.emission_timer_label());
        }
        Ok(())
    }

    pub(crate) fn record(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        mut timer: Option<&mut GpuTimer>,
    ) -> Result<()> {
        let _compute_batch = crate::gpu::passes_core::DeferredComputeBatchGuard::begin(
            crate::gpu::passes_core::compute_pass_batching_allowed(timer.is_some()),
            "lowering.executable.batch",
        );
        self.semantic.record_timed(encoder, timer.as_deref_mut())?;
        for page_id in 0..self.target.count_page_count() {
            self.target.record_count_page(encoder, page_id)?;
        }
        self.record_target_pages(encoder, false, &mut timer)?;
        self.status_readback_copy.record(encoder);
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "artifact.status_readback.done");
        }
        Ok(())
    }

    pub(crate) fn record_object(
        &self,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        library_id: u32,
        unit_id: u32,
        mut timer: Option<&mut GpuTimer>,
    ) -> Result<()> {
        let _compute_batch = crate::gpu::passes_core::DeferredComputeBatchGuard::begin(
            crate::gpu::passes_core::compute_pass_batching_allowed(timer.is_some()),
            "lowering.object.batch",
        );
        self.semantic.record_timed(encoder, timer.as_deref_mut())?;
        for page_id in 0..self.target.count_page_count() {
            self.target.record_count_page(encoder, page_id)?;
        }
        self.target
            .set_object_identity(queue, library_id, unit_id)?;
        self.record_target_pages(encoder, true, &mut timer)?;
        self.status_readback_copy.record(encoder);
        if let Some(timer) = timer.as_deref_mut() {
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
    ) -> Result<super::x86::GpuX86RelocatableObject> {
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
            required_capacity: word(2),
            available_capacity: word(3),
            diagnostic_reason: word(4),
            diagnostic_detail_kind: word(5),
            diagnostic_detail: word(6),
            diagnostic_aux: word(7),
        };
        drop(mapped);
        self.status_readback.unmap();
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
