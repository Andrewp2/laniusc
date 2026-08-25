// Stable scatter for the compact OptIR access relation.

import codegen.optimization_ir;
import gpu_index;
import radix;
import scatter;
import stable_radix_scatter;

struct Params
{
    uint item_capacity;
    uint subject_bits;
    uint max_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> opt_ir_access_total;
StructuredBuffer<OptIrAccessCore> opt_ir_accesses;
StructuredBuffer<uint> opt_ir_access_kinds;
StructuredBuffer<uint> radix_order_in;
StructuredBuffer<uint> radix_bucket_base;
StructuredBuffer<uint> radix_block_bucket_prefix;
RWStructuredBuffer<uint> radix_order_out;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = RADIX_U8_BUCKETS;

uint linear_group_id(uint3 gid)
{
    return linear_group_id_2d(gid, MAX_GROUPS_X);
}

uint active_access_count()
{
    return min(opt_ir_access_total[0u], gParams.item_capacity);
}

uint access_radix_key(uint access_id, uint key_step)
{
    if (access_id >= active_access_count()) return 0u;
    return radix_packed_u32x2_variable_bit_key(
        opt_ir_accesses[access_id].subject,
        opt_ir_access_domain(opt_ir_access_kinds[access_id]),
        gParams.subject_bits,
        1u,
        key_step);
}

public struct OptIrAccessScatterSource : IStableRadixScatterSource<uint>
{
    public static uint active_count()
    {
        return active_access_count();
    }

    public static uint inactive_value()
    {
        return INVALID;
    }

    public static uint ordered_value(uint order_i)
    {
        return radix_order_in[order_i];
    }

    public static uint radix_key(uint value, uint key_step)
    {
        return access_radix_key(value, key_step);
    }
}

public struct OptIrAccessOrderSink : IScatterSink<uint>
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
        OptIrAccessScatterSource,
        OptIrAccessOrderSink,
        256>(
            linear_group_id(gid),
            ltid.x,
            gParams.max_blocks,
            gParams.key_step,
            RADIX_BUCKETS,
            radix_bucket_base,
            radix_block_bucket_prefix);
}
