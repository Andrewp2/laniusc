import gpu_index;
import radix;
import scatter;

struct Params
{
    uint n_sc;
    uint n_layers;
    uint n_blocks;
    uint key_step;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> partial_parse_status;
StructuredBuffer<uint> sc_stream;
StructuredBuffer<uint> layer;
StructuredBuffer<uint> order_in;
StructuredBuffer<uint> radix_bucket_base;
StructuredBuffer<uint> radix_block_bucket_prefix;
RWStructuredBuffer<uint> order_out;
RWStructuredBuffer<uint> slot_for_index;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = 256u;
static const uint SMALL_PAIR_CAPACITY = 2048u;
groupshared uint local_radix_keys[256];

uint pair_active_count()
{
    return min(gParams.n_sc, partial_parse_status[4u]);
}

uint pair_key(uint row)
{
    uint kind = (sc_stream[row] & 1u) == 1u ? 0u : 1u;
    return layer[row] * 2u + kind;
}

public struct PairScatterSource : IStableRadixScatterSource<uint>
{
    public static uint active_count() { return pair_active_count(); }
    public static uint inactive_value() { return INVALID; }
    public static uint ordered_value(uint order_i) { return order_in[order_i]; }
    public static uint radix_key(uint value, uint key_step)
    {
        return radix_byte_key(pair_key(value), key_step);
    }
}

public struct PairOrderSink : IScatterSink<uint>
{
    public static void store(uint dst, uint value)
    {
        order_out[dst] = value;
        if (gParams.key_step == 3u)
            slot_for_index[value] = dst;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint n = pair_active_count();
    if (n <= SMALL_PAIR_CAPACITY)
        return;
    stable_radix_scatter_block<uint, PairScatterSource, PairOrderSink, 256>(
        linear_group_id_2d(gid, MAX_GROUPS_X),
        ltid.x,
        gParams.n_blocks,
        gParams.key_step,
        RADIX_BUCKETS,
        radix_bucket_base,
        radix_block_bucket_prefix,
        local_radix_keys);
}
