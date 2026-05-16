// GPU imported-visibility key radix stable scatter.
//
// Scheduling contract:
// - Dispatch after type_check_modules_09c_sort_import_visible_keys.slang and
//   GPU scans over radix bucket counts for the same key_step.
// - This pass performs stable scatter over imported visibility row ids ordered
//   by (importing module id, name id).
// - It does not resolve paths, scan source bytes, use hashes, append with
//   atomics, perform CPU lookup, or apply same-source shortcuts.

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
StructuredBuffer<uint> radix_bucket_base;
StructuredBuffer<uint> radix_block_bucket_prefix;

RWStructuredBuffer<uint> import_visible_key_order_out;

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

uint local_same_key_rank(uint block_begin, uint lane, uint key)
{
    uint rank = 0u;
    [loop]
    for (uint j = 0u; j < lane; j += 1u)
    {
        uint order_j = block_begin + j;
        if (order_j < active_visible_count())
        {
            uint prev_visible_i = import_visible_key_order_in[order_j];
            if (visible_key_radix_key(prev_visible_i, gParams.key_step) == key)
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
    uint visible_count = active_visible_count();
    if (order_i >= visible_count)
        return;

    uint visible_i = import_visible_key_order_in[order_i];
    uint key = visible_key_radix_key(visible_i, gParams.key_step);
    uint rank = local_same_key_rank(block_idx * WG_SIZE, lane, key);
    uint block_prefix = radix_block_bucket_prefix[block_idx * RADIX_BUCKETS + key];
    uint dst = radix_bucket_base[key] + block_prefix + rank;

    if (dst < visible_count)
        import_visible_key_order_out[dst] = visible_i;
}
