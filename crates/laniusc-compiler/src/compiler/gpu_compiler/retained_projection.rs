//! Native lowering of retained-instance projection batches
//! (docs/compiler-retained-projection.md). A batch's lowering columns are
//! GPU buffers the projection wrote; this entry runs the existing lowering
//! pipeline over them as one object job and links finished objects. It runs
//! no frontend stage.

use super::*;
use crate::codegen::{
    lowering::{GpuSemanticHirInputs, LoweringJobBounds, ReplaySelection},
    lowering_ir::LoweringArtifactKind,
    x86::{self, GpuX86RelocatableObject},
};

impl GpuCompiler<'_> {
    /// Lowers one projected batch to an x86 object with identity
    /// `(library, unit)`. `source_bytes`, `tokens` and `hir_nodes` are the
    /// batch column capacities. An output-capacity failure is retried once
    /// at the demand the GPU reported.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn lower_projected_x86_batch(
        &self,
        source_bytes: u32,
        tokens: u32,
        hir_nodes: u32,
        hir: GpuSemanticHirInputs<'_>,
        semantic: crate::type_checker::GpuSemanticArtifactView<'_>,
        library: u32,
        unit: u32,
    ) -> anyhow::Result<GpuX86RelocatableObject> {
        let device = &self.gpu.device;
        let queue = &self.gpu.queue;
        let mut bounds = LoweringJobBounds::CONSERVATIVE;
        for attempt in 0..2 {
            let pipeline = self
                .ensure_lowering_pipeline(
                    LoweringTarget::X86_64,
                    source_bytes,
                    tokens,
                    hir_nodes,
                    LoweringArtifactKind::Object,
                    &[],
                    hir,
                    semantic,
                )
                .map_err(anyhow::Error::msg)?;
            let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("retained_projection.lowering"),
            });
            pipeline.record_object(
                device,
                queue,
                &mut encoder,
                library,
                unit,
                ReplaySelection::Functions(&[]),
                None,
                bounds,
            )?;
            queue.submit(Some(encoder.finish()));
            match pipeline.finish_x86_object(device, queue, library, unit) {
                Ok((object, _)) => return Ok(object),
                Err(error) => {
                    crate::gpu::dispatch_capture::debug_write_capture(device, queue);
                    crate::gpu::passes_core::debug_dump_buffers(device, queue, "retained_lowering");
                    let demand = pipeline
                        .output_demand_for_retry(&error)
                        .map_err(anyhow::Error::msg)?;
                    match demand {
                        Some(demand) if attempt == 0 => bounds.output_demand = demand,
                        _ => return Err(error),
                    }
                }
            }
        }
        unreachable!("the loop returns on its second attempt")
    }

    /// Links x86 objects into an executable.
    #[doc(hidden)]
    pub fn link_x86_objects(&self, objects: &[GpuX86RelocatableObject]) -> anyhow::Result<Vec<u8>> {
        let input = x86::GpuX86LinkInput::for_executable_refs(objects.iter())
            .map_err(anyhow::Error::msg)?;
        let linker = self
            .x86_linker()
            .map_err(|reason| anyhow::anyhow!("{reason}"))?;
        linker
            .link_executable(&self.gpu.device, &self.gpu.queue, &input)
            .map_err(|error| anyhow::anyhow!("{error:?}"))
    }
}
