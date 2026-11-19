//! GPU-resident semantic-LIR to optimizer-IR projection.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::{
    lowering_ir::{
        LoweringCapacities,
        LoweringStatus,
        SemanticLirAggregateElement,
        SemanticLirCallArg,
        SemanticLirFunction,
        SemanticLirLocal,
        SemanticLirParam,
        SemanticLirString,
    },
    optimization_ir::{
        OptIrNodeControl,
        OptIrNodeCore,
        OptIrNodeOperands,
        OptIrNodeResults,
        OptIrValueDefinition,
    },
    semantics::{GpuSemanticLirView, lowering_allocations_with_semantic},
};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    compiler_graph::{
        CompilerGraph,
        CompilerGraphWorkspace,
    },
    kernels::KernelRegistry,
    operations::{
        STEP_PROGRAM_MAX_GROUPS,
        STEP_PROGRAM_SYNC_WORDS,
        StepProgramOperation,
    },
    resource_registry::ResourceMap,
    timer::GpuTimer,
};

pub(super) const OPTIMIZATION_PROGRAM_SLOTS: usize = 3;
pub(super) const OPTIMIZATION_PROGRAM_FAILURE_BYTES: usize = OPTIMIZATION_PROGRAM_SLOTS * 4;

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct ProjectionParams {
    semantic_capacity: u32,
    hir_capacity: u32,
    block_capacity: u32,
    edge_capacity: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct AccessParams {
    semantic_capacity: u32,
    hir_capacity: u32,
    block_capacity: u32,
    access_capacity: u32,
    declaration_capacity: u32,
    parameter_capacity: u32,
    local_capacity: u32,
    reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct SsaParams {
    block_capacity: u32,
    edge_capacity: u32,
    access_capacity: u32,
    declaration_capacity: u32,
    declaration_block_capacity: u32,
    demand_capacity: u32,
    alias_hops: u32,
    reserved: u32,
    incoming_capacity: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct SsaValueParams {
    semantic_capacity: u32,
    parameter_capacity: u32,
    block_argument_capacity: u32,
    value_capacity: u32,
    call_argument_capacity: u32,
    aggregate_element_capacity: u32,
    block_capacity: u32,
    access_capacity: u32,
    incoming_capacity: u32,
    hir_capacity: u32,
    use_capacity: u32,
    reserved1: u32,
}

#[derive(Clone, Copy)]
pub(crate) struct GpuOptIrMetadataView<'a> {
    pub layout_word_offset: &'a LaniusBuffer<u32>,
    pub function_id_by_hir: &'a LaniusBuffer<u32>,
    pub call_args: &'a LaniusBuffer<SemanticLirCallArg>,
    pub call_arg_count: &'a LaniusBuffer<u32>,
    pub call_arg_start_by_hir: &'a LaniusBuffer<u32>,
    pub call_arg_count_by_hir: &'a LaniusBuffer<u32>,
    pub aggregate_elements: &'a LaniusBuffer<SemanticLirAggregateElement>,
    pub aggregate_element_count: &'a LaniusBuffer<u32>,
    pub strings: &'a LaniusBuffer<SemanticLirString>,
    pub string_count: &'a LaniusBuffer<u32>,
    pub string_data_words: &'a LaniusBuffer<u32>,
    pub string_pool_len: &'a LaniusBuffer<u32>,
    pub functions: &'a LaniusBuffer<SemanticLirFunction>,
    pub function_count: &'a LaniusBuffer<u32>,
    pub params: &'a LaniusBuffer<SemanticLirParam>,
    pub param_value_layout: &'a LaniusBuffer<u32>,
    pub place_storage_by_token: &'a LaniusBuffer<u32>,
    pub param_count: &'a LaniusBuffer<u32>,
    pub locals: &'a LaniusBuffer<SemanticLirLocal>,
    pub local_count: &'a LaniusBuffer<u32>,
    pub execution_order: Option<&'a LaniusBuffer<u32>>,
    pub status: &'a LaniusBuffer<LoweringStatus>,
}

impl<'a> GpuOptIrMetadataView<'a> {
    pub(super) fn from_semantic(semantic: GpuSemanticLirView<'a>) -> Self {
        Self {
            layout_word_offset: semantic.layout_word_offset,
            function_id_by_hir: semantic.function_id_by_hir,
            call_args: semantic.call_args,
            call_arg_count: semantic.call_arg_count,
            call_arg_start_by_hir: semantic.call_arg_start_by_hir,
            call_arg_count_by_hir: semantic.call_arg_count_by_hir,
            aggregate_elements: semantic.aggregate_elements,
            aggregate_element_count: semantic.aggregate_element_count,
            strings: semantic.strings,
            string_count: semantic.string_count,
            string_data_words: semantic.string_data_words,
            string_pool_len: semantic.string_pool_len,
            functions: semantic.functions,
            function_count: semantic.function_count,
            params: semantic.params,
            param_value_layout: semantic.param_value_layout,
            place_storage_by_token: semantic.place_storage_by_token,
            param_count: semantic.param_count,
            locals: semantic.locals,
            local_count: semantic.local_count,
            execution_order: semantic.execution_order,
            status: semantic.status,
        }
    }

    pub(super) fn register(
        self,
        graph: &CompilerGraph,
        resources: &mut ResourceMap<'a>,
    ) -> Result<()> {
        macro_rules! buffer {
            ($name:literal, $value:expr) => {
                resources.graph_buffer(graph, $name, $value)?
            };
        }
        buffer!("lir.semantic.layout_word_offset", self.layout_word_offset);
        buffer!("semantic.function_ids", self.function_id_by_hir);
        buffer!("lir.semantic.call_args", self.call_args);
        buffer!("lir.semantic.call_arg_total", self.call_arg_count);
        buffer!(
            "lir.semantic.call_arg_prefix_by_hir",
            self.call_arg_start_by_hir
        );
        buffer!(
            "lir.semantic.call_arg_counts_by_hir",
            self.call_arg_count_by_hir
        );
        buffer!("lir.semantic.aggregate_elements", self.aggregate_elements);
        buffer!(
            "lir.semantic.aggregate_element_total",
            self.aggregate_element_count
        );
        buffer!("lir.semantic.strings", self.strings);
        buffer!("lir.semantic.string_total", self.string_count);
        buffer!("lir.semantic.string_data", self.string_data_words);
        buffer!("lir.semantic.string_pool_len", self.string_pool_len);
        buffer!("lir.semantic.functions", self.functions);
        buffer!("lir.semantic.function_total", self.function_count);
        buffer!("lir.semantic.params", self.params);
        buffer!("lir.semantic.param_value_layout", self.param_value_layout);
        buffer!("lir.semantic.place_storage_by_token", self.place_storage_by_token);
        buffer!("lir.semantic.param_total", self.param_count);
        buffer!("lir.semantic.locals", self.locals);
        buffer!("lir.semantic.local_total", self.local_count);
        if let Some(order) = self.execution_order {
            buffer!("lir.semantic.schedule_order", order);
        }
        buffer!("lowering.status", self.status);
        Ok(())
    }
}

#[derive(Clone, Copy)]
pub(crate) struct GpuOptIrView<'a> {
    /// Checked CFG execution ownership; target stages do not recompute it.
    pub block_count: &'a LaniusBuffer<u32>,
    pub reachable: &'a LaniusBuffer<u32>,
    pub count: &'a LaniusBuffer<u32>,
    pub core: &'a LaniusBuffer<OptIrNodeCore>,
    pub operands: &'a LaniusBuffer<OptIrNodeOperands>,
    pub control: &'a LaniusBuffer<OptIrNodeControl>,
    pub results: &'a LaniusBuffer<OptIrNodeResults>,
    pub value_count: &'a LaniusBuffer<u32>,
    pub value_definitions: &'a LaniusBuffer<OptIrValueDefinition>,
    pub value_by_block_argument: &'a LaniusBuffer<u32>,
    /// Original semantic row for diagnostics and differential validation.
    pub semantic_row: &'a LaniusBuffer<u32>,
    /// Source HIR owner. Kept as a separate hot column so ordinary target
    /// passes do not fetch the diagnostic-only semantic row.
    pub source_hir: &'a LaniusBuffer<u32>,
    /// Inverse of `metadata.execution_order`: stable OptIR node ID to its
    /// position in the target-independent scheduled stream.
    pub position_by_node: &'a LaniusBuffer<u32>,
    /// Compact variable-arity rows and declaration/string metadata are
    /// immutable auxiliary inputs. Their storage representation is already
    /// suitable for OptIR, so the ownership boundary transfers it without a
    /// second copy or exposing the mutable semantic instruction view.
    pub metadata: GpuOptIrMetadataView<'a>,
}

impl<'a> GpuOptIrView<'a> {
    pub(super) fn register(
        self,
        graph: &CompilerGraph,
        resources: &mut ResourceMap<'a>,
    ) -> Result<()> {
        self.metadata.register(graph, resources)?;
        resources.graph_buffer(graph, "lir.opt.block_total", self.block_count)?;
        resources.graph_buffer(graph, "lir.opt.reachable", self.reachable)?;
        resources.graph_buffer(graph, "lir.opt.total", self.count)?;
        resources.graph_buffer(graph, "lir.opt.core", self.core)?;
        resources.graph_buffer(graph, "lir.opt.operands", self.operands)?;
        resources.graph_buffer(graph, "lir.opt.control", self.control)?;
        resources.graph_buffer(graph, "lir.opt.results", self.results)?;
        resources.graph_buffer(graph, "lir.opt.ssa.value_total", self.value_count)?;
        resources.graph_buffer(
            graph,
            "lir.opt.ssa.value_definitions",
            self.value_definitions,
        )?;
        resources.graph_buffer(
            graph,
            "lir.opt.ssa.value_by_block_argument",
            self.value_by_block_argument,
        )?;
        resources.graph_buffer(graph, "lir.opt.semantic_row", self.semantic_row)?;
        resources.graph_buffer(graph, "lir.opt.source_hir", self.source_hir)?;
        resources.graph_buffer(graph, "lir.opt.position_by_node", self.position_by_node)?;
        Ok(())
    }
}

pub(crate) struct GpuOptimizationStage {
    control_flow: [[StepProgramOperation; 2]; 2],
    program_sync: LaniusBuffer<u32>,
    capacities: LoweringCapacities,
    block_arguments: [[StepProgramOperation; 2]; 2],
    ssa_values: [[StepProgramOperation; 2]; 2],
    _params: LaniusBuffer<ProjectionParams>,
    _access_params: LaniusBuffer<AccessParams>,
    _ssa_params: LaniusBuffer<SsaParams>,
    _ssa_value_params: LaniusBuffer<SsaValueParams>,
    count: LaniusBuffer<u32>,
    core: LaniusBuffer<OptIrNodeCore>,
    operands: LaniusBuffer<OptIrNodeOperands>,
    control: LaniusBuffer<OptIrNodeControl>,
    results: LaniusBuffer<OptIrNodeResults>,
    semantic_row: LaniusBuffer<u32>,
    source_hir: LaniusBuffer<u32>,
    position_by_node: LaniusBuffer<u32>,
    block_count: LaniusBuffer<u32>,
    reachable: LaniusBuffer<u32>,
    value_count: LaniusBuffer<u32>,
    value_definitions: LaniusBuffer<OptIrValueDefinition>,
    value_by_block_argument: LaniusBuffer<u32>,
}

impl GpuOptimizationStage {
    pub(crate) fn new(
        device: &wgpu::Device,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        capacities: LoweringCapacities,
        semantic: GpuSemanticLirView<'_>,
        kernels: &KernelRegistry,
    ) -> Result<Self> {
        let allocations = lowering_allocations_with_semantic(graph, workspace, semantic)?;
        let resource = |name: &str| {
            graph
                .resource_id(name)
                .with_context(|| format!("optimizer graph is missing {name}"))
        };
        let rows = capacities.semantic_instructions.max(1) as usize;
        let block_capacity = capacities.optimization_block_capacity();
        let edge_capacity = capacities.optimization_edge_capacity();
        let access_capacity = capacities.optimization_access_capacity();
        let declaration_block_capacity = capacities.optimization_declaration_block_capacity();
        let demand_capacity = capacities.optimization_ssa_demand_capacity();
        let incoming_capacity = capacities.optimization_ssa_incoming_capacity();
        let value_capacity = capacities.optimization_value_capacity();
        let use_capacity = capacities.optimization_use_capacity();
        let count = workspace
            .alias(graph, resource("lir.opt.total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let core = workspace
            .alias(graph, resource("lir.opt.core")?, rows)
            .map_err(anyhow::Error::msg)?;
        let operands = workspace
            .alias(graph, resource("lir.opt.operands")?, rows)
            .map_err(anyhow::Error::msg)?;
        let control = workspace
            .alias(graph, resource("lir.opt.control")?, rows)
            .map_err(anyhow::Error::msg)?;
        let results = workspace
            .alias(graph, resource("lir.opt.results")?, rows)
            .map_err(anyhow::Error::msg)?;
        let semantic_row = workspace
            .alias(graph, resource("lir.opt.semantic_row")?, rows)
            .map_err(anyhow::Error::msg)?;
        let source_hir = workspace
            .alias(graph, resource("lir.opt.source_hir")?, rows)
            .map_err(anyhow::Error::msg)?;
        let position_by_node = workspace
            .alias(graph, resource("lir.opt.position_by_node")?, rows)
            .map_err(anyhow::Error::msg)?;
        let block_count = workspace
            .alias(graph, resource("lir.opt.block_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let reachable = workspace
            .alias(
                graph,
                resource("lir.opt.reachable")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let value_count = workspace
            .alias(graph, resource("lir.opt.ssa.value_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let value_definitions = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.value_definitions")?,
                value_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let value_by_block_argument = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.value_by_block_argument")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        semantic.execution_order.context(
            "target lowering graph omitted the semantic execution permutation required by OptIR",
        )?;

        let params = uniform_from_val(
            device,
            "lir.opt.control_flow.params",
            &ProjectionParams {
                semantic_capacity: capacities.semantic_instructions.max(1),
                hir_capacity: capacities.hir_nodes.max(1),
                block_capacity,
                edge_capacity,
            },
        );
        let access_params = uniform_from_val(
            device,
            "lir.opt.access.params",
            &AccessParams {
                semantic_capacity: capacities.semantic_instructions.max(1),
                hir_capacity: capacities.hir_nodes.max(1),
                block_capacity,
                access_capacity,
                declaration_capacity: capacities.declaration_capacity(),
                parameter_capacity: capacities.parameters.max(1),
                local_capacity: capacities.local_capacity(),
                reserved: 0,
            },
        );
        let ssa_params = uniform_from_val(
            device,
            "lir.opt.ssa.params",
            &SsaParams {
                block_capacity,
                edge_capacity,
                access_capacity,
                declaration_capacity: capacities.declaration_capacity(),
                declaration_block_capacity,
                demand_capacity,
                alias_hops: demand_capacity.isqrt().max(1),
                reserved: 0,
                incoming_capacity,
            },
        );
        let ssa_value_params = uniform_from_val(
            device,
            "lir.opt.ssa.values.params",
            &SsaValueParams {
                semantic_capacity: capacities.semantic_instructions.max(1),
                parameter_capacity: capacities.parameters.max(1),
                block_argument_capacity: demand_capacity,
                value_capacity,
                call_argument_capacity: capacities.call_arguments.max(1),
                aggregate_element_capacity: capacities.aggregate_elements.max(1),
                block_capacity,
                access_capacity,
                incoming_capacity,
                hir_capacity: capacities.hir_nodes.max(1),
                use_capacity,
                reserved1: 0,
            },
        );
        let graph_bindings = workspace.bindings(graph).map_err(anyhow::Error::msg)?;
        let mut resources = ResourceMap::new();
        resources.attach_graph(graph, &allocations);
        resources.register_graph_bindings(graph, &graph_bindings);
        semantic.register(graph, &mut resources)?;
        let program_sync = workspace
            .alias(
                graph,
                resource("step_program_sync")?,
                STEP_PROGRAM_SYNC_WORDS * OPTIMIZATION_PROGRAM_SLOTS,
            )
            .map_err(anyhow::Error::msg)?;
        resources.buffer("gParams", &params);
        let variants = |resources: &ResourceMap<'_>, name, key, slot| -> Result<_> {
            let pass = kernels.kernel(key);
            let variant = |groups, validate| {
                StepProgramOperation::new(
                    device,
                    &(graph, &allocations),
                    resources,
                    name,
                    pass,
                    &program_sync,
                    slot,
                    groups,
                    validate,
                )
            };
            Ok([
                [variant(1, 0)?, variant(1, 1)?],
                [
                    variant(STEP_PROGRAM_MAX_GROUPS, 0)?,
                    variant(STEP_PROGRAM_MAX_GROUPS, 1)?,
                ],
            ])
        };
        let control_flow = variants(
            &resources,
            "lir.opt.build_control_flow",
            "codegen/lir/optimization/build_control_flow",
            0,
        )?;
        resources.buffer("access_params", &access_params);
        resources.buffer("demand_params", &ssa_params);
        let block_arguments = variants(
            &resources,
            "lir.opt.build_block_arguments",
            "codegen/lir/optimization/build_block_arguments",
            1,
        )?;
        resources.buffer("gParams", &ssa_value_params);
        let ssa_values = variants(
            &resources,
            "lir.opt.build_ssa_values",
            "codegen/lir/optimization/build_ssa_values",
            2,
        )?;

        Ok(Self {
            control_flow,
            program_sync,
            capacities,
            block_arguments,
            ssa_values,
            _params: params,
            _access_params: access_params,
            _ssa_params: ssa_params,
            _ssa_value_params: ssa_value_params,
            count,
            core,
            operands,
            control,
            results,
            semantic_row,
            source_hir,
            position_by_node,
            block_count,
            reachable,
            value_count,
            value_definitions,
            value_by_block_argument,
        })
    }

    #[cfg(test)]
    pub(crate) fn record(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        timer: Option<&mut GpuTimer>,
    ) -> Result<()> {
        self.record_for_job(encoder, timer, None, None, true)
    }

    /// Records each program with the active job's group count. The CFG
    /// program can be submitted with the earlier semantic lowering work.
    pub(crate) fn record_for_job(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        mut timer: Option<&mut GpuTimer>,
        split: Option<crate::gpu::passes_core::SubmissionSplit<'_>>,
        job: Option<LoweringCapacities>,
        validate_structure: bool,
    ) -> Result<()> {
        if let Some(timer) = timer.as_deref_mut() {
            timer.set_phase(crate::gpu::timer::GpuCompilerPhase::Optimization);
        }
        let capacities = job.unwrap_or(self.capacities);
        let rows = capacities.semantic_instructions.saturating_mul(2)
            .max(capacities.optimization_edge_capacity())
            .max(capacities.hir_nodes);
        let validate = usize::from(validate_structure);
        // CFG ownership and sparse admission clear tables across the built
        // workspace. Keep those clears parallel when a large arena is reused.
        let large_workspace = self.capacities.semantic_instructions > 4096;
        self.control_flow[usize::from(rows > 4096 || large_workspace)][validate]
            .record(encoder)?;
        if let Some(split) = split {
            split.submit_prefix(
                encoder,
                "compile.lowering.semantic",
                "lowering.optimizer.submission.begin",
                timer.as_deref_mut(),
            );
        }
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "optimization.structure.done");
        }
        let argument_rows = capacities.optimization_ssa_walk_capacity()
            .max(capacities.optimization_ssa_incoming_capacity())
            .max(capacities.optimization_access_group_capacity());
        self.block_arguments[usize::from(argument_rows > 4096 || large_workspace)][validate]
            .record(encoder)?;
        let value_rows = capacities.optimization_value_capacity()
            .max(capacities.optimization_use_capacity());
        self.ssa_values[usize::from(value_rows > 4096)][validate].record(encoder)
    }

    pub(crate) fn program_sync(&self) -> &LaniusBuffer<u32> {
        &self.program_sync
    }

    pub(crate) fn output<'a>(&'a self, semantic: GpuSemanticLirView<'a>) -> GpuOptIrView<'a> {
        GpuOptIrView {
            block_count: &self.block_count,
            reachable: &self.reachable,
            count: &self.count,
            core: &self.core,
            operands: &self.operands,
            control: &self.control,
            results: &self.results,
            value_count: &self.value_count,
            value_definitions: &self.value_definitions,
            value_by_block_argument: &self.value_by_block_argument,
            semantic_row: &self.semantic_row,
            source_hir: &self.source_hir,
            position_by_node: &self.position_by_node,
            metadata: GpuOptIrMetadataView::from_semantic(semantic),
        }
    }
}

pub(super) fn lowering_allocations_with_opt(
    graph: &CompilerGraph,
    workspace: &CompilerGraphWorkspace,
    opt: GpuOptIrView<'_>,
) -> Result<crate::gpu::compiler_graph::CompilerGraphAllocations> {
    let mut allocations = workspace.allocations();
    macro_rules! import {
        ($name:literal, $buffer:expr) => {
            allocations
                .import_buffer(
                    graph,
                    graph
                        .resource_id($name)
                        .with_context(|| format!("lowering graph is missing {}", $name))?,
                    $buffer,
                )
                .map_err(anyhow::Error::msg)?;
        };
    }
    let metadata = opt.metadata;
    import!(
        "lir.semantic.layout_word_offset",
        metadata.layout_word_offset
    );
    import!("semantic.function_ids", metadata.function_id_by_hir);
    import!("lir.semantic.call_args", metadata.call_args);
    import!(
        "lir.semantic.call_arg_prefix_by_hir",
        metadata.call_arg_start_by_hir
    );
    import!(
        "lir.semantic.call_arg_counts_by_hir",
        metadata.call_arg_count_by_hir
    );
    import!(
        "lir.semantic.aggregate_elements",
        metadata.aggregate_elements
    );
    import!(
        "lir.semantic.aggregate_element_total",
        metadata.aggregate_element_count
    );
    import!("lir.semantic.strings", metadata.strings);
    import!("lir.semantic.string_total", metadata.string_count);
    import!("lir.semantic.string_data", metadata.string_data_words);
    import!("lir.semantic.string_pool_len", metadata.string_pool_len);
    import!("lir.semantic.functions", metadata.functions);
    import!("lir.semantic.function_total", metadata.function_count);
    import!("lir.semantic.params", metadata.params);
    import!("lir.semantic.param_value_layout", metadata.param_value_layout);
    import!("lir.semantic.place_storage_by_token", metadata.place_storage_by_token);
    import!("lir.semantic.param_total", metadata.param_count);
    import!("lir.semantic.locals", metadata.locals);
    import!("lir.semantic.local_total", metadata.local_count);
    Ok(allocations)
}
