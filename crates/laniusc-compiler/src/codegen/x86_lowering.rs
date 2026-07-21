//! Resident semantic-LIR to scheduled x86 virtual-instruction lowering.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::{
    functions::{GpuTargetFunctionTable, GpuTargetFunctionView},
    lowering::{GpuSemanticLirView, bound, make_group, record_direct, target_lowering_allocations},
    lowering_ir::{LoweringCapacities, LoweringStatus, X86LirCore, X86LirOperands},
    scan::{GpuResidentExclusiveScan, GraphScanContract},
    x86_artifact::{GpuX86ArtifactStage, GpuX86ArtifactView},
};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    compiler_graph::{BoundGraphResource, CompilerGraph, CompilerGraphWorkspace},
    passes_core::{PassData, make_pass_data_from_shader_key},
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct CountParams {
    semantic_capacity: u32,
    reserved0: u32,
    reserved1: u32,
    reserved2: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct ScatterParams {
    semantic_capacity: u32,
    target_capacity: u32,
    reserved0: u32,
    reserved1: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct ScheduleParams {
    target_capacity: u32,
    semantic_capacity: u32,
    reserved0: u32,
    reserved1: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct DeclSlotParams {
    token_capacity: u32,
    parameter_capacity: u32,
    local_capacity: u32,
    function_capacity: u32,
}

pub(crate) struct GpuX86LirView<'a> {
    pub total: &'a LaniusBuffer<u32>,
    pub core: &'a LaniusBuffer<X86LirCore>,
    pub operands: &'a LaniusBuffer<X86LirOperands>,
    pub functions: GpuTargetFunctionView<'a>,
    pub frame_slot_by_decl_token: &'a LaniusBuffer<u32>,
}

/// Produces the uniform x86 virtual records consumed by register allocation
/// and instruction selection. `record` performs no setup or allocation.
pub(crate) struct GpuX86LirStage {
    semantic_capacity: u32,
    count_pass: PassData,
    scatter_pass: PassData,
    resolve_pass: PassData,
    validate_pass: PassData,
    decl_slots_clear_pass: PassData,
    decl_slots_scatter_pass: PassData,
    count_group: wgpu::BindGroup,
    scatter_group: wgpu::BindGroup,
    resolve_group: wgpu::BindGroup,
    validate_group: wgpu::BindGroup,
    decl_slots_clear_group: wgpu::BindGroup,
    decl_slots_scatter_group: wgpu::BindGroup,
    count_scan: GpuResidentExclusiveScan,
    functions: GpuTargetFunctionTable,
    _count_params: LaniusBuffer<CountParams>,
    _scatter_params: LaniusBuffer<ScatterParams>,
    _schedule_params: LaniusBuffer<ScheduleParams>,
    _decl_slot_params: LaniusBuffer<DeclSlotParams>,
    _counts: LaniusBuffer<u32>,
    _offsets: LaniusBuffer<u32>,
    total: LaniusBuffer<u32>,
    core: LaniusBuffer<X86LirCore>,
    operands: LaniusBuffer<X86LirOperands>,
    scheduled_function_ids: LaniusBuffer<u32>,
    _origins: LaniusBuffer<u32>,
    _flags: LaniusBuffer<u32>,
    frame_slot_by_decl_token: LaniusBuffer<u32>,
    decl_slot_dispatch_capacity: u32,
    artifact: GpuX86ArtifactStage,
}

impl GpuX86LirStage {
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
                .with_context(|| format!("x86 lowering graph is missing {name}"))
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
            .context("x86 lowering requires GPU-scheduled semantic LIR")?;
        let counts = alias_u32("lir.x86.count_by_semantic", semantic_capacity)?;
        let offsets = alias_u32("lir.x86.offset_by_semantic", semantic_capacity)?;
        let semantic_to_target =
            alias_u32("lir.target.semantic_to_target_start", semantic_capacity)?;
        let total = alias_u32("lir.x86.total", 1)?;
        let core = workspace
            .alias(graph, resource("lir.x86.core")?, target_capacity as usize)
            .map_err(anyhow::Error::msg)?;
        let operands = workspace
            .alias(
                graph,
                resource("lir.x86.operands")?,
                target_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let origins = alias_u32("lir.x86.semantic_origins", target_capacity)?;
        let flags = alias_u32("lir.x86.flags", target_capacity)?;
        let scheduled_function_ids =
            alias_u32("lir.target.scheduled_function_ids", target_capacity)?;
        let frame_slot_by_decl_token = alias_u32(
            "lir.x86.frame_slot_by_decl_token",
            capacities
                .tokens
                .saturating_add(capacities.hir_nodes)
                .max(1),
        )?;

        let count_pass = load(device, "lir.x86.count", "codegen/lir/x86/count")?;
        let scatter_pass = load(device, "lir.x86.scatter", "codegen/lir/x86/scatter")?;
        let resolve_pass = load(device, "lir.x86.resolve", "codegen/lir/x86/resolve")?;
        let validate_pass = load(device, "lir.x86.validate", "codegen/lir/x86/validate")?;
        let decl_slots_clear_pass = load(
            device,
            "lir.x86.decl_slots.clear",
            "codegen/lir/x86/decl_slots_clear",
        )?;
        let decl_slots_scatter_pass = load(
            device,
            "lir.x86.decl_slots.scatter",
            "codegen/lir/x86/decl_slots_scatter",
        )?;
        let count_params = uniform_from_val(
            device,
            "lir.x86.count.params",
            &CountParams {
                semantic_capacity,
                reserved0: 0,
                reserved1: 0,
                reserved2: 0,
            },
        );
        let scatter_params = uniform_from_val(
            device,
            "lir.x86.scatter.params",
            &ScatterParams {
                semantic_capacity,
                target_capacity,
                reserved0: 0,
                reserved1: 0,
            },
        );
        let schedule_params = uniform_from_val(
            device,
            "lir.x86.schedule.params",
            &ScheduleParams {
                target_capacity,
                semantic_capacity,
                reserved0: 0,
                reserved1: 0,
            },
        );
        let decl_slot_params = uniform_from_val(
            device,
            "lir.x86.decl_slots.params",
            &DeclSlotParams {
                token_capacity: capacities
                    .tokens
                    .saturating_add(capacities.hir_nodes)
                    .max(1),
                parameter_capacity: capacities.parameters.max(1),
                local_capacity: capacities.hir_nodes.max(1),
                function_capacity: capacities.hir_nodes.max(1),
            },
        );
        let count_group = make_group(
            device,
            &count_pass,
            "lir.x86.count.bind_group",
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
                (
                    "semantic_lir_call_arg_count_by_instruction",
                    semantic.call_arg_count_by_instruction.as_entire_binding(),
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
                input: "lir.x86.count_by_semantic",
                local: "lir.target.count_scan_local",
                block_sum: "lir.target.count_scan_block_sum",
                block_prefix: "lir.target.count_scan_block_prefix",
                hierarchy: "lir.target.count_scan_hierarchy",
                output: "lir.x86.offset_by_semantic",
                total: "lir.x86.total",
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
            "lir.x86.scatter.bind_group",
            &[
                ("gParams", scatter_params.as_entire_binding()),
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
                (
                    "semantic_lir_call_arg_count_by_instruction",
                    semantic.call_arg_count_by_instruction.as_entire_binding(),
                ),
                (
                    "semantic_lir_call_arg_start_by_instruction",
                    semantic.call_arg_start_by_instruction.as_entire_binding(),
                ),
                (
                    "semantic_lir_call_args",
                    semantic.call_args.as_entire_binding(),
                ),
                (
                    "semantic_lir_aggregate_element_total",
                    semantic.aggregate_element_count.as_entire_binding(),
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
                ("target_lir_core", core.as_entire_binding()),
                ("target_lir_operands", operands.as_entire_binding()),
                ("target_semantic_origin", origins.as_entire_binding()),
                ("target_lir_flags", flags.as_entire_binding()),
            ],
        )?;
        let validate_group = make_group(
            device,
            &validate_pass,
            "lir.x86.validate.bind_group",
            &[
                ("gParams", scatter_params.as_entire_binding()),
                ("target_lir_total", total.as_entire_binding()),
                ("target_lir_core", core.as_entire_binding()),
                ("target_lir_flags", flags.as_entire_binding()),
                ("lowering_status", semantic.status.as_entire_binding()),
            ],
        )?;
        let resolve_group = make_group(
            device,
            &resolve_pass,
            "lir.x86.resolve.bind_group",
            &[
                ("gParams", schedule_params.as_entire_binding()),
                ("target_lir_total", total.as_entire_binding()),
                ("target_lir_core", core.as_entire_binding()),
                ("target_lir_operands", operands.as_entire_binding()),
                ("target_semantic_origin", origins.as_entire_binding()),
                (
                    "semantic_to_target_start",
                    semantic_to_target.as_entire_binding(),
                ),
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
        validate(
            graph,
            &allocations,
            semantic,
            &counts,
            &offsets,
            &semantic_to_target,
            &total,
            &core,
            &operands,
            &origins,
            &flags,
        )?;
        validate_target_status(graph, &allocations, semantic.status, &total, &core, &flags)?;
        validate_resolve(
            graph,
            &allocations,
            semantic,
            &total,
            &core,
            &operands,
            &origins,
            &semantic_to_target,
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
        let decl_slots_clear_group = make_group(
            device,
            &decl_slots_clear_pass,
            "lir.x86.decl_slots.clear.bind_group",
            &[
                ("gParams", decl_slot_params.as_entire_binding()),
                (
                    "x86_frame_slot_by_decl_token",
                    frame_slot_by_decl_token.as_entire_binding(),
                ),
            ],
        )?;
        let decl_slots_scatter_group = make_group(
            device,
            &decl_slots_scatter_pass,
            "lir.x86.decl_slots.scatter.bind_group",
            &[
                ("gParams", decl_slot_params.as_entire_binding()),
                (
                    "semantic_lir_param_total",
                    semantic.param_count.as_entire_binding(),
                ),
                ("semantic_lir_params", semantic.params.as_entire_binding()),
                (
                    "semantic_lir_local_total",
                    semantic.local_count.as_entire_binding(),
                ),
                ("semantic_lir_locals", semantic.locals.as_entire_binding()),
                (
                    "semantic_lir_function_total",
                    semantic.function_count.as_entire_binding(),
                ),
                (
                    "semantic_lir_functions",
                    semantic.functions.as_entire_binding(),
                ),
                (
                    "target_function_count",
                    functions.output().count.as_entire_binding(),
                ),
                (
                    "target_functions",
                    functions.output().rows.as_entire_binding(),
                ),
                (
                    "target_function_index_by_semantic",
                    functions.output().index_by_semantic.as_entire_binding(),
                ),
                (
                    "x86_frame_slot_by_decl_token",
                    frame_slot_by_decl_token.as_entire_binding(),
                ),
            ],
        )?;
        validate_decl_slots(
            graph,
            &allocations,
            semantic,
            functions.output(),
            &frame_slot_by_decl_token,
        )?;
        let artifact = GpuX86ArtifactStage::new(
            device,
            graph,
            workspace,
            &allocations,
            capacities,
            semantic,
            &total,
            &core,
            &operands,
            &scheduled_function_ids,
            functions.output(),
            &frame_slot_by_decl_token,
        )?;
        Ok(Self {
            semantic_capacity,
            count_pass,
            scatter_pass,
            resolve_pass,
            validate_pass,
            decl_slots_clear_pass,
            decl_slots_scatter_pass,
            count_group,
            scatter_group,
            resolve_group,
            validate_group,
            decl_slots_clear_group,
            decl_slots_scatter_group,
            count_scan,
            functions,
            _count_params: count_params,
            _scatter_params: scatter_params,
            _schedule_params: schedule_params,
            _decl_slot_params: decl_slot_params,
            _counts: counts,
            _offsets: offsets,
            total,
            core,
            operands,
            scheduled_function_ids,
            _origins: origins,
            _flags: flags,
            frame_slot_by_decl_token,
            decl_slot_dispatch_capacity: capacities
                .parameters
                .max(capacities.semantic_instructions)
                .max(1),
            artifact,
        })
    }

    pub(crate) fn output(&self) -> GpuX86LirView<'_> {
        GpuX86LirView {
            total: &self.total,
            core: &self.core,
            operands: &self.operands,
            functions: self.functions.output(),
            frame_slot_by_decl_token: &self.frame_slot_by_decl_token,
        }
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.record_lir(encoder)?;
        self.artifact.record(encoder)
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
            self.core.count as u32,
        )?;
        record_direct(
            encoder,
            &self.validate_pass,
            &self.validate_group,
            self.core.count as u32,
        )?;
        record_direct(
            encoder,
            &self.resolve_pass,
            &self.resolve_group,
            self.core.count as u32,
        )?;
        self.functions.record(encoder)?;
        record_direct(
            encoder,
            &self.decl_slots_clear_pass,
            &self.decl_slots_clear_group,
            self.frame_slot_by_decl_token.count as u32,
        )?;
        record_direct(
            encoder,
            &self.decl_slots_scatter_pass,
            &self.decl_slots_scatter_group,
            self.decl_slot_dispatch_capacity,
        )
    }

    pub(crate) fn artifact(&self) -> GpuX86ArtifactView<'_> {
        self.artifact.output()
    }

    pub(crate) fn finish_artifact(&self, device: &wgpu::Device) -> Result<Vec<u8>> {
        self.artifact.finish(device)
    }
}

fn validate_decl_slots(
    graph: &CompilerGraph,
    allocations: &crate::gpu::compiler_graph::CompilerGraphAllocations,
    semantic: GpuSemanticLirView<'_>,
    functions: GpuTargetFunctionView<'_>,
    frame_slots: &LaniusBuffer<u32>,
) -> Result<()> {
    let resource = |name: &str| graph.resource_id(name).unwrap();
    let run = |pass: &str, bindings: Vec<BoundGraphResource>| {
        allocations
            .validate_pass_bindings(graph, graph.pass_id(pass).unwrap(), &bindings)
            .map_err(anyhow::Error::msg)
    };
    run(
        "lir.x86.decl_slots.clear",
        vec![bound(
            "x86_frame_slot_by_decl_token",
            resource("lir.x86.frame_slot_by_decl_token"),
            frame_slots,
        )?],
    )?;
    run(
        "lir.x86.decl_slots.scatter",
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
                "target_function_count",
                resource("lir.target.function_count"),
                functions.count,
            )?,
            bound(
                "target_functions",
                resource("lir.target.functions"),
                functions.rows,
            )?,
            bound(
                "target_function_index_by_semantic",
                resource("lir.target.function_index_by_semantic"),
                functions.index_by_semantic,
            )?,
            bound(
                "x86_frame_slot_by_decl_token",
                resource("lir.x86.frame_slot_by_decl_token"),
                frame_slots,
            )?,
        ],
    )
}

fn validate_target_status(
    graph: &CompilerGraph,
    allocations: &crate::gpu::compiler_graph::CompilerGraphAllocations,
    status: &LaniusBuffer<LoweringStatus>,
    total: &LaniusBuffer<u32>,
    core: &LaniusBuffer<X86LirCore>,
    flags: &LaniusBuffer<u32>,
) -> Result<()> {
    let resource = |name: &str| graph.resource_id(name).unwrap();
    allocations
        .validate_pass_bindings(
            graph,
            graph.pass_id("lir.x86.validate").unwrap(),
            &[
                bound("target_lir_total", resource("lir.x86.total"), total)?,
                bound("target_lir_core", resource("lir.x86.core"), core)?,
                bound("target_lir_flags", resource("lir.x86.flags"), flags)?,
                bound("lowering_status", resource("lowering.status"), status)?,
            ],
        )
        .map_err(anyhow::Error::msg)
}

#[allow(clippy::too_many_arguments)]
fn validate_resolve(
    graph: &CompilerGraph,
    allocations: &crate::gpu::compiler_graph::CompilerGraphAllocations,
    semantic: GpuSemanticLirView<'_>,
    total: &LaniusBuffer<u32>,
    core: &LaniusBuffer<X86LirCore>,
    operands: &LaniusBuffer<X86LirOperands>,
    origins: &LaniusBuffer<u32>,
    semantic_to_target: &LaniusBuffer<u32>,
    function_ids: &LaniusBuffer<u32>,
) -> Result<()> {
    let resource = |name: &str| graph.resource_id(name).unwrap();
    allocations
        .validate_pass_bindings(
            graph,
            graph.pass_id("lir.x86.resolve").unwrap(),
            &[
                bound("target_lir_total", resource("lir.x86.total"), total)?,
                bound("target_lir_core", resource("lir.x86.core"), core)?,
                bound(
                    "target_lir_operands",
                    resource("lir.x86.operands"),
                    operands,
                )?,
                bound(
                    "target_semantic_origin",
                    resource("lir.x86.semantic_origins"),
                    origins,
                )?,
                bound(
                    "semantic_to_target_start",
                    resource("lir.target.semantic_to_target_start"),
                    semantic_to_target,
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
    core: &LaniusBuffer<X86LirCore>,
    operands: &LaniusBuffer<X86LirOperands>,
    origins: &LaniusBuffer<u32>,
    flags: &LaniusBuffer<u32>,
) -> Result<()> {
    let resource = |name: &str| graph.resource_id(name).unwrap();
    let run = |pass: &str, bindings: Vec<BoundGraphResource>| {
        allocations
            .validate_pass_bindings(graph, graph.pass_id(pass).unwrap(), &bindings)
            .map_err(anyhow::Error::msg)
    };
    run(
        "lir.x86.count",
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
                "semantic_lir_call_arg_count_by_instruction",
                resource("lir.semantic.call_arg_count_by_instruction"),
                semantic.call_arg_count_by_instruction,
            )?,
            bound(
                "target_lir_count",
                resource("lir.x86.count_by_semantic"),
                counts,
            )?,
        ],
    )?;
    run(
        "lir.x86.scatter",
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
                "semantic_lir_call_arg_count_by_instruction",
                resource("lir.semantic.call_arg_count_by_instruction"),
                semantic.call_arg_count_by_instruction,
            )?,
            bound(
                "semantic_lir_call_arg_start_by_instruction",
                resource("lir.semantic.call_arg_start_by_instruction"),
                semantic.call_arg_start_by_instruction,
            )?,
            bound(
                "semantic_lir_call_args",
                resource("lir.semantic.call_args"),
                semantic.call_args,
            )?,
            bound(
                "semantic_lir_aggregate_element_total",
                resource("lir.semantic.aggregate_element_total"),
                semantic.aggregate_element_count,
            )?,
            bound(
                "semantic_lir_aggregate_elements",
                resource("lir.semantic.aggregate_elements"),
                semantic.aggregate_elements,
            )?,
            bound(
                "target_lir_offset",
                resource("lir.x86.offset_by_semantic"),
                offsets,
            )?,
            bound("target_lir_total", resource("lir.x86.total"), total)?,
            bound(
                "semantic_to_target_start",
                resource("lir.target.semantic_to_target_start"),
                semantic_to_target,
            )?,
            bound("target_lir_core", resource("lir.x86.core"), core)?,
            bound(
                "target_lir_operands",
                resource("lir.x86.operands"),
                operands,
            )?,
            bound(
                "target_semantic_origin",
                resource("lir.x86.semantic_origins"),
                origins,
            )?,
            bound("target_lir_flags", resource("lir.x86.flags"), flags)?,
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

    fn record_bytes<const N: usize>(records: &[[u32; N]]) -> Vec<u8> {
        records
            .iter()
            .flat_map(|record| record.iter())
            .flat_map(|word| word.to_le_bytes())
            .collect()
    }

    fn read_words(device: &wgpu::Device, buffer: &LaniusBuffer<u8>) -> Vec<u32> {
        let slice = buffer.slice(..);
        map_readback_blocking(device, &slice, "x86 LIR readback").unwrap();
        let mapped = slice.get_mapped_range();
        let words = mapped
            .chunks_exact(4)
            .map(|bytes| u32::from_le_bytes(bytes.try_into().unwrap()))
            .collect();
        drop(mapped);
        buffer.unmap();
        words
    }

    #[test]
    fn physical_gpu_runs_resident_semantic_to_scheduled_x86_lir() {
        let gpu = device::global();
        let capacities = LoweringCapacities {
            source_bytes: 8,
            tokens: 8,
            hir_nodes: 4,
            semantic_instructions: 8,
            call_arguments: 2,
            parameters: 2,
            aggregate_elements: 2,
            target_instructions: 10,
            artifact_bytes: 64,
        };
        let graph = lowering_compiler_graph(capacities, LoweringTarget::X86_64).unwrap();
        let workspace = CompilerGraphWorkspace::new(&gpu.device, "test.x86_lir", &graph).unwrap();
        let status: LaniusBuffer<LoweringStatus> = workspace
            .alias(&graph, graph.resource_id("lowering.status").unwrap(), 1)
            .unwrap();
        let total = storage_ro_from_u32s(&gpu.device, "test.x86_lir.total", &[7]);
        let core = storage_ro_from_bytes::<SemanticLirCore>(
            &gpu.device,
            "test.x86_lir.core",
            &record_bytes(&[
                [opcode::SEMANTIC_LIR_OP_CONST_I32, 3, 0, 0],
                [opcode::SEMANTIC_LIR_OP_CONST_I32, 3, 1, 0],
                [opcode::SEMANTIC_LIR_OP_ADD, 3, 2, 0],
                [opcode::SEMANTIC_LIR_OP_RETURN, 0, 3, 0],
                [opcode::SEMANTIC_LIR_OP_CALL, 3, 4, 0],
                [opcode::SEMANTIC_LIR_OP_BRANCH, 0, 5, 0],
                [opcode::SEMANTIC_LIR_OP_BLOCK_BEGIN, 0, 6, 0],
                [0, 0, 0, 0],
            ]),
            8,
        );
        let operands = storage_ro_from_bytes::<SemanticLirOperands>(
            &gpu.device,
            "test.x86_lir.operands",
            &record_bytes(&[
                [0, 7, u32::MAX, u32::MAX],
                [1, 9, u32::MAX, u32::MAX],
                [2, 1, 0, u32::MAX],
                [3, 2, u32::MAX, u32::MAX],
                [4, 42, 0, 2],
                [5, 6, u32::MAX, u32::MAX],
                [6, u32::MAX, u32::MAX, u32::MAX],
                [u32::MAX; 4],
            ]),
            8,
        );
        let schedule = storage_ro_from_bytes::<SemanticLirSchedule>(
            &gpu.device,
            "test.x86_lir.schedule",
            &record_bytes(&[
                [0, 0, 5, 0],
                [0, 0, 1, 0],
                [0, 0, 5, 4],
                [0, 6, 6, 0],
                [0, 10, 10, 0],
                [0, 8, 8, 0],
                [0, 9, 9, 0],
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
            &record_bytes(&[[1u32, 0, 2, 3, 5, 6, 4, 7]]),
        );
        let call_args = storage_ro_from_bytes::<SemanticLirCallArg>(
            &gpu.device,
            "test.x86_lir.call_args",
            &record_bytes(&[[4, 0, 0, 0], [4, 2, 1, 0]]),
            2,
        );
        let call_arg_count = storage_ro_from_u32s(&gpu.device, "test.x86_lir.call_arg_count", &[2]);
        let call_arg_start_by_instruction = storage_ro_from_u32s(
            &gpu.device,
            "test.x86_lir.call_arg_start_by_instruction",
            &[
                u32::MAX,
                u32::MAX,
                u32::MAX,
                u32::MAX,
                0,
                u32::MAX,
                u32::MAX,
                u32::MAX,
            ],
        );
        let call_arg_count_by_instruction = storage_ro_from_u32s(
            &gpu.device,
            "test.x86_lir.call_arg_count_by_instruction",
            &[0, 0, 0, 0, 2, 0, 0, 0],
        );
        let aggregate_elements = storage_ro_from_bytes::<SemanticLirAggregateElement>(
            &gpu.device,
            "test.x86_lir.aggregate_elements",
            &record_bytes(&[[u32::MAX; 4]; 4]),
            4,
        );
        let string_rows = storage_ro_from_bytes::<SemanticLirString>(
            &gpu.device,
            "test.x86_lir.strings",
            &record_bytes(&[[u32::MAX; 4]]),
            1,
        );
        let empty_count = storage_ro_from_u32s(&gpu.device, "test.x86_lir.empty_count", &[0]);
        let string_data = storage_ro_from_u32s(&gpu.device, "test.x86_lir.string_data", &[0; 2]);
        let functions = storage_ro_from_bytes::<SemanticLirFunction>(
            &gpu.device,
            "test.x86_lir.functions",
            &record_bytes(&[
                [0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0],
                [u32::MAX; 12],
                [u32::MAX; 12],
                [u32::MAX; 12],
            ]),
            4,
        );
        let params = storage_ro_from_bytes::<SemanticLirParam>(
            &gpu.device,
            "test.x86_lir.params",
            &record_bytes(&[[0, 3, 0, 3], [u32::MAX; 4]]),
            2,
        );
        let locals = storage_ro_from_bytes::<SemanticLirLocal>(
            &gpu.device,
            "test.x86_lir.locals",
            &record_bytes(&[
                [0, 4, 0, 3],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
            ]),
            8,
        );
        let function_count = storage_ro_from_u32s(&gpu.device, "test.x86_lir.fn_count", &[1]);
        let param_count = storage_ro_from_u32s(&gpu.device, "test.x86_lir.param_count", &[1]);
        let local_count = storage_ro_from_u32s(&gpu.device, "test.x86_lir.local_count", &[1]);
        let stage = GpuX86LirStage::new(
            &gpu.device,
            &graph,
            &workspace,
            capacities,
            GpuSemanticLirView {
                count: &total,
                core: &core,
                operands: &operands,
                call_args: &call_args,
                call_arg_count: &call_arg_count,
                call_arg_start_by_instruction: &call_arg_start_by_instruction,
                call_arg_count_by_instruction: &call_arg_count_by_instruction,
                aggregate_elements: &aggregate_elements,
                aggregate_element_count: &empty_count,
                strings: &string_rows,
                string_count: &empty_count,
                string_data_words: &string_data,
                string_pool_len: &empty_count,
                functions: &functions,
                function_count: &function_count,
                params: &params,
                param_count: &param_count,
                locals: &locals,
                local_count: &local_count,
                schedule: &schedule,
                execution_order: Some(&semantic_order),
                status: &status,
            },
        )
        .unwrap();
        let pipelines_before = pipeline_creation_count();
        let buffers_before = tracked_buffer_allocation_stats();
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.x86_lir.encoder"),
            });
        stage.record_lir(&mut encoder).unwrap();
        assert_eq!(pipeline_creation_count(), pipelines_before);
        assert_eq!(tracked_buffer_allocation_stats(), buffers_before);

        let output = stage.output();
        let total_rb = readback_bytes(&gpu.device, "test.x86_lir.total.rb", 4, 1);
        let core_rb = readback_bytes(&gpu.device, "test.x86_lir.core.rb", 160, 40);
        let operands_rb = readback_bytes(&gpu.device, "test.x86_lir.operands.rb", 160, 40);
        let function_count_rb = readback_bytes(&gpu.device, "test.x86_lir.function_count.rb", 4, 1);
        let functions_rb = readback_bytes(&gpu.device, "test.x86_lir.functions.rb", 64, 16);
        let status_rb = readback_bytes(&gpu.device, "test.x86_lir.status.rb", 16, 4);
        let frame_slots_rb = readback_bytes(&gpu.device, "test.x86_lir.frame_slots.rb", 32, 8);
        encoder.copy_buffer_to_buffer(&output.total.buffer, 0, &total_rb.buffer, 0, 4);
        encoder.copy_buffer_to_buffer(&output.core.buffer, 0, &core_rb.buffer, 0, 160);
        encoder.copy_buffer_to_buffer(&output.operands.buffer, 0, &operands_rb.buffer, 0, 160);
        encoder.copy_buffer_to_buffer(
            &output.functions.count.buffer,
            0,
            &function_count_rb.buffer,
            0,
            4,
        );
        encoder.copy_buffer_to_buffer(
            &output.functions.rows.buffer,
            0,
            &functions_rb.buffer,
            0,
            64,
        );
        encoder.copy_buffer_to_buffer(&status.buffer, 0, &status_rb.buffer, 0, 16);
        encoder.copy_buffer_to_buffer(
            &output.frame_slot_by_decl_token.buffer,
            0,
            &frame_slots_rb.buffer,
            0,
            32,
        );
        gpu.queue.submit(Some(encoder.finish()));

        assert_eq!(read_words(&gpu.device, &total_rb)[0], 9);
        let core_words = read_words(&gpu.device, &core_rb);
        assert_eq!(
            [
                core_words[2],
                core_words[6],
                core_words[10],
                core_words[14],
                core_words[18],
                core_words[22],
                core_words[26],
                core_words[30],
                core_words[34],
            ],
            [
                opcode::X86_LIR_OP_IMM_I32,
                opcode::X86_LIR_OP_IMM_I32,
                opcode::X86_LIR_OP_BINARY,
                opcode::X86_LIR_OP_RETURN,
                opcode::X86_LIR_OP_BRANCH,
                opcode::X86_LIR_OP_LABEL,
                opcode::X86_LIR_OP_CALL_ARG,
                opcode::X86_LIR_OP_CALL_ARG,
                opcode::X86_LIR_OP_CALL,
            ]
        );
        let operand_words = read_words(&gpu.device, &operands_rb);
        assert_eq!([operand_words[0], operand_words[4]], [9, 7]);
        assert_eq!(
            &operand_words[8..11],
            &[opcode::X86_LIR_BINARY_ADD_I32, 0, 1]
        );
        assert_eq!(read_words(&gpu.device, &function_count_rb)[0], 1);
        assert_eq!(&operand_words[16..20], &[u32::MAX, 5, 0, 0]);
        assert_eq!(&read_words(&gpu.device, &functions_rb)[..4], &[0, 0, 9, 0]);
        let frame_slots = read_words(&gpu.device, &frame_slots_rb);
        assert_eq!((frame_slots[3], frame_slots[4]), (9, 10));
        assert_eq!(
            read_words(&gpu.device, &status_rb)[0] & opcode::LOWERING_STATUS_UNSUPPORTED_TARGET,
            0
        );
    }
}
