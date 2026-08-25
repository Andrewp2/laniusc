// Capacity-derived stable ordering for sparse `(declaration, block)` demands.

import codegen.optimization_ir;
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
StructuredBuffer<uint> opt_ir_ssa_demand_total;
StructuredBuffer<OptIrSsaDemand> opt_ir_ssa_demands;
RWStructuredBuffer<uint> radix_order_in;
RWStructuredBuffer<uint> radix_block_histogram;

static const uint WG_SIZE = 256u;
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

public struct SsaDemandRadixSource : IRadixU8KeySource
{
    public static uint active_count()
    {
        return active_demand_count();
    }

    public static uint ordered_row(uint order_i)
    {
        if (gParams.key_step == 0u) radix_order_in[order_i] = order_i;
        return radix_order_in[order_i];
    }

    public static uint radix_key(uint row, uint key_step)
    {
        return demand_key(row, key_step);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    radix_u8_histogram_block<SsaDemandRadixSource>(
        linear_group_id(gid),
        ltid.x,
        gParams.max_blocks,
        gParams.key_step,
        WG_SIZE,
        RADIX_U8_BUCKETS,
        radix_block_histogram);
}
