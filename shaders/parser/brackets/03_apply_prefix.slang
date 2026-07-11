// shaders/parser/brackets_03_apply_prefix.slang
// Apply block_prefix to exscan_inblock → global depth; also compute layer[i].

import gpu_index;

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

// NEW: read min_depth to offset layers to non-negative range
StructuredBuffer<int> out_depths_ro; // [0]=final, [1]=min (written by pass 02)

RWStructuredBuffer<int> depth_exscan; // len = n_sc (global exclusive)
RWStructuredBuffer<uint> layer;       // len = n_sc (depth layer: push→d+1, pop→d)

static const uint MAX_GROUPS_X = 65535u;
static const uint WG_SIZE = 256u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    const uint n = min(gParams.n_sc, partial_parse_status[4u]);
    const uint GSIZE = gParams.wg_size;
    const uint i = linear_thread_id_2d(tid, MAX_GROUPS_X, WG_SIZE);
    const uint block = i / GSIZE;
    if (i >= n)
        return;

    int d0 = exscan_inblock[i] + block_prefix[block];

    // offset so layers are non-negative even for invalid streams
    int md = out_depths_ro[1];
    int off = (md < 0) ? -md : 0;
    int d = d0 + off;

    depth_exscan[i] = d0;

    uint code = sc_stream[i];
    bool is_push = (code & 1u) == 1u;
    layer[i] = is_push ? (uint)(d + 1) : (uint)d;
}
