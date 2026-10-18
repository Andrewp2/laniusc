// Pareas-style typed bracket validation with one previous-smaller-or-equal
// query per closing stack event. The query climbs the blocks' local layer
// heaps from 03_apply_prefix and the block-minimum tree from
// 04_build_min_tree, so it reads O(log distance) layers instead of scanning
// rows (blocked_search_tree.slang). The production path records only
// validity; debug/readback builds may additionally materialize the involutive
// match table.

import atomics;
import blocked_search_tree;
import gpu_index;
import segment_tree;

struct Params
{
    uint n_sc;
    uint n_blocks;
    uint leaf_base;
    uint typed_check;
    uint emit_matches;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> sc_stream;
StructuredBuffer<uint> partial_parse_status;
StructuredBuffer<uint> layer;
// Local minimum heaps of every 256-row block of layers.
StructuredBuffer<int> layer_local_min;
StructuredBuffer<int> min_tree;
RWStructuredBuffer<uint> match_for_index;
RWStructuredBuffer<uint> out_valid;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_count()
{
    return min(gParams.n_sc, partial_parse_status[4u]);
}

public struct StackDepthTree : IBlockedSearchTree<int>
{
    [ForceInline] public static uint row_count() { return active_count(); }
    [ForceInline] public static int row_value(uint row) { return int(layer[row]); }
    [ForceInline] public static int local_node(uint block, uint node) { return layer_local_min[block * WG_SIZE + node]; }
    [ForceInline] public static uint block_leaf_base() { return gParams.leaf_base; }
    [ForceInline] public static int block_node(uint node) { return min_tree[node]; }
}

public struct DepthAtMost : IRangeSearchPredicate<int, int>
{
    [ForceInline] public static bool aggregate_may_match(int aggregate, int query) { return aggregate <= query; }
    [ForceInline] public static bool leaf_matches(int value, int query) { return value <= query; }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint close_i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    uint n = active_count();
    if (close_i >= n)
        return;

    uint close_code = sc_stream[close_i];
    if ((close_code & 1u) != 0u)
        return;

    int wanted_depth = int(layer[close_i]);
    uint open_i = blocked_search_last_before<int, int, StackDepthTree, DepthAtMost>(
        close_i,
        wanted_depth);
    if (open_i >= close_i)
    {
        atomic_u32_and(out_valid, 0u, 0u);
        return;
    }

    uint open_code = sc_stream[open_i];
    bool pair_ok = (open_code & 1u) != 0u &&
        int(layer[open_i]) == wanted_depth;
    if (gParams.typed_check != 0u)
        pair_ok = pair_ok && (open_code >> 1u) == (close_code >> 1u);
    if (!pair_ok)
    {
        atomic_u32_and(out_valid, 0u, 0u);
        return;
    }

    if (gParams.emit_matches != 0u)
    {
        match_for_index[open_i] = close_i;
        match_for_index[close_i] = open_i;
    }
}
