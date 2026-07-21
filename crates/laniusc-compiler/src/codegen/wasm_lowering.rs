//! Resident target-specific lowering from semantic LIR to scheduled Wasm LIR.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::{
    functions::{GpuTargetFunctionTable, GpuTargetFunctionView},
    lowering::{GpuSemanticLirView, bound, make_group, record_direct, target_lowering_allocations},
    lowering_ir::{LoweringCapacities, LoweringStatus, WasmLirFunction, WasmLirInstruction},
    scan::{GpuResidentExclusiveScan, GraphScanContract},
    wasm_module::GpuWasmModuleStage,
};
use crate::gpu::{
    buffers::{LaniusBuffer, readback_bytes, uniform_from_val},
    compiler_graph::{BoundGraphResource, CompilerGraph, CompilerGraphWorkspace},
    passes_core::{PassData, make_pass_data_from_shader_key, map_readback_blocking},
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmCountParams {
    semantic_capacity: u32,
    reserved0: u32,
    reserved1: u32,
    reserved2: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmScatterParams {
    semantic_capacity: u32,
    target_capacity: u32,
    reserved0: u32,
    reserved1: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmScheduleParams {
    target_capacity: u32,
    semantic_capacity: u32,
    reserved0: u32,
    reserved1: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmByteCountParams {
    target_capacity: u32,
    reserved0: u32,
    reserved1: u32,
    reserved2: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmEmitParams {
    target_capacity: u32,
    artifact_capacity: u32,
    reserved0: u32,
    reserved1: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmAbiParams {
    function_capacity: u32,
    param_capacity: u32,
    local_capacity: u32,
    n_tokens: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmResolveParams {
    target_capacity: u32,
    n_tokens: u32,
    semantic_capacity: u32,
    reserved1: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmAttachBodyParams {
    function_capacity: u32,
    target_capacity: u32,
    reserved0: u32,
    reserved1: u32,
}

pub(crate) struct GpuWasmLirView<'a> {
    pub total: &'a LaniusBuffer<u32>,
    pub instructions: &'a LaniusBuffer<WasmLirInstruction>,
    pub functions: GpuTargetFunctionView<'a>,
    pub abi_functions: &'a LaniusBuffer<WasmLirFunction>,
    pub abi_function_count: &'a LaniusBuffer<u32>,
}

pub(crate) struct GpuWasmArtifactView<'a> {
    pub length: &'a LaniusBuffer<u32>,
    /// Packed little-endian byte storage; `length` is the logical byte count.
    pub words: &'a LaniusBuffer<u32>,
}

/// The complete second lowering level for Wasm through stable scheduling.
/// Every object needed by `record` is resident and bound during construction.
pub(crate) struct GpuWasmLirStage {
    semantic_capacity: u32,
    count_pass: PassData,
    scatter_pass: PassData,
    validate_pass: PassData,
    function_ids_pass: PassData,
    byte_count_pass: PassData,
    emit_pass: PassData,
    param_width_pass: PassData,
    local_width_pass: PassData,
    abi_functions_pass: PassData,
    declaration_indices_pass: PassData,
    resolve_indices_pass: PassData,
    attach_bodies_pass: PassData,
    count_group: wgpu::BindGroup,
    scatter_group: wgpu::BindGroup,
    validate_group: wgpu::BindGroup,
    function_ids_group: wgpu::BindGroup,
    byte_count_group: wgpu::BindGroup,
    emit_group: wgpu::BindGroup,
    param_width_group: wgpu::BindGroup,
    local_width_group: wgpu::BindGroup,
    abi_functions_group: wgpu::BindGroup,
    declaration_indices_group: wgpu::BindGroup,
    resolve_indices_group: wgpu::BindGroup,
    attach_bodies_group: wgpu::BindGroup,
    count_scan: GpuResidentExclusiveScan,
    functions: GpuTargetFunctionTable,
    byte_scan: GpuResidentExclusiveScan,
    param_scan: GpuResidentExclusiveScan,
    local_scan: GpuResidentExclusiveScan,
    _count_params: LaniusBuffer<WasmCountParams>,
    _scatter_params: LaniusBuffer<WasmScatterParams>,
    _schedule_params: LaniusBuffer<WasmScheduleParams>,
    _byte_count_params: LaniusBuffer<WasmByteCountParams>,
    _emit_params: LaniusBuffer<WasmEmitParams>,
    _abi_params: LaniusBuffer<WasmAbiParams>,
    _resolve_params: LaniusBuffer<WasmResolveParams>,
    _attach_body_params: LaniusBuffer<WasmAttachBodyParams>,
    _counts: LaniusBuffer<u32>,
    _offsets: LaniusBuffer<u32>,
    total: LaniusBuffer<u32>,
    instructions: LaniusBuffer<WasmLirInstruction>,
    scheduled_function_ids: LaniusBuffer<u32>,
    byte_lengths: LaniusBuffer<u32>,
    byte_offsets: LaniusBuffer<u32>,
    artifact_length: LaniusBuffer<u32>,
    artifact_words: LaniusBuffer<u32>,
    _param_widths: LaniusBuffer<u32>,
    param_prefix: LaniusBuffer<u32>,
    param_value_total: LaniusBuffer<u32>,
    _local_widths: LaniusBuffer<u32>,
    local_prefix: LaniusBuffer<u32>,
    local_value_total: LaniusBuffer<u32>,
    abi_functions: LaniusBuffer<WasmLirFunction>,
    abi_function_count: LaniusBuffer<u32>,
    local_index_by_token: LaniusBuffer<u32>,
    module: GpuWasmModuleStage,
    artifact_length_readback: LaniusBuffer<u8>,
    artifact_readback: LaniusBuffer<u8>,
}

impl GpuWasmLirStage {
    pub(crate) fn new(
        device: &wgpu::Device,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        capacities: LoweringCapacities,
        semantic: GpuSemanticLirView<'_>,
    ) -> Result<Self> {
        let allocations = target_lowering_allocations(graph, workspace, semantic)?;
        let resource = |name: &str| {
            graph
                .resource_id(name)
                .with_context(|| format!("Wasm lowering graph is missing {name}"))
        };
        let alias_u32 = |name: &str, rows: u32| -> Result<LaniusBuffer<u32>> {
            workspace
                .alias(graph, resource(name)?, rows.max(1) as usize)
                .map_err(anyhow::Error::msg)
        };
        let semantic_capacity = capacities.semantic_instructions.max(1);
        let target_capacity = capacities.target_instructions.max(1);
        let semantic_order = semantic
            .execution_order
            .context("Wasm lowering requires GPU-scheduled semantic LIR")?;
        let counts = alias_u32("lir.wasm.count_by_semantic", semantic_capacity)?;
        let offsets = alias_u32("lir.wasm.offset_by_semantic", semantic_capacity)?;
        let semantic_to_target =
            alias_u32("lir.target.semantic_to_target_start", semantic_capacity)?;
        let total = alias_u32("lir.wasm.total", 1)?;
        let instructions = workspace
            .alias(
                graph,
                resource("lir.wasm.instructions")?,
                target_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let scheduled_function_ids =
            alias_u32("lir.target.scheduled_function_ids", target_capacity)?;
        let byte_lengths = alias_u32("lir.wasm.byte_lengths", target_capacity)?;
        let byte_offsets = alias_u32("lir.wasm.byte_offsets", target_capacity)?;
        let artifact_length = alias_u32("lir.wasm.body_length", 1)?;
        let artifact_capacity = capacities.artifact_bytes.max(1);
        let artifact_words = alias_u32("lir.wasm.body_bytes", artifact_capacity.div_ceil(4))?;
        let param_widths = alias_u32("lir.wasm.param_widths", capacities.parameters)?;
        let param_prefix = alias_u32("lir.wasm.param_prefix", capacities.parameters)?;
        let param_value_total = alias_u32("lir.wasm.param_value_total", 1)?;
        let local_widths = alias_u32("lir.wasm.local_widths", capacities.hir_nodes)?;
        let local_prefix = alias_u32("lir.wasm.local_prefix", capacities.hir_nodes)?;
        let local_value_total = alias_u32("lir.wasm.local_value_total", 1)?;
        let abi_functions = workspace
            .alias(
                graph,
                resource("lir.wasm.functions")?,
                capacities.hir_nodes.max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let value_capacity = capacities
            .tokens
            .saturating_add(capacities.hir_nodes)
            .max(1);
        let local_index_by_token = alias_u32("lir.wasm.local_index_by_token", value_capacity)?;

        let count_pass = load(device, "lir.wasm.count", "codegen/lir/wasm/count")?;
        let scatter_pass = load(device, "lir.wasm.scatter", "codegen/lir/wasm/scatter")?;
        let validate_pass = load(device, "lir.wasm.validate", "codegen/lir/wasm/validate")?;
        let function_ids_pass = load(
            device,
            "lir.wasm.schedule.function_ids",
            "codegen/lir/wasm/materialize_function_ids",
        )?;
        let byte_count_pass = load(device, "lir.wasm.byte_count", "codegen/lir/wasm/byte_count")?;
        let emit_pass = load(device, "lir.wasm.emit", "codegen/lir/wasm/emit")?;
        let param_width_pass = load(
            device,
            "lir.wasm.abi.param_widths",
            "codegen/lir/wasm/param_widths",
        )?;
        let local_width_pass = load(
            device,
            "lir.wasm.abi.local_widths",
            "codegen/lir/wasm/local_widths",
        )?;
        let abi_functions_pass = load(
            device,
            "lir.wasm.abi.functions",
            "codegen/lir/wasm/functions",
        )?;
        let declaration_indices_pass = load(
            device,
            "lir.wasm.abi.declaration_indices",
            "codegen/lir/wasm/declaration_indices",
        )?;
        let resolve_indices_pass = load(
            device,
            "lir.wasm.resolve_indices",
            "codegen/lir/wasm/resolve_indices",
        )?;
        let attach_bodies_pass = load(
            device,
            "lir.wasm.abi.attach_bodies",
            "codegen/lir/wasm/attach_bodies",
        )?;
        let count_params = uniform_from_val(
            device,
            "lir.wasm.count.params",
            &WasmCountParams {
                semantic_capacity,
                reserved0: 0,
                reserved1: 0,
                reserved2: 0,
            },
        );
        let scatter_params = uniform_from_val(
            device,
            "lir.wasm.scatter.params",
            &WasmScatterParams {
                semantic_capacity,
                target_capacity,
                reserved0: 0,
                reserved1: 0,
            },
        );
        let schedule_params = uniform_from_val(
            device,
            "lir.wasm.schedule.params",
            &WasmScheduleParams {
                target_capacity,
                semantic_capacity,
                reserved0: 0,
                reserved1: 0,
            },
        );
        let byte_count_params = uniform_from_val(
            device,
            "lir.wasm.byte_count.params",
            &WasmByteCountParams {
                target_capacity,
                reserved0: 0,
                reserved1: 0,
                reserved2: 0,
            },
        );
        let emit_params = uniform_from_val(
            device,
            "lir.wasm.emit.params",
            &WasmEmitParams {
                target_capacity,
                artifact_capacity,
                reserved0: 0,
                reserved1: 0,
            },
        );
        let abi_params = uniform_from_val(
            device,
            "lir.wasm.abi.params",
            &WasmAbiParams {
                function_capacity: capacities.hir_nodes.max(1),
                param_capacity: capacities.parameters.max(1),
                local_capacity: capacities.hir_nodes.max(1),
                n_tokens: value_capacity,
            },
        );
        let resolve_params = uniform_from_val(
            device,
            "lir.wasm.resolve.params",
            &WasmResolveParams {
                target_capacity,
                n_tokens: value_capacity,
                semantic_capacity,
                reserved1: 0,
            },
        );
        let attach_body_params = uniform_from_val(
            device,
            "lir.wasm.attach_bodies.params",
            &WasmAttachBodyParams {
                function_capacity: capacities.hir_nodes.max(1),
                target_capacity,
                reserved0: 0,
                reserved1: 0,
            },
        );
        let count_group = make_group(
            device,
            &count_pass,
            "lir.wasm.count.bind_group",
            &[
                ("gParams", count_params.as_entire_binding()),
                ("semantic_lir_total", semantic.count.as_entire_binding()),
                ("semantic_lir_core", semantic.core.as_entire_binding()),
                (
                    "semantic_lir_operands",
                    semantic.operands.as_entire_binding(),
                ),
                (
                    "semantic_schedule_order",
                    semantic_order.as_entire_binding(),
                ),
                ("target_lir_count", counts.as_entire_binding()),
            ],
        )?;
        let count_scan = GpuResidentExclusiveScan::new(
            device,
            graph,
            workspace,
            &allocations,
            GraphScanContract {
                local_pass: "lir.target.count_scan.local",
                up_pass: "lir.target.count_scan.hierarchy_up",
                down_pass: "lir.target.count_scan.hierarchy_down",
                apply_pass: "lir.target.count_scan.apply",
                count: "lir.semantic.total",
                input: "lir.wasm.count_by_semantic",
                local: "lir.target.count_scan_local",
                block_sum: "lir.target.count_scan_block_sum",
                block_prefix: "lir.target.count_scan_block_prefix",
                hierarchy: "lir.target.count_scan_hierarchy",
                output: "lir.wasm.offset_by_semantic",
                total: "lir.wasm.total",
            },
            semantic_capacity,
            semantic.count,
            &counts,
            &offsets,
            &total,
        )?;
        let scatter_group = make_group(
            device,
            &scatter_pass,
            "lir.wasm.scatter.bind_group",
            &[
                ("gParams", scatter_params.as_entire_binding()),
                ("semantic_lir_total", semantic.count.as_entire_binding()),
                ("semantic_lir_core", semantic.core.as_entire_binding()),
                (
                    "semantic_lir_operands",
                    semantic.operands.as_entire_binding(),
                ),
                (
                    "semantic_lir_schedule",
                    semantic.schedule.as_entire_binding(),
                ),
                (
                    "semantic_schedule_order",
                    semantic_order.as_entire_binding(),
                ),
                (
                    "semantic_lir_aggregate_elements",
                    semantic.aggregate_elements.as_entire_binding(),
                ),
                ("target_lir_offset", offsets.as_entire_binding()),
                ("target_lir_total", total.as_entire_binding()),
                (
                    "semantic_to_target_start",
                    semantic_to_target.as_entire_binding(),
                ),
                ("target_lir_core", instructions.as_entire_binding()),
            ],
        )?;
        let param_width_group = make_group(
            device,
            &param_width_pass,
            "lir.wasm.abi.param_widths.bind_group",
            &[
                ("gParams", abi_params.as_entire_binding()),
                (
                    "semantic_lir_param_total",
                    semantic.param_count.as_entire_binding(),
                ),
                ("semantic_lir_params", semantic.params.as_entire_binding()),
                ("wasm_param_width", param_widths.as_entire_binding()),
            ],
        )?;
        let param_scan = GpuResidentExclusiveScan::new(
            device,
            graph,
            workspace,
            &allocations,
            GraphScanContract {
                local_pass: "lir.wasm.abi.param_scan.local",
                up_pass: "lir.wasm.abi.param_scan.hierarchy_up",
                down_pass: "lir.wasm.abi.param_scan.hierarchy_down",
                apply_pass: "lir.wasm.abi.param_scan.apply",
                count: "lir.semantic.param_total",
                input: "lir.wasm.param_widths",
                local: "lir.wasm.param_scan_local",
                block_sum: "lir.wasm.param_scan_block_sum",
                block_prefix: "lir.wasm.param_scan_block_prefix",
                hierarchy: "lir.wasm.param_scan_hierarchy",
                output: "lir.wasm.param_prefix",
                total: "lir.wasm.param_value_total",
            },
            capacities.parameters.max(1),
            semantic.param_count,
            &param_widths,
            &param_prefix,
            &param_value_total,
        )?;
        let local_width_group = make_group(
            device,
            &local_width_pass,
            "lir.wasm.abi.local_widths.bind_group",
            &[
                ("gParams", abi_params.as_entire_binding()),
                (
                    "semantic_lir_local_total",
                    semantic.local_count.as_entire_binding(),
                ),
                ("semantic_lir_locals", semantic.locals.as_entire_binding()),
                ("wasm_local_width", local_widths.as_entire_binding()),
            ],
        )?;
        let local_scan = GpuResidentExclusiveScan::new(
            device,
            graph,
            workspace,
            &allocations,
            GraphScanContract {
                local_pass: "lir.wasm.abi.local_scan.local",
                up_pass: "lir.wasm.abi.local_scan.hierarchy_up",
                down_pass: "lir.wasm.abi.local_scan.hierarchy_down",
                apply_pass: "lir.wasm.abi.local_scan.apply",
                count: "lir.semantic.local_total",
                input: "lir.wasm.local_widths",
                local: "lir.wasm.local_scan_local",
                block_sum: "lir.wasm.local_scan_block_sum",
                block_prefix: "lir.wasm.local_scan_block_prefix",
                hierarchy: "lir.wasm.local_scan_hierarchy",
                output: "lir.wasm.local_prefix",
                total: "lir.wasm.local_value_total",
            },
            capacities.hir_nodes.max(1),
            semantic.local_count,
            &local_widths,
            &local_prefix,
            &local_value_total,
        )?;
        let abi_functions_group = make_group(
            device,
            &abi_functions_pass,
            "lir.wasm.abi.functions.bind_group",
            &[
                ("gParams", abi_params.as_entire_binding()),
                (
                    "semantic_lir_function_total",
                    semantic.function_count.as_entire_binding(),
                ),
                (
                    "semantic_lir_functions",
                    semantic.functions.as_entire_binding(),
                ),
                (
                    "semantic_lir_param_total",
                    semantic.param_count.as_entire_binding(),
                ),
                ("wasm_param_prefix", param_prefix.as_entire_binding()),
                (
                    "wasm_param_value_total",
                    param_value_total.as_entire_binding(),
                ),
                (
                    "semantic_lir_local_total",
                    semantic.local_count.as_entire_binding(),
                ),
                ("wasm_local_prefix", local_prefix.as_entire_binding()),
                (
                    "wasm_local_value_total",
                    local_value_total.as_entire_binding(),
                ),
                ("wasm_lir_functions", abi_functions.as_entire_binding()),
            ],
        )?;
        let declaration_indices_group = make_group(
            device,
            &declaration_indices_pass,
            "lir.wasm.abi.declaration_indices.bind_group",
            &[
                ("gParams", abi_params.as_entire_binding()),
                (
                    "semantic_lir_param_total",
                    semantic.param_count.as_entire_binding(),
                ),
                ("semantic_lir_params", semantic.params.as_entire_binding()),
                ("wasm_param_prefix", param_prefix.as_entire_binding()),
                (
                    "semantic_lir_local_total",
                    semantic.local_count.as_entire_binding(),
                ),
                ("semantic_lir_locals", semantic.locals.as_entire_binding()),
                ("wasm_local_prefix", local_prefix.as_entire_binding()),
                ("wasm_lir_functions", abi_functions.as_entire_binding()),
                (
                    "wasm_local_index_by_decl_token",
                    local_index_by_token.as_entire_binding(),
                ),
            ],
        )?;
        let resolve_indices_group = make_group(
            device,
            &resolve_indices_pass,
            "lir.wasm.resolve_indices.bind_group",
            &[
                ("gParams", resolve_params.as_entire_binding()),
                ("target_lir_total", total.as_entire_binding()),
                (
                    "wasm_local_index_by_decl_token",
                    local_index_by_token.as_entire_binding(),
                ),
                (
                    "semantic_lir_schedule",
                    semantic.schedule.as_entire_binding(),
                ),
                ("wasm_lir_functions", abi_functions.as_entire_binding()),
                ("target_lir_core", instructions.as_entire_binding()),
            ],
        )?;
        validate_abi(
            graph,
            &allocations,
            semantic,
            &param_widths,
            &param_prefix,
            &param_value_total,
            &local_widths,
            &local_prefix,
            &local_value_total,
            &abi_functions,
            &local_index_by_token,
            &total,
            &instructions,
        )?;
        let validate_group = make_group(
            device,
            &validate_pass,
            "lir.wasm.validate.bind_group",
            &[
                ("gParams", scatter_params.as_entire_binding()),
                ("target_lir_total", total.as_entire_binding()),
                ("target_lir_core", instructions.as_entire_binding()),
                ("semantic_lir_core", semantic.core.as_entire_binding()),
                ("lowering_status", semantic.status.as_entire_binding()),
            ],
        )?;
        let byte_count_group = make_group(
            device,
            &byte_count_pass,
            "lir.wasm.byte_count.bind_group",
            &[
                ("gParams", byte_count_params.as_entire_binding()),
                ("target_lir_total", total.as_entire_binding()),
                ("target_lir_core", instructions.as_entire_binding()),
                ("target_byte_length", byte_lengths.as_entire_binding()),
            ],
        )?;
        validate(
            graph,
            &allocations,
            semantic,
            &counts,
            &offsets,
            &semantic_to_target,
            &total,
            &instructions,
        )?;
        validate_target_status(
            graph,
            &allocations,
            semantic.status,
            semantic.core,
            &total,
            &instructions,
        )?;
        let function_ids_group = make_group(
            device,
            &function_ids_pass,
            "lir.wasm.schedule.function_ids.bind_group",
            &[
                ("gParams", schedule_params.as_entire_binding()),
                ("target_lir_total", total.as_entire_binding()),
                ("target_lir_core", instructions.as_entire_binding()),
                (
                    "semantic_lir_schedule",
                    semantic.schedule.as_entire_binding(),
                ),
                (
                    "scheduled_function_id",
                    scheduled_function_ids.as_entire_binding(),
                ),
            ],
        )?;
        validate_function_ids(
            graph,
            &allocations,
            semantic,
            &total,
            &instructions,
            &scheduled_function_ids,
        )?;
        let functions = GpuTargetFunctionTable::new(
            device,
            graph,
            workspace,
            &allocations,
            target_capacity,
            capacities.hir_nodes,
            &total,
            &scheduled_function_ids,
        )?;
        let byte_scan = GpuResidentExclusiveScan::new(
            device,
            graph,
            workspace,
            &allocations,
            GraphScanContract {
                local_pass: "lir.target.byte_scan.local",
                up_pass: "lir.target.byte_scan.hierarchy_up",
                down_pass: "lir.target.byte_scan.hierarchy_down",
                apply_pass: "lir.target.byte_scan.apply",
                count: "lir.wasm.total",
                input: "lir.wasm.byte_lengths",
                local: "lir.target.byte_scan_local",
                block_sum: "lir.target.byte_scan_block_sum",
                block_prefix: "lir.target.byte_scan_block_prefix",
                hierarchy: "lir.target.byte_scan_hierarchy",
                output: "lir.wasm.byte_offsets",
                total: "lir.wasm.body_length",
            },
            target_capacity,
            &total,
            &byte_lengths,
            &byte_offsets,
            &artifact_length,
        )?;
        let attach_bodies_group = make_group(
            device,
            &attach_bodies_pass,
            "lir.wasm.abi.attach_bodies.bind_group",
            &[
                ("gParams", attach_body_params.as_entire_binding()),
                (
                    "target_function_count",
                    functions.output().count.as_entire_binding(),
                ),
                (
                    "target_functions",
                    functions.output().rows.as_entire_binding(),
                ),
                ("target_byte_length", byte_lengths.as_entire_binding()),
                ("target_byte_offset", byte_offsets.as_entire_binding()),
                ("wasm_lir_functions", abi_functions.as_entire_binding()),
            ],
        )?;
        allocations
            .validate_pass_bindings(
                graph,
                graph.pass_id("lir.wasm.abi.attach_bodies").unwrap(),
                &[
                    bound(
                        "target_function_count",
                        resource("lir.target.function_count")?,
                        functions.output().count,
                    )?,
                    bound(
                        "target_functions",
                        resource("lir.target.functions")?,
                        functions.output().rows,
                    )?,
                    bound(
                        "target_byte_length",
                        resource("lir.wasm.byte_lengths")?,
                        &byte_lengths,
                    )?,
                    bound(
                        "target_byte_offset",
                        resource("lir.wasm.byte_offsets")?,
                        &byte_offsets,
                    )?,
                    bound(
                        "wasm_lir_functions",
                        resource("lir.wasm.functions")?,
                        &abi_functions,
                    )?,
                ],
            )
            .map_err(anyhow::Error::msg)?;
        let emit_group = make_group(
            device,
            &emit_pass,
            "lir.wasm.emit.bind_group",
            &[
                ("gParams", emit_params.as_entire_binding()),
                ("target_lir_total", total.as_entire_binding()),
                ("target_lir_core", instructions.as_entire_binding()),
                ("target_byte_length", byte_lengths.as_entire_binding()),
                ("target_byte_offset", byte_offsets.as_entire_binding()),
                ("artifact_length", artifact_length.as_entire_binding()),
                ("artifact_bytes", artifact_words.as_entire_binding()),
            ],
        )?;
        validate_bytes(
            graph,
            &allocations,
            &total,
            &instructions,
            &byte_lengths,
            &byte_offsets,
            &artifact_length,
            &artifact_words,
        )?;
        let module = GpuWasmModuleStage::new(
            device,
            graph,
            workspace,
            &allocations,
            capacities,
            semantic,
            &abi_functions,
            &artifact_words,
        )?;
        let artifact_readback_bytes = capacities.artifact_bytes.max(4).next_multiple_of(4);
        let artifact_length_readback =
            readback_bytes(device, "artifact.wasm.length.readback", 4, 4);
        let artifact_readback = readback_bytes(
            device,
            "artifact.wasm.bytes.readback",
            artifact_readback_bytes as usize,
            artifact_readback_bytes as usize,
        );
        Ok(Self {
            semantic_capacity,
            count_pass,
            scatter_pass,
            validate_pass,
            function_ids_pass,
            byte_count_pass,
            emit_pass,
            param_width_pass,
            local_width_pass,
            abi_functions_pass,
            declaration_indices_pass,
            resolve_indices_pass,
            attach_bodies_pass,
            count_group,
            scatter_group,
            validate_group,
            function_ids_group,
            byte_count_group,
            emit_group,
            param_width_group,
            local_width_group,
            abi_functions_group,
            declaration_indices_group,
            resolve_indices_group,
            attach_bodies_group,
            count_scan,
            functions,
            byte_scan,
            param_scan,
            local_scan,
            _count_params: count_params,
            _scatter_params: scatter_params,
            _schedule_params: schedule_params,
            _byte_count_params: byte_count_params,
            _emit_params: emit_params,
            _abi_params: abi_params,
            _resolve_params: resolve_params,
            _attach_body_params: attach_body_params,
            _counts: counts,
            _offsets: offsets,
            total,
            instructions,
            scheduled_function_ids,
            byte_lengths,
            byte_offsets,
            artifact_length,
            artifact_words,
            _param_widths: param_widths,
            param_prefix,
            param_value_total,
            _local_widths: local_widths,
            local_prefix,
            local_value_total,
            abi_functions,
            abi_function_count: semantic.function_count.clone(),
            local_index_by_token,
            module,
            artifact_length_readback,
            artifact_readback,
        })
    }

    pub(crate) fn output(&self) -> GpuWasmLirView<'_> {
        GpuWasmLirView {
            total: &self.total,
            instructions: &self.instructions,
            functions: self.functions.output(),
            abi_functions: &self.abi_functions,
            abi_function_count: &self.abi_function_count,
        }
    }

    pub(crate) fn artifact(&self) -> GpuWasmArtifactView<'_> {
        let module = self.module.output();
        GpuWasmArtifactView {
            length: module.length,
            words: module.words,
        }
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.record_lir(encoder)?;
        self.module.record(encoder)?;
        let artifact = self.module.output();
        encoder.copy_buffer_to_buffer(
            &artifact.length.buffer,
            0,
            &self.artifact_length_readback.buffer,
            0,
            4,
        );
        encoder.copy_buffer_to_buffer(
            &artifact.words.buffer,
            0,
            &self.artifact_readback.buffer,
            0,
            self.artifact_readback.byte_size as u64,
        );
        Ok(())
    }

    /// Maps the daemon-resident readback buffers after the command buffer has
    /// been submitted. Recording allocates nothing; the same staging storage
    /// is reused by every sequential daemon job.
    pub(crate) fn finish_artifact(&self, device: &wgpu::Device) -> Result<Vec<u8>> {
        let length_slice = self.artifact_length_readback.slice(..);
        map_readback_blocking(device, &length_slice, "Wasm artifact length readback")?;
        let mapped_length = length_slice.get_mapped_range();
        let length = u32::from_le_bytes(mapped_length[0..4].try_into().unwrap()) as usize;
        drop(mapped_length);
        self.artifact_length_readback.unmap();
        if length > self.artifact_readback.byte_size {
            anyhow::bail!(
                "GPU Wasm artifact requires {length} bytes but the daemon workspace provides {}",
                self.artifact_readback.byte_size,
            );
        }

        let artifact_slice = self.artifact_readback.slice(..);
        map_readback_blocking(device, &artifact_slice, "Wasm artifact byte readback")?;
        let mapped_artifact = artifact_slice.get_mapped_range();
        let bytes = mapped_artifact[..length].to_vec();
        drop(mapped_artifact);
        self.artifact_readback.unmap();
        Ok(bytes)
    }

    fn record_lir(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        record_direct(
            encoder,
            &self.count_pass,
            &self.count_group,
            self.semantic_capacity,
        )?;
        self.count_scan.record(encoder)?;
        record_direct(
            encoder,
            &self.scatter_pass,
            &self.scatter_group,
            self.instructions.count as u32,
        )?;
        record_direct(
            encoder,
            &self.param_width_pass,
            &self.param_width_group,
            self._param_widths.count as u32,
        )?;
        self.param_scan.record(encoder)?;
        record_direct(
            encoder,
            &self.local_width_pass,
            &self.local_width_group,
            self._local_widths.count as u32,
        )?;
        self.local_scan.record(encoder)?;
        record_direct(
            encoder,
            &self.abi_functions_pass,
            &self.abi_functions_group,
            self.abi_functions.count as u32,
        )?;
        record_direct(
            encoder,
            &self.declaration_indices_pass,
            &self.declaration_indices_group,
            self._param_widths.count.max(self._local_widths.count) as u32,
        )?;
        record_direct(
            encoder,
            &self.resolve_indices_pass,
            &self.resolve_indices_group,
            self.instructions.count as u32,
        )?;
        record_direct(
            encoder,
            &self.validate_pass,
            &self.validate_group,
            self.instructions.count as u32,
        )?;
        record_direct(
            encoder,
            &self.function_ids_pass,
            &self.function_ids_group,
            self.instructions.count as u32,
        )?;
        self.functions.record(encoder)?;
        record_direct(
            encoder,
            &self.byte_count_pass,
            &self.byte_count_group,
            self.instructions.count as u32,
        )?;
        self.byte_scan.record(encoder)?;
        record_direct(
            encoder,
            &self.attach_bodies_pass,
            &self.attach_bodies_group,
            self.abi_functions.count as u32,
        )?;
        record_direct(
            encoder,
            &self.emit_pass,
            &self.emit_group,
            self.instructions.count as u32,
        )
    }
}

#[allow(clippy::too_many_arguments)]
fn validate_abi(
    graph: &CompilerGraph,
    allocations: &crate::gpu::compiler_graph::CompilerGraphAllocations,
    semantic: GpuSemanticLirView<'_>,
    param_widths: &LaniusBuffer<u32>,
    param_prefix: &LaniusBuffer<u32>,
    param_value_total: &LaniusBuffer<u32>,
    local_widths: &LaniusBuffer<u32>,
    local_prefix: &LaniusBuffer<u32>,
    local_value_total: &LaniusBuffer<u32>,
    abi_functions: &LaniusBuffer<WasmLirFunction>,
    local_index_by_token: &LaniusBuffer<u32>,
    target_total: &LaniusBuffer<u32>,
    instructions: &LaniusBuffer<WasmLirInstruction>,
) -> Result<()> {
    let resource = |name: &str| graph.resource_id(name).unwrap();
    let run = |pass: &str, bindings: Vec<BoundGraphResource>| {
        allocations
            .validate_pass_bindings(graph, graph.pass_id(pass).unwrap(), &bindings)
            .map_err(anyhow::Error::msg)
    };
    run(
        "lir.wasm.abi.param_widths",
        vec![
            bound(
                "semantic_lir_param_total",
                resource("lir.semantic.param_total"),
                semantic.param_count,
            )?,
            bound(
                "semantic_lir_params",
                resource("lir.semantic.params"),
                semantic.params,
            )?,
            bound(
                "wasm_param_width",
                resource("lir.wasm.param_widths"),
                param_widths,
            )?,
        ],
    )?;
    run(
        "lir.wasm.abi.local_widths",
        vec![
            bound(
                "semantic_lir_local_total",
                resource("lir.semantic.local_total"),
                semantic.local_count,
            )?,
            bound(
                "semantic_lir_locals",
                resource("lir.semantic.locals"),
                semantic.locals,
            )?,
            bound(
                "wasm_local_width",
                resource("lir.wasm.local_widths"),
                local_widths,
            )?,
        ],
    )?;
    run(
        "lir.wasm.abi.functions",
        vec![
            bound(
                "semantic_lir_function_total",
                resource("lir.semantic.function_total"),
                semantic.function_count,
            )?,
            bound(
                "semantic_lir_functions",
                resource("lir.semantic.functions"),
                semantic.functions,
            )?,
            bound(
                "semantic_lir_param_total",
                resource("lir.semantic.param_total"),
                semantic.param_count,
            )?,
            bound(
                "wasm_param_prefix",
                resource("lir.wasm.param_prefix"),
                param_prefix,
            )?,
            bound(
                "wasm_param_value_total",
                resource("lir.wasm.param_value_total"),
                param_value_total,
            )?,
            bound(
                "semantic_lir_local_total",
                resource("lir.semantic.local_total"),
                semantic.local_count,
            )?,
            bound(
                "wasm_local_prefix",
                resource("lir.wasm.local_prefix"),
                local_prefix,
            )?,
            bound(
                "wasm_local_value_total",
                resource("lir.wasm.local_value_total"),
                local_value_total,
            )?,
            bound(
                "wasm_lir_functions",
                resource("lir.wasm.functions"),
                abi_functions,
            )?,
        ],
    )?;
    run(
        "lir.wasm.abi.declaration_indices",
        vec![
            bound(
                "semantic_lir_param_total",
                resource("lir.semantic.param_total"),
                semantic.param_count,
            )?,
            bound(
                "semantic_lir_params",
                resource("lir.semantic.params"),
                semantic.params,
            )?,
            bound(
                "wasm_param_prefix",
                resource("lir.wasm.param_prefix"),
                param_prefix,
            )?,
            bound(
                "semantic_lir_local_total",
                resource("lir.semantic.local_total"),
                semantic.local_count,
            )?,
            bound(
                "semantic_lir_locals",
                resource("lir.semantic.locals"),
                semantic.locals,
            )?,
            bound(
                "wasm_local_prefix",
                resource("lir.wasm.local_prefix"),
                local_prefix,
            )?,
            bound(
                "wasm_lir_functions",
                resource("lir.wasm.functions"),
                abi_functions,
            )?,
            bound(
                "wasm_local_index_by_decl_token",
                resource("lir.wasm.local_index_by_token"),
                local_index_by_token,
            )?,
        ],
    )?;
    run(
        "lir.wasm.resolve_indices",
        vec![
            bound("target_lir_total", resource("lir.wasm.total"), target_total)?,
            bound(
                "wasm_local_index_by_decl_token",
                resource("lir.wasm.local_index_by_token"),
                local_index_by_token,
            )?,
            bound(
                "semantic_lir_schedule",
                resource("lir.semantic.schedule"),
                semantic.schedule,
            )?,
            bound(
                "wasm_lir_functions",
                resource("lir.wasm.functions"),
                abi_functions,
            )?,
            bound(
                "target_lir_core",
                resource("lir.wasm.instructions"),
                instructions,
            )?,
        ],
    )
}

fn validate_function_ids(
    graph: &CompilerGraph,
    allocations: &crate::gpu::compiler_graph::CompilerGraphAllocations,
    semantic: GpuSemanticLirView<'_>,
    total: &LaniusBuffer<u32>,
    instructions: &LaniusBuffer<WasmLirInstruction>,
    function_ids: &LaniusBuffer<u32>,
) -> Result<()> {
    let resource = |name: &str| graph.resource_id(name).unwrap();
    allocations
        .validate_pass_bindings(
            graph,
            graph.pass_id("lir.wasm.schedule.function_ids").unwrap(),
            &[
                bound("target_lir_total", resource("lir.wasm.total"), total)?,
                bound(
                    "target_lir_core",
                    resource("lir.wasm.instructions"),
                    instructions,
                )?,
                bound(
                    "semantic_lir_schedule",
                    resource("lir.semantic.schedule"),
                    semantic.schedule,
                )?,
                bound(
                    "scheduled_function_id",
                    resource("lir.target.scheduled_function_ids"),
                    function_ids,
                )?,
            ],
        )
        .map_err(anyhow::Error::msg)
}

fn validate_target_status(
    graph: &CompilerGraph,
    allocations: &crate::gpu::compiler_graph::CompilerGraphAllocations,
    status: &LaniusBuffer<LoweringStatus>,
    semantic_core: &LaniusBuffer<super::lowering_ir::SemanticLirCore>,
    total: &LaniusBuffer<u32>,
    instructions: &LaniusBuffer<WasmLirInstruction>,
) -> Result<()> {
    let resource = |name: &str| graph.resource_id(name).unwrap();
    allocations
        .validate_pass_bindings(
            graph,
            graph.pass_id("lir.wasm.validate").unwrap(),
            &[
                bound("target_lir_total", resource("lir.wasm.total"), total)?,
                bound(
                    "target_lir_core",
                    resource("lir.wasm.instructions"),
                    instructions,
                )?,
                bound(
                    "semantic_lir_core",
                    resource("lir.semantic.core"),
                    semantic_core,
                )?,
                bound("lowering_status", resource("lowering.status"), status)?,
            ],
        )
        .map_err(anyhow::Error::msg)
}

#[allow(clippy::too_many_arguments)]
fn validate_bytes(
    graph: &CompilerGraph,
    allocations: &crate::gpu::compiler_graph::CompilerGraphAllocations,
    total: &LaniusBuffer<u32>,
    instructions: &LaniusBuffer<WasmLirInstruction>,
    lengths: &LaniusBuffer<u32>,
    offsets: &LaniusBuffer<u32>,
    artifact_length: &LaniusBuffer<u32>,
    artifact_words: &LaniusBuffer<u32>,
) -> Result<()> {
    let resource = |name: &str| graph.resource_id(name).unwrap();
    let run = |pass: &str, bindings: Vec<BoundGraphResource>| {
        allocations
            .validate_pass_bindings(graph, graph.pass_id(pass).unwrap(), &bindings)
            .map_err(anyhow::Error::msg)
    };
    run(
        "lir.wasm.byte_count",
        vec![
            bound("target_lir_total", resource("lir.wasm.total"), total)?,
            bound(
                "target_lir_core",
                resource("lir.wasm.instructions"),
                instructions,
            )?,
            bound(
                "target_byte_length",
                resource("lir.wasm.byte_lengths"),
                lengths,
            )?,
        ],
    )?;
    run(
        "lir.wasm.emit",
        vec![
            bound("target_lir_total", resource("lir.wasm.total"), total)?,
            bound(
                "target_lir_core",
                resource("lir.wasm.instructions"),
                instructions,
            )?,
            bound(
                "target_byte_length",
                resource("lir.wasm.byte_lengths"),
                lengths,
            )?,
            bound(
                "target_byte_offset",
                resource("lir.wasm.byte_offsets"),
                offsets,
            )?,
            bound(
                "artifact_length",
                resource("lir.wasm.body_length"),
                artifact_length,
            )?,
            bound(
                "artifact_bytes",
                resource("lir.wasm.body_bytes"),
                artifact_words,
            )?,
        ],
    )
}

fn load(device: &wgpu::Device, label: &str, shader: &str) -> Result<PassData> {
    make_pass_data_from_shader_key(device, label, "main", shader)
}

#[allow(clippy::too_many_arguments)]
fn validate(
    graph: &CompilerGraph,
    allocations: &crate::gpu::compiler_graph::CompilerGraphAllocations,
    semantic: GpuSemanticLirView<'_>,
    counts: &LaniusBuffer<u32>,
    offsets: &LaniusBuffer<u32>,
    semantic_to_target: &LaniusBuffer<u32>,
    total: &LaniusBuffer<u32>,
    instructions: &LaniusBuffer<WasmLirInstruction>,
) -> Result<()> {
    let resource = |name: &str| graph.resource_id(name).unwrap();
    let run = |pass: &str, bindings: Vec<BoundGraphResource>| {
        allocations
            .validate_pass_bindings(graph, graph.pass_id(pass).unwrap(), &bindings)
            .map_err(anyhow::Error::msg)
    };
    run(
        "lir.wasm.count",
        vec![
            bound(
                "semantic_lir_total",
                resource("lir.semantic.total"),
                semantic.count,
            )?,
            bound(
                "semantic_lir_core",
                resource("lir.semantic.core"),
                semantic.core,
            )?,
            bound(
                "semantic_lir_operands",
                resource("lir.semantic.operands"),
                semantic.operands,
            )?,
            bound(
                "semantic_schedule_order",
                resource("lir.semantic.schedule_order"),
                semantic.execution_order.unwrap(),
            )?,
            bound(
                "target_lir_count",
                resource("lir.wasm.count_by_semantic"),
                counts,
            )?,
        ],
    )?;
    run(
        "lir.wasm.scatter",
        vec![
            bound(
                "semantic_lir_total",
                resource("lir.semantic.total"),
                semantic.count,
            )?,
            bound(
                "semantic_lir_core",
                resource("lir.semantic.core"),
                semantic.core,
            )?,
            bound(
                "semantic_lir_operands",
                resource("lir.semantic.operands"),
                semantic.operands,
            )?,
            bound(
                "semantic_lir_schedule",
                resource("lir.semantic.schedule"),
                semantic.schedule,
            )?,
            bound(
                "semantic_schedule_order",
                resource("lir.semantic.schedule_order"),
                semantic.execution_order.unwrap(),
            )?,
            bound(
                "semantic_lir_aggregate_elements",
                resource("lir.semantic.aggregate_elements"),
                semantic.aggregate_elements,
            )?,
            bound(
                "target_lir_offset",
                resource("lir.wasm.offset_by_semantic"),
                offsets,
            )?,
            bound("target_lir_total", resource("lir.wasm.total"), total)?,
            bound(
                "semantic_to_target_start",
                resource("lir.target.semantic_to_target_start"),
                semantic_to_target,
            )?,
            bound(
                "target_lir_core",
                resource("lir.wasm.instructions"),
                instructions,
            )?,
        ],
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        codegen::lowering_ir::{
            LoweringTarget,
            SemanticLirAggregateElement,
            SemanticLirCallArg,
            SemanticLirCore,
            SemanticLirFunction,
            SemanticLirLocal,
            SemanticLirOperands,
            SemanticLirParam,
            SemanticLirSchedule,
            SemanticLirString,
            lowering_compiler_graph,
            opcode,
        },
        gpu::{
            buffers::{
                readback_bytes,
                storage_ro_from_bytes,
                storage_ro_from_u32s,
                tracked_buffer_allocation_stats,
            },
            device,
            passes_core::{map_readback_blocking, pipeline_creation_count},
        },
    };

    fn words<const N: usize>(records: &[[u32; N]]) -> Vec<u8> {
        records
            .iter()
            .flat_map(|record| record.iter())
            .flat_map(|word| word.to_le_bytes())
            .collect()
    }

    fn read_words(device: &wgpu::Device, buffer: &LaniusBuffer<u8>) -> Vec<u32> {
        let slice = buffer.slice(..);
        map_readback_blocking(device, &slice, "Wasm LIR readback").unwrap();
        let mapped = slice.get_mapped_range();
        let result = mapped
            .chunks_exact(4)
            .map(|bytes| u32::from_le_bytes(bytes.try_into().unwrap()))
            .collect();
        drop(mapped);
        buffer.unmap();
        result
    }

    #[test]
    fn physical_gpu_runs_resident_semantic_to_scheduled_wasm_bytes() {
        let gpu = device::global();
        let capacities = LoweringCapacities {
            source_bytes: 8,
            tokens: 16,
            hir_nodes: 4,
            semantic_instructions: 8,
            call_arguments: 1,
            parameters: 4,
            aggregate_elements: 1,
            target_instructions: 8,
            artifact_bytes: 256,
        };
        let graph = lowering_compiler_graph(capacities, LoweringTarget::Wasm).unwrap();
        let workspace =
            CompilerGraphWorkspace::new(&gpu.device, "test.wasm_stage", &graph).unwrap();
        let semantic_status: LaniusBuffer<LoweringStatus> = workspace
            .alias(&graph, graph.resource_id("lowering.status").unwrap(), 1)
            .unwrap();
        let semantic_total =
            storage_ro_from_u32s(&gpu.device, "test.wasm_stage.semantic_total", &[7]);
        let semantic_core = storage_ro_from_bytes::<SemanticLirCore>(
            &gpu.device,
            "test.wasm_stage.semantic_core",
            &words(&[
                [opcode::SEMANTIC_LIR_OP_CONST_I32, 3, 0, 0],
                [opcode::SEMANTIC_LIR_OP_CONST_I32, 3, 1, 0],
                [opcode::SEMANTIC_LIR_OP_ADD, 3, 2, 0],
                [
                    opcode::SEMANTIC_LIR_OP_BRANCH_IF,
                    0,
                    3,
                    opcode::SEMANTIC_LIR_FLAG_BRANCH_DEPTH_VALID
                        | opcode::SEMANTIC_LIR_FLAG_BRANCH_FALSE,
                ],
                [opcode::SEMANTIC_LIR_OP_RETURN, 0, 4, 0],
                [opcode::SEMANTIC_LIR_OP_VALUE_GET, 7, 5, 0],
                [opcode::SEMANTIC_LIR_OP_VALUE_SET, 3, 6, 0],
                [0; 4],
            ]),
            8,
        );
        let semantic_operands = storage_ro_from_bytes::<SemanticLirOperands>(
            &gpu.device,
            "test.wasm_stage.semantic_operands",
            &words(&[
                [0, 7, u32::MAX, u32::MAX],
                [1, 9, u32::MAX, u32::MAX],
                [2, 1, 0, u32::MAX],
                [3, 2, 0, u32::MAX],
                [4, 2, u32::MAX, u32::MAX],
                [5, 4, u32::MAX, u32::MAX],
                [6, 8, 5, u32::MAX],
                [u32::MAX; 4],
            ]),
            8,
        );
        let semantic_schedule = storage_ro_from_bytes::<SemanticLirSchedule>(
            &gpu.device,
            "test.wasm_stage.semantic_schedule",
            &words(&[
                [0, 0, 5, 0],
                [0, 0, 1, 0],
                [0, 0, 5, 4],
                [0, 0, 5, 8],
                [0, 6, 6, 0],
                [0, 0, 5, 10],
                [0, 0, 5, 12],
                [u32::MAX; 4],
            ]),
            8,
        );
        let semantic_order: LaniusBuffer<u32> = workspace
            .alias(
                &graph,
                graph.resource_id("lir.semantic.schedule_order").unwrap(),
                8,
            )
            .unwrap();
        gpu.queue.write_buffer(
            &semantic_order.buffer,
            0,
            &words(&[[1u32, 0, 2, 3, 5, 6, 4, 7]]),
        );
        let semantic_call_args = storage_ro_from_bytes::<SemanticLirCallArg>(
            &gpu.device,
            "test.wasm_stage.semantic_call_args",
            &words(&[[u32::MAX; 4]]),
            1,
        );
        let semantic_call_arg_count =
            storage_ro_from_u32s(&gpu.device, "test.wasm_stage.call_arg_count", &[0]);
        let semantic_call_arg_start = storage_ro_from_u32s(
            &gpu.device,
            "test.wasm_stage.call_arg_start",
            &[u32::MAX; 8],
        );
        let semantic_call_arg_count_by_instruction = storage_ro_from_u32s(
            &gpu.device,
            "test.wasm_stage.call_arg_count_by_instruction",
            &[0; 8],
        );
        let semantic_aggregate_elements = storage_ro_from_bytes::<SemanticLirAggregateElement>(
            &gpu.device,
            "test.wasm_stage.aggregate_elements",
            &words(&[[u32::MAX; 4]; 2]),
            2,
        );
        let semantic_string_rows = storage_ro_from_bytes::<SemanticLirString>(
            &gpu.device,
            "test.wasm_stage.strings",
            &words(&[[u32::MAX; 4]]),
            1,
        );
        let semantic_empty_count =
            storage_ro_from_u32s(&gpu.device, "test.wasm_stage.empty_count", &[0]);
        let semantic_string_data =
            storage_ro_from_u32s(&gpu.device, "test.wasm_stage.string_data", &[0; 2]);
        let semantic_functions = storage_ro_from_bytes::<SemanticLirFunction>(
            &gpu.device,
            "test.wasm_stage.functions",
            &words(&[
                [0, 1, 0, 2, 0, 1, 0, 0, 2, 0, 0, 0],
                [u32::MAX; 12],
                [u32::MAX; 12],
                [u32::MAX; 12],
            ]),
            4,
        );
        let semantic_params = storage_ro_from_bytes::<SemanticLirParam>(
            &gpu.device,
            "test.wasm_stage.params",
            &words(&[[0, 2, 0, 3], [0, 4, 1, 7], [u32::MAX; 4], [u32::MAX; 4]]),
            4,
        );
        let semantic_locals = storage_ro_from_bytes::<SemanticLirLocal>(
            &gpu.device,
            "test.wasm_stage.locals",
            &words(&[
                [0, 6, 0, 7],
                [0, 8, 1, 3],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
            ]),
            8,
        );
        let semantic_function_count =
            storage_ro_from_u32s(&gpu.device, "test.wasm_stage.function_count", &[1]);
        let semantic_param_count =
            storage_ro_from_u32s(&gpu.device, "test.wasm_stage.param_count", &[2]);
        let semantic_local_count =
            storage_ro_from_u32s(&gpu.device, "test.wasm_stage.local_count", &[2]);
        let stage = GpuWasmLirStage::new(
            &gpu.device,
            &graph,
            &workspace,
            capacities,
            GpuSemanticLirView {
                count: &semantic_total,
                core: &semantic_core,
                operands: &semantic_operands,
                call_args: &semantic_call_args,
                call_arg_count: &semantic_call_arg_count,
                call_arg_start_by_instruction: &semantic_call_arg_start,
                call_arg_count_by_instruction: &semantic_call_arg_count_by_instruction,
                aggregate_elements: &semantic_aggregate_elements,
                aggregate_element_count: &semantic_empty_count,
                strings: &semantic_string_rows,
                string_count: &semantic_empty_count,
                string_data_words: &semantic_string_data,
                string_pool_len: &semantic_empty_count,
                functions: &semantic_functions,
                function_count: &semantic_function_count,
                params: &semantic_params,
                param_count: &semantic_param_count,
                locals: &semantic_locals,
                local_count: &semantic_local_count,
                schedule: &semantic_schedule,
                execution_order: Some(&semantic_order),
                status: &semantic_status,
            },
        )
        .unwrap();
        let pipelines_before = pipeline_creation_count();
        let buffers_before = tracked_buffer_allocation_stats();
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.wasm_stage.encoder"),
            });
        stage.record_lir(&mut encoder).unwrap();
        assert_eq!(pipeline_creation_count(), pipelines_before);
        assert_eq!(tracked_buffer_allocation_stats(), buffers_before);

        let output = stage.output();
        let artifact = stage.artifact();
        let total_readback = readback_bytes(&gpu.device, "test.wasm_stage.total.rb", 4, 1);
        let core_readback = readback_bytes(&gpu.device, "test.wasm_stage.core.rb", 128, 32);
        let function_count_readback =
            readback_bytes(&gpu.device, "test.wasm_stage.function_count.rb", 4, 1);
        let functions_readback =
            readback_bytes(&gpu.device, "test.wasm_stage.functions.rb", 64, 16);
        let abi_functions_readback =
            readback_bytes(&gpu.device, "test.wasm_stage.abi_functions.rb", 224, 56);
        let artifact_length_readback =
            readback_bytes(&gpu.device, "test.wasm_stage.artifact_length.rb", 4, 1);
        let artifact_readback = readback_bytes(&gpu.device, "test.wasm_stage.artifact.rb", 256, 64);
        let body_length_readback =
            readback_bytes(&gpu.device, "test.wasm_stage.body_length.rb", 4, 1);
        let body_readback = readback_bytes(&gpu.device, "test.wasm_stage.body.rb", 64, 16);
        encoder.copy_buffer_to_buffer(&output.total.buffer, 0, &total_readback.buffer, 0, 4);
        encoder.copy_buffer_to_buffer(
            &output.instructions.buffer,
            0,
            &core_readback.buffer,
            0,
            128,
        );
        encoder.copy_buffer_to_buffer(
            &output.functions.count.buffer,
            0,
            &function_count_readback.buffer,
            0,
            4,
        );
        encoder.copy_buffer_to_buffer(
            &output.functions.rows.buffer,
            0,
            &functions_readback.buffer,
            0,
            64,
        );
        encoder.copy_buffer_to_buffer(
            &output.abi_functions.buffer,
            0,
            &abi_functions_readback.buffer,
            0,
            224,
        );
        encoder.copy_buffer_to_buffer(
            &stage.artifact_length.buffer,
            0,
            &body_length_readback.buffer,
            0,
            4,
        );
        encoder.copy_buffer_to_buffer(
            &stage.artifact_words.buffer,
            0,
            &body_readback.buffer,
            0,
            64,
        );
        stage.module.record(&mut encoder).unwrap();
        encoder.copy_buffer_to_buffer(
            &artifact.length.buffer,
            0,
            &artifact_length_readback.buffer,
            0,
            4,
        );
        encoder.copy_buffer_to_buffer(&artifact.words.buffer, 0, &artifact_readback.buffer, 0, 256);
        gpu.queue.submit(Some(encoder.finish()));

        assert_eq!(read_words(&gpu.device, &total_readback)[0], 8);
        let core = read_words(&gpu.device, &core_readback);
        assert_eq!(
            [
                core[0], core[4], core[8], core[12], core[16], core[20], core[24], core[28],
            ],
            [
                opcode::WASM_LIR_OP_I32_CONST,
                opcode::WASM_LIR_OP_I32_CONST,
                opcode::WASM_LIR_OP_I32_ADD,
                opcode::WASM_LIR_OP_I32_EQZ,
                opcode::WASM_LIR_OP_BRANCH_IF,
                opcode::WASM_LIR_OP_LOCAL_GET,
                opcode::WASM_LIR_OP_LOCAL_SET,
                opcode::WASM_LIR_OP_RETURN,
            ]
        );
        assert_eq!(core[21], 1);
        assert_eq!(core[25], 5);
        assert_eq!(read_words(&gpu.device, &function_count_readback)[0], 1);
        assert_eq!(
            &read_words(&gpu.device, &functions_readback)[0..4],
            &[0, 0, 8, 0]
        );
        let abi = read_words(&gpu.device, &abi_functions_readback);
        assert_eq!(&abi[0..14], &[0, 0, 3, 3, 0, 8, 0, 13, 1, 0, 0, 2, 0, 2]);
        assert_eq!(read_words(&gpu.device, &body_length_readback)[0], 13);
        let body_bytes = read_words(&gpu.device, &body_readback)
            .into_iter()
            .flat_map(u32::to_le_bytes)
            .collect::<Vec<_>>();
        assert_eq!(
            &body_bytes[..13],
            &[
                opcode::WASM_LIR_OP_I32_CONST as u8,
                9,
                opcode::WASM_LIR_OP_I32_CONST as u8,
                7,
                opcode::WASM_LIR_OP_I32_ADD as u8,
                opcode::WASM_LIR_OP_I32_EQZ as u8,
                opcode::WASM_LIR_OP_BRANCH_IF as u8,
                0,
                opcode::WASM_LIR_OP_LOCAL_GET as u8,
                1,
                opcode::WASM_LIR_OP_LOCAL_SET as u8,
                5,
                opcode::WASM_LIR_OP_RETURN as u8,
            ]
        );
        // The module includes the target runtime's memory and mutable heap-pointer
        // global in addition to the function/table/export/code sections.
        assert_eq!(read_words(&gpu.device, &artifact_length_readback)[0], 143);
        let artifact_bytes = read_words(&gpu.device, &artifact_readback)
            .into_iter()
            .flat_map(u32::to_le_bytes)
            .collect::<Vec<_>>();
        assert_eq!(&artifact_bytes[..8], b"\0asm\x01\0\0\0");

        let allocations_before = tracked_buffer_allocation_stats();
        // A full compiler job regenerates semantic order before target lowering.
        // This target-only resident replay supplies the same input explicitly.
        gpu.queue.write_buffer(
            &semantic_order.buffer,
            0,
            &words(&[[1u32, 0, 2, 3, 5, 6, 4, 7]]),
        );
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.wasm_stage.resident_artifact.encoder"),
            });
        stage.record(&mut encoder).unwrap();
        assert_eq!(tracked_buffer_allocation_stats(), allocations_before);
        gpu.queue.submit(Some(encoder.finish()));
        let resident_artifact = stage.finish_artifact(&gpu.device).unwrap();
        assert_eq!(resident_artifact.len(), 143);
        assert_eq!(&resident_artifact[..8], b"\0asm\x01\0\0\0");
    }
}
