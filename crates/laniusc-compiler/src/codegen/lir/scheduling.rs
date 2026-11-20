//! Stable GPU scheduling for semantic lowering records.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::lowering_ir::{
    LOWERING_PROGRAM_SLOTS, SCHEDULE_PROGRAM_SLOT, TargetScheduleKey, TargetScheduleRadixLayout,
};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    compiler_graph::{CompilerGraph, CompilerGraphAllocations, CompilerGraphWorkspace},
    kernels::KernelRegistry,
    operations::{
        STEP_PROGRAM_MAX_GROUPS, STEP_PROGRAM_SYNC_WORDS, StepProgramOperation,
        step_program_group_counts, step_program_group_variant,
    },
    resource_registry::ResourceMap,
};

#[derive(ShaderType)]
struct ScheduleParams {
    capacity: u32,
    digits: u32,
}

pub(crate) struct GpuStableScheduleSorter {
    programs: [StepProgramOperation; 2],
    capacity: u32,
    order: LaniusBuffer<u32>,
}

impl GpuStableScheduleSorter {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new_semantic(
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        allocations: &CompilerGraphAllocations,
        capacity: u32,
        radix_layout: TargetScheduleRadixLayout,
        total: &LaniusBuffer<u32>,
        keys: &LaniusBuffer<TargetScheduleKey>,
        order: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        let alias = |name: &str, words: usize| -> Result<LaniusBuffer<u32>> {
            workspace
                .alias(
                    graph,
                    graph
                        .resource_id(name)
                        .with_context(|| format!("lowering graph is missing {name}"))?,
                    words,
                )
                .map_err(anyhow::Error::msg)
        };
        let temporary = alias("lir.semantic.schedule_order_tmp", capacity as usize)?;
        let histogram = alias(
            "lir.semantic.schedule_histogram",
            STEP_PROGRAM_MAX_GROUPS as usize * 256,
        )?;
        let bucket_total = alias("lir.semantic.schedule_bucket_total", 256)?;
        let sync = alias("step_program_sync", STEP_PROGRAM_SYNC_WORDS * LOWERING_PROGRAM_SLOTS)?;
        let params = uniform_from_val(
            device,
            "lir.semantic.sort_schedule.params",
            &ScheduleParams { capacity, digits: radix_layout.steps },
        );
        let mut resources = ResourceMap::new();
        resources.graph_buffer(graph, "lir.semantic.total", total)?;
        resources.graph_buffer(graph, "lir.semantic.schedule", keys)?;
        resources.graph_buffer(graph, "lir.semantic.schedule_order", order)?;
        resources.graph_buffer(graph, "lir.semantic.schedule_order_tmp", &temporary)?;
        resources.graph_buffer(graph, "lir.semantic.schedule_histogram", &histogram)?;
        resources.graph_buffer(graph, "lir.semantic.schedule_bucket_total", &bucket_total)?;
        resources.graph_buffer(graph, "step_program_sync", &sync)?;
        resources.buffer("gParams", &params);
        let pass = kernels.kernel("codegen/lir/scheduling/sort_semantic_schedule");
        let variant = |groups| {
            StepProgramOperation::new(
                device,
                &(graph, allocations),
                &resources,
                "lir.semantic.sort_schedule",
                pass,
                &sync,
                SCHEDULE_PROGRAM_SLOT,
                groups,
                0,
            )
        };
        let [small, large] = step_program_group_counts();
        Ok(Self {
            programs: [variant(small)?, variant(large)?],
            capacity,
            order: order.clone(),
        })
    }

    pub(crate) fn output_order(&self) -> &LaniusBuffer<u32> {
        &self.order
    }

    #[cfg(test)]
    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.record_for_job(encoder, None)
    }

    pub(crate) fn record_for_job(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        job_rows: Option<u32>,
    ) -> Result<()> {
        let rows = job_rows.unwrap_or(self.capacity);
        self.programs[step_program_group_variant(u64::from(rows))].record(encoder)
    }
}
