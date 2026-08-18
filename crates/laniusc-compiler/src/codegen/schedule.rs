//! Stable GPU scheduling for semantic lowering records.
//!
//! Semantic lowering creates one `TargetScheduleKey` per semantic instruction.
//! This component owns one compiler-graph radix-sort schedule whose pipelines,
//! uniforms, bind groups, and counted scans are all materialized before record.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::{
    lowering_ir::{TargetScheduleKey, TargetScheduleRadixLayout},
    scan::{GpuResidentExclusiveScan, GraphScanContract},
};
use crate::gpu::{
    buffers::{DynamicUniformBuffer, LaniusBuffer, dynamic_uniforms_from_vals},
    compiler_graph::{CompilerGraph, CompilerGraphAllocations, CompilerGraphWorkspace},
    kernels::KernelRegistry,
    operations::ComputeOperation,
    resource_registry::ResourceMap,
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
    direction: usize,
    histogram: ComputeOperation,
    scatter: ComputeOperation,
}

/// One stable schedule sort. Recording is only a sequence of graph-operation
/// calls; no pipelines, bind groups, buffers, uniforms, or offset vectors are
/// created on a warm job.
pub(crate) struct GpuStableScheduleSorter {
    steps: Vec<ScheduleStep>,
    scans: [GpuResidentExclusiveScan; 2],
    _radix_params: DynamicUniformBuffer<ScheduleParams>,
    order: LaniusBuffer<u32>,
    _order_tmp: LaniusBuffer<u32>,
    _slot_count: LaniusBuffer<u32>,
    _histogram: LaniusBuffer<u32>,
    _global_prefix: LaniusBuffer<u32>,
    _scan_total: LaniusBuffer<u32>,
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
        let slot_count = alias("lir.semantic.schedule_slot_count", 1)?;
        let histogram = alias("lir.semantic.schedule_histogram", slot_capacity)?;
        let global_prefix = alias("lir.semantic.schedule_global_prefix", slot_capacity)?;
        let scan_total = alias("lir.semantic.schedule_scan_total", 1)?;

        let scan_contract = |direction: &str| GraphScanContract {
            local_pass: if direction == "even" {
                "lir.semantic.schedule.scan.local.even"
            } else {
                "lir.semantic.schedule.scan.local.odd"
            },
            up_pass: if direction == "even" {
                "lir.semantic.schedule.scan.hierarchy_up.even"
            } else {
                "lir.semantic.schedule.scan.hierarchy_up.odd"
            },
            down_pass: if direction == "even" {
                "lir.semantic.schedule.scan.hierarchy_down.even"
            } else {
                "lir.semantic.schedule.scan.hierarchy_down.odd"
            },
            apply_pass: if direction == "even" {
                "lir.semantic.schedule.scan.apply.even"
            } else {
                "lir.semantic.schedule.scan.apply.odd"
            },
            count: "lir.semantic.schedule_slot_count",
            input: "lir.semantic.schedule_histogram",
            local: "lir.semantic.schedule_scan_local",
            block_sum: "lir.semantic.schedule_scan_block_sum",
            block_prefix: "lir.semantic.schedule_scan_block_prefix",
            hierarchy: "lir.semantic.schedule_scan_hierarchy",
            output: "lir.semantic.schedule_global_prefix",
            total: "lir.semantic.schedule_scan_total",
        };
        let scans = [
            GpuResidentExclusiveScan::new(
                device,
                kernels,
                graph,
                workspace,
                allocations,
                scan_contract("even"),
                slot_capacity,
                &slot_count,
                &histogram,
                &global_prefix,
                &scan_total,
            )?,
            GpuResidentExclusiveScan::new(
                device,
                kernels,
                graph,
                workspace,
                allocations,
                scan_contract("odd"),
                slot_capacity,
                &slot_count,
                &histogram,
                &global_prefix,
                &scan_total,
            )?,
        ];

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
        resources.graph_buffer(graph, "lir.semantic.schedule_slot_count", &slot_count)?;
        resources.graph_buffer(graph, "lir.semantic.schedule_histogram", &histogram)?;
        resources.graph_buffer(graph, "lir.semantic.schedule_global_prefix", &global_prefix)?;
        resources.add("gParams", radix_params.binding());
        let context = (graph, allocations);
        let initial_direction = usize::from(radix_layout.steps % 2 != 0);
        let histogram_names = [
            "lir.semantic.schedule.histogram.even",
            "lir.semantic.schedule.histogram.odd",
        ];
        let scatter_names = [
            "lir.semantic.schedule.scatter.even",
            "lir.semantic.schedule.scatter.odd",
        ];
        let histogram_kernel =
            kernels.dynamic_uniform_kernel("codegen/lir/schedule/histogram", "gParams");
        let scatter_kernel =
            kernels.dynamic_uniform_kernel("codegen/lir/schedule/scatter", "gParams");
        let steps = (0..radix_layout.steps as usize)
            .map(|step| {
                let direction = (step + initial_direction) % 2;
                let offsets = vec![radix_params.dynamic_offset(step)];
                Ok(ScheduleStep {
                    direction,
                    histogram: ComputeOperation::direct_with_offsets(
                        device,
                        &context,
                        &resources,
                        histogram_names[direction],
                        histogram_kernel,
                        target_capacity,
                        offsets.clone(),
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
            scans,
            _radix_params: radix_params,
            order: order.clone(),
            _order_tmp: order_tmp,
            _slot_count: slot_count,
            _histogram: histogram,
            _global_prefix: global_prefix,
            _scan_total: scan_total,
        })
    }

    pub(crate) fn output_order(&self) -> &LaniusBuffer<u32> {
        &self.order
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        for step in &self.steps {
            step.histogram.record(encoder)?;
            self.scans[step.direction].record(encoder)?;
            step.scatter.record(encoder)?;
        }
        Ok(())
    }
}
