// Stable scatter for sparse `(declaration, block)` demand ordering.

import codegen.optimization_ir;
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
StructuredBuffer<uint> opt_ir_ssa_demand_total;
StructuredBuffer<OptIrSsaDemand> opt_ir_ssa_demands;
StructuredBuffer<uint> radix_order_in;
StructuredBuffer<uint> radix_bucket_base;
StructuredBuffer<uint> radix_block_bucket_prefix;
RWStructuredBuffer<uint> radix_order_out;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;

uint linear_group_id(uint3 gid)
{
    return linear_group_id_2d(gid, MAX_GROUPS_X);
}

uint active_demand_count()
{
    return min(opt_ir_ssa_demand_total[0u], gParams.item_capacity);
}

uint demand_key(uint row, uint key_step)
{
    if (row >= active_demand_count()) return 0u;
    uint block_bits = gParams.key_bits & 0xffffu;
    uint declaration_bits = gParams.key_bits >> 16u;
    OptIrSsaDemand demand = opt_ir_ssa_demands[row];
    return radix_packed_u32x2_variable_bit_key(
        demand.block,
        demand.declaration,
        block_bits,
        declaration_bits,
        key_step);
}

public struct SsaDemandScatterSource : IStableRadixScatterSource<uint>
{
    public static uint active_count()
    {
        return active_demand_count();
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
        return demand_key(row, key_step);
    }
}

public struct SsaDemandOrderSink : IScatterSink<uint>
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
        SsaDemandScatterSource,
        SsaDemandOrderSink,
        256>(
            linear_group_id(gid),
            ltid.x,
            gParams.max_blocks,
            gParams.key_step,
            RADIX_U8_BUCKETS,
            radix_bucket_base,
            radix_block_bucket_prefix);
}
