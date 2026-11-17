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
        match self.lower_projected_batch(SourcePackArtifactTarget::X86_64,source_bytes,tokens,hir_nodes,hir,semantic,library,unit,&mut |_|{})? {
            typecheck::CompiledSourcePackObject::X86_64(object)=>Ok(object),
            _=>unreachable!("x86 lowering requested"),
        }
    }

    /// `submitted` runs after each lowering attempt is submitted and before
    /// its status is read: host work there overlaps the GPU lowering. It
    /// receives the slot the attempt's x86 object parked in.
    #[allow(clippy::too_many_arguments)]
    pub(super) fn lower_projected_batch(
        &self,target:SourcePackArtifactTarget,source_bytes:u32,tokens:u32,hir_nodes:u32,
        hir:GpuSemanticHirInputs<'_>,semantic:crate::type_checker::GpuSemanticArtifactView<'_>,library:u32,unit:u32,
        submitted:&mut dyn FnMut(Option<x86::ParkedSlot>),
    )->anyhow::Result<typecheck::CompiledSourcePackObject> {
        let recorded=self.record_projected_batch(target,source_bytes,tokens,hir_nodes,hir,semantic,library,unit,submitted)?;
        self.finish_projected_batch(recorded,hir,semantic,submitted)
    }

    /// The submission half of [`Self::lower_projected_batch`]: records and
    /// submits the batch's lowering. Dropping the result discards it; a
    /// later recording of the batch replaces everything it wrote.
    #[allow(clippy::too_many_arguments)]
    pub(super) fn record_projected_batch(
        &self,target:SourcePackArtifactTarget,source_bytes:u32,tokens:u32,hir_nodes:u32,
        hir:GpuSemanticHirInputs<'_>,semantic:crate::type_checker::GpuSemanticArtifactView<'_>,library:u32,unit:u32,
        submitted:&mut dyn FnMut(Option<x86::ParkedSlot>),
    )->anyhow::Result<RecordedProjectedBatch> {
        let lowering_target=match target { SourcePackArtifactTarget::X86_64=>LoweringTarget::X86_64,SourcePackArtifactTarget::Wasm=>LoweringTarget::Wasm,
            SourcePackArtifactTarget::Generic=>anyhow::bail!("projection requires an executable target") };
        // The batch's rows and bytes bound the job, as they would bound a
        // workspace built for it: the shared arena is the frontend's, and
        // its full capacity would size the phase reset and the clears.
        let bounds = LoweringJobBounds {
            hir_rows: hir_nodes,
            source_bytes,
            ..LoweringJobBounds::CONSERVATIVE
        };
        let mut recorded=RecordedProjectedBatch{
            pipeline:None,target,lowering_target,source_bytes,tokens,hir_nodes,library,unit,bounds,attempt:0,
        };
        self.record_projected_attempt(&mut recorded,hir,semantic,submitted)?;
        Ok(recorded)
    }

    fn record_projected_attempt(
        &self,recorded:&mut RecordedProjectedBatch,
        hir:GpuSemanticHirInputs<'_>,semantic:crate::type_checker::GpuSemanticArtifactView<'_>,
        submitted:&mut dyn FnMut(Option<x86::ParkedSlot>),
    )->anyhow::Result<()> {
        let device = &self.gpu.device;
        let queue = &self.gpu.queue;
        let pipeline = self
            .ensure_projected_lowering_pipeline(
                recorded.lowering_target,
                recorded.source_bytes,
                recorded.tokens,
                recorded.hir_nodes,
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
            recorded.library,
            recorded.unit,
            ObjectFunctions::All,
            None,
            recorded.bounds,
        )?;
        queue.submit(Some(encoder.finish()));
        submitted(pipeline.parked_x86_slot());
        recorded.pipeline=Some(pipeline);
        Ok(())
    }

    /// The readback half of [`Self::lower_projected_batch`]. An
    /// output-capacity failure is recorded again once, over the same
    /// columns, at the demand the GPU reported.
    pub(super) fn finish_projected_batch(
        &self,mut recorded:RecordedProjectedBatch,
        hir:GpuSemanticHirInputs<'_>,semantic:crate::type_checker::GpuSemanticArtifactView<'_>,
        submitted:&mut dyn FnMut(Option<x86::ParkedSlot>),
    )->anyhow::Result<typecheck::CompiledSourcePackObject> {
        let device = &self.gpu.device;
        let queue = &self.gpu.queue;
        loop {
            let pipeline=recorded.pipeline.take().expect("a recorded lowering has a pipeline");
            let (library,unit)=(recorded.library,recorded.unit);
            let _span = x86::TailSpan::new("tail.instance.finish_object");
            let result=match recorded.target {
                SourcePackArtifactTarget::X86_64=>pipeline.finish_x86_object(device,queue,library,unit,self.x86_linker().ok().and_then(|linker|linker.parking_store()).as_ref()).map(|(o,_)|typecheck::CompiledSourcePackObject::from(o)),
                SourcePackArtifactTarget::Wasm=>pipeline.finish_wasm_object(device,queue,library,unit).map(|(o,_)|typecheck::CompiledSourcePackObject::Wasm(o)),
                SourcePackArtifactTarget::Generic=>unreachable!("executable target checked above"),
            };
            let error = match result {
                Ok(object) => return Ok(object),
                Err(error) => error,
            };
            crate::gpu::dispatch_capture::debug_write_capture(device, queue);
            crate::gpu::passes_core::debug_dump_buffers(device, queue, "retained_lowering");
            let demand = pipeline
                .output_demand_for_retry(&error)
                .map_err(anyhow::Error::msg)?;
            match demand {
                Some(demand) if recorded.attempt == 0 => {
                    // The workspace clamps a job to its own output
                    // capacity, so the retry needs a larger one.
                    self.grow_projected_lowering_output(recorded.lowering_target, demand)
                        .map_err(anyhow::Error::msg)?;
                    recorded.bounds.output_demand = demand;
                    recorded.attempt += 1;
                    drop(_span);
                    self.record_projected_attempt(&mut recorded,hir,semantic,submitted)?;
                }
                _ => return Err(error),
            }
        }
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

/// A projected batch's lowering, submitted and not yet read back
/// ([`GpuCompiler::record_projected_batch`]).
pub(super) struct RecordedProjectedBatch {
    pipeline: Option<std::sync::Arc<crate::codegen::lowering_pipeline::GpuLoweringPipeline>>,
    target: SourcePackArtifactTarget,
    lowering_target: LoweringTarget,
    source_bytes: u32,
    tokens: u32,
    hir_nodes: u32,
    library: u32,
    unit: u32,
    bounds: LoweringJobBounds,
    attempt: u32,
}
