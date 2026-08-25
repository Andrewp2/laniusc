use super::{
    semantic_interface::{
        DECLARATION_WORDS,
        MEMBER_WORDS,
        MODULE_SEGMENT_WORDS,
        MODULE_WORDS,
        TYPE_WORDS,
    },
    *,
};
use crate::{
    gpu::{
        compiler_graph::{
            AccessMode,
            CompilerGraph,
            CompilerGraphAllocations,
            CompilerGraphBuilder,
            CompilerPhase,
            INDIRECT_DISPATCH_BINDING,
            MaterializedCompilerGraph,
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
    },
    parser::buffers::{
        HirArrayElement,
        HirCallArg,
        HirField,
        HirGenericParam,
        HirMatchArm,
        HirMatchPayload,
        HirMethodCore,
        HirMethodSignature,
        HirParam,
        HirPath,
        HirPathSegment,
        HirPredicate,
        HirRange,
        HirSemanticFacts,
        HirString,
        HirTypeArg,
        HirVariant,
        HirVariantPayload,
    },
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

/// Declares graph resources as a compact allocation schema. The Rust binding,
/// reflected resource name, ownership class, logical domain, and byte extent
/// stay on one row instead of being repeated through `add_storage` calls.
macro_rules! graph_resources {
    ($graph:ident, $class:ident { $(
        $var:ident $(as $name:literal)? in $domain:ident $([$usage:ident])? => $bytes:expr;
    )* }) => {
        $(
            let $var = graph_resources!(@add
                $graph,
                $class,
                graph_resources!(@name $var $(as $name)?),
                $domain
                $([$usage])?,
                $bytes
            )?;
        )*
    };
    (@add $graph:ident, $class:ident, $name:expr, $domain:ident, $bytes:expr) => {
        $graph.add_storage(
            $name,
            ResourceDomain::$domain,
            ResourceClass::$class,
            $bytes,
        )
    };
    (@add $graph:ident, $class:ident, $name:expr, $domain:ident [$usage:ident], $bytes:expr) => {
        $graph.add_resource(ResourceDesc {
            name: $name,
            domain: ResourceDomain::$domain,
            class: ResourceClass::$class,
            bytes: $bytes,
            usage: WorkspaceUsageClass::$usage,
        })
    };
    (@name $var:ident) => { stringify!($var) };
    (@name $var:ident as $name:literal) => { $name };
}

/// Overrides the few reflected bindings whose graph resource name or access
/// mode cannot be inferred directly from the shader declaration.
macro_rules! reflected_bindings {
    ($($binding:literal => $resource:ident $( : $mode:ident )?),* $(,)?) => {
        &[$(ReflectedResourceBinding {
            binding: $binding,
            resource: $resource,
            mode: reflected_bindings!(@mode $($mode)?),
        }),*]
    };
    (@mode) => { None };
    (@mode $mode:ident) => { Some(AccessMode::$mode) };
}

pub(super) const INIT_PASS: &str = "type_check.expression_types.init";
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
    };
pub(super) const AGGREGATE_FINAL_DISPATCH_PASS: &str =
    "type_check.aggregate_requests.final.dispatch";
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
    };
pub(super) const TYPE_SUBTREE_FINAL_DISPATCH_PASS: &str = "type_check.type_subtree.final.dispatch";
pub(super) const TYPE_SUBTREE_FINAL_INDIRECT_PASS: &str = "type_check.type_subtree.final.indirect";
pub(super) const TYPE_SEMANTIC_CLEAR_PASS: &str = "type_check.type_semantic.clear";
pub(super) const TYPE_SEMANTIC_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::HirNodes,
    passes: prefix_scan_graph_passes!("type_check.type_semantic.scan"),
    resources: PrefixScanResources {
        count: "compact_hir_count",
        input: "type_semantic_scan_input",
        output_prefix: "type_semantic_prefix",
        total: "type_semantic_count_out",
        dispatch_args: "hir_active_dispatch_args",
        local_prefix: "aggregate_compare_scan_local_prefix",
        block_sum: "aggregate_compare_scan_block_sum",
        block_prefix: "aggregate_compare_scan_prefix_a",
    },
};
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
    },
};
pub(super) const GENERIC_PARAM_SLOT_SCAN: PrefixScanPairSpec = PrefixScanPairSpec {
    left_label: "type_check.generic_params.type_slots",
    right_label: "type_check.generic_params.const_slots",
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::Declarations,
    passes: prefix_scan_graph_passes!("type_check.generic_params.slot_scan"),
    left: PrefixScanResources {
        count: "generic_param_count_out",
        input: "generic_type_param_flag",
        output_prefix: "generic_type_param_prefix",
        total: "generic_type_param_count_out",
        dispatch_args: "hir_active_dispatch_args",
        local_prefix: "generic_type_param_scan_local_prefix",
        block_sum: "generic_type_param_scan_block_sum",
        block_prefix: "generic_type_param_scan_prefix_a",
    },
    right: PrefixScanResources {
        count: "generic_param_count_out",
        input: "generic_const_param_flag",
        output_prefix: "generic_const_param_prefix",
        total: "generic_const_param_count_out",
        dispatch_args: "hir_active_dispatch_args",
        local_prefix: "generic_const_param_scan_local_prefix",
        block_sum: "generic_const_param_scan_block_sum",
        block_prefix: "generic_const_param_scan_prefix_a",
    },
};
pub(super) const LANGUAGE_NAMES_CLEAR_PASS: &str = "type_check.language_names.clear";
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
    },
};
pub(super) const NAMES_HASH_PREPARE_PASS: &str = "type_check.names.hash_prepare";
pub(super) const NAMES_HASH_INSERT_PASS: &str = "type_check.names.hash_insert";
pub(super) const NAMES_HASH_ASSIGN_PASS: &str = "type_check.names.hash_assign_ids";
pub(super) const LANGUAGE_TYPE_CODES_CLEAR_PASS: &str = "type_check.language_type_codes.clear";
pub(super) const LANGUAGE_DECLS_MATERIALIZE_PASS: &str = "type_check.language_decls.materialize";
pub(super) const TYPE_INSTANCES_MARK_GENERIC_PARAM_RECORDS_PASS: &str =
    "type_check.type_instances.mark_generic_param_records";
pub(super) const TYPE_INSTANCES_DECL_GENERIC_PARAMS_PASS: &str =
    "type_check.type_instances.decl_generic_params";
pub(super) const TYPE_INSTANCES_GENERIC_PARAM_USE_SLOTS_PASS: &str =
    "type_check.type_instances.generic_params.use_slots";
pub(super) const GENERIC_PARAM_EMPTY_PASS: &str = "type_check.generic_params.empty";
pub(super) const TYPE_INSTANCE_ARG_HASH_ROWS_PASS: &str = "type_check.type_instance_arg_rows.hash";
pub(super) const CONDITIONS_AGGREGATE_ARGS_FINAL_PASS: &str =
    "type_check.conditions.aggregate_args.final";
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
pub(super) const HIR_ACTIVE_DISPATCH_PASS: &str = "type_check.hir_active_dispatch_args";
pub(super) const IF_DEPTH_CLEAR_PASS: &str = "type_check.if_depth.clear";
pub(super) const IF_DEPTH_MARK_PASS: &str = "type_check.if_depth.mark";
pub(super) const IF_DEPTH_LOCAL_PASS: &str = "type_check.if_depth.local";
pub(super) const IF_DEPTH_SCAN_UP_FIRST_PASS: &str = "type_check.if_depth.hierarchy_up.first";
pub(super) const IF_DEPTH_SCAN_UP_REST_PASS: &str = "type_check.if_depth.hierarchy_up.rest";
pub(super) const IF_DEPTH_SCAN_DOWN_PASS: &str = "type_check.if_depth.hierarchy_down";
pub(super) const IF_DEPTH_APPLY_PASS: &str = "type_check.if_depth.apply";
pub(super) const FN_CONTEXT_CLEAR_PASS: &str = "type_check.fn_context.clear";
pub(super) const FN_CONTEXT_MARK_PASS: &str = "type_check.fn_context.mark";
pub(super) const FN_CONTEXT_LOCAL_PASS: &str = "type_check.fn_context.local";
pub(super) const FN_CONTEXT_SCAN_UP_FIRST_PASS: &str = "type_check.fn_context.hierarchy_up.first";
pub(super) const FN_CONTEXT_SCAN_UP_REST_PASS: &str = "type_check.fn_context.hierarchy_up.rest";
pub(super) const FN_CONTEXT_SCAN_DOWN_PASS: &str = "type_check.fn_context.hierarchy_down";
pub(super) const FN_CONTEXT_APPLY_PASS: &str = "type_check.fn_context.apply";
pub(super) const CALLS_BACKEND_TARGETS_PASS: &str = "type_check.calls.backend_targets";
pub(super) const VISIBLE_CLEAR_PASS: &str = "type_check.visible.clear";
pub(super) const VISIBLE_MATCH_DISPATCH_PASS: &str =
    "type_check.visible.match_payload_dispatch_args";
const VISIBLE_SCAN_PASS: &str = "type_check.visible.decl_scan";
const VISIBLE_SCAN_UP_FIRST_PASS: &str = "type_check.visible.decl_scan.hierarchy_up.first";
const VISIBLE_SCAN_UP_REST_PASS: &str = "type_check.visible.decl_scan.hierarchy_up.rest";
const VISIBLE_SCAN_DOWN_PASS: &str = "type_check.visible.decl_scan.hierarchy_down";
const VISIBLE_SCAN_APPLY_PASS: &str = "type_check.visible.decl_scan.apply";
pub(super) const VISIBLE_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::Tokens,
    passes: PrefixScanGraphPasses {
        local: VISIBLE_SCAN_PASS,
        hierarchy_up_first: VISIBLE_SCAN_UP_FIRST_PASS,
        hierarchy_up_rest: VISIBLE_SCAN_UP_REST_PASS,
        hierarchy_down: VISIBLE_SCAN_DOWN_PASS,
        apply: VISIBLE_SCAN_APPLY_PASS,
    },
    resources: PrefixScanResources {
        count: "token_count",
        input: "hir_visible_decl_flag",
        output_prefix: "hir_visible_decl_prefix",
        total: "hir_visible_decl_count_out",
        dispatch_args: "token_active_dispatch_args",
        local_prefix: "hir_visible_decl_scan_local_prefix",
        block_sum: "hir_visible_decl_scan_block_sum",
        block_prefix: "hir_visible_decl_scan_prefix_a",
    },
};
const VISIBLE_SORT_PASS: &str = "type_check.visible.sort_hir_decl_keys";
pub(super) const VISIBLE_RADIX_DISPATCH_PASS: &str =
    "type_check.visible.hir_decl_key_radix_dispatch_args";
pub(super) const VISIBLE_RADIX_SORT: RadixSortDefinition = RadixSortDefinition {
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::Declarations,
    small_pass: VISIBLE_SORT_PASS,
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
pub(super) const SCOPE_HIR_PASS: &str = "type_check.scope.hir";
pub(super) const SEMANTIC_ARTIFACT_PROJECT_PASS: &str = "type_check.semantic_artifact.project";
pub(super) const SEMANTIC_LOCAL_CONST_LITERALS_PROJECT_PASS: &str =
    "type_check.semantic_artifact.local_const_literals";
pub(super) const SEMANTIC_LOCAL_CONST_REFERENCES_PROJECT_PASS: &str =
    "type_check.semantic_artifact.local_const_references";
pub(super) const STATUS_READBACK_PASS: &str = "type_check.status.readback";

pub(super) const PREDICATES_CLEAR_BOUND_ARG_FACTS_PASS: &str =
    "type_check.predicates.clear_bound_arg_facts";
pub(super) const PREDICATES_CLEAR_SYNTAX_TOKENS_PASS: &str =
    "type_check.predicates.clear_syntax_tokens";
pub(super) const PREDICATES_COLLECT_BOUND_ARG_FACTS_PASS: &str =
    "type_check.predicates.collect_bound_arg_facts";
pub(super) const PREDICATES_COLLECT_METHOD_CONTRACTS_PASS: &str =
    "type_check.predicates.collect_method_contracts";
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
    },
};
pub(super) const PREDICATES_OBLIGATION_PAIR_DISPATCH_PASS: &str =
    "type_check.predicates.obligation_pair_dispatch";
pub(super) const PREDICATES_OBLIGATION_PAIR_DISPATCH_CLEAR_PASS: &str =
    "type_check.predicates.obligation_pair_dispatch.clear";
pub(super) const PREDICATES_VALIDATE_OBLIGATION_PAIRS_PASS: &str =
    "type_check.predicates.validate_obligation_pairs";

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
    },
};
pub(super) const GENERIC_CLAIM_INDEX_PREPARE_PASS: &str =
    "type_check.calls.generic_claims.index.prepare";
pub(super) const CONST_CLAIM_INDEX_PREPARE_PASS: &str =
    "type_check.calls.const_claims.index.prepare";
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
    },
};
pub(super) const REQUIRED_GENERIC_DISPATCH_PASS: &str =
    "type_check.calls.required_generics.dispatch";
const MODULE_RECORD_SCAN_LOCAL_PASS: &str = "type_check.modules.records.module_scan.local";
const MODULE_RECORD_SCAN_UP_FIRST_PASS: &str =
    "type_check.modules.records.module_scan.hierarchy_up.first";
const MODULE_RECORD_SCAN_UP_REST_PASS: &str =
    "type_check.modules.records.module_scan.hierarchy_up.rest";
const MODULE_RECORD_SCAN_DOWN_PASS: &str = "type_check.modules.records.module_scan.hierarchy_down";
const MODULE_RECORD_SCAN_APPLY_PASS: &str = "type_check.modules.records.module_scan.apply";
const IMPORT_RECORD_SCAN_LOCAL_PASS: &str = "type_check.modules.records.import_scan.local";
const IMPORT_RECORD_SCAN_UP_FIRST_PASS: &str =
    "type_check.modules.records.import_scan.hierarchy_up.first";
const IMPORT_RECORD_SCAN_UP_REST_PASS: &str =
    "type_check.modules.records.import_scan.hierarchy_up.rest";
const IMPORT_RECORD_SCAN_DOWN_PASS: &str = "type_check.modules.records.import_scan.hierarchy_down";
const IMPORT_RECORD_SCAN_APPLY_PASS: &str = "type_check.modules.records.import_scan.apply";
const DECL_RECORD_SCAN_LOCAL_PASS: &str = "type_check.modules.records.decl_scan.local";
const DECL_RECORD_SCAN_UP_FIRST_PASS: &str =
    "type_check.modules.records.decl_scan.hierarchy_up.first";
const DECL_RECORD_SCAN_UP_REST_PASS: &str =
    "type_check.modules.records.decl_scan.hierarchy_up.rest";
const DECL_RECORD_SCAN_DOWN_PASS: &str = "type_check.modules.records.decl_scan.hierarchy_down";
const DECL_RECORD_SCAN_APPLY_PASS: &str = "type_check.modules.records.decl_scan.apply";
const MODULE_DECL_KEY_SORT_PASS: &str = "type_check.modules.decl_keys";
pub(super) const MODULE_DECL_KEY_RADIX_SORT: RadixSortDefinition = RadixSortDefinition {
    phase: CompilerPhase::TypeCheck,
    dispatch_domain: ResourceDomain::Declarations,
    small_pass: MODULE_DECL_KEY_SORT_PASS,
    passes: radix_sort_graph_passes!("type_check.modules.decl_keys"),
    kernels: RadixSortKernels::new(
        "type_checker/modules/06_sort_decl_keys",
        "type_checker/modules/06b_sort_decl_keys_scatter",
    )
    .with_small("type_checker/modules/06a2_sort_decl_keys_small"),
    resources: RadixSortResources {
        count: "decl_count_out",
        order: "decl_key_to_decl_id",
        temporary_order: "decl_key_order_tmp",
        histogram: "module_path_key_radix_block_histogram",
        bucket_prefix: "module_path_key_radix_block_bucket_prefix",
        bucket_total: "module_path_key_radix_bucket_total",
        bucket_base: "module_path_key_radix_bucket_base",
    },
    dispatch_args: "decl_key_radix_dispatch_args",
};

#[cfg(test)]
const fn module_decl_key_radix_start_pass(capacity: u32, steps: u32) -> &'static str {
    if capacity <= MODULE_RELATION_SMALL_SORT_CAPACITY {
        MODULE_DECL_KEY_RADIX_SORT.small_pass
    } else if steps % 2 != 0 {
        MODULE_DECL_KEY_RADIX_SORT
            .passes
            .temporary_to_order
            .histogram
    } else {
        MODULE_DECL_KEY_RADIX_SORT
            .passes
            .order_to_temporary
            .histogram
    }
}

#[cfg(test)]
const fn visible_decl_radix_start_pass(capacity: u32, steps: u32) -> &'static str {
    if capacity <= VISIBLE_DECL_SMALL_SORT_CAPACITY {
        VISIBLE_RADIX_SORT.small_pass
    } else if steps % 2 != 0 {
        VISIBLE_RADIX_SORT.passes.temporary_to_order.histogram
    } else {
        VISIBLE_RADIX_SORT.passes.order_to_temporary.histogram
    }
}
const DECL_NAMESPACE_SCAN_LOCAL_PASS: &str = "type_check.modules.decl_namespace.scan.local";
const DECL_NAMESPACE_SCAN_UP_FIRST_PASS: &str =
    "type_check.modules.decl_namespace.scan.hierarchy_up.first";
const DECL_NAMESPACE_SCAN_UP_REST_PASS: &str =
    "type_check.modules.decl_namespace.scan.hierarchy_up.rest";
const DECL_NAMESPACE_SCAN_DOWN_PASS: &str = "type_check.modules.decl_namespace.scan.hierarchy_down";
const DECL_NAMESPACE_SCAN_APPLY_PASS: &str = "type_check.modules.decl_namespace.scan.apply";
const DECL_PUBLIC_SCAN_LOCAL_PASS: &str = "type_check.modules.decl_public.scan.local";
const DECL_PUBLIC_SCAN_UP_FIRST_PASS: &str =
    "type_check.modules.decl_public.scan.hierarchy_up.first";
const DECL_PUBLIC_SCAN_UP_REST_PASS: &str = "type_check.modules.decl_public.scan.hierarchy_up.rest";
const DECL_PUBLIC_SCAN_DOWN_PASS: &str = "type_check.modules.decl_public.scan.hierarchy_down";
const DECL_PUBLIC_SCAN_APPLY_PASS: &str = "type_check.modules.decl_public.scan.apply";
const IMPORT_VISIBLE_SCAN_LOCAL_PASS: &str = "type_check.modules.import_visibility.scan.local";
const IMPORT_VISIBLE_SCAN_UP_FIRST_PASS: &str =
    "type_check.modules.import_visibility.scan.hierarchy_up.first";
const IMPORT_VISIBLE_SCAN_UP_REST_PASS: &str =
    "type_check.modules.import_visibility.scan.hierarchy_up.rest";
const IMPORT_VISIBLE_SCAN_DOWN_PASS: &str =
    "type_check.modules.import_visibility.scan.hierarchy_down";
const IMPORT_VISIBLE_SCAN_APPLY_PASS: &str = "type_check.modules.import_visibility.scan.apply";
pub(super) const MODULE_RECORD_SCAN_RESOURCES: PrefixScanResources<&'static str> =
    module_record_scan_resources("module_record_count_out");
