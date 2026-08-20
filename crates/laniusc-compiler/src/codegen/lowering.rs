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
        SemanticLirString,
        TargetScheduleKey,
        TargetScheduleRadixLayout,
    },
    scan::{GpuResidentExclusiveScan, GraphScanContract},
    schedule::GpuStableScheduleSorter,
};
use crate::{
    gpu::{
        buffers::{LaniusBuffer, TrackedBufferView, uniform_from_val},
        compiler_graph::{
            CompilerGraph,
            CompilerGraphAllocations,
            CompilerGraphWorkspace,
            ResourceId,
        },
        kernels::KernelRegistry,
        operations::ComputeOperation,
        passes_core::PassData,
        resource_registry::ResourceMap,
        timer::GpuTimer,
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
    resident_rows: u32,
    schedule_packed_bits: u32,
    reserved0: u32,
    reserved1: u32,
    reserved2: u32,
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
    fn new(kernels: &KernelRegistry) -> Self {
        let load = |shader: &str| kernels.kernel(shader).clone();
        Self {
            status_clear: load("codegen/lir/status_clear"),
            project: load("codegen/lir/semantic/project"),
            execution_rank_init: load("codegen/lir/semantic/execution_rank_init"),
            execution_rank_step: load("codegen/lir/semantic/execution_rank_step"),
            count: load("codegen/lir/semantic/count"),
            scan_local: load("scan/counted/00_local"),
            scan_up: load("scan/counted/01_hierarchy_up"),
            scan_down: load("scan/counted/02_hierarchy_down"),
            scan_apply: load("scan/counted/02_apply"),
            scatter: load("codegen/lir/semantic/scatter"),
            call_args: load("codegen/lir/semantic/call_args"),
            aggregate_elements: load("codegen/lir/semantic/aggregate_elements"),
            strings: load("codegen/lir/semantic/strings"),
            function_mark: load("codegen/lir/semantic/function_mark"),
            function_layout_clear: load("codegen/lir/semantic/function_layout_clear"),
            function_layout_collect: load("codegen/lir/semantic/function_layout_collect"),
            function_layout_words: load("codegen/lir/semantic/function_layout_words"),
            function_scatter: load("codegen/lir/semantic/function_scatter"),
            function_params: load("codegen/lir/semantic/function_params"),
            local_mark: load("codegen/lir/semantic/local_mark"),
            local_scatter: load("codegen/lir/semantic/local_scatter"),
        }
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
    pub fn_return_type: &'a LaniusBuffer<u32>,
    pub const_value: &'a LaniusBuffer<u32>,
    pub expr_parent: &'a LaniusBuffer<u32>,
    pub expr_root: &'a LaniusBuffer<u32>,
    pub nearest_loop: &'a LaniusBuffer<u32>,
    pub call_arg_count: &'a LaniusBuffer<u32>,
    pub call_args: &'a LaniusBuffer<crate::parser::buffers::HirCallArg>,
    pub field_count: &'a LaniusBuffer<u32>,
    pub fields: &'a LaniusBuffer<crate::parser::buffers::HirField>,
    pub variant_count: &'a LaniusBuffer<u32>,
    pub variants: &'a LaniusBuffer<crate::parser::buffers::HirVariant>,
    pub variant_payload_start: &'a LaniusBuffer<u32>,
    pub variant_payload_count: &'a LaniusBuffer<u32>,
    pub variant_payload_row_count: &'a LaniusBuffer<u32>,
    pub variant_payloads: &'a LaniusBuffer<crate::parser::buffers::HirVariantPayload>,
    pub match_arm_count: &'a LaniusBuffer<u32>,
    pub match_arms: &'a LaniusBuffer<crate::parser::buffers::HirMatchArm>,
    pub match_payload_start: &'a LaniusBuffer<u32>,
    pub match_payload_count: &'a LaniusBuffer<u32>,
    pub match_payload_row_count: &'a LaniusBuffer<u32>,
    pub match_payloads: &'a LaniusBuffer<crate::parser::buffers::HirMatchPayload>,
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
            fn_return_type: &hir.fn_return_type,
            const_value: &hir.const_value,
            expr_parent: &hir.expr_parent,
            expr_root: &hir.expr_root,
            nearest_loop: &hir.nearest_loop,
            call_arg_count: &hir.call_arg_count,
            call_args: &hir.call_args,
            field_count: &hir.field_count,
            fields: &hir.fields,
            variant_count: &hir.variant_count,
            variants: &hir.variants,
            variant_payload_start: &hir.variant_payload_start,
            variant_payload_count: &hir.variant_payload_count,
            variant_payload_row_count: &hir.variant_payload_row_count,
            variant_payloads: &hir.variant_payloads,
            match_arm_count: &hir.match_arm_count,
            match_arms: &hir.match_arms,
            match_payload_start: &hir.match_payload_start,
            match_payload_count: &hir.match_payload_count,
            match_payload_row_count: &hir.match_payload_row_count,
            match_payloads: &hir.match_payloads,
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

impl<'a> GpuSemanticHirInputs<'a> {
    fn register(self, graph: &CompilerGraph, resources: &mut ResourceMap<'a>) -> Result<()> {
        macro_rules! buffer {
            ($name:literal, $value:expr) => {
                resources.graph_buffer(graph, $name, $value)?
            };
        }
        buffer!("hir.count", self.count);
        buffer!("hir.core", self.core);
        buffer!("hir.links", self.links);
        buffer!("hir.payload", self.payload);
        buffer!("hir.fn_return_type", self.fn_return_type);
        buffer!("hir.const_value", self.const_value);
        buffer!("hir.expression_parents", self.expr_parent);
        buffer!("hir.expression_roots", self.expr_root);
        buffer!("hir.nearest_loop", self.nearest_loop);
        buffer!("hir.call_arg_count", self.call_arg_count);
        buffer!("hir.call_args", self.call_args);
        buffer!("hir.field_count", self.field_count);
        buffer!("hir.fields", self.fields);
        buffer!("hir.variant_count", self.variant_count);
        buffer!("hir.variants", self.variants);
        buffer!("hir.variant_payload_start", self.variant_payload_start);
        buffer!("hir.variant_payload_count", self.variant_payload_count);
        buffer!(
            "hir.variant_payload_row_count",
            self.variant_payload_row_count
        );
        buffer!("hir.variant_payloads", self.variant_payloads);
        buffer!("hir.match_arm_count", self.match_arm_count);
        buffer!("hir.match_arms", self.match_arms);
        buffer!("hir.match_payload_start", self.match_payload_start);
        buffer!("hir.match_payload_count", self.match_payload_count);
        buffer!("hir.match_payload_row_count", self.match_payload_row_count);
        buffer!("hir.match_payloads", self.match_payloads);
        buffer!("hir.array_element_start", self.array_element_start);
        buffer!("hir.array_element_count", self.array_element_count);
        buffer!("hir.array_element_row_count", self.array_element_row_count);
        buffer!("hir.array_elements", self.array_elements);
        buffer!("hir.string_count", self.string_count);
        buffer!("hir.strings", self.strings);
        buffer!("hir.string_data", self.string_data_words);
        buffer!("hir.string_pool_len", self.string_pool_len);
        buffer!("hir.param_count", self.param_count);
        buffer!("hir.params", self.params);
        buffer!("hir.param_ranges", self.param_ranges);
        buffer!("hir.method_count", self.method_count);
        buffer!("hir.method_cores", self.method_cores);
        buffer!("hir.method_signatures", self.method_signatures);
        Ok(())
    }

    pub(crate) fn tracked_views(self) -> Vec<TrackedBufferView<'a>> {
        vec![
            self.count.into(),
            self.core.into(),
            self.links.into(),
            self.payload.into(),
            self.fn_return_type.into(),
            self.const_value.into(),
            self.expr_parent.into(),
            self.expr_root.into(),
            self.nearest_loop.into(),
            self.call_arg_count.into(),
            self.call_args.into(),
            self.field_count.into(),
            self.fields.into(),
            self.variant_count.into(),
            self.variants.into(),
            self.variant_payload_start.into(),
            self.variant_payload_count.into(),
            self.variant_payload_row_count.into(),
            self.variant_payloads.into(),
            self.match_arm_count.into(),
            self.match_arms.into(),
            self.match_payload_start.into(),
            self.match_payload_count.into(),
            self.match_payload_row_count.into(),
            self.match_payloads.into(),
            self.array_element_start.into(),
            self.array_element_count.into(),
            self.array_element_row_count.into(),
            self.array_elements.into(),
            self.string_count.into(),
            self.strings.into(),
            self.string_data_words.into(),
            self.string_pool_len.into(),
            self.param_count.into(),
            self.params.into(),
            self.param_ranges.into(),
            self.method_count.into(),
            self.method_cores.into(),
            self.method_signatures.into(),
        ]
    }
}

fn register_semantic_inputs<'a>(
    semantic: GpuSemanticArtifactView<'a>,
    graph: &CompilerGraph,
    resources: &mut ResourceMap<'a>,
) -> Result<()> {
    macro_rules! buffer {
        ($name:literal, $value:expr) => {
            resources.graph_buffer(graph, $name, $value)?
        };
    }
    buffer!(
        "typecheck.semantic_value_decls_by_hir",
        semantic.value_decl_by_hir
    );
    buffer!(
        "typecheck.semantic_value_types_by_hir",
        semantic.value_type_by_hir
    );
    buffer!(
        "typecheck.semantic_value_consts_by_hir",
        semantic.value_const_by_hir
    );
    buffer!(
        "typecheck.semantic_value_const_present_by_hir",
        semantic.value_const_present_by_hir
    );
    buffer!(
        "typecheck.semantic_param_types_by_row",
        semantic.param_type_by_row
    );
    buffer!(
        "typecheck.semantic_enclosing_functions_by_hir",
        semantic.enclosing_fn_by_hir
    );
    buffer!(
        "typecheck.semantic_function_return_types_by_hir",
        semantic.function_return_type_by_hir
    );
    buffer!(
        "typecheck.semantic_function_entrypoints_by_hir",
        semantic.function_entrypoint_by_hir
    );
    buffer!(
        "typecheck.semantic_function_host_services_by_hir",
        semantic.function_host_service_by_hir
    );
    buffer!(
        "typecheck.semantic_control_depths_by_hir",
        semantic.control_depth_by_hir
    );
    buffer!("typecheck.semantic_calls_by_hir", semantic.calls_by_hir);
    buffer!(
        "typecheck.semantic_expr_ref_tags_by_hir",
        semantic.expr_ref_tag_by_hir
    );
    buffer!(
        "typecheck.semantic_expr_ref_payloads_by_hir",
        semantic.expr_ref_payload_by_hir
    );
    buffer!(
        "typecheck.semantic_aggregate_decl_tokens_by_hir",
        semantic.aggregate_decl_token_by_hir
    );
    buffer!(
        "typecheck.semantic_aggregate_word_counts_by_hir",
        semantic.aggregate_word_count_by_hir
    );
    buffer!(
        "typecheck.semantic_array_lengths_by_hir",
        semantic.array_length_by_hir
    );
    buffer!(
        "typecheck.semantic_member_field_ordinals_by_hir",
        semantic.member_field_ordinal_by_hir
    );
    buffer!(
        "typecheck.semantic_iterable_kinds_by_hir",
        semantic.iterable_kind_by_hir
    );
    buffer!(
        "typecheck.semantic_function_result_word_counts_by_hir",
        semantic.function_result_word_count_by_hir
    );
    buffer!(
        "semantic.expression_types",
        semantic.expr_scalar_type_by_hir
    );
    buffer!(
        "typecheck.public_decl_index_by_hir",
        semantic.public_decl_index_by_hir
    );
    buffer!(
        "typecheck.struct_init_field_ordinals",
        semantic.struct_init_field_ordinal_by_row
    );
    Ok(())
}

pub(crate) fn semantic_input_views<'a>(
    hir: GpuSemanticHirInputs<'a>,
    semantic: GpuSemanticArtifactView<'a>,
) -> Vec<TrackedBufferView<'a>> {
    let mut views = hir.tracked_views();
    let semantic_views: [TrackedBufferView<'a>; 22] = [
        semantic.value_decl_by_hir.into(),
        semantic.value_type_by_hir.into(),
        semantic.value_const_by_hir.into(),
        semantic.value_const_present_by_hir.into(),
        semantic.param_type_by_row.into(),
        semantic.enclosing_fn_by_hir.into(),
        semantic.function_return_type_by_hir.into(),
        semantic.function_entrypoint_by_hir.into(),
        semantic.function_host_service_by_hir.into(),
        semantic.control_depth_by_hir.into(),
        semantic.calls_by_hir.into(),
        semantic.expr_ref_tag_by_hir.into(),
        semantic.expr_ref_payload_by_hir.into(),
        semantic.aggregate_decl_token_by_hir.into(),
        semantic.aggregate_word_count_by_hir.into(),
        semantic.array_length_by_hir.into(),
        semantic.member_field_ordinal_by_hir.into(),
        semantic.iterable_kind_by_hir.into(),
        semantic.function_result_word_count_by_hir.into(),
        semantic.expr_scalar_type_by_hir.into(),
        semantic.public_decl_index_by_hir.into(),
        semantic.struct_init_field_ordinal_by_row.into(),
    ];
    views.extend(semantic_views);
    views
}

