// GPU module-key radix stable scatter.
//
// Scheduling contract:
// - Dispatch after type_check_modules_03_sort_module_keys_histogram.slang and
//   GPU scans over radix bucket counts for the same key_step.
// - This pass performs the stable scatter for one radix key byte over fixed
//   module path key rows.
// - It does not resolve imports, validate duplicates, perform lookup, use
//   hashes, or ask the CPU to inspect module paths.

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

uint local_same_key_rank(uint block_begin, uint lane, uint key)
{
    uint rank = 0u;
    [loop]
    for (uint j = 0u; j < lane; j += 1u)
    {
        uint order_j = block_begin + j;
        if (order_j < active_module_count())
        {
            uint prev_module_i = module_key_order_in[order_j];
            if (module_key_radix_key(prev_module_i, gParams.key_step) == key)
                rank += 1u;
        }
    }
    return rank;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    if (block_idx >= gParams.n_blocks)
        return;

    uint lane = ltid.x;
    uint order_i = block_idx * WG_SIZE + lane;
    uint module_count = active_module_count();
    if (order_i >= module_count)
        return;

    uint module_i = module_key_order_in[order_i];
    uint key = module_key_radix_key(module_i, gParams.key_step);
    uint rank = local_same_key_rank(block_idx * WG_SIZE, lane, key);
    uint block_prefix = radix_block_bucket_prefix[block_idx * RADIX_BUCKETS + key];
    uint dst = radix_bucket_base[key] + block_prefix + rank;

    if (dst < module_count)
        module_key_order_out[dst] = module_i;
}
