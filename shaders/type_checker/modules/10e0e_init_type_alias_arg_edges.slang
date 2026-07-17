// Emit substitution edges from a target alias parameter to its corresponding
// argument node, and from a generic argument node to the source declaration's
// parameter token. Each HIR lane handles one argument; no declaration lane
// walks an argument list.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirTypeArg { uint owner; uint value; uint ordinal; uint file_id; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_type_arg_count;
StructuredBuffer<HirTypeArg> compact_type_args;
StructuredBuffer<uint> alias_source_hir_by_target_hir;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_token;
StructuredBuffer<uint> generic_param_token;
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> generic_param_slot_order;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> alias_equiv_edge_0;
RWStructuredBuffer<uint> alias_equiv_edge_1;

static const uint INVALID = 0xffffffffu;
static const uint GENERIC_PARAM_KIND_TYPE = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint HIR_ITEM_NAMESPACE_TYPE = 3u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_hir_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

uint active_type_arg_count() { return min(gParams.n_hir_nodes, compact_type_arg_count[0u]); }

uint active_generic_param_count()
{
    return min(generic_param_count_out[0u], gParams.n_tokens);
}

uint generic_owner_token(uint owner_node)
{
    if (owner_node >= active_hir_count())
        return INVALID;
    uint name_token = compact_hir_payload[owner_node].b;
    return name_token < gParams.n_tokens ? name_token : compact_hir_core[owner_node].token_start;
}

bool slot_key_less(uint row, uint owner, uint kind)
{
    if (row >= active_generic_param_count())
        return false;
    uint row_owner = generic_param_owner_token[row];
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
    if (row >= count || generic_param_owner_token[row] != owner ||
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
    uint count = min(decl_count_out[0u], gParams.n_hir_nodes);
    return decl_i < count && decl_kind[decl_i] == HIR_ITEM_KIND_TYPE_ALIAS &&
           decl_namespace[decl_i] == HIR_ITEM_NAMESPACE_TYPE
        ? decl_hir_node[decl_i]
        : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (row >= active_type_arg_count())
        return;
    HirTypeArg arg = compact_type_args[row];
    uint owner = arg.owner;
    uint source_owner = owner < active_hir_count()
        ? alias_source_hir_by_target_hir[owner]
        : INVALID;
    uint target_owner = target_alias_node(owner);
    if (source_owner == INVALID || target_owner == INVALID)
        return;
    uint target_parameter = type_parameter_token(
        generic_owner_token(target_owner), arg.ordinal);
    if (target_parameter == INVALID)
        return;

    uint value_node = arg.value;
    if (value_node >= active_hir_count())
        return;
    alias_equiv_edge_0[value_node] = target_parameter;
    uint token = compact_hir_core[value_node].token_start;
    if (token < gParams.n_tokens && type_expr_ref_tag[token] == TYPE_REF_GENERIC_PARAM)
    {
        uint source_slot = type_generic_param_slot_by_token[token];
        uint source_parameter = source_slot != INVALID
            ? type_parameter_token(generic_owner_token(source_owner), source_slot)
            : INVALID;
        if (source_parameter < gParams.n_tokens)
            alias_equiv_edge_1[value_node] = source_parameter;
    }
}