pub(super) const MODULE_VALUE_SCAN_WORKSPACE: PrefixScanWorkspace<&'static str> =
    PrefixScanWorkspace {
        local_prefix: "module_value_scan_local_prefix",
        block_sum: "module_value_scan_block_sum",
        block_prefix: "module_value_scan_prefix_a",
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
pub(super) const DEPENDENCY_VISIBLE_SCAN_CALL_COLLECTION: PrefixScanSpec = PrefixScanSpec {
    passes: prefix_scan_graph_passes!("type_check.dependencies.call_collection.visible.scan"),
    ..DEPENDENCY_VISIBLE_SCAN
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
    let (local_prefix, block_sum, block_prefix) = if value_workspace {
        (
            "module_value_scan_local_prefix",
            "module_value_scan_block_sum",
            "module_value_scan_prefix_a",
        )
    } else {
        (
            "module_record_scan_local_prefix",
            "module_record_scan_block_sum",
            "module_record_scan_prefix_a",
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
    }
}
pub(super) const DEPENDENCY_CALL_COMPARE_CLEAR_PASS: &str =
    "type_check.dependencies.call_compare.clear";
pub(super) const DEPENDENCY_CALL_ARGS_VALIDATE_PASS: &str =
    "type_check.dependencies.validate_call_args";
pub(super) const DEPENDENCY_CALL_RESULTS_SUBSTITUTE_PASS: &str =
    "type_check.dependencies.validate_call_results.substitute";
pub(super) const DEPENDENCY_CALL_RESULTS_VALIDATE_PASS: &str =
    "type_check.dependencies.validate_call_results.validate";
pub(super) const DEPENDENCY_GENERIC_CALL_RESULTS_RESOLVE_PASS: &str =
    "type_check.dependencies.resolve_generic_call_results";
pub(super) const DEPENDENCY_CALL_COMPARE_DISPATCH_PASS: &str =
    "type_check.dependencies.call_compare_dispatch_args";
pub(super) const DEPENDENCY_CALL_TYPE_ARGS_VALIDATE_PASS: &str =
    "type_check.dependencies.validate_call_type_args";
pub(super) const DEPENDENCY_METHODS_PROJECT_PASS: &str = "type_check.dependencies.project_methods";

/// Graph-owned storage and ownership contract for type checking. Logical
/// resources are recovered from the graph by name; the workspace is their
/// sole physical owner.
pub(super) struct TypeCheckCompilerGraph {
    materialized: MaterializedCompilerGraph,
    semantic_interface_scans: Option<SemanticInterfaceScanGraph>,
}

#[derive(Clone, Copy, Debug, Default)]
pub(super) struct DependencyWorkspaceCapacity {
    visible_rows: u32,
    lookup_rows: u32,
    type_rows: u32,
    declaration_rows: u32,
}

impl DependencyWorkspaceCapacity {
    pub(super) fn for_job(
        token_capacity: u32,
        dependency: Option<&GpuDependencyInterfaceState>,
    ) -> Result<Self> {
        let Some(dependency) = dependency else {
            return Ok(Self::default());
        };
        let visible_rows = token_capacity.max(dependency.declaration_count).max(1);
        let lookup_rows = visible_rows
            .checked_mul(2)
            .and_then(u32::checked_next_power_of_two)
            .ok_or_else(|| anyhow::anyhow!("dependency visibility lookup capacity exceeds u32"))?;
        Ok(Self {
            visible_rows,
            lookup_rows,
            type_rows: dependency.type_count.max(1),
            declaration_rows: dependency.declaration_count.max(1),
        })
    }
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

pub(super) const SEMANTIC_INTERFACE_ROOT_STEP_PASSES: [&str; 8] = [
    "type_check.interface.type_topology.root_step.0",
    "type_check.interface.type_topology.root_step.1",
    "type_check.interface.type_topology.root_step.2",
    "type_check.interface.type_topology.root_step.3",
    "type_check.interface.type_topology.root_step.4",
    "type_check.interface.type_topology.root_step.5",
    "type_check.interface.type_topology.root_step.6",
    "type_check.interface.type_topology.root_step.7",
];
const SEMANTIC_INTERFACE_ACTIVE_HIR_PASSES: &[&str] = &[
    "type_check.interface.type_topology.init",
    "type_check.interface.type_topology.attach_unary",
    "type_check.interface.type_topology.seed_declarations",
    "type_check.interface.type_topology.seed_params",
    "type_check.interface.type_topology.seed_fields",
    "type_check.interface.type_topology.seed_variants",
    "type_check.interface.type_topology.root_init",
    "type_check.interface.type_topology.mark_reverse",
    "type_check.interface.type_topology.scatter",
    "type_check.interface.type_topology.edge_counts",
    "type_check.interface.type_topology.edge_scatter",
    "type_check.interface.type_topology.resolve_local_decl",
    "type_check.interface.type_topology.classify_path",
    "type_check.interface.type_topology.type_records",
    "type_check.interface.type_topology.array_lengths",
    "type_check.interface.type_topology.validate",
    "type_check.interface.signature.param_edges",
    "type_check.interface.signature.variant_payload_edges",
    "type_check.interface.members.variant_counts",
    "type_check.interface.members.method_counts",
    "type_check.interface.members.scatter_hir",
    "type_check.interface.members.normalize_types",
];
pub(super) const SEMANTIC_INTERFACE_EDGE_WRITTEN_CLEAR_PASS: &str =
    "type_check.interface.type_topology.edge_written.clear";
pub(super) const SEMANTIC_INTERFACE_FIELD_COUNT_CLEAR_PASS: &str =
    "type_check.interface.members.field_count.clear";
pub(super) const SEMANTIC_INTERFACE_VARIANT_COUNT_CLEAR_PASS: &str =
    "type_check.interface.members.variant_count.clear";
pub(super) const SEMANTIC_INTERFACE_GENERIC_TYPE_COUNT_CLEAR_PASS: &str =
    "type_check.interface.members.generic_type_count.clear";
pub(super) const SEMANTIC_INTERFACE_GENERIC_CONST_COUNT_CLEAR_PASS: &str =
    "type_check.interface.members.generic_const_count.clear";
pub(super) const SEMANTIC_INTERFACE_MEMBER_WRITTEN_CLEAR_PASS: &str =
    "type_check.interface.members.written.clear";
pub(super) const SEMANTIC_INTERFACE_NAME_REF_CLEAR_PASS: &str =
    "type_check.interface.name_ref_len.clear";
pub(super) const SEMANTIC_INTERFACE_NAME_BYTES_CLEAR_PASS: &str =
    "type_check.interface.name_byte_words.clear";
pub(super) const SEMANTIC_INTERFACE_COUNTS_CLEAR_PASS: &str = "type_check.interface.counts.clear";
pub(super) const SEMANTIC_INTERFACE_ARTIFACT_LENGTH_READBACK_PASS: &str =
    "type_check.interface.artifact_length.readback";
pub(super) const SEMANTIC_INTERFACE_STATUS_READBACK_PASS: &str =
    "type_check.interface.status.readback";

struct SemanticInterfaceScanGraph {
    materialized: MaterializedCompilerGraph,
    bindings: CompilerGraphBindings,
    scratch: PrefixScanWorkspace<LaniusBuffer<u32>>,
    resources: [PrefixScanResources<ResourceId>; 7],
    passes: [PrefixScanGraphPasses; 7],
}

struct SemanticInterfaceScanPlan {
    graph: CompilerGraph,
    scan_capacity: u64,
    scratch: PrefixScanWorkspace<ResourceId>,
    resources: [PrefixScanResources<ResourceId>; 7],
    passes: [PrefixScanGraphPasses; 7],
}

impl SemanticInterfaceScanGraph {
    fn root_step_count(&self) -> usize {
        SEMANTIC_INTERFACE_ROOT_STEP_PASSES
            .iter()
            .take_while(|name| self.materialized.graph().pass_id(name).is_some())
            .count()
    }

    fn build(
        hir_capacity: u32,
        token_capacity: u32,
        source_file_capacity: u32,
        declaration_capacity: u32,
        kernels: &impl crate::gpu::kernels::KernelReflections,
        upstream_graph: &CompilerGraph,
    ) -> Result<SemanticInterfaceScanPlan> {
        let capacities = [
            u64::from(token_capacity) * 2
                + u64::from(hir_capacity) * 2
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
        let semantic_hir_rows = u64::from(hir_capacity.min(token_capacity).max(1));
        let declaration_rows = u64::from(declaration_capacity.min(token_capacity).max(1));
        let token_rows = u64::from(token_capacity.max(1));
        let module_rows = u64::from(source_file_capacity.max(1));
        let type_rows = semantic_hir_rows
            .checked_add(declaration_rows)
            .and_then(|rows| rows.checked_add(1))
            .ok_or_else(|| anyhow::anyhow!("semantic-interface type capacity overflows u64"))?;
        let edge_rows = semantic_hir_rows
            .checked_add(declaration_rows)
            .ok_or_else(|| anyhow::anyhow!("semantic-interface edge capacity overflows u64"))?;
        let member_rows = semantic_hir_rows
            .checked_mul(2)
            .and_then(|rows| rows.checked_add(token_rows))
            .ok_or_else(|| anyhow::anyhow!("semantic-interface member capacity overflows u64"))?;
        let name_ref_rows = token_rows
            .checked_mul(2)
            .and_then(|rows| rows.checked_add(semantic_hir_rows.saturating_mul(2)))
            .and_then(|rows| rows.checked_add(declaration_rows))
            .ok_or_else(|| anyhow::anyhow!("semantic-interface name capacity overflows u64"))?;
        for (name, rows) in [
            ("semantic_interface.name_ref_len", name_ref_rows),
            (
                "semantic_interface.modules",
                module_rows * MODULE_WORDS as u64,
            ),
            (
                "semantic_interface.module_segments",
                token_rows * MODULE_SEGMENT_WORDS as u64,
            ),
            (
                "semantic_interface.declarations",
                declaration_rows * DECLARATION_WORDS as u64,
            ),
            ("semantic_interface.type.parent", semantic_hir_rows),
            ("semantic_interface.type.seed_owner", semantic_hir_rows),
            ("semantic_interface.type.child_ordinal", semantic_hir_rows),
            (
                "semantic_interface.type.direct_hir_by_decl",
                declaration_rows,
            ),
            ("semantic_interface.type.index_by_hir", semantic_hir_rows),
            ("semantic_interface.type.root_link_a", semantic_hir_rows),
            ("semantic_interface.type.root_link_b", semantic_hir_rows),
            ("semantic_interface.type.root_owner_a", semantic_hir_rows),
            ("semantic_interface.type.root_owner_b", semantic_hir_rows),
            ("semantic_interface.type.reverse_flag", semantic_hir_rows),
            ("semantic_interface.type.hir_order", semantic_hir_rows),
            ("semantic_interface.type.edge_count", semantic_hir_rows),
            ("semantic_interface.type.edges", edge_rows),
            ("semantic_interface.type.edge_written", edge_rows),
            (
                "semantic_interface.type.local_decl_by_hir",
                semantic_hir_rows,
            ),
            (
                "semantic_interface.type.path_classification",
                semantic_hir_rows * 4,
            ),
            (
                "semantic_interface.type.types",
                type_rows * TYPE_WORDS as u64,
            ),
            ("semantic_interface.signature.type_flag", declaration_rows),
            ("semantic_interface.signature.edge_count", declaration_rows),
            (
                "semantic_interface.signature.type_by_decl",
                declaration_rows,
            ),
            ("semantic_interface.complete_type_count", 1),
            ("semantic_interface.complete_edge_total", 1),
            (
                "semantic_interface.members.variant_count_by_hir",
                semantic_hir_rows,
            ),
            (
                "semantic_interface.members.field_count_by_hir",
                semantic_hir_rows,
            ),
            (
                "semantic_interface.members.generic_type_count_by_decl",
                declaration_rows,
            ),
            (
                "semantic_interface.members.generic_const_count_by_decl",
                declaration_rows,
            ),
            ("semantic_interface.members.row_count", declaration_rows),
            ("semantic_interface.members.cursor", declaration_rows),
            (
                "semantic_interface.members.records",
                member_rows * MEMBER_WORDS as u64,
            ),
            ("semantic_interface.members.name_id", member_rows),
            (
                "semantic_interface.members.index_by_generic_row",
                token_rows,
            ),
            ("semantic_interface.members.written", member_rows),
        ] {
            builder
                .add_resource(ResourceDesc {
                    name,
                    domain: ResourceDomain::Types,
                    class: ResourceClass::Workspace,
                    bytes: rows.max(1) * 4,
                    usage: WorkspaceUsageClass::Storage,
                })
                .map_err(anyhow::Error::msg)?;
        }
        macro_rules! scan_resources {
            ($label:literal, $capacity:expr, $domain:expr, $input:expr) => {
                (|| -> Result<_, String> {
                    let count = resource!(
                        concat!($label, ".count"),
                        $domain,
                        ResourceClass::Input,
                        4,
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
                        ResourceClass::Workspace,
                        $capacity * 4,
                        WorkspaceUsageClass::Storage
                    );
                    let total = resource!(
                        concat!($label, ".total"),
                        $domain,
                        ResourceClass::Workspace,
                        4,
                        WorkspaceUsageClass::Storage
                    );
                    let resources = PrefixScanResources {
                        count,
                        input: $input,
                        output_prefix,
                        total,
                        dispatch_args,
                        local_prefix: scratch.local_prefix,
                        block_sum: scratch.block_sum,
                        block_prefix: scratch.block_prefix,
                    };
                    let passes = prefix_scan_graph_passes!($label);
                    Ok((resources, passes))
                })()
            };
        }
        let external_scan_input = |builder: &mut CompilerGraphBuilder,
                                   name: &'static str,
                                   domain: ResourceDomain,
                                   capacity: u64|
         -> Result<ResourceId, String> {
            builder.add_resource(ResourceDesc {
                name,
                domain,
                class: ResourceClass::Input,
                bytes: capacity.max(1) * 4,
                usage: WorkspaceUsageClass::Storage,
            })
        };
        let module_scan_input = external_scan_input(
            &mut builder,
            "semantic_interface.modules.input",
            ResourceDomain::Declarations,
            capacities[SemanticInterfaceScan::Modules as usize],
        )
        .map_err(anyhow::Error::msg)?;
        let scans = [
            scan_resources!(
                "semantic_interface.names",
                capacities[0],
                ResourceDomain::Bytes,
                builder
                    .resource_id("semantic_interface.name_ref_len")
                    .expect("semantic-interface name lengths")
            ),
            scan_resources!(
                "semantic_interface.modules",
                capacities[1],
                ResourceDomain::Declarations,
                module_scan_input
            ),
            scan_resources!(
                "semantic_interface.signature_types",
                capacities[2],
                ResourceDomain::Types,
                builder
                    .resource_id("semantic_interface.signature.type_flag")
                    .expect("semantic-interface signature type flags")
            ),
            scan_resources!(
                "semantic_interface.signature_edges",
                capacities[3],
                ResourceDomain::Types,
                builder
                    .resource_id("semantic_interface.signature.edge_count")
                    .expect("semantic-interface signature edge counts")
            ),
            scan_resources!(
                "semantic_interface.members",
                capacities[4],
                ResourceDomain::Declarations,
                builder
                    .resource_id("semantic_interface.members.row_count")
                    .expect("semantic-interface member counts")
            ),
            scan_resources!(
                "semantic_interface.type_order",
                capacities[5],
                ResourceDomain::Types,
                builder
                    .resource_id("semantic_interface.type.reverse_flag")
                    .expect("semantic-interface reverse flags")
            ),
            scan_resources!(
                "semantic_interface.type_edges",
                capacities[6],
                ResourceDomain::Types,
                builder
                    .resource_id("semantic_interface.type.edge_count")
                    .expect("semantic-interface type edge counts")
            ),
        ]
        .into_iter()
        .collect::<Result<Vec<_>, String>>()
        .map_err(anyhow::Error::msg)?;
        // Shader-facing aliases connect reflected operations to the compact
        // semantic relations above. Scan fragments are inserted later at their
        // exact execution positions, after the passes that produce their inputs.
        for (binding, resource_name) in [
            ("interface_name_ref_len", "semantic_interface.name_ref_len"),
            ("interface_modules", "semantic_interface.modules"),
            (
                "interface_module_segments",
                "semantic_interface.module_segments",
            ),
            (
                "interface_declaration_words",
                "semantic_interface.declarations",
            ),
            ("interface_type_parent", "semantic_interface.type.parent"),
            (
                "interface_type_seed_owner",
                "semantic_interface.type.seed_owner",
            ),
            (
                "interface_type_child_ordinal",
                "semantic_interface.type.child_ordinal",
            ),
            (
                "interface_decl_direct_type_hir",
                "semantic_interface.type.direct_hir_by_decl",
            ),
            (
                "interface_type_index_by_hir",
                "semantic_interface.type.index_by_hir",
            ),
            (
                "interface_type_root_link",
                "semantic_interface.type.root_link_a",
            ),
            (
                "interface_type_reverse_flag",
                "semantic_interface.type.reverse_flag",
            ),
            (
                "interface_type_hir_order",
                "semantic_interface.type.hir_order",
            ),
            (
                "interface_type_edge_count",
                "semantic_interface.type.edge_count",
            ),
            ("interface_type_edges", "semantic_interface.type.edges"),
            (
                "interface_type_edge_written",
                "semantic_interface.type.edge_written",
            ),
            (
                "interface_type_local_decl_by_hir",
                "semantic_interface.type.local_decl_by_hir",
            ),
            (
                "interface_type_path_classification",
                "semantic_interface.type.path_classification",
            ),
            ("interface_types", "semantic_interface.type.types"),
            (
                "interface_signature_type_flag",
                "semantic_interface.signature.type_flag",
            ),
            (
                "interface_signature_edge_count",
                "semantic_interface.signature.edge_count",
            ),
            (
                "interface_signature_type_by_decl",
                "semantic_interface.signature.type_by_decl",
            ),
            (
                "interface_complete_type_count",
                "semantic_interface.complete_type_count",
            ),
            (
                "interface_complete_edge_total",
                "semantic_interface.complete_edge_total",
            ),
            (
                "interface_variant_count_by_hir",
                "semantic_interface.members.variant_count_by_hir",
            ),
            (
                "interface_field_count_by_hir",
                "semantic_interface.members.field_count_by_hir",
            ),
            (
                "interface_generic_type_count_by_decl",
                "semantic_interface.members.generic_type_count_by_decl",
            ),
            (
                "interface_generic_const_count_by_decl",
                "semantic_interface.members.generic_const_count_by_decl",
            ),
            (
                "interface_member_count",
                "semantic_interface.members.row_count",
            ),
            (
                "interface_member_cursor",
                "semantic_interface.members.cursor",
            ),
            (
                "interface_member_words",
                "semantic_interface.members.records",
            ),
            (
                "interface_member_name_id",
                "semantic_interface.members.name_id",
            ),
            (
                "interface_member_index_by_generic_row",
                "semantic_interface.members.index_by_generic_row",
            ),
            (
                "interface_member_written",
                "semantic_interface.members.written",
            ),
        ] {
            let resource = builder.resource_id(resource_name).ok_or_else(|| {
                anyhow::anyhow!("missing semantic-interface graph resource {resource_name}")
            })?;
            builder
                .add_resource_alias(binding, resource)
                .map_err(anyhow::Error::msg)?;
        }
        let mut root_steps = 0u32;
        let mut covered_depth = 1u64;
        while covered_depth < semantic_hir_rows {
            covered_depth = covered_depth.saturating_mul(16);
            root_steps += 1;
        }
        let root_link_a = builder
            .resource_id("semantic_interface.type.root_link_a")
            .expect("semantic-interface root-link A");
        let root_link_b = builder
            .resource_id("semantic_interface.type.root_link_b")
            .expect("semantic-interface root-link B");
        let root_owner_a = builder
            .resource_id("semantic_interface.type.root_owner_a")
            .expect("semantic-interface root-owner A");
        let root_owner_b = builder
            .resource_id("semantic_interface.type.root_owner_b")
            .expect("semantic-interface root-owner B");
        builder
            .add_resource_alias(
                "interface_type_root_owner",
                if root_steps & 1 == 0 {
                    root_owner_a
                } else {
                    root_owner_b
                },
            )
            .map_err(anyhow::Error::msg)?;
        for (binding, resource) in [
            (
                "interface_name_ref_prefix",
                scans[SemanticInterfaceScan::Names as usize].0.output_prefix,
            ),
            (
                "module_segment_prefix",
                scans[SemanticInterfaceScan::Modules as usize]
                    .0
                    .output_prefix,
            ),
            (
                "module_segment_total",
                scans[SemanticInterfaceScan::Modules as usize].0.total,
            ),
            (
                "interface_signature_type_prefix",
                scans[SemanticInterfaceScan::SignatureTypes as usize]
                    .0
                    .output_prefix,
            ),
            (
                "interface_signature_type_total",
                scans[SemanticInterfaceScan::SignatureTypes as usize]
                    .0
                    .total,
            ),
            (
                "interface_signature_edge_prefix",
                scans[SemanticInterfaceScan::SignatureEdges as usize]
                    .0
                    .output_prefix,
            ),
            (
                "interface_signature_edge_total",
                scans[SemanticInterfaceScan::SignatureEdges as usize]
                    .0
                    .total,
            ),
            (
                "interface_member_prefix",
                scans[SemanticInterfaceScan::Members as usize]
                    .0
                    .output_prefix,
            ),
            (
                "interface_member_total",
                scans[SemanticInterfaceScan::Members as usize].0.total,
            ),
            (
                "interface_type_reverse_prefix",
                scans[SemanticInterfaceScan::TypeOrder as usize]
                    .0
                    .output_prefix,
            ),
            (
                "interface_type_count",
                scans[SemanticInterfaceScan::TypeOrder as usize].0.total,
            ),
            (
                "interface_type_edge_prefix",
                scans[SemanticInterfaceScan::TypeEdges as usize]
                    .0
                    .output_prefix,
            ),
            (
                "interface_type_edge_total",
                scans[SemanticInterfaceScan::TypeEdges as usize].0.total,
            ),
            (
                "interface_edges",
                builder
                    .resource_id("semantic_interface.type.edges")
                    .expect("semantic-interface edge storage"),
            ),
            (
                "interface_edge_written",
                builder
                    .resource_id("semantic_interface.type.edge_written")
                    .expect("semantic-interface edge validation storage"),
            ),
        ] {
            builder
                .add_resource_alias(binding, resource)
                .map_err(anyhow::Error::msg)?;
        }
        for name in [
            "interface_name_byte_words",
            "interface_counts",
            "interface_status",
            "interface_artifact_words",
            "interface_artifact_length",
            "interface_artifact_metadata_readback",
        ] {
            builder
                .add_resource(ResourceDesc {
                    name,
                    domain: ResourceDomain::ArtifactBytes,
                    class: ResourceClass::External,
                    bytes: 1,
                    usage: WorkspaceUsageClass::Storage,
                })
                .map_err(anyhow::Error::msg)?;
        }
        for (binding, upstream_name) in [
            ("name_count_out", "name_scan_total"),
            ("public_decl_count", "interface_public_decl_count"),
            ("public_decl_local_id", "interface_public_decl_local_id"),
            (
                "public_decl_index_by_local",
                "interface_public_decl_index_by_local",
            ),
            (
                "public_decl_index_by_hir",
                "interface_public_decl_index_by_hir",
            ),
        ] {
            builder
                .import_resource_alias_from(
                    upstream_graph,
                    binding,
                    upstream_name,
                    AccessMode::Read,
                )
                .map_err(anyhow::Error::msg)?;
        }
        builder
            .import_resource_alias_from(
                upstream_graph,
                "hir_active_dispatch_args",
                "hir_active_dispatch_args",
                AccessMode::Read,
            )
            .map_err(anyhow::Error::msg)?;
        const IDENTITY_KERNELS: &[&str] = &[
            "type_checker/interface/00_identity_sizes",
            "type_checker/interface/01_identity_records",
            "type_checker/interface/02_identity_bytes",
            "type_checker/interface/artifact/materialize",
        ];
        const TOPOLOGY_KERNELS: &[&str] = &[
            "type_checker/interface/type_topology/00_init",
            "type_checker/interface/type_topology/01_attach_unary",
            "type_checker/interface/type_topology/02_seed_declarations",
            "type_checker/interface/type_topology/02b_seed_params",
            "type_checker/interface/type_topology/02c_seed_fields",
            "type_checker/interface/type_topology/02d_seed_variants",
            "type_checker/interface/type_topology/03_root_init",
            "type_checker/interface/type_topology/05_mark_reverse",
            "type_checker/interface/type_topology/06_scatter",
            "type_checker/interface/type_topology/07_validate",
            "type_checker/interface/type_topology/08_edge_counts",
            "type_checker/interface/type_topology/09_edge_scatter",
            "type_checker/interface/type_topology/10_resolve_local_decl",
            "type_checker/interface/type_topology/11_classify_path",
            "type_checker/interface/type_topology/12_type_records",
            "type_checker/interface/type_topology/13_array_lengths",
            "type_checker/interface/signature/00_flags",
            "type_checker/interface/signature/01_totals",
            "type_checker/interface/signature/01b_direct_types",
            "type_checker/interface/signature/01c_synthetic_types",
            "type_checker/interface/signature/02_param_edges",
            "type_checker/interface/signature/02b_variant_payload_edges",
            "type_checker/interface/signature/03_return_edges",
            "type_checker/interface/members/00_variant_counts",
            "type_checker/interface/members/00b_generic_counts",
            "type_checker/interface/members/00c_method_counts",
            "type_checker/interface/members/01_counts",
            "type_checker/interface/members/02_scatter_hir",
            "type_checker/interface/members/03_scatter_generic",
            "type_checker/interface/members/04_normalize_types",
        ];
        builder
            .import_reflected_resources_from(upstream_graph, kernels, IDENTITY_KERNELS)
            .map_err(anyhow::Error::msg)?;
        builder
            .import_reflected_resources_from(upstream_graph, kernels, TOPOLOGY_KERNELS)
            .map_err(anyhow::Error::msg)?;
        macro_rules! add_kernel {
            ($name:literal, $kernel:literal, $domain:expr) => {
                builder
                    .add_kernel_pass_by_name(
                        $name,
                        CompilerPhase::TypeCheck,
                        $domain,
                        kernels,
                        $kernel,
                        &[],
                    )
                    .map_err(anyhow::Error::msg)?
            };
            ($name:literal, $kernel:literal) => {
                add_kernel!($name, $kernel, ResourceDomain::Types)
            };
        }
        macro_rules! add_kernel_writes {
            ($name:literal, $kernel:literal, $domain:expr, $(
                $binding:literal => $resource:literal
            ),+ $(,)?) => {{
                let overrides = [$(ReflectedResourceBinding {
                    binding: $binding,
                    resource: builder
                        .resource_id($resource)
                        .expect("semantic-interface initialized resource"),
                    mode: Some(AccessMode::Write),
                }),+];
                builder
                    .add_kernel_pass_by_name(
                        $name,
                        CompilerPhase::TypeCheck,
                        $domain,
                        kernels,
                        $kernel,
                        &overrides,
                    )
                    .map_err(anyhow::Error::msg)?
            }};
            ($name:literal, $kernel:literal, $(
                $binding:literal => $resource:literal
            ),+ $(,)?) => {
                add_kernel_writes!(
                    $name,
                    $kernel,
                    ResourceDomain::Types,
                    $($binding => $resource),+
                )
            };
        }
        macro_rules! add_scan {
            ($scan:expr) => {{
                let index = $scan as usize;
                let (resources, passes) = scans[index];
                builder
                    .add_fragment(PrefixScanGraph {
                        phase: CompilerPhase::TypeCheck,
                        dispatch_domain: match $scan {
                            SemanticInterfaceScan::Names => ResourceDomain::Bytes,
                            SemanticInterfaceScan::Modules | SemanticInterfaceScan::Members => {
                                ResourceDomain::Declarations
                            }
                            _ => ResourceDomain::Types,
                        },
                        hierarchy_levels: prefix_scan_hierarchy_levels(
                            capacities[index].div_ceil(256),
                        ),
                        passes,
                        resources,
                    })
                    .map_err(anyhow::Error::msg)?;
            }};
        }
        macro_rules! add_clear {
            ($name:expr, $binding:literal, $resource:literal) => {{
                let resource = builder
                    .resource_id($resource)
                    .expect("semantic-interface clear resource");
                builder
                    .add_buffer_clear_pass($name, CompilerPhase::TypeCheck, $binding, resource)
                    .map_err(anyhow::Error::msg)?
            }};
        }

        // Passes are declared in the same order in which the recorder submits
        // them. This order is the source of both dependency edges and phase-
        // local workspace lifetimes, so scans sit immediately after the
        // operations that produce their inputs.
        add_clear!(
            SEMANTIC_INTERFACE_EDGE_WRITTEN_CLEAR_PASS,
            "interface_type_edge_written",
            "semantic_interface.type.edge_written"
        );
        add_clear!(
            SEMANTIC_INTERFACE_FIELD_COUNT_CLEAR_PASS,
            "interface_field_count_by_hir",
            "semantic_interface.members.field_count_by_hir"
        );
        add_clear!(
            SEMANTIC_INTERFACE_VARIANT_COUNT_CLEAR_PASS,
            "interface_variant_count_by_hir",
            "semantic_interface.members.variant_count_by_hir"
        );
        add_clear!(
            SEMANTIC_INTERFACE_GENERIC_TYPE_COUNT_CLEAR_PASS,
            "interface_generic_type_count_by_decl",
            "semantic_interface.members.generic_type_count_by_decl"
        );
        add_clear!(
            SEMANTIC_INTERFACE_GENERIC_CONST_COUNT_CLEAR_PASS,
            "interface_generic_const_count_by_decl",
            "semantic_interface.members.generic_const_count_by_decl"
        );
        add_clear!(
            SEMANTIC_INTERFACE_MEMBER_WRITTEN_CLEAR_PASS,
            "interface_member_written",
            "semantic_interface.members.written"
        );
        builder
            .add_kernel_initializer_by_name(
                "type_check.interface.type_topology.init",
                CompilerPhase::TypeCheck,
                ResourceDomain::Types,
                kernels,
                "type_checker/interface/type_topology/00_init",
            )
            .map_err(anyhow::Error::msg)?;
        add_kernel!(
            "type_check.interface.type_topology.attach_unary",
            "type_checker/interface/type_topology/01_attach_unary"
        );
        let direct_type_hir = builder
            .resource_id("semantic_interface.type.direct_hir_by_decl")
            .expect("semantic-interface direct declaration type");
        builder
            .add_kernel_pass_by_name(
                "type_check.interface.type_topology.seed_declarations",
                CompilerPhase::TypeCheck,
                ResourceDomain::Types,
                kernels,
                "type_checker/interface/type_topology/02_seed_declarations",
                &[ReflectedResourceBinding {
                    binding: "interface_decl_direct_type_hir",
                    resource: direct_type_hir,
                    mode: Some(AccessMode::Write),
                }],
            )
            .map_err(anyhow::Error::msg)?;
        for (name, kernel) in [
            (
                "type_check.interface.type_topology.seed_params",
                "type_checker/interface/type_topology/02b_seed_params",
            ),
            (
                "type_check.interface.type_topology.seed_fields",
                "type_checker/interface/type_topology/02c_seed_fields",
            ),
            (
                "type_check.interface.type_topology.seed_variants",
                "type_checker/interface/type_topology/02d_seed_variants",
            ),
        ] {
            builder
                .add_kernel_pass_by_name(
                    name,
                    CompilerPhase::TypeCheck,
                    ResourceDomain::Types,
                    kernels,
                    kernel,
                    &[],
                )
                .map_err(anyhow::Error::msg)?;
        }
        builder
            .add_kernel_pass_by_name(
                "type_check.interface.type_topology.root_init",
                CompilerPhase::TypeCheck,
                ResourceDomain::Types,
                kernels,
                "type_checker/interface/type_topology/03_root_init",
                &[
                    ReflectedResourceBinding {
                        binding: "interface_type_root_link",
                        resource: root_link_a,
                        mode: Some(AccessMode::Write),
                    },
                    ReflectedResourceBinding {
                        binding: "interface_type_root_owner",
                        resource: root_owner_a,
                        mode: Some(AccessMode::Write),
                    },
                ],
            )
            .map_err(anyhow::Error::msg)?;
        for (step, &name) in SEMANTIC_INTERFACE_ROOT_STEP_PASSES
            .iter()
            .take(root_steps as usize)
            .enumerate()
        {
            let (link_in, owner_in, link_out, owner_out) = if step & 1 == 0 {
                (root_link_a, root_owner_a, root_link_b, root_owner_b)
            } else {
                (root_link_b, root_owner_b, root_link_a, root_owner_a)
            };
            builder
                .add_kernel_pass_by_name(
                    name,
                    CompilerPhase::TypeCheck,
                    ResourceDomain::Types,
                    kernels,
                    "type_checker/interface/type_topology/04_root_step",
                    &[
                        ReflectedResourceBinding {
                            binding: "interface_type_root_link_in",
                            resource: link_in,
                            mode: None,
                        },
                        ReflectedResourceBinding {
                            binding: "interface_type_root_owner_in",
                            resource: owner_in,
                            mode: None,
                        },
                        ReflectedResourceBinding {
                            binding: "interface_type_root_link_out",
                            resource: link_out,
                            mode: Some(AccessMode::Write),
                        },
                        ReflectedResourceBinding {
                            binding: "interface_type_root_owner_out",
                            resource: owner_out,
                            mode: Some(AccessMode::Write),
                        },
                    ],
                )
                .map_err(anyhow::Error::msg)?;
        }

        let reverse_flag = builder
            .resource_id("semantic_interface.type.reverse_flag")
            .expect("semantic-interface reverse flag");
        builder
            .add_kernel_pass_by_name(
                "type_check.interface.type_topology.mark_reverse",
                CompilerPhase::TypeCheck,
                ResourceDomain::Types,
                kernels,
                "type_checker/interface/type_topology/05_mark_reverse",
                &[ReflectedResourceBinding {
                    binding: "interface_type_reverse_flag",
                    resource: reverse_flag,
                    mode: Some(AccessMode::Write),
                }],
            )
            .map_err(anyhow::Error::msg)?;
        add_scan!(SemanticInterfaceScan::TypeOrder);
        let hir_order = builder
            .resource_id("semantic_interface.type.hir_order")
            .expect("semantic-interface HIR order");
        builder
            .add_kernel_pass_by_name(
                "type_check.interface.type_topology.scatter",
                CompilerPhase::TypeCheck,
                ResourceDomain::Types,
                kernels,
                "type_checker/interface/type_topology/06_scatter",
                &[ReflectedResourceBinding {
                    binding: "interface_type_hir_order",
                    resource: hir_order,
                    mode: Some(AccessMode::Write),
                }],
            )
            .map_err(anyhow::Error::msg)?;
        add_kernel_writes!(
            "type_check.interface.type_topology.edge_counts",
            "type_checker/interface/type_topology/08_edge_counts",
            "interface_type_edge_count" => "semantic_interface.type.edge_count"
        );
        add_scan!(SemanticInterfaceScan::TypeEdges);
        add_kernel_writes!(
            "type_check.interface.type_topology.edge_scatter",
            "type_checker/interface/type_topology/09_edge_scatter",
            "interface_type_edges" => "semantic_interface.type.edges"
        );
        add_kernel_writes!(
            "type_check.interface.type_topology.resolve_local_decl",
            "type_checker/interface/type_topology/10_resolve_local_decl",
            "interface_type_local_decl_by_hir" => "semantic_interface.type.local_decl_by_hir"
        );
        add_kernel_writes!(
            "type_check.interface.type_topology.classify_path",
            "type_checker/interface/type_topology/11_classify_path",
            "interface_type_path_classification" => "semantic_interface.type.path_classification"
        );
        add_kernel_writes!(
            "type_check.interface.type_topology.type_records",
            "type_checker/interface/type_topology/12_type_records",
            "interface_types" => "semantic_interface.type.types"
        );
        for (name, kernel) in [
            (
                "type_check.interface.type_topology.array_lengths",
                "type_checker/interface/type_topology/13_array_lengths",
            ),
            (
                "type_check.interface.type_topology.validate",
                "type_checker/interface/type_topology/07_validate",
            ),
        ] {
            builder
                .add_kernel_pass_by_name(
                    name,
                    CompilerPhase::TypeCheck,
                    ResourceDomain::Types,
                    kernels,
                    kernel,
                    &[],
                )
                .map_err(anyhow::Error::msg)?;
        }
        add_kernel_writes!(
            "type_check.interface.signature.flags",
            "type_checker/interface/signature/00_flags",
            "interface_signature_type_flag" => "semantic_interface.signature.type_flag",
            "interface_signature_edge_count" => "semantic_interface.signature.edge_count",
            "interface_signature_type_by_decl" => "semantic_interface.signature.type_by_decl"
        );
        add_scan!(SemanticInterfaceScan::SignatureTypes);
        add_scan!(SemanticInterfaceScan::SignatureEdges);
        add_kernel_writes!(
            "type_check.interface.signature.totals",
            "type_checker/interface/signature/01_totals",
            "interface_complete_type_count" => "semantic_interface.complete_type_count",
            "interface_complete_edge_total" => "semantic_interface.complete_edge_total"
        );
        for (name, kernel) in [
            (
                "type_check.interface.signature.direct_types",
                "type_checker/interface/signature/01b_direct_types",
            ),
            (
                "type_check.interface.signature.synthetic_types",
                "type_checker/interface/signature/01c_synthetic_types",
            ),
            (
                "type_check.interface.signature.param_edges",
                "type_checker/interface/signature/02_param_edges",
            ),
            (
                "type_check.interface.signature.variant_payload_edges",
                "type_checker/interface/signature/02b_variant_payload_edges",
            ),
            (
                "type_check.interface.signature.return_edges",
                "type_checker/interface/signature/03_return_edges",
            ),
            (
                "type_check.interface.members.variant_counts",
                "type_checker/interface/members/00_variant_counts",
            ),
            (
                "type_check.interface.members.generic_counts",
                "type_checker/interface/members/00b_generic_counts",
            ),
        ] {
            builder
                .add_kernel_pass_by_name(
                    name,
                    CompilerPhase::TypeCheck,
                    ResourceDomain::Types,
                    kernels,
                    kernel,
                    &[],
                )
                .map_err(anyhow::Error::msg)?;
        }
        add_kernel_writes!(
            "type_check.interface.members.counts",
            "type_checker/interface/members/01_counts",
            "interface_member_count" => "semantic_interface.members.row_count",
            "interface_member_cursor" => "semantic_interface.members.cursor"
        );
        add_kernel!(
            "type_check.interface.members.method_counts",
            "type_checker/interface/members/00c_method_counts"
        );
        add_scan!(SemanticInterfaceScan::Members);
        add_kernel_writes!(
            "type_check.interface.members.scatter_hir",
            "type_checker/interface/members/02_scatter_hir",
            "interface_member_words" => "semantic_interface.members.records",
            "interface_member_name_id" => "semantic_interface.members.name_id"
        );
        add_kernel_writes!(
            "type_check.interface.members.scatter_generic",
            "type_checker/interface/members/03_scatter_generic",
            "interface_member_index_by_generic_row" => "semantic_interface.members.index_by_generic_row"
        );
        for (name, kernel) in [(
            "type_check.interface.members.normalize_types",
            "type_checker/interface/members/04_normalize_types",
        )] {
            builder
                .add_kernel_pass_by_name(
                    name,
                    CompilerPhase::TypeCheck,
                    ResourceDomain::Types,
                    kernels,
                    kernel,
                    &[],
                )
                .map_err(anyhow::Error::msg)?;
        }
        for &name in SEMANTIC_INTERFACE_ACTIVE_HIR_PASSES.iter().chain(
            SEMANTIC_INTERFACE_ROOT_STEP_PASSES
                .iter()
                .take(root_steps as usize),
        ) {
            builder
                .add_indirect_dispatch(name, "hir_active_dispatch_args")
                .map_err(anyhow::Error::msg)?;
        }

        add_clear!(
            SEMANTIC_INTERFACE_NAME_REF_CLEAR_PASS,
            "interface_name_ref_len",
            "semantic_interface.name_ref_len"
        );
        add_clear!(
            SEMANTIC_INTERFACE_NAME_BYTES_CLEAR_PASS,
            "interface_name_byte_words",
            "interface_name_byte_words"
        );
        add_clear!(
            SEMANTIC_INTERFACE_COUNTS_CLEAR_PASS,
            "interface_counts",
            "interface_counts"
        );
        add_scan!(SemanticInterfaceScan::Modules);
        add_kernel!(
            "type_check.interface.identity_sizes",
            "type_checker/interface/00_identity_sizes",
            ResourceDomain::Declarations
        );
        add_scan!(SemanticInterfaceScan::Names);
        add_kernel_writes!(
            "type_check.interface.identity_records",
            "type_checker/interface/01_identity_records",
            ResourceDomain::Declarations,
            "interface_modules" => "semantic_interface.modules",
            "interface_module_segments" => "semantic_interface.module_segments",
            "interface_declaration_words" => "semantic_interface.declarations"
        );
        add_kernel!(
            "type_check.interface.identity_bytes",
            "type_checker/interface/02_identity_bytes",
            ResourceDomain::Bytes
        );
        add_kernel!(
            "type_check.interface.artifact",
            "type_checker/interface/artifact/materialize",
            ResourceDomain::ArtifactBytes
        );
        let artifact_length = builder
            .resource_id("interface_artifact_length")
            .expect("semantic-interface artifact length");
        let interface_status = builder
            .resource_id("interface_status")
            .expect("semantic-interface status");
        let metadata_readback = builder
            .resource_id("interface_artifact_metadata_readback")
            .expect("semantic-interface metadata readback");
        builder
            .add_buffer_copy_pass(
                SEMANTIC_INTERFACE_ARTIFACT_LENGTH_READBACK_PASS,
                CompilerPhase::TypeCheck,
                "interface_artifact_length",
                artifact_length,
                "interface_artifact_metadata_readback",
                metadata_readback,
            )
            .map_err(anyhow::Error::msg)?;
        builder
            .add_buffer_copy_pass(
                SEMANTIC_INTERFACE_STATUS_READBACK_PASS,
                CompilerPhase::TypeCheck,
                "interface_status",
                interface_status,
                "interface_artifact_metadata_readback",
                metadata_readback,
            )
            .map_err(anyhow::Error::msg)?;
        builder.add_registered_pass_arena_conflicts();
        let graph = builder.build().map_err(anyhow::Error::msg)?;
        let (resources, passes): (Vec<_>, Vec<_>) = scans.into_iter().unzip();
        Ok(SemanticInterfaceScanPlan {
            graph,
            scan_capacity,
            scratch,
            resources: resources
                .try_into()
                .expect("seven semantic-interface scans"),
            passes: passes.try_into().expect("seven semantic-interface scans"),
        })
    }

    fn materialize(device: &wgpu::Device, plan: SemanticInterfaceScanPlan) -> Result<Self> {
        let SemanticInterfaceScanPlan {
            graph,
            scan_capacity,
            scratch,
            resources,
            passes,
        } = plan;
        let materialized = MaterializedCompilerGraph::new_with_upstream_storage(
            device,
            "semantic_interface",
            graph,
            &[],
        )
        .map_err(anyhow::Error::msg)?;
        debug_assert!(materialized.graph().workspace_plan().slots.len() >= 4);
        let alias = |resource, rows| {
            materialized
                .buffer::<u32>(
                    materialized
                        .graph()
                        .resource(resource)
                        .expect("scan resource")
                        .name,
                )
                .map(|buffer| buffer.alias(rows))
        };
        let block_capacity = scan_capacity.div_ceil(256) as usize;
        let scratch_buffers = PrefixScanWorkspace {
            local_prefix: alias(scratch.local_prefix, scan_capacity as usize)?,
            block_sum: alias(scratch.block_sum, block_capacity)?,
            block_prefix: alias(scratch.block_prefix, block_capacity)?,
        };
        let bindings = materialized.bindings()?;
        Ok(Self {
            materialized,
            bindings,
            scratch: scratch_buffers,
            resources,
            passes,
        })
    }

    fn workspace(&self) -> PrefixScanWorkspace<&LaniusBuffer<u32>> {
        self.scratch.as_ref()
    }

    fn outputs(
        &self,
        scan: SemanticInterfaceScan,
    ) -> Result<(LaniusBuffer<u32>, LaniusBuffer<u32>)> {
        let resources = self.resources[scan as usize];
        let buffer = |resource| {
            self.materialized.buffer::<u32>(
                self.materialized
                    .graph()
                    .resource(resource)
                    .expect("semantic-interface scan resource")
                    .name,
            )
        };
        Ok((buffer(resources.output_prefix)?, buffer(resources.total)?))
    }

    fn buffer(&self, name: &str) -> Result<LaniusBuffer<u32>> {
        self.materialized.buffer(name)
    }

    fn register_bindings<'a>(&'a self, resources: &mut ResourceMap<'a>) {
        resources.attach_graph(self.materialized.graph(), self.materialized.allocations());
        resources.register_graph_bindings(self.materialized.graph(), &self.bindings);
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
        ]
        .map(|(resource, registered)| {
            (
                self.materialized
                    .graph()
                    .resource(resource)
                    .expect("scan resource")
                    .name,
                registered,
            )
        });
        for pass_name in self.passes[index].names() {
            if let Some(pass) = self.materialized.graph().pass_id(pass_name) {
                let bindings = resources.graph_bindings_with_aliases(
                    self.materialized.graph(),
                    pass_name,
                    &aliases,
                )?;
                self.materialized
                    .allocations()
                    .validate_pass_bindings(self.materialized.graph(), pass, &bindings)
                    .map_err(anyhow::Error::msg)?;
            }
        }
        Ok(())
    }
}

impl crate::gpu::operations::ComputeGraph for SemanticInterfaceScanGraph {
    fn graph(&self) -> &CompilerGraph {
        self.materialized.graph()
    }

    fn allocations(&self) -> &CompilerGraphAllocations {
        self.materialized.allocations()
    }
}

impl TypeCheckCompilerGraph {
    pub(super) fn record_phase_reset(&self, encoder: &mut wgpu::CommandEncoder) {
        self.materialized.record_phase_reset(encoder);
    }

    pub(super) fn register_bindings<'a>(
        &'a self,
        bindings: &'a CompilerGraphBindings,
        resources: &mut ResourceMap<'a>,
    ) {
        resources.attach_graph(self.materialized.graph(), self.materialized.allocations());
        resources.register_graph_bindings(self.materialized.graph(), bindings);
    }

    pub(super) fn prefix_scan_workspace(
        &self,
        names: PrefixScanWorkspace<&str>,
    ) -> Result<PrefixScanWorkspace<LaniusBuffer<u32>>> {
        Ok(PrefixScanWorkspace {
            local_prefix: self.materialized.u32_buffer(names.local_prefix)?,
            block_sum: self.materialized.u32_buffer(names.block_sum)?,
            block_prefix: self.materialized.u32_buffer(names.block_prefix)?,
        })
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
        dependency_capacity: DependencyWorkspaceCapacity,
        parser_feature_flags: u32,
        semantic_interface_required: bool,
        passes: &TypeCheckPasses,
        upstream_workspace: &[crate::gpu::buffers::TrackedBufferView<'_>],
    ) -> Result<Self> {
        let timing = crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false);
        let started = std::time::Instant::now();
        let mut last = started;
        macro_rules! stamp {
            ($stage:literal) => {
                if timing {
                    let now = std::time::Instant::now();
                    eprintln!(
                        "[gpu_compile_host_timer] typecheck.graph.{}: {:.3}ms (total {:.3}ms)",
                        $stage,
                        now.duration_since(last).as_secs_f64() * 1000.0,
                        now.duration_since(started).as_secs_f64() * 1000.0,
                    );
                    last = now;
                }
            };
        }
        macro_rules! final_stamp {
            ($stage:literal) => {
                if timing {
                    let now = std::time::Instant::now();
                    eprintln!(
                        "[gpu_compile_host_timer] typecheck.graph.{}: {:.3}ms (total {:.3}ms)",
                        $stage,
                        now.duration_since(last).as_secs_f64() * 1000.0,
                        now.duration_since(started).as_secs_f64() * 1000.0,
                    );
                }
            };
        }
        let mut graph = build_graph(
            hir_capacity,
            token_capacity,
            source_file_capacity,
            module_record_capacity,
            call_param_capacity,
            call_arg_capacity,
            generic_claim_capacity,
            predicate_capacity,
            dependency_capacity,
            parser_feature_flags,
            passes,
        )
        .map_err(anyhow::Error::msg)?;
        stamp!("build");
        let semantic_interface_plan = semantic_interface_required
            .then(|| {
                SemanticInterfaceScanGraph::build(
                    hir_capacity,
                    token_capacity,
                    source_file_capacity,
                    module_record_capacity,
                    passes,
                    &graph,
                )
            })
            .transpose()?;
        stamp!("semantic_interface_build");
        if let Some(plan) = semantic_interface_plan.as_ref() {
            graph
                .retain_resources_imported_by(&plan.graph)
                .map_err(anyhow::Error::msg)?;
        }
        stamp!("retain_imports");
        graph
            .validate_assigned_pass_reflections(passes)
            .map_err(anyhow::Error::msg)?;
        stamp!("validate_reflection");

        let materialized = MaterializedCompilerGraph::new_with_upstream_storage_excluding_outputs(
            device,
            "type_check",
            graph,
            upstream_workspace,
        )
        .map_err(anyhow::Error::msg)?;
        stamp!("materialize");
        let semantic_interface_scans = semantic_interface_plan
            .map(|plan| SemanticInterfaceScanGraph::materialize(device, plan))
            .transpose()?;
        final_stamp!("semantic_interface_materialize");
        Ok(Self {
            materialized,
            semantic_interface_scans,
        })
    }

    pub(super) fn semantic_interface_scan_workspace(
        &self,
    ) -> Result<PrefixScanWorkspace<&LaniusBuffer<u32>>> {
        Ok(self.semantic_interface_scans()?.workspace())
    }

    pub(super) fn semantic_interface_scan_outputs(
        &self,
        scan: SemanticInterfaceScan,
    ) -> Result<(LaniusBuffer<u32>, LaniusBuffer<u32>)> {
        self.semantic_interface_scans()?.outputs(scan)
    }

    pub(super) fn semantic_interface_buffer(&self, name: &str) -> Result<LaniusBuffer<u32>> {
        self.semantic_interface_scans()?.buffer(name)
    }

    pub(super) fn validate_semantic_interface_scan(
        &self,
        scan: SemanticInterfaceScan,
        resources: &ResourceMap<'_>,
    ) -> Result<()> {
        self.semantic_interface_scans()?.validate(scan, resources)
    }

    pub(super) fn register_semantic_interface_bindings<'a>(
        &'a self,
        resources: &mut ResourceMap<'a>,
    ) -> Result<()> {
        self.semantic_interface_scans()?
            .register_bindings(resources);
        Ok(())
    }

    pub(super) fn semantic_interface_graph(
        &self,
    ) -> Result<&impl crate::gpu::operations::ComputeGraph> {
        self.semantic_interface_scans()
    }

    pub(super) fn semantic_interface_scan_passes(
        &self,
        scan: SemanticInterfaceScan,
    ) -> Result<PrefixScanGraphPasses> {
        Ok(self.semantic_interface_scans()?.passes[scan as usize])
    }

    /// Returns the root-walk schedule materialized for the resident graph
    /// capacity. Recording must use this stable count even when the active job
    /// is smaller: its parity selects which ping-pong buffer downstream graph
    /// passes consume.
    pub(super) fn semantic_interface_root_step_count(&self) -> Result<usize> {
        Ok(self.semantic_interface_scans()?.root_step_count())
    }

    fn semantic_interface_scans(&self) -> Result<&SemanticInterfaceScanGraph> {
        self.semantic_interface_scans.as_ref().ok_or_else(|| {
            anyhow::anyhow!("semantic-interface workspace was not requested for this job")
        })
    }
}

