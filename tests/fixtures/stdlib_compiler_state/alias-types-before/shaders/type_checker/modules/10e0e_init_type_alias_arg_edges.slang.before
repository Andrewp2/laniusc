// Emit substitution edges from a target alias parameter to its corresponding
// argument node, and from a generic argument node to the source declaration's
// parameter token. Each HIR lane handles one argument; no declaration lane
// walks an argument list.

import hir_records;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirRange> compact_generic_param_ranges;
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
StructuredBuffer<uint> generic_param_token;
StructuredBuffer<uint> generic_type_param_prefix;
StructuredBuffer<uint> generic_type_param_rows;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> alias_equiv_edge_0;
RWStructuredBuffer<uint> alias_equiv_edge_1;

static const uint INVALID = 0xffffffffu;
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

uint type_parameter_token(uint owner_node, uint slot)
{
    uint count = active_generic_param_count();
    if (owner_node >= active_hir_count())
        return INVALID;
    HirRange range = compact_generic_param_ranges[owner_node];
    if (range.count == 0u || range.start == INVALID || range.start >= count)
        return INVALID;
    uint ordered = generic_type_param_prefix[range.start] + slot;
    uint row = ordered < count ? generic_type_param_rows[ordered] : INVALID;
    if (row >= count || row < range.start || row >= range.start + range.count)
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
        target_owner, arg.ordinal);
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
            ? type_parameter_token(source_owner, source_slot)
            : INVALID;
        if (source_parameter < gParams.n_tokens)
            alias_equiv_edge_1[value_node] = source_parameter;
    }
}
