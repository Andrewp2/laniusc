//! Resident graph-backed counted exclusive scan.

use anyhow::{Context, Result};

use super::lowering::ScanParams;
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
    pub apply_pass: &'static str,
    pub count: &'static str,
    pub input: &'static str,
    pub local: &'static str,
    pub block_sum: &'static str,
    pub output: &'static str,
    pub total: &'static str,
}

/// A complete counted exclusive scan expressed as compiler-graph operations:
/// local block scans, then the apply, whose workgroups each sum the earlier
/// blocks' sums for their carry (scan/blocks/block_carry.slang).
/// All pipelines, uniforms, bind groups, and allocation checks are materialized
/// once; recording only emits the already-bound operation sequence.
pub(crate) struct GpuResidentExclusiveScan {
    local: ComputeOperation,
    apply: ComputeOperation,
    _params: LaniusBuffer<ScanParams>,
    _local: LaniusBuffer<u32>,
    _block_sum: LaniusBuffer<u32>,
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
        let params = uniform_from_val(
            device,
            "lir.scan.params",
            &ScanParams {
                n_items: capacity,
                n_blocks: blocks,
                scan_step: 0,
            },
        );

        let mut resources = ResourceMap::new();
        resources.graph_buffer(graph, contract.count, count)?;
        resources.graph_buffer(graph, contract.input, input)?;
        resources.graph_buffer(graph, contract.local, &local)?;
        resources.graph_buffer(graph, contract.block_sum, &block_sum)?;
        resources.graph_buffer(graph, contract.output, output)?;
        resources.graph_buffer(graph, contract.total, total)?;
        resources.buffer("gScan", &params);

        let context = (graph, allocations);
        let local_operation = ComputeOperation::direct(
            device,
            &context,
            &resources,
            contract.local_pass,
            kernels.kernel("scan/words/scan_counted_word_blocks"),
            capacity,
        )?;
        let apply_operation = ComputeOperation::direct(
            device,
            &context,
            &resources,
            contract.apply_pass,
            kernels.kernel("scan/words/apply_counted_word_carries"),
            capacity,
        )?;

        Ok(Self {
            local: local_operation,
            apply: apply_operation,
            _params: params,
            _local: local,
            _block_sum: block_sum,
        })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.local.record(encoder)?;
        self.apply.record(encoder)
    }
}
