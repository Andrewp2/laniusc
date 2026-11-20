//! Shared GPU planning for the semantic interval behind each target page.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::lowering_ir::{
    LOWERING_PROGRAM_SLOTS, LoweringCapacities, TARGET_LIR_PAGE_ROWS, TARGET_PAGE_PROGRAM_SLOT,
    TargetSemanticPage,
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
struct TargetPagePlanParams {
    semantic_capacity: u32,
    target_capacity: u32,
    page_count: u32,
    page_rows: u32,
}

pub(crate) struct GpuTargetPagePlanner {
    programs: [StepProgramOperation; 2],
    semantic_capacity: u32,
    _params: LaniusBuffer<TargetPagePlanParams>,
    _pages: LaniusBuffer<TargetSemanticPage>,
}

impl GpuTargetPagePlanner {
    pub fn new(
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        allocations: &CompilerGraphAllocations,
        resources: &ResourceMap<'_>,
        capacities: LoweringCapacities,
    ) -> Result<Self> {
        let page_count = capacities
            .target_instructions
            .max(1)
            .div_ceil(TARGET_LIR_PAGE_ROWS);
        let pages = workspace
            .alias(
                graph,
                graph
                    .resource_id("lir.target.semantic_pages")
                    .context("lowering graph has no target semantic-page plan")?,
                page_count as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let params = uniform_from_val(
            device,
            "lir.target.semantic_page_plan.params",
            &TargetPagePlanParams {
                semantic_capacity: capacities.semantic_instructions.max(1),
                target_capacity: capacities.target_instructions.max(1),
                page_count,
                page_rows: TARGET_LIR_PAGE_ROWS,
            },
        );
        let sync = workspace
            .alias(
                graph,
                graph.resource_id("step_program_sync").context("lowering graph has no program sync")?,
                STEP_PROGRAM_SYNC_WORDS * LOWERING_PROGRAM_SLOTS,
            )
            .map_err(anyhow::Error::msg)?;
        let mut resources = resources.clone();
        resources.buffer("gParams", &params);
        let pass = kernels.kernel("codegen/lir/functions/plan_target_semantic_pages");
        let variant = |groups| {
            StepProgramOperation::new(
                device,
                &(graph, allocations),
                &resources,
                "lir.target.semantic_page_plan",
                pass,
                &sync,
                TARGET_PAGE_PROGRAM_SLOT,
                groups,
                0,
            )
        };
        let [small, large] = step_program_group_counts();
        Ok(Self {
            programs: [variant(small)?, variant(large)?],
            semantic_capacity: capacities.semantic_instructions,
            _params: params,
            _pages: pages,
        })
    }

    pub fn record(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        job: Option<LoweringCapacities>,
    ) -> Result<()> {
        let rows = job.map_or(self.semantic_capacity, |job| job.semantic_instructions);
        self.programs[step_program_group_variant(u64::from(rows))].record(encoder)
    }
}
