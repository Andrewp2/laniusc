// Validate generic-bound argument rows after declaration resolution.
//
// The preceding collector owns bound syntax, generic subjects, and trait-path
// resolution. This pass consumes those records and independently validates the
// argument types and the resolved trait's generic arity.

import atomics;
import type_checker.predicates.owner_lookup;

#define PREDICATE_BOUND_DECL_RESOLUTION 0
#include "collect_common.slang"

StructuredBuffer<uint> compact_predicate_count;
RWStructuredBuffer<uint> predicate_owner_lookup_head;
RWStructuredBuffer<uint> predicate_owner_lookup_next;

uint active_predicate_count_for_owner_lookup()
{
    return min(compact_predicate_count[0u], gParams.n_hir_nodes);
}

void insert_owner_predicate(uint node, uint owner_decl)
{
    uint predicate_count = active_predicate_count_for_owner_lookup();
    uint owner_token = generic_owner_token_for_decl(owner_decl);
    if (predicate_count == 0u || !valid_token(owner_token))
        return;

    uint bucket = predicate_owner_lookup_bucket(owner_token, predicate_count);
    uint prior = predicate_owner_lookup_head[bucket];
    for (;;)
    {
        predicate_owner_lookup_next[node] = prior;
        uint observed = atomic_u32_compare_exchange(
            predicate_owner_lookup_head,
            bucket,
            prior,
            node + 1u);
        if (observed == prior)
            return;
        prior = observed;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node) ||
        compact_hir_semantic_facts[node].semantic_kind != HIR_SEMANTIC_BOUND_PATH)
        return;

    uint owner_decl = predicate_owner_node[node];
    uint trait_decl_i = predicate_bound_decl_id[node];
    if (!valid_node(owner_decl) || trait_decl_i == INVALID)
        return;

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
    if (trait_param_count != INVALID && arg_count == trait_param_count)
    {
        predicate_status[node] = PREDICATE_STATUS_OK;
        insert_owner_predicate(node, owner_decl);
    }
    else
    {
        predicate_status[node] = PREDICATE_STATUS_BOUND_ARITY_MISMATCH;
    }
}
