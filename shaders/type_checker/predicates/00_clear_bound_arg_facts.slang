// Clear predicate-bound argument facts before the structural scatter pass.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<uint> compact_predicate_count;

RWStructuredBuffer<uint> predicate_bound_arg_count;
RWStructuredBuffer<uint> predicate_bound_first_arg_token;
RWStructuredBuffer<uint> predicate_bound_second_arg_token;
RWStructuredBuffer<uint> predicate_status;
RWStructuredBuffer<uint> predicate_trait_impl_trait_type_node;
RWStructuredBuffer<uint> predicate_owner_node;
RWStructuredBuffer<uint> predicate_subject_token;
RWStructuredBuffer<uint> predicate_bound_token;
RWStructuredBuffer<uint> predicate_bound_decl_id;
RWStructuredBuffer<uint> predicate_method_contract_owner_count;
RWStructuredBuffer<uint> predicate_method_contract_lookup_head;
RWStructuredBuffer<uint> predicate_method_validation_status;
RWStructuredBuffer<uint> predicate_method_validation_first_error_row;
RWStructuredBuffer<uint> predicate_owner_lookup_head;
RWStructuredBuffer<uint> predicate_owner_lookup_next;
RWStructuredBuffer<uint> predicate_impl_lookup_head;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

uint active_predicate_count()
{
    return min(compact_predicate_count[0u], active_hir_node_count());
}

uint active_method_count()
{
    return min(compact_method_count[0u], active_hir_node_count());
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= active_hir_node_count())
        return;

    // Two hash buckets per compact predicate keep the average non-owner
    // collision chain below one entry. This pass already spans every active
    // HIR node, so initializing the index adds no dispatch.
    uint predicate_count = active_predicate_count();
    if (node < predicate_count)
    {
        predicate_owner_lookup_head[node * 2u] = 0u;
        predicate_owner_lookup_head[node * 2u + 1u] = 0u;
        predicate_impl_lookup_head[node * 2u] = 0u;
        predicate_impl_lookup_head[node * 2u + 1u] = 0u;
    }
    predicate_owner_lookup_next[node] = 0u;

    uint method_count = active_method_count();
    if (node < method_count)
    {
        predicate_method_contract_lookup_head[node * 2u] = 0u;
        predicate_method_contract_lookup_head[node * 2u + 1u] = 0u;
    }
    predicate_method_contract_owner_count[node] = 0u;

    predicate_bound_arg_count[node] = 0u;
    predicate_bound_first_arg_token[node] = INVALID;
    predicate_bound_second_arg_token[node] = INVALID;
    predicate_status[node] = INVALID;
    predicate_trait_impl_trait_type_node[node] = INVALID;
    predicate_owner_node[node] = INVALID;
    predicate_subject_token[node] = INVALID;
    predicate_bound_token[node] = INVALID;
    predicate_bound_decl_id[node] = INVALID;
    predicate_method_validation_status[node] = INVALID;
    predicate_method_validation_first_error_row[node] = INVALID;
}
