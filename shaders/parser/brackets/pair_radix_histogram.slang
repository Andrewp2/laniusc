import gpu_index;
import radix;

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
RWStructuredBuffer<uint> radix_block_histogram;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = 256u;
static const uint SMALL_PAIR_CAPACITY = 2048u;

uint pair_active_count()
{
    return min(gParams.n_sc, partial_parse_status[4u]);
}

uint pair_key(uint row)
{
    uint kind = (sc_stream[row] & 1u) == 1u ? 0u : 1u;
    return layer[row] * 2u + kind;
}

public struct PairRadixSource : IRadixU8KeySource
{
    public static uint active_count() { return pair_active_count(); }
    public static uint ordered_row(uint order_i) { return order_in[order_i]; }
    public static uint radix_key(uint row, uint key_step)
    {
        return radix_byte_key(pair_key(row), key_step);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint n = pair_active_count();
    if (n <= SMALL_PAIR_CAPACITY)
        return;
    radix_u8_histogram_block<PairRadixSource>(
        linear_group_id_2d(gid, MAX_GROUPS_X),
        ltid.x,
        gParams.n_blocks,
        gParams.key_step,
        WG_SIZE,
        RADIX_BUCKETS,
        radix_block_histogram);
}
