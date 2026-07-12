// Collect generic-bound predicate rows.

#include "collect_common.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    clear_predicate_record(node);

    if (node_kind[node] == PROD_BOUND_TYPE_IDENT || node_kind[node] == PROD_BOUND_TYPE_REF)
        mark_direct_bound_syntax_tokens(node);

    uint list_node = INVALID;
    if (node_kind[node] == PROD_BOUND_TYPE_IDENT || node_kind[node] == PROD_BOUND_TYPE_REF)
        list_node = predicate_list_for_direct_bound(node);

    if (!valid_node(list_node))
    {
        if (unsupported_direct_bound_list_relation(node))
        {
            uint owner_decl = generic_decl_owner_for_node(node);
            predicate_bound_token[node] = node_kind[node] == PROD_BOUND_TYPE_IDENT
                ? bound_path_leaf_token(node)
                : hir_token_pos[node];
            predicate_status[node] =
                valid_node(owner_decl) &&
                !callable_generic_decl_item_kind(hir_item_kind[owner_decl])
                    ? PREDICATE_STATUS_UNSUPPORTED_NON_CALLABLE_BOUND
                    : PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION;
        }
        return;
    }

    uint owner_decl = generic_decl_owner_for_node(list_node);
    if (!valid_node(owner_decl))
        owner_decl = generic_decl_owner_for_node(node);
    uint subject_token = predicate_subject_token_for_list(list_node);
    uint bound_token = node_kind[node] == PROD_BOUND_TYPE_IDENT
        ? bound_path_leaf_token(node)
        : hir_token_pos[node];

    predicate_owner_node[node] = owner_decl;
    predicate_subject_token[node] = subject_token;
    predicate_bound_token[node] = bound_token;

    if (node_kind[node] != PROD_BOUND_TYPE_IDENT)
    {
        predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;
        return;
    }

    if (!valid_node(owner_decl) || !valid_token(subject_token))
    {
        predicate_status[node] =
            valid_node(owner_decl) &&
            !callable_generic_decl_item_kind(hir_item_kind[owner_decl])
                ? PREDICATE_STATUS_UNSUPPORTED_NON_CALLABLE_BOUND
                : PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION;
        return;
    }

    if (!callable_generic_decl_item_kind(hir_item_kind[owner_decl]))
    {
        predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_NON_CALLABLE_BOUND;
        return;
    }

    uint subject_slot = generic_param_slot_for_name(owner_decl, subject_token);
    if (subject_slot == INVALID)
    {
        predicate_status[node] = direct_type_param_bound_list(list_node)
            ? PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION
            : PREDICATE_STATUS_INVALID_SUBJECT;
        return;
    }

    if (!bound_path_shape_supported(node))
    {
        uint overflow_token = bound_path_prefix_overflow_token(node);
        if (valid_token(overflow_token))
        {
            predicate_bound_first_arg_token[node] = overflow_token;
            predicate_status[node] = PREDICATE_STATUS_BOUND_PATH_TOO_DEEP;
            return;
        }

        uint arg_token = first_direct_bound_arg_diagnostic_token(node);
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
        uint arg_token = first_direct_bound_arg_diagnostic_token(node);
        if (valid_token(arg_token))
            predicate_bound_first_arg_token[node] = arg_token;
        predicate_status[node] = PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE;
        return;
    }

    uint trait_decl_i = type_decl_for_bound_path(node, owner_decl);
    if (!valid_token(bound_token) ||
        trait_decl_i == INVALID ||
        decl_kind[trait_decl_i] != HIR_ITEM_KIND_TRAIT ||
        decl_namespace[trait_decl_i] != HIR_ITEM_NAMESPACE_TYPE)
    {
        predicate_status[node] = PREDICATE_STATUS_BOUND_NOT_TRAIT;
        return;
    }
    predicate_bound_decl_id[node] = trait_decl_i;

    uint arg_count;
    uint first_arg_token;
    uint second_arg_token;
    uint arg_status = validate_bound_type_args(
        owner_decl,
        node,
        arg_count,
        first_arg_token,
        second_arg_token);
    predicate_bound_arg_count[node] = arg_count;
    predicate_bound_first_arg_token[node] = first_arg_token;
    predicate_bound_second_arg_token[node] = second_arg_token;
    if (arg_status != PREDICATE_STATUS_OK)
    {
        predicate_status[node] = arg_status;
        return;
    }

    uint trait_param_count = trait_decl_generic_param_count(trait_decl_i);
    predicate_status[node] = trait_param_count != INVALID && arg_count == trait_param_count
        ? PREDICATE_STATUS_OK
        : PREDICATE_STATUS_BOUND_ARITY_MISMATCH;
}
