// GPU imported-visibility key radix histogram.
//
// Scheduling contract:
// - Dispatch after imported visibility rows have been scattered and order rows
//   have been seeded.
// - For key_step 0..7, the host schedules histogram, GPU bucket-prefix scan,
//   GPU bucket-base scan, and stable scatter.
// - key_step walks the fixed imported-visibility key from least-significant to
//   most-significant: name_id, then importing module id.
// - This pass only counts radix buckets. It does not resolve paths, scan source
//   bytes, use hashes, append with atomics, perform CPU lookup, or apply
//   same-source shortcuts.

struct Params
{
    uint capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> import_visible_count_out;
StructuredBuffer<uint> import_visible_module_id;
StructuredBuffer<uint> import_visible_name_id;
StructuredBuffer<uint> import_visible_key_order_in;

RWStructuredBuffer<uint> radix_block_histogram;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = 257u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_visible_count()
{
    return min(import_visible_count_out[0], gParams.capacity);
}

uint encoded_id(uint value)
{
    return value == INVALID ? 0u : value + 1u;
}

uint visible_key_field(uint visible_i, uint field_i)
{
    if (visible_i >= active_visible_count())
        return 0u;
    if (field_i == 0u)
        return encoded_id(import_visible_name_id[visible_i]);
    return encoded_id(import_visible_module_id[visible_i]);
}

uint visible_key_radix_key(uint visible_i, uint key_step)
{
    uint field_i = min(key_step / 4u, 1u);
    uint byte_i = key_step & 3u;
    uint value = visible_key_field(visible_i, field_i);
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
    if (order_i >= active_visible_count())
        return;

    uint visible_i = import_visible_key_order_in[order_i];
    uint key = visible_key_radix_key(visible_i, gParams.key_step);
    uint old_count;
    InterlockedAdd(radix_block_histogram[block_base + key], 1u, old_count);
}
