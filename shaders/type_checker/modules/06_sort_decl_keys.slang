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

import gpu_index;
import radix;

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
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;

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

public struct DeclKeyRadixSource : IRadixU8KeySource
{
    public static uint active_count()
    {
        return active_decl_count();
    }

    public static uint ordered_row(uint order_i)
    {
        return decl_key_order_in[order_i];
    }

    public static uint radix_key(uint row, uint key_step)
    {
        return decl_key_radix_key(row, key_step);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    uint lane = ltid.x;
    radix_u8_histogram_block<DeclKeyRadixSource>(
        block_idx,
        lane,
        gParams.n_blocks,
        gParams.key_step,
        WG_SIZE,
        RADIX_BUCKETS,
        radix_block_histogram);
}
