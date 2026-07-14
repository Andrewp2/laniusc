// Per-block u8 histogram for stable sorting of exact 96-bit symbol identities.

import gpu_index;
import radix;

struct Params
{
    uint symbol_count;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

// (identity word 0, identity word 1, identity word 2, section)
StructuredBuffer<uint4> link_symbol_identity_section;
StructuredBuffer<uint> link_symbol_order_in;
RWStructuredBuffer<uint> radix_block_histogram;

static const uint WG_SIZE = 256u;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;
static const uint MAX_GROUPS_X = 65535u;

uint symbol_key(uint symbol_i, uint key_step)
{
    uint4 symbol = link_symbol_identity_section[symbol_i];
    // Sort definition priority first so stable identity passes retain defined
    // rows before undefined references within each exact-identity group.
    if (key_step == 0u)
        return symbol.w == 0u ? 1u : 0u;
    return radix_packed_u32x3_byte_key(
        symbol.x,
        symbol.y,
        symbol.z,
        key_step - 1u,
        0x444u);
}

public struct LinkSymbolRadixSource : IRadixU8KeySource
{
    public static uint active_count()
    {
        return gParams.symbol_count;
    }

    public static uint ordered_row(uint order_i)
    {
        return link_symbol_order_in[order_i];
    }

    public static uint radix_key(uint row, uint key_step)
    {
        return symbol_key(row, key_step);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    radix_u8_histogram_block<LinkSymbolRadixSource>(
        linear_group_id_2d(gid, MAX_GROUPS_X),
        ltid.x,
        gParams.n_blocks,
        gParams.key_step,
        WG_SIZE,
        RADIX_BUCKETS,
        radix_block_histogram);
}
