// GPU HIR declaration-key radix histogram.
//
// Scheduling contract:
// - For each capacity-derived key_step, the host schedules histogram, GPU
//   bucket-prefix scan, GPU bucket-base scan, and stable scatter.
// - key_step walks the fixed declaration key from least-significant to
//   most-significant: declaration token, name id, then owner function.
// - This pass only counts radix buckets for compact HIR declaration records.
//   It does not resolve names, scan source bytes, use token spelling, or apply
//   helper/body-shape shortcuts.

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

StructuredBuffer<uint> hir_visible_decl_count_out;
StructuredBuffer<uint> hir_visible_decl_owner_fn;
StructuredBuffer<uint> hir_visible_decl_name_id;
StructuredBuffer<uint> hir_visible_decl_token;
StructuredBuffer<uint> hir_visible_decl_key_order_in;

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
    return min(hir_visible_decl_count_out[0], gParams.decl_capacity);
}

uint decl_key_field(uint decl_i, uint field_i)
{
    if (decl_i >= active_decl_count())
        return 0u;

    if (field_i == 0u)
        return encode_nullable_id(hir_visible_decl_token[decl_i], INVALID);
    if (field_i == 1u)
        return encode_nullable_id(hir_visible_decl_name_id[decl_i], INVALID);
    return hir_visible_decl_owner_fn[decl_i];
}

uint decl_key_radix_key(uint decl_i, uint key_step)
{
    uint bytes_per_field = clamp(gParams.reserved, 1u, 4u);
    uint field_i = min(key_step / bytes_per_field, 2u);
    uint byte_i = key_step - field_i * bytes_per_field;
    uint value = decl_key_field(decl_i, field_i);
    return radix_byte_key(value, byte_i);
}

public struct HirVisibleDeclKeyRadixSource : IRadixU8KeySource
{
    public static uint active_count()
    {
        return active_decl_count();
    }

    public static uint ordered_row(uint order_i)
    {
        return hir_visible_decl_key_order_in[order_i];
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
    radix_u8_histogram_block<HirVisibleDeclKeyRadixSource>(
        block_idx,
        lane,
        gParams.n_blocks,
        gParams.key_step,
        WG_SIZE,
        RADIX_BUCKETS,
        radix_block_histogram);
}
