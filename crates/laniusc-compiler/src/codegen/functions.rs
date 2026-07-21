//! Shared compaction of a scheduled target instruction stream into functions.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::{
    lowering::{bound, make_group, record_direct},
    lowering_ir::TargetLirFunction,
    scan::{GpuResidentExclusiveScan, GraphScanContract},
};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    compiler_graph::{
        BoundGraphResource,
        CompilerGraph,
        CompilerGraphAllocations,
        CompilerGraphWorkspace,
    },
    passes_core::{PassData, make_pass_data_from_shader_key},
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct FunctionParams {
    target_capacity: u32,
    function_capacity: u32,
    reserved0: u32,
    reserved1: u32,
}

#[derive(Clone, Copy)]
pub(crate) struct GpuTargetFunctionView<'a> {
    pub count: &'a LaniusBuffer<u32>,
    pub rows: &'a LaniusBuffer<TargetLirFunction>,
    pub index_by_semantic: &'a LaniusBuffer<u32>,
}

/// A target-independent function table over already scheduled instructions.
/// All storage and bind groups are resident; recording only dispatches work.
pub(crate) struct GpuTargetFunctionTable {
    target_capacity: u32,
    function_capacity: u32,
    mark_pass: PassData,
    scatter_pass: PassData,
    finalize_pass: PassData,
    mark_group: wgpu::BindGroup,
    scatter_group: wgpu::BindGroup,
    finalize_group: wgpu::BindGroup,
    scan: GpuResidentExclusiveScan,
    _params: LaniusBuffer<FunctionParams>,
    _flags: LaniusBuffer<u32>,
    _prefix: LaniusBuffer<u32>,
    _starts: LaniusBuffer<u32>,
    _compact_ids: LaniusBuffer<u32>,
    count: LaniusBuffer<u32>,
    rows: LaniusBuffer<TargetLirFunction>,
    index_by_semantic: LaniusBuffer<u32>,
}

impl GpuTargetFunctionTable {
    pub(crate) fn new(
        device: &wgpu::Device,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        allocations: &CompilerGraphAllocations,
        target_capacity: u32,
        function_capacity: u32,
        target_total: &LaniusBuffer<u32>,
        scheduled_function_ids: &LaniusBuffer<u32>,
    ) -> Result<Self> {
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
        let flags = alias_u32("lir.target.function_flags", target_capacity)?;
        let prefix = alias_u32("lir.target.function_prefix", target_capacity)?;
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
        let mark_pass = load(
            device,
            "lir.target.functions.mark",
            "codegen/lir/functions/mark",
        )?;
        let scatter_pass = load(
            device,
            "lir.target.functions.scatter_starts",
            "codegen/lir/functions/scatter_starts",
        )?;
        let finalize_pass = load(
            device,
            "lir.target.functions.finalize",
            "codegen/lir/functions/finalize",
        )?;
        let params = uniform_from_val(
            device,
            "lir.target.functions.params",
            &FunctionParams {
                target_capacity,
                function_capacity,
                reserved0: 0,
                reserved1: 0,
            },
        );
        let mark_group = make_group(
            device,
            &mark_pass,
            "lir.target.functions.mark.bind_group",
            &[
                ("gParams", params.as_entire_binding()),
                ("target_lir_total", target_total.as_entire_binding()),
                (
                    "scheduled_function_id",
                    scheduled_function_ids.as_entire_binding(),
                ),
                ("function_start_flag", flags.as_entire_binding()),
                (
                    "function_index_by_semantic",
                    index_by_semantic.as_entire_binding(),
                ),
            ],
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
                count: target_total_resource(graph)?,
                input: "lir.target.function_flags",
                local: "lir.target.function_scan_local",
                block_sum: "lir.target.function_scan_block_sum",
                block_prefix: "lir.target.function_scan_block_prefix",
                hierarchy: "lir.target.function_scan_hierarchy",
                output: "lir.target.function_prefix",
                total: "lir.target.function_count",
            },
            target_capacity,
            target_total,
            &flags,
            &prefix,
            &count,
        )?;
        let scatter_group = make_group(
            device,
            &scatter_pass,
            "lir.target.functions.scatter_starts.bind_group",
            &[
                ("gParams", params.as_entire_binding()),
                ("target_lir_total", target_total.as_entire_binding()),
                (
                    "scheduled_function_id",
                    scheduled_function_ids.as_entire_binding(),
                ),
                ("function_start_flag", flags.as_entire_binding()),
                ("function_prefix", prefix.as_entire_binding()),
                ("function_start", starts.as_entire_binding()),
                ("compact_function_id", compact_ids.as_entire_binding()),
            ],
        )?;
        let finalize_group = make_group(
            device,
            &finalize_pass,
            "lir.target.functions.finalize.bind_group",
            &[
                ("gParams", params.as_entire_binding()),
                ("target_lir_total", target_total.as_entire_binding()),
                ("function_count", count.as_entire_binding()),
                ("function_start", starts.as_entire_binding()),
                ("compact_function_id", compact_ids.as_entire_binding()),
                ("target_function", rows.as_entire_binding()),
                (
                    "function_index_by_semantic",
                    index_by_semantic.as_entire_binding(),
                ),
            ],
        )?;
        validate(
            graph,
            allocations,
            target_total,
            scheduled_function_ids,
            &flags,
            &prefix,
            &starts,
            &compact_ids,
            &count,
            &rows,
            &index_by_semantic,
        )?;
        Ok(Self {
            target_capacity,
            function_capacity,
            mark_pass,
            scatter_pass,
            finalize_pass,
            mark_group,
            scatter_group,
            finalize_group,
            scan,
            _params: params,
            _flags: flags,
            _prefix: prefix,
            _starts: starts,
            _compact_ids: compact_ids,
            count,
            rows,
            index_by_semantic,
        })
    }

    pub(crate) fn output(&self) -> GpuTargetFunctionView<'_> {
        GpuTargetFunctionView {
            count: &self.count,
            rows: &self.rows,
            index_by_semantic: &self.index_by_semantic,
        }
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        record_direct(
            encoder,
            &self.mark_pass,
            &self.mark_group,
            self.target_capacity,
        )?;
        self.scan.record(encoder)?;
        record_direct(
            encoder,
            &self.scatter_pass,
            &self.scatter_group,
            self.target_capacity,
        )?;
        record_direct(
            encoder,
            &self.finalize_pass,
            &self.finalize_group,
            self.function_capacity,
        )
    }
}

