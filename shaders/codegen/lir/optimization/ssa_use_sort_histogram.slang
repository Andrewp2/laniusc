// Capacity-derived stable ordering for compact SSA uses by dense value ID.

import gpu_index;
import radix;

struct Params
{
    uint item_capacity;
    uint key_bits;
    uint max_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_ssa_use_total;
StructuredBuffer<uint> opt_ir_ssa_use_values;
RWStructuredBuffer<uint> radix_order_in;
RWStructuredBuffer<uint> radix_block_histogram;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_use_count()
{
    return min(opt_ir_ssa_use_total[0u], gParams.item_capacity);
}

public struct SsaUseRadixSource : IRadixU8KeySource
{
    public static uint active_count()
    {
        return active_use_count();
    }

    public static uint ordered_row(uint order_i)
    {
        if (gParams.key_step == 0u) radix_order_in[order_i] = order_i;
        return radix_order_in[order_i];
    }

    public static uint radix_key(uint row, uint key_step)
    {
        return row < active_use_count()
            ? radix_byte_key(opt_ir_ssa_use_values[row], key_step) : 0u;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    radix_u8_histogram_block<SsaUseRadixSource>(
        linear_group_id_2d(gid, MAX_GROUPS_X),
        ltid.x,
        gParams.max_blocks,
        gParams.key_step,
        WG_SIZE,
        RADIX_U8_BUCKETS,
        radix_block_histogram);
}
