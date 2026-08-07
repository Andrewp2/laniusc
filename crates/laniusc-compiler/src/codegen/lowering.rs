use anyhow::{Context, Result};
use encase::ShaderType;

#[cfg(test)]
use super::lowering_ir::semantic_lowering_compiler_graph;
use super::{
    lowering_ir::{
        LoweringCapacities,
        LoweringStatus,
        SemanticLirAggregateElement,
        SemanticLirCallArg,
        SemanticLirCore,
        SemanticLirFunction,
        SemanticLirLocal,
        SemanticLirOperands,
        SemanticLirParam,
        SemanticLirSchedule,
        SemanticLirString,
        TargetScheduleKey,
    },
    schedule::GpuStableScheduleSorter,
};
use crate::{
    gpu::{
        buffers::{LaniusBuffer, uniform_from_val},
        compiler_graph::{
            BoundGraphResource,
            CompilerGraph,
            CompilerGraphAllocations,
            CompilerGraphWorkspace,
            PassId,
            ResourceId,
        },
        passes_core::{
            DispatchDim,
            InputElements,
            PassData,
            bind_group,
            make_pass_data_from_shader_key,
            plan_workgroups,
        },
        resource_registry::ResourceMap,
        scan::{HierarchicalScanLevel, hierarchical_scan_levels},
    },
    parser::buffers::GpuHirView,
    type_checker::GpuSemanticArtifactView,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct SemanticProjectParams {
    n_tokens: u32,
    n_hir_nodes: u32,
    reserved0: u32,
    reserved1: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct SemanticCountParams {
    n_hir_nodes: u32,
    reserved0: u32,
    reserved1: u32,
    reserved2: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct SemanticScatterParams {
    n_hir_nodes: u32,
    lir_capacity: u32,
    n_tokens: u32,
    reserved1: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct SemanticCallArgParams {
    n_call_args: u32,
    n_hir_nodes: u32,
    lir_capacity: u32,
    reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct SemanticAggregateParams {
    element_capacity: u32,
    n_hir_nodes: u32,
    semantic_capacity: u32,
    n_tokens: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct SemanticStringParams {
    string_capacity: u32,
    word_capacity: u32,
    n_hir_nodes: u32,
    reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct SemanticFunctionParams {
    n_hir_nodes: u32,
    param_capacity: u32,
    n_tokens: u32,
    local_capacity: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct SemanticScheduleParams {
    semantic_capacity: u32,
    reserved0: u32,
    reserved1: u32,
    reserved2: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(super) struct ScanParams {
    pub(super) n_items: u32,
    pub(super) n_blocks: u32,
    pub(super) scan_step: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(super) struct ScanHierarchyParams {
    pub(super) n_items: u32,
    pub(super) n_blocks: u32,
    pub(super) level_divisor: u32,
    pub(super) level_offset: u32,
    pub(super) parent_divisor: u32,
    pub(super) parent_offset: u32,
}

struct SemanticPasses {
    status_clear: PassData,
    project: PassData,
    execution_rank_init: PassData,
    execution_rank_step: PassData,
    count: PassData,
    scan_local: PassData,
    scan_up: PassData,
    scan_down: PassData,
    scan_apply: PassData,
    scatter: PassData,
    schedule_init: PassData,
    call_args: PassData,
    aggregate_elements: PassData,
    strings: PassData,
    function_mark: PassData,
    function_layout_clear: PassData,
    function_layout_collect: PassData,
    function_layout_words: PassData,
    function_scatter: PassData,
    function_params: PassData,
    local_mark: PassData,
    local_scatter: PassData,
}

impl SemanticPasses {
    fn new(device: &wgpu::Device) -> Result<Self> {
        let load = |label: &str, shader: &str| {
            make_pass_data_from_shader_key(device, label, "main", shader)
        };
        Ok(Self {
            status_clear: load("lir.status.clear", "codegen/lir/status_clear")?,
            project: load("lir.semantic.project", "codegen/lir/semantic/project")?,
            execution_rank_init: load(
                "lir.semantic.execution_rank.init",
                "codegen/lir/semantic/execution_rank_init",
            )?,
            execution_rank_step: load(
                "lir.semantic.execution_rank.step",
                "codegen/lir/semantic/execution_rank_step",
            )?,
            count: load("lir.semantic.count", "codegen/lir/semantic/count")?,
            scan_local: load("lir.semantic.scan.local", "scan/counted/00_local")?,
            scan_up: load(
                "lir.semantic.scan.hierarchy_up",
                "scan/counted/01_hierarchy_up",
            )?,
            scan_down: load(
                "lir.semantic.scan.hierarchy_down",
                "scan/counted/02_hierarchy_down",
            )?,
            scan_apply: load("lir.semantic.scan.apply", "scan/counted/02_apply")?,
            scatter: load("lir.semantic.scatter", "codegen/lir/semantic/scatter")?,
            schedule_init: load(
                "lir.semantic.schedule.init",
                "codegen/lir/semantic/schedule_init",
            )?,
            call_args: load("lir.semantic.call_args", "codegen/lir/semantic/call_args")?,
            aggregate_elements: load(
                "lir.semantic.aggregate_elements",
                "codegen/lir/semantic/aggregate_elements",
            )?,
            strings: load("lir.semantic.strings", "codegen/lir/semantic/strings")?,
            function_mark: load(
                "lir.semantic.functions.mark",
                "codegen/lir/semantic/function_mark",
            )?,
            function_layout_clear: load(
                "lir.semantic.functions.layout.clear",
                "codegen/lir/semantic/function_layout_clear",
            )?,
            function_layout_collect: load(
                "lir.semantic.functions.layout.collect",
                "codegen/lir/semantic/function_layout_collect",
            )?,
            function_layout_words: load(
                "lir.semantic.functions.layout.words",
                "codegen/lir/semantic/function_layout_words",
            )?,
            function_scatter: load(
                "lir.semantic.functions.scatter",
                "codegen/lir/semantic/function_scatter",
            )?,
            function_params: load(
                "lir.semantic.functions.params",
                "codegen/lir/semantic/function_params",
            )?,
            local_mark: load(
                "lir.semantic.locals.mark",
                "codegen/lir/semantic/local_mark",
            )?,
            local_scatter: load(
                "lir.semantic.locals.scatter",
                "codegen/lir/semantic/local_scatter",
            )?,
        })
    }
}

#[derive(Clone, Copy)]
pub(crate) struct GpuSemanticLirView<'a> {
    pub count: &'a LaniusBuffer<u32>,
    pub core: &'a LaniusBuffer<SemanticLirCore>,
    pub operands: &'a LaniusBuffer<SemanticLirOperands>,
    pub layout_word_offset: &'a LaniusBuffer<u32>,
    pub owner_by_instruction: &'a LaniusBuffer<u32>,
    pub op_by_instruction: &'a LaniusBuffer<u32>,
    pub function_id_by_hir: &'a LaniusBuffer<u32>,
    pub call_args: &'a LaniusBuffer<SemanticLirCallArg>,
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
    pub param_count: &'a LaniusBuffer<u32>,
    pub locals: &'a LaniusBuffer<SemanticLirLocal>,
    pub local_count: &'a LaniusBuffer<u32>,
    pub execution_order: Option<&'a LaniusBuffer<u32>>,
    pub status: &'a LaniusBuffer<LoweringStatus>,
}

impl<'a> GpuSemanticLirView<'a> {
    /// Registers the concrete semantic artifact imported by target lowering.
    /// Each logical graph resource and all of its reflected shader names are
    /// rebound together, preserving one ownership source of truth.
    pub(super) fn register(
        self,
        graph: &CompilerGraph,
        resources: &mut crate::gpu::resource_registry::ResourceMap<'a>,
    ) -> Result<()> {
        macro_rules! buffer {
            ($name:literal, $value:expr) => {
                resources.graph_buffer(graph, $name, $value)?
            };
        }
        buffer!("lir.semantic.total", self.count);
        buffer!("lir.semantic.core", self.core);
        buffer!("lir.semantic.operands", self.operands);
        buffer!("lir.semantic.layout_word_offset", self.layout_word_offset);
        buffer!(
            "lir.semantic.owner_by_instruction",
            self.owner_by_instruction
        );
        buffer!("lir.semantic.op_by_instruction", self.op_by_instruction);
        buffer!("semantic.function_ids", self.function_id_by_hir);
        buffer!("lir.semantic.call_args", self.call_args);
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

/// Creates the physical ownership scope for a target-lowering stage. Semantic
/// artifacts are explicit imports at this boundary; target scratch and outputs
/// retain the graph workspace's allocation identities.
pub(super) fn target_lowering_allocations(
    graph: &CompilerGraph,
    workspace: &CompilerGraphWorkspace,
    semantic: GpuSemanticLirView<'_>,
) -> Result<CompilerGraphAllocations> {
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
    import!("lir.semantic.total", semantic.count);
    import!("lir.semantic.core", semantic.core);
    import!("lir.semantic.operands", semantic.operands);
    import!(
        "lir.semantic.layout_word_offset",
        semantic.layout_word_offset
    );
    import!(
        "lir.semantic.owner_by_instruction",
        semantic.owner_by_instruction
    );
    import!("lir.semantic.op_by_instruction", semantic.op_by_instruction);
    import!("semantic.function_ids", semantic.function_id_by_hir);
    import!("lir.semantic.call_args", semantic.call_args);
    import!(
        "lir.semantic.call_arg_prefix_by_hir",
        semantic.call_arg_start_by_hir
    );
    import!(
        "lir.semantic.call_arg_counts_by_hir",
        semantic.call_arg_count_by_hir
    );
    import!(
        "lir.semantic.aggregate_elements",
        semantic.aggregate_elements
    );
    import!(
        "lir.semantic.aggregate_element_total",
        semantic.aggregate_element_count
    );
    import!("lir.semantic.strings", semantic.strings);
    import!("lir.semantic.string_total", semantic.string_count);
    import!("lir.semantic.string_data", semantic.string_data_words);
    import!("lir.semantic.string_pool_len", semantic.string_pool_len);
    import!("lir.semantic.functions", semantic.functions);
    import!("lir.semantic.function_total", semantic.function_count);
    import!("lir.semantic.params", semantic.params);
    import!("lir.semantic.param_total", semantic.param_count);
    import!("lir.semantic.locals", semantic.locals);
    import!("lir.semantic.local_total", semantic.local_count);
    Ok(allocations)
}

#[derive(Clone, Copy)]
pub(crate) struct GpuSemanticHirInputs<'a> {
    pub count: &'a LaniusBuffer<u32>,
    pub core: &'a LaniusBuffer<crate::parser::buffers::HirCore>,
    pub links: &'a LaniusBuffer<crate::parser::buffers::HirLinks>,
    pub payload: &'a LaniusBuffer<crate::parser::buffers::HirPayload>,
    pub const_value: &'a LaniusBuffer<u32>,
    pub expr_parent: &'a LaniusBuffer<u32>,
    pub expr_root: &'a LaniusBuffer<u32>,
    pub nearest_loop: &'a LaniusBuffer<u32>,
    pub call_arg_count: &'a LaniusBuffer<u32>,
    pub call_args: &'a LaniusBuffer<crate::parser::buffers::HirCallArg>,
    pub field_count: &'a LaniusBuffer<u32>,
    pub fields: &'a LaniusBuffer<crate::parser::buffers::HirField>,
    pub array_element_start: &'a LaniusBuffer<u32>,
    pub array_element_count: &'a LaniusBuffer<u32>,
    pub array_element_row_count: &'a LaniusBuffer<u32>,
    pub array_elements: &'a LaniusBuffer<crate::parser::buffers::HirArrayElement>,
    pub string_count: &'a LaniusBuffer<u32>,
    pub strings: &'a LaniusBuffer<crate::parser::buffers::HirString>,
    pub string_data_words: &'a LaniusBuffer<u32>,
    pub string_pool_len: &'a LaniusBuffer<u32>,
    pub param_count: &'a LaniusBuffer<u32>,
    pub params: &'a LaniusBuffer<crate::parser::buffers::HirParam>,
    pub param_ranges: &'a LaniusBuffer<crate::parser::buffers::HirRange>,
    pub method_count: &'a LaniusBuffer<u32>,
    pub method_cores: &'a LaniusBuffer<crate::parser::buffers::HirMethodCore>,
    pub method_signatures: &'a LaniusBuffer<crate::parser::buffers::HirMethodSignature>,
}

impl<'a> From<&'a GpuHirView> for GpuSemanticHirInputs<'a> {
    fn from(hir: &'a GpuHirView) -> Self {
        Self {
            count: &hir.count,
            core: &hir.core,
            links: &hir.links,
            payload: &hir.payload,
            const_value: &hir.const_value,
            expr_parent: &hir.expr_parent,
            expr_root: &hir.expr_root,
            nearest_loop: &hir.nearest_loop,
            call_arg_count: &hir.call_arg_count,
            call_args: &hir.call_args,
            field_count: &hir.field_count,
            fields: &hir.fields,
            array_element_start: &hir.array_element_start,
            array_element_count: &hir.array_element_count,
            array_element_row_count: &hir.array_element_row_count,
            array_elements: &hir.array_elements,
            string_count: &hir.string_count,
            strings: &hir.strings,
            string_data_words: &hir.string_data_words,
            string_pool_len: &hir.string_pool_len,
            param_count: &hir.param_count,
            params: &hir.params,
            param_ranges: &hir.param_ranges,
            method_count: &hir.method_count,
            method_cores: &hir.method_cores,
            method_signatures: &hir.method_signatures,
        }
    }
}

#[derive(Clone, Copy)]
enum SemanticScanFamily {
    Instructions,
    Functions,
    Locals,
    CallArguments,
}

/// Executable compact-HIR to target-independent LIR stage. Pipelines,
/// uniforms, physical workspace slots, and output aliases are all created by
/// `new`; `record` performs no pipeline or buffer allocation.
pub(crate) struct GpuSemanticLoweringStage {
    capacities: LoweringCapacities,
    graph: CompilerGraph,
    allocations: CompilerGraphAllocations,
    passes: SemanticPasses,
    project_params: LaniusBuffer<SemanticProjectParams>,
    count_params: LaniusBuffer<SemanticCountParams>,
    scatter_params: LaniusBuffer<SemanticScatterParams>,
    call_arg_params: LaniusBuffer<SemanticCallArgParams>,
    aggregate_params: LaniusBuffer<SemanticAggregateParams>,
    string_params: LaniusBuffer<SemanticStringParams>,
    function_params: LaniusBuffer<SemanticFunctionParams>,
    scan_params: LaniusBuffer<ScanParams>,
    scan_hierarchy_params: Vec<LaniusBuffer<ScanHierarchyParams>>,
    scan_levels: Vec<HierarchicalScanLevel>,
    execution_rank_pairs: u32,
    execution_rank_link_a: LaniusBuffer<u32>,
    execution_rank_a: LaniusBuffer<u32>,
    execution_rank_link_b: LaniusBuffer<u32>,
    execution_rank_b: LaniusBuffer<u32>,
    value_ids: LaniusBuffer<u32>,
    value_types: LaniusBuffer<u32>,
    call_targets: LaniusBuffer<u32>,
    call_kinds: LaniusBuffer<u32>,
    call_result_types: LaniusBuffer<u32>,
    call_receivers: LaniusBuffer<u32>,
    call_arg_counts_by_hir: LaniusBuffer<u32>,
    call_arg_prefix_by_hir: LaniusBuffer<u32>,
    call_arg_scan_local: LaniusBuffer<u32>,
    call_arg_scan_block_sum: LaniusBuffer<u32>,
    call_arg_scan_block_prefix: LaniusBuffer<u32>,
    call_arg_scan_hierarchy: LaniusBuffer<u32>,
    function_ids: LaniusBuffer<u32>,
    function_flags: LaniusBuffer<u32>,
    function_prefix: LaniusBuffer<u32>,
    function_id_by_token: LaniusBuffer<u32>,
    const_function_by_root: LaniusBuffer<u32>,
    struct_hir_by_name_token: LaniusBuffer<u32>,
    struct_field_count_by_hir: LaniusBuffer<u32>,
    struct_field_start_by_hir: LaniusBuffer<u32>,
    struct_word_count_by_hir: LaniusBuffer<u32>,
    struct_field_word_offset_by_row: LaniusBuffer<u32>,
    struct_field_word_count_by_row: LaniusBuffer<u32>,
    function_count: LaniusBuffer<u32>,
    function_scan_local: LaniusBuffer<u32>,
    function_scan_block_sum: LaniusBuffer<u32>,
    function_scan_block_prefix: LaniusBuffer<u32>,
    function_scan_hierarchy: LaniusBuffer<u32>,
    local_flags: LaniusBuffer<u32>,
    local_prefix: LaniusBuffer<u32>,
    local_count: LaniusBuffer<u32>,
    local_scan_local: LaniusBuffer<u32>,
    local_scan_block_sum: LaniusBuffer<u32>,
    local_scan_block_prefix: LaniusBuffer<u32>,
    local_scan_hierarchy: LaniusBuffer<u32>,
    counts: LaniusBuffer<u32>,
    offsets: LaniusBuffer<u32>,
    scan_local: LaniusBuffer<u32>,
    scan_block_sum: LaniusBuffer<u32>,
    scan_block_prefix: LaniusBuffer<u32>,
    scan_hierarchy: LaniusBuffer<u32>,
    total: LaniusBuffer<u32>,
    core: LaniusBuffer<SemanticLirCore>,
    operands: LaniusBuffer<SemanticLirOperands>,
    layout_word_offset: LaniusBuffer<u32>,
    owner_by_instruction: LaniusBuffer<u32>,
    op_by_instruction: LaniusBuffer<u32>,
    schedule: LaniusBuffer<SemanticLirSchedule>,
    semantic_schedule_group: Option<wgpu::BindGroup>,
    semantic_sorter: Option<GpuStableScheduleSorter>,
    call_args: LaniusBuffer<SemanticLirCallArg>,
    call_arg_count: LaniusBuffer<u32>,
    aggregate_elements: LaniusBuffer<SemanticLirAggregateElement>,
    aggregate_element_count: LaniusBuffer<u32>,
    strings: LaniusBuffer<SemanticLirString>,
    string_count: LaniusBuffer<u32>,
    string_data_words: LaniusBuffer<u32>,
    string_pool_len: LaniusBuffer<u32>,
    functions: LaniusBuffer<SemanticLirFunction>,
    params: LaniusBuffer<SemanticLirParam>,
    param_count: LaniusBuffer<u32>,
    locals: LaniusBuffer<SemanticLirLocal>,
    status: LaniusBuffer<LoweringStatus>,
    call_symbol_library_ids: LaniusBuffer<u32>,
    call_symbol_unit_ids: LaniusBuffer<u32>,
    call_symbol_local_indices: LaniusBuffer<u32>,
}

impl GpuSemanticLoweringStage {
    #[cfg(test)]
    pub(crate) fn new(device: &wgpu::Device, capacities: LoweringCapacities) -> Result<Self> {
        let graph = semantic_lowering_compiler_graph(capacities).map_err(anyhow::Error::msg)?;
        let workspace = CompilerGraphWorkspace::new(device, "codegen.lir", &graph)
            .map_err(anyhow::Error::msg)?;
        Self::from_workspace(device, capacities, graph, &workspace)
    }

    pub(crate) fn from_workspace(
        device: &wgpu::Device,
        capacities: LoweringCapacities,
        graph: CompilerGraph,
        workspace: &CompilerGraphWorkspace,
    ) -> Result<Self> {
        let resource = |name: &str| -> Result<ResourceId> {
            graph
                .resource_id(name)
                .with_context(|| format!("lowering graph is missing {name}"))
        };
        let alias = |name: &str, count: u32| -> Result<LaniusBuffer<u32>> {
            workspace
                .alias(&graph, resource(name)?, count.max(1) as usize)
                .map_err(anyhow::Error::msg)
        };
        let hir_nodes = capacities.hir_nodes.max(1);
        let blocks = hir_nodes.div_ceil(256).max(1);
        let scan_levels = hierarchical_scan_levels(blocks);
        let scan_hierarchy_params = scan_levels
            .iter()
            .enumerate()
            .map(|(index, level)| {
                let parent = scan_levels.get(index + 1);
                uniform_from_val(
                    device,
                    &format!("lir.semantic.scan.hierarchy.{index}"),
                    &ScanHierarchyParams {
                        n_items: hir_nodes,
                        n_blocks: blocks,
                        level_divisor: level.divisor,
                        level_offset: level.offset,
                        parent_divisor: parent.map_or(0, |parent| parent.divisor),
                        parent_offset: parent.map_or(0, |parent| parent.offset),
                    },
                )
            })
            .collect();

        let semantic_resident_rows = capacities.semantic_instructions.max(1);
        let core = workspace
            .alias(
                &graph,
                resource("lir.semantic.core")?,
                semantic_resident_rows as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let operands = workspace
            .alias(
                &graph,
                resource("lir.semantic.operands")?,
                semantic_resident_rows as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let layout_word_offset = alias("lir.semantic.layout_word_offset", semantic_resident_rows)?;
        let owner_by_instruction = alias(
            "lir.semantic.owner_by_instruction",
            capacities.semantic_instructions,
        )?;
        let op_by_instruction = alias(
            "lir.semantic.op_by_instruction",
            capacities.semantic_instructions,
        )?;
        let schedule = workspace
            .alias(
                &graph,
                resource("lir.semantic.schedule")?,
                capacities.semantic_instructions.max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let call_args = workspace
            .alias(
                &graph,
                resource("lir.semantic.call_args")?,
                capacities.call_arguments.max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let call_arg_count = alias("lir.semantic.call_arg_total", 1)?;
        let aggregate_elements = workspace
            .alias(
                &graph,
                resource("lir.semantic.aggregate_elements")?,
                capacities.aggregate_elements.saturating_mul(2).max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let aggregate_element_count = alias("lir.semantic.aggregate_element_total", 1)?;
        let strings = workspace
            .alias(
                &graph,
                resource("lir.semantic.strings")?,
                capacities.hir_nodes.max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let string_count = alias("lir.semantic.string_total", 1)?;
        let string_data_words = alias(
            "lir.semantic.string_data",
            capacities.source_bytes.max(4).div_ceil(4),
        )?;
        let string_pool_len = alias("lir.semantic.string_pool_len", 1)?;
        let functions = workspace
            .alias(
                &graph,
                resource("lir.semantic.functions")?,
                capacities.hir_nodes.max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let params = workspace
            .alias(
                &graph,
                resource("lir.semantic.params")?,
                capacities.parameters.max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let param_count = alias("lir.semantic.param_total", 1)?;
        let function_count = alias("lir.semantic.function_total", 1)?;
        let locals = workspace
            .alias(
                &graph,
                resource("lir.semantic.locals")?,
                capacities.hir_nodes.max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let local_count = alias("lir.semantic.local_total", 1)?;
        let status = workspace
            .alias(&graph, resource("lowering.status")?, 1)
            .map_err(anyhow::Error::msg)?;
        let value_ids = alias("semantic.value_ids", hir_nodes)?;
        let value_types = alias("semantic.value_types", hir_nodes)?;
        let call_targets = alias("semantic.call_targets", hir_nodes)?;
        let call_kinds = alias("semantic.call_kinds", hir_nodes)?;
        let call_result_types = alias("semantic.call_result_types", hir_nodes)?;
        let call_receivers = alias("semantic.call_receivers", hir_nodes)?;
        let call_symbol_library_ids = alias("semantic.call_symbol_library_ids", hir_nodes)?;
        let call_symbol_unit_ids = alias("semantic.call_symbol_unit_ids", hir_nodes)?;
        let call_symbol_local_indices = alias("semantic.call_symbol_local_indices", hir_nodes)?;
        let call_arg_counts_by_hir = alias("lir.semantic.call_arg_counts_by_hir", hir_nodes)?;
        let call_arg_prefix_by_hir = alias("lir.semantic.call_arg_prefix_by_hir", hir_nodes)?;
        let call_arg_scan_local = alias("lir.semantic.call_arg_scan_local", hir_nodes)?;
        let call_arg_scan_block_sum = alias("lir.semantic.call_arg_scan_block_sum", blocks)?;
        let call_arg_scan_block_prefix = alias("lir.semantic.call_arg_scan_block_prefix", blocks)?;
        let call_arg_scan_hierarchy = alias("lir.semantic.call_arg_scan_hierarchy", blocks)?;
        let function_ids = alias("semantic.function_ids", hir_nodes)?;
        let function_flags = alias("lir.semantic.function_flags", hir_nodes)?;
        let function_prefix = alias("lir.semantic.function_prefix", hir_nodes)?;
        let function_id_by_token = alias(
            "lir.semantic.function_id_by_token",
            capacities.tokens.max(1),
        )?;
        let const_function_by_root = alias("lir.semantic.const_function_by_root", hir_nodes)?;
        let struct_hir_by_name_token = alias(
            "lir.semantic.struct_hir_by_name_token",
            capacities.tokens.max(1),
        )?;
        let struct_field_count_by_hir = alias("lir.semantic.struct_field_count_by_hir", hir_nodes)?;
        let struct_field_start_by_hir = alias("lir.semantic.struct_field_start_by_hir", hir_nodes)?;
        let struct_word_count_by_hir = alias("lir.semantic.struct_word_count_by_hir", hir_nodes)?;
        let struct_field_word_offset_by_row =
            alias("lir.semantic.struct_field_word_offset_by_row", hir_nodes)?;
        let struct_field_word_count_by_row =
            alias("lir.semantic.struct_field_word_count_by_row", hir_nodes)?;
        let function_scan_local = alias("lir.semantic.function_scan_local", hir_nodes)?;
        let function_scan_block_sum = alias("lir.semantic.function_scan_block_sum", blocks)?;
        let function_scan_block_prefix = alias("lir.semantic.function_scan_block_prefix", blocks)?;
        let function_scan_hierarchy = alias("lir.semantic.function_scan_hierarchy", blocks)?;
        let local_flags = alias("lir.semantic.local_flags", hir_nodes)?;
        let local_prefix = alias("lir.semantic.local_prefix", hir_nodes)?;
        let local_scan_local = alias("lir.semantic.local_scan_local", hir_nodes)?;
        let local_scan_block_sum = alias("lir.semantic.local_scan_block_sum", blocks)?;
        let local_scan_block_prefix = alias("lir.semantic.local_scan_block_prefix", blocks)?;
        let local_scan_hierarchy = alias("lir.semantic.local_scan_hierarchy", blocks)?;
        let execution_rank_link_a = alias("lir.semantic.execution_rank_link_a", hir_nodes)?;
        let execution_rank_a = alias("lir.semantic.execution_rank_a", hir_nodes)?;
        let execution_rank_link_b = alias("lir.semantic.execution_rank_link_b", hir_nodes)?;
        let execution_rank_b = alias("lir.semantic.execution_rank_b", hir_nodes)?;
        let counts = alias("lir.semantic.count_by_hir", hir_nodes)?;
        let offsets = alias("lir.semantic.offset_by_hir", hir_nodes)?;
        let scan_local = alias("lir.semantic.scan_local", hir_nodes)?;
        let scan_block_sum = alias("lir.semantic.scan_block_sum", blocks)?;
        let scan_block_prefix = alias("lir.semantic.scan_block_prefix", blocks)?;
        let scan_hierarchy = alias("lir.semantic.scan_hierarchy", blocks)?;
        let total = alias("lir.semantic.total", 1)?;
        let passes = SemanticPasses::new(device)?;
        let allocations = workspace.allocations();
        for (name, reflection) in [
            ("lir.status.clear", passes.status_clear.reflection.as_ref()),
            ("lir.semantic.project", passes.project.reflection.as_ref()),
            (
                "lir.semantic.call_arg_scan.local",
                passes.scan_local.reflection.as_ref(),
            ),
            (
                "lir.semantic.call_arg_scan.hierarchy_up",
                passes.scan_up.reflection.as_ref(),
            ),
            (
                "lir.semantic.call_arg_scan.hierarchy_down",
                passes.scan_down.reflection.as_ref(),
            ),
            (
                "lir.semantic.call_arg_scan.apply",
                passes.scan_apply.reflection.as_ref(),
            ),
            (
                "lir.semantic.execution_rank.init",
                passes.execution_rank_init.reflection.as_ref(),
            ),
            (
                "lir.semantic.execution_rank.step_a_to_b",
                passes.execution_rank_step.reflection.as_ref(),
            ),
            (
                "lir.semantic.execution_rank.step_b_to_a",
                passes.execution_rank_step.reflection.as_ref(),
            ),
            ("lir.semantic.count", passes.count.reflection.as_ref()),
            (
                "lir.semantic.scan.local",
                passes.scan_local.reflection.as_ref(),
            ),
            (
                "lir.semantic.scan.hierarchy_up",
                passes.scan_up.reflection.as_ref(),
            ),
            (
                "lir.semantic.scan.hierarchy_down",
                passes.scan_down.reflection.as_ref(),
            ),
            (
                "lir.semantic.scan.apply",
                passes.scan_apply.reflection.as_ref(),
            ),
            ("lir.semantic.scatter", passes.scatter.reflection.as_ref()),
            (
                "lir.semantic.call_args",
                passes.call_args.reflection.as_ref(),
            ),
            (
                "lir.semantic.aggregate_elements",
                passes.aggregate_elements.reflection.as_ref(),
            ),
            ("lir.semantic.strings", passes.strings.reflection.as_ref()),
            (
                "lir.semantic.functions.mark",
                passes.function_mark.reflection.as_ref(),
            ),
            (
                "lir.semantic.functions.layout.clear",
                passes.function_layout_clear.reflection.as_ref(),
            ),
            (
                "lir.semantic.functions.layout.collect",
                passes.function_layout_collect.reflection.as_ref(),
            ),
            (
                "lir.semantic.functions.layout.words",
                passes.function_layout_words.reflection.as_ref(),
            ),
            (
                "lir.semantic.function_scan.local",
                passes.scan_local.reflection.as_ref(),
            ),
            (
                "lir.semantic.function_scan.hierarchy_up",
                passes.scan_up.reflection.as_ref(),
            ),
            (
                "lir.semantic.function_scan.hierarchy_down",
                passes.scan_down.reflection.as_ref(),
            ),
            (
                "lir.semantic.function_scan.apply",
                passes.scan_apply.reflection.as_ref(),
            ),
            (
                "lir.semantic.functions.scatter",
                passes.function_scatter.reflection.as_ref(),
            ),
            (
                "lir.semantic.functions.params",
                passes.function_params.reflection.as_ref(),
            ),
            (
                "lir.semantic.locals.mark",
                passes.local_mark.reflection.as_ref(),
            ),
            (
                "lir.semantic.local_scan.local",
                passes.scan_local.reflection.as_ref(),
            ),
            (
                "lir.semantic.local_scan.hierarchy_up",
                passes.scan_up.reflection.as_ref(),
            ),
            (
                "lir.semantic.local_scan.hierarchy_down",
                passes.scan_down.reflection.as_ref(),
            ),
            (
                "lir.semantic.local_scan.apply",
                passes.scan_apply.reflection.as_ref(),
            ),
            (
                "lir.semantic.locals.scatter",
                passes.local_scatter.reflection.as_ref(),
            ),
        ] {
            graph
                .validate_pass_reflection(graph.pass_id(name).unwrap(), reflection)
                .map_err(anyhow::Error::msg)?;
        }

        let schedule_order_resource = if graph.resource_id("lir.semantic.schedule_order").is_some()
        {
            Some("lir.semantic.schedule_order")
        } else {
            None
        };
        let (semantic_schedule_group, semantic_sorter) =
            if let Some(order_name) = schedule_order_resource {
                let keys = schedule
                    .alias::<TargetScheduleKey>(capacities.semantic_instructions.max(1) as usize);
                let order = workspace
                    .alias(
                        &graph,
                        resource(order_name)?,
                        capacities.semantic_instructions.max(1) as usize,
                    )
                    .map_err(anyhow::Error::msg)?;
                let params = uniform_from_val(
                    device,
                    "lir.semantic.schedule.init.params",
                    &SemanticScheduleParams {
                        semantic_capacity: capacities.semantic_instructions.max(1),
                        reserved0: 0,
                        reserved1: 0,
                        reserved2: 0,
                    },
                );
                graph
                    .validate_pass_reflection(
                        graph.pass_id("lir.semantic.schedule.init").unwrap(),
                        passes.schedule_init.reflection.as_ref(),
                    )
                    .map_err(anyhow::Error::msg)?;
                allocations
                    .validate_pass_bindings(
                        &graph,
                        graph.pass_id("lir.semantic.schedule.init").unwrap(),
                        &[
                            bound(
                                "semantic_lir_total",
                                resource("lir.semantic.total")?,
                                &total,
                            )?,
                            bound("target_schedule_order", resource(order_name)?, &order)?,
                        ],
                    )
                    .map_err(anyhow::Error::msg)?;
                let group = make_group(
                    device,
                    &passes.schedule_init,
                    "lir.semantic.schedule.init.bind_group",
                    &[
                        ("gParams", params.as_entire_binding()),
                        ("semantic_lir_total", total.as_entire_binding()),
                        ("target_schedule_order", order.as_entire_binding()),
                    ],
                )?;
                let sorter = GpuStableScheduleSorter::new_semantic(
                    device,
                    &graph,
                    workspace,
                    &allocations,
                    capacities.semantic_instructions.max(1),
                    &total,
                    &keys,
                    &order,
                )?;
                (Some(group), Some(sorter))
            } else {
                (None, None)
            };

        Ok(Self {
            capacities,
            graph,
            allocations,
            passes,
            project_params: uniform_from_val(
                device,
                "lir.semantic.project.params",
                &SemanticProjectParams {
                    n_tokens: capacities.tokens,
                    n_hir_nodes: hir_nodes,
                    reserved0: 0,
                    reserved1: 0,
                },
            ),
            count_params: uniform_from_val(
                device,
                "lir.semantic.count.params",
                &SemanticCountParams {
                    n_hir_nodes: hir_nodes,
                    reserved0: 0,
                    reserved1: 0,
                    reserved2: 0,
                },
            ),
            scatter_params: uniform_from_val(
                device,
                "lir.semantic.scatter.params",
                &SemanticScatterParams {
                    n_hir_nodes: hir_nodes,
                    lir_capacity: capacities.semantic_instructions.max(1),
                    n_tokens: capacities.tokens,
                    reserved1: semantic_resident_rows,
                },
            ),
            call_arg_params: uniform_from_val(
                device,
                "lir.semantic.call_args.params",
                &SemanticCallArgParams {
                    n_call_args: capacities.call_arguments,
                    n_hir_nodes: hir_nodes,
                    lir_capacity: capacities.semantic_instructions.max(1),
                    reserved: 0,
                },
            ),
            aggregate_params: uniform_from_val(
                device,
                "lir.semantic.aggregate_elements.params",
                &SemanticAggregateParams {
                    element_capacity: capacities.aggregate_elements,
                    n_hir_nodes: hir_nodes,
                    semantic_capacity: capacities.semantic_instructions.max(1),
                    n_tokens: capacities.tokens,
                },
            ),
            string_params: uniform_from_val(
                device,
                "lir.semantic.strings.params",
                &SemanticStringParams {
                    string_capacity: hir_nodes,
                    word_capacity: capacities.source_bytes.max(4).div_ceil(4),
                    n_hir_nodes: hir_nodes,
                    reserved: 0,
                },
            ),
            function_params: uniform_from_val(
                device,
                "lir.semantic.functions.params",
                &SemanticFunctionParams {
                    n_hir_nodes: hir_nodes,
                    param_capacity: capacities.parameters,
                    n_tokens: capacities.tokens,
                    local_capacity: capacities.hir_nodes.max(1),
                },
            ),
            scan_params: uniform_from_val(
                device,
                "lir.semantic.scan.params",
                &ScanParams {
                    n_items: hir_nodes,
                    n_blocks: blocks,
                    scan_step: 0,
                },
            ),
            scan_hierarchy_params,
            scan_levels,
            execution_rank_pairs: (u32::BITS - hir_nodes.leading_zeros()).max(1).div_ceil(2),
            execution_rank_link_a,
            execution_rank_a,
            execution_rank_link_b,
            execution_rank_b,
            value_ids,
            value_types,
            call_targets,
            call_kinds,
            call_result_types,
            call_receivers,
            call_symbol_library_ids,
            call_symbol_unit_ids,
            call_symbol_local_indices,
            call_arg_counts_by_hir,
            call_arg_prefix_by_hir,
            call_arg_scan_local,
            call_arg_scan_block_sum,
            call_arg_scan_block_prefix,
            call_arg_scan_hierarchy,
            function_ids,
            function_flags,
            function_prefix,
            function_id_by_token,
            const_function_by_root,
            struct_hir_by_name_token,
            struct_field_count_by_hir,
            struct_field_start_by_hir,
            struct_word_count_by_hir,
            struct_field_word_offset_by_row,
            struct_field_word_count_by_row,
            function_count,
            function_scan_local,
            function_scan_block_sum,
            function_scan_block_prefix,
            function_scan_hierarchy,
            local_flags,
            local_prefix,
            local_count,
            local_scan_local,
            local_scan_block_sum,
            local_scan_block_prefix,
            local_scan_hierarchy,
            counts,
            offsets,
            scan_local,
            scan_block_sum,
            scan_block_prefix,
            scan_hierarchy,
            total,
            core,
            operands,
            layout_word_offset,
            owner_by_instruction,
            op_by_instruction,
            schedule,
            semantic_schedule_group,
            semantic_sorter,
            call_args,
            call_arg_count,
            aggregate_elements,
            aggregate_element_count,
            strings,
            string_count,
            string_data_words,
            string_pool_len,
            functions,
            params,
            param_count,
            locals,
            status,
        })
    }

    pub(crate) fn output(&self) -> GpuSemanticLirView<'_> {
        GpuSemanticLirView {
            count: &self.total,
            core: &self.core,
            operands: &self.operands,
            layout_word_offset: &self.layout_word_offset,
            owner_by_instruction: &self.owner_by_instruction,
            op_by_instruction: &self.op_by_instruction,
            function_id_by_hir: &self.function_ids,
            call_args: &self.call_args,
            call_arg_start_by_hir: &self.call_arg_prefix_by_hir,
            call_arg_count_by_hir: &self.call_arg_counts_by_hir,
            aggregate_elements: &self.aggregate_elements,
            aggregate_element_count: &self.aggregate_element_count,
            strings: &self.strings,
            string_count: &self.string_count,
            string_data_words: &self.string_data_words,
            string_pool_len: &self.string_pool_len,
            functions: &self.functions,
            function_count: &self.function_count,
            params: &self.params,
            param_count: &self.param_count,
            locals: &self.locals,
            local_count: &self.local_count,
            execution_order: self
                .semantic_sorter
                .as_ref()
                .map(GpuStableScheduleSorter::output_order),
            status: &self.status,
        }
    }

    pub(crate) fn status(&self) -> &LaniusBuffer<LoweringStatus> {
        &self.status
    }

    fn materializer_resources<'a>(
        &'a self,
        hir: GpuSemanticHirInputs<'a>,
        semantic: GpuSemanticArtifactView<'a>,
    ) -> Result<ResourceMap<'a>> {
        let mut resources = ResourceMap::new();
        macro_rules! graph_buffer {
            ($name:literal, $buffer:expr) => {
                resources.graph_buffer(&self.graph, $name, $buffer)?
            };
        }
        graph_buffer!("hir.count", hir.count);
        graph_buffer!("hir.core", hir.core);
        graph_buffer!("hir.links", hir.links);
        graph_buffer!("hir.payload", hir.payload);
        graph_buffer!("hir.const_value", hir.const_value);
        graph_buffer!(
            "semantic.expression_types",
            semantic.expr_scalar_type_by_hir
        );
        graph_buffer!(
            "typecheck.semantic_expr_ref_tags_by_hir",
            semantic.expr_ref_tag_by_hir
        );
        graph_buffer!(
            "typecheck.semantic_expr_ref_payloads_by_hir",
            semantic.expr_ref_payload_by_hir
        );
        graph_buffer!(
            "typecheck.semantic_aggregate_decl_tokens_by_hir",
            semantic.aggregate_decl_token_by_hir
        );
        graph_buffer!(
            "typecheck.semantic_aggregate_word_counts_by_hir",
            semantic.aggregate_word_count_by_hir
        );
        graph_buffer!(
            "typecheck.semantic_array_lengths_by_hir",
            semantic.array_length_by_hir
        );
        graph_buffer!(
            "typecheck.semantic_iterable_kinds_by_hir",
            semantic.iterable_kind_by_hir
        );
        graph_buffer!("semantic.value_ids", &self.value_ids);
        graph_buffer!("semantic.value_types", &self.value_types);
        graph_buffer!(
            "typecheck.semantic_value_consts_by_hir",
            semantic.value_const_by_hir
        );
        graph_buffer!(
            "typecheck.semantic_value_const_present_by_hir",
            semantic.value_const_present_by_hir
        );
        graph_buffer!("semantic.call_targets", &self.call_targets);
        graph_buffer!("semantic.call_kinds", &self.call_kinds);
        graph_buffer!("semantic.call_result_types", &self.call_result_types);
        graph_buffer!(
            "semantic.call_symbol_library_ids",
            &self.call_symbol_library_ids
        );
        graph_buffer!("semantic.call_symbol_unit_ids", &self.call_symbol_unit_ids);
        graph_buffer!(
            "semantic.call_symbol_local_indices",
            &self.call_symbol_local_indices
        );
        graph_buffer!("semantic.function_ids", &self.function_ids);
        graph_buffer!(
            "lir.semantic.function_id_by_token",
            &self.function_id_by_token
        );
        graph_buffer!("lir.semantic.functions", &self.functions);
        graph_buffer!(
            "typecheck.semantic_control_depths_by_hir",
            semantic.control_depth_by_hir
        );
        graph_buffer!(
            "typecheck.semantic_member_field_ordinals_by_hir",
            semantic.member_field_ordinal_by_hir
        );
        graph_buffer!(
            "lir.semantic.struct_hir_by_name_token",
            &self.struct_hir_by_name_token
        );
        graph_buffer!(
            "lir.semantic.struct_field_count_by_hir",
            &self.struct_field_count_by_hir
        );
        graph_buffer!(
            "lir.semantic.struct_field_start_by_hir",
            &self.struct_field_start_by_hir
        );
        graph_buffer!(
            "lir.semantic.struct_word_count_by_hir",
            &self.struct_word_count_by_hir
        );
        graph_buffer!(
            "lir.semantic.struct_field_word_offset_by_row",
            &self.struct_field_word_offset_by_row
        );
        graph_buffer!(
            "lir.semantic.struct_field_word_count_by_row",
            &self.struct_field_word_count_by_row
        );
        graph_buffer!("hir.expression_roots", hir.expr_root);
        graph_buffer!("hir.nearest_loop", hir.nearest_loop);
        graph_buffer!("hir.array_element_start", hir.array_element_start);
        graph_buffer!("hir.array_element_count", hir.array_element_count);
        graph_buffer!("hir.array_element_row_count", hir.array_element_row_count);
        graph_buffer!("lir.semantic.count_by_hir", &self.counts);
        graph_buffer!("lir.semantic.offset_by_hir", &self.offsets);
        graph_buffer!("lir.semantic.execution_rank_a", &self.execution_rank_a);
        graph_buffer!("lir.semantic.total", &self.total);
        graph_buffer!("lowering.status", &self.status);
        graph_buffer!("lir.semantic.core", &self.core);
        graph_buffer!("lir.semantic.operands", &self.operands);
        graph_buffer!("lir.semantic.layout_word_offset", &self.layout_word_offset);
        graph_buffer!(
            "lir.semantic.owner_by_instruction",
            &self.owner_by_instruction
        );
        graph_buffer!("lir.semantic.op_by_instruction", &self.op_by_instruction);
        graph_buffer!("lir.semantic.schedule", &self.schedule);
        if let Some(sorter) = &self.semantic_sorter {
            graph_buffer!("lir.semantic.schedule_order", sorter.output_order());
        }
        resources.buffer("gParams", &self.scatter_params);
        Ok(resources)
    }

    pub(crate) fn record(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        hir: GpuSemanticHirInputs<'_>,
        semantic: GpuSemanticArtifactView<'_>,
    ) -> Result<()> {
        let pass = |name: &str| self.graph.pass_id(name).unwrap();
        let resource = |name: &str| self.graph.resource_id(name).unwrap();
        self.validate(
            pass("lir.status.clear"),
            vec![bound(
                "lowering_status",
                resource("lowering.status"),
                &self.status,
            )?],
        )?;
        let status_clear = make_group(
            device,
            &self.passes.status_clear,
            "lir.status.clear.bind_group",
            &[("lowering_status", self.status.as_entire_binding())],
        )?;
        record_direct(encoder, &self.passes.status_clear, &status_clear, 1)?;
        self.record_functions(device, encoder, &hir, semantic)?;
        self.validate(
            pass("lir.semantic.project"),
            vec![
                bound("compact_hir_count", resource("hir.count"), &hir.count)?,
                bound("compact_hir_core", resource("hir.core"), &hir.core)?,
                bound("compact_hir_payload", resource("hir.payload"), &hir.payload)?,
                bound(
                    "compact_expr_root",
                    resource("hir.expression_roots"),
                    hir.expr_root,
                )?,
                bound(
                    "semantic_value_decl_by_hir",
                    resource("typecheck.semantic_value_decls_by_hir"),
                    semantic.value_decl_by_hir,
                )?,
                bound(
                    "semantic_value_type_by_hir",
                    resource("typecheck.semantic_value_types_by_hir"),
                    semantic.value_type_by_hir,
                )?,
                bound(
                    "semantic_calls_by_hir",
                    resource("typecheck.semantic_calls_by_hir"),
                    semantic.calls_by_hir,
                )?,
                bound(
                    "semantic_enclosing_fn_by_hir",
                    resource("typecheck.semantic_enclosing_functions_by_hir"),
                    semantic.enclosing_fn_by_hir,
                )?,
                bound(
                    "semantic_function_flag",
                    resource("lir.semantic.function_flags"),
                    &self.function_flags,
                )?,
                bound(
                    "semantic_const_function_by_root",
                    resource("lir.semantic.const_function_by_root"),
                    &self.const_function_by_root,
                )?,
                bound(
                    "semantic_function_prefix",
                    resource("lir.semantic.function_prefix"),
                    &self.function_prefix,
                )?,
                bound(
                    "semantic_function_id_by_token",
                    resource("lir.semantic.function_id_by_token"),
                    &self.function_id_by_token,
                )?,
                bound(
                    "semantic_lir_functions",
                    resource("lir.semantic.functions"),
                    &self.functions,
                )?,
                bound(
                    "semantic_value_id",
                    resource("semantic.value_ids"),
                    &self.value_ids,
                )?,
                bound(
                    "semantic_value_type",
                    resource("semantic.value_types"),
                    &self.value_types,
                )?,
                bound(
                    "semantic_call_target",
                    resource("semantic.call_targets"),
                    &self.call_targets,
                )?,
                bound(
                    "semantic_call_kind",
                    resource("semantic.call_kinds"),
                    &self.call_kinds,
                )?,
                bound(
                    "semantic_call_result_type",
                    resource("semantic.call_result_types"),
                    &self.call_result_types,
                )?,
                bound(
                    "semantic_call_receiver",
                    resource("semantic.call_receivers"),
                    &self.call_receivers,
                )?,
                bound(
                    "semantic_call_symbol_library_id",
                    resource("semantic.call_symbol_library_ids"),
                    &self.call_symbol_library_ids,
                )?,
                bound(
                    "semantic_call_symbol_unit_id",
                    resource("semantic.call_symbol_unit_ids"),
                    &self.call_symbol_unit_ids,
                )?,
                bound(
                    "semantic_call_symbol_local_index",
                    resource("semantic.call_symbol_local_indices"),
                    &self.call_symbol_local_indices,
                )?,
                bound(
                    "semantic_call_arg_count_by_hir",
                    resource("lir.semantic.call_arg_counts_by_hir"),
                    &self.call_arg_counts_by_hir,
                )?,
                bound(
                    "semantic_function_id",
                    resource("semantic.function_ids"),
                    &self.function_ids,
                )?,
            ],
        )?;
        let project = make_group(
            device,
            &self.passes.project,
            "lir.semantic.project.bind_group",
            &[
                ("gParams", self.project_params.as_entire_binding()),
                ("compact_hir_count", hir.count.as_entire_binding()),
                ("compact_hir_core", hir.core.as_entire_binding()),
                ("compact_hir_payload", hir.payload.as_entire_binding()),
                ("compact_expr_root", hir.expr_root.as_entire_binding()),
                (
                    "semantic_value_decl_by_hir",
                    semantic.value_decl_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_value_type_by_hir",
                    semantic.value_type_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_calls_by_hir",
                    semantic.calls_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_enclosing_fn_by_hir",
                    semantic.enclosing_fn_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_function_flag",
                    self.function_flags.as_entire_binding(),
                ),
                (
                    "semantic_const_function_by_root",
                    self.const_function_by_root.as_entire_binding(),
                ),
                (
                    "semantic_function_prefix",
                    self.function_prefix.as_entire_binding(),
                ),
                (
                    "semantic_function_id_by_token",
                    self.function_id_by_token.as_entire_binding(),
                ),
                ("semantic_lir_functions", self.functions.as_entire_binding()),
                ("semantic_value_id", self.value_ids.as_entire_binding()),
                ("semantic_value_type", self.value_types.as_entire_binding()),
                (
                    "semantic_call_target",
                    self.call_targets.as_entire_binding(),
                ),
                ("semantic_call_kind", self.call_kinds.as_entire_binding()),
                (
                    "semantic_call_result_type",
                    self.call_result_types.as_entire_binding(),
                ),
                (
                    "semantic_call_receiver",
                    self.call_receivers.as_entire_binding(),
                ),
                (
                    "semantic_call_symbol_library_id",
                    self.call_symbol_library_ids.as_entire_binding(),
                ),
                (
                    "semantic_call_symbol_unit_id",
                    self.call_symbol_unit_ids.as_entire_binding(),
                ),
                (
                    "semantic_call_symbol_local_index",
                    self.call_symbol_local_indices.as_entire_binding(),
                ),
                (
                    "semantic_call_arg_count_by_hir",
                    self.call_arg_counts_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_function_id",
                    self.function_ids.as_entire_binding(),
                ),
            ],
        )?;
        record_direct(
            encoder,
            &self.passes.project,
            &project,
            self.capacities.hir_nodes,
        )?;
        self.record_scan(
            device,
            encoder,
            hir.count,
            SemanticScanFamily::CallArguments,
        )?;
        self.record_local_rows(device, encoder, &hir, semantic)?;

        self.record_execution_rank(device, encoder, &hir)?;

        self.validate(
            pass("lir.semantic.count"),
            vec![
                bound("compact_hir_count", resource("hir.count"), &hir.count)?,
                bound("compact_hir_core", resource("hir.core"), &hir.core)?,
                bound("compact_hir_payload", resource("hir.payload"), &hir.payload)?,
                bound(
                    "compact_expr_parent",
                    resource("hir.expression_parents"),
                    hir.expr_parent,
                )?,
                bound(
                    "semantic_function_id",
                    resource("semantic.function_ids"),
                    &self.function_ids,
                )?,
                bound(
                    "semantic_array_length",
                    resource("typecheck.semantic_array_lengths_by_hir"),
                    semantic.array_length_by_hir,
                )?,
                bound(
                    "semantic_iterable_kind",
                    resource("typecheck.semantic_iterable_kinds_by_hir"),
                    semantic.iterable_kind_by_hir,
                )?,
                bound(
                    "semantic_lir_count",
                    resource("lir.semantic.count_by_hir"),
                    &self.counts,
                )?,
            ],
        )?;
        let count = make_group(
            device,
            &self.passes.count,
            "lir.semantic.count.bind_group",
            &[
                ("gParams", self.count_params.as_entire_binding()),
                ("compact_hir_count", hir.count.as_entire_binding()),
                ("compact_hir_core", hir.core.as_entire_binding()),
                ("compact_hir_payload", hir.payload.as_entire_binding()),
                ("compact_expr_parent", hir.expr_parent.as_entire_binding()),
                (
                    "semantic_function_id",
                    self.function_ids.as_entire_binding(),
                ),
                (
                    "semantic_array_length",
                    semantic.array_length_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_iterable_kind",
                    semantic.iterable_kind_by_hir.as_entire_binding(),
                ),
                ("semantic_lir_count", self.counts.as_entire_binding()),
            ],
        )?;
        record_direct(
            encoder,
            &self.passes.count,
            &count,
            self.capacities.hir_nodes,
        )?;

        self.record_scan(
            device,
            encoder,
            &hir.count,
            SemanticScanFamily::Instructions,
        )?;

        let materializer_resources = self.materializer_resources(hir, semantic)?;
        self.validate(
            pass("lir.semantic.scatter"),
            materializer_resources.graph_bindings(&self.graph, "lir.semantic.scatter")?,
        )?;
        let scatter = materializer_resources.reflected_bind_group_with_overrides(
            device,
            "lir.semantic.scatter.bind_group",
            &self.passes.scatter,
            &[],
        )?;
        record_direct(
            encoder,
            &self.passes.scatter,
            &scatter,
            self.capacities.hir_nodes,
        )?;

        self.validate(
            pass("lir.semantic.call_args"),
            vec![
                bound(
                    "compact_call_arg_count",
                    resource("hir.call_arg_count"),
                    &hir.call_arg_count,
                )?,
                bound(
                    "compact_call_args",
                    resource("hir.call_args"),
                    &hir.call_args,
                )?,
                bound(
                    "semantic_call_receiver",
                    resource("semantic.call_receivers"),
                    &self.call_receivers,
                )?,
                bound(
                    "semantic_call_arg_count_by_hir",
                    resource("lir.semantic.call_arg_counts_by_hir"),
                    &self.call_arg_counts_by_hir,
                )?,
                bound(
                    "semantic_call_arg_prefix_by_hir",
                    resource("lir.semantic.call_arg_prefix_by_hir"),
                    &self.call_arg_prefix_by_hir,
                )?,
                bound(
                    "semantic_expr_type",
                    resource("semantic.expression_types"),
                    semantic.expr_scalar_type_by_hir,
                )?,
                bound(
                    "semantic_expr_ref_tag",
                    resource("typecheck.semantic_expr_ref_tags_by_hir"),
                    semantic.expr_ref_tag_by_hir,
                )?,
                bound(
                    "semantic_expr_ref_payload",
                    resource("typecheck.semantic_expr_ref_payloads_by_hir"),
                    semantic.expr_ref_payload_by_hir,
                )?,
                bound(
                    "semantic_lir_count",
                    resource("lir.semantic.count_by_hir"),
                    &self.counts,
                )?,
                bound(
                    "semantic_lir_offset",
                    resource("lir.semantic.offset_by_hir"),
                    &self.offsets,
                )?,
                bound(
                    "semantic_lir_call_args",
                    resource("lir.semantic.call_args"),
                    &self.call_args,
                )?,
            ],
        )?;
        let call_args = make_group(
            device,
            &self.passes.call_args,
            "lir.semantic.call_args.bind_group",
            &[
                ("gParams", self.call_arg_params.as_entire_binding()),
                (
                    "compact_call_arg_count",
                    hir.call_arg_count.as_entire_binding(),
                ),
                ("compact_call_args", hir.call_args.as_entire_binding()),
                (
                    "semantic_call_receiver",
                    self.call_receivers.as_entire_binding(),
                ),
                (
                    "semantic_call_arg_count_by_hir",
                    self.call_arg_counts_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_call_arg_prefix_by_hir",
                    self.call_arg_prefix_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_expr_type",
                    semantic.expr_scalar_type_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_expr_ref_tag",
                    semantic.expr_ref_tag_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_expr_ref_payload",
                    semantic.expr_ref_payload_by_hir.as_entire_binding(),
                ),
                ("semantic_lir_count", self.counts.as_entire_binding()),
                ("semantic_lir_offset", self.offsets.as_entire_binding()),
                ("semantic_lir_call_args", self.call_args.as_entire_binding()),
            ],
        )?;
        record_direct(
            encoder,
            &self.passes.call_args,
            &call_args,
            self.capacities
                .call_arguments
                .max(self.capacities.hir_nodes),
        )?;

        self.record_aggregate_elements(device, encoder, &hir, semantic)?;
        self.record_strings(device, encoder, &hir)?;
        if let (Some(group), Some(sorter)) = (&self.semantic_schedule_group, &self.semantic_sorter)
        {
            record_direct(
                encoder,
                &self.passes.schedule_init,
                group,
                self.capacities.semantic_instructions,
            )?;
            sorter.record(encoder)?;
        }
        Ok(())
    }

    fn record_local_rows(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        hir: &GpuSemanticHirInputs<'_>,
        semantic: GpuSemanticArtifactView<'_>,
    ) -> Result<()> {
        let resource = |name: &str| self.graph.resource_id(name).unwrap();
        self.validate(
            self.graph.pass_id("lir.semantic.locals.scatter").unwrap(),
            vec![
                bound("compact_hir_count", resource("hir.count"), hir.count)?,
                bound("compact_hir_payload", resource("hir.payload"), hir.payload)?,
                bound(
                    "semantic_local_flag",
                    resource("lir.semantic.local_flags"),
                    &self.local_flags,
                )?,
                bound(
                    "semantic_local_prefix",
                    resource("lir.semantic.local_prefix"),
                    &self.local_prefix,
                )?,
                bound(
                    "semantic_function_id",
                    resource("semantic.function_ids"),
                    &self.function_ids,
                )?,
                bound(
                    "semantic_value_type_by_hir",
                    resource("typecheck.semantic_value_types_by_hir"),
                    semantic.value_type_by_hir,
                )?,
                bound(
                    "semantic_lir_functions",
                    resource("lir.semantic.functions"),
                    &self.functions,
                )?,
                bound(
                    "semantic_lir_locals",
                    resource("lir.semantic.locals"),
                    &self.locals,
                )?,
            ],
        )?;
        let group = make_group(
            device,
            &self.passes.local_scatter,
            "lir.semantic.locals.scatter.bind_group",
            &[
                ("gParams", self.function_params.as_entire_binding()),
                ("compact_hir_count", hir.count.as_entire_binding()),
                ("compact_hir_payload", hir.payload.as_entire_binding()),
                ("semantic_local_flag", self.local_flags.as_entire_binding()),
                (
                    "semantic_local_prefix",
                    self.local_prefix.as_entire_binding(),
                ),
                (
                    "semantic_function_id",
                    self.function_ids.as_entire_binding(),
                ),
                (
                    "semantic_value_type_by_hir",
                    semantic.value_type_by_hir.as_entire_binding(),
                ),
                ("semantic_lir_functions", self.functions.as_entire_binding()),
                ("semantic_lir_locals", self.locals.as_entire_binding()),
            ],
        )?;
        record_direct(
            encoder,
            &self.passes.local_scatter,
            &group,
            self.capacities.hir_nodes,
        )
    }

    fn record_functions(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        hir: &GpuSemanticHirInputs<'_>,
        semantic: GpuSemanticArtifactView<'_>,
    ) -> Result<()> {
        let resource = |name: &str| self.graph.resource_id(name).unwrap();
        self.validate(
            self.graph.pass_id("lir.semantic.functions.mark").unwrap(),
            vec![
                bound("compact_hir_count", resource("hir.count"), hir.count)?,
                bound("compact_hir_core", resource("hir.core"), hir.core)?,
                bound("compact_hir_payload", resource("hir.payload"), hir.payload)?,
                bound(
                    "semantic_function_flag",
                    resource("lir.semantic.function_flags"),
                    &self.function_flags,
                )?,
                bound(
                    "semantic_const_function_by_root",
                    resource("lir.semantic.const_function_by_root"),
                    &self.const_function_by_root,
                )?,
            ],
        )?;
        let mark = make_group(
            device,
            &self.passes.function_mark,
            "lir.semantic.functions.mark.bind_group",
            &[
                ("gParams", self.function_params.as_entire_binding()),
                ("compact_hir_count", hir.count.as_entire_binding()),
                ("compact_hir_core", hir.core.as_entire_binding()),
                (
                    "semantic_function_flag",
                    self.function_flags.as_entire_binding(),
                ),
                (
                    "semantic_const_function_by_root",
                    self.const_function_by_root.as_entire_binding(),
                ),
            ],
        )?;
        record_direct(
            encoder,
            &self.passes.function_mark,
            &mark,
            self.capacities.hir_nodes,
        )?;
        self.record_scan(device, encoder, hir.count, SemanticScanFamily::Functions)?;

        self.validate(
            self.graph.pass_id("lir.semantic.locals.mark").unwrap(),
            vec![
                bound("compact_hir_count", resource("hir.count"), hir.count)?,
                bound("compact_hir_core", resource("hir.core"), hir.core)?,
                bound("compact_hir_payload", resource("hir.payload"), hir.payload)?,
                bound(
                    "semantic_local_flag",
                    resource("lir.semantic.local_flags"),
                    &self.local_flags,
                )?,
            ],
        )?;
        let local_mark = make_group(
            device,
            &self.passes.local_mark,
            "lir.semantic.locals.mark.bind_group",
            &[
                ("gParams", self.function_params.as_entire_binding()),
                ("compact_hir_count", hir.count.as_entire_binding()),
                ("compact_hir_core", hir.core.as_entire_binding()),
                ("compact_hir_payload", hir.payload.as_entire_binding()),
                ("semantic_local_flag", self.local_flags.as_entire_binding()),
            ],
        )?;
        record_direct(
            encoder,
            &self.passes.local_mark,
            &local_mark,
            self.capacities.hir_nodes,
        )?;
        self.record_scan(device, encoder, hir.count, SemanticScanFamily::Locals)?;

        self.validate(
            self.graph
                .pass_id("lir.semantic.functions.layout.clear")
                .unwrap(),
            vec![
                bound(
                    "semantic_struct_hir_by_name_token",
                    resource("lir.semantic.struct_hir_by_name_token"),
                    &self.struct_hir_by_name_token,
                )?,
                bound(
                    "semantic_struct_field_count_by_hir",
                    resource("lir.semantic.struct_field_count_by_hir"),
                    &self.struct_field_count_by_hir,
                )?,
                bound(
                    "semantic_struct_field_start_by_hir",
                    resource("lir.semantic.struct_field_start_by_hir"),
                    &self.struct_field_start_by_hir,
                )?,
                bound(
                    "semantic_struct_word_count_by_hir",
                    resource("lir.semantic.struct_word_count_by_hir"),
                    &self.struct_word_count_by_hir,
                )?,
                bound(
                    "semantic_struct_field_word_offset_by_row",
                    resource("lir.semantic.struct_field_word_offset_by_row"),
                    &self.struct_field_word_offset_by_row,
                )?,
                bound(
                    "semantic_struct_field_word_count_by_row",
                    resource("lir.semantic.struct_field_word_count_by_row"),
                    &self.struct_field_word_count_by_row,
                )?,
                bound(
                    "semantic_function_id_by_token",
                    resource("lir.semantic.function_id_by_token"),
                    &self.function_id_by_token,
                )?,
            ],
        )?;
        let layout_clear = make_group(
            device,
            &self.passes.function_layout_clear,
            "lir.semantic.functions.layout.clear.bind_group",
            &[
                ("gParams", self.function_params.as_entire_binding()),
                (
                    "semantic_struct_hir_by_name_token",
                    self.struct_hir_by_name_token.as_entire_binding(),
                ),
                (
                    "semantic_struct_field_count_by_hir",
                    self.struct_field_count_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_struct_field_start_by_hir",
                    self.struct_field_start_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_struct_word_count_by_hir",
                    self.struct_word_count_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_struct_field_word_offset_by_row",
                    self.struct_field_word_offset_by_row.as_entire_binding(),
                ),
                (
                    "semantic_struct_field_word_count_by_row",
                    self.struct_field_word_count_by_row.as_entire_binding(),
                ),
                (
                    "semantic_function_id_by_token",
                    self.function_id_by_token.as_entire_binding(),
                ),
            ],
        )?;
        record_direct(
            encoder,
            &self.passes.function_layout_clear,
            &layout_clear,
            self.capacities.tokens.max(self.capacities.hir_nodes),
        )?;

        self.validate(
            self.graph
                .pass_id("lir.semantic.functions.layout.collect")
                .unwrap(),
            vec![
                bound("compact_hir_count", resource("hir.count"), hir.count)?,
                bound("compact_hir_core", resource("hir.core"), hir.core)?,
                bound("compact_hir_payload", resource("hir.payload"), hir.payload)?,
                bound(
                    "compact_field_count",
                    resource("hir.field_count"),
                    hir.field_count,
                )?,
                bound("compact_fields", resource("hir.fields"), hir.fields)?,
                bound(
                    "semantic_struct_hir_by_name_token",
                    resource("lir.semantic.struct_hir_by_name_token"),
                    &self.struct_hir_by_name_token,
                )?,
                bound(
                    "semantic_struct_field_count_by_hir",
                    resource("lir.semantic.struct_field_count_by_hir"),
                    &self.struct_field_count_by_hir,
                )?,
                bound(
                    "semantic_struct_field_start_by_hir",
                    resource("lir.semantic.struct_field_start_by_hir"),
                    &self.struct_field_start_by_hir,
                )?,
            ],
        )?;
        let layout_collect = make_group(
            device,
            &self.passes.function_layout_collect,
            "lir.semantic.functions.layout.collect.bind_group",
            &[
                ("gParams", self.function_params.as_entire_binding()),
                ("compact_hir_count", hir.count.as_entire_binding()),
                ("compact_hir_core", hir.core.as_entire_binding()),
                ("compact_hir_payload", hir.payload.as_entire_binding()),
                ("compact_field_count", hir.field_count.as_entire_binding()),
                ("compact_fields", hir.fields.as_entire_binding()),
                (
                    "semantic_struct_hir_by_name_token",
                    self.struct_hir_by_name_token.as_entire_binding(),
                ),
                (
                    "semantic_struct_field_count_by_hir",
                    self.struct_field_count_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_struct_field_start_by_hir",
                    self.struct_field_start_by_hir.as_entire_binding(),
                ),
            ],
        )?;
        record_direct(
            encoder,
            &self.passes.function_layout_collect,
            &layout_collect,
            self.capacities
                .hir_nodes
                .max(self.capacities.aggregate_elements),
        )?;

        self.validate(
            self.graph
                .pass_id("lir.semantic.functions.layout.words")
                .unwrap(),
            vec![
                bound("compact_hir_count", resource("hir.count"), hir.count)?,
                bound("compact_hir_core", resource("hir.core"), hir.core)?,
                bound("compact_hir_payload", resource("hir.payload"), hir.payload)?,
                bound("compact_fields", resource("hir.fields"), hir.fields)?,
                bound(
                    "semantic_expr_ref_tag",
                    resource("typecheck.semantic_expr_ref_tags_by_hir"),
                    semantic.expr_ref_tag_by_hir,
                )?,
                bound(
                    "semantic_expr_ref_payload",
                    resource("typecheck.semantic_expr_ref_payloads_by_hir"),
                    semantic.expr_ref_payload_by_hir,
                )?,
                bound(
                    "semantic_aggregate_decl_token",
                    resource("typecheck.semantic_aggregate_decl_tokens_by_hir"),
                    semantic.aggregate_decl_token_by_hir,
                )?,
                bound(
                    "semantic_struct_hir_by_name_token",
                    resource("lir.semantic.struct_hir_by_name_token"),
                    &self.struct_hir_by_name_token,
                )?,
                bound(
                    "semantic_struct_field_start_by_hir",
                    resource("lir.semantic.struct_field_start_by_hir"),
                    &self.struct_field_start_by_hir,
                )?,
                bound(
                    "semantic_struct_field_count_by_hir",
                    resource("lir.semantic.struct_field_count_by_hir"),
                    &self.struct_field_count_by_hir,
                )?,
                bound(
                    "semantic_struct_word_count_by_hir",
                    resource("lir.semantic.struct_word_count_by_hir"),
                    &self.struct_word_count_by_hir,
                )?,
                bound(
                    "semantic_struct_field_word_offset_by_row",
                    resource("lir.semantic.struct_field_word_offset_by_row"),
                    &self.struct_field_word_offset_by_row,
                )?,
                bound(
                    "semantic_struct_field_word_count_by_row",
                    resource("lir.semantic.struct_field_word_count_by_row"),
                    &self.struct_field_word_count_by_row,
                )?,
            ],
        )?;
        let layout_words = make_group(
            device,
            &self.passes.function_layout_words,
            "lir.semantic.functions.layout.words.bind_group",
            &[
                ("gParams", self.function_params.as_entire_binding()),
                ("compact_hir_count", hir.count.as_entire_binding()),
                ("compact_hir_core", hir.core.as_entire_binding()),
                ("compact_hir_payload", hir.payload.as_entire_binding()),
                ("compact_fields", hir.fields.as_entire_binding()),
                (
                    "semantic_expr_ref_tag",
                    semantic.expr_ref_tag_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_expr_ref_payload",
                    semantic.expr_ref_payload_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_aggregate_decl_token",
                    semantic.aggregate_decl_token_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_struct_hir_by_name_token",
                    self.struct_hir_by_name_token.as_entire_binding(),
                ),
                (
                    "semantic_struct_field_start_by_hir",
                    self.struct_field_start_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_struct_field_count_by_hir",
                    self.struct_field_count_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_struct_word_count_by_hir",
                    self.struct_word_count_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_struct_field_word_offset_by_row",
                    self.struct_field_word_offset_by_row.as_entire_binding(),
                ),
                (
                    "semantic_struct_field_word_count_by_row",
                    self.struct_field_word_count_by_row.as_entire_binding(),
                ),
            ],
        )?;
        record_direct(
            encoder,
            &self.passes.function_layout_words,
            &layout_words,
            self.capacities.hir_nodes,
        )?;

        self.validate(
            self.graph
                .pass_id("lir.semantic.functions.scatter")
                .unwrap(),
            vec![
                bound("compact_hir_count", resource("hir.count"), hir.count)?,
                bound("compact_hir_core", resource("hir.core"), hir.core)?,
                bound("compact_hir_links", resource("hir.links"), hir.links)?,
                bound("compact_hir_payload", resource("hir.payload"), hir.payload)?,
                bound(
                    "compact_const_value",
                    resource("hir.const_value"),
                    hir.const_value,
                )?,
                bound(
                    "compact_param_ranges",
                    resource("hir.param_ranges"),
                    hir.param_ranges,
                )?,
                bound(
                    "compact_method_count",
                    resource("hir.method_count"),
                    hir.method_count,
                )?,
                bound(
                    "compact_method_cores",
                    resource("hir.method_cores"),
                    hir.method_cores,
                )?,
                bound(
                    "compact_method_signatures",
                    resource("hir.method_signatures"),
                    hir.method_signatures,
                )?,
                bound(
                    "semantic_function_flag",
                    resource("lir.semantic.function_flags"),
                    &self.function_flags,
                )?,
                bound(
                    "semantic_function_prefix",
                    resource("lir.semantic.function_prefix"),
                    &self.function_prefix,
                )?,
                bound(
                    "semantic_local_prefix",
                    resource("lir.semantic.local_prefix"),
                    &self.local_prefix,
                )?,
                bound(
                    "semantic_local_total",
                    resource("lir.semantic.local_total"),
                    &self.local_count,
                )?,
                bound(
                    "semantic_function_return_type_by_hir",
                    resource("typecheck.semantic_function_return_types_by_hir"),
                    semantic.function_return_type_by_hir,
                )?,
                bound(
                    "semantic_function_result_word_count_by_hir",
                    resource("typecheck.semantic_function_result_word_counts_by_hir"),
                    semantic.function_result_word_count_by_hir,
                )?,
                bound(
                    "semantic_function_entrypoint_by_hir",
                    resource("typecheck.semantic_function_entrypoints_by_hir"),
                    semantic.function_entrypoint_by_hir,
                )?,
                bound(
                    "semantic_function_host_service_by_hir",
                    resource("typecheck.semantic_function_host_services_by_hir"),
                    semantic.function_host_service_by_hir,
                )?,
                bound(
                    "public_decl_index_by_hir",
                    resource("typecheck.public_decl_index_by_hir"),
                    semantic.public_decl_index_by_hir,
                )?,
                bound(
                    "semantic_value_type_by_hir",
                    resource("typecheck.semantic_value_types_by_hir"),
                    semantic.value_type_by_hir,
                )?,
                bound(
                    "semantic_struct_hir_by_name_token",
                    resource("lir.semantic.struct_hir_by_name_token"),
                    &self.struct_hir_by_name_token,
                )?,
                bound(
                    "semantic_struct_word_count_by_hir",
                    resource("lir.semantic.struct_word_count_by_hir"),
                    &self.struct_word_count_by_hir,
                )?,
                bound(
                    "semantic_lir_functions",
                    resource("lir.semantic.functions"),
                    &self.functions,
                )?,
                bound(
                    "semantic_function_id_by_token",
                    resource("lir.semantic.function_id_by_token"),
                    &self.function_id_by_token,
                )?,
                bound(
                    "semantic_const_function_by_root",
                    resource("lir.semantic.const_function_by_root"),
                    &self.const_function_by_root,
                )?,
            ],
        )?;
        let scatter = make_group(
            device,
            &self.passes.function_scatter,
            "lir.semantic.functions.scatter.bind_group",
            &[
                ("gParams", self.function_params.as_entire_binding()),
                ("compact_hir_count", hir.count.as_entire_binding()),
                ("compact_hir_core", hir.core.as_entire_binding()),
                ("compact_hir_links", hir.links.as_entire_binding()),
                ("compact_hir_payload", hir.payload.as_entire_binding()),
                ("compact_const_value", hir.const_value.as_entire_binding()),
                ("compact_param_ranges", hir.param_ranges.as_entire_binding()),
                ("compact_method_count", hir.method_count.as_entire_binding()),
                ("compact_method_cores", hir.method_cores.as_entire_binding()),
                (
                    "compact_method_signatures",
                    hir.method_signatures.as_entire_binding(),
                ),
                (
                    "semantic_function_flag",
                    self.function_flags.as_entire_binding(),
                ),
                (
                    "semantic_function_prefix",
                    self.function_prefix.as_entire_binding(),
                ),
                (
                    "semantic_local_prefix",
                    self.local_prefix.as_entire_binding(),
                ),
                ("semantic_local_total", self.local_count.as_entire_binding()),
                (
                    "semantic_function_return_type_by_hir",
                    semantic.function_return_type_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_function_result_word_count_by_hir",
                    semantic
                        .function_result_word_count_by_hir
                        .as_entire_binding(),
                ),
                (
                    "semantic_function_entrypoint_by_hir",
                    semantic.function_entrypoint_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_function_host_service_by_hir",
                    semantic.function_host_service_by_hir.as_entire_binding(),
                ),
                (
                    "public_decl_index_by_hir",
                    semantic.public_decl_index_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_value_type_by_hir",
                    semantic.value_type_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_struct_hir_by_name_token",
                    self.struct_hir_by_name_token.as_entire_binding(),
                ),
                (
                    "semantic_struct_word_count_by_hir",
                    self.struct_word_count_by_hir.as_entire_binding(),
                ),
                ("semantic_lir_functions", self.functions.as_entire_binding()),
                (
                    "semantic_function_id_by_token",
                    self.function_id_by_token.as_entire_binding(),
                ),
                (
                    "semantic_const_function_by_root",
                    self.const_function_by_root.as_entire_binding(),
                ),
            ],
        )?;
        record_direct(
            encoder,
            &self.passes.function_scatter,
            &scatter,
            self.capacities.hir_nodes,
        )?;

        self.validate(
            self.graph.pass_id("lir.semantic.functions.params").unwrap(),
            vec![
                bound(
                    "compact_param_count",
                    resource("hir.param_count"),
                    hir.param_count,
                )?,
                bound("compact_params", resource("hir.params"), hir.params)?,
                bound(
                    "semantic_function_flag",
                    resource("lir.semantic.function_flags"),
                    &self.function_flags,
                )?,
                bound(
                    "semantic_function_prefix",
                    resource("lir.semantic.function_prefix"),
                    &self.function_prefix,
                )?,
                bound(
                    "semantic_param_type_by_row",
                    resource("typecheck.semantic_param_types_by_row"),
                    semantic.param_type_by_row,
                )?,
                bound(
                    "semantic_lir_param_total",
                    resource("lir.semantic.param_total"),
                    &self.param_count,
                )?,
                bound(
                    "semantic_lir_params",
                    resource("lir.semantic.params"),
                    &self.params,
                )?,
                bound("lowering_status", resource("lowering.status"), &self.status)?,
            ],
        )?;
        let params = make_group(
            device,
            &self.passes.function_params,
            "lir.semantic.functions.params.bind_group",
            &[
                ("gParams", self.function_params.as_entire_binding()),
                ("compact_param_count", hir.param_count.as_entire_binding()),
                ("compact_params", hir.params.as_entire_binding()),
                (
                    "semantic_function_flag",
                    self.function_flags.as_entire_binding(),
                ),
                (
                    "semantic_function_prefix",
                    self.function_prefix.as_entire_binding(),
                ),
                (
                    "semantic_param_type_by_row",
                    semantic.param_type_by_row.as_entire_binding(),
                ),
                (
                    "semantic_lir_param_total",
                    self.param_count.as_entire_binding(),
                ),
                ("semantic_lir_params", self.params.as_entire_binding()),
                ("lowering_status", self.status.as_entire_binding()),
            ],
        )?;
        record_direct(
            encoder,
            &self.passes.function_params,
            &params,
            self.capacities.parameters.max(1),
        )
    }

    fn record_aggregate_elements(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        hir: &GpuSemanticHirInputs<'_>,
        semantic: GpuSemanticArtifactView<'_>,
    ) -> Result<()> {
        let resource = |name: &str| self.graph.resource_id(name).unwrap();
        self.validate(
            self.graph
                .pass_id("lir.semantic.aggregate_elements")
                .unwrap(),
            vec![
                bound("compact_hir_count", resource("hir.count"), hir.count)?,
                bound("compact_hir_core", resource("hir.core"), hir.core)?,
                bound("compact_hir_payload", resource("hir.payload"), hir.payload)?,
                bound(
                    "compact_field_count",
                    resource("hir.field_count"),
                    hir.field_count,
                )?,
                bound("compact_fields", resource("hir.fields"), hir.fields)?,
                bound(
                    "struct_init_field_ordinal_by_row",
                    resource("typecheck.struct_init_field_ordinals"),
                    semantic.struct_init_field_ordinal_by_row,
                )?,
                bound(
                    "compact_array_element_count",
                    resource("hir.array_element_row_count"),
                    hir.array_element_row_count,
                )?,
                bound(
                    "compact_array_elements",
                    resource("hir.array_elements"),
                    hir.array_elements,
                )?,
                bound(
                    "semantic_expr_type",
                    resource("semantic.expression_types"),
                    semantic.expr_scalar_type_by_hir,
                )?,
                bound(
                    "semantic_expr_ref_tag",
                    resource("typecheck.semantic_expr_ref_tags_by_hir"),
                    semantic.expr_ref_tag_by_hir,
                )?,
                bound(
                    "semantic_expr_ref_payload",
                    resource("typecheck.semantic_expr_ref_payloads_by_hir"),
                    semantic.expr_ref_payload_by_hir,
                )?,
                bound(
                    "semantic_aggregate_decl_token",
                    resource("typecheck.semantic_aggregate_decl_tokens_by_hir"),
                    semantic.aggregate_decl_token_by_hir,
                )?,
                bound(
                    "semantic_struct_hir_by_name_token",
                    resource("lir.semantic.struct_hir_by_name_token"),
                    &self.struct_hir_by_name_token,
                )?,
                bound(
                    "semantic_struct_field_start_by_hir",
                    resource("lir.semantic.struct_field_start_by_hir"),
                    &self.struct_field_start_by_hir,
                )?,
                bound(
                    "semantic_struct_field_word_offset_by_row",
                    resource("lir.semantic.struct_field_word_offset_by_row"),
                    &self.struct_field_word_offset_by_row,
                )?,
                bound(
                    "semantic_struct_field_word_count_by_row",
                    resource("lir.semantic.struct_field_word_count_by_row"),
                    &self.struct_field_word_count_by_row,
                )?,
                bound(
                    "semantic_lir_count",
                    resource("lir.semantic.count_by_hir"),
                    &self.counts,
                )?,
                bound(
                    "semantic_lir_offset",
                    resource("lir.semantic.offset_by_hir"),
                    &self.offsets,
                )?,
                bound(
                    "semantic_lir_aggregate_element_total",
                    resource("lir.semantic.aggregate_element_total"),
                    &self.aggregate_element_count,
                )?,
                bound(
                    "semantic_lir_aggregate_elements",
                    resource("lir.semantic.aggregate_elements"),
                    &self.aggregate_elements,
                )?,
                bound("lowering_status", resource("lowering.status"), &self.status)?,
            ],
        )?;
        let group = make_group(
            device,
            &self.passes.aggregate_elements,
            "lir.semantic.aggregate_elements.bind_group",
            &[
                ("gParams", self.aggregate_params.as_entire_binding()),
                ("compact_hir_count", hir.count.as_entire_binding()),
                ("compact_hir_core", hir.core.as_entire_binding()),
                ("compact_field_count", hir.field_count.as_entire_binding()),
                ("compact_fields", hir.fields.as_entire_binding()),
                (
                    "struct_init_field_ordinal_by_row",
                    semantic
                        .struct_init_field_ordinal_by_row
                        .as_entire_binding(),
                ),
                (
                    "compact_array_element_count",
                    hir.array_element_row_count.as_entire_binding(),
                ),
                (
                    "compact_array_elements",
                    hir.array_elements.as_entire_binding(),
                ),
                (
                    "semantic_expr_type",
                    semantic.expr_scalar_type_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_expr_ref_tag",
                    semantic.expr_ref_tag_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_expr_ref_payload",
                    semantic.expr_ref_payload_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_aggregate_decl_token",
                    semantic.aggregate_decl_token_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_struct_hir_by_name_token",
                    self.struct_hir_by_name_token.as_entire_binding(),
                ),
                (
                    "semantic_struct_field_start_by_hir",
                    self.struct_field_start_by_hir.as_entire_binding(),
                ),
                (
                    "semantic_struct_field_word_offset_by_row",
                    self.struct_field_word_offset_by_row.as_entire_binding(),
                ),
                (
                    "semantic_struct_field_word_count_by_row",
                    self.struct_field_word_count_by_row.as_entire_binding(),
                ),
                ("semantic_lir_count", self.counts.as_entire_binding()),
                ("semantic_lir_offset", self.offsets.as_entire_binding()),
                (
                    "semantic_lir_aggregate_element_total",
                    self.aggregate_element_count.as_entire_binding(),
                ),
                (
                    "semantic_lir_aggregate_elements",
                    self.aggregate_elements.as_entire_binding(),
                ),
                ("lowering_status", self.status.as_entire_binding()),
            ],
        )?;
        record_direct(
            encoder,
            &self.passes.aggregate_elements,
            &group,
            self.capacities.aggregate_elements.saturating_mul(2),
        )
    }

    fn record_strings(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        hir: &GpuSemanticHirInputs<'_>,
    ) -> Result<()> {
        let resource = |name: &str| self.graph.resource_id(name).unwrap();
        self.validate(
            self.graph.pass_id("lir.semantic.strings").unwrap(),
            vec![
                bound(
                    "compact_string_count",
                    resource("hir.string_count"),
                    hir.string_count,
                )?,
                bound("compact_strings", resource("hir.strings"), hir.strings)?,
                bound(
                    "compact_string_pool_len",
                    resource("hir.string_pool_len"),
                    hir.string_pool_len,
                )?,
                bound(
                    "compact_string_data",
                    resource("hir.string_data"),
                    hir.string_data_words,
                )?,
                bound(
                    "semantic_lir_count",
                    resource("lir.semantic.count_by_hir"),
                    &self.counts,
                )?,
                bound(
                    "semantic_lir_offset",
                    resource("lir.semantic.offset_by_hir"),
                    &self.offsets,
                )?,
                bound(
                    "semantic_lir_string_total",
                    resource("lir.semantic.string_total"),
                    &self.string_count,
                )?,
                bound(
                    "semantic_lir_strings",
                    resource("lir.semantic.strings"),
                    &self.strings,
                )?,
                bound(
                    "semantic_lir_string_pool_len",
                    resource("lir.semantic.string_pool_len"),
                    &self.string_pool_len,
                )?,
                bound(
                    "semantic_lir_string_data",
                    resource("lir.semantic.string_data"),
                    &self.string_data_words,
                )?,
                bound("lowering_status", resource("lowering.status"), &self.status)?,
            ],
        )?;
        let group = make_group(
            device,
            &self.passes.strings,
            "lir.semantic.strings.bind_group",
            &[
                ("gParams", self.string_params.as_entire_binding()),
                ("compact_string_count", hir.string_count.as_entire_binding()),
                ("compact_strings", hir.strings.as_entire_binding()),
                (
                    "compact_string_pool_len",
                    hir.string_pool_len.as_entire_binding(),
                ),
                (
                    "compact_string_data",
                    hir.string_data_words.as_entire_binding(),
                ),
                ("semantic_lir_count", self.counts.as_entire_binding()),
                ("semantic_lir_offset", self.offsets.as_entire_binding()),
                (
                    "semantic_lir_string_total",
                    self.string_count.as_entire_binding(),
                ),
                ("semantic_lir_strings", self.strings.as_entire_binding()),
                (
                    "semantic_lir_string_pool_len",
                    self.string_pool_len.as_entire_binding(),
                ),
                (
                    "semantic_lir_string_data",
                    self.string_data_words.as_entire_binding(),
                ),
                ("lowering_status", self.status.as_entire_binding()),
            ],
        )?;
        record_direct(
            encoder,
            &self.passes.strings,
            &group,
            self.capacities.source_bytes.max(self.capacities.hir_nodes),
        )
    }

    fn record_execution_rank(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        hir: &GpuSemanticHirInputs<'_>,
    ) -> Result<()> {
        let resource = |name: &str| self.graph.resource_id(name).unwrap();
        let init_pass = self
            .graph
            .pass_id("lir.semantic.execution_rank.init")
            .unwrap();
        self.validate(
            init_pass,
            vec![
                bound("compact_hir_count", resource("hir.count"), hir.count)?,
                bound("compact_hir_core", resource("hir.core"), hir.core)?,
                bound(
                    "compact_expr_parent",
                    resource("hir.expression_parents"),
                    hir.expr_parent,
                )?,
                bound(
                    "execution_rank_link",
                    resource("lir.semantic.execution_rank_link_a"),
                    &self.execution_rank_link_a,
                )?,
                bound(
                    "execution_rank",
                    resource("lir.semantic.execution_rank_a"),
                    &self.execution_rank_a,
                )?,
            ],
        )?;
        let init = make_group(
            device,
            &self.passes.execution_rank_init,
            "lir.semantic.execution_rank.init.bind_group",
            &[
                ("gParams", self.count_params.as_entire_binding()),
                ("compact_hir_count", hir.count.as_entire_binding()),
                ("compact_hir_core", hir.core.as_entire_binding()),
                ("compact_expr_parent", hir.expr_parent.as_entire_binding()),
                (
                    "execution_rank_link",
                    self.execution_rank_link_a.as_entire_binding(),
                ),
                ("execution_rank", self.execution_rank_a.as_entire_binding()),
            ],
        )?;
        record_direct(
            encoder,
            &self.passes.execution_rank_init,
            &init,
            self.capacities.hir_nodes,
        )?;

        for _ in 0..self.execution_rank_pairs {
            self.record_execution_rank_step(
                device,
                encoder,
                "lir.semantic.execution_rank.step_a_to_b",
                &self.execution_rank_link_a,
                &self.execution_rank_a,
                &self.execution_rank_link_b,
                &self.execution_rank_b,
                hir.count,
            )?;
            self.record_execution_rank_step(
                device,
                encoder,
                "lir.semantic.execution_rank.step_b_to_a",
                &self.execution_rank_link_b,
                &self.execution_rank_b,
                &self.execution_rank_link_a,
                &self.execution_rank_a,
                hir.count,
            )?;
        }
        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    fn record_execution_rank_step(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        pass_name: &str,
        link_in: &LaniusBuffer<u32>,
        rank_in: &LaniusBuffer<u32>,
        link_out: &LaniusBuffer<u32>,
        rank_out: &LaniusBuffer<u32>,
        active_count: &LaniusBuffer<u32>,
    ) -> Result<()> {
        let resource = |name: &str| self.graph.resource_id(name).unwrap();
        let pass = self.graph.pass_id(pass_name).unwrap();
        let (link_in_name, rank_in_name, link_out_name, rank_out_name) =
            if pass_name.ends_with("a_to_b") {
                (
                    "lir.semantic.execution_rank_link_a",
                    "lir.semantic.execution_rank_a",
                    "lir.semantic.execution_rank_link_b",
                    "lir.semantic.execution_rank_b",
                )
            } else {
                (
                    "lir.semantic.execution_rank_link_b",
                    "lir.semantic.execution_rank_b",
                    "lir.semantic.execution_rank_link_a",
                    "lir.semantic.execution_rank_a",
                )
            };
        self.validate(
            pass,
            vec![
                bound("compact_hir_count", resource("hir.count"), active_count)?,
                bound("execution_rank_link_in", resource(link_in_name), link_in)?,
                bound("execution_rank_in", resource(rank_in_name), rank_in)?,
                bound("execution_rank_link_out", resource(link_out_name), link_out)?,
                bound("execution_rank_out", resource(rank_out_name), rank_out)?,
            ],
        )?;
        let group = make_group(
            device,
            &self.passes.execution_rank_step,
            "lir.semantic.execution_rank.step.bind_group",
            &[
                ("gParams", self.count_params.as_entire_binding()),
                ("compact_hir_count", active_count.as_entire_binding()),
                ("execution_rank_link_in", link_in.as_entire_binding()),
                ("execution_rank_in", rank_in.as_entire_binding()),
                ("execution_rank_link_out", link_out.as_entire_binding()),
                ("execution_rank_out", rank_out.as_entire_binding()),
            ],
        )?;
        record_direct(
            encoder,
            &self.passes.execution_rank_step,
            &group,
            self.capacities.hir_nodes,
        )
    }

    fn record_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        active_count: &LaniusBuffer<u32>,
        family: SemanticScanFamily,
    ) -> Result<()> {
        let resource = |name: &str| self.graph.resource_id(name).unwrap();
        let (
            local_pass,
            up_pass,
            down_pass,
            apply_pass,
            input_name,
            input,
            local_name,
            local_buffer,
            block_sum_name,
            block_sum,
            block_prefix_name,
            block_prefix,
            hierarchy_name,
            hierarchy,
            output_name,
            output,
            total_name,
            total,
        ) = match family {
            SemanticScanFamily::Functions => (
                "lir.semantic.function_scan.local",
                "lir.semantic.function_scan.hierarchy_up",
                "lir.semantic.function_scan.hierarchy_down",
                "lir.semantic.function_scan.apply",
                "lir.semantic.function_flags",
                &self.function_flags,
                "lir.semantic.function_scan_local",
                &self.function_scan_local,
                "lir.semantic.function_scan_block_sum",
                &self.function_scan_block_sum,
                "lir.semantic.function_scan_block_prefix",
                &self.function_scan_block_prefix,
                "lir.semantic.function_scan_hierarchy",
                &self.function_scan_hierarchy,
                "lir.semantic.function_prefix",
                &self.function_prefix,
                "lir.semantic.function_total",
                &self.function_count,
            ),
            SemanticScanFamily::Locals => (
                "lir.semantic.local_scan.local",
                "lir.semantic.local_scan.hierarchy_up",
                "lir.semantic.local_scan.hierarchy_down",
                "lir.semantic.local_scan.apply",
                "lir.semantic.local_flags",
                &self.local_flags,
                "lir.semantic.local_scan_local",
                &self.local_scan_local,
                "lir.semantic.local_scan_block_sum",
                &self.local_scan_block_sum,
                "lir.semantic.local_scan_block_prefix",
                &self.local_scan_block_prefix,
                "lir.semantic.local_scan_hierarchy",
                &self.local_scan_hierarchy,
                "lir.semantic.local_prefix",
                &self.local_prefix,
                "lir.semantic.local_total",
                &self.local_count,
            ),
            SemanticScanFamily::CallArguments => (
                "lir.semantic.call_arg_scan.local",
                "lir.semantic.call_arg_scan.hierarchy_up",
                "lir.semantic.call_arg_scan.hierarchy_down",
                "lir.semantic.call_arg_scan.apply",
                "lir.semantic.call_arg_counts_by_hir",
                &self.call_arg_counts_by_hir,
                "lir.semantic.call_arg_scan_local",
                &self.call_arg_scan_local,
                "lir.semantic.call_arg_scan_block_sum",
                &self.call_arg_scan_block_sum,
                "lir.semantic.call_arg_scan_block_prefix",
                &self.call_arg_scan_block_prefix,
                "lir.semantic.call_arg_scan_hierarchy",
                &self.call_arg_scan_hierarchy,
                "lir.semantic.call_arg_prefix_by_hir",
                &self.call_arg_prefix_by_hir,
                "lir.semantic.call_arg_total",
                &self.call_arg_count,
            ),
            SemanticScanFamily::Instructions => (
                "lir.semantic.scan.local",
                "lir.semantic.scan.hierarchy_up",
                "lir.semantic.scan.hierarchy_down",
                "lir.semantic.scan.apply",
                "lir.semantic.count_by_hir",
                &self.counts,
                "lir.semantic.scan_local",
                &self.scan_local,
                "lir.semantic.scan_block_sum",
                &self.scan_block_sum,
                "lir.semantic.scan_block_prefix",
                &self.scan_block_prefix,
                "lir.semantic.scan_hierarchy",
                &self.scan_hierarchy,
                "lir.semantic.offset_by_hir",
                &self.offsets,
                "lir.semantic.total",
                &self.total,
            ),
        };
        self.validate(
            self.graph.pass_id(local_pass).unwrap(),
            vec![
                bound("scan_count", resource("hir.count"), active_count)?,
                bound("scan_input", resource(input_name), input)?,
                bound("scan_local_prefix", resource(local_name), local_buffer)?,
                bound("scan_block_sum", resource(block_sum_name), block_sum)?,
            ],
        )?;
        let local = make_group(
            device,
            &self.passes.scan_local,
            "lir.semantic.scan.local.bind_group",
            &[
                ("gScan", self.scan_params.as_entire_binding()),
                ("scan_count", active_count.as_entire_binding()),
                ("scan_input", input.as_entire_binding()),
                ("scan_local_prefix", local_buffer.as_entire_binding()),
                ("scan_block_sum", block_sum.as_entire_binding()),
            ],
        )?;
        record_direct(
            encoder,
            &self.passes.scan_local,
            &local,
            self.capacities.hir_nodes,
        )?;

        self.validate(
            self.graph.pass_id(up_pass).unwrap(),
            vec![
                bound("scan_count", resource("hir.count"), active_count)?,
                bound("scan_block_sum", resource(block_sum_name), block_sum)?,
                bound(
                    "scan_block_prefix",
                    resource(block_prefix_name),
                    block_prefix,
                )?,
                bound("scan_hierarchy", resource(hierarchy_name), hierarchy)?,
            ],
        )?;
        for (index, level) in self.scan_levels.iter().enumerate() {
            let up = make_group(
                device,
                &self.passes.scan_up,
                "lir.semantic.scan.up.bind_group",
                &[
                    (
                        "gHierarchy",
                        self.scan_hierarchy_params[index].as_entire_binding(),
                    ),
                    ("scan_count", active_count.as_entire_binding()),
                    ("scan_block_sum", block_sum.as_entire_binding()),
                    ("scan_block_prefix", block_prefix.as_entire_binding()),
                    ("scan_hierarchy", hierarchy.as_entire_binding()),
                ],
            )?;
            record_direct(encoder, &self.passes.scan_up, &up, level.count)?;
        }
        self.validate(
            self.graph.pass_id(down_pass).unwrap(),
            vec![
                bound("scan_count", resource("hir.count"), active_count)?,
                bound(
                    "scan_block_prefix",
                    resource(block_prefix_name),
                    block_prefix,
                )?,
                bound("scan_hierarchy", resource(hierarchy_name), hierarchy)?,
            ],
        )?;
        for child_index in (0..self.scan_levels.len().saturating_sub(1)).rev() {
            let level = self.scan_levels[child_index];
            let down = make_group(
                device,
                &self.passes.scan_down,
                "lir.semantic.scan.down.bind_group",
                &[
                    (
                        "gHierarchy",
                        self.scan_hierarchy_params[child_index].as_entire_binding(),
                    ),
                    ("scan_count", active_count.as_entire_binding()),
                    ("scan_block_prefix", block_prefix.as_entire_binding()),
                    ("scan_hierarchy", hierarchy.as_entire_binding()),
                ],
            )?;
            record_direct(encoder, &self.passes.scan_down, &down, level.count)?;
        }
        self.validate(
            self.graph.pass_id(apply_pass).unwrap(),
            vec![
                bound("scan_count", resource("hir.count"), active_count)?,
                bound("scan_local_prefix", resource(local_name), local_buffer)?,
                bound(
                    "scan_block_prefix",
                    resource(block_prefix_name),
                    block_prefix,
                )?,
                bound("scan_output_prefix", resource(output_name), output)?,
                bound("scan_total", resource(total_name), total)?,
            ],
        )?;
        let apply = make_group(
            device,
            &self.passes.scan_apply,
            "lir.semantic.scan.apply.bind_group",
            &[
                ("gScan", self.scan_params.as_entire_binding()),
                ("scan_count", active_count.as_entire_binding()),
                ("scan_local_prefix", local_buffer.as_entire_binding()),
                ("scan_block_prefix", block_prefix.as_entire_binding()),
                ("scan_output_prefix", output.as_entire_binding()),
                ("scan_total", total.as_entire_binding()),
            ],
        )?;
        record_direct(
            encoder,
            &self.passes.scan_apply,
            &apply,
            self.capacities.hir_nodes,
        )
    }

    fn validate(&self, pass: PassId, bindings: Vec<BoundGraphResource>) -> Result<()> {
        self.allocations
            .validate_pass_bindings(&self.graph, pass, &bindings)
            .map_err(anyhow::Error::msg)
    }
}

pub(super) fn bound<T>(
    binding: &'static str,
    resource: ResourceId,
    buffer: &LaniusBuffer<T>,
) -> Result<BoundGraphResource> {
    BoundGraphResource::buffer(binding, resource, buffer).map_err(anyhow::Error::msg)
}

pub(super) fn make_group<'a>(
    device: &wgpu::Device,
    pass: &PassData,
    label: &str,
    bindings: &[(&str, wgpu::BindingResource<'a>)],
) -> Result<wgpu::BindGroup> {
    bind_group::validate_exact_binding_names(pass, 0, bindings)?;
    bind_group::create_bind_group_from_bindings(device, Some(label), pass, 0, bindings)
}

pub(super) fn record_direct(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    elements: u32,
) -> Result<()> {
    record_direct_with_offsets(encoder, pass, bind_group, elements, &[])
}

pub(super) fn record_direct_with_offsets(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    elements: u32,
    dynamic_offsets: &[u32],
) -> Result<()> {
    if elements == 0 {
        return Ok(());
    }
    let (x, y, z) = plan_workgroups(
        DispatchDim::D1,
        InputElements::Elements1D(elements),
        pass.thread_group_size,
    )?;
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some("lir.semantic"),
        timestamp_writes: None,
    });
    compute.set_pipeline(&pass.pipeline);
    compute.set_bind_group(0, Some(bind_group), dynamic_offsets);
    compute.dispatch_workgroups(x, y, z);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        codegen::{
            lowering_ir::{
                LoweringTarget,
                TargetScheduleKey,
                WasmLirInstruction,
                WasmLirOperands,
                lowering_compiler_graph,
            },
            schedule::GpuStableScheduleSorter,
        },
        gpu::{
            buffers::{
                readback_bytes,
                storage_ro_from_bytes,
                storage_ro_from_u32s,
                storage_rw_for_array,
                tracked_buffer_allocation_stats,
            },
            compiler_graph::CompilerGraphWorkspace,
            device,
            passes_core::{map_readback_blocking, pipeline_creation_count},
        },
        parser::buffers::{HirCallArg, HirCore, HirMethodCore, HirMethodSignature, HirPayload},
    };

    fn words<const N: usize>(records: &[[u32; N]]) -> Vec<u8> {
        records
            .iter()
            .flat_map(|record| record.iter())
            .flat_map(|word| word.to_le_bytes())
            .collect()
    }

    fn checked_calls(
        device: &wgpu::Device,
        label: &str,
        records: &[[u32; 10]],
    ) -> LaniusBuffer<crate::type_checker::GpuCheckedCallArtifact> {
        let records = records
            .iter()
            .map(|record| {
                let mut complete = [u32::MAX; 11];
                complete[..10].copy_from_slice(record);
                complete
            })
            .collect::<Vec<_>>();
        storage_ro_from_bytes(device, label, &words(&records), records.len().max(1))
    }

    fn absent_checked_calls(
        device: &wgpu::Device,
        label: &str,
        count: usize,
    ) -> LaniusBuffer<crate::type_checker::GpuCheckedCallArtifact> {
        let absent = [
            u32::MAX,
            u32::MAX,
            u32::MAX,
            u32::MAX,
            u32::MAX,
            0,
            u32::MAX,
            u32::MAX,
            0,
            0,
            u32::MAX,
        ];
        storage_ro_from_bytes(device, label, &words(&vec![absent; count]), count.max(1))
    }

    fn empty_method_families(
        device: &wgpu::Device,
        label: &str,
    ) -> (
        LaniusBuffer<u32>,
        LaniusBuffer<HirMethodCore>,
        LaniusBuffer<HirMethodSignature>,
    ) {
        let count = storage_ro_from_u32s(device, &format!("{label}.count"), &[0]);
        let cores = storage_ro_from_bytes::<HirMethodCore>(
            device,
            &format!("{label}.cores"),
            &words(&[[u32::MAX; 4]]),
            1,
        );
        let signatures = storage_ro_from_bytes::<HirMethodSignature>(
            device,
            &format!("{label}.signatures"),
            &words(&[[u32::MAX; 4]]),
            1,
        );
        (count, cores, signatures)
    }

    fn read_words(device: &wgpu::Device, buffer: &LaniusBuffer<u8>) -> Vec<u32> {
        let slice = buffer.slice(..);
        map_readback_blocking(device, &slice, "semantic LIR test readback").unwrap();
        let mapped = slice.get_mapped_range();
        let result = mapped
            .chunks_exact(4)
            .map(|bytes| u32::from_le_bytes(bytes.try_into().unwrap()))
            .collect();
        drop(mapped);
        buffer.unmap();
        result
    }

    #[repr(C)]
    #[derive(Clone, Copy, ShaderType)]
    struct WasmCountTestParams {
        semantic_capacity: u32,
        semantic_start: u32,
        page_capacity: u32,
        reserved: u32,
    }

    #[repr(C)]
    #[derive(Clone, Copy, ShaderType)]
    struct WasmScatterTestParams {
        semantic_capacity: u32,
        target_capacity: u32,
        target_start: u32,
        page_capacity: u32,
    }

    #[repr(C)]
    #[derive(Clone, Copy, ShaderType)]
    struct WasmRadixTestParams {
        target_capacity: u32,
        max_blocks: u32,
        key_step: u32,
        reserved: u32,
    }

    #[test]
    fn physical_gpu_stably_sorts_wasm_schedule_across_workgroups() {
        let gpu = device::global();
        let count = 600u32;
        let blocks = count.div_ceil(256);
        let slots = blocks * 256;
        let key_words = (0..count)
            .map(|row| {
                [
                    (row * 17) % 5,
                    (row * 13) % 11,
                    (row * 7) % 19,
                    !((row * 3) % 23),
                ]
            })
            .collect::<Vec<_>>();
        let target_total = storage_ro_from_u32s(&gpu.device, "test.schedule.total", &[count]);
        let keys = storage_ro_from_bytes::<TargetScheduleKey>(
            &gpu.device,
            "test.schedule.keys",
            &words(&key_words),
            count as usize,
        );
        let initial_order = (0..count).collect::<Vec<_>>();
        let order_a = storage_ro_from_u32s(&gpu.device, "test.schedule.order_a", &initial_order);
        let order_b =
            storage_rw_for_array::<u32>(&gpu.device, "test.schedule.order_b", count as usize);
        let slot_count = storage_rw_for_array::<u32>(&gpu.device, "test.schedule.slot_count", 1);
        let histogram =
            storage_rw_for_array::<u32>(&gpu.device, "test.schedule.histogram", slots as usize);
        let global_prefix =
            storage_rw_for_array::<u32>(&gpu.device, "test.schedule.global_prefix", slots as usize);
        let scan_local =
            storage_rw_for_array::<u32>(&gpu.device, "test.schedule.scan_local", slots as usize);
        let scan_blocks = slots.div_ceil(256);
        let scan_block_sum = storage_rw_for_array::<u32>(
            &gpu.device,
            "test.schedule.scan_block_sum",
            scan_blocks as usize,
        );
        let scan_block_prefix = storage_rw_for_array::<u32>(
            &gpu.device,
            "test.schedule.scan_block_prefix",
            scan_blocks as usize,
        );
        let scan_hierarchy = storage_rw_for_array::<u32>(
            &gpu.device,
            "test.schedule.scan_hierarchy",
            scan_blocks as usize,
        );
        let scan_total = storage_rw_for_array::<u32>(&gpu.device, "test.schedule.scan_total", 1);

        let slot_params = uniform_from_val(
            &gpu.device,
            "test.schedule.slot_params",
            &WasmRadixTestParams {
                target_capacity: count,
                max_blocks: blocks,
                key_step: 0,
                reserved: 0,
            },
        );
        let scan_params = uniform_from_val(
            &gpu.device,
            "test.schedule.scan_params",
            &ScanParams {
                n_items: slots,
                n_blocks: scan_blocks,
                scan_step: 0,
            },
        );
        let scan_levels = hierarchical_scan_levels(scan_blocks);
        let hierarchy_params = scan_levels
            .iter()
            .enumerate()
            .map(|(index, level)| {
                let parent = scan_levels.get(index + 1);
                uniform_from_val(
                    &gpu.device,
                    &format!("test.schedule.hierarchy.{index}"),
                    &ScanHierarchyParams {
                        n_items: slots,
                        n_blocks: scan_blocks,
                        level_divisor: level.divisor,
                        level_offset: level.offset,
                        parent_divisor: parent.map_or(0, |parent| parent.divisor),
                        parent_offset: parent.map_or(0, |parent| parent.offset),
                    },
                )
            })
            .collect::<Vec<_>>();
        let slot_pass = make_pass_data_from_shader_key(
            &gpu.device,
            "test.schedule.slot_count",
            "main",
            "codegen/lir/schedule/slot_count",
        )
        .unwrap();
        let histogram_pass = make_pass_data_from_shader_key(
            &gpu.device,
            "test.schedule.histogram",
            "main",
            "codegen/lir/schedule/histogram",
        )
        .unwrap();
        let scatter_pass = make_pass_data_from_shader_key(
            &gpu.device,
            "test.schedule.scatter",
            "main",
            "codegen/lir/schedule/scatter",
        )
        .unwrap();
        let scan_local_pass = make_pass_data_from_shader_key(
            &gpu.device,
            "test.schedule.scan.local",
            "main",
            "scan/counted/00_local",
        )
        .unwrap();
        let scan_up_pass = make_pass_data_from_shader_key(
            &gpu.device,
            "test.schedule.scan.up",
            "main",
            "scan/counted/01_hierarchy_up",
        )
        .unwrap();
        let scan_down_pass = make_pass_data_from_shader_key(
            &gpu.device,
            "test.schedule.scan.down",
            "main",
            "scan/counted/02_hierarchy_down",
        )
        .unwrap();
        let scan_apply_pass = make_pass_data_from_shader_key(
            &gpu.device,
            "test.schedule.scan.apply",
            "main",
            "scan/counted/02_apply",
        )
        .unwrap();
        let slot_group = make_group(
            &gpu.device,
            &slot_pass,
            "test.schedule.slot.group",
            &[
                ("gParams", slot_params.as_entire_binding()),
                ("target_lir_total", target_total.as_entire_binding()),
                ("target_schedule_slot_count", slot_count.as_entire_binding()),
            ],
        )
        .unwrap();
        let scan_local_group = make_group(
            &gpu.device,
            &scan_local_pass,
            "test.schedule.scan.local.group",
            &[
                ("gScan", scan_params.as_entire_binding()),
                ("scan_count", slot_count.as_entire_binding()),
                ("scan_input", histogram.as_entire_binding()),
                ("scan_local_prefix", scan_local.as_entire_binding()),
                ("scan_block_sum", scan_block_sum.as_entire_binding()),
            ],
        )
        .unwrap();
        let scan_apply_group = make_group(
            &gpu.device,
            &scan_apply_pass,
            "test.schedule.scan.apply.group",
            &[
                ("gScan", scan_params.as_entire_binding()),
                ("scan_count", slot_count.as_entire_binding()),
                ("scan_local_prefix", scan_local.as_entire_binding()),
                ("scan_block_prefix", scan_block_prefix.as_entire_binding()),
                ("scan_output_prefix", global_prefix.as_entire_binding()),
                ("scan_total", scan_total.as_entire_binding()),
            ],
        )
        .unwrap();

        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.schedule.encoder"),
            });
        record_direct(&mut encoder, &slot_pass, &slot_group, 1).unwrap();
        for key_step in 0..16u32 {
            let params = uniform_from_val(
                &gpu.device,
                &format!("test.schedule.radix.{key_step}"),
                &WasmRadixTestParams {
                    target_capacity: count,
                    max_blocks: blocks,
                    key_step,
                    reserved: 0,
                },
            );
            let (input, output) = if key_step % 2 == 0 {
                (&order_a, &order_b)
            } else {
                (&order_b, &order_a)
            };
            let histogram_group = make_group(
                &gpu.device,
                &histogram_pass,
                "test.schedule.histogram.group",
                &[
                    ("gParams", params.as_entire_binding()),
                    ("target_lir_total", target_total.as_entire_binding()),
                    ("target_schedule_key", keys.as_entire_binding()),
                    ("target_schedule_order_in", input.as_entire_binding()),
                    ("target_schedule_histogram", histogram.as_entire_binding()),
                ],
            )
            .unwrap();
            let scatter_group = make_group(
                &gpu.device,
                &scatter_pass,
                "test.schedule.scatter.group",
                &[
                    ("gParams", params.as_entire_binding()),
                    ("target_lir_total", target_total.as_entire_binding()),
                    ("target_schedule_key", keys.as_entire_binding()),
                    ("target_schedule_order_in", input.as_entire_binding()),
                    (
                        "target_schedule_global_prefix",
                        global_prefix.as_entire_binding(),
                    ),
                    ("target_schedule_order_out", output.as_entire_binding()),
                ],
            )
            .unwrap();
            record_direct(&mut encoder, &histogram_pass, &histogram_group, count).unwrap();
            record_direct(&mut encoder, &scan_local_pass, &scan_local_group, slots).unwrap();
            for (index, level) in scan_levels.iter().enumerate() {
                let group = make_group(
                    &gpu.device,
                    &scan_up_pass,
                    "test.schedule.scan.up.group",
                    &[
                        ("gHierarchy", hierarchy_params[index].as_entire_binding()),
                        ("scan_count", slot_count.as_entire_binding()),
                        ("scan_block_sum", scan_block_sum.as_entire_binding()),
                        ("scan_block_prefix", scan_block_prefix.as_entire_binding()),
                        ("scan_hierarchy", scan_hierarchy.as_entire_binding()),
                    ],
                )
                .unwrap();
                record_direct(&mut encoder, &scan_up_pass, &group, level.count).unwrap();
            }
            for child_index in (0..scan_levels.len().saturating_sub(1)).rev() {
                let level = scan_levels[child_index];
                let group = make_group(
                    &gpu.device,
                    &scan_down_pass,
                    "test.schedule.scan.down.group",
                    &[
                        (
                            "gHierarchy",
                            hierarchy_params[child_index].as_entire_binding(),
                        ),
                        ("scan_count", slot_count.as_entire_binding()),
                        ("scan_block_prefix", scan_block_prefix.as_entire_binding()),
                        ("scan_hierarchy", scan_hierarchy.as_entire_binding()),
                    ],
                )
                .unwrap();
                record_direct(&mut encoder, &scan_down_pass, &group, level.count).unwrap();
            }
            record_direct(&mut encoder, &scan_apply_pass, &scan_apply_group, slots).unwrap();
            record_direct(&mut encoder, &scatter_pass, &scatter_group, count).unwrap();
        }
        let readback = readback_bytes(
            &gpu.device,
            "test.schedule.order.readback",
            count as usize * 4,
            count as usize,
        );
        encoder.copy_buffer_to_buffer(
            &order_a.buffer,
            0,
            &readback.buffer,
            0,
            u64::from(count) * 4,
        );
        gpu.queue.submit(Some(encoder.finish()));

        let actual = read_words(&gpu.device, &readback);
        let mut expected = initial_order;
        expected.sort_by_key(|&row| key_words[row as usize]);
        assert_eq!(actual, expected);
    }

    #[test]
    fn physical_gpu_resident_scheduler_uses_graph_workspace_without_record_allocations() {
        let gpu = device::global();
        let count = 600u32;
        let capacities = LoweringCapacities {
            source_bytes: count,
            tokens: count,
            hir_nodes: count,
            semantic_instructions: count,
            call_arguments: 1,
            parameters: 1,
            aggregate_elements: 1,
            target_instructions: count,
            artifact_bytes: 1,
        };
        let graph = lowering_compiler_graph(capacities, LoweringTarget::Wasm).unwrap();
        let workspace =
            CompilerGraphWorkspace::new(&gpu.device, "test.resident_schedule", &graph).unwrap();
        let alias_u32 = |name: &str, rows: usize| {
            workspace
                .alias(&graph, graph.resource_id(name).unwrap(), rows)
                .unwrap()
        };
        let total: LaniusBuffer<u32> = alias_u32("lir.semantic.total", 1);
        let keys: LaniusBuffer<TargetScheduleKey> = workspace
            .alias(
                &graph,
                graph.resource_id("lir.semantic.schedule").unwrap(),
                count as usize,
            )
            .unwrap();
        let order: LaniusBuffer<u32> = alias_u32("lir.semantic.schedule_order", count as usize);
        let key_words = (0..count)
            .map(|row| {
                [
                    (row * 17) % 5,
                    (row * 13) % 11,
                    (row * 7) % 19,
                    !((row * 3) % 23),
                ]
            })
            .collect::<Vec<_>>();
        let initial_order = (0..count).collect::<Vec<_>>();
        gpu.queue
            .write_buffer(&total.buffer, 0, &count.to_le_bytes());
        gpu.queue.write_buffer(&keys.buffer, 0, &words(&key_words));
        let order_bytes = initial_order
            .iter()
            .flat_map(|word| word.to_le_bytes())
            .collect::<Vec<_>>();
        gpu.queue.write_buffer(&order.buffer, 0, &order_bytes);

        let sorter = GpuStableScheduleSorter::new_semantic(
            &gpu.device,
            &graph,
            &workspace,
            &workspace.allocations(),
            count,
            &total,
            &keys,
            &order,
        )
        .unwrap();
        let pipelines_before = pipeline_creation_count();
        let buffers_before = tracked_buffer_allocation_stats();
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.resident_schedule.encoder"),
            });
        sorter.record(&mut encoder).unwrap();
        assert_eq!(pipeline_creation_count(), pipelines_before);
        assert_eq!(tracked_buffer_allocation_stats(), buffers_before);

        let readback = readback_bytes(
            &gpu.device,
            "test.resident_schedule.readback",
            count as usize * 4,
            count as usize,
        );
        encoder.copy_buffer_to_buffer(
            &sorter.output_order().buffer,
            0,
            &readback.buffer,
            0,
            u64::from(count) * 4,
        );
        gpu.queue.submit(Some(encoder.finish()));
        let actual = read_words(&gpu.device, &readback);
        let mut expected = initial_order;
        expected.sort_by_key(|&row| key_words[row as usize]);
        assert_eq!(actual, expected);
    }

    #[test]
    fn physical_gpu_lowers_semantic_lir_to_wasm_lir() {
        let gpu = device::global();
        let semantic_total = storage_ro_from_u32s(&gpu.device, "test.wasm_lir.total", &[5]);
        let semantic_core = storage_ro_from_bytes::<SemanticLirCore>(
            &gpu.device,
            "test.wasm_lir.semantic_core",
            &words(&[
                [
                    super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_CONST_I32,
                    3,
                    0,
                    u32::MAX,
                    0,
                    0,
                    0,
                ],
                [
                    super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_CONST_I32,
                    3,
                    0,
                    u32::MAX,
                    1,
                    0,
                    0,
                ],
                [
                    super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_ADD,
                    3,
                    0,
                    u32::MAX,
                    2,
                    0,
                    0,
                ],
                [
                    super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_RETURN,
                    0,
                    0,
                    u32::MAX,
                    3,
                    0,
                    0,
                ],
                [
                    super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_CALL_SYMBOL,
                    3,
                    0,
                    u32::MAX,
                    4,
                    0,
                    0,
                ],
            ]),
            5,
        );
        let semantic_operands = storage_ro_from_bytes::<SemanticLirOperands>(
            &gpu.device,
            "test.wasm_lir.semantic_operands",
            &words(&[
                [0, 7, u32::MAX, u32::MAX],
                [1, 9, u32::MAX, u32::MAX],
                [2, 0, 1, u32::MAX],
                [3, 2, u32::MAX, u32::MAX],
                [4, 7, 11, 23],
            ]),
            5,
        );
        let semantic_aggregate_elements = storage_ro_from_bytes::<SemanticLirAggregateElement>(
            &gpu.device,
            "test.wasm_lir.aggregate_elements",
            &words(&[[u32::MAX; 5]]),
            1,
        );
        let semantic_string_total =
            storage_ro_from_u32s(&gpu.device, "test.wasm_lir.string_total", &[0]);
        let semantic_strings = storage_ro_from_bytes::<SemanticLirString>(
            &gpu.device,
            "test.wasm_lir.strings",
            &words(&[[u32::MAX; 4]]),
            1,
        );
        let offsets = storage_ro_from_u32s(&gpu.device, "test.wasm_lir.offsets", &[0, 1, 2, 3, 4]);
        let target_total = storage_ro_from_u32s(&gpu.device, "test.wasm_lir.target_total", &[5]);
        let target_counts = storage_rw_for_array::<u32>(&gpu.device, "test.wasm_lir.counts", 5);
        let semantic_order =
            storage_ro_from_u32s(&gpu.device, "test.wasm_lir.order", &[0, 1, 2, 3, 4]);
        let semantic_owner =
            storage_ro_from_u32s(&gpu.device, "test.wasm_lir.owner", &[0, 1, 2, 3, 4]);
        let semantic_function =
            storage_ro_from_u32s(&gpu.device, "test.wasm_lir.function_by_hir", &[u32::MAX; 5]);
        let semantic_to_target =
            storage_rw_for_array::<u32>(&gpu.device, "test.wasm_lir.semantic_to_target", 5);
        let target_core =
            storage_rw_for_array::<WasmLirInstruction>(&gpu.device, "test.wasm_lir.core", 5);
        let target_operands =
            storage_rw_for_array::<WasmLirOperands>(&gpu.device, "test.wasm_lir.operands", 5);
        let count_params = uniform_from_val(
            &gpu.device,
            "test.wasm_lir.count_params",
            &WasmCountTestParams {
                semantic_capacity: 5,
                semantic_start: 0,
                page_capacity: 5,
                reserved: 0,
            },
        );
        let scatter_params = uniform_from_val(
            &gpu.device,
            "test.wasm_lir.scatter_params",
            &WasmScatterTestParams {
                semantic_capacity: 5,
                target_capacity: 5,
                target_start: 0,
                page_capacity: 5,
            },
        );
        let count_pass = make_pass_data_from_shader_key(
            &gpu.device,
            "test.wasm_lir.count",
            "main",
            "codegen/lir/wasm/count",
        )
        .unwrap();
        let scatter_pass = make_pass_data_from_shader_key(
            &gpu.device,
            "test.wasm_lir.scatter",
            "main",
            "codegen/lir/wasm/scatter",
        )
        .unwrap();
        let count_group = make_group(
            &gpu.device,
            &count_pass,
            "test.wasm_lir.count.group",
            &[
                ("gParams", count_params.as_entire_binding()),
                ("semantic_lir_total", semantic_total.as_entire_binding()),
                ("semantic_lir_core", semantic_core.as_entire_binding()),
                (
                    "semantic_lir_operands",
                    semantic_operands.as_entire_binding(),
                ),
                (
                    "semantic_schedule_order",
                    semantic_order.as_entire_binding(),
                ),
                ("target_lir_count", target_counts.as_entire_binding()),
            ],
        )
        .unwrap();
        let scatter_group = make_group(
            &gpu.device,
            &scatter_pass,
            "test.wasm_lir.scatter.group",
            &[
                ("gParams", scatter_params.as_entire_binding()),
                ("semantic_lir_total", semantic_total.as_entire_binding()),
                ("semantic_lir_core", semantic_core.as_entire_binding()),
                (
                    "semantic_lir_operands",
                    semantic_operands.as_entire_binding(),
                ),
                (
                    "semantic_owner_by_instruction",
                    semantic_owner.as_entire_binding(),
                ),
                (
                    "semantic_function_id_by_hir",
                    semantic_function.as_entire_binding(),
                ),
                (
                    "semantic_schedule_order",
                    semantic_order.as_entire_binding(),
                ),
                (
                    "semantic_lir_aggregate_elements",
                    semantic_aggregate_elements.as_entire_binding(),
                ),
                (
                    "semantic_lir_string_total",
                    semantic_string_total.as_entire_binding(),
                ),
                ("semantic_lir_strings", semantic_strings.as_entire_binding()),
                ("target_lir_offset", offsets.as_entire_binding()),
                ("target_lir_total", target_total.as_entire_binding()),
                (
                    "semantic_to_target_start",
                    semantic_to_target.as_entire_binding(),
                ),
                ("target_lir_core", target_core.as_entire_binding()),
                ("target_lir_operands", target_operands.as_entire_binding()),
            ],
        )
        .unwrap();
        let count_readback = readback_bytes(&gpu.device, "test.wasm_lir.count.rb", 20, 5);
        let core_readback = readback_bytes(&gpu.device, "test.wasm_lir.core.rb", 80, 20);
        let operands_readback = readback_bytes(&gpu.device, "test.wasm_lir.operands.rb", 80, 20);
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.wasm_lir.encoder"),
            });
        record_direct(&mut encoder, &count_pass, &count_group, 5).unwrap();
        record_direct(&mut encoder, &scatter_pass, &scatter_group, 5).unwrap();
        encoder.copy_buffer_to_buffer(&target_counts.buffer, 0, &count_readback.buffer, 0, 20);
        encoder.copy_buffer_to_buffer(&target_core.buffer, 0, &core_readback.buffer, 0, 80);
        encoder.copy_buffer_to_buffer(&target_operands.buffer, 0, &operands_readback.buffer, 0, 80);
        gpu.queue.submit(Some(encoder.finish()));

        assert_eq!(read_words(&gpu.device, &count_readback), &[1, 1, 1, 1, 1]);
        let core = read_words(&gpu.device, &core_readback);
        assert_eq!(
            [core[0], core[4], core[8], core[12], core[16]],
            [
                super::super::lowering_ir::opcode::WASM_LIR_OP_I32_CONST,
                super::super::lowering_ir::opcode::WASM_LIR_OP_I32_CONST,
                super::super::lowering_ir::opcode::WASM_LIR_OP_I32_ADD,
                super::super::lowering_ir::opcode::WASM_LIR_OP_RETURN,
                super::super::lowering_ir::opcode::WASM_LIR_OP_CALL_SYMBOL,
            ]
        );
        assert_eq!([core[1], core[5]], [7, 9]);
        assert_eq!(
            &read_words(&gpu.device, &operands_readback)[16..19],
            &[7, 11, 23]
        );
    }

    #[test]
    fn physical_gpu_lowers_scalar_dependency_graph() {
        let gpu = device::global();
        let hir_rows = [
            [23, u32::MAX, 0, 1],
            [23, u32::MAX, 2, 3],
            [16, u32::MAX, 0, 3],
            [7, u32::MAX, 0, 4],
            [22, u32::MAX, 5, 6],
            [19, u32::MAX, 5, 8],
            [3, u32::MAX, 10, 14],
            [22, 6, 11, 12],
            [19, 6, 11, 14],
            [19, 6, 13, 16],
        ];
        let payload_rows = [
            [3, 7, u32::MAX, 0],
            [3, 9, u32::MAX, 2],
            [14, 0, 1, u32::MAX],
            [2, 2, u32::MAX, 0],
            [2, u32::MAX, u32::MAX, 5],
            [4, u32::MAX, 0, u32::MAX],
            [5, 11, u32::MAX, u32::MAX],
            [2, u32::MAX, u32::MAX, 11],
            [7, u32::MAX, 0, u32::MAX],
            [7, 13, u32::MAX, u32::MAX],
        ];
        let hir_count = storage_ro_from_u32s(&gpu.device, "test.lir.hir_count", &[10]);
        let hir_core = storage_ro_from_bytes::<HirCore>(
            &gpu.device,
            "test.lir.hir_core",
            &words(&hir_rows),
            10,
        );
        let hir_links = storage_ro_from_bytes::<crate::parser::buffers::HirLinks>(
            &gpu.device,
            "test.lir.hir_links",
            &words(&[
                [u32::MAX, 1, 1, 0],
                [u32::MAX, 2, 2, 0],
                [0, 3, 3, 0],
                [2, 4, 4, 0],
                [u32::MAX, 5, 5, 0],
                [4, u32::MAX, 6, 0],
                [7, u32::MAX, 10, 0],
                [u32::MAX, 8, 8, 0],
                [7, 9, 9, 0],
                [u32::MAX, u32::MAX, 10, 0],
            ]),
            10,
        );
        let hir_payload = storage_ro_from_bytes::<HirPayload>(
            &gpu.device,
            "test.lir.hir_payload",
            &words(&payload_rows),
            10,
        );
        let expr_parent = storage_ro_from_u32s(
            &gpu.device,
            "test.lir.expr_parent",
            &[
                2,
                2,
                u32::MAX,
                u32::MAX,
                5,
                u32::MAX,
                u32::MAX,
                8,
                u32::MAX,
                u32::MAX,
            ],
        );
        let expr_root = storage_ro_from_u32s(
            &gpu.device,
            "test.lir.expr_root",
            &[2, 2, 2, 3, 5, 5, 6, 8, 8, 9],
        );
        let call_arg_count = storage_ro_from_u32s(&gpu.device, "test.lir.arg_count", &[0]);
        let call_args = storage_ro_from_bytes::<HirCallArg>(
            &gpu.device,
            "test.lir.args",
            &words(&[[u32::MAX; 4]]),
            1,
        );
        let family_count = storage_ro_from_u32s(&gpu.device, "test.lir.family_count", &[0]);
        let family_by_hir = storage_ro_from_u32s(&gpu.device, "test.lir.family_by_hir", &[0; 10]);
        let fields = storage_ro_from_bytes::<crate::parser::buffers::HirField>(
            &gpu.device,
            "test.lir.fields",
            &words(&[[u32::MAX; 4]]),
            1,
        );
        let params = storage_ro_from_bytes::<crate::parser::buffers::HirParam>(
            &gpu.device,
            "test.lir.params",
            &words(&[[u32::MAX; 4]]),
            1,
        );
        let param_ranges = storage_ro_from_bytes::<crate::parser::buffers::HirRange>(
            &gpu.device,
            "test.lir.param_ranges",
            &words(&[[u32::MAX, 0, 0, 0]; 10]),
            10,
        );
        let array_elements = storage_ro_from_bytes::<crate::parser::buffers::HirArrayElement>(
            &gpu.device,
            "test.lir.array_elements",
            &words(&[[u32::MAX; 4]]),
            1,
        );
        let strings = storage_ro_from_bytes::<crate::parser::buffers::HirString>(
            &gpu.device,
            "test.lir.strings",
            &words(&[[u32::MAX; 4]; 10]),
            10,
        );
        let string_data = storage_ro_from_u32s(&gpu.device, "test.lir.string_data", &[0; 4]);
        let expression_types = storage_ro_from_u32s(
            &gpu.device,
            "test.lir.types",
            &[
                3 << 28,
                3 << 28,
                3 << 28,
                0,
                0,
                1 << 28,
                0,
                0,
                3 << 28,
                3 << 28,
            ],
        );
        let visible = storage_ro_from_u32s(&gpu.device, "test.lir.visible", &[u32::MAX; 16]);
        let checked_layout_facts =
            storage_ro_from_u32s(&gpu.device, "test.lir.checked_layout_facts", &[0; 16]);
        let mut enclosing_fn = [0u32; 16];
        enclosing_fn[0] = 7;
        enclosing_fn[2] = 7;
        enclosing_fn[5] = 7;
        enclosing_fn[10] = 7;
        enclosing_fn[11] = 7;
        enclosing_fn[13] = 7;
        let enclosing_fn =
            storage_ro_from_u32s(&gpu.device, "test.lir.enclosing_fn", &enclosing_fn);
        let checked_enclosing_fn =
            storage_ro_from_u32s(&gpu.device, "test.lir.checked_enclosing_fn", &[7; 10]);
        let absent_call = [
            u32::MAX,
            u32::MAX,
            u32::MAX,
            u32::MAX,
            u32::MAX,
            0,
            u32::MAX,
            u32::MAX,
            0,
            0,
        ];
        let mut call_records = [absent_call; 10];
        call_records[5] = [
            u32::MAX,
            u32::MAX,
            u32::MAX,
            u32::MAX,
            u32::MAX,
            7,
            7,
            u32::MAX,
            0,
            0,
        ];
        call_records[8] = [
            10,
            u32::MAX,
            u32::MAX,
            u32::MAX,
            u32::MAX,
            0,
            7,
            u32::MAX,
            0,
            0,
        ];
        call_records[9] = [u32::MAX, 7, 11, 23, u32::MAX, 0, 7, u32::MAX, 0, 0];
        let checked_calls = checked_calls(&gpu.device, "test.lir.checked_calls", &call_records);
        let semantic_ref_tags = storage_ro_from_u32s(
            &gpu.device,
            "test.lir.semantic_ref_tags",
            &[1, 1, 1, 0, 0, 1, 0, 0, 1, 3],
        );
        let semantic_ref_payloads = storage_ro_from_u32s(
            &gpu.device,
            "test.lir.semantic_ref_payloads",
            &[3, 3, 3, u32::MAX, u32::MAX, 7, u32::MAX, u32::MAX, 7, 42],
        );
        let semantic_array_lengths = storage_ro_from_u32s(
            &gpu.device,
            "test.lir.semantic_array_lengths",
            &[u32::MAX; 10],
        );
        let capacities = LoweringCapacities {
            source_bytes: 16,
            tokens: 16,
            hir_nodes: 10,
            semantic_instructions: 9,
            call_arguments: 1,
            parameters: 1,
            aggregate_elements: 1,
            target_instructions: 9,
            artifact_bytes: 64,
        };
        let graph = super::super::lowering_ir::lowering_compiler_graph(
            capacities,
            super::super::lowering_ir::LoweringTarget::X86_64,
        )
        .unwrap();
        let workspace = CompilerGraphWorkspace::new(&gpu.device, "test.lir", &graph).unwrap();
        let stage =
            GpuSemanticLoweringStage::from_workspace(&gpu.device, capacities, graph, &workspace)
                .unwrap();
        let (method_count, method_cores, method_signatures) =
            empty_method_families(&gpu.device, "test.semantic_lir.methods");
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.semantic_lir.encoder"),
            });
        stage
            .record(
                &gpu.device,
                &mut encoder,
                GpuSemanticHirInputs {
                    count: &hir_count,
                    core: &hir_core,
                    links: &hir_links,
                    payload: &hir_payload,
                    const_value: &expr_root,
                    expr_parent: &expr_parent,
                    expr_root: &expr_root,
                    nearest_loop: &expr_root,
                    call_arg_count: &call_arg_count,
                    call_args: &call_args,
                    field_count: &family_count,
                    fields: &fields,
                    array_element_start: &family_by_hir,
                    array_element_count: &family_by_hir,
                    array_element_row_count: &family_count,
                    array_elements: &array_elements,
                    string_count: &family_count,
                    strings: &strings,
                    string_data_words: &string_data,
                    string_pool_len: &family_count,
                    param_count: &family_count,
                    params: &params,
                    param_ranges: &param_ranges,
                    method_count: &method_count,
                    method_cores: &method_cores,
                    method_signatures: &method_signatures,
                },
                GpuSemanticArtifactView {
                    value_decl_by_hir: &visible,
                    value_type_by_hir: &enclosing_fn,
                    value_const_by_hir: &checked_layout_facts,
                    value_const_present_by_hir: &checked_layout_facts,
                    param_type_by_row: &visible,
                    enclosing_fn_by_hir: &checked_enclosing_fn,
                    function_return_type_by_hir: &enclosing_fn,
                    function_entrypoint_by_hir: &enclosing_fn,
                    function_host_service_by_hir: &semantic_array_lengths,
                    control_depth_by_hir: &enclosing_fn,
                    calls_by_hir: &checked_calls,
                    expr_ref_tag_by_hir: &semantic_ref_tags,
                    expr_ref_payload_by_hir: &semantic_ref_payloads,
                    aggregate_decl_token_by_hir: &semantic_ref_payloads,
                    aggregate_word_count_by_hir: &checked_layout_facts,
                    array_length_by_hir: &semantic_array_lengths,
                    member_field_ordinal_by_hir: &visible,
                    iterable_kind_by_hir: &checked_layout_facts,
                    function_result_word_count_by_hir: &checked_layout_facts,
                    expr_scalar_type_by_hir: &expression_types,
                    public_decl_index_by_hir: &visible,
                    struct_init_field_ordinal_by_row: &visible,
                },
            )
            .unwrap();
        let output = stage.output();
        let count_readback = readback_bytes(&gpu.device, "test.lir.count.rb", 4, 1);
        let core_readback = readback_bytes(&gpu.device, "test.lir.core.rb", 252, 63);
        let operands_readback = readback_bytes(&gpu.device, "test.lir.operands.rb", 144, 36);
        let owner_readback = readback_bytes(&gpu.device, "test.lir.owner.rb", 36, 9);
        let order_readback = readback_bytes(&gpu.device, "test.lir.order.rb", 36, 9);
        let scheduled_core_readback =
            readback_bytes(&gpu.device, "test.lir.scheduled_core.rb", 252, 63);
        let scheduled_operands_readback =
            readback_bytes(&gpu.device, "test.lir.scheduled_operands.rb", 144, 36);
        encoder.copy_buffer_to_buffer(&output.count.buffer, 0, &count_readback.buffer, 0, 4);
        encoder.copy_buffer_to_buffer(&output.core.buffer, 0, &core_readback.buffer, 0, 252);
        encoder.copy_buffer_to_buffer(
            &output.operands.buffer,
            0,
            &operands_readback.buffer,
            0,
            144,
        );
        encoder.copy_buffer_to_buffer(
            &output.owner_by_instruction.buffer,
            0,
            &owner_readback.buffer,
            0,
            36,
        );
        encoder.copy_buffer_to_buffer(
            &output.execution_order.unwrap().buffer,
            0,
            &order_readback.buffer,
            0,
            36,
        );
        encoder.copy_buffer_to_buffer(
            &stage.core.buffer,
            0,
            &scheduled_core_readback.buffer,
            0,
            252,
        );
        encoder.copy_buffer_to_buffer(
            &stage.operands.buffer,
            0,
            &scheduled_operands_readback.buffer,
            0,
            144,
        );
        gpu.queue.submit(Some(encoder.finish()));

        assert_eq!(read_words(&gpu.device, &count_readback)[0], 7);
        let core = read_words(&gpu.device, &core_readback);
        let owners = read_words(&gpu.device, &owner_readback);
        assert_eq!(
            &owners[..7],
            &core
                .chunks_exact(7)
                .take(7)
                .map(|row| row[4])
                .collect::<Vec<_>>(),
        );
        assert_eq!(
            [
                core[0], core[7], core[14], core[21], core[28], core[35], core[42],
            ],
            [
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_CONST_I32,
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_CONST_I32,
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_ADD,
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_RETURN,
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_CALL_INTRINSIC,
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_CALL,
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_CALL_SYMBOL,
            ]
        );
        assert_eq!([core[2], core[3]], [1, 3]);
        assert_eq!([core[44], core[45]], [3, 42]);
        let operands = read_words(&gpu.device, &operands_readback);
        assert_eq!([operands[1], operands[5]], [7, 9]);
        assert_eq!(&operands[8..12], &[2, 0, 1, u32::MAX]);
        assert_eq!(&operands[12..16], &[3, 2, u32::MAX, u32::MAX]);
        assert_eq!(&operands[16..20], &[4, 7, u32::MAX, 0]);
        assert_eq!(&operands[20..24], &[5, 0, u32::MAX, 0]);
        assert_eq!(&operands[24..28], &[6, 7, 11, 23]);
        let order = read_words(&gpu.device, &order_readback);
        let scheduled_core = read_words(&gpu.device, &scheduled_core_readback);
        let scheduled_operands = read_words(&gpu.device, &scheduled_operands_readback);
        for (scheduled_row, &semantic_row) in order.iter().take(7).enumerate() {
            let semantic_row = semantic_row as usize;
            assert_eq!(
                &scheduled_core[scheduled_row * 7..scheduled_row * 7 + 7],
                &core[semantic_row * 7..semantic_row * 7 + 7],
            );
            assert_eq!(
                &scheduled_operands[scheduled_row * 4..scheduled_row * 4 + 4],
                &operands[semantic_row * 4..semantic_row * 4 + 4],
            );
        }
    }

    #[test]
    fn physical_gpu_projects_dense_function_abi() {
        let gpu = device::global();
        let hir_count = storage_ro_from_u32s(&gpu.device, "test.abi.hir_count", &[4]);
        let hir_core = storage_ro_from_bytes::<HirCore>(
            &gpu.device,
            "test.abi.hir_core",
            &words(&[
                [3, u32::MAX, 4, 11],
                [7, 0, 8, 10],
                [23, 1, 9, 10],
                [32, u32::MAX, 10, 11],
            ]),
            4,
        );
        let hir_links = storage_ro_from_bytes::<crate::parser::buffers::HirLinks>(
            &gpu.device,
            "test.abi.hir_links",
            &words(&[
                [1, 3, 3, 2],
                [2, u32::MAX, 3, 2],
                [u32::MAX, u32::MAX, 3, 2],
                [u32::MAX, u32::MAX, 4, 2],
            ]),
            4,
        );
        let hir_payload = storage_ro_from_bytes::<HirPayload>(
            &gpu.device,
            "test.abi.hir_payload",
            &words(&[
                [0, 5, u32::MAX, u32::MAX],
                [1, 8, 2, u32::MAX],
                [3, 7, u32::MAX, u32::MAX],
                [2, 1, u32::MAX, u32::MAX],
            ]),
            4,
        );
        let no_parent = storage_ro_from_u32s(&gpu.device, "test.abi.no_parent", &[u32::MAX; 4]);
        let identity = storage_ro_from_u32s(&gpu.device, "test.abi.identity", &[0, 1, 2, 3]);
        let zero_count = storage_ro_from_u32s(&gpu.device, "test.abi.zero_count", &[0]);
        let param_count = storage_ro_from_u32s(&gpu.device, "test.abi.param_count", &[2]);
        let params = storage_ro_from_bytes::<crate::parser::buffers::HirParam>(
            &gpu.device,
            "test.abi.params",
            &words(&[[0, 6, u32::MAX, 0], [0, 7, u32::MAX, 1]]),
            2,
        );
        let param_ranges = storage_ro_from_bytes::<crate::parser::buffers::HirRange>(
            &gpu.device,
            "test.abi.param_ranges",
            &words(&[[0, 2], [u32::MAX, 0], [u32::MAX, 0], [u32::MAX, 0]]),
            4,
        );
        let empty_rows = storage_ro_from_bytes::<HirCallArg>(
            &gpu.device,
            "test.abi.empty_rows",
            &words(&[[u32::MAX; 4]; 2]),
            2,
        );
        let empty_fields = storage_ro_from_bytes::<crate::parser::buffers::HirField>(
            &gpu.device,
            "test.abi.empty_fields",
            &words(&[[u32::MAX; 4]; 2]),
            2,
        );
        let empty_array_elements = storage_ro_from_bytes::<crate::parser::buffers::HirArrayElement>(
            &gpu.device,
            "test.abi.empty_array_elements",
            &words(&[[u32::MAX; 4]; 2]),
            2,
        );
        let empty_strings = storage_ro_from_bytes::<crate::parser::buffers::HirString>(
            &gpu.device,
            "test.abi.empty_strings",
            &words(&[[u32::MAX; 4]; 4]),
            4,
        );
        let zero_by_hir = storage_ro_from_u32s(&gpu.device, "test.abi.zero_by_hir", &[0; 4]);
        let string_data = storage_ro_from_u32s(&gpu.device, "test.abi.string_data", &[0; 4]);
        let checked_value_decls = storage_ro_from_u32s(
            &gpu.device,
            "test.abi.checked_value_decls",
            &[u32::MAX, 8, u32::MAX, u32::MAX],
        );
        let checked_value_types =
            storage_ro_from_u32s(&gpu.device, "test.abi.checked_value_types", &[0, 3, 0, 0]);
        let checked_param_types =
            storage_ro_from_u32s(&gpu.device, "test.abi.checked_param_types", &[3, 7]);
        let mut return_types = vec![0; 12];
        return_types[0] = 3;
        let return_types =
            storage_ro_from_u32s(&gpu.device, "test.abi.return_types", &return_types);
        let mut entrypoints = vec![0; 12];
        entrypoints[0] = 1;
        let entrypoints = storage_ro_from_u32s(&gpu.device, "test.abi.entrypoints", &entrypoints);
        let public_declarations = storage_ro_from_u32s(
            &gpu.device,
            "test.abi.public_declarations",
            &[23, u32::MAX, u32::MAX, u32::MAX],
        );
        let invalid_tokens =
            storage_ro_from_u32s(&gpu.device, "test.abi.invalid_tokens", &[u32::MAX; 12]);
        let _language_names =
            storage_ro_from_u32s(&gpu.device, "test.abi.language_names", &[u32::MAX; 67]);
        let mut enclosing_functions = vec![0; 12];
        enclosing_functions[8] = 1;
        enclosing_functions[9] = 1;
        let enclosing_functions = storage_ro_from_u32s(
            &gpu.device,
            "test.abi.enclosing_functions",
            &enclosing_functions,
        );
        let checked_enclosing_functions = storage_ro_from_u32s(
            &gpu.device,
            "test.abi.checked_enclosing_functions",
            &[0, 1, 1, 0],
        );
        let checked_calls = absent_checked_calls(&gpu.device, "test.abi.checked_calls", 4);
        let expression_types = storage_ro_from_u32s(
            &gpu.device,
            "test.abi.expression_types",
            &[0, 3 << 28, 3 << 28, 0],
        );
        let semantic_ref_tags =
            storage_ro_from_u32s(&gpu.device, "test.abi.semantic_ref_tags", &[0; 4]);
        let semantic_ref_payloads = storage_ro_from_u32s(
            &gpu.device,
            "test.abi.semantic_ref_payloads",
            &[u32::MAX; 4],
        );
        let semantic_array_lengths = storage_ro_from_u32s(
            &gpu.device,
            "test.abi.semantic_array_lengths",
            &[u32::MAX; 4],
        );
        let stage = GpuSemanticLoweringStage::new(
            &gpu.device,
            LoweringCapacities {
                source_bytes: 12,
                tokens: 12,
                hir_nodes: 4,
                semantic_instructions: 4,
                call_arguments: 2,
                parameters: 2,
                aggregate_elements: 2,
                target_instructions: 4,
                artifact_bytes: 32,
            },
        )
        .unwrap();
        let (method_count, method_cores, method_signatures) =
            empty_method_families(&gpu.device, "test.abi.methods");
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.abi.encoder"),
            });
        stage
            .record(
                &gpu.device,
                &mut encoder,
                GpuSemanticHirInputs {
                    count: &hir_count,
                    core: &hir_core,
                    links: &hir_links,
                    payload: &hir_payload,
                    const_value: &identity,
                    expr_parent: &no_parent,
                    expr_root: &identity,
                    nearest_loop: &no_parent,
                    call_arg_count: &zero_count,
                    call_args: &empty_rows,
                    field_count: &zero_count,
                    fields: &empty_fields,
                    array_element_start: &zero_by_hir,
                    array_element_count: &zero_by_hir,
                    array_element_row_count: &zero_count,
                    array_elements: &empty_array_elements,
                    string_count: &zero_count,
                    strings: &empty_strings,
                    string_data_words: &string_data,
                    string_pool_len: &zero_count,
                    param_count: &param_count,
                    params: &params,
                    param_ranges: &param_ranges,
                    method_count: &method_count,
                    method_cores: &method_cores,
                    method_signatures: &method_signatures,
                },
                GpuSemanticArtifactView {
                    value_decl_by_hir: &checked_value_decls,
                    value_type_by_hir: &checked_value_types,
                    value_const_by_hir: &zero_by_hir,
                    value_const_present_by_hir: &zero_by_hir,
                    param_type_by_row: &checked_param_types,
                    enclosing_fn_by_hir: &checked_enclosing_functions,
                    function_return_type_by_hir: &return_types,
                    function_entrypoint_by_hir: &entrypoints,
                    function_host_service_by_hir: &semantic_array_lengths,
                    control_depth_by_hir: &enclosing_functions,
                    calls_by_hir: &checked_calls,
                    expr_ref_tag_by_hir: &semantic_ref_tags,
                    expr_ref_payload_by_hir: &semantic_ref_payloads,
                    aggregate_decl_token_by_hir: &semantic_ref_payloads,
                    aggregate_word_count_by_hir: &zero_by_hir,
                    array_length_by_hir: &semantic_array_lengths,
                    member_field_ordinal_by_hir: &invalid_tokens,
                    iterable_kind_by_hir: &zero_by_hir,
                    function_result_word_count_by_hir: &zero_by_hir,
                    expr_scalar_type_by_hir: &expression_types,
                    public_decl_index_by_hir: &public_declarations,
                    struct_init_field_ordinal_by_row: &invalid_tokens,
                },
            )
            .unwrap();
        let function_readback = readback_bytes(&gpu.device, "test.abi.functions.rb", 52, 13);
        let param_readback = readback_bytes(&gpu.device, "test.abi.params.rb", 32, 8);
        let local_readback = readback_bytes(&gpu.device, "test.abi.locals.rb", 16, 4);
        let schedule_readback = readback_bytes(&gpu.device, "test.abi.schedule.rb", 32, 8);
        let param_count_readback = readback_bytes(&gpu.device, "test.abi.param_count.rb", 4, 1);
        let function_count_readback =
            readback_bytes(&gpu.device, "test.abi.function_count.rb", 4, 1);
        let local_count_readback = readback_bytes(&gpu.device, "test.abi.local_count.rb", 4, 1);
        let output = stage.output();
        encoder.copy_buffer_to_buffer(
            &output.functions.buffer,
            0,
            &function_readback.buffer,
            0,
            52,
        );
        encoder.copy_buffer_to_buffer(&output.params.buffer, 0, &param_readback.buffer, 0, 32);
        encoder.copy_buffer_to_buffer(&output.locals.buffer, 0, &local_readback.buffer, 0, 16);
        encoder.copy_buffer_to_buffer(&stage.schedule.buffer, 0, &schedule_readback.buffer, 0, 32);
        encoder.copy_buffer_to_buffer(
            &output.param_count.buffer,
            0,
            &param_count_readback.buffer,
            0,
            4,
        );
        encoder.copy_buffer_to_buffer(
            &output.function_count.buffer,
            0,
            &function_count_readback.buffer,
            0,
            4,
        );
        encoder.copy_buffer_to_buffer(
            &output.local_count.buffer,
            0,
            &local_count_readback.buffer,
            0,
            4,
        );
        gpu.queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_words(&gpu.device, &function_readback),
            &[0, 5, 0, 2, 3, 1, 2, 0, 1, 0, 23, 0, u32::MAX]
        );
        assert_eq!(
            read_words(&gpu.device, &param_readback),
            &[0, 6, 0, 3, 0, 7, 1, 7]
        );
        assert_eq!(read_words(&gpu.device, &param_count_readback), &[2]);
        assert_eq!(read_words(&gpu.device, &function_count_readback), &[1]);
        assert_eq!(read_words(&gpu.device, &local_readback), &[0, 8, 0, 3]);
        assert_eq!(read_words(&gpu.device, &local_count_readback), &[1]);
        let schedule = read_words(&gpu.device, &schedule_readback);
        assert_eq!([schedule[0], schedule[4]], [0, 0]);
    }

    #[test]
    fn physical_gpu_preserves_unowned_family_shapes_without_executable_rows() {
        let gpu = device::global();
        let hir_count = storage_ro_from_u32s(&gpu.device, "test.family.hir_count", &[4]);
        let hir_core = storage_ro_from_bytes::<HirCore>(
            &gpu.device,
            "test.family.hir_core",
            &words(&[
                [23, u32::MAX, 0, 1],
                [23, u32::MAX, 2, 3],
                [24, u32::MAX, 4, 8],
                [28, u32::MAX, 9, 14],
            ]),
            4,
        );
        let hir_links = storage_ro_from_bytes::<crate::parser::buffers::HirLinks>(
            &gpu.device,
            "test.family.hir_links",
            &words(&[[u32::MAX, u32::MAX, 1, 0]; 4]),
            4,
        );
        let hir_payload = storage_ro_from_bytes::<HirPayload>(
            &gpu.device,
            "test.family.hir_payload",
            &words(&[
                [3, 7, u32::MAX, u32::MAX],
                [28, 0, u32::MAX, u32::MAX],
                [0, u32::MAX, u32::MAX, u32::MAX],
                [0, 0, 1, u32::MAX],
            ]),
            4,
        );
        let identity = storage_ro_from_u32s(&gpu.device, "test.family.identity", &[0, 1, 2, 3]);
        let no_parent = storage_ro_from_u32s(&gpu.device, "test.family.no_parent", &[u32::MAX; 4]);
        let zero_count = storage_ro_from_u32s(&gpu.device, "test.family.zero_count", &[0]);
        let call_args = storage_ro_from_bytes::<HirCallArg>(
            &gpu.device,
            "test.family.call_args",
            &words(&[[u32::MAX; 4]]),
            1,
        );
        let field_count = storage_ro_from_u32s(&gpu.device, "test.family.field_count", &[1]);
        let fields = storage_ro_from_bytes::<crate::parser::buffers::HirField>(
            &gpu.device,
            "test.family.fields",
            &words(&[[3, 55, 1, 0], [u32::MAX; 4], [u32::MAX; 4], [u32::MAX; 4]]),
            4,
        );
        let params = storage_ro_from_bytes::<crate::parser::buffers::HirParam>(
            &gpu.device,
            "test.family.params",
            &words(&[[u32::MAX; 4]; 4]),
            4,
        );
        let param_ranges = storage_ro_from_bytes::<crate::parser::buffers::HirRange>(
            &gpu.device,
            "test.family.param_ranges",
            &words(&[[u32::MAX, 0, 0, 0]; 4]),
            4,
        );
        let array_start = storage_ro_from_u32s(
            &gpu.device,
            "test.family.array_start",
            &[u32::MAX, u32::MAX, 0, u32::MAX],
        );
        let array_count =
            storage_ro_from_u32s(&gpu.device, "test.family.array_count", &[0, 0, 2, 0]);
        let array_row_count = storage_ro_from_u32s(&gpu.device, "test.family.array_rows", &[2]);
        let array_elements = storage_ro_from_bytes::<crate::parser::buffers::HirArrayElement>(
            &gpu.device,
            "test.family.array_elements",
            &words(&[[2, 0, 0, 0], [2, 1, 1, 0], [u32::MAX; 4], [u32::MAX; 4]]),
            4,
        );
        let string_count = storage_ro_from_u32s(&gpu.device, "test.family.string_count", &[1]);
        let strings = storage_ro_from_bytes::<crate::parser::buffers::HirString>(
            &gpu.device,
            "test.family.strings",
            &words(&[[1, 0, 2, 0], [u32::MAX; 4], [u32::MAX; 4], [u32::MAX; 4]]),
            4,
        );
        let string_len = storage_ro_from_u32s(&gpu.device, "test.family.string_len", &[2]);
        let string_data =
            storage_ro_from_u32s(&gpu.device, "test.family.string_data", &[0x6968, 0, 0, 0]);
        let types = storage_ro_from_u32s(&gpu.device, "test.family.types", &[3 << 28; 4]);
        let visible = storage_ro_from_u32s(&gpu.device, "test.family.visible", &[u32::MAX; 16]);
        let _language_names =
            storage_ro_from_u32s(&gpu.device, "test.family.language_names", &[u32::MAX; 67]);
        let enclosing = storage_ro_from_u32s(&gpu.device, "test.family.enclosing", &[0; 16]);
        let checked_calls = absent_checked_calls(&gpu.device, "test.family.checked_calls", 4);
        let semantic_ref_tags =
            storage_ro_from_u32s(&gpu.device, "test.family.semantic_ref_tags", &[0; 4]);
        let semantic_ref_payloads = storage_ro_from_u32s(
            &gpu.device,
            "test.family.semantic_ref_payloads",
            &[u32::MAX; 4],
        );
        let semantic_array_lengths = storage_ro_from_u32s(
            &gpu.device,
            "test.family.semantic_array_lengths",
            &[u32::MAX; 4],
        );
        let family_by_hir = storage_ro_from_u32s(
            &gpu.device,
            "test.family.value_const_by_hir",
            &[u32::MAX; 16],
        );
        let stage = GpuSemanticLoweringStage::new(
            &gpu.device,
            LoweringCapacities {
                source_bytes: 16,
                tokens: 16,
                hir_nodes: 4,
                semantic_instructions: 4,
                call_arguments: 1,
                parameters: 1,
                aggregate_elements: 4,
                target_instructions: 8,
                artifact_bytes: 64,
            },
        )
        .unwrap();
        let (method_count, method_cores, method_signatures) =
            empty_method_families(&gpu.device, "test.family.methods");
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.family.encoder"),
            });
        stage
            .record(
                &gpu.device,
                &mut encoder,
                GpuSemanticHirInputs {
                    count: &hir_count,
                    core: &hir_core,
                    links: &hir_links,
                    payload: &hir_payload,
                    const_value: &identity,
                    expr_parent: &no_parent,
                    expr_root: &identity,
                    nearest_loop: &no_parent,
                    call_arg_count: &zero_count,
                    call_args: &call_args,
                    field_count: &field_count,
                    fields: &fields,
                    array_element_start: &array_start,
                    array_element_count: &array_count,
                    array_element_row_count: &array_row_count,
                    array_elements: &array_elements,
                    string_count: &string_count,
                    strings: &strings,
                    string_data_words: &string_data,
                    string_pool_len: &string_len,
                    param_count: &zero_count,
                    params: &params,
                    param_ranges: &param_ranges,
                    method_count: &method_count,
                    method_cores: &method_cores,
                    method_signatures: &method_signatures,
                },
                GpuSemanticArtifactView {
                    value_decl_by_hir: &visible,
                    value_type_by_hir: &enclosing,
                    value_const_by_hir: &family_by_hir,
                    value_const_present_by_hir: &enclosing,
                    param_type_by_row: &visible,
                    enclosing_fn_by_hir: &enclosing,
                    function_return_type_by_hir: &enclosing,
                    function_entrypoint_by_hir: &enclosing,
                    function_host_service_by_hir: &semantic_array_lengths,
                    control_depth_by_hir: &enclosing,
                    calls_by_hir: &checked_calls,
                    expr_ref_tag_by_hir: &semantic_ref_tags,
                    expr_ref_payload_by_hir: &semantic_ref_payloads,
                    aggregate_decl_token_by_hir: &semantic_ref_payloads,
                    aggregate_word_count_by_hir: &enclosing,
                    array_length_by_hir: &semantic_array_lengths,
                    member_field_ordinal_by_hir: &visible,
                    iterable_kind_by_hir: &enclosing,
                    function_result_word_count_by_hir: &enclosing,
                    expr_scalar_type_by_hir: &types,
                    public_decl_index_by_hir: &visible,
                    struct_init_field_ordinal_by_row: &enclosing,
                },
            )
            .unwrap();
        let output = stage.output();
        let operands_rb = readback_bytes(&gpu.device, "test.family.operands.rb", 64, 16);
        let core_rb = readback_bytes(&gpu.device, "test.family.core.rb", 112, 28);
        let aggregate_count_rb =
            readback_bytes(&gpu.device, "test.family.aggregate_count.rb", 4, 1);
        let aggregates_rb = readback_bytes(&gpu.device, "test.family.aggregates.rb", 84, 21);
        let strings_rb = readback_bytes(&gpu.device, "test.family.strings.rb", 16, 4);
        let string_data_rb = readback_bytes(&gpu.device, "test.family.string_data.rb", 4, 1);
        encoder.copy_buffer_to_buffer(&output.operands.buffer, 0, &operands_rb.buffer, 0, 64);
        encoder.copy_buffer_to_buffer(&output.core.buffer, 0, &core_rb.buffer, 0, 112);
        encoder.copy_buffer_to_buffer(
            &output.aggregate_element_count.buffer,
            0,
            &aggregate_count_rb.buffer,
            0,
            4,
        );
        encoder.copy_buffer_to_buffer(
            &output.aggregate_elements.buffer,
            0,
            &aggregates_rb.buffer,
            0,
            84,
        );
        encoder.copy_buffer_to_buffer(&output.strings.buffer, 0, &strings_rb.buffer, 0, 16);
        encoder.copy_buffer_to_buffer(
            &output.string_data_words.buffer,
            0,
            &string_data_rb.buffer,
            0,
            4,
        );
        gpu.queue.submit(Some(encoder.finish()));

        let operands = read_words(&gpu.device, &operands_rb);
        assert_eq!(read_words(&gpu.device, &core_rb), &[0; 28]);
        assert_eq!(operands, &[0; 16]);
        assert_eq!(read_words(&gpu.device, &aggregate_count_rb), &[3]);
        assert_eq!(
            read_words(&gpu.device, &aggregates_rb),
            &[
                u32::MAX,
                u32::MAX,
                0,
                u32::MAX,
                3,
                0,
                1,
                u32::MAX,
                u32::MAX,
                1,
                u32::MAX,
                3,
                1,
                1,
                u32::MAX,
                u32::MAX,
                0,
                55,
                3,
                0,
                1,
            ]
        );
        assert_eq!(read_words(&gpu.device, &strings_rb), &[u32::MAX, 0, 2, 0]);
        assert_eq!(read_words(&gpu.device, &string_data_rb), &[0x6968]);
    }

    #[test]
    fn physical_gpu_materializes_control_events_and_unsupported_rows() {
        let gpu = device::global();
        let hir_count = storage_ro_from_u32s(&gpu.device, "test.control.hir_count", &[5]);
        let hir_core = storage_ro_from_bytes::<HirCore>(
            &gpu.device,
            "test.control.hir_core",
            &words(&[
                [23, 1, 1, 2],
                [7, u32::MAX, 0, 8],
                [34, u32::MAX, 9, 12],
                [7, u32::MAX, 13, 20],
                [3, u32::MAX, 0, 20],
            ]),
            5,
        );
        let hir_links = storage_ro_from_bytes::<crate::parser::buffers::HirLinks>(
            &gpu.device,
            "test.control.hir_links",
            &words(&[
                [u32::MAX, u32::MAX, 1, 0],
                [0, 2, 2, 0],
                [u32::MAX, 3, 3, 0],
                [0, u32::MAX, 4, 0],
                [1, u32::MAX, 5, 0],
            ]),
            5,
        );
        let hir_payload = storage_ro_from_bytes::<HirPayload>(
            &gpu.device,
            "test.control.hir_payload",
            &words(&[
                [4, 0, u32::MAX, 1],
                [3, 0, u32::MAX, u32::MAX],
                [26, 0, 0, u32::MAX],
                [6, 0, u32::MAX, u32::MAX],
                [4, 0, u32::MAX, u32::MAX],
            ]),
            5,
        );
        let expr_parent =
            storage_ro_from_u32s(&gpu.device, "test.control.expr_parent", &[u32::MAX; 5]);
        let expr_root =
            storage_ro_from_u32s(&gpu.device, "test.control.expr_root", &[0, 1, 2, 3, 4]);
        let call_arg_count = storage_ro_from_u32s(&gpu.device, "test.control.arg_count", &[0]);
        let call_args = storage_ro_from_bytes::<HirCallArg>(
            &gpu.device,
            "test.control.args",
            &words(&[[u32::MAX; 4]]),
            1,
        );
        let family_count = storage_ro_from_u32s(&gpu.device, "test.control.family_count", &[0]);
        let family_by_hir =
            storage_ro_from_u32s(&gpu.device, "test.control.family_by_hir", &[0; 5]);
        let fields = storage_ro_from_bytes::<crate::parser::buffers::HirField>(
            &gpu.device,
            "test.control.fields",
            &words(&[[u32::MAX; 4]]),
            1,
        );
        let params = storage_ro_from_bytes::<crate::parser::buffers::HirParam>(
            &gpu.device,
            "test.control.params",
            &words(&[[u32::MAX; 4]]),
            1,
        );
        let param_ranges = storage_ro_from_bytes::<crate::parser::buffers::HirRange>(
            &gpu.device,
            "test.control.param_ranges",
            &words(&[[u32::MAX, 0, 0, 0]; 5]),
            5,
        );
        let array_elements = storage_ro_from_bytes::<crate::parser::buffers::HirArrayElement>(
            &gpu.device,
            "test.control.array_elements",
            &words(&[[u32::MAX; 4]]),
            1,
        );
        let strings = storage_ro_from_bytes::<crate::parser::buffers::HirString>(
            &gpu.device,
            "test.control.strings",
            &words(&[[u32::MAX; 4]; 4]),
            4,
        );
        let string_data = storage_ro_from_u32s(&gpu.device, "test.control.string_data", &[0; 4]);
        let expression_types = storage_ro_from_u32s(
            &gpu.device,
            "test.control.types",
            &[2 << 28, 0, 3 << 28, 0, 0],
        );
        let visible = storage_ro_from_u32s(&gpu.device, "test.control.visible", &[u32::MAX; 16]);
        let _language_names =
            storage_ro_from_u32s(&gpu.device, "test.control.language_names", &[u32::MAX; 67]);
        let checked_layout_facts =
            storage_ro_from_u32s(&gpu.device, "test.control.checked_layout_facts", &[0; 16]);
        let mut enclosing_fn = vec![0; 16];
        enclosing_fn[..4].fill(5);
        let enclosing_fn =
            storage_ro_from_u32s(&gpu.device, "test.control.enclosing_fn", &enclosing_fn);
        let checked_calls = absent_checked_calls(&gpu.device, "test.control.checked_calls", 5);
        let semantic_ref_tags =
            storage_ro_from_u32s(&gpu.device, "test.control.semantic_ref_tags", &[0; 5]);
        let semantic_ref_payloads = storage_ro_from_u32s(
            &gpu.device,
            "test.control.semantic_ref_payloads",
            &[u32::MAX; 5],
        );
        let semantic_array_lengths = storage_ro_from_u32s(
            &gpu.device,
            "test.control.semantic_array_lengths",
            &[u32::MAX; 5],
        );
        let stage = GpuSemanticLoweringStage::new(
            &gpu.device,
            LoweringCapacities {
                source_bytes: 16,
                tokens: 16,
                hir_nodes: 5,
                semantic_instructions: 10,
                call_arguments: 1,
                parameters: 1,
                aggregate_elements: 1,
                target_instructions: 8,
                artifact_bytes: 64,
            },
        )
        .unwrap();
        let (method_count, method_cores, method_signatures) =
            empty_method_families(&gpu.device, "test.control.methods");
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.control.encoder"),
            });
        stage
            .record(
                &gpu.device,
                &mut encoder,
                GpuSemanticHirInputs {
                    count: &hir_count,
                    core: &hir_core,
                    links: &hir_links,
                    payload: &hir_payload,
                    const_value: &expr_root,
                    expr_parent: &expr_parent,
                    expr_root: &expr_root,
                    nearest_loop: &expr_root,
                    call_arg_count: &call_arg_count,
                    call_args: &call_args,
                    field_count: &family_count,
                    fields: &fields,
                    array_element_start: &family_by_hir,
                    array_element_count: &family_by_hir,
                    array_element_row_count: &family_count,
                    array_elements: &array_elements,
                    string_count: &family_count,
                    strings: &strings,
                    string_data_words: &string_data,
                    string_pool_len: &family_count,
                    param_count: &family_count,
                    params: &params,
                    param_ranges: &param_ranges,
                    method_count: &method_count,
                    method_cores: &method_cores,
                    method_signatures: &method_signatures,
                },
                GpuSemanticArtifactView {
                    value_decl_by_hir: &visible,
                    value_type_by_hir: &enclosing_fn,
                    value_const_by_hir: &family_by_hir,
                    value_const_present_by_hir: &checked_layout_facts,
                    param_type_by_row: &visible,
                    enclosing_fn_by_hir: &enclosing_fn,
                    function_return_type_by_hir: &enclosing_fn,
                    function_entrypoint_by_hir: &enclosing_fn,
                    function_host_service_by_hir: &semantic_array_lengths,
                    control_depth_by_hir: &enclosing_fn,
                    calls_by_hir: &checked_calls,
                    expr_ref_tag_by_hir: &semantic_ref_tags,
                    expr_ref_payload_by_hir: &semantic_ref_payloads,
                    aggregate_decl_token_by_hir: &semantic_ref_payloads,
                    aggregate_word_count_by_hir: &checked_layout_facts,
                    array_length_by_hir: &semantic_array_lengths,
                    member_field_ordinal_by_hir: &visible,
                    iterable_kind_by_hir: &checked_layout_facts,
                    function_result_word_count_by_hir: &checked_layout_facts,
                    expr_scalar_type_by_hir: &expression_types,
                    public_decl_index_by_hir: &visible,
                    struct_init_field_ordinal_by_row: &visible,
                },
            )
            .unwrap();
        let output = stage.output();
        let count_readback = readback_bytes(&gpu.device, "test.control.count.rb", 4, 1);
        let core_readback = readback_bytes(&gpu.device, "test.control.core.rb", 280, 70);
        let operands_readback = readback_bytes(&gpu.device, "test.control.operands.rb", 160, 40);
        let status_readback = readback_bytes(&gpu.device, "test.control.status.rb", 16, 4);
        let schedule_readback = readback_bytes(&gpu.device, "test.control.schedule.rb", 160, 40);
        encoder.copy_buffer_to_buffer(&output.count.buffer, 0, &count_readback.buffer, 0, 4);
        encoder.copy_buffer_to_buffer(&output.core.buffer, 0, &core_readback.buffer, 0, 280);
        encoder.copy_buffer_to_buffer(
            &output.operands.buffer,
            0,
            &operands_readback.buffer,
            0,
            160,
        );
        encoder.copy_buffer_to_buffer(&stage.status().buffer, 0, &status_readback.buffer, 0, 16);
        encoder.copy_buffer_to_buffer(&stage.schedule.buffer, 0, &schedule_readback.buffer, 0, 160);
        gpu.queue.submit(Some(encoder.finish()));

        let status = read_words(&gpu.device, &status_readback);
        assert_eq!(
            read_words(&gpu.device, &count_readback)[0],
            10,
            "lowering status: {status:?}"
        );
        let core = read_words(&gpu.device, &core_readback);
        assert_eq!(
            [core[0], core[7], core[14], core[21]],
            [
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_CONST_I32,
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_IF_BEGIN,
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_CONTROL_END,
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_INVALID,
            ]
        );
        assert_ne!(
            core[26] & super::super::lowering_ir::opcode::SEMANTIC_LIR_FLAG_UNSUPPORTED,
            0
        );
        assert_eq!(
            [core[28], core[35], core[42], core[49], core[56], core[63]],
            [
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_BLOCK_BEGIN,
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_LOOP_BEGIN,
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_BRANCH_IF,
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_BRANCH,
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_CONTROL_END,
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_CONTROL_END,
            ]
        );
        let operands = read_words(&gpu.device, &operands_readback);
        assert_eq!(&operands[24..28], &[6, 0, 1, 9]);
        assert_eq!(&operands[28..32], &[7, 5, 0, u32::MAX]);
        assert_eq!(status, [0, u32::MAX, 0, u32::MAX]);
        let schedule = read_words(&gpu.device, &schedule_readback);
        assert_eq!(
            [
                schedule[0],
                schedule[4],
                schedule[8],
                schedule[12],
                schedule[16]
            ],
            [0; 5]
        );
    }
}
