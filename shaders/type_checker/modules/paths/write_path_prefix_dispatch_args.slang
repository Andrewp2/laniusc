// Produces indirect dispatches for exact path-prefix canonicalization.
//
// Every possible doubling round is recorded by the host. Rounds at or beyond
// the GPU-produced maximum path depth receive a zero dispatch, so source shape
// never creates pipelines or requires a CPU readback.

struct Params
{
    uint segment_capacity;
    uint round_count;
    uint reserved0;
    uint reserved1;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> path_segment_count_out;
StructuredBuffer<uint> path_max_segment_count;
RWStructuredBuffer<uint> path_prefix_row_dispatch_args;
RWStructuredBuffer<uint> path_prefix_round_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

void write_dispatch(RWStructuredBuffer<uint> args, uint base, uint rows)
{
    uint groups = (rows + WG_SIZE - 1u) / WG_SIZE;
    args[base + 0u] = min(groups, MAX_GROUPS_X);
    args[base + 1u] = max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    args[base + 2u] = 1u;
}

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 ltid: SV_GroupThreadID)
{
    uint round_i = ltid.x;
    uint rows = min(path_segment_count_out[0u], gParams.segment_capacity);
    uint max_depth = path_max_segment_count[0u];

    if (round_i == 0u)
        write_dispatch(path_prefix_row_dispatch_args, 0u, rows);

    if (round_i >= gParams.round_count)
        return;

    uint step = 1u << round_i;
    write_dispatch(
        path_prefix_round_dispatch_args,
        round_i * 3u,
        step < max_depth ? rows : 0u);
}
