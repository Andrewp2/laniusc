// Stable ordering for the compact OptIR access relation.
//
// Metadata rows are materialized before scheduled instruction rows. Sorting
// only `(domain, subject)` therefore preserves control position as the stable
// tie-breaker without spending radix passes on a redundant position field.

import codegen.optimization_ir;
import gpu_index;
import radix;

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
RWStructuredBuffer<uint> radix_order_in;
RWStructuredBuffer<uint> radix_block_histogram;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
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

public struct OptIrAccessRadixSource : IRadixU8KeySource
{
    public static uint active_count()
    {
        return active_access_count();
    }

    public static uint ordered_row(uint order_i)
    {
        if (gParams.key_step == 0u)
            radix_order_in[order_i] = order_i;
        return radix_order_in[order_i];
    }

    public static uint radix_key(uint row, uint key_step)
    {
        return access_radix_key(row, key_step);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    radix_u8_histogram_block<OptIrAccessRadixSource>(
        linear_group_id(gid),
        ltid.x,
        gParams.max_blocks,
        gParams.key_step,
        WG_SIZE,
        RADIX_BUCKETS,
        radix_block_histogram);
}
