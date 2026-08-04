// Mark compact-HIR type nodes and publish an inverse token-to-row map. A
// counted scan turns these flags into stable compact type ordinals.

import atomics;
import gpu_index;
import hir_records;

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
StructuredBuffer<uint> compact_path_count;
StructuredBuffer<HirPath> compact_paths;
StructuredBuffer<uint> compact_path_segment_count;
StructuredBuffer<HirPathSegment> compact_path_segments;
StructuredBuffer<uint> path_id_by_owner_hir;
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
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

uint type_path_leaf_token(uint node)
{
    if (node >= active_hir_count() || compact_hir_core[node].kind != 5u ||
        compact_hir_payload[node].a != 1u)
        return INVALID;
    uint path_node = compact_hir_payload[node].b;
    if (path_node >= active_hir_count())
        return INVALID;
    uint path = path_id_by_owner_hir[path_node];
    uint path_count = min(compact_path_count[0u], gParams.n_hir_nodes);
    if (path >= path_count)
        return INVALID;
    HirPath record = compact_paths[path];
    uint segment_count = min(compact_path_segment_count[0u], gParams.n_tokens);
    if (record.segment_count == 0u ||
        record.segment_start >= segment_count ||
        record.segment_count > segment_count - record.segment_start)
        return INVALID;
    return compact_path_segments[record.segment_start + record.segment_count - 1u].name_token;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    uint semantic_count = active_hir_count();
    if (row >= semantic_count)
        return;
    uint node = row;
    if (node >= active_hir_count() || compact_hir_core[node].kind != 5u ||
        compact_hir_payload[node].a == TYPE_FORM_NONE)
        return;
    uint token = compact_hir_core[node].token_start;
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
    uint leaf_token = type_path_leaf_token(node);
    if (leaf_token < gParams.n_tokens)
    {
        atomic_u32_min(type_semantic_row_by_token, leaf_token, row);
    }
}
