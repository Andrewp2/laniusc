// Emit one graph edge for every alias output. An alias application connects to
// the target alias output; a direct generic target connects to its declaration
// parameter token. Concrete terminal targets are selected after connectivity.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_type_alias_target_node;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_node;
StructuredBuffer<uint> generic_param_token;
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> generic_param_slot_order;
StructuredBuffer<uint> type_generic_param_slot_by_token;
RWStructuredBuffer<uint> alias_equiv_edge_0;
RWStructuredBuffer<uint> alias_source_hir_by_target_hir;

static const uint INVALID = 0xffffffffu;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint HIR_ITEM_NAMESPACE_TYPE = 3u;
static const uint GENERIC_PARAM_KIND_TYPE = 1u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_hir_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint active_decl_count()
{
    return min(decl_count_out[0u], gParams.n_hir_nodes);
}

bool alias_decl(uint decl_i)
{
    return decl_i < active_decl_count() &&
           decl_kind[decl_i] == HIR_ITEM_KIND_TYPE_ALIAS &&
           decl_namespace[decl_i] == HIR_ITEM_NAMESPACE_TYPE;
}

uint graph_hir_node(uint node)
{
    return node < active_hir_count() && gParams.n_tokens <= INVALID - node
        ? gParams.n_tokens + node
        : INVALID;
}

uint active_generic_param_count()
{
    return min(generic_param_count_out[0u], gParams.n_tokens);
}

bool slot_key_less(uint row, uint owner, uint kind)
{
    if (row >= active_generic_param_count())
        return false;
    uint row_owner = generic_param_owner_node[row];
    if (row_owner != owner)
        return row_owner < owner;
    return generic_param_kind[row] < kind;
}

uint type_parameter_token(uint owner, uint slot)
{
    uint count = active_generic_param_count();
    uint lo = 0u;
    uint hi = count;
    for (uint step = 0u; step < 32u; step += 1u)
    {
        if (lo >= hi)
            continue;
        uint mid = lo + (hi - lo) / 2u;
        uint row = generic_param_slot_order[mid];
        if (slot_key_less(row, owner, GENERIC_PARAM_KIND_TYPE))
            lo = mid + 1u;
        else
            hi = mid;
    }
    uint ordered = lo + slot;
    if (ordered >= count)
        return INVALID;
    uint row = generic_param_slot_order[ordered];
    if (row >= count || generic_param_owner_node[row] != owner ||
        generic_param_kind[row] != GENERIC_PARAM_KIND_TYPE)
        return INVALID;
    uint token = generic_param_token[row];
    return token < gParams.n_tokens ? token : INVALID;
}

uint target_alias_node(uint target_node)
{
    uint path_i = target_node < active_hir_count()
        ? path_id_by_owner_hir[target_node]
        : INVALID;
    uint decl_i = path_i < gParams.n_hir_nodes ? resolved_type_decl[path_i] : INVALID;
    return alias_decl(decl_i)
        ? decl_hir_node[decl_i]
        : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint decl_i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (!alias_decl(decl_i))
        return;
    uint alias_node = decl_hir_node[decl_i];
    if (alias_node >= active_hir_count())
        return;

    uint target_node = hir_type_alias_target_node[alias_node];
    uint target_alias = target_alias_node(target_node);
    if (target_alias != INVALID)
    {
        alias_source_hir_by_target_hir[target_node] = alias_node;
        uint target_graph_node = graph_hir_node(target_alias);
        if (target_graph_node != INVALID)
            alias_equiv_edge_0[alias_node] = target_graph_node;
        return;
    }

    uint target_token = target_node < active_hir_count() ? hir_token_pos[target_node] : INVALID;
    uint slot = target_token < gParams.n_tokens
        ? type_generic_param_slot_by_token[target_token]
        : INVALID;
    uint parameter_token = slot != INVALID ? type_parameter_token(alias_node, slot) : INVALID;
    if (parameter_token != INVALID)
        alias_equiv_edge_0[alias_node] = parameter_token;
    else
    {
        uint target_graph_node = graph_hir_node(target_node);
        if (target_graph_node != INVALID)
            alias_equiv_edge_0[alias_node] = target_graph_node;
    }
}
