use super::*;
use crate::gpu::{
    compiler_graph::{
        BoundGraphResource,
        CompilerGraph,
        CompilerGraphAllocations,
        CompilerGraphBuilder,
        CompilerGraphWorkspace,
        CompilerPhase,
        PassAccess,
        PassDesc,
        ReflectedResourceBinding,
        ResourceClass,
        ResourceDesc,
        ResourceDomain,
        ResourceId,
    },
    workspace::WorkspaceUsageClass,
};

pub(super) const INIT_PASS: &str = "type_check.expression_types.init";
const STEP_A_TO_B_PASS: &str = "type_check.expression_types.step.a_to_b";
const STEP_B_TO_A_PASS: &str = "type_check.expression_types.step.b_to_a";
const STEP_A_TO_B_TAIL_PASS: &str = "type_check.expression_types.step.a_to_b.tail";
pub(super) const CONDITIONS_COMPACT_EXPR_PASS: &str = "type_check.conditions.compact_expr";
pub(super) const CONDITIONS_COMPACT_STMT_PASS: &str = "type_check.conditions.compact_stmt";
pub(super) const CONDITIONS_COMPACT_AGGREGATE_REQUESTS_PASS: &str =
    "type_check.conditions.compact_aggregate_requests";
pub(super) const CONDITIONS_AGGREGATE_ARGS_CALLS_PASS: &str =
    "type_check.conditions.aggregate_args.calls";
pub(super) const CONDITIONS_AGGREGATE_ARGS_FINAL_PASS: &str =
    "type_check.conditions.aggregate_args.final";
pub(super) const CONDITIONS_COMPACT_CALLS_PASS: &str = "type_check.conditions.compact_calls";
pub(super) const CONDITIONS_COMPACT_TYPES_PASS: &str = "type_check.conditions.compact_types";
pub(super) const CONDITIONS_COMPACT_METHODS_PASS: &str = "type_check.conditions.compact_methods";
pub(super) const PREDICATE_DIAGNOSTICS_CLEAR_PASS: &str =
    "type_check.semantic_artifact.predicate_diagnostics.clear";
pub(super) const PREDICATE_DIAGNOSTICS_CLAIM_PASS: &str =
    "type_check.semantic_artifact.predicate_diagnostics.claim";
pub(super) const PREDICATE_DIAGNOSTICS_PROJECT_PASS: &str =
    "type_check.semantic_artifact.predicate_diagnostics";
pub(super) const CONDITIONS_COMPACT_PREDICATES_PASS: &str =
    "type_check.conditions.compact_predicates";
pub(super) const CONDITIONS_COMPACT_NAMES_PASS: &str = "type_check.conditions.compact_names";
pub(super) const SEMANTIC_CALLS_PROJECT_PASS: &str = "type_check.semantic_artifact.calls";
pub(super) const SEMANTIC_EXPRESSION_REFS_PROJECT_PASS: &str =
    "type_check.semantic_artifact.expression_refs";
pub(super) const SEMANTIC_STRUCT_LITERAL_REFS_PROJECT_PASS: &str =
    "type_check.semantic_artifact.struct_literal_refs";
pub(super) const FEATURES_CLEAR_PASS: &str = "type_check.semantic_features.clear";
pub(super) const FEATURES_COLLECT_PASS: &str = "type_check.semantic_features.collect";
pub(super) const FEATURES_DISPATCH_PASS: &str = "type_check.semantic_features.dispatch_args";
const CALL_ARRAY_STATE_INIT_PASS: &str = "type_check.calls.array_state.init";
const CALL_ARRAY_STATE_PUBLISH_PASS: &str = "type_check.calls.array_state.publish";
const CALL_ARRAY_STATE_CONSUME_PASS: &str = "type_check.calls.array_state.consume";
pub(super) const CALL_RESULT_INSTANCE_PROJECT_PASS: &str =
    "type_check.calls.result_instances.project";
pub(super) const CALLS_BACKEND_TARGETS_PASS: &str = "type_check.calls.backend_targets";
const VISIBLE_MARK_PASS: &str = "type_check.visible.mark_hir_decl_names";
const VISIBLE_SCAN_PASS: &str = "type_check.visible.decl_scan";
const VISIBLE_SCATTER_PASS: &str = "type_check.visible.scatter_hir_decl_records";
const VISIBLE_SORT_PASS: &str = "type_check.visible.sort_hir_decl_keys";
const VISIBLE_SCOPE_TREE_PASS: &str = "type_check.visible.build_hir_decl_scope_tree";
const VISIBLE_NAMES_PASS: &str = "type_check.visible.hir_names";
pub(super) const SCOPE_HIR_PASS: &str = "type_check.scope.hir";
pub(super) const SEMANTIC_ARTIFACT_PROJECT_PASS: &str = "type_check.semantic_artifact.project";

pub(super) const REGISTERED_VISIBLE_PASSES: [&str; 6] = [
    VISIBLE_MARK_PASS,
    VISIBLE_SCAN_PASS,
    VISIBLE_SCATTER_PASS,
    VISIBLE_SORT_PASS,
    VISIBLE_SCOPE_TREE_PASS,
    VISIBLE_NAMES_PASS,
];
const CALL_PARAM_ROW_SCAN_PASS: &str = "type_check.calls.param_rows.scan";
const CALL_ARG_MATCH_INIT_PASS: &str = "type_check.calls.arg_match.init";
const CALL_ARG_MATCH_CONSUME_PASS: &str = "type_check.calls.arg_match.consume";
const CALL_ARG_ROW_MARK_PASS: &str = "type_check.calls.arg_rows.mark";
const CALL_ARG_ROW_SCAN_PASS: &str = "type_check.calls.arg_rows.scan";
const CALL_ARG_ROW_SCATTER_PASS: &str = "type_check.calls.arg_rows.scatter";
const GENERIC_CLAIM_COLLECT_PASS: &str = "type_check.calls.generic_claims.collect";
const GENERIC_CLAIM_SCAN_PASS: &str = "type_check.calls.generic_claims.scan";
const GENERIC_CLAIM_EMIT_PASS: &str = "type_check.calls.generic_claims.emit";
const GENERIC_CLAIM_SORT_PASS: &str = "type_check.calls.generic_claims.sort";
const CONST_CLAIM_SORT_PASS: &str = "type_check.calls.const_claims.sort";
const REQUIRED_GENERIC_MARK_PASS: &str = "type_check.calls.required_generics.mark";
const REQUIRED_GENERIC_SCAN_PASS: &str = "type_check.calls.required_generics.scan";
const REQUIRED_GENERIC_DISPATCH_PASS: &str = "type_check.calls.required_generics.dispatch";
const REQUIRED_GENERIC_VALIDATE_PASS: &str = "type_check.calls.required_generics.validate";
pub(super) const RETURNS_CLEAR_PASS: &str = "type_check.returns.clear";
pub(super) const RETURNS_MARK_PASS: &str = "type_check.returns.mark";
pub(super) const RETURNS_MARK_IF_PASS: &str = "type_check.returns.mark_if";
pub(super) const RETURNS_VALIDATE_PASS: &str = "type_check.returns.validate";

#[derive(Clone, Copy)]
struct ExpressionTypeResources {
    compact_hir_count: ResourceId,
    compact_hir_core: ResourceId,
    compact_hir_links: ResourceId,
    compact_hir_payload: ResourceId,
    compact_param_count: ResourceId,
    compact_params: ResourceId,
    compact_hir_expr_parent: ResourceId,
    compact_hir_nearest_loop: ResourceId,
    compact_hir_nearest_block: ResourceId,
    compact_hir_nearest_control: ResourceId,
    compact_hir_nearest_fn: ResourceId,
    compact_path_count: ResourceId,
    compact_paths: ResourceId,
    compact_path_segment_count: ResourceId,
    compact_path_segments: ResourceId,
    path_id_by_owner_hir: ResourceId,
    visible_decl: ResourceId,
    visible_type: ResourceId,
    call_return_type: ResourceId,
    call_return_type_token: ResourceId,
    enclosing_fn: ResourceId,
    decl_type_ref_tag: ResourceId,
    decl_type_ref_payload: ResourceId,
    fn_return_ref_tag: ResourceId,
    fn_return_ref_payload: ResourceId,
    call_fn_index: ResourceId,
    fn_start_token_by_decl_token: ResourceId,
    backend_call_fn_index: ResourceId,
    call_param_row_count_out: ResourceId,
    call_param_row_fn_token: ResourceId,
    call_param_row_start: ResourceId,
    call_param_row_count: ResourceId,
    call_param_count: ResourceId,
    method_decl_param_offset: ResourceId,
    method_decl_receiver_mode: ResourceId,
    call_dependency_decl: ResourceId,
    type_instance_kind: ResourceId,
    type_instance_decl_token: ResourceId,
    type_instance_external_canonical: ResourceId,
    type_instance_arg_count: ResourceId,
    type_instance_elem_ref_tag: ResourceId,
    type_instance_elem_ref_payload: ResourceId,
    call_intrinsic_tag: ResourceId,
    method_call_name_id: ResourceId,
    module_value_path_status: ResourceId,
    module_type_path_status: ResourceId,
    module_value_path_call_leaf: ResourceId,
    module_value_path_associated_method_token: ResourceId,
    token_count: ResourceId,
    hir_active_count: ResourceId,
    compact_method_count: ResourceId,
    compact_method_cores: ResourceId,
    compact_method_signatures: ResourceId,
    token_words: ResourceId,
    predicate_syntax_token: ResourceId,
    type_expr_ref_tag: ResourceId,
    type_expr_ref_payload: ResourceId,
    member_result_ref_tag: ResourceId,
    member_result_ref_payload: ResourceId,
    type_generic_param_slot_by_token: ResourceId,
    type_const_param_slot_by_token: ResourceId,
    type_instance_len_kind: ResourceId,
    type_instance_len_payload: ResourceId,
    compact_predicate_count: ResourceId,
    compact_predicates: ResourceId,
    hir_status: ResourceId,
    hir_token_pos: ResourceId,
    raw_to_compact_hir: ResourceId,
    predicate_bound_first_arg_token: ResourceId,
    predicate_bound_second_arg_token: ResourceId,
    predicate_status: ResourceId,
    predicate_method_contract_status: ResourceId,
    predicate_method_validation_first_error_row: ResourceId,
    predicate_method_validation_status: ResourceId,
    predicate_method_validation_detail_token: ResourceId,
    compact_predicate_diagnostic_facts: ResourceId,
    semantic_feature_flags: ResourceId,
    method_token_dispatch_args: ResourceId,
    method_hir_dispatch_args: ResourceId,
    method_compact_dispatch_args: ResourceId,
    method_token_hir_dispatch_args: ResourceId,
    method_radix_prefix_dispatch_args: ResourceId,
    method_radix_bases_dispatch_args: ResourceId,
    predicate_token_dispatch_args: ResourceId,
    predicate_hir_dispatch_args: ResourceId,
    predicate_radix_prefix_dispatch_args: ResourceId,
    predicate_radix_bases_dispatch_args: ResourceId,
    predicate_single_dispatch_args: ResourceId,
    match_hir_dispatch_args: ResourceId,
    scalar_a: ResourceId,
    scalar_b: ResourceId,
    status: ResourceId,
    return_fn_flags: ResourceId,
    return_block_flags: ResourceId,
    call_has_array_arg: ResourceId,
    call_result_instance: ResourceId,
    call_generic_return_arg_node: ResourceId,
    call_arg_param_row: ResourceId,
    call_param_row_scan_local_prefix: ResourceId,
    call_param_row_scan_block_sum: ResourceId,
    call_param_row_scan_prefix_a: ResourceId,
    call_param_row_scan_prefix_b: ResourceId,
    call_arg_row_scan_input: ResourceId,
    call_arg_row_prefix: ResourceId,
    call_arg_row_count_out: ResourceId,
    call_arg_row_scan_local_prefix: ResourceId,
    call_arg_row_scan_block_sum: ResourceId,
    call_arg_row_scan_prefix_a: ResourceId,
    call_arg_row_scan_prefix_b: ResourceId,
    generic_claim_scan_local_prefix: ResourceId,
    generic_claim_scan_block_sum: ResourceId,
    generic_claim_scan_prefix_a: ResourceId,
    generic_claim_scan_prefix_b: ResourceId,
    generic_claim_scan_input: ResourceId,
    generic_claim_prefix: ResourceId,
    generic_claim_count_out: ResourceId,
    generic_claim_radix_block_histogram: ResourceId,
    generic_claim_radix_block_bucket_prefix: ResourceId,
    generic_claim_radix_bucket_total: ResourceId,
    generic_claim_radix_bucket_base: ResourceId,
    const_claim_radix_block_histogram: ResourceId,
    const_claim_radix_block_bucket_prefix: ResourceId,
    const_claim_radix_bucket_total: ResourceId,
    const_claim_radix_bucket_base: ResourceId,
    required_generic_scan_input: ResourceId,
    required_generic_prefix: ResourceId,
    required_generic_scan_local_prefix: ResourceId,
    required_generic_scan_block_sum: ResourceId,
    required_generic_scan_prefix_a: ResourceId,
    required_generic_scan_prefix_b: ResourceId,
    required_generic_count_out: ResourceId,
    required_generic_dispatch_args: ResourceId,
    semantic_value_decl_by_hir: ResourceId,
    semantic_value_type_by_hir: ResourceId,
    semantic_param_type_by_row: ResourceId,
    semantic_enclosing_fn_by_hir: ResourceId,
    semantic_calls_by_hir: ResourceId,
    semantic_expr_ref_tag_by_hir: ResourceId,
    semantic_expr_ref_payload_by_hir: ResourceId,
    aggregate_compare_scan_input: ResourceId,
    aggregate_compare_expected_instance: ResourceId,
    aggregate_compare_actual_instance: ResourceId,
    aggregate_compare_error_token: ResourceId,
    aggregate_compare_error_detail: ResourceId,
}

/// Graph-owned storage and ownership contract for checked dense-expression
/// scalar types. This is the first type-check family on the compiler graph;
/// adjacent families are added to the same graph as their legacy resident
/// allocations are removed.
pub(super) struct TypeCheckCompilerGraph {
    graph: CompilerGraph,
    _workspace: CompilerGraphWorkspace,
    allocations: CompilerGraphAllocations,
    pub(super) scalar_a: LaniusBuffer<u32>,
    pub(super) scalar_b: LaniusBuffer<u32>,
    pub(super) semantic_feature_flags: LaniusBuffer<u32>,
    pub(super) method_token_dispatch_args: LaniusBuffer<u32>,
    pub(super) method_hir_dispatch_args: LaniusBuffer<u32>,
    pub(super) method_compact_dispatch_args: LaniusBuffer<u32>,
    pub(super) method_token_hir_dispatch_args: LaniusBuffer<u32>,
    pub(super) method_radix_prefix_dispatch_args: LaniusBuffer<u32>,
    pub(super) method_radix_bases_dispatch_args: LaniusBuffer<u32>,
    pub(super) predicate_token_dispatch_args: LaniusBuffer<u32>,
    pub(super) predicate_hir_dispatch_args: LaniusBuffer<u32>,
    pub(super) predicate_radix_prefix_dispatch_args: LaniusBuffer<u32>,
    pub(super) predicate_radix_bases_dispatch_args: LaniusBuffer<u32>,
    pub(super) predicate_single_dispatch_args: LaniusBuffer<u32>,
    pub(super) match_hir_dispatch_args: LaniusBuffer<u32>,
    pub(super) call_has_array_arg: LaniusBuffer<u32>,
    pub(super) call_result_instance: LaniusBuffer<u32>,
    pub(super) call_generic_return_arg_node: LaniusBuffer<u32>,
    pub(super) call_arg_param_row: LaniusBuffer<u32>,
    pub(super) call_param_row_scan_local_prefix: LaniusBuffer<u32>,
    pub(super) call_param_row_scan_block_sum: LaniusBuffer<u32>,
    pub(super) call_param_row_scan_prefix_a: LaniusBuffer<u32>,
    pub(super) call_param_row_scan_prefix_b: LaniusBuffer<u32>,
    pub(super) call_arg_row_scan_input: LaniusBuffer<u32>,
    pub(super) call_arg_row_prefix: LaniusBuffer<u32>,
    pub(super) call_arg_row_count_out: LaniusBuffer<u32>,
    pub(super) call_arg_row_scan_local_prefix: LaniusBuffer<u32>,
    pub(super) call_arg_row_scan_block_sum: LaniusBuffer<u32>,
    pub(super) call_arg_row_scan_prefix_a: LaniusBuffer<u32>,
    pub(super) call_arg_row_scan_prefix_b: LaniusBuffer<u32>,
    pub(super) generic_claim_scan_local_prefix: LaniusBuffer<u32>,
    pub(super) generic_claim_scan_block_sum: LaniusBuffer<u32>,
    pub(super) generic_claim_scan_prefix_a: LaniusBuffer<u32>,
    pub(super) generic_claim_scan_prefix_b: LaniusBuffer<u32>,
    pub(super) generic_claim_scan_input: LaniusBuffer<u32>,
    pub(super) generic_claim_prefix: LaniusBuffer<u32>,
    pub(super) generic_claim_count_out: LaniusBuffer<u32>,
    pub(super) generic_claim_radix_block_histogram: LaniusBuffer<u32>,
    pub(super) generic_claim_radix_block_bucket_prefix: LaniusBuffer<u32>,
    pub(super) generic_claim_radix_bucket_total: LaniusBuffer<u32>,
    pub(super) generic_claim_radix_bucket_base: LaniusBuffer<u32>,
    pub(super) const_claim_radix_block_histogram: LaniusBuffer<u32>,
    pub(super) const_claim_radix_block_bucket_prefix: LaniusBuffer<u32>,
    pub(super) const_claim_radix_bucket_total: LaniusBuffer<u32>,
    pub(super) const_claim_radix_bucket_base: LaniusBuffer<u32>,
    pub(super) required_generic_scan_input: LaniusBuffer<u32>,
    pub(super) required_generic_prefix: LaniusBuffer<u32>,
    pub(super) required_generic_scan_local_prefix: LaniusBuffer<u32>,
    pub(super) required_generic_scan_block_sum: LaniusBuffer<u32>,
    pub(super) required_generic_scan_prefix_a: LaniusBuffer<u32>,
    pub(super) required_generic_scan_prefix_b: LaniusBuffer<u32>,
    pub(super) required_generic_count_out: LaniusBuffer<u32>,
    pub(super) required_generic_dispatch_args: LaniusBuffer<u32>,
    /// Dense checked declaration identity keyed by compact HIR row.
    pub(super) semantic_value_decl_by_hir: LaniusBuffer<u32>,
    /// Dense checked type identity keyed by compact HIR row.
    pub(super) semantic_value_type_by_hir: LaniusBuffer<u32>,
    /// Checked type identity keyed by compact parameter row.
    pub(super) semantic_param_type_by_row: LaniusBuffer<u32>,
    /// Encoded enclosing compact-HIR function identity keyed by HIR row.
    pub(super) semantic_enclosing_fn_by_hir: LaniusBuffer<u32>,
    /// Fixed-width checked call records keyed by compact HIR row.
    pub(super) semantic_calls_by_hir: LaniusBuffer<GpuCheckedCallArtifact>,
    /// Canonical checked type-reference tag keyed by compact expression HIR.
    pub(super) semantic_expr_ref_tag_by_hir: LaniusBuffer<u32>,
    /// Canonical checked type-reference payload keyed by compact expression HIR.
    pub(super) semantic_expr_ref_payload_by_hir: LaniusBuffer<u32>,
    /// Phase-local raw predicate results projected by dense compact HIR row.
    /// Eight words per row; consumed only by compact diagnostic reducers.
    pub(super) compact_predicate_diagnostic_facts: LaniusBuffer<u32>,
    pub(super) return_fn_flags: LaniusBuffer<u32>,
    pub(super) return_block_flags: LaniusBuffer<u32>,
    step_count: usize,
}

