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

import gpu_index;
import radix;

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
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;

uint linear_group_id(uint3 gid)
{
    return linear_group_id_2d(gid, MAX_GROUPS_X);
}

uint active_visible_count()
{
    return min(import_visible_count_out[0], gParams.capacity);
}

uint visible_key_field(uint visible_i, uint field_i)
{
    if (visible_i >= active_visible_count())
        return 0u;
    if (field_i == 0u)
        return encode_nullable_id(import_visible_name_id[visible_i], INVALID);
    return encode_nullable_id(import_visible_module_id[visible_i], INVALID);
}

uint visible_key_radix_key(uint visible_i, uint key_step)
{
    uint field_i = radix_field_index(key_step, 1u);
    uint value = visible_key_field(visible_i, field_i);
    return radix_byte_key(value, key_step);
}

public struct VisibleKeyRadixSource : IRadixU8KeySource
{
    public static uint active_count()
    {
        return active_visible_count();
    }

    public static uint ordered_row(uint order_i)
    {
        return import_visible_key_order_in[order_i];
    }

    public static uint radix_key(uint row, uint key_step)
    {
        return visible_key_radix_key(row, key_step);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    uint lane = ltid.x;
    radix_u8_histogram_block<VisibleKeyRadixSource>(
        block_idx,
        lane,
        gParams.n_blocks,
        gParams.key_step,
        WG_SIZE,
        RADIX_BUCKETS,
        radix_block_histogram);
}
