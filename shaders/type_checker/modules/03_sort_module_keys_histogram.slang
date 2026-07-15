// GPU module-key radix histogram.
//
// Scheduling contract:
// - Dispatch after type_check_modules_02e_build_module_keys.slang.
// - For key_step 0..255, the host schedules histogram, GPU bucket-prefix scan,
//   GPU bucket-base scan, and stable scatter.
// - key_step walks the four bytes of an exact canonical path-prefix id.
// - This pass only counts radix buckets. It does not resolve imports,
//   validate duplicates, perform lookup, use hashes, or ask the CPU to inspect
//   module paths.

import gpu_index;
import radix;

struct Params
{
    uint module_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> module_table_count_out;
StructuredBuffer<uint> module_key_canonical_id;
StructuredBuffer<uint> module_key_order_in;

RWStructuredBuffer<uint> radix_block_histogram;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;

uint linear_group_id(uint3 gid)
{
    return linear_group_id_2d(gid, MAX_GROUPS_X);
}

uint active_module_count()
{
    return min(module_table_count_out[0], gParams.module_capacity);
}

uint module_key_radix_key(uint module_i, uint key_step)
{
    return radix_byte_key(module_key_canonical_id[module_i], key_step);
}

public struct ModuleKeyRadixSource : IRadixU8KeySource
{
    public static uint active_count()
    {
        return active_module_count();
    }

    public static uint ordered_row(uint order_i)
    {
        return module_key_order_in[order_i];
    }

    public static uint radix_key(uint row, uint key_step)
    {
        return module_key_radix_key(row, key_step);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    uint lane = ltid.x;
    radix_u8_histogram_block<ModuleKeyRadixSource>(
        block_idx,
        lane,
        gParams.n_blocks,
        gParams.key_step,
        WG_SIZE,
        RADIX_BUCKETS,
        radix_block_histogram);
}
