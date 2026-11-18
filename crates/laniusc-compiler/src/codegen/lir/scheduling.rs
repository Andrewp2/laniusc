//! Stable GPU scheduling for semantic lowering records.
//!
//! Semantic lowering creates one `TargetScheduleKey` per semantic instruction.
//! This component owns one compiler-graph radix-sort schedule whose pipelines,
//! uniforms and bind groups are all materialized before record. A digit
//! records three dispatches: per-block bucket counts, one workgroup per bucket
//! scanning its column of block counts, and the stable scatter, which adds
//! the smaller buckets' totals.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::lowering_ir::{TargetScheduleKey, TargetScheduleRadixLayout};
use crate::gpu::{
    buffers::{DynamicUniformBuffer, LaniusBuffer, dynamic_uniforms_from_vals, uniform_from_val},
    compiler_graph::{CompilerGraph, CompilerGraphAllocations, CompilerGraphWorkspace},
    kernels::KernelRegistry,
    operations::ComputeOperation,
    resource_registry::ResourceMap,
    timer::GpuTimer,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct ScheduleParams {
    target_capacity: u32,
    max_blocks: u32,
    key_step: u32,
    reserved: u32,
}

struct ScheduleStep {
    key_step: u32,
    histogram: ComputeOperation,
    buckets: ComputeOperation,
    scatter: ComputeOperation,
}

/// One stable schedule sort. Recording is only a sequence of graph-operation
/// calls; no pipelines, bind groups, buffers, uniforms, or offset vectors are
/// created on a warm job.
pub(crate) struct GpuStableScheduleSorter {
    steps: Vec<ScheduleStep>,
    target_capacity: u32,
    _radix_params: DynamicUniformBuffer<ScheduleParams>,
    _bucket_params: LaniusBuffer<ScheduleParams>,
    order: LaniusBuffer<u32>,
    _order_tmp: LaniusBuffer<u32>,
    _histogram: LaniusBuffer<u32>,
    _global_prefix: LaniusBuffer<u32>,
    _bucket_total: LaniusBuffer<u32>,
}

impl GpuStableScheduleSorter {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new_semantic(
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        allocations: &CompilerGraphAllocations,
        semantic_capacity: u32,
        radix_layout: TargetScheduleRadixLayout,
        total: &LaniusBuffer<u32>,
        keys: &LaniusBuffer<TargetScheduleKey>,
        order: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        let target_capacity = semantic_capacity.max(1);
        let alias = |name: &str, count: u32| -> Result<LaniusBuffer<u32>> {
            workspace
                .alias(
                    graph,
                    graph
                        .resource_id(name)
                        .with_context(|| format!("lowering graph is missing {name}"))?,
                    count.max(1) as usize,
                )
                .map_err(anyhow::Error::msg)
        };
        let max_blocks = target_capacity.div_ceil(256);
        let slot_capacity = max_blocks.saturating_mul(256);
        let order_tmp = alias("lir.semantic.schedule_order_tmp", target_capacity)?;
        let histogram = alias("lir.semantic.schedule_histogram", slot_capacity)?;
        let global_prefix = alias("lir.semantic.schedule_global_prefix", slot_capacity)?;
        let bucket_total = alias("lir.semantic.schedule_bucket_total", 256)?;

        let radix_values = (0..radix_layout.steps)
            .map(|key_step| ScheduleParams {
                target_capacity,
                max_blocks,
                key_step,
                reserved: radix_layout.packed_bits,
            })
            .collect::<Vec<_>>();
        let radix_params =
            dynamic_uniforms_from_vals(device, "lir.target.schedule.radix.params", &radix_values);
        let mut resources = ResourceMap::new();
        resources.graph_buffer(graph, "lir.semantic.total", total)?;
        resources.graph_buffer(graph, "lir.semantic.schedule", keys)?;
        resources.graph_buffer(graph, "lir.semantic.schedule_order", order)?;
        resources.graph_buffer(graph, "lir.semantic.schedule_order_tmp", &order_tmp)?;
        resources.graph_buffer(graph, "lir.semantic.schedule_histogram", &histogram)?;
        resources.graph_buffer(graph, "lir.semantic.schedule_global_prefix", &global_prefix)?;
        resources.graph_buffer(graph, "lir.semantic.schedule_bucket_total", &bucket_total)?;
        let bucket_params = uniform_from_val(
            device,
            "lir.target.schedule.bucket.params",
            &ScheduleParams {
                target_capacity,
                max_blocks,
                key_step: 0,
                reserved: radix_layout.packed_bits,
            },
        );
        resources.add("gParams", radix_params.binding());
        resources.add("gBuckets", bucket_params.as_entire_binding());
        let context = (graph, allocations);
        let initial_direction = usize::from(radix_layout.steps % 2 != 0);
        let histogram_names = [
            "lir.semantic.schedule.histogram.even",
            "lir.semantic.schedule.histogram.odd",
        ];
        let bucket_names = [
            "lir.semantic.schedule.scan.buckets.even",
            "lir.semantic.schedule.scan.buckets.odd",
        ];
        let scatter_names = [
            "lir.semantic.schedule.scatter.even",
            "lir.semantic.schedule.scatter.odd",
        ];
        let histogram_kernel = kernels.dynamic_uniform_kernel(
            "codegen/lir/scheduling/count_target_schedule_buckets",
            "gParams",
        );
        let bucket_kernel = kernels.kernel("codegen/lir/scheduling/scan_target_schedule_buckets");
        let scatter_kernel = kernels.dynamic_uniform_kernel(
            "codegen/lir/scheduling/scatter_target_schedule_rows",
            "gParams",
        );
        let steps = (0..radix_layout.steps as usize)
            .map(|step| {
                let direction = (step + initial_direction) % 2;
                let offsets = vec![radix_params.dynamic_offset(step)];
                Ok(ScheduleStep {
                    key_step: step as u32,
                    histogram: ComputeOperation::direct_with_offsets(
                        device,
                        &context,
                        &resources,
                        histogram_names[direction],
                        histogram_kernel,
                        target_capacity,
                        offsets.clone(),
                    )?,
                    // One workgroup per bucket.
                    buckets: ComputeOperation::direct(
                        device,
                        &context,
                        &resources,
                        bucket_names[direction],
                        bucket_kernel,
                        256 * 256,
                    )?,
                    scatter: ComputeOperation::direct_with_offsets(
                        device,
                        &context,
                        &resources,
                        scatter_names[direction],
                        scatter_kernel,
                        target_capacity,
                        offsets,
                    )?,
                })
            })
            .collect::<Result<Vec<_>>>()?;

        Ok(Self {
            steps,
            target_capacity,
            _radix_params: radix_params,
            _bucket_params: bucket_params,
            order: order.clone(),
            _order_tmp: order_tmp,
            _histogram: histogram,
            _global_prefix: global_prefix,
            _bucket_total: bucket_total,
        })
    }

    pub(crate) fn output_order(&self) -> &LaniusBuffer<u32> {
        &self.order
    }

    #[cfg(test)]
    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.record_timed(encoder, None, None)
    }

    /// Records the sort. With `job_rows`, the histogram and scatter grids
    /// cover that many semantic rows instead of the built capacity: both
    /// kernels take their active blocks from the GPU-written row total, so a
    /// grid that covers the job's rows covers every active block.
    pub(crate) fn record_timed(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        mut timer: Option<&mut GpuTimer>,
        job_rows: Option<u32>,
    ) -> Result<()> {
        let rows = job_rows.map(|rows| rows.max(1).min(self.target_capacity));
        let mut stamp = |label: String, encoder: &mut wgpu::CommandEncoder| {
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, label);
            }
        };
        for step in &self.steps {
            let digit = step.key_step;
            match rows {
                Some(rows) => step.histogram.record_elements(encoder, rows)?,
                None => step.histogram.record(encoder)?,
            }
            stamp(
                format!("lowering.semantic.schedule.digit.{digit}.histogram.done"),
                encoder,
            );
            step.buckets.record(encoder)?;
            stamp(
                format!("lowering.semantic.schedule.digit.{digit}.scan.done"),
                encoder,
            );
            match rows {
                Some(rows) => step.scatter.record_elements(encoder, rows)?,
                None => step.scatter.record(encoder)?,
            }
            stamp(
                format!("lowering.semantic.schedule.digit.{digit}.scatter.done"),
                encoder,
            );
        }
        Ok(())
    }
}
