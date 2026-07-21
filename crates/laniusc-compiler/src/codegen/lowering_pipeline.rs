//! One graph-owned lowering pipeline from compact semantic HIR to the selected
//! target LIR and artifact boundary.

use anyhow::Result;

use super::{
    lowering::{GpuSemanticHirInputs, GpuSemanticLoweringStage},
    lowering_ir::{LoweringCapacities, LoweringStatus, LoweringTarget, lowering_compiler_graph},
    wasm_lowering::{GpuWasmArtifactView, GpuWasmLirStage, GpuWasmLirView},
    x86_lowering::{GpuX86LirStage, GpuX86LirView},
};
use crate::{
    gpu::{
        buffers::{LaniusBuffer, readback_bytes},
        compiler_graph::{CompilerGraph, CompilerGraphWorkspace},
        passes_core::map_readback_blocking,
    },
    parser::buffers::GpuHirView,
    type_checker::{GpuCodegenBuffers, GpuSemanticLoweringBuffers},
};

enum TargetStage {
    X86_64(GpuX86LirStage),
    Wasm(GpuWasmLirStage),
}

pub(crate) enum GpuTargetLirView<'a> {
    X86_64(GpuX86LirView<'a>),
    Wasm {
        lir: GpuWasmLirView<'a>,
        artifact: GpuWasmArtifactView<'a>,
    },
}

/// Daemon-resident ownership root for both lowering levels. The graph assigns
/// all phase-local aliases in one workspace, while the target enum guarantees
/// that an inactive backend consumes no resident slots.
///
/// The target passes and their bind groups are created here. Semantic input
/// bind groups are still job-bound until parser/type-check outputs themselves
/// move into stable graph-owned slots; that remaining boundary is explicit in
/// `record` rather than hidden inside either backend.
pub(crate) struct GpuLoweringPipeline {
    graph: CompilerGraph,
    _workspace: CompilerGraphWorkspace,
    semantic: GpuSemanticLoweringStage,
    target: TargetStage,
    status_readback: LaniusBuffer<u8>,
}

impl GpuLoweringPipeline {
    pub(crate) fn new(
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
            graph,
            _workspace: workspace,
            semantic,
            target,
            status_readback,
        })
    }

    pub(crate) fn record(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        hir: GpuSemanticHirInputs<'_>,
        semantic_inputs: GpuSemanticLoweringBuffers<'_>,
    ) -> Result<()> {
        self.semantic
            .record(device, encoder, hir, semantic_inputs)?;
        match &self.target {
            TargetStage::X86_64(stage) => stage.record(encoder),
            TargetStage::Wasm(stage) => stage.record(encoder),
        }?;
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
        semantic: GpuCodegenBuffers<'_>,
    ) -> Result<()> {
        self.record(device, encoder, hir.into(), semantic.lowering)
    }

    pub(crate) fn output(&self) -> GpuTargetLirView<'_> {
        match &self.target {
            TargetStage::X86_64(stage) => GpuTargetLirView::X86_64(stage.output()),
            TargetStage::Wasm(stage) => GpuTargetLirView::Wasm {
                lir: stage.output(),
                artifact: stage.artifact(),
            },
        }
    }

    pub(crate) fn graph(&self) -> &CompilerGraph {
        &self.graph
    }

    pub(crate) fn status(&self) -> &LaniusBuffer<super::lowering_ir::LoweringStatus> {
        self.semantic.status()
    }

    /// Completes a previously submitted Wasm job from daemon-resident
    /// readback storage. x86 obtains an equivalent artifact boundary once its
    /// register-allocation and executable-layout passes are attached.
    pub(crate) fn finish_wasm_artifact(&self, device: &wgpu::Device) -> Result<Vec<u8>> {
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
        match &self.target {
            TargetStage::Wasm(stage) => stage.finish_artifact(device),
            TargetStage::X86_64(_) => {
                anyhow::bail!("the selected lowering pipeline does not produce a Wasm artifact")
            }
        }
    }

    pub(crate) fn finish_x86_artifact(&self, device: &wgpu::Device) -> Result<Vec<u8>> {
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
        match &self.target {
            TargetStage::X86_64(stage) => stage.finish_artifact(device),
            TargetStage::Wasm(_) => {
                anyhow::bail!("the selected lowering pipeline does not produce an x86 artifact")
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
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::gpu::device;

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
        for (target, target_pass) in [
            (LoweringTarget::X86_64, "lir.x86.scatter"),
            (LoweringTarget::Wasm, "lir.wasm.scatter"),
        ] {
            let pipeline = GpuLoweringPipeline::new(&gpu.device, capacities, target).unwrap();
            assert!(pipeline.graph().pass_id("lir.semantic.scatter").is_some());
            assert!(pipeline.graph().pass_id(target_pass).is_some());
            match (target, pipeline.output()) {
                (LoweringTarget::X86_64, GpuTargetLirView::X86_64(_))
                | (LoweringTarget::Wasm, GpuTargetLirView::Wasm { .. }) => {}
                _ => panic!("pipeline selected the wrong target stage"),
            }
        }
    }
}
