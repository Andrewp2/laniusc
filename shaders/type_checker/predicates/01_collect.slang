// Collect generic-bound predicate rows from the bounds/impl shared module.

#define PREDICATE_BOUND_ARGUMENT_VALIDATION 0
#include "collect_common.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint count = min(compact_predicate_count[0u], gParams.n_hir_nodes);
    if (row >= count)
        return;

    HirPredicate predicate = compact_predicates[row];
    if ((predicate.metadata & 0xffu) != 1u)
        return;

    uint node = predicate.bound;
    if (!valid_node(node))
        return;

    clear_predicate_record(node);

    if (compact_hir_semantic_facts[node].semantic_kind == HIR_SEMANTIC_BOUND_PATH ||
        compact_hir_semantic_facts[node].semantic_kind == HIR_SEMANTIC_BOUND_REFERENCE)
        mark_direct_bound_syntax_tokens(node);

    uint owner_decl = predicate.owner;
    if (!valid_node(owner_decl))
        owner_decl = generic_decl_owner_for_node(node);
    uint subject_token = predicate.subject;
    uint bound_token = compact_hir_semantic_facts[node].semantic_kind == HIR_SEMANTIC_BOUND_PATH
        ? bound_path_leaf_token(node)
        : compact_hir_core[node].token_start;

    predicate_owner_node[node] = owner_decl;
    predicate_subject_token[node] = subject_token;
    predicate_bound_token[node] = bound_token;

    if (compact_hir_semantic_facts[node].semantic_kind != HIR_SEMANTIC_BOUND_PATH)
    {
        predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;
        return;
    }

    if (!valid_node(owner_decl))
    {
        predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_NON_CALLABLE_BOUND;
        return;
    }
    if (!valid_token(subject_token))
    {
        predicate_status[node] = PREDICATE_STATUS_INVALID_SUBJECT;
        return;
    }

    if (!callable_generic_decl_item_kind(compact_item_kind_for_node(owner_decl)))
    {
        predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_NON_CALLABLE_BOUND;
        return;
    }

    if (!generic_type_param_declared_on(owner_decl, subject_token))
    {
        predicate_status[node] = PREDICATE_STATUS_INVALID_SUBJECT;
        return;
    }

    if (!bound_path_shape_supported(node))
    {
        uint arg_token = bound_path_leaf_token(node);
        if (valid_token(arg_token))
        {
            predicate_bound_first_arg_token[node] = arg_token;
            predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;
        }
        else
        {
            predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION;
        }
        return;
    }
    if (bound_path_segment_count(node) == 0u)
    {
        uint arg_token = bound_path_leaf_token(node);
        if (valid_token(arg_token))
            predicate_bound_first_arg_token[node] = arg_token;
        predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;
        return;
    }

    uint trait_decl_i = type_decl_for_bound_path(node, owner_decl);
    if (!valid_token(bound_token) || trait_decl_i == INVALID)
    {
        predicate_status[node] = bound_path_segment_count(node) > 1u
            ? PREDICATE_STATUS_BOUND_NOT_TRAIT
            : PREDICATE_STATUS_UNKNOWN_BOUND_TYPE;
        return;
    }
    if (
        decl_kind[trait_decl_i] != HIR_ITEM_KIND_TRAIT ||
        decl_namespace[trait_decl_i] != HIR_ITEM_NAMESPACE_TYPE)
    {
        predicate_status[node] = PREDICATE_STATUS_BOUND_NOT_TRAIT;
        return;
    }
    predicate_bound_decl_id[node] = trait_decl_i;
}
