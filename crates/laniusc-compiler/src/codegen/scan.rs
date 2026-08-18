//! Resident graph-backed hierarchical exclusive scan.

use anyhow::{Context, Result};

use super::lowering::{ScanHierarchyParams, ScanParams};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    compiler_graph::{CompilerGraph, CompilerGraphAllocations, CompilerGraphWorkspace},
    kernels::KernelRegistry,
    operations::ComputeOperation,
    resource_registry::ResourceMap,
    scan::hierarchical_scan_levels,
};

#[derive(Clone, Copy)]
pub(crate) struct GraphScanContract {
    pub local_pass: &'static str,
    pub up_pass: &'static str,
    pub down_pass: &'static str,
    pub apply_pass: &'static str,
    pub count: &'static str,
    pub input: &'static str,
    pub local: &'static str,
    pub block_sum: &'static str,
    pub block_prefix: &'static str,
    pub hierarchy: &'static str,
    pub output: &'static str,
    pub total: &'static str,
}

/// A complete counted exclusive scan expressed as compiler-graph operations.
/// All pipelines, uniforms, bind groups, and allocation checks are materialized
/// once; recording only emits the already-bound operation sequence.
pub(crate) struct GpuResidentExclusiveScan {
    local: ComputeOperation,
    hierarchy_up: Vec<ComputeOperation>,
    hierarchy_down: Vec<ComputeOperation>,
    apply: ComputeOperation,
    _params: LaniusBuffer<ScanParams>,
    _hierarchy_params: Vec<LaniusBuffer<ScanHierarchyParams>>,
    _local: LaniusBuffer<u32>,
    _block_sum: LaniusBuffer<u32>,
    _block_prefix: LaniusBuffer<u32>,
    _hierarchy: LaniusBuffer<u32>,
}

impl GpuResidentExclusiveScan {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new(
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        allocations: &CompilerGraphAllocations,
        contract: GraphScanContract,
        capacity: u32,
        count: &LaniusBuffer<u32>,
        input: &LaniusBuffer<u32>,
        output: &LaniusBuffer<u32>,
        total: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        let capacity = capacity.max(1);
        let blocks = capacity.div_ceil(256);
        let alias = |name: &str, rows: u32| -> Result<LaniusBuffer<u32>> {
            workspace
                .alias(
                    graph,
                    graph
                        .resource_id(name)
                        .with_context(|| format!("scan graph is missing {name}"))?,
                    rows.max(1) as usize,
                )
                .map_err(anyhow::Error::msg)
        };
        let local = alias(contract.local, capacity)?;
        let block_sum = alias(contract.block_sum, blocks)?;
        let block_prefix = alias(contract.block_prefix, blocks)?;
        let hierarchy = alias(contract.hierarchy, blocks)?;
        let params = uniform_from_val(
            device,
            "lir.scan.params",
            &ScanParams {
                n_items: capacity,
                n_blocks: blocks,
                scan_step: 0,
            },
        );
        let levels = hierarchical_scan_levels(blocks);
        let hierarchy_params = levels
            .iter()
            .enumerate()
            .map(|(index, level)| {
                let parent = levels.get(index + 1);
                uniform_from_val(
                    device,
                    &format!("lir.scan.hierarchy.{index}"),
                    &ScanHierarchyParams {
                        n_items: capacity,
                        n_blocks: blocks,
                        level_divisor: level.divisor,
                        level_offset: level.offset,
                        parent_divisor: parent.map_or(0, |parent| parent.divisor),
                        parent_offset: parent.map_or(0, |parent| parent.offset),
                    },
                )
            })
            .collect::<Vec<_>>();

        let mut resources = ResourceMap::new();
        resources.graph_buffer(graph, contract.count, count)?;
        resources.graph_buffer(graph, contract.input, input)?;
        resources.graph_buffer(graph, contract.local, &local)?;
        resources.graph_buffer(graph, contract.block_sum, &block_sum)?;
        resources.graph_buffer(graph, contract.block_prefix, &block_prefix)?;
        resources.graph_buffer(graph, contract.hierarchy, &hierarchy)?;
        resources.graph_buffer(graph, contract.output, output)?;
        resources.graph_buffer(graph, contract.total, total)?;
        resources.buffer("gScan", &params);

        let context = (graph, allocations);
        let local_operation = ComputeOperation::direct(
            device,
            &context,
            &resources,
            contract.local_pass,
            kernels.kernel("scan/counted/00_local"),
            capacity,
        )?;
        let hierarchy_up = hierarchy_params
            .iter()
            .zip(&levels)
            .map(|(params, level)| {
                let mut resources = resources.clone();
                resources.buffer("gHierarchy", params);
                ComputeOperation::direct(
                    device,
                    &context,
                    &resources,
                    contract.up_pass,
                    kernels.kernel("scan/counted/01_hierarchy_up"),
                    level.count,
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let hierarchy_down = hierarchy_params
            .iter()
            .zip(&levels)
            .take(levels.len().saturating_sub(1))
            .map(|(params, level)| {
                let mut resources = resources.clone();
                resources.buffer("gHierarchy", params);
                ComputeOperation::direct(
                    device,
                    &context,
                    &resources,
                    contract.down_pass,
                    kernels.kernel("scan/counted/02_hierarchy_down"),
                    level.count,
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let apply_operation = ComputeOperation::direct(
            device,
            &context,
            &resources,
            contract.apply_pass,
            kernels.kernel("scan/counted/02_apply"),
            capacity,
        )?;

        Ok(Self {
            local: local_operation,
            hierarchy_up,
            hierarchy_down,
            apply: apply_operation,
            _params: params,
            _hierarchy_params: hierarchy_params,
            _local: local,
            _block_sum: block_sum,
            _block_prefix: block_prefix,
            _hierarchy: hierarchy,
        })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.local.record(encoder)?;
        for operation in &self.hierarchy_up {
            operation.record(encoder)?;
        }
        for operation in self.hierarchy_down.iter().rev() {
            operation.record(encoder)?;
        }
        self.apply.record(encoder)
    }
}
