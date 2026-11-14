//! Resident graph-backed counted exclusive scan.

use anyhow::{Context, Result};

use super::lowering::{ScanHierarchyParams, ScanParams};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    compiler_graph::{CompilerGraph, CompilerGraphAllocations, CompilerGraphWorkspace},
    kernels::KernelRegistry,
    operations::ComputeOperation,
    resource_registry::ResourceMap,
};

#[derive(Clone, Copy)]
pub(crate) struct GraphScanContract {
    pub local_pass: &'static str,
    pub block_prefix_pass: &'static str,
    pub apply_pass: &'static str,
    pub count: &'static str,
    pub input: &'static str,
    pub local: &'static str,
    pub block_sum: &'static str,
    pub block_prefix: &'static str,
    pub output: &'static str,
    pub total: &'static str,
}

/// A complete counted exclusive scan expressed as compiler-graph operations:
/// local block scans, one workgroup that scans the block sums, and the apply.
/// All pipelines, uniforms, bind groups, and allocation checks are materialized
/// once; recording only emits the already-bound operation sequence.
pub(crate) struct GpuResidentExclusiveScan {
    local: ComputeOperation,
    block_prefix: ComputeOperation,
    apply: ComputeOperation,
    _params: LaniusBuffer<ScanParams>,
    _block_prefix_params: LaniusBuffer<ScanHierarchyParams>,
    _local: LaniusBuffer<u32>,
    _block_sum: LaniusBuffer<u32>,
    _block_prefix: LaniusBuffer<u32>,
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
        let params = uniform_from_val(
            device,
            "lir.scan.params",
            &ScanParams {
                n_items: capacity,
                n_blocks: blocks,
                scan_step: 0,
            },
        );
        let block_prefix_params = uniform_from_val(
            device,
            "lir.scan.block_prefix",
            &ScanHierarchyParams {
                n_items: capacity,
                n_blocks: blocks,
                level_divisor: 1,
                level_offset: 0,
                parent_divisor: 0,
                parent_offset: 0,
            },
        );

        let mut resources = ResourceMap::new();
        resources.graph_buffer(graph, contract.count, count)?;
        resources.graph_buffer(graph, contract.input, input)?;
        resources.graph_buffer(graph, contract.local, &local)?;
        resources.graph_buffer(graph, contract.block_sum, &block_sum)?;
        resources.graph_buffer(graph, contract.block_prefix, &block_prefix)?;
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
        let block_prefix_operation = {
            let mut resources = resources.clone();
            resources.buffer("gHierarchy", &block_prefix_params);
            ComputeOperation::direct(
                device,
                &context,
                &resources,
                contract.block_prefix_pass,
                kernels.kernel("scan/counted/04_block_prefix"),
                1,
            )?
        };
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
            block_prefix: block_prefix_operation,
            apply: apply_operation,
            _params: params,
            _block_prefix_params: block_prefix_params,
            _local: local,
            _block_sum: block_sum,
            _block_prefix: block_prefix,
        })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.local.record(encoder)?;
        self.block_prefix.record(encoder)?;
        self.apply.record(encoder)
    }
}
