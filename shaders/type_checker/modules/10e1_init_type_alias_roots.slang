// Seed type-alias parent links. Non-generic aliases always forward. Generic
// aliases forward only when the preceding parallel validation proved a full
// positional parameter mapping, which preserves use-site substitution.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirRange { uint start; uint count; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_type_alias_target;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> type_decl_generic_param_count_by_owner_token;
StructuredBuffer<HirRange> compact_type_arg_ranges;
StructuredBuffer<uint> alias_forwarding;
StructuredBuffer<uint> alias_forwarding_target_decl;
StructuredBuffer<uint> alias_forwarding_valid_arg_count;
RWStructuredBuffer<uint> alias_root_decl;

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
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

uint active_decl_count()
{
    return min(decl_count_out[0u], gParams.n_hir_nodes);
}

bool non_generic_alias(uint decl_i)
{
    if (decl_i >= active_decl_count() || decl_kind[decl_i] != HIR_ITEM_KIND_TYPE_ALIAS ||
        decl_namespace[decl_i] != HIR_ITEM_NAMESPACE_TYPE)
        return false;
    uint node = decl_hir_node[decl_i];
    uint owner_token = node < active_hir_count() ? compact_hir_payload[node].b : INVALID;
    return owner_token < gParams.n_tokens &&
           type_decl_generic_param_count_by_owner_token[owner_token] == 0u;
}

bool alias_decl(uint decl_i)
{
    return decl_i < active_decl_count() && decl_kind[decl_i] == HIR_ITEM_KIND_TYPE_ALIAS &&
           decl_namespace[decl_i] == HIR_ITEM_NAMESPACE_TYPE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint decl_i = linear_thread_id(dtid);
    if (decl_i >= gParams.n_hir_nodes)
        return;
    alias_root_decl[decl_i] = decl_i;
    if (!alias_decl(decl_i))
        return;
    if (!non_generic_alias(decl_i))
    {
        uint target_decl = alias_forwarding_target_decl[decl_i];
        uint alias_node = decl_hir_node[decl_i];
        uint target_node = alias_node < active_hir_count()
            ? compact_type_alias_target[alias_node]
            : INVALID;
        uint expected = target_node < active_hir_count() ? compact_type_arg_ranges[target_node].count : 0u;
        if (alias_forwarding[decl_i] != 0u &&
            alias_forwarding_valid_arg_count[decl_i] == expected &&
            target_decl != decl_i && alias_decl(target_decl))
            alias_root_decl[decl_i] = target_decl;
        return;
    }
    uint alias_node = decl_hir_node[decl_i];
    uint target_node = alias_node < active_hir_count()
        ? compact_type_alias_target[alias_node]
        : INVALID;
    uint path_i = target_node < active_hir_count()
        ? path_id_by_owner_hir[target_node]
        : INVALID;
    uint target_decl = path_i < gParams.n_hir_nodes ? resolved_type_decl[path_i] : INVALID;
    if (target_decl != decl_i && non_generic_alias(target_decl))
        alias_root_decl[decl_i] = target_decl;
}
