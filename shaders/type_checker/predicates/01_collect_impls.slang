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

static const uint IMPL_TYPE_REF_SCALAR = 1u;
static const uint IMPL_TYPE_REF_GENERIC_PARAM = 2u;
static const uint IMPL_TY_UNKNOWN = 0u;
static const uint IMPL_TY_GENERIC_BASE = 8192u;
static const uint HIR_IMPL = 35u;

uint impl_type_code_for_token(uint token)
{
    if (!valid_token(token))
        return IMPL_TY_UNKNOWN;
    uint tag = type_expr_ref_tag[token];
    uint payload = type_expr_ref_payload[token];
    if (tag == IMPL_TYPE_REF_SCALAR)
        return payload;
    if (tag == IMPL_TYPE_REF_GENERIC_PARAM)
    {
        uint slot = type_generic_param_slot_by_token[token];
        return slot == INVALID ? IMPL_TY_UNKNOWN : IMPL_TY_GENERIC_BASE + slot;
    }
    return visible_type[token];
}

uint impl_type_code(uint value)
{
    return value != INVALID && (value & PREDICATE_ARG_TYPE_CODE_BIT) != 0u
        ? value & ~PREDICATE_ARG_TYPE_CODE_BIT
        : impl_type_code_for_token(value);
}

void index_trait_impl(uint node)
{
    uint predicate_count = min(compact_predicate_count[0u], gParams.n_hir_nodes);
    if (predicate_count == 0u || predicate_status[node] != PREDICATE_STATUS_OK)
        return;

    uint arg_count = predicate_bound_arg_count[node];
    uint arg0_type = arg_count >= 1u
        ? impl_type_code(predicate_bound_first_arg_token[node])
        : IMPL_TY_UNKNOWN;
    uint arg1_type = arg_count >= 2u
        ? impl_type_code(predicate_bound_second_arg_token[node])
        : IMPL_TY_UNKNOWN;
    uint bucket = predicate_impl_lookup_bucket(
        predicate_bound_decl_id[node],
        impl_type_code(predicate_subject_token[node]),
        arg_count,
        arg0_type,
        arg1_type,
        predicate_count);
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
