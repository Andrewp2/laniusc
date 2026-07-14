// Substitute a normalized alias output at every named alias application.
// One HIR lane handles one type-expression root. Generic outputs select from
// the application's compact argument row; concrete outputs reuse the
// declaration ref finalized by alias-equivalence normalization.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_type_path_leaf_node;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_decl_hir_node_by_token;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> alias_normalized_source;
RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;

static const uint INVALID = 0xffffffffu;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_ERROR = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_hir_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_ref(uint tag, uint payload)
{
    return tag != TYPE_REF_INVALID && tag != TYPE_REF_ERROR && payload != INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (node >= active_hir_count())
        return;

    uint owner_token = hir_token_pos[node];
    uint leaf_node = hir_type_path_leaf_node[node];
    uint leaf_token = leaf_node < active_hir_count() ? hir_token_pos[leaf_node] : INVALID;
    if (owner_token >= gParams.n_tokens || leaf_token >= gParams.n_tokens)
        return;

    uint decl_token = type_instance_decl_token[leaf_token];
    uint alias_node = decl_token < gParams.n_tokens
        ? type_decl_hir_node_by_token[decl_token]
        : INVALID;
    if (alias_node >= active_hir_count() ||
        hir_item_kind[alias_node] != HIR_ITEM_KIND_TYPE_ALIAS)
        return;

    uint source = alias_normalized_source[alias_node];
    uint tag = TYPE_REF_INVALID;
    uint payload = INVALID;
    if (source < gParams.n_tokens)
    {
        uint slot = type_generic_param_slot_by_token[source];
        uint row_start = type_instance_arg_row_start[leaf_token];
        uint row_i = slot != INVALID && row_start != INVALID ? row_start + slot : INVALID;
        if (row_i < type_instance_arg_row_count_out[0u])
        {
            tag = type_instance_arg_row_ref_tag[row_i];
            payload = type_instance_arg_row_ref_payload[row_i];
        }
    }
    else if (source != INVALID && decl_token < gParams.n_tokens)
    {
        tag = type_expr_ref_tag[decl_token];
        payload = type_expr_ref_payload[decl_token];
    }

    if (!valid_ref(tag, payload))
        return;
    type_expr_ref_tag[owner_token] = tag;
    type_expr_ref_payload[owner_token] = payload;
    type_expr_ref_tag[leaf_token] = tag;
    type_expr_ref_payload[leaf_token] = payload;
}
