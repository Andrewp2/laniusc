// Scatter semantic HIR node ids into dense row order.
//
// Inputs are the local node prefix and scanned block prefixes produced by the
// preceding passes. Outputs form the phase-boundary map used to move later
// stages off sparse parse-tree capacity:
//   - hir_node_dense_id[parse_node] = dense semantic row or INVALID
//   - hir_semantic_prefix_before_node[parse_node] = semantic rows before parse_node
//   - hir_semantic_dense_node[dense_row] = original parse node
//   - hir_semantic_count[0] = dense semantic row count

import prefix_scan;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_flag;
StructuredBuffer<uint> hir_semantic_local_prefix;
StructuredBuffer<uint> hir_semantic_block_prefix;

RWStructuredBuffer<uint> hir_node_dense_id;
RWStructuredBuffer<uint> hir_semantic_prefix_before_node;
RWStructuredBuffer<uint> hir_semantic_dense_node;
RWStructuredBuffer<uint> hir_semantic_count;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirSemantic.uses_status_count != 0u ? min(gHirSemantic.n, tree_count_status[5u]) : gHirSemantic.n;
}

uint block_count()
{
    return (gHirSemantic.n + WG_SIZE - 1u) / WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    uint semantic_count = inclusive_scan_total(
        block_count(),
        hir_semantic_block_prefix);
    if (node == 0u)
        hir_semantic_count[0u] = semantic_count;

    if (node >= gHirSemantic.n)
        return;

    uint active = active_node_count();
    uint block_i = node / WG_SIZE;
    uint block_base = block_i == 0u ? 0u : hir_semantic_block_prefix[block_i - 1u];
    uint prefix_before = node < active ? block_base + hir_semantic_local_prefix[node] : semantic_count;
    hir_semantic_prefix_before_node[node] = prefix_before;

    uint flag = node < active ? hir_semantic_flag[node] : 0u;
    if (flag == 0u)
    {
        hir_node_dense_id[node] = INVALID;
        return;
    }

    uint dense_row = prefix_before;
    hir_node_dense_id[node] = dense_row;
    if (dense_row < gHirSemantic.n)
        hir_semantic_dense_node[dense_row] = node;
}