impl crate::gpu::operations::ComputeGraph for TypeCheckCompilerGraph {
    fn graph(&self) -> &CompilerGraph {
        self.materialized.graph()
    }

    fn allocations(&self) -> &CompilerGraphAllocations {
        self.materialized.allocations()
    }
}

impl std::ops::Deref for TypeCheckCompilerGraph {
    type Target = MaterializedCompilerGraph;

    fn deref(&self) -> &Self::Target {
        &self.materialized
    }
}

fn prefix_scan_hierarchy_levels(block_count: u64) -> u32 {
    crate::gpu::scan::hierarchical_scan_levels(u32::try_from(block_count).unwrap_or(u32::MAX))
        .len()
        .try_into()
        .unwrap_or(u32::MAX)
}

#[derive(Clone, Copy)]
struct ControlHierarchyGraphSpec {
    up_first: &'static str,
    up_rest: &'static str,
    down: &'static str,
    up_kernel: &'static str,
    down_kernel: &'static str,
}

/// Registers the actual hierarchy dispatch sequence used by the fixed-size
/// control-flow scans. The first up-sweep initializes the scan workspace;
/// later levels and the down-sweep carry it through repeated graph regions.
fn add_control_hierarchy_passes(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    spec: ControlHierarchyGraphSpec,
    hierarchy_levels: u32,
    block_sum: ResourceId,
    scan_prefix: ResourceId,
    scan_hierarchy: ResourceId,
    block_prefix: ResourceId,
) -> Result<(), String> {
    if hierarchy_levels == 0 {
        return Err(format!(
            "control hierarchy {} requires at least one level",
            spec.up_first,
        ));
    }
    let binding = |binding, resource, mode| ReflectedResourceBinding {
        binding,
        resource,
        mode: Some(mode),
    };
    graph.add_kernel_pass_by_name(
        spec.up_first,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        spec.up_kernel,
        &[
            binding("block_sum", block_sum, AccessMode::Read),
            binding("block_prefix", block_prefix, AccessMode::Write),
            binding("scan_prefix", scan_prefix, AccessMode::Write),
            binding("scan_hierarchy", scan_hierarchy, AccessMode::Write),
        ],
    )?;
    if hierarchy_levels > 1 {
        graph.add_kernel_pass_by_name(
            spec.up_rest,
            CompilerPhase::TypeCheck,
            ResourceDomain::Tokens,
            kernels,
            spec.up_kernel,
            &[
                binding("block_sum", block_sum, AccessMode::Read),
                binding("block_prefix", block_prefix, AccessMode::ReadWrite),
                binding("scan_prefix", scan_prefix, AccessMode::ReadWrite),
                binding("scan_hierarchy", scan_hierarchy, AccessMode::ReadWrite),
            ],
        )?;
        graph.repeat_pass_range(hierarchy_levels - 1, spec.up_rest, spec.up_rest)?;
        graph.add_kernel_pass_by_name(
            spec.down,
            CompilerPhase::TypeCheck,
            ResourceDomain::Tokens,
            kernels,
            spec.down_kernel,
            &[
                binding("block_prefix", block_prefix, AccessMode::ReadWrite),
                binding("scan_prefix", scan_prefix, AccessMode::ReadWrite),
                binding("scan_hierarchy", scan_hierarchy, AccessMode::ReadWrite),
            ],
        )?;
        graph.repeat_pass_range(hierarchy_levels - 1, spec.down, spec.down)?;
    }
    Ok(())
}

