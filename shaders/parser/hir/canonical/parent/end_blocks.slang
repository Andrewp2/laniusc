// The second level of the canonical-end search heaps (end_rows.slang): one
// local maximum heap over each group of 256 block maxima. One workgroup owns
// one group.

import prefix_scan;
import blocked_search_tree;
import parser.hir.semantic.parent.end_tree;

struct Params
{
    uint raw_capacity;
    uint canonical_capacity;
    uint uses_status_count;
    uint local_ancestor_span;
    uint records_use_token_rows;
};

ConstantBuffer<Params> gCanonical;

StructuredBuffer<uint> canonical_count;
StructuredBuffer<uint> hir_canonical_end_local_max;

RWStructuredBuffer<uint> hir_canonical_end_blocks;

static const uint MAX_GROUPS_X = 65535u;

groupshared uint s_heap[512];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint group = gid.x + gid.y * MAX_GROUPS_X;
    uint lane = ltid.x;
    uint count = min(canonical_count[0u], gCanonical.canonical_capacity);
    uint active_blocks = (count + SEMANTIC_END_FANOUT - 1u) / SEMANTIC_END_FANOUT;
    // The whole group leaves together; end_top reads its maximum as 0.
    if (group >= semantic_end_group_count(gCanonical.canonical_capacity) ||
        group * SEMANTIC_END_FANOUT >= active_blocks)
        return;
    uint block = group * SEMANTIC_END_FANOUT + lane;
    uint block_max = block < active_blocks
        ? hir_canonical_end_local_max[block * SEMANTIC_END_FANOUT]
        : 0u;
    blocked_local_heap_build<uint, PrefixScanU32Max>(lane, block_max, s_heap);
    hir_canonical_end_blocks[group * SEMANTIC_END_FANOUT + lane] = s_heap[max(lane, 1u)];
}