struct GpuSemanticLoweringOperations {
    status_clear: ComputeOperation,
    function_mark: ComputeOperation,
    function_scan: GpuResidentExclusiveScan,
    local_mark: ComputeOperation,
    local_scan: GpuResidentExclusiveScan,
    function_layout_clear: ComputeOperation,
    function_layout_collect: ComputeOperation,
    function_layout_words: ComputeOperation,
    function_scatter: ComputeOperation,
    function_params: ComputeOperation,
    project: ComputeOperation,
    call_argument_scan: GpuResidentExclusiveScan,
    local_scatter: ComputeOperation,
    execution_rank_init: ComputeOperation,
    execution_rank_a_to_b: ComputeOperation,
    execution_rank_b_to_a: ComputeOperation,
    count: ComputeOperation,
    instruction_scan: GpuResidentExclusiveScan,
    scatter: ComputeOperation,
    call_args: ComputeOperation,
    aggregate_elements: ComputeOperation,
    strings: ComputeOperation,
}

/// Executable compact-HIR to target-independent LIR stage. Pipelines,
/// uniforms, physical workspace slots, and output aliases are all created by
/// `new`; `record` performs no pipeline or buffer allocation.
pub(crate) struct GpuSemanticLoweringStage {
    operations: GpuSemanticLoweringOperations,
    _project_params: LaniusBuffer<SemanticProjectParams>,
    _count_params: LaniusBuffer<SemanticCountParams>,
    _scatter_params: LaniusBuffer<SemanticScatterParams>,
    _call_arg_params: LaniusBuffer<SemanticCallArgParams>,
    _aggregate_params: LaniusBuffer<SemanticAggregateParams>,
    _string_params: LaniusBuffer<SemanticStringParams>,
    _function_params: LaniusBuffer<SemanticFunctionParams>,
    execution_rank_pairs: u32,
    total: LaniusBuffer<u32>,
    core: LaniusBuffer<SemanticLirCore>,
    operands: LaniusBuffer<SemanticLirOperands>,
    layout_word_offset: LaniusBuffer<u32>,
    owner_by_instruction: LaniusBuffer<u32>,
    op_by_instruction: LaniusBuffer<u32>,
    function_ids: LaniusBuffer<u32>,
    semantic_sorter: Option<GpuStableScheduleSorter>,
    call_args: LaniusBuffer<SemanticLirCallArg>,
    call_arg_counts_by_hir: LaniusBuffer<u32>,
    call_arg_prefix_by_hir: LaniusBuffer<u32>,
    aggregate_elements: LaniusBuffer<SemanticLirAggregateElement>,
    aggregate_element_count: LaniusBuffer<u32>,
    strings: LaniusBuffer<SemanticLirString>,
    string_count: LaniusBuffer<u32>,
    string_data_words: LaniusBuffer<u32>,
    string_pool_len: LaniusBuffer<u32>,
    functions: LaniusBuffer<SemanticLirFunction>,
    function_count: LaniusBuffer<u32>,
    params: LaniusBuffer<SemanticLirParam>,
    param_count: LaniusBuffer<u32>,
    locals: LaniusBuffer<SemanticLirLocal>,
    local_count: LaniusBuffer<u32>,
    status: LaniusBuffer<LoweringStatus>,
    #[cfg(test)]
    _standalone_workspace: Option<CompilerGraphWorkspace>,
}