fn add_dependency_type_index_passes(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    names: DependencyTypeIndexPassNames,
    jump_rounds: u32,
    roots_a: ResourceId,
    roots_b: ResourceId,
    subtree_a: ResourceId,
    subtree_b: ResourceId,
    declaration_generic_arity: ResourceId,
    declaration_field_count: ResourceId,
) -> Result<(), String> {
    graph.add_kernel_pass_by_name(
        names.initialize,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        "type_checker/dependencies/09_init_canonical_type_roots",
        reflected_bindings![
            "canonical_type_roots" => roots_a: Write,
            "canonical_type_subtree_start" => subtree_a: Write,
        ],
    )?;
    let add_jump =
        |graph: &mut CompilerGraphBuilder, name, roots_in, roots_out, subtree_in, subtree_out| {
            graph
                .add_kernel_pass_by_name(
                    name,
                    CompilerPhase::TypeCheck,
                    ResourceDomain::Declarations,
                    kernels,
                    "type_checker/dependencies/10_jump_canonical_type_roots",
                    reflected_bindings![
                        "canonical_type_roots_in" => roots_in: Read,
                        "canonical_type_roots_out" => roots_out: Write,
                        "canonical_type_subtree_start_in" => subtree_in: Read,
                        "canonical_type_subtree_start_out" => subtree_out: Write,
                    ],
                )
                .map(|_| ())
        };
    if jump_rounds >= 2 {
        add_jump(
            graph,
            names.jump_a_to_b,
            roots_a,
            roots_b,
            subtree_a,
            subtree_b,
        )?;
        add_jump(
            graph,
            names.jump_b_to_a,
            roots_b,
            roots_a,
            subtree_b,
            subtree_a,
        )?;
        graph.repeat_pass_range(jump_rounds / 2, names.jump_a_to_b, names.jump_b_to_a)?;
    }
    if jump_rounds % 2 != 0 {
        add_jump(
            graph,
            names.jump_final_a_to_b,
            roots_a,
            roots_b,
            subtree_a,
            subtree_b,
        )?;
    }
    graph.add_kernel_pass_by_name(
        names.clear_generic_arity,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        "type_checker/dependencies/12_clear_declaration_generic_arity",
        reflected_bindings![
            "declaration_generic_arity" => declaration_generic_arity: Write,
            "declaration_field_count" => declaration_field_count: Write,
        ],
    )?;
    graph.add_kernel_pass_by_name(
        names.count_generic_arity,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        "type_checker/dependencies/13_count_declaration_generic_arity",
        reflected_bindings![
            "declaration_generic_arity" => declaration_generic_arity: ReadWrite,
            "declaration_field_count" => declaration_field_count: ReadWrite,
        ],
    )?;
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn add_dependency_page_replay_passes(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    names: DependencyPagePassNames,
    visible_scan: PrefixScanSpec,
    record_scan_levels: u32,
    jump_rounds: u32,
    roots_a: ResourceId,
    roots_b: ResourceId,
    subtree_a: ResourceId,
    subtree_b: ResourceId,
    final_roots: ResourceId,
    declaration_generic_arity: ResourceId,
    declaration_field_count: ResourceId,
    resolved_type_decl: ResourceId,
) -> Result<(), String> {
    for operation in [
        DEPENDENCY_MODULE_LOOKUP_CLEAR.with_name(names.clear_module_lookup),
        DEPENDENCY_MODULE_LOOKUP_BUILD.with_name(names.build_module_lookup),
        DEPENDENCY_IMPORTS_RESOLVE.with_name(names.resolve_imports),
        DEPENDENCY_IMPORT_VISIBILITY_COUNT.with_name(names.count_import_visibility),
    ] {
        operation.register_kernel(graph, kernels)?;
    }
    visible_scan.register(graph, record_scan_levels)?;
    for operation in [
        DEPENDENCY_IMPORT_VISIBILITY_SCATTER.with_name(names.scatter_import_visibility),
        DEPENDENCY_VISIBLE_LOOKUP_CLEAR.with_name(names.clear_visible_lookup),
        DEPENDENCY_VISIBLE_LOOKUP_BUILD.with_name(names.build_visible_lookup),
        DEPENDENCY_TYPE_PATHS_RESOLVE.with_name(names.resolve_type_paths),
        DEPENDENCY_VALUE_PATHS_RESOLVE.with_name(names.resolve_value_paths),
    ] {
        operation.register_kernel(graph, kernels)?;
    }
    add_dependency_type_index_passes(
        graph,
        kernels,
        names.type_index,
        jump_rounds,
        roots_a,
        roots_b,
        subtree_a,
        subtree_b,
        declaration_generic_arity,
        declaration_field_count,
    )?;
    graph.add_kernel_pass_by_name(
        names.project_types,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        DEPENDENCY_TYPES_PROJECT.kernel,
        reflected_bindings![
            "resolved_dependency_decl" => resolved_type_decl: Read,
            "canonical_type_roots" => final_roots: Read,
        ],
    )?;
    graph.add_indirect_dispatch(names.project_types, "path_dispatch_args")?;
    Ok(())
}

fn add_type_subtree_passes(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    scan_passes: PrefixScanGraphPasses,
    dispatch_name: &'static str,
    indirect_name: &'static str,
    hierarchy_levels: u32,
) -> Result<(), String> {
    let type_subtree_compare_count_out = graph
        .resource_id("type_subtree_compare_count_out")
        .ok_or_else(|| {
            "type-subtree operation requires graph resource `type_subtree_compare_count_out`"
                .to_owned()
        })?;
    let type_subtree_compare_dispatch_args = graph
        .resource_id("type_subtree_compare_dispatch_args")
        .ok_or_else(|| {
            "type-subtree operation requires graph resource `type_subtree_compare_dispatch_args`"
                .to_owned()
        })?;
    let scan_resources = graph.resolve_prefix_scan_resources(TYPE_SUBTREE_SCAN_RESOURCES)?;
    graph.add_fragment(PrefixScanGraph {
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        hierarchy_levels,
        passes: scan_passes,
        resources: scan_resources,
    })?;
    graph.add_kernel_pass_by_name(
        dispatch_name,
        CompilerPhase::TypeCheck,
        ResourceDomain::DispatchArguments,
        kernels,
        "type_checker/count/dispatch_args",
        reflected_bindings![
            "count_in" => type_subtree_compare_count_out,
            "dispatch_args" => type_subtree_compare_dispatch_args: Write,
        ],
    )?;
    graph.add_kernel_pass_by_name(
        indirect_name,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/conditions/type_subtree",
        &[],
    )?;
    graph.add_indirect_dispatch(indirect_name, "type_subtree_compare_dispatch_args")?;
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
    dependency_capacity: DependencyWorkspaceCapacity,
    parser_feature_flags: u32,
    kernels: &impl crate::gpu::kernels::KernelReflections,
) -> Result<CompilerGraph, String> {
    let hir_rows = u64::from(hir_capacity.max(1));
    let token_rows = u64::from(token_capacity.max(1));
    let module_rows = u64::from(source_file_capacity.max(1));
    let record_rows = u64::from(module_record_capacity.max(1));
    let module_path_key_radix_rows = u64::from(
        source_file_capacity
            .max(module_record_capacity)
            .max(token_capacity)
            .max(1),
    )
    .div_ceil(256)
        * u64::from(RADIX_U8_BUCKET_COUNT);
    let call_arg_rows = u64::from(call_arg_capacity.max(1));
    let call_param_rows = u64::from(call_param_capacity.max(1));
    let predicate_rows = u64::from(predicate_capacity.max(1));
    let hir_blocks = hir_rows.div_ceil(256);
    let token_blocks = token_rows.div_ceil(256);
    let call_arg_blocks = call_arg_rows.div_ceil(256);
    let predicate_blocks = predicate_rows.div_ceil(256);
    let claim_rows = u64::from(generic_claim_capacity.max(1));
    let mut type_alias_root_jump_rounds = 0;
    let mut covered_alias_declarations = 1u64;
    while covered_alias_declarations < record_rows {
        type_alias_root_jump_rounds += 1;
        covered_alias_declarations = covered_alias_declarations.saturating_mul(16);
    }
    let alias_equivalence_rows = u64::from(token_capacity)
        .saturating_add(u64::from(hir_capacity))
        .max(1);
    let mut type_alias_equivalence_rounds = 1;
    let mut covered_alias_equivalence_rows = 16u64;
    while covered_alias_equivalence_rows < alias_equivalence_rows {
        type_alias_equivalence_rounds += 1;
        covered_alias_equivalence_rows = covered_alias_equivalence_rows.saturating_mul(16);
    }
    let dependency_visible_rows = u64::from(dependency_capacity.visible_rows.max(1));
    let dependency_lookup_rows = u64::from(dependency_capacity.lookup_rows.max(1));
    let dependency_type_rows = u64::from(dependency_capacity.type_rows.max(1));
    let dependency_declaration_rows = u64::from(dependency_capacity.declaration_rows.max(1));
    let mut graph = CompilerGraphBuilder::new();
    graph.add_storage(
        "import_target_dependency_module_id",
        ResourceDomain::Declarations,
        if dependency_capacity.visible_rows == 0 {
            ResourceClass::External
        } else {
            ResourceClass::Workspace
        },
        u64::from(module_record_capacity.max(1)) * 4,
    )?;
    graph_resources!(graph, Input {
        compact_hir_count in HirNodes => 4;
        compact_hir_core in HirNodes => hir_rows * 16;
        _compact_hir_links as "compact_hir_links" in HirNodes => hir_rows * 16;
        _compact_hir_payload as "compact_hir_payload" in HirNodes => hir_rows * 16;
        _compact_const_value as "compact_const_value" in HirNodes => hir_rows * 4;
        _compact_const_type as "compact_const_type" in HirNodes => hir_rows * 4;
        compact_hir_semantic_facts in HirNodes =>
            hir_rows * core::mem::size_of::<HirSemanticFacts>() as u64;
        _compact_type_root_owner as "compact_type_root_owner" in HirNodes => hir_rows * 4;
        _compact_type_alias_target as "compact_type_alias_target" in HirNodes => hir_rows * 4;
        _compact_fn_return_type as "compact_fn_return_type" in HirNodes => hir_rows * 4;
        _compact_param_count as "compact_param_count" in Declarations => 4;
        _compact_params as "compact_params" in Declarations =>
            hir_rows * core::mem::size_of::<HirParam>() as u64;
        _compact_call_arg_count as "compact_call_arg_count" in CallArguments => 4;
        _compact_call_args as "compact_call_args" in CallArguments =>
            hir_rows * core::mem::size_of::<HirCallArg>() as u64;
        _compact_hir_expr_parent as "compact_hir_expr_parent" in HirNodes => hir_rows * 4;
        _compact_hir_expr_root as "compact_hir_expr_root" in HirNodes => hir_rows * 4;
        _compact_hir_nearest_loop as "compact_hir_nearest_loop" in HirNodes => hir_rows * 4;
        _compact_hir_nearest_block as "compact_hir_nearest_block" in HirNodes => hir_rows * 4;
        _compact_hir_nearest_control as "compact_hir_nearest_control" in HirNodes => hir_rows * 4;
        _compact_hir_nearest_fn as "compact_hir_nearest_fn" in HirNodes => hir_rows * 4;
        _compact_path_count as "compact_path_count" in HirNodes => 4;
        _compact_paths as "compact_paths" in HirNodes =>
            hir_rows * core::mem::size_of::<HirPath>() as u64;
        _compact_path_segment_count as "compact_path_segment_count" in Tokens => 4;
        _compact_path_segments as "compact_path_segments" in Tokens =>
            token_rows * core::mem::size_of::<HirPathSegment>() as u64;
        _compact_variant_payload_start as "compact_variant_payload_start" in Declarations => hir_rows * 4;
        _compact_array_element_start as "compact_array_element_start" in HirNodes => hir_rows * 4;
        _compact_array_element_count as "compact_array_element_count" in HirNodes => hir_rows * 4;
        _compact_array_element_row_count as "compact_array_element_row_count" in Declarations => 4;
        _compact_array_elements as "compact_array_elements" in Declarations =>
            hir_rows * core::mem::size_of::<HirArrayElement>() as u64;
        _compact_match_arm_count as "compact_match_arm_count" in HirNodes => 4;
        _compact_match_arms as "compact_match_arms" in HirNodes =>
            hir_rows * core::mem::size_of::<HirMatchArm>() as u64;
        _compact_match_payload_start as "compact_match_payload_start" in HirNodes => hir_rows * 4;
        _compact_match_payload_count as "compact_match_payload_count" in HirNodes => hir_rows * 4;
        _compact_match_pattern_payload_count as "compact_match_pattern_payload_count" in HirNodes => hir_rows * 4;
        compact_match_payload_row_count in HirNodes => 4;
        _compact_match_payloads as "compact_match_payloads" in HirNodes =>
            hir_rows * core::mem::size_of::<HirMatchPayload>() as u64;
        _compact_string_count as "compact_string_count" in HirNodes => 4;
        _compact_strings as "compact_strings" in HirNodes =>
            hir_rows * core::mem::size_of::<HirString>() as u64;
        _compact_string_data_words as "compact_string_data_words" in Tokens => token_rows * 4;
        _compact_string_pool_len as "compact_string_pool_len" in HirNodes => 4;
    });

    // Function return references are initialized by the physical type-instance
    // clear and then republished from compact HIR. Their complete type-check
    // lifetime is represented below, so they are ordinary colorable workspace.
    graph_resources!(graph, Workspace {
        _fn_return_ref_tag as "fn_return_ref_tag" in Tokens => token_rows * 4;
        _fn_return_ref_payload as "fn_return_ref_payload" in Tokens => token_rows * 4;
        _type_instance_kind as "type_instance_kind" in Tokens => token_rows * 4;
    });
    graph_resources!(graph, Workspace {
        decl_type_ref_tag in Tokens => token_rows * 4;
        decl_type_ref_payload in Tokens => token_rows * 4;
        _call_dependency_library_id as "call_dependency_library_id" in Tokens => token_rows * 4;
        _call_dependency_unit_id as "call_dependency_unit_id" in Tokens => token_rows * 4;
        _call_dependency_local_index as "call_dependency_local_index" in Tokens => token_rows * 4;
        _call_dependency_host_service as "call_dependency_host_service" in Tokens => token_rows * 4;
    });
    graph_resources!(graph, Input {
        _token_count as "token_count" in Tokens => 4;
        _compact_method_count as "compact_method_count" in Declarations => 4;
        _compact_method_cores as "compact_method_cores" in Declarations =>
            hir_rows * core::mem::size_of::<HirMethodCore>() as u64;
        _compact_method_signatures as "compact_method_signatures" in Declarations =>
            hir_rows * core::mem::size_of::<HirMethodSignature>() as u64;
        _token_words as "token_words" in Tokens => token_rows * 12;
        _source_bytes as "source_bytes" in Bytes => 1;
        _language_symbol_bytes as "language_symbol_bytes" in Bytes => LANGUAGE_SYMBOL_BYTES.len() as u64;
        _language_symbol_start as "language_symbol_start" in Declarations => LANGUAGE_SYMBOL_COUNT as u64 * 4;
        _language_symbol_len as "language_symbol_len" in Declarations => LANGUAGE_SYMBOL_COUNT as u64 * 4;
        _language_decl_symbol_slot as "language_decl_symbol_slot" in Declarations => LANGUAGE_DECL_COUNT as u64 * 4;
        _language_decl_kind as "language_decl_kind" in Declarations => LANGUAGE_DECL_COUNT as u64 * 4;
        _language_decl_tag as "language_decl_tag" in Declarations => LANGUAGE_DECL_COUNT as u64 * 4;
    });
    graph_resources!(graph, Workspace {
        _module_type_path_status as "module_type_path_status" in Tokens => token_rows * 4;
        _module_value_path_expr_head as "module_value_path_expr_head" in Tokens => token_rows * 4;
        _module_value_path_call_head as "module_value_path_call_head" in Tokens => token_rows * 4;
        _module_value_path_call_leaf as "module_value_path_call_leaf" in Tokens => token_rows * 4;
        _module_value_path_associated_method_token as "module_value_path_associated_method_token" in Tokens => token_rows * 4;
        _module_value_path_const_head as "module_value_path_const_head" in Tokens => token_rows * 4;
        _module_value_path_const_end as "module_value_path_const_end" in Tokens => token_rows * 4;
        _token_active_dispatch_args as "token_active_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
        hir_active_dispatch_args in DispatchArguments [StorageIndirect] => 12;
        _token_hir_active_dispatch_args as "token_hir_active_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
        _hir_active_count as "hir_active_count" in HirNodes => 4;
    });

    graph_resources!(graph, Workspace {
        _module_value_path_status as "module_value_path_status" in Tokens => token_rows * 4;
        _type_instance_decl_token as "type_instance_decl_token" in Types => token_rows * 4;
        _type_instance_aggregate_word_count as "type_instance_aggregate_word_count" in Types => token_rows * 4;
        _module_file_id as "module_file_id" in Declarations => module_rows * 4;
        _module_path_id as "module_path_id" in Declarations => module_rows * 4;
        _module_owner_hir as "module_owner_hir" in Declarations => module_rows * 4;
        _import_module_file_id as "import_module_file_id" in Declarations => record_rows * 4;
        _import_path_id as "import_path_id" in Declarations => record_rows * 4;
        _import_kind as "import_kind" in Declarations => record_rows * 4;
        _import_owner_hir as "import_owner_hir" in Declarations => record_rows * 4;
        _decl_module_file_id as "decl_module_file_id" in Declarations => record_rows * 4;
        _decl_name_id as "decl_name_id" in Declarations => record_rows * 4;
        _decl_namespace as "decl_namespace" in Declarations => record_rows * 4;
        _decl_visibility as "decl_visibility" in Declarations => record_rows * 4;
        _decl_hir_node as "decl_hir_node" in Declarations => record_rows * 4;
        _decl_parent_type_decl as "decl_parent_type_decl" in Declarations => record_rows * 4;
        _decl_token_start as "decl_token_start" in Declarations => record_rows * 4;
        _decl_token_end as "decl_token_end" in Declarations => record_rows * 4;
    });
    let import_visible_rows = if source_file_capacity <= 1 {
        1
    } else {
        token_rows
    };
    let path_prefix_rounds =
        u64::from(u32::BITS - token_capacity.max(1).saturating_sub(1).leading_zeros()).max(1);
    graph_resources!(graph, Workspace {
        _module_status as "module_status" in Declarations => module_rows * 4;
        _module_dispatch_args as "module_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
        _import_edge_set_state as "import_edge_set_state" in Declarations => record_rows * 8;
        _interface_public_decl_count as "interface_public_decl_count" in Declarations => 4;
        _interface_public_decl_local_id as "interface_public_decl_local_id" in Declarations => record_rows * 4;
        _interface_public_decl_index_by_local as "interface_public_decl_index_by_local" in Declarations => record_rows * 4;
        _interface_public_decl_index_by_hir as "interface_public_decl_index_by_hir" in HirNodes => hir_rows * 4;
        _import_visible_type_lookup_state as "import_visible_type_lookup_state" in Declarations => import_visible_rows * 8;
        _import_visible_type_duplicate_of as "import_visible_type_duplicate_of" in Declarations => import_visible_rows * 4;
        _import_visible_value_lookup_state as "import_visible_value_lookup_state" in Declarations => import_visible_rows * 8;
        _import_visible_value_duplicate_of as "import_visible_value_duplicate_of" in Declarations => import_visible_rows * 4;
        _import_visible_validate_dispatch_args as "import_visible_validate_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
        _path_prefix_id_b as "path_prefix_id_b" in Tokens => token_rows * 4;
        _path_prefix_table_state as "path_prefix_table_state" in Tokens => token_rows * 8;
        _path_prefix_row_dispatch_args as "path_prefix_row_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
        _path_prefix_round_dispatch_args as "path_prefix_round_dispatch_args" in DispatchArguments [StorageIndirect] => path_prefix_rounds * 12;
        _path_dispatch_args as "path_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
    });
    graph.add_resource_alias("module_by_canonical_id", _path_prefix_table_state)?;
    graph_resources!(graph, Workspace {
        predicate_syntax_token in Tokens => predicate_rows * 4;
        _type_expr_ref_tag as "type_expr_ref_tag" in Tokens => token_rows * 4;
        _type_expr_ref_payload as "type_expr_ref_payload" in Tokens => token_rows * 4;
        _external_type_library_id as "external_type_library_id" in Tokens => token_rows * 4;
        _external_type_unit_id as "external_type_unit_id" in Tokens => token_rows * 4;
        _external_type_local_index as "external_type_local_index" in Tokens => token_rows * 4;
        _type_generic_param_slot_by_token as "type_generic_param_slot_by_token" in Tokens => token_rows * 4;
        _type_const_param_slot_by_token as "type_const_param_slot_by_token" in Tokens => token_rows * 4;
    });
    graph_resources!(graph, Input {
        _compact_hir_scope_end as "compact_hir_scope_end" in HirNodes => hir_rows * 4;
    });

    let name_rows = token_rows.saturating_add(LANGUAGE_SYMBOL_COUNT as u64);
    graph_resources!(graph, Workspace {
        name_id_by_token in Tokens => token_rows * 4;
    });
    graph_resources!(graph, Workspace {
        _language_name_id as "language_name_id" in Declarations => LANGUAGE_SYMBOL_COUNT as u64 * 4;
        _language_decl_name_id as "language_decl_name_id" in Declarations => LANGUAGE_DECL_COUNT as u64 * 4;
    });
    // These tiny language lookup tables are initialized once per job and are
    // consumed throughout type checking. Keep them out of phase-colored
    // scratch: recorder branches and dependency-page work may interleave
    // consumers that cannot safely share their physical storage.
    graph_resources!(graph, Workspace {
        _language_type_code_by_name_id as "language_type_code_by_name_id" in Declarations => name_rows * 4;
        _language_entrypoint_tag_by_name_id as "language_entrypoint_tag_by_name_id" in Declarations => name_rows * 4;
        _language_intrinsic_tag_by_name_id as "language_intrinsic_tag_by_name_id" in Declarations => name_rows * 4;
    });
    graph_resources!(graph, Input {
        _compact_predicate_count as "compact_predicate_count" in Declarations => 4;
        _compact_predicates as "compact_predicates" in Declarations =>
            hir_rows * core::mem::size_of::<HirPredicate>() as u64;
        _token_file_id as "token_file_id" in Tokens => token_rows * 4;
        _compact_field_count as "compact_field_count" in Declarations => 4;
        _compact_fields as "compact_fields" in Declarations =>
            hir_rows * core::mem::size_of::<HirField>() as u64;
    });
    graph_resources!(graph, Workspace {
        _module_type_path_type as "module_type_path_type" in Tokens => token_rows * 4;
        _module_value_path_call_open as "module_value_path_call_open" in Tokens => token_rows * 4;
        _module_value_path_call_path_id as "module_value_path_call_path_id" in Tokens => token_rows * 4;
        _module_value_path_associated_receiver_token as "module_value_path_associated_receiver_token" in Tokens => token_rows * 4;
        module_count_out in Declarations => 4;
    });

    // Path relations are consumed across the module-resolution, visibility,
    // and expression-projection recorder stages. Keep them graph-owned but
    // dedicated until those three stages are represented by one exact pass
    // order; coloring them from the partial schedule is not sound.
    graph_resources!(graph, Workspace {
        _path_owner_hir as "path_owner_hir" in HirNodes => record_rows * 4;
        _path_kind as "path_kind" in Tokens => record_rows * 4;
        _path_owner_token as "path_owner_token" in Tokens => record_rows * 4;
        _path_id_by_owner_hir as "path_id_by_owner_hir" in HirNodes => hir_rows * 4;
        _path_len as "path_len" in HirNodes => record_rows * 4;
        _path_segment_count as "path_segment_count" in HirNodes => record_rows * 4;
        _path_segment_base as "path_segment_base" in HirNodes => record_rows * 4;
        _path_segment_token as "path_segment_token" in Tokens => token_rows * 4;
    });
    graph_resources!(graph, Workspace {
        _path_call_hir as "path_call_hir" in HirNodes => record_rows * 4;
        _path_id_by_owner_token as "path_id_by_owner_token" in Tokens => token_rows * 4;
        _path_count_out as "path_count_out" in HirNodes => 4;
        _path_segment_count_out as "path_segment_count_out" in Tokens => 4;
        _path_max_segment_count as "path_max_segment_count" in Tokens => 4;
        _path_prefix_base as "path_prefix_base" in Tokens => token_rows * 4;
        _path_prefix_id_a as "path_prefix_id_a" in Tokens => token_rows * 4;
    });
    graph_resources!(graph, Workspace {
        _alias_root_a as "alias_root_a" in Declarations => u64::from(module_record_capacity.max(1)) * 4;
        _alias_root_b as "alias_root_b" in Declarations => u64::from(module_record_capacity.max(1)) * 4;
        alias_forwarding in HirNodes => hir_rows * 4;
        alias_forwarding_target_decl in HirNodes => hir_rows * 4;
        alias_forwarding_valid_arg_count in HirNodes => hir_rows * 4;
        alias_decl_by_target_hir in HirNodes => hir_rows * 4;
        // Equivalence rows use two token-indexed partitions. The dispatch
        // contract is `2 * token_capacity`, not HIR rows plus tokens; compact
        // HIR can be smaller than the token domain.
        _alias_equiv_parent_a as "alias_equiv_parent_a" in HirNodes => token_rows * 2 * 4;
        _alias_equiv_parent_b as "alias_equiv_parent_b" in HirNodes => token_rows * 2 * 4;
        _alias_equiv_component_source as "alias_equiv_component_source" in HirNodes => token_rows * 2 * 4;
    });
    for (alias, resource) in [
        ("alias_equiv_edge_0", alias_forwarding),
        ("alias_equiv_edge_1", alias_forwarding_target_decl),
        ("alias_normalized_source", alias_forwarding_valid_arg_count),
        ("alias_source_hir_by_target_hir", alias_decl_by_target_hir),
    ] {
        graph.add_resource_alias(alias, resource)?;
    }

    graph_resources!(graph, Workspace {
        _method_decl_method_row as "method_decl_method_row" in Declarations => token_rows * 4;
        _method_decl_receiver_ref_tag as "method_decl_receiver_ref_tag" in Declarations => token_rows * 4;
        _method_decl_receiver_ref_payload as "method_decl_receiver_ref_payload" in Declarations => token_rows * 4;
        _method_decl_module_id as "method_decl_module_id" in Declarations => token_rows * 4;
        _method_decl_name_token as "method_decl_name_token" in Declarations => token_rows * 4;
        _method_decl_name_id as "method_decl_name_id" in Declarations => token_rows * 4;
        _method_decl_param_offset as "method_decl_param_offset" in Declarations => token_rows * 4;
        _method_decl_receiver_mode as "method_decl_receiver_mode" in Declarations => token_rows * 4;
        _method_decl_visibility as "method_decl_visibility" in Declarations => token_rows * 4;
        _method_decl_signature_flags as "method_decl_signature_flags" in Declarations => token_rows * 4;
    });
    graph_resources!(graph, Workspace {
        _struct_field_lookup_state as "struct_field_lookup_state" in Declarations => token_rows * 8;
    });
    let name_blocks = name_rows.div_ceil(256).max(1);
    let name_hash_rows = name_blocks * u64::from(NAME_HASH_TABLE_ROWS_PER_BLOCK);
    graph_resources!(graph, Workspace {
        _name_lexeme_flag as "name_lexeme_flag" in Tokens => token_rows * 4;
        _name_lexeme_kind as "name_lexeme_kind" in Tokens => token_rows * 4;
        _name_lexeme_prefix as "name_lexeme_prefix" in Tokens => token_rows * 4;
        _name_scan_local_prefix as "name_scan_local_prefix" in Tokens => name_rows * 4;
        _name_scan_block_sum as "name_scan_block_sum" in Tokens => name_blocks * 4;
        _name_scan_prefix_a as "name_scan_prefix_a" in Tokens => name_blocks * 4;
    });

    // These four arrays form the retained name artifact consumed by module
    // resolution and semantic-interface export after the graph's last name
    // pass.  Marking them as ordinary scratch allowed later type-check arrays
    // to overwrite live names in the same colored workspace slot.
    graph_resources!(graph, Output {
        name_scan_total in Declarations => 4;
        _name_spans as "name_spans" in Declarations => name_rows * 16;
        name_hash_lo in Declarations => name_rows * 4;
        name_hash_hi in Declarations => name_rows * 4;
    });
    graph_resources!(graph, Workspace {
        name_max_len in Declarations => 4;
        name_hash_table_a in Declarations => name_hash_rows * 4;
        name_hash_table_b in Declarations => name_hash_rows * 4;
        sorted_name_id in Declarations => name_rows * 4;
        name_id_by_input in Declarations => name_rows * 4;
        unique_name_count in Declarations => 4;
        decl_name_token in Declarations => hir_rows * 4;
        decl_id_by_name_token in Tokens => token_rows * 4;
        _module_record_family_bits as "module_record_family_bits" in HirNodes => hir_rows * 4;
        _module_record_family_flag as "module_record_family_flag" in HirNodes => hir_rows * 4;
        _module_record_prefix as "module_record_prefix" in HirNodes => hir_rows * 4;
        _module_record_scan_local_prefix as "module_record_scan_local_prefix" in HirNodes => hir_rows * 4;
        _module_record_scan_block_sum as "module_record_scan_block_sum" in HirNodes => hir_blocks * 4;
        _module_record_scan_prefix_a as "module_record_scan_prefix_a" in HirNodes => hir_blocks * 4;
        _module_value_scan_local_prefix as "module_value_scan_local_prefix" in Declarations => hir_rows * 4;
        _module_value_scan_block_sum as "module_value_scan_block_sum" in Declarations => hir_blocks * 4;
        _module_value_scan_prefix_a as "module_value_scan_prefix_a" in Declarations => hir_blocks * 4;
    });
    if module_record_capacity > MODULE_RELATION_SMALL_SORT_CAPACITY {
        graph_resources!(graph, Workspace {
            _module_path_key_radix_block_histogram as "module_path_key_radix_block_histogram" in Declarations => module_path_key_radix_rows * 4;
            _module_path_key_radix_block_bucket_prefix as "module_path_key_radix_block_bucket_prefix" in Declarations => module_path_key_radix_rows * 4;
            _module_path_key_radix_bucket_total as "module_path_key_radix_bucket_total" in Declarations => u64::from(RADIX_U8_BUCKET_COUNT) * 4;
            _module_path_key_radix_bucket_base as "module_path_key_radix_bucket_base" in Declarations => u64::from(RADIX_U8_BUCKET_COUNT) * 4;
        });
    }

    graph_resources!(graph, Input {
        _type_decl_hir_node_by_token as "type_decl_hir_node_by_token" in Tokens => token_rows * 4;
    });
    graph_resources!(graph, Workspace {
        predicate_bound_first_arg_token in HirNodes => predicate_rows * 4;
        predicate_bound_second_arg_token in HirNodes => predicate_rows * 4;
        predicate_status in HirNodes => predicate_rows * 4;
        predicate_method_contract_status in HirNodes => predicate_rows * 4;
        predicate_method_validation_first_error_row in HirNodes => predicate_rows * 4;
        predicate_method_validation_status in HirNodes => predicate_rows * 4;
        predicate_method_validation_detail_token in HirNodes => predicate_rows * 4;
    });
    graph_resources!(graph, Workspace {
        struct_lit_context_instance in HirNodes => hir_rows * 4;
        struct_lit_context_decl_token in HirNodes => hir_rows * 4;
        _type_instance_arg_start as "type_instance_arg_start" in Types => token_rows * 4;
        _type_instance_head_token as "type_instance_head_token" in Types => token_rows * 4;
        _type_instance_state as "type_instance_state" in Types => token_rows * 4;
        _type_instance_elem_ref_tag as "type_instance_elem_ref_tag" in Types => token_rows * 4;
        _type_instance_elem_ref_payload as "type_instance_elem_ref_payload" in Types => token_rows * 4;
        _type_instance_len_kind as "type_instance_len_kind" in Types => token_rows * 4;
        _type_instance_len_payload as "type_instance_len_payload" in Types => token_rows * 4;
        _type_instance_arg_count as "type_instance_arg_count" in Types => token_rows * 4;
    });
    graph_resources!(graph, Workspace {
        visible_type in Tokens => token_rows * 4;
        visible_decl in Tokens => token_rows * 4;
    });
    graph_resources!(graph, Workspace {
        _call_return_type as "call_return_type" in Tokens => token_rows * 4;
        _call_return_type_token as "call_return_type_token" in Tokens => token_rows * 4;
        _call_return_generic_slot as "call_return_generic_slot" in Tokens => token_rows * 4;
        _call_return_aggregate_word_count as "call_return_aggregate_word_count" in Tokens => token_rows * 4;
        _call_fn_index as "call_fn_index" in Calls => token_rows * 4;
        _method_call_receiver_ref_tag as "method_call_receiver_ref_tag" in Calls => token_rows * 4;
        _method_call_receiver_ref_payload as "method_call_receiver_ref_payload" in Calls => token_rows * 4;
        _method_call_name_id as "method_call_name_id" in Calls => token_rows * 4;
        _method_call_site_module_id as "method_call_site_module_id" in Calls => token_rows * 4;
        _fn_entrypoint_tag as "fn_entrypoint_tag" in Tokens => token_rows.max(hir_rows) * 4;
        _type_instance_arg_row_start as "type_instance_arg_row_start" in Types => token_rows * 4;
        _type_instance_arg_row_count_out as "type_instance_arg_row_count_out" in Types => 4;
        _type_instance_arg_row_scan_local_prefix as "type_instance_arg_row_scan_local_prefix" in Types => token_rows * 4;
        _type_instance_arg_row_scan_block_sum as "type_instance_arg_row_scan_block_sum" in Types => token_rows.div_ceil(256) * 4;
        _type_instance_arg_row_scan_prefix_a as "type_instance_arg_row_scan_prefix_a" in Types => token_rows.div_ceil(256) * 4;
        _method_key_status as "method_key_status" in Declarations => token_rows * 4;
        _method_key_duplicate_of as "method_key_duplicate_of" in Declarations => token_rows * 4;
        _method_lookup_head as "method_lookup_head" in Declarations => token_rows.saturating_mul(2) * 4;
        _method_lookup_next as "method_lookup_next" in Declarations => hir_rows * 4;
    });
    graph_resources!(graph, Workspace {
        member_result_context_instance in Tokens => token_rows * 4;
        member_result_ref_tag in Tokens => token_rows * 4;
        member_result_ref_payload in Tokens => token_rows * 4;
        member_result_field_ordinal in Tokens => token_rows * 4;
        member_result_field_node in Tokens => token_rows * 4;
        struct_init_field_context_instance in Tokens => token_rows * 4;
        struct_init_field_expected_ref_tag in Tokens => token_rows * 4;
        struct_init_field_expected_ref_payload in Tokens => token_rows * 4;
        struct_init_field_ordinal in Tokens => token_rows * 4;
    });
    graph_resources!(graph, Workspace {
        _type_instance_arg_row_ref_tag as "type_instance_arg_row_ref_tag" in Types => hir_rows * 4;
        _type_instance_arg_row_ref_payload as "type_instance_arg_row_ref_payload" in Types => hir_rows * 4;
        type_instance_arg_hash in Types => token_rows * 4;
        _type_instance_arg_ref_tag as "type_instance_arg_ref_tag" in Types => token_rows * 16;
        _type_instance_arg_ref_payload as "type_instance_arg_ref_payload" in Types => token_rows * 16;
    });
    graph_resources!(graph, Output {
        struct_init_field_ordinal_by_row in Declarations => hir_rows * 4;
    });
    graph_resources!(graph, Workspace {
        generic_decl_owner_by_node_a as "generic_decl_owner_by_node" in HirNodes => hir_rows * 4;
        predicate_bound_list_by_node_a as "predicate_bound_list_by_node" in HirNodes => hir_rows * 4;
        predicate_bound_list_by_node_b as "predicate_trait_impl_trait_type_node" in HirNodes => hir_rows * 4;
    });
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
    graph_resources!(graph, Workspace {
        _type_decl_generic_param_count as "type_decl_generic_param_count" in Tokens => token_rows * 4;
        _type_decl_generic_param_count_by_owner_token as "type_decl_generic_param_count_by_owner_token" in Tokens => token_rows * 4;
        _type_decl_const_param_count_by_owner_token as "type_decl_const_param_count_by_owner_token" in Tokens => token_rows * 4;
    });
    graph_resources!(graph, Workspace {
        generic_param_count_out in Declarations => 4;
        generic_param_owner_token in Declarations => token_rows * 4;
        generic_param_name_id in Declarations => token_rows * 4;
        generic_param_token in Declarations => token_rows * 4;
        generic_param_kind in Declarations => token_rows * 4;
        _generic_param_lookup_state as "generic_param_lookup_state" in Declarations => token_rows * 8;
        generic_type_param_flag in Declarations => token_rows * 4;
        generic_const_param_flag in Declarations => token_rows * 4;
        _generic_type_param_prefix as "generic_type_param_prefix" in Declarations => token_rows * 4;
        _generic_const_param_prefix as "generic_const_param_prefix" in Declarations => token_rows * 4;
        _generic_type_param_count_out as "generic_type_param_count_out" in Declarations => 4;
        _generic_const_param_count_out as "generic_const_param_count_out" in Declarations => 4;
        _generic_type_param_rows as "generic_type_param_rows" in Declarations => token_rows * 4;
        _generic_type_param_scan_local_prefix as "generic_type_param_scan_local_prefix" in Declarations => token_rows * 4;
        _generic_const_param_scan_local_prefix as "generic_const_param_scan_local_prefix" in Declarations => token_rows * 4;
        _generic_type_param_scan_block_sum as "generic_type_param_scan_block_sum" in Declarations => token_rows.div_ceil(256) * 4;
        _generic_const_param_scan_block_sum as "generic_const_param_scan_block_sum" in Declarations => token_rows.div_ceil(256) * 4;
        _generic_type_param_scan_prefix_a as "generic_type_param_scan_prefix_a" in Declarations => token_rows.div_ceil(256) * 4;
        _generic_const_param_scan_prefix_a as "generic_const_param_scan_prefix_a" in Declarations => token_rows.div_ceil(256) * 4;
    });
    graph_resources!(graph, Input {
        _compact_generic_param_count as "compact_generic_param_count" in HirNodes => 4;
        _compact_generic_params as "compact_generic_params" in HirNodes =>
            token_rows * core::mem::size_of::<HirGenericParam>() as u64;
        compact_generic_param_ranges in HirNodes =>
            hir_rows * core::mem::size_of::<HirRange>() as u64;
        _compact_variant_count as "compact_variant_count" in HirNodes => 4;
        _compact_variants as "compact_variants" in HirNodes =>
            token_rows * core::mem::size_of::<HirVariant>() as u64;
        _compact_variant_payload_count as "compact_variant_payload_count" in HirNodes => hir_rows * 4;
        _compact_variant_payload_row_count as "compact_variant_payload_row_count" in HirNodes => 4;
        _compact_variant_payloads as "compact_variant_payloads" in HirNodes =>
            token_rows * core::mem::size_of::<HirVariantPayload>() as u64;
    });
    graph.add_storage(
        "module_key_canonical_id",
        ResourceDomain::Declarations,
        ResourceClass::Workspace,
        module_rows * 4,
    )?;
    for name in [
        "import_visible_type_key_module_id",
        "import_visible_type_key_name_id",
        "import_visible_type_key_to_decl_id",
        "import_visible_type_status",
        "import_visible_value_key_module_id",
        "import_visible_value_key_name_id",
        "import_visible_value_key_to_decl_id",
        "import_visible_value_status",
    ] {
        graph.add_storage(
            name,
            ResourceDomain::Declarations,
            ResourceClass::Workspace,
            import_visible_rows * 4,
        )?;
    }
    // Logical reflected name supplied by bind-group construction. Model it as
    // the same graph-owned path-prefix allocation so reflection-derived arena
    // conflicts follow the real binding identity.
    graph.add_resource_alias("path_prefix_id", _path_prefix_id_a)?;
    let path_segment_name_id = graph.add_storage(
        "path_segment_name_id",
        ResourceDomain::Tokens,
        // Module keys alias this relation and semantic-interface export reads
        // those canonical segment names after the type-check schedule ends.
        // It therefore crosses the graph boundary and must never share a
        // phase-local workspace slot.
        ResourceClass::Output,
        token_rows * 4,
    )?;
    graph_resources!(graph, Input {
        _compact_param_ranges as "compact_param_ranges" in HirNodes =>
            hir_rows * core::mem::size_of::<HirRange>() as u64;
        _compact_type_arg_count as "compact_type_arg_count" in HirNodes => 4;
        _compact_type_args as "compact_type_args" in HirNodes =>
            hir_rows * core::mem::size_of::<HirTypeArg>() as u64;
        _compact_type_arg_ranges as "compact_type_arg_ranges" in HirNodes =>
            hir_rows * core::mem::size_of::<HirRange>() as u64;
    });
    let predicate_trait_impl_trait_type_node = predicate_bound_list_by_node_b;
    graph_resources!(graph, Workspace {
        predicate_owner_node in HirNodes => predicate_rows * 4;
        predicate_subject_token in HirNodes => predicate_rows * 4;
        predicate_bound_token in HirNodes => predicate_rows * 4;
        predicate_bound_decl_id in HirNodes => predicate_rows * 4;
        predicate_bound_arg_count in HirNodes => predicate_rows * 4;
        predicate_method_contract_owner_hir in HirNodes => predicate_rows * 4;
        predicate_method_contract_name_token in HirNodes => predicate_rows * 4;
        predicate_method_contract_name_id in HirNodes => predicate_rows * 4;
        predicate_method_contract_param_count in HirNodes => predicate_rows * 4;
        predicate_method_contract_return_type_node in HirNodes => predicate_rows * 4;
        predicate_method_contract_visibility in HirNodes => predicate_rows * 4;
        predicate_method_contract_param_type_node in HirNodes => predicate_rows * 4;
        predicate_method_contract_owner_count in HirNodes => predicate_rows * 4;
        predicate_method_contract_lookup_head in HirNodes => predicate_rows * 2 * 4;
        predicate_method_contract_lookup_next in HirNodes => predicate_rows * 4;
        predicate_method_validation_owner_node in HirNodes => predicate_rows * 4;
        predicate_method_validation_peer_node in HirNodes => predicate_rows * 4;
        predicate_owner_lookup_head in HirNodes => predicate_rows * 2 * 4;
        predicate_owner_lookup_next in HirNodes => predicate_rows * 4;
        predicate_impl_lookup_head in HirNodes => predicate_rows * 2 * 4;
        predicate_impl_lookup_next in HirNodes => predicate_rows * 4;
    });
    graph_resources!(graph, Workspace {
        predicate_obligation_count_by_call in HirNodes => predicate_rows * 4;
        _predicate_obligation_prefix_by_call as "predicate_obligation_prefix_by_call" in HirNodes => predicate_rows * 4;
        _predicate_obligation_scan_local_prefix as "predicate_obligation_scan_local_prefix" in HirNodes => predicate_rows * 4;
        _predicate_obligation_scan_block_sum as "predicate_obligation_scan_block_sum" in HirNodes => predicate_rows.div_ceil(256) * 4;
        _predicate_obligation_scan_prefix_a as "predicate_obligation_scan_prefix_a" in HirNodes => predicate_rows.div_ceil(256) * 4;
        predicate_obligation_pair_total in HirNodes => 4;
        predicate_obligation_pair_dispatch_args in DispatchArguments [StorageIndirect] => 12;
    });
    graph_resources!(graph, Workspace {
        decl_kind in Declarations => hir_rows * 4;
    });
    graph_resources!(graph, Workspace {
        _resolved_type_decl as "resolved_type_decl" in Declarations => record_rows * 4;
        _resolved_type_status as "resolved_type_status" in Declarations => record_rows * 4;
        _resolved_value_decl as "resolved_value_decl" in Declarations => record_rows * 4;
        _resolved_value_status as "resolved_value_status" in Declarations => record_rows * 4;
    });
    graph_resources!(graph, Workspace {
        _module_id_by_file_id as "module_id_by_file_id" in Declarations => u64::from(source_file_capacity.max(1)) * 4;
        _decl_module_id as "decl_module_id" in Declarations => record_rows * 4;
        _module_key_segment_count as "module_key_segment_count" in Declarations => module_rows * 4;
        _module_key_segment_base as "module_key_segment_base" in Declarations => module_rows * 4;
        _decl_type_key_to_decl_id as "decl_type_key_to_decl_id" in Declarations => record_rows * 4;
        _decl_value_key_to_decl_id as "decl_value_key_to_decl_id" in Declarations => record_rows * 4;
        _decl_lookup_state as "decl_lookup_state" in Declarations => record_rows * 8;
        import_record_count_out in Declarations => 4;
        _decl_count_out as "decl_count_out" in Declarations => 4;
    });
    graph.add_resource_alias("module_key_segment_name_id", path_segment_name_id)?;
    graph.add_resource_alias("module_record_count_out", module_count_out)?;
    graph.add_resource_alias("import_count_out", import_record_count_out)?;
    graph.add_storage(
        "path_owner_module_id",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        record_rows * 4,
    )?;
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
        graph.add_storage(name, domain, ResourceClass::Workspace, bytes)?;
    }
    let mut canonical_type_jump_rounds = 0u32;
    let mut canonical_type_jump_reach = 1u32;
    while canonical_type_jump_reach < dependency_capacity.type_rows.max(1) {
        canonical_type_jump_reach = canonical_type_jump_reach.saturating_mul(16);
        canonical_type_jump_rounds += 1;
    }
    for (name, rows) in [
        ("dependency_visible_owner_module", dependency_visible_rows),
        ("dependency_visible_decl", dependency_visible_rows),
        ("dependency_visible_lookup", dependency_lookup_rows),
        (
            "dependency_resolved_type_decl",
            u64::from(module_record_capacity.max(1)),
        ),
        ("dependency_canonical_type_roots_a", dependency_type_rows),
        ("dependency_canonical_type_subtree_a", dependency_type_rows),
        (
            "dependency_declaration_generic_arity",
            dependency_declaration_rows,
        ),
    ] {
        graph.add_storage(
            name,
            ResourceDomain::Declarations,
            ResourceClass::Workspace,
            rows * 4,
        )?;
    }
    let dependency_resolved_type_decl = graph
        .resource_id("dependency_resolved_type_decl")
        .expect("dependency resolved type declaration resource");
    let dependency_canonical_type_roots_a = graph
        .resource_id("dependency_canonical_type_roots_a")
        .expect("dependency canonical root A resource");
    let dependency_canonical_type_subtree_a = graph
        .resource_id("dependency_canonical_type_subtree_a")
        .expect("dependency canonical subtree A resource");
    // A zero-round dependency relation never reads or writes the second side
    // of the ping-pong pair. Give the runtime-facing B names the A ownership
    // identity instead of allocating an unproduced workspace relation.
    let (dependency_canonical_type_roots_b, dependency_canonical_type_subtree_b) =
        if canonical_type_jump_rounds == 0 {
            graph.add_resource_alias(
                "dependency_canonical_type_roots_b",
                dependency_canonical_type_roots_a,
            )?;
            graph.add_resource_alias(
                "dependency_canonical_type_subtree_b",
                dependency_canonical_type_subtree_a,
            )?;
            (
                dependency_canonical_type_roots_a,
                dependency_canonical_type_subtree_a,
            )
        } else {
            (
                graph.add_storage(
                    "dependency_canonical_type_roots_b",
                    ResourceDomain::Declarations,
                    ResourceClass::Workspace,
                    dependency_type_rows * 4,
                )?,
                graph.add_storage(
                    "dependency_canonical_type_subtree_b",
                    ResourceDomain::Declarations,
                    ResourceClass::Workspace,
                    dependency_type_rows * 4,
                )?,
            )
        };
    let dependency_declaration_generic_arity = graph
        .resource_id("dependency_declaration_generic_arity")
        .expect("dependency declaration generic arity resource");
    let (dependency_canonical_type_roots, dependency_canonical_type_subtree_start) =
        if canonical_type_jump_rounds % 2 == 0 {
            (
                dependency_canonical_type_roots_a,
                dependency_canonical_type_subtree_a,
            )
        } else {
            (
                dependency_canonical_type_roots_b,
                dependency_canonical_type_subtree_b,
            )
        };
    let _dependency_resolved_value_decl = graph.add_storage(
        "dependency_resolved_value_decl",
        ResourceDomain::Declarations,
        ResourceClass::Workspace,
        u64::from(module_record_capacity.max(1)) * 4,
    )?;
    let _dependency_words = graph.add_storage(
        "dependency_words",
        ResourceDomain::Declarations,
        ResourceClass::External,
        4,
    )?;
    let _dependency_module_lookup = graph.add_storage(
        "dependency_module_lookup",
        ResourceDomain::Declarations,
        ResourceClass::External,
        4,
    )?;
    let dependency_identity = |graph: &mut CompilerGraphBuilder, name| {
        graph.add_storage(
            name,
            ResourceDomain::Declarations,
            if dependency_capacity.visible_rows == 0 {
                ResourceClass::External
            } else {
                ResourceClass::Workspace
            },
            u64::from(module_record_capacity.max(1)) * 4,
        )
    };
    let _resolved_dependency_library_id =
        dependency_identity(&mut graph, "resolved_dependency_library_id")?;
    let _resolved_dependency_unit_id =
        dependency_identity(&mut graph, "resolved_dependency_unit_id")?;
    let _resolved_dependency_local_index =
        dependency_identity(&mut graph, "resolved_dependency_local_index")?;
    let resolved_dependency_value_metadata = graph.add_storage(
        "resolved_dependency_value_metadata",
        ResourceDomain::Declarations,
        ResourceClass::Workspace,
        u64::from(module_record_capacity.max(1)) * 3 * 4,
    )?;
    let dependency_declaration_field_count = graph.add_storage(
        "dependency_declaration_field_count",
        ResourceDomain::Declarations,
        ResourceClass::Workspace,
        dependency_declaration_rows * 4,
    )?;
    graph_resources!(graph, Workspace {
        hir_value_decl_name_present in Declarations => (token_rows + u64::from(LANGUAGE_SYMBOL_COUNT)) * 4;
    });
    graph_resources!(graph, Workspace {
        dependency_call_compare_dispatch_args in DispatchArguments [StorageIndirect] => 12;
    });
    graph_resources!(graph, Workspace {
        _fn_start_token_by_decl_token as "fn_start_token_by_decl_token" in Tokens => token_rows * 4;
        backend_call_fn_index in Tokens => token_rows * 4;
        _call_intrinsic_tag as "call_intrinsic_tag" in Tokens => token_rows * 4;
        _call_param_count as "call_param_count" in Tokens => token_rows * 4;
        _call_param_type as "call_param_type" in CallArguments => token_rows * u64::from(CALL_PARAM_CACHE_STRIDE as u32) * 4;
        _call_param_ref_tag as "call_param_ref_tag" in CallArguments => token_rows * u64::from(CALL_PARAM_CACHE_STRIDE as u32) * 4;
        _call_param_ref_payload as "call_param_ref_payload" in CallArguments => token_rows * u64::from(CALL_PARAM_CACHE_STRIDE as u32) * 4;
        call_generic_slot_type in CallArguments => token_rows * u64::from(CALL_PARAM_CACHE_STRIDE as u32) * 4;
        _call_generic_slot_ordinal as "call_generic_slot_ordinal" in CallArguments => token_rows * u64::from(CALL_PARAM_CACHE_STRIDE as u32) * 4;
        _call_const_slot_len as "call_const_slot_len" in CallArguments => token_rows * u64::from(CALL_PARAM_CACHE_STRIDE as u32) * 4;
        _call_param_row_count_out as "call_param_row_count_out" in CallArguments => 4;
    });
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
    graph_resources!(graph, Workspace {
        _call_param_row_fn_token as "call_param_row_fn_token" in CallArguments => call_param_rows * 4;
        _call_param_row_start as "call_param_row_start" in Tokens => token_rows * 4;
        _call_param_row_count as "call_param_row_count" in Tokens => token_rows * 4;
        _call_arg_record as "call_arg_record" in CallArguments => token_rows * 16;
    });
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
    graph_resources!(graph, Workspace {
        _function_lookup_key as "function_lookup_key" in Declarations => token_rows * 2 * 4;
        _function_lookup_fn as "function_lookup_fn" in Declarations => token_rows * 2 * 4;
        _decl_type_key_prefix as "decl_type_key_prefix" in Declarations => record_rows * 4;
        _decl_value_key_prefix as "decl_value_key_prefix" in Declarations => record_rows * 4;
        _decl_type_key_count_out as "decl_type_key_count_out" in Declarations => 4;
        _decl_value_key_count_out as "decl_value_key_count_out" in Declarations => 4;
        _decl_key_to_decl_id as "decl_key_to_decl_id" in Declarations => record_rows * 4;
        _decl_status as "decl_status" in Declarations => record_rows * 4;
        _import_visible_type_count as "import_visible_type_count" in Declarations => record_rows * 4;
        _import_visible_value_count as "import_visible_value_count" in Declarations => record_rows * 4;
        _import_visible_type_prefix as "import_visible_type_prefix" in Declarations => record_rows * 4;
        _import_visible_value_prefix as "import_visible_value_prefix" in Declarations => record_rows * 4;
        _import_visible_type_count_out as "import_visible_type_count_out" in Declarations => 4;
        _import_visible_value_count_out as "import_visible_value_count_out" in Declarations => 4;
        _import_module_id as "import_module_id" in Declarations => record_rows * 4;
        _import_target_module_id as "import_target_module_id" in Declarations => record_rows * 4;
        _import_status as "import_status" in Declarations => record_rows * 4;
    });
    if module_record_capacity <= MODULE_RELATION_SMALL_SORT_CAPACITY {
        graph.add_resource_alias("decl_key_order_tmp", _decl_key_to_decl_id)?;
    } else {
        graph.add_storage(
            "decl_key_order_tmp",
            ResourceDomain::Declarations,
            ResourceClass::Workspace,
            record_rows * 4,
        )?;
    }
    graph_resources!(graph, Workspace {
        _decl_key_radix_dispatch_args as "decl_key_radix_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
    });
    graph_resources!(graph, Workspace {
        _import_dispatch_args as "import_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
    });
    graph_resources!(graph, Workspace {
        hir_visible_decl_flag in Tokens => token_rows * 4;
        _hir_visible_decl_prefix as "hir_visible_decl_prefix" in Tokens => token_rows * 4;
        _hir_visible_decl_scan_local_prefix as "hir_visible_decl_scan_local_prefix" in Tokens => token_rows * 4;
        _hir_visible_decl_scan_block_sum as "hir_visible_decl_scan_block_sum" in Tokens => token_blocks * 4;
        _hir_visible_decl_scan_prefix_a as "hir_visible_decl_scan_prefix_a" in Tokens => token_blocks * 4;
    });
    graph_resources!(graph, Workspace {
        hir_visible_decl_count_out in Declarations => 4;
        _hir_visible_decl_owner_fn as "hir_visible_decl_owner_fn" in Declarations => token_rows * 4;
        _hir_visible_decl_name_id as "hir_visible_decl_name_id" in Declarations => token_rows * 4;
        _hir_visible_decl_token as "hir_visible_decl_token" in Declarations => token_rows * 4;
        _hir_visible_decl_scope_end as "hir_visible_decl_scope_end" in Declarations => token_rows * 4;
        _hir_visible_decl_node as "hir_visible_decl_node" in Declarations => token_rows * 4;
    });
    graph_resources!(graph, Workspace {
        match_payload_dispatch_args in DispatchArguments [StorageIndirect] => 12;
    });
    let visible_decl_uses_radix = token_capacity > VISIBLE_DECL_SMALL_SORT_CAPACITY;
    let visible_decl_sort_resources = graph.add_selected_radix_sort_storage(
        ResourceDomain::Declarations,
        token_rows,
        256,
        u64::from(RADIX_U8_BUCKET_COUNT),
        visible_decl_uses_radix,
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
    let _hir_visible_decl_key_order = visible_decl_sort_resources.order;
    let hir_visible_decl_key_order_tmp = visible_decl_sort_resources.temporary_order;
    graph.add_resource_alias(
        "hir_visible_decl_source_by_token",
        hir_visible_decl_key_order_tmp,
    )?;
    let hir_visible_decl_key_radix_dispatch_args = visible_decl_sort_resources.dispatch_args;
    let visible_tree_leaves = token_capacity
        .max(1)
        .div_ceil(HIR_VISIBLE_DECL_ROW_BLOCK_SIZE)
        .max(1);
    let visible_tree_leaf_base = visible_tree_leaves.next_power_of_two();
    let visible_tree_rows = visible_tree_leaf_base.saturating_mul(2).max(2);
    graph_resources!(graph, Workspace {
        _hir_visible_decl_scope_tree as "hir_visible_decl_scope_tree" in Declarations => u64::from(visible_tree_rows) * 4;
    });
    graph_resources!(graph, Workspace {
        semantic_feature_flags in HirNodes => 4;
    });
    graph_resources!(graph, Workspace {
        _method_token_dispatch_args as "method_token_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
        _method_hir_dispatch_args as "method_hir_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
        _method_compact_dispatch_args as "method_compact_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
        _method_token_hir_dispatch_args as "method_token_hir_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
        _predicate_token_dispatch_args as "predicate_token_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
        _predicate_hir_dispatch_args as "predicate_hir_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
        _predicate_compact_dispatch_args as "predicate_compact_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
        _predicate_single_dispatch_args as "predicate_single_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
        _match_hir_dispatch_args as "match_hir_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
        scalar_a as "compact_expr_scalar_type.a" in HirNodes => hir_rows * 4;
    });
    graph_resources!(graph, External {
        _status as "status" in Bytes => 16;
        _status_readback as "status_readback" in Bytes => 16;
    });
    graph_resources!(graph, Workspace {
        _return_fn_flags as "return_fn_flags" in HirNodes => hir_rows * 4;
        _return_block_flags as "return_block_flags" in HirNodes => hir_rows * 4;
    });
    graph_resources!(graph, Workspace {
        _call_result_instance as "call_result_instance" in Calls => hir_rows * 4;
        _call_generic_return_arg_node as "call_generic_return_arg_node" in Calls => hir_rows * 4;
    });
    graph_resources!(graph, Workspace {
        _call_arg_param_row as "call_arg_param_row" in CallArguments => call_arg_rows * 4;
    });
    graph_resources!(graph, Workspace {
        member_next_node in HirNodes => hir_rows * 4;
    });
    let if_blocks = token_rows.div_ceil(256);
    graph_resources!(graph, Workspace {
        if_delta in Tokens => (token_rows + 1) * 4;
        if_depth_inblock in Tokens => token_rows * 4;
        if_block_sum in Tokens => if_blocks * 4;
        if_prefix_a in Tokens => if_blocks * 4;
        if_prefix_b in Tokens => if_blocks * 4;
        if_block_prefix in Tokens => if_blocks * 4;
        if_depth in Tokens => token_rows * 4;
        enclosing_fn in Tokens => token_rows * 4;
        enclosing_fn_end in Tokens => token_rows * 4;
        fn_event_value in Tokens => (token_rows + 1) * 4;
        fn_event_end in Tokens => (token_rows + 1) * 4;
        fn_event_index in Tokens => (token_rows + 1) * 4;
        fn_event_inblock in Tokens => token_rows * 4;
        fn_block_sum in Tokens => if_blocks * 4;
        fn_prefix_a in Tokens => if_blocks * 4;
        fn_prefix_b in Tokens => if_blocks * 4;
        fn_block_prefix in Tokens => if_blocks * 4;
        _call_arg_row_scan_local_prefix as "call_arg_row_scan_local_prefix" in HirNodes => hir_rows * 4;
        _call_param_row_scan_local_prefix as "call_param_row_scan_local_prefix" in Tokens => token_rows * 4;
        _call_param_row_scan_block_sum as "call_param_row_scan_block_sum" in Tokens => token_rows.div_ceil(256) * 4;
        _call_param_row_scan_prefix_a as "call_param_row_scan_prefix_a" in Tokens => token_rows.div_ceil(256) * 4;
        _call_arg_row_scan_input as "call_arg_row_scan_input" in HirNodes => hir_rows * 4;
        _call_arg_row_prefix as "call_arg_row_prefix" in HirNodes => hir_rows * 4;
        _call_arg_row_scan_block_sum as "call_arg_row_scan_block_sum" in HirNodes => hir_blocks * 4;
        _call_arg_row_scan_prefix_a as "call_arg_row_scan_prefix_a" in HirNodes => hir_blocks * 4;
        _call_generic_claim_scan_local_prefix as "call_generic_claim_scan_local_prefix" in CallArguments => call_arg_rows * 4;
        _call_generic_claim_scan_input as "call_generic_claim_scan_input" in CallArguments => call_arg_rows * 4;
        _call_generic_claim_prefix as "call_generic_claim_prefix" in CallArguments => call_arg_rows * 4;
        _call_generic_claim_scan_block_sum as "call_generic_claim_scan_block_sum" in CallArguments => call_arg_blocks * 4;
        _call_generic_claim_scan_prefix_a as "call_generic_claim_scan_prefix_a" in CallArguments => call_arg_blocks * 4;
        _call_required_generic_scan_input as "call_required_generic_scan_input" in HirNodes => hir_rows * 4;
        _call_required_generic_prefix as "call_required_generic_prefix" in HirNodes => hir_rows * 4;
        _call_required_generic_scan_local_prefix as "call_required_generic_scan_local_prefix" in HirNodes => hir_rows * 4;
        _call_required_generic_scan_block_sum as "call_required_generic_scan_block_sum" in HirNodes => hir_blocks * 4;
        _call_required_generic_scan_prefix_a as "call_required_generic_scan_prefix_a" in HirNodes => hir_blocks * 4;
        required_generic_count_out as "call_required_generic_count_out" in CallArguments => 4;
        required_generic_dispatch_args as "call_required_generic_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
        _call_generic_claim_callee as "call_generic_claim_callee" in CallArguments => claim_rows * 4;
        _call_generic_claim_slot as "call_generic_claim_slot" in CallArguments => claim_rows * 4;
        _call_generic_claim_type as "call_generic_claim_type" in CallArguments => claim_rows * 4;
        _call_generic_claim_ref_tag as "call_generic_claim_ref_tag" in CallArguments => claim_rows * 4;
        _call_generic_claim_ref_payload as "call_generic_claim_ref_payload" in CallArguments => claim_rows * 4;
        _call_generic_claim_arg_row as "call_generic_claim_arg_row" in CallArguments => claim_rows * 4;
        _call_generic_claim_lookup_head as "call_generic_claim_lookup_head" in CallArguments => claim_rows * 4;
        _call_generic_claim_lookup_next as "call_generic_claim_lookup_next" in CallArguments => claim_rows * 4;
        generic_claim_index_dispatch_args as "call_generic_claim_index_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
        _call_const_claim_callee as "call_const_claim_callee" in CallArguments => call_arg_rows * 4;
        _call_const_claim_slot as "call_const_claim_slot" in CallArguments => call_arg_rows * 4;
        _call_const_claim_len as "call_const_claim_len" in CallArguments => call_arg_rows * 4;
        _call_const_claim_lookup_head as "call_const_claim_lookup_head" in CallArguments => call_arg_rows * 4;
        _call_const_claim_lookup_next as "call_const_claim_lookup_next" in CallArguments => call_arg_rows * 4;
        const_claim_index_dispatch_args as "call_const_claim_index_dispatch_args" in DispatchArguments [StorageIndirect] => 12;
    });
    graph_resources!(graph, Workspace {
        call_arg_row_count_out in CallArguments => 4;
        generic_claim_count_out as "call_generic_claim_count_out" in CallArguments => 4;
    });
    graph_resources!(graph, Output {
        semantic_value_decl_by_hir in HirNodes => hir_rows * 4;
        semantic_value_type_by_hir in HirNodes => hir_rows * 4;
        semantic_value_const_by_hir in HirNodes => hir_rows * 4;
        semantic_value_const_present_by_hir in HirNodes => hir_rows * 4;
        semantic_param_type_by_row in Declarations => hir_rows * 4;
        semantic_enclosing_fn_by_hir in HirNodes => hir_rows * 4;
        semantic_function_return_type_by_hir in HirNodes => hir_rows * 4;
        semantic_function_entrypoint_by_hir in HirNodes => hir_rows * 4;
        semantic_function_host_service_by_hir in HirNodes => hir_rows * 4;
        semantic_control_depth_by_hir in HirNodes => hir_rows * 4;
        semantic_expr_scalar_type_by_hir in HirNodes => hir_rows * 4;
        semantic_type_ref_tag_by_hir in HirNodes => hir_rows * 4;
        semantic_type_ref_payload_by_hir in HirNodes => hir_rows * 4;
        semantic_type_generic_param_slot_by_hir in HirNodes => hir_rows * 4;
        semantic_type_external_library_id_by_hir in HirNodes => hir_rows * 4;
        semantic_type_external_unit_id_by_hir in HirNodes => hir_rows * 4;
        semantic_type_external_local_index_by_hir in HirNodes => hir_rows * 4;
        semantic_calls_by_hir in Calls => hir_rows * std::mem::size_of::<GpuCheckedCallArtifact>() as u64;
        semantic_expr_ref_tag_by_hir in HirNodes => hir_rows * 4;
        semantic_expr_ref_payload_by_hir in HirNodes => hir_rows * 4;
        semantic_aggregate_decl_token_by_hir in HirNodes => hir_rows * 4;
        semantic_aggregate_word_count_by_hir in HirNodes => hir_rows * 4;
        semantic_array_length_by_hir in HirNodes => hir_rows * 4;
        semantic_member_field_ordinal_by_hir in HirNodes => hir_rows * 4;
        semantic_iterable_kind_by_hir in HirNodes => hir_rows * 4;
        semantic_function_result_word_count_by_hir in HirNodes => hir_rows * 4;
    });
    graph_resources!(graph, Workspace {
        _aggregate_compare_scan_input as "aggregate_compare_scan_input" in HirNodes => hir_rows * 4;
        _aggregate_compare_expected_instance as "aggregate_compare_expected_instance" in HirNodes => hir_rows * 4;
        _aggregate_compare_actual_instance as "aggregate_compare_actual_instance" in HirNodes => hir_rows * 4;
        _aggregate_compare_error_token as "aggregate_compare_error_token" in HirNodes => hir_rows * 4;
        _aggregate_compare_error_detail as "aggregate_compare_error_detail" in HirNodes => hir_rows * 4;
        _aggregate_compare_prefix as "aggregate_compare_prefix" in HirNodes => hir_rows * 4;
        aggregate_compare_count_out in HirNodes => 4;
    });
    let aggregate_blocks = hir_rows.div_ceil(256);
    graph_resources!(graph, Workspace {
        _aggregate_compare_scan_local_prefix as "aggregate_compare_scan_local_prefix" in HirNodes => hir_rows * 4;
        _aggregate_compare_scan_block_sum as "aggregate_compare_scan_block_sum" in HirNodes => aggregate_blocks * 4;
        _aggregate_compare_scan_prefix_a as "aggregate_compare_scan_prefix_a" in HirNodes => aggregate_blocks * 4;
        aggregate_compare_dispatch_args in HirNodes [StorageIndirect] => 12;
    });
    graph_resources!(graph, Workspace {
        type_semantic_row_by_token in Tokens => (token_capacity.max(1) as u64) * 4;
        type_semantic_scan_input in HirNodes => hir_rows * 4;
        _type_semantic_prefix as "type_semantic_prefix" in HirNodes => hir_rows * 4;
        _type_semantic_count_out as "type_semantic_count_out" in HirNodes => 4;
        _type_semantic_row_by_ordinal as "type_semantic_row_by_ordinal" in HirNodes => hir_rows * 4;
    });
    graph_resources!(graph, Workspace {
        type_subtree_compare_scan_input in HirNodes => hir_rows * 4;
        _type_subtree_compare_prefix as "type_subtree_compare_prefix" in HirNodes => hir_rows * 4;
        _type_subtree_compare_count_out as "type_subtree_compare_count_out" in HirNodes => 4;
        type_subtree_compare_left_root in HirNodes => hir_rows * 4;
        type_subtree_compare_right_root in HirNodes => hir_rows * 4;
        type_subtree_compare_error_token in HirNodes => hir_rows * 4;
        type_subtree_compare_error_detail in HirNodes => hir_rows * 4;
        _type_subtree_compare_dispatch_args as "type_subtree_compare_dispatch_args" in HirNodes [StorageIndirect] => 12;
    });
    graph.add_kernel_initializer_by_name(
        HIR_ACTIVE_DISPATCH_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::DispatchArguments,
        kernels,
        "type_checker/hir_active_dispatch_args",
    )?;
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
    graph.add_pass_access(
        FEATURES_COLLECT_PASS,
        PassAccess::indirect(INDIRECT_DISPATCH_BINDING, hir_active_dispatch_args),
    )?;
    graph.add_kernel_initializer_by_name(
        FEATURES_DISPATCH_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::DispatchArguments,
        kernels,
        "type_checker/semantic/features/01_dispatch_args",
    )?;
    graph.add_kernel_pass_by_name(
        IF_DEPTH_CLEAR_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        "type_checker/loop/depth/01_clear",
        reflected_bindings!["if_delta" => if_delta: Write],
    )?;
    graph.add_kernel_pass_by_name(
        IF_DEPTH_MARK_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/loop/depth/02_mark",
        &[],
    )?;
    graph.add_indirect_dispatch(IF_DEPTH_MARK_PASS, "hir_active_dispatch_args")?;
    graph.add_kernel_pass_by_name(
        IF_DEPTH_LOCAL_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        "type_checker/loop/depth/03_local",
        reflected_bindings![
            "if_depth_inblock" => if_depth_inblock: Write,
            "block_sum" => if_block_sum: Write,
        ],
    )?;
    add_control_hierarchy_passes(
        &mut graph,
        kernels,
        ControlHierarchyGraphSpec {
            up_first: IF_DEPTH_SCAN_UP_FIRST_PASS,
            up_rest: IF_DEPTH_SCAN_UP_REST_PASS,
            down: IF_DEPTH_SCAN_DOWN_PASS,
            up_kernel: "type_checker/loop/depth/04_hierarchy_up",
            down_kernel: "type_checker/loop/depth/04_hierarchy_down",
        },
        prefix_scan_hierarchy_levels(token_blocks),
        if_block_sum,
        if_prefix_a,
        if_prefix_b,
        if_block_prefix,
    )?;
    graph.add_kernel_pass_by_name(
        IF_DEPTH_APPLY_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        "type_checker/loop/depth/05_apply",
        reflected_bindings![
            "block_prefix" => if_block_prefix: Read,
            "if_depth" => if_depth: Write,
        ],
    )?;
    graph.add_kernel_pass_by_name(
        LANGUAGE_NAMES_CLEAR_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        "type_checker/language/names/00_clear",
        reflected_bindings![
            "language_name_id" => _language_name_id: Write,
            "name_max_len" => name_max_len: Write,
        ],
    )?;
    NAME_COMPACTION.register(
        &mut graph,
        kernels,
        prefix_scan_hierarchy_levels(token_blocks),
    )?;
    graph.add_kernel_pass_by_name(
        NAMES_HASH_PREPARE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        "type_checker/names/hash/00_prepare",
        reflected_bindings![
            "name_count_in" => name_scan_total: Read,
            "name_hash_table_a" => name_hash_table_a: Write,
            "name_hash_table_b" => name_hash_table_b: Write,
            "name_hash_lo" => name_hash_lo: Write,
            "name_hash_hi" => name_hash_hi: Write,
            "unique_name_count" => unique_name_count: Write,
        ],
    )?;
    graph.add_kernel_pass_by_name(
        NAMES_HASH_INSERT_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        "type_checker/names/hash/01_insert",
        reflected_bindings![
            "name_count_in" => name_scan_total: Read,
            "name_hash_table_a" => name_hash_table_a: ReadWrite,
            "name_hash_table_b" => name_hash_table_b: ReadWrite,
        ],
    )?;
    graph.add_kernel_pass_by_name(
        NAMES_HASH_ASSIGN_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        "type_checker/names/hash/02_assign_ids",
        reflected_bindings![
            "name_count_in" => name_scan_total: Read,
            "name_hash_table_a" => name_hash_table_a: ReadWrite,
            "name_hash_table_b" => name_hash_table_b: ReadWrite,
            "sorted_name_id" => sorted_name_id: Write,
            "name_id_by_input" => name_id_by_input: Write,
            "name_id_by_token" => name_id_by_token: Write,
            "language_name_id" => _language_name_id: Write,
            "unique_name_count" => unique_name_count: ReadWrite,
        ],
    )?;
    graph.add_kernel_pass_by_name(
        LANGUAGE_TYPE_CODES_CLEAR_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        "type_checker/language/decls/00a_clear_type_codes",
        reflected_bindings![
            "language_type_code_by_name_id" => _language_type_code_by_name_id: Write,
            "language_entrypoint_tag_by_name_id" => _language_entrypoint_tag_by_name_id: Write,
            "language_intrinsic_tag_by_name_id" => _language_intrinsic_tag_by_name_id: Write,
        ],
    )?;
    graph.add_kernel_pass_by_name(
        LANGUAGE_DECLS_MATERIALIZE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        "type_checker/language/decls/00_materialize",
        reflected_bindings!["language_decl_name_id" => _language_decl_name_id: Write],
    )?;
    graph.add_kernel_pass_by_name(
        PREDICATES_CLEAR_SYNTAX_TOKENS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        "type_checker/predicates/00a_clear_syntax_tokens",
        reflected_bindings!["predicate_syntax_token" => predicate_syntax_token: Write],
    )?;
    graph.add_indirect_dispatch(
        PREDICATES_CLEAR_SYNTAX_TOKENS_PASS,
        "token_active_dispatch_args",
    )?;
    // Record-family extraction reuses one flag, prefix, and hierarchy workspace
    // across the module, import, and declaration scans. Each scan is a semantic
    // graph operation; callers do not reproduce its internal access modes.
    MODULE_RECORDS_MARK.register_kernel(&mut graph, kernels)?;
    PATH_STATE_CLEAR.register_kernel(&mut graph, kernels)?;
    PATHS_SCATTER.register_kernel(&mut graph, kernels)?;
    PATH_DISPATCH.register_kernel(&mut graph, kernels)?;
    PATH_SEGMENTS_COUNT.register_kernel(&mut graph, kernels)?;
    PATH_SEGMENTS_SCATTER.register_kernel(&mut graph, kernels)?;
    PATH_PREFIX_DISPATCH.register_kernel(&mut graph, kernels)?;
    PATH_PREFIX_TABLE_CLEAR.register_kernel(&mut graph, kernels)?;
    PATH_PREFIX_INTERN_A_TO_B.register_kernel(&mut graph, kernels)?;
    PATH_PREFIX_INTERN_B_TO_A.register_kernel(&mut graph, kernels)?;
    graph.repeat_pass_range(
        u32::try_from(path_prefix_rounds)
            .map_err(|_| "path-prefix round count exceeds u32".to_owned())?
            .div_ceil(2),
        PATH_PREFIX_INTERN_A_TO_B.name,
        PATH_PREFIX_INTERN_B_TO_A.name,
    )?;
    PATH_PREFIX_FINALIZE.register_kernel(&mut graph, kernels)?;
    let record_scan_levels = prefix_scan_hierarchy_levels(hir_blocks);
    MODULE_RECORD_COMPACTION.register(&mut graph, kernels, record_scan_levels)?;
    MODULE_LOOKUP_CLEAR.register_kernel(&mut graph, kernels)?;
    MODULE_KEYS_BUILD.register_kernel(&mut graph, kernels)?;
    MODULE_DISPATCH.register_kernel(&mut graph, kernels)?;
    MODULES_VALIDATE.register_kernel(&mut graph, kernels)?;
    IMPORT_RECORD_COMPACTION.register(&mut graph, kernels, record_scan_levels)?;
    IMPORT_DISPATCH.register_kernel(&mut graph, kernels)?;
    DECL_RECORD_COMPACTION.register(&mut graph, kernels, record_scan_levels)?;
    VARIANT_DECL_COUNT_APPEND.register_kernel(&mut graph, kernels)?;
    DECL_RECORD_LOOKUP_CLEAR.register_kernel(&mut graph, kernels)?;
    DECL_SPAN_RECORDS_SCATTER.register_kernel(&mut graph, kernels)?;
    VARIANT_DECL_RECORDS_SCATTER.register_kernel(&mut graph, kernels)?;
    FILE_MODULE_MAP_CLEAR.register_kernel(&mut graph, kernels)?;
    FILE_MODULE_MAP_BUILD.register_kernel(&mut graph, kernels)?;
    ATTACH_RECORD_MODULES.register_kernel(&mut graph, kernels)?;
    RESOLVE_IMPORTS.register_kernel(&mut graph, kernels)?;
    IMPORT_EDGE_SET_CLEAR.register_kernel(&mut graph, kernels)?;
    IMPORT_EDGE_SET_BUILD.register_kernel(&mut graph, kernels)?;
    IMPORT_CYCLES_VALIDATE.register_kernel(&mut graph, kernels)?;
    let (_, module_decl_key_radix_steps) =
        decl_key_radix_layout(token_capacity, source_file_capacity);
    DECL_KEY_RADIX_DISPATCH.register_kernel(&mut graph, kernels)?;
    MODULE_DECL_KEY_RADIX_SORT.register(
        &mut graph,
        module_record_capacity,
        MODULE_RELATION_SMALL_SORT_CAPACITY,
        module_decl_key_radix_steps,
        &["decl_module_id"],
    )?;
    DECLS_VALIDATE.register_kernel(&mut graph, kernels)?;
    DECL_LOOKUP_CLEAR.register_kernel(&mut graph, kernels)?;
    DECL_LOOKUP_BUILD.register_kernel(&mut graph, kernels)?;
    DECL_DUPLICATES_VALIDATE.register_kernel(&mut graph, kernels)?;
    DECL_NAMESPACE_MARK.register_kernel(&mut graph, kernels)?;
    DECL_NAMESPACE_SCAN.register(&mut graph, record_scan_levels)?;
    DECL_NAMESPACE_SCATTER.register_kernel(&mut graph, kernels)?;
    DECL_PUBLIC_MARK.register_kernel(&mut graph, kernels)?;
    DECL_PUBLIC_SCAN.register(&mut graph, record_scan_levels)?;
    INTERFACE_PUBLIC_DECLS_CLEAR.register_kernel(&mut graph, kernels)?;
    INTERFACE_PUBLIC_DECLS_MAP.register_kernel(&mut graph, kernels)?;
    IMPORT_VISIBILITY_COUNT.register_kernel(&mut graph, kernels)?;
    IMPORT_VISIBLE_SCAN.register(&mut graph, record_scan_levels)?;
    IMPORT_VISIBLE_DISPATCH.register_kernel(&mut graph, kernels)?;
    for operation in [
        IMPORT_VISIBLE_TYPE_SCATTER,
        IMPORT_VISIBLE_VALUE_SCATTER,
        IMPORT_VISIBLE_TYPE_LOOKUP_CLEAR,
        IMPORT_VISIBLE_VALUE_LOOKUP_CLEAR,
        IMPORT_VISIBLE_TYPE_LOOKUP_BUILD,
        IMPORT_VISIBLE_VALUE_LOOKUP_BUILD,
        IMPORT_VISIBLE_STATUS_INITIALIZE,
        IMPORT_VISIBLE_AMBIGUITY_VALIDATE,
    ] {
        operation.register_kernel(&mut graph, kernels)?;
    }
    for operation in [
        RESOLVE_LOCAL_TYPE_PATHS,
        RESOLVE_LOCAL_VALUE_PATHS,
        RESOLVE_IMPORTED_TYPE_PATHS,
        RESOLVE_IMPORTED_VALUE_PATHS,
    ] {
        operation.register_kernel(&mut graph, kernels)?;
    }
    TYPE_PATH_STATE_CLEAR.register_kernel(&mut graph, kernels)?;
    DEPENDENCY_WORKSPACE_CLEAR.register_kernel(&mut graph, kernels)?;
    DEPENDENCY_MODULE_LOOKUP_CLEAR.register_kernel(&mut graph, kernels)?;
    DEPENDENCY_MODULE_LOOKUP_BUILD.register_kernel(&mut graph, kernels)?;
    DEPENDENCY_IMPORTS_RESOLVE.register_kernel(&mut graph, kernels)?;
    DEPENDENCY_IMPORT_VISIBILITY_COUNT.register_kernel(&mut graph, kernels)?;
    DEPENDENCY_VISIBLE_SCAN.register(&mut graph, record_scan_levels)?;
    DEPENDENCY_IMPORT_VISIBILITY_SCATTER.register_kernel(&mut graph, kernels)?;
    DEPENDENCY_VISIBLE_LOOKUP_CLEAR.register_kernel(&mut graph, kernels)?;
    DEPENDENCY_VISIBLE_LOOKUP_BUILD.register_kernel(&mut graph, kernels)?;
    DEPENDENCY_TYPE_PATHS_RESOLVE.register_kernel(&mut graph, kernels)?;
    DEPENDENCY_VALUE_PATHS_RESOLVE.register_kernel(&mut graph, kernels)?;
    add_dependency_type_index_passes(
        &mut graph,
        kernels,
        DEPENDENCY_TYPE_INDEX_MODULE_PATHS,
        canonical_type_jump_rounds,
        dependency_canonical_type_roots_a,
        dependency_canonical_type_roots_b,
        dependency_canonical_type_subtree_a,
        dependency_canonical_type_subtree_b,
        dependency_declaration_generic_arity,
        dependency_declaration_field_count,
    )?;
    graph.add_kernel_pass_by_name(
        DEPENDENCY_TYPES_PROJECT.name,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        DEPENDENCY_TYPES_PROJECT.kernel,
        reflected_bindings![
            "resolved_dependency_decl" => dependency_resolved_type_decl: Read,
            "canonical_type_roots" => dependency_canonical_type_roots: Read,
            "type_expr_ref_tag" => _type_expr_ref_tag: Write,
            "type_expr_ref_payload" => _type_expr_ref_payload: Write,
            "module_type_path_type" => _module_type_path_type: Write,
            "module_type_path_status" => _module_type_path_status: Write,
            "external_type_library_id" => _external_type_library_id: Write,
            "external_type_unit_id" => _external_type_unit_id: Write,
            "external_type_local_index" => _external_type_local_index: Write,
            "resolved_dependency_value_metadata" => resolved_dependency_value_metadata: Write,
        ],
    )?;
    graph.add_indirect_dispatch(DEPENDENCY_TYPES_PROJECT.name, "path_dispatch_args")?;
    for operation in [RESOLVE_QUALIFIED_TYPE_PATHS, RESOLVE_QUALIFIED_VALUE_PATHS] {
        operation.register_kernel(&mut graph, kernels)?;
    }
    TYPE_PATHS_PROJECT.register_kernel(&mut graph, kernels)?;
    VALUE_CALL_PATHS_MARK.register_kernel(&mut graph, kernels)?;
    VALUE_PATHS_PROJECT.register_kernel(&mut graph, kernels)?;
    TYPE_PATHS_VALIDATE.register_kernel(&mut graph, kernels)?;
    TYPE_INSTANCES_CLEAR.register_kernel(&mut graph, kernels)?;
    add_dependency_type_index_passes(
        &mut graph,
        kernels,
        DEPENDENCY_TYPE_INDEX_AFTER_TYPE_CLEAR,
        canonical_type_jump_rounds,
        dependency_canonical_type_roots_a,
        dependency_canonical_type_roots_b,
        dependency_canonical_type_subtree_a,
        dependency_canonical_type_subtree_b,
        dependency_declaration_generic_arity,
        dependency_declaration_field_count,
    )?;
    graph.add_kernel_pass_by_name(
        DEPENDENCY_TYPES_PROJECT_AFTER_CLEAR.name,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        DEPENDENCY_TYPES_PROJECT_AFTER_CLEAR.kernel,
        reflected_bindings![
            "resolved_dependency_decl" => dependency_resolved_type_decl: Read,
            "canonical_type_roots" => dependency_canonical_type_roots: Read,
        ],
    )?;
    graph.add_indirect_dispatch(
        DEPENDENCY_TYPES_PROJECT_AFTER_CLEAR.name,
        "path_dispatch_args",
    )?;
    if generic_param_record_passes_required(parser_feature_flags) {
        graph.add_kernel_pass_by_name(
            TYPE_INSTANCES_MARK_GENERIC_PARAM_RECORDS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/type/instances/00a_mark_generic_param_records",
            reflected_bindings![
                "compact_hir_count" => compact_hir_count: Read,
                "compact_hir_core" => compact_hir_core: Read,
                "compact_hir_semantic_facts" => compact_hir_semantic_facts: Read,
                "compact_generic_param_ranges" => compact_generic_param_ranges: Read,
                "generic_decl_owner_by_node_a" => generic_decl_owner_by_node_a: Write,
                "predicate_bound_list_by_node_a" => predicate_bound_list_by_node_a: Write,
            ],
        )?;
        graph.add_kernel_pass_by_name(
            TYPE_INSTANCES_DECL_GENERIC_PARAMS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::Declarations,
            kernels,
            "type_checker/type/instances/00b_decl_generic_params",
            reflected_bindings![
                "generic_param_count_out" => generic_param_count_out: Write,
                "generic_param_owner_token" => generic_param_owner_token: Write,
                "generic_param_name_id" => generic_param_name_id: Write,
                "generic_param_token" => generic_param_token: Write,
                "generic_param_kind" => generic_param_kind: Write,
                "generic_type_param_flag" => generic_type_param_flag: Write,
                "generic_const_param_flag" => generic_const_param_flag: Write,
            ],
        )?;
        GENERIC_PARAM_LOOKUP_CLEAR.register_kernel(&mut graph, kernels)?;
        GENERIC_PARAM_LOOKUP_BUILD.register_kernel(&mut graph, kernels)?;
        GENERIC_PARAM_SLOT_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(token_blocks))?;
        GENERIC_PARAM_ROWS_SCATTER.register_kernel(&mut graph, kernels)?;
        graph.add_kernel_pass_by_name(
            TYPE_INSTANCES_GENERIC_PARAM_USE_SLOTS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/type/instances/00e_generic_param_use_slots",
            &[],
        )?;
    } else {
        graph.add_pass(PassDesc {
            name: GENERIC_PARAM_EMPTY_PASS,
            phase: CompilerPhase::TypeCheck,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::write("generic_param_count_out", generic_param_count_out),
                PassAccess::write(
                    "generic_type_param_count_out",
                    _generic_type_param_count_out,
                ),
                PassAccess::write(
                    "generic_const_param_count_out",
                    _generic_const_param_count_out,
                ),
                PassAccess::write("generic_decl_owner_by_node", generic_decl_owner_by_node_a),
                PassAccess::write(
                    "predicate_bound_list_by_node",
                    predicate_bound_list_by_node_a,
                ),
                PassAccess::write("generic_param_owner_token", generic_param_owner_token),
                PassAccess::write("generic_param_name_id", generic_param_name_id),
                PassAccess::write("generic_param_token", generic_param_token),
                PassAccess::write("generic_param_kind", generic_param_kind),
                PassAccess::write("generic_param_lookup_state", _generic_param_lookup_state),
                PassAccess::write("generic_type_param_flag", generic_type_param_flag),
                PassAccess::write("generic_const_param_flag", generic_const_param_flag),
                PassAccess::write("generic_type_param_prefix", _generic_type_param_prefix),
                PassAccess::write("generic_const_param_prefix", _generic_const_param_prefix),
                PassAccess::write("generic_type_param_rows", _generic_type_param_rows),
                PassAccess::write(
                    "generic_type_param_scan_local_prefix",
                    _generic_type_param_scan_local_prefix,
                ),
                PassAccess::write(
                    "generic_const_param_scan_local_prefix",
                    _generic_const_param_scan_local_prefix,
                ),
                PassAccess::write(
                    "generic_type_param_scan_block_sum",
                    _generic_type_param_scan_block_sum,
                ),
                PassAccess::write(
                    "generic_const_param_scan_block_sum",
                    _generic_const_param_scan_block_sum,
                ),
                PassAccess::write(
                    "generic_type_param_scan_prefix_a",
                    _generic_type_param_scan_prefix_a,
                ),
                PassAccess::write(
                    "generic_const_param_scan_prefix_a",
                    _generic_const_param_scan_prefix_a,
                ),
            ],
        })?;
    }
    for operation in [
        TYPE_INSTANCES_COLLECT_INITIAL,
        TYPE_INSTANCES_COLLECT_INITIAL_NAMED,
        TYPE_INSTANCES_COLLECT_INITIAL_AGGREGATE_REFS,
        TYPE_INSTANCES_COLLECT_INITIAL_AGGREGATE_DETAILS,
    ] {
        operation.register_kernel(&mut graph, kernels)?;
    }
    for operation in [
        TYPE_ALIAS_FORWARDING_CLEAR,
        TYPE_ALIAS_FORWARDING_INITIALIZE,
        TYPE_ALIAS_FORWARDING_VALIDATE,
        TYPE_ALIAS_ROOT_INITIALIZE,
    ] {
        operation.register_kernel(&mut graph, kernels)?;
    }
    if type_alias_root_jump_rounds >= 2 {
        TYPE_ALIAS_ROOT_JUMP_A_TO_B.register_kernel(&mut graph, kernels)?;
        TYPE_ALIAS_ROOT_JUMP_B_TO_A.register_kernel(&mut graph, kernels)?;
        graph.repeat_pass_range(
            type_alias_root_jump_rounds / 2,
            TYPE_ALIAS_ROOT_JUMP_A_TO_B.name,
            TYPE_ALIAS_ROOT_JUMP_B_TO_A.name,
        )?;
    }
    if type_alias_root_jump_rounds % 2 != 0 {
        TYPE_ALIAS_ROOT_JUMP_FINAL_A_TO_B.register_kernel(&mut graph, kernels)?;
    }
    let final_alias_root = if type_alias_root_jump_rounds % 2 == 0 {
        _alias_root_a
    } else {
        _alias_root_b
    };
    let register_type_alias_projection =
        |graph: &mut CompilerGraphBuilder, name: &'static str| -> Result<(), String> {
            graph.add_kernel_pass_by_name(
                name,
                CompilerPhase::TypeCheck,
                ResourceDomain::Declarations,
                kernels,
                "type_checker/modules/10e2_project_type_aliases",
                reflected_bindings!["alias_root_decl" => final_alias_root: Read],
            )?;
            graph.add_indirect_dispatch(name, "decl_key_radix_dispatch_args")?;
            Ok(())
        };
    register_type_alias_projection(&mut graph, TYPE_ALIAS_PROJECT_PASS)?;
    TYPE_PATHS_PROJECT_AFTER_ALIASES.register_kernel(&mut graph, kernels)?;
    for operation in [
        TYPE_INSTANCES_COLLECT_PROJECTED,
        TYPE_INSTANCES_COLLECT_PROJECTED_NAMED,
        TYPE_INSTANCES_COLLECT_PROJECTED_AGGREGATE_REFS,
        TYPE_INSTANCES_COLLECT_PROJECTED_AGGREGATE_DETAILS,
    ] {
        operation.register_kernel(&mut graph, kernels)?;
    }
    register_type_alias_projection(&mut graph, TYPE_ALIAS_PROJECT_AFTER_PROJECTED_REFS_PASS)?;
    TYPE_PATHS_PROJECT_AFTER_PROJECTED_ALIASES.register_kernel(&mut graph, kernels)?;
    TYPE_INSTANCES_PROJECT.register_kernel(&mut graph, kernels)?;
    add_dependency_type_index_passes(
        &mut graph,
        kernels,
        DEPENDENCY_TYPE_INDEX_TYPE_INSTANCE_PROJECTION,
        canonical_type_jump_rounds,
        dependency_canonical_type_roots_a,
        dependency_canonical_type_roots_b,
        dependency_canonical_type_subtree_a,
        dependency_canonical_type_subtree_b,
        dependency_declaration_generic_arity,
        dependency_declaration_field_count,
    )?;
    graph.add_kernel_pass_by_name(
        DEPENDENCY_TYPE_INSTANCES_PROJECT.name,
        CompilerPhase::TypeCheck,
        ResourceDomain::Declarations,
        kernels,
        DEPENDENCY_TYPE_INSTANCES_PROJECT.kernel,
        reflected_bindings![
            "canonical_type_roots" => dependency_canonical_type_roots: Read,
            "declaration_generic_arity" => dependency_declaration_generic_arity: Read,
            "declaration_field_count" => dependency_declaration_field_count: Read,
        ],
    )?;
    graph.add_indirect_dispatch(DEPENDENCY_TYPE_INSTANCES_PROJECT.name, "path_dispatch_args")?;
    for operation in [
        TYPE_ALIAS_EQUIVALENCE_CLEAR,
        TYPE_ALIAS_EQUIVALENCE_DECL_EDGES_INITIALIZE,
        TYPE_ALIAS_EQUIVALENCE_ARG_EDGES_INITIALIZE,
    ] {
        operation.register_kernel(&mut graph, kernels)?;
    }
    if type_alias_equivalence_rounds >= 2 {
        for operation in [
            TYPE_ALIAS_EQUIVALENCE_HOOK_A,
            TYPE_ALIAS_EQUIVALENCE_JUMP_A_TO_B,
            TYPE_ALIAS_EQUIVALENCE_HOOK_B,
            TYPE_ALIAS_EQUIVALENCE_JUMP_B_TO_A,
        ] {
            operation.register_kernel(&mut graph, kernels)?;
        }
        graph.repeat_pass_range(
            type_alias_equivalence_rounds / 2,
            TYPE_ALIAS_EQUIVALENCE_HOOK_A.name,
            TYPE_ALIAS_EQUIVALENCE_JUMP_B_TO_A.name,
        )?;
    }
    if type_alias_equivalence_rounds % 2 != 0 {
        TYPE_ALIAS_EQUIVALENCE_FINAL_HOOK_A.register_kernel(&mut graph, kernels)?;
        TYPE_ALIAS_EQUIVALENCE_FINAL_JUMP_A_TO_B.register_kernel(&mut graph, kernels)?;
    }
    let final_alias_equivalence_parent = if type_alias_equivalence_rounds % 2 == 0 {
        _alias_equiv_parent_a
    } else {
        _alias_equiv_parent_b
    };
    for (name, kernel) in [
        (
            TYPE_ALIAS_GENERIC_SOURCES_SELECT_PASS,
            "type_checker/modules/10e0h_select_type_alias_generic_sources",
        ),
        (
            TYPE_ALIAS_CONCRETE_SOURCES_SELECT_PASS,
            "type_checker/modules/10e0i_select_type_alias_concrete_sources",
        ),
        (
            TYPE_ALIAS_EQUIVALENCE_FINALIZE_PASS,
            "type_checker/modules/10e0j_finalize_type_alias_equivalence",
        ),
    ] {
        graph.add_kernel_pass_by_name(
            name,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            kernel,
            reflected_bindings![
                "alias_equiv_parent" => final_alias_equivalence_parent: Read
            ],
        )?;
        if name == TYPE_ALIAS_EQUIVALENCE_FINALIZE_PASS {
            graph.add_indirect_dispatch(name, "decl_key_radix_dispatch_args")?;
        }
    }
    TYPE_PATHS_PROJECT_AFTER_ALIAS_EQUIVALENCE.register_kernel(&mut graph, kernels)?;
    // Expression typing executes after call argument matching has published
    // per-call generic and aggregate result dependencies. Keep the graph in
    // the same order as command recording so ownership validation describes
    // the actual GPU schedule.
    // Preserve the precise producer contract so workspace liveness starts at
    // the receiver projection rather than requiring hidden preinitialization.
    let member_receiver_overrides = reflected_bindings![
        "member_result_context_instance" => member_result_context_instance: Write,
        "member_result_ref_tag" => member_result_ref_tag: Write,
        "member_result_ref_payload" => member_result_ref_payload: Write,
        "member_result_field_ordinal" => member_result_field_ordinal: Write,
        "member_result_field_node" => member_result_field_node: Write,
    ];
    let final_scalar = scalar_a;
    let add_expression_type_passes =
        |graph: &mut CompilerGraphBuilder| -> std::result::Result<(), String> {
            graph.add_kernel_pass_by_name(
                INIT_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                kernels,
                "type_checker/semantic/expression_types/00_init",
                reflected_bindings!["compact_expr_scalar_type_out" => scalar_a: Write],
            )?;
            graph.add_kernel_pass_by_name(
                SEMANTIC_EXPRESSION_REFS_PROJECT_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                kernels,
                "type_checker/semantic/artifact/01_expression_refs",
                reflected_bindings![
                    "compact_expr_scalar_type" => final_scalar,
                    "type_instance_decl_token" => _type_instance_decl_token: Read,
                    "type_instance_aggregate_word_count" => _type_instance_aggregate_word_count: Read,
                    "resolved_type_decl" => _resolved_type_decl: Read,
                    "decl_name_token" => decl_name_token: Read,
                    "semantic_expr_ref_tag_by_hir" => semantic_expr_ref_tag_by_hir: Write,
                    "semantic_expr_ref_payload_by_hir" => semantic_expr_ref_payload_by_hir: Write,
                    "semantic_aggregate_decl_token_by_hir" => semantic_aggregate_decl_token_by_hir: Write,
                    "semantic_aggregate_word_count_by_hir" => semantic_aggregate_word_count_by_hir: ReadWrite,
                    "semantic_array_length_by_hir" => semantic_array_length_by_hir: Write,
                    "semantic_member_field_ordinal_by_hir" => semantic_member_field_ordinal_by_hir: Write,
                    "semantic_iterable_kind_by_hir" => semantic_iterable_kind_by_hir: Write,
                    "semantic_function_result_word_count_by_hir" => semantic_function_result_word_count_by_hir: Write,
                ],
            )?;
            graph.add_kernel_pass_by_name(
                SEMANTIC_STRUCT_LITERAL_REFS_PROJECT_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                kernels,
                "type_checker/semantic/artifact/01a_struct_literal_refs",
                &[],
            )?;
            graph.add_kernel_pass_by_name(
                SEMANTIC_ARRAY_INDEX_REFS_PROJECT_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                kernels,
                "type_checker/semantic/artifact/01b_array_index_refs",
                reflected_bindings![
                    "semantic_aggregate_decl_token_by_hir" => semantic_aggregate_decl_token_by_hir: ReadWrite,
                    "semantic_iterable_kind_by_hir" => semantic_iterable_kind_by_hir: Write,
                    "semantic_function_result_word_count_by_hir" => semantic_function_result_word_count_by_hir: Write,
                ],
            )?;
            graph.add_kernel_pass_by_name(
                CONDITIONS_COMPACT_EXPR_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                kernels,
                "type_checker/conditions/compact_expr",
                reflected_bindings!["compact_expr_scalar_type" => final_scalar],
            )?;
            graph.add_kernel_pass_by_name(
                CONDITIONS_COMPACT_STMT_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                kernels,
                "type_checker/conditions/compact_stmt",
                reflected_bindings!["compact_expr_scalar_type" => final_scalar],
            )?;
            graph.add_kernel_pass_by_name(
                CONDITIONS_COMPACT_AGGREGATE_REQUESTS_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                kernels,
                "type_checker/conditions/compact_aggregate_requests",
                &[],
            )?;
            let aggregate_scan_resources =
                graph.resolve_prefix_scan_resources(AGGREGATE_SCAN_RESOURCES)?;
            graph.add_fragment(PrefixScanGraph {
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::HirNodes,
                hierarchy_levels: prefix_scan_hierarchy_levels(hir_blocks),
                passes: AGGREGATE_FINAL_SCAN_PASSES,
                resources: aggregate_scan_resources,
            })?;
            graph.add_kernel_pass_by_name(
                AGGREGATE_FINAL_DISPATCH_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                kernels,
                "type_checker/count/dispatch_args",
                reflected_bindings![
                    "count_in" => aggregate_compare_count_out,
                    "dispatch_args" => aggregate_compare_dispatch_args: Write,
                ],
            )?;
            graph.add_kernel_pass_by_name(
                CONDITIONS_AGGREGATE_ARGS_FINAL_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::CallArguments,
                kernels,
                "type_checker/conditions/aggregate_args",
                reflected_bindings![
                    "call_generic_slot_type" => call_generic_slot_type: ReadWrite,
                    "type_subtree_compare_scan_input" => type_subtree_compare_scan_input: Write,
                    "type_subtree_compare_left_root" => type_subtree_compare_left_root: Write,
                    "type_subtree_compare_right_root" => type_subtree_compare_right_root: Write,
                    "type_subtree_compare_error_token" => type_subtree_compare_error_token: Write,
                    "type_subtree_compare_error_detail" => type_subtree_compare_error_detail: Write,
                ],
            )?;
            graph.add_indirect_dispatch(
                CONDITIONS_AGGREGATE_ARGS_FINAL_PASS,
                "aggregate_compare_dispatch_args",
            )?;
            add_type_subtree_passes(
                graph,
                kernels,
                TYPE_SUBTREE_FINAL_SCAN_PASSES,
                TYPE_SUBTREE_FINAL_DISPATCH_PASS,
                TYPE_SUBTREE_FINAL_INDIRECT_PASS,
                prefix_scan_hierarchy_levels(hir_blocks),
            )?;
            METHODS_MARK_CALL_KEYS_CONDITION_FINALIZATION.register_kernel(graph, kernels)?;
            ConditionFinalizationOperation::register(graph, kernels)?;
            Ok(())
        };
    TYPE_INSTANCE_ARG_ROW_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(token_blocks))?;
    TYPE_INSTANCES_COLLECT_NAMED_ARG_REFS.register_kernel(&mut graph, kernels)?;
    TYPE_ALIAS_INSTANCES_PROJECT.register_kernel(&mut graph, kernels)?;
    graph.add_kernel_pass_by_name(
        TYPE_INSTANCE_ARG_HASH_ROWS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Types,
        kernels,
        "type_checker/type/instances/01g_hash_arg_rows",
        reflected_bindings!["type_instance_arg_hash" => type_instance_arg_hash: Write],
    )?;
    graph.add_kernel_pass_by_name(
        TYPE_SEMANTIC_CLEAR_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        "type_checker/type/instances/01h_clear_semantic_type_rows",
        reflected_bindings![
            "type_semantic_row_by_token" => type_semantic_row_by_token: Write,
            "type_semantic_scan_input" => type_semantic_scan_input: Write,
            "member_next_node" => member_next_node: Write,
        ],
    )?;
    TYPE_SEMANTIC_COMPACTION.register(
        &mut graph,
        kernels,
        prefix_scan_hierarchy_levels(hir_blocks),
    )?;
    graph.add_kernel_pass_by_name(
        FN_CONTEXT_CLEAR_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        "type_checker/fn/context/01_clear",
        reflected_bindings![
            "enclosing_fn" => enclosing_fn: Write,
            "enclosing_fn_end" => enclosing_fn_end: Write,
            "fn_event_value" => fn_event_value: Write,
            "fn_event_end" => fn_event_end: Write,
            "fn_event_index" => fn_event_index: Write,
            "fn_event_inblock" => fn_event_inblock: Write,
            "block_sum" => fn_block_sum: Write,
            "block_prefix" => fn_block_prefix: Write,
        ],
    )?;
    graph.add_kernel_pass_by_name(
        FN_CONTEXT_MARK_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/fn/context/02_mark",
        &[],
    )?;
    graph.add_indirect_dispatch(FN_CONTEXT_MARK_PASS, "hir_active_dispatch_args")?;
    graph.add_kernel_pass_by_name(
        FN_CONTEXT_LOCAL_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        "type_checker/fn/context/03_local",
        reflected_bindings![
            "fn_event_inblock" => fn_event_inblock: Write,
            "block_sum" => fn_block_sum: Write,
        ],
    )?;
    add_control_hierarchy_passes(
        &mut graph,
        kernels,
        ControlHierarchyGraphSpec {
            up_first: FN_CONTEXT_SCAN_UP_FIRST_PASS,
            up_rest: FN_CONTEXT_SCAN_UP_REST_PASS,
            down: FN_CONTEXT_SCAN_DOWN_PASS,
            up_kernel: "type_checker/fn/context/04_hierarchy_up",
            down_kernel: "type_checker/fn/context/04_hierarchy_down",
        },
        prefix_scan_hierarchy_levels(token_blocks),
        fn_block_sum,
        fn_prefix_a,
        fn_prefix_b,
        fn_block_prefix,
    )?;
    graph.add_kernel_pass_by_name(
        FN_CONTEXT_APPLY_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        "type_checker/fn/context/05_apply",
        reflected_bindings![
            "block_prefix" => fn_block_prefix: Read,
            "enclosing_fn" => enclosing_fn: Write,
            "enclosing_fn_end" => enclosing_fn_end: Write,
        ],
    )?;
    CALLS_CLEAR.register_kernel(&mut graph, kernels)?;
    CALLS_ENTRYPOINT_CLEAR.register_kernel(&mut graph, kernels)?;
    CALLS_RETURN_REFS.register_kernel(&mut graph, kernels)?;
    CALLS_ENTRYPOINT_PROJECT.register_kernel(&mut graph, kernels)?;
    CALLS_FUNCTIONS.register_kernel(&mut graph, kernels)?;
    CALLS_PARAM_TYPES.register_kernel(&mut graph, kernels)?;
    add_dependency_page_replay_passes(
        &mut graph,
        kernels,
        DEPENDENCY_PAGE_CALL_COLLECTION,
        DEPENDENCY_VISIBLE_SCAN_CALL_COLLECTION,
        record_scan_levels,
        canonical_type_jump_rounds,
        dependency_canonical_type_roots_a,
        dependency_canonical_type_roots_b,
        dependency_canonical_type_subtree_a,
        dependency_canonical_type_subtree_b,
        dependency_canonical_type_roots,
        dependency_declaration_generic_arity,
        dependency_declaration_field_count,
        dependency_resolved_type_decl,
    )?;
    graph.add_kernel_pass_by_name(
        DEPENDENCY_CALLS_PROJECT.name,
        CompilerPhase::TypeCheck,
        ResourceDomain::Calls,
        kernels,
        DEPENDENCY_CALLS_PROJECT.kernel,
        reflected_bindings![
            "canonical_type_roots" => dependency_canonical_type_roots: Read,
            "declaration_field_count" => dependency_declaration_field_count: Read,
        ],
    )?;
    graph.add_indirect_dispatch(DEPENDENCY_CALLS_PROJECT.name, "hir_active_dispatch_args")?;
    DEPENDENCY_CALL_PARAMS_PROJECT.register_kernel(&mut graph, kernels)?;
    CALL_PARAM_ROW_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(token_blocks))?;
    CALLS_PARAM_SCATTER.register_kernel(&mut graph, kernels)?;
    add_dependency_type_index_passes(
        &mut graph,
        kernels,
        DEPENDENCY_TYPE_INDEX_CALL_PARAM_SCATTER,
        canonical_type_jump_rounds,
        dependency_canonical_type_roots_a,
        dependency_canonical_type_roots_b,
        dependency_canonical_type_subtree_a,
        dependency_canonical_type_subtree_b,
        dependency_declaration_generic_arity,
        dependency_declaration_field_count,
    )?;
    graph.add_kernel_pass_by_name(
        DEPENDENCY_CALL_PARAMS_SCATTER.name,
        CompilerPhase::TypeCheck,
        ResourceDomain::CallArguments,
        kernels,
        DEPENDENCY_CALL_PARAMS_SCATTER.kernel,
        reflected_bindings![
            "canonical_type_roots" => dependency_canonical_type_roots: Read,
        ],
    )?;
    graph.add_indirect_dispatch(
        DEPENDENCY_CALL_PARAMS_SCATTER.name,
        "hir_active_dispatch_args",
    )?;
    // The resident recorder completes call-argument compaction before method
    // and struct-field indexing. Keep the graph in that same order so compact
    // call rows remain live while those indexes are constructed.
    CALLS_INTRINSICS.register_kernel(&mut graph, kernels)?;
    CALLS_ARGUMENT_CLEAR.register_kernel(&mut graph, kernels)?;
    CALLS_ARGUMENT_PACK.register_kernel(&mut graph, kernels)?;
    CALL_ARGUMENT_COMPACTION.register(
        &mut graph,
        kernels,
        prefix_scan_hierarchy_levels(hir_blocks),
    )?;
    let add_method_and_field_passes =
        |graph: &mut CompilerGraphBuilder| -> std::result::Result<(), String> {
            METHODS_CLEAR.register_kernel(graph, kernels)?;
            METHODS_COLLECT.register_kernel(graph, kernels)?;
            METHODS_ATTACH_METADATA.register_kernel(graph, kernels)?;
            METHODS_BIND_SELF_RECEIVERS.register_kernel(graph, kernels)?;
            graph.add_kernel_pass_by_name(
                TYPE_INSTANCES_MEMBER_RECEIVERS_PASS,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                kernels,
                "type_checker/type/instances/03a_member_receivers",
                member_receiver_overrides,
            )?;
            STRUCT_FIELD_LOOKUP_CLEAR.register_kernel(graph, kernels)?;
            STRUCT_FIELD_LOOKUP_BUILD.register_kernel(graph, kernels)?;
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
        reflected_bindings![
            "struct_init_field_context_instance" => struct_init_field_context_instance: Write,
            "struct_init_field_expected_ref_tag" => struct_init_field_expected_ref_tag: Write,
            "struct_init_field_expected_ref_payload" => struct_init_field_expected_ref_payload: Write,
            "struct_init_field_ordinal" => struct_init_field_ordinal: Write,
            "struct_lit_context_decl_token" => struct_lit_context_decl_token: Write,
            "struct_lit_context_instance" => struct_lit_context_instance: Write,
            "struct_init_field_ordinal_by_row" => struct_init_field_ordinal_by_row: Write,
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
                ResourceDomain::HirNodes,
                kernels,
                "type_checker/type/instances/04_struct_init_fields",
                &[],
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
                    PassAccess::write(
                        "semantic_aggregate_decl_token_by_hir",
                        semantic_aggregate_decl_token_by_hir,
                    ),
                ],
            })?;
            graph.add_pass(PassDesc {
                name: SEMANTIC_STRUCT_LITERAL_REFS_EARLY_PROJECT_PASS,
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read("compact_hir_core", compact_hir_core),
                    PassAccess::read("compact_hir_payload", _compact_hir_payload),
                    PassAccess::read(
                        "struct_lit_context_decl_token",
                        struct_lit_context_decl_token,
                    ),
                    PassAccess::read("struct_lit_context_instance", struct_lit_context_instance),
                    PassAccess::read("decl_type_ref_tag", decl_type_ref_tag),
                    PassAccess::read("decl_type_ref_payload", decl_type_ref_payload),
                    PassAccess::read("type_instance_decl_token", _type_instance_decl_token),
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
                        "semantic_aggregate_decl_token_by_hir",
                        semantic_aggregate_decl_token_by_hir,
                    ),
                    PassAccess::write(
                        "semantic_member_field_ordinal_by_hir",
                        semantic_member_field_ordinal_by_hir,
                    ),
                ],
            })?;
            graph.assign_kernel(
                SEMANTIC_STRUCT_LITERAL_REFS_EARLY_PROJECT_PASS,
                "type_checker/semantic/artifact/01a_struct_literal_refs",
            )?;
            graph.require_complete_reflection(SEMANTIC_STRUCT_LITERAL_REFS_EARLY_PROJECT_PASS)?;
            Ok(())
        };
    graph.add_kernel_pass_by_name(
        VISIBLE_CLEAR_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        "type_checker/visible/01/clear/resident",
        reflected_bindings![
            "visible_decl" => visible_decl: Write,
            "visible_type" => visible_type: Write,
            "hir_value_decl_name_present" => hir_value_decl_name_present: Write,
            "hir_visible_decl_flag" => hir_visible_decl_flag: Write,
            "hir_visible_decl_source_by_token" => hir_visible_decl_key_order_tmp: Write,
        ],
    )?;
    VISIBLE_HIR_DECL_MARK.register_kernel(&mut graph, kernels)?;
    graph.add_kernel_pass_by_name(
        VISIBLE_MATCH_DISPATCH_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::DispatchArguments,
        kernels,
        "type_checker/count/dispatch_args",
        reflected_bindings![
            "count_in" => compact_match_payload_row_count,
            "dispatch_args" => match_payload_dispatch_args: Write,
        ],
    )?;
    VISIBLE_MATCH_DECL_MARK.register_kernel(&mut graph, kernels)?;
    VISIBLE_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(token_blocks))?;
    VISIBLE_DECL_SCATTER.register_kernel(&mut graph, kernels)?;
    let visible_radix_steps = visible_decl_key_radix_steps(token_capacity);
    if let Some(hir_visible_decl_key_radix_dispatch_args) = hir_visible_decl_key_radix_dispatch_args
    {
        graph.add_pass(PassDesc {
            name: VISIBLE_RADIX_DISPATCH_PASS,
            phase: CompilerPhase::TypeCheck,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("name_count_in", hir_visible_decl_count_out),
                PassAccess::write(
                    "radix_dispatch_args",
                    hir_visible_decl_key_radix_dispatch_args,
                ),
            ],
        })?;
    }
    VISIBLE_RADIX_SORT.register(
        &mut graph,
        token_capacity,
        VISIBLE_DECL_SMALL_SORT_CAPACITY,
        visible_radix_steps,
        &["hir_visible_decl_owner_fn", "hir_visible_decl_name_id"],
    )?;
    VISIBLE_SCOPE_TREE_LEAVES.register_kernel(&mut graph, kernels)?;
    let visible_tree_level_count = visible_tree_leaf_base.trailing_zeros();
    if visible_tree_level_count > 0 {
        VISIBLE_SCOPE_TREE_LEVEL.register_kernel(&mut graph, kernels)?;
        graph.repeat_pass_range(
            visible_tree_level_count,
            VISIBLE_SCOPE_TREE_LEVEL.name,
            VISIBLE_SCOPE_TREE_LEVEL.name,
        )?;
    }
    VISIBLE_NAMES.register_kernel(&mut graph, kernels)?;
    TYPE_INSTANCES_DECL_REFS.register_kernel(&mut graph, kernels)?;
    TYPE_INSTANCES_DECL_REFS_FOR_BINDINGS.register_kernel(&mut graph, kernels)?;
    add_method_and_field_passes(&mut graph)?;
    MATCH_PATTERNS_BIND.register_kernel(&mut graph, kernels)?;
    MATCH_PAYLOADS_TYPE.register_kernel(&mut graph, kernels)?;
    graph.add_kernel_pass_by_name(
        SCOPE_HIR_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        "type_checker/scope/hir",
        &[],
    )?;
    CALLS_RESOLVE.register_kernel(&mut graph, kernels)?;
    CALLS_ARGUMENT_MATCH_INITIALIZE.register_kernel(&mut graph, kernels)?;
    CALLS_ARGUMENT_MATCH_CONSUME.register_kernel(&mut graph, kernels)?;
    CALLS_APPLY_ARGUMENTS.register_kernel(&mut graph, kernels)?;
    METHODS_MARK_CALL_KEYS.register_kernel(&mut graph, kernels)?;
    add_dependency_type_index_passes(
        &mut graph,
        kernels,
        DEPENDENCY_TYPE_INDEX_METHOD_PROJECTION,
        canonical_type_jump_rounds,
        dependency_canonical_type_roots_a,
        dependency_canonical_type_roots_b,
        dependency_canonical_type_subtree_a,
        dependency_canonical_type_subtree_b,
        dependency_declaration_generic_arity,
        dependency_declaration_field_count,
    )?;
    graph.add_kernel_pass_by_name(
        DEPENDENCY_METHODS_PROJECT_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/dependencies/15_project_methods",
        reflected_bindings![
            "canonical_type_roots" => dependency_canonical_type_roots: Read,
        ],
    )?;
    graph.add_indirect_dispatch(DEPENDENCY_METHODS_PROJECT_PASS, "hir_active_dispatch_args")?;
    VALUE_CALLS_CONSUME.register_kernel(&mut graph, kernels)?;
    VALUE_CALL_LEAF_MIRROR.register_kernel(&mut graph, kernels)?;
    CALLS_ARGUMENT_MATCH_MODULE_INITIALIZE.register_kernel(&mut graph, kernels)?;
    CALLS_ARGUMENT_MATCH_MODULE_CONSUME.register_kernel(&mut graph, kernels)?;
    CALLS_APPLY_MODULE_ARGUMENTS.register_kernel(&mut graph, kernels)?;
    VALUE_CALL_LEAF_MIRROR_AFTER_ROW_ARGS.register_kernel(&mut graph, kernels)?;
    METHODS_LOOKUP_CLEAR.register_kernel(&mut graph, kernels)?;
    METHODS_LOOKUP_BUILD.register_kernel(&mut graph, kernels)?;
    METHODS_VALIDATE_KEYS.register_kernel(&mut graph, kernels)?;
    METHODS_MARK_CALL_KEYS_LOOKUP.register_kernel(&mut graph, kernels)?;
    METHODS_MARK_CALL_RETURN_KEYS.register_kernel(&mut graph, kernels)?;
    METHODS_RESOLVE_TABLE.register_kernel(&mut graph, kernels)?;
    graph.repeat_pass_range(
        8,
        METHODS_MARK_CALL_RETURN_KEYS.name,
        METHODS_RESOLVE_TABLE.name,
    )?;
    CALLS_RESULT_INSTANCE_PROJECT.register_kernel(&mut graph, kernels)?;
    CALLS_ARGUMENT_MATCH_METHOD_RESULT_INITIALIZE.register_kernel(&mut graph, kernels)?;
    CALLS_ARGUMENT_MATCH_METHOD_RESULT_CONSUME.register_kernel(&mut graph, kernels)?;
    CALLS_APPLY_METHOD_RESULT_ARGUMENTS.register_kernel(&mut graph, kernels)?;
    VALUE_CALLS_CONSUME_AFTER_METHODS.register_kernel(&mut graph, kernels)?;
    VALUE_CALL_LEAF_MIRROR_AFTER_METHODS.register_kernel(&mut graph, kernels)?;
    CALLS_ARGUMENT_MATCH_METHOD_MODULE_INITIALIZE.register_kernel(&mut graph, kernels)?;
    CALLS_ARGUMENT_MATCH_METHOD_MODULE_CONSUME.register_kernel(&mut graph, kernels)?;
    CALLS_APPLY_METHOD_MODULE_ARGUMENTS.register_kernel(&mut graph, kernels)?;
    VALUE_CALL_LEAF_MIRROR_AFTER_METHOD_ROW_ARGS.register_kernel(&mut graph, kernels)?;
    CALLS_INFER_ARRAY_GENERICS.register_kernel(&mut graph, kernels)?;
    CALLS_ARRAY_STATE_PUBLISH.register_kernel(&mut graph, kernels)?;
    CALLS_ARRAY_STATE_CONSUME.register_kernel(&mut graph, kernels)?;
    CALLS_GENERIC_PARAMS_ERASE.register_kernel(&mut graph, kernels)?;
    VALUE_ENUM_CALLS_CONSUME.register_kernel(&mut graph, kernels)?;
    VALUE_ENUM_CALL_PAYLOADS_VALIDATE.register_kernel(&mut graph, kernels)?;
    VALUE_ENUM_CALLS_FINALIZE.register_kernel(&mut graph, kernels)?;
    MATCH_EXPRS_TYPE.register_kernel(&mut graph, kernels)?;
    VALUE_CONSTS_CONSUME.register_kernel(&mut graph, kernels)?;
    VALUE_ENUM_UNITS_CONSUME.register_kernel(&mut graph, kernels)?;
    METHODS_RESOLVE.register_kernel(&mut graph, kernels)?;
    CALLS_ARGUMENT_MATCH_FINAL_INITIALIZE.register_kernel(&mut graph, kernels)?;
    CALLS_ARGUMENT_MATCH_FINAL_CONSUME.register_kernel(&mut graph, kernels)?;
    // The recorder validates and resolves the claims produced by final
    // argument matching before publishing those arguments to call state.
    // Keep that semantic interval in the graph's real execution order so
    // neither the claim inputs nor the delayed apply inputs can be colored
    // onto scratch used by the intervening operations.
    CALLS_GENERIC_CLAIM_CLEAR.register_kernel(&mut graph, kernels)?;
    GENERIC_CLAIM_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(call_arg_blocks))?;
    CALLS_GENERIC_CLAIM_EMIT.register_kernel(&mut graph, kernels)?;
    graph.add_kernel_pass_by_name(
        GENERIC_CLAIM_INDEX_PREPARE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::DispatchArguments,
        kernels,
        "type_checker/count/dispatch_args",
        reflected_bindings![
            "count_in" => generic_claim_count_out,
            "dispatch_args" => generic_claim_index_dispatch_args: Write,
        ],
    )?;
    CALLS_GENERIC_CLAIM_INDEX_CLEAR.register_kernel(&mut graph, kernels)?;
    CALLS_GENERIC_CLAIM_INDEX_BUILD.register_kernel(&mut graph, kernels)?;
    CALLS_GENERIC_CLAIM_VALIDATE.register_kernel(&mut graph, kernels)?;
    CALLS_REQUIRED_GENERIC_MARK.register_kernel(&mut graph, kernels)?;
    REQUIRED_GENERIC_SCAN.register(&mut graph, prefix_scan_hierarchy_levels(hir_blocks))?;
    graph.add_kernel_pass_by_name(
        REQUIRED_GENERIC_DISPATCH_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::DispatchArguments,
        kernels,
        "type_checker/count/dispatch_args",
        reflected_bindings![
            "count_in" => required_generic_count_out,
            "dispatch_args" => required_generic_dispatch_args: Write,
        ],
    )?;
    graph.add_kernel_pass_by_name(
        CONST_CLAIM_INDEX_PREPARE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::DispatchArguments,
        kernels,
        "type_checker/count/dispatch_args",
        reflected_bindings![
            "count_in" => call_arg_row_count_out,
            "dispatch_args" => const_claim_index_dispatch_args: Write,
        ],
    )?;
    CALLS_CONST_CLAIM_INDEX_CLEAR.register_kernel(&mut graph, kernels)?;
    CALLS_CONST_CLAIM_INDEX_BUILD.register_kernel(&mut graph, kernels)?;
    CALLS_CONST_CLAIM_VALIDATE.register_kernel(&mut graph, kernels)?;
    CALLS_CONTEXTUAL_RESULT_REQUESTS.register_kernel(&mut graph, kernels)?;
    graph.add_kernel_pass_by_name(
        DEPENDENCY_GENERIC_CALL_RESULTS_RESOLVE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/dependencies/08a_validate_call_results",
        reflected_bindings![
            "canonical_type_roots" => dependency_canonical_type_roots: Read,
            "canonical_type_subtree_start" => dependency_canonical_type_subtree_start: Read,
            "call_result_instance" => _call_result_instance: Write,
        ],
    )?;
    graph.add_indirect_dispatch(
        DEPENDENCY_GENERIC_CALL_RESULTS_RESOLVE_PASS,
        "hir_active_dispatch_args",
    )?;
    let aggregate_scan_resources = graph.resolve_prefix_scan_resources(AGGREGATE_SCAN_RESOURCES)?;
    graph.add_fragment(PrefixScanGraph {
        phase: CompilerPhase::TypeCheck,
        dispatch_domain: ResourceDomain::HirNodes,
        hierarchy_levels: prefix_scan_hierarchy_levels(hir_blocks),
        passes: AGGREGATE_CALL_SCAN_PASSES,
        resources: aggregate_scan_resources,
    })?;
    graph.add_kernel_pass_by_name(
        AGGREGATE_CALL_DISPATCH_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/count/dispatch_args",
        reflected_bindings![
            "count_in" => aggregate_compare_count_out,
            "dispatch_args" => aggregate_compare_dispatch_args: Write,
        ],
    )?;
    graph.add_kernel_pass_by_name(
        CONDITIONS_AGGREGATE_ARGS_CALLS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::CallArguments,
        kernels,
        "type_checker/conditions/aggregate_args",
        reflected_bindings![
            "call_generic_slot_type" => call_generic_slot_type: ReadWrite,
            "type_subtree_compare_scan_input" => type_subtree_compare_scan_input: Write,
            "type_subtree_compare_left_root" => type_subtree_compare_left_root: Write,
            "type_subtree_compare_right_root" => type_subtree_compare_right_root: Write,
            "type_subtree_compare_error_token" => type_subtree_compare_error_token: Write,
            "type_subtree_compare_error_detail" => type_subtree_compare_error_detail: Write,
        ],
    )?;
    graph.add_indirect_dispatch(
        CONDITIONS_AGGREGATE_ARGS_CALLS_PASS,
        "aggregate_compare_dispatch_args",
    )?;
    add_type_subtree_passes(
        &mut graph,
        kernels,
        TYPE_SUBTREE_CALL_SCAN_PASSES,
        TYPE_SUBTREE_CALL_DISPATCH_PASS,
        TYPE_SUBTREE_CALL_INDIRECT_PASS,
        prefix_scan_hierarchy_levels(hir_blocks),
    )?;
    CALLS_REQUIRED_GENERIC_VALIDATE.register_kernel(&mut graph, kernels)?;
    CALLS_APPLY_FINAL_ARGUMENTS.register_kernel(&mut graph, kernels)?;
    graph.add_kernel_pass_by_name(
        TYPE_INSTANCES_MEMBER_RECEIVERS_AFTER_ARRAY_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/type/instances/03a_member_receivers",
        member_receiver_overrides,
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
    TYPE_INSTANCES_ARRAY_RETURN_REFS.register_kernel(&mut graph, kernels)?;
    TYPE_INSTANCES_ARRAY_LITERAL_RETURN_REFS.register_kernel(&mut graph, kernels)?;
    graph.add_kernel_pass_by_name(
        TYPE_INSTANCES_STRUCT_INIT_SUBSTITUTE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        "type_checker/type/instances/04b_struct_init_substitute",
        &[],
    )?;
    METHODS_MARK_CALL_KEYS_AGGREGATE_VALIDATION.register_kernel(&mut graph, kernels)?;
    graph.add_kernel_pass_by_name(
        TYPE_INSTANCES_VALIDATE_AGGREGATE_ACCESS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/type/instances/08_validate_aggregate_access",
        &[],
    )?;
    {
        let predicate_clear_overrides = reflected_bindings![
            "predicate_trait_impl_trait_type_node" => predicate_trait_impl_trait_type_node: Write,
            "predicate_owner_node" => predicate_owner_node: Write,
            "predicate_subject_token" => predicate_subject_token: Write,
            "predicate_bound_token" => predicate_bound_token: Write,
            "predicate_bound_decl_id" => predicate_bound_decl_id: Write,
            "predicate_bound_arg_count" => predicate_bound_arg_count: Write,
            "predicate_bound_first_arg_token" => predicate_bound_first_arg_token: Write,
            "predicate_bound_second_arg_token" => predicate_bound_second_arg_token: Write,
            "predicate_status" => predicate_status: Write,
            "predicate_method_contract_owner_count" => predicate_method_contract_owner_count: Write,
            "predicate_method_contract_lookup_head" => predicate_method_contract_lookup_head: Write,
            "predicate_method_validation_status" => predicate_method_validation_status: Write,
            "predicate_method_validation_first_error_row" => predicate_method_validation_first_error_row: Write,
            "predicate_owner_lookup_head" => predicate_owner_lookup_head: Write,
            "predicate_owner_lookup_next" => predicate_owner_lookup_next: Write,
            "predicate_impl_lookup_head" => predicate_impl_lookup_head: Write,
        ];
        graph.add_kernel_pass_by_name(
            PREDICATES_CLEAR_BOUND_ARG_FACTS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/predicates/00_clear_bound_arg_facts",
            predicate_clear_overrides,
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
            reflected_bindings![
                "predicate_method_contract_owner_hir" => predicate_method_contract_owner_hir: Write,
                "predicate_method_contract_name_token" => predicate_method_contract_name_token: Write,
                "predicate_method_contract_name_id" => predicate_method_contract_name_id: Write,
                "predicate_method_contract_param_count" => predicate_method_contract_param_count: Write,
                "predicate_method_contract_return_type_node" => predicate_method_contract_return_type_node: Write,
                "predicate_method_contract_visibility" => predicate_method_contract_visibility: Write,
                "predicate_method_contract_status" => predicate_method_contract_status: Write,
                "predicate_method_contract_param_type_node" => predicate_method_contract_param_type_node: Write,
                "predicate_method_contract_lookup_next" => predicate_method_contract_lookup_next: Write,
            ],
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
            reflected_bindings![
                "predicate_impl_lookup_next" => predicate_impl_lookup_next: Write,
            ],
        )?;
        graph.add_kernel_pass_by_name(
            PREDICATES_EMIT_METHOD_VALIDATION_ROWS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/predicates/01f_emit_method_validation_rows",
            reflected_bindings![
                "predicate_method_validation_owner_node" => predicate_method_validation_owner_node: Write,
                "predicate_method_validation_peer_node" => predicate_method_validation_peer_node: Write,
                "predicate_method_validation_detail_token" => predicate_method_validation_detail_token: Write,
            ],
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
        graph.add_kernel_pass_by_name(
            PREDICATES_COUNT_OBLIGATION_PAIRS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/predicates/02a_count_obligations",
            reflected_bindings![
                "predicate_obligation_count_by_call" => predicate_obligation_count_by_call: Write,
            ],
        )?;
        PREDICATES_OBLIGATION_PAIR_SCAN
            .register(&mut graph, prefix_scan_hierarchy_levels(predicate_blocks))?;
        graph.add_buffer_clear_pass(
            PREDICATES_OBLIGATION_PAIR_DISPATCH_CLEAR_PASS,
            CompilerPhase::TypeCheck,
            "predicate_obligation_pair_dispatch_args",
            predicate_obligation_pair_dispatch_args,
        )?;
        graph.add_kernel_pass_by_name(
            PREDICATES_OBLIGATION_PAIR_DISPATCH_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::DispatchArguments,
            kernels,
            "type_checker/count/dispatch_args",
            reflected_bindings![
                "count_in" => predicate_obligation_pair_total,
                "dispatch_args" => predicate_obligation_pair_dispatch_args: Write,
            ],
        )?;
        graph.add_kernel_pass_by_name(
            PREDICATES_VALIDATE_OBLIGATION_PAIRS_PASS,
            CompilerPhase::TypeCheck,
            ResourceDomain::HirNodes,
            kernels,
            "type_checker/predicates/02b_validate_obligations",
            &[],
        )?;
        graph.add_indirect_dispatch(
            PREDICATES_CLEAR_BOUND_ARG_FACTS_PASS,
            "hir_active_dispatch_args",
        )?;
        for pass in [
            PREDICATES_COLLECT_BOUND_ARG_FACTS_PASS,
            PREDICATES_COLLECT_METHOD_CONTRACTS_PASS,
            PREDICATES_COLLECT_PASS,
            PREDICATES_VALIDATE_BOUND_ARGS_PASS,
            PREDICATES_COLLECT_IMPLS_PASS,
            PREDICATES_EMIT_METHOD_VALIDATION_ROWS_PASS,
            PREDICATES_EMIT_METHOD_PARAM_VALIDATION_ROWS_PASS,
            PREDICATES_VALIDATE_METHOD_TYPE_ARG_ROWS_PASS,
            PREDICATES_REDUCE_METHOD_VALIDATION_ERRORS_PASS,
            PREDICATES_COUNT_OBLIGATION_PAIRS_PASS,
        ] {
            graph.add_indirect_dispatch(pass, "predicate_hir_dispatch_args")?;
        }
        graph.add_indirect_dispatch(
            PREDICATES_OBLIGATION_PAIR_DISPATCH_PASS,
            "predicate_single_dispatch_args",
        )?;
        graph.add_indirect_dispatch(
            PREDICATES_VALIDATE_OBLIGATION_PAIRS_PASS,
            "predicate_obligation_pair_dispatch_args",
        )?;
    }
    if generic_param_record_passes_required(parser_feature_flags) {
        for pass in [
            TYPE_INSTANCES_MARK_GENERIC_PARAM_RECORDS_PASS,
            TYPE_INSTANCES_DECL_GENERIC_PARAMS_PASS,
            TYPE_INSTANCES_GENERIC_PARAM_USE_SLOTS_PASS,
        ] {
            graph.add_indirect_dispatch(pass, "hir_active_dispatch_args")?;
        }
    }
    for pass in [
        TYPE_INSTANCES_MEMBER_RECEIVERS_PASS,
        TYPE_INSTANCES_MEMBER_RESULTS_PASS,
        TYPE_INSTANCES_MEMBER_RECEIVERS_AFTER_ARRAY_PASS,
        TYPE_INSTANCES_MEMBER_RESULTS_AFTER_ARRAY_PASS,
        TYPE_INSTANCES_STRUCT_INIT_CONTEXTS_PASS,
        TYPE_INSTANCES_STRUCT_INIT_FIELDS_PASS,
        TYPE_INSTANCES_VALIDATE_AGGREGATE_ACCESS_PASS,
    ] {
        graph.add_indirect_dispatch(pass, "hir_active_dispatch_args")?;
    }
    for pass in [
        TYPE_INSTANCES_MEMBER_SUBSTITUTE_PASS,
        TYPE_INSTANCES_MEMBER_SUBSTITUTE_AFTER_ARRAY_PASS,
        TYPE_INSTANCES_STRUCT_INIT_SUBSTITUTE_PASS,
        TYPE_INSTANCE_ARG_HASH_ROWS_PASS,
        SCOPE_HIR_PASS,
    ] {
        graph.add_indirect_dispatch(pass, "token_active_dispatch_args")?;
    }
    ReturnValidationOperation::register(&mut graph, kernels)?;
    add_dependency_type_index_passes(
        &mut graph,
        kernels,
        DEPENDENCY_TYPE_INDEX_CALL_VALIDATION,
        canonical_type_jump_rounds,
        dependency_canonical_type_roots_a,
        dependency_canonical_type_roots_b,
        dependency_canonical_type_subtree_a,
        dependency_canonical_type_subtree_b,
        dependency_declaration_generic_arity,
        dependency_declaration_field_count,
    )?;
    let dependency_call_compare_scan_input = graph
        .resource_id("dependency_call_compare_scan_input")
        .ok_or("dependency call comparison requires its scan input")?;
    let call_result_instance = graph
        .resource_id("call_result_instance")
        .ok_or("dependency call results require call result instances")?;
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
        reflected_bindings![
            "canonical_type_roots" => dependency_canonical_type_roots: Read,
            "canonical_type_subtree_start" => dependency_canonical_type_subtree_start: Read,
        ],
    )?;
    graph.add_kernel_pass_by_name(
        DEPENDENCY_CALL_RESULTS_SUBSTITUTE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/dependencies/08a_validate_call_results",
        reflected_bindings![
            "canonical_type_roots" => dependency_canonical_type_roots: Read,
            "canonical_type_subtree_start" => dependency_canonical_type_subtree_start: Read,
            "call_result_instance" => call_result_instance: Write,
        ],
    )?;
    graph.add_kernel_pass_by_name(
        DEPENDENCY_CALL_RESULTS_VALIDATE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/dependencies/08a_validate_call_results",
        reflected_bindings![
            "canonical_type_roots" => dependency_canonical_type_roots: Read,
            "canonical_type_subtree_start" => dependency_canonical_type_subtree_start: Read,
            "call_result_instance" => call_result_instance: Write,
        ],
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
        reflected_bindings![
            "count_in" => dependency_call_compare_total,
            "dispatch_args" => dependency_call_compare_dispatch_args: Write,
        ],
    )?;
    graph.add_kernel_pass_by_name(
        DEPENDENCY_CALL_TYPE_ARGS_VALIDATE_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/dependencies/08b_validate_call_type_args",
        reflected_bindings![
            "canonical_type_roots" => dependency_canonical_type_roots: Read,
            "canonical_type_subtree_start" => dependency_canonical_type_subtree_start: Read,
        ],
    )?;
    for pass in [
        DEPENDENCY_CALL_ARGS_VALIDATE_PASS,
        DEPENDENCY_CALL_RESULTS_SUBSTITUTE_PASS,
        DEPENDENCY_CALL_RESULTS_VALIDATE_PASS,
    ] {
        graph.add_indirect_dispatch(pass, "hir_active_dispatch_args")?;
    }
    graph.add_indirect_dispatch(
        DEPENDENCY_CALL_TYPE_ARGS_VALIDATE_PASS,
        "dependency_call_compare_dispatch_args",
    )?;
    graph.add_kernel_pass_by_name(
        CALLS_BACKEND_TARGETS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        "type_checker/calls/04_backend_targets",
        reflected_bindings![
            "call_dependency_library_id" => _call_dependency_library_id: Read,
            "backend_call_fn_index" => backend_call_fn_index: Write,
        ],
    )?;
    graph.add_kernel_pass_by_name(
        SEMANTIC_CALLS_PROJECT_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/semantic/artifact/00_calls",
        reflected_bindings![
            "call_fn_index" => _call_fn_index: Read,
            "backend_call_fn_index" => backend_call_fn_index: Read,
            "compact_variant_count" => _compact_variant_count: Read,
            "compact_variants" => _compact_variants: Read,
            "resolved_value_decl" => _resolved_value_decl: Read,
            "decl_id_by_name_token" => decl_id_by_name_token: Read,
            "decl_kind" => decl_kind: Read,
            "decl_hir_node" => _decl_hir_node: Read,
            "call_dependency_library_id" => _call_dependency_library_id: Read,
            "call_dependency_unit_id" => _call_dependency_unit_id: Read,
            "call_dependency_local_index" => _call_dependency_local_index: Read,
            "call_dependency_host_service" => _call_dependency_host_service: Read,
            "call_intrinsic_tag" => _call_intrinsic_tag: Read,
            "call_return_type" => _call_return_type: Read,
            "call_return_type_token" => _call_return_type_token: Read,
            "call_return_aggregate_word_count" => _call_return_aggregate_word_count: Read,
            "call_result_instance" => call_result_instance: Read,
            "type_instance_aggregate_word_count" => _type_instance_aggregate_word_count: Read,
            "type_expr_ref_tag" => _type_expr_ref_tag: Read,
            "type_expr_ref_payload" => _type_expr_ref_payload: Read,
            "type_generic_param_slot_by_token" => _type_generic_param_slot_by_token: Read,
            "decl_type_ref_tag" => decl_type_ref_tag: Read,
            "decl_type_ref_payload" => decl_type_ref_payload: Read,
            "semantic_calls_by_hir" => semantic_calls_by_hir: Write,
            "semantic_aggregate_word_count_by_hir" => semantic_aggregate_word_count_by_hir: Write,
        ],
    )?;
    add_expression_type_passes(&mut graph)?;
    graph.add_kernel_pass_by_name(
        SEMANTIC_ARTIFACT_PROJECT_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/semantic/artifact/00_project",
        reflected_bindings![
            "path_id_by_owner_hir" => _path_id_by_owner_hir: Read,
            "resolved_dependency_value_metadata" => resolved_dependency_value_metadata: Read,
            "semantic_value_decl_by_hir" => semantic_value_decl_by_hir: Write,
            "semantic_value_type_by_hir" => semantic_value_type_by_hir: Write,
            "semantic_value_const_by_hir" => semantic_value_const_by_hir: Write,
            "semantic_value_const_present_by_hir" => semantic_value_const_present_by_hir: Write,
            "semantic_param_type_by_row" => semantic_param_type_by_row: Write,
            "semantic_enclosing_fn_by_hir" => semantic_enclosing_fn_by_hir: Write,
            "semantic_function_return_type_by_hir" => semantic_function_return_type_by_hir: Write,
            "semantic_function_entrypoint_by_hir" => semantic_function_entrypoint_by_hir: Write,
            "semantic_function_host_service_by_hir" => semantic_function_host_service_by_hir: Write,
            "semantic_control_depth_by_hir" => semantic_control_depth_by_hir: Write,
            "compact_expr_scalar_type" => final_scalar: Read,
            "semantic_expr_scalar_type_by_hir" => semantic_expr_scalar_type_by_hir: Write,
            "type_expr_ref_tag" => _type_expr_ref_tag: Read,
            "type_expr_ref_payload" => _type_expr_ref_payload: Read,
            "external_type_library_id" => _external_type_library_id: Read,
            "external_type_unit_id" => _external_type_unit_id: Read,
            "external_type_local_index" => _external_type_local_index: Read,
            "semantic_type_ref_tag_by_hir" => semantic_type_ref_tag_by_hir: Write,
            "semantic_type_ref_payload_by_hir" => semantic_type_ref_payload_by_hir: Write,
            "semantic_type_generic_param_slot_by_hir" => semantic_type_generic_param_slot_by_hir: Write,
            "semantic_type_external_library_id_by_hir" => semantic_type_external_library_id_by_hir: Write,
            "semantic_type_external_unit_id_by_hir" => semantic_type_external_unit_id_by_hir: Write,
            "semantic_type_external_local_index_by_hir" => semantic_type_external_local_index_by_hir: Write,
        ],
    )?;
    graph.add_kernel_pass_by_name(
        SEMANTIC_LOCAL_CONST_LITERALS_PROJECT_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/semantic/artifact/00a_local_const_literals",
        reflected_bindings![
            "compact_hir_expr_parent" => _compact_hir_expr_parent: Read,
            "compact_hir_nearest_fn" => _compact_hir_nearest_fn: Read,
            "compact_expr_scalar_type" => final_scalar: Read,
            "semantic_value_const_by_hir" => semantic_value_const_by_hir: ReadWrite,
            "semantic_value_const_present_by_hir" => semantic_value_const_present_by_hir: ReadWrite,
        ],
    )?;
    graph.add_kernel_pass_by_name(
        SEMANTIC_LOCAL_CONST_REFERENCES_PROJECT_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        "type_checker/semantic/artifact/00b_local_const_references",
        reflected_bindings![
            "compact_const_value" => _compact_const_value: Read,
            "decl_id_by_name_token" => decl_id_by_name_token: Read,
            "decl_kind" => decl_kind: Read,
            "decl_hir_node" => _decl_hir_node: Read,
            "semantic_value_const_by_hir" => semantic_value_const_by_hir: ReadWrite,
            "semantic_value_const_present_by_hir" => semantic_value_const_present_by_hir: ReadWrite,
        ],
    )?;
    graph.add_buffer_copy_pass(
        STATUS_READBACK_PASS,
        CompilerPhase::TypeCheck,
        "status",
        _status,
        "status_readback",
        _status_readback,
    )?;
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
    // Exact pass accesses are also the arena co-binding source of truth.
    graph.add_registered_pass_arena_conflicts();
    graph.build()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dependency_ping_pong_bindings_protect_their_actual_resources() {
        let kernels =
            crate::gpu::kernels::KernelCatalog::load_prefixes(&["type_checker", "scan", "radix"])
                .unwrap();
        let graph = build_graph(
            1024,
            4096,
            4,
            4096,
            1024,
            768,
            768,
            10_000,
            DependencyWorkspaceCapacity {
                visible_rows: 16,
                lookup_rows: 32,
                type_rows: 2,
                declaration_rows: 16,
            },
            u32::MAX,
            &kernels,
        )
        .unwrap();
        graph.validate_assigned_pass_reflections(&kernels).unwrap();

        let validate_results = graph
            .pass(
                graph
                    .pass_id(DEPENDENCY_CALL_RESULTS_VALIDATE_PASS)
                    .unwrap(),
            )
            .unwrap();
        for (binding, expected_resource) in [
            ("canonical_type_roots", "dependency_canonical_type_roots_b"),
            (
                "canonical_type_subtree_start",
                "dependency_canonical_type_subtree_b",
            ),
        ] {
            let access = validate_results
                .accesses
                .iter()
                .find(|access| access.binding == binding)
                .unwrap_or_else(|| panic!("missing reflected binding `{binding}`"));
            assert_eq!(
                access.resource,
                graph.resource_id(expected_resource).unwrap(),
                "one 16-link jump round leaves the canonical dependency relation in buffer B",
            );
        }

        let arena_layout = graph
            .workspace_arena_layout(&wgpu::Limits::default())
            .unwrap();
        let physical_arena = |name| {
            let slot = graph
                .workspace_plan()
                .assignments
                .iter()
                .find(|assignment| assignment.name == name)
                .unwrap_or_else(|| panic!("missing workspace assignment `{name}`"))
                .slot;
            arena_layout
                .placements
                .iter()
                .find(|placement| placement.slot == slot)
                .unwrap_or_else(|| panic!("missing arena placement for `{name}`"))
                .arena
        };
        let writable_call_arena = physical_arena("call_result_instance");
        for name in [
            "dependency_canonical_type_roots_a",
            "dependency_canonical_type_roots_b",
            "dependency_canonical_type_subtree_a",
            "dependency_canonical_type_subtree_b",
        ] {
            assert_ne!(
                physical_arena(name),
                writable_call_arena,
                "read-only dependency canonical relation `{name}` must not share a physical buffer with writable call results",
            );
        }
        assert!(graph.resource_id("canonical_type_roots").is_none());
        assert!(graph.resource_id("canonical_type_subtree_start").is_none());
    }

    #[test]
    fn typecheck_graph_tracks_operation_workspace_lifetimes() {
        let kernels =
            crate::gpu::kernels::KernelCatalog::load_prefixes(&["type_checker", "scan", "radix"])
                .unwrap();
        let graph = build_graph(
            1024,
            4096,
            4,
            4096,
            1024,
            768,
            768,
            10_000,
            DependencyWorkspaceCapacity::default(),
            u32::MAX,
            &kernels,
        )
        .unwrap();
        graph.validate_assigned_pass_reflections(&kernels).unwrap();
        let resource = |name| {
            graph
                .resource_id(name)
                .unwrap_or_else(|| panic!("missing graph resource `{name}`"))
        };
        for operation in [
            MATCH_PATTERNS_BIND,
            MATCH_PAYLOADS_TYPE,
            VALUE_ENUM_CALLS_CONSUME,
            VALUE_ENUM_CALL_PAYLOADS_VALIDATE,
            VALUE_ENUM_CALLS_FINALIZE,
            MATCH_EXPRS_TYPE,
        ] {
            assert!(
                graph.pass_id(operation.name).is_some(),
                "missing graph operation {}",
                operation.name,
            );
        }
        assert!(
            graph.pass_id(MATCH_PATTERNS_BIND.name).unwrap()
                < graph.pass_id(SCOPE_HIR_PASS).unwrap(),
            "match-pattern binding executes before lexical scope projection",
        );
        assert!(
            graph.pass_id(VALUE_ENUM_CALLS_FINALIZE.name).unwrap()
                < graph.pass_id(MATCH_EXPRS_TYPE.name).unwrap(),
            "enum-call finalization executes before match-expression typing",
        );
        let arena_layout = graph
            .workspace_arena_layout(&wgpu::Limits::default())
            .unwrap();
        let physical_arena = |name| {
            let slot = graph
                .workspace_plan()
                .assignments
                .iter()
                .find(|assignment| assignment.name == name)
                .unwrap_or_else(|| panic!("missing workspace assignment `{name}`"))
                .slot;
            arena_layout
                .placements
                .iter()
                .find(|placement| placement.slot == slot)
                .unwrap_or_else(|| panic!("missing arena placement for `{name}`"))
                .arena
        };
        let alias_root_initialize = graph
            .pass(graph.pass_id(TYPE_ALIAS_ROOT_INITIALIZE.name).unwrap())
            .unwrap();
        assert!(alias_root_initialize.accesses.iter().any(|access| {
            access.binding == "alias_root_decl"
                && access.resource == resource("alias_root_a")
                && access.mode == AccessMode::Write
        }));
        assert!(alias_root_initialize.accesses.iter().any(|access| {
            access.binding == "decl_kind" && access.resource == resource("decl_kind")
        }));
        assert_ne!(
            physical_arena("alias_root_a"),
            physical_arena("decl_kind"),
            "resources co-bound by alias-root initialization must use different physical buffers",
        );
        assert_ne!(
            physical_arena("module_type_path_type"),
            physical_arena("type_instance_len_kind"),
            "reflection must keep resources co-bound by aggregate-detail collection in separate physical buffers",
        );
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
        assert!(
            graph.repeated_regions().len() >= 4,
            "every scalable operation must retain its own explicit repeated region",
        );
        let path_prefix_region = graph
            .repeated_regions()
            .iter()
            .find(|region| {
                region.first_pass == graph.pass_id(PATH_PREFIX_INTERN_A_TO_B.name).unwrap()
            })
            .expect("path-prefix interning repeated region");
        assert_eq!(
            path_prefix_region.iterations,
            (u32::BITS - 4096u32.saturating_sub(1).leading_zeros()).div_ceil(2),
        );
        let (_, module_radix_steps) = decl_key_radix_layout(4096, 4);
        let module_radix_region = graph
            .repeated_regions()
            .iter()
            .find(|region| {
                region.first_pass
                    == graph
                        .pass_id(module_decl_key_radix_start_pass(4096, module_radix_steps))
                        .unwrap()
            })
            .expect("module-declaration radix sort repeated region");
        assert_eq!(
            module_radix_region.iterations,
            module_radix_steps.div_ceil(2)
        );
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
        let visible_tree_region = graph
            .repeated_regions()
            .iter()
            .find(|region| {
                region.first_pass == graph.pass_id(VISIBLE_SCOPE_TREE_LEVEL.name).unwrap()
            })
            .expect("visible-declaration scope tree repeated region");
        assert_eq!(
            visible_tree_region.iterations,
            4096u32
                .div_ceil(HIR_VISIBLE_DECL_ROW_BLOCK_SIZE)
                .next_power_of_two()
                .trailing_zeros(),
        );
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
        let storage_identity = |resource: ResourceId| {
            let name = graph.resource(resource).unwrap().name;
            graph
                .workspace_plan()
                .assignments
                .iter()
                .find(|assignment| assignment.name == name)
                .map_or((false, resource.index()), |assignment| {
                    (true, assignment.slot as usize)
                })
        };
        let slot = storage_identity;
        let name_workspace = [
            graph.resource_id("name_lexeme_flag").unwrap(),
            graph.resource_id("name_lexeme_kind").unwrap(),
            graph.resource_id("name_lexeme_prefix").unwrap(),
            graph.resource_id("name_scan_local_prefix").unwrap(),
            graph.resource_id("name_scan_block_sum").unwrap(),
            graph.resource_id("name_scan_prefix_a").unwrap(),
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
            resource("module_path_key_radix_block_histogram"),
            resource("module_path_key_radix_block_bucket_prefix"),
            resource("module_path_key_radix_bucket_total"),
            resource("module_path_key_radix_bucket_base"),
        ];
        for resource in name_workspace {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "source-name compaction scratch must be lifetime-colored graph workspace",
            );
        }
        assert_ne!(
            storage_identity(graph.resource_id("name_hash_lo").unwrap()),
            storage_identity(graph.resource_id("name_hash_hi").unwrap()),
            "the two halves of each name hash are written together",
        );
        assert_ne!(
            storage_identity(graph.resource_id("name_hash_table_a").unwrap()),
            storage_identity(graph.resource_id("name_hash_table_b").unwrap()),
            "both open-addressed name tables are updated together",
        );
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
                "semantic-interface export retains this compact source-name row through the graph output boundary",
            );
        }
        let local_const_reference_projection = graph
            .pass_id(SEMANTIC_LOCAL_CONST_REFERENCES_PROJECT_PASS)
            .unwrap();
        assert_eq!(
            graph
                .lifetime(graph.resource_id("decl_kind").unwrap())
                .unwrap()
                .last_pass,
            local_const_reference_projection,
            "declaration kinds must survive local-constant reference projection",
        );
        assert_eq!(
            graph
                .lifetime(graph.resource_id("decl_id_by_name_token").unwrap())
                .unwrap()
                .last_pass,
            local_const_reference_projection,
            "the declaration reverse lookup must survive local-constant projection",
        );
        assert_ne!(
            storage_identity(graph.resource_id("decl_name_token").unwrap()),
            storage_identity(graph.resource_id("decl_kind").unwrap()),
            "module declaration scatter writes names and kinds together",
        );
        assert_ne!(
            storage_identity(graph.resource_id("decl_name_token").unwrap()),
            storage_identity(graph.resource_id("decl_id_by_name_token").unwrap()),
            "module declaration scatter writes names and reverse lookup together",
        );
        assert_ne!(
            storage_identity(graph.resource_id("decl_kind").unwrap()),
            storage_identity(graph.resource_id("decl_id_by_name_token").unwrap()),
            "module declaration scatter writes kinds and reverse lookup together",
        );
        let initial_module_scan_resources = [
            resource("module_record_family_bits"),
            resource("module_record_family_flag"),
            resource("module_record_prefix"),
        ];
        let module_scan_start = graph.pass_id(MODULE_RECORDS_MARK.name).unwrap();
        let module_scan_end = graph.pass_id(VARIANT_DECL_RECORDS_SCATTER.name).unwrap();
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
        .map(storage_identity)
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
        ]
        .map(storage_identity)
        .into_iter()
        .collect::<std::collections::BTreeSet<_>>();
        assert_eq!(
            hierarchy_bindings.len(),
            2,
            "scan block sums and block prefixes are bound together",
        );
        let module_radix_resources = [
            resource("module_path_key_radix_block_histogram"),
            resource("module_path_key_radix_block_bucket_prefix"),
            resource("module_path_key_radix_bucket_total"),
            resource("module_path_key_radix_bucket_base"),
        ];
        let module_radix_start = module_radix_region.first_pass;
        let module_radix_end_name = if module_radix_steps % 2 != 0 {
            MODULE_DECL_KEY_RADIX_SORT.passes.order_to_temporary.scatter
        } else {
            MODULE_DECL_KEY_RADIX_SORT.passes.temporary_to_order.scatter
        };
        let module_radix_end = graph.pass_id(module_radix_end_name).unwrap();
        let final_dependency_visibility_scan = DEPENDENCY_VISIBLE_SCAN_CALL_COLLECTION;
        let module_type_scan_end = graph
            .pass_id(final_dependency_visibility_scan.passes.apply)
            .unwrap();
        let module_type_scan_start = graph
            .pass_id(final_dependency_visibility_scan.passes.local)
            .unwrap();
        for resource in module_radix_resources {
            let lifetime = graph.lifetime(resource).unwrap();
            assert_eq!(lifetime.first_pass, module_radix_start);
            assert_eq!(lifetime.last_pass, module_radix_end);
        }
        assert_eq!(
            graph
                .lifetime(resource("module_record_family_flag"))
                .unwrap()
                .last_pass,
            graph.pass_id(VARIANT_DECL_RECORDS_SCATTER.name).unwrap(),
            "the declaration flag remains live through every declaration scatter",
        );
        for resource in [
            resource("module_record_scan_local_prefix"),
            resource("module_record_scan_block_sum"),
            resource("module_record_scan_prefix_a"),
        ] {
            let lifetime = graph.lifetime(resource).unwrap();
            assert!(
                lifetime.last_pass.index() >= module_type_scan_start.index()
                    && lifetime.last_pass.index() <= module_type_scan_end.index(),
                "shared scan workspace ends inside its final modeled visibility scan",
            );
            for radix_resource in module_radix_resources {
                assert_ne!(
                    storage_identity(resource),
                    storage_identity(radix_resource),
                    "module scan workspace and radix storage overlap in the real schedule",
                );
            }
        }
        assert_ne!(
            storage_identity(resource("module_record_scan_local_prefix")),
            storage_identity(resource("type_instance_arg_ref_tag")),
            "declaration type flags use the future type-instance tag column while scanning",
        );
        assert_ne!(
            storage_identity(resource("module_record_scan_local_prefix")),
            storage_identity(resource("type_instance_arg_ref_payload")),
            "declaration value flags use the future type-instance payload column while scanning",
        );
        let type_reference_resources = [
            resource("type_expr_ref_tag"),
            resource("type_expr_ref_payload"),
            resource("type_generic_param_slot_by_token"),
            resource("type_const_param_slot_by_token"),
        ];
        for resource in type_reference_resources {
            assert!(
                matches!(
                    graph.resource(resource).unwrap().class,
                    ResourceClass::Input | ResourceClass::Workspace | ResourceClass::Output
                ),
                "type-reference and generic-slot relations must be graph-owned workspace or retained outputs",
            );
        }
        assert_eq!(
            type_reference_resources
                .map(storage_identity)
                .into_iter()
                .collect::<std::collections::BTreeSet<_>>()
                .len(),
            type_reference_resources.len(),
            "the type-instance clear pass initializes all four relations together",
        );
        assert_eq!(
            graph
                .resource(resource("type_decl_hir_node_by_token"))
                .unwrap()
                .class,
            ResourceClass::Input,
            "the compact parser declaration index remains an external graph input",
        );
        let visible_resources = [
            graph.resource_id("hir_visible_decl_flag").unwrap(),
            graph.resource_id("hir_visible_decl_prefix").unwrap(),
            graph
                .resource_id("hir_visible_decl_scan_local_prefix")
                .unwrap(),
            graph
                .resource_id("hir_visible_decl_scan_block_sum")
                .unwrap(),
            graph.resource_id("hir_visible_decl_scan_prefix_a").unwrap(),
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
        for resource in visible_resources {
            assert!(
                matches!(
                    graph.resource(resource).unwrap().class,
                    ResourceClass::Workspace
                ),
                "visible-declaration compaction storage must be graph-owned",
            );
        }
        assert_ne!(
            storage_identity(graph.resource_id("hir_visible_decl_flag").unwrap()),
            storage_identity(graph.resource_id("hir_visible_decl_prefix").unwrap()),
            "visible scan input and prefix output are simultaneously bound",
        );
        assert_ne!(
            storage_identity(graph.resource_id("hir_visible_decl_key_order").unwrap()),
            storage_identity(graph.resource_id("hir_visible_decl_key_order_tmp").unwrap()),
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
            resource("predicate_method_contract_owner_count"),
            resource("predicate_method_contract_lookup_head"),
            resource("predicate_method_contract_lookup_next"),
            resource("predicate_method_validation_owner_node"),
            resource("predicate_method_validation_peer_node"),
            resource("predicate_method_validation_status"),
            resource("predicate_method_validation_detail_token"),
            resource("predicate_method_validation_first_error_row"),
            resource("predicate_owner_lookup_head"),
            resource("predicate_owner_lookup_next"),
            resource("predicate_impl_lookup_head"),
            resource("predicate_impl_lookup_next"),
        ];
        assert_eq!(
            graph
                .resource(resource("predicate_syntax_token"))
                .unwrap()
                .class,
            ResourceClass::Workspace,
            "predicate syntax markers must be lifetime-colored graph workspace",
        );
        assert!(
            graph
                .pass_id(PREDICATES_CLEAR_SYNTAX_TOKENS_PASS)
                .unwrap()
                .index()
                < graph.pass_id(TYPE_INSTANCES_CLEAR.name).unwrap().index(),
            "predicate syntax markers are cleared before their module-path producer runs",
        );
        let generic_owner_artifacts = [
            resource("generic_decl_owner_by_node_a"),
            resource("predicate_bound_list_by_node_a"),
            resource("predicate_bound_list_by_node_b"),
        ];
        for resource in generic_owner_artifacts {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "generic-owner artifacts must be lifetime-colored graph workspace",
            );
        }
        for removed_scratch in [
            "generic_decl_owner_by_node_b",
            "generic_decl_parent_jump_a",
            "generic_decl_parent_jump_b",
        ] {
            assert!(
                graph.resource_id(removed_scratch).is_none(),
                "local owner traversal must not retain `{removed_scratch}` pointer-jump scratch",
            );
        }
        assert!(
            graph.pass_id(TYPE_INSTANCES_CLEAR.name).unwrap().index()
                < graph
                    .pass_id(TYPE_INSTANCES_MARK_GENERIC_PARAM_RECORDS_PASS)
                    .unwrap()
                    .index(),
            "generic-owner initialization follows the shared type-instance clear",
        );
        assert!(
            graph
                .pass_id(TYPE_INSTANCES_MARK_GENERIC_PARAM_RECORDS_PASS)
                .unwrap()
                .index()
                < graph
                    .pass_id(TYPE_INSTANCES_COLLECT_INITIAL.name)
                    .unwrap()
                    .index(),
            "generic-owner traversal completes before type-instance collection",
        );
        let generic_use_pass = graph
            .pass(
                graph
                    .pass_id(TYPE_INSTANCES_GENERIC_PARAM_USE_SLOTS_PASS)
                    .unwrap(),
            )
            .unwrap();
        assert!(
            generic_use_pass.accesses.iter().any(|access| {
                access.binding == "generic_decl_owner_by_node_a" && access.mode == AccessMode::Read
            }),
            "generic uses must consume the propagated declaration-owner relation"
        );
        for resource in [
            resource("generic_param_count_out"),
            resource("generic_param_owner_token"),
            resource("generic_param_name_id"),
            resource("generic_param_token"),
            resource("generic_param_kind"),
            resource("generic_param_lookup_state"),
            resource("generic_type_param_flag"),
            resource("generic_const_param_flag"),
            resource("generic_type_param_prefix"),
            resource("generic_const_param_prefix"),
            resource("generic_type_param_rows"),
        ] {
            assert!(
                matches!(
                    graph.resource(resource).unwrap().class,
                    ResourceClass::Workspace | ResourceClass::Output
                ),
                "generic-parameter rows must be graph-owned workspace or retained interface outputs",
            );
        }
        assert!(
            graph
                .pass_id(TYPE_INSTANCES_DECL_GENERIC_PARAMS_PASS)
                .unwrap()
                .index()
                < graph
                    .pass_id(GENERIC_PARAM_LOOKUP_BUILD.name)
                    .unwrap()
                    .index(),
            "compact generic rows are produced before indexing",
        );
        assert!(
            graph
                .pass_id(GENERIC_PARAM_ROWS_SCATTER.name)
                .unwrap()
                .index()
                < graph
                    .pass_id(TYPE_INSTANCES_GENERIC_PARAM_USE_SLOTS_PASS)
                    .unwrap()
                    .index(),
            "generic lookup and slot compaction complete before use-site resolution",
        );
        for resource in predicate_row_workspace {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "predicate core and method-validation rows must be lifetime-colored graph workspace",
            );
        }
        let mut predicate_clear_slots = predicate_row_workspace.map(storage_identity);
        predicate_clear_slots.sort_unstable();
        assert!(
            predicate_clear_slots
                .windows(2)
                .all(|pair| pair[0] != pair[1]),
            "all predicate rows overwritten by the shared clear pass are simultaneously bound",
        );
        for name in [
            "predicate_method_contract_key_order",
            "predicate_method_contract_key_order_tmp",
            "type_check.predicates.method_contract_keys.small",
            "type_check.predicates.method_contract_keys.radix.histogram.a",
            "type_check.predicates.build_method_owner_ranges",
        ] {
            assert!(
                graph.resource_id(name).is_none() && graph.pass_id(name).is_none(),
                "method contracts must not retain sort artifact `{name}`",
            );
        }
        assert_ne!(
            storage_identity(resource("predicate_method_contract_lookup_head")),
            storage_identity(resource("predicate_method_contract_lookup_next")),
            "method-contract buckets and links are simultaneously bound",
        );
        assert!(
            graph
                .resource_id("predicate_method_param_key_order")
                .is_none(),
            "compact parameter ranges replace the former method-parameter sort index",
        );
        assert!(
            graph
                .pass_id("type_check.predicates.method_param_keys.radix.histogram.a")
                .is_none(),
            "method parameters must not schedule a radix sort",
        );
        for name in [
            "predicate_owner_key_order",
            "predicate_owner_key_order_tmp",
            "type_check.predicates.owner_keys.small",
            "type_check.predicates.owner_keys.radix.histogram.a",
        ] {
            assert!(
                graph.resource_id(name).is_none() && graph.pass_id(name).is_none(),
                "predicate owner lookup must not retain radix artifact `{name}`",
            );
        }
        assert_ne!(
            storage_identity(resource("predicate_owner_lookup_head")),
            storage_identity(resource("predicate_owner_lookup_next")),
            "owner-index buckets and links are simultaneously bound",
        );
        for name in [
            "predicate_impl_key_order",
            "predicate_impl_key_order_tmp",
            "predicate_key_radix_block_histogram",
            "predicate_key_radix_block_bucket_prefix",
            "predicate_key_radix_bucket_total",
            "predicate_key_radix_bucket_base",
            "type_check.predicates.impl_keys.small",
            "type_check.predicates.impl_keys.radix.histogram.a",
        ] {
            assert!(
                graph.resource_id(name).is_none() && graph.pass_id(name).is_none(),
                "implementation lookup must not retain radix artifact `{name}`",
            );
        }
        assert_ne!(
            storage_identity(resource("predicate_impl_lookup_head")),
            storage_identity(resource("predicate_impl_lookup_next")),
            "implementation-index buckets and links are simultaneously bound",
        );
        for resource in [
            resource("predicate_obligation_count_by_call"),
            resource("predicate_obligation_prefix_by_call"),
            resource("predicate_obligation_scan_local_prefix"),
            resource("predicate_obligation_scan_block_sum"),
            resource("predicate_obligation_scan_prefix_a"),
            resource("predicate_obligation_pair_total"),
            resource("predicate_obligation_pair_dispatch_args"),
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "predicate obligation emission must use lifetime-colored graph workspace",
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
            storage_identity(resource("predicate_obligation_count_by_call")),
            storage_identity(resource("predicate_obligation_prefix_by_call")),
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
            "dense member-chain edges must use lifetime-colored graph workspace",
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
        let mut member_result_slots = member_result_resources.map(storage_identity);
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
            graph.pass_id(TYPE_INSTANCES_CLEAR.name).unwrap(),
            "member-result columns are initialized by the shared type-instance clear",
        );
        assert_eq!(
            member_lifetime.last_pass, graph_output_boundary,
            "retained member-result metadata must survive beyond compact semantic projection",
        );
        let struct_workspace_resources = [
            resource("struct_init_field_context_instance"),
            resource("struct_init_field_expected_ref_tag"),
            resource("struct_init_field_expected_ref_payload"),
            resource("struct_init_field_ordinal"),
            resource("struct_lit_context_decl_token"),
            resource("struct_lit_context_instance"),
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
            "function entrypoint tags must use lifetime-colored graph workspace",
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
        ];
        argument_row_slots.sort_unstable();
        assert!(
            argument_row_slots.windows(2).all(|pair| pair[0] != pair[1]),
            "all buffers bound by the argument-row scan must occupy distinct slots",
        );
        assert!(
            graph.pass_id(TYPE_INSTANCES_CLEAR.name).unwrap().index()
                < graph
                    .pass_id(TYPE_INSTANCE_ARG_ROW_SCAN.passes.local)
                    .unwrap()
                    .index(),
            "argument-row sentinels must be initialized before compaction",
        );
        assert!(
            graph.pass_id(TYPE_INSTANCES_CLEAR.name).unwrap().index()
                < graph
                    .pass_id(TYPE_INSTANCES_COLLECT_INITIAL.name)
                    .unwrap()
                    .index(),
            "type-instance arguments must be reset before initial collection",
        );
        assert!(
            graph
                .pass_id(TYPE_INSTANCES_COLLECT_INITIAL_AGGREGATE_DETAILS.name)
                .unwrap()
                .index()
                < graph
                    .pass_id(TYPE_INSTANCES_COLLECT_PROJECTED.name)
                    .unwrap()
                    .index(),
            "projected collection follows the initial unresolved collection",
        );
        assert!(
            graph
                .pass_id(TYPE_INSTANCES_COLLECT_PROJECTED_AGGREGATE_DETAILS.name)
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
                    .pass_id(TYPE_INSTANCES_COLLECT_NAMED_ARG_REFS.name)
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
                .pass_id(TYPE_INSTANCES_COLLECT_NAMED_ARG_REFS.name)
                .unwrap()
                .index()
                < graph.pass_id(TYPE_SEMANTIC_CLEAR_PASS).unwrap().index(),
            "sparse argument references must be populated before semantic consumers",
        );
        let hash_rows = graph.pass_id(TYPE_INSTANCE_ARG_HASH_ROWS_PASS).unwrap();
        let mark_call_keys = graph.pass_id(METHODS_MARK_CALL_KEYS.name).unwrap();
        let method_lookup_clear = graph.pass_id(METHODS_LOOKUP_CLEAR.name).unwrap();
        let method_lookup_build = graph.pass_id(METHODS_LOOKUP_BUILD.name).unwrap();
        let method_key_validation = graph.pass_id(METHODS_VALIDATE_KEYS.name).unwrap();
        let mark_call_return_keys = graph.pass_id(METHODS_MARK_CALL_RETURN_KEYS.name).unwrap();
        let resolve_table = graph.pass_id(METHODS_RESOLVE_TABLE.name).unwrap();
        let resolve = graph.pass_id(METHODS_RESOLVE.name).unwrap();
        for resource in [
            resource("method_key_status"),
            resource("method_key_duplicate_of"),
            resource("method_lookup_head"),
            resource("method_lookup_next"),
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "method index state must use lifetime-colored graph workspace",
            );
        }
        assert_ne!(
            slot(resource("type_instance_arg_hash")),
            slot(resource("method_lookup_head")),
            "method-index construction reads argument hashes while writing bucket heads",
        );
        assert_ne!(
            slot(resource("type_instance_arg_hash")),
            slot(resource("method_lookup_next")),
            "method-index construction reads argument hashes while writing bucket links",
        );
        assert_ne!(
            slot(resource("method_lookup_head")),
            slot(resource("method_lookup_next")),
            "bucket heads and links are written together",
        );
        assert_ne!(
            slot(resource("method_lookup_head")),
            slot(resource("method_key_status")),
            "method validation reads bucket heads while writing status",
        );
        for old_resource in [
            "method_key_to_fn_token",
            "method_key_order_tmp",
            "method_key_radix_block_histogram",
            "method_key_radix_block_bucket_prefix",
            "method_key_radix_bucket_total",
            "method_key_radix_bucket_base",
        ] {
            assert!(
                graph.resource_id(old_resource).is_none(),
                "removed method radix resource `{old_resource}` must stay absent",
            );
        }
        assert!(
            graph
                .pass_id(TYPE_INSTANCES_COLLECT_NAMED_ARG_REFS.name)
                .unwrap()
                .index()
                < hash_rows.index()
        );
        assert!(hash_rows.index() < mark_call_keys.index());
        assert!(mark_call_keys.index() < method_lookup_clear.index());
        assert!(method_lookup_clear.index() < method_lookup_build.index());
        assert!(method_lookup_build.index() < method_key_validation.index());
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
                "semantic type compaction must use lifetime-colored graph workspace",
            );
        }
        assert_ne!(
            slot(resource("type_semantic_scan_input")),
            slot(resource("type_semantic_prefix")),
            "semantic scan input and prefix are simultaneously bound",
        );
        let semantic_clear = graph.pass_id(TYPE_SEMANTIC_CLEAR_PASS).unwrap();
        let semantic_mark = graph.pass_id(TYPE_SEMANTIC_COMPACTION.mark.name).unwrap();
        let semantic_scan = graph.pass_id(TYPE_SEMANTIC_SCAN.passes.local).unwrap();
        let semantic_scatter = graph
            .pass_id(TYPE_SEMANTIC_COMPACTION.scatter.name)
            .unwrap();
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
            graph_output_boundary,
            "the retained type-instance state must survive through the graph output boundary",
        );
        assert_ne!(
            slot(resource("fn_event_inblock")),
            slot(resource("fn_block_prefix")),
            "simultaneously read function-context rows must not alias",
        );
        assert_eq!(
            graph
                .resource(graph.resource_id("semantic_feature_flags").unwrap())
                .unwrap()
                .class,
            ResourceClass::Workspace,
            "feature state must use lifetime-colored graph workspace",
        );
        assert_eq!(
            graph.resource(resource("return_fn_flags")).unwrap().class,
            ResourceClass::Workspace,
            "return convergence must use lifetime-colored graph workspace",
        );
        assert_eq!(
            graph
                .resource(resource("return_block_flags"))
                .unwrap()
                .class,
            ResourceClass::Workspace,
            "block return convergence must use lifetime-colored graph workspace",
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
        assert!(graph.pass_id(CONDITIONS_CALLS.name).is_some());
        assert!(graph.pass_id(CONDITIONS_TYPES.name).is_some());
        assert!(graph.pass_id(CONDITIONS_METHODS.name).is_some());
        assert!(graph.pass_id(CONDITIONS_PREDICATES.name).is_some());
        assert!(graph.pass_id(CONDITIONS_NAMES.name).is_some());
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
        let visible_sort_start =
            visible_decl_radix_start_pass(4096, visible_decl_key_radix_steps(4096));
        let visible_order = [
            VISIBLE_HIR_DECL_MARK.name,
            VISIBLE_MATCH_DISPATCH_PASS,
            VISIBLE_MATCH_DECL_MARK.name,
            VISIBLE_SCAN_PASS,
            VISIBLE_DECL_SCATTER.name,
            visible_sort_start,
            VISIBLE_SCOPE_TREE_LEAVES.name,
            VISIBLE_SCOPE_TREE_LEVEL.name,
            VISIBLE_NAMES.name,
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
            ResourceClass::Workspace,
            "visible declarations must use lifetime-colored graph workspace",
        );
        assert_eq!(
            graph
                .resource(graph.resource_id("visible_type").unwrap())
                .unwrap()
                .class,
            ResourceClass::Workspace,
            "visible types must use lifetime-colored graph workspace",
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
                ResourceClass::Workspace,
                "aggregate request columns must use lifetime-colored graph workspace",
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
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "aggregate scan workspace must use lifetime-colored graph workspace",
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
        let predicate_reducer = graph.pass_id(CONDITIONS_PREDICATES.name).unwrap();
        assert!(
            graph
                .resource_id("compact_predicate_diagnostic_facts")
                .is_none(),
            "predicate reduction must consume producer-owned columns without materializing a duplicate HIR table",
        );
        let reducer = graph.pass(predicate_reducer).unwrap();
        for source in [
            "predicate_status",
            "predicate_method_contract_status",
            "predicate_method_validation_status",
            "predicate_method_validation_detail_token",
        ] {
            let source = resource(source);
            assert!(
                reducer.accesses.iter().any(|access| {
                    access.resource == source && access.mode.reads() && !access.mode.writes()
                }),
                "predicate reducer must read `{}` directly",
                graph.resource(source).unwrap().name,
            );
        }
        assert!(artifact_pass.index() > graph.pass_id(CONDITIONS_NAMES.name).unwrap().index());
        for resource in [
            resource("semantic_value_decl_by_hir"),
            resource("semantic_value_type_by_hir"),
            resource("semantic_value_const_by_hir"),
            resource("semantic_value_const_present_by_hir"),
            resource("semantic_param_type_by_row"),
            resource("semantic_enclosing_fn_by_hir"),
            resource("semantic_function_return_type_by_hir"),
            resource("semantic_function_entrypoint_by_hir"),
            resource("semantic_function_host_service_by_hir"),
            resource("semantic_control_depth_by_hir"),
            resource("semantic_expr_scalar_type_by_hir"),
            resource("semantic_type_ref_tag_by_hir"),
            resource("semantic_type_ref_payload_by_hir"),
            resource("semantic_type_generic_param_slot_by_hir"),
            resource("semantic_type_external_library_id_by_hir"),
            resource("semantic_type_external_unit_id_by_hir"),
            resource("semantic_type_external_local_index_by_hir"),
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
            slot(resource("semantic_calls_by_hir")),
            slot(resource("compact_expr_scalar_type.a")),
            "expression typing reads the checked-call artifact while writing scalar scratch",
        );
        for resource in [
            resource("compact_expr_scalar_type.a"),
            resource("call_result_instance"),
            resource("call_generic_return_arg_node"),
            resource("call_arg_row_count_out"),
            resource("call_generic_claim_count_out"),
        ] {
            assert_eq!(
                graph.resource(resource).unwrap().class,
                ResourceClass::Workspace,
                "type-check implementation state must use lifetime-colored graph workspace",
            );
        }
        assert!(
            graph
                .pass_id(CALLS_ARGUMENT_MATCH_INITIALIZE.name)
                .is_some()
        );
        assert!(graph.pass_id(CALLS_ARGUMENT_MATCH_CONSUME.name).is_some());
        let semantic_boundary = graph.pass_id(SEMANTIC_ARTIFACT_PROJECT_PASS).unwrap();
        let final_argument_match = graph
            .pass_id(CALLS_ARGUMENT_MATCH_FINAL_CONSUME.name)
            .unwrap();
        for name in [
            "call_param_count",
            "call_param_row_count_out",
            "call_param_row_fn_token",
            "call_param_row_ordinal",
            "call_param_row_type",
            "call_param_row_ref_tag",
            "call_param_row_ref_payload",
            "call_param_row_start",
            "call_param_row_count",
        ] {
            let lifetime = graph.lifetime(resource(name)).unwrap();
            assert!(
                lifetime.first_pass.index() <= final_argument_match.index(),
                "compact parameter resource {name} must be produced before final argument matching",
            );
            assert!(
                lifetime.last_pass.index() >= final_argument_match.index(),
                "compact parameter resource {name} must survive every call-matching stage",
            );
            assert!(
                lifetime.last_pass.index() < semantic_boundary.index(),
                "compact parameter resource {name} should end at its reflected consumer instead of a phase-wide fence",
            );
        }
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
        let aggregate_publish = graph.pass_id(CALLS_GENERIC_CLAIM_VALIDATE.name).unwrap();
        let final_argument_apply = graph.pass_id(CALLS_APPLY_FINAL_ARGUMENTS.name).unwrap();
        assert!(
            final_argument_match.index()
                < graph
                    .pass_id(CALLS_GENERIC_CLAIM_CLEAR.name)
                    .unwrap()
                    .index(),
            "generic claim preparation starts after final argument matching",
        );
        assert!(
            graph
                .pass_id(CALLS_GENERIC_CLAIM_INDEX_BUILD.name)
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
                .pass_id(CALLS_CONST_CLAIM_INDEX_BUILD.name)
                .unwrap()
                .index()
                < graph
                    .pass_id(AGGREGATE_CALL_SCAN_PASSES.local)
                    .unwrap()
                    .index()
        );
        assert!(
            graph
                .pass_id(TYPE_SUBTREE_CALL_INDIRECT_PASS)
                .unwrap()
                .index()
                < graph
                    .pass_id(CALLS_REQUIRED_GENERIC_VALIDATE.name)
                    .unwrap()
                    .index(),
            "required-generic validation consumes aggregate comparison results",
        );
        assert!(
            graph
                .pass_id(CALLS_REQUIRED_GENERIC_VALIDATE.name)
                .unwrap()
                .index()
                < final_argument_apply.index(),
            "final call arguments are published only after generic validation",
        );
        assert_ne!(
            slot(resource("call_generic_claim_lookup_head")),
            slot(resource("call_generic_claim_lookup_next")),
            "simultaneously bound generic-claim index rows must not alias",
        );
        assert_ne!(
            slot(resource("call_const_claim_lookup_head")),
            slot(resource("call_const_claim_lookup_next")),
            "simultaneously bound const-claim index rows must not alias",
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
        assert!(graph.resource_id("compact_expr_scalar_type.b").is_none());
    }

    #[test]
    fn expression_types_use_one_local_traversal_without_jump_scratch() {
        let kernels =
            crate::gpu::kernels::KernelCatalog::load_prefixes(&["type_checker", "radix"]).unwrap();
        let graph = build_graph(
            1024,
            1024,
            4,
            1024,
            1024,
            768,
            768,
            512,
            DependencyWorkspaceCapacity::default(),
            u32::MAX,
            &kernels,
        )
        .unwrap();
        assert!(graph.pass_id(GENERIC_PARAM_LOOKUP_BUILD.name).is_some());
        assert!(graph.pass_id(GENERIC_PARAM_ROWS_SCATTER.name).is_some());
        for name in [
            "generic_param_key_order_tmp",
            "generic_param_slot_order_tmp",
            "generic_param_slot_radix_block_histogram",
            "generic_param_slot_radix_block_bucket_prefix",
            "generic_param_slot_radix_bucket_total",
            "generic_param_slot_radix_bucket_base",
        ] {
            assert!(
                graph.resource_id(name).is_none(),
                "generic parameters no longer allocate radix resource `{name}`",
            );
        }
        for name in [
            "predicate_method_contract_key_order_tmp",
            "predicate_method_contract_key_order",
            "predicate_owner_key_order_tmp",
            "predicate_owner_key_order",
            "predicate_impl_key_order_tmp",
            "predicate_impl_key_order",
            "predicate_key_radix_block_histogram",
            "predicate_key_radix_block_bucket_prefix",
            "predicate_key_radix_bucket_total",
            "predicate_key_radix_bucket_base",
        ] {
            assert!(
                graph.resource_id(name).is_none(),
                "predicate indexing should not allocate removed sort resource `{name}`",
            );
        }
        assert!(graph.pass_id(INIT_PASS).is_some());
        assert!(graph.resource_id("compact_expr_scalar_type.b").is_none());
    }
}
