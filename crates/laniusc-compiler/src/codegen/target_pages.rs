//! Shared GPU planning for the semantic interval behind each target page.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::lowering_ir::{LoweringCapacities, TARGET_LIR_PAGE_ROWS, TargetSemanticPage};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    compiler_graph::{CompilerGraph, CompilerGraphAllocations, CompilerGraphWorkspace},
    kernels::KernelRegistry,
    operations::ComputeOperation,
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
    operation: ComputeOperation,
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
        let pass = kernels
            .kernel("codegen/lir/semantic/target_page_plan")
            .clone();
        let operation = ComputeOperation::direct_with_uniform(
            device,
            &(graph, allocations),
            resources,
            "lir.target.semantic_page_plan",
            &pass,
            &params,
            page_count,
        )?;
        Ok(Self {
            operation,
            _params: params,
            _pages: pages,
        })
    }

    pub fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.operation.record(encoder)
    }
}
