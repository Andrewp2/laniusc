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

RWStructuredBuffer<uint> radix_block_histogram;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_PATH_SEGMENTS = 64u;
static const uint SORT_PATH_SEGMENTS = 8u;
static const uint RADIX_BUCKETS = 257u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_module_count()
{
    return min(module_count_out[0], gParams.module_capacity);
}

uint module_key_segment_value(uint module_i, uint segment_i)
{
    if (module_i >= active_module_count())
        return 0u;
    if (segment_i >= min(module_key_segment_count[module_i], MAX_PATH_SEGMENTS))
        return 0u;

    uint segment_base = module_key_segment_base[module_i];
    uint name_id = module_key_segment_name_id[segment_base + segment_i];
    return name_id == INVALID ? 0u : name_id + 1u;
}

uint module_key_radix_key(uint module_i, uint key_step)
{
    uint segment_i = SORT_PATH_SEGMENTS - 1u - min(key_step / 4u, SORT_PATH_SEGMENTS - 1u);
    uint byte_i = key_step & 3u;
    uint value = module_key_segment_value(module_i, segment_i);
    return (value >> (byte_i * 8u)) & 0xffu;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    if (block_idx >= gParams.n_blocks)
        return;

    uint lane = ltid.x;
    uint block_base = block_idx * RADIX_BUCKETS;
    for (uint bucket = lane; bucket < RADIX_BUCKETS; bucket += WG_SIZE)
    {
        radix_block_histogram[block_base + bucket] = 0u;
    }
    DeviceMemoryBarrierWithGroupSync();

    uint order_i = block_idx * WG_SIZE + lane;
    if (order_i >= active_module_count())
        return;

    uint module_i = module_key_order_in[order_i];
    uint key = module_key_radix_key(module_i, gParams.key_step);
    uint old_count;
    InterlockedAdd(radix_block_histogram[block_base + key], 1u, old_count);
}
