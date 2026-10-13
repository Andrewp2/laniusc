// Validate trait and inherent impl-header rows from the bounds/impl shared module.

import atomics;
import type_checker.predicates.impl_lookup;

#define PREDICATE_COLLECT_IMPL_RECORDS 1
#define PREDICATE_BOUND_DECL_RESOLUTION 0
#define PREDICATE_BOUND_ARGUMENT_VALIDATION 0
#include "collect_common.slang"

StructuredBuffer<uint> compact_predicate_count;
StructuredBuffer<uint> visible_type;
RWStructuredBuffer<uint> predicate_impl_lookup_head;
RWStructuredBuffer<uint> predicate_impl_lookup_next;

static const uint HIR_IMPL = 35u;

void index_trait_impl(uint node)
{
    uint predicate_count = min(compact_predicate_count[0u], gParams.n_hir_nodes);
    if (predicate_count == 0u || predicate_status[node] != PREDICATE_STATUS_OK)
        return;

    uint arg_count = predicate_bound_arg_count[node];
    uint root = predicate_trait_impl_trait_type_node[node];
    uint2 subject = predicate_type_reference(impl_receiver_type_node(node));
    uint hash;
    if (!predicate_key_hash<ScopedCheckedTypeGraph>(subject, root, arg_count, INVALID, hash))
    {
        predicate_status[node] = PREDICATE_STATUS_INVALID_IMPL_ARG;
        return;
    }
    uint bucket = predicate_impl_lookup_bucket(predicate_bound_decl_id[node],
        arg_count, hash, predicate_count);
    uint prior = predicate_impl_lookup_head[bucket];
    for (;;)
    {
        predicate_impl_lookup_next[node] = prior;
        uint observed = atomic_u32_compare_exchange(
            predicate_impl_lookup_head,
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
    if (!valid_node(node) || compact_hir_core[node].kind != HIR_IMPL)
        return;

    if (compact_hir_semantic_facts[node].semantic_kind == HIR_SEMANTIC_IMPL_TRAIT)
    {
        validate_trait_impl_node(node);
        index_trait_impl(node);
        return;
    }

    if (compact_hir_semantic_facts[node].semantic_kind == HIR_SEMANTIC_IMPL_INHERENT)
    {
        validate_inherent_impl_header_node(node);
        return;
    }
}
