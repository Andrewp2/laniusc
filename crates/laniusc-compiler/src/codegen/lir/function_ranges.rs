//! Shared compaction of scheduled semantic rows into target function ranges.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::lowering_ir::{
    LOWERING_PROGRAM_SLOTS, LoweringCapacities, TARGET_FUNCTION_PROGRAM_SLOT, TargetLirFunction,
};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    compiler_graph::{CompilerGraph, CompilerGraphAllocations, CompilerGraphWorkspace},
    kernels::KernelRegistry,
    operations::{
        STEP_PROGRAM_SYNC_WORDS, StepProgramOperation,
        step_program_group_counts, step_program_group_variant,
    },
    resource_registry::ResourceMap,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct FunctionParams {
    semantic_capacity: u32,
    target_capacity: u32,
    function_capacity: u32,
    reserved: u32,
}

#[derive(Clone, Copy)]
#[cfg(test)]
pub(crate) struct GpuTargetFunctionView<'a> {
    pub count: &'a LaniusBuffer<u32>,
    pub rows: &'a LaniusBuffer<TargetLirFunction>,
}

/// Compact target ranges derived from the already sorted semantic schedule.
///
/// Function ownership is preserved as optimizer provenance. Target lowering
/// supplies only the exact scanned target offset for each scheduled OptIR row, so this stage
/// never scans or allocates scratch proportional to expanded target capacity.
pub(crate) struct GpuTargetFunctionTable {
    programs: [StepProgramOperation; 2],
    semantic_capacity: u32,
    function_capacity: u32,
    _params: LaniusBuffer<FunctionParams>,
    _count: LaniusBuffer<u32>,
    _rows: LaniusBuffer<TargetLirFunction>,
}

impl GpuTargetFunctionTable {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new(
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        allocations: &CompilerGraphAllocations,
        resources: &ResourceMap<'_>,
        semantic_capacity: u32,
        target_capacity: u32,
        function_capacity: u32,
    ) -> Result<Self> {
        let semantic_capacity = semantic_capacity.max(1);
        let target_capacity = target_capacity.max(1);
        let function_capacity = function_capacity.max(1);
        let resource = |name: &str| {
            graph
                .resource_id(name)
                .with_context(|| format!("target function graph is missing {name}"))
        };
        let count = workspace
            .alias(graph, resource("lir.target.function_count")?, 1)
            .map_err(anyhow::Error::msg)?;
        let rows = workspace
            .alias(
                graph,
                resource("lir.target.functions")?,
                function_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let params = uniform_from_val(
            device,
            "lir.target.functions.params",
            &FunctionParams {
                semantic_capacity,
                target_capacity,
                function_capacity,
                reserved: 0,
            },
        );
        let sync = workspace
            .alias(
                graph,
                resource("step_program_sync")?,
                STEP_PROGRAM_SYNC_WORDS * LOWERING_PROGRAM_SLOTS,
            )
            .map_err(anyhow::Error::msg)?;
        let mut resources = resources.clone();
        resources.buffer("gParams", &params);
        let pass = kernels.kernel("codegen/lir/functions/build_target_function_ranges");
        let variant = |groups| {
            StepProgramOperation::new(
                device,
                &(graph, allocations),
                &resources,
                "lir.target.build_function_ranges",
                pass,
                &sync,
                TARGET_FUNCTION_PROGRAM_SLOT,
                groups,
                0,
            )
        };
        let [small, large] = step_program_group_counts();
        Ok(Self {
            programs: [variant(small)?, variant(large)?],
            semantic_capacity,
            function_capacity,
            _params: params,
            _count: count,
            _rows: rows,
        })
    }

    #[cfg(test)]
    pub(crate) fn output(&self) -> GpuTargetFunctionView<'_> {
        GpuTargetFunctionView {
            count: &self._count,
            rows: &self._rows,
        }
    }

    pub(crate) fn record(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        job: Option<LoweringCapacities>,
    ) -> Result<()> {
        // The semantic-to-target function index is cleared over its full allocation.
        let rows = job.map_or(self.semantic_capacity, |job| job.semantic_instructions)
            .max(self.function_capacity);
        self.programs[step_program_group_variant(u64::from(rows))].record(encoder)
    }
}
