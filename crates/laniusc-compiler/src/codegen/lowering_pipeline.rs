//! One graph-owned lowering pipeline from compact semantic HIR to the selected
//! target LIR and artifact boundary.

use std::sync::{Arc, Mutex};

use anyhow::Result;

use super::{
    lowering::{GpuSemanticHirInputs, GpuSemanticLoweringStage},
    lowering_ir::{LoweringCapacities, LoweringStatus, LoweringTarget, lowering_compiler_graph},
    wasm_lowering::GpuWasmLirStage,
    x86_lowering::GpuX86LirStage,
};
use crate::{
    gpu::{
        buffers::{LaniusBuffer, readback_bytes, with_uniform_buffer_arena},
        compiler_graph::CompilerGraphWorkspace,
        passes_core::map_readback_blocking,
    },
    parser::buffers::GpuHirView,
    type_checker::GpuSemanticArtifactView,
};

enum TargetStage {
    X86_64(GpuX86LirStage),
    Wasm(GpuWasmLirStage),
}

impl TargetStage {
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

    fn set_object_identity(&self, queue: &wgpu::Queue, library_id: u32, unit_id: u32) {
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
    _workspace: CompilerGraphWorkspace,
    semantic: GpuSemanticLoweringStage,
    target: TargetStage,
    status_readback: LaniusBuffer<u8>,
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
        source_bytes: u32,
        tokens: u32,
        hir_nodes: u32,
    ) -> Result<Arc<GpuLoweringPipeline>, String> {
        let required =
            LoweringCapacities::from_frontend_unit(source_bytes, tokens, hir_nodes, self.target)?
                .bucketed();
        let mut current = self
            .current
            .lock()
            .expect("lowering workspace cache poisoned");
        if let Some(pipeline) = current.as_ref()
            && pipeline.capacities.covers(required)
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
            GpuLoweringPipeline::new(device, capacities, self.target)
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
    pub(crate) fn new(
        device: &wgpu::Device,
        capacities: LoweringCapacities,
        target: LoweringTarget,
    ) -> Result<Self> {
        let label = match target {
            LoweringTarget::X86_64 => "codegen.x86.lowering.uniform_arena",
            LoweringTarget::Wasm => "codegen.wasm.lowering.uniform_arena",
        };
        with_uniform_buffer_arena(device, label, || {
            Self::new_with_uniform_arena(device, capacities, target)
        })
    }

    fn new_with_uniform_arena(
        device: &wgpu::Device,
        capacities: LoweringCapacities,
        target: LoweringTarget,
    ) -> Result<Self> {
        let graph = lowering_compiler_graph(capacities, target).map_err(anyhow::Error::msg)?;
        let workspace = CompilerGraphWorkspace::new(device, "codegen.lowering", &graph)
            .map_err(anyhow::Error::msg)?;
        let semantic = GpuSemanticLoweringStage::from_workspace(
            device,
            capacities,
            graph.clone(),
            &workspace,
        )?;
        let target = match target {
            LoweringTarget::X86_64 => TargetStage::X86_64(GpuX86LirStage::new(
                device,
                &graph,
                &workspace,
                capacities,
                semantic.output(),
            )?),
            LoweringTarget::Wasm => TargetStage::Wasm(GpuWasmLirStage::new(
                device,
                &graph,
                &workspace,
                capacities,
                semantic.output(),
            )?),
        };
        let status_readback = readback_bytes(device, "lowering.status.readback", 16, 16);
        Ok(Self {
            capacities,
            _workspace: workspace,
            semantic,
            target,
            status_readback,
        })
    }

    fn record_target_pages(&self, encoder: &mut wgpu::CommandEncoder, object: bool) -> Result<()> {
        self.target.record_before_target_pages(encoder)?;
        for page_id in 0..self.target.target_page_count() {
            self.target.record_measure_page(encoder, page_id)?;
        }
        self.target.record_between_target_pages(encoder, object)?;
        for page_id in 0..self.target.target_page_count() {
            self.target.record_emit_page(encoder, page_id)?;
        }
        self.target.record_after_target_pages(encoder, object)
    }

    pub(crate) fn record(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        hir: GpuSemanticHirInputs<'_>,
        semantic_inputs: GpuSemanticArtifactView<'_>,
    ) -> Result<()> {
        self.semantic
            .record(device, encoder, hir, semantic_inputs)?;
        for page_id in 0..self.target.count_page_count() {
            self.target.record_count_page(encoder, page_id)?;
        }
        self.record_target_pages(encoder, false)?;
        encoder.copy_buffer_to_buffer(
            &self.semantic.status().buffer,
            0,
            &self.status_readback.buffer,
            0,
            16,
        );
        Ok(())
    }

    /// Production boundary from checked compact HIR and the narrow semantic
    /// type-check artifact. Keeping this conversion here prevents backend
    /// orchestration from reaching back into raw parser rows or the full
    /// type-check scratch surface.
    pub(crate) fn record_checked_hir(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        hir: &GpuHirView,
        semantic: GpuSemanticArtifactView<'_>,
    ) -> Result<()> {
        self.record(device, encoder, hir.into(), semantic)
    }

    pub(crate) fn record_checked_hir_object(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        hir: &GpuHirView,
        semantic: GpuSemanticArtifactView<'_>,
        library_id: u32,
        unit_id: u32,
    ) -> Result<()> {
        self.semantic
            .record(device, encoder, hir.into(), semantic)?;
        for page_id in 0..self.target.count_page_count() {
            self.target.record_count_page(encoder, page_id)?;
        }
        self.target.set_object_identity(queue, library_id, unit_id);
        self.record_target_pages(encoder, true)?;
        encoder.copy_buffer_to_buffer(
            &self.semantic.status().buffer,
            0,
            &self.status_readback.buffer,
            0,
            16,
        );
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
        };
        drop(mapped);
        self.status_readback.unmap();
        Ok(status)
    }

    fn ensure_success(&self, device: &wgpu::Device) -> Result<()> {
        let status = self.finish_status(device)?;
        if status.flags != 0 {
            anyhow::bail!(
                "GPU lowering failed (flags=0x{:x}, first HIR={}, required capacity={}, available capacity={})",
                status.flags,
                status.first_unsupported_hir,
                status.required_capacity,
                status.available_capacity,
            );
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::gpu::device;

    #[test]
    fn lowering_workspace_cache_starts_without_job_storage() {
        for target in [LoweringTarget::X86_64, LoweringTarget::Wasm] {
            let cache = GpuLoweringWorkspaceCache::new(target);
            assert_eq!(cache.retained_capacities(), None);
        }
    }

    #[test]
    fn physical_gpu_constructs_one_workspace_pipeline_for_each_target() {
        let gpu = device::global();
        let capacities = LoweringCapacities {
            source_bytes: 32,
            tokens: 32,
            hir_nodes: 16,
            semantic_instructions: 48,
            call_arguments: 16,
            parameters: 16,
            aggregate_elements: 16,
            target_instructions: 64,
            artifact_bytes: 256,
        };
        for target in [LoweringTarget::X86_64, LoweringTarget::Wasm] {
            let pipeline = GpuLoweringPipeline::new(&gpu.device, capacities, target).unwrap();
            match (target, &pipeline.target) {
                (LoweringTarget::X86_64, TargetStage::X86_64(_))
                | (LoweringTarget::Wasm, TargetStage::Wasm(_)) => {}
                _ => panic!("pipeline selected the wrong target stage"),
            }
        }
    }
}