impl GpuSemanticLoweringStage {
    #[cfg(test)]
    pub(crate) fn new(
        device: &wgpu::Device,
        capacities: LoweringCapacities,
        hir: GpuSemanticHirInputs<'_>,
        semantic: GpuSemanticArtifactView<'_>,
    ) -> Result<Self> {
        let kernels =
            KernelRegistry::prepare_prefixes(device, &["codegen/lir", "scan/counted"], |_| true)?;
        let graph = semantic_lowering_compiler_graph(capacities).map_err(anyhow::Error::msg)?;
        let workspace = CompilerGraphWorkspace::new(device, "codegen.lir", &graph)
            .map_err(anyhow::Error::msg)?;
        let mut stage = Self::from_workspace(
            device, capacities, graph, &workspace, &kernels, hir, semantic,
        )?;
        stage._standalone_workspace = Some(workspace);
        Ok(stage)
    }

    pub(crate) fn from_workspace(
        device: &wgpu::Device,
        capacities: LoweringCapacities,
        graph: CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        kernels: &KernelRegistry,
        hir: GpuSemanticHirInputs<'_>,
        semantic: GpuSemanticArtifactView<'_>,
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
        let schedule: LaniusBuffer<TargetScheduleKey> = workspace
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
                capacities.local_capacity().max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let local_count = alias("lir.semantic.local_total", 1)?;
        let status = workspace
            .alias(&graph, resource("lowering.status")?, 1)
            .map_err(anyhow::Error::msg)?;
        let call_arg_counts_by_hir = alias("lir.semantic.call_arg_counts_by_hir", hir_nodes)?;
        let call_arg_prefix_by_hir = alias("lir.semantic.call_arg_prefix_by_hir", hir_nodes)?;
        let function_ids = alias("semantic.function_ids", hir_nodes)?;
        let function_flags = alias("lir.semantic.function_flags", hir_nodes)?;
        let function_prefix = alias("lir.semantic.function_prefix", hir_nodes)?;
        let local_flags = alias("lir.semantic.local_flags", hir_nodes)?;
        let local_prefix = alias("lir.semantic.local_prefix", hir_nodes)?;
        let counts = alias("lir.semantic.count_by_hir", hir_nodes)?;
        let offsets = alias("lir.semantic.offset_by_hir", hir_nodes)?;
        let total = alias("lir.semantic.total", 1)?;
        let passes = SemanticPasses::new(kernels);
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
                .validate_complete_pass_reflection(graph.pass_id(name).unwrap(), reflection)
                .map_err(anyhow::Error::msg)?;
        }

        let schedule_order_resource = if graph.resource_id("lir.semantic.schedule_order").is_some()
        {
            Some("lir.semantic.schedule_order")
        } else {
            None
        };
        let semantic_sorter = if let Some(order_name) = schedule_order_resource {
            let keys = schedule
                .alias::<TargetScheduleKey>(capacities.semantic_instructions.max(1) as usize);
            let order = workspace
                .alias(
                    &graph,
                    resource(order_name)?,
                    capacities.semantic_instructions.max(1) as usize,
                )
                .map_err(anyhow::Error::msg)?;
            let radix_layout = TargetScheduleRadixLayout::for_capacities(capacities);
            let sorter = GpuStableScheduleSorter::new_semantic(
                device,
                kernels,
                &graph,
                workspace,
                &allocations,
                capacities.semantic_instructions.max(1),
                radix_layout,
                &total,
                &keys,
                &order,
            )?;
            Some(sorter)
        } else {
            None
        };

        let project_params = uniform_from_val(
            device,
            "lir.semantic.project.params",
            &SemanticProjectParams {
                n_tokens: capacities.tokens,
                n_hir_nodes: hir_nodes,
                reserved0: 0,
                reserved1: 0,
            },
        );
        let count_params = uniform_from_val(
            device,
            "lir.semantic.count.params",
            &SemanticCountParams {
                n_hir_nodes: hir_nodes,
                reserved0: 0,
                reserved1: 0,
                reserved2: 0,
            },
        );
        let scatter_params = uniform_from_val(
            device,
            "lir.semantic.scatter.params",
            &SemanticScatterParams {
                n_hir_nodes: hir_nodes,
                lir_capacity: capacities.semantic_instructions.max(1),
                n_tokens: capacities.tokens,
                resident_rows: semantic_resident_rows,
                schedule_packed_bits: TargetScheduleRadixLayout::for_capacities(capacities)
                    .packed_bits,
                reserved0: 0,
                reserved1: 0,
                reserved2: 0,
            },
        );
        let call_arg_params = uniform_from_val(
            device,
            "lir.semantic.call_args.params",
            &SemanticCallArgParams {
                n_call_args: capacities.call_arguments,
                n_hir_nodes: hir_nodes,
                lir_capacity: capacities.semantic_instructions.max(1),
                reserved: 0,
            },
        );
        let aggregate_params = uniform_from_val(
            device,
            "lir.semantic.aggregate_elements.params",
            &SemanticAggregateParams {
                element_capacity: capacities.aggregate_elements,
                n_hir_nodes: hir_nodes,
                semantic_capacity: capacities.semantic_instructions.max(1),
                n_tokens: capacities.tokens,
            },
        );
        let string_params = uniform_from_val(
            device,
            "lir.semantic.strings.params",
            &SemanticStringParams {
                string_capacity: hir_nodes,
                word_capacity: capacities.source_bytes.max(4).div_ceil(4),
                n_hir_nodes: hir_nodes,
                reserved: 0,
            },
        );
        let function_params = uniform_from_val(
            device,
            "lir.semantic.functions.params",
            &SemanticFunctionParams {
                n_hir_nodes: hir_nodes,
                param_capacity: capacities.parameters,
                n_tokens: capacities.tokens,
                local_capacity: capacities.local_capacity(),
            },
        );

