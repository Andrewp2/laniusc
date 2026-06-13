// GPU module-key radix histogram.
//
// Scheduling contract:
// - Dispatch after type_check_modules_02e_build_module_keys.slang.
// - For key_step 0..255, the host schedules histogram, GPU bucket-prefix scan,
//   GPU bucket-base scan, and stable scatter.
// - key_step walks the bounded fixed-width path keys from least-significant to
//   most-significant: segment 7 low byte through segment 0 high byte.
// - Missing segments are sentinel 0; real segment ids are encoded as
//   name_id + 1. This keeps prefix paths ordered before longer paths.
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
StructuredBuffer<uint> module_key_segment_count;
StructuredBuffer<uint> module_key_segment_base;
StructuredBuffer<uint> module_key_segment_name_id;
StructuredBuffer<uint> module_key_order_in;

RWStructuredBuffer<uint> radix_block_histogram;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint SORT_PATH_SEGMENTS = 8u;
static const uint MODULE_KEY_SEGMENT_ROW_WIDTH = SORT_PATH_SEGMENTS;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;

uint linear_group_id(uint3 gid)
{
    return linear_group_id_2d(gid, MAX_GROUPS_X);
}

uint active_module_count()
{
    return min(module_table_count_out[0], gParams.module_capacity);
}

uint module_key_segment_value(uint module_i, uint segment_i)
{
    if (module_i >= active_module_count())
        return 0u;
    if (segment_i >= min(module_key_segment_count[module_i], MODULE_KEY_SEGMENT_ROW_WIDTH))
        return 0u;

    uint segment_base = module_key_segment_base[module_i];
    uint name_id = module_key_segment_name_id[segment_base + segment_i];
    return encode_nullable_id(name_id, INVALID);
}

uint module_key_radix_key(uint module_i, uint key_step)
{
    uint segment_i = radix_reverse_field_index(key_step, SORT_PATH_SEGMENTS);
    uint value = module_key_segment_value(module_i, segment_i);
    return radix_byte_key(value, key_step);
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
