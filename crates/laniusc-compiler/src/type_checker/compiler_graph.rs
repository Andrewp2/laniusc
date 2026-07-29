use super::*;
use crate::gpu::{
    compiler_graph::{
        AccessMode,
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
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Declarations,
        passes: radix_sort_graph_passes!("type_check.type_instances.generic_params.key"),
        kernels: RadixSortKernels::new(
            "type_checker/type/instances/00c_sort_generic_param_keys",
            "type_checker/type/instances/00d_sort_generic_param_keys_scatter",
        ),
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
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Declarations,
        passes: radix_sort_graph_passes!("type_check.type_instances.generic_params.slot"),
        kernels: RadixSortKernels::new(
            "type_checker/type/instances/00c2_sort_generic_param_slots",
            "type_checker/type/instances/00d2_sort_generic_param_slots_scatter",
        ),
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
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::Declarations,
        passes: hierarchical_radix_sort_graph_passes!(
            "type_check.type_instances.struct_fields.sort"
        ),
        kernels: HierarchicalRadixSortKernels {
            histogram: "type_checker/type/instances/02b_sort_struct_field_keys",
            bucket_local: "type_checker/type/instances/02b1_struct_field_bucket_local",
            bucket_chunks: "type_checker/type/instances/02b2_struct_field_bucket_chunks",
            bucket_apply: "type_checker/type/instances/02b3_struct_field_bucket_apply",
            scatter: "type_checker/type/instances/02c_sort_struct_field_keys_scatter",
        },
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
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::Declarations,
    passes: radix_sort_graph_passes!("type_check.methods.keys.sort"),
    kernels: RadixSortKernels::new(
        "type_checker/methods/04_sort_keys",
        "type_checker/methods/04b_sort_keys_scatter",
    )
    .with_small("type_checker/methods/03b_sort_key_order_small"),
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
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::Declarations,
    passes: radix_sort_graph_passes!("type_check.visible.sort_hir_decl_keys"),
    kernels: RadixSortKernels::new(
        "type_checker/visible/03e_sort_hir_decl_keys",
        "type_checker/visible/03f_sort_hir_decl_keys_scatter",
    )
    .with_small("type_checker/visible/03d2_sort_hir_decl_keys_small"),
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
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::CallArguments,
    passes: radix_sort_graph_passes!("type_check.calls.generic_claims.sort"),
    kernels: RadixSortKernels::new(
        "type_checker/calls/03a2_sort_generic_claims",
        "type_checker/calls/03a3_sort_generic_claims_scatter",
    ),
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
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::CallArguments,
    passes: radix_sort_graph_passes!("type_check.calls.const_claims.sort"),
    kernels: RadixSortKernels::new(
        "type_checker/calls/03a2_sort_generic_claims",
        "type_checker/calls/03a3_sort_generic_claims_scatter",
    ),
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
pub(super) const DEPENDENCY_CALL_COMPARE_CLEAR_PASS: &str =
    "type_check.dependencies.call_compare.clear";
pub(super) const DEPENDENCY_CALL_ARGS_VALIDATE_PASS: &str =
    "type_check.dependencies.call_args.validate";
pub(super) const DEPENDENCY_CALL_RESULTS_SUBSTITUTE_PASS: &str =
    "type_check.dependencies.call_results.substitute";
pub(super) const DEPENDENCY_CALL_RESULTS_VALIDATE_PASS: &str =
    "type_check.dependencies.call_results.validate";
pub(super) const DEPENDENCY_CALL_COMPARE_DISPATCH_PASS: &str =
    "type_check.dependencies.call_compare.dispatch";
pub(super) const DEPENDENCY_CALL_TYPE_ARGS_VALIDATE_PASS: &str =
    "type_check.dependencies.call_type_args.validate";

/// Graph-owned storage and ownership contract for type checking. Logical
/// resources are recovered from the graph by name; the workspace is their
/// sole physical owner.
pub(super) struct TypeCheckCompilerGraph {
    graph: CompilerGraph,
    workspace: CompilerGraphWorkspace,
    allocations: CompilerGraphAllocations,
    semantic_interface_scans: SemanticInterfaceScanGraph,
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
    pub(super) fn bindings(&self) -> Result<CompilerGraphBindings> {
        self.workspace
            .bindings(&self.graph)
            .map_err(anyhow::Error::msg)
    }

    pub(super) fn register_bindings<'a>(
        &self,
        bindings: &'a CompilerGraphBindings,
        resources: &mut ResourceMap<'a>,
    ) {
        resources.register_graph_bindings(&self.graph, bindings);
    }

    /// Returns a typed view of one graph-owned resource without duplicating
    /// ownership fields for every logical array.
    pub(super) fn buffer<T>(&self, name: &str) -> Result<LaniusBuffer<T>> {
        let resource = self
            .graph
            .resource_id(name)
            .ok_or_else(|| anyhow::anyhow!("type-check graph has no resource `{name}`"))?;
        let bytes = self
            .graph
            .resource(resource)
            .expect("graph resource id")
            .bytes;
        let element_bytes = std::mem::size_of::<T>() as u64;
        if element_bytes == 0 || bytes % element_bytes != 0 {
            return Err(anyhow::anyhow!(
                "type-check resource `{name}` has {bytes} bytes, incompatible with {}-byte elements",
                element_bytes,
            ));
        }
        self.workspace
            .alias(&self.graph, resource, (bytes / element_bytes) as usize)
            .map_err(anyhow::Error::msg)
    }

    pub(super) fn u32_buffer(&self, name: &str) -> Result<LaniusBuffer<u32>> {
        self.buffer(name)
    }

    pub(super) fn optional_buffer<T>(&self, name: &str) -> Result<Option<LaniusBuffer<T>>> {
        self.graph
            .resource_id(name)
            .map(|_| self.buffer(name))
            .transpose()
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
        let init_pass = &passes.kernel("type_checker/semantic/expression_types/00_init");
        let step_pass = &passes.kernel("type_checker/semantic/expression_types/01_step");
        let conditions_compact_expr_pass = &passes.kernel("type_checker/conditions/compact_expr");
        let conditions_compact_stmt_pass = &passes.kernel("type_checker/conditions/compact_stmt");
        let conditions_compact_aggregate_requests_pass =
            &passes.kernel("type_checker/conditions/compact_aggregate_requests");
        let conditions_compact_methods_pass =
            &passes.kernel("type_checker/conditions/compact_methods");
        let predicate_diagnostics_clear_pass =
            &passes.kernel("type_checker/semantic/artifact/00_predicate_diagnostics_clear");
        let predicate_diagnostics_claim_pass =
            &passes.kernel("type_checker/semantic/artifact/01_predicate_diagnostics_claim");
        let predicate_diagnostics_project_pass =
            &passes.kernel("type_checker/semantic/artifact/02_predicate_diagnostics");
        let conditions_compact_predicates_pass =
            &passes.kernel("type_checker/conditions/compact_predicates");
        let conditions_compact_names_pass = &passes.kernel("type_checker/conditions/compact_names");
        let calls_project_result_instances_pass =
            &passes.kernel("type_checker/calls/03e_project_result_instances");
        let visible_clear_pass = &passes.kernel("type_checker/visible/01/clear/resident");
        let visible_mark_pass = &passes.kernel("type_checker/visible/03b_mark_hir_decl_names");
        let visible_scatter_pass = &passes.kernel("type_checker/visible/03c_scatter_hir_decls");
        let visible_names_pass = &passes.kernel("type_checker/visible/04_hir_names");
        let scope_hir_pass = &passes.kernel("type_checker/scope/hir");
        let returns_clear_pass = &passes.kernel("type_checker/returns/00_clear");
        let returns_mark_pass = &passes.kernel("type_checker/returns/01_mark");
        let returns_mark_if_pass = &passes.kernel("type_checker/returns/02_mark_if");
        let returns_validate_pass = &passes.kernel("type_checker/returns/03_validate");
        let calls_backend_targets_pass = &passes.kernel("type_checker/calls/04_backend_targets");
        let semantic_calls_project_pass = &passes.kernel("type_checker/semantic/artifact/00_calls");
        let semantic_expression_refs_project_pass =
            &passes.kernel("type_checker/semantic/artifact/01_expression_refs");
        let semantic_struct_literal_refs_project_pass =
            &passes.kernel("type_checker/semantic/artifact/01a_struct_literal_refs");
        let semantic_artifact_project_pass =
            &passes.kernel("type_checker/semantic/artifact/00_project");
        let step_count = pointer_jump_step_count(hir_capacity);
        let graph = build_graph(
            hir_capacity,
            token_capacity,
            source_file_capacity,
            module_record_capacity,
            call_param_capacity,
            call_arg_capacity,
            generic_claim_capacity,
            predicate_capacity,
            step_count,
            passes,
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
                &passes
                    .kernel("type_checker/type/instances/00a_mark_generic_param_records")
                    .reflection,
            ),
            (
                TYPE_INSTANCES_PROPAGATE_GENERIC_OWNER_A_TO_B_PASS,
                &passes
                    .kernel("type_checker/type/instances/00a1_propagate_generic_decl_owner")
                    .reflection,
            ),
            (
                TYPE_INSTANCES_PROPAGATE_GENERIC_OWNER_B_TO_A_PASS,
                &passes
                    .kernel("type_checker/type/instances/00a1_propagate_generic_decl_owner")
                    .reflection,
            ),
            (
                TYPE_INSTANCES_GENERIC_PARAM_SORT_DISPATCH_PASS,
                &passes
                    .kernel("type_checker/names/radix/dispatch_args")
                    .reflection,
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
                &passes
                    .kernel("type_checker/type/instances/00c_sort_generic_param_keys")
                    .reflection,
                &passes
                    .kernel("type_checker/type/instances/00d_sort_generic_param_keys_scatter")
                    .reflection,
            ),
            (
                GENERIC_PARAMETER_RADIX_SORTS.slot,
                &passes
                    .kernel("type_checker/type/instances/00c2_sort_generic_param_slots")
                    .reflection,
                &passes
                    .kernel("type_checker/type/instances/00d2_sort_generic_param_slots_scatter")
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
                    &passes
                        .kernel("type_checker/names/radix/00b/bucket/prefix")
                        .reflection,
                )?;
                validate(
                    step.bucket_bases,
                    &passes
                        .kernel("type_checker/names/radix/00c/bucket/bases")
                        .reflection,
                )?;
                validate(step.scatter, scatter)?;
            }
        }

        let workspace = CompilerGraphWorkspace::new(device, "type_check", &graph)
            .map_err(anyhow::Error::msg)?;
        let allocations = workspace.allocations();
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
) -> Result<(), String> {
    let resource = |name| {
        graph
            .resource_id(name)
            .ok_or_else(|| format!("type-subtree operation requires graph resource `{name}`"))
    };
    let count_out = resource("type_subtree_compare_count_out")?;
    let dispatch_args = resource("type_subtree_compare_dispatch_args")?;
    let prefix = resource("type_subtree_compare_prefix")?;
    let left_root = resource("type_subtree_compare_left_root")?;
    let right_root = resource("type_subtree_compare_right_root")?;
    let error_token = resource("type_subtree_compare_error_token")?;
    let error_detail = resource("type_subtree_compare_error_detail")?;
    let status = resource("status")?;
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
            PassAccess::read("type_subtree_compare_count_out", count_out),
            PassAccess::write("type_subtree_compare_dispatch_args", dispatch_args),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: indirect_name,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("type_subtree_compare_prefix", prefix),
            PassAccess::read("type_subtree_compare_left_root", left_root),
            PassAccess::read("type_subtree_compare_right_root", right_root),
            PassAccess::read("type_subtree_compare_error_token", error_token),
            PassAccess::read("type_subtree_compare_error_detail", error_detail),
            PassAccess::read("type_subtree_compare_dispatch_args", dispatch_args),
            PassAccess::read_write("status", status),
        ],
    })?;
    Ok(())
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
    kernels: &impl crate::gpu::kernels::KernelReflections,
) -> Result<CompilerGraph, String> {
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
    method_workspace("method_decl_method_row")?;
    method_workspace("method_decl_receiver_ref_tag")?;
    method_workspace("method_decl_receiver_ref_payload")?;
    method_workspace("method_decl_module_id")?;
    method_workspace("method_decl_name_token")?;
    method_workspace("method_decl_name_id")?;
    let method_decl_param_offset = method_workspace("method_decl_param_offset")?;
    let method_decl_receiver_mode = method_workspace("method_decl_receiver_mode")?;
    method_workspace("method_decl_visibility")?;
    method_workspace("method_decl_signature_flags")?;
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
    struct_field_sort_resources.temporary_order;
    let struct_field_key_radix_dispatch_args = struct_field_sort_resources.dispatch_args;
    struct_field_sort_resources.histogram;
    struct_field_sort_resources.bucket_prefix;
    struct_field_sort_resources.bucket_total;
    struct_field_sort_resources.bucket_base;
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
    drop(name_workspace);
    // These four arrays form the retained name artifact consumed by module
    // resolution and semantic-interface export after the graph's last name
    // pass.  Marking them as ordinary scratch allowed later type-check arrays
    // to overwrite live names in the same colored workspace slot.
    let name_scan_total = graph.add_storage(
        "name_scan_total",
        ResourceDomain::Declarations,
        ResourceClass::Output,
        4,
    )?;
    let name_spans = graph.add_storage(
        "name_spans",
        ResourceDomain::Declarations,
        ResourceClass::Output,
        name_rows * 16,
    )?;
    let name_hash_lo = graph.add_storage(
        "name_hash_lo",
        ResourceDomain::Declarations,
        ResourceClass::Output,
        name_rows * 4,
    )?;
    let name_hash_hi = graph.add_storage(
        "name_hash_hi",
        ResourceDomain::Declarations,
        ResourceClass::Output,
        name_rows * 4,
    )?;
    let mut name_workspace =
        |name, domain, bytes| graph.add_storage(name, domain, ResourceClass::Workspace, bytes);
    let name_max_len = name_workspace("name_max_len", ResourceDomain::Declarations, 4)?;
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
        ($name:expr, $bytes:expr) => {
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
    graph.add_storage(
        "method_call_receiver_ref_tag",
        ResourceDomain::Calls,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    graph.add_storage(
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
    graph.add_storage(
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
    graph.add_storage(
        "type_instance_arg_row_scan_local_prefix",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows * 4,
    )?;
    graph.add_storage(
        "type_instance_arg_row_scan_block_sum",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows.div_ceil(256) * 4,
    )?;
    graph.add_storage(
        "type_instance_arg_row_scan_prefix_a",
        ResourceDomain::Types,
        ResourceClass::Workspace,
        token_rows.div_ceil(256) * 4,
    )?;
    graph.add_storage(
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
    graph.add_storage(
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
    graph.add_storage(
        "method_key_radix_block_histogram",
        ResourceDomain::Declarations,
        ResourceClass::Workspace,
        method_key_radix_rows * 4,
    )?;
    graph.add_storage(
        "method_key_radix_block_bucket_prefix",
        ResourceDomain::Declarations,
        ResourceClass::Workspace,
        method_key_radix_rows * 4,
    )?;
    graph.add_storage(
        "method_key_radix_bucket_total",
        ResourceDomain::Declarations,
        ResourceClass::Workspace,
        u64::from(NAME_RADIX_BUCKETS) * 4,
    )?;
    graph.add_storage(
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
    for (alias, resource) in [
        ("generic_decl_owner_by_node_a", generic_decl_owner_by_node_a),
        (
            "predicate_bound_list_by_node_a",
            predicate_bound_list_by_node_a,
        ),
        (
            "predicate_bound_list_by_node_b",
            predicate_bound_list_by_node_b,
        ),
    ] {
        graph.add_resource_alias(alias, resource)?;
    }
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
        ($name:expr, $bytes:expr) => {
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
    if token_capacity.max(1) > GENERIC_PARAM_SMALL_SORT_CAPACITY {
        generic_param_workspace!("generic_param_key_order_tmp", token_rows * 4);
    }
    let generic_param_slot_order =
        generic_param_workspace!("generic_param_slot_order", token_rows * 4);
    if token_capacity.max(1) > GENERIC_PARAM_SMALL_SORT_CAPACITY {
        generic_param_workspace!("generic_param_slot_order_tmp", token_rows * 4);
    }
    let generic_param_radix_rows = token_rows.div_ceil(256) * u64::from(NAME_RADIX_BUCKETS);
    if token_capacity.max(1) > GENERIC_PARAM_SMALL_SORT_CAPACITY {
        for name in [
            "generic_param_slot_radix_block_histogram",
            "generic_param_slot_radix_block_bucket_prefix",
        ] {
            generic_param_workspace!(name, generic_param_radix_rows * 4);
        }
        for name in [
            "generic_param_slot_radix_bucket_total",
            "generic_param_slot_radix_bucket_base",
        ] {
            generic_param_workspace!(name, u64::from(NAME_RADIX_BUCKETS) * 4);
        }
    }
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
    predicate_workspace_resource!("predicate_obligation_prefix_by_call", predicate_rows * 4);
    predicate_workspace_resource!("predicate_obligation_scan_local_prefix", predicate_rows * 4);
    graph.add_storage(
        "predicate_obligation_scan_block_sum",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        predicate_rows.div_ceil(256) * 4,
    )?;
    graph.add_storage(
        "predicate_obligation_scan_prefix_a",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        predicate_rows.div_ceil(256) * 4,
    )?;
    graph.add_storage(
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
        ("dependency_counts", ResourceDomain::Declarations, 20),
        (
            "dependency_declaration_words",
            ResourceDomain::Declarations,
            4,
        ),
        ("dependency_type_words", ResourceDomain::Declarations, 4),
        (
            "dependency_type_edge_words",
            ResourceDomain::Declarations,
            4,
        ),
        ("canonical_type_roots", ResourceDomain::Declarations, 4),
        (
            "canonical_type_subtree_start",
            ResourceDomain::Declarations,
            4,
        ),
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
        (
            "dependency_call_compare_expected_type",
            ResourceDomain::HirNodes,
            hir_rows * 4,
        ),
        (
            "dependency_call_compare_actual_instance",
            ResourceDomain::HirNodes,
            hir_rows * 4,
        ),
        (
            "dependency_call_compare_error_token",
            ResourceDomain::HirNodes,
            hir_rows * 4,
        ),
    ] {
        external(name, domain, bytes)?;
    }
    let hir_value_decl_name_present = external(
        "hir_value_decl_name_present",
        ResourceDomain::Declarations,
        (token_rows + u64::from(LANGUAGE_SYMBOL_COUNT)) * 4,
    )?;
    drop(external);
    let dependency_call_compare_dispatch_args = graph.add_indirect_storage(
        "dependency_call_compare_dispatch_args",
        ResourceDomain::DispatchArguments,
        ResourceClass::External,
        12,
    )?;
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
    // Both the fused small sort and the scalable radix path publish their row
    // count through this operation-owned indirect dispatch buffer.
    graph.add_resource_alias(
        "generic_param_key_radix_dispatch_args",
        hir_visible_decl_key_radix_dispatch_args,
    )?;
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
    graph.add_storage(
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
    graph.add_storage(
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
    required_workspace(
        "call_arg_row_scan_local_prefix",
        ResourceDomain::HirNodes,
        hir_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_param_row_scan_local_prefix",
        ResourceDomain::Tokens,
        token_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_param_row_scan_block_sum",
        ResourceDomain::Tokens,
        token_rows.div_ceil(256) * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_param_row_scan_prefix_a",
        ResourceDomain::Tokens,
        token_rows.div_ceil(256) * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_param_row_scan_prefix_b",
        ResourceDomain::Tokens,
        token_rows.div_ceil(256) * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_arg_row_scan_input",
        ResourceDomain::HirNodes,
        hir_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_arg_row_prefix",
        ResourceDomain::HirNodes,
        hir_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_arg_row_scan_block_sum",
        ResourceDomain::HirNodes,
        hir_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_arg_row_scan_prefix_a",
        ResourceDomain::HirNodes,
        hir_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_arg_row_scan_prefix_b",
        ResourceDomain::HirNodes,
        hir_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_generic_claim_scan_local_prefix",
        ResourceDomain::CallArguments,
        call_arg_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_generic_claim_scan_input",
        ResourceDomain::CallArguments,
        call_arg_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_generic_claim_prefix",
        ResourceDomain::CallArguments,
        call_arg_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_generic_claim_scan_block_sum",
        ResourceDomain::CallArguments,
        call_arg_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_generic_claim_scan_prefix_a",
        ResourceDomain::CallArguments,
        call_arg_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_generic_claim_scan_prefix_b",
        ResourceDomain::CallArguments,
        call_arg_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_required_generic_scan_input",
        ResourceDomain::HirNodes,
        hir_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_required_generic_prefix",
        ResourceDomain::HirNodes,
        hir_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_required_generic_scan_local_prefix",
        ResourceDomain::HirNodes,
        hir_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_required_generic_scan_block_sum",
        ResourceDomain::HirNodes,
        hir_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_required_generic_scan_prefix_a",
        ResourceDomain::HirNodes,
        hir_blocks * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
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
    required_workspace(
        "call_generic_claim_callee",
        ResourceDomain::CallArguments,
        claim_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_generic_claim_slot",
        ResourceDomain::CallArguments,
        claim_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_generic_claim_type",
        ResourceDomain::CallArguments,
        claim_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_generic_claim_ref_tag",
        ResourceDomain::CallArguments,
        claim_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_generic_claim_ref_payload",
        ResourceDomain::CallArguments,
        claim_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_generic_claim_arg_row",
        ResourceDomain::CallArguments,
        claim_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_generic_claim_order",
        ResourceDomain::CallArguments,
        claim_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
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
    required_workspace(
        "call_generic_claim_radix_block_histogram",
        ResourceDomain::CallArguments,
        claim_histogram_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_generic_claim_radix_block_bucket_prefix",
        ResourceDomain::CallArguments,
        claim_histogram_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_generic_claim_radix_bucket_total",
        ResourceDomain::CallArguments,
        u64::from(NAME_RADIX_BUCKETS) * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_generic_claim_radix_bucket_base",
        ResourceDomain::CallArguments,
        u64::from(NAME_RADIX_BUCKETS) * 4,
        WorkspaceUsageClass::Storage,
    )?;
    // Both claim sorts execute sequentially through the same radix operation.
    // Scratch belongs to that operation, not to the semantic key family.
    required_workspace(
        "call_const_claim_callee",
        ResourceDomain::CallArguments,
        call_arg_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_const_claim_slot",
        ResourceDomain::CallArguments,
        call_arg_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_const_claim_len",
        ResourceDomain::CallArguments,
        call_arg_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
        "call_const_claim_order",
        ResourceDomain::CallArguments,
        call_arg_rows * 4,
        WorkspaceUsageClass::Storage,
    )?;
    required_workspace(
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
    graph.add_resource(comparison_resident_u32("aggregate_compare_prefix"))?;
    let aggregate_compare_count_out = graph.add_storage(
        "aggregate_compare_count_out",
        ResourceDomain::HirNodes,
        ResourceClass::Resident,
        4,
    )?;
    let aggregate_blocks = hir_rows.div_ceil(256);
    graph.add_resource(comparison_resident_u32(
        "aggregate_compare_scan_local_prefix",
    ))?;
    graph.add_storage(
        "aggregate_compare_scan_block_sum",
        ResourceDomain::HirNodes,
        ResourceClass::Resident,
        aggregate_blocks * 4,
    )?;
    graph.add_storage(
        "aggregate_compare_scan_prefix_a",
        ResourceDomain::HirNodes,
        ResourceClass::Resident,
        aggregate_blocks * 4,
    )?;
    graph.add_storage(
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
    graph.add_resource(hir_workspace_u32("type_semantic_prefix"))?;
    graph.add_storage(
        "type_semantic_count_out",
        ResourceDomain::HirNodes,
        ResourceClass::Workspace,
        4,
    )?;
    let type_semantic_row_by_ordinal =
        graph.add_resource(hir_workspace_u32("type_semantic_row_by_ordinal"))?;
    let type_subtree_compare_scan_input =
        graph.add_resource(comparison_resident_u32("type_subtree_compare_scan_input"))?;
    graph.add_resource(comparison_resident_u32("type_subtree_compare_prefix"))?;
    graph.add_storage(
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
    graph.add_indirect_storage(
        "type_subtree_compare_dispatch_args",
        ResourceDomain::HirNodes,
        ResourceClass::Resident,
        12,
    )?;
    graph.add_kernel_pass_by_name(
        LANGUAGE_NAMES_CLEAR_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        "type_checker/language/names/00_clear",
        &[ReflectedResourceBinding {
            binding: "name_max_len",
            resource: name_max_len,
            mode: Some(AccessMode::Write),
        }],
    )?;
    graph.add_kernel_pass_by_name(
        NAMES_MARK_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        "type_checker/names/00_mark_lexemes",
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
    graph.add_kernel_pass_by_name(
        NAMES_SCATTER_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        "type_checker/names/01_scatter_lexemes",
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
    graph.add_kernel_pass_by_name(
        NAMES_HASH_PREPARE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        "type_checker/names/hash/00_prepare",
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
    graph.add_kernel_pass_by_name(
        NAMES_HASH_INSERT_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        "type_checker/names/hash/01_insert",
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
    graph.add_kernel_pass_by_name(
        NAMES_HASH_ASSIGN_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        "type_checker/names/hash/02_assign_ids",
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
    graph.add_kernel_pass_by_name(
        LANGUAGE_TYPE_CODES_CLEAR_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        "type_checker/language/decls/00a_clear_type_codes",
        &[],
    )?;
    graph.add_kernel_pass_by_name(
        LANGUAGE_DECLS_MATERIALIZE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        "type_checker/language/decls/00_materialize",
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
    {
        graph.add_kernel_pass_by_name(
            PREDICATES_CLEAR_SYNTAX_TOKENS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::Tokens,
            kernels,
            "type_checker/predicates/00a_clear_syntax_tokens",
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
    graph.add_kernel_pass_by_name(
        TYPE_INSTANCES_DECL_GENERIC_PARAMS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        "type_checker/type/instances/00b_decl_generic_params",
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
        graph.add_kernel_pass_by_name(
            TYPE_INSTANCES_GENERIC_PARAM_SORT_SMALL_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::Declarations,
            kernels,
            "type_checker/type/instances/00b2_sort_generic_params_small",
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
    graph.add_kernel_pass_by_name(
        TYPE_INSTANCES_GENERIC_PARAM_USE_SLOTS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/type/instances/00e_generic_param_use_slots",
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
    graph.add_kernel_pass_by_name(
        FEATURES_COLLECT_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/semantic/features/00_collect",
        &[],
    )?;
    graph.add_kernel_initializer_by_name(
        FEATURES_DISPATCH_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::DispatchArguments,
        kernels,
        "type_checker/semantic/features/01_dispatch_args",
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
            graph.add_kernel_pass_by_name(
                TYPE_INSTANCES_STRUCT_INIT_SUBSTITUTE_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::Tokens,
                kernels,
                "type_checker/type/instances/04b_struct_init_substitute",
                &[],
            )?;
            graph.add_kernel_pass_by_name(
                TYPE_INSTANCES_MEMBER_RECEIVERS_AFTER_ARRAY_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                kernels,
                "type_checker/type/instances/03a_member_receivers",
                &member_receiver_overrides,
            )?;
            graph.add_kernel_pass_by_name(
                TYPE_INSTANCES_MEMBER_RESULTS_AFTER_ARRAY_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                kernels,
                "type_checker/type/instances/03_member_results",
                &[],
            )?;
            graph.add_kernel_pass_by_name(
                TYPE_INSTANCES_MEMBER_SUBSTITUTE_AFTER_ARRAY_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::Tokens,
                kernels,
                "type_checker/type/instances/03b_member_substitute",
                &[],
            )?;
            graph.add_kernel_pass_by_name(
                TYPE_INSTANCES_VALIDATE_AGGREGATE_ACCESS_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                kernels,
                "type_checker/type/instances/08_validate_aggregate_access",
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
            graph.add_kernel_pass_by_name(
                SEMANTIC_ARRAY_INDEX_REFS_PROJECT_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                kernels,
                "type_checker/semantic/artifact/01b_array_index_refs",
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
                    PassAccess::read("call_dependency_decl", call_dependency_decl),
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
                    PassAccess::read("call_dependency_decl", call_dependency_decl),
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
            graph.add_kernel_pass_by_name(
                CONDITIONS_AGGREGATE_ARGS_FINAL_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::CallArguments,
                kernels,
                "type_checker/conditions/aggregate_args",
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
            graph.add_kernel_pass_by_name(
                CONDITIONS_COMPACT_CALLS_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                kernels,
                "type_checker/conditions/compact_calls",
                &[ReflectedResourceBinding {
                    binding: "call_fn_index",
                    resource: backend_call_fn_index,
                    mode: None,
                }],
            )?;
            graph.add_kernel_pass_by_name(
                CONDITIONS_COMPACT_TYPES_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                kernels,
                "type_checker/conditions/compact_types",
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
    graph.add_kernel_pass_by_name(
        TYPE_SEMANTIC_CLEAR_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        "type_checker/type/instances/01h_clear_semantic_type_rows",
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
    graph.add_kernel_pass_by_name(
        TYPE_SEMANTIC_MARK_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/type/instances/01i_mark_semantic_type_rows",
        &[],
    )?;
    TYPE_SEMANTIC_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(hir_blocks))?;
    graph.add_kernel_pass_by_name(
        TYPE_SEMANTIC_SCATTER_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/type/instances/01j_scatter_semantic_type_rows",
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
    CALLS_CLEAR.register_kernel(&mut graph, kernels)?;
    CALLS_ENTRYPOINT_CLEAR.register_kernel(&mut graph, kernels)?;
    CALLS_RETURN_REFS.register_kernel(&mut graph, kernels)?;
    CALLS_ENTRYPOINT_PROJECT.register_kernel(&mut graph, kernels)?;
    CALLS_FUNCTIONS.register_kernel(&mut graph, kernels)?;
    CALLS_PARAM_TYPES.register_kernel(&mut graph, kernels)?;
    METHODS_CLEAR.register_kernel(&mut graph, kernels)?;
    METHODS_COLLECT.register_kernel(&mut graph, kernels)?;
    METHODS_ATTACH_METADATA.register_kernel(&mut graph, kernels)?;
    METHODS_BIND_SELF_RECEIVERS.register_kernel(&mut graph, kernels)?;
    graph.add_kernel_pass_by_name(
        TYPE_INSTANCES_MEMBER_RECEIVERS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/type/instances/03a_member_receivers",
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
    graph.add_kernel_pass_by_name(
        TYPE_INSTANCES_MEMBER_RESULTS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/type/instances/03_member_results",
        &[],
    )?;
    graph.add_kernel_pass_by_name(
        TYPE_INSTANCES_MEMBER_SUBSTITUTE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        "type_checker/type/instances/03b_member_substitute",
        &[],
    )?;
    graph.add_kernel_pass_by_name(
        TYPE_INSTANCES_STRUCT_INIT_CLEAR_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        "type_checker/type/instances/04a_struct_init_clear",
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
    graph.add_kernel_pass_by_name(
        TYPE_INSTANCES_STRUCT_INIT_CONTEXTS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/type/instances/04a2_struct_init_contexts",
        &[],
    )?;
    graph.add_kernel_pass_by_name(
        TYPE_INSTANCES_STRUCT_INIT_FIELDS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::RawNodes,
        kernels,
        "type_checker/type/instances/04_struct_init_fields",
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
    CALLS_PARAM_SCATTER.register_kernel(&mut graph, kernels)?;
    CALLS_INTRINSICS.register_kernel(&mut graph, kernels)?;
    CALLS_ARGUMENT_CLEAR.register_kernel(&mut graph, kernels)?;
    CALLS_ARGUMENT_PACK.register_kernel(&mut graph, kernels)?;
    CALLS_ARGUMENT_MARK.register_kernel(&mut graph, kernels)?;
    CALL_ARG_ROW_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(hir_blocks))?;
    CALLS_ARGUMENT_SCATTER.register_kernel(&mut graph, kernels)?;
    CALLS_RESOLVE.register_kernel(&mut graph, kernels)?;
    CALLS_ARGUMENT_MATCH_INITIALIZE.register_kernel(&mut graph, kernels)?;
    CALLS_ARGUMENT_MATCH_CONSUME.register_kernel(&mut graph, kernels)?;
    CALLS_APPLY_ARGUMENTS.register_kernel(&mut graph, kernels)?;
    CALLS_RESULT_INSTANCE_PROJECT.register_kernel(&mut graph, kernels)?;
    CALLS_ARRAY_STATE_PUBLISH.register_kernel(&mut graph, kernels)?;
    GENERIC_CLAIM_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(call_arg_blocks))?;
    CALLS_GENERIC_CLAIM_EMIT.register_kernel(&mut graph, kernels)?;
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
    CALLS_GENERIC_CLAIM_CLEAR.register_kernel(&mut graph, kernels)?;
    CALLS_GENERIC_CLAIM_VALIDATE.register_kernel(&mut graph, kernels)?;
    CALLS_REQUIRED_GENERIC_MARK.register_kernel(&mut graph, kernels)?;
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
    CALLS_REQUIRED_GENERIC_VALIDATE.register_kernel(&mut graph, kernels)?;
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
    CALLS_CONST_CLAIM_VALIDATE.register_kernel(&mut graph, kernels)?;
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
    graph.add_kernel_pass_by_name(
        CONDITIONS_AGGREGATE_ARGS_CALLS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::CallArguments,
        kernels,
        "type_checker/conditions/aggregate_args",
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
    CALLS_ARRAY_STATE_CONSUME.register_kernel(&mut graph, kernels)?;
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
    METHODS_MARK_CALL_KEYS.register_kernel(&mut graph, kernels)?;
    graph.add_kernel_pass_by_name(
        METHOD_KEY_SEED_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        "type_checker/methods/03/seed_key_order",
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
    graph.add_kernel_pass_by_name(
        METHOD_KEY_VALIDATION_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        "type_checker/methods/05_validate_keys",
        &[ReflectedResourceBinding {
            binding: "sorted_method_key_order",
            resource: method_key_to_fn_token,
            mode: Some(AccessMode::Read),
        }],
    )?;
    METHODS_MARK_CALL_RETURN_KEYS.register_kernel(&mut graph, kernels)?;
    METHODS_RESOLVE_TABLE.register_kernel(&mut graph, kernels)?;
    METHODS_RESOLVE.register_kernel(&mut graph, kernels)?;
    {
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
        graph.add_kernel_pass_by_name(
            PREDICATES_CLEAR_BOUND_ARG_FACTS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/predicates/00_clear_bound_arg_facts",
            &predicate_clear_overrides,
        )?;
        graph.add_kernel_pass_by_name(
            PREDICATES_COLLECT_BOUND_ARG_FACTS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/predicates/00b_collect_bound_arg_facts",
            &[],
        )?;
        graph.add_kernel_pass_by_name(
            PREDICATES_COLLECT_METHOD_CONTRACTS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/predicates/00c_collect_method_contracts",
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
        graph.add_kernel_pass_by_name(
            PREDICATES_BUILD_METHOD_OWNER_RANGES_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/predicates/01e_build_method_owner_ranges",
            &[],
        )?;
        graph.add_kernel_pass_by_name(
            PREDICATES_COLLECT_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/predicates/01_collect",
            &[],
        )?;
        graph.add_kernel_pass_by_name(
            PREDICATES_VALIDATE_BOUND_ARGS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/predicates/01a_validate_bound_args",
            &[],
        )?;
        graph.add_kernel_pass_by_name(
            PREDICATES_COLLECT_IMPLS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/predicates/01_collect_impls",
            &[],
        )?;
        graph.add_kernel_pass_by_name(
            PREDICATES_EMIT_METHOD_VALIDATION_ROWS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/predicates/01f_emit_method_validation_rows",
            &[],
        )?;
        graph.add_kernel_pass_by_name(
            PREDICATES_EMIT_METHOD_PARAM_VALIDATION_ROWS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/predicates/01f1_emit_method_param_validation_rows",
            &[],
        )?;
        graph.add_kernel_pass_by_name(
            PREDICATES_VALIDATE_METHOD_TYPE_ARG_ROWS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/predicates/01f2_validate_method_type_arg_rows",
            &[],
        )?;
        graph.add_kernel_pass_by_name(
            PREDICATES_REDUCE_METHOD_VALIDATION_ERRORS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/predicates/01g_reduce_method_validation_errors",
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
        graph.add_kernel_pass_by_name(
            PREDICATES_COUNT_OBLIGATION_PAIRS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/predicates/02a_count_obligations",
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
        graph.add_kernel_pass_by_name(
            PREDICATES_VALIDATE_OBLIGATION_PAIRS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/predicates/02b_validate_obligations",
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
    let dependency_call_compare_scan_input = graph
        .resource_id("dependency_call_compare_scan_input")
        .ok_or("dependency call comparison requires its scan input")?;
    graph.add_pass(PassDesc {
        name: DEPENDENCY_CALL_COMPARE_CLEAR_PASS,
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![PassAccess::write(
            "dependency_call_compare_scan_input",
            dependency_call_compare_scan_input,
        )],
    })?;
    graph.add_kernel_pass_by_name(
        DEPENDENCY_CALL_ARGS_VALIDATE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/dependencies/08_validate_call_args",
        &[],
    )?;
    graph.add_kernel_pass_by_name(
        DEPENDENCY_CALL_RESULTS_SUBSTITUTE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/dependencies/08a_validate_call_results",
        &[],
    )?;
    graph.add_kernel_pass_by_name(
        DEPENDENCY_CALL_RESULTS_VALIDATE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/dependencies/08a_validate_call_results",
        &[],
    )?;
    DEPENDENCY_CALL_COMPARE_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(hir_blocks))?;
    let dependency_call_compare_total = graph
        .resource_id("dependency_call_compare_total")
        .ok_or("dependency call comparison requires its total")?;
    graph.add_kernel_pass_by_name(
        DEPENDENCY_CALL_COMPARE_DISPATCH_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::DispatchArguments,
        kernels,
        "type_checker/count/dispatch_args",
        &[
            ReflectedResourceBinding {
                binding: "count_in",
                resource: dependency_call_compare_total,
                mode: None,
            },
            ReflectedResourceBinding {
                binding: "dispatch_args",
                resource: dependency_call_compare_dispatch_args,
                mode: Some(AccessMode::Write),
            },
        ],
    )?;
    graph.add_kernel_pass_by_name(
        DEPENDENCY_CALL_TYPE_ARGS_VALIDATE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/dependencies/08b_validate_call_type_args",
        &[],
    )?;
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
    graph.retain_outputs(&[
        // Exact-name identity exported to dependency interfaces.
        "name_scan_total",
        "name_spans",
        "name_hash_lo",
        "name_hash_hi",
        // Canonical type metadata consumed by interface export and lowering.
        "type_expr_ref_tag",
        "type_expr_ref_payload",
        "type_generic_param_slot_by_token",
        "type_const_param_slot_by_token",
        "generic_param_count_out",
        "generic_param_owner_token",
        "generic_param_name_id",
        "generic_param_token",
        "generic_param_kind",
        "type_decl_generic_param_count_by_owner_token",
        "type_decl_const_param_count_by_owner_token",
        "type_instance_kind",
        "type_instance_arg_start",
        "type_instance_arg_count",
        "type_instance_arg_ref_tag",
        "type_instance_arg_ref_payload",
        "type_instance_state",
        "type_instance_elem_ref_tag",
        "member_result_ref_tag",
        "member_result_ref_payload",
        "fn_return_ref_tag",
        "fn_return_ref_payload",
        "struct_init_field_expected_ref_tag",
        "struct_init_field_expected_ref_payload",
    ])?;
    graph.build()
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

    #[test]
    fn typecheck_graph_colors_only_complete_workspace_intervals() {
        let kernels = crate::gpu::kernels::KernelCatalog::load_prefix("type_checker").unwrap();
        let graph = build_graph(1024, 4096, 4, 4096, 1024, 768, 768, 512, 10, &kernels).unwrap();
        let resource = |name| {
            graph
                .resource_id(name)
                .unwrap_or_else(|| panic!("missing graph resource `{name}`"))
        };
        for name in [
            "name_scan_total",
            "name_spans",
            "type_expr_ref_tag",
            "generic_param_owner_token",
            "type_instance_arg_ref_tag",
            "fn_return_ref_tag",
        ] {
            assert_eq!(
                graph.resource(resource(name)).unwrap().class,
                ResourceClass::Output,
                "retained type-check artifact `{name}` must outlive workspace coloring",
            );
        }
        assert_eq!(
            graph.pass_kernel(graph.pass_id(NAMES_SCAN.passes.local).unwrap()),
            Some("scan/counted/00_local"),
        );
        assert_eq!(
            graph.pass_kernel(
                graph
                    .pass_id(VISIBLE_RADIX_SORT.passes.order_to_temporary.histogram)
                    .unwrap(),
            ),
            Some("type_checker/visible/03e_sort_hir_decl_keys"),
        );
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
                .lifetime(resource("member_result_ref_tag"))
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
        assert_ne!(
            slot(resource("compact_expr_scalar_type.a")),
            slot(resource("compact_expr_scalar_type.b")),
        );
        let name_workspace = [
            graph.resource_id("name_lexeme_flag").unwrap(),
            graph.resource_id("name_lexeme_kind").unwrap(),
            graph.resource_id("name_lexeme_prefix").unwrap(),
            graph.resource_id("name_scan_local_prefix").unwrap(),
            graph.resource_id("name_scan_block_sum").unwrap(),
            graph.resource_id("name_scan_prefix_a").unwrap(),
            graph.resource_id("name_scan_prefix_b").unwrap(),
            graph.resource_id("name_max_len").unwrap(),
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
        let graph_output_boundary = graph
            .pass_id(graph.passes().last().expect("type-check graph pass").name)
            .unwrap();
        for resource in [
            graph.resource_id("name_spans").unwrap(),
            graph.resource_id("name_hash_lo").unwrap(),
            graph.resource_id("name_hash_hi").unwrap(),
        ] {
            assert_eq!(
                graph.lifetime(resource).unwrap().last_pass,
                graph_output_boundary,
                "semantic-interface export retains this compact source-name row beyond module indexing at pass {}",
                module_borrow_fence.index(),
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
            slot(resource("type_instance_arg_ref_tag")),
            "declaration type flags use the future type-instance tag column while scanning",
        );
        assert_ne!(
            slot(resource("module_record_scan_local_prefix")),
            slot(resource("type_instance_arg_ref_payload")),
            "declaration value flags use the future type-instance payload column while scanning",
        );
        let type_reference_resources = [
            resource("type_expr_ref_tag"),
            resource("type_expr_ref_payload"),
            resource("type_generic_param_slot_by_token"),
            resource("type_const_param_slot_by_token"),
            resource("type_decl_hir_node_by_token"),
        ];
        for resource in type_reference_resources {
            assert!(
                matches!(
                    graph.resource(resource).unwrap().class,
                    ResourceClass::Workspace | ResourceClass::Output
                ),
                "type-reference and generic-slot relations must be graph-owned workspace or retained outputs",
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
            resource("predicate_owner_node"),
            resource("predicate_subject_token"),
            resource("predicate_bound_token"),
            resource("predicate_bound_decl_id"),
            resource("predicate_bound_arg_count"),
            resource("predicate_bound_first_arg_token"),
            resource("predicate_bound_second_arg_token"),
            resource("predicate_status"),
            resource("predicate_method_contract_owner_hir"),
            resource("predicate_method_contract_name_token"),
            resource("predicate_method_contract_name_id"),
            resource("predicate_method_contract_param_count"),
            resource("predicate_method_contract_return_type_node"),
            resource("predicate_method_contract_visibility"),
            resource("predicate_method_contract_status"),
            resource("predicate_method_contract_param_type_node"),
            resource("predicate_method_contract_owner_range_first"),
            resource("predicate_method_contract_owner_range_count"),
            resource("predicate_method_validation_owner_node"),
            resource("predicate_method_validation_peer_node"),
            resource("predicate_method_validation_status"),
            resource("predicate_method_validation_detail_token"),
            resource("predicate_method_validation_first_error_row"),
        ];
        assert_eq!(
            graph
                .resource(resource("predicate_syntax_token"))
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
            resource("generic_decl_owner_by_node_a"),
            resource("generic_decl_owner_by_node_b"),
            resource("predicate_bound_list_by_node_a"),
            resource("predicate_bound_list_by_node_b"),
            resource("generic_decl_parent_jump_a"),
            resource("generic_decl_parent_jump_b"),
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
            resource("generic_param_count_out"),
            resource("generic_param_owner_token"),
            resource("generic_param_name_id"),
            resource("generic_param_token"),
            resource("generic_param_kind"),
            resource("generic_param_key_order"),
            resource("generic_param_slot_order"),
        ] {
            assert!(
                matches!(
                    graph.resource(resource).unwrap().class,
                    ResourceClass::Workspace | ResourceClass::Output
                ),
                "generic-parameter rows must be graph-owned workspace or retained interface outputs",
            );
        }
        for resource in [
            resource("generic_param_node"),
            graph
                .resource_id("generic_param_key_order_tmp")
                .expect("large sort key-order ping-pong"),
            graph
                .resource_id("generic_param_slot_order_tmp")
                .expect("large sort slot-order ping-pong"),
            graph
                .resource_id("generic_param_slot_radix_block_histogram")
                .expect("large sort slot histogram"),
            graph
                .resource_id("generic_param_slot_radix_block_bucket_prefix")
                .expect("large sort slot prefix"),
            graph
                .resource_id("generic_param_slot_radix_bucket_total")
                .expect("large sort slot total"),
            graph
                .resource_id("generic_param_slot_radix_bucket_base")
                .expect("large sort slot base"),
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "generic-parameter sort intermediates must be graph-owned workspace",
            );
        }
        assert_ne!(
            slot(resource("generic_param_key_order")),
            slot(
                graph
                    .resource_id("generic_param_key_order_tmp")
                    .expect("large sort key-order ping-pong"),
            ),
            "generic key radix input and output may not alias",
        );
        assert_ne!(
            slot(resource("generic_param_slot_order")),
            slot(
                graph
                    .resource_id("generic_param_slot_order_tmp")
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
            resource("predicate_method_contract_key_order"),
            resource("predicate_method_contract_key_order_tmp"),
            resource("predicate_method_param_key_order"),
            resource("predicate_method_param_key_order_tmp"),
            resource("predicate_owner_key_order"),
            resource("predicate_owner_key_order_tmp"),
            resource("predicate_impl_key_order"),
            resource("predicate_impl_key_order_tmp"),
            resource("predicate_key_radix_block_histogram"),
            resource("predicate_key_radix_block_bucket_prefix"),
            resource("predicate_key_radix_bucket_total"),
            resource("predicate_key_radix_bucket_base"),
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "predicate key sorting must use graph-owned phase workspace",
            );
        }
        assert_ne!(
            slot(resource("predicate_method_contract_key_order")),
            slot(resource("predicate_method_contract_key_order_tmp")),
            "predicate radix input and scatter output are simultaneously bound",
        );
        assert_ne!(
            slot(resource("predicate_owner_key_order")),
            slot(resource("predicate_owner_key_order_tmp")),
            "predicate owner-key radix input and output may not alias",
        );
        for resource in [
            resource("predicate_obligation_count_by_call"),
            resource("predicate_obligation_prefix_by_call"),
            resource("predicate_obligation_scan_local_prefix"),
            resource("predicate_obligation_scan_block_sum"),
            resource("predicate_obligation_scan_prefix_a"),
            resource("predicate_obligation_scan_prefix_b"),
            resource("predicate_obligation_pair_total"),
            resource("predicate_obligation_pair_dispatch_args"),
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "predicate obligation emission must use graph-owned workspace",
            );
        }
        assert!(
            graph
                .lifetime(resource("predicate_obligation_count_by_call"))
                .unwrap()
                .last_pass
                .index()
                >= graph
                    .lifetime(resource("predicate_obligation_prefix_by_call"))
                    .unwrap()
                    .first_pass
                    .index(),
            "predicate validation reads the per-call counts after the scan output is produced",
        );
        assert_ne!(
            slot(resource("predicate_obligation_count_by_call")),
            slot(resource("predicate_obligation_prefix_by_call")),
            "overlapping scan input and output lifetimes must not alias",
        );
        assert_eq!(
            graph
                .resource(resource("predicate_obligation_pair_dispatch_args"))
                .unwrap()
                .usage,
            WorkspaceUsageClass::StorageIndirect,
        );
        assert_eq!(
            graph.resource(resource("member_next_node")).unwrap().class,
            ResourceClass::Workspace,
            "dense member-chain edges must remain phase-local graph workspace",
        );
        let member_result_resources = [
            resource("member_result_context_instance"),
            resource("member_result_ref_tag"),
            resource("member_result_ref_payload"),
            resource("member_result_field_ordinal"),
            resource("member_result_field_node"),
        ];
        for resource in member_result_resources {
            assert!(
                matches!(
                    graph.resource(resource).unwrap().class,
                    ResourceClass::Workspace | ResourceClass::Output
                ),
                "member-result columns must be graph-owned workspace or retained metadata outputs",
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
            .lifetime(resource("member_result_ref_tag"))
            .expect("member-result lifetime");
        assert_eq!(
            member_lifetime.first_pass,
            graph.pass_id(TYPE_SEMANTIC_CLEAR_PASS).unwrap(),
            "member-result workspace must cover the omitted early projection schedule",
        );
        assert_eq!(
            member_lifetime.last_pass, graph_output_boundary,
            "retained member-result metadata must survive beyond compact semantic projection",
        );
        for member_slot in member_result_slots {
            assert_ne!(
                member_slot,
                slot(resource("compact_expr_scalar_type.a")),
                "member results are live while expression scalar propagation runs",
            );
            assert_ne!(
                member_slot,
                slot(resource("compact_expr_scalar_type.b")),
                "member results are live while expression scalar propagation runs",
            );
        }
        let struct_workspace_resources = [
            resource("struct_init_field_context_instance"),
            resource("struct_init_field_expected_ref_tag"),
            resource("struct_init_field_expected_ref_payload"),
            resource("struct_init_field_ordinal"),
            resource("struct_init_field_ordinal_by_node"),
            resource("struct_init_field_decl_node_by_node"),
            resource("struct_init_field_decl_token_by_row"),
            resource("struct_lit_context_decl_token"),
            resource("struct_lit_context_instance"),
            resource("array_element_struct_literal_node"),
        ];
        for resource in struct_workspace_resources {
            assert!(
                matches!(
                    graph.resource(resource).unwrap().class,
                    ResourceClass::Workspace | ResourceClass::Output
                ),
                "struct-literal relations must be graph-owned workspace or retained metadata outputs",
            );
        }
        assert_eq!(
            graph
                .resource(resource("type_instance_kind"))
                .unwrap()
                .class,
            ResourceClass::Output,
            "type-instance kinds must be retained for post-type-check consumers",
        );
        assert_ne!(
            slot(resource("type_instance_kind")),
            slot(resource("array_element_struct_literal_node")),
            "struct contexts read type-instance kinds while writing array-element scratch",
        );
        assert_eq!(
            graph
                .resource(resource("struct_init_field_ordinal_by_row"))
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
            graph.resource(resource("fn_entrypoint_tag")).unwrap().class,
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
            resource("type_instance_arg_start"),
            resource("type_instance_arg_count"),
            resource("type_instance_arg_ref_tag"),
            resource("type_instance_arg_ref_payload"),
            resource("type_instance_arg_row_start"),
            resource("type_instance_arg_row_count_out"),
            resource("type_instance_arg_row_scan_local_prefix"),
            resource("type_instance_arg_row_scan_block_sum"),
            resource("type_instance_arg_row_scan_prefix_a"),
            resource("type_instance_arg_row_scan_prefix_b"),
            resource("type_instance_arg_row_ref_tag"),
            resource("type_instance_arg_row_ref_payload"),
            resource("type_instance_arg_hash"),
        ] {
            assert!(
                matches!(
                    graph.resource(resource).unwrap().class,
                    ResourceClass::Workspace | ResourceClass::Output
                ),
                "type-instance argument storage must be graph-owned workspace or retained metadata outputs",
            );
        }
        let mut clear_slots = [
            slot(resource("type_instance_arg_start")),
            slot(resource("type_instance_arg_count")),
            slot(resource("type_instance_arg_ref_tag")),
            slot(resource("type_instance_arg_ref_payload")),
            slot(resource("type_instance_arg_row_start")),
            slot(resource("type_instance_arg_row_count_out")),
            slot(resource("type_instance_arg_row_ref_tag")),
            slot(resource("type_instance_arg_row_ref_payload")),
            slot(resource("type_instance_arg_hash")),
        ];
        clear_slots.sort_unstable();
        assert!(
            clear_slots.windows(2).all(|pair| pair[0] != pair[1]),
            "all columns reset by the physical type-instance clear must occupy distinct slots",
        );
        assert_ne!(
            slot(resource("type_instance_arg_row_start")),
            slot(resource("type_instance_arg_row_scan_local_prefix")),
            "the argument-row output and scan-local prefix are simultaneously bound",
        );
        let mut argument_row_slots = [
            slot(resource("type_instance_arg_row_start")),
            slot(resource("type_instance_arg_row_count_out")),
            slot(resource("type_instance_arg_row_scan_local_prefix")),
            slot(resource("type_instance_arg_row_scan_block_sum")),
            slot(resource("type_instance_arg_row_scan_prefix_a")),
            slot(resource("type_instance_arg_row_scan_prefix_b")),
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
            slot(resource("type_instance_arg_row_ref_tag")),
            slot(resource("type_instance_arg_row_ref_payload")),
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
            resource("method_key_to_fn_token"),
            resource("method_key_order_tmp"),
            resource("method_key_status"),
            resource("method_key_duplicate_of"),
            resource("method_key_radix_block_histogram"),
            resource("method_key_radix_block_bucket_prefix"),
            resource("method_key_radix_bucket_total"),
            resource("method_key_radix_bucket_base"),
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "method-key lookup state must be graph-owned workspace",
            );
        }
        assert_ne!(
            slot(resource("type_instance_arg_hash")),
            slot(resource("method_key_status")),
            "method-key validation reads argument hashes while writing status",
        );
        assert_ne!(
            slot(resource("type_instance_arg_hash")),
            slot(resource("method_key_to_fn_token")),
            "method-key construction reads argument hashes while writing key order",
        );
        assert_ne!(
            slot(resource("method_key_to_fn_token")),
            slot(resource("method_key_status")),
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
            resource("type_semantic_row_by_token"),
            resource("type_semantic_scan_input"),
            resource("type_semantic_prefix"),
            resource("type_semantic_count_out"),
            resource("type_semantic_row_by_ordinal"),
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "semantic type compaction must be graph-owned workspace",
            );
        }
        assert_ne!(
            slot(resource("type_semantic_scan_input")),
            slot(resource("type_semantic_prefix")),
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
            slot(resource("if_delta")),
            slot(resource("if_depth_inblock")),
            slot(resource("if_block_sum")),
            slot(resource("if_prefix_a")),
            slot(resource("if_prefix_b")),
            slot(resource("if_block_prefix")),
            slot(resource("if_depth")),
        ];
        control_slots.sort_unstable();
        assert!(
            control_slots.windows(2).any(|pair| pair[0] == pair[1]),
            "at least one non-overlapping control-depth row must reuse workspace",
        );
        assert_ne!(
            slot(resource("if_depth_inblock")),
            slot(resource("if_block_prefix")),
            "simultaneously read control-scan rows must not alias",
        );
        assert_ne!(
            slot(resource("type_instance_state")),
            slot(resource("if_depth")),
            "late-recorded type-instance state must not overwrite control depth retained for semantic projection",
        );
        assert_eq!(
            graph
                .lifetime(resource("type_instance_state"))
                .unwrap()
                .last_pass,
            graph.pass_id(SEMANTIC_ARTIFACT_PROJECT_PASS).unwrap(),
            "the conservative fence must cover the resident recorder's unmodeled middle schedule",
        );
        let mut function_slots = [
            slot(resource("enclosing_fn")),
            slot(resource("enclosing_fn_end")),
            slot(resource("fn_event_value")),
            slot(resource("fn_event_end")),
            slot(resource("fn_event_index")),
            slot(resource("fn_event_inblock")),
            slot(resource("fn_block_sum")),
            slot(resource("fn_prefix_a")),
            slot(resource("fn_prefix_b")),
            slot(resource("fn_block_prefix")),
        ];
        function_slots.sort_unstable();
        assert!(
            function_slots.windows(2).any(|pair| pair[0] == pair[1]),
            "non-overlapping function-context rows must reuse workspace",
        );
        assert_ne!(
            slot(resource("fn_event_inblock")),
            slot(resource("fn_block_prefix")),
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
            graph.resource(resource("return_fn_flags")).unwrap().class,
            ResourceClass::Workspace,
            "return convergence is fully described by the registered return passes",
        );
        assert_eq!(
            graph
                .resource(resource("return_block_flags"))
                .unwrap()
                .class,
            ResourceClass::Workspace,
            "block return convergence is fully described by the registered return passes",
        );
        assert_ne!(
            slot(resource("return_fn_flags")),
            slot(resource("return_block_flags")),
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
                    access.resource == resource("semantic_expr_ref_tag_by_hir")
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
            resource("aggregate_compare_scan_input"),
            resource("aggregate_compare_expected_instance"),
            resource("aggregate_compare_actual_instance"),
            resource("aggregate_compare_error_token"),
            resource("aggregate_compare_error_detail"),
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
            resource("aggregate_compare_prefix"),
            resource("aggregate_compare_count_out"),
            resource("aggregate_compare_scan_local_prefix"),
            resource("aggregate_compare_scan_block_sum"),
            resource("aggregate_compare_scan_prefix_a"),
            resource("aggregate_compare_scan_prefix_b"),
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Resident,
                "aggregate scan hierarchy remains dedicated until every invocation is graph-scheduled",
            );
        }
        assert_eq!(
            graph
                .resource(resource("aggregate_compare_dispatch_args"))
                .unwrap()
                .usage,
            WorkspaceUsageClass::StorageIndirect,
            "indirect aggregate dispatch storage must not alias storage-only slots",
        );
        assert_ne!(
            slot(resource("aggregate_compare_scan_input")),
            slot(resource("aggregate_compare_prefix")),
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
                .resource(resource("compact_predicate_diagnostic_facts"))
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
                    access.resource == resource("compact_predicate_diagnostic_facts")
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
                    access.resource == resource("compact_predicate_diagnostic_facts")
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
            resource("semantic_value_decl_by_hir"),
            resource("semantic_value_type_by_hir"),
            resource("semantic_param_type_by_row"),
            resource("semantic_enclosing_fn_by_hir"),
            resource("semantic_function_return_type_by_hir"),
            resource("semantic_function_entrypoint_by_hir"),
            resource("semantic_function_host_service_by_hir"),
            resource("semantic_control_depth_by_hir"),
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
                .lifetime(resource("semantic_calls_by_hir"))
                .unwrap()
                .producer,
            Some(call_artifact_pass),
        );
        assert_ne!(
            slot(resource("semantic_value_decl_by_hir")),
            slot(resource("semantic_value_type_by_hir")),
            "simultaneously written semantic artifact columns must not alias",
        );
        assert_ne!(
            slot(resource("semantic_calls_by_hir")),
            slot(resource("semantic_value_type_by_hir")),
            "the checked-call artifact must not alias another projection output",
        );
        assert_ne!(
            slot(resource("call_has_array_arg")),
            slot(resource("call_result_instance")),
            "simultaneously writable call state must not alias",
        );
        assert!(
            graph
                .pass_id(CALLS_ARGUMENT_MATCH_INITIALIZE.name)
                .is_some()
        );
        assert!(graph.pass_id(CALLS_ARGUMENT_MATCH_CONSUME.name).is_some());
        assert_ne!(
            slot(resource("call_arg_row_scan_local_prefix")),
            slot(resource("call_arg_row_scan_input")),
            "simultaneously bound call-row scan buffers must not alias",
        );
        assert_ne!(
            slot(resource("call_generic_claim_scan_local_prefix")),
            slot(resource("call_generic_claim_scan_block_sum")),
            "simultaneously bound generic-claim scan rows must not alias",
        );
        assert_eq!(
            GENERIC_CLAIM_RADIX_SORT.resources.histogram,
            CONST_CLAIM_RADIX_SORT.resources.histogram,
            "sequential claim sorts should declare the same radix scratch",
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
            slot(resource("call_generic_claim_radix_block_histogram")),
            slot(resource("call_generic_claim_radix_block_bucket_prefix")),
            "simultaneously bound radix histogram and prefix rows must not alias",
        );
        assert_ne!(
            slot(resource("call_arg_row_scan_block_sum")),
            slot(resource("call_arg_row_scan_prefix_a")),
            "simultaneously bound scan hierarchy rows must not alias",
        );
        assert!(
            graph
                .lifetime(resource("call_arg_param_row"))
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
            slot(resource("call_required_generic_scan_input")),
            slot(resource("call_required_generic_prefix")),
            "scan input and output prefix are simultaneously bound",
        );
        assert!(graph.pass_id(STEP_A_TO_B_TAIL_PASS).is_none());
    }

    #[test]
    fn odd_expression_type_jump_count_has_a_real_tail_pass() {
        let kernels = crate::gpu::kernels::KernelCatalog::load_prefix("type_checker").unwrap();
        let graph = build_graph(1024, 1024, 4, 1024, 1024, 768, 768, 512, 11, &kernels).unwrap();
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
        assert!(
            graph
                .resource_id("generic_param_slot_radix_block_histogram")
                .is_none()
        );
        assert!(graph.resource_id("generic_param_key_order_tmp").is_none());
        assert!(graph.resource_id("generic_param_slot_order_tmp").is_none());
        assert!(
            graph
                .resource_id("generic_param_slot_radix_block_bucket_prefix")
                .is_none()
        );
        assert!(
            graph
                .resource_id("generic_param_slot_radix_bucket_total")
                .is_none()
        );
        assert!(
            graph
                .resource_id("generic_param_slot_radix_bucket_base")
                .is_none()
        );
        let expression_region = graph
            .repeated_regions()
            .iter()
            .find(|region| region.first_pass == graph.pass_id(STEP_A_TO_B_PASS).unwrap())
            .expect("expression pointer-jump repeated region");
        assert_eq!(expression_region.iterations, 5);
        assert!(graph.pass_id(STEP_A_TO_B_TAIL_PASS).is_some());
    }
}
