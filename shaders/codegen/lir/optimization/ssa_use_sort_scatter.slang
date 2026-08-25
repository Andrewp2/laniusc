// Stable scatter for compact SSA uses ordered by dense value ID.

import gpu_index;
import radix;
import scatter;
import stable_radix_scatter;

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
StructuredBuffer<uint> radix_order_in;
StructuredBuffer<uint> radix_bucket_base;
StructuredBuffer<uint> radix_block_bucket_prefix;
RWStructuredBuffer<uint> radix_order_out;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;

uint active_use_count()
{
    return min(opt_ir_ssa_use_total[0u], gParams.item_capacity);
}

public struct SsaUseScatterSource : IStableRadixScatterSource<uint>
{
    public static uint active_count()
    {
        return active_use_count();
    }

    public static uint inactive_value()
    {
        return INVALID;
    }

    public static uint ordered_value(uint order_i)
    {
        return radix_order_in[order_i];
    }

    public static uint radix_key(uint row, uint key_step)
    {
        return row < active_use_count()
            ? radix_byte_key(opt_ir_ssa_use_values[row], key_step) : 0u;
    }
}

public struct SsaUseOrderSink : IScatterSink<uint>
{
    public static void store(uint dst, uint value)
    {
        radix_order_out[dst] = value;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    stable_radix_scatter_block<
        SsaUseScatterSource,
        SsaUseOrderSink,
        256>(
            linear_group_id_2d(gid, MAX_GROUPS_X),
            ltid.x,
            gParams.max_blocks,
            gParams.key_step,
            RADIX_U8_BUCKETS,
            radix_bucket_base,
            radix_block_bucket_prefix);
}
