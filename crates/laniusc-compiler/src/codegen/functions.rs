//! Shared compaction of scheduled semantic rows into target function ranges.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::{
    lowering_ir::TargetLirFunction,
    scan::{GpuResidentExclusiveScan, GraphScanContract},
};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    compiler_graph::{CompilerGraph, CompilerGraphAllocations, CompilerGraphWorkspace},
    operations::ComputeOperation,
    passes_core::{PassData, make_pass_data_from_shader_key},
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
/// Function ownership is semantic metadata. Target lowering supplies only the
/// exact scanned target offset for each scheduled semantic row, so this stage
/// never scans or allocates scratch proportional to expanded target capacity.
pub(crate) struct GpuTargetFunctionTable {
    mark: ComputeOperation,
    scatter: ComputeOperation,
    finalize: ComputeOperation,
    scan: GpuResidentExclusiveScan,
    _params: LaniusBuffer<FunctionParams>,
    _flags: LaniusBuffer<u32>,
    _prefix: LaniusBuffer<u32>,
    _starts: LaniusBuffer<u32>,
    _compact_ids: LaniusBuffer<u32>,
    _count: LaniusBuffer<u32>,
    _rows: LaniusBuffer<TargetLirFunction>,
    _index_by_semantic: LaniusBuffer<u32>,
}

impl GpuTargetFunctionTable {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new(
        device: &wgpu::Device,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        allocations: &CompilerGraphAllocations,
        resources: &ResourceMap<'_>,
        semantic_capacity: u32,
        target_capacity: u32,
        function_capacity: u32,
        semantic_total: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        let semantic_capacity = semantic_capacity.max(1);
        let target_capacity = target_capacity.max(1);
        let function_capacity = function_capacity.max(1);
        let resource = |name: &str| {
            graph
                .resource_id(name)
                .with_context(|| format!("target function graph is missing {name}"))
        };
        let alias_u32 = |name: &str, rows: u32| -> Result<LaniusBuffer<u32>> {
            workspace
                .alias(graph, resource(name)?, rows.max(1) as usize)
                .map_err(anyhow::Error::msg)
        };
        let flags = alias_u32("lir.target.function_flags", semantic_capacity)?;
        let prefix = alias_u32("lir.target.function_prefix", semantic_capacity)?;
        let starts = alias_u32("lir.target.function_starts", function_capacity)?;
        let compact_ids = alias_u32("lir.target.compact_function_ids", function_capacity)?;
        let count = alias_u32("lir.target.function_count", 1)?;
        let rows = workspace
            .alias(
                graph,
                resource("lir.target.functions")?,
                function_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let index_by_semantic =
            alias_u32("lir.target.function_index_by_semantic", function_capacity)?;
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
        let context = (graph, allocations);
        let mark = ComputeOperation::direct_with_uniform(
            device,
            &context,
            resources,
            "lir.target.functions.mark",
            &load(
                device,
                "lir.target.functions.mark",
                "codegen/lir/functions/mark",
            )?,
            &params,
            semantic_capacity.max(function_capacity),
        )?;
        let scan = GpuResidentExclusiveScan::new(
            device,
            graph,
            workspace,
            allocations,
            GraphScanContract {
                local_pass: "lir.target.function_scan.local",
                up_pass: "lir.target.function_scan.hierarchy_up",
                down_pass: "lir.target.function_scan.hierarchy_down",
                apply_pass: "lir.target.function_scan.apply",
                count: "lir.semantic.total",
                input: "lir.target.function_flags",
                local: "lir.target.function_scan_local",
                block_sum: "lir.target.function_scan_block_sum",
                block_prefix: "lir.target.function_scan_block_prefix",
                hierarchy: "lir.target.function_scan_hierarchy",
                output: "lir.target.function_prefix",
                total: "lir.target.function_count",
            },
            semantic_capacity,
            semantic_total,
            &flags,
            &prefix,
            &count,
        )?;
        let scatter = ComputeOperation::direct_with_uniform(
            device,
            &context,
            resources,
            "lir.target.functions.scatter_starts",
            &load(
                device,
                "lir.target.functions.scatter_starts",
                "codegen/lir/functions/scatter_starts",
            )?,
            &params,
            semantic_capacity,
        )?;
        let finalize = ComputeOperation::direct_with_uniform(
            device,
            &context,
            resources,
            "lir.target.functions.finalize",
            &load(
                device,
                "lir.target.functions.finalize",
                "codegen/lir/functions/finalize",
            )?,
            &params,
            function_capacity,
        )?;

        Ok(Self {
            mark,
            scatter,
            finalize,
            scan,
            _params: params,
            _flags: flags,
            _prefix: prefix,
            _starts: starts,
            _compact_ids: compact_ids,
            _count: count,
            _rows: rows,
            _index_by_semantic: index_by_semantic,
        })
    }

    #[cfg(test)]
    pub(crate) fn output(&self) -> GpuTargetFunctionView<'_> {
        GpuTargetFunctionView {
            count: &self._count,
            rows: &self._rows,
        }
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.mark.record(encoder)?;
        self.scan.record(encoder)?;
        self.scatter.record(encoder)?;
        self.finalize.record(encoder)
    }
}

fn load(device: &wgpu::Device, label: &str, shader: &str) -> Result<PassData> {
    make_pass_data_from_shader_key(device, label, "main", shader)
}
