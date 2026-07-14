// Identify generic aliases whose target is another alias with a complete
// positional parameter forwarding row. Argument lanes validate the row in the
// following pass; no declaration lane walks the argument list.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_type_alias_target_node;
StructuredBuffer<uint> hir_type_arg_count;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> type_decl_generic_param_count_by_node;
RWStructuredBuffer<uint> alias_forwarding;
RWStructuredBuffer<uint> alias_forwarding_target_decl;
RWStructuredBuffer<uint> alias_decl_by_target_hir;

static const uint INVALID = 0xffffffffu;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint HIR_ITEM_NAMESPACE_TYPE = 3u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint decl_i = linear_thread_id(dtid);
    if (!alias_decl(decl_i))
        return;

    uint alias_node = decl_hir_node[decl_i];
    if (alias_node >= active_hir_count() ||
        type_decl_generic_param_count_by_node[alias_node] == 0u)
        return;

    uint target_node = hir_type_alias_target_node[alias_node];
    uint path_i = target_node < active_hir_count()
        ? path_id_by_owner_hir[target_node]
        : INVALID;
    uint target_decl = path_i < gParams.n_hir_nodes ? resolved_type_decl[path_i] : INVALID;
    if (!alias_decl(target_decl) || target_decl == decl_i)
        return;

    uint target_alias_node = decl_hir_node[target_decl];
    uint target_arity = target_alias_node < active_hir_count()
        ? type_decl_generic_param_count_by_node[target_alias_node]
        : 0u;
    if (target_arity == 0u || hir_type_arg_count[target_node] != target_arity)
        return;

    alias_forwarding[decl_i] = 1u;
    alias_forwarding_target_decl[decl_i] = target_decl;
    alias_decl_by_target_hir[target_node] = decl_i;
}
