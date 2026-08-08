// Local semantic-HIR prefix scan.
//
// This is the first half of a Pareas-style compactification boundary: mark
// parser tree nodes that have semantic HIR meaning, compute per-block exclusive
// prefixes, and publish block sums for the global block-prefix scan.

import prefix_scan;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_expr_record;

RWStructuredBuffer<uint> hir_semantic_flag;
RWStructuredBuffer<uint> hir_semantic_local_prefix;
RWStructuredBuffer<uint> hir_semantic_block_sum;

static const uint HIR_NONE = 0u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_EXPR_FORWARD = 1u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_node_count()
{
    return gHirSemantic.uses_status_count != 0u ? min(gHirSemantic.n, tree_count_status[5u]) : gHirSemantic.n;
}

bool meaningful_node(uint node)
{
    uint kind = hir_kind[node];
    if (kind == HIR_NONE)
        return false;
    // The binary-precedence grammar contributes one forwarding/end row per
    // precedence level.  Those rows carry no ownership or source-level
    // construct. Assignment, unary, postfix, and general-expression wrappers
    // still carry parser context in the current HIR and remain until those
    // relations have their own compact representation.
    return kind != HIR_BINARY_EXPR ||
           hir_expr_record[node * 4u] > HIR_EXPR_FORWARD;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_i = linear_group_id(gid);
    uint lane = ltid.x;
    uint node = block_i * WG_SIZE + lane;
    uint active = active_node_count();
    uint flag = node < active && meaningful_node(node) ? 1u : 0u;
    uint inclusive = prefix_scan_u32_256(lane, flag);

    if (node < gHirSemantic.n)
    {
        hir_semantic_flag[node] = flag;
        hir_semantic_local_prefix[node] = inclusive - flag;
    }

    if (lane == WG_SIZE - 1u)
        hir_semantic_block_sum[block_i] = inclusive;
}
