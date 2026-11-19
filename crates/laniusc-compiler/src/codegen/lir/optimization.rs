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
        OptIrAccessGroup,
        OptIrBlock,
        OptIrBlockArgument,
        OptIrBlockArgumentIncoming,
        OptIrDeclarationBlock,
        OptIrDominatorJump,
        OptIrDominatorTourLink,
        OptIrEdge,
        OptIrFunction,
        OptIrImmediateDominator,
        OptIrIncomingValue,
        OptIrNodeControl,
        OptIrNodeCore,
        OptIrNodeOperands,
        OptIrNodeResults,
        OptIrReachingDefinitionState,
        OptIrRegion,
        OptIrSsaDemand,
        OptIrUseGroup,
        OptIrValueDefinition,
    },
    semantics::{GpuSemanticLirView, lowering_allocations_with_semantic},
};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    compiler_graph::{
        CompilerGraph,
        CompilerGraphWorkspace,
        CompilerPhase,
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

pub(super) const OPTIMIZATION_PROGRAM_SLOTS: usize = 5;
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
    program_groups_override: Option<u32>,
    control_flow_analysis: [[StepProgramOperation; 2]; 2],
    declaration_accesses: [[StepProgramOperation; 2]; 2],
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
    _block_count: LaniusBuffer<u32>,
    _blocks: LaniusBuffer<OptIrBlock>,
    _edge_count: LaniusBuffer<u32>,
    _edges: LaniusBuffer<OptIrEdge>,
    _predecessor_edge_ids: LaniusBuffer<u32>,
    _reachable: LaniusBuffer<u32>,
    _dead_claim_by_block: LaniusBuffer<u32>,
    _immediate_dominator: LaniusBuffer<OptIrImmediateDominator>,
    _dominator_children: LaniusBuffer<u32>,
    _dominator_child_row_by_block: LaniusBuffer<u32>,
    _dominator_tour_link_a: LaniusBuffer<OptIrDominatorTourLink>,
    _dominator_tour_link_b: LaniusBuffer<OptIrDominatorTourLink>,
    _dominator_preorder: LaniusBuffer<u32>,
    _dominator_subtree_end: LaniusBuffer<u32>,
    _block_by_dominator_preorder: LaniusBuffer<u32>,
    _dominator_depth_link_a: LaniusBuffer<OptIrDominatorJump>,
    _dominator_depth_link_b: LaniusBuffer<OptIrDominatorJump>,
    _dominator_depth: LaniusBuffer<u32>,
    _region_count: LaniusBuffer<u32>,
    _regions: LaniusBuffer<OptIrRegion>,
    _region_parent_link_a: LaniusBuffer<u32>,
    _region_parent_link_b: LaniusBuffer<u32>,
    _region_ownership_tree: LaniusBuffer<u32>,
    _block_region: LaniusBuffer<u32>,
    _functions: LaniusBuffer<OptIrFunction>,
    _access_order: LaniusBuffer<u32>,
    _access_groups: LaniusBuffer<OptIrAccessGroup>,
    _local_definition_by_access: LaniusBuffer<u32>,
    _declaration_blocks: LaniusBuffer<OptIrDeclarationBlock>,
    _reaching_definition_states: LaniusBuffer<OptIrReachingDefinitionState>,
    _ssa_demands: LaniusBuffer<OptIrSsaDemand>,
    _ssa_demand_seed_total: LaniusBuffer<u32>,
    _ssa_sparse_declaration: LaniusBuffer<u32>,
    _ssa_sparse_block: LaniusBuffer<u32>,
    _ssa_walk: LaniusBuffer<u32>,
    _ssa_demand_order: LaniusBuffer<u32>,
    _ssa_canonical_demands_tmp: LaniusBuffer<OptIrSsaDemand>,
    _ssa_demand_resolutions: LaniusBuffer<u32>,
    _ssa_demand_resolution_tmp: LaniusBuffer<u32>,
    _ssa_block_argument_total: LaniusBuffer<u32>,
    _ssa_block_arguments: LaniusBuffer<OptIrBlockArgument>,
    _ssa_block_argument_incoming_total: LaniusBuffer<u32>,
    _ssa_block_argument_incoming: LaniusBuffer<OptIrBlockArgumentIncoming>,
    _ssa_block_argument_user_count: LaniusBuffer<u32>,
    _ssa_block_argument_user_prefix: LaniusBuffer<u32>,
    _ssa_block_argument_user_total: LaniusBuffer<u32>,
    _ssa_block_argument_user_arguments: LaniusBuffer<u32>,
    _ssa_block_argument_summary: LaniusBuffer<u32>,
    _ssa_block_argument_replacement: LaniusBuffer<u32>,
    value_count: LaniusBuffer<u32>,
    value_definitions: LaniusBuffer<OptIrValueDefinition>,
    value_by_block_argument: LaniusBuffer<u32>,
    _ssa_node_value_flag: LaniusBuffer<u32>,
    _ssa_node_value_total: LaniusBuffer<u32>,
    _ssa_block_argument_value_flag: LaniusBuffer<u32>,
    _ssa_surviving_block_argument_total: LaniusBuffer<u32>,
    _ssa_value_link_a: LaniusBuffer<u32>,
    _ssa_value_link_b: LaniusBuffer<u32>,
    _ssa_operands: LaniusBuffer<OptIrNodeOperands>,
    _ssa_call_argument_values: LaniusBuffer<u32>,
    _ssa_aggregate_element_values: LaniusBuffer<u32>,
    _ssa_incoming_values: LaniusBuffer<OptIrIncomingValue>,
    _ssa_node_use_count: LaniusBuffer<u32>,
    _ssa_node_use_total: LaniusBuffer<u32>,
    _ssa_call_use_flag: LaniusBuffer<u32>,
    _ssa_call_use_total: LaniusBuffer<u32>,
    _ssa_aggregate_use_flag: LaniusBuffer<u32>,
    _ssa_aggregate_use_total: LaniusBuffer<u32>,
    _ssa_use_total: LaniusBuffer<u32>,
    _ssa_use_values: LaniusBuffer<u32>,
    _ssa_use_users: LaniusBuffer<u32>,
    _ssa_use_order: LaniusBuffer<u32>,
    _ssa_use_group_start_flag: LaniusBuffer<u32>,
    _ssa_use_group_total: LaniusBuffer<u32>,
    _ssa_use_groups: LaniusBuffer<OptIrUseGroup>,
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
        let region_capacity = capacities.optimization_region_capacity();
        let access_capacity = capacities.optimization_access_capacity();
        let access_group_capacity = capacities.optimization_access_group_capacity();
        let declaration_block_capacity = capacities.optimization_declaration_block_capacity();
        let demand_capacity = capacities.optimization_ssa_demand_capacity();
        let incoming_capacity = capacities.optimization_ssa_incoming_capacity();
        let user_capacity = capacities.optimization_ssa_user_capacity();
        let ssa_sparse_capacity = capacities.optimization_ssa_sparse_capacity();
        let ssa_walk_capacity = capacities.optimization_ssa_walk_capacity();
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
        let blocks = workspace
            .alias(graph, resource("lir.opt.blocks")?, block_capacity as usize)
            .map_err(anyhow::Error::msg)?;
        let edge_count = workspace
            .alias(graph, resource("lir.opt.edge_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let edges = workspace
            .alias(graph, resource("lir.opt.edges")?, edge_capacity as usize)
            .map_err(anyhow::Error::msg)?;
        let predecessor_edge_ids = workspace
            .alias(
                graph,
                resource("lir.opt.predecessor_edge_ids")?,
                edge_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let reachable = workspace
            .alias(
                graph,
                resource("lir.opt.reachable")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dead_claim_by_block = workspace
            .alias(
                graph,
                resource("lir.opt.dead_claim_by_block")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let immediate_dominator = workspace
            .alias(
                graph,
                resource("lir.opt.immediate_dominator")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dominator_children = workspace
            .alias(
                graph,
                resource("lir.opt.dominator_children")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dominator_child_row_by_block = workspace
            .alias(
                graph,
                resource("lir.opt.dominator_child_row_by_block")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dominator_tour_arc_capacity = block_capacity.saturating_mul(2);
        let dominator_tour_link_a = workspace
            .alias(
                graph,
                resource("lir.opt.dominator_tour_link_a")?,
                dominator_tour_arc_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dominator_tour_link_b = workspace
            .alias(
                graph,
                resource("lir.opt.dominator_tour_link_b")?,
                dominator_tour_arc_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dominator_preorder = workspace
            .alias(
                graph,
                resource("lir.opt.dominator_preorder")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dominator_subtree_end = workspace
            .alias(
                graph,
                resource("lir.opt.dominator_subtree_end")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let block_by_dominator_preorder = workspace
            .alias(
                graph,
                resource("lir.opt.block_by_dominator_preorder")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dominator_depth_link_a = workspace
            .alias(
                graph,
                resource("lir.opt.dominator_depth_link_a")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dominator_depth_link_b = workspace
            .alias(
                graph,
                resource("lir.opt.dominator_depth_link_b")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dominator_depth = workspace
            .alias(
                graph,
                resource("lir.opt.dominator_depth")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let region_count = workspace
            .alias(graph, resource("lir.opt.region_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let regions = workspace
            .alias(
                graph,
                resource("lir.opt.regions")?,
                region_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let region_parent_link_a = workspace
            .alias(
                graph,
                resource("lir.opt.region_parent_link_a")?,
                region_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let region_parent_link_b = workspace
            .alias(
                graph,
                resource("lir.opt.region_parent_link_b")?,
                region_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let region_ownership_tree = workspace
            .alias(
                graph,
                resource("lir.opt.region_ownership_tree")?,
                capacities.semantic_instructions.max(1).saturating_mul(2) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let block_region = workspace
            .alias(
                graph,
                resource("lir.opt.block_region")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let functions = workspace
            .alias(
                graph,
                resource("lir.opt.functions")?,
                capacities.hir_nodes.max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let access_order = workspace
            .alias(
                graph,
                resource("lir.opt.access_order")?,
                access_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let access_groups = workspace
            .alias(
                graph,
                resource("lir.opt.access_groups")?,
                access_group_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let local_definition_by_access = workspace
            .alias(
                graph,
                resource("lir.opt.local_definition_by_access")?,
                access_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let declaration_blocks = workspace
            .alias(
                graph,
                resource("lir.opt.declaration_blocks")?,
                declaration_block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let reaching_definition_states = workspace
            .alias(
                graph,
                resource("lir.opt.reaching_definition_states")?,
                declaration_block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_demands = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.demands")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_demand_seed_total = workspace
            .alias(graph, resource("lir.opt.ssa.demand_seed_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_sparse_declaration = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.sparse_declaration")?,
                ssa_sparse_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_sparse_block = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.sparse_block")?,
                ssa_sparse_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_walk = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.walk")?,
                ssa_walk_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_demand_order = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.demand_order")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_canonical_demands_tmp = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.canonical_demands_tmp")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_demand_resolutions = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.demand_resolutions")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_demand_resolution_tmp = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.demand_resolution_tmp")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_total = workspace
            .alias(graph, resource("lir.opt.ssa.block_argument_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_block_arguments = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.block_arguments")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_incoming_total = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.block_argument_incoming_total")?,
                1,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_incoming = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.block_argument_incoming")?,
                incoming_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_user_count = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.block_argument_user_count")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_user_prefix = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.block_argument_user_prefix")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_user_total = workspace
            .alias(graph, resource("lir.opt.ssa.block_argument_user_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_user_arguments = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.block_argument_user_arguments")?,
                user_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_summary = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.block_argument_summary")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_replacement = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.block_argument_replacement")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_node_value_flag = workspace
            .alias(graph, resource("lir.opt.ssa.node_value_flag")?, rows)
            .map_err(anyhow::Error::msg)?;
        let ssa_node_value_total = workspace
            .alias(graph, resource("lir.opt.ssa.node_value_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_value_flag = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.block_argument_value_flag")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_surviving_block_argument_total = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.surviving_block_argument_total")?,
                1,
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
        let ssa_value_link_a = workspace
            .alias(graph, resource("lir.opt.ssa.value_link_a")?, rows)
            .map_err(anyhow::Error::msg)?;
        let ssa_value_link_b = workspace
            .alias(graph, resource("lir.opt.ssa.value_link_b")?, rows)
            .map_err(anyhow::Error::msg)?;
        let ssa_operands = workspace
            .alias(graph, resource("lir.opt.ssa.operands")?, rows)
            .map_err(anyhow::Error::msg)?;
        let ssa_call_argument_values = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.call_argument_values")?,
                capacities.call_arguments.max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_aggregate_element_values = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.aggregate_element_values")?,
                capacities.aggregate_elements.max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_incoming_values = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.incoming_values")?,
                incoming_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_node_use_count = workspace
            .alias(graph, resource("lir.opt.ssa.node_use_count")?, rows)
            .map_err(anyhow::Error::msg)?;
        let ssa_node_use_total = workspace
            .alias(graph, resource("lir.opt.ssa.node_use_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_call_use_flag = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.call_use_flag")?,
                capacities.call_arguments.max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_call_use_total = workspace
            .alias(graph, resource("lir.opt.ssa.call_use_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_aggregate_use_flag = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.aggregate_use_flag")?,
                capacities.aggregate_elements.max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_aggregate_use_total = workspace
            .alias(graph, resource("lir.opt.ssa.aggregate_use_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_use_total = workspace
            .alias(graph, resource("lir.opt.ssa.use_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_use_values = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.use_values")?,
                use_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_use_users = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.use_users")?,
                use_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_use_order = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.use_order")?,
                use_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_use_group_start_flag = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.use_group_start_flag")?,
                use_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_use_group_total = workspace
            .alias(graph, resource("lir.opt.ssa.use_group_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_use_groups = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.use_groups")?,
                value_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        semantic.execution_order.context(
            "target lowering graph omitted the semantic execution permutation required by OptIR",
        )?;

        let params = uniform_from_val(
            device,
            "lir.opt.project.params",
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
            .alias(graph, resource("step_program_sync")?, STEP_PROGRAM_SYNC_WORDS * OPTIMIZATION_PROGRAM_SLOTS)
            .map_err(anyhow::Error::msg)?;
        let program_groups_override = std::env::var("LANIUS_LIR_PROGRAM_GROUPS")
            .ok()
            .and_then(|value| value.parse().ok());
        let program_parallel_groups = program_groups_override.unwrap_or(STEP_PROGRAM_MAX_GROUPS);
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
                [variant(program_parallel_groups, 0)?, variant(program_parallel_groups, 1)?],
            ])
        };
        let control_flow = variants(
            &resources,
            "lir.opt.build_control_flow",
            "codegen/lir/optimization/control_flow/build_control_flow",
            0,
        )?;
        let control_flow_analysis = variants(
            &resources,
            "lir.opt.analyze_control_flow",
            "codegen/lir/optimization/analyze_control_flow",
            1,
        )?;
        resources.buffer("gParams", &access_params);
        let declaration_accesses = variants(
            &resources,
            "lir.opt.build_declaration_accesses",
            "codegen/lir/optimization/accesses/build_declaration_accesses",
            2,
        )?;
        resources.buffer("gParams", &ssa_params);
        let block_arguments = variants(
            &resources,
            "lir.opt.build_block_arguments",
            "codegen/lir/optimization/demands/build_block_arguments",
            3,
        )?;
        resources.buffer("gParams", &ssa_value_params);
        let ssa_values = variants(
            &resources,
            "lir.opt.build_ssa_values",
            "codegen/lir/optimization/build_ssa_values",
            4,
        )?;

        Ok(Self {
            control_flow,
            program_sync,
            capacities,
            program_groups_override,
            control_flow_analysis,
            declaration_accesses,
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
            _block_count: block_count,
            _blocks: blocks,
            _edge_count: edge_count,
            _edges: edges,
            _predecessor_edge_ids: predecessor_edge_ids,
            _reachable: reachable,
            _dead_claim_by_block: dead_claim_by_block,
            _immediate_dominator: immediate_dominator,
            _dominator_children: dominator_children,
            _dominator_child_row_by_block: dominator_child_row_by_block,
            _dominator_tour_link_a: dominator_tour_link_a,
            _dominator_tour_link_b: dominator_tour_link_b,
            _dominator_preorder: dominator_preorder,
            _dominator_subtree_end: dominator_subtree_end,
            _block_by_dominator_preorder: block_by_dominator_preorder,
            _dominator_depth_link_a: dominator_depth_link_a,
            _dominator_depth_link_b: dominator_depth_link_b,
            _dominator_depth: dominator_depth,
            _region_count: region_count,
            _regions: regions,
            _region_parent_link_a: region_parent_link_a,
            _region_parent_link_b: region_parent_link_b,
            _region_ownership_tree: region_ownership_tree,
            _block_region: block_region,
            _functions: functions,
            _access_order: access_order,
            _access_groups: access_groups,
            _local_definition_by_access: local_definition_by_access,
            _declaration_blocks: declaration_blocks,
            _reaching_definition_states: reaching_definition_states,
            _ssa_demands: ssa_demands,
            _ssa_demand_seed_total: ssa_demand_seed_total,
            _ssa_sparse_declaration: ssa_sparse_declaration,
            _ssa_sparse_block: ssa_sparse_block,
            _ssa_walk: ssa_walk,
            _ssa_demand_order: ssa_demand_order,
            _ssa_canonical_demands_tmp: ssa_canonical_demands_tmp,
            _ssa_demand_resolutions: ssa_demand_resolutions,
            _ssa_demand_resolution_tmp: ssa_demand_resolution_tmp,
            _ssa_block_argument_total: ssa_block_argument_total,
            _ssa_block_arguments: ssa_block_arguments,
            _ssa_block_argument_incoming_total: ssa_block_argument_incoming_total,
            _ssa_block_argument_incoming: ssa_block_argument_incoming,
            _ssa_block_argument_user_count: ssa_block_argument_user_count,
            _ssa_block_argument_user_prefix: ssa_block_argument_user_prefix,
            _ssa_block_argument_user_total: ssa_block_argument_user_total,
            _ssa_block_argument_user_arguments: ssa_block_argument_user_arguments,
            _ssa_block_argument_summary: ssa_block_argument_summary,
            _ssa_block_argument_replacement: ssa_block_argument_replacement,
            value_count,
            value_definitions,
            value_by_block_argument,
            _ssa_node_value_flag: ssa_node_value_flag,
            _ssa_node_value_total: ssa_node_value_total,
            _ssa_block_argument_value_flag: ssa_block_argument_value_flag,
            _ssa_surviving_block_argument_total: ssa_surviving_block_argument_total,
            _ssa_value_link_a: ssa_value_link_a,
            _ssa_value_link_b: ssa_value_link_b,
            _ssa_operands: ssa_operands,
            _ssa_call_argument_values: ssa_call_argument_values,
            _ssa_aggregate_element_values: ssa_aggregate_element_values,
            _ssa_incoming_values: ssa_incoming_values,
            _ssa_node_use_count: ssa_node_use_count,
            _ssa_node_use_total: ssa_node_use_total,
            _ssa_call_use_flag: ssa_call_use_flag,
            _ssa_call_use_total: ssa_call_use_total,
            _ssa_aggregate_use_flag: ssa_aggregate_use_flag,
            _ssa_aggregate_use_total: ssa_aggregate_use_total,
            _ssa_use_total: ssa_use_total,
            _ssa_use_values: ssa_use_values,
            _ssa_use_users: ssa_use_users,
            _ssa_use_order: ssa_use_order,
            _ssa_use_group_start_flag: ssa_use_group_start_flag,
            _ssa_use_group_total: ssa_use_group_total,
            _ssa_use_groups: ssa_use_groups,
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
    /// programs can be submitted with the earlier semantic lowering work.
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
        let rows = capacities.semantic_instructions.max(capacities.optimization_edge_capacity());
        let parallel = rows > 4096 || self.program_groups_override.is_some();
        self.control_flow[usize::from(parallel)][usize::from(validate_structure)].record(encoder)?;
        let analysis_rows = rows.max(capacities.semantic_instructions.saturating_mul(2));
        let analysis_parallel = analysis_rows > 4096 || self.program_groups_override.is_some();
        self.control_flow_analysis[usize::from(analysis_parallel)][usize::from(validate_structure)]
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
        let access_rows = capacities.optimization_access_capacity()
            .max(capacities.optimization_access_group_capacity());
        let access_parallel = access_rows > 4096 || self.program_groups_override.is_some();
        self.declaration_accesses[usize::from(access_parallel)][usize::from(validate_structure)]
            .record(encoder)?;
        let argument_rows = capacities.optimization_ssa_sparse_capacity()
            .max(capacities.optimization_ssa_incoming_capacity());
        let argument_parallel = argument_rows > 4096 || self.program_groups_override.is_some();
        self.block_arguments[usize::from(argument_parallel)][usize::from(validate_structure)]
            .record(encoder)?;
        let value_rows = capacities.optimization_value_capacity()
            .max(capacities.optimization_use_capacity());
        let value_parallel = value_rows > 4096 || self.program_groups_override.is_some();
        self.ssa_values[usize::from(value_parallel)][usize::from(validate_structure)]
            .record(encoder)?;
        Ok(())
    }

    pub(crate) fn program_sync(&self) -> &LaniusBuffer<u32> {
        &self.program_sync
    }

    pub(crate) fn output<'a>(&'a self, semantic: GpuSemanticLirView<'a>) -> GpuOptIrView<'a> {
        GpuOptIrView {
            block_count: &self._block_count,
            reachable: &self._reachable,
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
