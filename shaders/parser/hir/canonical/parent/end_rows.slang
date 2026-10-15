// The first level of the canonical-end search heaps: one local maximum heap
// over each block of 256 canonical subtree ends. The heaps use the
// semantic-end layout (semantic/parent/end_tree.slang); canonical/core.slang
// searches them for each canonical row's nearest canonical ancestor. One
// workgroup owns one block of the canonical rows.

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
StructuredBuffer<uint> canonical_prefix_before_raw;
StructuredBuffer<uint> canonical_dense_to_raw;
StructuredBuffer<uint> subtree_end;

RWStructuredBuffer<uint> hir_canonical_end_local_max;

static const uint MAX_GROUPS_X = 65535u;

groupshared uint s_heap[512];

// The canonical row just past canonical row `row`'s subtree, as
// canonical/core.slang publishes it in HirLinks.subtree_end.
uint canonical_end(uint row, uint count)
{
    uint raw = canonical_dense_to_raw[row];
    uint end = raw < gCanonical.raw_capacity ? subtree_end[raw] : gCanonical.raw_capacity;
    return end >= gCanonical.raw_capacity ? count : canonical_prefix_before_raw[end];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block = gid.x + gid.y * MAX_GROUPS_X;
    uint lane = ltid.x;
    uint count = min(canonical_count[0u], gCanonical.canonical_capacity);
    // The whole group leaves together: searches never read blocks past the
    // canonical rows, and end_blocks reads their maxima as 0.
    if (block * SEMANTIC_END_FANOUT >= count)
        return;
    uint row = block * SEMANTIC_END_FANOUT + lane;
    uint end = row < count ? canonical_end(row, count) : 0u;
    blocked_local_heap_build<uint, PrefixScanU32Max>(lane, end, s_heap);
    hir_canonical_end_local_max[block * SEMANTIC_END_FANOUT + lane] = s_heap[max(lane, 1u)];
}
