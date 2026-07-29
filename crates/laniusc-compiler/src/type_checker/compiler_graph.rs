use super::*;
use crate::gpu::{
    compiler_graph::{
        AccessMode,
        BoundGraphResource,
        CompilerGraph,
        CompilerGraphAllocations,
        CompilerGraphBuilder,
        CompilerGraphWorkspace,
        CompilerPhase,
        HierarchicalRadixSortGraphPasses,
        HierarchicalRadixSortGraphStepPasses,
        PassAccess,
        PassDesc,
        PrefixScanGraph,
        PrefixScanGraphPasses,
        PrefixScanPairSpec,
        PrefixScanResources,
        PrefixScanSpec,
        PrefixScanWorkspace,
        RadixSortGraphPasses,
        RadixSortGraphResourceNames,
        RadixSortGraphStepPasses,
        ReflectedResourceBinding,
        ResourceClass,
        ResourceDesc,
        ResourceDomain,
        ResourceId,
    },
    workspace::WorkspaceUsageClass,
};

macro_rules! radix_sort_graph_passes {
    ($label:literal) => {
        RadixSortGraphPasses {
            order_to_temporary: RadixSortGraphStepPasses {
                histogram: concat!($label, ".histogram.a"),
                bucket_prefix: concat!($label, ".prefix.a"),
                bucket_bases: concat!($label, ".bases.a"),
                scatter: concat!($label, ".scatter.a"),
            },
            temporary_to_order: RadixSortGraphStepPasses {
                histogram: concat!($label, ".histogram.b"),
                bucket_prefix: concat!($label, ".prefix.b"),
                bucket_bases: concat!($label, ".bases.b"),
                scatter: concat!($label, ".scatter.b"),
            },
        }
    };
}

macro_rules! prefix_scan_graph_passes {
    ($label:literal) => {
        PrefixScanGraphPasses {
            local: $label,
            hierarchy_up_first: concat!($label, ".hierarchy_up.first"),
            hierarchy_up_rest: concat!($label, ".hierarchy_up.rest"),
            hierarchy_down: concat!($label, ".hierarchy_down"),
            apply: concat!($label, ".apply"),
        }
    };
}

macro_rules! hierarchical_radix_sort_graph_passes {
    ($label:literal) => {
        HierarchicalRadixSortGraphPasses {
            order_to_temporary: HierarchicalRadixSortGraphStepPasses {
                histogram: concat!($label, ".histogram.a"),
                bucket_local: concat!($label, ".bucket_local.a"),
                bucket_chunks: concat!($label, ".bucket_chunks.a"),
                bucket_apply: concat!($label, ".bucket_apply.a"),
                bucket_bases: concat!($label, ".bucket_bases.a"),
                scatter: concat!($label, ".scatter.a"),
            },
            temporary_to_order: HierarchicalRadixSortGraphStepPasses {
                histogram: concat!($label, ".histogram.b"),
                bucket_local: concat!($label, ".bucket_local.b"),
                bucket_chunks: concat!($label, ".bucket_chunks.b"),
                bucket_apply: concat!($label, ".bucket_apply.b"),
                bucket_bases: concat!($label, ".bucket_bases.b"),
                scatter: concat!($label, ".scatter.b"),
            },
        }
    };
}

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
pub(super) const AGGREGATE_CALL_SCAN_PASSES: PrefixScanGraphPasses =
    prefix_scan_graph_passes!("type_check.aggregate_requests.calls.scan");
pub(super) const AGGREGATE_CALL_DISPATCH_PASS: &str =
    "type_check.aggregate_requests.calls.dispatch";
pub(super) const AGGREGATE_CALL_INDIRECT_PASS: &str =
    "type_check.aggregate_requests.calls.indirect";
pub(super) const AGGREGATE_FINAL_SCAN_PASSES: PrefixScanGraphPasses =
    prefix_scan_graph_passes!("type_check.aggregate_requests.final.scan");
pub(super) const AGGREGATE_SCAN_RESOURCES: PrefixScanResources<&'static str> =
    PrefixScanResources {
        count: "hir_active_count",
        input: "aggregate_compare_scan_input",
        output_prefix: "aggregate_compare_prefix",
        total: "aggregate_compare_count_out",
        dispatch_args: "hir_active_dispatch_args",
        local_prefix: "aggregate_compare_scan_local_prefix",
        block_sum: "aggregate_compare_scan_block_sum",
        block_prefix: "aggregate_compare_scan_prefix_a",
        hierarchy: "aggregate_compare_scan_prefix_b",
    };
pub(super) const AGGREGATE_FINAL_DISPATCH_PASS: &str =
    "type_check.aggregate_requests.final.dispatch";
pub(super) const AGGREGATE_FINAL_INDIRECT_PASS: &str =
    "type_check.aggregate_requests.final.indirect";
pub(super) const TYPE_SUBTREE_CALL_SCAN_PASSES: PrefixScanGraphPasses =
    prefix_scan_graph_passes!("type_check.type_subtree.calls.scan");
pub(super) const TYPE_SUBTREE_CALL_DISPATCH_PASS: &str = "type_check.type_subtree.calls.dispatch";
pub(super) const TYPE_SUBTREE_CALL_INDIRECT_PASS: &str = "type_check.type_subtree.calls.indirect";
pub(super) const TYPE_SUBTREE_FINAL_SCAN_PASSES: PrefixScanGraphPasses =
    prefix_scan_graph_passes!("type_check.type_subtree.final.scan");
pub(super) const TYPE_SUBTREE_SCAN_RESOURCES: PrefixScanResources<&'static str> =
    PrefixScanResources {
        count: "aggregate_compare_count_out",
        input: "type_subtree_compare_scan_input",
        output_prefix: "type_subtree_compare_prefix",
        total: "type_subtree_compare_count_out",
        dispatch_args: "aggregate_compare_dispatch_args",
        local_prefix: "aggregate_compare_scan_local_prefix",
        block_sum: "aggregate_compare_scan_block_sum",
        block_prefix: "aggregate_compare_scan_prefix_a",
        hierarchy: "aggregate_compare_scan_prefix_b",
    };
pub(super) const TYPE_SUBTREE_FINAL_DISPATCH_PASS: &str = "type_check.type_subtree.final.dispatch";
pub(super) const TYPE_SUBTREE_FINAL_INDIRECT_PASS: &str = "type_check.type_subtree.final.indirect";
pub(super) const TYPE_SEMANTIC_CLEAR_PASS: &str = "type_check.type_semantic.clear";
pub(super) const TYPE_SEMANTIC_MARK_PASS: &str = "type_check.type_semantic.mark";
pub(super) const TYPE_SEMANTIC_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::HirNodes,
    passes: prefix_scan_graph_passes!("type_check.type_semantic.scan"),
    resources: PrefixScanResources {
        count: "hir_semantic_count",
        input: "type_semantic_scan_input",
        output_prefix: "type_semantic_prefix",
        total: "type_semantic_count_out",
        dispatch_args: "hir_active_dispatch_args",
        local_prefix: "aggregate_compare_scan_local_prefix",
        block_sum: "aggregate_compare_scan_block_sum",
        block_prefix: "aggregate_compare_scan_prefix_a",
        hierarchy: "aggregate_compare_scan_prefix_b",
    },
};
pub(super) const TYPE_SEMANTIC_SCATTER_PASS: &str = "type_check.type_semantic.scatter";
pub(super) const TYPE_INSTANCE_ARG_ROW_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::Types,
    passes: prefix_scan_graph_passes!("type_check.type_instance_arg_rows.scan"),
    resources: PrefixScanResources {
        count: "token_count",
        input: "type_instance_arg_count",
        output_prefix: "type_instance_arg_row_start",
        total: "type_instance_arg_row_count_out",
        dispatch_args: "token_active_dispatch_args",
        local_prefix: "type_instance_arg_row_scan_local_prefix",
        block_sum: "type_instance_arg_row_scan_block_sum",
        block_prefix: "type_instance_arg_row_scan_prefix_a",
        hierarchy: "type_instance_arg_row_scan_prefix_b",
    },
};
pub(super) const TYPE_INSTANCE_ARG_ROW_CLEAR_PASS: &str = "type_check.type_instance_arg_rows.clear";
pub(super) const LANGUAGE_NAMES_CLEAR_PASS: &str = "type_check.language_names.clear";
pub(super) const NAMES_MARK_PASS: &str = "type_check.names.mark_lexemes";
pub(super) const NAMES_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::Tokens,
    passes: prefix_scan_graph_passes!("type_check.names.scan"),
    resources: PrefixScanResources {
        count: "token_count",
        input: "name_lexeme_flag",
        output_prefix: "name_lexeme_prefix",
        total: "name_scan_total",
        dispatch_args: "token_active_dispatch_args",
        local_prefix: "name_scan_local_prefix",
        block_sum: "name_scan_block_sum",
        block_prefix: "name_scan_prefix_a",
        hierarchy: "name_scan_prefix_b",
    },
};
pub(super) const NAMES_SCATTER_PASS: &str = "type_check.names.scatter_lexemes";
pub(super) const NAMES_HASH_PREPARE_PASS: &str = "type_check.names.hash_prepare";
pub(super) const NAMES_HASH_INSERT_PASS: &str = "type_check.names.hash_insert";
pub(super) const NAMES_HASH_ASSIGN_PASS: &str = "type_check.names.hash_assign_ids";
pub(super) const LANGUAGE_TYPE_CODES_CLEAR_PASS: &str = "type_check.language_type_codes.clear";
pub(super) const LANGUAGE_DECLS_MATERIALIZE_PASS: &str = "type_check.language_decls.materialize";
pub(super) const TYPE_INSTANCES_MARK_GENERIC_PARAM_RECORDS_PASS: &str =
    "type_check.type_instances.mark_generic_param_records";
pub(super) const TYPE_INSTANCES_PROPAGATE_GENERIC_OWNER_A_TO_B_PASS: &str =
    "type_check.type_instances.propagate_generic_owner.a_to_b";
pub(super) const TYPE_INSTANCES_PROPAGATE_GENERIC_OWNER_B_TO_A_PASS: &str =
    "type_check.type_instances.propagate_generic_owner.b_to_a";
pub(super) const TYPE_INSTANCES_DECL_GENERIC_PARAMS_PASS: &str =
    "type_check.type_instances.decl_generic_params";
pub(super) const TYPE_INSTANCES_GENERIC_PARAM_SORT_DISPATCH_PASS: &str =
    "type_check.type_instances.generic_params.sort_dispatch";
pub(super) const TYPE_INSTANCES_GENERIC_PARAM_SORT_SMALL_PASS: &str =
    "type_check.type_instances.generic_params.sort_small";
pub(super) const GENERIC_PARAMETER_RADIX_SORTS: RadixSortPairDefinition = RadixSortPairDefinition {
    key: RadixSortDefinition {
        dispatch_domain: ResourceDomain::Declarations,
        passes: radix_sort_graph_passes!("type_check.type_instances.generic_params.key"),
        resources: RadixSortResources {
            count: "generic_param_count_out",
            order: "generic_param_key_order",
            temporary_order: "generic_param_key_order_tmp",
            histogram: "generic_param_key_radix_block_histogram",
            bucket_prefix: "generic_param_key_radix_block_bucket_prefix",
            bucket_total: "generic_param_key_radix_bucket_total",
            bucket_base: "generic_param_key_radix_bucket_base",
        },
        dispatch_args: "generic_param_key_radix_dispatch_args",
    },
    slot: RadixSortDefinition {
        dispatch_domain: ResourceDomain::Declarations,
        passes: radix_sort_graph_passes!("type_check.type_instances.generic_params.slot"),
        resources: RadixSortResources {
            count: "generic_param_count_out",
            order: "generic_param_slot_order",
            temporary_order: "generic_param_slot_order_tmp",
            histogram: "generic_param_slot_radix_block_histogram",
            bucket_prefix: "generic_param_slot_radix_block_bucket_prefix",
            bucket_total: "generic_param_slot_radix_bucket_total",
            bucket_base: "generic_param_slot_radix_bucket_base",
        },
        dispatch_args: "generic_param_key_radix_dispatch_args",
    },
};
pub(super) const TYPE_INSTANCES_GENERIC_PARAM_USE_SLOTS_PASS: &str =
    "type_check.type_instances.generic_params.use_slots";
const TYPE_INSTANCES_STRUCT_FIELD_SORT_SEED_PASS: &str =
    "type_check.type_instances.struct_fields.sort.seed";
const TYPE_INSTANCES_STRUCT_FIELD_SORT_PREPARE_PASS: &str =
    "type_check.type_instances.struct_fields.sort.prepare";
pub(super) const STRUCT_FIELD_RADIX_SORT: HierarchicalRadixSortDefinition =
    HierarchicalRadixSortDefinition {
        dispatch_domain: ResourceDomain::Declarations,
        passes: hierarchical_radix_sort_graph_passes!(
            "type_check.type_instances.struct_fields.sort"
        ),
        resources: RadixSortResources {
            count: "compact_field_count",
            order: "struct_field_key_order",
            temporary_order: "struct_field_key_order_tmp",
            histogram: "struct_field_key_radix_block_histogram",
            bucket_prefix: "struct_field_key_radix_block_bucket_prefix",
            bucket_total: "struct_field_key_radix_bucket_total",
            bucket_base: "struct_field_key_radix_bucket_base",
        },
        dispatch_args: "struct_field_key_radix_dispatch_args",
    };
const TYPE_INSTANCE_CORE_COLLECT_INITIAL_PASS: &str =
    "type_check.type_instances.core.collect.initial";
const TYPE_INSTANCE_CORE_COLLECT_PROJECTED_PASS: &str =
    "type_check.type_instances.core.collect.projected";
pub(super) const TYPE_INSTANCE_ARG_ROW_POPULATE_PASS: &str =
    "type_check.type_instance_arg_rows.populate";
pub(super) const TYPE_INSTANCE_ARG_HASH_ROWS_PASS: &str = "type_check.type_instance_arg_rows.hash";
pub(super) const METHOD_KEY_SEED_PASS: &str = "type_check.methods.keys.seed";
pub(super) const METHOD_KEY_RADIX_SORT: RadixSortDefinition = RadixSortDefinition {
    dispatch_domain: ResourceDomain::Declarations,
    passes: radix_sort_graph_passes!("type_check.methods.keys.sort"),
    resources: RadixSortResources {
        count: "token_count",
        order: "method_key_to_fn_token",
        temporary_order: "method_key_order_tmp",
        histogram: "method_key_radix_block_histogram",
        bucket_prefix: "method_key_radix_block_bucket_prefix",
        bucket_total: "method_key_radix_bucket_total",
        bucket_base: "method_key_radix_bucket_base",
    },
    dispatch_args: "method_token_dispatch_args",
};
pub(super) const METHOD_KEY_VALIDATION_PASS: &str = "type_check.methods.keys.validate";
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
pub(super) const SEMANTIC_STRUCT_LITERAL_REFS_EARLY_CLEAR_PASS: &str =
    "type_check.semantic_artifact.struct_literal_refs_early.clear";
pub(super) const SEMANTIC_STRUCT_LITERAL_REFS_EARLY_PROJECT_PASS: &str =
    "type_check.semantic_artifact.struct_literal_refs_early.project";
pub(super) const SEMANTIC_ARRAY_INDEX_REFS_PROJECT_PASS: &str =
    "type_check.semantic_artifact.array_index_refs";
pub(super) const TYPE_INSTANCES_STRUCT_INIT_FIELDS_PASS: &str =
    "type_check.type_instances.struct_init_fields";
pub(super) const TYPE_INSTANCES_STRUCT_INIT_CLEAR_PASS: &str =
    "type_check.type_instances.struct_init.clear";
pub(super) const TYPE_INSTANCES_STRUCT_INIT_CONTEXTS_PASS: &str =
    "type_check.type_instances.struct_init.contexts";
pub(super) const TYPE_INSTANCES_STRUCT_INIT_SUBSTITUTE_PASS: &str =
    "type_check.type_instances.struct_init.substitute";
pub(super) const TYPE_INSTANCES_VALIDATE_AGGREGATE_ACCESS_PASS: &str =
    "type_check.type_instances.validate_aggregate_access";
pub(super) const TYPE_INSTANCES_MEMBER_RECEIVERS_PASS: &str =
    "type_check.type_instances.member_receivers";
pub(super) const TYPE_INSTANCES_MEMBER_RESULTS_PASS: &str =
    "type_check.type_instances.member_results";
pub(super) const TYPE_INSTANCES_MEMBER_SUBSTITUTE_PASS: &str =
    "type_check.type_instances.member_substitute";
pub(super) const TYPE_INSTANCES_MEMBER_RECEIVERS_AFTER_ARRAY_PASS: &str =
    "type_check.type_instances.member_receivers_after_array";
pub(super) const TYPE_INSTANCES_MEMBER_RESULTS_AFTER_ARRAY_PASS: &str =
    "type_check.type_instances.member_results_after_array";
pub(super) const TYPE_INSTANCES_MEMBER_SUBSTITUTE_AFTER_ARRAY_PASS: &str =
    "type_check.type_instances.member_substitute_after_array";
pub(super) const FEATURES_CLEAR_PASS: &str = "type_check.semantic_features.clear";
pub(super) const FEATURES_COLLECT_PASS: &str = "type_check.semantic_features.collect";
pub(super) const FEATURES_DISPATCH_PASS: &str = "type_check.semantic_features.dispatch_args";
pub(super) const IF_DEPTH_CLEAR_PASS: &str = "type_check.if_depth.clear";
pub(super) const IF_DEPTH_MARK_PASS: &str = "type_check.if_depth.mark";
pub(super) const IF_DEPTH_LOCAL_PASS: &str = "type_check.if_depth.local";
pub(super) const IF_DEPTH_SCAN_PASS: &str = "type_check.if_depth.scan";
pub(super) const IF_DEPTH_APPLY_PASS: &str = "type_check.if_depth.apply";
pub(super) const FN_CONTEXT_CLEAR_PASS: &str = "type_check.fn_context.clear";
pub(super) const FN_CONTEXT_MARK_PASS: &str = "type_check.fn_context.mark";
pub(super) const FN_CONTEXT_LOCAL_PASS: &str = "type_check.fn_context.local";
pub(super) const FN_CONTEXT_SCAN_PASS: &str = "type_check.fn_context.scan";
pub(super) const FN_CONTEXT_APPLY_PASS: &str = "type_check.fn_context.apply";
pub(super) const CALLS_BACKEND_TARGETS_PASS: &str = "type_check.calls.backend_targets";
const VISIBLE_MARK_PASS: &str = "type_check.visible.mark_hir_decl_names";
pub(super) const VISIBLE_CLEAR_PASS: &str = "type_check.visible.clear";
const VISIBLE_SEMANTIC_DISPATCH_PASS: &str = "type_check.visible.semantic_dispatch";
const VISIBLE_SCAN_PASS: &str = "type_check.visible.decl_scan";
const VISIBLE_SCAN_UP_FIRST_PASS: &str = "type_check.visible.decl_scan.hierarchy_up.first";
const VISIBLE_SCAN_UP_REST_PASS: &str = "type_check.visible.decl_scan.hierarchy_up.rest";
const VISIBLE_SCAN_DOWN_PASS: &str = "type_check.visible.decl_scan.hierarchy_down";
const VISIBLE_SCAN_APPLY_PASS: &str = "type_check.visible.decl_scan.apply";
pub(super) const VISIBLE_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::HirNodes,
    passes: PrefixScanGraphPasses {
        local: VISIBLE_SCAN_PASS,
        hierarchy_up_first: VISIBLE_SCAN_UP_FIRST_PASS,
        hierarchy_up_rest: VISIBLE_SCAN_UP_REST_PASS,
        hierarchy_down: VISIBLE_SCAN_DOWN_PASS,
        apply: VISIBLE_SCAN_APPLY_PASS,
    },
    resources: PrefixScanResources {
        count: "hir_semantic_count",
        input: "hir_visible_decl_flag",
        output_prefix: "hir_visible_decl_prefix",
        total: "hir_visible_decl_count_out",
        dispatch_args: "hir_semantic_dispatch_args",
        local_prefix: "hir_visible_decl_scan_local_prefix",
        block_sum: "hir_visible_decl_scan_block_sum",
        block_prefix: "hir_visible_decl_scan_prefix_a",
        hierarchy: "hir_visible_decl_scan_prefix_b",
    },
};
const VISIBLE_SCATTER_PASS: &str = "type_check.visible.scatter_hir_decl_records";
const VISIBLE_SORT_PASS: &str = "type_check.visible.sort_hir_decl_keys";
pub(super) const VISIBLE_RADIX_SORT: RadixSortDefinition = RadixSortDefinition {
    dispatch_domain: ResourceDomain::Declarations,
    passes: radix_sort_graph_passes!("type_check.visible.sort_hir_decl_keys"),
    resources: RadixSortResources {
        count: "hir_visible_decl_count_out",
        order: "hir_visible_decl_key_order",
        temporary_order: "hir_visible_decl_key_order_tmp",
        histogram: "hir_visible_decl_key_radix_block_histogram",
        bucket_prefix: "hir_visible_decl_key_radix_block_bucket_prefix",
        bucket_total: "hir_visible_decl_key_radix_bucket_total",
        bucket_base: "hir_visible_decl_key_radix_bucket_base",
    },
    dispatch_args: "hir_visible_decl_key_radix_dispatch_args",
};
const VISIBLE_SCOPE_TREE_PASS: &str = "type_check.visible.build_hir_decl_scope_tree";
const VISIBLE_NAMES_PASS: &str = "type_check.visible.hir_names";
pub(super) const SCOPE_HIR_PASS: &str = "type_check.scope.hir";
pub(super) const SEMANTIC_ARTIFACT_PROJECT_PASS: &str = "type_check.semantic_artifact.project";

pub(super) const PREDICATES_CLEAR_BOUND_ARG_FACTS_PASS: &str =
    "type_check.predicates.clear_bound_arg_facts";
pub(super) const PREDICATES_CLEAR_SYNTAX_TOKENS_PASS: &str =
    "type_check.predicates.clear_syntax_tokens";
pub(super) const PREDICATES_COLLECT_BOUND_ARG_FACTS_PASS: &str =
    "type_check.predicates.collect_bound_arg_facts";
pub(super) const PREDICATES_COLLECT_METHOD_CONTRACTS_PASS: &str =
    "type_check.predicates.collect_method_contracts";
pub(super) const PREDICATES_METHOD_CONTRACT_KEYS_PASS: &str =
    "type_check.predicates.method_contract_keys";
pub(super) const PREDICATES_BUILD_METHOD_OWNER_RANGES_PASS: &str =
    "type_check.predicates.build_method_owner_ranges";
pub(super) const PREDICATES_COLLECT_PASS: &str = "type_check.predicates.collect";
pub(super) const PREDICATES_VALIDATE_BOUND_ARGS_PASS: &str =
    "type_check.predicates.validate_bound_args";
pub(super) const PREDICATES_COLLECT_IMPLS_PASS: &str = "type_check.predicates.collect_impls";
pub(super) const PREDICATES_EMIT_METHOD_VALIDATION_ROWS_PASS: &str =
    "type_check.predicates.emit_method_validation_rows";
pub(super) const PREDICATES_EMIT_METHOD_PARAM_VALIDATION_ROWS_PASS: &str =
    "type_check.predicates.emit_method_param_validation_rows";
pub(super) const PREDICATES_VALIDATE_METHOD_TYPE_ARG_ROWS_PASS: &str =
    "type_check.predicates.validate_method_type_arg_rows";
pub(super) const PREDICATES_REDUCE_METHOD_VALIDATION_ERRORS_PASS: &str =
    "type_check.predicates.reduce_method_validation_errors";
pub(super) const PREDICATES_OWNER_IMPL_KEYS_PASS: &str = "type_check.predicates.owner_impl_keys";
pub(super) const PREDICATES_COUNT_OBLIGATION_PAIRS_PASS: &str =
    "type_check.predicates.count_obligation_pairs";
pub(super) const PREDICATES_OBLIGATION_PAIR_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::HirNodes,
    passes: prefix_scan_graph_passes!("type_check.predicates.obligation_pair_scan"),
    resources: PrefixScanResources {
        count: "hir_active_count",
        input: "predicate_obligation_count_by_call",
        output_prefix: "predicate_obligation_prefix_by_call",
        total: "predicate_obligation_pair_total",
        dispatch_args: "predicate_hir_dispatch_args",
        local_prefix: "predicate_obligation_scan_local_prefix",
        block_sum: "predicate_obligation_scan_block_sum",
        block_prefix: "predicate_obligation_scan_prefix_a",
        hierarchy: "predicate_obligation_scan_prefix_b",
    },
};
pub(super) const PREDICATES_OBLIGATION_PAIR_DISPATCH_PASS: &str =
    "type_check.predicates.obligation_pair_dispatch";
pub(super) const PREDICATES_VALIDATE_OBLIGATION_PAIRS_PASS: &str =
    "type_check.predicates.validate_obligation_pairs";

pub(super) const REGISTERED_PREDICATE_DIRECT_PASSES: [&str; 14] = [
    PREDICATES_CLEAR_SYNTAX_TOKENS_PASS,
    PREDICATES_CLEAR_BOUND_ARG_FACTS_PASS,
    PREDICATES_COLLECT_BOUND_ARG_FACTS_PASS,
    PREDICATES_COLLECT_METHOD_CONTRACTS_PASS,
    PREDICATES_COLLECT_PASS,
    PREDICATES_VALIDATE_BOUND_ARGS_PASS,
    PREDICATES_COLLECT_IMPLS_PASS,
    PREDICATES_BUILD_METHOD_OWNER_RANGES_PASS,
    PREDICATES_EMIT_METHOD_VALIDATION_ROWS_PASS,
    PREDICATES_EMIT_METHOD_PARAM_VALIDATION_ROWS_PASS,
    PREDICATES_VALIDATE_METHOD_TYPE_ARG_ROWS_PASS,
    PREDICATES_REDUCE_METHOD_VALIDATION_ERRORS_PASS,
    PREDICATES_COUNT_OBLIGATION_PAIRS_PASS,
    PREDICATES_VALIDATE_OBLIGATION_PAIRS_PASS,
];
pub(super) const REGISTERED_PREDICATE_LOGICAL_PASSES: [&str; 3] = [
    PREDICATES_METHOD_CONTRACT_KEYS_PASS,
    PREDICATES_OWNER_IMPL_KEYS_PASS,
    PREDICATES_OBLIGATION_PAIR_DISPATCH_PASS,
];

pub(super) const REGISTERED_VISIBLE_PASSES: [&str; 7] = [
    VISIBLE_CLEAR_PASS,
    VISIBLE_SEMANTIC_DISPATCH_PASS,
    VISIBLE_MARK_PASS,
    VISIBLE_SCATTER_PASS,
    VISIBLE_SORT_PASS,
    VISIBLE_SCOPE_TREE_PASS,
    VISIBLE_NAMES_PASS,
];
pub(super) const CALL_PARAM_ROW_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::Tokens,
    passes: prefix_scan_graph_passes!("type_check.calls.param_rows.scan"),
    resources: PrefixScanResources {
        count: "token_count",
        input: "call_param_count",
        output_prefix: "call_param_row_start",
        total: "call_param_row_count_out",
        dispatch_args: "token_active_dispatch_args",
        local_prefix: "call_param_row_scan_local_prefix",
        block_sum: "call_param_row_scan_block_sum",
        block_prefix: "call_param_row_scan_prefix_a",
        hierarchy: "call_param_row_scan_prefix_b",
    },
};
pub(super) const CALL_ARG_ROW_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::HirNodes,
    passes: prefix_scan_graph_passes!("type_check.calls.arg_rows.scan"),
    resources: PrefixScanResources {
        count: "hir_active_count",
        input: "call_arg_row_scan_input",
        output_prefix: "call_arg_row_prefix",
        total: "call_arg_row_count_out",
        dispatch_args: "hir_active_dispatch_args",
        local_prefix: "call_arg_row_scan_local_prefix",
        block_sum: "call_arg_row_scan_block_sum",
        block_prefix: "call_arg_row_scan_prefix_a",
        hierarchy: "call_arg_row_scan_prefix_b",
    },
};
pub(super) const GENERIC_CLAIM_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::CallArguments,
    passes: prefix_scan_graph_passes!("type_check.calls.generic_claims.scan"),
    resources: PrefixScanResources {
        count: "call_arg_row_count_out",
        input: "call_generic_claim_scan_input",
        output_prefix: "call_generic_claim_prefix",
        total: "call_generic_claim_count_out",
        dispatch_args: "hir_active_dispatch_args",
        local_prefix: "call_generic_claim_scan_local_prefix",
        block_sum: "call_generic_claim_scan_block_sum",
        block_prefix: "call_generic_claim_scan_prefix_a",
        hierarchy: "call_generic_claim_scan_prefix_b",
    },
};
const GENERIC_CLAIM_SORT_PREPARE_PASS: &str = "type_check.calls.generic_claims.sort.prepare";
pub(super) const GENERIC_CLAIM_RADIX_SORT: RadixSortDefinition = RadixSortDefinition {
    dispatch_domain: ResourceDomain::CallArguments,
    passes: radix_sort_graph_passes!("type_check.calls.generic_claims.sort"),
    resources: RadixSortResources {
        count: "call_generic_claim_count_out",
        order: "call_generic_claim_order",
        temporary_order: "call_generic_claim_order_tmp",
        histogram: "call_generic_claim_radix_block_histogram",
        bucket_prefix: "call_generic_claim_radix_block_bucket_prefix",
        bucket_total: "call_generic_claim_radix_bucket_total",
        bucket_base: "call_generic_claim_radix_bucket_base",
    },
    dispatch_args: "call_generic_claim_radix_dispatch_args",
};
const CONST_CLAIM_SORT_PREPARE_PASS: &str = "type_check.calls.const_claims.sort.prepare";
pub(super) const CONST_CLAIM_RADIX_SORT: RadixSortDefinition = RadixSortDefinition {
    dispatch_domain: ResourceDomain::CallArguments,
    passes: radix_sort_graph_passes!("type_check.calls.const_claims.sort"),
    resources: RadixSortResources {
        count: "call_arg_row_count_out",
        order: "call_const_claim_order",
        temporary_order: "call_const_claim_order_tmp",
        histogram: "call_generic_claim_radix_block_histogram",
        bucket_prefix: "call_generic_claim_radix_block_bucket_prefix",
        bucket_total: "call_generic_claim_radix_bucket_total",
        bucket_base: "call_generic_claim_radix_bucket_base",
    },
    dispatch_args: "call_const_claim_radix_dispatch_args",
};
pub(super) const REQUIRED_GENERIC_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::HirNodes,
    passes: prefix_scan_graph_passes!("type_check.calls.required_generics.scan"),
    resources: PrefixScanResources {
        count: "hir_active_count",
        input: "call_required_generic_scan_input",
        output_prefix: "call_required_generic_prefix",
        total: "call_required_generic_count_out",
        dispatch_args: "hir_active_dispatch_args",
        local_prefix: "call_required_generic_scan_local_prefix",
        block_sum: "call_required_generic_scan_block_sum",
        block_prefix: "call_required_generic_scan_prefix_a",
        hierarchy: "call_required_generic_scan_prefix_b",
    },
};
pub(super) const REQUIRED_GENERIC_DISPATCH_PASS: &str =
    "type_check.calls.required_generics.dispatch";
pub(super) const MODULE_DECL_ROWS_MATERIALIZE_PASS: &str =
    "type_check.modules.declarations.materialize";
const MODULE_RECORD_SCAN_PASS: &str = "type_check.modules.records.scan";
const MODULE_RECORD_SCAN_LOCAL_PASS: &str = "type_check.modules.records.module_scan.local";
const MODULE_RECORD_SCAN_UP_FIRST_PASS: &str =
    "type_check.modules.records.module_scan.hierarchy_up.first";
const MODULE_RECORD_SCAN_UP_REST_PASS: &str =
    "type_check.modules.records.module_scan.hierarchy_up.rest";
const MODULE_RECORD_SCAN_DOWN_PASS: &str = "type_check.modules.records.module_scan.hierarchy_down";
const MODULE_RECORD_SCAN_APPLY_PASS: &str = "type_check.modules.records.module_scan.apply";
const MODULE_RECORD_SCAN_CONSUME_PASS: &str = "type_check.modules.records.module_scan.consume";
const IMPORT_RECORD_SCAN_PREPARE_PASS: &str = "type_check.modules.records.import_scan.prepare";
const IMPORT_RECORD_SCAN_LOCAL_PASS: &str = "type_check.modules.records.import_scan.local";
const IMPORT_RECORD_SCAN_UP_FIRST_PASS: &str =
    "type_check.modules.records.import_scan.hierarchy_up.first";
const IMPORT_RECORD_SCAN_UP_REST_PASS: &str =
    "type_check.modules.records.import_scan.hierarchy_up.rest";
const IMPORT_RECORD_SCAN_DOWN_PASS: &str = "type_check.modules.records.import_scan.hierarchy_down";
const IMPORT_RECORD_SCAN_APPLY_PASS: &str = "type_check.modules.records.import_scan.apply";
const IMPORT_RECORD_SCAN_CONSUME_PASS: &str = "type_check.modules.records.import_scan.consume";
const DECL_RECORD_SCAN_PREPARE_PASS: &str = "type_check.modules.records.decl_scan.prepare";
const DECL_RECORD_SCAN_LOCAL_PASS: &str = "type_check.modules.records.decl_scan.local";
const DECL_RECORD_SCAN_UP_FIRST_PASS: &str =
    "type_check.modules.records.decl_scan.hierarchy_up.first";
const DECL_RECORD_SCAN_UP_REST_PASS: &str =
    "type_check.modules.records.decl_scan.hierarchy_up.rest";
const DECL_RECORD_SCAN_DOWN_PASS: &str = "type_check.modules.records.decl_scan.hierarchy_down";
const DECL_RECORD_SCAN_APPLY_PASS: &str = "type_check.modules.records.decl_scan.apply";
const MODULE_PATH_KEY_RADIX_PASS: &str = "type_check.modules.keys.radix";
const DECL_NAMESPACE_MARK_PASS: &str = "type_check.modules.decl_namespace.mark";
const DECL_NAMESPACE_SCAN_LOCAL_PASS: &str = "type_check.modules.decl_namespace.scan.local";
const DECL_NAMESPACE_SCAN_UP_FIRST_PASS: &str =
    "type_check.modules.decl_namespace.scan.hierarchy_up.first";
const DECL_NAMESPACE_SCAN_UP_REST_PASS: &str =
    "type_check.modules.decl_namespace.scan.hierarchy_up.rest";
const DECL_NAMESPACE_SCAN_DOWN_PASS: &str = "type_check.modules.decl_namespace.scan.hierarchy_down";
const DECL_NAMESPACE_SCAN_APPLY_PASS: &str = "type_check.modules.decl_namespace.scan.apply";
const DECL_NAMESPACE_CONSUME_PASS: &str = "type_check.modules.decl_namespace.consume";
const DECL_PUBLIC_MARK_PASS: &str = "type_check.modules.decl_public.mark";
const DECL_PUBLIC_SCAN_LOCAL_PASS: &str = "type_check.modules.decl_public.scan.local";
const DECL_PUBLIC_SCAN_UP_FIRST_PASS: &str =
    "type_check.modules.decl_public.scan.hierarchy_up.first";
const DECL_PUBLIC_SCAN_UP_REST_PASS: &str = "type_check.modules.decl_public.scan.hierarchy_up.rest";
const DECL_PUBLIC_SCAN_DOWN_PASS: &str = "type_check.modules.decl_public.scan.hierarchy_down";
const DECL_PUBLIC_SCAN_APPLY_PASS: &str = "type_check.modules.decl_public.scan.apply";
const DECL_PUBLIC_CONSUME_PASS: &str = "type_check.modules.decl_public.consume";
const IMPORT_VISIBILITY_COUNT_PASS: &str = "type_check.modules.import_visibility.count";
const IMPORT_VISIBLE_SCAN_LOCAL_PASS: &str = "type_check.modules.import_visibility.scan.local";
const IMPORT_VISIBLE_SCAN_UP_FIRST_PASS: &str =
    "type_check.modules.import_visibility.scan.hierarchy_up.first";
const IMPORT_VISIBLE_SCAN_UP_REST_PASS: &str =
    "type_check.modules.import_visibility.scan.hierarchy_up.rest";
const IMPORT_VISIBLE_SCAN_DOWN_PASS: &str =
    "type_check.modules.import_visibility.scan.hierarchy_down";
const IMPORT_VISIBLE_SCAN_APPLY_PASS: &str = "type_check.modules.import_visibility.scan.apply";
const IMPORT_VISIBLE_CONSUME_PASS: &str = "type_check.modules.import_visibility.scan.consume";
pub(super) const MODULE_RECORD_SCAN_RESOURCES: PrefixScanResources<&'static str> =
    module_record_scan_resources("module_record_count_out");
pub(super) const MODULE_VALUE_SCAN_WORKSPACE: PrefixScanWorkspace<&'static str> =
    PrefixScanWorkspace {
        local_prefix: "module_value_scan_local_prefix",
        block_sum: "module_value_scan_block_sum",
        block_prefix: "module_value_scan_prefix_a",
        hierarchy: "module_value_scan_prefix_b",
    };
pub(super) const IMPORT_RECORD_SCAN_RESOURCES: PrefixScanResources<&'static str> =
    module_record_scan_resources("import_record_count_out");
pub(super) const DECL_RECORD_SCAN_RESOURCES: PrefixScanResources<&'static str> =
    module_record_scan_resources("decl_count_out");

pub(super) const MODULE_RECORD_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::HirNodes,
    passes: PrefixScanGraphPasses {
        local: MODULE_RECORD_SCAN_LOCAL_PASS,
        hierarchy_up_first: MODULE_RECORD_SCAN_UP_FIRST_PASS,
        hierarchy_up_rest: MODULE_RECORD_SCAN_UP_REST_PASS,
        hierarchy_down: MODULE_RECORD_SCAN_DOWN_PASS,
        apply: MODULE_RECORD_SCAN_APPLY_PASS,
    },
    resources: MODULE_RECORD_SCAN_RESOURCES,
};
pub(super) const IMPORT_RECORD_SCAN: PrefixScanSpec = PrefixScanSpec {
    passes: PrefixScanGraphPasses {
        local: IMPORT_RECORD_SCAN_LOCAL_PASS,
        hierarchy_up_first: IMPORT_RECORD_SCAN_UP_FIRST_PASS,
        hierarchy_up_rest: IMPORT_RECORD_SCAN_UP_REST_PASS,
        hierarchy_down: IMPORT_RECORD_SCAN_DOWN_PASS,
        apply: IMPORT_RECORD_SCAN_APPLY_PASS,
    },
    resources: IMPORT_RECORD_SCAN_RESOURCES,
    ..MODULE_RECORD_SCAN
};
pub(super) const DECL_RECORD_SCAN: PrefixScanSpec = PrefixScanSpec {
    passes: PrefixScanGraphPasses {
        local: DECL_RECORD_SCAN_LOCAL_PASS,
        hierarchy_up_first: DECL_RECORD_SCAN_UP_FIRST_PASS,
        hierarchy_up_rest: DECL_RECORD_SCAN_UP_REST_PASS,
        hierarchy_down: DECL_RECORD_SCAN_DOWN_PASS,
        apply: DECL_RECORD_SCAN_APPLY_PASS,
    },
    resources: DECL_RECORD_SCAN_RESOURCES,
    ..MODULE_RECORD_SCAN
};

const fn module_record_scan_resources(total: &'static str) -> PrefixScanResources<&'static str> {
    PrefixScanResources {
        count: "hir_active_count",
        input: "module_record_family_flag",
        output_prefix: "module_record_prefix",
        total,
        dispatch_args: "hir_active_dispatch_args",
        local_prefix: "module_record_scan_local_prefix",
        block_sum: "module_record_scan_block_sum",
        block_prefix: "module_record_scan_prefix_a",
        hierarchy: "module_record_scan_prefix_b",
    }
}
pub(super) const DECL_TYPE_KEY_SCAN_RESOURCES: PrefixScanResources<&'static str> =
    module_compact_scan_resources(
        "decl_count_out",
        "type_instance_arg_ref_tag",
        "decl_type_key_prefix",
        "decl_type_key_count_out",
        "decl_key_radix_dispatch_args",
        false,
    );
pub(super) const DECL_VALUE_KEY_SCAN_RESOURCES: PrefixScanResources<&'static str> =
    module_compact_scan_resources(
        "decl_count_out",
        "type_instance_arg_ref_payload",
        "decl_value_key_prefix",
        "decl_value_key_count_out",
        "decl_key_radix_dispatch_args",
        true,
    );
pub(super) const DECL_TYPE_PUBLIC_SCAN_RESOURCES: PrefixScanResources<&'static str> =
    module_compact_scan_resources(
        "decl_type_key_count_out",
        "type_instance_arg_ref_tag",
        "decl_status",
        "import_visible_type_count_out",
        "decl_key_radix_dispatch_args",
        false,
    );
pub(super) const DECL_VALUE_PUBLIC_SCAN_RESOURCES: PrefixScanResources<&'static str> =
    module_compact_scan_resources(
        "decl_value_key_count_out",
        "type_instance_arg_ref_payload",
        "type_decl_generic_param_count_by_owner_token",
        "import_visible_value_count_out",
        "decl_key_radix_dispatch_args",
        true,
    );
pub(super) const IMPORT_VISIBLE_TYPE_SCAN_RESOURCES: PrefixScanResources<&'static str> =
    module_compact_scan_resources(
        "import_record_count_out",
        "import_visible_type_count",
        "import_visible_type_prefix",
        "import_visible_type_count_out",
        "import_dispatch_args",
        false,
    );
pub(super) const IMPORT_VISIBLE_VALUE_SCAN_RESOURCES: PrefixScanResources<&'static str> =
    module_compact_scan_resources(
        "import_record_count_out",
        "import_visible_value_count",
        "import_visible_value_prefix",
        "import_visible_value_count_out",
        "import_dispatch_args",
        true,
    );
pub(super) const DECL_NAMESPACE_SCAN: PrefixScanPairSpec = PrefixScanPairSpec {
    left_label: "type_check.modules.decl_type_keys",
    right_label: "type_check.modules.decl_value_keys",
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::Declarations,
    passes: PrefixScanGraphPasses {
        local: DECL_NAMESPACE_SCAN_LOCAL_PASS,
        hierarchy_up_first: DECL_NAMESPACE_SCAN_UP_FIRST_PASS,
        hierarchy_up_rest: DECL_NAMESPACE_SCAN_UP_REST_PASS,
        hierarchy_down: DECL_NAMESPACE_SCAN_DOWN_PASS,
        apply: DECL_NAMESPACE_SCAN_APPLY_PASS,
    },
    left: DECL_TYPE_KEY_SCAN_RESOURCES,
    right: DECL_VALUE_KEY_SCAN_RESOURCES,
};
pub(super) const DECL_PUBLIC_SCAN: PrefixScanPairSpec = PrefixScanPairSpec {
    left_label: "type_check.modules.decl_type_public_keys",
    right_label: "type_check.modules.decl_value_public_keys",
    passes: PrefixScanGraphPasses {
        local: DECL_PUBLIC_SCAN_LOCAL_PASS,
        hierarchy_up_first: DECL_PUBLIC_SCAN_UP_FIRST_PASS,
        hierarchy_up_rest: DECL_PUBLIC_SCAN_UP_REST_PASS,
        hierarchy_down: DECL_PUBLIC_SCAN_DOWN_PASS,
        apply: DECL_PUBLIC_SCAN_APPLY_PASS,
    },
    left: DECL_TYPE_PUBLIC_SCAN_RESOURCES,
    right: DECL_VALUE_PUBLIC_SCAN_RESOURCES,
    ..DECL_NAMESPACE_SCAN
};
pub(super) const IMPORT_VISIBLE_SCAN: PrefixScanPairSpec = PrefixScanPairSpec {
    left_label: "type_check.modules.import_visible_type",
    right_label: "type_check.modules.import_visible_value",
    passes: PrefixScanGraphPasses {
        local: IMPORT_VISIBLE_SCAN_LOCAL_PASS,
        hierarchy_up_first: IMPORT_VISIBLE_SCAN_UP_FIRST_PASS,
        hierarchy_up_rest: IMPORT_VISIBLE_SCAN_UP_REST_PASS,
        hierarchy_down: IMPORT_VISIBLE_SCAN_DOWN_PASS,
        apply: IMPORT_VISIBLE_SCAN_APPLY_PASS,
    },
    left: IMPORT_VISIBLE_TYPE_SCAN_RESOURCES,
    right: IMPORT_VISIBLE_VALUE_SCAN_RESOURCES,
    ..DECL_NAMESPACE_SCAN
};
pub(super) const DEPENDENCY_VISIBLE_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::Declarations,
    passes: prefix_scan_graph_passes!("type_check.dependencies.visible.scan"),
    resources: module_compact_scan_resources(
        "import_record_count_out",
        "dependency_visible_count",
        "dependency_visible_prefix",
        "dependency_visible_total",
        "import_dispatch_args",
        false,
    ),
};
pub(super) const DEPENDENCY_CALL_COMPARE_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::HirNodes,
    passes: prefix_scan_graph_passes!("type_check.dependencies.call_compare.scan"),
    resources: module_compact_scan_resources(
        "hir_active_count",
        "dependency_call_compare_scan_input",
        "dependency_call_compare_prefix",
        "dependency_call_compare_total",
        "hir_active_dispatch_args",
        true,
    ),
};

const fn module_compact_scan_resources(
    count: &'static str,
    input: &'static str,
    output_prefix: &'static str,
    total: &'static str,
    dispatch_args: &'static str,
    value_workspace: bool,
) -> PrefixScanResources<&'static str> {
    let (local_prefix, block_sum, block_prefix, hierarchy) = if value_workspace {
        (
            "module_value_scan_local_prefix",
            "module_value_scan_block_sum",
            "module_value_scan_prefix_a",
            "module_value_scan_prefix_b",
        )
    } else {
        (
            "module_record_scan_local_prefix",
            "module_record_scan_block_sum",
            "module_record_scan_prefix_a",
            "module_record_scan_prefix_b",
        )
    };
    PrefixScanResources {
        count,
        input,
        output_prefix,
        total,
        dispatch_args,
        local_prefix,
        block_sum,
        block_prefix,
        hierarchy,
    }
}
pub(super) const RETURNS_CLEAR_PASS: &str = "type_check.returns.clear";
pub(super) const RETURNS_MARK_PASS: &str = "type_check.returns.mark";
pub(super) const RETURNS_MARK_IF_PASS: &str = "type_check.returns.mark_if";
pub(super) const RETURNS_VALIDATE_PASS: &str = "type_check.returns.validate";

#[derive(Clone, Copy)]
struct ExpressionTypeResources {
    call_return_type: ResourceId,
    call_return_type_token: ResourceId,
    fn_entrypoint_tag: ResourceId,
    enclosing_fn: ResourceId,
    call_fn_index: ResourceId,
    method_decl_method_row: ResourceId,
    method_decl_receiver_ref_tag: ResourceId,
    method_decl_receiver_ref_payload: ResourceId,
    method_decl_module_id: ResourceId,
    method_decl_name_token: ResourceId,
    method_decl_name_id: ResourceId,
    method_decl_param_offset: ResourceId,
    method_decl_receiver_mode: ResourceId,
    method_decl_visibility: ResourceId,
    method_decl_signature_flags: ResourceId,
    type_instance_kind: ResourceId,
    type_instance_head_token: ResourceId,
    type_instance_state: ResourceId,
    type_instance_arg_start: ResourceId,
    type_instance_arg_count: ResourceId,
    type_instance_arg_ref_tag: ResourceId,
    type_instance_arg_ref_payload: ResourceId,
    type_instance_arg_hash: ResourceId,
    method_key_to_fn_token: ResourceId,
    method_key_order_tmp: ResourceId,
    method_key_status: ResourceId,
    method_key_duplicate_of: ResourceId,
    method_key_radix_block_histogram: ResourceId,
    method_key_radix_block_bucket_prefix: ResourceId,
    method_key_radix_bucket_total: ResourceId,
    method_key_radix_bucket_base: ResourceId,
    type_instance_arg_row_start: ResourceId,
    type_instance_arg_row_count_out: ResourceId,
    type_instance_arg_row_ref_tag: ResourceId,
    type_instance_arg_row_ref_payload: ResourceId,
    type_instance_arg_row_scan_local_prefix: ResourceId,
    type_instance_arg_row_scan_block_sum: ResourceId,
    type_instance_arg_row_scan_prefix_a: ResourceId,
    type_instance_arg_row_scan_prefix_b: ResourceId,
    type_instance_elem_ref_tag: ResourceId,
    type_instance_elem_ref_payload: ResourceId,
    method_call_receiver_ref_tag: ResourceId,
    method_call_receiver_ref_payload: ResourceId,
    method_call_name_id: ResourceId,
    method_call_site_module_id: ResourceId,
    predicate_syntax_token: ResourceId,
    generic_decl_owner_by_node_a: ResourceId,
    generic_decl_owner_by_node_b: ResourceId,
    predicate_bound_list_by_node_a: ResourceId,
    predicate_bound_list_by_node_b: ResourceId,
    generic_decl_parent_jump_a: ResourceId,
    generic_decl_parent_jump_b: ResourceId,
    type_decl_generic_param_count: ResourceId,
    type_decl_generic_param_count_by_owner_token: ResourceId,
    type_decl_const_param_count_by_owner_token: ResourceId,
    generic_param_count_out: ResourceId,
    generic_param_owner_token: ResourceId,
    generic_param_name_id: ResourceId,
    generic_param_token: ResourceId,
    generic_param_node: ResourceId,
    generic_param_kind: ResourceId,
    generic_param_key_order: ResourceId,
    generic_param_key_order_tmp: Option<ResourceId>,
    generic_param_slot_order: ResourceId,
    generic_param_slot_order_tmp: Option<ResourceId>,
    generic_param_slot_radix_block_histogram: Option<ResourceId>,
    generic_param_slot_radix_block_bucket_prefix: Option<ResourceId>,
    generic_param_slot_radix_bucket_total: Option<ResourceId>,
    generic_param_slot_radix_bucket_base: Option<ResourceId>,
    type_expr_ref_tag: ResourceId,
    type_expr_ref_payload: ResourceId,
    member_result_context_instance: ResourceId,
    member_result_ref_tag: ResourceId,
    member_result_ref_payload: ResourceId,
    member_result_field_ordinal: ResourceId,
    member_result_field_node: ResourceId,
    struct_init_field_context_instance: ResourceId,
    struct_init_field_expected_ref_tag: ResourceId,
    struct_init_field_expected_ref_payload: ResourceId,
    struct_init_field_ordinal: ResourceId,
    struct_init_field_ordinal_by_node: ResourceId,
    struct_init_field_decl_node_by_node: ResourceId,
    struct_init_field_ordinal_by_row: ResourceId,
    struct_init_field_decl_token_by_row: ResourceId,
    struct_field_key_order: ResourceId,
    struct_field_key_order_tmp: ResourceId,
    struct_field_key_radix_dispatch_args: ResourceId,
    struct_field_key_radix_block_histogram: ResourceId,
    struct_field_key_radix_block_bucket_prefix: ResourceId,
    struct_field_key_radix_bucket_total: ResourceId,
    struct_field_key_radix_bucket_base: ResourceId,
    struct_lit_context_decl_token: ResourceId,
    struct_lit_context_instance: ResourceId,
    array_element_struct_literal_node: ResourceId,
    type_generic_param_slot_by_token: ResourceId,
    type_const_param_slot_by_token: ResourceId,
    type_decl_hir_node_by_token: ResourceId,
    type_instance_len_kind: ResourceId,
    type_instance_len_payload: ResourceId,
    predicate_owner_node: ResourceId,
    predicate_subject_token: ResourceId,
    predicate_bound_token: ResourceId,
    predicate_bound_decl_id: ResourceId,
    predicate_bound_arg_count: ResourceId,
    predicate_bound_first_arg_token: ResourceId,
    predicate_bound_second_arg_token: ResourceId,
    predicate_status: ResourceId,
    predicate_method_contract_owner_hir: ResourceId,
    predicate_method_contract_name_token: ResourceId,
    predicate_method_contract_name_id: ResourceId,
    predicate_method_contract_param_count: ResourceId,
    predicate_method_contract_return_type_node: ResourceId,
    predicate_method_contract_visibility: ResourceId,
    predicate_method_contract_status: ResourceId,
    predicate_method_contract_param_type_node: ResourceId,
    predicate_method_contract_owner_range_first: ResourceId,
    predicate_method_contract_owner_range_count: ResourceId,
    predicate_method_validation_owner_node: ResourceId,
    predicate_method_validation_peer_node: ResourceId,
    predicate_method_validation_first_error_row: ResourceId,
    predicate_method_validation_status: ResourceId,
    predicate_method_validation_detail_token: ResourceId,
    predicate_method_contract_key_order: ResourceId,
    predicate_method_contract_key_order_tmp: ResourceId,
    predicate_method_param_key_order: ResourceId,
    predicate_method_param_key_order_tmp: ResourceId,
    predicate_owner_key_order: ResourceId,
    predicate_owner_key_order_tmp: ResourceId,
    predicate_impl_key_order: ResourceId,
    predicate_impl_key_order_tmp: ResourceId,
    predicate_key_radix_block_histogram: ResourceId,
    predicate_key_radix_block_bucket_prefix: ResourceId,
    predicate_key_radix_bucket_total: ResourceId,
    predicate_key_radix_bucket_base: ResourceId,
    predicate_obligation_count_by_call: ResourceId,
    predicate_obligation_prefix_by_call: ResourceId,
    predicate_obligation_scan_local_prefix: ResourceId,
    predicate_obligation_scan_block_sum: ResourceId,
    predicate_obligation_scan_prefix_a: ResourceId,
    predicate_obligation_scan_prefix_b: ResourceId,
    predicate_obligation_pair_total: ResourceId,
    predicate_obligation_pair_dispatch_args: ResourceId,
    compact_predicate_diagnostic_facts: ResourceId,
    if_delta: ResourceId,
    if_depth_inblock: ResourceId,
    if_block_sum: ResourceId,
    if_prefix_a: ResourceId,
    if_prefix_b: ResourceId,
    if_block_prefix: ResourceId,
    if_depth: ResourceId,
    enclosing_fn_end: ResourceId,
    fn_event_value: ResourceId,
    fn_event_end: ResourceId,
    fn_event_index: ResourceId,
    fn_event_inblock: ResourceId,
    fn_block_sum: ResourceId,
    fn_prefix_a: ResourceId,
    fn_prefix_b: ResourceId,
    fn_block_prefix: ResourceId,
    member_next_node: ResourceId,
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
    generic_claim_callee: ResourceId,
    generic_claim_slot: ResourceId,
    generic_claim_type: ResourceId,
    generic_claim_ref_tag: ResourceId,
    generic_claim_ref_payload: ResourceId,
    generic_claim_arg_row: ResourceId,
    generic_claim_order: ResourceId,
    generic_claim_order_tmp: ResourceId,
    generic_claim_radix_dispatch_args: ResourceId,
    generic_claim_radix_block_histogram: ResourceId,
    generic_claim_radix_block_bucket_prefix: ResourceId,
    generic_claim_radix_bucket_total: ResourceId,
    generic_claim_radix_bucket_base: ResourceId,
    const_claim_radix_block_histogram: ResourceId,
    const_claim_radix_block_bucket_prefix: ResourceId,
    const_claim_radix_bucket_total: ResourceId,
    const_claim_radix_bucket_base: ResourceId,
    const_claim_callee: ResourceId,
    const_claim_slot: ResourceId,
    const_claim_len: ResourceId,
    const_claim_order: ResourceId,
    const_claim_order_tmp: ResourceId,
    const_claim_radix_dispatch_args: ResourceId,
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
    semantic_function_return_type_by_hir: ResourceId,
    semantic_function_entrypoint_by_hir: ResourceId,
    semantic_function_host_service_by_hir: ResourceId,
    semantic_control_depth_by_hir: ResourceId,
    semantic_calls_by_hir: ResourceId,
    semantic_expr_ref_tag_by_hir: ResourceId,
    semantic_expr_ref_payload_by_hir: ResourceId,
    semantic_array_length_by_hir: ResourceId,
    semantic_member_field_ordinal_by_hir: ResourceId,
    type_semantic_row_by_token: ResourceId,
    type_semantic_scan_input: ResourceId,
    type_semantic_prefix: ResourceId,
    type_semantic_count_out: ResourceId,
    type_semantic_row_by_ordinal: ResourceId,
    aggregate_compare_scan_input: ResourceId,
    aggregate_compare_expected_instance: ResourceId,
    aggregate_compare_actual_instance: ResourceId,
    aggregate_compare_error_token: ResourceId,
    aggregate_compare_error_detail: ResourceId,
    aggregate_compare_prefix: ResourceId,
    aggregate_compare_count_out: ResourceId,
    aggregate_compare_scan_local_prefix: ResourceId,
    aggregate_compare_scan_block_sum: ResourceId,
    aggregate_compare_scan_prefix_a: ResourceId,
    aggregate_compare_scan_prefix_b: ResourceId,
    aggregate_compare_dispatch_args: ResourceId,
    type_subtree_compare_scan_input: ResourceId,
    type_subtree_compare_prefix: ResourceId,
    type_subtree_compare_count_out: ResourceId,
    type_subtree_compare_left_root: ResourceId,
    type_subtree_compare_right_root: ResourceId,
    type_subtree_compare_error_token: ResourceId,
    type_subtree_compare_error_detail: ResourceId,
    type_subtree_compare_dispatch_args: ResourceId,
}

/// Typed physical views of the call-analysis resources selected by the
/// compiler graph. Bind-group construction consumes this view; it does not
/// allocate buffers or recover resources from string names.
pub(super) struct TypeCheckCallBuffers {
    pub(super) fn_start_token_by_decl_token: LaniusBuffer<u32>,
    pub(super) backend_call_fn_index: LaniusBuffer<u32>,
    pub(super) call_intrinsic_tag: LaniusBuffer<u32>,
    pub(super) call_param_count: LaniusBuffer<u32>,
    pub(super) call_param_type: LaniusBuffer<u32>,
    pub(super) call_param_ref_tag: LaniusBuffer<u32>,
    pub(super) call_param_ref_payload: LaniusBuffer<u32>,
    pub(super) call_generic_slot_type: LaniusBuffer<u32>,
    pub(super) call_generic_slot_ordinal: LaniusBuffer<u32>,
    pub(super) call_const_slot_len: LaniusBuffer<u32>,
    pub(super) call_param_row_count_out: LaniusBuffer<u32>,
    pub(super) call_param_row_flag: LaniusBuffer<u32>,
    pub(super) call_param_row_node_type: LaniusBuffer<u32>,
    pub(super) call_param_row_node_ref_tag: LaniusBuffer<u32>,
    pub(super) call_param_row_node_ref_payload: LaniusBuffer<u32>,
    pub(super) call_param_row_node: LaniusBuffer<u32>,
    pub(super) call_param_row_fn_token: LaniusBuffer<u32>,
    pub(super) call_param_row_ordinal: LaniusBuffer<u32>,
    pub(super) call_param_row_type: LaniusBuffer<u32>,
    pub(super) call_param_row_ref_tag: LaniusBuffer<u32>,
    pub(super) call_param_row_ref_payload: LaniusBuffer<u32>,
    pub(super) call_param_row_start: LaniusBuffer<u32>,
    pub(super) call_param_row_count: LaniusBuffer<u32>,
    pub(super) call_arg_record: LaniusBuffer<u32>,
    pub(super) call_arg_row_node: LaniusBuffer<u32>,
    pub(super) call_arg_row_call_node: LaniusBuffer<u32>,
    pub(super) call_arg_row_ordinal: LaniusBuffer<u32>,
    pub(super) call_arg_row_start: LaniusBuffer<u32>,
    pub(super) call_arg_row_count: LaniusBuffer<u32>,
    pub(super) function_lookup_key: LaniusBuffer<u32>,
    pub(super) function_lookup_fn: LaniusBuffer<u32>,
    pub(super) fn_return_ref_tag: LaniusBuffer<u32>,
    pub(super) fn_return_ref_payload: LaniusBuffer<u32>,
}

/// Graph-owned storage and ownership contract for checked dense-expression
/// scalar types. This is the first type-check family on the compiler graph;
/// adjacent families are added to the same graph as their legacy resident
/// allocations are removed.
pub(super) struct TypeCheckCompilerGraph {
    graph: CompilerGraph,
    workspace: CompilerGraphWorkspace,
    allocations: CompilerGraphAllocations,
    semantic_interface_scans: SemanticInterfaceScanGraph,
    pub(super) calls: TypeCheckCallBuffers,
    pub(super) scalar_a: LaniusBuffer<u32>,
    pub(super) scalar_b: LaniusBuffer<u32>,
    pub(super) type_expr_ref_tag: LaniusBuffer<u32>,
    pub(super) type_expr_ref_payload: LaniusBuffer<u32>,
    pub(super) type_generic_param_slot_by_token: LaniusBuffer<u32>,
    pub(super) type_const_param_slot_by_token: LaniusBuffer<u32>,
    pub(super) type_decl_hir_node_by_token: LaniusBuffer<u32>,
    pub(super) predicate_syntax_token: LaniusBuffer<u32>,
    pub(super) generic_decl_owner_by_node_a: LaniusBuffer<u32>,
    pub(super) generic_decl_owner_by_node_b: LaniusBuffer<u32>,
    pub(super) predicate_bound_list_by_node_a: LaniusBuffer<u32>,
    pub(super) predicate_bound_list_by_node_b: LaniusBuffer<u32>,
    pub(super) generic_decl_parent_jump_a: LaniusBuffer<u32>,
    pub(super) generic_decl_parent_jump_b: LaniusBuffer<u32>,
    pub(super) type_decl_generic_param_count: LaniusBuffer<u32>,
    pub(super) type_decl_generic_param_count_by_owner_token: LaniusBuffer<u32>,
    pub(super) type_decl_const_param_count_by_owner_token: LaniusBuffer<u32>,
    pub(super) generic_param_count_out: LaniusBuffer<u32>,
    pub(super) generic_param_owner_token: LaniusBuffer<u32>,
    pub(super) generic_param_name_id: LaniusBuffer<u32>,
    pub(super) generic_param_token: LaniusBuffer<u32>,
    pub(super) generic_param_node: LaniusBuffer<u32>,
    pub(super) generic_param_kind: LaniusBuffer<u32>,
    pub(super) generic_param_key_order: LaniusBuffer<u32>,
    pub(super) generic_param_key_order_tmp: Option<LaniusBuffer<u32>>,
    pub(super) generic_param_slot_order: LaniusBuffer<u32>,
    pub(super) generic_param_slot_order_tmp: Option<LaniusBuffer<u32>>,
    pub(super) generic_param_slot_radix_block_histogram: Option<LaniusBuffer<u32>>,
    pub(super) generic_param_slot_radix_block_bucket_prefix: Option<LaniusBuffer<u32>>,
    pub(super) generic_param_slot_radix_bucket_total: Option<LaniusBuffer<u32>>,
    pub(super) generic_param_slot_radix_bucket_base: Option<LaniusBuffer<u32>>,
    pub(super) predicate_owner_node: LaniusBuffer<u32>,
    pub(super) predicate_subject_token: LaniusBuffer<u32>,
    pub(super) predicate_bound_token: LaniusBuffer<u32>,
    pub(super) predicate_bound_decl_id: LaniusBuffer<u32>,
    pub(super) predicate_bound_arg_count: LaniusBuffer<u32>,
    pub(super) predicate_bound_first_arg_token: LaniusBuffer<u32>,
    pub(super) predicate_bound_second_arg_token: LaniusBuffer<u32>,
    pub(super) predicate_status: LaniusBuffer<u32>,
    pub(super) predicate_method_contract_owner_hir: LaniusBuffer<u32>,
    pub(super) predicate_method_contract_name_token: LaniusBuffer<u32>,
    pub(super) predicate_method_contract_name_id: LaniusBuffer<u32>,
    pub(super) predicate_method_contract_param_count: LaniusBuffer<u32>,
    pub(super) predicate_method_contract_return_type_node: LaniusBuffer<u32>,
    pub(super) predicate_method_contract_visibility: LaniusBuffer<u32>,
    pub(super) predicate_method_contract_status: LaniusBuffer<u32>,
    pub(super) predicate_method_contract_param_type_node: LaniusBuffer<u32>,
    pub(super) predicate_method_contract_key_order: LaniusBuffer<u32>,
    pub(super) predicate_method_contract_key_order_tmp: LaniusBuffer<u32>,
    pub(super) predicate_method_param_key_order: LaniusBuffer<u32>,
    pub(super) predicate_method_param_key_order_tmp: LaniusBuffer<u32>,
    pub(super) predicate_method_contract_owner_range_first: LaniusBuffer<u32>,
    pub(super) predicate_method_contract_owner_range_count: LaniusBuffer<u32>,
    pub(super) predicate_method_validation_owner_node: LaniusBuffer<u32>,
    pub(super) predicate_method_validation_peer_node: LaniusBuffer<u32>,
    pub(super) predicate_method_validation_status: LaniusBuffer<u32>,
    pub(super) predicate_method_validation_detail_token: LaniusBuffer<u32>,
    pub(super) predicate_method_validation_first_error_row: LaniusBuffer<u32>,
    pub(super) predicate_owner_key_order: LaniusBuffer<u32>,
    pub(super) predicate_owner_key_order_tmp: LaniusBuffer<u32>,
    pub(super) predicate_impl_key_order: LaniusBuffer<u32>,
    pub(super) predicate_impl_key_order_tmp: LaniusBuffer<u32>,
    pub(super) predicate_key_radix_block_histogram: LaniusBuffer<u32>,
    pub(super) predicate_key_radix_block_bucket_prefix: LaniusBuffer<u32>,
    pub(super) predicate_key_radix_bucket_total: LaniusBuffer<u32>,
    pub(super) predicate_key_radix_bucket_base: LaniusBuffer<u32>,
    pub(super) predicate_obligation_count_by_call: LaniusBuffer<u32>,
    pub(super) predicate_obligation_prefix_by_call: LaniusBuffer<u32>,
    pub(super) predicate_obligation_scan_local_prefix: LaniusBuffer<u32>,
    pub(super) predicate_obligation_scan_block_sum: LaniusBuffer<u32>,
    pub(super) predicate_obligation_scan_prefix_a: LaniusBuffer<u32>,
    pub(super) predicate_obligation_scan_prefix_b: LaniusBuffer<u32>,
    pub(super) predicate_obligation_pair_total: LaniusBuffer<u32>,
    pub(super) predicate_obligation_pair_dispatch_args: LaniusBuffer<u32>,
    pub(super) if_delta: LaniusBuffer<i32>,
    pub(super) if_depth_inblock: LaniusBuffer<i32>,
    pub(super) if_block_sum: LaniusBuffer<i32>,
    pub(super) if_prefix_a: LaniusBuffer<i32>,
    pub(super) if_prefix_b: LaniusBuffer<i32>,
    pub(super) if_block_prefix: LaniusBuffer<i32>,
    pub(super) if_depth: LaniusBuffer<i32>,
    pub(super) enclosing_fn: LaniusBuffer<u32>,
    pub(super) enclosing_fn_end: LaniusBuffer<u32>,
    pub(super) fn_event_value: LaniusBuffer<u32>,
    pub(super) fn_event_end: LaniusBuffer<u32>,
    pub(super) fn_event_index: LaniusBuffer<u32>,
    pub(super) fn_event_inblock: LaniusBuffer<u32>,
    pub(super) fn_block_sum: LaniusBuffer<u32>,
    pub(super) fn_prefix_a: LaniusBuffer<u32>,
    pub(super) fn_prefix_b: LaniusBuffer<u32>,
    pub(super) fn_block_prefix: LaniusBuffer<u32>,
    pub(super) member_result_context_instance: LaniusBuffer<u32>,
    pub(super) member_result_ref_tag: LaniusBuffer<u32>,
    pub(super) member_result_ref_payload: LaniusBuffer<u32>,
    pub(super) member_result_field_ordinal: LaniusBuffer<u32>,
    pub(super) member_result_field_node: LaniusBuffer<u32>,
    pub(super) struct_init_field_context_instance: LaniusBuffer<u32>,
    pub(super) struct_init_field_expected_ref_tag: LaniusBuffer<u32>,
    pub(super) struct_init_field_expected_ref_payload: LaniusBuffer<u32>,
    pub(super) struct_init_field_ordinal: LaniusBuffer<u32>,
    pub(super) struct_init_field_ordinal_by_node: LaniusBuffer<u32>,
    pub(super) struct_init_field_decl_node_by_node: LaniusBuffer<u32>,
    pub(super) struct_init_field_ordinal_by_row: LaniusBuffer<u32>,
    pub(super) struct_init_field_decl_token_by_row: LaniusBuffer<u32>,
    pub(super) struct_field_key_order: LaniusBuffer<u32>,
    pub(super) struct_field_key_order_tmp: LaniusBuffer<u32>,
    pub(super) struct_field_key_radix_dispatch_args: LaniusBuffer<u32>,
    pub(super) struct_field_key_radix_block_histogram: LaniusBuffer<u32>,
    pub(super) struct_field_key_radix_block_bucket_prefix: LaniusBuffer<u32>,
    pub(super) struct_field_key_radix_bucket_total: LaniusBuffer<u32>,
    pub(super) struct_field_key_radix_bucket_base: LaniusBuffer<u32>,
    pub(super) struct_lit_context_decl_token: LaniusBuffer<u32>,
    pub(super) struct_lit_context_instance: LaniusBuffer<u32>,
    pub(super) array_element_struct_literal_node: LaniusBuffer<u32>,
    pub(super) member_next_node: LaniusBuffer<u32>,
    pub(super) type_instance_kind: LaniusBuffer<u32>,
    pub(super) type_instance_head_token: LaniusBuffer<u32>,
    pub(super) type_instance_state: LaniusBuffer<u32>,
    pub(super) type_instance_elem_ref_tag: LaniusBuffer<u32>,
    pub(super) type_instance_elem_ref_payload: LaniusBuffer<u32>,
    pub(super) type_instance_len_kind: LaniusBuffer<u32>,
    pub(super) type_instance_len_payload: LaniusBuffer<u32>,
    pub(super) fn_entrypoint_tag: LaniusBuffer<u32>,
    pub(super) call_fn_index: LaniusBuffer<u32>,
    pub(super) call_return_type: LaniusBuffer<u32>,
    pub(super) call_return_type_token: LaniusBuffer<u32>,
    pub(super) method_decl_method_row: LaniusBuffer<u32>,
    pub(super) method_decl_receiver_ref_tag: LaniusBuffer<u32>,
    pub(super) method_decl_receiver_ref_payload: LaniusBuffer<u32>,
    pub(super) method_decl_module_id: LaniusBuffer<u32>,
    pub(super) method_decl_name_token: LaniusBuffer<u32>,
    pub(super) method_decl_name_id: LaniusBuffer<u32>,
    pub(super) method_decl_param_offset: LaniusBuffer<u32>,
    pub(super) method_decl_receiver_mode: LaniusBuffer<u32>,
    pub(super) method_decl_visibility: LaniusBuffer<u32>,
    pub(super) method_decl_signature_flags: LaniusBuffer<u32>,
    pub(super) method_call_receiver_ref_tag: LaniusBuffer<u32>,
    pub(super) method_call_receiver_ref_payload: LaniusBuffer<u32>,
    pub(super) method_call_name_id: LaniusBuffer<u32>,
    pub(super) method_call_site_module_id: LaniusBuffer<u32>,
    pub(super) type_instance_arg_start: LaniusBuffer<u32>,
    pub(super) type_instance_arg_count: LaniusBuffer<u32>,
    pub(super) type_instance_arg_ref_tag: LaniusBuffer<u32>,
    pub(super) type_instance_arg_ref_payload: LaniusBuffer<u32>,
    pub(super) type_instance_arg_row_start: LaniusBuffer<u32>,
    pub(super) type_instance_arg_row_count_out: LaniusBuffer<u32>,
    pub(super) type_instance_arg_row_ref_tag: LaniusBuffer<u32>,
    pub(super) type_instance_arg_row_ref_payload: LaniusBuffer<u32>,
    pub(super) type_instance_arg_hash: LaniusBuffer<u32>,
    pub(super) method_key_to_fn_token: LaniusBuffer<u32>,
    pub(super) method_key_order_tmp: LaniusBuffer<u32>,
    pub(super) method_key_status: LaniusBuffer<u32>,
    pub(super) method_key_duplicate_of: LaniusBuffer<u32>,
    pub(super) method_key_radix_block_histogram: LaniusBuffer<u32>,
    pub(super) method_key_radix_block_bucket_prefix: LaniusBuffer<u32>,
    pub(super) method_key_radix_bucket_total: LaniusBuffer<u32>,
    pub(super) method_key_radix_bucket_base: LaniusBuffer<u32>,
    pub(super) type_instance_arg_row_scan_local_prefix: LaniusBuffer<u32>,
    pub(super) type_instance_arg_row_scan_block_sum: LaniusBuffer<u32>,
    pub(super) type_instance_arg_row_scan_prefix_a: LaniusBuffer<u32>,
    pub(super) type_instance_arg_row_scan_prefix_b: LaniusBuffer<u32>,
    pub(super) type_semantic_row_by_token: LaniusBuffer<u32>,
    pub(super) type_semantic_scan_input: LaniusBuffer<u32>,
    pub(super) type_semantic_prefix: LaniusBuffer<u32>,
    pub(super) type_semantic_count_out: LaniusBuffer<u32>,
    pub(super) type_semantic_row_by_ordinal: LaniusBuffer<u32>,
    pub(super) aggregate_compare_scan_input: LaniusBuffer<u32>,
    pub(super) aggregate_compare_expected_instance: LaniusBuffer<u32>,
    pub(super) aggregate_compare_actual_instance: LaniusBuffer<u32>,
    pub(super) aggregate_compare_error_token: LaniusBuffer<u32>,
    pub(super) aggregate_compare_error_detail: LaniusBuffer<u32>,
    pub(super) aggregate_compare_prefix: LaniusBuffer<u32>,
    pub(super) aggregate_compare_count_out: LaniusBuffer<u32>,
    pub(super) aggregate_compare_scan_local_prefix: LaniusBuffer<u32>,
    pub(super) aggregate_compare_scan_block_sum: LaniusBuffer<u32>,
    pub(super) aggregate_compare_scan_prefix_a: LaniusBuffer<u32>,
    pub(super) aggregate_compare_scan_prefix_b: LaniusBuffer<u32>,
    pub(super) aggregate_compare_dispatch_args: LaniusBuffer<u32>,
    pub(super) type_subtree_compare_scan_input: LaniusBuffer<u32>,
    pub(super) type_subtree_compare_prefix: LaniusBuffer<u32>,
    pub(super) type_subtree_compare_count_out: LaniusBuffer<u32>,
    pub(super) type_subtree_compare_left_root: LaniusBuffer<u32>,
    pub(super) type_subtree_compare_right_root: LaniusBuffer<u32>,
    pub(super) type_subtree_compare_error_token: LaniusBuffer<u32>,
    pub(super) type_subtree_compare_error_detail: LaniusBuffer<u32>,
    pub(super) type_subtree_compare_dispatch_args: LaniusBuffer<u32>,
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
    pub(super) generic_claim_callee: LaniusBuffer<u32>,
    pub(super) generic_claim_slot: LaniusBuffer<u32>,
    pub(super) generic_claim_type: LaniusBuffer<u32>,
    pub(super) generic_claim_ref_tag: LaniusBuffer<u32>,
    pub(super) generic_claim_ref_payload: LaniusBuffer<u32>,
    pub(super) generic_claim_arg_row: LaniusBuffer<u32>,
    pub(super) generic_claim_order: LaniusBuffer<u32>,
    pub(super) generic_claim_order_tmp: LaniusBuffer<u32>,
    pub(super) generic_claim_radix_dispatch_args: LaniusBuffer<u32>,
    pub(super) generic_claim_radix_block_histogram: LaniusBuffer<u32>,
    pub(super) generic_claim_radix_block_bucket_prefix: LaniusBuffer<u32>,
    pub(super) generic_claim_radix_bucket_total: LaniusBuffer<u32>,
    pub(super) generic_claim_radix_bucket_base: LaniusBuffer<u32>,
    pub(super) const_claim_radix_block_histogram: LaniusBuffer<u32>,
    pub(super) const_claim_radix_block_bucket_prefix: LaniusBuffer<u32>,
    pub(super) const_claim_radix_bucket_total: LaniusBuffer<u32>,
    pub(super) const_claim_radix_bucket_base: LaniusBuffer<u32>,
    pub(super) const_claim_callee: LaniusBuffer<u32>,
    pub(super) const_claim_slot: LaniusBuffer<u32>,
    pub(super) const_claim_len: LaniusBuffer<u32>,
    pub(super) const_claim_order: LaniusBuffer<u32>,
    pub(super) const_claim_order_tmp: LaniusBuffer<u32>,
    pub(super) const_claim_radix_dispatch_args: LaniusBuffer<u32>,
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
    /// Checked return type keyed by dense function HIR row.
    pub(super) semantic_function_return_type_by_hir: LaniusBuffer<u32>,
    /// Checked entrypoint tag keyed by dense function HIR row.
    pub(super) semantic_function_entrypoint_by_hir: LaniusBuffer<u32>,
    /// Resolved runtime host service keyed by dense function HIR row.
    pub(super) semantic_function_host_service_by_hir: LaniusBuffer<u32>,
    /// Structured-control nesting depth keyed by dense HIR row.
    pub(super) semantic_control_depth_by_hir: LaniusBuffer<u32>,
    /// Fixed-width checked call records keyed by compact HIR row.
    pub(super) semantic_calls_by_hir: LaniusBuffer<GpuCheckedCallArtifact>,
    /// Canonical checked type-reference tag keyed by compact expression HIR.
    pub(super) semantic_expr_ref_tag_by_hir: LaniusBuffer<u32>,
    /// Canonical checked type-reference payload keyed by compact expression HIR.
    pub(super) semantic_expr_ref_payload_by_hir: LaniusBuffer<u32>,
    /// Checked fixed-array length keyed by compact expression HIR.
    pub(super) semantic_array_length_by_hir: LaniusBuffer<u32>,
    /// Checked field ordinal keyed by compact member-expression HIR.
    pub(super) semantic_member_field_ordinal_by_hir: LaniusBuffer<u32>,
    /// Phase-local raw predicate results projected by dense compact HIR row.
    /// Eight words per row; consumed only by compact diagnostic reducers.
    pub(super) compact_predicate_diagnostic_facts: LaniusBuffer<u32>,
    pub(super) return_fn_flags: LaniusBuffer<u32>,
    pub(super) return_block_flags: LaniusBuffer<u32>,
    step_count: usize,
}

#[derive(Clone, Copy)]
pub(super) enum SemanticInterfaceScan {
    Names = 0,
    Modules = 1,
    SignatureTypes = 2,
    SignatureEdges = 3,
    Members = 4,
    TypeOrder = 5,
    TypeEdges = 6,
}

struct SemanticInterfaceScanGraph {
    graph: CompilerGraph,
    _workspace: CompilerGraphWorkspace,
    allocations: CompilerGraphAllocations,
    scratch: PrefixScanWorkspace<LaniusBuffer<u32>>,
    resources: [PrefixScanResources<ResourceId>; 7],
    passes: [PrefixScanGraphPasses; 7],
}

impl SemanticInterfaceScanGraph {
    fn new(
        device: &wgpu::Device,
        hir_capacity: u32,
        token_capacity: u32,
        source_file_capacity: u32,
        declaration_capacity: u32,
    ) -> Result<Self> {
        let capacities = [
            u64::from(token_capacity) * 2
                + u64::from(hir_capacity)
                + u64::from(declaration_capacity),
            u64::from(source_file_capacity),
            u64::from(declaration_capacity),
            u64::from(declaration_capacity),
            u64::from(declaration_capacity),
            u64::from(hir_capacity),
            u64::from(hir_capacity),
        ]
        .map(|capacity| capacity.max(1));
        let scan_capacity = capacities.into_iter().max().unwrap_or(1);
        let mut builder = CompilerGraphBuilder::new();
        let scratch = builder
            .add_prefix_scan_workspace(
                ResourceDomain::Types,
                scan_capacity,
                256,
                PrefixScanWorkspace {
                    local_prefix: "semantic_interface.scan.local_prefix",
                    block_sum: "semantic_interface.scan.block_sum",
                    block_prefix: "semantic_interface.scan.block_prefix",
                    hierarchy: "semantic_interface.scan.hierarchy",
                },
            )
            .map_err(anyhow::Error::msg)?;
        macro_rules! resource {
            ($name:expr, $domain:expr, $class:expr, $bytes:expr, $usage:expr) => {
                builder.add_resource(ResourceDesc {
                    name: $name,
                    domain: $domain,
                    class: $class,
                    bytes: $bytes,
                    usage: $usage,
                })?
            };
        }
        macro_rules! scan {
            ($label:literal, $capacity:expr, $domain:expr) => {
                (|| -> Result<_, String> {
                    let count = resource!(
                        concat!($label, ".count"),
                        $domain,
                        ResourceClass::Input,
                        4,
                        WorkspaceUsageClass::Storage
                    );
                    let input = resource!(
                        concat!($label, ".input"),
                        $domain,
                        ResourceClass::Input,
                        $capacity * 4,
                        WorkspaceUsageClass::Storage
                    );
                    let dispatch_args = resource!(
                        concat!($label, ".dispatch"),
                        ResourceDomain::DispatchArguments,
                        ResourceClass::Input,
                        12,
                        WorkspaceUsageClass::StorageIndirect
                    );
                    let output_prefix = resource!(
                        concat!($label, ".output"),
                        $domain,
                        ResourceClass::External,
                        $capacity * 4,
                        WorkspaceUsageClass::Storage
                    );
                    let total = resource!(
                        concat!($label, ".total"),
                        $domain,
                        ResourceClass::External,
                        4,
                        WorkspaceUsageClass::Storage
                    );
                    let resources = PrefixScanResources {
                        count,
                        input,
                        output_prefix,
                        total,
                        dispatch_args,
                        local_prefix: scratch.local_prefix,
                        block_sum: scratch.block_sum,
                        block_prefix: scratch.block_prefix,
                        hierarchy: scratch.hierarchy,
                    };
                    let passes = prefix_scan_graph_passes!($label);
                    builder.add_fragment(PrefixScanGraph {
                        phase: CompilerPhase::TypeCheck,
                        dispatch_domain: $domain,
                        hierarchy_levels: prefix_scan_hierarchy_levels($capacity.div_ceil(256)),
                        passes,
                        resources,
                    })?;
                    Ok((resources, passes))
                })()
            };
        }
        let scans = [
            scan!(
                "semantic_interface.names",
                capacities[0],
                ResourceDomain::Bytes
            ),
            scan!(
                "semantic_interface.modules",
                capacities[1],
                ResourceDomain::Declarations
            ),
            scan!(
                "semantic_interface.signature_types",
                capacities[2],
                ResourceDomain::Types
            ),
            scan!(
                "semantic_interface.signature_edges",
                capacities[3],
                ResourceDomain::Types
            ),
            scan!(
                "semantic_interface.members",
                capacities[4],
                ResourceDomain::Declarations
            ),
            scan!(
                "semantic_interface.type_order",
                capacities[5],
                ResourceDomain::Types
            ),
            scan!(
                "semantic_interface.type_edges",
                capacities[6],
                ResourceDomain::Types
            ),
        ]
        .into_iter()
        .collect::<Result<Vec<_>, String>>()
        .map_err(anyhow::Error::msg)?;
        let graph = builder.build().map_err(anyhow::Error::msg)?;
        let workspace = CompilerGraphWorkspace::new(device, "semantic_interface", &graph)
            .map_err(anyhow::Error::msg)?;
        debug_assert_eq!(workspace.allocation_count(), 4);
        let alias = |resource, rows| {
            workspace
                .alias(&graph, resource, rows)
                .map_err(anyhow::Error::msg)
        };
        let block_capacity = scan_capacity.div_ceil(256) as usize;
        let scratch_buffers = PrefixScanWorkspace {
            local_prefix: alias(scratch.local_prefix, scan_capacity as usize)?,
            block_sum: alias(scratch.block_sum, block_capacity)?,
            block_prefix: alias(scratch.block_prefix, block_capacity)?,
            hierarchy: alias(scratch.hierarchy, block_capacity)?,
        };
        let allocations = workspace.allocations();
        let (resources, passes): (Vec<_>, Vec<_>) = scans.into_iter().unzip();
        Ok(Self {
            graph,
            _workspace: workspace,
            allocations,
            scratch: scratch_buffers,
            resources: resources
                .try_into()
                .expect("seven semantic-interface scans"),
            passes: passes.try_into().expect("seven semantic-interface scans"),
        })
    }

    fn workspace(&self) -> PrefixScanWorkspace<&LaniusBuffer<u32>> {
        self.scratch.as_ref()
    }

    fn validate(&self, scan: SemanticInterfaceScan, resources: &ResourceMap<'_>) -> Result<()> {
        let index = scan as usize;
        let scan_resources = self.resources[index];
        let aliases = [
            (scan_resources.count, "scan_count"),
            (scan_resources.input, "scan_input"),
            (scan_resources.output_prefix, "scan_output_prefix"),
            (scan_resources.total, "scan_total"),
            (scan_resources.dispatch_args, "scan_dispatch_args"),
            (scan_resources.local_prefix, "scan_local_prefix"),
            (scan_resources.block_sum, "scan_block_sum"),
            (scan_resources.block_prefix, "scan_block_prefix"),
            (scan_resources.hierarchy, "scan_hierarchy"),
        ]
        .map(|(resource, registered)| {
            (
                self.graph.resource(resource).expect("scan resource").name,
                registered,
            )
        });
        for pass_name in self.passes[index].names() {
            if let Some(pass) = self.graph.pass_id(pass_name) {
                let bindings =
                    resources.graph_bindings_with_aliases(&self.graph, pass_name, &aliases)?;
                self.allocations
                    .validate_pass_bindings(&self.graph, pass, &bindings)
                    .map_err(anyhow::Error::msg)?;
            }
        }
        Ok(())
    }
}

impl TypeCheckCompilerGraph {
    /// Returns a typed view of one graph-owned resource without duplicating
    /// ownership fields for every logical array.
    pub(super) fn u32_buffer(&self, name: &str) -> Result<LaniusBuffer<u32>> {
        let resource = self
            .graph
            .resource_id(name)
            .ok_or_else(|| anyhow::anyhow!("type-check graph has no resource `{name}`"))?;
        let bytes = self
            .graph
            .resource(resource)
            .expect("graph resource id")
            .bytes;
        if bytes % 4 != 0 {
            return Err(anyhow::anyhow!(
                "type-check resource `{name}` has {bytes} bytes, incompatible with u32 elements",
            ));
        }
        self.workspace
            .alias(&self.graph, resource, (bytes / 4) as usize)
            .map_err(anyhow::Error::msg)
    }

    pub(super) fn prefix_scan_workspace(
        &self,
        names: PrefixScanWorkspace<&str>,
    ) -> Result<PrefixScanWorkspace<LaniusBuffer<u32>>> {
        Ok(PrefixScanWorkspace {
            local_prefix: self.u32_buffer(names.local_prefix)?,
            block_sum: self.u32_buffer(names.block_sum)?,
            block_prefix: self.u32_buffer(names.block_prefix)?,
            hierarchy: self.u32_buffer(names.hierarchy)?,
        })
    }

    pub(super) fn contains_pass(&self, pass_name: &str) -> bool {
        self.graph.pass_id(pass_name).is_some()
    }

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

    /// Validates the complete module prefix-scan schedule against the tracked
    /// allocations used by its runtime bind groups. Optional hierarchy passes
    /// are absent for one-level scans and are skipped.
    pub(super) fn validate_module_prefix_scan_bindings(
        &self,
        resources: &ResourceMap<'_>,
    ) -> Result<()> {
        for passes in [
            MODULE_RECORD_SCAN.passes,
            IMPORT_RECORD_SCAN.passes,
            DECL_RECORD_SCAN.passes,
            DECL_NAMESPACE_SCAN.passes,
            DECL_PUBLIC_SCAN.passes,
            IMPORT_VISIBLE_SCAN.passes,
        ] {
            self.validate_prefix_scan_bindings(passes, resources)?;
        }
        for pass_name in [
            MODULE_RECORD_SCAN_PASS,
            MODULE_RECORD_SCAN_CONSUME_PASS,
            IMPORT_RECORD_SCAN_PREPARE_PASS,
            IMPORT_RECORD_SCAN_CONSUME_PASS,
            DECL_RECORD_SCAN_PREPARE_PASS,
            DECL_NAMESPACE_MARK_PASS,
            DECL_NAMESPACE_CONSUME_PASS,
            DECL_PUBLIC_MARK_PASS,
            DECL_PUBLIC_CONSUME_PASS,
            IMPORT_VISIBILITY_COUNT_PASS,
            IMPORT_VISIBLE_CONSUME_PASS,
        ] {
            if self.contains_pass(pass_name) {
                self.validate_registered_pass_bindings(pass_name, resources)?;
            }
        }
        Ok(())
    }

    /// Validates all graph passes generated by one prefix-scan operation.
    /// Optional hierarchy passes are absent for one-level scans and skipped.
    pub(super) fn validate_prefix_scan_bindings(
        &self,
        passes: PrefixScanGraphPasses,
        resources: &ResourceMap<'_>,
    ) -> Result<()> {
        for pass_name in [
            passes.local,
            passes.hierarchy_up_first,
            passes.hierarchy_up_rest,
            passes.hierarchy_down,
            passes.apply,
        ] {
            if self.contains_pass(pass_name) {
                self.validate_registered_pass_bindings(pass_name, resources)?;
            }
        }
        Ok(())
    }

    /// Validates a reflected pass whose binding names select explicit
    /// ping-pong resources rather than same-named registry entries.
    pub(super) fn validate_registered_pass_binding_aliases(
        &self,
        pass_name: &str,
        resources: &ResourceMap<'_>,
        aliases: &[(&str, &str)],
    ) -> Result<()> {
        let bindings = resources.graph_bindings_with_aliases(&self.graph, pass_name, aliases)?;
        let pass = self
            .graph
            .pass_id(pass_name)
            .ok_or_else(|| anyhow::anyhow!("compiler graph has no pass `{pass_name}`"))?;
        self.allocations
            .validate_pass_bindings(&self.graph, pass, &bindings)
            .map_err(anyhow::Error::msg)
    }

    fn validate_radix_sort_bindings(
        &self,
        sort: RadixSortDefinition,
        resources: &ResourceMap<'_>,
    ) -> Result<()> {
        let r = sort.resources;
        for (passes, input, output) in [
            (sort.passes.order_to_temporary, r.order, r.temporary_order),
            (sort.passes.temporary_to_order, r.temporary_order, r.order),
        ] {
            self.validate_registered_pass_binding_aliases(
                passes.histogram,
                resources,
                &[
                    ("radix_order_in", input),
                    ("radix_block_histogram", r.histogram),
                ],
            )?;
            self.validate_registered_pass_binding_aliases(
                passes.bucket_prefix,
                resources,
                &[
                    ("name_count_in", r.count),
                    ("radix_block_histogram", r.histogram),
                    ("radix_block_bucket_prefix", r.bucket_prefix),
                    ("radix_bucket_total", r.bucket_total),
                ],
            )?;
            self.validate_registered_pass_binding_aliases(
                passes.bucket_bases,
                resources,
                &[
                    ("radix_bucket_total", r.bucket_total),
                    ("radix_bucket_base", r.bucket_base),
                ],
            )?;
            self.validate_registered_pass_binding_aliases(
                passes.scatter,
                resources,
                &[
                    ("radix_order_in", input),
                    ("radix_order_out", output),
                    ("radix_bucket_base", r.bucket_base),
                    ("radix_block_bucket_prefix", r.bucket_prefix),
                ],
            )?;
        }
        Ok(())
    }

    /// Proves that the compact generic-parameter producer, both sort orders,
    /// and use-site resolver bind the physical allocations selected by the
    /// graph. The scalable path deliberately aliases generic binding names to
    /// the shared radix workspace used by the recorded bind groups.
    pub(super) fn validate_registered_generic_param_bindings(
        &self,
        resources: &ResourceMap<'_>,
    ) -> Result<()> {
        self.validate_registered_pass_bindings(TYPE_INSTANCES_DECL_GENERIC_PARAMS_PASS, resources)?;
        self.validate_registered_pass_binding_aliases(
            TYPE_INSTANCES_GENERIC_PARAM_SORT_DISPATCH_PASS,
            resources,
            &[
                ("name_count_in", "generic_param_count_out"),
                (
                    "radix_dispatch_args",
                    "generic_param_key_radix_dispatch_args",
                ),
            ],
        )?;

        if self
            .graph
            .pass_id(TYPE_INSTANCES_GENERIC_PARAM_SORT_SMALL_PASS)
            .is_some()
        {
            self.validate_registered_pass_bindings(
                TYPE_INSTANCES_GENERIC_PARAM_SORT_SMALL_PASS,
                resources,
            )?;
        } else {
            self.validate_radix_sort_bindings(GENERIC_PARAMETER_RADIX_SORTS.key, resources)?;
            self.validate_radix_sort_bindings(GENERIC_PARAMETER_RADIX_SORTS.slot, resources)?;
        }

        self.validate_registered_pass_bindings(
            TYPE_INSTANCES_GENERIC_PARAM_USE_SLOTS_PASS,
            resources,
        )
    }

    pub(super) fn new(
        device: &wgpu::Device,
        hir_capacity: u32,
        token_capacity: u32,
        source_file_capacity: u32,
        module_record_capacity: u32,
        call_param_capacity: u32,
        call_arg_capacity: u32,
        generic_claim_capacity: u32,
        predicate_capacity: u32,
        passes: &TypeCheckPasses,
    ) -> Result<Self> {
        let init_pass = &passes.expression_types_init;
        let step_pass = &passes.expression_types_step;
        let conditions_compact_expr_pass = &passes.conditions_compact_expr;
        let conditions_compact_stmt_pass = &passes.conditions_compact_stmt;
        let conditions_compact_aggregate_requests_pass =
            &passes.conditions_compact_aggregate_requests;
        let conditions_aggregate_args_pass = &passes.conditions_aggregate_args;
        let conditions_compact_calls_pass = &passes.conditions_compact_calls;
        let conditions_compact_types_pass = &passes.conditions_compact_types;
        let conditions_compact_methods_pass = &passes.conditions_compact_methods;
        let predicate_diagnostics_clear_pass = &passes.semantic_predicate_diagnostics_clear;
        let predicate_diagnostics_claim_pass = &passes.semantic_predicate_diagnostics_claim;
        let predicate_diagnostics_project_pass = &passes.semantic_predicate_diagnostics_project;
        let conditions_compact_predicates_pass = &passes.conditions_compact_predicates;
        let conditions_compact_names_pass = &passes.conditions_compact_names;
        let calls_project_result_instances_pass = &passes.calls_project_result_instances;
        let visible_clear_pass = &passes.visible_clear_resident;
        let visible_mark_pass = &passes.visible_mark_hir_decl_names;
        let visible_scatter_pass = &passes.visible_scatter_hir_decl_records;
        let visible_names_pass = &passes.visible_hir_names;
        let scope_hir_pass = &passes.scope_hir;
        let returns_clear_pass = &passes.returns_clear;
        let returns_mark_pass = &passes.returns_mark;
        let returns_mark_if_pass = &passes.returns_mark_if;
        let returns_validate_pass = &passes.returns_validate;
        let calls_backend_targets_pass = &passes.calls_backend_targets;
        let semantic_calls_project_pass = &passes.semantic_calls_project;
        let semantic_expression_refs_project_pass = &passes.semantic_expression_refs_project;
        let semantic_struct_literal_refs_project_pass =
            &passes.semantic_struct_literal_refs_project;
        let semantic_array_index_refs_project_pass = &passes.semantic_array_index_refs_project;
        let type_instances_struct_init_clear_pass = &passes.type_instances_struct_init_clear;
        let type_instances_struct_init_contexts_pass = &passes.type_instances_struct_init_contexts;
        let type_instances_struct_init_fields_pass = &passes.type_instances_struct_init_fields;
        let type_instances_struct_init_substitute_pass =
            &passes.type_instances_struct_init_substitute;
        let type_instances_validate_aggregate_access_pass =
            &passes.type_instances_validate_aggregate_access;
        let type_instances_member_receivers_pass = &passes.type_instances_member_receivers;
        let type_instances_member_results_pass = &passes.type_instances_member_results;
        let type_instances_member_substitute_pass = &passes.type_instances_member_substitute;
        let type_instances_clear_semantic_type_rows_pass =
            &passes.type_instances_clear_semantic_type_rows;
        let type_instances_mark_semantic_type_rows_pass =
            &passes.type_instances_mark_semantic_type_rows;
        let type_instances_scatter_semantic_type_rows_pass =
            &passes.type_instances_scatter_semantic_type_rows;
        let semantic_artifact_project_pass = &passes.semantic_artifact_project;
        let step_count = pointer_jump_step_count(hir_capacity);
        let build_reflections = BuildGraphReflections {
            semantic_features_collect: &passes.semantic_features_collect.reflection,
            semantic_features_dispatch: &passes.semantic_features_dispatch_args.reflection,
            names_mark: &passes.names_mark_lexemes.reflection,
            names_scatter: &passes.names_scatter_lexemes.reflection,
            names_hash_prepare: &passes.names_hash_prepare.reflection,
            names_hash_insert: &passes.names_hash_insert.reflection,
            names_hash_assign: &passes.names_hash_assign_ids.reflection,
            language_names_clear: &passes.language_names_clear.reflection,
            language_type_codes_clear: &passes.language_type_codes_clear.reflection,
            language_decls_materialize: &passes.language_decls_materialize.reflection,
            conditions_compact_calls: &conditions_compact_calls_pass.reflection,
            conditions_compact_types: &conditions_compact_types_pass.reflection,
            conditions_aggregate_args: &conditions_aggregate_args_pass.reflection,
            calls_mark_array_args: &passes.calls_mark_array_args.reflection,
            calls_validate_array_results: &passes.calls_validate_array_results.reflection,
            calls_project_result_instances: &calls_project_result_instances_pass.reflection,
            calls: CallGraphReflections {
                clear: &passes.calls_clear.reflection,
                clear_entrypoints: &passes.calls_clear_entrypoints.reflection,
                return_refs: &passes.calls_return_refs.reflection,
                entrypoints: &passes.calls_entrypoints.reflection,
                functions: &passes.calls_functions.reflection,
                param_types: &passes.calls_param_types.reflection,
                scatter_params: &passes.calls_scatter_compact_hir_params.reflection,
                intrinsics: &passes.calls_intrinsics.reflection,
                clear_args: &passes.calls_clear_hir_call_args.reflection,
                pack_args: &passes.calls_pack_hir_call_args.reflection,
                mark_args: &passes.calls_mark_compact_hir_call_args.reflection,
                scatter_args: &passes.calls_scatter_compact_hir_call_args.reflection,
                resolve: &passes.calls_resolve.reflection,
                match_args: &passes.calls_match_arg_params_init.reflection,
                collect_args: &passes.calls_collect_row_args.reflection,
                apply_args: &passes.calls_apply_row_args.reflection,
                emit_generic_claims: &passes.calls_emit_generic_claims.reflection,
                clear_generic_claim_type_args: &passes
                    .calls_clear_generic_claim_type_args
                    .reflection,
                validate_generic_claims: &passes.calls_validate_generic_claims.reflection,
                mark_required_generics: &passes.calls_mark_required_generics.reflection,
                validate_required_generics: &passes.calls_validate_required_generics.reflection,
                validate_const_claims: &passes.calls_validate_const_claims.reflection,
            },
            methods_clear: &passes.methods_clear.reflection,
            methods_collect: &passes.methods_collect.reflection,
            methods_attach_metadata: &passes.methods_attach_metadata.reflection,
            methods_bind_self_receivers: &passes.methods_bind_self_receivers.reflection,
            methods_seed_key_order: &passes.methods_seed_key_order.reflection,
            methods_validate_keys: &passes.methods_validate_keys.reflection,
            methods_mark_call_keys: &passes.methods_mark_call_keys.reflection,
            methods_mark_call_return_keys: &passes.methods_mark_call_return_keys.reflection,
            methods_resolve_table: &passes.methods_resolve_table.reflection,
            methods_resolve: &passes.methods_resolve.reflection,
            type_instances_struct_init_clear: &type_instances_struct_init_clear_pass.reflection,
            type_instances_struct_init_contexts: &type_instances_struct_init_contexts_pass
                .reflection,
            type_instances_struct_init_fields: &type_instances_struct_init_fields_pass.reflection,
            type_instances_struct_init_substitute: &type_instances_struct_init_substitute_pass
                .reflection,
            type_instances_validate_aggregate_access:
                &type_instances_validate_aggregate_access_pass.reflection,
            type_instances_member_receivers: &type_instances_member_receivers_pass.reflection,
            type_instances_member_results: &type_instances_member_results_pass.reflection,
            type_instances_member_substitute: &type_instances_member_substitute_pass.reflection,
            type_instances_clear_semantic_type_rows: &type_instances_clear_semantic_type_rows_pass
                .reflection,
            type_instances_mark_semantic_type_rows: &type_instances_mark_semantic_type_rows_pass
                .reflection,
            type_instances_scatter_semantic_type_rows:
                &type_instances_scatter_semantic_type_rows_pass.reflection,
            semantic_array_index_refs: &semantic_array_index_refs_project_pass.reflection,
            type_instances_decl_generic_params: &passes
                .type_instances_decl_generic_params
                .reflection,
            type_instances_sort_generic_params_small: &passes
                .type_instances_sort_generic_params_small
                .reflection,
            type_instances_generic_param_use_slots: &passes
                .type_instances_generic_param_use_slots
                .reflection,
            predicates: Some(PredicateGraphReflections {
                clear_syntax_tokens: &passes.predicates_clear_syntax_tokens.reflection,
                clear_bound_arg_facts: &passes.predicates_clear_bound_arg_facts.reflection,
                collect_bound_arg_facts: &passes.predicates_collect_bound_arg_facts.reflection,
                collect_method_contracts: &passes.predicates_collect_method_contracts.reflection,
                collect: &passes.predicates_collect.reflection,
                validate_bound_args: &passes.predicates_validate_bound_args.reflection,
                collect_impls: &passes.predicates_collect_impls.reflection,
                build_method_owner_ranges: &passes.predicates_build_method_owner_ranges.reflection,
                emit_method_validation_rows: &passes
                    .predicates_emit_method_validation_rows
                    .reflection,
                emit_method_param_validation_rows: &passes
                    .predicates_emit_method_param_validation_rows
                    .reflection,
                validate_method_type_arg_rows: &passes
                    .predicates_validate_method_type_arg_rows
                    .reflection,
                reduce_method_validation_errors: &passes
                    .predicates_reduce_method_validation_errors
                    .reflection,
                count_obligations: &passes.predicates_count_obligations.reflection,
                validate_obligations: &passes.predicates_validate_obligations.reflection,
            }),
        };
        let (graph, resources) = build_graph(
            hir_capacity,
            token_capacity,
            source_file_capacity,
            module_record_capacity,
            call_param_capacity,
            call_arg_capacity,
            generic_claim_capacity,
            predicate_capacity,
            step_count,
            &build_reflections,
        )
        .map_err(anyhow::Error::msg)?;
        let validate = |name, reflection: &std::sync::Arc<crate::reflection::SlangReflection>| {
            graph
                .validate_complete_pass_reflection(
                    graph.pass_id(name).expect("registered compiler graph pass"),
                    reflection,
                )
                .map_err(anyhow::Error::msg)
        };
        for (name, reflection) in [
            (
                TYPE_INSTANCES_MARK_GENERIC_PARAM_RECORDS_PASS,
                &passes.type_instances_mark_generic_param_records.reflection,
            ),
            (
                TYPE_INSTANCES_PROPAGATE_GENERIC_OWNER_A_TO_B_PASS,
                &passes
                    .type_instances_propagate_generic_decl_owner
                    .reflection,
            ),
            (
                TYPE_INSTANCES_PROPAGATE_GENERIC_OWNER_B_TO_A_PASS,
                &passes
                    .type_instances_propagate_generic_decl_owner
                    .reflection,
            ),
            (
                TYPE_INSTANCES_GENERIC_PARAM_SORT_DISPATCH_PASS,
                &passes.names_radix_dispatch_args.reflection,
            ),
            (
                SEMANTIC_STRUCT_LITERAL_REFS_EARLY_PROJECT_PASS,
                &semantic_struct_literal_refs_project_pass.reflection,
            ),
            (
                SEMANTIC_STRUCT_LITERAL_REFS_PROJECT_PASS,
                &semantic_struct_literal_refs_project_pass.reflection,
            ),
            (
                CONDITIONS_COMPACT_AGGREGATE_REQUESTS_PASS,
                &conditions_compact_aggregate_requests_pass.reflection,
            ),
            (
                CALLS_BACKEND_TARGETS_PASS,
                &calls_backend_targets_pass.reflection,
            ),
            (
                SEMANTIC_CALLS_PROJECT_PASS,
                &semantic_calls_project_pass.reflection,
            ),
            (
                SEMANTIC_EXPRESSION_REFS_PROJECT_PASS,
                &semantic_expression_refs_project_pass.reflection,
            ),
            (
                SEMANTIC_ARTIFACT_PROJECT_PASS,
                &semantic_artifact_project_pass.reflection,
            ),
            (VISIBLE_CLEAR_PASS, &visible_clear_pass.reflection),
            (VISIBLE_MARK_PASS, &visible_mark_pass.reflection),
            (VISIBLE_SCATTER_PASS, &visible_scatter_pass.reflection),
            (VISIBLE_NAMES_PASS, &visible_names_pass.reflection),
            (SCOPE_HIR_PASS, &scope_hir_pass.reflection),
            (RETURNS_CLEAR_PASS, &returns_clear_pass.reflection),
            (RETURNS_MARK_PASS, &returns_mark_pass.reflection),
            (RETURNS_MARK_IF_PASS, &returns_mark_if_pass.reflection),
            (RETURNS_VALIDATE_PASS, &returns_validate_pass.reflection),
            (
                CONDITIONS_COMPACT_METHODS_PASS,
                &conditions_compact_methods_pass.reflection,
            ),
            (
                PREDICATE_DIAGNOSTICS_CLEAR_PASS,
                &predicate_diagnostics_clear_pass.reflection,
            ),
            (
                PREDICATE_DIAGNOSTICS_CLAIM_PASS,
                &predicate_diagnostics_claim_pass.reflection,
            ),
            (
                PREDICATE_DIAGNOSTICS_PROJECT_PASS,
                &predicate_diagnostics_project_pass.reflection,
            ),
            (
                CONDITIONS_COMPACT_PREDICATES_PASS,
                &conditions_compact_predicates_pass.reflection,
            ),
            (
                CONDITIONS_COMPACT_NAMES_PASS,
                &conditions_compact_names_pass.reflection,
            ),
            (INIT_PASS, &init_pass.reflection),
            (STEP_A_TO_B_PASS, &step_pass.reflection),
            (STEP_B_TO_A_PASS, &step_pass.reflection),
            (STEP_A_TO_B_TAIL_PASS, &step_pass.reflection),
            (
                CONDITIONS_COMPACT_EXPR_PASS,
                &conditions_compact_expr_pass.reflection,
            ),
            (
                CONDITIONS_COMPACT_STMT_PASS,
                &conditions_compact_stmt_pass.reflection,
            ),
            (
                CALLS_RESULT_INSTANCE_PROJECT.name,
                &calls_project_result_instances_pass.reflection,
            ),
        ] {
            if graph.pass_id(name).is_some() {
                validate(name, reflection)?;
            }
        }
        for (sort, histogram, scatter) in [
            (
                GENERIC_PARAMETER_RADIX_SORTS.key,
                &passes.type_instances_sort_generic_param_keys.reflection,
                &passes
                    .type_instances_sort_generic_param_keys_scatter
                    .reflection,
            ),
            (
                GENERIC_PARAMETER_RADIX_SORTS.slot,
                &passes.type_instances_sort_generic_param_slots.reflection,
                &passes
                    .type_instances_sort_generic_param_slots_scatter
                    .reflection,
            ),
        ] {
            for step in [
                sort.passes.order_to_temporary,
                sort.passes.temporary_to_order,
            ] {
                if graph.pass_id(step.histogram).is_none() {
                    continue;
                }
                validate(step.histogram, histogram)?;
                validate(
                    step.bucket_prefix,
                    &passes.names_radix_bucket_prefix.reflection,
                )?;
                validate(
                    step.bucket_bases,
                    &passes.names_radix_bucket_bases.reflection,
                )?;
                validate(step.scatter, scatter)?;
            }
        }

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
        let token_rows = token_capacity.max(1) as usize;
        let type_expr_ref_tag = alias_u32(resources.type_expr_ref_tag, token_rows)?;
        let type_expr_ref_payload = alias_u32(resources.type_expr_ref_payload, token_rows)?;
        let type_generic_param_slot_by_token =
            alias_u32(resources.type_generic_param_slot_by_token, token_rows)?;
        let type_const_param_slot_by_token =
            alias_u32(resources.type_const_param_slot_by_token, token_rows)?;
        let type_decl_hir_node_by_token =
            alias_u32(resources.type_decl_hir_node_by_token, token_rows)?;
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
        let claim_rows = generic_claim_capacity.max(1) as usize;
        let claim_blocks = generic_claim_capacity.max(1).div_ceil(256) as usize;
        let claim_histogram_rows = claim_blocks * NAME_RADIX_BUCKETS as usize;
        let predicate_rows = predicate_capacity.max(1) as usize;
        let predicate_radix_rows =
            predicate_capacity.max(1).div_ceil(256) as usize * NAME_RADIX_BUCKETS as usize;
        let predicate_blocks = predicate_capacity.max(1).div_ceil(256) as usize;
        let predicate_syntax_token = alias_u32(resources.predicate_syntax_token, predicate_rows)?;
        let generic_decl_owner_by_node_a =
            alias_u32(resources.generic_decl_owner_by_node_a, hir_rows)?;
        let generic_decl_owner_by_node_b =
            alias_u32(resources.generic_decl_owner_by_node_b, hir_rows)?;
        let predicate_bound_list_by_node_a =
            alias_u32(resources.predicate_bound_list_by_node_a, hir_rows)?;
        let predicate_bound_list_by_node_b =
            alias_u32(resources.predicate_bound_list_by_node_b, hir_rows)?;
        let generic_decl_parent_jump_a = alias_u32(resources.generic_decl_parent_jump_a, hir_rows)?;
        let generic_decl_parent_jump_b = alias_u32(resources.generic_decl_parent_jump_b, hir_rows)?;
        let type_decl_generic_param_count =
            alias_u32(resources.type_decl_generic_param_count, token_rows)?;
        let type_decl_generic_param_count_by_owner_token = alias_u32(
            resources.type_decl_generic_param_count_by_owner_token,
            token_rows,
        )?;
        let type_decl_const_param_count_by_owner_token = alias_u32(
            resources.type_decl_const_param_count_by_owner_token,
            token_rows,
        )?;
        let generic_param_count_out = alias_u32(resources.generic_param_count_out, 1)?;
        let generic_param_owner_token = alias_u32(resources.generic_param_owner_token, token_rows)?;
        let generic_param_name_id = alias_u32(resources.generic_param_name_id, token_rows)?;
        let generic_param_token = alias_u32(resources.generic_param_token, token_rows)?;
        let generic_param_node = alias_u32(resources.generic_param_node, token_rows)?;
        let generic_param_kind = alias_u32(resources.generic_param_kind, token_rows)?;
        let generic_param_key_order = alias_u32(resources.generic_param_key_order, token_rows)?;
        let generic_param_key_order_tmp = resources
            .generic_param_key_order_tmp
            .map(|resource| alias_u32(resource, token_rows))
            .transpose()?;
        let generic_param_slot_order = alias_u32(resources.generic_param_slot_order, token_rows)?;
        let generic_param_slot_order_tmp = resources
            .generic_param_slot_order_tmp
            .map(|resource| alias_u32(resource, token_rows))
            .transpose()?;
        let generic_param_radix_rows =
            token_capacity.max(1).div_ceil(256) as usize * NAME_RADIX_BUCKETS as usize;
        let generic_param_slot_radix_block_histogram = resources
            .generic_param_slot_radix_block_histogram
            .map(|resource| alias_u32(resource, generic_param_radix_rows))
            .transpose()?;
        let generic_param_slot_radix_block_bucket_prefix = resources
            .generic_param_slot_radix_block_bucket_prefix
            .map(|resource| alias_u32(resource, generic_param_radix_rows))
            .transpose()?;
        let generic_param_slot_radix_bucket_total = resources
            .generic_param_slot_radix_bucket_total
            .map(|resource| alias_u32(resource, NAME_RADIX_BUCKETS as usize))
            .transpose()?;
        let generic_param_slot_radix_bucket_base = resources
            .generic_param_slot_radix_bucket_base
            .map(|resource| alias_u32(resource, NAME_RADIX_BUCKETS as usize))
            .transpose()?;
        let predicate_owner_node = alias_u32(resources.predicate_owner_node, predicate_rows)?;
        let predicate_subject_token = alias_u32(resources.predicate_subject_token, predicate_rows)?;
        let predicate_bound_token = alias_u32(resources.predicate_bound_token, predicate_rows)?;
        let predicate_bound_decl_id = alias_u32(resources.predicate_bound_decl_id, predicate_rows)?;
        let predicate_bound_arg_count =
            alias_u32(resources.predicate_bound_arg_count, predicate_rows)?;
        let predicate_bound_first_arg_token =
            alias_u32(resources.predicate_bound_first_arg_token, predicate_rows)?;
        let predicate_bound_second_arg_token =
            alias_u32(resources.predicate_bound_second_arg_token, predicate_rows)?;
        let predicate_status = alias_u32(resources.predicate_status, predicate_rows)?;
        let predicate_method_contract_owner_hir = alias_u32(
            resources.predicate_method_contract_owner_hir,
            predicate_rows,
        )?;
        let predicate_method_contract_name_token = alias_u32(
            resources.predicate_method_contract_name_token,
            predicate_rows,
        )?;
        let predicate_method_contract_name_id =
            alias_u32(resources.predicate_method_contract_name_id, predicate_rows)?;
        let predicate_method_contract_param_count = alias_u32(
            resources.predicate_method_contract_param_count,
            predicate_rows,
        )?;
        let predicate_method_contract_return_type_node = alias_u32(
            resources.predicate_method_contract_return_type_node,
            predicate_rows,
        )?;
        let predicate_method_contract_visibility = alias_u32(
            resources.predicate_method_contract_visibility,
            predicate_rows,
        )?;
        let predicate_method_contract_status =
            alias_u32(resources.predicate_method_contract_status, predicate_rows)?;
        let predicate_method_contract_param_type_node = alias_u32(
            resources.predicate_method_contract_param_type_node,
            predicate_rows,
        )?;
        let predicate_method_contract_key_order = alias_u32(
            resources.predicate_method_contract_key_order,
            predicate_rows,
        )?;
        let predicate_method_contract_key_order_tmp = alias_u32(
            resources.predicate_method_contract_key_order_tmp,
            predicate_rows,
        )?;
        let predicate_method_param_key_order =
            alias_u32(resources.predicate_method_param_key_order, predicate_rows)?;
        let predicate_method_param_key_order_tmp = alias_u32(
            resources.predicate_method_param_key_order_tmp,
            predicate_rows,
        )?;
        let predicate_method_contract_owner_range_first = alias_u32(
            resources.predicate_method_contract_owner_range_first,
            predicate_rows,
        )?;
        let predicate_method_contract_owner_range_count = alias_u32(
            resources.predicate_method_contract_owner_range_count,
            predicate_rows,
        )?;
        let predicate_method_validation_owner_node = alias_u32(
            resources.predicate_method_validation_owner_node,
            predicate_rows,
        )?;
        let predicate_method_validation_peer_node = alias_u32(
            resources.predicate_method_validation_peer_node,
            predicate_rows,
        )?;
        let predicate_method_validation_status =
            alias_u32(resources.predicate_method_validation_status, predicate_rows)?;
        let predicate_method_validation_detail_token = alias_u32(
            resources.predicate_method_validation_detail_token,
            predicate_rows,
        )?;
        let predicate_method_validation_first_error_row = alias_u32(
            resources.predicate_method_validation_first_error_row,
            predicate_rows,
        )?;
        let predicate_owner_key_order =
            alias_u32(resources.predicate_owner_key_order, predicate_rows)?;
        let predicate_owner_key_order_tmp =
            alias_u32(resources.predicate_owner_key_order_tmp, predicate_rows)?;
        let predicate_impl_key_order =
            alias_u32(resources.predicate_impl_key_order, predicate_rows)?;
        let predicate_impl_key_order_tmp =
            alias_u32(resources.predicate_impl_key_order_tmp, predicate_rows)?;
        let predicate_key_radix_block_histogram = alias_u32(
            resources.predicate_key_radix_block_histogram,
            predicate_radix_rows,
        )?;
        let predicate_key_radix_block_bucket_prefix = alias_u32(
            resources.predicate_key_radix_block_bucket_prefix,
            predicate_radix_rows,
        )?;
        let predicate_key_radix_bucket_total = alias_u32(
            resources.predicate_key_radix_bucket_total,
            NAME_RADIX_BUCKETS as usize,
        )?;
        let predicate_key_radix_bucket_base = alias_u32(
            resources.predicate_key_radix_bucket_base,
            NAME_RADIX_BUCKETS as usize,
        )?;
        let predicate_obligation_count_by_call =
            alias_u32(resources.predicate_obligation_count_by_call, predicate_rows)?;
        let predicate_obligation_prefix_by_call = alias_u32(
            resources.predicate_obligation_prefix_by_call,
            predicate_rows,
        )?;
        let predicate_obligation_scan_local_prefix = alias_u32(
            resources.predicate_obligation_scan_local_prefix,
            predicate_rows,
        )?;
        let predicate_obligation_scan_block_sum = alias_u32(
            resources.predicate_obligation_scan_block_sum,
            predicate_blocks,
        )?;
        let predicate_obligation_scan_prefix_a = alias_u32(
            resources.predicate_obligation_scan_prefix_a,
            predicate_blocks,
        )?;
        let predicate_obligation_scan_prefix_b = alias_u32(
            resources.predicate_obligation_scan_prefix_b,
            predicate_blocks,
        )?;
        let predicate_obligation_pair_total =
            alias_u32(resources.predicate_obligation_pair_total, 1)?;
        let predicate_obligation_pair_dispatch_args =
            alias_u32(resources.predicate_obligation_pair_dispatch_args, 3)?;
        let alias_i32 = |resource, count| {
            workspace
                .alias(&graph, resource, count)
                .map_err(anyhow::Error::msg)
        };
        let if_delta = alias_i32(resources.if_delta, token_rows + 1)?;
        let if_depth_inblock = alias_i32(resources.if_depth_inblock, token_rows)?;
        let if_block_sum = alias_i32(resources.if_block_sum, token_blocks)?;
        let if_prefix_a = alias_i32(resources.if_prefix_a, token_blocks)?;
        let if_prefix_b = alias_i32(resources.if_prefix_b, token_blocks)?;
        let if_block_prefix = alias_i32(resources.if_block_prefix, token_blocks)?;
        let if_depth = alias_i32(resources.if_depth, token_rows)?;
        let enclosing_fn = alias_u32(resources.enclosing_fn, token_rows)?;
        let enclosing_fn_end = alias_u32(resources.enclosing_fn_end, token_rows)?;
        let fn_event_value = alias_u32(resources.fn_event_value, token_rows + 1)?;
        let fn_event_end = alias_u32(resources.fn_event_end, token_rows + 1)?;
        let fn_event_index = alias_u32(resources.fn_event_index, token_rows + 1)?;
        let fn_event_inblock = alias_u32(resources.fn_event_inblock, token_rows)?;
        let fn_block_sum = alias_u32(resources.fn_block_sum, token_blocks)?;
        let fn_prefix_a = alias_u32(resources.fn_prefix_a, token_blocks)?;
        let fn_prefix_b = alias_u32(resources.fn_prefix_b, token_blocks)?;
        let fn_block_prefix = alias_u32(resources.fn_block_prefix, token_blocks)?;
        let member_result_context_instance =
            alias_u32(resources.member_result_context_instance, token_rows)?;
        let member_result_ref_tag = alias_u32(resources.member_result_ref_tag, token_rows)?;
        let member_result_ref_payload = alias_u32(resources.member_result_ref_payload, token_rows)?;
        let member_result_field_ordinal =
            alias_u32(resources.member_result_field_ordinal, token_rows)?;
        let member_result_field_node = alias_u32(resources.member_result_field_node, token_rows)?;
        let struct_init_field_context_instance =
            alias_u32(resources.struct_init_field_context_instance, token_rows)?;
        let struct_init_field_expected_ref_tag =
            alias_u32(resources.struct_init_field_expected_ref_tag, token_rows)?;
        let struct_init_field_expected_ref_payload =
            alias_u32(resources.struct_init_field_expected_ref_payload, token_rows)?;
        let struct_init_field_ordinal = alias_u32(resources.struct_init_field_ordinal, token_rows)?;
        let struct_init_field_ordinal_by_node =
            alias_u32(resources.struct_init_field_ordinal_by_node, hir_rows)?;
        let struct_init_field_decl_node_by_node =
            alias_u32(resources.struct_init_field_decl_node_by_node, hir_rows)?;
        let struct_init_field_ordinal_by_row =
            alias_u32(resources.struct_init_field_ordinal_by_row, hir_rows)?;
        let struct_init_field_decl_token_by_row =
            alias_u32(resources.struct_init_field_decl_token_by_row, hir_rows)?;
        let struct_field_key_order = alias_u32(resources.struct_field_key_order, token_rows)?;
        let struct_field_key_order_tmp =
            alias_u32(resources.struct_field_key_order_tmp, token_rows)?;
        let struct_field_key_radix_dispatch_args =
            alias_u32(resources.struct_field_key_radix_dispatch_args, 3)?;
        let struct_field_key_radix_histogram_len =
            token_rows.div_ceil(256) * NAME_RADIX_BUCKETS as usize;
        let struct_field_key_radix_block_histogram = alias_u32(
            resources.struct_field_key_radix_block_histogram,
            struct_field_key_radix_histogram_len,
        )?;
        let struct_field_key_radix_block_bucket_prefix = alias_u32(
            resources.struct_field_key_radix_block_bucket_prefix,
            struct_field_key_radix_histogram_len,
        )?;
        let struct_field_key_radix_bucket_total = alias_u32(
            resources.struct_field_key_radix_bucket_total,
            NAME_RADIX_BUCKETS as usize,
        )?;
        let struct_field_key_radix_bucket_base = alias_u32(
            resources.struct_field_key_radix_bucket_base,
            NAME_RADIX_BUCKETS as usize,
        )?;
        let struct_lit_context_decl_token =
            alias_u32(resources.struct_lit_context_decl_token, hir_rows)?;
        let struct_lit_context_instance =
            alias_u32(resources.struct_lit_context_instance, hir_rows)?;
        let array_element_struct_literal_node =
            alias_u32(resources.array_element_struct_literal_node, hir_rows)?;
        let member_next_node = alias_u32(resources.member_next_node, hir_rows)?;
        let fn_entrypoint_tag = alias_u32(resources.fn_entrypoint_tag, token_rows.max(hir_rows))?;
        let call_fn_index = alias_u32(resources.call_fn_index, token_rows)?;
        let call_return_type = alias_u32(resources.call_return_type, token_rows)?;
        let call_return_type_token = alias_u32(resources.call_return_type_token, token_rows)?;
        let method_decl_method_row = alias_u32(resources.method_decl_method_row, token_rows)?;
        let method_decl_receiver_ref_tag =
            alias_u32(resources.method_decl_receiver_ref_tag, token_rows)?;
        let method_decl_receiver_ref_payload =
            alias_u32(resources.method_decl_receiver_ref_payload, token_rows)?;
        let method_decl_module_id = alias_u32(resources.method_decl_module_id, token_rows)?;
        let method_decl_name_token = alias_u32(resources.method_decl_name_token, token_rows)?;
        let method_decl_name_id = alias_u32(resources.method_decl_name_id, token_rows)?;
        let method_decl_param_offset = alias_u32(resources.method_decl_param_offset, token_rows)?;
        let method_decl_receiver_mode = alias_u32(resources.method_decl_receiver_mode, token_rows)?;
        let method_decl_visibility = alias_u32(resources.method_decl_visibility, token_rows)?;
        let method_decl_signature_flags =
            alias_u32(resources.method_decl_signature_flags, token_rows)?;
        let method_call_receiver_ref_tag =
            alias_u32(resources.method_call_receiver_ref_tag, token_rows)?;
        let method_call_receiver_ref_payload =
            alias_u32(resources.method_call_receiver_ref_payload, token_rows)?;
        let method_call_name_id = alias_u32(resources.method_call_name_id, token_rows)?;
        let method_call_site_module_id =
            alias_u32(resources.method_call_site_module_id, token_rows)?;
        let type_instance_kind = alias_u32(resources.type_instance_kind, token_rows)?;
        let type_instance_head_token = alias_u32(resources.type_instance_head_token, token_rows)?;
        let type_instance_state = alias_u32(resources.type_instance_state, token_rows)?;
        let type_instance_elem_ref_tag =
            alias_u32(resources.type_instance_elem_ref_tag, token_rows)?;
        let type_instance_elem_ref_payload =
            alias_u32(resources.type_instance_elem_ref_payload, token_rows)?;
        let type_instance_len_kind = alias_u32(resources.type_instance_len_kind, token_rows)?;
        let type_instance_len_payload = alias_u32(resources.type_instance_len_payload, token_rows)?;
        let type_instance_arg_start = alias_u32(resources.type_instance_arg_start, token_rows)?;
        let type_instance_arg_count = alias_u32(resources.type_instance_arg_count, token_rows)?;
        let type_instance_arg_ref_tag =
            alias_u32(resources.type_instance_arg_ref_tag, token_rows * 4)?;
        let type_instance_arg_ref_payload =
            alias_u32(resources.type_instance_arg_ref_payload, token_rows * 4)?;
        let type_instance_arg_row_start =
            alias_u32(resources.type_instance_arg_row_start, token_rows)?;
        let type_instance_arg_row_count_out =
            alias_u32(resources.type_instance_arg_row_count_out, 1)?;
        let type_instance_arg_row_ref_tag =
            alias_u32(resources.type_instance_arg_row_ref_tag, hir_rows)?;
        let type_instance_arg_row_ref_payload =
            alias_u32(resources.type_instance_arg_row_ref_payload, hir_rows)?;
        let type_instance_arg_hash = alias_u32(resources.type_instance_arg_hash, token_rows)?;
        let method_key_to_fn_token = alias_u32(resources.method_key_to_fn_token, token_rows)?;
        let method_key_order_tmp = alias_u32(resources.method_key_order_tmp, token_rows)?;
        let method_key_status = alias_u32(resources.method_key_status, token_rows)?;
        let method_key_duplicate_of = alias_u32(resources.method_key_duplicate_of, token_rows)?;
        let method_key_radix_rows = token_rows.div_ceil(256) * NAME_RADIX_BUCKETS as usize;
        let method_key_radix_block_histogram = alias_u32(
            resources.method_key_radix_block_histogram,
            method_key_radix_rows,
        )?;
        let method_key_radix_block_bucket_prefix = alias_u32(
            resources.method_key_radix_block_bucket_prefix,
            method_key_radix_rows,
        )?;
        let method_key_radix_bucket_total = alias_u32(
            resources.method_key_radix_bucket_total,
            NAME_RADIX_BUCKETS as usize,
        )?;
        let method_key_radix_bucket_base = alias_u32(
            resources.method_key_radix_bucket_base,
            NAME_RADIX_BUCKETS as usize,
        )?;
        let type_instance_arg_row_scan_local_prefix = alias_u32(
            resources.type_instance_arg_row_scan_local_prefix,
            token_rows,
        )?;
        let type_instance_arg_row_scan_block_sum =
            alias_u32(resources.type_instance_arg_row_scan_block_sum, token_blocks)?;
        let type_instance_arg_row_scan_prefix_a =
            alias_u32(resources.type_instance_arg_row_scan_prefix_a, token_blocks)?;
        let type_instance_arg_row_scan_prefix_b =
            alias_u32(resources.type_instance_arg_row_scan_prefix_b, token_blocks)?;
        let aggregate_compare_scan_input =
            alias_u32(resources.aggregate_compare_scan_input, hir_rows)?;
        let aggregate_compare_expected_instance =
            alias_u32(resources.aggregate_compare_expected_instance, hir_rows)?;
        let aggregate_compare_actual_instance =
            alias_u32(resources.aggregate_compare_actual_instance, hir_rows)?;
        let aggregate_compare_error_token =
            alias_u32(resources.aggregate_compare_error_token, hir_rows)?;
        let aggregate_compare_error_detail =
            alias_u32(resources.aggregate_compare_error_detail, hir_rows)?;
        let aggregate_compare_prefix = alias_u32(resources.aggregate_compare_prefix, hir_rows)?;
        let aggregate_compare_count_out = alias_u32(resources.aggregate_compare_count_out, 1)?;
        let aggregate_compare_scan_local_prefix =
            alias_u32(resources.aggregate_compare_scan_local_prefix, hir_rows)?;
        let aggregate_compare_scan_block_sum =
            alias_u32(resources.aggregate_compare_scan_block_sum, hir_blocks)?;
        let aggregate_compare_scan_prefix_a =
            alias_u32(resources.aggregate_compare_scan_prefix_a, hir_blocks)?;
        let aggregate_compare_scan_prefix_b =
            alias_u32(resources.aggregate_compare_scan_prefix_b, hir_blocks)?;
        let aggregate_compare_dispatch_args =
            alias_u32(resources.aggregate_compare_dispatch_args, 3)?;
        let type_subtree_compare_scan_input =
            alias_u32(resources.type_subtree_compare_scan_input, hir_rows)?;
        let type_subtree_compare_prefix =
            alias_u32(resources.type_subtree_compare_prefix, hir_rows)?;
        let type_subtree_compare_count_out =
            alias_u32(resources.type_subtree_compare_count_out, 1)?;
        let type_subtree_compare_left_root =
            alias_u32(resources.type_subtree_compare_left_root, hir_rows)?;
        let type_subtree_compare_right_root =
            alias_u32(resources.type_subtree_compare_right_root, hir_rows)?;
        let type_subtree_compare_error_token =
            alias_u32(resources.type_subtree_compare_error_token, hir_rows)?;
        let type_subtree_compare_error_detail =
            alias_u32(resources.type_subtree_compare_error_detail, hir_rows)?;
        let type_subtree_compare_dispatch_args =
            alias_u32(resources.type_subtree_compare_dispatch_args, 3)?;
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
        let generic_claim_callee = alias_u32(resources.generic_claim_callee, claim_rows)?;
        let generic_claim_slot = alias_u32(resources.generic_claim_slot, claim_rows)?;
        let generic_claim_type = alias_u32(resources.generic_claim_type, claim_rows)?;
        let generic_claim_ref_tag = alias_u32(resources.generic_claim_ref_tag, claim_rows)?;
        let generic_claim_ref_payload = alias_u32(resources.generic_claim_ref_payload, claim_rows)?;
        let generic_claim_arg_row = alias_u32(resources.generic_claim_arg_row, claim_rows)?;
        let generic_claim_order = alias_u32(resources.generic_claim_order, claim_rows)?;
        let generic_claim_order_tmp = alias_u32(resources.generic_claim_order_tmp, claim_rows)?;
        let generic_claim_radix_dispatch_args =
            alias_u32(resources.generic_claim_radix_dispatch_args, 3)?;
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
        let const_claim_callee = alias_u32(resources.const_claim_callee, call_arg_rows)?;
        let const_claim_slot = alias_u32(resources.const_claim_slot, call_arg_rows)?;
        let const_claim_len = alias_u32(resources.const_claim_len, call_arg_rows)?;
        let const_claim_order = alias_u32(resources.const_claim_order, call_arg_rows)?;
        let const_claim_order_tmp = alias_u32(resources.const_claim_order_tmp, call_arg_rows)?;
        let const_claim_radix_dispatch_args =
            alias_u32(resources.const_claim_radix_dispatch_args, 3)?;
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
        let semantic_function_return_type_by_hir =
            alias_u32(resources.semantic_function_return_type_by_hir, hir_rows)?;
        let semantic_function_entrypoint_by_hir =
            alias_u32(resources.semantic_function_entrypoint_by_hir, hir_rows)?;
        let semantic_function_host_service_by_hir =
            alias_u32(resources.semantic_function_host_service_by_hir, hir_rows)?;
        let semantic_control_depth_by_hir =
            alias_u32(resources.semantic_control_depth_by_hir, hir_rows)?;
        let semantic_calls_by_hir = workspace
            .alias(&graph, resources.semantic_calls_by_hir, hir_rows)
            .map_err(anyhow::Error::msg)?;
        let semantic_expr_ref_tag_by_hir =
            alias_u32(resources.semantic_expr_ref_tag_by_hir, hir_rows)?;
        let semantic_expr_ref_payload_by_hir =
            alias_u32(resources.semantic_expr_ref_payload_by_hir, hir_rows)?;
        let semantic_array_length_by_hir =
            alias_u32(resources.semantic_array_length_by_hir, hir_rows)?;
        let semantic_member_field_ordinal_by_hir =
            alias_u32(resources.semantic_member_field_ordinal_by_hir, hir_rows)?;
        let type_semantic_row_by_token =
            alias_u32(resources.type_semantic_row_by_token, token_rows)?;
        let type_semantic_scan_input = alias_u32(resources.type_semantic_scan_input, hir_rows)?;
        let type_semantic_prefix = alias_u32(resources.type_semantic_prefix, hir_rows)?;
        let type_semantic_count_out = alias_u32(resources.type_semantic_count_out, 1)?;
        let type_semantic_row_by_ordinal =
            alias_u32(resources.type_semantic_row_by_ordinal, hir_rows)?;
        let compact_predicate_diagnostic_facts = alias_u32(
            resources.compact_predicate_diagnostic_facts,
            hir_rows.saturating_mul(8),
        )?;
        let return_fn_flags = alias_u32(resources.return_fn_flags, hir_rows)?;
        let return_block_flags = alias_u32(resources.return_block_flags, hir_rows)?;
        let alias_named_u32 = |name, count| {
            workspace
                .alias_named::<u32>(&graph, name, count)
                .map_err(anyhow::Error::msg)
        };
        let call_param_rows = call_param_capacity.max(1) as usize;
        let call_arg_rows = call_arg_capacity.max(1) as usize;
        let call_param_cache_rows = token_rows.saturating_mul(CALL_PARAM_CACHE_STRIDE);
        let calls = TypeCheckCallBuffers {
            fn_start_token_by_decl_token: alias_named_u32(
                "fn_start_token_by_decl_token",
                token_rows,
            )?,
            backend_call_fn_index: alias_named_u32("backend_call_fn_index", token_rows)?,
            call_intrinsic_tag: alias_named_u32("call_intrinsic_tag", token_rows)?,
            call_param_count: alias_named_u32("call_param_count", token_rows)?,
            call_param_type: alias_named_u32("call_param_type", call_param_cache_rows)?,
            call_param_ref_tag: alias_named_u32("call_param_ref_tag", call_param_cache_rows)?,
            call_param_ref_payload: alias_named_u32(
                "call_param_ref_payload",
                call_param_cache_rows,
            )?,
            call_generic_slot_type: alias_named_u32(
                "call_generic_slot_type",
                call_param_cache_rows,
            )?,
            call_generic_slot_ordinal: alias_named_u32(
                "call_generic_slot_ordinal",
                call_param_cache_rows,
            )?,
            call_const_slot_len: alias_named_u32("call_const_slot_len", call_param_cache_rows)?,
            call_param_row_count_out: alias_named_u32("call_param_row_count_out", 1)?,
            call_param_row_flag: alias_named_u32("call_param_row_flag", call_param_rows)?,
            call_param_row_node_type: alias_named_u32("call_param_row_node_type", call_param_rows)?,
            call_param_row_node_ref_tag: alias_named_u32(
                "call_param_row_node_ref_tag",
                call_param_rows,
            )?,
            call_param_row_node_ref_payload: alias_named_u32(
                "call_param_row_node_ref_payload",
                call_param_rows,
            )?,
            call_param_row_node: alias_named_u32("call_param_row_node", call_param_rows)?,
            call_param_row_fn_token: alias_named_u32("call_param_row_fn_token", call_param_rows)?,
            call_param_row_ordinal: alias_named_u32("call_param_row_ordinal", call_param_rows)?,
            call_param_row_type: alias_named_u32("call_param_row_type", call_param_rows)?,
            call_param_row_ref_tag: alias_named_u32("call_param_row_ref_tag", call_param_rows)?,
            call_param_row_ref_payload: alias_named_u32(
                "call_param_row_ref_payload",
                call_param_rows,
            )?,
            call_param_row_start: alias_named_u32("call_param_row_start", token_rows)?,
            call_param_row_count: alias_named_u32("call_param_row_count", token_rows)?,
            call_arg_record: alias_named_u32("call_arg_record", token_rows.saturating_mul(4))?,
            call_arg_row_node: alias_named_u32("call_arg_row_node", call_arg_rows)?,
            call_arg_row_call_node: alias_named_u32("call_arg_row_call_node", call_arg_rows)?,
            call_arg_row_ordinal: alias_named_u32("call_arg_row_ordinal", call_arg_rows)?,
            call_arg_row_start: alias_named_u32("call_arg_row_start", hir_rows)?,
            call_arg_row_count: alias_named_u32("call_arg_row_count", hir_rows)?,
            function_lookup_key: alias_named_u32(
                "function_lookup_key",
                token_rows.saturating_mul(2),
            )?,
            function_lookup_fn: alias_named_u32(
                "function_lookup_fn",
                token_rows.saturating_mul(2),
            )?,
            fn_return_ref_tag: alias_named_u32("fn_return_ref_tag", token_rows)?,
            fn_return_ref_payload: alias_named_u32("fn_return_ref_payload", token_rows)?,
        };
        let allocations = workspace.allocations();
        let relation_bindings = [
            BoundGraphResource::buffer(
                "call_arg_param_row",
                resources.call_arg_param_row,
                &call_arg_param_row,
            ),
            BoundGraphResource::buffer(
                "semantic_expr_ref_tag_by_hir",
                resources.semantic_expr_ref_tag_by_hir,
                &semantic_expr_ref_tag_by_hir,
            ),
            BoundGraphResource::buffer(
                "semantic_expr_ref_payload_by_hir",
                resources.semantic_expr_ref_payload_by_hir,
                &semantic_expr_ref_payload_by_hir,
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
                "call_generic_claim_callee",
                resources.generic_claim_callee,
                &generic_claim_callee,
            ),
            BoundGraphResource::buffer(
                "call_generic_claim_slot",
                resources.generic_claim_slot,
                &generic_claim_slot,
            ),
            BoundGraphResource::buffer(
                "call_generic_claim_type",
                resources.generic_claim_type,
                &generic_claim_type,
            ),
            BoundGraphResource::buffer(
                "call_generic_claim_ref_tag",
                resources.generic_claim_ref_tag,
                &generic_claim_ref_tag,
            ),
            BoundGraphResource::buffer(
                "call_generic_claim_ref_payload",
                resources.generic_claim_ref_payload,
                &generic_claim_ref_payload,
            ),
            BoundGraphResource::buffer(
                "call_generic_claim_arg_row",
                resources.generic_claim_arg_row,
                &generic_claim_arg_row,
            ),
            BoundGraphResource::buffer(
                "call_generic_claim_order",
                resources.generic_claim_order,
                &generic_claim_order,
            ),
            BoundGraphResource::buffer(
                "type_instance_arg_start",
                resources.type_instance_arg_start,
                &type_instance_arg_start,
            ),
            BoundGraphResource::buffer(
                "type_instance_arg_count",
                resources.type_instance_arg_count,
                &type_instance_arg_count,
            ),
            BoundGraphResource::buffer(
                "type_instance_kind",
                resources.type_instance_kind,
                &type_instance_kind,
            ),
            BoundGraphResource::buffer(
                "type_instance_arg_ref_tag",
                resources.type_instance_arg_ref_tag,
                &type_instance_arg_ref_tag,
            ),
            BoundGraphResource::buffer(
                "type_instance_arg_ref_payload",
                resources.type_instance_arg_ref_payload,
                &type_instance_arg_ref_payload,
            ),
            BoundGraphResource::buffer(
                "type_instance_arg_row_start",
                resources.type_instance_arg_row_start,
                &type_instance_arg_row_start,
            ),
            BoundGraphResource::buffer(
                "type_instance_arg_row_count_out",
                resources.type_instance_arg_row_count_out,
                &type_instance_arg_row_count_out,
            ),
            BoundGraphResource::buffer(
                "type_instance_arg_row_ref_tag",
                resources.type_instance_arg_row_ref_tag,
                &type_instance_arg_row_ref_tag,
            ),
            BoundGraphResource::buffer(
                "type_instance_arg_row_ref_payload",
                resources.type_instance_arg_row_ref_payload,
                &type_instance_arg_row_ref_payload,
            ),
            BoundGraphResource::buffer(
                "type_instance_head_token",
                resources.type_instance_head_token,
                &type_instance_head_token,
            ),
            BoundGraphResource::buffer(
                "type_instance_state",
                resources.type_instance_state,
                &type_instance_state,
            ),
            BoundGraphResource::buffer(
                "type_instance_elem_ref_tag",
                resources.type_instance_elem_ref_tag,
                &type_instance_elem_ref_tag,
            ),
            BoundGraphResource::buffer(
                "type_instance_elem_ref_payload",
                resources.type_instance_elem_ref_payload,
                &type_instance_elem_ref_payload,
            ),
            BoundGraphResource::buffer(
                "type_instance_len_kind",
                resources.type_instance_len_kind,
                &type_instance_len_kind,
            ),
            BoundGraphResource::buffer(
                "type_instance_len_payload",
                resources.type_instance_len_payload,
                &type_instance_len_payload,
            ),
            BoundGraphResource::buffer(
                "type_instance_arg_hash",
                resources.type_instance_arg_hash,
                &type_instance_arg_hash,
            ),
            BoundGraphResource::buffer(
                "method_key_to_fn_token",
                resources.method_key_to_fn_token,
                &method_key_to_fn_token,
            ),
            BoundGraphResource::buffer(
                "sorted_method_key_order",
                resources.method_key_to_fn_token,
                &method_key_to_fn_token,
            ),
            BoundGraphResource::buffer(
                "method_key_order_tmp",
                resources.method_key_order_tmp,
                &method_key_order_tmp,
            ),
            BoundGraphResource::buffer(
                "method_key_status",
                resources.method_key_status,
                &method_key_status,
            ),
            BoundGraphResource::buffer(
                "method_key_duplicate_of",
                resources.method_key_duplicate_of,
                &method_key_duplicate_of,
            ),
            BoundGraphResource::buffer(
                "method_key_radix_block_histogram",
                resources.method_key_radix_block_histogram,
                &method_key_radix_block_histogram,
            ),
            BoundGraphResource::buffer(
                "method_key_radix_block_bucket_prefix",
                resources.method_key_radix_block_bucket_prefix,
                &method_key_radix_block_bucket_prefix,
            ),
            BoundGraphResource::buffer(
                "method_key_radix_bucket_total",
                resources.method_key_radix_bucket_total,
                &method_key_radix_bucket_total,
            ),
            BoundGraphResource::buffer(
                "method_key_radix_bucket_base",
                resources.method_key_radix_bucket_base,
                &method_key_radix_bucket_base,
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
            TYPE_INSTANCE_CORE_COLLECT_INITIAL_PASS,
            TYPE_INSTANCE_CORE_COLLECT_PROJECTED_PASS,
            TYPE_INSTANCE_ARG_ROW_POPULATE_PASS,
            TYPE_INSTANCE_ARG_HASH_ROWS_PASS,
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
        for pass in [REQUIRED_GENERIC_DISPATCH_PASS] {
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
        let claim_radix_bindings = vec![
            BoundGraphResource::buffer(
                "call_generic_claim_count_out",
                resources.generic_claim_count_out,
                &generic_claim_count_out,
            ),
            BoundGraphResource::buffer(
                "call_generic_claim_callee",
                resources.generic_claim_callee,
                &generic_claim_callee,
            ),
            BoundGraphResource::buffer(
                "call_generic_claim_slot",
                resources.generic_claim_slot,
                &generic_claim_slot,
            ),
            BoundGraphResource::buffer(
                "call_generic_claim_type",
                resources.generic_claim_type,
                &generic_claim_type,
            ),
            BoundGraphResource::buffer(
                "call_generic_claim_ref_tag",
                resources.generic_claim_ref_tag,
                &generic_claim_ref_tag,
            ),
            BoundGraphResource::buffer(
                "call_generic_claim_order",
                resources.generic_claim_order,
                &generic_claim_order,
            ),
            BoundGraphResource::buffer(
                "call_generic_claim_order_tmp",
                resources.generic_claim_order_tmp,
                &generic_claim_order_tmp,
            ),
            BoundGraphResource::buffer(
                "call_generic_claim_radix_dispatch_args",
                resources.generic_claim_radix_dispatch_args,
                &generic_claim_radix_dispatch_args,
            ),
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
            BoundGraphResource::buffer(
                "call_arg_row_count_out",
                resources.call_arg_row_count_out,
                &call_arg_row_count_out,
            ),
            BoundGraphResource::buffer(
                "call_const_claim_callee",
                resources.const_claim_callee,
                &const_claim_callee,
            ),
            BoundGraphResource::buffer(
                "call_const_claim_slot",
                resources.const_claim_slot,
                &const_claim_slot,
            ),
            BoundGraphResource::buffer(
                "call_const_claim_len",
                resources.const_claim_len,
                &const_claim_len,
            ),
            BoundGraphResource::buffer(
                "call_const_claim_order",
                resources.const_claim_order,
                &const_claim_order,
            ),
            BoundGraphResource::buffer(
                "call_const_claim_order_tmp",
                resources.const_claim_order_tmp,
                &const_claim_order_tmp,
            ),
            BoundGraphResource::buffer(
                "call_const_claim_radix_dispatch_args",
                resources.const_claim_radix_dispatch_args,
                &const_claim_radix_dispatch_args,
            ),
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
        ]
        .into_iter()
        .collect::<Result<Vec<_>, _>>()
        .map_err(anyhow::Error::msg)?;
        let claim_radix_passes = [
            (
                GENERIC_CLAIM_SORT_PREPARE_PASS,
                GENERIC_CLAIM_RADIX_SORT.passes,
            ),
            (CONST_CLAIM_SORT_PREPARE_PASS, CONST_CLAIM_RADIX_SORT.passes),
        ];
        for pass in claim_radix_passes
            .into_iter()
            .flat_map(|(prepare, radix)| std::iter::once(prepare).chain(radix.names()))
        {
            let pass_id = graph.pass_id(pass).expect("claim radix graph pass");
            let declared = graph
                .pass(pass_id)
                .expect("claim radix pass descriptor")
                .accesses
                .iter()
                .map(|access| access.resource)
                .collect::<Vec<_>>();
            let bindings = claim_radix_bindings
                .iter()
                .filter(|binding| declared.contains(&binding.resource))
                .cloned()
                .collect::<Vec<_>>();
            allocations
                .validate_pass_bindings(&graph, pass_id, &bindings)
                .map_err(anyhow::Error::msg)?;
        }
        let semantic_interface_scans = SemanticInterfaceScanGraph::new(
            device,
            hir_capacity,
            token_capacity,
            source_file_capacity,
            module_record_capacity,
        )?;
        Ok(Self {
            graph,
            workspace,
            allocations,
            semantic_interface_scans,
            calls,
            scalar_a,
            scalar_b,
            type_expr_ref_tag,
            type_expr_ref_payload,
            type_generic_param_slot_by_token,
            type_const_param_slot_by_token,
            type_decl_hir_node_by_token,
            predicate_syntax_token,
            generic_decl_owner_by_node_a,
            generic_decl_owner_by_node_b,
            predicate_bound_list_by_node_a,
            predicate_bound_list_by_node_b,
            generic_decl_parent_jump_a,
            generic_decl_parent_jump_b,
            type_decl_generic_param_count,
            type_decl_generic_param_count_by_owner_token,
            type_decl_const_param_count_by_owner_token,
            generic_param_count_out,
            generic_param_owner_token,
            generic_param_name_id,
            generic_param_token,
            generic_param_node,
            generic_param_kind,
            generic_param_key_order,
            generic_param_key_order_tmp,
            generic_param_slot_order,
            generic_param_slot_order_tmp,
            generic_param_slot_radix_block_histogram,
            generic_param_slot_radix_block_bucket_prefix,
            generic_param_slot_radix_bucket_total,
            generic_param_slot_radix_bucket_base,
            predicate_owner_node,
            predicate_subject_token,
            predicate_bound_token,
            predicate_bound_decl_id,
            predicate_bound_arg_count,
            predicate_bound_first_arg_token,
            predicate_bound_second_arg_token,
            predicate_status,
            predicate_method_contract_owner_hir,
            predicate_method_contract_name_token,
            predicate_method_contract_name_id,
            predicate_method_contract_param_count,
            predicate_method_contract_return_type_node,
            predicate_method_contract_visibility,
            predicate_method_contract_status,
            predicate_method_contract_param_type_node,
            predicate_method_contract_key_order,
            predicate_method_contract_key_order_tmp,
            predicate_method_param_key_order,
            predicate_method_param_key_order_tmp,
            predicate_method_contract_owner_range_first,
            predicate_method_contract_owner_range_count,
            predicate_method_validation_owner_node,
            predicate_method_validation_peer_node,
            predicate_method_validation_status,
            predicate_method_validation_detail_token,
            predicate_method_validation_first_error_row,
            predicate_owner_key_order,
            predicate_owner_key_order_tmp,
            predicate_impl_key_order,
            predicate_impl_key_order_tmp,
            predicate_key_radix_block_histogram,
            predicate_key_radix_block_bucket_prefix,
            predicate_key_radix_bucket_total,
            predicate_key_radix_bucket_base,
            predicate_obligation_count_by_call,
            predicate_obligation_prefix_by_call,
            predicate_obligation_scan_local_prefix,
            predicate_obligation_scan_block_sum,
            predicate_obligation_scan_prefix_a,
            predicate_obligation_scan_prefix_b,
            predicate_obligation_pair_total,
            predicate_obligation_pair_dispatch_args,
            if_delta,
            if_depth_inblock,
            if_block_sum,
            if_prefix_a,
            if_prefix_b,
            if_block_prefix,
            if_depth,
            enclosing_fn,
            enclosing_fn_end,
            fn_event_value,
            fn_event_end,
            fn_event_index,
            fn_event_inblock,
            fn_block_sum,
            fn_prefix_a,
            fn_prefix_b,
            fn_block_prefix,
            member_result_context_instance,
            member_result_ref_tag,
            member_result_ref_payload,
            member_result_field_ordinal,
            member_result_field_node,
            struct_init_field_context_instance,
            struct_init_field_expected_ref_tag,
            struct_init_field_expected_ref_payload,
            struct_init_field_ordinal,
            struct_init_field_ordinal_by_node,
            struct_init_field_decl_node_by_node,
            struct_init_field_ordinal_by_row,
            struct_init_field_decl_token_by_row,
            struct_field_key_order,
            struct_field_key_order_tmp,
            struct_field_key_radix_dispatch_args,
            struct_field_key_radix_block_histogram,
            struct_field_key_radix_block_bucket_prefix,
            struct_field_key_radix_bucket_total,
            struct_field_key_radix_bucket_base,
            struct_lit_context_decl_token,
            struct_lit_context_instance,
            array_element_struct_literal_node,
            member_next_node,
            fn_entrypoint_tag,
            call_fn_index,
            call_return_type,
            call_return_type_token,
            method_decl_method_row,
            method_decl_receiver_ref_tag,
            method_decl_receiver_ref_payload,
            method_decl_module_id,
            method_decl_name_token,
            method_decl_name_id,
            method_decl_param_offset,
            method_decl_receiver_mode,
            method_decl_visibility,
            method_decl_signature_flags,
            method_call_receiver_ref_tag,
            method_call_receiver_ref_payload,
            method_call_name_id,
            method_call_site_module_id,
            type_instance_kind,
            type_instance_head_token,
            type_instance_state,
            type_instance_elem_ref_tag,
            type_instance_elem_ref_payload,
            type_instance_len_kind,
            type_instance_len_payload,
            type_instance_arg_start,
            type_instance_arg_count,
            type_instance_arg_ref_tag,
            type_instance_arg_ref_payload,
            type_instance_arg_row_start,
            type_instance_arg_row_count_out,
            type_instance_arg_row_ref_tag,
            type_instance_arg_row_ref_payload,
            type_instance_arg_hash,
            method_key_to_fn_token,
            method_key_order_tmp,
            method_key_status,
            method_key_duplicate_of,
            method_key_radix_block_histogram,
            method_key_radix_block_bucket_prefix,
            method_key_radix_bucket_total,
            method_key_radix_bucket_base,
            type_instance_arg_row_scan_local_prefix,
            type_instance_arg_row_scan_block_sum,
            type_instance_arg_row_scan_prefix_a,
            type_instance_arg_row_scan_prefix_b,
            aggregate_compare_scan_input,
            aggregate_compare_expected_instance,
            aggregate_compare_actual_instance,
            aggregate_compare_error_token,
            aggregate_compare_error_detail,
            aggregate_compare_prefix,
            aggregate_compare_count_out,
            aggregate_compare_scan_local_prefix,
            aggregate_compare_scan_block_sum,
            aggregate_compare_scan_prefix_a,
            aggregate_compare_scan_prefix_b,
            aggregate_compare_dispatch_args,
            type_subtree_compare_scan_input,
            type_subtree_compare_prefix,
            type_subtree_compare_count_out,
            type_subtree_compare_left_root,
            type_subtree_compare_right_root,
            type_subtree_compare_error_token,
            type_subtree_compare_error_detail,
            type_subtree_compare_dispatch_args,
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
            generic_claim_callee,
            generic_claim_slot,
            generic_claim_type,
            generic_claim_ref_tag,
            generic_claim_ref_payload,
            generic_claim_arg_row,
            generic_claim_order,
            generic_claim_order_tmp,
            generic_claim_radix_dispatch_args,
            generic_claim_radix_block_histogram,
            generic_claim_radix_block_bucket_prefix,
            generic_claim_radix_bucket_total,
            generic_claim_radix_bucket_base,
            const_claim_radix_block_histogram,
            const_claim_radix_block_bucket_prefix,
            const_claim_radix_bucket_total,
            const_claim_radix_bucket_base,
            const_claim_callee,
            const_claim_slot,
            const_claim_len,
            const_claim_order,
            const_claim_order_tmp,
            const_claim_radix_dispatch_args,
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
            semantic_function_return_type_by_hir,
            semantic_function_entrypoint_by_hir,
            semantic_function_host_service_by_hir,
            semantic_control_depth_by_hir,
            semantic_calls_by_hir,
            semantic_expr_ref_tag_by_hir,
            semantic_expr_ref_payload_by_hir,
            semantic_array_length_by_hir,
            semantic_member_field_ordinal_by_hir,
            type_semantic_row_by_token,
            type_semantic_scan_input,
            type_semantic_prefix,
            type_semantic_count_out,
            type_semantic_row_by_ordinal,
            compact_predicate_diagnostic_facts,
            return_fn_flags,
            return_block_flags,
            step_count,
        })
    }

    pub(super) fn step_count(&self) -> usize {
        self.step_count
    }

    pub(super) fn semantic_interface_scan_workspace(
        &self,
    ) -> PrefixScanWorkspace<&LaniusBuffer<u32>> {
        self.semantic_interface_scans.workspace()
    }

    pub(super) fn validate_semantic_interface_scan(
        &self,
        scan: SemanticInterfaceScan,
        resources: &ResourceMap<'_>,
    ) -> Result<()> {
        self.semantic_interface_scans.validate(scan, resources)
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

fn prefix_scan_hierarchy_levels(block_count: u64) -> u32 {
    crate::gpu::scan::hierarchical_scan_levels(u32::try_from(block_count).unwrap_or(u32::MAX))
        .len()
        .try_into()
        .unwrap_or(u32::MAX)
}

fn add_type_subtree_passes(
    graph: &mut CompilerGraphBuilder,
    scan_passes: PrefixScanGraphPasses,
    dispatch_name: &'static str,
    indirect_name: &'static str,
    hierarchy_levels: u32,
    resources: &ExpressionTypeResources,
) -> Result<(), String> {
    let scan_resources = graph.resolve_prefix_scan_resources(TYPE_SUBTREE_SCAN_RESOURCES)?;
    graph.add_fragment(PrefixScanGraph {
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        hierarchy_levels,
        passes: scan_passes,
        resources: scan_resources,
    })?;
    graph.add_pass(PassDesc {
        name: dispatch_name,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::DispatchArguments,
        accesses: vec![
            PassAccess::read(
                "type_subtree_compare_count_out",
                resources.type_subtree_compare_count_out,
            ),
            PassAccess::write(
                "type_subtree_compare_dispatch_args",
                resources.type_subtree_compare_dispatch_args,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: indirect_name,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read(
                "type_subtree_compare_prefix",
                resources.type_subtree_compare_prefix,
            ),
            PassAccess::read(
                "type_subtree_compare_left_root",
                resources.type_subtree_compare_left_root,
            ),
            PassAccess::read(
                "type_subtree_compare_right_root",
                resources.type_subtree_compare_right_root,
            ),
            PassAccess::read(
                "type_subtree_compare_error_token",
                resources.type_subtree_compare_error_token,
            ),
            PassAccess::read(
                "type_subtree_compare_error_detail",
                resources.type_subtree_compare_error_detail,
            ),
            PassAccess::read(
                "type_subtree_compare_dispatch_args",
                resources.type_subtree_compare_dispatch_args,
            ),
            PassAccess::read_write("status", resources.status),
        ],
    })?;
    Ok(())
}

struct BuildGraphReflections<'a> {
    semantic_features_collect: &'a crate::reflection::SlangReflection,
    semantic_features_dispatch: &'a crate::reflection::SlangReflection,
    names_mark: &'a crate::reflection::SlangReflection,
    names_scatter: &'a crate::reflection::SlangReflection,
    names_hash_prepare: &'a crate::reflection::SlangReflection,
    names_hash_insert: &'a crate::reflection::SlangReflection,
    names_hash_assign: &'a crate::reflection::SlangReflection,
    language_names_clear: &'a crate::reflection::SlangReflection,
    language_type_codes_clear: &'a crate::reflection::SlangReflection,
    language_decls_materialize: &'a crate::reflection::SlangReflection,
    conditions_compact_calls: &'a crate::reflection::SlangReflection,
    conditions_compact_types: &'a crate::reflection::SlangReflection,
    conditions_aggregate_args: &'a crate::reflection::SlangReflection,
    calls_mark_array_args: &'a crate::reflection::SlangReflection,
    calls_validate_array_results: &'a crate::reflection::SlangReflection,
    calls_project_result_instances: &'a crate::reflection::SlangReflection,
    calls: CallGraphReflections<'a>,
    methods_clear: &'a crate::reflection::SlangReflection,
    methods_collect: &'a crate::reflection::SlangReflection,
    methods_attach_metadata: &'a crate::reflection::SlangReflection,
    methods_bind_self_receivers: &'a crate::reflection::SlangReflection,
    methods_seed_key_order: &'a crate::reflection::SlangReflection,
    methods_validate_keys: &'a crate::reflection::SlangReflection,
    methods_mark_call_keys: &'a crate::reflection::SlangReflection,
    methods_mark_call_return_keys: &'a crate::reflection::SlangReflection,
    methods_resolve_table: &'a crate::reflection::SlangReflection,
    methods_resolve: &'a crate::reflection::SlangReflection,
    type_instances_struct_init_clear: &'a crate::reflection::SlangReflection,
    type_instances_struct_init_contexts: &'a crate::reflection::SlangReflection,
    type_instances_struct_init_fields: &'a crate::reflection::SlangReflection,
    type_instances_struct_init_substitute: &'a crate::reflection::SlangReflection,
    type_instances_validate_aggregate_access: &'a crate::reflection::SlangReflection,
    type_instances_member_receivers: &'a crate::reflection::SlangReflection,
    type_instances_member_results: &'a crate::reflection::SlangReflection,
    type_instances_member_substitute: &'a crate::reflection::SlangReflection,
    type_instances_clear_semantic_type_rows: &'a crate::reflection::SlangReflection,
    type_instances_mark_semantic_type_rows: &'a crate::reflection::SlangReflection,
    type_instances_scatter_semantic_type_rows: &'a crate::reflection::SlangReflection,
    semantic_array_index_refs: &'a crate::reflection::SlangReflection,
    type_instances_decl_generic_params: &'a crate::reflection::SlangReflection,
    type_instances_sort_generic_params_small: &'a crate::reflection::SlangReflection,
    type_instances_generic_param_use_slots: &'a crate::reflection::SlangReflection,
    predicates: Option<PredicateGraphReflections<'a>>,
}

#[derive(Clone, Copy)]
struct CallGraphReflections<'a> {
    clear: &'a crate::reflection::SlangReflection,
    clear_entrypoints: &'a crate::reflection::SlangReflection,
    return_refs: &'a crate::reflection::SlangReflection,
    entrypoints: &'a crate::reflection::SlangReflection,
    functions: &'a crate::reflection::SlangReflection,
    param_types: &'a crate::reflection::SlangReflection,
    scatter_params: &'a crate::reflection::SlangReflection,
    intrinsics: &'a crate::reflection::SlangReflection,
    clear_args: &'a crate::reflection::SlangReflection,
    pack_args: &'a crate::reflection::SlangReflection,
    mark_args: &'a crate::reflection::SlangReflection,
    scatter_args: &'a crate::reflection::SlangReflection,
    resolve: &'a crate::reflection::SlangReflection,
    match_args: &'a crate::reflection::SlangReflection,
    collect_args: &'a crate::reflection::SlangReflection,
    apply_args: &'a crate::reflection::SlangReflection,
    emit_generic_claims: &'a crate::reflection::SlangReflection,
    clear_generic_claim_type_args: &'a crate::reflection::SlangReflection,
    validate_generic_claims: &'a crate::reflection::SlangReflection,
    mark_required_generics: &'a crate::reflection::SlangReflection,
    validate_required_generics: &'a crate::reflection::SlangReflection,
    validate_const_claims: &'a crate::reflection::SlangReflection,
}

#[derive(Clone, Copy)]
struct PredicateGraphReflections<'a> {
    clear_syntax_tokens: &'a crate::reflection::SlangReflection,
    clear_bound_arg_facts: &'a crate::reflection::SlangReflection,
    collect_bound_arg_facts: &'a crate::reflection::SlangReflection,
    collect_method_contracts: &'a crate::reflection::SlangReflection,
    collect: &'a crate::reflection::SlangReflection,
    validate_bound_args: &'a crate::reflection::SlangReflection,
    collect_impls: &'a crate::reflection::SlangReflection,
    build_method_owner_ranges: &'a crate::reflection::SlangReflection,
    emit_method_validation_rows: &'a crate::reflection::SlangReflection,
    emit_method_param_validation_rows: &'a crate::reflection::SlangReflection,
    validate_method_type_arg_rows: &'a crate::reflection::SlangReflection,
    reduce_method_validation_errors: &'a crate::reflection::SlangReflection,
    count_obligations: &'a crate::reflection::SlangReflection,
    validate_obligations: &'a crate::reflection::SlangReflection,
}

fn build_graph(
    hir_capacity: u32,
    token_capacity: u32,
    source_file_capacity: u32,
    module_record_capacity: u32,
    call_param_capacity: u32,
    call_arg_capacity: u32,
    generic_claim_capacity: u32,
    predicate_capacity: u32,
    step_count: usize,
    reflections: &BuildGraphReflections<'_>,
) -> Result<(CompilerGraph, ExpressionTypeResources), String> {
    let hir_rows = u64::from(hir_capacity.max(1));
    let token_rows = u64::from(token_capacity.max(1));
    let module_path_key_radix_rows = u64::from(
        source_file_capacity
            .max(module_record_capacity)
            .max(token_capacity)
            .max(1),
    )
    .div_ceil(256)
        * u64::from(NAME_RADIX_BUCKETS);
    let call_arg_rows = u64::from(call_arg_capacity.max(1));
    let call_param_rows = u64::from(call_param_capacity.max(1));
    let predicate_rows = u64::from(predicate_capacity.max(1));
    let hir_blocks = hir_rows.div_ceil(256);
    let token_blocks = token_rows.div_ceil(256);
    let call_arg_blocks = call_arg_rows.div_ceil(256);
    let predicate_blocks = predicate_rows.div_ceil(256);
    let claim_rows = u64::from(generic_claim_capacity.max(1));
    let claim_blocks = claim_rows.div_ceil(256);
    let claim_histogram_rows = claim_blocks * u64::from(NAME_RADIX_BUCKETS);
    let mut graph = CompilerGraphBuilder::new();
    let mut input =
        |name, domain, bytes| graph.add_storage(name, domain, ResourceClass::Input, bytes);
    let compact_hir_count = input("compact_hir_count", ResourceDomain::HirNodes, 4)?;
    let compact_hir_core = input("compact_hir_core", ResourceDomain::HirNodes, hir_rows * 16)?;
    let compact_hir_links = input("compact_hir_links", ResourceDomain::HirNodes, hir_rows * 16)?;
    let compact_hir_payload = input(
        "compact_hir_payload",
        ResourceDomain::HirNodes,
        hir_rows * 16,
    )?;
    let compact_type_root_owner = input(
        "compact_type_root_owner",
        ResourceDomain::HirNodes,
        hir_rows * 4,
    )?;
    let compact_param_count = input("compact_param_count", ResourceDomain::Declarations, 4)?;
    let compact_params = input(
        "compact_params",
        ResourceDomain::Declarations,
        hir_rows * 16,
    )?;
    let _compact_call_arg_count =
        input("compact_call_arg_count", ResourceDomain::CallArguments, 4)?;
    let _compact_call_args = input(
        "compact_call_args",
        ResourceDomain::CallArguments,
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
    let call_dependency_decl = input(
        "call_dependency_decl",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    drop(input);
    // Function return references are initialized by the physical type-instance
    // clear and then republished from compact HIR. Their complete type-check
    // lifetime is represented below, so they are ordinary colorable workspace.
    let fn_return_ref_tag = graph.add_storage(
        "fn_return_ref_tag",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let fn_return_ref_payload = graph.add_storage(
        "fn_return_ref_payload",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let decl_type_ref_tag = graph.add_storage(
        "decl_type_ref_tag",
        ResourceDomain::Tokens,
        ResourceClass::External,
        token_rows * 4,
    )?;
    let decl_type_ref_payload = graph.add_storage(
        "decl_type_ref_payload",
        ResourceDomain::Tokens,
        ResourceClass::External,
        token_rows * 4,
    )?;
    let type_instance_kind = graph.add_storage(
        "type_instance_kind",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let mut input =
        |name, domain, bytes| graph.add_storage(name, domain, ResourceClass::Input, bytes);
    let type_instance_external_canonical = input(
        "type_instance_external_canonical",
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
    input(
        "token_active_dispatch_args",
        ResourceDomain::DispatchArguments,
        12,
    )?;
    let hir_active_count = input("hir_active_count", ResourceDomain::HirNodes, 4)?;
    input(
        "hir_active_dispatch_args",
        ResourceDomain::DispatchArguments,
        12,
    )?;
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
    let _source_bytes = input("source_bytes", ResourceDomain::Bytes, 1)?;
    let _language_symbol_bytes = input(
        "language_symbol_bytes",
        ResourceDomain::Bytes,
        LANGUAGE_SYMBOL_BYTES.len() as u64,
    )?;
    let _language_symbol_start = input(
        "language_symbol_start",
        ResourceDomain::Declarations,
        LANGUAGE_SYMBOL_COUNT as u64 * 4,
    )?;
    let _language_symbol_len = input(
        "language_symbol_len",
        ResourceDomain::Declarations,
        LANGUAGE_SYMBOL_COUNT as u64 * 4,
    )?;
    let _language_decl_symbol_slot = input(
        "language_decl_symbol_slot",
        ResourceDomain::Declarations,
        LANGUAGE_DECL_COUNT as u64 * 4,
    )?;
    let _language_decl_kind = input(
        "language_decl_kind",
        ResourceDomain::Declarations,
        LANGUAGE_DECL_COUNT as u64 * 4,
    )?;
    let _language_decl_tag = input(
        "language_decl_tag",
        ResourceDomain::Declarations,
        LANGUAGE_DECL_COUNT as u64 * 4,
    )?;
    drop(input);
    let module_value_path_status = graph.add_storage(
        "module_value_path_status",
        ResourceDomain::Tokens,
        ResourceClass::External,
        token_rows * 4,
    )?;
    let type_instance_decl_token = graph.add_storage(
        "type_instance_decl_token",
        ResourceDomain::Types,
        ResourceClass::External,
        token_rows * 4,
    )?;
    let predicate_syntax_token = graph.add_storage(
        "predicate_syntax_token",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        predicate_rows * 4,
    )?;
    let type_expr_ref_tag = graph.add_storage(
        "type_expr_ref_tag",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let type_expr_ref_payload = graph.add_storage(
        "type_expr_ref_payload",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let type_generic_param_slot_by_token = graph.add_storage(
        "type_generic_param_slot_by_token",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let type_const_param_slot_by_token = graph.add_storage(
        "type_const_param_slot_by_token",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let mut input =
        |name, domain, bytes| graph.add_storage(name, domain, ResourceClass::Input, bytes);
    let compact_hir_scope_end = input(
        "compact_hir_scope_end",
        ResourceDomain::HirNodes,
        hir_rows * 4,
    )?;
    drop(input);
    let external_u32 = |graph: &mut CompilerGraphBuilder, name, domain, bytes| {
        graph.add_storage(name, domain, ResourceClass::External, bytes)
    };
    let name_rows = token_rows.saturating_add(LANGUAGE_SYMBOL_COUNT as u64);
    let name_id_by_token = external_u32(
        &mut graph,
        "name_id_by_token",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let language_name_id = external_u32(
        &mut graph,
        "language_name_id",
        ResourceDomain::Declarations,
        LANGUAGE_SYMBOL_COUNT as u64 * 4,
    )?;
    let _language_decl_name_id = external_u32(
        &mut graph,
        "language_decl_name_id",
        ResourceDomain::Declarations,
        LANGUAGE_DECL_COUNT as u64 * 4,
    )?;
    let _language_type_code_by_name_id = external_u32(
        &mut graph,
        "language_type_code_by_name_id",
        ResourceDomain::Declarations,
        name_rows * 4,
    )?;
    external_u32(
        &mut graph,
        "language_entrypoint_tag_by_name_id",
        ResourceDomain::Declarations,
        name_rows * 4,
    )?;
    let _language_intrinsic_tag_by_name_id = external_u32(
        &mut graph,
        "language_intrinsic_tag_by_name_id",
        ResourceDomain::Declarations,
        name_rows * 4,
    )?;
    let mut input =
        |name, domain, bytes| graph.add_storage(name, domain, ResourceClass::Input, bytes);
    let compact_predicate_count =
        input("compact_predicate_count", ResourceDomain::Declarations, 4)?;
    let compact_predicates = input(
        "compact_predicates",
        ResourceDomain::Declarations,
        hir_rows * 16,
    )?;
    let hir_status = input("hir_status", ResourceDomain::HirNodes, 24)?;
    let hir_kind = input("hir_kind", ResourceDomain::RawNodes, hir_rows * 4)?;
    let hir_token_pos = input("hir_token_pos", ResourceDomain::HirNodes, hir_rows * 4)?;
    input("hir_token_end", ResourceDomain::HirNodes, hir_rows * 4)?;
    let _hir_struct_lit_head_node = input(
        "hir_struct_lit_head_node",
        ResourceDomain::RawNodes,
        hir_rows * 4,
    )?;
    let _hir_struct_lit_field_parent_lit = input(
        "hir_struct_lit_field_parent_lit",
        ResourceDomain::RawNodes,
        hir_rows * 4,
    )?;
    let _hir_struct_lit_field_value_node = input(
        "hir_struct_lit_field_value_node",
        ResourceDomain::RawNodes,
        hir_rows * 4,
    )?;
    let _hir_member_receiver_node = input(
        "hir_member_receiver_node",
        ResourceDomain::RawNodes,
        hir_rows * 4,
    )?;
    let _hir_expr_record = input("hir_expr_record", ResourceDomain::RawNodes, hir_rows * 16)?;
    let _hir_stmt_record = input("hir_stmt_record", ResourceDomain::RawNodes, hir_rows * 16)?;
    let _hir_type_value_node = input(
        "hir_type_value_node",
        ResourceDomain::RawNodes,
        hir_rows * 4,
    )?;
    let _hir_array_lit_context_stmt_node = input(
        "hir_array_lit_context_stmt_node",
        ResourceDomain::RawNodes,
        hir_rows * 4,
    )?;
    let _hir_array_element_parent_lit = input(
        "hir_array_element_parent_lit",
        ResourceDomain::RawNodes,
        hir_rows * 4,
    )?;
    let _hir_nearest_array_element_node = input(
        "hir_nearest_array_element_node",
        ResourceDomain::RawNodes,
        hir_rows * 4,
    )?;
    let _hir_struct_lit_context_stmt_node = input(
        "hir_struct_lit_context_stmt_node",
        ResourceDomain::RawNodes,
        hir_rows * 4,
    )?;
    let _hir_expr_name_role = input("hir_expr_name_role", ResourceDomain::RawNodes, hir_rows * 4)?;
    let _hir_expr_result_root_node = input(
        "hir_expr_result_root_node",
        ResourceDomain::RawNodes,
        hir_rows * 4,
    )?;
    let _hir_member_receiver_token = input(
        "hir_member_receiver_token",
        ResourceDomain::RawNodes,
        hir_rows * 4,
    )?;
    let _hir_member_name_token = input(
        "hir_member_name_token",
        ResourceDomain::RawNodes,
        hir_rows * 4,
    )?;
    let _module_type_path_type = input(
        "module_type_path_type",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let _token_file_id = input("token_file_id", ResourceDomain::Tokens, token_rows * 4)?;
    let _path_owner_hir = input("path_owner_hir", ResourceDomain::HirNodes, hir_rows * 4)?;
    let _path_kind = input("path_kind", ResourceDomain::Tokens, token_rows * 4)?;
    let _path_owner_token = input("path_owner_token", ResourceDomain::Tokens, token_rows * 4)?;
    let _path_owner_module_id = input(
        "path_owner_module_id",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let _module_value_path_call_open = input(
        "module_value_path_call_open",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let _module_value_path_call_path_id = input(
        "module_value_path_call_path_id",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let _module_value_path_associated_receiver_token = input(
        "module_value_path_associated_receiver_token",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let _module_id_by_file_id = input(
        "module_id_by_file_id",
        ResourceDomain::Declarations,
        u64::from(source_file_capacity.max(1)) * 4,
    )?;
    let _module_count_out = input("module_count_out", ResourceDomain::Declarations, 4)?;
    let raw_to_compact_hir = input("raw_to_compact_hir", ResourceDomain::HirNodes, hir_rows * 4)?;
    let compact_field_count = input("compact_field_count", ResourceDomain::Declarations, 4)?;
    let compact_fields = input(
        "compact_fields",
        ResourceDomain::Declarations,
        hir_rows * 16,
    )?;
    let _path_count_out = input("path_count_out", ResourceDomain::HirNodes, 4)?;
    let _path_segment_count = input("path_segment_count", ResourceDomain::HirNodes, hir_rows * 4)?;
    let _path_segment_base = input("path_segment_base", ResourceDomain::HirNodes, hir_rows * 4)?;
    let _path_segment_token = input("path_segment_token", ResourceDomain::Tokens, token_rows * 4)?;
    drop(input);
    let mut method_workspace = |name| {
        graph.add_storage(
            name,
            ResourceDomain::Declarations,
            ResourceClass::Workspace,
            token_rows * 4,
        )
    };
    let method_decl_method_row = method_workspace("method_decl_method_row")?;
    let method_decl_receiver_ref_tag = method_workspace("method_decl_receiver_ref_tag")?;
    let method_decl_receiver_ref_payload = method_workspace("method_decl_receiver_ref_payload")?;
    let method_decl_module_id = method_workspace("method_decl_module_id")?;
    let method_decl_name_token = method_workspace("method_decl_name_token")?;
    let method_decl_name_id = method_workspace("method_decl_name_id")?;
    let method_decl_param_offset = method_workspace("method_decl_param_offset")?;
    let method_decl_receiver_mode = method_workspace("method_decl_receiver_mode")?;
    let method_decl_visibility = method_workspace("method_decl_visibility")?;
    let method_decl_signature_flags = method_workspace("method_decl_signature_flags")?;
    drop(method_workspace);
    let struct_field_sort_resources = graph.add_radix_sort_resources(
        compact_field_count,
        vec![
            compact_hir_count,
            compact_hir_core,
            compact_fields,
            name_id_by_token,
        ],
        ResourceDomain::Declarations,
        token_rows,
        256,
        u64::from(NAME_RADIX_BUCKETS),
        RadixSortGraphResourceNames {
            order: "struct_field_key_order",
            temporary_order: "struct_field_key_order_tmp",
            dispatch_args: "struct_field_key_radix_dispatch_args",
            histogram: "struct_field_key_radix_block_histogram",
            bucket_prefix: "struct_field_key_radix_block_bucket_prefix",
            bucket_total: "struct_field_key_radix_bucket_total",
            bucket_base: "struct_field_key_radix_bucket_base",
        },
    )?;
    let struct_field_key_order = struct_field_sort_resources.order;
    let struct_field_key_order_tmp = struct_field_sort_resources.temporary_order;
    let struct_field_key_radix_dispatch_args = struct_field_sort_resources.dispatch_args;
    let struct_field_key_radix_block_histogram = struct_field_sort_resources.histogram;
    let struct_field_key_radix_block_bucket_prefix = struct_field_sort_resources.bucket_prefix;
    let struct_field_key_radix_bucket_total = struct_field_sort_resources.bucket_total;
    let struct_field_key_radix_bucket_base = struct_field_sort_resources.bucket_base;
    let name_blocks = name_rows.div_ceil(256).max(1);
    let name_hash_rows = name_blocks * u64::from(NAME_RADIX_BUCKETS);
    let mut name_workspace =
        |name, domain, bytes| graph.add_storage(name, domain, ResourceClass::Workspace, bytes);
    let name_lexeme_flag =
        name_workspace("name_lexeme_flag", ResourceDomain::Tokens, token_rows * 4)?;
    let name_lexeme_kind =
        name_workspace("name_lexeme_kind", ResourceDomain::Tokens, token_rows * 4)?;
    name_workspace("name_lexeme_prefix", ResourceDomain::Tokens, token_rows * 4)?;
    name_workspace(
        "name_scan_local_prefix",
        ResourceDomain::Tokens,
        name_rows * 4,
    )?;
    name_workspace(
        "name_scan_block_sum",
        ResourceDomain::Tokens,
        name_blocks * 4,
    )?;
    name_workspace(
        "name_scan_prefix_a",
        ResourceDomain::Tokens,
        name_blocks * 4,
    )?;
    name_workspace(
        "name_scan_prefix_b",
        ResourceDomain::Tokens,
        name_blocks * 4,
    )?;
    let name_scan_total = name_workspace("name_scan_total", ResourceDomain::Declarations, 4)?;
    let name_max_len = name_workspace("name_max_len", ResourceDomain::Declarations, 4)?;
    let name_spans = name_workspace("name_spans", ResourceDomain::Declarations, name_rows * 16)?;
    let name_hash_lo = name_workspace("name_hash_lo", ResourceDomain::Declarations, name_rows * 4)?;
    let name_hash_hi = name_workspace("name_hash_hi", ResourceDomain::Declarations, name_rows * 4)?;
    let name_hash_table_a = name_workspace(
        "name_hash_table_a",
        ResourceDomain::Declarations,
        name_hash_rows * 4,
    )?;
    let name_hash_table_b = name_workspace(
        "name_hash_table_b",
        ResourceDomain::Declarations,
        name_hash_rows * 4,
    )?;
    let sorted_name_id = name_workspace(
        "sorted_name_id",
        ResourceDomain::Declarations,
        name_rows * 4,
    )?;
    let name_id_by_input = name_workspace(
        "name_id_by_input",
        ResourceDomain::Declarations,
        name_rows * 4,
    )?;
    let unique_name_count = name_workspace("unique_name_count", ResourceDomain::Declarations, 4)?;
    let decl_name_token = name_workspace(
        "decl_name_token",
        ResourceDomain::Declarations,
        hir_rows * 4,
    )?;
    let decl_id_by_name_token = name_workspace(
        "decl_id_by_name_token",
        ResourceDomain::Tokens,
        token_rows * 4,
    )?;
    let module_record_family_bits = name_workspace(
        "module_record_family_bits",
        ResourceDomain::HirNodes,
        hir_rows * 4,
    )?;
    let module_record_family_flag = name_workspace(
        "module_record_family_flag",
        ResourceDomain::HirNodes,
        hir_rows * 4,
    )?;
    let module_record_prefix = name_workspace(
        "module_record_prefix",
        ResourceDomain::HirNodes,
        hir_rows * 4,
    )?;
    name_workspace(
        "module_record_scan_local_prefix",
        ResourceDomain::HirNodes,
        hir_rows * 4,
    )?;
    name_workspace(
        "module_record_scan_block_sum",
        ResourceDomain::HirNodes,
        hir_blocks * 4,
    )?;
    name_workspace(
        "module_record_scan_prefix_a",
        ResourceDomain::HirNodes,
        hir_blocks * 4,
    )?;
    name_workspace(
        "module_record_scan_prefix_b",
        ResourceDomain::HirNodes,
        hir_blocks * 4,
    )?;
    name_workspace(
        "module_value_scan_local_prefix",
        ResourceDomain::Declarations,
        hir_rows * 4,
    )?;
    name_workspace(
        "module_value_scan_block_sum",
        ResourceDomain::Declarations,
        hir_blocks * 4,
    )?;
    name_workspace(
        "module_value_scan_prefix_a",
        ResourceDomain::Declarations,
        hir_blocks * 4,
    )?;
    name_workspace(
        "module_value_scan_prefix_b",
        ResourceDomain::Declarations,
        hir_blocks * 4,
    )?;
    let module_path_key_radix_block_histogram = name_workspace(
        "module_path_key_radix_block_histogram",
        ResourceDomain::Declarations,
        module_path_key_radix_rows * 4,
    )?;
    let module_path_key_radix_block_bucket_prefix = name_workspace(
        "module_path_key_radix_block_bucket_prefix",
        ResourceDomain::Declarations,
        module_path_key_radix_rows * 4,
    )?;
    let module_path_key_radix_bucket_total = name_workspace(
        "module_path_key_radix_bucket_total",
        ResourceDomain::Declarations,
        u64::from(NAME_RADIX_BUCKETS) * 4,
    )?;
    let module_path_key_radix_bucket_base = name_workspace(
        "module_path_key_radix_bucket_base",
        ResourceDomain::Declarations,
        u64::from(NAME_RADIX_BUCKETS) * 4,
    )?;
    drop(name_workspace);
    let type_decl_hir_node_by_token = graph.add_storage(
        "type_decl_hir_node_by_token",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    macro_rules! predicate_workspace_row_resource {
        ($name:literal) => {
            graph.add_storage(
                $name,
                ResourceDomain::HirNodes,
                ResourceClass::Workspace,
                predicate_rows * 4,
            )?
        };
    }
    macro_rules! predicate_workspace_resource {
        ($name:literal, $bytes:expr) => {
            graph.add_storage(
                $name,
                ResourceDomain::HirNodes,
                ResourceClass::Workspace,
                $bytes,
            )?
        };
    }
    let predicate_bound_first_arg_token =
        predicate_workspace_row_resource!("predicate_bound_first_arg_token");
    let predicate_bound_second_arg_token =
        predicate_workspace_row_resource!("predicate_bound_second_arg_token");
    let predicate_status = predicate_workspace_row_resource!("predicate_status");
    let predicate_method_contract_status =
        predicate_workspace_row_resource!("predicate_method_contract_status");
    let predicate_method_validation_first_error_row =
        predicate_workspace_row_resource!("predicate_method_validation_first_error_row");
    let predicate_method_validation_status =
        predicate_workspace_row_resource!("predicate_method_validation_status");
    let predicate_method_validation_detail_token =
        predicate_workspace_row_resource!("predicate_method_validation_detail_token");
    let struct_lit_context_instance = graph.add_storage(
        "struct_lit_context_instance",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        hir_rows * 4,
    )?;
    let struct_lit_context_decl_token = graph.add_storage(
        "struct_lit_context_decl_token",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        hir_rows * 4,
    )?;
    let array_element_struct_literal_node = graph.add_storage(
        "array_element_struct_literal_node",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        hir_rows * 4,
    )?;
    let type_instance_arg_start = graph.add_storage(
        "type_instance_arg_start",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let type_instance_head_token = graph.add_storage(
        "type_instance_head_token",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let type_instance_state = graph.add_storage(
        "type_instance_state",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let type_instance_elem_ref_tag = graph.add_storage(
        "type_instance_elem_ref_tag",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let type_instance_elem_ref_payload = graph.add_storage(
        "type_instance_elem_ref_payload",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let type_instance_len_kind = graph.add_storage(
        "type_instance_len_kind",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let type_instance_len_payload = graph.add_storage(
        "type_instance_len_payload",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let type_instance_arg_count = graph.add_storage(
        "type_instance_arg_count",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let visible_type = graph.add_storage(
        "visible_type",
        ResourceDomain::Tokens,
        ResourceClass::External,
        token_rows * 4,
    )?;
    let visible_decl = graph.add_storage(
        "visible_decl",
        ResourceDomain::Tokens,
        ResourceClass::External,
        token_rows * 4,
    )?;
    let call_return_type = graph.add_storage(
        "call_return_type",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let call_return_type_token = graph.add_storage(
        "call_return_type_token",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let call_fn_index = graph.add_storage(
        "call_fn_index",
        ResourceDomain::Calls,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let method_call_receiver_ref_tag = graph.add_storage(
        "method_call_receiver_ref_tag",
        ResourceDomain::Calls,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let method_call_receiver_ref_payload = graph.add_storage(
        "method_call_receiver_ref_payload",
        ResourceDomain::Calls,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let method_call_name_id = graph.add_storage(
        "method_call_name_id",
        ResourceDomain::Calls,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let method_call_site_module_id = graph.add_storage(
        "method_call_site_module_id",
        ResourceDomain::Calls,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let fn_entrypoint_tag = graph.add_storage(
        "fn_entrypoint_tag",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows.max(hir_rows) * 4,
    )?;
    let type_instance_arg_row_start = graph.add_storage(
        "type_instance_arg_row_start",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let type_instance_arg_row_count_out = graph.add_storage(
        "type_instance_arg_row_count_out",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        4,
    )?;
    let type_instance_arg_row_scan_local_prefix = graph.add_storage(
        "type_instance_arg_row_scan_local_prefix",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let type_instance_arg_row_scan_block_sum = graph.add_storage(
        "type_instance_arg_row_scan_block_sum",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows.div_ceil(256) * 4,
    )?;
    let type_instance_arg_row_scan_prefix_a = graph.add_storage(
        "type_instance_arg_row_scan_prefix_a",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows.div_ceil(256) * 4,
    )?;
    let type_instance_arg_row_scan_prefix_b = graph.add_storage(
        "type_instance_arg_row_scan_prefix_b",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows.div_ceil(256) * 4,
    )?;
    let type_instance_arg_row_ref_tag = graph.add_storage(
        "type_instance_arg_row_ref_tag",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        hir_rows * 4,
    )?;
    let type_instance_arg_row_ref_payload = graph.add_storage(
        "type_instance_arg_row_ref_payload",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        hir_rows * 4,
    )?;
    let type_instance_arg_hash = graph.add_storage(
        "type_instance_arg_hash",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let method_key_to_fn_token = graph.add_storage(
        "method_key_to_fn_token",
        ResourceDomain::Declarations,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let method_key_order_tmp = graph.add_storage(
        "method_key_order_tmp",
        ResourceDomain::Declarations,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let method_key_status = graph.add_storage(
        "method_key_status",
        ResourceDomain::Declarations,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let method_key_duplicate_of = graph.add_storage(
        "method_key_duplicate_of",
        ResourceDomain::Declarations,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let method_key_radix_rows = token_rows.div_ceil(256) * u64::from(NAME_RADIX_BUCKETS);
    let method_key_radix_block_histogram = graph.add_storage(
        "method_key_radix_block_histogram",
        ResourceDomain::Declarations,
        ResourceClass::Workspace,
        method_key_radix_rows * 4,
    )?;
    let method_key_radix_block_bucket_prefix = graph.add_storage(
        "method_key_radix_block_bucket_prefix",
        ResourceDomain::Declarations,
        ResourceClass::Workspace,
        method_key_radix_rows * 4,
    )?;
    let method_key_radix_bucket_total = graph.add_storage(
        "method_key_radix_bucket_total",
        ResourceDomain::Declarations,
        ResourceClass::Workspace,
        u64::from(NAME_RADIX_BUCKETS) * 4,
    )?;
    let method_key_radix_bucket_base = graph.add_storage(
        "method_key_radix_bucket_base",
        ResourceDomain::Declarations,
        ResourceClass::Workspace,
        u64::from(NAME_RADIX_BUCKETS) * 4,
    )?;
    let type_instance_arg_ref_tag = graph.add_storage(
        "type_instance_arg_ref_tag",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows * 16,
    )?;
    let type_instance_arg_ref_payload = graph.add_storage(
        "type_instance_arg_ref_payload",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows * 16,
    )?;
    let member_result_context_instance = graph.add_storage(
        "member_result_context_instance",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let member_result_ref_tag = graph.add_storage(
        "member_result_ref_tag",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let member_result_ref_payload = graph.add_storage(
        "member_result_ref_payload",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let member_result_field_ordinal = graph.add_storage(
        "member_result_field_ordinal",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let member_result_field_node = graph.add_storage(
        "member_result_field_node",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let struct_init_field_context_instance = graph.add_storage(
        "struct_init_field_context_instance",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let struct_init_field_expected_ref_tag = graph.add_storage(
        "struct_init_field_expected_ref_tag",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let struct_init_field_expected_ref_payload = graph.add_storage(
        "struct_init_field_expected_ref_payload",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let struct_init_field_ordinal = graph.add_storage(
        "struct_init_field_ordinal",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let struct_init_field_ordinal_by_node = graph.add_storage(
        "struct_init_field_ordinal_by_node",
        ResourceDomain::RawNodes,
        ResourceClass::Workspace,
        hir_rows * 4,
    )?;
    let struct_init_field_decl_node_by_node = graph.add_storage(
        "struct_init_field_decl_node_by_node",
        ResourceDomain::RawNodes,
        ResourceClass::Workspace,
        hir_rows * 4,
    )?;
    let struct_init_field_ordinal_by_row = graph.add_storage(
        "struct_init_field_ordinal_by_row",
        ResourceDomain::Declarations,
        ResourceClass::Output,
        hir_rows * 4,
    )?;
    let struct_init_field_decl_token_by_row = graph.add_storage(
        "struct_init_field_decl_token_by_row",
        ResourceDomain::Declarations,
        ResourceClass::Workspace,
        hir_rows * 4,
    )?;
    macro_rules! predicate_input_resource {
        ($name:expr, $bytes:expr) => {
            graph.add_storage(
                $name,
                ResourceDomain::HirNodes,
                ResourceClass::Input,
                $bytes,
            )?
        };
    }
    let node_kind = predicate_input_resource!("node_kind", hir_rows * 4);
    let parent = predicate_input_resource!("parent", hir_rows * 4);
    let generic_decl_owner_by_node_a = graph.add_storage(
        "generic_decl_owner_by_node",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        hir_rows * 4,
    )?;
    let generic_decl_owner_by_node_b = graph.add_storage(
        "generic_decl_owner_by_node_b",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        hir_rows * 4,
    )?;
    let predicate_bound_list_by_node_a = graph.add_storage(
        "predicate_bound_list_by_node",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        hir_rows * 4,
    )?;
    let predicate_bound_list_by_node_b = graph.add_storage(
        "predicate_trait_impl_trait_type_node",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        hir_rows * 4,
    )?;
    let generic_decl_parent_jump_a = graph.add_storage(
        "generic_decl_parent_jump_a",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        hir_rows * 4,
    )?;
    let generic_decl_parent_jump_b = graph.add_storage(
        "generic_decl_parent_jump_b",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        hir_rows * 4,
    )?;
    let type_decl_generic_param_count = graph.add_storage(
        "type_decl_generic_param_count",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let type_decl_generic_param_count_by_owner_token = graph.add_storage(
        "type_decl_generic_param_count_by_owner_token",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    let type_decl_const_param_count_by_owner_token = graph.add_storage(
        "type_decl_const_param_count_by_owner_token",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    macro_rules! generic_param_workspace {
        ($name:literal, $bytes:expr) => {
            graph.add_storage(
                $name,
                ResourceDomain::Declarations,
                ResourceClass::Workspace,
                $bytes,
            )?
        };
    }
    let generic_param_count_out = generic_param_workspace!("generic_param_count_out", 4);
    let generic_param_owner_token =
        generic_param_workspace!("generic_param_owner_token", token_rows * 4);
    let generic_param_name_id = generic_param_workspace!("generic_param_name_id", token_rows * 4);
    let generic_param_token = generic_param_workspace!("generic_param_token", token_rows * 4);
    let generic_param_node = generic_param_workspace!("generic_param_node", token_rows * 4);
    let generic_param_kind = generic_param_workspace!("generic_param_kind", token_rows * 4);
    let generic_param_key_order =
        generic_param_workspace!("generic_param_key_order", token_rows * 4);
    let generic_param_key_order_tmp = if token_capacity.max(1) > GENERIC_PARAM_SMALL_SORT_CAPACITY {
        Some(generic_param_workspace!(
            "generic_param_key_order_tmp",
            token_rows * 4
        ))
    } else {
        None
    };
    let generic_param_slot_order =
        generic_param_workspace!("generic_param_slot_order", token_rows * 4);
    let generic_param_slot_order_tmp = if token_capacity.max(1) > GENERIC_PARAM_SMALL_SORT_CAPACITY
    {
        Some(generic_param_workspace!(
            "generic_param_slot_order_tmp",
            token_rows * 4
        ))
    } else {
        None
    };
    let generic_param_radix_rows = token_rows.div_ceil(256) * u64::from(NAME_RADIX_BUCKETS);
    let (
        generic_param_slot_radix_block_histogram,
        generic_param_slot_radix_block_bucket_prefix,
        generic_param_slot_radix_bucket_total,
        generic_param_slot_radix_bucket_base,
    ) = if token_capacity.max(1) > GENERIC_PARAM_SMALL_SORT_CAPACITY {
        (
            Some(generic_param_workspace!(
                "generic_param_slot_radix_block_histogram",
                generic_param_radix_rows * 4
            )),
            Some(generic_param_workspace!(
                "generic_param_slot_radix_block_bucket_prefix",
                generic_param_radix_rows * 4
            )),
            Some(generic_param_workspace!(
                "generic_param_slot_radix_bucket_total",
                u64::from(NAME_RADIX_BUCKETS) * 4
            )),
            Some(generic_param_workspace!(
                "generic_param_slot_radix_bucket_base",
                u64::from(NAME_RADIX_BUCKETS) * 4
            )),
        )
    } else {
        (None, None, None, None)
    };
    let _compact_generic_param_count = predicate_input_resource!("compact_generic_param_count", 4);
    let _compact_generic_params =
        predicate_input_resource!("compact_generic_params", token_rows * 16);
    let _compact_variant_count = predicate_input_resource!("compact_variant_count", 4);
    let _compact_variants = predicate_input_resource!("compact_variants", token_rows * 16);
    let _compact_variant_payload_row_count =
        predicate_input_resource!("compact_variant_payload_row_count", 4);
    let _compact_variant_payloads =
        predicate_input_resource!("compact_variant_payloads", token_rows * 16);
    let _hir_type_len_token = predicate_input_resource!("hir_type_len_token", hir_rows * 4);
    let _hir_nearest_fn_node = predicate_input_resource!("hir_nearest_fn_node", hir_rows * 4);
    for name in [
        "first_child",
        "next_sibling",
        "subtree_end",
        "hir_bound_path_owner_by_leaf",
        "hir_type_arg_start",
        "hir_type_arg_count",
        "hir_type_arg_next",
        "hir_method_impl_receiver_type_node",
        "decl_name_id",
        "decl_namespace",
        "decl_hir_node",
        "decl_visibility",
        "module_table_count_out",
        "sorted_module_key_order",
        "module_key_canonical_id",
        "decl_type_key_to_decl_id",
        "decl_value_key_to_decl_id",
        "decl_module_id",
        "path_segment_name_id",
        "path_prefix_id",
        "path_id_by_owner_token",
        "import_visible_type_key_module_id",
        "import_visible_type_key_name_id",
        "import_visible_type_key_to_decl_id",
        "import_visible_type_status",
        "import_visible_value_key_module_id",
        "import_visible_value_key_name_id",
        "import_visible_value_key_to_decl_id",
        "import_visible_value_status",
        "compact_fn_return_type",
    ] {
        predicate_input_resource!(name, hir_rows * 4);
    }
    predicate_input_resource!("compact_param_ranges", hir_rows * 8);
    predicate_input_resource!("compact_type_arg_count", 4);
    predicate_input_resource!("compact_type_args", hir_rows * 16);
    predicate_input_resource!("compact_type_arg_ranges", hir_rows * 8);
    let predicate_trait_impl_trait_type_node = predicate_bound_list_by_node_b;
    let predicate_owner_node = predicate_workspace_row_resource!("predicate_owner_node");
    let predicate_subject_token = predicate_workspace_row_resource!("predicate_subject_token");
    let predicate_bound_token = predicate_workspace_row_resource!("predicate_bound_token");
    let predicate_bound_decl_id = predicate_workspace_row_resource!("predicate_bound_decl_id");
    let predicate_bound_arg_count = predicate_workspace_row_resource!("predicate_bound_arg_count");
    let predicate_method_contract_owner_hir =
        predicate_workspace_row_resource!("predicate_method_contract_owner_hir");
    let predicate_method_contract_name_token =
        predicate_workspace_row_resource!("predicate_method_contract_name_token");
    let predicate_method_contract_name_id =
        predicate_workspace_row_resource!("predicate_method_contract_name_id");
    let predicate_method_contract_param_count =
        predicate_workspace_row_resource!("predicate_method_contract_param_count");
    let predicate_method_contract_return_type_node =
        predicate_workspace_row_resource!("predicate_method_contract_return_type_node");
    let predicate_method_contract_visibility =
        predicate_workspace_row_resource!("predicate_method_contract_visibility");
    let predicate_method_contract_param_type_node =
        predicate_workspace_row_resource!("predicate_method_contract_param_type_node");
    let predicate_method_contract_key_order =
        predicate_workspace_resource!("predicate_method_contract_key_order", predicate_rows * 4);
    let predicate_method_contract_key_order_tmp = predicate_workspace_resource!(
        "predicate_method_contract_key_order_tmp",
        predicate_rows * 4
    );
    let predicate_method_param_key_order =
        predicate_workspace_resource!("predicate_method_param_key_order", predicate_rows * 4);
    let predicate_method_param_key_order_tmp =
        predicate_workspace_resource!("predicate_method_param_key_order_tmp", predicate_rows * 4);
    let predicate_method_contract_owner_range_first =
        predicate_workspace_row_resource!("predicate_method_contract_owner_range_first");
    let predicate_method_contract_owner_range_count =
        predicate_workspace_row_resource!("predicate_method_contract_owner_range_count");
    let predicate_method_validation_owner_node =
        predicate_workspace_row_resource!("predicate_method_validation_owner_node");
    let predicate_method_validation_peer_node =
        predicate_workspace_row_resource!("predicate_method_validation_peer_node");
    let predicate_owner_key_order =
        predicate_workspace_resource!("predicate_owner_key_order", predicate_rows * 4);
    let predicate_owner_key_order_tmp =
        predicate_workspace_resource!("predicate_owner_key_order_tmp", predicate_rows * 4);
    let predicate_impl_key_order =
        predicate_workspace_resource!("predicate_impl_key_order", predicate_rows * 4);
    let predicate_impl_key_order_tmp =
        predicate_workspace_resource!("predicate_impl_key_order_tmp", predicate_rows * 4);
    let predicate_key_radix_rows = predicate_rows.div_ceil(256) * u64::from(NAME_RADIX_BUCKETS);
    let predicate_key_radix_block_histogram = graph.add_storage(
        "predicate_key_radix_block_histogram",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        predicate_key_radix_rows * 4,
    )?;
    let predicate_key_radix_block_bucket_prefix = graph.add_storage(
        "predicate_key_radix_block_bucket_prefix",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        predicate_key_radix_rows * 4,
    )?;
    let predicate_key_radix_bucket_total = graph.add_storage(
        "predicate_key_radix_bucket_total",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        u64::from(NAME_RADIX_BUCKETS) * 4,
    )?;
    let predicate_key_radix_bucket_base = graph.add_storage(
        "predicate_key_radix_bucket_base",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        u64::from(NAME_RADIX_BUCKETS) * 4,
    )?;
    let predicate_obligation_count_by_call =
        predicate_workspace_resource!("predicate_obligation_count_by_call", predicate_rows * 4);
    let predicate_obligation_prefix_by_call =
        predicate_workspace_resource!("predicate_obligation_prefix_by_call", predicate_rows * 4);
    let predicate_obligation_scan_local_prefix =
        predicate_workspace_resource!("predicate_obligation_scan_local_prefix", predicate_rows * 4);
    let predicate_obligation_scan_block_sum = graph.add_storage(
        "predicate_obligation_scan_block_sum",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        predicate_rows.div_ceil(256) * 4,
    )?;
    let predicate_obligation_scan_prefix_a = graph.add_storage(
        "predicate_obligation_scan_prefix_a",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        predicate_rows.div_ceil(256) * 4,
    )?;
    let predicate_obligation_scan_prefix_b = graph.add_storage(
        "predicate_obligation_scan_prefix_b",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        predicate_rows.div_ceil(256) * 4,
    )?;
    let predicate_obligation_pair_total = graph.add_storage(
        "predicate_obligation_pair_total",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        4,
    )?;
    let predicate_obligation_pair_dispatch_args = graph.add_indirect_storage(
        "predicate_obligation_pair_dispatch_args",
        ResourceDomain::DispatchArguments,
        ResourceClass::Workspace,
        12,
    )?;
    let decl_kind = graph.add_storage(
        "decl_kind",
        ResourceDomain::Declarations,
        ResourceClass::Workspace,
        hir_rows * 4,
    )?;
    let mut external =
        |name, domain, bytes| graph.add_storage(name, domain, ResourceClass::External, bytes);
    macro_rules! workspace_resource {
        ($name:literal, $domain:expr, $bytes:expr) => {
            graph.add_storage($name, $domain, ResourceClass::Workspace, $bytes)?
        };
        ($name:literal, $domain:expr, $bytes:expr, indirect) => {
            graph.add_indirect_storage($name, $domain, ResourceClass::Workspace, $bytes)?
        };
    }
    let resolved_type_decl = external("resolved_type_decl", ResourceDomain::Declarations, 4)?;
    let resolved_type_status = external("resolved_type_status", ResourceDomain::Declarations, 4)?;
    let _resolved_value_decl = external(
        "resolved_value_decl",
        ResourceDomain::Declarations,
        token_rows * 4,
    )?;
    let _resolved_value_status = external(
        "resolved_value_status",
        ResourceDomain::Declarations,
        token_rows * 4,
    )?;
    let module_record_count_out =
        external("module_record_count_out", ResourceDomain::Declarations, 4)?;
    let import_record_count_out =
        external("import_record_count_out", ResourceDomain::Declarations, 4)?;
    let decl_count_out = external("decl_count_out", ResourceDomain::Declarations, 4)?;
    for (name, domain, bytes) in [
        (
            "dependency_visible_count",
            ResourceDomain::Declarations,
            u64::from(module_record_capacity.max(1)) * 4,
        ),
        (
            "dependency_visible_prefix",
            ResourceDomain::Declarations,
            u64::from(module_record_capacity.max(1)) * 4,
        ),
        ("dependency_visible_total", ResourceDomain::Declarations, 4),
        (
            "dependency_call_compare_scan_input",
            ResourceDomain::HirNodes,
            hir_rows * 4,
        ),
        (
            "dependency_call_compare_prefix",
            ResourceDomain::HirNodes,
            hir_rows * 4,
        ),
        ("dependency_call_compare_total", ResourceDomain::HirNodes, 4),
    ] {
        external(name, domain, bytes)?;
    }
    let hir_value_decl_name_present = external(
        "hir_value_decl_name_present",
        ResourceDomain::Declarations,
        (token_rows + u64::from(LANGUAGE_SYMBOL_COUNT)) * 4,
    )?;
    drop(external);
    let fn_start_token_by_decl_token = workspace_resource!(
        "fn_start_token_by_decl_token",
        ResourceDomain::Tokens,
        token_rows * 4
    );
    let backend_call_fn_index = workspace_resource!(
        "backend_call_fn_index",
        ResourceDomain::Tokens,
        token_rows * 4
    );
    let call_intrinsic_tag =
        workspace_resource!("call_intrinsic_tag", ResourceDomain::Tokens, token_rows * 4);
    let call_param_count =
        workspace_resource!("call_param_count", ResourceDomain::Tokens, token_rows * 4);
    workspace_resource!(
        "call_param_type",
        ResourceDomain::CallArguments,
        token_rows * u64::from(CALL_PARAM_CACHE_STRIDE as u32) * 4
    );
    workspace_resource!(
        "call_param_ref_tag",
        ResourceDomain::CallArguments,
        token_rows * u64::from(CALL_PARAM_CACHE_STRIDE as u32) * 4
    );
    workspace_resource!(
        "call_param_ref_payload",
        ResourceDomain::CallArguments,
        token_rows * u64::from(CALL_PARAM_CACHE_STRIDE as u32) * 4
    );
    workspace_resource!(
        "call_generic_slot_type",
        ResourceDomain::CallArguments,
        token_rows * u64::from(CALL_PARAM_CACHE_STRIDE as u32) * 4
    );
    workspace_resource!(
        "call_generic_slot_ordinal",
        ResourceDomain::CallArguments,
        token_rows * u64::from(CALL_PARAM_CACHE_STRIDE as u32) * 4
    );
    workspace_resource!(
        "call_const_slot_len",
        ResourceDomain::CallArguments,
        token_rows * u64::from(CALL_PARAM_CACHE_STRIDE as u32) * 4
    );
    let call_param_row_count_out =
        workspace_resource!("call_param_row_count_out", ResourceDomain::CallArguments, 4);
    for name in [
        "call_param_row_flag",
        "call_param_row_node_type",
        "call_param_row_node_ref_tag",
        "call_param_row_node_ref_payload",
        "call_param_row_node",
        "call_param_row_ordinal",
        "call_param_row_type",
        "call_param_row_ref_tag",
        "call_param_row_ref_payload",
    ] {
        graph.add_storage(
            name,
            ResourceDomain::CallArguments,
            ResourceClass::Workspace,
            call_param_rows * 4,
        )?;
    }
    let call_param_row_fn_token = workspace_resource!(
        "call_param_row_fn_token",
        ResourceDomain::CallArguments,
        call_param_rows * 4
    );
    let call_param_row_start = workspace_resource!(
        "call_param_row_start",
        ResourceDomain::Tokens,
        token_rows * 4
    );
    let call_param_row_count = workspace_resource!(
        "call_param_row_count",
        ResourceDomain::Tokens,
        token_rows * 4
    );
    workspace_resource!(
        "call_arg_record",
        ResourceDomain::CallArguments,
        token_rows * 16
    );
    for name in [
        "call_arg_row_node",
        "call_arg_row_call_node",
        "call_arg_row_ordinal",
    ] {
        graph.add_storage(
            name,
            ResourceDomain::CallArguments,
            ResourceClass::Workspace,
            call_arg_rows * 4,
        )?;
    }
    for name in ["call_arg_row_start", "call_arg_row_count"] {
        graph.add_storage(
            name,
            ResourceDomain::HirNodes,
            ResourceClass::Workspace,
            hir_rows * 4,
        )?;
    }
    workspace_resource!(
        "function_lookup_key",
        ResourceDomain::Declarations,
        token_rows * 2 * 4
    );
    workspace_resource!(
        "function_lookup_fn",
        ResourceDomain::Declarations,
        token_rows * 2 * 4
    );
    let decl_type_key_prefix = workspace_resource!(
        "decl_type_key_prefix",
        ResourceDomain::Declarations,
        hir_rows * 4
    );
    let decl_value_key_prefix = workspace_resource!(
        "decl_value_key_prefix",
        ResourceDomain::Declarations,
        hir_rows * 4
    );
    let decl_type_key_count_out =
        workspace_resource!("decl_type_key_count_out", ResourceDomain::Declarations, 4);
    let decl_value_key_count_out =
        workspace_resource!("decl_value_key_count_out", ResourceDomain::Declarations, 4);
    let decl_status =
        workspace_resource!("decl_status", ResourceDomain::Declarations, hir_rows * 4);
    let import_visible_type_count = workspace_resource!(
        "import_visible_type_count",
        ResourceDomain::Declarations,
        hir_rows * 4
    );
    let import_visible_value_count = workspace_resource!(
        "import_visible_value_count",
        ResourceDomain::Declarations,
        hir_rows * 4
    );
    let import_visible_type_prefix = workspace_resource!(
        "import_visible_type_prefix",
        ResourceDomain::Declarations,
        hir_rows * 4
    );
    let import_visible_value_prefix = workspace_resource!(
        "import_visible_value_prefix",
        ResourceDomain::Declarations,
        hir_rows * 4
    );
    let import_visible_type_count_out = workspace_resource!(
        "import_visible_type_count_out",
        ResourceDomain::Declarations,
        4
    );
    let import_visible_value_count_out = workspace_resource!(
        "import_visible_value_count_out",
        ResourceDomain::Declarations,
        4
    );
    graph.add_indirect_storage(
        "decl_key_radix_dispatch_args",
        ResourceDomain::DispatchArguments,
        ResourceClass::External,
        12,
    )?;
    graph.add_indirect_storage(
        "import_dispatch_args",
        ResourceDomain::DispatchArguments,
        ResourceClass::External,
        12,
    )?;
    let hir_visible_decl_flag = workspace_resource!(
        "hir_visible_decl_flag",
        ResourceDomain::HirNodes,
        hir_rows * 4
    );
    let hir_visible_decl_prefix = workspace_resource!(
        "hir_visible_decl_prefix",
        ResourceDomain::HirNodes,
        hir_rows * 4
    );
    let hir_semantic_dispatch_args = graph.add_indirect_storage(
        "hir_semantic_dispatch_args",
        ResourceDomain::DispatchArguments,
        ResourceClass::Workspace,
        12,
    )?;
    workspace_resource!(
        "hir_visible_decl_scan_local_prefix",
        ResourceDomain::HirNodes,
        hir_rows * 4
    );
    workspace_resource!(
        "hir_visible_decl_scan_block_sum",
        ResourceDomain::HirNodes,
        hir_blocks * 4
    );
    workspace_resource!(
        "hir_visible_decl_scan_prefix_a",
        ResourceDomain::HirNodes,
        hir_blocks * 4
    );
    workspace_resource!(
        "hir_visible_decl_scan_prefix_b",
        ResourceDomain::HirNodes,
        hir_blocks * 4
    );
    let hir_visible_decl_count_out = workspace_resource!(
        "hir_visible_decl_count_out",
        ResourceDomain::Declarations,
        4
    );
    let hir_visible_decl_owner_fn = workspace_resource!(
        "hir_visible_decl_owner_fn",
        ResourceDomain::Declarations,
        token_rows * 4
    );
    let hir_visible_decl_name_id = workspace_resource!(
        "hir_visible_decl_name_id",
        ResourceDomain::Declarations,
        token_rows * 4
    );
    let hir_visible_decl_token = workspace_resource!(
        "hir_visible_decl_token",
        ResourceDomain::Declarations,
        token_rows * 4
    );
    let hir_visible_decl_scope_end = workspace_resource!(
        "hir_visible_decl_scope_end",
        ResourceDomain::Declarations,
        token_rows * 4
    );
    let hir_visible_decl_node = workspace_resource!(
        "hir_visible_decl_node",
        ResourceDomain::Declarations,
        token_rows * 4
    );
    let visible_decl_sort_resources = graph.add_radix_sort_resources(
        hir_visible_decl_count_out,
        vec![
            hir_visible_decl_owner_fn,
            hir_visible_decl_name_id,
            hir_visible_decl_token,
        ],
        ResourceDomain::Declarations,
        token_rows,
        256,
        u64::from(NAME_RADIX_BUCKETS),
        RadixSortGraphResourceNames {
            order: "hir_visible_decl_key_order",
            temporary_order: "hir_visible_decl_key_order_tmp",
            dispatch_args: "hir_visible_decl_key_radix_dispatch_args",
            histogram: "hir_visible_decl_key_radix_block_histogram",
            bucket_prefix: "hir_visible_decl_key_radix_block_bucket_prefix",
            bucket_total: "hir_visible_decl_key_radix_bucket_total",
            bucket_base: "hir_visible_decl_key_radix_bucket_base",
        },
    )?;
    let hir_visible_decl_key_order = visible_decl_sort_resources.order;
    let hir_visible_decl_key_radix_dispatch_args = visible_decl_sort_resources.dispatch_args;
    let hir_visible_decl_key_radix_block_histogram = visible_decl_sort_resources.histogram;
    let hir_visible_decl_key_radix_block_bucket_prefix = visible_decl_sort_resources.bucket_prefix;
    let hir_visible_decl_key_radix_bucket_total = visible_decl_sort_resources.bucket_total;
    let hir_visible_decl_key_radix_bucket_base = visible_decl_sort_resources.bucket_base;
    if token_capacity.max(1) > GENERIC_PARAM_SMALL_SORT_CAPACITY {
        for (alias, resource) in [
            (
                "generic_param_key_radix_block_histogram",
                hir_visible_decl_key_radix_block_histogram,
            ),
            (
                "generic_param_key_radix_block_bucket_prefix",
                hir_visible_decl_key_radix_block_bucket_prefix,
            ),
            (
                "generic_param_key_radix_bucket_total",
                hir_visible_decl_key_radix_bucket_total,
            ),
            (
                "generic_param_key_radix_bucket_base",
                hir_visible_decl_key_radix_bucket_base,
            ),
            (
                "generic_param_key_radix_dispatch_args",
                hir_visible_decl_key_radix_dispatch_args,
            ),
        ] {
            graph.add_resource_alias(alias, resource)?;
        }
    }
    let visible_tree_leaves = token_capacity
        .max(1)
        .div_ceil(HIR_VISIBLE_DECL_ROW_BLOCK_SIZE)
        .max(1);
    let visible_tree_rows = visible_tree_leaves
        .next_power_of_two()
        .saturating_mul(2)
        .max(2);
    let hir_visible_decl_scope_tree = workspace_resource!(
        "hir_visible_decl_scope_tree",
        ResourceDomain::Declarations,
        u64::from(visible_tree_rows) * 4
    );
    let semantic_feature_flags = graph.add_storage(
        "semantic_feature_flags",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        4,
    )?;
    let mut indirect_output = |name| {
        graph.add_resource(ResourceDesc {
            name,
            domain: ResourceDomain::DispatchArguments,
            class: ResourceClass::Output,
            bytes: 12,
            usage: WorkspaceUsageClass::StorageIndirect,
        })
    };
    let _method_token_dispatch_args = indirect_output("method_token_dispatch_args")?;
    indirect_output("method_hir_dispatch_args")?;
    indirect_output("method_compact_dispatch_args")?;
    indirect_output("method_token_hir_dispatch_args")?;
    indirect_output("method_radix_prefix_dispatch_args")?;
    indirect_output("method_radix_bases_dispatch_args")?;
    indirect_output("predicate_token_dispatch_args")?;
    indirect_output("predicate_hir_dispatch_args")?;
    indirect_output("predicate_radix_prefix_dispatch_args")?;
    indirect_output("predicate_radix_bases_dispatch_args")?;
    indirect_output("predicate_single_dispatch_args")?;
    indirect_output("match_hir_dispatch_args")?;
    let scalar_a = graph.add_storage(
        "compact_expr_scalar_type.a",
        ResourceDomain::HirNodes,
        ResourceClass::Output,
        hir_rows * 4,
    )?;
    let scalar_b = graph.add_storage(
        "compact_expr_scalar_type.b",
        ResourceDomain::HirNodes,
        ResourceClass::Output,
        hir_rows * 4,
    )?;
    let status = graph.add_storage("status", ResourceDomain::Bytes, ResourceClass::External, 16)?;
    let return_fn_flags = graph.add_storage(
        "return_fn_flags",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        hir_rows * 4,
    )?;
    let return_block_flags = graph.add_storage(
        "return_block_flags",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        hir_rows * 4,
    )?;
    let call_has_array_arg = graph.add_storage(
        "call_has_array_arg",
        ResourceDomain::Calls,
        ResourceClass::Output,
        hir_rows * 4,
    )?;
    let call_result_instance = graph.add_storage(
        "call_result_instance",
        ResourceDomain::Calls,
        ResourceClass::Output,
        hir_rows * 4,
    )?;
    let call_generic_return_arg_node = graph.add_storage(
        "call_generic_return_arg_node",
        ResourceDomain::Calls,
        ResourceClass::Output,
        hir_rows * 4,
    )?;
    let call_arg_param_row = graph.add_storage(
        "call_arg_param_row",
        ResourceDomain::CallArguments,
        ResourceClass::Workspace,
        call_arg_rows * 4,
    )?;
    let mut required_workspace = |name, domain, bytes, usage| {
        graph.add_resource(ResourceDesc {
            name,
            domain,
            class: ResourceClass::Workspace,
            bytes,
            usage,
        })
    };
    let member_next_node = required_workspace(
        "member_next_node",
        ResourceDomain::HirNodes,
        hir_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let if_blocks = token_rows.div_ceil(256);
    let if_delta = required_workspace(
        "if_delta",
        ResourceDomain::Tokens,
        (token_rows + 1) * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let if_depth_inblock = required_workspace(
        "if_depth_inblock",
        ResourceDomain::Tokens,
        token_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let if_block_sum = required_workspace(
        "if_block_sum",
        ResourceDomain::Tokens,
        if_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let if_prefix_a = required_workspace(
        "if_prefix_a",
        ResourceDomain::Tokens,
        if_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let if_prefix_b = required_workspace(
        "if_prefix_b",
        ResourceDomain::Tokens,
        if_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let if_block_prefix = required_workspace(
        "if_block_prefix",
        ResourceDomain::Tokens,
        if_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let if_depth = required_workspace(
        "if_depth",
        ResourceDomain::Tokens,
        token_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let enclosing_fn = required_workspace(
        "enclosing_fn",
        ResourceDomain::Tokens,
        token_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let enclosing_fn_end = required_workspace(
        "enclosing_fn_end",
        ResourceDomain::Tokens,
        token_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let fn_event_value = required_workspace(
        "fn_event_value",
        ResourceDomain::Tokens,
        (token_rows + 1) * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let fn_event_end = required_workspace(
        "fn_event_end",
        ResourceDomain::Tokens,
        (token_rows + 1) * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let fn_event_index = required_workspace(
        "fn_event_index",
        ResourceDomain::Tokens,
        (token_rows + 1) * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let fn_event_inblock = required_workspace(
        "fn_event_inblock",
        ResourceDomain::Tokens,
        token_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let fn_block_sum = required_workspace(
        "fn_block_sum",
        ResourceDomain::Tokens,
        if_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let fn_prefix_a = required_workspace(
        "fn_prefix_a",
        ResourceDomain::Tokens,
        if_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let fn_prefix_b = required_workspace(
        "fn_prefix_b",
        ResourceDomain::Tokens,
        if_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let fn_block_prefix = required_workspace(
        "fn_block_prefix",
        ResourceDomain::Tokens,
        if_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
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
    let generic_claim_callee = required_workspace(
        "call_generic_claim_callee",
        ResourceDomain::CallArguments,
        claim_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let generic_claim_slot = required_workspace(
        "call_generic_claim_slot",
        ResourceDomain::CallArguments,
        claim_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let generic_claim_type = required_workspace(
        "call_generic_claim_type",
        ResourceDomain::CallArguments,
        claim_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let generic_claim_ref_tag = required_workspace(
        "call_generic_claim_ref_tag",
        ResourceDomain::CallArguments,
        claim_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let generic_claim_ref_payload = required_workspace(
        "call_generic_claim_ref_payload",
        ResourceDomain::CallArguments,
        claim_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let generic_claim_arg_row = required_workspace(
        "call_generic_claim_arg_row",
        ResourceDomain::CallArguments,
        claim_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let generic_claim_order = required_workspace(
        "call_generic_claim_order",
        ResourceDomain::CallArguments,
        claim_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let generic_claim_order_tmp = required_workspace(
        "call_generic_claim_order_tmp",
        ResourceDomain::CallArguments,
        claim_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let generic_claim_radix_dispatch_args = required_workspace(
        "call_generic_claim_radix_dispatch_args",
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
    // Both claim sorts execute sequentially through the same radix operation.
    // Scratch belongs to that operation, not to the semantic key family.
    let const_claim_radix_block_histogram = generic_claim_radix_block_histogram;
    let const_claim_radix_block_bucket_prefix = generic_claim_radix_block_bucket_prefix;
    let const_claim_radix_bucket_total = generic_claim_radix_bucket_total;
    let const_claim_radix_bucket_base = generic_claim_radix_bucket_base;
    let const_claim_callee = required_workspace(
        "call_const_claim_callee",
        ResourceDomain::CallArguments,
        call_arg_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let const_claim_slot = required_workspace(
        "call_const_claim_slot",
        ResourceDomain::CallArguments,
        call_arg_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let const_claim_len = required_workspace(
        "call_const_claim_len",
        ResourceDomain::CallArguments,
        call_arg_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let const_claim_order = required_workspace(
        "call_const_claim_order",
        ResourceDomain::CallArguments,
        call_arg_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let const_claim_order_tmp = required_workspace(
        "call_const_claim_order_tmp",
        ResourceDomain::CallArguments,
        call_arg_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    let const_claim_radix_dispatch_args = required_workspace(
        "call_const_claim_radix_dispatch_args",
        ResourceDomain::DispatchArguments,
        12,
        WorkspaceUsageClass::StorageIndirect,
    )?;
    let call_arg_row_count_out = graph.add_storage(
        "call_arg_row_count_out",
        ResourceDomain::CallArguments,
        ResourceClass::Output,
        4,
    )?;
    let generic_claim_count_out = graph.add_storage(
        "call_generic_claim_count_out",
        ResourceDomain::CallArguments,
        ResourceClass::Output,
        4,
    )?;
    let semantic_value_decl_by_hir = graph.add_storage(
        "semantic_value_decl_by_hir",
        ResourceDomain::HirNodes,
        ResourceClass::Output,
        hir_rows * 4,
    )?;
    let semantic_value_type_by_hir = graph.add_storage(
        "semantic_value_type_by_hir",
        ResourceDomain::HirNodes,
        ResourceClass::Output,
        hir_rows * 4,
    )?;
    let semantic_param_type_by_row = graph.add_storage(
        "semantic_param_type_by_row",
        ResourceDomain::Declarations,
        ResourceClass::Output,
        hir_rows * 4,
    )?;
    let semantic_enclosing_fn_by_hir = graph.add_storage(
        "semantic_enclosing_fn_by_hir",
        ResourceDomain::HirNodes,
        ResourceClass::Output,
        hir_rows * 4,
    )?;
    let semantic_function_return_type_by_hir = graph.add_storage(
        "semantic_function_return_type_by_hir",
        ResourceDomain::HirNodes,
        ResourceClass::Output,
        hir_rows * 4,
    )?;
    let semantic_function_entrypoint_by_hir = graph.add_storage(
        "semantic_function_entrypoint_by_hir",
        ResourceDomain::HirNodes,
        ResourceClass::Output,
        hir_rows * 4,
    )?;
    let semantic_function_host_service_by_hir = graph.add_storage(
        "semantic_function_host_service_by_hir",
        ResourceDomain::HirNodes,
        ResourceClass::Output,
        hir_rows * 4,
    )?;
    let semantic_control_depth_by_hir = graph.add_storage(
        "semantic_control_depth_by_hir",
        ResourceDomain::HirNodes,
        ResourceClass::Output,
        hir_rows * 4,
    )?;
    let semantic_calls_by_hir = graph.add_storage(
        "semantic_calls_by_hir",
        ResourceDomain::Calls,
        ResourceClass::Output,
        hir_rows * std::mem::size_of::<GpuCheckedCallArtifact>() as u64,
    )?;
    let semantic_expr_ref_tag_by_hir = graph.add_storage(
        "semantic_expr_ref_tag_by_hir",
        ResourceDomain::HirNodes,
        ResourceClass::Output,
        hir_rows * 4,
    )?;
    let semantic_expr_ref_payload_by_hir = graph.add_storage(
        "semantic_expr_ref_payload_by_hir",
        ResourceDomain::HirNodes,
        ResourceClass::Output,
        hir_rows * 4,
    )?;
    let semantic_array_length_by_hir = graph.add_storage(
        "semantic_array_length_by_hir",
        ResourceDomain::HirNodes,
        ResourceClass::Output,
        hir_rows * 4,
    )?;
    let semantic_member_field_ordinal_by_hir = graph.add_storage(
        "semantic_member_field_ordinal_by_hir",
        ResourceDomain::HirNodes,
        ResourceClass::Output,
        hir_rows * 4,
    )?;
    let compact_predicate_diagnostic_facts = graph.add_storage(
        "compact_predicate_diagnostic_facts",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        hir_rows * 32,
    )?;
    // Aggregate and recursive-subtree comparison are currently invoked at
    // several noncontiguous points by the resident recorder. Until those
    // invocations are emitted from one graph schedule, their logical rows
    // must not alias unrelated workspace between modeled occurrences.
    let comparison_resident_u32 = |name| ResourceDesc {
        name,
        domain: ResourceDomain::HirNodes,
        class: ResourceClass::Resident,
        bytes: hir_rows * 4,
        usage: WorkspaceUsageClass::Storage,
    };
    let hir_workspace_u32 = |name| ResourceDesc {
        name,
        domain: ResourceDomain::HirNodes,
        class: ResourceClass::Workspace,
        bytes: hir_rows * 4,
        usage: WorkspaceUsageClass::Storage,
    };
    let aggregate_compare_scan_input =
        graph.add_resource(comparison_resident_u32("aggregate_compare_scan_input"))?;
    let aggregate_compare_expected_instance = graph.add_resource(comparison_resident_u32(
        "aggregate_compare_expected_instance",
    ))?;
    let aggregate_compare_actual_instance =
        graph.add_resource(comparison_resident_u32("aggregate_compare_actual_instance"))?;
    let aggregate_compare_error_token =
        graph.add_resource(comparison_resident_u32("aggregate_compare_error_token"))?;
    let aggregate_compare_error_detail =
        graph.add_resource(comparison_resident_u32("aggregate_compare_error_detail"))?;
    let aggregate_compare_prefix =
        graph.add_resource(comparison_resident_u32("aggregate_compare_prefix"))?;
    let aggregate_compare_count_out = graph.add_storage(
        "aggregate_compare_count_out",
        ResourceDomain::HirNodes,
        ResourceClass::Resident,
        4,
    )?;
    let aggregate_blocks = hir_rows.div_ceil(256);
    let aggregate_compare_scan_local_prefix = graph.add_resource(comparison_resident_u32(
        "aggregate_compare_scan_local_prefix",
    ))?;
    let aggregate_compare_scan_block_sum = graph.add_storage(
        "aggregate_compare_scan_block_sum",
        ResourceDomain::HirNodes,
        ResourceClass::Resident,
        aggregate_blocks * 4,
    )?;
    let aggregate_compare_scan_prefix_a = graph.add_storage(
        "aggregate_compare_scan_prefix_a",
        ResourceDomain::HirNodes,
        ResourceClass::Resident,
        aggregate_blocks * 4,
    )?;
    let aggregate_compare_scan_prefix_b = graph.add_storage(
        "aggregate_compare_scan_prefix_b",
        ResourceDomain::HirNodes,
        ResourceClass::Resident,
        aggregate_blocks * 4,
    )?;
    let aggregate_compare_dispatch_args = graph.add_indirect_storage(
        "aggregate_compare_dispatch_args",
        ResourceDomain::HirNodes,
        ResourceClass::Resident,
        12,
    )?;
    let hir_semantic_count = graph.add_storage(
        "hir_semantic_count",
        ResourceDomain::HirNodes,
        ResourceClass::Input,
        4,
    )?;
    for name in [
        "hir_type_form",
        "hir_type_path_leaf_node",
        "hir_semantic_dense_node",
    ] {
        graph.add_storage(
            name,
            ResourceDomain::HirNodes,
            ResourceClass::Input,
            hir_rows * 4,
        )?;
    }
    graph.add_storage(
        "hir_semantic_subtree_end",
        ResourceDomain::HirNodes,
        ResourceClass::Input,
        4,
    )?;
    let type_semantic_row_by_token = graph.add_storage(
        "type_semantic_row_by_token",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        (token_capacity.max(1) as u64) * 4,
    )?;
    let type_semantic_scan_input =
        graph.add_resource(hir_workspace_u32("type_semantic_scan_input"))?;
    let type_semantic_prefix = graph.add_resource(hir_workspace_u32("type_semantic_prefix"))?;
    let type_semantic_count_out = graph.add_storage(
        "type_semantic_count_out",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        4,
    )?;
    let type_semantic_row_by_ordinal =
        graph.add_resource(hir_workspace_u32("type_semantic_row_by_ordinal"))?;
    let type_subtree_compare_scan_input =
        graph.add_resource(comparison_resident_u32("type_subtree_compare_scan_input"))?;
    let type_subtree_compare_prefix =
        graph.add_resource(comparison_resident_u32("type_subtree_compare_prefix"))?;
    let type_subtree_compare_count_out = graph.add_storage(
        "type_subtree_compare_count_out",
        ResourceDomain::HirNodes,
        ResourceClass::Resident,
        4,
    )?;
    let type_subtree_compare_left_root =
        graph.add_resource(comparison_resident_u32("type_subtree_compare_left_root"))?;
    let type_subtree_compare_right_root =
        graph.add_resource(comparison_resident_u32("type_subtree_compare_right_root"))?;
    let type_subtree_compare_error_token =
        graph.add_resource(comparison_resident_u32("type_subtree_compare_error_token"))?;
    let type_subtree_compare_error_detail =
        graph.add_resource(comparison_resident_u32("type_subtree_compare_error_detail"))?;
    let type_subtree_compare_dispatch_args = graph.add_indirect_storage(
        "type_subtree_compare_dispatch_args",
        ResourceDomain::HirNodes,
        ResourceClass::Resident,
        12,
    )?;
    let resources = ExpressionTypeResources {
        call_return_type,
        call_return_type_token,
        fn_entrypoint_tag,
        enclosing_fn,
        call_fn_index,
        method_decl_method_row,
        method_decl_receiver_ref_tag,
        method_decl_receiver_ref_payload,
        method_decl_module_id,
        method_decl_name_token,
        method_decl_name_id,
        method_decl_param_offset,
        method_decl_receiver_mode,
        method_decl_visibility,
        method_decl_signature_flags,
        type_instance_kind,
        type_instance_head_token,
        type_instance_state,
        type_instance_arg_start,
        type_instance_arg_count,
        type_instance_arg_ref_tag,
        type_instance_arg_ref_payload,
        type_instance_arg_hash,
        method_key_to_fn_token,
        method_key_order_tmp,
        method_key_status,
        method_key_duplicate_of,
        method_key_radix_block_histogram,
        method_key_radix_block_bucket_prefix,
        method_key_radix_bucket_total,
        method_key_radix_bucket_base,
        type_instance_arg_row_start,
        type_instance_arg_row_count_out,
        type_instance_arg_row_ref_tag,
        type_instance_arg_row_ref_payload,
        type_instance_arg_row_scan_local_prefix,
        type_instance_arg_row_scan_block_sum,
        type_instance_arg_row_scan_prefix_a,
        type_instance_arg_row_scan_prefix_b,
        type_instance_elem_ref_tag,
        type_instance_elem_ref_payload,
        method_call_receiver_ref_tag,
        method_call_receiver_ref_payload,
        method_call_name_id,
        method_call_site_module_id,
        predicate_syntax_token,
        generic_decl_owner_by_node_a,
        generic_decl_owner_by_node_b,
        predicate_bound_list_by_node_a,
        predicate_bound_list_by_node_b,
        generic_decl_parent_jump_a,
        generic_decl_parent_jump_b,
        type_decl_generic_param_count,
        type_decl_generic_param_count_by_owner_token,
        type_decl_const_param_count_by_owner_token,
        generic_param_count_out,
        generic_param_owner_token,
        generic_param_name_id,
        generic_param_token,
        generic_param_node,
        generic_param_kind,
        generic_param_key_order,
        generic_param_key_order_tmp,
        generic_param_slot_order,
        generic_param_slot_order_tmp,
        generic_param_slot_radix_block_histogram,
        generic_param_slot_radix_block_bucket_prefix,
        generic_param_slot_radix_bucket_total,
        generic_param_slot_radix_bucket_base,
        type_expr_ref_tag,
        type_expr_ref_payload,
        member_result_context_instance,
        member_result_ref_tag,
        member_result_ref_payload,
        member_result_field_ordinal,
        member_result_field_node,
        struct_init_field_context_instance,
        struct_init_field_expected_ref_tag,
        struct_init_field_expected_ref_payload,
        struct_init_field_ordinal,
        struct_init_field_ordinal_by_node,
        struct_init_field_decl_node_by_node,
        struct_init_field_ordinal_by_row,
        struct_init_field_decl_token_by_row,
        struct_field_key_order,
        struct_field_key_order_tmp,
        struct_field_key_radix_dispatch_args,
        struct_field_key_radix_block_histogram,
        struct_field_key_radix_block_bucket_prefix,
        struct_field_key_radix_bucket_total,
        struct_field_key_radix_bucket_base,
        struct_lit_context_decl_token,
        struct_lit_context_instance,
        array_element_struct_literal_node,
        type_generic_param_slot_by_token,
        type_const_param_slot_by_token,
        type_decl_hir_node_by_token,
        type_instance_len_kind,
        type_instance_len_payload,
        predicate_owner_node,
        predicate_subject_token,
        predicate_bound_token,
        predicate_bound_decl_id,
        predicate_bound_arg_count,
        predicate_bound_first_arg_token,
        predicate_bound_second_arg_token,
        predicate_status,
        predicate_method_contract_owner_hir,
        predicate_method_contract_name_token,
        predicate_method_contract_name_id,
        predicate_method_contract_param_count,
        predicate_method_contract_return_type_node,
        predicate_method_contract_visibility,
        predicate_method_contract_status,
        predicate_method_contract_param_type_node,
        predicate_method_contract_owner_range_first,
        predicate_method_contract_owner_range_count,
        predicate_method_validation_owner_node,
        predicate_method_validation_peer_node,
        predicate_method_validation_first_error_row,
        predicate_method_validation_status,
        predicate_method_validation_detail_token,
        predicate_method_contract_key_order,
        predicate_method_contract_key_order_tmp,
        predicate_method_param_key_order,
        predicate_method_param_key_order_tmp,
        predicate_owner_key_order,
        predicate_owner_key_order_tmp,
        predicate_impl_key_order,
        predicate_impl_key_order_tmp,
        predicate_key_radix_block_histogram,
        predicate_key_radix_block_bucket_prefix,
        predicate_key_radix_bucket_total,
        predicate_key_radix_bucket_base,
        predicate_obligation_count_by_call,
        predicate_obligation_prefix_by_call,
        predicate_obligation_scan_local_prefix,
        predicate_obligation_scan_block_sum,
        predicate_obligation_scan_prefix_a,
        predicate_obligation_scan_prefix_b,
        predicate_obligation_pair_total,
        predicate_obligation_pair_dispatch_args,
        compact_predicate_diagnostic_facts,
        if_delta,
        if_depth_inblock,
        if_block_sum,
        if_prefix_a,
        if_prefix_b,
        if_block_prefix,
        if_depth,
        enclosing_fn_end,
        fn_event_value,
        fn_event_end,
        fn_event_index,
        fn_event_inblock,
        fn_block_sum,
        fn_prefix_a,
        fn_prefix_b,
        fn_block_prefix,
        member_next_node,
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
        generic_claim_callee,
        generic_claim_slot,
        generic_claim_type,
        generic_claim_ref_tag,
        generic_claim_ref_payload,
        generic_claim_arg_row,
        generic_claim_order,
        generic_claim_order_tmp,
        generic_claim_radix_dispatch_args,
        generic_claim_radix_block_histogram,
        generic_claim_radix_block_bucket_prefix,
        generic_claim_radix_bucket_total,
        generic_claim_radix_bucket_base,
        const_claim_radix_block_histogram,
        const_claim_radix_block_bucket_prefix,
        const_claim_radix_bucket_total,
        const_claim_radix_bucket_base,
        const_claim_callee,
        const_claim_slot,
        const_claim_len,
        const_claim_order,
        const_claim_order_tmp,
        const_claim_radix_dispatch_args,
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
        semantic_function_return_type_by_hir,
        semantic_function_entrypoint_by_hir,
        semantic_function_host_service_by_hir,
        semantic_control_depth_by_hir,
        semantic_calls_by_hir,
        semantic_expr_ref_tag_by_hir,
        semantic_expr_ref_payload_by_hir,
        semantic_array_length_by_hir,
        semantic_member_field_ordinal_by_hir,
        type_semantic_row_by_token,
        type_semantic_scan_input,
        type_semantic_prefix,
        type_semantic_count_out,
        type_semantic_row_by_ordinal,
        aggregate_compare_scan_input,
        aggregate_compare_expected_instance,
        aggregate_compare_actual_instance,
        aggregate_compare_error_token,
        aggregate_compare_error_detail,
        aggregate_compare_prefix,
        aggregate_compare_count_out,
        aggregate_compare_scan_local_prefix,
        aggregate_compare_scan_block_sum,
        aggregate_compare_scan_prefix_a,
        aggregate_compare_scan_prefix_b,
        aggregate_compare_dispatch_args,
        type_subtree_compare_scan_input,
        type_subtree_compare_prefix,
        type_subtree_compare_count_out,
        type_subtree_compare_left_root,
        type_subtree_compare_right_root,
        type_subtree_compare_error_token,
        type_subtree_compare_error_detail,
        type_subtree_compare_dispatch_args,
    };
    graph.add_reflected_compute_pass_by_name(
        LANGUAGE_NAMES_CLEAR_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        reflections.language_names_clear,
        &[ReflectedResourceBinding {
            binding: "name_max_len",
            resource: name_max_len,
            mode: Some(AccessMode::Write),
        }],
    )?;
    graph.add_reflected_compute_pass_by_name(
        NAMES_MARK_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        reflections.names_mark,
        &[
            ReflectedResourceBinding {
                binding: "name_lexeme_flag",
                resource: name_lexeme_flag,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "name_lexeme_kind",
                resource: name_lexeme_kind,
                mode: Some(AccessMode::Write),
            },
        ],
    )?;
    NAMES_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(token_blocks))?;
    graph.add_reflected_compute_pass_by_name(
        NAMES_SCATTER_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        reflections.names_scatter,
        &[
            ReflectedResourceBinding {
                binding: "name_order_in",
                resource: name_hash_lo,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "name_order_tmp",
                resource: name_hash_hi,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "name_spans",
                resource: name_spans,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "name_count_out",
                resource: name_scan_total,
                mode: Some(AccessMode::ReadWrite),
            },
            ReflectedResourceBinding {
                binding: "name_max_len_out",
                resource: name_max_len,
                mode: Some(AccessMode::ReadWrite),
            },
        ],
    )?;
    graph.add_reflected_compute_pass_by_name(
        NAMES_HASH_PREPARE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        reflections.names_hash_prepare,
        &[
            ReflectedResourceBinding {
                binding: "name_count_in",
                resource: name_scan_total,
                mode: Some(AccessMode::Read),
            },
            ReflectedResourceBinding {
                binding: "name_hash_table_a",
                resource: name_hash_table_a,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "name_hash_table_b",
                resource: name_hash_table_b,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "name_hash_lo",
                resource: name_hash_lo,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "name_hash_hi",
                resource: name_hash_hi,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "unique_name_count",
                resource: unique_name_count,
                mode: Some(AccessMode::Write),
            },
        ],
    )?;
    graph.add_reflected_compute_pass_by_name(
        NAMES_HASH_INSERT_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        reflections.names_hash_insert,
        &[
            ReflectedResourceBinding {
                binding: "name_count_in",
                resource: name_scan_total,
                mode: Some(AccessMode::Read),
            },
            ReflectedResourceBinding {
                binding: "name_hash_table_a",
                resource: name_hash_table_a,
                mode: Some(AccessMode::ReadWrite),
            },
            ReflectedResourceBinding {
                binding: "name_hash_table_b",
                resource: name_hash_table_b,
                mode: Some(AccessMode::ReadWrite),
            },
        ],
    )?;
    graph.add_reflected_compute_pass_by_name(
        NAMES_HASH_ASSIGN_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        reflections.names_hash_assign,
        &[
            ReflectedResourceBinding {
                binding: "name_count_in",
                resource: name_scan_total,
                mode: Some(AccessMode::Read),
            },
            ReflectedResourceBinding {
                binding: "sorted_name_id",
                resource: sorted_name_id,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "name_id_by_input",
                resource: name_id_by_input,
                mode: Some(AccessMode::Write),
            },
        ],
    )?;
    graph.add_reflected_compute_pass_by_name(
        LANGUAGE_TYPE_CODES_CLEAR_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        reflections.language_type_codes_clear,
        &[],
    )?;
    graph.add_reflected_compute_pass_by_name(
        LANGUAGE_DECLS_MATERIALIZE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        reflections.language_decls_materialize,
        &[],
    )?;
    // Record-family extraction reuses one flag, prefix, and hierarchy workspace
    // across the module, import, and declaration scans. Each scan is a semantic
    // graph operation; callers do not reproduce its internal access modes.
    graph.add_pass(PassDesc {
        name: MODULE_RECORD_SCAN_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::write("module_record_family_bits", module_record_family_bits),
            PassAccess::write("module_record_family_flag", module_record_family_flag),
        ],
    })?;
    let record_scan_levels = prefix_scan_hierarchy_levels(hir_blocks);
    MODULE_RECORD_SCAN.register(&mut graph, record_scan_levels)?;
    graph.add_pass(PassDesc {
        name: MODULE_RECORD_SCAN_CONSUME_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::read("module_record_prefix", module_record_prefix),
            PassAccess::read("module_record_count_out", module_record_count_out),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: IMPORT_RECORD_SCAN_PREPARE_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("module_record_family_bits", module_record_family_bits),
            PassAccess::write("module_record_family_flag", module_record_family_flag),
        ],
    })?;
    IMPORT_RECORD_SCAN.register(&mut graph, record_scan_levels)?;
    graph.add_pass(PassDesc {
        name: IMPORT_RECORD_SCAN_CONSUME_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::read("module_record_prefix", module_record_prefix),
            PassAccess::read("import_record_count_out", import_record_count_out),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: DECL_RECORD_SCAN_PREPARE_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("module_record_family_bits", module_record_family_bits),
            PassAccess::write("module_record_family_flag", module_record_family_flag),
        ],
    })?;
    DECL_RECORD_SCAN.register(&mut graph, record_scan_levels)?;
    graph.add_pass(PassDesc {
        name: MODULE_PATH_KEY_RADIX_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::write(
                "module_path_key_radix_block_histogram",
                module_path_key_radix_block_histogram,
            ),
            PassAccess::write(
                "module_path_key_radix_block_bucket_prefix",
                module_path_key_radix_block_bucket_prefix,
            ),
            PassAccess::write(
                "module_path_key_radix_bucket_total",
                module_path_key_radix_bucket_total,
            ),
            PassAccess::write(
                "module_path_key_radix_bucket_base",
                module_path_key_radix_bucket_base,
            ),
        ],
    })?;
    // Declaration materialization consumes the record-scan region and leaves
    // compact lookup relations live for calls, predicates, and interfaces.
    graph.add_pass(PassDesc {
        name: MODULE_DECL_ROWS_MATERIALIZE_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::read("name_id_by_token", name_id_by_token),
            PassAccess::read("module_record_family_bits", module_record_family_bits),
            PassAccess::read("module_record_prefix", module_record_prefix),
            PassAccess::read("decl_count_out", decl_count_out),
            // Module construction temporarily stores namespace flags in the
            // future type-instance argument columns. Naming both the runtime
            // role and the graph resource makes that early lifetime explicit.
            PassAccess::write("decl_type_key_flag", type_instance_arg_ref_tag),
            PassAccess::write("decl_value_key_flag", type_instance_arg_ref_payload),
            PassAccess::write(
                "decl_duplicate_of",
                type_decl_generic_param_count_by_owner_token,
            ),
            PassAccess::write("decl_status", decl_status),
            PassAccess::read_write(
                "module_path_key_radix_block_histogram",
                module_path_key_radix_block_histogram,
            ),
            PassAccess::read_write(
                "module_path_key_radix_block_bucket_prefix",
                module_path_key_radix_block_bucket_prefix,
            ),
            PassAccess::read_write(
                "module_path_key_radix_bucket_total",
                module_path_key_radix_bucket_total,
            ),
            PassAccess::read_write(
                "module_path_key_radix_bucket_base",
                module_path_key_radix_bucket_base,
            ),
            PassAccess::write("decl_name_token", decl_name_token),
            PassAccess::write("decl_id_by_name_token", decl_id_by_name_token),
            PassAccess::write("decl_kind", decl_kind),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: DECL_NAMESPACE_MARK_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::write("decl_type_key_flag", type_instance_arg_ref_tag),
            PassAccess::write("decl_value_key_flag", type_instance_arg_ref_payload),
        ],
    })?;
    DECL_NAMESPACE_SCAN.register(&mut graph, record_scan_levels)?;
    graph.add_pass(PassDesc {
        name: DECL_NAMESPACE_CONSUME_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::read("decl_type_key_prefix", decl_type_key_prefix),
            PassAccess::read("decl_type_key_count_out", decl_type_key_count_out),
            PassAccess::read("decl_value_key_prefix", decl_value_key_prefix),
            PassAccess::read("decl_value_key_count_out", decl_value_key_count_out),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: DECL_PUBLIC_MARK_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::write("decl_type_key_flag", type_instance_arg_ref_tag),
            PassAccess::write("decl_value_key_flag", type_instance_arg_ref_payload),
        ],
    })?;
    DECL_PUBLIC_SCAN.register(&mut graph, record_scan_levels)?;
    graph.add_pass(PassDesc {
        name: DECL_PUBLIC_CONSUME_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::read("decl_status", decl_status),
            PassAccess::read(
                "import_visible_type_count_out",
                import_visible_type_count_out,
            ),
            PassAccess::read(
                "type_decl_generic_param_count_by_owner_token",
                type_decl_generic_param_count_by_owner_token,
            ),
            PassAccess::read(
                "import_visible_value_count_out",
                import_visible_value_count_out,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: IMPORT_VISIBILITY_COUNT_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::read("decl_type_key_count_out", decl_type_key_count_out),
            PassAccess::read("decl_value_key_count_out", decl_value_key_count_out),
            PassAccess::read("decl_type_key_flag", type_instance_arg_ref_tag),
            PassAccess::read("decl_value_key_flag", type_instance_arg_ref_payload),
            PassAccess::read("decl_status", decl_status),
            PassAccess::read(
                "type_decl_generic_param_count_by_owner_token",
                type_decl_generic_param_count_by_owner_token,
            ),
            PassAccess::write("import_visible_type_count", import_visible_type_count),
            PassAccess::write("import_visible_value_count", import_visible_value_count),
        ],
    })?;
    IMPORT_VISIBLE_SCAN.register(&mut graph, record_scan_levels)?;
    graph.add_pass(PassDesc {
        name: IMPORT_VISIBLE_CONSUME_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::read("import_visible_type_count", import_visible_type_count),
            PassAccess::read("import_visible_type_prefix", import_visible_type_prefix),
            PassAccess::read(
                "import_visible_type_count_out",
                import_visible_type_count_out,
            ),
            PassAccess::read("import_visible_value_count", import_visible_value_count),
            PassAccess::read("import_visible_value_prefix", import_visible_value_prefix),
            PassAccess::read(
                "import_visible_value_count_out",
                import_visible_value_count_out,
            ),
        ],
    })?;
    DEPENDENCY_VISIBLE_SCAN.register(&mut graph, record_scan_levels)?;
    for resource in [decl_name_token, decl_id_by_name_token, decl_kind] {
        graph.fence_resource_lifetime(
            resource,
            MODULE_DECL_ROWS_MATERIALIZE_PASS,
            SEMANTIC_ARTIFACT_PROJECT_PASS,
        )?;
    }
    // Module indexing still reads exact source-name spans and hashes before
    // its passes are represented individually in this graph. Keep those
    // source-name inputs alive through that conservative boundary.
    for resource in [name_spans, name_hash_lo, name_hash_hi] {
        graph.fence_resource_lifetime(
            resource,
            NAMES_MARK_PASS,
            TYPE_INSTANCE_ARG_ROW_CLEAR_PASS,
        )?;
    }
    if let Some(predicate_reflections) = reflections.predicates {
        graph.add_reflected_compute_pass_by_name(
            PREDICATES_CLEAR_SYNTAX_TOKENS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::Tokens,
            predicate_reflections.clear_syntax_tokens,
            &[ReflectedResourceBinding {
                binding: "predicate_syntax_token",
                resource: predicate_syntax_token,
                mode: Some(AccessMode::Write),
            }],
        )?;
    }
    // The physical clear shader initializes the complete type-instance table
    // before any collection pass. Keep the argument family in that same
    // lifetime position even while the remaining clear surface is migrated.
    graph.add_pass(PassDesc {
        name: TYPE_INSTANCE_ARG_ROW_CLEAR_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Tokens,
        accesses: vec![
            PassAccess::write("type_expr_ref_tag", type_expr_ref_tag),
            PassAccess::write("type_expr_ref_payload", type_expr_ref_payload),
            PassAccess::write(
                "type_decl_generic_param_count",
                type_decl_generic_param_count,
            ),
            PassAccess::write(
                "type_decl_generic_param_count_by_owner_token",
                type_decl_generic_param_count_by_owner_token,
            ),
            PassAccess::write(
                "type_decl_const_param_count_by_owner_token",
                type_decl_const_param_count_by_owner_token,
            ),
            PassAccess::write("type_decl_hir_node_by_token", type_decl_hir_node_by_token),
            PassAccess::write(
                "type_generic_param_slot_by_token",
                type_generic_param_slot_by_token,
            ),
            PassAccess::write(
                "type_const_param_slot_by_token",
                type_const_param_slot_by_token,
            ),
            PassAccess::write("type_instance_head_token", type_instance_head_token),
            PassAccess::write("type_instance_kind", type_instance_kind),
            PassAccess::write("type_instance_state", type_instance_state),
            PassAccess::write("type_instance_elem_ref_tag", type_instance_elem_ref_tag),
            PassAccess::write(
                "type_instance_elem_ref_payload",
                type_instance_elem_ref_payload,
            ),
            PassAccess::write("type_instance_len_kind", type_instance_len_kind),
            PassAccess::write("type_instance_len_payload", type_instance_len_payload),
            PassAccess::write("type_instance_arg_start", type_instance_arg_start),
            PassAccess::write("type_instance_arg_count", type_instance_arg_count),
            PassAccess::write("type_instance_arg_ref_tag", type_instance_arg_ref_tag),
            PassAccess::write(
                "type_instance_arg_ref_payload",
                type_instance_arg_ref_payload,
            ),
            PassAccess::write("type_instance_arg_row_start", type_instance_arg_row_start),
            PassAccess::write(
                "type_instance_arg_row_count_out",
                type_instance_arg_row_count_out,
            ),
            PassAccess::write(
                "type_instance_arg_row_ref_tag",
                type_instance_arg_row_ref_tag,
            ),
            PassAccess::write(
                "type_instance_arg_row_ref_payload",
                type_instance_arg_row_ref_payload,
            ),
            PassAccess::write("type_instance_arg_hash", type_instance_arg_hash),
            PassAccess::write("fn_return_ref_tag", fn_return_ref_tag),
            PassAccess::write("fn_return_ref_payload", fn_return_ref_payload),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: TYPE_INSTANCES_MARK_GENERIC_PARAM_RECORDS_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", compact_hir_count),
            PassAccess::read("compact_hir_payload", compact_hir_payload),
            PassAccess::read("raw_to_compact_hir", raw_to_compact_hir),
            PassAccess::read("compact_method_count", compact_method_count),
            PassAccess::read("compact_method_cores", compact_method_cores),
            PassAccess::read("compact_method_signatures", compact_method_signatures),
            PassAccess::read("hir_status", hir_status),
            PassAccess::read("node_kind", node_kind),
            PassAccess::read("parent", parent),
            PassAccess::write("generic_decl_owner_by_node_a", generic_decl_owner_by_node_a),
            PassAccess::write(
                "predicate_bound_list_by_node_a",
                predicate_bound_list_by_node_a,
            ),
            PassAccess::write("generic_decl_parent_jump_a", generic_decl_parent_jump_a),
            PassAccess::write("type_decl_hir_node_by_token", type_decl_hir_node_by_token),
        ],
    })?;
    let generic_owner_steps = generic_decl_owner_step_count(hir_capacity);
    if generic_owner_steps > 0 {
        graph.add_repeated_region(
            generic_owner_steps / 2,
            vec![
                generic_owner_propagation_pass(
                    TYPE_INSTANCES_PROPAGATE_GENERIC_OWNER_A_TO_B_PASS,
                    hir_status,
                    generic_decl_owner_by_node_a,
                    predicate_bound_list_by_node_a,
                    generic_decl_parent_jump_a,
                    generic_decl_owner_by_node_b,
                    predicate_bound_list_by_node_b,
                    generic_decl_parent_jump_b,
                ),
                generic_owner_propagation_pass(
                    TYPE_INSTANCES_PROPAGATE_GENERIC_OWNER_B_TO_A_PASS,
                    hir_status,
                    generic_decl_owner_by_node_b,
                    predicate_bound_list_by_node_b,
                    generic_decl_parent_jump_b,
                    generic_decl_owner_by_node_a,
                    predicate_bound_list_by_node_a,
                    generic_decl_parent_jump_a,
                ),
            ],
        )?;
    }
    graph.add_reflected_compute_pass_by_name(
        TYPE_INSTANCES_DECL_GENERIC_PARAMS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        reflections.type_instances_decl_generic_params,
        &[
            ReflectedResourceBinding {
                binding: "generic_param_count_out",
                resource: generic_param_count_out,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "generic_param_owner_token",
                resource: generic_param_owner_token,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "generic_param_name_id",
                resource: generic_param_name_id,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "generic_param_token",
                resource: generic_param_token,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "generic_param_node",
                resource: generic_param_node,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "generic_param_kind",
                resource: generic_param_kind,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "generic_param_key_order",
                resource: generic_param_key_order,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "generic_param_slot_order",
                resource: generic_param_slot_order,
                mode: Some(AccessMode::Write),
            },
        ],
    )?;
    graph.add_pass(PassDesc {
        name: TYPE_INSTANCES_GENERIC_PARAM_SORT_DISPATCH_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::DispatchArguments,
        accesses: vec![
            PassAccess::read("name_count_in", generic_param_count_out),
            PassAccess::write(
                "radix_dispatch_args",
                hir_visible_decl_key_radix_dispatch_args,
            ),
        ],
    })?;
    if token_capacity.max(1) <= GENERIC_PARAM_SMALL_SORT_CAPACITY {
        graph.add_reflected_compute_pass_by_name(
            TYPE_INSTANCES_GENERIC_PARAM_SORT_SMALL_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::Declarations,
            reflections.type_instances_sort_generic_params_small,
            &[],
        )?;
    } else {
        let radix_steps = generic_param_key_radix_steps(token_capacity.max(1), hir_capacity.max(1));
        GENERIC_PARAMETER_RADIX_SORTS.register(
            &mut graph,
            radix_steps,
            &[
                "generic_param_owner_token",
                "generic_param_name_id",
                "generic_param_node",
            ],
            &[
                "generic_param_owner_token",
                "generic_param_node",
                "generic_param_kind",
            ],
        )?;
    }
    graph.add_reflected_compute_pass_by_name(
        TYPE_INSTANCES_GENERIC_PARAM_USE_SLOTS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        reflections.type_instances_generic_param_use_slots,
        &[],
    )?;
    for name in [
        TYPE_INSTANCE_CORE_COLLECT_INITIAL_PASS,
        TYPE_INSTANCE_CORE_COLLECT_PROJECTED_PASS,
    ] {
        graph.add_pass(PassDesc {
            name,
            phase: CompilerPhase::TypeCheck,
            dispatch_domain: ResourceDomain::HirNodes,
            accesses: vec![
                PassAccess::read_write("type_instance_head_token", type_instance_head_token),
                PassAccess::read_write("type_instance_kind", type_instance_kind),
                PassAccess::read_write("type_instance_state", type_instance_state),
                PassAccess::read_write("type_instance_elem_ref_tag", type_instance_elem_ref_tag),
                PassAccess::read_write(
                    "type_instance_elem_ref_payload",
                    type_instance_elem_ref_payload,
                ),
                PassAccess::read_write("type_instance_len_kind", type_instance_len_kind),
                PassAccess::read_write("type_instance_len_payload", type_instance_len_payload),
                PassAccess::read_write("type_instance_arg_start", type_instance_arg_start),
                PassAccess::read_write("type_instance_arg_count", type_instance_arg_count),
            ],
        })?;
    }
    graph.add_pass(PassDesc {
        name: FEATURES_CLEAR_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![PassAccess::write(
            "semantic_feature_flags",
            semantic_feature_flags,
        )],
    })?;
    graph.add_reflected_compute_pass_by_name(
        FEATURES_COLLECT_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        reflections.semantic_features_collect,
        &[],
    )?;
    graph.add_reflected_initializer_by_name(
        FEATURES_DISPATCH_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::DispatchArguments,
        reflections.semantic_features_dispatch,
    )?;
    graph.add_pass(PassDesc {
        name: IF_DEPTH_CLEAR_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Tokens,
        accesses: vec![PassAccess::write("if_delta", if_delta)],
    })?;
    graph.add_pass(PassDesc {
        name: IF_DEPTH_MARK_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", compact_hir_count),
            PassAccess::read("compact_hir_core", compact_hir_core),
            PassAccess::read_write("if_delta", if_delta),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: IF_DEPTH_LOCAL_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Tokens,
        accesses: vec![
            PassAccess::read("if_delta", if_delta),
            PassAccess::write("if_depth_inblock", if_depth_inblock),
            PassAccess::write("if_block_sum", if_block_sum),
        ],
    })?;
    // The fixed hierarchical prefix scan records several dispatches, but is
    // one logical pass for lifetime coloring: all hierarchy rows overlap.
    graph.add_pass(PassDesc {
        name: IF_DEPTH_SCAN_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Tokens,
        accesses: vec![
            PassAccess::read("if_block_sum", if_block_sum),
            PassAccess::write("if_prefix_a", if_prefix_a),
            PassAccess::write("if_prefix_b", if_prefix_b),
            PassAccess::write("if_block_prefix", if_block_prefix),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: IF_DEPTH_APPLY_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Tokens,
        accesses: vec![
            PassAccess::read("if_depth_inblock", if_depth_inblock),
            PassAccess::read("if_block_prefix", if_block_prefix),
            PassAccess::write("if_depth", if_depth),
        ],
    })?;
    // Expression typing executes after call argument matching has published
    // per-call generic and aggregate result dependencies. Keep the graph in
    // the same order as command recording so ownership validation describes
    // the actual GPU schedule.
    // Preserve the precise producer contract so workspace liveness starts at
    // the receiver projection rather than requiring hidden preinitialization.
    let member_receiver_overrides = [
        ReflectedResourceBinding {
            binding: "member_result_context_instance",
            resource: member_result_context_instance,
            mode: Some(AccessMode::Write),
        },
        ReflectedResourceBinding {
            binding: "member_result_ref_tag",
            resource: member_result_ref_tag,
            mode: Some(AccessMode::Write),
        },
        ReflectedResourceBinding {
            binding: "member_result_ref_payload",
            resource: member_result_ref_payload,
            mode: Some(AccessMode::Write),
        },
        ReflectedResourceBinding {
            binding: "member_result_field_ordinal",
            resource: member_result_field_ordinal,
            mode: Some(AccessMode::Write),
        },
        ReflectedResourceBinding {
            binding: "member_result_field_node",
            resource: member_result_field_node,
            mode: Some(AccessMode::Write),
        },
    ];
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
                    PassAccess::read("decl_type_ref_tag", decl_type_ref_tag),
                    PassAccess::read("decl_type_ref_payload", decl_type_ref_payload),
                    PassAccess::read(
                        "type_generic_param_slot_by_token",
                        type_generic_param_slot_by_token,
                    ),
                    PassAccess::read("type_instance_kind", type_instance_kind),
                    PassAccess::read("type_instance_elem_ref_tag", type_instance_elem_ref_tag),
                    PassAccess::read(
                        "type_instance_elem_ref_payload",
                        type_instance_elem_ref_payload,
                    ),
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
            graph.add_reflected_compute_pass_by_name(
                TYPE_INSTANCES_STRUCT_INIT_SUBSTITUTE_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::Tokens,
                reflections.type_instances_struct_init_substitute,
                &[],
            )?;
            graph.add_reflected_compute_pass_by_name(
                TYPE_INSTANCES_MEMBER_RECEIVERS_AFTER_ARRAY_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                reflections.type_instances_member_receivers,
                &member_receiver_overrides,
            )?;
            graph.add_reflected_compute_pass_by_name(
                TYPE_INSTANCES_MEMBER_RESULTS_AFTER_ARRAY_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                reflections.type_instances_member_results,
                &[],
            )?;
            graph.add_reflected_compute_pass_by_name(
                TYPE_INSTANCES_MEMBER_SUBSTITUTE_AFTER_ARRAY_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::Tokens,
                reflections.type_instances_member_substitute,
                &[],
            )?;
            graph.add_reflected_compute_pass_by_name(
                TYPE_INSTANCES_VALIDATE_AGGREGATE_ACCESS_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                reflections.type_instances_validate_aggregate_access,
                &[],
            )?;
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
                    PassAccess::write("semantic_array_length_by_hir", semantic_array_length_by_hir),
                    PassAccess::write(
                        "semantic_member_field_ordinal_by_hir",
                        semantic_member_field_ordinal_by_hir,
                    ),
                ],
            })?;
            graph.add_pass(PassDesc {
                name: SEMANTIC_STRUCT_LITERAL_REFS_PROJECT_PASS,
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read("raw_to_compact_hir", raw_to_compact_hir),
                    PassAccess::read("hir_kind", hir_kind),
                    PassAccess::read("hir_member_name_token", _hir_member_name_token),
                    PassAccess::read(
                        "struct_lit_context_decl_token",
                        struct_lit_context_decl_token,
                    ),
                    PassAccess::read("struct_lit_context_instance", struct_lit_context_instance),
                    PassAccess::read("decl_type_ref_tag", decl_type_ref_tag),
                    PassAccess::read("decl_type_ref_payload", decl_type_ref_payload),
                    PassAccess::read("member_result_field_ordinal", member_result_field_ordinal),
                    PassAccess::read_write(
                        "semantic_expr_ref_tag_by_hir",
                        semantic_expr_ref_tag_by_hir,
                    ),
                    PassAccess::read_write(
                        "semantic_expr_ref_payload_by_hir",
                        semantic_expr_ref_payload_by_hir,
                    ),
                    PassAccess::read_write(
                        "semantic_member_field_ordinal_by_hir",
                        semantic_member_field_ordinal_by_hir,
                    ),
                ],
            })?;
            graph.add_reflected_compute_pass_by_name(
                SEMANTIC_ARRAY_INDEX_REFS_PROJECT_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                reflections.semantic_array_index_refs,
                &[],
            )?;
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
            let aggregate_scan_resources =
                graph.resolve_prefix_scan_resources(AGGREGATE_SCAN_RESOURCES)?;
            graph.add_fragment(PrefixScanGraph {
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::HirNodes,
                hierarchy_levels: prefix_scan_hierarchy_levels(hir_blocks),
                passes: AGGREGATE_FINAL_SCAN_PASSES,
                resources: aggregate_scan_resources,
            })?;
            graph.add_pass(PassDesc {
                name: AGGREGATE_FINAL_DISPATCH_PASS,
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read("aggregate_compare_count_out", aggregate_compare_count_out),
                    PassAccess::write(
                        "aggregate_compare_dispatch_args",
                        aggregate_compare_dispatch_args,
                    ),
                ],
            })?;
            graph.add_reflected_compute_pass_by_name(
                CONDITIONS_AGGREGATE_ARGS_FINAL_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::CallArguments,
                reflections.conditions_aggregate_args,
                &[
                    ReflectedResourceBinding {
                        binding: "type_subtree_compare_scan_input",
                        resource: type_subtree_compare_scan_input,
                        mode: Some(AccessMode::Write),
                    },
                    ReflectedResourceBinding {
                        binding: "type_subtree_compare_left_root",
                        resource: type_subtree_compare_left_root,
                        mode: Some(AccessMode::Write),
                    },
                    ReflectedResourceBinding {
                        binding: "type_subtree_compare_right_root",
                        resource: type_subtree_compare_right_root,
                        mode: Some(AccessMode::Write),
                    },
                    ReflectedResourceBinding {
                        binding: "type_subtree_compare_error_token",
                        resource: type_subtree_compare_error_token,
                        mode: Some(AccessMode::Write),
                    },
                    ReflectedResourceBinding {
                        binding: "type_subtree_compare_error_detail",
                        resource: type_subtree_compare_error_detail,
                        mode: Some(AccessMode::Write),
                    },
                ],
            )?;
            add_type_subtree_passes(
                graph,
                TYPE_SUBTREE_FINAL_SCAN_PASSES,
                TYPE_SUBTREE_FINAL_DISPATCH_PASS,
                TYPE_SUBTREE_FINAL_INDIRECT_PASS,
                prefix_scan_hierarchy_levels(hir_blocks),
                &resources,
            )?;
            graph.add_pass(PassDesc {
                name: AGGREGATE_FINAL_INDIRECT_PASS,
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::CallArguments,
                accesses: vec![PassAccess::read(
                    "aggregate_compare_dispatch_args",
                    aggregate_compare_dispatch_args,
                )],
            })?;
            graph.add_reflected_compute_pass_by_name(
                CONDITIONS_COMPACT_CALLS_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                reflections.conditions_compact_calls,
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
                reflections.conditions_compact_types,
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
                    PassAccess::read("compact_hir_payload", compact_hir_payload),
                    PassAccess::read("compact_type_root_owner", compact_type_root_owner),
                    PassAccess::read("compact_predicate_count", compact_predicate_count),
                    PassAccess::read("compact_predicates", compact_predicates),
                    PassAccess::read("compact_path_count", compact_path_count),
                    PassAccess::read("compact_paths", compact_paths),
                    PassAccess::read("compact_path_segment_count", compact_path_segment_count),
                    PassAccess::read("compact_path_segments", compact_path_segments),
                    PassAccess::read("path_id_by_owner_hir", path_id_by_owner_hir),
                    PassAccess::read("resolved_type_decl", resolved_type_decl),
                    PassAccess::read("resolved_type_status", resolved_type_status),
                    PassAccess::read("decl_count_out", decl_count_out),
                    PassAccess::read("decl_kind", decl_kind),
                    PassAccess::read("type_expr_ref_tag", type_expr_ref_tag),
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
        name: FN_CONTEXT_CLEAR_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Tokens,
        accesses: vec![
            PassAccess::write("enclosing_fn", enclosing_fn),
            PassAccess::write("enclosing_fn_end", enclosing_fn_end),
            PassAccess::write("fn_event_value", fn_event_value),
            PassAccess::write("fn_event_end", fn_event_end),
            PassAccess::write("fn_event_index", fn_event_index),
            PassAccess::write("fn_event_inblock", fn_event_inblock),
            PassAccess::write("fn_block_sum", fn_block_sum),
            PassAccess::write("fn_block_prefix", fn_block_prefix),
        ],
    })?;
    TYPE_INSTANCE_ARG_ROW_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(token_blocks))?;
    graph.add_pass(PassDesc {
        name: TYPE_INSTANCE_ARG_ROW_POPULATE_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read_write("type_instance_arg_start", type_instance_arg_start),
            PassAccess::read_write("type_instance_arg_count", type_instance_arg_count),
            PassAccess::write("type_instance_arg_ref_tag", type_instance_arg_ref_tag),
            PassAccess::write(
                "type_instance_arg_ref_payload",
                type_instance_arg_ref_payload,
            ),
            PassAccess::read("type_instance_arg_row_start", type_instance_arg_row_start),
            PassAccess::read(
                "type_instance_arg_row_count_out",
                type_instance_arg_row_count_out,
            ),
            PassAccess::write(
                "type_instance_arg_row_ref_tag",
                type_instance_arg_row_ref_tag,
            ),
            PassAccess::write(
                "type_instance_arg_row_ref_payload",
                type_instance_arg_row_ref_payload,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: TYPE_INSTANCE_ARG_HASH_ROWS_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Types,
        accesses: vec![
            PassAccess::read("type_instance_arg_start", type_instance_arg_start),
            PassAccess::read("type_instance_arg_count", type_instance_arg_count),
            PassAccess::read("type_instance_arg_ref_tag", type_instance_arg_ref_tag),
            PassAccess::read(
                "type_instance_arg_ref_payload",
                type_instance_arg_ref_payload,
            ),
            PassAccess::write("type_instance_arg_hash", type_instance_arg_hash),
        ],
    })?;
    graph.add_reflected_compute_pass_by_name(
        TYPE_SEMANTIC_CLEAR_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        reflections.type_instances_clear_semantic_type_rows,
        &[
            ReflectedResourceBinding {
                binding: "type_semantic_row_by_token",
                resource: type_semantic_row_by_token,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "type_semantic_scan_input",
                resource: type_semantic_scan_input,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "member_next_node",
                resource: member_next_node,
                mode: Some(AccessMode::Write),
            },
        ],
    )?;
    graph.add_reflected_compute_pass_by_name(
        TYPE_SEMANTIC_MARK_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        reflections.type_instances_mark_semantic_type_rows,
        &[],
    )?;
    TYPE_SEMANTIC_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(hir_blocks))?;
    graph.add_reflected_compute_pass_by_name(
        TYPE_SEMANTIC_SCATTER_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        reflections.type_instances_scatter_semantic_type_rows,
        &[ReflectedResourceBinding {
            binding: "type_semantic_row_by_ordinal",
            resource: type_semantic_row_by_ordinal,
            mode: Some(AccessMode::Write),
        }],
    )?;
    graph.add_pass(PassDesc {
        name: FN_CONTEXT_MARK_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", compact_hir_count),
            PassAccess::read("compact_hir_core", compact_hir_core),
            PassAccess::read("compact_hir_payload", compact_hir_payload),
            PassAccess::read_write("fn_event_value", fn_event_value),
            PassAccess::read_write("fn_event_end", fn_event_end),
            PassAccess::read_write("fn_event_index", fn_event_index),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: FN_CONTEXT_LOCAL_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Tokens,
        accesses: vec![
            PassAccess::read("fn_event_index", fn_event_index),
            PassAccess::write("fn_event_inblock", fn_event_inblock),
            PassAccess::write("fn_block_sum", fn_block_sum),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: FN_CONTEXT_SCAN_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Tokens,
        accesses: vec![
            PassAccess::read("fn_block_sum", fn_block_sum),
            PassAccess::write("fn_prefix_a", fn_prefix_a),
            PassAccess::write("fn_prefix_b", fn_prefix_b),
            PassAccess::write("fn_block_prefix", fn_block_prefix),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: FN_CONTEXT_APPLY_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Tokens,
        accesses: vec![
            PassAccess::read("fn_event_value", fn_event_value),
            PassAccess::read("fn_event_end", fn_event_end),
            PassAccess::read("fn_event_inblock", fn_event_inblock),
            PassAccess::read("fn_block_prefix", fn_block_prefix),
            PassAccess::write("enclosing_fn", enclosing_fn),
            PassAccess::write("enclosing_fn_end", enclosing_fn_end),
        ],
    })?;
    CALLS_CLEAR.register(&mut graph, reflections.calls.clear)?;
    CALLS_ENTRYPOINT_CLEAR.register(&mut graph, reflections.calls.clear_entrypoints)?;
    CALLS_RETURN_REFS.register(&mut graph, reflections.calls.return_refs)?;
    CALLS_ENTRYPOINT_PROJECT.register(&mut graph, reflections.calls.entrypoints)?;
    CALLS_FUNCTIONS.register(&mut graph, reflections.calls.functions)?;
    CALLS_PARAM_TYPES.register(&mut graph, reflections.calls.param_types)?;
    METHODS_CLEAR.register(&mut graph, reflections.methods_clear)?;
    METHODS_COLLECT.register(&mut graph, reflections.methods_collect)?;
    METHODS_ATTACH_METADATA.register(&mut graph, reflections.methods_attach_metadata)?;
    METHODS_BIND_SELF_RECEIVERS.register(&mut graph, reflections.methods_bind_self_receivers)?;
    graph.add_reflected_compute_pass_by_name(
        TYPE_INSTANCES_MEMBER_RECEIVERS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        reflections.type_instances_member_receivers,
        &member_receiver_overrides,
    )?;
    graph.add_pass(PassDesc {
        name: TYPE_INSTANCES_STRUCT_FIELD_SORT_SEED_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::read("compact_field_count", compact_field_count),
            PassAccess::write("struct_field_key_order", struct_field_key_order),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: TYPE_INSTANCES_STRUCT_FIELD_SORT_PREPARE_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::DispatchArguments,
        accesses: vec![
            PassAccess::read("compact_field_count", compact_field_count),
            PassAccess::write(
                "struct_field_key_radix_dispatch_args",
                struct_field_key_radix_dispatch_args,
            ),
        ],
    })?;
    STRUCT_FIELD_RADIX_SORT.register(
        &mut graph,
        struct_field_key_radix_steps(token_capacity, token_capacity),
        &[
            "compact_hir_count",
            "compact_hir_core",
            "compact_fields",
            "name_id_by_token",
        ],
    )?;
    graph.add_reflected_compute_pass_by_name(
        TYPE_INSTANCES_MEMBER_RESULTS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        reflections.type_instances_member_results,
        &[],
    )?;
    graph.add_reflected_compute_pass_by_name(
        TYPE_INSTANCES_MEMBER_SUBSTITUTE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        reflections.type_instances_member_substitute,
        &[],
    )?;
    graph.add_reflected_compute_pass_by_name(
        TYPE_INSTANCES_STRUCT_INIT_CLEAR_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        reflections.type_instances_struct_init_clear,
        &[
            ReflectedResourceBinding {
                binding: "struct_init_field_context_instance",
                resource: struct_init_field_context_instance,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "struct_init_field_expected_ref_tag",
                resource: struct_init_field_expected_ref_tag,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "struct_init_field_expected_ref_payload",
                resource: struct_init_field_expected_ref_payload,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "struct_init_field_ordinal",
                resource: struct_init_field_ordinal,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "struct_lit_context_decl_token",
                resource: struct_lit_context_decl_token,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "struct_lit_context_instance",
                resource: struct_lit_context_instance,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "array_element_struct_literal_node",
                resource: array_element_struct_literal_node,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "struct_init_field_decl_node_by_node",
                resource: struct_init_field_decl_node_by_node,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "struct_init_field_ordinal_by_row",
                resource: struct_init_field_ordinal_by_row,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "struct_init_field_decl_token_by_row",
                resource: struct_init_field_decl_token_by_row,
                mode: Some(AccessMode::Write),
            },
        ],
    )?;
    graph.add_reflected_compute_pass_by_name(
        TYPE_INSTANCES_STRUCT_INIT_CONTEXTS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        reflections.type_instances_struct_init_contexts,
        &[],
    )?;
    graph.add_reflected_compute_pass_by_name(
        TYPE_INSTANCES_STRUCT_INIT_FIELDS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::RawNodes,
        reflections.type_instances_struct_init_fields,
        &[ReflectedResourceBinding {
            binding: "struct_init_field_ordinal_by_node",
            resource: struct_init_field_ordinal_by_node,
            mode: Some(AccessMode::Write),
        }],
    )?;
    graph.add_pass(PassDesc {
        name: SEMANTIC_STRUCT_LITERAL_REFS_EARLY_CLEAR_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::write("semantic_expr_ref_tag_by_hir", semantic_expr_ref_tag_by_hir),
            PassAccess::write(
                "semantic_expr_ref_payload_by_hir",
                semantic_expr_ref_payload_by_hir,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: SEMANTIC_STRUCT_LITERAL_REFS_EARLY_PROJECT_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::RawNodes,
        accesses: vec![
            PassAccess::read("raw_to_compact_hir", raw_to_compact_hir),
            PassAccess::read("hir_kind", hir_kind),
            PassAccess::read("hir_member_name_token", _hir_member_name_token),
            PassAccess::read(
                "struct_lit_context_decl_token",
                struct_lit_context_decl_token,
            ),
            PassAccess::read("struct_lit_context_instance", struct_lit_context_instance),
            PassAccess::read("decl_type_ref_tag", decl_type_ref_tag),
            PassAccess::read("decl_type_ref_payload", decl_type_ref_payload),
            PassAccess::read("member_result_field_ordinal", member_result_field_ordinal),
            PassAccess::read_write("semantic_expr_ref_tag_by_hir", semantic_expr_ref_tag_by_hir),
            PassAccess::read_write(
                "semantic_expr_ref_payload_by_hir",
                semantic_expr_ref_payload_by_hir,
            ),
            PassAccess::write(
                "semantic_member_field_ordinal_by_hir",
                semantic_member_field_ordinal_by_hir,
            ),
        ],
    })?;
    CALL_PARAM_ROW_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(token_blocks))?;
    CALLS_PARAM_SCATTER.register(&mut graph, reflections.calls.scatter_params)?;
    CALLS_INTRINSICS.register(&mut graph, reflections.calls.intrinsics)?;
    CALLS_ARGUMENT_CLEAR.register(&mut graph, reflections.calls.clear_args)?;
    CALLS_ARGUMENT_PACK.register(&mut graph, reflections.calls.pack_args)?;
    CALLS_ARGUMENT_MARK.register(&mut graph, reflections.calls.mark_args)?;
    CALL_ARG_ROW_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(hir_blocks))?;
    CALLS_ARGUMENT_SCATTER.register(&mut graph, reflections.calls.scatter_args)?;
    CALLS_RESOLVE.register(&mut graph, reflections.calls.resolve)?;
    CALLS_ARGUMENT_MATCH_INITIALIZE.register(&mut graph, reflections.calls.match_args)?;
    CALLS_ARGUMENT_MATCH_CONSUME.register(&mut graph, reflections.calls.collect_args)?;
    CALLS_APPLY_ARGUMENTS.register(&mut graph, reflections.calls.apply_args)?;
    CALLS_RESULT_INSTANCE_PROJECT
        .register(&mut graph, reflections.calls_project_result_instances)?;
    CALLS_ARRAY_STATE_PUBLISH.register(&mut graph, reflections.calls_mark_array_args)?;
    GENERIC_CLAIM_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(call_arg_blocks))?;
    CALLS_GENERIC_CLAIM_EMIT.register(&mut graph, reflections.calls.emit_generic_claims)?;
    graph.add_pass(PassDesc {
        name: GENERIC_CLAIM_SORT_PREPARE_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::DispatchArguments,
        accesses: vec![
            PassAccess::read("call_generic_claim_count_out", generic_claim_count_out),
            PassAccess::write(
                "call_generic_claim_radix_dispatch_args",
                generic_claim_radix_dispatch_args,
            ),
        ],
    })?;
    GENERIC_CLAIM_RADIX_SORT.register(
        &mut graph,
        call_claim_radix_steps(token_capacity, generic_claim_capacity),
        &[
            "call_generic_claim_callee",
            "call_generic_claim_slot",
            "call_generic_claim_type",
            "call_generic_claim_ref_tag",
        ],
    )?;
    CALLS_GENERIC_CLAIM_CLEAR
        .register(&mut graph, reflections.calls.clear_generic_claim_type_args)?;
    CALLS_GENERIC_CLAIM_VALIDATE.register(&mut graph, reflections.calls.validate_generic_claims)?;
    CALLS_REQUIRED_GENERIC_MARK.register(&mut graph, reflections.calls.mark_required_generics)?;
    REQUIRED_GENERIC_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(hir_blocks))?;
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
    CALLS_REQUIRED_GENERIC_VALIDATE
        .register(&mut graph, reflections.calls.validate_required_generics)?;
    graph.add_pass(PassDesc {
        name: CONST_CLAIM_SORT_PREPARE_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::DispatchArguments,
        accesses: vec![
            PassAccess::read("call_arg_row_count_out", call_arg_row_count_out),
            PassAccess::write(
                "call_const_claim_radix_dispatch_args",
                const_claim_radix_dispatch_args,
            ),
        ],
    })?;
    CONST_CLAIM_RADIX_SORT.register(
        &mut graph,
        call_claim_radix_steps(token_capacity, call_arg_capacity),
        &[
            "call_const_claim_callee",
            "call_const_claim_slot",
            "call_const_claim_len",
            "call_generic_claim_ref_tag",
        ],
    )?;
    CALLS_CONST_CLAIM_VALIDATE.register(&mut graph, reflections.calls.validate_const_claims)?;
    let aggregate_scan_resources = graph.resolve_prefix_scan_resources(AGGREGATE_SCAN_RESOURCES)?;
    graph.add_fragment(PrefixScanGraph {
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        hierarchy_levels: prefix_scan_hierarchy_levels(hir_blocks),
        passes: AGGREGATE_CALL_SCAN_PASSES,
        resources: aggregate_scan_resources,
    })?;
    graph.add_pass(PassDesc {
        name: AGGREGATE_CALL_DISPATCH_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("aggregate_compare_count_out", aggregate_compare_count_out),
            PassAccess::write(
                "aggregate_compare_dispatch_args",
                aggregate_compare_dispatch_args,
            ),
        ],
    })?;
    graph.add_reflected_compute_pass_by_name(
        CONDITIONS_AGGREGATE_ARGS_CALLS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::CallArguments,
        reflections.conditions_aggregate_args,
        &[
            ReflectedResourceBinding {
                binding: "type_subtree_compare_scan_input",
                resource: type_subtree_compare_scan_input,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "type_subtree_compare_left_root",
                resource: type_subtree_compare_left_root,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "type_subtree_compare_right_root",
                resource: type_subtree_compare_right_root,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "type_subtree_compare_error_token",
                resource: type_subtree_compare_error_token,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "type_subtree_compare_error_detail",
                resource: type_subtree_compare_error_detail,
                mode: Some(AccessMode::Write),
            },
        ],
    )?;
    add_type_subtree_passes(
        &mut graph,
        TYPE_SUBTREE_CALL_SCAN_PASSES,
        TYPE_SUBTREE_CALL_DISPATCH_PASS,
        TYPE_SUBTREE_CALL_INDIRECT_PASS,
        prefix_scan_hierarchy_levels(hir_blocks),
        &resources,
    )?;
    graph.add_pass(PassDesc {
        name: AGGREGATE_CALL_INDIRECT_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::CallArguments,
        accesses: vec![PassAccess::read(
            "aggregate_compare_dispatch_args",
            aggregate_compare_dispatch_args,
        )],
    })?;
    CALLS_ARRAY_STATE_CONSUME.register(&mut graph, reflections.calls_validate_array_results)?;
    graph.add_pass(PassDesc {
        name: VISIBLE_CLEAR_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Tokens,
        accesses: vec![
            PassAccess::read("token_count", token_count),
            PassAccess::write("visible_decl", visible_decl),
            PassAccess::write("visible_type", visible_type),
            PassAccess::write("hir_value_decl_name_present", hir_value_decl_name_present),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: VISIBLE_SEMANTIC_DISPATCH_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::DispatchArguments,
        accesses: vec![
            PassAccess::read("hir_semantic_count", hir_semantic_count),
            PassAccess::write("hir_semantic_dispatch_args", hir_semantic_dispatch_args),
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
    VISIBLE_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(hir_blocks))?;
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
            PassAccess::write("hir_visible_decl_key_order", hir_visible_decl_key_order),
            PassAccess::write(
                "hir_visible_decl_key_radix_dispatch_args",
                hir_visible_decl_key_radix_dispatch_args,
            ),
        ],
    })?;
    VISIBLE_RADIX_SORT.register(
        &mut graph,
        visible_decl_key_radix_steps(token_capacity),
        &[
            "hir_visible_decl_owner_fn",
            "hir_visible_decl_name_id",
            "hir_visible_decl_token",
        ],
    )?;
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
    METHODS_MARK_CALL_KEYS.register(&mut graph, reflections.methods_mark_call_keys)?;
    graph.add_reflected_compute_pass_by_name(
        METHOD_KEY_SEED_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        reflections.methods_seed_key_order,
        &[
            ReflectedResourceBinding {
                binding: "method_key_to_fn_token",
                resource: method_key_to_fn_token,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "method_key_status",
                resource: method_key_status,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "method_key_duplicate_of",
                resource: method_key_duplicate_of,
                mode: Some(AccessMode::Write),
            },
        ],
    )?;
    METHOD_KEY_RADIX_SORT.register(
        &mut graph,
        METHOD_KEY_RADIX_STEPS,
        &[
            "method_decl_method_row",
            "method_decl_receiver_ref_tag",
            "method_decl_receiver_ref_payload",
            "method_decl_module_id",
            "method_decl_name_id",
            "module_type_path_type",
            "type_instance_decl_token",
            "type_instance_arg_start",
            "type_instance_arg_count",
            "type_instance_arg_ref_tag",
            "type_instance_arg_ref_payload",
            "type_instance_arg_hash",
        ],
    )?;
    graph.add_reflected_compute_pass_by_name(
        METHOD_KEY_VALIDATION_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        reflections.methods_validate_keys,
        &[ReflectedResourceBinding {
            binding: "sorted_method_key_order",
            resource: method_key_to_fn_token,
            mode: Some(AccessMode::Read),
        }],
    )?;
    METHODS_MARK_CALL_RETURN_KEYS
        .register(&mut graph, reflections.methods_mark_call_return_keys)?;
    METHODS_RESOLVE_TABLE.register(&mut graph, reflections.methods_resolve_table)?;
    METHODS_RESOLVE.register(&mut graph, reflections.methods_resolve)?;
    if let Some(predicate_reflections) = reflections.predicates {
        let predicate_clear_overrides = [
            ReflectedResourceBinding {
                binding: "predicate_trait_impl_trait_type_node",
                resource: predicate_trait_impl_trait_type_node,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_owner_node",
                resource: predicate_owner_node,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_subject_token",
                resource: predicate_subject_token,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_bound_token",
                resource: predicate_bound_token,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_bound_decl_id",
                resource: predicate_bound_decl_id,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_bound_arg_count",
                resource: predicate_bound_arg_count,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_bound_first_arg_token",
                resource: predicate_bound_first_arg_token,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_bound_second_arg_token",
                resource: predicate_bound_second_arg_token,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_status",
                resource: predicate_status,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_method_contract_owner_hir",
                resource: predicate_method_contract_owner_hir,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_method_contract_name_token",
                resource: predicate_method_contract_name_token,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_method_contract_name_id",
                resource: predicate_method_contract_name_id,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_method_contract_param_count",
                resource: predicate_method_contract_param_count,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_method_contract_return_type_node",
                resource: predicate_method_contract_return_type_node,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_method_contract_visibility",
                resource: predicate_method_contract_visibility,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_method_contract_status",
                resource: predicate_method_contract_status,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_method_contract_param_type_node",
                resource: predicate_method_contract_param_type_node,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_method_contract_owner_range_first",
                resource: predicate_method_contract_owner_range_first,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_method_contract_owner_range_count",
                resource: predicate_method_contract_owner_range_count,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_method_validation_owner_node",
                resource: predicate_method_validation_owner_node,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_method_validation_peer_node",
                resource: predicate_method_validation_peer_node,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_method_validation_status",
                resource: predicate_method_validation_status,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_method_validation_detail_token",
                resource: predicate_method_validation_detail_token,
                mode: Some(AccessMode::Write),
            },
            ReflectedResourceBinding {
                binding: "predicate_method_validation_first_error_row",
                resource: predicate_method_validation_first_error_row,
                mode: Some(AccessMode::Write),
            },
        ];
        graph.add_reflected_compute_pass_by_name(
            PREDICATES_CLEAR_BOUND_ARG_FACTS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            predicate_reflections.clear_bound_arg_facts,
            &predicate_clear_overrides,
        )?;
        graph.add_reflected_compute_pass_by_name(
            PREDICATES_COLLECT_BOUND_ARG_FACTS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            predicate_reflections.collect_bound_arg_facts,
            &[],
        )?;
        graph.add_reflected_compute_pass_by_name(
            PREDICATES_COLLECT_METHOD_CONTRACTS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            predicate_reflections.collect_method_contracts,
            &[],
        )?;
        graph.add_pass(PassDesc {
            name: PREDICATES_METHOD_CONTRACT_KEYS_PASS,
            phase: CompilerPhase::TypeCheck,
            dispatch_domain: ResourceDomain::HirNodes,
            accesses: vec![
                PassAccess::read("hir_active_count", hir_active_count),
                PassAccess::read("hir_token_pos", hir_token_pos),
                PassAccess::read("name_id_by_token", name_id_by_token),
                PassAccess::read(
                    "predicate_method_contract_owner_hir",
                    predicate_method_contract_owner_hir,
                ),
                PassAccess::read(
                    "predicate_method_contract_name_id",
                    predicate_method_contract_name_id,
                ),
                PassAccess::read(
                    "predicate_method_contract_param_type_node",
                    predicate_method_contract_param_type_node,
                ),
                PassAccess::write(
                    "predicate_method_contract_key_order",
                    predicate_method_contract_key_order,
                ),
                PassAccess::write(
                    "predicate_method_contract_key_order_tmp",
                    predicate_method_contract_key_order_tmp,
                ),
                PassAccess::write(
                    "predicate_method_param_key_order",
                    predicate_method_param_key_order,
                ),
                PassAccess::write(
                    "predicate_method_param_key_order_tmp",
                    predicate_method_param_key_order_tmp,
                ),
                PassAccess::write(
                    "predicate_key_radix_block_histogram",
                    predicate_key_radix_block_histogram,
                ),
                PassAccess::write(
                    "predicate_key_radix_block_bucket_prefix",
                    predicate_key_radix_block_bucket_prefix,
                ),
                PassAccess::write(
                    "predicate_key_radix_bucket_total",
                    predicate_key_radix_bucket_total,
                ),
                PassAccess::write(
                    "predicate_key_radix_bucket_base",
                    predicate_key_radix_bucket_base,
                ),
            ],
        })?;
        graph.add_reflected_compute_pass_by_name(
            PREDICATES_BUILD_METHOD_OWNER_RANGES_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            predicate_reflections.build_method_owner_ranges,
            &[],
        )?;
        graph.add_reflected_compute_pass_by_name(
            PREDICATES_COLLECT_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            predicate_reflections.collect,
            &[],
        )?;
        graph.add_reflected_compute_pass_by_name(
            PREDICATES_VALIDATE_BOUND_ARGS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            predicate_reflections.validate_bound_args,
            &[],
        )?;
        graph.add_reflected_compute_pass_by_name(
            PREDICATES_COLLECT_IMPLS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            predicate_reflections.collect_impls,
            &[],
        )?;
        graph.add_reflected_compute_pass_by_name(
            PREDICATES_EMIT_METHOD_VALIDATION_ROWS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            predicate_reflections.emit_method_validation_rows,
            &[],
        )?;
        graph.add_reflected_compute_pass_by_name(
            PREDICATES_EMIT_METHOD_PARAM_VALIDATION_ROWS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            predicate_reflections.emit_method_param_validation_rows,
            &[],
        )?;
        graph.add_reflected_compute_pass_by_name(
            PREDICATES_VALIDATE_METHOD_TYPE_ARG_ROWS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            predicate_reflections.validate_method_type_arg_rows,
            &[],
        )?;
        graph.add_reflected_compute_pass_by_name(
            PREDICATES_REDUCE_METHOD_VALIDATION_ERRORS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            predicate_reflections.reduce_method_validation_errors,
            &[],
        )?;
        graph.add_pass(PassDesc {
            name: PREDICATES_OWNER_IMPL_KEYS_PASS,
            phase: CompilerPhase::TypeCheck,
            dispatch_domain: ResourceDomain::HirNodes,
            accesses: vec![
                PassAccess::read("hir_active_count", hir_active_count),
                PassAccess::read("hir_token_pos", hir_token_pos),
                PassAccess::read("predicate_owner_node", predicate_owner_node),
                PassAccess::read("predicate_subject_token", predicate_subject_token),
                PassAccess::read("predicate_bound_decl_id", predicate_bound_decl_id),
                PassAccess::read("predicate_status", predicate_status),
                PassAccess::write("predicate_owner_key_order", predicate_owner_key_order),
                PassAccess::write(
                    "predicate_owner_key_order_tmp",
                    predicate_owner_key_order_tmp,
                ),
                PassAccess::write("predicate_impl_key_order", predicate_impl_key_order),
                PassAccess::write("predicate_impl_key_order_tmp", predicate_impl_key_order_tmp),
                PassAccess::write(
                    "predicate_key_radix_block_histogram",
                    predicate_key_radix_block_histogram,
                ),
                PassAccess::write(
                    "predicate_key_radix_block_bucket_prefix",
                    predicate_key_radix_block_bucket_prefix,
                ),
                PassAccess::write(
                    "predicate_key_radix_bucket_total",
                    predicate_key_radix_bucket_total,
                ),
                PassAccess::write(
                    "predicate_key_radix_bucket_base",
                    predicate_key_radix_bucket_base,
                ),
            ],
        })?;
        // All four predicate-key sorts use the same runtime-mode kernels.
        // Consequently every key-input column remains shader-visible while
        // both the method-contract/parameter and owner/impl sorts are
        // recorded, even when one mode does not dynamically read a column.
        // Keep that common interface live as one operation boundary so graph
        // coloring cannot alias an input with another mode's writable order.
        for resource in [
            hir_active_count,
            hir_token_pos,
            visible_type,
            type_expr_ref_tag,
            type_expr_ref_payload,
            type_generic_param_slot_by_token,
            predicate_owner_node,
            predicate_subject_token,
            predicate_bound_decl_id,
            predicate_bound_arg_count,
            predicate_bound_first_arg_token,
            predicate_bound_second_arg_token,
            predicate_status,
            compact_param_count,
            compact_params,
            predicate_method_contract_owner_hir,
            predicate_method_contract_name_id,
        ] {
            graph.fence_resource_lifetime(
                resource,
                PREDICATES_METHOD_CONTRACT_KEYS_PASS,
                PREDICATES_OWNER_IMPL_KEYS_PASS,
            )?;
        }
        graph.add_reflected_compute_pass_by_name(
            PREDICATES_COUNT_OBLIGATION_PAIRS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            predicate_reflections.count_obligations,
            &[ReflectedResourceBinding {
                binding: "predicate_obligation_count_by_call",
                resource: predicate_obligation_count_by_call,
                mode: Some(AccessMode::Write),
            }],
        )?;
        PREDICATES_OBLIGATION_PAIR_SCAN
            .register(&mut graph, prefix_scan_hierarchy_levels(predicate_blocks))?;
        graph.add_pass(PassDesc {
            name: PREDICATES_OBLIGATION_PAIR_DISPATCH_PASS,
            phase: CompilerPhase::TypeCheck,
            dispatch_domain: ResourceDomain::DispatchArguments,
            accesses: vec![
                PassAccess::read(
                    "predicate_obligation_pair_total",
                    predicate_obligation_pair_total,
                ),
                PassAccess::write(
                    "predicate_obligation_pair_dispatch_args",
                    predicate_obligation_pair_dispatch_args,
                ),
            ],
        })?;
        graph.add_reflected_compute_pass_by_name(
            PREDICATES_VALIDATE_OBLIGATION_PAIRS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            predicate_reflections.validate_obligations,
            &[],
        )?;
    }
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
    DEPENDENCY_CALL_COMPARE_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(hir_blocks))?;
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
            PassAccess::read("call_result_instance", call_result_instance),
            PassAccess::read("type_expr_ref_tag", type_expr_ref_tag),
            PassAccess::read("type_expr_ref_payload", type_expr_ref_payload),
            PassAccess::read("decl_type_ref_tag", decl_type_ref_tag),
            PassAccess::read("decl_type_ref_payload", decl_type_ref_payload),
            PassAccess::write("semantic_calls_by_hir", semantic_calls_by_hir),
        ],
    })?;
    add_expression_type_passes(&mut graph)?;
    // Member projection currently executes once before several call/method
    // passes and again immediately before expression-type propagation. Until
    // that complete middle schedule is represented here, keep the member
    // chain and result columns live from their real shared clear boundary to
    // the compact semantic projection consumer.
    for resource in [
        member_next_node,
        member_result_context_instance,
        member_result_ref_tag,
        member_result_ref_payload,
        member_result_field_ordinal,
        member_result_field_node,
    ] {
        graph.fence_resource_lifetime(
            resource,
            TYPE_SEMANTIC_CLEAR_PASS,
            SEMANTIC_EXPRESSION_REFS_PROJECT_PASS,
        )?;
    }
    // Struct-literal context and field facts are produced before several
    // aggregate-validation passes that are not all graph-owned yet. Their
    // output row survives into lowering, while the remaining columns stay
    // conservatively live through semantic projection.
    for resource in [
        struct_init_field_context_instance,
        struct_init_field_expected_ref_tag,
        struct_init_field_expected_ref_payload,
        struct_init_field_ordinal,
        struct_init_field_ordinal_by_node,
        struct_init_field_decl_node_by_node,
        struct_init_field_ordinal_by_row,
        struct_init_field_decl_token_by_row,
        struct_lit_context_decl_token,
        struct_lit_context_instance,
        array_element_struct_literal_node,
    ] {
        graph.fence_resource_lifetime(
            resource,
            TYPE_INSTANCE_ARG_ROW_CLEAR_PASS,
            SEMANTIC_STRUCT_LITERAL_REFS_PROJECT_PASS,
        )?;
    }
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
            PassAccess::read("call_return_type", call_return_type),
            PassAccess::read("fn_entrypoint_tag", fn_entrypoint_tag),
            PassAccess::read("name_id_by_token", name_id_by_token),
            PassAccess::read("language_name_id", language_name_id),
            PassAccess::read("if_depth", if_depth),
            PassAccess::write("semantic_value_decl_by_hir", semantic_value_decl_by_hir),
            PassAccess::write("semantic_value_type_by_hir", semantic_value_type_by_hir),
            PassAccess::write("semantic_param_type_by_row", semantic_param_type_by_row),
            PassAccess::write("semantic_enclosing_fn_by_hir", semantic_enclosing_fn_by_hir),
            PassAccess::write(
                "semantic_function_return_type_by_hir",
                semantic_function_return_type_by_hir,
            ),
            PassAccess::write(
                "semantic_function_entrypoint_by_hir",
                semantic_function_entrypoint_by_hir,
            ),
            PassAccess::write(
                "semantic_function_host_service_by_hir",
                semantic_function_host_service_by_hir,
            ),
            PassAccess::write(
                "semantic_control_depth_by_hir",
                semantic_control_depth_by_hir,
            ),
        ],
    })?;
    // The resident recorder computes control depth before the still-partly
    // unmodeled type-instance collection schedule. `type_instance_state` is
    // cleared and consumed after that point, while `if_depth` must survive to
    // this final projection. Keep the state row live across the real schedule
    // so the two cannot be colored onto one physical slot.
    graph.fence_resource_lifetime(
        type_instance_state,
        TYPE_INSTANCE_ARG_ROW_CLEAR_PASS,
        SEMANTIC_ARTIFACT_PROJECT_PASS,
    )?;
    // The resident schedule invokes argument matching after direct-call,
    // module-call, and method-call resolution. Those invocations are not yet
    // individual graph nodes, so the resource surface reflected for the
    // matching operation must remain live across the complete reconciliation
    // interval. This fence disappears when the resident recorder executes the
    // graph schedule directly.
    graph.fence_resources_accessed_by_passes(
        &[
            CALLS_ARGUMENT_MATCH_INITIALIZE.name,
            CALLS_ARGUMENT_MATCH_CONSUME.name,
        ],
        CALLS_ARGUMENT_MATCH_INITIALIZE.name,
        SEMANTIC_ARTIFACT_PROJECT_PASS,
    )?;
    // Direct-call generic inference, method lookup, type-instance path
    // projection, type-alias forwarding, and predicate collection still read
    // these declaration arity tables after generic use-slot resolution. Keep
    // their graph slots live through the final compact semantic projection
    // until those consumers are each represented as reflected graph passes.
    for resource in [
        type_decl_generic_param_count,
        type_decl_generic_param_count_by_owner_token,
    ] {
        graph.fence_resource_lifetime(
            resource,
            TYPE_INSTANCE_ARG_ROW_CLEAR_PASS,
            SEMANTIC_ARTIFACT_PROJECT_PASS,
        )?;
    }
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

#[allow(clippy::too_many_arguments)]
fn generic_owner_propagation_pass(
    name: &'static str,
    hir_status: ResourceId,
    owner_in: ResourceId,
    bound_list_in: ResourceId,
    jump_in: ResourceId,
    owner_out: ResourceId,
    bound_list_out: ResourceId,
    jump_out: ResourceId,
) -> PassDesc {
    PassDesc {
        name,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("hir_status", hir_status),
            PassAccess::read("generic_decl_owner_by_node_in", owner_in),
            PassAccess::read("predicate_bound_list_by_node_in", bound_list_in),
            PassAccess::read("generic_decl_parent_jump_in", jump_in),
            PassAccess::write("generic_decl_owner_by_node_out", owner_out),
            PassAccess::write("predicate_bound_list_by_node_out", bound_list_out),
            PassAccess::write("generic_decl_parent_jump_out", jump_out),
        ],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn empty_call_reflections<'a>(
        initializer: &'a crate::reflection::SlangReflection,
        return_refs: &'a crate::reflection::SlangReflection,
        reflection: &'a crate::reflection::SlangReflection,
    ) -> CallGraphReflections<'a> {
        CallGraphReflections {
            clear: initializer,
            clear_entrypoints: reflection,
            return_refs,
            entrypoints: reflection,
            functions: reflection,
            param_types: reflection,
            scatter_params: reflection,
            intrinsics: reflection,
            clear_args: reflection,
            pack_args: reflection,
            mark_args: reflection,
            scatter_args: reflection,
            resolve: reflection,
            match_args: reflection,
            collect_args: reflection,
            apply_args: reflection,
            emit_generic_claims: reflection,
            clear_generic_claim_type_args: initializer,
            validate_generic_claims: reflection,
            mark_required_generics: initializer,
            validate_required_generics: reflection,
            validate_const_claims: reflection,
        }
    }

    fn call_initializer_reflection() -> crate::reflection::SlangReflection {
        crate::reflection::SlangReflection {
            parameters: [
                "call_fn_index",
                "fn_start_token_by_decl_token",
                "backend_call_fn_index",
                "call_intrinsic_tag",
                "call_return_type",
                "call_return_type_token",
                "call_param_count",
                "call_param_type",
                "call_param_ref_tag",
                "call_param_ref_payload",
                "call_param_row_count_out",
                "call_param_row_flag",
                "call_param_row_node_type",
                "call_param_row_node_ref_tag",
                "call_param_row_node_ref_payload",
                "call_param_row_node",
                "call_param_row_fn_token",
                "call_param_row_ordinal",
                "call_param_row_type",
                "call_param_row_ref_tag",
                "call_param_row_ref_payload",
                "call_param_row_start",
                "call_param_row_count",
                "call_generic_slot_type",
                "call_generic_slot_ordinal",
                "call_const_slot_len",
                "call_has_array_arg",
                "call_result_instance",
                "call_arg_record",
                "call_arg_row_scan_input",
                "call_arg_row_node",
                "call_arg_row_call_node",
                "call_arg_row_ordinal",
                "call_arg_row_start",
                "call_arg_row_count",
                "call_arg_param_row",
                "call_generic_return_arg_node",
                "call_generic_claim_scan_input",
                "call_generic_claim_prefix",
                "call_generic_claim_count_out",
                "call_generic_claim_callee",
                "call_generic_claim_slot",
                "call_generic_claim_type",
                "call_generic_claim_ref_tag",
                "call_generic_claim_ref_payload",
                "call_generic_claim_arg_row",
                "call_generic_claim_order",
                "call_generic_claim_order_tmp",
                "call_const_claim_callee",
                "call_const_claim_slot",
                "call_const_claim_len",
                "call_const_claim_order",
                "call_const_claim_order_tmp",
                "call_required_generic_scan_input",
                "call_required_generic_prefix",
                "call_required_generic_count_out",
                "aggregate_compare_scan_input",
                "aggregate_compare_expected_instance",
                "aggregate_compare_actual_instance",
                "aggregate_compare_error_token",
                "aggregate_compare_error_detail",
                "function_lookup_key",
                "function_lookup_fn",
                "fn_entrypoint_tag",
            ]
            .into_iter()
            .map(|name| reflected_storage(name, true))
            .collect(),
            ..Default::default()
        }
    }

    fn call_return_refs_reflection() -> crate::reflection::SlangReflection {
        crate::reflection::SlangReflection {
            parameters: ["fn_return_ref_tag", "fn_return_ref_payload"]
                .into_iter()
                .map(|name| reflected_storage(name, true))
                .collect(),
            ..Default::default()
        }
    }

    fn empty_predicate_reflections<'a>(
        reflection: &'a crate::reflection::SlangReflection,
        clear_syntax_tokens: &'a crate::reflection::SlangReflection,
        clear: &'a crate::reflection::SlangReflection,
        count_obligations: &'a crate::reflection::SlangReflection,
    ) -> PredicateGraphReflections<'a> {
        PredicateGraphReflections {
            clear_syntax_tokens,
            clear_bound_arg_facts: clear,
            collect_bound_arg_facts: reflection,
            collect_method_contracts: reflection,
            collect: reflection,
            validate_bound_args: reflection,
            collect_impls: reflection,
            build_method_owner_ranges: reflection,
            emit_method_validation_rows: reflection,
            emit_method_param_validation_rows: reflection,
            validate_method_type_arg_rows: reflection,
            reduce_method_validation_errors: reflection,
            count_obligations,
            validate_obligations: reflection,
        }
    }

    fn predicate_clear_reflection() -> crate::reflection::SlangReflection {
        crate::reflection::SlangReflection {
            parameters: [
                "predicate_owner_node",
                "predicate_subject_token",
                "predicate_bound_token",
                "predicate_bound_decl_id",
                "predicate_bound_arg_count",
                "predicate_bound_first_arg_token",
                "predicate_bound_second_arg_token",
                "predicate_status",
                "predicate_method_contract_owner_hir",
                "predicate_method_contract_name_token",
                "predicate_method_contract_name_id",
                "predicate_method_contract_param_count",
                "predicate_method_contract_return_type_node",
                "predicate_method_contract_visibility",
                "predicate_method_contract_status",
                "predicate_method_contract_param_type_node",
                "predicate_method_contract_owner_range_first",
                "predicate_method_contract_owner_range_count",
                "predicate_method_validation_owner_node",
                "predicate_method_validation_peer_node",
                "predicate_method_validation_status",
                "predicate_method_validation_detail_token",
                "predicate_method_validation_first_error_row",
            ]
            .into_iter()
            .map(|name| reflected_storage(name, true))
            .collect(),
            ..Default::default()
        }
    }

    fn predicate_syntax_clear_reflection() -> crate::reflection::SlangReflection {
        crate::reflection::SlangReflection {
            parameters: vec![reflected_storage("predicate_syntax_token", true)],
            ..Default::default()
        }
    }

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

    fn semantic_feature_reflections() -> [crate::reflection::SlangReflection; 2] {
        let reflection = |parameters: &[(&str, bool)]| crate::reflection::SlangReflection {
            parameters: parameters
                .iter()
                .map(|(name, writable)| reflected_storage(name, *writable))
                .collect(),
            ..Default::default()
        };
        [
            reflection(&[
                ("compact_hir_count", false),
                ("compact_hir_core", false),
                ("compact_method_count", false),
                ("compact_predicate_count", false),
                ("semantic_feature_flags", true),
            ]),
            reflection(&[
                ("token_count", false),
                ("hir_active_count", false),
                ("compact_method_count", false),
                ("semantic_feature_flags", false),
                ("method_token_dispatch_args", true),
                ("method_hir_dispatch_args", true),
                ("method_compact_dispatch_args", true),
                ("method_token_hir_dispatch_args", true),
                ("method_radix_prefix_dispatch_args", true),
                ("method_radix_bases_dispatch_args", true),
                ("predicate_token_dispatch_args", true),
                ("predicate_hir_dispatch_args", true),
                ("predicate_radix_prefix_dispatch_args", true),
                ("predicate_radix_bases_dispatch_args", true),
                ("predicate_single_dispatch_args", true),
                ("match_hir_dispatch_args", true),
            ]),
        ]
    }

    fn generic_param_reflections() -> (
        crate::reflection::SlangReflection,
        crate::reflection::SlangReflection,
        crate::reflection::SlangReflection,
    ) {
        let decl = crate::reflection::SlangReflection {
            parameters: [
                ("compact_hir_count", false),
                ("compact_hir_core", false),
                ("compact_hir_payload", false),
                ("compact_generic_param_count", false),
                ("compact_generic_params", false),
                ("name_id_by_token", false),
                ("type_decl_generic_param_count", true),
                ("type_decl_generic_param_count_by_owner_token", true),
                ("type_decl_const_param_count_by_owner_token", true),
                ("generic_param_count_out", true),
                ("generic_param_owner_token", true),
                ("generic_param_name_id", true),
                ("generic_param_token", true),
                ("generic_param_node", true),
                ("generic_param_kind", true),
                ("generic_param_key_order", true),
                ("generic_param_slot_order", true),
                ("status", true),
            ]
            .into_iter()
            .map(|(name, writable)| reflected_storage(name, writable))
            .collect(),
            ..Default::default()
        };
        let small_sort = crate::reflection::SlangReflection {
            parameters: [
                ("generic_param_count_out", false),
                ("generic_param_owner_token", false),
                ("generic_param_name_id", false),
                ("generic_param_node", false),
                ("generic_param_kind", false),
                ("generic_param_key_order", true),
                ("generic_param_slot_order", true),
            ]
            .into_iter()
            .map(|(name, writable)| reflected_storage(name, writable))
            .collect(),
            ..Default::default()
        };
        let use_slots = crate::reflection::SlangReflection {
            parameters: [
                ("compact_hir_count", false),
                ("compact_hir_core", false),
                ("compact_hir_payload", false),
                ("compact_method_count", false),
                ("compact_method_cores", false),
                ("raw_to_compact_hir", false),
                ("compact_variant_count", false),
                ("compact_variants", false),
                ("compact_variant_payload_row_count", false),
                ("compact_variant_payloads", false),
                ("hir_status", false),
                ("hir_kind", false),
                ("hir_token_pos", false),
                ("hir_type_form", false),
                ("hir_type_len_token", false),
                ("hir_nearest_fn_node", false),
                ("name_id_by_token", false),
                ("type_decl_generic_param_count_by_owner_token", false),
                ("type_decl_const_param_count_by_owner_token", false),
                ("generic_decl_owner_by_node", false),
                ("generic_param_count_out", false),
                ("generic_param_owner_token", false),
                ("generic_param_name_id", false),
                ("generic_param_token", false),
                ("generic_param_node", false),
                ("generic_param_kind", false),
                ("generic_param_key_order", false),
                ("generic_param_slot_order", false),
                ("type_generic_param_slot_by_token", true),
                ("type_const_param_slot_by_token", true),
                ("type_expr_ref_tag", true),
                ("type_expr_ref_payload", true),
                ("status", true),
            ]
            .into_iter()
            .map(|(name, writable)| reflected_storage(name, writable))
            .collect(),
            ..Default::default()
        };
        (decl, small_sort, use_slots)
    }

    fn compact_condition_reflections() -> (
        crate::reflection::SlangReflection,
        crate::reflection::SlangReflection,
        crate::reflection::SlangReflection,
        crate::reflection::SlangReflection,
        crate::reflection::SlangReflection,
        crate::reflection::SlangReflection,
        crate::reflection::SlangReflection,
        crate::reflection::SlangReflection,
        crate::reflection::SlangReflection,
        crate::reflection::SlangReflection,
        crate::reflection::SlangReflection,
        crate::reflection::SlangReflection,
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
        let struct_init_clear = [
            "struct_init_field_context_instance",
            "struct_init_field_expected_ref_tag",
            "struct_init_field_expected_ref_payload",
            "struct_init_field_ordinal",
            "struct_lit_context_decl_token",
            "struct_lit_context_instance",
            "array_element_struct_literal_node",
            "struct_init_field_decl_node_by_node",
            "struct_init_field_ordinal_by_row",
            "struct_init_field_decl_token_by_row",
        ]
        .into_iter()
        .map(|name| reflected_storage(name, true))
        .collect();
        let struct_init_contexts = [
            "hir_status",
            "hir_token_pos",
            "hir_stmt_record",
            "hir_type_value_node",
            "hir_type_path_leaf_node",
            "hir_array_lit_context_stmt_node",
            "hir_array_element_parent_lit",
            "hir_nearest_array_element_node",
            "hir_struct_lit_head_node",
            "hir_struct_lit_context_stmt_node",
            "type_expr_ref_tag",
            "type_expr_ref_payload",
            "type_instance_kind",
            "type_instance_decl_token",
            "type_instance_elem_ref_tag",
            "type_instance_elem_ref_payload",
            "decl_type_ref_tag",
            "decl_type_ref_payload",
            "enclosing_fn",
            "compact_hir_count",
            "compact_hir_payload",
            "fn_return_ref_tag",
            "fn_return_ref_payload",
        ]
        .into_iter()
        .map(|name| reflected_storage(name, false))
        .chain(
            [
                "struct_lit_context_decl_token",
                "struct_lit_context_instance",
                "array_element_struct_literal_node",
            ]
            .into_iter()
            .map(|name| reflected_storage(name, true)),
        )
        .collect();
        let struct_init_fields = [
            "hir_status",
            "hir_kind",
            "hir_token_pos",
            "hir_struct_lit_head_node",
            "hir_struct_lit_field_parent_lit",
            "compact_hir_count",
            "compact_hir_core",
            "compact_hir_payload",
            "raw_to_compact_hir",
            "compact_field_count",
            "compact_fields",
            "struct_field_key_order",
            "name_id_by_token",
            "type_expr_ref_tag",
            "type_expr_ref_payload",
            "type_generic_param_slot_by_token",
            "type_decl_hir_node_by_token",
            "path_count_out",
            "path_id_by_owner_hir",
            "path_segment_count",
            "path_segment_base",
            "path_segment_token",
            "struct_lit_context_decl_token",
            "struct_lit_context_instance",
        ]
        .into_iter()
        .map(|name| reflected_storage(name, false))
        .chain(
            [
                "struct_init_field_context_instance",
                "struct_init_field_expected_ref_tag",
                "struct_init_field_expected_ref_payload",
                "struct_init_field_ordinal",
                "struct_init_field_ordinal_by_node",
                "struct_init_field_decl_node_by_node",
                "struct_init_field_ordinal_by_row",
                "struct_init_field_decl_token_by_row",
            ]
            .into_iter()
            .map(|name| reflected_storage(name, true)),
        )
        .collect();
        let struct_init_substitute = [
            "struct_init_field_context_instance",
            "type_instance_arg_start",
            "type_instance_arg_count",
            "type_instance_arg_ref_tag",
            "type_instance_arg_ref_payload",
            "type_instance_arg_row_start",
            "type_instance_arg_row_count_out",
            "type_instance_arg_row_ref_tag",
            "type_instance_arg_row_ref_payload",
            "type_generic_param_slot_by_token",
        ]
        .into_iter()
        .map(|name| reflected_storage(name, false))
        .chain(
            [
                "visible_type",
                "struct_init_field_expected_ref_tag",
                "struct_init_field_expected_ref_payload",
                "status",
            ]
            .into_iter()
            .map(|name| reflected_storage(name, true)),
        )
        .collect();
        let validate_aggregate_access = [
            "hir_status",
            "hir_kind",
            "hir_token_pos",
            "hir_expr_record",
            "hir_expr_result_root_node",
            "hir_struct_lit_field_parent_lit",
            "hir_struct_lit_field_value_node",
            "compact_hir_count",
            "compact_hir_core",
            "compact_hir_payload",
            "compact_hir_expr_parent",
            "raw_to_compact_hir",
            "compact_field_count",
            "compact_fields",
            "visible_decl",
            "visible_type",
            "call_return_type",
            "member_result_ref_tag",
            "member_result_field_ordinal",
            "name_id_by_token",
            "struct_field_key_order",
            "struct_lit_context_decl_token",
            "struct_init_field_ordinal",
        ]
        .into_iter()
        .map(|name| reflected_storage(name, false))
        .chain(std::iter::once(reflected_storage("status", true)))
        .collect();
        let member_receivers = [
            "compact_hir_count",
            "compact_hir_core",
            "compact_hir_payload",
            "compact_hir_expr_parent",
            "compact_hir_nearest_fn",
            "visible_decl",
            "visible_type",
            "decl_type_ref_tag",
            "decl_type_ref_payload",
            "method_decl_receiver_ref_tag",
            "method_decl_receiver_ref_payload",
            "type_instance_kind",
            "type_instance_elem_ref_tag",
            "type_instance_elem_ref_payload",
        ]
        .into_iter()
        .map(|name| reflected_storage(name, false))
        .chain(
            [
                "member_result_context_instance",
                "member_result_ref_tag",
                "member_result_ref_payload",
                "member_result_field_ordinal",
                "member_result_field_node",
                "member_next_node",
            ]
            .into_iter()
            .map(|name| reflected_storage(name, true)),
        )
        .collect();
        let member_results = [
            "compact_hir_count",
            "compact_hir_core",
            "compact_hir_payload",
            "compact_hir_expr_parent",
            "compact_field_count",
            "compact_fields",
            "struct_field_key_order",
            "name_id_by_token",
            "type_expr_ref_tag",
            "type_expr_ref_payload",
            "type_generic_param_slot_by_token",
            "type_instance_decl_token",
            "type_instance_arg_start",
            "type_instance_arg_count",
            "type_instance_arg_ref_tag",
            "type_instance_arg_ref_payload",
            "type_instance_arg_row_start",
            "type_instance_arg_row_count_out",
            "type_instance_arg_row_ref_tag",
            "type_instance_arg_row_ref_payload",
            "type_decl_hir_node_by_token",
            "path_count_out",
            "path_id_by_owner_hir",
            "path_segment_count",
            "path_segment_base",
            "path_segment_token",
            "member_next_node",
        ]
        .into_iter()
        .map(|name| reflected_storage(name, false))
        .chain(
            [
                "member_result_context_instance",
                "member_result_ref_tag",
                "member_result_ref_payload",
                "member_result_field_ordinal",
                "member_result_field_node",
            ]
            .into_iter()
            .map(|name| reflected_storage(name, true)),
        )
        .collect();
        let member_substitute = [
            "member_result_context_instance",
            "type_instance_arg_start",
            "type_instance_arg_count",
            "type_instance_arg_ref_tag",
            "type_instance_arg_ref_payload",
            "type_instance_arg_row_start",
            "type_instance_arg_row_count_out",
            "type_instance_arg_row_ref_tag",
            "type_instance_arg_row_ref_payload",
            "type_generic_param_slot_by_token",
        ]
        .into_iter()
        .map(|name| reflected_storage(name, false))
        .chain(
            [
                "visible_type",
                "member_result_ref_tag",
                "member_result_ref_payload",
                "status",
            ]
            .into_iter()
            .map(|name| reflected_storage(name, true)),
        )
        .collect();
        let semantic_array_index_refs = [
            "hir_kind",
            "hir_expr_record",
            "hir_expr_result_root_node",
            "raw_to_compact_hir",
            "visible_decl",
            "decl_type_ref_tag",
            "decl_type_ref_payload",
            "type_instance_kind",
            "type_instance_elem_ref_tag",
            "type_instance_elem_ref_payload",
        ]
        .into_iter()
        .map(|name| reflected_storage(name, false))
        .chain(
            [
                "semantic_expr_ref_tag_by_hir",
                "semantic_expr_ref_payload_by_hir",
            ]
            .into_iter()
            .map(|name| reflected_storage(name, true)),
        )
        .collect();
        let type_semantic_clear = [
            "type_semantic_row_by_token",
            "type_semantic_scan_input",
            "member_next_node",
        ]
        .into_iter()
        .map(|name| reflected_storage(name, true))
        .collect();
        let type_semantic_mark = [
            "hir_status",
            "hir_token_pos",
            "hir_type_form",
            "hir_type_path_leaf_node",
            "hir_semantic_dense_node",
            "hir_semantic_count",
            "type_expr_ref_tag",
            "type_expr_ref_payload",
        ]
        .into_iter()
        .map(|name| reflected_storage(name, false))
        .chain(
            ["type_semantic_row_by_token", "type_semantic_scan_input"]
                .into_iter()
                .map(|name| reflected_storage(name, true)),
        )
        .collect();
        let type_semantic_scatter = [
            "hir_semantic_count",
            "type_semantic_scan_input",
            "type_semantic_prefix",
            "type_semantic_count_out",
        ]
        .into_iter()
        .map(|name| reflected_storage(name, false))
        .chain(
            ["type_semantic_row_by_ordinal"]
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
            crate::reflection::SlangReflection {
                parameters: struct_init_clear,
                ..Default::default()
            },
            crate::reflection::SlangReflection {
                parameters: struct_init_contexts,
                ..Default::default()
            },
            crate::reflection::SlangReflection {
                parameters: struct_init_fields,
                ..Default::default()
            },
            crate::reflection::SlangReflection {
                parameters: struct_init_substitute,
                ..Default::default()
            },
            crate::reflection::SlangReflection {
                parameters: validate_aggregate_access,
                ..Default::default()
            },
            crate::reflection::SlangReflection {
                parameters: member_receivers,
                ..Default::default()
            },
            crate::reflection::SlangReflection {
                parameters: member_results,
                ..Default::default()
            },
            crate::reflection::SlangReflection {
                parameters: member_substitute,
                ..Default::default()
            },
            crate::reflection::SlangReflection {
                parameters: type_semantic_clear,
                ..Default::default()
            },
            crate::reflection::SlangReflection {
                parameters: type_semantic_mark,
                ..Default::default()
            },
            crate::reflection::SlangReflection {
                parameters: type_semantic_scatter,
                ..Default::default()
            },
            crate::reflection::SlangReflection {
                parameters: semantic_array_index_refs,
                ..Default::default()
            },
        )
    }

    fn name_family_reflections() -> [crate::reflection::SlangReflection; 8] {
        let reflection = |parameters: &[(&str, bool)]| crate::reflection::SlangReflection {
            parameters: parameters
                .iter()
                .map(|(name, writable)| reflected_storage(name, *writable))
                .collect(),
            ..Default::default()
        };
        let hash_common = [
            ("name_spans", false),
            ("name_count_in", false),
            ("source_bytes", false),
            ("language_symbol_bytes", false),
            ("name_hash_lo", true),
            ("name_hash_hi", true),
            ("name_hash_table_a", true),
            ("name_hash_table_b", true),
            ("status", true),
        ];
        let mut hash_assign = hash_common.to_vec();
        hash_assign.extend([
            ("sorted_name_id", true),
            ("name_id_by_input", true),
            ("name_id_by_token", true),
            ("language_name_id", true),
            ("unique_name_count", true),
        ]);
        [
            reflection(&[
                ("token_words", false),
                ("token_count", false),
                ("name_lexeme_flag", true),
                ("name_lexeme_kind", true),
            ]),
            reflection(&[
                ("token_words", false),
                ("token_count", false),
                ("name_lexeme_flag", false),
                ("name_lexeme_kind", false),
                ("name_lexeme_prefix", false),
                ("language_symbol_start", false),
                ("language_symbol_len", false),
                ("name_spans", true),
                ("name_order_in", true),
                ("name_order_tmp", true),
                ("name_id_by_token", true),
                ("name_count_out", true),
                ("name_max_len_out", true),
                ("status", true),
            ]),
            {
                let mut parameters = hash_common.to_vec();
                parameters.push(("unique_name_count", true));
                reflection(&parameters)
            },
            reflection(&hash_common),
            reflection(&hash_assign),
            reflection(&[("language_name_id", true), ("name_max_len", true)]),
            reflection(&[
                ("language_type_code_by_name_id", true),
                ("language_entrypoint_tag_by_name_id", true),
                ("language_intrinsic_tag_by_name_id", true),
            ]),
            reflection(&[
                ("language_name_id", false),
                ("language_decl_symbol_slot", false),
                ("language_decl_kind", false),
                ("language_decl_tag", false),
                ("language_decl_name_id", true),
                ("language_type_code_by_name_id", true),
                ("language_entrypoint_tag_by_name_id", true),
                ("language_intrinsic_tag_by_name_id", true),
            ]),
        ]
    }

    fn call_array_reflections() -> [crate::reflection::SlangReflection; 3] {
        let reflection = |reads: &[&str], writes: &[&str]| crate::reflection::SlangReflection {
            parameters: reads
                .iter()
                .map(|name| reflected_storage(name, false))
                .chain(writes.iter().map(|name| reflected_storage(name, true)))
                .collect(),
            ..Default::default()
        };
        let common = [
            "compact_hir_count",
            "compact_hir_core",
            "compact_hir_payload",
            "call_fn_index",
            "call_param_row_count_out",
            "call_param_row_ref_tag",
            "call_param_row_ref_payload",
            "fn_return_ref_tag",
            "fn_return_ref_payload",
            "decl_type_ref_tag",
            "decl_type_ref_payload",
            "visible_decl",
            "visible_type",
            "type_generic_param_slot_by_token",
            "type_const_param_slot_by_token",
            "type_instance_kind",
            "type_instance_len_kind",
            "type_instance_len_payload",
            "type_instance_elem_ref_tag",
            "type_instance_elem_ref_payload",
            "call_arg_row_count_out",
            "call_arg_row_node",
            "call_arg_row_call_node",
            "call_arg_param_row",
        ];
        let mut publish_reads = vec!["token_count", "call_return_type"];
        publish_reads.extend(common);
        let mut consume_reads = vec![
            "call_arg_record",
            "call_arg_row_ordinal",
            "call_arg_row_start",
            "call_arg_row_count",
            "call_result_instance",
            "call_param_count",
            "call_generic_slot_type",
            "call_const_slot_len",
            "call_generic_claim_callee",
            "call_generic_claim_slot",
            "call_generic_claim_type",
            "call_const_claim_callee",
            "call_const_claim_slot",
            "call_const_claim_len",
            "method_call_name_id",
        ];
        consume_reads.extend(common);
        [
            reflection(
                &publish_reads,
                &["call_has_array_arg", "call_result_instance"],
            ),
            reflection(&consume_reads, &["status", "call_return_type"]),
            reflection(
                &[
                    "compact_hir_count",
                    "compact_hir_core",
                    "compact_hir_payload",
                    "call_fn_index",
                    "fn_return_ref_tag",
                    "fn_return_ref_payload",
                    "type_instance_kind",
                ],
                &["call_result_instance"],
            ),
        ]
    }

    fn method_reflections() -> [crate::reflection::SlangReflection; 10] {
        let reflection = |reads: &[&str], writes: &[&str]| crate::reflection::SlangReflection {
            parameters: reads
                .iter()
                .map(|name| reflected_storage(name, false))
                .chain(writes.iter().map(|name| reflected_storage(name, true)))
                .collect(),
            ..Default::default()
        };
        [
            reflection(
                &[],
                &[
                    "method_decl_receiver_ref_tag",
                    "method_decl_receiver_ref_payload",
                    "method_decl_module_id",
                    "method_decl_method_row",
                    "method_decl_name_token",
                    "method_decl_name_id",
                    "method_decl_param_offset",
                    "method_decl_receiver_mode",
                    "method_decl_visibility",
                    "method_decl_signature_flags",
                    "method_call_receiver_ref_tag",
                    "method_call_receiver_ref_payload",
                    "method_call_name_id",
                    "method_call_site_module_id",
                ],
            ),
            reflection(
                &[
                    "compact_hir_count",
                    "compact_method_count",
                    "compact_method_cores",
                    "compact_method_signatures",
                ],
                &[
                    "method_decl_method_row",
                    "method_decl_name_token",
                    "method_decl_param_offset",
                    "method_decl_receiver_mode",
                    "method_decl_visibility",
                    "method_decl_signature_flags",
                ],
            ),
            reflection(
                &[
                    "compact_hir_count",
                    "compact_hir_core",
                    "compact_hir_links",
                    "compact_method_count",
                    "compact_method_cores",
                    "compact_method_signatures",
                    "name_id_by_token",
                    "type_expr_ref_tag",
                    "type_expr_ref_payload",
                    "method_decl_method_row",
                    "method_decl_name_token",
                ],
                &[
                    "method_decl_receiver_ref_tag",
                    "method_decl_receiver_ref_payload",
                    "method_decl_module_id",
                    "method_decl_name_id",
                ],
            ),
            reflection(
                &[
                    "compact_hir_count",
                    "compact_hir_payload",
                    "enclosing_fn",
                    "method_decl_param_offset",
                    "method_decl_receiver_mode",
                    "method_decl_receiver_ref_tag",
                    "method_decl_receiver_ref_payload",
                ],
                &["visible_decl", "decl_type_ref_tag", "decl_type_ref_payload"],
            ),
            reflection(
                &["token_count"],
                &[
                    "method_key_to_fn_token",
                    "method_key_status",
                    "method_key_duplicate_of",
                ],
            ),
            reflection(
                &[
                    "token_count",
                    "module_count_out",
                    "sorted_method_key_order",
                    "method_decl_method_row",
                    "method_decl_receiver_ref_tag",
                    "method_decl_receiver_ref_payload",
                    "method_decl_module_id",
                    "method_decl_name_token",
                    "method_decl_name_id",
                    "method_decl_visibility",
                    "module_type_path_type",
                    "type_instance_decl_token",
                    "type_instance_arg_start",
                    "type_instance_arg_count",
                    "type_instance_arg_ref_tag",
                    "type_instance_arg_ref_payload",
                    "type_instance_arg_hash",
                    "type_instance_arg_row_start",
                    "type_instance_arg_row_count_out",
                    "type_instance_arg_row_ref_tag",
                    "type_instance_arg_row_ref_payload",
                ],
                &["method_key_status", "method_key_duplicate_of", "status"],
            ),
            reflection(
                &[
                    "compact_hir_count",
                    "compact_hir_core",
                    "compact_hir_payload",
                    "visible_decl",
                    "decl_type_ref_tag",
                    "decl_type_ref_payload",
                    "member_result_ref_tag",
                    "member_result_ref_payload",
                    "type_expr_ref_tag",
                    "type_expr_ref_payload",
                    "type_instance_arg_row_start",
                    "type_instance_arg_row_count_out",
                    "type_instance_arg_row_ref_tag",
                    "type_instance_arg_row_ref_payload",
                ],
                &[
                    "method_call_receiver_ref_tag",
                    "method_call_receiver_ref_payload",
                    "method_call_name_id",
                    "method_call_site_module_id",
                    "type_instance_kind",
                    "type_instance_decl_token",
                    "type_instance_arg_start",
                    "type_instance_arg_count",
                    "type_instance_arg_ref_tag",
                    "type_instance_arg_ref_payload",
                    "type_instance_arg_hash",
                    "type_instance_state",
                ],
            ),
            reflection(
                &[
                    "compact_hir_count",
                    "compact_hir_core",
                    "compact_hir_payload",
                    "call_fn_index",
                    "call_return_type",
                    "call_return_type_token",
                    "fn_return_ref_tag",
                    "fn_return_ref_payload",
                    "decl_type_ref_tag",
                    "decl_type_ref_payload",
                ],
                &[
                    "method_call_receiver_ref_tag",
                    "method_call_receiver_ref_payload",
                    "method_call_name_id",
                    "method_call_site_module_id",
                ],
            ),
            reflection(
                &[
                    "token_count",
                    "method_call_receiver_ref_tag",
                    "method_call_receiver_ref_payload",
                    "method_call_name_id",
                    "method_call_site_module_id",
                    "sorted_method_key_order",
                    "method_key_status",
                    "method_decl_receiver_ref_tag",
                    "method_decl_receiver_ref_payload",
                    "method_decl_module_id",
                    "method_decl_name_id",
                    "type_instance_arg_hash",
                ],
                &[
                    "call_fn_index",
                    "call_return_type",
                    "call_return_type_token",
                ],
            ),
            reflection(
                &[
                    "compact_hir_count",
                    "compact_hir_core",
                    "compact_hir_payload",
                    "call_fn_index",
                    "call_return_type",
                    "call_return_type_token",
                    "method_decl_receiver_mode",
                    "method_decl_signature_flags",
                    "method_call_name_id",
                    "method_call_receiver_ref_tag",
                    "method_call_receiver_ref_payload",
                ],
                &["visible_type", "module_value_path_status", "status"],
            ),
        ]
    }

    #[test]
    fn typecheck_graph_colors_only_complete_workspace_intervals() {
        let (
            calls,
            types,
            aggregate_args,
            struct_init_clear,
            struct_init_contexts,
            struct_init_fields,
            struct_init_substitute,
            validate_aggregate_access,
            member_receivers,
            member_results,
            member_substitute,
            type_semantic_clear,
            type_semantic_mark,
            type_semantic_scatter,
            semantic_array_index_refs,
        ) = compact_condition_reflections();
        let predicate_reflection = crate::reflection::SlangReflection::default();
        let call_reflection = crate::reflection::SlangReflection::default();
        let call_initializer = call_initializer_reflection();
        let call_return_refs = call_return_refs_reflection();
        let predicate_syntax_clear_reflection = predicate_syntax_clear_reflection();
        let predicate_clear_reflection = predicate_clear_reflection();
        let predicate_obligation_reflection = crate::reflection::SlangReflection {
            parameters: vec![reflected_storage(
                "predicate_obligation_count_by_call",
                true,
            )],
            ..Default::default()
        };
        let (decl_generic_params, sort_generic_params_small, generic_param_use_slots) =
            generic_param_reflections();
        let [
            names_mark,
            names_scatter,
            names_hash_prepare,
            names_hash_insert,
            names_hash_assign,
            language_names_clear,
            language_type_codes_clear,
            language_decls_materialize,
        ] = name_family_reflections();
        let [
            calls_mark_array_args,
            calls_validate_array_results,
            calls_project_result_instances,
        ] = call_array_reflections();
        let [
            methods_clear,
            methods_collect,
            methods_attach_metadata,
            methods_bind_self_receivers,
            methods_seed_key_order,
            methods_validate_keys,
            methods_mark_call_keys,
            methods_mark_call_return_keys,
            methods_resolve_table,
            methods_resolve,
        ] = method_reflections();
        let [semantic_features_collect, semantic_features_dispatch] =
            semantic_feature_reflections();
        let reflections = BuildGraphReflections {
            semantic_features_collect: &semantic_features_collect,
            semantic_features_dispatch: &semantic_features_dispatch,
            names_mark: &names_mark,
            names_scatter: &names_scatter,
            names_hash_prepare: &names_hash_prepare,
            names_hash_insert: &names_hash_insert,
            names_hash_assign: &names_hash_assign,
            language_names_clear: &language_names_clear,
            language_type_codes_clear: &language_type_codes_clear,
            language_decls_materialize: &language_decls_materialize,
            conditions_compact_calls: &calls,
            conditions_compact_types: &types,
            conditions_aggregate_args: &aggregate_args,
            calls_mark_array_args: &calls_mark_array_args,
            calls_validate_array_results: &calls_validate_array_results,
            calls_project_result_instances: &calls_project_result_instances,
            calls: empty_call_reflections(&call_initializer, &call_return_refs, &call_reflection),
            methods_clear: &methods_clear,
            methods_collect: &methods_collect,
            methods_attach_metadata: &methods_attach_metadata,
            methods_bind_self_receivers: &methods_bind_self_receivers,
            methods_seed_key_order: &methods_seed_key_order,
            methods_validate_keys: &methods_validate_keys,
            methods_mark_call_keys: &methods_mark_call_keys,
            methods_mark_call_return_keys: &methods_mark_call_return_keys,
            methods_resolve_table: &methods_resolve_table,
            methods_resolve: &methods_resolve,
            type_instances_struct_init_clear: &struct_init_clear,
            type_instances_struct_init_contexts: &struct_init_contexts,
            type_instances_struct_init_fields: &struct_init_fields,
            type_instances_struct_init_substitute: &struct_init_substitute,
            type_instances_validate_aggregate_access: &validate_aggregate_access,
            type_instances_member_receivers: &member_receivers,
            type_instances_member_results: &member_results,
            type_instances_member_substitute: &member_substitute,
            type_instances_clear_semantic_type_rows: &type_semantic_clear,
            type_instances_mark_semantic_type_rows: &type_semantic_mark,
            type_instances_scatter_semantic_type_rows: &type_semantic_scatter,
            semantic_array_index_refs: &semantic_array_index_refs,
            type_instances_decl_generic_params: &decl_generic_params,
            type_instances_sort_generic_params_small: &sort_generic_params_small,
            type_instances_generic_param_use_slots: &generic_param_use_slots,
            predicates: Some(empty_predicate_reflections(
                &predicate_reflection,
                &predicate_syntax_clear_reflection,
                &predicate_clear_reflection,
                &predicate_obligation_reflection,
            )),
        };
        let (graph, resources) =
            build_graph(1024, 4096, 4, 4096, 1024, 768, 768, 512, 10, &reflections).unwrap();
        assert_eq!(graph.repeated_regions().len(), 9);
        let generic_owner_region = graph
            .repeated_regions()
            .iter()
            .find(|region| {
                region.first_pass
                    == graph
                        .pass_id(TYPE_INSTANCES_PROPAGATE_GENERIC_OWNER_A_TO_B_PASS)
                        .unwrap()
            })
            .expect("generic-owner pointer-jump repeated region");
        assert_eq!(generic_owner_region.iterations, 5);
        let generic_param_radix_region = graph
            .repeated_regions()
            .iter()
            .find(|region| {
                region.first_pass
                    == graph
                        .pass_id(
                            GENERIC_PARAMETER_RADIX_SORTS
                                .key
                                .passes
                                .order_to_temporary
                                .histogram,
                        )
                        .unwrap()
            })
            .expect("generic-parameter paired radix repeated region");
        assert_eq!(generic_param_radix_region.iterations, 3);
        let visible_radix_region = graph
            .repeated_regions()
            .iter()
            .find(|region| {
                region.first_pass
                    == graph
                        .pass_id(VISIBLE_RADIX_SORT.passes.order_to_temporary.histogram)
                        .unwrap()
            })
            .expect("visible-declaration radix sort repeated region");
        assert_eq!(
            visible_radix_region.iterations,
            visible_decl_key_radix_steps(4096) / 2,
        );
        let expression_region = graph
            .repeated_regions()
            .iter()
            .find(|region| region.first_pass == graph.pass_id(STEP_A_TO_B_PASS).unwrap())
            .expect("expression pointer-jump repeated region");
        assert_eq!(expression_region.iterations, 5);
        let early_struct_refs = graph
            .pass_id(SEMANTIC_STRUCT_LITERAL_REFS_EARLY_PROJECT_PASS)
            .unwrap();
        let generic_claim_emit = graph.pass_id(CALLS_GENERIC_CLAIM_EMIT.name).unwrap();
        assert!(early_struct_refs.index() < generic_claim_emit.index());
        let aggregate_validation = graph
            .pass_id(TYPE_INSTANCES_VALIDATE_AGGREGATE_ACCESS_PASS)
            .unwrap();
        assert!(
            graph
                .lifetime(resources.member_result_ref_tag)
                .unwrap()
                .last_pass
                .index()
                >= aggregate_validation.index(),
            "member results must remain live through final aggregate validation",
        );
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
        let resource = |name| graph.resource_id(name).unwrap();
        assert_ne!(slot(resources.scalar_a), slot(resources.scalar_b),);
        let name_workspace = [
            graph.resource_id("name_lexeme_flag").unwrap(),
            graph.resource_id("name_lexeme_kind").unwrap(),
            graph.resource_id("name_lexeme_prefix").unwrap(),
            graph.resource_id("name_scan_local_prefix").unwrap(),
            graph.resource_id("name_scan_block_sum").unwrap(),
            graph.resource_id("name_scan_prefix_a").unwrap(),
            graph.resource_id("name_scan_prefix_b").unwrap(),
            graph.resource_id("name_scan_total").unwrap(),
            graph.resource_id("name_max_len").unwrap(),
            graph.resource_id("name_spans").unwrap(),
            graph.resource_id("name_hash_lo").unwrap(),
            graph.resource_id("name_hash_hi").unwrap(),
            graph.resource_id("name_hash_table_a").unwrap(),
            graph.resource_id("name_hash_table_b").unwrap(),
            graph.resource_id("sorted_name_id").unwrap(),
            graph.resource_id("name_id_by_input").unwrap(),
            graph.resource_id("unique_name_count").unwrap(),
            graph.resource_id("decl_name_token").unwrap(),
            graph.resource_id("decl_id_by_name_token").unwrap(),
            graph.resource_id("decl_kind").unwrap(),
            resource("module_record_family_bits"),
            resource("module_record_family_flag"),
            resource("module_record_prefix"),
            resource("module_record_scan_local_prefix"),
            resource("module_record_scan_block_sum"),
            resource("module_record_scan_prefix_a"),
            resource("module_record_scan_prefix_b"),
            resource("module_path_key_radix_block_histogram"),
            resource("module_path_key_radix_block_bucket_prefix"),
            resource("module_path_key_radix_bucket_total"),
            resource("module_path_key_radix_bucket_base"),
        ];
        for resource in name_workspace {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "source-name compaction scratch must be graph-owned",
            );
        }
        assert_ne!(
            slot(graph.resource_id("name_hash_lo").unwrap()),
            slot(graph.resource_id("name_hash_hi").unwrap()),
            "the two halves of each name hash are written together",
        );
        assert_ne!(
            slot(graph.resource_id("name_hash_table_a").unwrap()),
            slot(graph.resource_id("name_hash_table_b").unwrap()),
            "both open-addressed name tables are updated together",
        );
        let module_borrow_fence = graph.pass_id(TYPE_INSTANCE_ARG_ROW_CLEAR_PASS).unwrap();
        for resource in [
            graph.resource_id("name_spans").unwrap(),
            graph.resource_id("name_hash_lo").unwrap(),
            graph.resource_id("name_hash_hi").unwrap(),
        ] {
            assert_eq!(
                graph.lifetime(resource).unwrap().last_pass,
                module_borrow_fence,
                "module indexing still reads this compact source-name row",
            );
        }
        let declaration_lifetime_end = graph.pass_id(SEMANTIC_ARTIFACT_PROJECT_PASS).unwrap();
        for resource in [
            graph.resource_id("decl_name_token").unwrap(),
            graph.resource_id("decl_id_by_name_token").unwrap(),
            graph.resource_id("decl_kind").unwrap(),
        ] {
            assert_eq!(
                graph.lifetime(resource).unwrap().last_pass,
                declaration_lifetime_end,
                "compact declaration lookup must survive every type-check consumer",
            );
        }
        assert_ne!(
            slot(graph.resource_id("decl_name_token").unwrap()),
            slot(graph.resource_id("decl_kind").unwrap()),
            "module declaration scatter writes names and kinds together",
        );
        assert_ne!(
            slot(graph.resource_id("decl_name_token").unwrap()),
            slot(graph.resource_id("decl_id_by_name_token").unwrap()),
            "module declaration scatter writes names and reverse lookup together",
        );
        assert_ne!(
            slot(graph.resource_id("decl_kind").unwrap()),
            slot(graph.resource_id("decl_id_by_name_token").unwrap()),
            "module declaration scatter writes kinds and reverse lookup together",
        );
        let initial_module_scan_resources = [
            resource("module_record_family_bits"),
            resource("module_record_family_flag"),
            resource("module_record_prefix"),
        ];
        let module_scan_start = graph.pass_id(MODULE_RECORD_SCAN_PASS).unwrap();
        let module_scan_end = graph.pass_id(MODULE_DECL_ROWS_MATERIALIZE_PASS).unwrap();
        for resource in initial_module_scan_resources {
            let lifetime = graph.lifetime(resource).unwrap();
            assert!(lifetime.first_pass.index() >= module_scan_start.index());
            assert!(lifetime.last_pass.index() <= module_scan_end.index());
        }
        let local_bindings = [
            resource("module_record_family_flag"),
            resource("module_record_scan_local_prefix"),
            resource("module_record_scan_block_sum"),
        ]
        .map(slot)
        .into_iter()
        .collect::<std::collections::BTreeSet<_>>();
        assert_eq!(
            local_bindings.len(),
            3,
            "scan input, local prefix, and block sums are bound together",
        );
        let hierarchy_bindings = [
            resource("module_record_scan_block_sum"),
            resource("module_record_scan_prefix_a"),
            resource("module_record_scan_prefix_b"),
        ]
        .map(slot)
        .into_iter()
        .collect::<std::collections::BTreeSet<_>>();
        assert_eq!(
            hierarchy_bindings.len(),
            3,
            "scan block sums, block prefixes, and hierarchy are bound together",
        );
        let module_radix_resources = [
            resource("module_path_key_radix_block_histogram"),
            resource("module_path_key_radix_block_bucket_prefix"),
            resource("module_path_key_radix_bucket_total"),
            resource("module_path_key_radix_bucket_base"),
        ];
        let module_radix_start = graph.pass_id(MODULE_PATH_KEY_RADIX_PASS).unwrap();
        let module_type_scan_end = graph.pass_id(DEPENDENCY_VISIBLE_SCAN.passes.apply).unwrap();
        let module_type_scan_start = graph.pass_id(DEPENDENCY_VISIBLE_SCAN.passes.local).unwrap();
        for resource in module_radix_resources {
            let lifetime = graph.lifetime(resource).unwrap();
            assert_eq!(lifetime.first_pass, module_radix_start);
            assert_eq!(lifetime.last_pass, module_scan_end);
        }
        assert!(
            graph
                .lifetime(resource("module_record_family_flag"))
                .unwrap()
                .last_pass
                .index()
                < module_radix_start.index(),
            "record-family input is dead before module radix sorting",
        );
        for resource in [
            resource("module_record_scan_local_prefix"),
            resource("module_record_scan_block_sum"),
            resource("module_record_scan_prefix_a"),
            resource("module_record_scan_prefix_b"),
        ] {
            let lifetime = graph.lifetime(resource).unwrap();
            assert!(
                lifetime.last_pass.index() >= module_type_scan_start.index()
                    && lifetime.last_pass.index() <= module_type_scan_end.index(),
                "shared scan hierarchy ends inside its final modeled visibility scan",
            );
            for radix_resource in module_radix_resources {
                assert_ne!(
                    slot(resource),
                    slot(radix_resource),
                    "module scan hierarchy and radix storage overlap in the real schedule",
                );
            }
        }
        assert_ne!(
            slot(resource("module_record_scan_local_prefix")),
            slot(resources.type_instance_arg_ref_tag),
            "declaration type flags use the future type-instance tag column while scanning",
        );
        assert_ne!(
            slot(resource("module_record_scan_local_prefix")),
            slot(resources.type_instance_arg_ref_payload),
            "declaration value flags use the future type-instance payload column while scanning",
        );
        let type_reference_resources = [
            resources.type_expr_ref_tag,
            resources.type_expr_ref_payload,
            resources.type_generic_param_slot_by_token,
            resources.type_const_param_slot_by_token,
            resources.type_decl_hir_node_by_token,
        ];
        for resource in type_reference_resources {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "type-reference and generic-slot relations must be graph-owned",
            );
        }
        assert_eq!(
            type_reference_resources
                .map(slot)
                .into_iter()
                .collect::<std::collections::BTreeSet<_>>()
                .len(),
            type_reference_resources.len(),
            "the type-instance clear pass initializes all five relations together",
        );
        let visible_workspace = [
            graph.resource_id("hir_visible_decl_flag").unwrap(),
            graph.resource_id("hir_visible_decl_prefix").unwrap(),
            graph
                .resource_id("hir_visible_decl_scan_local_prefix")
                .unwrap(),
            graph
                .resource_id("hir_visible_decl_scan_block_sum")
                .unwrap(),
            graph.resource_id("hir_visible_decl_scan_prefix_a").unwrap(),
            graph.resource_id("hir_visible_decl_scan_prefix_b").unwrap(),
            graph.resource_id("hir_visible_decl_count_out").unwrap(),
            graph.resource_id("hir_visible_decl_owner_fn").unwrap(),
            graph.resource_id("hir_visible_decl_name_id").unwrap(),
            graph.resource_id("hir_visible_decl_token").unwrap(),
            graph.resource_id("hir_visible_decl_scope_end").unwrap(),
            graph.resource_id("hir_visible_decl_node").unwrap(),
            graph.resource_id("hir_visible_decl_key_order").unwrap(),
            graph.resource_id("hir_visible_decl_key_order_tmp").unwrap(),
            graph
                .resource_id("hir_visible_decl_key_radix_dispatch_args")
                .unwrap(),
            graph
                .resource_id("hir_visible_decl_key_radix_block_histogram")
                .unwrap(),
            graph
                .resource_id("hir_visible_decl_key_radix_block_bucket_prefix")
                .unwrap(),
            graph
                .resource_id("hir_visible_decl_key_radix_bucket_total")
                .unwrap(),
            graph
                .resource_id("hir_visible_decl_key_radix_bucket_base")
                .unwrap(),
            graph.resource_id("hir_visible_decl_scope_tree").unwrap(),
        ];
        for resource in visible_workspace {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "visible-declaration compaction scratch must be graph-owned",
            );
        }
        assert_ne!(
            slot(graph.resource_id("hir_visible_decl_flag").unwrap()),
            slot(graph.resource_id("hir_visible_decl_prefix").unwrap()),
            "visible scan input and prefix output are simultaneously bound",
        );
        assert_ne!(
            slot(graph.resource_id("hir_visible_decl_key_order").unwrap()),
            slot(graph.resource_id("hir_visible_decl_key_order_tmp").unwrap()),
            "visible radix input and scatter output are simultaneously bound",
        );
        let predicate_row_workspace = [
            resources.predicate_owner_node,
            resources.predicate_subject_token,
            resources.predicate_bound_token,
            resources.predicate_bound_decl_id,
            resources.predicate_bound_arg_count,
            resources.predicate_bound_first_arg_token,
            resources.predicate_bound_second_arg_token,
            resources.predicate_status,
            resources.predicate_method_contract_owner_hir,
            resources.predicate_method_contract_name_token,
            resources.predicate_method_contract_name_id,
            resources.predicate_method_contract_param_count,
            resources.predicate_method_contract_return_type_node,
            resources.predicate_method_contract_visibility,
            resources.predicate_method_contract_status,
            resources.predicate_method_contract_param_type_node,
            resources.predicate_method_contract_owner_range_first,
            resources.predicate_method_contract_owner_range_count,
            resources.predicate_method_validation_owner_node,
            resources.predicate_method_validation_peer_node,
            resources.predicate_method_validation_status,
            resources.predicate_method_validation_detail_token,
            resources.predicate_method_validation_first_error_row,
        ];
        assert_eq!(
            graph
                .resource(resources.predicate_syntax_token)
                .unwrap()
                .class,
            ResourceClass::Workspace,
            "predicate syntax markers must use graph-owned phase workspace",
        );
        assert!(
            graph
                .pass_id(PREDICATES_CLEAR_SYNTAX_TOKENS_PASS)
                .unwrap()
                .index()
                < graph
                    .pass_id(TYPE_INSTANCE_ARG_ROW_CLEAR_PASS)
                    .unwrap()
                    .index(),
            "predicate syntax markers are cleared before their module-path producer runs",
        );
        let generic_owner_workspace = [
            resources.generic_decl_owner_by_node_a,
            resources.generic_decl_owner_by_node_b,
            resources.predicate_bound_list_by_node_a,
            resources.predicate_bound_list_by_node_b,
            resources.generic_decl_parent_jump_a,
            resources.generic_decl_parent_jump_b,
        ];
        for resource in generic_owner_workspace {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "generic-owner pointer jumping must use graph-owned workspace",
            );
        }
        let mut generic_owner_slots = generic_owner_workspace.map(slot);
        generic_owner_slots.sort_unstable();
        assert!(
            generic_owner_slots
                .windows(2)
                .all(|pair| pair[0] != pair[1]),
            "all generic-owner pointer-jump inputs and outputs are simultaneously bound",
        );
        assert!(
            graph
                .pass_id(TYPE_INSTANCE_ARG_ROW_CLEAR_PASS)
                .unwrap()
                .index()
                < graph
                    .pass_id(TYPE_INSTANCES_MARK_GENERIC_PARAM_RECORDS_PASS)
                    .unwrap()
                    .index(),
            "generic-owner initialization follows the shared type-instance clear",
        );
        assert!(
            graph
                .pass_id(TYPE_INSTANCES_PROPAGATE_GENERIC_OWNER_B_TO_A_PASS)
                .unwrap()
                .index()
                < graph
                    .pass_id(TYPE_INSTANCE_CORE_COLLECT_INITIAL_PASS)
                    .unwrap()
                    .index(),
            "generic-owner propagation completes before type-instance collection",
        );
        for resource in [
            resources.generic_param_count_out,
            resources.generic_param_owner_token,
            resources.generic_param_name_id,
            resources.generic_param_token,
            resources.generic_param_kind,
            resources.generic_param_key_order,
            resources.generic_param_slot_order,
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "generic-parameter rows must be graph-owned phase workspace",
            );
        }
        for resource in [
            resources.generic_param_node,
            resources
                .generic_param_key_order_tmp
                .expect("large sort key-order ping-pong"),
            resources
                .generic_param_slot_order_tmp
                .expect("large sort slot-order ping-pong"),
            resources
                .generic_param_slot_radix_block_histogram
                .expect("large sort slot histogram"),
            resources
                .generic_param_slot_radix_block_bucket_prefix
                .expect("large sort slot prefix"),
            resources
                .generic_param_slot_radix_bucket_total
                .expect("large sort slot total"),
            resources
                .generic_param_slot_radix_bucket_base
                .expect("large sort slot base"),
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "generic-parameter sort intermediates must be graph-owned workspace",
            );
        }
        assert_ne!(
            slot(resources.generic_param_key_order),
            slot(
                resources
                    .generic_param_key_order_tmp
                    .expect("large sort key-order ping-pong"),
            ),
            "generic key radix input and output may not alias",
        );
        assert_ne!(
            slot(resources.generic_param_slot_order),
            slot(
                resources
                    .generic_param_slot_order_tmp
                    .expect("large sort slot-order ping-pong"),
            ),
            "generic slot radix input and output may not alias",
        );
        assert!(
            graph
                .pass_id(TYPE_INSTANCES_DECL_GENERIC_PARAMS_PASS)
                .unwrap()
                .index()
                < graph
                    .pass_id(
                        GENERIC_PARAMETER_RADIX_SORTS
                            .key
                            .passes
                            .order_to_temporary
                            .histogram
                    )
                    .unwrap()
                    .index(),
            "compact generic rows are produced before sorting",
        );
        assert!(
            graph
                .pass_id(
                    GENERIC_PARAMETER_RADIX_SORTS
                        .slot
                        .passes
                        .temporary_to_order
                        .scatter
                )
                .unwrap()
                .index()
                < graph
                    .pass_id(TYPE_INSTANCES_GENERIC_PARAM_USE_SLOTS_PASS)
                    .unwrap()
                    .index(),
            "both generic sort orders complete before use-site resolution",
        );
        for resource in predicate_row_workspace {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "predicate core and method-validation rows must be graph-owned workspace",
            );
        }
        let mut predicate_clear_slots = predicate_row_workspace.map(slot);
        predicate_clear_slots.sort_unstable();
        assert!(
            predicate_clear_slots
                .windows(2)
                .all(|pair| pair[0] != pair[1]),
            "all predicate rows overwritten by the shared clear pass are simultaneously bound",
        );
        for resource in [
            resources.predicate_method_contract_key_order,
            resources.predicate_method_contract_key_order_tmp,
            resources.predicate_method_param_key_order,
            resources.predicate_method_param_key_order_tmp,
            resources.predicate_owner_key_order,
            resources.predicate_owner_key_order_tmp,
            resources.predicate_impl_key_order,
            resources.predicate_impl_key_order_tmp,
            resources.predicate_key_radix_block_histogram,
            resources.predicate_key_radix_block_bucket_prefix,
            resources.predicate_key_radix_bucket_total,
            resources.predicate_key_radix_bucket_base,
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "predicate key sorting must use graph-owned phase workspace",
            );
        }
        assert_ne!(
            slot(resources.predicate_method_contract_key_order),
            slot(resources.predicate_method_contract_key_order_tmp),
            "predicate radix input and scatter output are simultaneously bound",
        );
        assert_ne!(
            slot(resources.predicate_owner_key_order),
            slot(resources.predicate_owner_key_order_tmp),
            "predicate owner-key radix input and output may not alias",
        );
        for resource in [
            resources.predicate_obligation_count_by_call,
            resources.predicate_obligation_prefix_by_call,
            resources.predicate_obligation_scan_local_prefix,
            resources.predicate_obligation_scan_block_sum,
            resources.predicate_obligation_scan_prefix_a,
            resources.predicate_obligation_scan_prefix_b,
            resources.predicate_obligation_pair_total,
            resources.predicate_obligation_pair_dispatch_args,
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "predicate obligation emission must use graph-owned workspace",
            );
        }
        assert_eq!(
            slot(resources.predicate_obligation_count_by_call),
            slot(resources.predicate_obligation_prefix_by_call),
            "the scan output should reuse its dead input allocation after the local pass",
        );
        assert_eq!(
            graph
                .resource(resources.predicate_obligation_pair_dispatch_args)
                .unwrap()
                .usage,
            WorkspaceUsageClass::StorageIndirect,
        );
        assert_eq!(
            graph.resource(resources.member_next_node).unwrap().class,
            ResourceClass::Workspace,
            "dense member-chain edges must remain phase-local graph workspace",
        );
        let member_result_resources = [
            resources.member_result_context_instance,
            resources.member_result_ref_tag,
            resources.member_result_ref_payload,
            resources.member_result_field_ordinal,
            resources.member_result_field_node,
        ];
        for resource in member_result_resources {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "member-result columns must be graph-owned phase-local workspace",
            );
        }
        let mut member_result_slots = member_result_resources.map(slot);
        member_result_slots.sort_unstable();
        assert!(
            member_result_slots
                .windows(2)
                .all(|pair| pair[0] != pair[1]),
            "simultaneously written member-result columns must occupy distinct slots",
        );
        let member_lifetime = graph
            .lifetime(resources.member_result_ref_tag)
            .expect("member-result lifetime");
        assert_eq!(
            member_lifetime.first_pass,
            graph.pass_id(TYPE_SEMANTIC_CLEAR_PASS).unwrap(),
            "member-result workspace must cover the omitted early projection schedule",
        );
        assert_eq!(
            member_lifetime.last_pass,
            graph
                .pass_id(SEMANTIC_EXPRESSION_REFS_PROJECT_PASS)
                .unwrap(),
            "member-result workspace must survive through compact semantic projection",
        );
        for member_slot in member_result_slots {
            assert_ne!(
                member_slot,
                slot(resources.scalar_a),
                "member results are live while expression scalar propagation runs",
            );
            assert_ne!(
                member_slot,
                slot(resources.scalar_b),
                "member results are live while expression scalar propagation runs",
            );
        }
        let struct_workspace_resources = [
            resources.struct_init_field_context_instance,
            resources.struct_init_field_expected_ref_tag,
            resources.struct_init_field_expected_ref_payload,
            resources.struct_init_field_ordinal,
            resources.struct_init_field_ordinal_by_node,
            resources.struct_init_field_decl_node_by_node,
            resources.struct_init_field_decl_token_by_row,
            resources.struct_lit_context_decl_token,
            resources.struct_lit_context_instance,
            resources.array_element_struct_literal_node,
        ];
        for resource in struct_workspace_resources {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "struct-literal scratch must be graph-owned workspace",
            );
        }
        assert_eq!(
            graph.resource(resources.type_instance_kind).unwrap().class,
            ResourceClass::Workspace,
            "type-instance kinds must be assigned by the graph rather than hand-aliased",
        );
        assert_ne!(
            slot(resources.type_instance_kind),
            slot(resources.array_element_struct_literal_node),
            "struct contexts read type-instance kinds while writing array-element scratch",
        );
        assert_eq!(
            graph
                .resource(resources.struct_init_field_ordinal_by_row)
                .unwrap()
                .class,
            ResourceClass::Output,
            "the compact field-ordinal row consumed by lowering is a graph output",
        );
        assert!(
            graph
                .pass_id(TYPE_INSTANCES_STRUCT_INIT_CLEAR_PASS)
                .unwrap()
                .index()
                < graph
                    .pass_id(TYPE_INSTANCES_STRUCT_INIT_CONTEXTS_PASS)
                    .unwrap()
                    .index(),
        );
        assert!(
            graph
                .pass_id(TYPE_INSTANCES_STRUCT_INIT_CONTEXTS_PASS)
                .unwrap()
                .index()
                < graph
                    .pass_id(TYPE_INSTANCES_STRUCT_INIT_FIELDS_PASS)
                    .unwrap()
                    .index(),
        );
        assert!(
            graph
                .pass_id(TYPE_INSTANCES_STRUCT_INIT_FIELDS_PASS)
                .unwrap()
                .index()
                < graph
                    .pass_id(TYPE_INSTANCES_STRUCT_INIT_SUBSTITUTE_PASS)
                    .unwrap()
                    .index(),
        );
        assert_eq!(
            graph.resource(resources.fn_entrypoint_tag).unwrap().class,
            ResourceClass::Workspace,
            "function entrypoint tags must be phase-local graph workspace",
        );
        assert!(
            graph.pass_id(CALLS_ENTRYPOINT_CLEAR.name).unwrap().index()
                < graph
                    .pass_id(CALLS_ENTRYPOINT_PROJECT.name)
                    .unwrap()
                    .index(),
            "function entrypoint tags must be cleared before projection",
        );
        assert!(
            graph
                .pass_id(CALLS_ENTRYPOINT_PROJECT.name)
                .unwrap()
                .index()
                < graph
                    .pass_id(SEMANTIC_ARTIFACT_PROJECT_PASS)
                    .unwrap()
                    .index(),
            "function entrypoint tags must exist before semantic artifact projection",
        );
        for resource in [
            resources.type_instance_arg_start,
            resources.type_instance_arg_count,
            resources.type_instance_arg_ref_tag,
            resources.type_instance_arg_ref_payload,
            resources.type_instance_arg_row_start,
            resources.type_instance_arg_row_count_out,
            resources.type_instance_arg_row_scan_local_prefix,
            resources.type_instance_arg_row_scan_block_sum,
            resources.type_instance_arg_row_scan_prefix_a,
            resources.type_instance_arg_row_scan_prefix_b,
            resources.type_instance_arg_row_ref_tag,
            resources.type_instance_arg_row_ref_payload,
            resources.type_instance_arg_hash,
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "type-instance argument storage must be graph-owned",
            );
        }
        let mut clear_slots = [
            slot(resources.type_instance_arg_start),
            slot(resources.type_instance_arg_count),
            slot(resources.type_instance_arg_ref_tag),
            slot(resources.type_instance_arg_ref_payload),
            slot(resources.type_instance_arg_row_start),
            slot(resources.type_instance_arg_row_count_out),
            slot(resources.type_instance_arg_row_ref_tag),
            slot(resources.type_instance_arg_row_ref_payload),
            slot(resources.type_instance_arg_hash),
        ];
        clear_slots.sort_unstable();
        assert!(
            clear_slots.windows(2).all(|pair| pair[0] != pair[1]),
            "all columns reset by the physical type-instance clear must occupy distinct slots",
        );
        assert_ne!(
            slot(resources.type_instance_arg_row_start),
            slot(resources.type_instance_arg_row_scan_local_prefix),
            "the argument-row output and scan-local prefix are simultaneously bound",
        );
        let mut argument_row_slots = [
            slot(resources.type_instance_arg_row_start),
            slot(resources.type_instance_arg_row_count_out),
            slot(resources.type_instance_arg_row_scan_local_prefix),
            slot(resources.type_instance_arg_row_scan_block_sum),
            slot(resources.type_instance_arg_row_scan_prefix_a),
            slot(resources.type_instance_arg_row_scan_prefix_b),
        ];
        argument_row_slots.sort_unstable();
        assert!(
            argument_row_slots.windows(2).all(|pair| pair[0] != pair[1]),
            "all buffers bound by the argument-row scan must occupy distinct slots",
        );
        assert!(
            graph
                .pass_id(TYPE_INSTANCE_ARG_ROW_CLEAR_PASS)
                .unwrap()
                .index()
                < graph
                    .pass_id(TYPE_INSTANCE_ARG_ROW_SCAN.passes.local)
                    .unwrap()
                    .index(),
            "argument-row sentinels must be initialized before compaction",
        );
        assert!(
            graph
                .pass_id(TYPE_INSTANCE_ARG_ROW_CLEAR_PASS)
                .unwrap()
                .index()
                < graph
                    .pass_id(TYPE_INSTANCE_CORE_COLLECT_INITIAL_PASS)
                    .unwrap()
                    .index(),
            "type-instance arguments must be reset before initial collection",
        );
        assert!(
            graph
                .pass_id(TYPE_INSTANCE_CORE_COLLECT_INITIAL_PASS)
                .unwrap()
                .index()
                < graph
                    .pass_id(TYPE_INSTANCE_CORE_COLLECT_PROJECTED_PASS)
                    .unwrap()
                    .index(),
            "projected collection follows the initial unresolved collection",
        );
        assert!(
            graph
                .pass_id(TYPE_INSTANCE_CORE_COLLECT_PROJECTED_PASS)
                .unwrap()
                .index()
                < graph
                    .pass_id(TYPE_INSTANCE_ARG_ROW_SCAN.passes.local)
                    .unwrap()
                    .index(),
            "argument counts must be final before row compaction",
        );
        assert!(
            graph
                .pass_id(TYPE_INSTANCE_ARG_ROW_SCAN.passes.local)
                .unwrap()
                .index()
                < graph.pass_id(TYPE_SEMANTIC_CLEAR_PASS).unwrap().index(),
            "argument-row compaction must precede semantic type compaction",
        );
        assert!(
            graph
                .pass_id(TYPE_INSTANCE_ARG_ROW_SCAN.passes.local)
                .unwrap()
                .index()
                < graph
                    .pass_id(TYPE_INSTANCE_ARG_ROW_POPULATE_PASS)
                    .unwrap()
                    .index(),
            "argument-row offsets must exist before sparse references are populated",
        );
        assert_ne!(
            slot(resources.type_instance_arg_row_ref_tag),
            slot(resources.type_instance_arg_row_ref_payload),
            "sparse reference tag and payload columns are written together",
        );
        assert!(
            graph
                .pass_id(TYPE_INSTANCE_ARG_ROW_POPULATE_PASS)
                .unwrap()
                .index()
                < graph.pass_id(TYPE_SEMANTIC_CLEAR_PASS).unwrap().index(),
            "sparse argument references must be populated before semantic consumers",
        );
        let hash_rows = graph.pass_id(TYPE_INSTANCE_ARG_HASH_ROWS_PASS).unwrap();
        let method_key_seed = graph.pass_id(METHOD_KEY_SEED_PASS).unwrap();
        let method_key_sort_first = graph
            .pass_id(METHOD_KEY_RADIX_SORT.passes.names()[0])
            .unwrap();
        let method_key_sort_last = graph
            .pass_id(METHOD_KEY_RADIX_SORT.passes.names()[7])
            .unwrap();
        let method_key_validation = graph.pass_id(METHOD_KEY_VALIDATION_PASS).unwrap();
        let mark_call_keys = graph.pass_id(METHODS_MARK_CALL_KEYS.name).unwrap();
        let mark_call_return_keys = graph.pass_id(METHODS_MARK_CALL_RETURN_KEYS.name).unwrap();
        let resolve_table = graph.pass_id(METHODS_RESOLVE_TABLE.name).unwrap();
        let resolve = graph.pass_id(METHODS_RESOLVE.name).unwrap();
        for resource in [
            resources.method_key_to_fn_token,
            resources.method_key_order_tmp,
            resources.method_key_status,
            resources.method_key_duplicate_of,
            resources.method_key_radix_block_histogram,
            resources.method_key_radix_block_bucket_prefix,
            resources.method_key_radix_bucket_total,
            resources.method_key_radix_bucket_base,
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "method-key lookup state must be graph-owned workspace",
            );
        }
        assert_ne!(
            slot(resources.type_instance_arg_hash),
            slot(resources.method_key_status),
            "method-key validation reads argument hashes while writing status",
        );
        assert_ne!(
            slot(resources.type_instance_arg_hash),
            slot(resources.method_key_to_fn_token),
            "method-key construction reads argument hashes while writing key order",
        );
        assert_ne!(
            slot(resources.method_key_to_fn_token),
            slot(resources.method_key_status),
            "method-key validation reads sorted order while writing status",
        );
        assert!(
            graph
                .pass_id(TYPE_INSTANCE_ARG_ROW_POPULATE_PASS)
                .unwrap()
                .index()
                < hash_rows.index()
        );
        assert!(hash_rows.index() < mark_call_keys.index());
        assert!(mark_call_keys.index() < method_key_seed.index());
        assert!(method_key_seed.index() < method_key_sort_first.index());
        assert!(method_key_sort_last.index() < method_key_validation.index());
        assert!(method_key_validation.index() < mark_call_return_keys.index());
        assert!(mark_call_return_keys.index() < resolve_table.index());
        assert!(resolve_table.index() < resolve.index());
        for resource in [
            resources.type_semantic_row_by_token,
            resources.type_semantic_scan_input,
            resources.type_semantic_prefix,
            resources.type_semantic_count_out,
            resources.type_semantic_row_by_ordinal,
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "semantic type compaction must be graph-owned workspace",
            );
        }
        assert_ne!(
            slot(resources.type_semantic_scan_input),
            slot(resources.type_semantic_prefix),
            "semantic scan input and prefix are simultaneously bound",
        );
        let semantic_clear = graph.pass_id(TYPE_SEMANTIC_CLEAR_PASS).unwrap();
        let semantic_mark = graph.pass_id(TYPE_SEMANTIC_MARK_PASS).unwrap();
        let semantic_scan = graph.pass_id(TYPE_SEMANTIC_SCAN.passes.local).unwrap();
        let semantic_scatter = graph.pass_id(TYPE_SEMANTIC_SCATTER_PASS).unwrap();
        assert!(semantic_clear.index() < semantic_mark.index());
        assert!(semantic_mark.index() < semantic_scan.index());
        assert!(semantic_scan.index() < semantic_scatter.index());
        assert!(
            semantic_scatter.index() < graph.pass_id(FN_CONTEXT_MARK_PASS).unwrap().index(),
            "type-instance semantic rows are produced before function-context workspace runs",
        );
        assert!(
            semantic_scatter.index()
                < graph
                    .pass_id(CONDITIONS_AGGREGATE_ARGS_CALLS_PASS)
                    .unwrap()
                    .index(),
            "semantic compaction must finish before aggregate consumers",
        );
        let mut control_slots = [
            slot(resources.if_delta),
            slot(resources.if_depth_inblock),
            slot(resources.if_block_sum),
            slot(resources.if_prefix_a),
            slot(resources.if_prefix_b),
            slot(resources.if_block_prefix),
            slot(resources.if_depth),
        ];
        control_slots.sort_unstable();
        assert!(
            control_slots.windows(2).any(|pair| pair[0] == pair[1]),
            "at least one non-overlapping control-depth row must reuse workspace",
        );
        assert_ne!(
            slot(resources.if_depth_inblock),
            slot(resources.if_block_prefix),
            "simultaneously read control-scan rows must not alias",
        );
        assert_ne!(
            slot(resources.type_instance_state),
            slot(resources.if_depth),
            "late-recorded type-instance state must not overwrite control depth retained for semantic projection",
        );
        assert_eq!(
            graph
                .lifetime(resources.type_instance_state)
                .unwrap()
                .last_pass,
            graph.pass_id(SEMANTIC_ARTIFACT_PROJECT_PASS).unwrap(),
            "the conservative fence must cover the resident recorder's unmodeled middle schedule",
        );
        let mut function_slots = [
            slot(resources.enclosing_fn),
            slot(resources.enclosing_fn_end),
            slot(resources.fn_event_value),
            slot(resources.fn_event_end),
            slot(resources.fn_event_index),
            slot(resources.fn_event_inblock),
            slot(resources.fn_block_sum),
            slot(resources.fn_prefix_a),
            slot(resources.fn_prefix_b),
            slot(resources.fn_block_prefix),
        ];
        function_slots.sort_unstable();
        assert!(
            function_slots.windows(2).any(|pair| pair[0] == pair[1]),
            "non-overlapping function-context rows must reuse workspace",
        );
        assert_ne!(
            slot(resources.fn_event_inblock),
            slot(resources.fn_block_prefix),
            "simultaneously read function-context rows must not alias",
        );
        for resource in graph.resources() {
            let comparison_boundary = resource.name.starts_with("aggregate_compare_")
                || resource.name.starts_with("type_subtree_compare_");
            assert_eq!(
                resource.class == ResourceClass::Resident,
                comparison_boundary,
                "only comparison families with noncontiguous resident-recorder invocations may remain dedicated: {}",
                resource.name,
            );
        }
        assert_eq!(
            graph
                .resource(graph.resource_id("semantic_feature_flags").unwrap())
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
        assert!(graph.pass_id(CALLS_ARRAY_STATE_PUBLISH.name).is_some());
        assert!(graph.pass_id(CALLS_RESULT_INSTANCE_PROJECT.name).is_some());
        assert!(
            graph
                .pass_id(CALLS_RESULT_INSTANCE_PROJECT.name)
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
            graph
                .resource(graph.resource_id("visible_decl").unwrap())
                .unwrap()
                .class,
            ResourceClass::External,
            "visible declarations remain owned by the resident type-check state",
        );
        assert_eq!(
            graph
                .resource(graph.resource_id("visible_type").unwrap())
                .unwrap()
                .class,
            ResourceClass::External,
            "visible types remain owned by the resident type-check state",
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
                ResourceClass::Resident,
                "aggregate request columns remain dedicated until every invocation is graph-scheduled",
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
        for resource in [
            resources.aggregate_compare_prefix,
            resources.aggregate_compare_count_out,
            resources.aggregate_compare_scan_local_prefix,
            resources.aggregate_compare_scan_block_sum,
            resources.aggregate_compare_scan_prefix_a,
            resources.aggregate_compare_scan_prefix_b,
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Resident,
                "aggregate scan hierarchy remains dedicated until every invocation is graph-scheduled",
            );
        }
        assert_eq!(
            graph
                .resource(resources.aggregate_compare_dispatch_args)
                .unwrap()
                .usage,
            WorkspaceUsageClass::StorageIndirect,
            "indirect aggregate dispatch storage must not alias storage-only slots",
        );
        assert_ne!(
            slot(resources.aggregate_compare_scan_input),
            slot(resources.aggregate_compare_prefix),
            "aggregate scan input and output are simultaneously live",
        );
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
            resources.semantic_function_return_type_by_hir,
            resources.semantic_function_entrypoint_by_hir,
            resources.semantic_function_host_service_by_hir,
            resources.semantic_control_depth_by_hir,
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
        assert!(
            graph
                .pass_id(CALLS_ARGUMENT_MATCH_INITIALIZE.name)
                .is_some()
        );
        assert!(graph.pass_id(CALLS_ARGUMENT_MATCH_CONSUME.name).is_some());
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
            "radix histogram scratch is dead after each claim-family sort and should reuse workspace",
        );
        let aggregate_publish = graph.pass_id(CALLS_GENERIC_CLAIM_VALIDATE.name).unwrap();
        assert!(
            graph
                .pass_id(GENERIC_CLAIM_RADIX_SORT.passes.temporary_to_order.scatter)
                .unwrap()
                .index()
                < aggregate_publish.index()
        );
        assert!(
            aggregate_publish.index()
                < graph
                    .pass_id(CALLS_REQUIRED_GENERIC_MARK.name)
                    .unwrap()
                    .index()
        );
        assert!(
            graph
                .pass_id(CONST_CLAIM_RADIX_SORT.passes.temporary_to_order.scatter)
                .unwrap()
                .index()
                < graph
                    .pass_id(AGGREGATE_CALL_SCAN_PASSES.local)
                    .unwrap()
                    .index()
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
        assert!(
            graph
                .lifetime(resources.call_arg_param_row)
                .unwrap()
                .last_pass
                .index()
                >= graph
                    .pass_id(CALLS_ARRAY_STATE_CONSUME.name)
                    .unwrap()
                    .index(),
            "array-result validation still consumes the matched argument relation",
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
        let (
            calls,
            types,
            aggregate_args,
            struct_init_clear,
            struct_init_contexts,
            struct_init_fields,
            struct_init_substitute,
            validate_aggregate_access,
            member_receivers,
            member_results,
            member_substitute,
            type_semantic_clear,
            type_semantic_mark,
            type_semantic_scatter,
            semantic_array_index_refs,
        ) = compact_condition_reflections();
        let predicate_reflection = crate::reflection::SlangReflection::default();
        let call_reflection = crate::reflection::SlangReflection::default();
        let call_initializer = call_initializer_reflection();
        let call_return_refs = call_return_refs_reflection();
        let predicate_syntax_clear_reflection = predicate_syntax_clear_reflection();
        let predicate_clear_reflection = predicate_clear_reflection();
        let predicate_obligation_reflection = crate::reflection::SlangReflection {
            parameters: vec![reflected_storage(
                "predicate_obligation_count_by_call",
                true,
            )],
            ..Default::default()
        };
        let (decl_generic_params, sort_generic_params_small, generic_param_use_slots) =
            generic_param_reflections();
        let [
            names_mark,
            names_scatter,
            names_hash_prepare,
            names_hash_insert,
            names_hash_assign,
            language_names_clear,
            language_type_codes_clear,
            language_decls_materialize,
        ] = name_family_reflections();
        let [
            calls_mark_array_args,
            calls_validate_array_results,
            calls_project_result_instances,
        ] = call_array_reflections();
        let [
            methods_clear,
            methods_collect,
            methods_attach_metadata,
            methods_bind_self_receivers,
            methods_seed_key_order,
            methods_validate_keys,
            methods_mark_call_keys,
            methods_mark_call_return_keys,
            methods_resolve_table,
            methods_resolve,
        ] = method_reflections();
        let [semantic_features_collect, semantic_features_dispatch] =
            semantic_feature_reflections();
        let reflections = BuildGraphReflections {
            semantic_features_collect: &semantic_features_collect,
            semantic_features_dispatch: &semantic_features_dispatch,
            names_mark: &names_mark,
            names_scatter: &names_scatter,
            names_hash_prepare: &names_hash_prepare,
            names_hash_insert: &names_hash_insert,
            names_hash_assign: &names_hash_assign,
            language_names_clear: &language_names_clear,
            language_type_codes_clear: &language_type_codes_clear,
            language_decls_materialize: &language_decls_materialize,
            conditions_compact_calls: &calls,
            conditions_compact_types: &types,
            conditions_aggregate_args: &aggregate_args,
            calls_mark_array_args: &calls_mark_array_args,
            calls_validate_array_results: &calls_validate_array_results,
            calls_project_result_instances: &calls_project_result_instances,
            calls: empty_call_reflections(&call_initializer, &call_return_refs, &call_reflection),
            methods_clear: &methods_clear,
            methods_collect: &methods_collect,
            methods_attach_metadata: &methods_attach_metadata,
            methods_bind_self_receivers: &methods_bind_self_receivers,
            methods_seed_key_order: &methods_seed_key_order,
            methods_validate_keys: &methods_validate_keys,
            methods_mark_call_keys: &methods_mark_call_keys,
            methods_mark_call_return_keys: &methods_mark_call_return_keys,
            methods_resolve_table: &methods_resolve_table,
            methods_resolve: &methods_resolve,
            type_instances_struct_init_clear: &struct_init_clear,
            type_instances_struct_init_contexts: &struct_init_contexts,
            type_instances_struct_init_fields: &struct_init_fields,
            type_instances_struct_init_substitute: &struct_init_substitute,
            type_instances_validate_aggregate_access: &validate_aggregate_access,
            type_instances_member_receivers: &member_receivers,
            type_instances_member_results: &member_results,
            type_instances_member_substitute: &member_substitute,
            type_instances_clear_semantic_type_rows: &type_semantic_clear,
            type_instances_mark_semantic_type_rows: &type_semantic_mark,
            type_instances_scatter_semantic_type_rows: &type_semantic_scatter,
            semantic_array_index_refs: &semantic_array_index_refs,
            type_instances_decl_generic_params: &decl_generic_params,
            type_instances_sort_generic_params_small: &sort_generic_params_small,
            type_instances_generic_param_use_slots: &generic_param_use_slots,
            predicates: Some(empty_predicate_reflections(
                &predicate_reflection,
                &predicate_syntax_clear_reflection,
                &predicate_clear_reflection,
                &predicate_obligation_reflection,
            )),
        };
        let (graph, resources) =
            build_graph(1024, 1024, 4, 1024, 1024, 768, 768, 512, 11, &reflections).unwrap();
        assert!(
            graph
                .pass_id(TYPE_INSTANCES_GENERIC_PARAM_SORT_SMALL_PASS)
                .is_some(),
            "small generic tables use the cooperative in-workgroup sort",
        );
        assert!(
            graph
                .pass_id(
                    GENERIC_PARAMETER_RADIX_SORTS
                        .key
                        .passes
                        .order_to_temporary
                        .histogram
                )
                .is_none(),
            "small generic tables do not allocate or schedule scalable radix scratch",
        );
        assert!(resources.generic_param_slot_radix_block_histogram.is_none());
        assert!(resources.generic_param_key_order_tmp.is_none());
        assert!(resources.generic_param_slot_order_tmp.is_none());
        assert!(
            resources
                .generic_param_slot_radix_block_bucket_prefix
                .is_none()
        );
        assert!(resources.generic_param_slot_radix_bucket_total.is_none());
        assert!(resources.generic_param_slot_radix_bucket_base.is_none());
        let expression_region = graph
            .repeated_regions()
            .iter()
            .find(|region| region.first_pass == graph.pass_id(STEP_A_TO_B_PASS).unwrap())
            .expect("expression pointer-jump repeated region");
        assert_eq!(expression_region.iterations, 5);
        assert!(graph.pass_id(STEP_A_TO_B_TAIL_PASS).is_some());
    }
}
