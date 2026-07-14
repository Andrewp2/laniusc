// Stable scatter for one exact linker-symbol radix byte.

import gpu_index;
import radix;
import scatter;

struct Params
{
    uint symbol_count;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint4> link_symbol_identity_section;
StructuredBuffer<uint> link_symbol_order_in;
StructuredBuffer<uint> radix_bucket_base;
StructuredBuffer<uint> radix_block_bucket_prefix;
RWStructuredBuffer<uint> link_symbol_order_out;

static const uint WG_SIZE = 256u;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;
static const uint MAX_GROUPS_X = 65535u;
groupshared uint local_radix_keys[256];

uint symbol_key(uint symbol_i, uint key_step)
{
    uint4 symbol = link_symbol_identity_section[symbol_i];
    if (key_step == 0u)
        return symbol.w == 0u ? 1u : 0u;
    return radix_packed_u32x3_byte_key(
        symbol.x,
        symbol.y,
        symbol.z,
        key_step - 1u,
        0x444u);
}

public struct LinkSymbolScatterSource : IStableRadixScatterSource<uint>
{
    public static uint active_count()
    {
        return gParams.symbol_count;
    }

    public static uint inactive_value()
    {
        return 0u;
    }

    public static uint ordered_value(uint order_i)
    {
        return link_symbol_order_in[order_i];
    }

    public static uint radix_key(uint value, uint key_step)
    {
        return symbol_key(value, key_step);
    }
}

public struct LinkSymbolOrderSink : IScatterSink<uint>
{
    public static void store(uint dst, uint value)
    {
        link_symbol_order_out[dst] = value;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    stable_radix_scatter_block<
        uint,
        LinkSymbolScatterSource,
        LinkSymbolOrderSink,
        256>(
            linear_group_id_2d(gid, MAX_GROUPS_X),
            ltid.x,
            gParams.n_blocks,
            gParams.key_step,
            RADIX_BUCKETS,
            radix_bucket_base,
            radix_block_bucket_prefix,
            local_radix_keys);
}