impl TypeCheckCompilerGraph {
    /// Validates one recorded pass against the allocation identities retained
    /// by the reflected resource map used to build its bind group.
    pub(super) fn validate_registered_pass_bindings(
        &self,
        pass_name: &str,
        resources: &ResourceMap<'_>,
    ) -> Result<()> {
        let bindings = resources.graph_bindings(&self.graph, pass_name)?;
        let pass = self
            .graph
            .pass_id(pass_name)
            .ok_or_else(|| anyhow::anyhow!("compiler graph has no pass `{pass_name}`"))?;
        self.allocations
            .validate_pass_bindings(&self.graph, pass, &bindings)
            .map_err(anyhow::Error::msg)
    }

    pub(super) fn new(
        device: &wgpu::Device,
        hir_capacity: u32,
        token_capacity: u32,
        call_arg_capacity: u32,
        generic_claim_capacity: u32,
        feature_collect_pass: &PassData,
        feature_dispatch_pass: &PassData,
        init_pass: &PassData,
        step_pass: &PassData,
        conditions_compact_expr_pass: &PassData,
        conditions_compact_stmt_pass: &PassData,
        conditions_compact_aggregate_requests_pass: &PassData,
        conditions_aggregate_args_pass: &PassData,
        conditions_compact_calls_pass: &PassData,
        conditions_compact_types_pass: &PassData,
        conditions_compact_methods_pass: &PassData,
        predicate_diagnostics_clear_pass: &PassData,
        predicate_diagnostics_claim_pass: &PassData,
        predicate_diagnostics_project_pass: &PassData,
        conditions_compact_predicates_pass: &PassData,
        conditions_compact_names_pass: &PassData,
        calls_project_result_instances_pass: &PassData,
        visible_mark_pass: &PassData,
        visible_scatter_pass: &PassData,
        visible_names_pass: &PassData,
        scope_hir_pass: &PassData,
        returns_clear_pass: &PassData,
        returns_mark_pass: &PassData,
        returns_mark_if_pass: &PassData,
        returns_validate_pass: &PassData,
        calls_backend_targets_pass: &PassData,
        semantic_calls_project_pass: &PassData,
        semantic_expression_refs_project_pass: &PassData,
        semantic_struct_literal_refs_project_pass: &PassData,
        semantic_artifact_project_pass: &PassData,
    ) -> Result<Self> {
        let step_count = pointer_jump_step_count(hir_capacity);
        let (graph, resources) = build_graph(
            hir_capacity,
            token_capacity,
            call_arg_capacity,
            generic_claim_capacity,
            step_count,
            &conditions_compact_calls_pass.reflection,
            &conditions_compact_types_pass.reflection,
            &conditions_aggregate_args_pass.reflection,
        )
        .map_err(anyhow::Error::msg)?;
        graph
            .validate_complete_pass_reflection(
                graph
                    .pass_id(FEATURES_COLLECT_PASS)
                    .expect("semantic feature collect graph pass"),
                &feature_collect_pass.reflection,
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .validate_complete_pass_reflection(
                graph
                    .pass_id(SEMANTIC_STRUCT_LITERAL_REFS_PROJECT_PASS)
                    .expect("semantic struct-literal reference projection graph pass"),
                &semantic_struct_literal_refs_project_pass.reflection,
            )
            .map_err(anyhow::Error::msg)?;
        for name in [
            CONDITIONS_AGGREGATE_ARGS_CALLS_PASS,
            CONDITIONS_AGGREGATE_ARGS_FINAL_PASS,
        ] {
            graph
                .validate_complete_pass_reflection(
                    graph
                        .pass_id(name)
                        .expect("aggregate argument comparison graph pass"),
                    &conditions_aggregate_args_pass.reflection,
                )
                .map_err(anyhow::Error::msg)?;
        }
        graph
            .validate_complete_pass_reflection(
                graph
                    .pass_id(CONDITIONS_COMPACT_AGGREGATE_REQUESTS_PASS)
                    .expect("compact aggregate request graph pass"),
                &conditions_compact_aggregate_requests_pass.reflection,
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .validate_complete_pass_reflection(
                graph
                    .pass_id(CALLS_BACKEND_TARGETS_PASS)
                    .expect("backend call target graph pass"),
                &calls_backend_targets_pass.reflection,
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .validate_complete_pass_reflection(
                graph
                    .pass_id(SEMANTIC_CALLS_PROJECT_PASS)
                    .expect("semantic call projection graph pass"),
                &semantic_calls_project_pass.reflection,
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .validate_complete_pass_reflection(
                graph
                    .pass_id(SEMANTIC_EXPRESSION_REFS_PROJECT_PASS)
                    .expect("semantic expression-reference projection graph pass"),
                &semantic_expression_refs_project_pass.reflection,
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .validate_complete_pass_reflection(
                graph
                    .pass_id(SEMANTIC_ARTIFACT_PROJECT_PASS)
                    .expect("semantic artifact projection graph pass"),
                &semantic_artifact_project_pass.reflection,
            )
            .map_err(anyhow::Error::msg)?;
        for (name, pass) in [
            (VISIBLE_MARK_PASS, visible_mark_pass),
            (VISIBLE_SCATTER_PASS, visible_scatter_pass),
            (VISIBLE_NAMES_PASS, visible_names_pass),
        ] {
            graph
                .validate_complete_pass_reflection(
                    graph.pass_id(name).expect("visible graph pass"),
                    &pass.reflection,
                )
                .map_err(anyhow::Error::msg)?;
        }
        graph
            .validate_complete_pass_reflection(
                graph.pass_id(SCOPE_HIR_PASS).expect("scope HIR graph pass"),
                &scope_hir_pass.reflection,
            )
            .map_err(anyhow::Error::msg)?;
        for (name, pass) in [
            (RETURNS_CLEAR_PASS, returns_clear_pass),
            (RETURNS_MARK_PASS, returns_mark_pass),
            (RETURNS_MARK_IF_PASS, returns_mark_if_pass),
            (RETURNS_VALIDATE_PASS, returns_validate_pass),
        ] {
            graph
                .validate_complete_pass_reflection(
                    graph.pass_id(name).expect("return graph pass"),
                    &pass.reflection,
                )
                .map_err(anyhow::Error::msg)?;
        }
        graph
            .validate_complete_pass_reflection(
                graph
                    .pass_id(CONDITIONS_COMPACT_CALLS_PASS)
                    .expect("compact call condition graph pass"),
                &conditions_compact_calls_pass.reflection,
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .validate_complete_pass_reflection(
                graph
                    .pass_id(CONDITIONS_COMPACT_TYPES_PASS)
                    .expect("compact type condition graph pass"),
                &conditions_compact_types_pass.reflection,
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .validate_complete_pass_reflection(
                graph
                    .pass_id(CONDITIONS_COMPACT_METHODS_PASS)
                    .expect("compact method condition graph pass"),
                &conditions_compact_methods_pass.reflection,
            )
            .map_err(anyhow::Error::msg)?;
        for (name, pass) in [
            (
                PREDICATE_DIAGNOSTICS_CLEAR_PASS,
                predicate_diagnostics_clear_pass,
            ),
            (
                PREDICATE_DIAGNOSTICS_CLAIM_PASS,
                predicate_diagnostics_claim_pass,
            ),
            (
                PREDICATE_DIAGNOSTICS_PROJECT_PASS,
                predicate_diagnostics_project_pass,
            ),
        ] {
            graph
                .validate_complete_pass_reflection(
                    graph
                        .pass_id(name)
                        .expect("predicate diagnostic graph pass"),
                    &pass.reflection,
                )
                .map_err(anyhow::Error::msg)?;
        }
        graph
            .validate_complete_pass_reflection(
                graph
                    .pass_id(CONDITIONS_COMPACT_PREDICATES_PASS)
                    .expect("compact predicate condition graph pass"),
                &conditions_compact_predicates_pass.reflection,
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .validate_complete_pass_reflection(
                graph
                    .pass_id(CONDITIONS_COMPACT_NAMES_PASS)
                    .expect("compact name condition graph pass"),
                &conditions_compact_names_pass.reflection,
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .validate_complete_pass_reflection(
                graph
                    .pass_id(FEATURES_DISPATCH_PASS)
                    .expect("semantic feature dispatch graph pass"),
                &feature_dispatch_pass.reflection,
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .validate_complete_pass_reflection(
                graph
                    .pass_id(INIT_PASS)
                    .expect("expression init graph pass"),
                &init_pass.reflection,
            )
            .map_err(anyhow::Error::msg)?;
        for name in [STEP_A_TO_B_PASS, STEP_B_TO_A_PASS, STEP_A_TO_B_TAIL_PASS] {
            if let Some(pass) = graph.pass_id(name) {
                graph
                    .validate_complete_pass_reflection(pass, &step_pass.reflection)
                    .map_err(anyhow::Error::msg)?;
            }
        }
        graph
            .validate_complete_pass_reflection(
                graph
                    .pass_id(CONDITIONS_COMPACT_EXPR_PASS)
                    .expect("compact expression condition graph pass"),
                &conditions_compact_expr_pass.reflection,
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .validate_complete_pass_reflection(
                graph
                    .pass_id(CONDITIONS_COMPACT_STMT_PASS)
                    .expect("compact statement condition graph pass"),
                &conditions_compact_stmt_pass.reflection,
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .validate_complete_pass_reflection(
                graph
                    .pass_id(CALL_RESULT_INSTANCE_PROJECT_PASS)
                    .expect("call result-instance projection graph pass"),
                &calls_project_result_instances_pass.reflection,
            )
            .map_err(anyhow::Error::msg)?;

        let workspace = CompilerGraphWorkspace::new(device, "type_check.expression_types", &graph)
            .map_err(anyhow::Error::msg)?;
        let scalar_a = workspace
            .alias(&graph, resources.scalar_a, hir_capacity.max(1) as usize)
            .map_err(anyhow::Error::msg)?;
        let scalar_b = workspace
            .alias(&graph, resources.scalar_b, hir_capacity.max(1) as usize)
            .map_err(anyhow::Error::msg)?;
        let alias_u32 = |resource, count| {
            workspace
                .alias(&graph, resource, count)
                .map_err(anyhow::Error::msg)
        };
        let semantic_feature_flags = alias_u32(resources.semantic_feature_flags, 1)?;
        let method_token_dispatch_args = alias_u32(resources.method_token_dispatch_args, 3)?;
        let method_hir_dispatch_args = alias_u32(resources.method_hir_dispatch_args, 3)?;
        let method_compact_dispatch_args = alias_u32(resources.method_compact_dispatch_args, 3)?;
        let method_token_hir_dispatch_args =
            alias_u32(resources.method_token_hir_dispatch_args, 3)?;
        let method_radix_prefix_dispatch_args =
            alias_u32(resources.method_radix_prefix_dispatch_args, 3)?;
        let method_radix_bases_dispatch_args =
            alias_u32(resources.method_radix_bases_dispatch_args, 3)?;
        let predicate_token_dispatch_args = alias_u32(resources.predicate_token_dispatch_args, 3)?;
        let predicate_hir_dispatch_args = alias_u32(resources.predicate_hir_dispatch_args, 3)?;
        let predicate_radix_prefix_dispatch_args =
            alias_u32(resources.predicate_radix_prefix_dispatch_args, 3)?;
        let predicate_radix_bases_dispatch_args =
            alias_u32(resources.predicate_radix_bases_dispatch_args, 3)?;
        let predicate_single_dispatch_args =
            alias_u32(resources.predicate_single_dispatch_args, 3)?;
        let match_hir_dispatch_args = alias_u32(resources.match_hir_dispatch_args, 3)?;
        let call_has_array_arg =
            alias_u32(resources.call_has_array_arg, hir_capacity.max(1) as usize)?;
        let call_result_instance =
            alias_u32(resources.call_result_instance, hir_capacity.max(1) as usize)?;
        let call_generic_return_arg_node = alias_u32(
            resources.call_generic_return_arg_node,
            hir_capacity.max(1) as usize,
        )?;
        let call_arg_param_row = alias_u32(
            resources.call_arg_param_row,
            call_arg_capacity.max(1) as usize,
        )?;
        let hir_rows = hir_capacity.max(1) as usize;
        let hir_blocks = hir_capacity.max(1).div_ceil(256) as usize;
        let token_rows = token_capacity.max(1) as usize;
        let token_blocks = token_capacity.max(1).div_ceil(256) as usize;
        let call_arg_rows = call_arg_capacity.max(1) as usize;
        let call_arg_blocks = call_arg_capacity.max(1).div_ceil(256) as usize;
        let claim_blocks = generic_claim_capacity.max(1).div_ceil(256) as usize;
        let claim_histogram_rows = claim_blocks * NAME_RADIX_BUCKETS as usize;
        let call_arg_row_scan_local_prefix =
            alias_u32(resources.call_arg_row_scan_local_prefix, hir_rows)?;
        let call_param_row_scan_local_prefix =
            alias_u32(resources.call_param_row_scan_local_prefix, token_rows)?;
        let call_param_row_scan_block_sum =
            alias_u32(resources.call_param_row_scan_block_sum, token_blocks)?;
        let call_param_row_scan_prefix_a =
            alias_u32(resources.call_param_row_scan_prefix_a, token_blocks)?;
        let call_param_row_scan_prefix_b =
            alias_u32(resources.call_param_row_scan_prefix_b, token_blocks)?;
        let call_arg_row_scan_input = alias_u32(resources.call_arg_row_scan_input, hir_rows)?;
        let call_arg_row_prefix = alias_u32(resources.call_arg_row_prefix, hir_rows)?;
        let call_arg_row_count_out = alias_u32(resources.call_arg_row_count_out, 1)?;
        let call_arg_row_scan_block_sum =
            alias_u32(resources.call_arg_row_scan_block_sum, hir_blocks)?;
        let call_arg_row_scan_prefix_a =
            alias_u32(resources.call_arg_row_scan_prefix_a, hir_blocks)?;
        let call_arg_row_scan_prefix_b =
            alias_u32(resources.call_arg_row_scan_prefix_b, hir_blocks)?;
        let generic_claim_scan_local_prefix =
            alias_u32(resources.generic_claim_scan_local_prefix, call_arg_rows)?;
        let generic_claim_scan_input =
            alias_u32(resources.generic_claim_scan_input, call_arg_rows)?;
        let generic_claim_prefix = alias_u32(resources.generic_claim_prefix, call_arg_rows)?;
        let generic_claim_count_out = alias_u32(resources.generic_claim_count_out, 1)?;
        let generic_claim_radix_block_histogram = alias_u32(
            resources.generic_claim_radix_block_histogram,
            claim_histogram_rows,
        )?;
        let generic_claim_radix_block_bucket_prefix = alias_u32(
            resources.generic_claim_radix_block_bucket_prefix,
            claim_histogram_rows,
        )?;
        let generic_claim_radix_bucket_total = alias_u32(
            resources.generic_claim_radix_bucket_total,
            NAME_RADIX_BUCKETS as usize,
        )?;
        let generic_claim_radix_bucket_base = alias_u32(
            resources.generic_claim_radix_bucket_base,
            NAME_RADIX_BUCKETS as usize,
        )?;
        let const_claim_radix_block_histogram = alias_u32(
            resources.const_claim_radix_block_histogram,
            claim_histogram_rows,
        )?;
        let const_claim_radix_block_bucket_prefix = alias_u32(
            resources.const_claim_radix_block_bucket_prefix,
            claim_histogram_rows,
        )?;
        let const_claim_radix_bucket_total = alias_u32(
            resources.const_claim_radix_bucket_total,
            NAME_RADIX_BUCKETS as usize,
        )?;
        let const_claim_radix_bucket_base = alias_u32(
            resources.const_claim_radix_bucket_base,
            NAME_RADIX_BUCKETS as usize,
        )?;
        let generic_claim_scan_block_sum =
            alias_u32(resources.generic_claim_scan_block_sum, call_arg_blocks)?;
        let generic_claim_scan_prefix_a =
            alias_u32(resources.generic_claim_scan_prefix_a, call_arg_blocks)?;
        let generic_claim_scan_prefix_b =
            alias_u32(resources.generic_claim_scan_prefix_b, call_arg_blocks)?;
        let required_generic_scan_input =
            alias_u32(resources.required_generic_scan_input, hir_rows)?;
        let required_generic_prefix = alias_u32(resources.required_generic_prefix, hir_rows)?;
        let required_generic_scan_local_prefix =
            alias_u32(resources.required_generic_scan_local_prefix, hir_rows)?;
        let required_generic_scan_block_sum =
            alias_u32(resources.required_generic_scan_block_sum, hir_blocks)?;
        let required_generic_scan_prefix_a =
            alias_u32(resources.required_generic_scan_prefix_a, hir_blocks)?;
        let required_generic_scan_prefix_b =
            alias_u32(resources.required_generic_scan_prefix_b, hir_blocks)?;
        let required_generic_count_out = alias_u32(resources.required_generic_count_out, 1)?;
        let required_generic_dispatch_args =
            alias_u32(resources.required_generic_dispatch_args, 3)?;
        let semantic_value_decl_by_hir = alias_u32(resources.semantic_value_decl_by_hir, hir_rows)?;
        let semantic_value_type_by_hir = alias_u32(resources.semantic_value_type_by_hir, hir_rows)?;
        let semantic_param_type_by_row = alias_u32(resources.semantic_param_type_by_row, hir_rows)?;
        let semantic_enclosing_fn_by_hir =
            alias_u32(resources.semantic_enclosing_fn_by_hir, hir_rows)?;
        let semantic_calls_by_hir = workspace
            .alias(&graph, resources.semantic_calls_by_hir, hir_rows)
            .map_err(anyhow::Error::msg)?;
        let semantic_expr_ref_tag_by_hir =
            alias_u32(resources.semantic_expr_ref_tag_by_hir, hir_rows)?;
        let semantic_expr_ref_payload_by_hir =
            alias_u32(resources.semantic_expr_ref_payload_by_hir, hir_rows)?;
        let compact_predicate_diagnostic_facts = alias_u32(
            resources.compact_predicate_diagnostic_facts,
            hir_rows.saturating_mul(8),
        )?;
        let return_fn_flags = alias_u32(resources.return_fn_flags, hir_rows)?;
        let return_block_flags = alias_u32(resources.return_block_flags, hir_rows)?;
        let allocations = workspace.allocations();
        let call_array_bindings = [
            BoundGraphResource::buffer(
                "call_has_array_arg",
                resources.call_has_array_arg,
                &call_has_array_arg,
            ),
            BoundGraphResource::buffer(
                "call_result_instance",
                resources.call_result_instance,
                &call_result_instance,
            ),
        ]
        .into_iter()
        .collect::<Result<Vec<_>, _>>()
        .map_err(anyhow::Error::msg)?;
        for pass in [
            CALL_ARRAY_STATE_INIT_PASS,
            CALL_ARRAY_STATE_PUBLISH_PASS,
            CALL_ARRAY_STATE_CONSUME_PASS,
        ] {
            allocations
                .validate_pass_bindings(
                    &graph,
                    graph.pass_id(pass).expect("call-array state graph pass"),
                    &call_array_bindings,
                )
                .map_err(anyhow::Error::msg)?;
        }
        let call_arg_match_binding = [BoundGraphResource::buffer(
            "call_arg_param_row",
            resources.call_arg_param_row,
            &call_arg_param_row,
        )
        .map_err(anyhow::Error::msg)?];
        for pass in [CALL_ARG_MATCH_INIT_PASS, CALL_ARG_MATCH_CONSUME_PASS] {
            allocations
                .validate_pass_bindings(
                    &graph,
                    graph.pass_id(pass).expect("call argument-match graph pass"),
                    &call_arg_match_binding,
                )
                .map_err(anyhow::Error::msg)?;
        }
        let scan_bindings = [
            (
                CALL_PARAM_ROW_SCAN_PASS,
                vec![
                    BoundGraphResource::buffer(
                        "call_param_row_scan_local_prefix",
                        resources.call_param_row_scan_local_prefix,
                        &call_param_row_scan_local_prefix,
                    ),
                    BoundGraphResource::buffer(
                        "call_param_row_scan_block_sum",
                        resources.call_param_row_scan_block_sum,
                        &call_param_row_scan_block_sum,
                    ),
                    BoundGraphResource::buffer(
                        "call_param_row_scan_prefix_a",
                        resources.call_param_row_scan_prefix_a,
                        &call_param_row_scan_prefix_a,
                    ),
                    BoundGraphResource::buffer(
                        "call_param_row_scan_prefix_b",
                        resources.call_param_row_scan_prefix_b,
                        &call_param_row_scan_prefix_b,
                    ),
                ],
            ),
            (
                CALL_ARG_ROW_SCAN_PASS,
                vec![
                    BoundGraphResource::buffer(
                        "call_arg_row_scan_input",
                        resources.call_arg_row_scan_input,
                        &call_arg_row_scan_input,
                    ),
                    BoundGraphResource::buffer(
                        "call_arg_row_prefix",
                        resources.call_arg_row_prefix,
                        &call_arg_row_prefix,
                    ),
                    BoundGraphResource::buffer(
                        "call_arg_row_count_out",
                        resources.call_arg_row_count_out,
                        &call_arg_row_count_out,
                    ),
                    BoundGraphResource::buffer(
                        "call_arg_row_scan_local_prefix",
                        resources.call_arg_row_scan_local_prefix,
                        &call_arg_row_scan_local_prefix,
                    ),
                    BoundGraphResource::buffer(
                        "call_arg_row_scan_block_sum",
                        resources.call_arg_row_scan_block_sum,
                        &call_arg_row_scan_block_sum,
                    ),
                    BoundGraphResource::buffer(
                        "call_arg_row_scan_prefix_a",
                        resources.call_arg_row_scan_prefix_a,
                        &call_arg_row_scan_prefix_a,
                    ),
                    BoundGraphResource::buffer(
                        "call_arg_row_scan_prefix_b",
                        resources.call_arg_row_scan_prefix_b,
                        &call_arg_row_scan_prefix_b,
                    ),
                ],
            ),
            (
                GENERIC_CLAIM_SCAN_PASS,
                vec![
                    BoundGraphResource::buffer(
                        "call_generic_claim_scan_input",
                        resources.generic_claim_scan_input,
                        &generic_claim_scan_input,
                    ),
                    BoundGraphResource::buffer(
                        "call_generic_claim_prefix",
                        resources.generic_claim_prefix,
                        &generic_claim_prefix,
                    ),
                    BoundGraphResource::buffer(
                        "call_generic_claim_count_out",
                        resources.generic_claim_count_out,
                        &generic_claim_count_out,
                    ),
                    BoundGraphResource::buffer(
                        "call_generic_claim_scan_local_prefix",
                        resources.generic_claim_scan_local_prefix,
                        &generic_claim_scan_local_prefix,
                    ),
                    BoundGraphResource::buffer(
                        "call_generic_claim_scan_block_sum",
                        resources.generic_claim_scan_block_sum,
                        &generic_claim_scan_block_sum,
                    ),
                    BoundGraphResource::buffer(
                        "call_generic_claim_scan_prefix_a",
                        resources.generic_claim_scan_prefix_a,
                        &generic_claim_scan_prefix_a,
                    ),
                    BoundGraphResource::buffer(
                        "call_generic_claim_scan_prefix_b",
                        resources.generic_claim_scan_prefix_b,
                        &generic_claim_scan_prefix_b,
                    ),
                ],
            ),
        ];
        for (pass, bindings) in scan_bindings {
            let bindings = bindings
                .into_iter()
                .collect::<Result<Vec<_>, _>>()
                .map_err(anyhow::Error::msg)?;
            allocations
                .validate_pass_bindings(
                    &graph,
                    graph.pass_id(pass).expect("call scan graph pass"),
                    &bindings,
                )
                .map_err(anyhow::Error::msg)?;
        }
        let relation_bindings = [
            BoundGraphResource::buffer(
                "call_arg_param_row",
                resources.call_arg_param_row,
                &call_arg_param_row,
            ),
            BoundGraphResource::buffer(
                "call_arg_row_scan_input",
                resources.call_arg_row_scan_input,
                &call_arg_row_scan_input,
            ),
            BoundGraphResource::buffer(
                "call_arg_row_prefix",
                resources.call_arg_row_prefix,
                &call_arg_row_prefix,
            ),
            BoundGraphResource::buffer(
                "call_arg_row_count_out",
                resources.call_arg_row_count_out,
                &call_arg_row_count_out,
            ),
            BoundGraphResource::buffer(
                "call_generic_claim_scan_input",
                resources.generic_claim_scan_input,
                &generic_claim_scan_input,
            ),
            BoundGraphResource::buffer(
                "call_generic_claim_prefix",
                resources.generic_claim_prefix,
                &generic_claim_prefix,
            ),
            BoundGraphResource::buffer(
                "call_generic_claim_count_out",
                resources.generic_claim_count_out,
                &generic_claim_count_out,
            ),
            BoundGraphResource::buffer(
                "call_generic_return_arg_node",
                resources.call_generic_return_arg_node,
                &call_generic_return_arg_node,
            ),
            BoundGraphResource::buffer(
                "call_result_instance",
                resources.call_result_instance,
                &call_result_instance,
            ),
        ]
        .into_iter()
        .collect::<Result<Vec<_>, _>>()
        .map_err(anyhow::Error::msg)?;
        for pass in [
            CALL_ARG_ROW_MARK_PASS,
            CALL_ARG_ROW_SCATTER_PASS,
            GENERIC_CLAIM_COLLECT_PASS,
            GENERIC_CLAIM_EMIT_PASS,
        ] {
            let pass_id = graph.pass_id(pass).expect("call relation graph pass");
            let declared = graph
                .pass(pass_id)
                .expect("call relation pass descriptor")
                .accesses
                .iter()
                .map(|access| access.resource)
                .collect::<Vec<_>>();
            let bindings = relation_bindings
                .iter()
                .filter(|binding| declared.contains(&binding.resource))
                .cloned()
                .collect::<Vec<_>>();
            allocations
                .validate_pass_bindings(&graph, pass_id, &bindings)
                .map_err(anyhow::Error::msg)?;
        }
        let required_bindings = [
            BoundGraphResource::buffer(
                "call_required_generic_scan_input",
                resources.required_generic_scan_input,
                &required_generic_scan_input,
            ),
            BoundGraphResource::buffer(
                "call_required_generic_prefix",
                resources.required_generic_prefix,
                &required_generic_prefix,
            ),
            BoundGraphResource::buffer(
                "call_required_generic_scan_local_prefix",
                resources.required_generic_scan_local_prefix,
                &required_generic_scan_local_prefix,
            ),
            BoundGraphResource::buffer(
                "call_required_generic_scan_block_sum",
                resources.required_generic_scan_block_sum,
                &required_generic_scan_block_sum,
            ),
            BoundGraphResource::buffer(
                "call_required_generic_scan_prefix_a",
                resources.required_generic_scan_prefix_a,
                &required_generic_scan_prefix_a,
            ),
            BoundGraphResource::buffer(
                "call_required_generic_scan_prefix_b",
                resources.required_generic_scan_prefix_b,
                &required_generic_scan_prefix_b,
            ),
            BoundGraphResource::buffer(
                "call_required_generic_count_out",
                resources.required_generic_count_out,
                &required_generic_count_out,
            ),
            BoundGraphResource::buffer(
                "call_required_generic_dispatch_args",
                resources.required_generic_dispatch_args,
                &required_generic_dispatch_args,
            ),
        ]
        .into_iter()
        .collect::<Result<Vec<_>, _>>()
        .map_err(anyhow::Error::msg)?;
        for pass in [
            REQUIRED_GENERIC_MARK_PASS,
            REQUIRED_GENERIC_SCAN_PASS,
            REQUIRED_GENERIC_DISPATCH_PASS,
            REQUIRED_GENERIC_VALIDATE_PASS,
        ] {
            let pass_id = graph.pass_id(pass).expect("required-generic graph pass");
            let declared = graph
                .pass(pass_id)
                .expect("required-generic pass descriptor")
                .accesses
                .iter()
                .map(|access| access.resource)
                .collect::<Vec<_>>();
            let bindings = required_bindings
                .iter()
                .filter(|binding| declared.contains(&binding.resource))
                .cloned()
                .collect::<Vec<_>>();
            allocations
                .validate_pass_bindings(&graph, pass_id, &bindings)
                .map_err(anyhow::Error::msg)?;
        }
        let radix_bindings = [
            (
                GENERIC_CLAIM_SORT_PASS,
                vec![
                    BoundGraphResource::buffer(
                        "call_generic_claim_radix_block_histogram",
                        resources.generic_claim_radix_block_histogram,
                        &generic_claim_radix_block_histogram,
                    ),
                    BoundGraphResource::buffer(
                        "call_generic_claim_radix_block_bucket_prefix",
                        resources.generic_claim_radix_block_bucket_prefix,
                        &generic_claim_radix_block_bucket_prefix,
                    ),
                    BoundGraphResource::buffer(
                        "call_generic_claim_radix_bucket_total",
                        resources.generic_claim_radix_bucket_total,
                        &generic_claim_radix_bucket_total,
                    ),
                    BoundGraphResource::buffer(
                        "call_generic_claim_radix_bucket_base",
                        resources.generic_claim_radix_bucket_base,
                        &generic_claim_radix_bucket_base,
                    ),
                ],
            ),
            (
                CONST_CLAIM_SORT_PASS,
                vec![
                    BoundGraphResource::buffer(
                        "call_const_claim_radix_block_histogram",
                        resources.const_claim_radix_block_histogram,
                        &const_claim_radix_block_histogram,
                    ),
                    BoundGraphResource::buffer(
                        "call_const_claim_radix_block_bucket_prefix",
                        resources.const_claim_radix_block_bucket_prefix,
                        &const_claim_radix_block_bucket_prefix,
                    ),
                    BoundGraphResource::buffer(
                        "call_const_claim_radix_bucket_total",
                        resources.const_claim_radix_bucket_total,
                        &const_claim_radix_bucket_total,
                    ),
                    BoundGraphResource::buffer(
                        "call_const_claim_radix_bucket_base",
                        resources.const_claim_radix_bucket_base,
                        &const_claim_radix_bucket_base,
                    ),
                ],
            ),
        ];
        for (pass, bindings) in radix_bindings {
            let bindings = bindings
                .into_iter()
                .collect::<Result<Vec<_>, _>>()
                .map_err(anyhow::Error::msg)?;
            allocations
                .validate_pass_bindings(
                    &graph,
                    graph.pass_id(pass).expect("claim radix graph pass"),
                    &bindings,
                )
                .map_err(anyhow::Error::msg)?;
        }
        Ok(Self {
            graph,
            _workspace: workspace,
            allocations,
            scalar_a,
            scalar_b,
            semantic_feature_flags,
            method_token_dispatch_args,
            method_hir_dispatch_args,
            method_compact_dispatch_args,
            method_token_hir_dispatch_args,
            method_radix_prefix_dispatch_args,
            method_radix_bases_dispatch_args,
            predicate_token_dispatch_args,
            predicate_hir_dispatch_args,
            predicate_radix_prefix_dispatch_args,
            predicate_radix_bases_dispatch_args,
            predicate_single_dispatch_args,
            match_hir_dispatch_args,
            call_has_array_arg,
            call_result_instance,
            call_generic_return_arg_node,
            call_arg_param_row,
            call_param_row_scan_local_prefix,
            call_param_row_scan_block_sum,
            call_param_row_scan_prefix_a,
            call_param_row_scan_prefix_b,
            call_arg_row_scan_input,
            call_arg_row_prefix,
            call_arg_row_count_out,
            call_arg_row_scan_local_prefix,
            call_arg_row_scan_block_sum,
            call_arg_row_scan_prefix_a,
            call_arg_row_scan_prefix_b,
            generic_claim_scan_local_prefix,
            generic_claim_scan_block_sum,
            generic_claim_scan_prefix_a,
            generic_claim_scan_prefix_b,
            generic_claim_scan_input,
            generic_claim_prefix,
            generic_claim_count_out,
            generic_claim_radix_block_histogram,
            generic_claim_radix_block_bucket_prefix,
            generic_claim_radix_bucket_total,
            generic_claim_radix_bucket_base,
            const_claim_radix_block_histogram,
            const_claim_radix_block_bucket_prefix,
            const_claim_radix_bucket_total,
            const_claim_radix_bucket_base,
            required_generic_scan_input,
            required_generic_prefix,
            required_generic_scan_local_prefix,
            required_generic_scan_block_sum,
            required_generic_scan_prefix_a,
            required_generic_scan_prefix_b,
            required_generic_count_out,
            required_generic_dispatch_args,
            semantic_value_decl_by_hir,
            semantic_value_type_by_hir,
            semantic_param_type_by_row,
            semantic_enclosing_fn_by_hir,
            semantic_calls_by_hir,
            semantic_expr_ref_tag_by_hir,
            semantic_expr_ref_payload_by_hir,
            compact_predicate_diagnostic_facts,
            return_fn_flags,
            return_block_flags,
            step_count,
        })
    }

    pub(super) fn step_count(&self) -> usize {
        self.step_count
    }

    pub(super) fn step_pass_name(&self, step: usize) -> &'static str {
        assert!(step < self.step_count, "expression type step is in range");
        if step % 2 == 0 {
            if step + 1 == self.step_count && self.step_count % 2 == 1 {
                STEP_A_TO_B_TAIL_PASS
            } else {
                STEP_A_TO_B_PASS
            }
        } else {
            STEP_B_TO_A_PASS
        }
    }
}

fn pointer_jump_step_count(hir_capacity: u32) -> usize {
    ((u32::BITS - hir_capacity.max(1).saturating_sub(1).leading_zeros()) as usize).max(1)
}

fn build_graph(
    hir_capacity: u32,
    token_capacity: u32,
    call_arg_capacity: u32,
    generic_claim_capacity: u32,
    step_count: usize,
    conditions_compact_calls_reflection: &crate::reflection::SlangReflection,
    conditions_compact_types_reflection: &crate::reflection::SlangReflection,
    conditions_aggregate_args_reflection: &crate::reflection::SlangReflection,
) -> Result<(CompilerGraph, ExpressionTypeResources), String> {
    let hir_rows = u64::from(hir_capacity.max(1));
    let token_rows = u64::from(token_capacity.max(1));
    let call_arg_rows = u64::from(call_arg_capacity.max(1));
    let hir_blocks = hir_rows.div_ceil(256);
    let call_arg_blocks = call_arg_rows.div_ceil(256);
    let claim_blocks = u64::from(generic_claim_capacity.max(1)).div_ceil(256);
    let claim_histogram_rows = claim_blocks * u64::from(NAME_RADIX_BUCKETS);
    let mut graph = CompilerGraphBuilder::new();
    let mut input = |name, domain, bytes| {
        graph.add_resource(ResourceDesc {
            name,
            domain,
            class: ResourceClass::Input,
            bytes,
            usage: WorkspaceUsageClass::Storage,
        })
    };
    let compact_hir_count = input("compact_hir_count", ResourceDomain::HirNodes, 4)?;
    let compact_hir_core = input("compact_hir_core", ResourceDomain::HirNodes, hir_rows * 16)?;
    let compact_hir_links = input("compact_hir_links", ResourceDomain::HirNodes, hir_rows * 16)?;
    let compact_hir_payload = input(
        "compact_hir_payload",
        ResourceDomain::HirNodes,
        hir_rows * 16,
    )?;
    let compact_param_count = input("compact_param_count", ResourceDomain::Declarations, 4)?;
    let compact_params = input(
        "compact_params",
        ResourceDomain::Declarations,
        hir_rows * 16,
    )?;
    let compact_hir_expr_parent = input(
        "compact_hir_expr_parent",
        ResourceDomain::HirNodes,
        hir_rows * 4,
    )?;
    let compact_hir_nearest_loop = input(
        "compact_hir_nearest_loop",
        ResourceDomain::HirNodes,
        hir_rows * 4,
    )?;
    let compact_hir_nearest_block = input(
        "compact_hir_nearest_block",
        ResourceDomain::HirNodes,
        hir_rows * 4,
    )?;
    let compact_hir_nearest_control = input(
        "compact_hir_nearest_control",
        ResourceDomain::HirNodes,
        hir_rows * 4,
    )?;
    let compact_hir_nearest_fn = input(
        "compact_hir_nearest_fn",
        ResourceDomain::HirNodes,
        hir_rows * 4,
    )?;
    let compact_path_count = input("compact_path_count", ResourceDomain::HirNodes, 4)?;
    let compact_paths = input("compact_paths", ResourceDomain::HirNodes, hir_rows * 16)?;
    let compact_path_segment_count =
        input("compact_path_segment_count", ResourceDomain::Tokens, 4)?;
    let compact_path_segments = input(
        "compact_path_segments",
        ResourceDomain::Tokens,
        token_rows * 16,
    )?;
    let path_id_by_owner_hir = input(
        "path_id_by_owner_hir",
        ResourceDomain::HirNodes,
        hir_rows * 4,
    )?;
    let call_return_type = input("call_return_type", ResourceDomain::Tokens, token_rows * 4)?;
    let call_return_type_token = input(
        "call_return_type_token",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let enclosing_fn = input("enclosing_fn", ResourceDomain::Tokens, token_rows * 4)?;
    let decl_type_ref_tag = input("decl_type_ref_tag", ResourceDomain::Tokens, token_rows * 4)?;
    let decl_type_ref_payload = input(
        "decl_type_ref_payload",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let fn_return_ref_tag = input("fn_return_ref_tag", ResourceDomain::Tokens, token_rows * 4)?;
    let fn_return_ref_payload = input(
        "fn_return_ref_payload",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let call_fn_index = input("call_fn_index", ResourceDomain::Tokens, token_rows * 4)?;
    let call_dependency_decl = input(
        "call_dependency_decl",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let type_instance_kind = input("type_instance_kind", ResourceDomain::Tokens, token_rows * 4)?;
    let type_instance_decl_token = input(
        "type_instance_decl_token",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let type_instance_external_canonical = input(
        "type_instance_external_canonical",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let type_instance_arg_count = input(
        "type_instance_arg_count",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let type_instance_elem_ref_tag = input(
        "type_instance_elem_ref_tag",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let type_instance_elem_ref_payload = input(
        "type_instance_elem_ref_payload",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let call_intrinsic_tag = input("call_intrinsic_tag", ResourceDomain::Tokens, token_rows * 4)?;
    let method_call_name_id = input(
        "method_call_name_id",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let module_value_path_status = input(
        "module_value_path_status",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let module_type_path_status = input(
        "module_type_path_status",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let module_value_path_call_leaf = input(
        "module_value_path_call_leaf",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let module_value_path_associated_method_token = input(
        "module_value_path_associated_method_token",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let token_count = input("token_count", ResourceDomain::Tokens, 4)?;
    let hir_active_count = input("hir_active_count", ResourceDomain::HirNodes, 4)?;
    let compact_method_count = input("compact_method_count", ResourceDomain::Declarations, 4)?;
    let compact_method_cores = input(
        "compact_method_cores",
        ResourceDomain::Declarations,
        hir_rows * 16,
    )?;
    let compact_method_signatures = input(
        "compact_method_signatures",
        ResourceDomain::Declarations,
        hir_rows * 16,
    )?;
    let token_words = input("token_words", ResourceDomain::Tokens, token_rows * 12)?;
    let predicate_syntax_token = input(
        "predicate_syntax_token",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let type_expr_ref_tag = input("type_expr_ref_tag", ResourceDomain::Tokens, token_rows * 4)?;
    let type_expr_ref_payload = input(
        "type_expr_ref_payload",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let member_result_ref_tag = input(
        "member_result_ref_tag",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let member_result_ref_payload = input(
        "member_result_ref_payload",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let struct_lit_context_instance = input(
        "struct_lit_context_instance",
        ResourceDomain::HirNodes,
        hir_rows * 4,
    )?;
    let struct_lit_context_decl_token = input(
        "struct_lit_context_decl_token",
        ResourceDomain::HirNodes,
        hir_rows * 4,
    )?;
    let type_generic_param_slot_by_token = input(
        "type_generic_param_slot_by_token",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let type_const_param_slot_by_token = input(
        "type_const_param_slot_by_token",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let type_instance_len_kind = input(
        "type_instance_len_kind",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let type_instance_len_payload = input(
        "type_instance_len_payload",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let compact_hir_scope_end = input(
        "compact_hir_scope_end",
        ResourceDomain::HirNodes,
        hir_rows * 4,
    )?;
    let name_id_by_token = input("name_id_by_token", ResourceDomain::Tokens, token_rows * 4)?;
    let compact_predicate_count =
        input("compact_predicate_count", ResourceDomain::Declarations, 4)?;
    let compact_predicates = input(
        "compact_predicates",
        ResourceDomain::Declarations,
        hir_rows * 16,
    )?;
    let hir_status = input("hir_status", ResourceDomain::HirNodes, 24)?;
    let hir_token_pos = input("hir_token_pos", ResourceDomain::HirNodes, hir_rows * 4)?;
    let raw_to_compact_hir = input("raw_to_compact_hir", ResourceDomain::HirNodes, hir_rows * 4)?;
    // Predicate scratch is feature-sized and may be a one-row sentinel when
    // the source contains no predicates. Reflection validates the binding;
    // the projection shader guards full-row reads with parser feature flags.
    let predicate_bound_first_arg_token = input(
        "predicate_bound_first_arg_token",
        ResourceDomain::HirNodes,
        4,
    )?;
    let predicate_bound_second_arg_token = input(
        "predicate_bound_second_arg_token",
        ResourceDomain::HirNodes,
        4,
    )?;
    let predicate_status = input("predicate_status", ResourceDomain::HirNodes, 4)?;
    let predicate_method_contract_status = input(
        "predicate_method_contract_status",
        ResourceDomain::HirNodes,
        4,
    )?;
    let predicate_method_validation_first_error_row = input(
        "predicate_method_validation_first_error_row",
        ResourceDomain::HirNodes,
        4,
    )?;
    let predicate_method_validation_status = input(
        "predicate_method_validation_status",
        ResourceDomain::HirNodes,
        4,
    )?;
    let predicate_method_validation_detail_token = input(
        "predicate_method_validation_detail_token",
        ResourceDomain::HirNodes,
        4,
    )?;
    let fn_start_token_by_decl_token = input(
        "fn_start_token_by_decl_token",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let call_param_row_count_out =
        input("call_param_row_count_out", ResourceDomain::CallArguments, 4)?;
    let visible_type = graph.add_resource(ResourceDesc {
        name: "visible_type",
        domain: ResourceDomain::Tokens,
        class: ResourceClass::External,
        bytes: token_rows * 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let visible_decl = graph.add_resource(ResourceDesc {
        name: "visible_decl",
        domain: ResourceDomain::Tokens,
        class: ResourceClass::External,
        bytes: token_rows * 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let mut boundary_input = |name, domain, bytes| {
        graph.add_resource(ResourceDesc {
            name,
            domain,
            class: ResourceClass::Input,
            bytes,
            usage: WorkspaceUsageClass::Storage,
        })
    };
    let type_instance_arg_row_start = boundary_input(
        "type_instance_arg_row_start",
        ResourceDomain::Types,
        token_rows * 4,
    )?;
    let type_instance_arg_row_count_out =
        boundary_input("type_instance_arg_row_count_out", ResourceDomain::Types, 4)?;
    let type_instance_arg_row_ref_tag = boundary_input(
        "type_instance_arg_row_ref_tag",
        ResourceDomain::Types,
        token_rows * 4,
    )?;
    let type_instance_arg_row_ref_payload = boundary_input(
        "type_instance_arg_row_ref_payload",
        ResourceDomain::Types,
        token_rows * 4,
    )?;
    let type_instance_arg_ref_tag = boundary_input(
        "type_instance_arg_ref_tag",
        ResourceDomain::Types,
        token_rows * 16,
    )?;
    let type_instance_arg_ref_payload = boundary_input(
        "type_instance_arg_ref_payload",
        ResourceDomain::Types,
        token_rows * 16,
    )?;
    let mut external = |name, domain, bytes| {
        graph.add_resource(ResourceDesc {
            name,
            domain,
            class: ResourceClass::External,
            bytes,
            usage: WorkspaceUsageClass::Storage,
        })
    };
    let backend_call_fn_index = external(
        "backend_call_fn_index",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let call_param_row_fn_token = external(
        "call_param_row_fn_token",
        ResourceDomain::CallArguments,
        token_rows * 4,
    )?;
    let call_param_row_start = external(
        "call_param_row_start",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let call_param_row_count = external(
        "call_param_row_count",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let call_param_count = external("call_param_count", ResourceDomain::Tokens, token_rows * 4)?;
    let method_decl_param_offset = external(
        "method_decl_param_offset",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let method_decl_receiver_mode = external(
        "method_decl_receiver_mode",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let hir_value_decl_name_present = external(
        "hir_value_decl_name_present",
        ResourceDomain::Declarations,
        (token_rows + u64::from(LANGUAGE_SYMBOL_COUNT)) * 4,
    )?;
    let hir_visible_decl_flag = external(
        "hir_visible_decl_flag",
        ResourceDomain::HirNodes,
        hir_rows * 4,
    )?;
    let hir_visible_decl_prefix = external(
        "hir_visible_decl_prefix",
        ResourceDomain::HirNodes,
        hir_rows * 4,
    )?;
    let hir_visible_decl_scan_local_prefix = external(
        "hir_visible_decl_scan_local_prefix",
        ResourceDomain::HirNodes,
        hir_rows * 4,
    )?;
    let hir_visible_decl_scan_block_sum = external(
        "hir_visible_decl_scan_block_sum",
        ResourceDomain::HirNodes,
        hir_blocks * 4,
    )?;
    let hir_visible_decl_scan_prefix_a = external(
        "hir_visible_decl_scan_prefix_a",
        ResourceDomain::HirNodes,
        hir_blocks * 4,
    )?;
    let hir_visible_decl_scan_prefix_b = external(
        "hir_visible_decl_scan_prefix_b",
        ResourceDomain::HirNodes,
        hir_blocks * 4,
    )?;
    let hir_visible_decl_count_out = external(
        "hir_visible_decl_count_out",
        ResourceDomain::Declarations,
        4,
    )?;
    let hir_visible_decl_owner_fn = external(
        "hir_visible_decl_owner_fn",
        ResourceDomain::Declarations,
        token_rows * 4,
    )?;
    let hir_visible_decl_name_id = external(
        "hir_visible_decl_name_id",
        ResourceDomain::Declarations,
        token_rows * 4,
    )?;
    let hir_visible_decl_token = external(
        "hir_visible_decl_token",
        ResourceDomain::Declarations,
        token_rows * 4,
    )?;
    let hir_visible_decl_scope_end = external(
        "hir_visible_decl_scope_end",
        ResourceDomain::Declarations,
        token_rows * 4,
    )?;
    let hir_visible_decl_node = external(
        "hir_visible_decl_node",
        ResourceDomain::Declarations,
        token_rows * 4,
    )?;
    let hir_visible_decl_key_order = external(
        "hir_visible_decl_key_order",
        ResourceDomain::Declarations,
        token_rows * 4,
    )?;
    let hir_visible_decl_key_order_tmp = external(
        "hir_visible_decl_key_order_tmp",
        ResourceDomain::Declarations,
        token_rows * 4,
    )?;
    let hir_visible_decl_key_radix_dispatch_args = external(
        "hir_visible_decl_key_radix_dispatch_args",
        ResourceDomain::DispatchArguments,
        12,
    )?;
    let visible_radix_rows = token_rows.div_ceil(256) * u64::from(NAME_RADIX_BUCKETS);
    let hir_visible_decl_key_radix_block_histogram = external(
        "hir_visible_decl_key_radix_block_histogram",
        ResourceDomain::Declarations,
        visible_radix_rows * 4,
    )?;
    let hir_visible_decl_key_radix_block_bucket_prefix = external(
        "hir_visible_decl_key_radix_block_bucket_prefix",
        ResourceDomain::Declarations,
        visible_radix_rows * 4,
    )?;
    let hir_visible_decl_key_radix_bucket_total = external(
        "hir_visible_decl_key_radix_bucket_total",
        ResourceDomain::Declarations,
        u64::from(NAME_RADIX_BUCKETS) * 4,
    )?;
    let hir_visible_decl_key_radix_bucket_base = external(
        "hir_visible_decl_key_radix_bucket_base",
        ResourceDomain::Declarations,
        u64::from(NAME_RADIX_BUCKETS) * 4,
    )?;
    let visible_tree_leaves = token_capacity
        .max(1)
        .div_ceil(HIR_VISIBLE_DECL_ROW_BLOCK_SIZE)
        .max(1);
    let visible_tree_rows = visible_tree_leaves
        .next_power_of_two()
        .saturating_mul(2)
        .max(2);
    let hir_visible_decl_scope_tree = external(
        "hir_visible_decl_scope_tree",
        ResourceDomain::Declarations,
        u64::from(visible_tree_rows) * 4,
    )?;
    let semantic_feature_flags = graph.add_resource(ResourceDesc {
        name: "semantic_feature_flags",
        domain: ResourceDomain::HirNodes,
        class: ResourceClass::Workspace,
        bytes: 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let mut indirect_output = |name| {
        graph.add_resource(ResourceDesc {
            name,
            domain: ResourceDomain::DispatchArguments,
            class: ResourceClass::Output,
            bytes: 12,
            usage: WorkspaceUsageClass::StorageIndirect,
        })
    };
    let method_token_dispatch_args = indirect_output("method_token_dispatch_args")?;
    let method_hir_dispatch_args = indirect_output("method_hir_dispatch_args")?;
    let method_compact_dispatch_args = indirect_output("method_compact_dispatch_args")?;
    let method_token_hir_dispatch_args = indirect_output("method_token_hir_dispatch_args")?;
    let method_radix_prefix_dispatch_args = indirect_output("method_radix_prefix_dispatch_args")?;
    let method_radix_bases_dispatch_args = indirect_output("method_radix_bases_dispatch_args")?;
    let predicate_token_dispatch_args = indirect_output("predicate_token_dispatch_args")?;
    let predicate_hir_dispatch_args = indirect_output("predicate_hir_dispatch_args")?;
    let predicate_radix_prefix_dispatch_args =
        indirect_output("predicate_radix_prefix_dispatch_args")?;
    let predicate_radix_bases_dispatch_args =
        indirect_output("predicate_radix_bases_dispatch_args")?;
    let predicate_single_dispatch_args = indirect_output("predicate_single_dispatch_args")?;
    let match_hir_dispatch_args = indirect_output("match_hir_dispatch_args")?;
    let scalar_a = graph.add_resource(ResourceDesc {
        name: "compact_expr_scalar_type.a",
        domain: ResourceDomain::HirNodes,
        class: ResourceClass::Output,
        bytes: hir_rows * 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let scalar_b = graph.add_resource(ResourceDesc {
        name: "compact_expr_scalar_type.b",
        domain: ResourceDomain::HirNodes,
        class: ResourceClass::Output,
        bytes: hir_rows * 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let status = graph.add_resource(ResourceDesc {
        name: "status",
        domain: ResourceDomain::Bytes,
        class: ResourceClass::External,
        bytes: 16,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let return_fn_flags = graph.add_resource(ResourceDesc {
        name: "return_fn_flags",
        domain: ResourceDomain::HirNodes,
        class: ResourceClass::Workspace,
        bytes: hir_rows * 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let return_block_flags = graph.add_resource(ResourceDesc {
        name: "return_block_flags",
        domain: ResourceDomain::HirNodes,
        class: ResourceClass::Workspace,
        bytes: hir_rows * 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let call_has_array_arg = graph.add_resource(ResourceDesc {
        name: "call_has_array_arg",
        domain: ResourceDomain::Calls,
        class: ResourceClass::Output,
        bytes: hir_rows * 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let call_result_instance = graph.add_resource(ResourceDesc {
        name: "call_result_instance",
        domain: ResourceDomain::Calls,
        class: ResourceClass::Output,
        bytes: hir_rows * 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let call_generic_return_arg_node = graph.add_resource(ResourceDesc {
        name: "call_generic_return_arg_node",
        domain: ResourceDomain::Calls,
        class: ResourceClass::Output,
        bytes: hir_rows * 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let call_arg_param_row = graph.add_resource(ResourceDesc {
        name: "call_arg_param_row",
        domain: ResourceDomain::CallArguments,
        class: ResourceClass::Workspace,
        bytes: call_arg_rows * 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let mut required_workspace = |name, domain, bytes, usage| {
        graph.add_resource(ResourceDesc {
            name,
            domain,
            class: ResourceClass::Workspace,
            bytes,
            usage,
        })
    };
    let call_arg_row_scan_local_prefix = required_workspace(
        "call_arg_row_scan_local_prefix",
        ResourceDomain::HirNodes,
        hir_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let call_param_row_scan_local_prefix = required_workspace(
        "call_param_row_scan_local_prefix",
        ResourceDomain::Tokens,
        token_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let call_param_row_scan_block_sum = required_workspace(
        "call_param_row_scan_block_sum",
        ResourceDomain::Tokens,
        token_rows.div_ceil(256) * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let call_param_row_scan_prefix_a = required_workspace(
        "call_param_row_scan_prefix_a",
        ResourceDomain::Tokens,
        token_rows.div_ceil(256) * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let call_param_row_scan_prefix_b = required_workspace(
        "call_param_row_scan_prefix_b",
        ResourceDomain::Tokens,
        token_rows.div_ceil(256) * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let call_arg_row_scan_input = required_workspace(
        "call_arg_row_scan_input",
        ResourceDomain::HirNodes,
        hir_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let call_arg_row_prefix = required_workspace(
        "call_arg_row_prefix",
        ResourceDomain::HirNodes,
        hir_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let call_arg_row_scan_block_sum = required_workspace(
        "call_arg_row_scan_block_sum",
        ResourceDomain::HirNodes,
        hir_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let call_arg_row_scan_prefix_a = required_workspace(
        "call_arg_row_scan_prefix_a",
        ResourceDomain::HirNodes,
        hir_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let call_arg_row_scan_prefix_b = required_workspace(
        "call_arg_row_scan_prefix_b",
        ResourceDomain::HirNodes,
        hir_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let generic_claim_scan_local_prefix = required_workspace(
        "call_generic_claim_scan_local_prefix",
        ResourceDomain::CallArguments,
        call_arg_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let generic_claim_scan_input = required_workspace(
        "call_generic_claim_scan_input",
        ResourceDomain::CallArguments,
        call_arg_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let generic_claim_prefix = required_workspace(
        "call_generic_claim_prefix",
        ResourceDomain::CallArguments,
        call_arg_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let generic_claim_scan_block_sum = required_workspace(
        "call_generic_claim_scan_block_sum",
        ResourceDomain::CallArguments,
        call_arg_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let generic_claim_scan_prefix_a = required_workspace(
        "call_generic_claim_scan_prefix_a",
        ResourceDomain::CallArguments,
        call_arg_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let generic_claim_scan_prefix_b = required_workspace(
        "call_generic_claim_scan_prefix_b",
        ResourceDomain::CallArguments,
        call_arg_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let required_generic_scan_input = required_workspace(
        "call_required_generic_scan_input",
        ResourceDomain::HirNodes,
        hir_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let required_generic_prefix = required_workspace(
        "call_required_generic_prefix",
        ResourceDomain::HirNodes,
        hir_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let required_generic_scan_local_prefix = required_workspace(
        "call_required_generic_scan_local_prefix",
        ResourceDomain::HirNodes,
        hir_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let required_generic_scan_block_sum = required_workspace(
        "call_required_generic_scan_block_sum",
        ResourceDomain::HirNodes,
        hir_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let required_generic_scan_prefix_a = required_workspace(
        "call_required_generic_scan_prefix_a",
        ResourceDomain::HirNodes,
        hir_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let required_generic_scan_prefix_b = required_workspace(
        "call_required_generic_scan_prefix_b",
        ResourceDomain::HirNodes,
        hir_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let required_generic_count_out = required_workspace(
        "call_required_generic_count_out",
        ResourceDomain::CallArguments,
        4,
        WorkspaceUsageClass::Storage,
    )?;
    let required_generic_dispatch_args = required_workspace(
        "call_required_generic_dispatch_args",
        ResourceDomain::DispatchArguments,
        12,
        WorkspaceUsageClass::StorageIndirect,
    )?;
    let generic_claim_radix_block_histogram = required_workspace(
        "call_generic_claim_radix_block_histogram",
        ResourceDomain::CallArguments,
        claim_histogram_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let generic_claim_radix_block_bucket_prefix = required_workspace(
        "call_generic_claim_radix_block_bucket_prefix",
        ResourceDomain::CallArguments,
        claim_histogram_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let generic_claim_radix_bucket_total = required_workspace(
        "call_generic_claim_radix_bucket_total",
        ResourceDomain::CallArguments,
        u64::from(NAME_RADIX_BUCKETS) * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let generic_claim_radix_bucket_base = required_workspace(
        "call_generic_claim_radix_bucket_base",
        ResourceDomain::CallArguments,
        u64::from(NAME_RADIX_BUCKETS) * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let const_claim_radix_block_histogram = required_workspace(
        "call_const_claim_radix_block_histogram",
        ResourceDomain::CallArguments,
        claim_histogram_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let const_claim_radix_block_bucket_prefix = required_workspace(
        "call_const_claim_radix_block_bucket_prefix",
        ResourceDomain::CallArguments,
        claim_histogram_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let const_claim_radix_bucket_total = required_workspace(
        "call_const_claim_radix_bucket_total",
        ResourceDomain::CallArguments,
        u64::from(NAME_RADIX_BUCKETS) * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let const_claim_radix_bucket_base = required_workspace(
        "call_const_claim_radix_bucket_base",
        ResourceDomain::CallArguments,
        u64::from(NAME_RADIX_BUCKETS) * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let call_arg_row_count_out = graph.add_resource(ResourceDesc {
        name: "call_arg_row_count_out",
        domain: ResourceDomain::CallArguments,
        class: ResourceClass::Output,
        bytes: 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let generic_claim_count_out = graph.add_resource(ResourceDesc {
        name: "call_generic_claim_count_out",
        domain: ResourceDomain::CallArguments,
        class: ResourceClass::Output,
        bytes: 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let semantic_value_decl_by_hir = graph.add_resource(ResourceDesc {
        name: "semantic_value_decl_by_hir",
        domain: ResourceDomain::HirNodes,
        class: ResourceClass::Output,
        bytes: hir_rows * 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let semantic_value_type_by_hir = graph.add_resource(ResourceDesc {
        name: "semantic_value_type_by_hir",
        domain: ResourceDomain::HirNodes,
        class: ResourceClass::Output,
        bytes: hir_rows * 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let semantic_param_type_by_row = graph.add_resource(ResourceDesc {
        name: "semantic_param_type_by_row",
        domain: ResourceDomain::Declarations,
        class: ResourceClass::Output,
        bytes: hir_rows * 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let semantic_enclosing_fn_by_hir = graph.add_resource(ResourceDesc {
        name: "semantic_enclosing_fn_by_hir",
        domain: ResourceDomain::HirNodes,
        class: ResourceClass::Output,
        bytes: hir_rows * 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let semantic_calls_by_hir = graph.add_resource(ResourceDesc {
        name: "semantic_calls_by_hir",
        domain: ResourceDomain::Calls,
        class: ResourceClass::Output,
        bytes: hir_rows * std::mem::size_of::<GpuCheckedCallArtifact>() as u64,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let semantic_expr_ref_tag_by_hir = graph.add_resource(ResourceDesc {
        name: "semantic_expr_ref_tag_by_hir",
        domain: ResourceDomain::HirNodes,
        class: ResourceClass::Output,
        bytes: hir_rows * 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let semantic_expr_ref_payload_by_hir = graph.add_resource(ResourceDesc {
        name: "semantic_expr_ref_payload_by_hir",
        domain: ResourceDomain::HirNodes,
        class: ResourceClass::Output,
        bytes: hir_rows * 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    let compact_predicate_diagnostic_facts = graph.add_resource(ResourceDesc {
        name: "compact_predicate_diagnostic_facts",
        domain: ResourceDomain::HirNodes,
        class: ResourceClass::Workspace,
        bytes: hir_rows * 32,
        usage: WorkspaceUsageClass::Storage,
    })?;
    // Aggregate comparison columns are feature-sized and bind a one-row
    // sentinel for scalar-only jobs. The graph tracks their external identity
    // and pass ownership; runtime active counts bound full-row accesses.
    let external_hir_u32 = |name| ResourceDesc {
        name,
        domain: ResourceDomain::HirNodes,
        class: ResourceClass::External,
        bytes: 4,
        usage: WorkspaceUsageClass::Storage,
    };
    let aggregate_compare_scan_input =
        graph.add_resource(external_hir_u32("aggregate_compare_scan_input"))?;
    let aggregate_compare_expected_instance =
        graph.add_resource(external_hir_u32("aggregate_compare_expected_instance"))?;
    let aggregate_compare_actual_instance =
        graph.add_resource(external_hir_u32("aggregate_compare_actual_instance"))?;
    let aggregate_compare_error_token =
        graph.add_resource(external_hir_u32("aggregate_compare_error_token"))?;
    let aggregate_compare_error_detail =
        graph.add_resource(external_hir_u32("aggregate_compare_error_detail"))?;
    graph.add_resource(external_hir_u32("aggregate_compare_prefix"))?;
    graph.add_resource(external_hir_u32("aggregate_compare_count_out"))?;
    graph.add_resource(ResourceDesc {
        name: "hir_semantic_count",
        domain: ResourceDomain::HirNodes,
        class: ResourceClass::Input,
        bytes: 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    graph.add_resource(ResourceDesc {
        name: "hir_semantic_subtree_end",
        domain: ResourceDomain::HirNodes,
        class: ResourceClass::Input,
        bytes: 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    graph.add_resource(ResourceDesc {
        name: "type_instance_arg_start",
        domain: ResourceDomain::Types,
        class: ResourceClass::Input,
        bytes: 4,
        usage: WorkspaceUsageClass::Storage,
    })?;
    graph.add_resource(external_hir_u32("type_semantic_row_by_token"))?;
    graph.add_resource(external_hir_u32("type_semantic_scan_input"))?;
    graph.add_resource(external_hir_u32("type_semantic_prefix"))?;
    graph.add_resource(external_hir_u32("type_semantic_count_out"))?;
    graph.add_resource(external_hir_u32("type_subtree_compare_scan_input"))?;
    graph.add_resource(external_hir_u32("type_subtree_compare_left_root"))?;
    graph.add_resource(external_hir_u32("type_subtree_compare_right_root"))?;
    graph.add_resource(external_hir_u32("type_subtree_compare_error_token"))?;
    graph.add_resource(external_hir_u32("type_subtree_compare_error_detail"))?;
    let resources = ExpressionTypeResources {
        compact_hir_count,
        compact_hir_core,
        compact_hir_links,
        compact_hir_payload,
        compact_param_count,
        compact_params,
        compact_hir_expr_parent,
        compact_hir_nearest_loop,
        compact_hir_nearest_block,
        compact_hir_nearest_control,
        compact_hir_nearest_fn,
        compact_path_count,
        compact_paths,
        compact_path_segment_count,
        compact_path_segments,
        path_id_by_owner_hir,
        visible_decl,
        visible_type,
        call_return_type,
        call_return_type_token,
        enclosing_fn,
        decl_type_ref_tag,
        decl_type_ref_payload,
        fn_return_ref_tag,
        fn_return_ref_payload,
        call_fn_index,
        fn_start_token_by_decl_token,
        backend_call_fn_index,
        call_param_row_count_out,
        call_param_row_fn_token,
        call_param_row_start,
        call_param_row_count,
        call_param_count,
        method_decl_param_offset,
        method_decl_receiver_mode,
        call_dependency_decl,
        type_instance_kind,
        type_instance_decl_token,
        type_instance_external_canonical,
        type_instance_arg_count,
        type_instance_elem_ref_tag,
        type_instance_elem_ref_payload,
        call_intrinsic_tag,
        method_call_name_id,
        module_value_path_status,
        module_type_path_status,
        module_value_path_call_leaf,
        module_value_path_associated_method_token,
        token_count,
        hir_active_count,
        compact_method_count,
        compact_method_cores,
        compact_method_signatures,
        token_words,
        predicate_syntax_token,
        type_expr_ref_tag,
        type_expr_ref_payload,
        member_result_ref_tag,
        member_result_ref_payload,
        type_generic_param_slot_by_token,
        type_const_param_slot_by_token,
        type_instance_len_kind,
        type_instance_len_payload,
        compact_predicate_count,
        compact_predicates,
        hir_status,
        hir_token_pos,
        raw_to_compact_hir,
        predicate_bound_first_arg_token,
        predicate_bound_second_arg_token,
        predicate_status,
        predicate_method_contract_status,
        predicate_method_validation_first_error_row,
        predicate_method_validation_status,
        predicate_method_validation_detail_token,
        compact_predicate_diagnostic_facts,
        semantic_feature_flags,
        method_token_dispatch_args,
        method_hir_dispatch_args,
        method_compact_dispatch_args,
        method_token_hir_dispatch_args,
        method_radix_prefix_dispatch_args,
        method_radix_bases_dispatch_args,
        predicate_token_dispatch_args,
        predicate_hir_dispatch_args,
        predicate_radix_prefix_dispatch_args,
        predicate_radix_bases_dispatch_args,
        predicate_single_dispatch_args,
        match_hir_dispatch_args,
        scalar_a,
        scalar_b,
        status,
        return_fn_flags,
        return_block_flags,
        call_has_array_arg,
        call_result_instance,
        call_generic_return_arg_node,
        call_arg_param_row,
        call_param_row_scan_local_prefix,
        call_param_row_scan_block_sum,
        call_param_row_scan_prefix_a,
        call_param_row_scan_prefix_b,
        call_arg_row_scan_input,
        call_arg_row_prefix,
        call_arg_row_count_out,
        call_arg_row_scan_local_prefix,
        call_arg_row_scan_block_sum,
        call_arg_row_scan_prefix_a,
        call_arg_row_scan_prefix_b,
        generic_claim_scan_local_prefix,
        generic_claim_scan_block_sum,
        generic_claim_scan_prefix_a,
        generic_claim_scan_prefix_b,
        generic_claim_scan_input,
        generic_claim_prefix,
        generic_claim_count_out,
        generic_claim_radix_block_histogram,
        generic_claim_radix_block_bucket_prefix,
        generic_claim_radix_bucket_total,
        generic_claim_radix_bucket_base,
        const_claim_radix_block_histogram,
        const_claim_radix_block_bucket_prefix,
        const_claim_radix_bucket_total,
        const_claim_radix_bucket_base,
        required_generic_scan_input,
        required_generic_prefix,
        required_generic_scan_local_prefix,
        required_generic_scan_block_sum,
        required_generic_scan_prefix_a,
        required_generic_scan_prefix_b,
        required_generic_count_out,
        required_generic_dispatch_args,
        semantic_value_decl_by_hir,
        semantic_value_type_by_hir,
        semantic_param_type_by_row,
        semantic_enclosing_fn_by_hir,
        semantic_calls_by_hir,
        semantic_expr_ref_tag_by_hir,
        semantic_expr_ref_payload_by_hir,
        aggregate_compare_scan_input,
        aggregate_compare_expected_instance,
        aggregate_compare_actual_instance,
        aggregate_compare_error_token,
        aggregate_compare_error_detail,
    };
    graph.add_pass(PassDesc {
        name: FEATURES_CLEAR_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![PassAccess::write(
            "semantic_feature_flags",
            semantic_feature_flags,
        )],
    })?;
    graph.add_pass(PassDesc {
        name: FEATURES_COLLECT_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", compact_hir_count),
            PassAccess::read("compact_hir_core", compact_hir_core),
            PassAccess::read("compact_method_count", compact_method_count),
            PassAccess::read("compact_predicate_count", compact_predicate_count),
            PassAccess::read_write("semantic_feature_flags", semantic_feature_flags),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: FEATURES_DISPATCH_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::DispatchArguments,
        accesses: vec![
            PassAccess::read("token_count", token_count),
            PassAccess::read("hir_active_count", hir_active_count),
            PassAccess::read("compact_method_count", compact_method_count),
            PassAccess::read("semantic_feature_flags", semantic_feature_flags),
            PassAccess::write("method_token_dispatch_args", method_token_dispatch_args),
            PassAccess::write("method_hir_dispatch_args", method_hir_dispatch_args),
            PassAccess::write("method_compact_dispatch_args", method_compact_dispatch_args),
            PassAccess::write(
                "method_token_hir_dispatch_args",
                method_token_hir_dispatch_args,
            ),
            PassAccess::write(
                "method_radix_prefix_dispatch_args",
                method_radix_prefix_dispatch_args,
            ),
            PassAccess::write(
                "method_radix_bases_dispatch_args",
                method_radix_bases_dispatch_args,
            ),
            PassAccess::write(
                "predicate_token_dispatch_args",
                predicate_token_dispatch_args,
            ),
            PassAccess::write("predicate_hir_dispatch_args", predicate_hir_dispatch_args),
            PassAccess::write(
                "predicate_radix_prefix_dispatch_args",
                predicate_radix_prefix_dispatch_args,
            ),
            PassAccess::write(
                "predicate_radix_bases_dispatch_args",
                predicate_radix_bases_dispatch_args,
            ),
            PassAccess::write(
                "predicate_single_dispatch_args",
                predicate_single_dispatch_args,
            ),
            PassAccess::write("match_hir_dispatch_args", match_hir_dispatch_args),
        ],
    })?;
    // Expression typing executes after call argument matching has published
    // per-call generic and aggregate result dependencies. Keep the graph in
    // the same order as command recording so ownership validation describes
    // the actual GPU schedule.
    let add_expression_type_passes =
        |graph: &mut CompilerGraphBuilder| -> std::result::Result<(), String> {
            graph.add_pass(PassDesc {
                name: INIT_PASS,
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read("compact_hir_count", compact_hir_count),
                    PassAccess::read("compact_hir_core", compact_hir_core),
                    PassAccess::read("compact_hir_payload", compact_hir_payload),
                    PassAccess::read("visible_decl", visible_decl),
                    PassAccess::read("visible_type", visible_type),
                    PassAccess::read("call_return_type", call_return_type),
                    PassAccess::read("semantic_calls_by_hir", semantic_calls_by_hir),
                    PassAccess::read("call_generic_return_arg_node", call_generic_return_arg_node),
                    PassAccess::write("compact_expr_scalar_type_out", scalar_a),
                ],
            })?;
            let pair_count = step_count / 2;
            if pair_count > 0 {
                graph.add_repeated_region(
                    pair_count as u32,
                    vec![
                        step_pass(STEP_A_TO_B_PASS, compact_hir_count, scalar_a, scalar_b),
                        step_pass(STEP_B_TO_A_PASS, compact_hir_count, scalar_b, scalar_a),
                    ],
                )?;
            }
            if step_count % 2 == 1 {
                graph.add_pass(step_pass(
                    STEP_A_TO_B_TAIL_PASS,
                    compact_hir_count,
                    scalar_a,
                    scalar_b,
                ))?;
            }
            let final_scalar = if step_count % 2 == 0 {
                scalar_a
            } else {
                scalar_b
            };
            graph.add_pass(PassDesc {
                name: SEMANTIC_EXPRESSION_REFS_PROJECT_PASS,
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read("compact_hir_count", compact_hir_count),
                    PassAccess::read("compact_hir_core", compact_hir_core),
                    PassAccess::read("compact_hir_payload", compact_hir_payload),
                    PassAccess::read("compact_expr_scalar_type", final_scalar),
                    PassAccess::read("visible_decl", visible_decl),
                    PassAccess::read("decl_type_ref_tag", decl_type_ref_tag),
                    PassAccess::read("decl_type_ref_payload", decl_type_ref_payload),
                    PassAccess::read("type_expr_ref_tag", type_expr_ref_tag),
                    PassAccess::read("type_expr_ref_payload", type_expr_ref_payload),
                    PassAccess::read("member_result_ref_tag", member_result_ref_tag),
                    PassAccess::read("member_result_ref_payload", member_result_ref_payload),
                    PassAccess::read("semantic_calls_by_hir", semantic_calls_by_hir),
                    PassAccess::write("semantic_expr_ref_tag_by_hir", semantic_expr_ref_tag_by_hir),
                    PassAccess::write(
                        "semantic_expr_ref_payload_by_hir",
                        semantic_expr_ref_payload_by_hir,
                    ),
                ],
            })?;
            graph.add_pass(PassDesc {
                name: SEMANTIC_STRUCT_LITERAL_REFS_PROJECT_PASS,
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read("raw_to_compact_hir", raw_to_compact_hir),
                    PassAccess::read(
                        "struct_lit_context_decl_token",
                        struct_lit_context_decl_token,
                    ),
                    PassAccess::read("struct_lit_context_instance", struct_lit_context_instance),
                    PassAccess::read("decl_type_ref_tag", decl_type_ref_tag),
                    PassAccess::read("decl_type_ref_payload", decl_type_ref_payload),
                    PassAccess::read_write(
                        "semantic_expr_ref_tag_by_hir",
                        semantic_expr_ref_tag_by_hir,
                    ),
                    PassAccess::read_write(
                        "semantic_expr_ref_payload_by_hir",
                        semantic_expr_ref_payload_by_hir,
                    ),
                ],
            })?;
            graph.add_pass(PassDesc {
                name: CONDITIONS_COMPACT_EXPR_PASS,
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read("compact_hir_count", compact_hir_count),
                    PassAccess::read("compact_hir_core", compact_hir_core),
                    PassAccess::read("compact_hir_payload", compact_hir_payload),
                    PassAccess::read("compact_hir_nearest_loop", compact_hir_nearest_loop),
                    PassAccess::read("compact_expr_scalar_type", final_scalar),
                    PassAccess::read("semantic_expr_ref_tag_by_hir", semantic_expr_ref_tag_by_hir),
                    PassAccess::read(
                        "semantic_expr_ref_payload_by_hir",
                        semantic_expr_ref_payload_by_hir,
                    ),
                    PassAccess::read("type_instance_kind", type_instance_kind),
                    PassAccess::read_write("status", status),
                ],
            })?;
            graph.add_pass(PassDesc {
                name: CONDITIONS_COMPACT_STMT_PASS,
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read("compact_hir_count", compact_hir_count),
                    PassAccess::read("compact_hir_core", compact_hir_core),
                    PassAccess::read("compact_hir_payload", compact_hir_payload),
                    PassAccess::read("compact_hir_nearest_fn", compact_hir_nearest_fn),
                    PassAccess::read("compact_expr_scalar_type", final_scalar),
                    PassAccess::read("visible_decl", visible_decl),
                    PassAccess::read("visible_type", visible_type),
                    PassAccess::read("call_return_type", call_return_type),
                    PassAccess::read("call_return_type_token", call_return_type_token),
                    PassAccess::read("decl_type_ref_tag", decl_type_ref_tag),
                    PassAccess::read("type_expr_ref_tag", type_expr_ref_tag),
                    PassAccess::read("fn_return_ref_tag", fn_return_ref_tag),
                    PassAccess::read("semantic_expr_ref_tag_by_hir", semantic_expr_ref_tag_by_hir),
                    PassAccess::read(
                        "semantic_expr_ref_payload_by_hir",
                        semantic_expr_ref_payload_by_hir,
                    ),
                    PassAccess::read_write("status", status),
                ],
            })?;
            graph.add_pass(PassDesc {
                name: CONDITIONS_COMPACT_AGGREGATE_REQUESTS_PASS,
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read("compact_hir_count", compact_hir_count),
                    PassAccess::read("compact_hir_core", compact_hir_core),
                    PassAccess::read("compact_hir_payload", compact_hir_payload),
                    PassAccess::read("compact_hir_nearest_fn", compact_hir_nearest_fn),
                    PassAccess::read("visible_decl", visible_decl),
                    PassAccess::read("decl_type_ref_tag", decl_type_ref_tag),
                    PassAccess::read("decl_type_ref_payload", decl_type_ref_payload),
                    PassAccess::read("type_expr_ref_tag", type_expr_ref_tag),
                    PassAccess::read("type_expr_ref_payload", type_expr_ref_payload),
                    PassAccess::read("fn_return_ref_tag", fn_return_ref_tag),
                    PassAccess::read("fn_return_ref_payload", fn_return_ref_payload),
                    PassAccess::read("semantic_expr_ref_tag_by_hir", semantic_expr_ref_tag_by_hir),
                    PassAccess::read(
                        "semantic_expr_ref_payload_by_hir",
                        semantic_expr_ref_payload_by_hir,
                    ),
                    PassAccess::read("type_instance_kind", type_instance_kind),
                    PassAccess::read("type_instance_decl_token", type_instance_decl_token),
                    PassAccess::read(
                        "type_instance_external_canonical",
                        type_instance_external_canonical,
                    ),
                    PassAccess::read("type_instance_arg_count", type_instance_arg_count),
                    PassAccess::read("type_instance_elem_ref_tag", type_instance_elem_ref_tag),
                    PassAccess::read(
                        "type_instance_elem_ref_payload",
                        type_instance_elem_ref_payload,
                    ),
                    PassAccess::read("type_instance_len_kind", type_instance_len_kind),
                    PassAccess::read("type_instance_len_payload", type_instance_len_payload),
                    PassAccess::read(
                        "type_generic_param_slot_by_token",
                        type_generic_param_slot_by_token,
                    ),
                    PassAccess::read(
                        "type_const_param_slot_by_token",
                        type_const_param_slot_by_token,
                    ),
                    PassAccess::write("aggregate_compare_scan_input", aggregate_compare_scan_input),
                    PassAccess::write(
                        "aggregate_compare_expected_instance",
                        aggregate_compare_expected_instance,
                    ),
                    PassAccess::write(
                        "aggregate_compare_actual_instance",
                        aggregate_compare_actual_instance,
                    ),
                    PassAccess::write(
                        "aggregate_compare_error_token",
                        aggregate_compare_error_token,
                    ),
                    PassAccess::write(
                        "aggregate_compare_error_detail",
                        aggregate_compare_error_detail,
                    ),
                    PassAccess::read_write("status", status),
                ],
            })?;
            graph.add_reflected_compute_pass_by_name(
                CONDITIONS_AGGREGATE_ARGS_FINAL_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::CallArguments,
                conditions_aggregate_args_reflection,
                &[],
            )?;
            graph.add_reflected_compute_pass_by_name(
                CONDITIONS_COMPACT_CALLS_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                conditions_compact_calls_reflection,
                &[ReflectedResourceBinding {
                    binding: "call_fn_index",
                    resource: backend_call_fn_index,
                    mode: None,
                }],
            )?;
            graph.add_reflected_compute_pass_by_name(
                CONDITIONS_COMPACT_TYPES_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                conditions_compact_types_reflection,
                &[],
            )?;
            graph.add_pass(PassDesc {
                name: CONDITIONS_COMPACT_METHODS_PASS,
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Declarations,
                accesses: vec![
                    PassAccess::read("compact_method_count", compact_method_count),
                    PassAccess::read("compact_method_cores", compact_method_cores),
                    PassAccess::read("compact_method_signatures", compact_method_signatures),
                    PassAccess::read_write("status", status),
                ],
            })?;
            graph.add_pass(PassDesc {
                name: CONDITIONS_COMPACT_PREDICATES_PASS,
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Declarations,
                accesses: vec![
                    PassAccess::read("compact_hir_count", compact_hir_count),
                    PassAccess::read("compact_hir_core", compact_hir_core),
                    PassAccess::read("compact_predicate_count", compact_predicate_count),
                    PassAccess::read("compact_predicates", compact_predicates),
                    PassAccess::read("compact_method_count", compact_method_count),
                    PassAccess::read("compact_method_cores", compact_method_cores),
                    PassAccess::read(
                        "compact_predicate_diagnostic_facts",
                        compact_predicate_diagnostic_facts,
                    ),
                    PassAccess::read_write("status", status),
                ],
            })?;
            graph.add_pass(PassDesc {
                name: CONDITIONS_COMPACT_NAMES_PASS,
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read("compact_hir_count", compact_hir_count),
                    PassAccess::read("compact_hir_core", compact_hir_core),
                    PassAccess::read("compact_hir_links", compact_hir_links),
                    PassAccess::read("compact_hir_payload", compact_hir_payload),
                    PassAccess::read("compact_hir_expr_parent", compact_hir_expr_parent),
                    PassAccess::read("token_words", token_words),
                    PassAccess::read("predicate_syntax_token", predicate_syntax_token),
                    PassAccess::read("type_expr_ref_tag", type_expr_ref_tag),
                    PassAccess::read("module_type_path_status", module_type_path_status),
                    PassAccess::read("module_value_path_status", module_value_path_status),
                    PassAccess::read("module_value_path_call_leaf", module_value_path_call_leaf),
                    PassAccess::read(
                        "module_value_path_associated_method_token",
                        module_value_path_associated_method_token,
                    ),
                    PassAccess::read("visible_decl", visible_decl),
                    PassAccess::read("visible_type", visible_type),
                    PassAccess::read("call_fn_index", backend_call_fn_index),
                    PassAccess::read("call_return_type", call_return_type),
                    PassAccess::read("call_intrinsic_tag", call_intrinsic_tag),
                    PassAccess::read("method_call_name_id", method_call_name_id),
                    PassAccess::read("enclosing_fn", enclosing_fn),
                    PassAccess::read_write("status", status),
                ],
            })?;
            Ok(())
        };
    graph.add_pass(PassDesc {
        name: CALL_ARRAY_STATE_INIT_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Calls,
        accesses: vec![
            PassAccess::write("call_has_array_arg", call_has_array_arg),
            PassAccess::write("call_result_instance", call_result_instance),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: CALL_PARAM_ROW_SCAN_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Tokens,
        accesses: vec![
            PassAccess::write(
                "call_param_row_scan_local_prefix",
                call_param_row_scan_local_prefix,
            ),
            PassAccess::write(
                "call_param_row_scan_block_sum",
                call_param_row_scan_block_sum,
            ),
            PassAccess::write("call_param_row_scan_prefix_a", call_param_row_scan_prefix_a),
            PassAccess::write("call_param_row_scan_prefix_b", call_param_row_scan_prefix_b),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: CALL_ARG_ROW_MARK_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::write("call_arg_row_scan_input", call_arg_row_scan_input),
            PassAccess::write("call_generic_return_arg_node", call_generic_return_arg_node),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: CALL_ARG_ROW_SCAN_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("call_arg_row_scan_input", call_arg_row_scan_input),
            PassAccess::write("call_arg_row_prefix", call_arg_row_prefix),
            PassAccess::write("call_arg_row_count_out", call_arg_row_count_out),
            PassAccess::write(
                "call_arg_row_scan_local_prefix",
                call_arg_row_scan_local_prefix,
            ),
            PassAccess::write("call_arg_row_scan_block_sum", call_arg_row_scan_block_sum),
            PassAccess::write("call_arg_row_scan_prefix_a", call_arg_row_scan_prefix_a),
            PassAccess::write("call_arg_row_scan_prefix_b", call_arg_row_scan_prefix_b),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: CALL_ARG_ROW_SCATTER_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("call_arg_row_scan_input", call_arg_row_scan_input),
            PassAccess::read("call_arg_row_prefix", call_arg_row_prefix),
            PassAccess::read("call_arg_row_count_out", call_arg_row_count_out),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: CALL_ARG_MATCH_INIT_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::CallArguments,
        accesses: vec![PassAccess::write("call_arg_param_row", call_arg_param_row)],
    })?;
    graph.add_pass(PassDesc {
        name: CALL_ARG_MATCH_CONSUME_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::CallArguments,
        accesses: vec![PassAccess::read("call_arg_param_row", call_arg_param_row)],
    })?;
    graph.add_pass(PassDesc {
        name: GENERIC_CLAIM_COLLECT_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::CallArguments,
        accesses: vec![
            PassAccess::write("call_generic_claim_scan_input", generic_claim_scan_input),
            PassAccess::read_write("call_generic_return_arg_node", call_generic_return_arg_node),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: GENERIC_CLAIM_SCAN_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::CallArguments,
        accesses: vec![
            PassAccess::read("call_generic_claim_scan_input", generic_claim_scan_input),
            PassAccess::write("call_generic_claim_prefix", generic_claim_prefix),
            PassAccess::write("call_generic_claim_count_out", generic_claim_count_out),
            PassAccess::write(
                "call_generic_claim_scan_local_prefix",
                generic_claim_scan_local_prefix,
            ),
            PassAccess::write(
                "call_generic_claim_scan_block_sum",
                generic_claim_scan_block_sum,
            ),
            PassAccess::write(
                "call_generic_claim_scan_prefix_a",
                generic_claim_scan_prefix_a,
            ),
            PassAccess::write(
                "call_generic_claim_scan_prefix_b",
                generic_claim_scan_prefix_b,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: GENERIC_CLAIM_EMIT_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::CallArguments,
        accesses: vec![
            PassAccess::read("call_arg_param_row", call_arg_param_row),
            PassAccess::read("call_generic_claim_scan_input", generic_claim_scan_input),
            PassAccess::read("call_generic_claim_prefix", generic_claim_prefix),
            PassAccess::read("call_generic_claim_count_out", generic_claim_count_out),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: GENERIC_CLAIM_SORT_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::CallArguments,
        accesses: vec![
            PassAccess::write(
                "call_generic_claim_radix_block_histogram",
                generic_claim_radix_block_histogram,
            ),
            PassAccess::write(
                "call_generic_claim_radix_block_bucket_prefix",
                generic_claim_radix_block_bucket_prefix,
            ),
            PassAccess::write(
                "call_generic_claim_radix_bucket_total",
                generic_claim_radix_bucket_total,
            ),
            PassAccess::write(
                "call_generic_claim_radix_bucket_base",
                generic_claim_radix_bucket_base,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: REQUIRED_GENERIC_MARK_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![PassAccess::write(
            "call_required_generic_scan_input",
            required_generic_scan_input,
        )],
    })?;
    graph.add_pass(PassDesc {
        name: REQUIRED_GENERIC_SCAN_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read(
                "call_required_generic_scan_input",
                required_generic_scan_input,
            ),
            PassAccess::write("call_required_generic_prefix", required_generic_prefix),
            PassAccess::write(
                "call_required_generic_scan_local_prefix",
                required_generic_scan_local_prefix,
            ),
            PassAccess::write(
                "call_required_generic_scan_block_sum",
                required_generic_scan_block_sum,
            ),
            PassAccess::write(
                "call_required_generic_scan_prefix_a",
                required_generic_scan_prefix_a,
            ),
            PassAccess::write(
                "call_required_generic_scan_prefix_b",
                required_generic_scan_prefix_b,
            ),
            PassAccess::write(
                "call_required_generic_count_out",
                required_generic_count_out,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: REQUIRED_GENERIC_DISPATCH_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::DispatchArguments,
        accesses: vec![
            PassAccess::read(
                "call_required_generic_count_out",
                required_generic_count_out,
            ),
            PassAccess::write(
                "call_required_generic_dispatch_args",
                required_generic_dispatch_args,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: REQUIRED_GENERIC_VALIDATE_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::CallArguments,
        accesses: vec![
            PassAccess::read(
                "call_required_generic_scan_input",
                required_generic_scan_input,
            ),
            PassAccess::read("call_required_generic_prefix", required_generic_prefix),
            PassAccess::read(
                "call_required_generic_count_out",
                required_generic_count_out,
            ),
            PassAccess::read(
                "call_required_generic_dispatch_args",
                required_generic_dispatch_args,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: CONST_CLAIM_SORT_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::CallArguments,
        accesses: vec![
            PassAccess::write(
                "call_const_claim_radix_block_histogram",
                const_claim_radix_block_histogram,
            ),
            PassAccess::write(
                "call_const_claim_radix_block_bucket_prefix",
                const_claim_radix_block_bucket_prefix,
            ),
            PassAccess::write(
                "call_const_claim_radix_bucket_total",
                const_claim_radix_bucket_total,
            ),
            PassAccess::write(
                "call_const_claim_radix_bucket_base",
                const_claim_radix_bucket_base,
            ),
        ],
    })?;
    graph.add_reflected_compute_pass_by_name(
        CONDITIONS_AGGREGATE_ARGS_CALLS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::CallArguments,
        conditions_aggregate_args_reflection,
        &[],
    )?;
    graph.add_pass(PassDesc {
        name: CALL_ARRAY_STATE_PUBLISH_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::CallArguments,
        accesses: vec![
            PassAccess::read_write("call_has_array_arg", call_has_array_arg),
            PassAccess::read_write("call_result_instance", call_result_instance),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: CALL_ARRAY_STATE_CONSUME_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("call_has_array_arg", call_has_array_arg),
            PassAccess::read("call_result_instance", call_result_instance),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: CALL_RESULT_INSTANCE_PROJECT_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", compact_hir_count),
            PassAccess::read("compact_hir_core", compact_hir_core),
            PassAccess::read("compact_hir_payload", compact_hir_payload),
            PassAccess::read("call_fn_index", call_fn_index),
            PassAccess::read("fn_return_ref_tag", fn_return_ref_tag),
            PassAccess::read("fn_return_ref_payload", fn_return_ref_payload),
            PassAccess::read("type_instance_kind", type_instance_kind),
            PassAccess::read_write("call_result_instance", call_result_instance),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: VISIBLE_MARK_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("token_count", token_count),
            PassAccess::read("compact_hir_count", compact_hir_count),
            PassAccess::read("compact_hir_core", compact_hir_core),
            PassAccess::read("compact_hir_payload", compact_hir_payload),
            PassAccess::read("name_id_by_token", name_id_by_token),
            PassAccess::write("hir_value_decl_name_present", hir_value_decl_name_present),
            PassAccess::write("hir_visible_decl_flag", hir_visible_decl_flag),
        ],
    })?;
    // One logical graph node represents the fixed, GPU-counted scan family;
    // its internal hierarchy is recorded as multiple shader dispatches.
    graph.add_pass(PassDesc {
        name: VISIBLE_SCAN_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("hir_visible_decl_flag", hir_visible_decl_flag),
            PassAccess::write("hir_visible_decl_prefix", hir_visible_decl_prefix),
            PassAccess::write(
                "hir_visible_decl_scan_local_prefix",
                hir_visible_decl_scan_local_prefix,
            ),
            PassAccess::write(
                "hir_visible_decl_scan_block_sum",
                hir_visible_decl_scan_block_sum,
            ),
            PassAccess::write(
                "hir_visible_decl_scan_prefix_a",
                hir_visible_decl_scan_prefix_a,
            ),
            PassAccess::write(
                "hir_visible_decl_scan_prefix_b",
                hir_visible_decl_scan_prefix_b,
            ),
            PassAccess::write("hir_visible_decl_count_out", hir_visible_decl_count_out),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: VISIBLE_SCATTER_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::read("token_count", token_count),
            PassAccess::read("compact_hir_count", compact_hir_count),
            PassAccess::read("compact_hir_core", compact_hir_core),
            PassAccess::read("compact_hir_payload", compact_hir_payload),
            PassAccess::read("compact_hir_scope_end", compact_hir_scope_end),
            PassAccess::read("name_id_by_token", name_id_by_token),
            PassAccess::read("enclosing_fn", enclosing_fn),
            PassAccess::read("hir_visible_decl_flag", hir_visible_decl_flag),
            PassAccess::read("hir_visible_decl_prefix", hir_visible_decl_prefix),
            PassAccess::write("hir_visible_decl_owner_fn", hir_visible_decl_owner_fn),
            PassAccess::write("hir_visible_decl_name_id", hir_visible_decl_name_id),
            PassAccess::write("hir_visible_decl_token", hir_visible_decl_token),
            PassAccess::write("hir_visible_decl_scope_end", hir_visible_decl_scope_end),
            PassAccess::write("hir_visible_decl_node", hir_visible_decl_node),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: VISIBLE_SORT_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::read("hir_visible_decl_count_out", hir_visible_decl_count_out),
            PassAccess::read("hir_visible_decl_owner_fn", hir_visible_decl_owner_fn),
            PassAccess::read("hir_visible_decl_name_id", hir_visible_decl_name_id),
            PassAccess::read("hir_visible_decl_token", hir_visible_decl_token),
            PassAccess::read_write("hir_visible_decl_key_order", hir_visible_decl_key_order),
            PassAccess::read_write(
                "hir_visible_decl_key_order_tmp",
                hir_visible_decl_key_order_tmp,
            ),
            PassAccess::write(
                "hir_visible_decl_key_radix_dispatch_args",
                hir_visible_decl_key_radix_dispatch_args,
            ),
            PassAccess::write(
                "hir_visible_decl_key_radix_block_histogram",
                hir_visible_decl_key_radix_block_histogram,
            ),
            PassAccess::write(
                "hir_visible_decl_key_radix_block_bucket_prefix",
                hir_visible_decl_key_radix_block_bucket_prefix,
            ),
            PassAccess::write(
                "hir_visible_decl_key_radix_bucket_total",
                hir_visible_decl_key_radix_bucket_total,
            ),
            PassAccess::write(
                "hir_visible_decl_key_radix_bucket_base",
                hir_visible_decl_key_radix_bucket_base,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: VISIBLE_SCOPE_TREE_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::read("hir_visible_decl_count_out", hir_visible_decl_count_out),
            PassAccess::read("hir_visible_decl_scope_end", hir_visible_decl_scope_end),
            PassAccess::read("hir_visible_decl_key_order", hir_visible_decl_key_order),
            PassAccess::write("hir_visible_decl_scope_tree", hir_visible_decl_scope_tree),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: VISIBLE_NAMES_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("token_count", token_count),
            PassAccess::read("compact_hir_count", compact_hir_count),
            PassAccess::read("compact_hir_core", compact_hir_core),
            PassAccess::read("compact_hir_payload", compact_hir_payload),
            PassAccess::read("name_id_by_token", name_id_by_token),
            PassAccess::read("hir_value_decl_name_present", hir_value_decl_name_present),
            PassAccess::read("enclosing_fn", enclosing_fn),
            PassAccess::read("hir_visible_decl_count_out", hir_visible_decl_count_out),
            PassAccess::read("hir_visible_decl_owner_fn", hir_visible_decl_owner_fn),
            PassAccess::read("hir_visible_decl_name_id", hir_visible_decl_name_id),
            PassAccess::read("hir_visible_decl_token", hir_visible_decl_token),
            PassAccess::read("hir_visible_decl_scope_end", hir_visible_decl_scope_end),
            PassAccess::read("hir_visible_decl_node", hir_visible_decl_node),
            PassAccess::read("hir_visible_decl_key_order", hir_visible_decl_key_order),
            PassAccess::read("hir_visible_decl_scope_tree", hir_visible_decl_scope_tree),
            PassAccess::read("module_value_path_call_leaf", module_value_path_call_leaf),
            PassAccess::read(
                "module_value_path_associated_method_token",
                module_value_path_associated_method_token,
            ),
            PassAccess::read("type_expr_ref_tag", type_expr_ref_tag),
            PassAccess::read_write("status", status),
            PassAccess::write("visible_decl", visible_decl),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: SCOPE_HIR_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Tokens,
        accesses: vec![
            PassAccess::read("token_count", token_count),
            PassAccess::read("visible_decl", visible_decl),
            PassAccess::read("decl_type_ref_tag", decl_type_ref_tag),
            PassAccess::read("decl_type_ref_payload", decl_type_ref_payload),
            PassAccess::read(
                "type_generic_param_slot_by_token",
                type_generic_param_slot_by_token,
            ),
            PassAccess::read("type_expr_ref_tag", type_expr_ref_tag),
            PassAccess::read("type_expr_ref_payload", type_expr_ref_payload),
            PassAccess::read("type_instance_kind", type_instance_kind),
            PassAccess::read("type_instance_decl_token", type_instance_decl_token),
            PassAccess::read("type_instance_arg_count", type_instance_arg_count),
            PassAccess::read("type_instance_arg_row_start", type_instance_arg_row_start),
            PassAccess::read(
                "type_instance_arg_row_count_out",
                type_instance_arg_row_count_out,
            ),
            PassAccess::read(
                "type_instance_arg_row_ref_tag",
                type_instance_arg_row_ref_tag,
            ),
            PassAccess::read(
                "type_instance_arg_row_ref_payload",
                type_instance_arg_row_ref_payload,
            ),
            PassAccess::read("type_instance_arg_ref_tag", type_instance_arg_ref_tag),
            PassAccess::read(
                "type_instance_arg_ref_payload",
                type_instance_arg_ref_payload,
            ),
            PassAccess::read("type_instance_elem_ref_tag", type_instance_elem_ref_tag),
            PassAccess::read(
                "type_instance_elem_ref_payload",
                type_instance_elem_ref_payload,
            ),
            PassAccess::read_write("visible_type", visible_type),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: PREDICATE_DIAGNOSTICS_CLEAR_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", compact_hir_count),
            PassAccess::write(
                "compact_predicate_diagnostic_facts",
                compact_predicate_diagnostic_facts,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: PREDICATE_DIAGNOSTICS_CLAIM_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("hir_status", hir_status),
            PassAccess::read("raw_to_compact_hir", raw_to_compact_hir),
            PassAccess::read("compact_hir_count", compact_hir_count),
            PassAccess::read("predicate_status", predicate_status),
            PassAccess::read(
                "predicate_method_contract_status",
                predicate_method_contract_status,
            ),
            PassAccess::read(
                "predicate_method_validation_first_error_row",
                predicate_method_validation_first_error_row,
            ),
            PassAccess::read(
                "predicate_method_validation_status",
                predicate_method_validation_status,
            ),
            PassAccess::read_write(
                "compact_predicate_diagnostic_facts",
                compact_predicate_diagnostic_facts,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: PREDICATE_DIAGNOSTICS_PROJECT_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("hir_status", hir_status),
            PassAccess::read("hir_token_pos", hir_token_pos),
            PassAccess::read("raw_to_compact_hir", raw_to_compact_hir),
            PassAccess::read("compact_hir_count", compact_hir_count),
            PassAccess::read("token_words", token_words),
            PassAccess::read(
                "predicate_bound_first_arg_token",
                predicate_bound_first_arg_token,
            ),
            PassAccess::read(
                "predicate_bound_second_arg_token",
                predicate_bound_second_arg_token,
            ),
            PassAccess::read("predicate_status", predicate_status),
            PassAccess::read(
                "predicate_method_contract_status",
                predicate_method_contract_status,
            ),
            PassAccess::read(
                "predicate_method_validation_first_error_row",
                predicate_method_validation_first_error_row,
            ),
            PassAccess::read(
                "predicate_method_validation_status",
                predicate_method_validation_status,
            ),
            PassAccess::read(
                "predicate_method_validation_detail_token",
                predicate_method_validation_detail_token,
            ),
            PassAccess::read_write(
                "compact_predicate_diagnostic_facts",
                compact_predicate_diagnostic_facts,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: RETURNS_CLEAR_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", compact_hir_count),
            PassAccess::write("return_fn_flags", return_fn_flags),
            PassAccess::write("return_block_flags", return_block_flags),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: RETURNS_MARK_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", compact_hir_count),
            PassAccess::read("compact_hir_core", compact_hir_core),
            PassAccess::read("compact_hir_payload", compact_hir_payload),
            PassAccess::read("compact_hir_nearest_block", compact_hir_nearest_block),
            PassAccess::read("compact_hir_nearest_control", compact_hir_nearest_control),
            PassAccess::read("compact_hir_nearest_fn", compact_hir_nearest_fn),
            PassAccess::read_write("return_fn_flags", return_fn_flags),
            PassAccess::read_write("return_block_flags", return_block_flags),
        ],
    })?;
    graph.add_repeated_region(
        2,
        vec![PassDesc {
            name: RETURNS_MARK_IF_PASS,
            phase: CompilerPhase::TypeCheck,
            dispatch_domain: ResourceDomain::HirNodes,
            accesses: vec![
                PassAccess::read("compact_hir_count", compact_hir_count),
                PassAccess::read("compact_hir_core", compact_hir_core),
                PassAccess::read("compact_hir_payload", compact_hir_payload),
                PassAccess::read("compact_hir_nearest_block", compact_hir_nearest_block),
                PassAccess::read("compact_hir_nearest_control", compact_hir_nearest_control),
                PassAccess::read("compact_hir_nearest_fn", compact_hir_nearest_fn),
                PassAccess::read_write("return_fn_flags", return_fn_flags),
                PassAccess::read_write("return_block_flags", return_block_flags),
            ],
        }],
    )?;
    graph.add_pass(PassDesc {
        name: RETURNS_VALIDATE_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", compact_hir_count),
            PassAccess::read("compact_hir_core", compact_hir_core),
            PassAccess::read("compact_hir_payload", compact_hir_payload),
            PassAccess::read("compact_method_count", compact_method_count),
            PassAccess::read("compact_method_cores", compact_method_cores),
            PassAccess::read("fn_return_ref_tag", fn_return_ref_tag),
            PassAccess::read("fn_return_ref_payload", fn_return_ref_payload),
            PassAccess::read("return_fn_flags", return_fn_flags),
            PassAccess::read_write("status", status),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: CALLS_BACKEND_TARGETS_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Tokens,
        accesses: vec![
            PassAccess::read("call_fn_index", call_fn_index),
            PassAccess::read("fn_start_token_by_decl_token", fn_start_token_by_decl_token),
            PassAccess::read("call_param_row_count_out", call_param_row_count_out),
            PassAccess::write("backend_call_fn_index", backend_call_fn_index),
            PassAccess::read_write("call_param_row_fn_token", call_param_row_fn_token),
            PassAccess::read_write("call_param_row_start", call_param_row_start),
            PassAccess::read_write("call_param_row_count", call_param_row_count),
            PassAccess::read_write("call_param_count", call_param_count),
            PassAccess::read_write("method_decl_param_offset", method_decl_param_offset),
            PassAccess::read_write("method_decl_receiver_mode", method_decl_receiver_mode),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: SEMANTIC_CALLS_PROJECT_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", compact_hir_count),
            PassAccess::read("compact_hir_core", compact_hir_core),
            PassAccess::read("compact_hir_links", compact_hir_links),
            PassAccess::read("compact_hir_payload", compact_hir_payload),
            PassAccess::read("compact_path_count", compact_path_count),
            PassAccess::read("compact_paths", compact_paths),
            PassAccess::read("compact_path_segment_count", compact_path_segment_count),
            PassAccess::read("compact_path_segments", compact_path_segments),
            PassAccess::read("path_id_by_owner_hir", path_id_by_owner_hir),
            PassAccess::read("call_fn_index", call_fn_index),
            PassAccess::read("backend_call_fn_index", backend_call_fn_index),
            PassAccess::read("call_dependency_decl", call_dependency_decl),
            PassAccess::read("call_intrinsic_tag", call_intrinsic_tag),
            PassAccess::read("call_return_type", call_return_type),
            PassAccess::read("call_return_type_token", call_return_type_token),
            PassAccess::read("type_expr_ref_tag", type_expr_ref_tag),
            PassAccess::read("type_expr_ref_payload", type_expr_ref_payload),
            PassAccess::read("decl_type_ref_tag", decl_type_ref_tag),
            PassAccess::read("decl_type_ref_payload", decl_type_ref_payload),
            PassAccess::write("semantic_calls_by_hir", semantic_calls_by_hir),
        ],
    })?;
    add_expression_type_passes(&mut graph)?;
    graph.add_pass(PassDesc {
        name: SEMANTIC_ARTIFACT_PROJECT_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", compact_hir_count),
            PassAccess::read("compact_hir_core", compact_hir_core),
            PassAccess::read("compact_hir_payload", compact_hir_payload),
            PassAccess::read("compact_param_count", compact_param_count),
            PassAccess::read("compact_params", compact_params),
            PassAccess::read("visible_decl", visible_decl),
            PassAccess::read("visible_type", visible_type),
            PassAccess::read("enclosing_fn", enclosing_fn),
            PassAccess::write("semantic_value_decl_by_hir", semantic_value_decl_by_hir),
            PassAccess::write("semantic_value_type_by_hir", semantic_value_type_by_hir),
            PassAccess::write("semantic_param_type_by_row", semantic_param_type_by_row),
            PassAccess::write("semantic_enclosing_fn_by_hir", semantic_enclosing_fn_by_hir),
        ],
    })?;
    Ok((graph.build()?, resources))
}

fn step_pass(
    name: &'static str,
    hir_count: ResourceId,
    input: ResourceId,
    output: ResourceId,
) -> PassDesc {
    PassDesc {
        name,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_expr_scalar_type_in", input),
            PassAccess::write("compact_expr_scalar_type_out", output),
        ],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn reflected_storage(name: &str, writable: bool) -> crate::reflection::ParameterReflection {
        crate::reflection::ParameterReflection {
            name: name.to_owned(),
            binding: crate::reflection::BindingInfo {
                kind: "descriptorTableSlot".to_owned(),
                index: Some(0),
                offset: None,
                size: None,
            },
            ty: crate::reflection::TypeLayout {
                kind: Some("resource".to_owned()),
                base_shape: Some("structuredBuffer".to_owned()),
                access: writable.then(|| "readWrite".to_owned()),
                ..Default::default()
            },
            user_attribs: Vec::new(),
        }
    }

    fn compact_condition_reflections() -> (
        crate::reflection::SlangReflection,
        crate::reflection::SlangReflection,
        crate::reflection::SlangReflection,
    ) {
        let calls = [
            "compact_hir_count",
            "compact_hir_core",
            "compact_hir_links",
            "compact_hir_payload",
            "compact_path_count",
            "compact_paths",
            "compact_path_segment_count",
            "compact_path_segments",
            "path_id_by_owner_hir",
            "call_fn_index",
            "call_return_type",
            "call_intrinsic_tag",
            "method_call_name_id",
            "module_value_path_status",
            "module_value_path_associated_method_token",
        ]
        .into_iter()
        .map(|name| reflected_storage(name, false))
        .chain(std::iter::once(reflected_storage("status", true)))
        .collect();
        let types = [
            "compact_hir_count",
            "compact_hir_core",
            "compact_hir_payload",
            "compact_method_count",
            "compact_method_cores",
            "token_words",
            "predicate_syntax_token",
            "enclosing_fn",
            "type_expr_ref_tag",
            "type_expr_ref_payload",
            "type_generic_param_slot_by_token",
            "type_const_param_slot_by_token",
            "type_instance_len_kind",
            "type_instance_len_payload",
        ]
        .into_iter()
        .map(|name| reflected_storage(name, false))
        .chain(std::iter::once(reflected_storage("status", true)))
        .collect();
        let aggregate_args = [
            "hir_status",
            "hir_semantic_count",
            "hir_semantic_subtree_end",
            "aggregate_compare_scan_input",
            "aggregate_compare_prefix",
            "aggregate_compare_count_out",
            "aggregate_compare_expected_instance",
            "aggregate_compare_actual_instance",
            "aggregate_compare_error_token",
            "aggregate_compare_error_detail",
            "type_generic_param_slot_by_token",
            "type_instance_arg_start",
            "type_instance_arg_count",
            "type_instance_arg_ref_tag",
            "type_instance_arg_ref_payload",
            "type_instance_arg_row_start",
            "type_instance_arg_row_count_out",
            "type_instance_arg_row_ref_tag",
            "type_instance_arg_row_ref_payload",
            "type_semantic_row_by_token",
            "type_semantic_scan_input",
            "type_semantic_prefix",
            "type_semantic_count_out",
        ]
        .into_iter()
        .map(|name| reflected_storage(name, false))
        .chain(
            [
                "type_subtree_compare_scan_input",
                "type_subtree_compare_left_root",
                "type_subtree_compare_right_root",
                "type_subtree_compare_error_token",
                "type_subtree_compare_error_detail",
                "status",
            ]
            .into_iter()
            .map(|name| reflected_storage(name, true)),
        )
        .collect();
        (
            crate::reflection::SlangReflection {
                parameters: calls,
                ..Default::default()
            },
            crate::reflection::SlangReflection {
                parameters: types,
                ..Default::default()
            },
            crate::reflection::SlangReflection {
                parameters: aggregate_args,
                ..Default::default()
            },
        )
    }

    #[test]
    fn typecheck_graph_colors_only_complete_workspace_intervals() {
        let (calls, types, aggregate_args) = compact_condition_reflections();
        let (graph, resources) =
            build_graph(1024, 4096, 768, 768, 10, &calls, &types, &aggregate_args).unwrap();
        assert_eq!(graph.repeated_regions().len(), 2);
        let expression_region = graph
            .repeated_regions()
            .iter()
            .find(|region| region.first_pass == graph.pass_id(STEP_A_TO_B_PASS).unwrap())
            .expect("expression pointer-jump repeated region");
        assert_eq!(expression_region.iterations, 5);
        let slot = |resource: ResourceId| {
            let name = graph.resource(resource).unwrap().name;
            graph
                .workspace_plan()
                .assignments
                .iter()
                .find(|assignment| assignment.name == name)
                .unwrap()
                .slot
        };
        assert_ne!(slot(resources.scalar_a), slot(resources.scalar_b),);
        assert!(
            graph
                .resources()
                .iter()
                .all(|resource| resource.class != ResourceClass::Resident),
            "every graph-owned type-check resource now has a complete registered lifetime",
        );
        assert_eq!(
            graph
                .resource(resources.semantic_feature_flags)
                .unwrap()
                .class,
            ResourceClass::Workspace,
            "the fully described feature clear/collect/dispatch interval is colorable",
        );
        assert_eq!(
            graph.resource(resources.return_fn_flags).unwrap().class,
            ResourceClass::Workspace,
            "return convergence is fully described by the registered return passes",
        );
        assert_eq!(
            graph.resource(resources.return_block_flags).unwrap().class,
            ResourceClass::Workspace,
            "block return convergence is fully described by the registered return passes",
        );
        assert_ne!(
            slot(resources.return_fn_flags),
            slot(resources.return_block_flags),
            "simultaneously accessed return columns must never alias",
        );
        assert!(graph.pass_id(FEATURES_COLLECT_PASS).is_some());
        assert!(graph.pass_id(FEATURES_DISPATCH_PASS).is_some());
        assert!(graph.pass_id(CONDITIONS_COMPACT_EXPR_PASS).is_some());
        assert!(graph.pass_id(CONDITIONS_COMPACT_STMT_PASS).is_some());
        assert!(
            graph
                .pass_id(CONDITIONS_COMPACT_AGGREGATE_REQUESTS_PASS)
                .is_some()
        );
        assert!(graph.pass_id(CONDITIONS_COMPACT_CALLS_PASS).is_some());
        assert!(graph.pass_id(CONDITIONS_COMPACT_TYPES_PASS).is_some());
        assert!(graph.pass_id(CONDITIONS_COMPACT_METHODS_PASS).is_some());
        assert!(graph.pass_id(PREDICATE_DIAGNOSTICS_CLEAR_PASS).is_some());
        assert!(graph.pass_id(PREDICATE_DIAGNOSTICS_CLAIM_PASS).is_some());
        assert!(graph.pass_id(PREDICATE_DIAGNOSTICS_PROJECT_PASS).is_some());
        assert!(graph.pass_id(CONDITIONS_COMPACT_PREDICATES_PASS).is_some());
        assert!(graph.pass_id(CONDITIONS_COMPACT_NAMES_PASS).is_some());
        assert!(graph.pass_id(CALL_ARRAY_STATE_PUBLISH_PASS).is_some());
        assert!(graph.pass_id(CALL_RESULT_INSTANCE_PROJECT_PASS).is_some());
        assert!(
            graph
                .pass_id(CALL_RESULT_INSTANCE_PROJECT_PASS)
                .unwrap()
                .index()
                < graph.pass_id(INIT_PASS).unwrap().index(),
            "call-site result instances must be published before expression typing",
        );
        let visible_order = [
            VISIBLE_MARK_PASS,
            VISIBLE_SCAN_PASS,
            VISIBLE_SCATTER_PASS,
            VISIBLE_SORT_PASS,
            VISIBLE_SCOPE_TREE_PASS,
            VISIBLE_NAMES_PASS,
            SCOPE_HIR_PASS,
            INIT_PASS,
        ]
        .map(|name| graph.pass_id(name).unwrap().index());
        assert!(
            visible_order.windows(2).all(|pair| pair[0] < pair[1]),
            "visible declaration production must precede every lookup consumer",
        );
        assert_eq!(
            graph.resource(resources.visible_decl).unwrap().class,
            ResourceClass::External,
            "visible_decl is mutable legacy storage until the visible family moves into graph workspace",
        );
        assert_eq!(
            graph.resource(resources.visible_type).unwrap().class,
            ResourceClass::External,
            "scope publication mutates the legacy visible-type table through a tracked boundary",
        );
        let artifact_pass = graph.pass_id(SEMANTIC_ARTIFACT_PROJECT_PASS).unwrap();
        let call_artifact_pass = graph.pass_id(SEMANTIC_CALLS_PROJECT_PASS).unwrap();
        assert!(
            graph.pass_id(CALLS_BACKEND_TARGETS_PASS).unwrap().index() < call_artifact_pass.index(),
            "backend target-domain projection must precede dense call artifacts",
        );
        assert!(call_artifact_pass.index() < graph.pass_id(INIT_PASS).unwrap().index());
        let aggregate_request_pass = graph
            .pass_id(CONDITIONS_COMPACT_AGGREGATE_REQUESTS_PASS)
            .unwrap();
        let expression_ref_pass = graph
            .pass_id(SEMANTIC_EXPRESSION_REFS_PROJECT_PASS)
            .unwrap();
        let struct_literal_ref_pass = graph
            .pass_id(SEMANTIC_STRUCT_LITERAL_REFS_PROJECT_PASS)
            .unwrap();
        assert!(
            expression_ref_pass.index() < struct_literal_ref_pass.index()
                && struct_literal_ref_pass.index() < aggregate_request_pass.index(),
            "canonical expression references must be projected before aggregate requests consume them",
        );
        assert!(
            graph
                .pass(struct_literal_ref_pass)
                .unwrap()
                .accesses
                .iter()
                .any(|access| {
                    access.resource == resources.semantic_expr_ref_tag_by_hir
                        && access.mode.reads()
                        && access.mode.writes()
                }),
            "raw struct-literal inference must refine the dense expression-reference artifact",
        );
        assert!(
            graph
                .pass_id(CONDITIONS_AGGREGATE_ARGS_CALLS_PASS)
                .unwrap()
                .index()
                < graph.pass_id(INIT_PASS).unwrap().index(),
            "call argument structural comparison must complete before expression typing",
        );
        assert!(
            aggregate_request_pass.index()
                < graph
                    .pass_id(CONDITIONS_AGGREGATE_ARGS_FINAL_PASS)
                    .unwrap()
                    .index(),
            "final structural comparison must consume compact aggregate requests",
        );
        assert!(
            graph.pass_id(CONDITIONS_COMPACT_STMT_PASS).unwrap().index()
                < aggregate_request_pass.index(),
            "scalar statement validation must precede structural aggregate validation",
        );
        let aggregate_request_resources = [
            resources.aggregate_compare_scan_input,
            resources.aggregate_compare_expected_instance,
            resources.aggregate_compare_actual_instance,
            resources.aggregate_compare_error_token,
            resources.aggregate_compare_error_detail,
        ];
        for resource in aggregate_request_resources {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::External,
                "aggregate request columns remain explicit cross-graph resources during migration",
            );
            assert!(
                graph
                    .pass(aggregate_request_pass)
                    .unwrap()
                    .accesses
                    .iter()
                    .any(|access| access.resource == resource && access.mode.writes()),
                "the compact aggregate-request pass must own every request output column",
            );
        }
        let predicate_clear = graph.pass_id(PREDICATE_DIAGNOSTICS_CLEAR_PASS).unwrap();
        let predicate_claim = graph.pass_id(PREDICATE_DIAGNOSTICS_CLAIM_PASS).unwrap();
        let predicate_projection = graph.pass_id(PREDICATE_DIAGNOSTICS_PROJECT_PASS).unwrap();
        let predicate_reducer = graph.pass_id(CONDITIONS_COMPACT_PREDICATES_PASS).unwrap();
        assert!(predicate_clear.index() < predicate_claim.index());
        assert!(predicate_claim.index() < predicate_projection.index());
        assert!(predicate_projection.index() < graph.pass_id(RETURNS_CLEAR_PASS).unwrap().index());
        assert!(predicate_projection.index() < predicate_reducer.index());
        assert_eq!(
            graph
                .resource(resources.compact_predicate_diagnostic_facts)
                .unwrap()
                .class,
            ResourceClass::Workspace,
            "raw predicate diagnostics must be a phase-colored migration fact, not retained state",
        );
        assert!(
            graph
                .pass(predicate_projection)
                .unwrap()
                .accesses
                .iter()
                .any(|access| {
                    access.resource == resources.compact_predicate_diagnostic_facts
                        && access.mode.writes()
                }),
            "the raw-to-dense projection must own diagnostic-fact writes",
        );
        assert!(
            graph
                .pass(predicate_reducer)
                .unwrap()
                .accesses
                .iter()
                .any(|access| {
                    access.resource == resources.compact_predicate_diagnostic_facts
                        && access.mode.reads()
                        && !access.mode.writes()
                }),
            "the compact reducer may only read projected facts",
        );
        assert!(
            artifact_pass.index()
                > graph
                    .pass_id(CONDITIONS_COMPACT_NAMES_PASS)
                    .unwrap()
                    .index()
        );
        for resource in [
            resources.semantic_value_decl_by_hir,
            resources.semantic_value_type_by_hir,
            resources.semantic_param_type_by_row,
            resources.semantic_enclosing_fn_by_hir,
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Output
            );
            assert_eq!(
                graph.lifetime(resource).unwrap().producer,
                Some(artifact_pass)
            );
        }
        assert_eq!(
            graph
                .lifetime(resources.semantic_calls_by_hir)
                .unwrap()
                .producer,
            Some(call_artifact_pass),
        );
        assert_ne!(
            slot(resources.semantic_value_decl_by_hir),
            slot(resources.semantic_value_type_by_hir),
            "simultaneously written semantic artifact columns must not alias",
        );
        assert_ne!(
            slot(resources.semantic_calls_by_hir),
            slot(resources.semantic_value_type_by_hir),
            "the checked-call artifact must not alias another projection output",
        );
        assert_ne!(
            slot(resources.call_has_array_arg),
            slot(resources.call_result_instance),
            "simultaneously writable call state must not alias",
        );
        assert!(graph.pass_id(CALL_ARG_MATCH_INIT_PASS).is_some());
        assert!(graph.pass_id(CALL_ARG_MATCH_CONSUME_PASS).is_some());
        assert_ne!(
            slot(resources.call_arg_row_scan_local_prefix),
            slot(resources.call_arg_row_scan_input),
            "simultaneously bound call-row scan buffers must not alias",
        );
        assert_ne!(
            slot(resources.generic_claim_scan_local_prefix),
            slot(resources.generic_claim_scan_block_sum),
            "simultaneously bound generic-claim scan rows must not alias",
        );
        assert_eq!(
            slot(resources.generic_claim_radix_block_histogram),
            slot(resources.const_claim_radix_block_histogram),
            "fully described sequential radix families should reuse one workspace slot",
        );
        assert_ne!(
            slot(resources.generic_claim_radix_block_histogram),
            slot(resources.generic_claim_radix_block_bucket_prefix),
            "simultaneously bound radix histogram and prefix rows must not alias",
        );
        assert_ne!(
            slot(resources.call_arg_row_scan_block_sum),
            slot(resources.call_arg_row_scan_prefix_a),
            "simultaneously bound scan hierarchy rows must not alias",
        );
        assert_eq!(
            slot(resources.call_arg_param_row),
            slot(resources.required_generic_scan_input),
            "disjoint argument-matching relations should reuse one certified workspace slot",
        );
        assert_ne!(
            slot(resources.required_generic_scan_input),
            slot(resources.required_generic_prefix),
            "scan input and output prefix are simultaneously bound",
        );
        assert!(graph.pass_id(STEP_A_TO_B_TAIL_PASS).is_none());
    }

    #[test]
    fn odd_expression_type_jump_count_has_a_real_tail_pass() {
        let (calls, types, aggregate_args) = compact_condition_reflections();
        let (graph, _) =
            build_graph(1024, 4096, 768, 768, 11, &calls, &types, &aggregate_args).unwrap();
        let expression_region = graph
            .repeated_regions()
            .iter()
            .find(|region| region.first_pass == graph.pass_id(STEP_A_TO_B_PASS).unwrap())
            .expect("expression pointer-jump repeated region");
        assert_eq!(expression_region.iterations, 5);
        assert!(graph.pass_id(STEP_A_TO_B_TAIL_PASS).is_some());
    }
}
