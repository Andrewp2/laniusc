// Finalize generic-parameter candidate flags after owner pointer jumping.
//
// Ordinary generic parameters have explicit parameter productions. Impl
// headers use list-link productions as parameter rows, so the mark pass emits
// those as candidates and this pass retains them only when their resolved
// declaration owner is an impl. No lane walks a parent or source-span chain.

import generated_parse_production_ids;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> generic_decl_owner_by_node;
RWStructuredBuffer<uint> generic_param_flag;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool impl_param_candidate(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = node_kind[node];
    return kind == PROD_ENUM_TYPE_PARAMS_SOME || kind == PROD_ENUM_TYPE_PARAMS_MORE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node) || generic_param_flag[node] == 0u || !impl_param_candidate(node))
        return;

    uint owner = generic_decl_owner_by_node[node];
    generic_param_flag[node] = valid_node(owner) &&
                               (node_kind[owner] == PROD_IMPL_INHERENT ||
                                node_kind[owner] == PROD_IMPL_TRAIT)
        ? 1u
        : 0u;
}
