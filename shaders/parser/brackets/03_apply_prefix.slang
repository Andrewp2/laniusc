// shaders/parser/brackets_03_apply_prefix.slang
// Apply block_prefix to exscan_inblock and publish the bracket layer, and each
// 256-row block's local minimum heap over the layers. pse_04_pair_by_layer
// searches those heaps (blocked_search_tree.slang); 04_build_min_tree builds
// the heap over the blocks from their roots. The global exclusive depth is
// phase-local and no longer retained by this pass.

import blocked_search_tree;
import gpu_index;
import prefix_scan;

struct Params
{
    uint n_sc;
    uint wg_size;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> sc_stream;
StructuredBuffer<uint> partial_parse_status; // [4]=actual stack-change count
StructuredBuffer<int> exscan_inblock;
StructuredBuffer<int> block_prefix;

// read min_depth to offset layers to non-negative range
StructuredBuffer<int> out_depths_ro; // [0]=final, [1]=min (written by pass 02)

RWStructuredBuffer<uint> layer;       // len = n_sc (depth layer: push→d+1, pop→d)
RWStructuredBuffer<int> layer_local_min; // len = blocks * 256

groupshared int s_heap[512];

static const uint MAX_GROUPS_X = 65535u;
static const uint WG_SIZE = 256u;
static const int INF = 2147483647;

struct LayerMin : IPrefixScanOp<int>
{
    static int identity()
    {
        return INF;
    }

    static int combine(int left, int right)
    {
        return min(left, right);
    }
};

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    const uint n = min(gParams.n_sc, partial_parse_status[4u]);
    const uint block = linear_group_id_2d(gid, MAX_GROUPS_X);
    const uint lane = ltid.x;
    const uint i = block * WG_SIZE + lane;
    // The whole group leaves together: searches never read blocks past the
    // stack changes, and 04_build_min_tree never combines them with earlier
    // ones in a node a search reads.
    if (block * WG_SIZE >= n)
        return;

    int value = INF;
    if (i < n)
    {
        int d0 = exscan_inblock[i] + block_prefix[block];

        // offset so layers are non-negative even for invalid streams
        int md = out_depths_ro[1];
        int off = (md < 0) ? -md : 0;
        int d = d0 + off;

        uint code = sc_stream[i];
        bool is_push = (code & 1u) == 1u;
        uint row_layer = is_push ? (uint)(d + 1) : (uint)d;
        layer[i] = row_layer;
        value = int(row_layer);
    }

    blocked_local_heap_build<int, LayerMin>(lane, value, s_heap);
    layer_local_min[block * WG_SIZE + lane] = s_heap[max(lane, 1u)];
}