fn target_total_resource(graph: &CompilerGraph) -> Result<&'static str> {
    if graph.resource_id("lir.x86.total").is_some() {
        Ok("lir.x86.total")
    } else if graph.resource_id("lir.wasm.total").is_some() {
        Ok("lir.wasm.total")
    } else {
        anyhow::bail!("target function graph has no target total")
    }
}

fn load(device: &wgpu::Device, label: &str, shader: &str) -> Result<PassData> {
    make_pass_data_from_shader_key(device, label, "main", shader)
}

#[allow(clippy::too_many_arguments)]
fn validate(
    graph: &CompilerGraph,
    allocations: &CompilerGraphAllocations,
    total: &LaniusBuffer<u32>,
    function_ids: &LaniusBuffer<u32>,
    flags: &LaniusBuffer<u32>,
    prefix: &LaniusBuffer<u32>,
    starts: &LaniusBuffer<u32>,
    compact_ids: &LaniusBuffer<u32>,
    count: &LaniusBuffer<u32>,
    rows: &LaniusBuffer<TargetLirFunction>,
    index_by_semantic: &LaniusBuffer<u32>,
) -> Result<()> {
    let resource = |name: &str| graph.resource_id(name).unwrap();
    let total_name = target_total_resource(graph)?;
    let run = |pass: &str, bindings: Vec<BoundGraphResource>| {
        allocations
            .validate_pass_bindings(graph, graph.pass_id(pass).unwrap(), &bindings)
            .map_err(anyhow::Error::msg)
    };
    run(
        "lir.target.functions.mark",
        vec![
            bound("target_lir_total", resource(total_name), total)?,
            bound(
                "scheduled_function_id",
                resource("lir.target.scheduled_function_ids"),
                function_ids,
            )?,
            bound(
                "function_start_flag",
                resource("lir.target.function_flags"),
                flags,
            )?,
            bound(
                "function_index_by_semantic",
                resource("lir.target.function_index_by_semantic"),
                index_by_semantic,
            )?,
        ],
    )?;
    run(
        "lir.target.functions.scatter_starts",
        vec![
            bound("target_lir_total", resource(total_name), total)?,
            bound(
                "scheduled_function_id",
                resource("lir.target.scheduled_function_ids"),
                function_ids,
            )?,
            bound(
                "function_start_flag",
                resource("lir.target.function_flags"),
                flags,
            )?,
            bound(
                "function_prefix",
                resource("lir.target.function_prefix"),
                prefix,
            )?,
            bound(
                "function_start",
                resource("lir.target.function_starts"),
                starts,
            )?,
            bound(
                "compact_function_id",
                resource("lir.target.compact_function_ids"),
                compact_ids,
            )?,
        ],
    )?;
    run(
        "lir.target.functions.finalize",
        vec![
            bound("target_lir_total", resource(total_name), total)?,
            bound(
                "function_count",
                resource("lir.target.function_count"),
                count,
            )?,
            bound(
                "function_start",
                resource("lir.target.function_starts"),
                starts,
            )?,
            bound(
                "compact_function_id",
                resource("lir.target.compact_function_ids"),
                compact_ids,
            )?,
            bound("target_function", resource("lir.target.functions"), rows)?,
            bound(
                "function_index_by_semantic",
                resource("lir.target.function_index_by_semantic"),
                index_by_semantic,
            )?,
        ],
    )
}
