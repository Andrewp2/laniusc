// GPU module-key radix stable scatter.
//
// Scheduling contract:
// - Dispatch after type_check_modules_03_sort_module_keys_histogram.slang and
//   GPU scans over radix bucket counts for the same key_step.
// - This pass performs the stable scatter for one radix key byte over fixed
//   module path key rows.
// - It does not resolve imports, validate duplicates, perform lookup, use
//   hashes, or ask the CPU to inspect module paths.

import gpu_index;
import radix;
import scatter;

struct Params
{
    uint module_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> module_key_segment_count;
StructuredBuffer<uint> module_key_segment_base;
StructuredBuffer<uint> module_key_segment_name_id;
StructuredBuffer<uint> module_key_order_in;
StructuredBuffer<uint> radix_bucket_base;
StructuredBuffer<uint> radix_block_bucket_prefix;

RWStructuredBuffer<uint> module_key_order_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint SORT_PATH_SEGMENTS = 8u;
static const uint MODULE_KEY_SEGMENT_ROW_WIDTH = SORT_PATH_SEGMENTS;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;

groupshared uint local_radix_keys[256];

uint linear_group_id(uint3 gid)
{
    return linear_group_id_2d(gid, MAX_GROUPS_X);
}

uint active_module_count()
{
    return min(module_count_out[0], gParams.module_capacity);
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

public struct ModuleKeyScatterSource : IStableRadixScatterSource<uint>
{
    public static uint active_count()
    {
        return active_module_count();
    }

    public static uint inactive_value()
    {
        return 0u;
    }

    public static uint ordered_value(uint order_i)
    {
        return module_key_order_in[order_i];
    }

    public static uint radix_key(uint value, uint key_step)
    {
        return module_key_radix_key(value, key_step);
    }
}

public struct ModuleKeyOrderOutSink : IScatterSink<uint>
{
    public static void store(uint dst, uint value)
    {
        module_key_order_out[dst] = value;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    uint lane = ltid.x;
    stable_radix_scatter_block<uint, ModuleKeyScatterSource, ModuleKeyOrderOutSink, 256>(
        block_idx,
        lane,
        gParams.n_blocks,
        gParams.key_step,
        RADIX_BUCKETS,
        radix_bucket_base,
        radix_block_bucket_prefix,
        local_radix_keys);
}
