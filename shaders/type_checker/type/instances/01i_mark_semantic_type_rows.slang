// Mark semantic type nodes in the parser's authoritative dense preorder and
// publish an inverse token-to-row map. A counted scan turns these flags into
// stable compact type ordinals while subtree-end indices remain parser-owned.

import atomics;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_type_path_leaf_node;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> type_semantic_row_by_token;
RWStructuredBuffer<uint> type_semantic_scan_input;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_FORM_NONE = 0u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_hir_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    uint semantic_count = min(hir_semantic_count[0u], active_hir_count());
    if (row >= semantic_count)
        return;
    uint node = hir_semantic_dense_node[row];
    if (node >= active_hir_count() || hir_type_form[node] == TYPE_FORM_NONE)
        return;
    uint token = hir_token_pos[node];
    if (token >= gParams.n_tokens)
        return;
    type_semantic_scan_input[row] = 1u;
    atomic_u32_min(type_semantic_row_by_token, token, row);
    if (type_expr_ref_tag[token] == TYPE_REF_INSTANCE)
    {
        uint instance = type_expr_ref_payload[token];
        if (instance < gParams.n_tokens)
            atomic_u32_min(type_semantic_row_by_token, instance, row);
    }
    uint leaf_node = hir_type_path_leaf_node[node];
    if (leaf_node < active_hir_count())
    {
        uint leaf_token = hir_token_pos[leaf_node];
        if (leaf_token < gParams.n_tokens)
            atomic_u32_min(type_semantic_row_by_token, leaf_token, row);
    }
}
