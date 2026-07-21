// Pareas-style typed bracket validation using a block-minimum tree and one
// previous-smaller-or-equal query per closing stack event. The production path
// records only validity; debug/readback builds may additionally materialize the
// involutive match table.

import atomics;
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
StructuredBuffer<int> block_row_min;
StructuredBuffer<int> block_prefix;
StructuredBuffer<int> min_tree;
RWStructuredBuffer<uint> match_for_index;
RWStructuredBuffer<uint> out_valid;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_count()
{
    return min(gParams.n_sc, partial_parse_status[4u]);
}

public struct StackDepthTree : IRangeSearchTree<int>
{
    public static uint n_blocks()
    {
        return gParams.n_blocks;
    }

    public static uint leaf_base()
    {
        return gParams.leaf_base;
    }

    public static int leaf_value(uint block)
    {
        return block_prefix[block] + block_row_min[block];
    }

    public static int tree_value(uint node)
    {
        return min_tree[node];
    }
}

public struct StackDepthRows : IRangeSearchRows<int>
{
    public static uint item_count()
    {
        return active_count();
    }

    public static uint block_size()
    {
        return WG_SIZE;
    }

    public static int row_value(uint row)
    {
        return int(layer[row]);
    }
}

public struct DepthAtMost : IRangeSearchPredicate<int, int>
{
    public static bool aggregate_may_match(int aggregate, int query)
    {
        return aggregate <= query;
    }

    public static bool leaf_matches(int value, int query)
    {
        return value <= query;
    }
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

    uint open_i;
    int wanted_depth = int(layer[close_i]);
    bool found = range_search_tree_last_index_before<
        int,
        int,
        StackDepthTree,
        StackDepthRows,
        DepthAtMost>(close_i, wanted_depth, open_i);

    if (!found || open_i >= close_i)
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
