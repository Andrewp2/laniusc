// GPU declaration-key radix stable scatter.
//
// Scheduling contract:
// - Dispatch after type_check_modules_06_sort_decl_keys.slang and GPU scans
//   over radix bucket counts for the same key_step.
// - This pass performs the stable scatter for one radix key byte over
//   declaration keys ordered by (module_id, namespace, name_id).
// - It does not resolve imports, validate duplicates, perform lookup, scan
//   source bytes, use hashes, or apply same-source shortcuts.

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
StructuredBuffer<uint> radix_bucket_base;
StructuredBuffer<uint> radix_block_bucket_prefix;

RWStructuredBuffer<uint> decl_key_order_out;

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

uint local_same_key_rank(uint block_begin, uint lane, uint key)
{
    uint rank = 0u;
    [loop]
    for (uint j = 0u; j < lane; j += 1u)
    {
        uint order_j = block_begin + j;
        if (order_j < active_decl_count())
        {
            uint prev_decl_i = decl_key_order_in[order_j];
            if (decl_key_radix_key(prev_decl_i, gParams.key_step) == key)
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
    uint decl_count = active_decl_count();
    if (order_i >= decl_count)
        return;

    uint decl_i = decl_key_order_in[order_i];
    uint key = decl_key_radix_key(decl_i, gParams.key_step);
    uint rank = local_same_key_rank(block_idx * WG_SIZE, lane, key);
    uint block_prefix = radix_block_bucket_prefix[block_idx * RADIX_BUCKETS + key];
    uint dst = radix_bucket_base[key] + block_prefix + rank;

    if (dst < decl_count)
        decl_key_order_out[dst] = decl_i;
}