        let graph_bindings = workspace.bindings(&graph).map_err(anyhow::Error::msg)?;
        let mut resources = ResourceMap::new();
        resources.register_graph_bindings(&graph, &graph_bindings);
        hir.register(&graph, &mut resources)?;
        register_semantic_inputs(semantic, &graph, &mut resources)?;
        resources.attach_graph(&graph, &allocations);
        let context = (&graph, &allocations);
        let direct =
            |name: &'static str, pass: &PassData, elements: u32| -> Result<ComputeOperation> {
                ComputeOperation::direct(device, &context, &resources, name, pass, elements)
            };
        macro_rules! direct_uniform {
            ($name:expr, $pass:expr, $params:expr, $elements:expr $(,)?) => {
                ComputeOperation::direct_with_uniform(
                    device, &context, &resources, $name, $pass, $params, $elements,
                )
            };
        }

        let function_scan = GpuResidentExclusiveScan::new(
            device,
            kernels,
            &graph,
            workspace,
            &allocations,
            GraphScanContract {
                local_pass: "lir.semantic.function_scan.local",
                up_pass: "lir.semantic.function_scan.hierarchy_up",
                down_pass: "lir.semantic.function_scan.hierarchy_down",
                apply_pass: "lir.semantic.function_scan.apply",
                count: "hir.count",
                input: "lir.semantic.function_flags",
                local: "lir.semantic.function_scan_local",
                block_sum: "lir.semantic.function_scan_block_sum",
                block_prefix: "lir.semantic.function_scan_block_prefix",
                hierarchy: "lir.semantic.function_scan_hierarchy",
                output: "lir.semantic.function_prefix",
                total: "lir.semantic.function_total",
            },
            hir_nodes,
            hir.count,
            &function_flags,
            &function_prefix,
            &function_count,
        )?;
        let local_scan = GpuResidentExclusiveScan::new(
            device,
            kernels,
            &graph,
            workspace,
            &allocations,
            GraphScanContract {
                local_pass: "lir.semantic.local_scan.local",
                up_pass: "lir.semantic.local_scan.hierarchy_up",
                down_pass: "lir.semantic.local_scan.hierarchy_down",
                apply_pass: "lir.semantic.local_scan.apply",
                count: "hir.count",
                input: "lir.semantic.local_flags",
                local: "lir.semantic.local_scan_local",
                block_sum: "lir.semantic.local_scan_block_sum",
                block_prefix: "lir.semantic.local_scan_block_prefix",
                hierarchy: "lir.semantic.local_scan_hierarchy",
                output: "lir.semantic.local_prefix",
                total: "lir.semantic.local_total",
            },
            hir_nodes,
            hir.count,
            &local_flags,
            &local_prefix,
            &local_count,
        )?;
        let call_argument_scan = GpuResidentExclusiveScan::new(
            device,
            kernels,
            &graph,
            workspace,
            &allocations,
            GraphScanContract {
                local_pass: "lir.semantic.call_arg_scan.local",
                up_pass: "lir.semantic.call_arg_scan.hierarchy_up",
                down_pass: "lir.semantic.call_arg_scan.hierarchy_down",
                apply_pass: "lir.semantic.call_arg_scan.apply",
                count: "hir.count",
                input: "lir.semantic.call_arg_counts_by_hir",
                local: "lir.semantic.call_arg_scan_local",
                block_sum: "lir.semantic.call_arg_scan_block_sum",
                block_prefix: "lir.semantic.call_arg_scan_block_prefix",
                hierarchy: "lir.semantic.call_arg_scan_hierarchy",
                output: "lir.semantic.call_arg_prefix_by_hir",
                total: "lir.semantic.call_arg_total",
            },
            hir_nodes,
            hir.count,
            &call_arg_counts_by_hir,
            &call_arg_prefix_by_hir,
            &call_arg_count,
        )?;
        let instruction_scan = GpuResidentExclusiveScan::new(
            device,
            kernels,
            &graph,
            workspace,
            &allocations,
            GraphScanContract {
                local_pass: "lir.semantic.scan.local",
                up_pass: "lir.semantic.scan.hierarchy_up",
                down_pass: "lir.semantic.scan.hierarchy_down",
                apply_pass: "lir.semantic.scan.apply",
                count: "hir.count",
                input: "lir.semantic.count_by_hir",
                local: "lir.semantic.scan_local",
                block_sum: "lir.semantic.scan_block_sum",
                block_prefix: "lir.semantic.scan_block_prefix",
                hierarchy: "lir.semantic.scan_hierarchy",
                output: "lir.semantic.offset_by_hir",
                total: "lir.semantic.total",
            },
            hir_nodes,
            hir.count,
            &counts,
            &offsets,
            &total,
        )?;

        let execution_rank_a_to_b = direct_uniform!(
            "lir.semantic.execution_rank.step_a_to_b",
            &passes.execution_rank_step,
            &count_params,
            hir_nodes,
        )?;
        let execution_rank_b_to_a = direct_uniform!(
            "lir.semantic.execution_rank.step_b_to_a",
            &passes.execution_rank_step,
            &count_params,
            hir_nodes,
        )?;
        let operations = GpuSemanticLoweringOperations {
            status_clear: direct("lir.status.clear", &passes.status_clear, 1)?,
            function_mark: direct_uniform!(
                "lir.semantic.functions.mark",
                &passes.function_mark,
                &function_params,
                hir_nodes,
            )?,
            function_scan,
            local_mark: direct_uniform!(
                "lir.semantic.locals.mark",
                &passes.local_mark,
                &function_params,
                hir_nodes,
            )?,
            local_scan,
            function_layout_clear: direct_uniform!(
                "lir.semantic.functions.layout.clear",
                &passes.function_layout_clear,
                &function_params,
                capacities.tokens.max(hir_nodes),
            )?,
            function_layout_collect: direct_uniform!(
                "lir.semantic.functions.layout.collect",
                &passes.function_layout_collect,
                &function_params,
                hir_nodes.max(capacities.aggregate_elements),
            )?,
            function_layout_words: direct_uniform!(
                "lir.semantic.functions.layout.words",
                &passes.function_layout_words,
                &function_params,
                hir_nodes,
            )?,
            function_scatter: direct_uniform!(
                "lir.semantic.functions.scatter",
                &passes.function_scatter,
                &function_params,
                hir_nodes,
            )?,
            function_params: direct_uniform!(
                "lir.semantic.functions.params",
                &passes.function_params,
                &function_params,
                capacities.parameters.max(1),
            )?,
            project: direct_uniform!(
                "lir.semantic.project",
                &passes.project,
                &project_params,
                hir_nodes,
            )?,
            call_argument_scan,
            local_scatter: direct_uniform!(
                "lir.semantic.locals.scatter",
                &passes.local_scatter,
                &function_params,
                hir_nodes,
            )?,
            execution_rank_init: direct_uniform!(
                "lir.semantic.execution_rank.init",
                &passes.execution_rank_init,
                &count_params,
                hir_nodes,
            )?,
            execution_rank_a_to_b,
            execution_rank_b_to_a,
            count: direct_uniform!(
                "lir.semantic.count",
                &passes.count,
                &count_params,
                hir_nodes,
            )?,
            instruction_scan,
            scatter: direct_uniform!(
                "lir.semantic.scatter",
                &passes.scatter,
                &scatter_params,
                capacities.semantic_instructions,
            )?,
            call_args: direct_uniform!(
                "lir.semantic.call_args",
                &passes.call_args,
                &call_arg_params,
                capacities.call_arguments.max(hir_nodes),
            )?,
            aggregate_elements: direct_uniform!(
                "lir.semantic.aggregate_elements",
                &passes.aggregate_elements,
                &aggregate_params,
                capacities.aggregate_elements.saturating_mul(2),
            )?,
            strings: direct_uniform!(
                "lir.semantic.strings",
                &passes.strings,
                &string_params,
                capacities.source_bytes.max(hir_nodes),
            )?,
        };
        Ok(Self {
            operations,
            _project_params: project_params,
            _count_params: count_params,
            _scatter_params: scatter_params,
            _call_arg_params: call_arg_params,
            _aggregate_params: aggregate_params,
            _string_params: string_params,
            _function_params: function_params,
            execution_rank_pairs: (u32::BITS - hir_nodes.leading_zeros()).max(1).div_ceil(2),
            total,
            core,
            operands,
            layout_word_offset,
            owner_by_instruction,
            op_by_instruction,
            function_ids,
            semantic_sorter,
            call_args,
            call_arg_counts_by_hir,
            call_arg_prefix_by_hir,
            aggregate_elements,
            aggregate_element_count,
            strings,
            string_count,
            string_data_words,
            string_pool_len,
            functions,
            function_count,
            params,
            param_count,
            locals,
            local_count,
            status,
            #[cfg(test)]
            _standalone_workspace: None,
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

    #[cfg(test)]
    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.record_timed(encoder, None)
    }

    pub(crate) fn record_timed(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        mut timer: Option<&mut GpuTimer>,
    ) -> Result<()> {
        macro_rules! stamp {
            ($label:literal) => {
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, $label);
                }
            };
        }

        let operations = &self.operations;
        operations.status_clear.record(encoder)?;
        stamp!("lowering.semantic.status.done");
        operations.function_mark.record(encoder)?;
        operations.function_scan.record(encoder)?;
        stamp!("lowering.semantic.functions.scan.done");
        operations.local_mark.record(encoder)?;
        operations.local_scan.record(encoder)?;
        stamp!("lowering.semantic.locals.scan.done");
        operations.function_layout_clear.record(encoder)?;
        operations.function_layout_collect.record(encoder)?;
        operations.function_layout_words.record(encoder)?;
        operations.function_scatter.record(encoder)?;
        operations.function_params.record(encoder)?;
        stamp!("lowering.semantic.functions.layout.done");
        operations.project.record(encoder)?;
        stamp!("lowering.semantic.project.done");
        operations.call_argument_scan.record(encoder)?;
        stamp!("lowering.semantic.call_arguments.scan.done");
        operations.local_scatter.record(encoder)?;
        stamp!("lowering.semantic.locals.scatter.done");
        operations.execution_rank_init.record(encoder)?;
        for _ in 0..self.execution_rank_pairs {
            operations.execution_rank_a_to_b.record(encoder)?;
            operations.execution_rank_b_to_a.record(encoder)?;
        }
        stamp!("lowering.semantic.execution_rank.done");
        operations.count.record(encoder)?;
        operations.instruction_scan.record(encoder)?;
        stamp!("lowering.semantic.instructions.scan.done");
        operations.scatter.record(encoder)?;
        stamp!("lowering.semantic.instructions.scatter.done");
        operations.call_args.record(encoder)?;
        stamp!("lowering.semantic.call_arguments.scatter.done");
        operations.aggregate_elements.record(encoder)?;
        stamp!("lowering.semantic.aggregate_elements.done");
        operations.strings.record(encoder)?;
        stamp!("lowering.semantic.strings.done");
        if let Some(sorter) = &self.semantic_sorter {
            sorter.record_timed(encoder, timer.as_deref_mut())?;
        }
        stamp!("lowering.semantic.schedule.done");
        Ok(())
    }
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
            passes_core::{
                make_pass_data_from_shader_key,
                map_readback_blocking,
                pipeline_creation_count,
            },
            scan::hierarchical_scan_levels,
        },
        parser::buffers::{
            HirCallArg,
            HirCore,
            HirMatchArm,
            HirMatchPayload,
            HirMethodCore,
            HirMethodSignature,
            HirPayload,
            HirVariant,
            HirVariantPayload,
        },
    };

    fn make_group<'a>(
        device: &wgpu::Device,
        pass: &PassData,
        label: &str,
        bindings: &[(&str, wgpu::BindingResource<'a>)],
    ) -> Result<wgpu::BindGroup> {
        crate::gpu::passes_core::bind_group::validate_exact_binding_names(pass, 0, bindings)?;
        crate::gpu::passes_core::bind_group::create_bind_group_from_bindings(
            device,
            Some(label),
            pass,
            0,
            bindings,
        )
    }

    fn record_direct(
        encoder: &mut wgpu::CommandEncoder,
        pass: &PassData,
        bind_group: &wgpu::BindGroup,
        elements: u32,
    ) -> Result<()> {
        if elements == 0 {
            return Ok(());
        }
        let (x, y, z) = crate::gpu::passes_core::plan_workgroups(
            crate::gpu::passes_core::DispatchDim::D1,
            crate::gpu::passes_core::InputElements::Elements1D(elements),
            pass.thread_group_size,
        )?;
        let mut compute = crate::gpu::passes_core::begin_counted_compute_pass(
            encoder,
            &wgpu::ComputePassDescriptor {
                label: Some(&pass.shader_id),
                timestamp_writes: None,
            },
        );
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, Some(bind_group), &[]);
        crate::gpu::passes_core::record_compute_dispatch();
        compute.dispatch_workgroups(x, y, z);
        Ok(())
    }

    fn words<const N: usize>(records: &[[u32; N]]) -> Vec<u8> {
        records
            .iter()
            .flat_map(|record| record.iter())
            .flat_map(|word| word.to_le_bytes())
            .collect()
    }

    fn packed_schedule_key(layout: TargetScheduleRadixLayout, raw: [u32; 4]) -> [u32; 3] {
        let mut packed = 0u128;
        let mut destination_bit = 0u32;
        for (field, value) in [raw[3], raw[2], raw[1]].into_iter().enumerate() {
            let width = ((layout.packed_bits >> (field as u32 * 6)) & 0x3f).clamp(1, 32);
            let mask = if width == 32 {
                u32::MAX
            } else {
                (1u32 << width) - 1
            };
            let encoded = if value == u32::MAX {
                mask
            } else if field == 0
                && layout.packed_bits & (1 << 31) != 0
                && (0x4000_0000..=0x7fff_ffff).contains(&value)
            {
                let depth = 0x7fff_ffff - value;
                mask - 1 - depth.min(mask - 1)
            } else {
                value & mask
            };
            packed |= u128::from(encoded) << destination_bit;
            destination_bit += width;
        }
        [packed as u32, (packed >> 32) as u32, (packed >> 64) as u32]
    }

    fn compact_semantic_core_records(records: &[[u32; 8]]) -> Vec<[u32; 4]> {
        records
            .iter()
            .map(|record| {
                let [
                    op,
                    type_id,
                    type_ref_tag,
                    type_ref_payload,
                    _,
                    flags,
                    words,
                    _array_length,
                ] = *record;
                [
                    type_id,
                    type_ref_payload,
                    flags | ((op & 0x3f) << 24) | ((type_ref_tag & 3) << 30),
                    words,
                ]
            })
            .collect()
    }

    fn semantic_op(core: &[u32], row: usize) -> u32 {
        (core[row * 4 + 2] >> 24) & 0x3f
    }

    fn checked_calls(
        device: &wgpu::Device,
        label: &str,
        records: &[[u32; 10]],
    ) -> LaniusBuffer<crate::type_checker::GpuCheckedCallArtifact> {
        let records = records
            .iter()
            .map(|record| {
                let mut complete = [u32::MAX; 14];
                complete[..10].copy_from_slice(record);
                complete[11] = if record[0] != u32::MAX {
                    1
                } else if record[1] != u32::MAX && record[2] != u32::MAX && record[3] != u32::MAX {
                    3
                } else if record[5] != 0 {
                    2
                } else {
                    0
                };
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
            0,
            u32::MAX,
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

    struct EmptyPatternFamilies {
        fn_return_type: LaniusBuffer<u32>,
        variant_count: LaniusBuffer<u32>,
        variants: LaniusBuffer<HirVariant>,
        variant_payload_start: LaniusBuffer<u32>,
        variant_payload_count: LaniusBuffer<u32>,
        variant_payload_row_count: LaniusBuffer<u32>,
        variant_payloads: LaniusBuffer<HirVariantPayload>,
        match_arm_count: LaniusBuffer<u32>,
        match_arms: LaniusBuffer<HirMatchArm>,
        match_payload_start: LaniusBuffer<u32>,
        match_payload_count: LaniusBuffer<u32>,
        match_payload_row_count: LaniusBuffer<u32>,
        match_payloads: LaniusBuffer<HirMatchPayload>,
    }

    fn empty_pattern_families(
        device: &wgpu::Device,
        label: &str,
        hir_capacity: usize,
    ) -> EmptyPatternFamilies {
        EmptyPatternFamilies {
            fn_return_type: storage_ro_from_u32s(
                device,
                &format!("{label}.fn_return_type"),
                &vec![u32::MAX; hir_capacity.max(1)],
            ),
            variant_count: storage_ro_from_u32s(device, &format!("{label}.variant_count"), &[0]),
            variants: storage_ro_from_bytes::<HirVariant>(
                device,
                &format!("{label}.variants"),
                &words(&[[u32::MAX; 4]]),
                1,
            ),
            variant_payload_start: storage_ro_from_u32s(
                device,
                &format!("{label}.variant_payload_start"),
                &vec![u32::MAX; hir_capacity.max(1)],
            ),
            variant_payload_count: storage_ro_from_u32s(
                device,
                &format!("{label}.variant_payload_count"),
                &vec![0; hir_capacity.max(1)],
            ),
            variant_payload_row_count: storage_ro_from_u32s(
                device,
                &format!("{label}.variant_payload_row_count"),
                &[0],
            ),
            variant_payloads: storage_ro_from_bytes::<HirVariantPayload>(
                device,
                &format!("{label}.variant_payloads"),
                &words(&[[u32::MAX; 4]]),
                1,
            ),
            match_arm_count: storage_ro_from_u32s(
                device,
                &format!("{label}.match_arm_count"),
                &[0],
            ),
            match_arms: storage_ro_from_bytes::<HirMatchArm>(
                device,
                &format!("{label}.match_arms"),
                &words(&[[u32::MAX; 4]]),
                1,
            ),
            match_payload_start: storage_ro_from_u32s(
                device,
                &format!("{label}.match_payload_start"),
                &vec![u32::MAX; hir_capacity.max(1)],
            ),
            match_payload_count: storage_ro_from_u32s(
                device,
                &format!("{label}.match_payload_count"),
                &vec![0; hir_capacity.max(1)],
            ),
            match_payload_row_count: storage_ro_from_u32s(
                device,
                &format!("{label}.match_payload_row_count"),
                &[0],
            ),
            match_payloads: storage_ro_from_bytes::<HirMatchPayload>(
                device,
                &format!("{label}.match_payloads"),
                &words(&[[u32::MAX; 4]]),
                1,
            ),
        }
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
    fn physical_gpu_stably_sorts_wasm_schedule_across_scan_hierarchy() {
        let gpu = device::global();
        let radix_layout = TargetScheduleRadixLayout::packed_width();
        let count = 70_000u32;
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
        let packed_keys = key_words
            .iter()
            .copied()
            .map(|key| packed_schedule_key(radix_layout, key))
            .collect::<Vec<_>>();
        let keys = storage_ro_from_bytes::<TargetScheduleKey>(
            &gpu.device,
            "test.schedule.keys",
            &words(&packed_keys),
            count as usize,
        );
        let order_a =
            storage_rw_for_array::<u32>(&gpu.device, "test.schedule.order_a", count as usize);
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
        for key_step in 0..radix_layout.steps {
            let params = uniform_from_val(
                &gpu.device,
                &format!("test.schedule.radix.{key_step}"),
                &WasmRadixTestParams {
                    target_capacity: count,
                    max_blocks: blocks,
                    key_step,
                    reserved: radix_layout.packed_bits,
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
                    ("target_schedule_slot_count", slot_count.as_entire_binding()),
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
        order_b.copy_to(&mut encoder, 0, &readback, 0, u64::from(count) * 4);
        gpu.queue.submit(Some(encoder.finish()));

        let actual = read_words(&gpu.device, &readback);
        let mut expected = (0..count).collect::<Vec<_>>();
        expected.sort_by_key(|&row| {
            let key = key_words[row as usize];
            [key[1], key[2], key[3]]
        });
        assert_eq!(actual, expected);
    }

    #[test]
    fn physical_gpu_resident_scheduler_handles_odd_width_without_record_allocations() {
        let gpu = device::global();
        let count = 257u32;
        let capacities = LoweringCapacities {
            source_bytes: count,
            tokens: 128,
            hir_nodes: 128,
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
                    match row % 3 {
                        0 => (row * 3) % 23,
                        1 => 0x7fff_ffff - ((row * 3) % 23),
                        _ => u32::MAX,
                    },
                ]
            })
            .collect::<Vec<_>>();
        total.write(&gpu.queue, 0, &count.to_le_bytes());
        let radix_layout = TargetScheduleRadixLayout::for_capacities(capacities);
        let packed_keys = key_words
            .iter()
            .copied()
            .map(|key| packed_schedule_key(radix_layout, key))
            .collect::<Vec<_>>();
        keys.write(&gpu.queue, 0, &words(&packed_keys));
        let kernels =
            KernelRegistry::prepare_prefixes(&gpu.device, &["codegen/lir", "scan/counted"], |_| {
                true
            })
            .unwrap();
        let sorter = GpuStableScheduleSorter::new_semantic(
            &gpu.device,
            &kernels,
            &graph,
            &workspace,
            &workspace.allocations(),
            count,
            radix_layout,
            &total,
            &keys,
            &order,
        )
        .unwrap();
        assert_eq!(radix_layout.steps, 4);
        let pipelines_before = pipeline_creation_count();
        let buffers_before = tracked_buffer_allocation_stats();
        let passes_before = crate::gpu::passes_core::recorded_compute_pass_count();
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.resident_schedule.encoder"),
            });
        sorter.record(&mut encoder).unwrap();
        let passes_after = crate::gpu::passes_core::recorded_compute_pass_count();
        let hierarchy_levels = hierarchical_scan_levels(count.div_ceil(256)).len();
        let passes_per_digit = 3 + 2 * hierarchy_levels as u64;
        assert_eq!(passes_after - passes_before, 4 * passes_per_digit);
        assert_eq!(pipeline_creation_count(), pipelines_before);
        assert_eq!(tracked_buffer_allocation_stats(), buffers_before);

        let readback = readback_bytes(
            &gpu.device,
            "test.resident_schedule.readback",
            count as usize * 4,
            count as usize,
        );
        sorter
            .output_order()
            .copy_to(&mut encoder, 0, &readback, 0, u64::from(count) * 4);
        gpu.queue.submit(Some(encoder.finish()));
        let actual = read_words(&gpu.device, &readback);
        let mut expected = (0..count).collect::<Vec<_>>();
        expected.sort_by_key(|&row| {
            let key = key_words[row as usize];
            [key[1], key[2], key[3]]
        });
        assert_eq!(actual, expected);
    }

    #[test]
    fn physical_gpu_lowers_semantic_lir_to_wasm_lir() {
        let gpu = device::global();
        let semantic_total = storage_ro_from_u32s(&gpu.device, "test.wasm_lir.total", &[5]);
        let semantic_core = storage_ro_from_bytes::<SemanticLirCore>(
            &gpu.device,
            "test.wasm_lir.semantic_core",
            &words(&compact_semantic_core_records(&[
                [
                    super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_CONST_I32,
                    3,
                    0,
                    u32::MAX,
                    0,
                    0,
                    0,
                    u32::MAX,
                ],
                [
                    super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_CONST_I32,
                    3,
                    0,
                    u32::MAX,
                    1,
                    0,
                    0,
                    u32::MAX,
                ],
                [
                    super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_ADD,
                    3,
                    0,
                    u32::MAX,
                    2,
                    0,
                    0,
                    u32::MAX,
                ],
                [
                    super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_RETURN,
                    0,
                    0,
                    u32::MAX,
                    3,
                    0,
                    0,
                    u32::MAX,
                ],
                [
                    super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_CALL_SYMBOL,
                    3,
                    0,
                    u32::MAX,
                    4,
                    0,
                    0,
                    u32::MAX,
                ],
            ])),
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
        let semantic_layout =
            storage_ro_from_u32s(&gpu.device, "test.wasm_lir.layout_word_offset", &[0; 5]);
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
                    "semantic_lir_layout_word_offset",
                    semantic_layout.as_entire_binding(),
                ),
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
        target_counts.copy_to(&mut encoder, 0, &count_readback, 0, 20);
        target_core.copy_to(&mut encoder, 0, &core_readback, 0, 80);
        target_operands.copy_to(&mut encoder, 0, &operands_readback, 0, 80);
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
        let kernels =
            KernelRegistry::prepare_prefixes(&gpu.device, &["codegen/lir", "scan/counted"], |_| {
                true
            })
            .unwrap();
        let (method_count, method_cores, method_signatures) =
            empty_method_families(&gpu.device, "test.semantic_lir.methods");
        let patterns = empty_pattern_families(&gpu.device, "test.semantic_lir.patterns", 10);
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.semantic_lir.encoder"),
            });
        let hir_inputs = GpuSemanticHirInputs {
            count: &hir_count,
            core: &hir_core,
            links: &hir_links,
            payload: &hir_payload,
            fn_return_type: &patterns.fn_return_type,
            const_value: &expr_root,
            expr_parent: &expr_parent,
            expr_root: &expr_root,
            nearest_loop: &expr_root,
            call_arg_count: &call_arg_count,
            call_args: &call_args,
            field_count: &family_count,
            fields: &fields,
            variant_count: &patterns.variant_count,
            variants: &patterns.variants,
            variant_payload_start: &patterns.variant_payload_start,
            variant_payload_count: &patterns.variant_payload_count,
            variant_payload_row_count: &patterns.variant_payload_row_count,
            variant_payloads: &patterns.variant_payloads,
            match_arm_count: &patterns.match_arm_count,
            match_arms: &patterns.match_arms,
            match_payload_start: &patterns.match_payload_start,
            match_payload_count: &patterns.match_payload_count,
            match_payload_row_count: &patterns.match_payload_row_count,
            match_payloads: &patterns.match_payloads,
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
        };
        let semantic_inputs = GpuSemanticArtifactView {
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
        };
        let stage = GpuSemanticLoweringStage::from_workspace(
            &gpu.device,
            capacities,
            graph,
            &workspace,
            &kernels,
            hir_inputs,
            semantic_inputs,
        )
        .unwrap();
        stage.record(&mut encoder).unwrap();
        let output = stage.output();
        let count_readback = readback_bytes(&gpu.device, "test.lir.count.rb", 4, 1);
        let core_readback = readback_bytes(&gpu.device, "test.lir.core.rb", 144, 36);
        let operands_readback = readback_bytes(&gpu.device, "test.lir.operands.rb", 144, 36);
        let owner_readback = readback_bytes(&gpu.device, "test.lir.owner.rb", 36, 9);
        let order_readback = readback_bytes(&gpu.device, "test.lir.order.rb", 36, 9);
        let scheduled_core_readback =
            readback_bytes(&gpu.device, "test.lir.scheduled_core.rb", 144, 36);
        let scheduled_operands_readback =
            readback_bytes(&gpu.device, "test.lir.scheduled_operands.rb", 144, 36);
        output.count.copy_to(&mut encoder, 0, &count_readback, 0, 4);
        output.core.copy_to(&mut encoder, 0, &core_readback, 0, 144);
        output
            .operands
            .copy_to(&mut encoder, 0, &operands_readback, 0, 144);
        output
            .owner_by_instruction
            .copy_to(&mut encoder, 0, &owner_readback, 0, 36);
        output
            .execution_order
            .unwrap()
            .copy_to(&mut encoder, 0, &order_readback, 0, 36);
        stage
            .core
            .copy_to(&mut encoder, 0, &scheduled_core_readback, 0, 144);
        stage
            .operands
            .copy_to(&mut encoder, 0, &scheduled_operands_readback, 0, 144);
        gpu.queue.submit(Some(encoder.finish()));

        assert_eq!(read_words(&gpu.device, &count_readback)[0], 7);
        let core = read_words(&gpu.device, &core_readback);
        let owners = read_words(&gpu.device, &owner_readback);
        assert_eq!(&owners[..7], &[0, 1, 2, 3, 5, 8, 9]);
        assert_eq!(
            [
                semantic_op(&core, 0),
                semantic_op(&core, 1),
                semantic_op(&core, 2),
                semantic_op(&core, 3),
                semantic_op(&core, 4),
                semantic_op(&core, 5),
                semantic_op(&core, 6),
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
        assert_eq!([core[2] >> 30, core[1]], [1, 3]);
        assert_eq!([core[26] >> 30, core[25]], [3, 42]);
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
                &scheduled_core[scheduled_row * 4..scheduled_row * 4 + 4],
                &core[semantic_row * 4..semantic_row * 4 + 4],
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
        let capacities = LoweringCapacities {
            source_bytes: 12,
            tokens: 12,
            hir_nodes: 4,
            semantic_instructions: 4,
            call_arguments: 2,
            parameters: 2,
            aggregate_elements: 2,
            target_instructions: 4,
            artifact_bytes: 32,
        };
        let (method_count, method_cores, method_signatures) =
            empty_method_families(&gpu.device, "test.abi.methods");
        let patterns = empty_pattern_families(&gpu.device, "test.abi.patterns", 4);
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.abi.encoder"),
            });
        let hir_inputs = GpuSemanticHirInputs {
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
            fn_return_type: &patterns.fn_return_type,
            field_count: &zero_count,
            fields: &empty_fields,
            variant_count: &patterns.variant_count,
            variants: &patterns.variants,
            variant_payload_start: &patterns.variant_payload_start,
            variant_payload_count: &patterns.variant_payload_count,
            variant_payload_row_count: &patterns.variant_payload_row_count,
            variant_payloads: &patterns.variant_payloads,
            match_arm_count: &patterns.match_arm_count,
            match_arms: &patterns.match_arms,
            match_payload_start: &patterns.match_payload_start,
            match_payload_count: &patterns.match_payload_count,
            match_payload_row_count: &patterns.match_payload_row_count,
            match_payloads: &patterns.match_payloads,
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
        };
        let semantic_inputs = GpuSemanticArtifactView {
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
        };
        let stage =
            GpuSemanticLoweringStage::new(&gpu.device, capacities, hir_inputs, semantic_inputs)
                .unwrap();
        stage.record(&mut encoder).unwrap();
        let function_readback = readback_bytes(&gpu.device, "test.abi.functions.rb", 52, 13);
        let param_readback = readback_bytes(&gpu.device, "test.abi.params.rb", 32, 8);
        let local_readback = readback_bytes(&gpu.device, "test.abi.locals.rb", 16, 4);
        let param_count_readback = readback_bytes(&gpu.device, "test.abi.param_count.rb", 4, 1);
        let function_count_readback =
            readback_bytes(&gpu.device, "test.abi.function_count.rb", 4, 1);
        let local_count_readback = readback_bytes(&gpu.device, "test.abi.local_count.rb", 4, 1);
        let output = stage.output();
        output
            .functions
            .copy_to(&mut encoder, 0, &function_readback, 0, 52);
        output
            .params
            .copy_to(&mut encoder, 0, &param_readback, 0, 32);
        output
            .locals
            .copy_to(&mut encoder, 0, &local_readback, 0, 16);
        output
            .param_count
            .copy_to(&mut encoder, 0, &param_count_readback, 0, 4);
        output
            .function_count
            .copy_to(&mut encoder, 0, &function_count_readback, 0, 4);
        output
            .local_count
            .copy_to(&mut encoder, 0, &local_count_readback, 0, 4);
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
        let capacities = LoweringCapacities {
            source_bytes: 16,
            tokens: 16,
            hir_nodes: 4,
            semantic_instructions: 4,
            call_arguments: 1,
            parameters: 1,
            aggregate_elements: 4,
            target_instructions: 8,
            artifact_bytes: 64,
        };
        let (method_count, method_cores, method_signatures) =
            empty_method_families(&gpu.device, "test.family.methods");
        let patterns = empty_pattern_families(&gpu.device, "test.family.patterns", 4);
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.family.encoder"),
            });
        let hir_inputs = GpuSemanticHirInputs {
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
            fn_return_type: &patterns.fn_return_type,
            field_count: &field_count,
            fields: &fields,
            variant_count: &patterns.variant_count,
            variants: &patterns.variants,
            variant_payload_start: &patterns.variant_payload_start,
            variant_payload_count: &patterns.variant_payload_count,
            variant_payload_row_count: &patterns.variant_payload_row_count,
            variant_payloads: &patterns.variant_payloads,
            match_arm_count: &patterns.match_arm_count,
            match_arms: &patterns.match_arms,
            match_payload_start: &patterns.match_payload_start,
            match_payload_count: &patterns.match_payload_count,
            match_payload_row_count: &patterns.match_payload_row_count,
            match_payloads: &patterns.match_payloads,
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
        };
        let semantic_inputs = GpuSemanticArtifactView {
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
        };
        let stage =
            GpuSemanticLoweringStage::new(&gpu.device, capacities, hir_inputs, semantic_inputs)
                .unwrap();
        stage.record(&mut encoder).unwrap();
        let output = stage.output();
        let operands_rb = readback_bytes(&gpu.device, "test.family.operands.rb", 64, 16);
        let core_rb = readback_bytes(&gpu.device, "test.family.core.rb", 64, 16);
        let aggregate_count_rb =
            readback_bytes(&gpu.device, "test.family.aggregate_count.rb", 4, 1);
        let aggregates_rb = readback_bytes(&gpu.device, "test.family.aggregates.rb", 84, 21);
        let strings_rb = readback_bytes(&gpu.device, "test.family.strings.rb", 16, 4);
        let string_data_rb = readback_bytes(&gpu.device, "test.family.string_data.rb", 4, 1);
        output
            .operands
            .copy_to(&mut encoder, 0, &operands_rb, 0, 64);
        output.core.copy_to(&mut encoder, 0, &core_rb, 0, 64);
        output
            .aggregate_element_count
            .copy_to(&mut encoder, 0, &aggregate_count_rb, 0, 4);
        output
            .aggregate_elements
            .copy_to(&mut encoder, 0, &aggregates_rb, 0, 84);
        output.strings.copy_to(&mut encoder, 0, &strings_rb, 0, 16);
        output
            .string_data_words
            .copy_to(&mut encoder, 0, &string_data_rb, 0, 4);
        gpu.queue.submit(Some(encoder.finish()));

        let operands = read_words(&gpu.device, &operands_rb);
        assert_eq!(read_words(&gpu.device, &core_rb), &[0; 16]);
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
        let capacities = LoweringCapacities {
            source_bytes: 16,
            tokens: 16,
            hir_nodes: 5,
            semantic_instructions: 13,
            call_arguments: 1,
            parameters: 1,
            aggregate_elements: 1,
            target_instructions: 8,
            artifact_bytes: 64,
        };
        let (method_count, method_cores, method_signatures) =
            empty_method_families(&gpu.device, "test.control.methods");
        let patterns = empty_pattern_families(&gpu.device, "test.control.patterns", 5);
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.control.encoder"),
            });
        let hir_inputs = GpuSemanticHirInputs {
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
            fn_return_type: &patterns.fn_return_type,
            field_count: &family_count,
            fields: &fields,
            variant_count: &patterns.variant_count,
            variants: &patterns.variants,
            variant_payload_start: &patterns.variant_payload_start,
            variant_payload_count: &patterns.variant_payload_count,
            variant_payload_row_count: &patterns.variant_payload_row_count,
            variant_payloads: &patterns.variant_payloads,
            match_arm_count: &patterns.match_arm_count,
            match_arms: &patterns.match_arms,
            match_payload_start: &patterns.match_payload_start,
            match_payload_count: &patterns.match_payload_count,
            match_payload_row_count: &patterns.match_payload_row_count,
            match_payloads: &patterns.match_payloads,
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
        };
        let semantic_inputs = GpuSemanticArtifactView {
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
        };
        let stage =
            GpuSemanticLoweringStage::new(&gpu.device, capacities, hir_inputs, semantic_inputs)
                .unwrap();
        stage.record(&mut encoder).unwrap();
        let output = stage.output();
        let count_readback = readback_bytes(&gpu.device, "test.control.count.rb", 4, 1);
        let core_readback = readback_bytes(&gpu.device, "test.control.core.rb", 208, 52);
        let operands_readback = readback_bytes(&gpu.device, "test.control.operands.rb", 208, 52);
        let status_readback = readback_bytes(&gpu.device, "test.control.status.rb", 16, 4);
        output.count.copy_to(&mut encoder, 0, &count_readback, 0, 4);
        output.core.copy_to(&mut encoder, 0, &core_readback, 0, 208);
        output
            .operands
            .copy_to(&mut encoder, 0, &operands_readback, 0, 208);
        stage
            .status()
            .copy_to(&mut encoder, 0, &status_readback, 0, 16);
        gpu.queue.submit(Some(encoder.finish()));

        let status = read_words(&gpu.device, &status_readback);
        assert_eq!(
            read_words(&gpu.device, &count_readback)[0],
            13,
            "lowering status: {status:?}"
        );
        let core = read_words(&gpu.device, &core_readback);
        assert_eq!(
            [
                semantic_op(&core, 0),
                semantic_op(&core, 1),
                semantic_op(&core, 2)
            ],
            [
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_CONST_I32,
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_IF_BEGIN,
                super::super::lowering_ir::opcode::SEMANTIC_LIR_OP_CONTROL_END,
            ]
        );
        assert_eq!(
            core[14]
                & super::super::lowering_ir::opcode::SEMANTIC_LIR_FLAG_UNSUPPORTED_MATCH_CONTEXT,
            0,
            "match result rows are valid values in ordinary expression contexts"
        );
        assert_eq!(
            [
                semantic_op(&core, 7),
                semantic_op(&core, 8),
                semantic_op(&core, 9),
                semantic_op(&core, 10),
                semantic_op(&core, 11),
                semantic_op(&core, 12),
            ],
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
        assert_eq!(&operands[36..40], &[9, 0, 1, 12]);
        assert_eq!(&operands[40..44], &[10, 8, 0, u32::MAX]);
        assert_eq!(status, [0, u32::MAX, 0, u32::MAX]);
    }
}
