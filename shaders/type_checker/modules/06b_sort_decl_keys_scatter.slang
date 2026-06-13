// GPU declaration-key radix stable scatter.
//
// Scheduling contract:
// - Dispatch after type_check_modules_06_sort_decl_keys.slang and GPU scans
//   over radix bucket counts for the same key_step.
// - This pass performs the stable scatter for one radix key byte over
//   declaration keys ordered by (module_id, namespace, name_id).
// - It does not resolve imports, validate duplicates, perform lookup, scan
//   source bytes, use hashes, or apply same-source shortcuts.

import gpu_index;
import radix;
import scatter;

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
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;

groupshared uint local_radix_keys[256];

uint linear_group_id(uint3 gid)
{
    return linear_group_id_2d(gid, MAX_GROUPS_X);
}

uint active_decl_count()
{
    return min(decl_count_out[0], gParams.decl_capacity);
}

uint decl_key_field(uint decl_i, uint field_i)
{
    if (decl_i >= active_decl_count())
        return 0u;

    if (field_i == 0u)
        return encode_nullable_id(decl_name_id[decl_i], INVALID);
    if (field_i == 1u)
        return decl_namespace[decl_i];
    return encode_nullable_id(decl_module_id[decl_i], INVALID);
}

uint decl_key_radix_key(uint decl_i, uint key_step)
{
    uint field_i = radix_field_index(key_step, 2u);
    uint value = decl_key_field(decl_i, field_i);
    return radix_byte_key(value, key_step);
}

public struct DeclKeyScatterSource : IStableRadixScatterSource<uint>
{
    public static uint active_count()
    {
        return active_decl_count();
    }

    public static uint inactive_value()
    {
        return 0u;
    }

    public static uint ordered_value(uint order_i)
    {
        return decl_key_order_in[order_i];
    }

    public static uint radix_key(uint value, uint key_step)
    {
        return decl_key_radix_key(value, key_step);
    }
}

public struct DeclKeyOrderOutSink : IScatterSink<uint>
{
    public static void store(uint dst, uint value)
    {
        decl_key_order_out[dst] = value;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    uint lane = ltid.x;
    stable_radix_scatter_block<uint, DeclKeyScatterSource, DeclKeyOrderOutSink, 256>(
        block_idx,
        lane,
        gParams.n_blocks,
        gParams.key_step,
        RADIX_BUCKETS,
        radix_bucket_base,
        radix_block_bucket_prefix,
        local_radix_keys);
}
