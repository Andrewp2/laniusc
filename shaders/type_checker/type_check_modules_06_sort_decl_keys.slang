// GPU declaration-key radix histogram.
//
// Scheduling contract:
// - Dispatch after type_check_modules_06a_seed_decl_key_order.slang or an
//   equivalent GPU declaration-order seed has initialized decl_key_order_in.
// - For key_step 0..11, the host schedules histogram, GPU bucket-prefix scan,
//   GPU bucket-base scan, and stable scatter.
// - key_step walks the fixed declaration key from least-significant to
//   most-significant: name_id, namespace, then module_id.
// - Invalid module/name ids are encoded as sentinel 0; real ids are encoded as
//   id + 1. This keeps invalid keys fail-closed and sortable.
// - This pass only counts radix buckets. It does not resolve imports, validate
//   duplicates, perform lookup, scan source bytes, use hashes, or apply
//   same-source shortcuts.

struct Params
{
    uint decl_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_name_id;
StructuredBuffer<uint> decl_key_order_in;

RWStructuredBuffer<uint> radix_block_histogram;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = 257u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_decl_count()
{
    return min(decl_count_out[0], gParams.decl_capacity);
}

uint encoded_id(uint value)
{
    return value == INVALID ? 0u : value + 1u;
}

uint decl_key_field(uint decl_i, uint field_i)
{
    if (decl_i >= active_decl_count())
        return 0u;

    if (field_i == 0u)
        return encoded_id(decl_name_id[decl_i]);
    if (field_i == 1u)
        return decl_namespace[decl_i];
    return encoded_id(decl_module_id[decl_i]);
}

uint decl_key_radix_key(uint decl_i, uint key_step)
{
    uint field_i = min(key_step / 4u, 2u);
    uint byte_i = key_step & 3u;
    uint value = decl_key_field(decl_i, field_i);
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
    if (order_i >= active_decl_count())
        return;

    uint decl_i = decl_key_order_in[order_i];
    uint key = decl_key_radix_key(decl_i, gParams.key_step);
    uint old_count;
    InterlockedAdd(radix_block_histogram[block_base + key], 1u, old_count);
}
