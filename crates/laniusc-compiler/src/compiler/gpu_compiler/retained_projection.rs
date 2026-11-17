//! Native lowering of retained-instance projection batches
//! (docs/compiler-retained-projection.md). A batch's lowering columns are
//! GPU buffers the projection wrote; this entry runs the existing lowering
//! pipeline over them as one object job and links finished objects. It runs
//! no frontend stage.

use super::*;
use crate::codegen::{
    lowering::{GpuSemanticHirInputs, LoweringJobBounds, ObjectFunctions},
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
        match self.lower_projected_batch(SourcePackArtifactTarget::X86_64,source_bytes,tokens,hir_nodes,hir,semantic,library,unit,&mut ||{})? {
            typecheck::CompiledSourcePackObject::X86_64(object)=>Ok(object),
            _=>unreachable!("x86 lowering requested"),
        }
    }

    /// `submitted` runs after each lowering attempt is submitted and before
    /// its status is read: host work there overlaps the GPU lowering.
    #[allow(clippy::too_many_arguments)]
    pub(super) fn lower_projected_batch(
        &self,target:SourcePackArtifactTarget,source_bytes:u32,tokens:u32,hir_nodes:u32,
        hir:GpuSemanticHirInputs<'_>,semantic:crate::type_checker::GpuSemanticArtifactView<'_>,library:u32,unit:u32,
        submitted:&mut dyn FnMut(),
    )->anyhow::Result<typecheck::CompiledSourcePackObject> {
        let lowering_target=match target { SourcePackArtifactTarget::X86_64=>LoweringTarget::X86_64,SourcePackArtifactTarget::Wasm=>LoweringTarget::Wasm,
            SourcePackArtifactTarget::Generic=>anyhow::bail!("projection requires an executable target") };
        let device = &self.gpu.device;
        let queue = &self.gpu.queue;
        // The batch's rows and bytes bound the job, as they would bound a
        // workspace built for it: the shared arena is the frontend's, and
        // its full capacity would size the phase reset and the clears.
        let mut bounds = LoweringJobBounds {
            hir_rows: hir_nodes,
            source_bytes,
            ..LoweringJobBounds::CONSERVATIVE
        };
        for attempt in 0..2 {
            let pipeline = self
                .ensure_projected_lowering_pipeline(
                    lowering_target,
                    source_bytes,
                    tokens,
                    hir_nodes,
                    LoweringArtifactKind::Object,
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
                ObjectFunctions::All,
                None,
                bounds,
            )?;
            queue.submit(Some(encoder.finish()));
            submitted();
            let _span = x86::TailSpan::new("tail.instance.finish_object");
            let result=match target {
                SourcePackArtifactTarget::X86_64=>pipeline.finish_x86_object(device,queue,library,unit).map(|(o,_)|typecheck::CompiledSourcePackObject::from(o)),
                SourcePackArtifactTarget::Wasm=>pipeline.finish_wasm_object(device,queue,library,unit).map(|(o,_)|typecheck::CompiledSourcePackObject::Wasm(o)),
                SourcePackArtifactTarget::Generic=>unreachable!("executable target checked above"),
            };
            match result {
                Ok(object) => return Ok(object),
                Err(error) => {
                    crate::gpu::dispatch_capture::debug_write_capture(device, queue);
                    crate::gpu::passes_core::debug_dump_buffers(device, queue, "retained_lowering");
                    let demand = pipeline
                        .output_demand_for_retry(&error)
                        .map_err(anyhow::Error::msg)?;
                    match demand {
                        Some(demand) if attempt == 0 => {
                            // The workspace clamps a job to its own output
                            // capacity, so the retry needs a larger one.
                            self.grow_projected_lowering_output(lowering_target, demand)
                                .map_err(anyhow::Error::msg)?;
                            bounds.output_demand = demand;
                        }
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
