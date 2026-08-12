// GPU HIR declaration-key radix histogram.
//
// Scheduling contract:
// - For each capacity-derived key_step, the host schedules histogram, GPU
//   bucket-prefix scan, GPU bucket-base scan, and stable scatter.
// - Input records are already in declaration-token order. Stable byte passes
//   walk name id and then owner function, preserving token order within equal
//   owner/name groups.
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
RWStructuredBuffer<uint> radix_order_in;

RWStructuredBuffer<uint> radix_block_histogram;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = RADIX_U8_BUCKETS;

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

    return field_i == 0u
        ? encode_nullable_id(hir_visible_decl_name_id[decl_i], INVALID)
        : hir_visible_decl_owner_fn[decl_i];
}

uint decl_key_radix_key(uint decl_i, uint key_step)
{
    return radix_packed_u32x2_bit_key(
        decl_key_field(decl_i, 0u),
        decl_key_field(decl_i, 1u),
        gParams.reserved,
        key_step);
}

public struct HirVisibleDeclKeyRadixSource : IRadixU8KeySource
{
    public static uint active_count()
    {
        return active_decl_count();
    }

    public static uint ordered_row(uint order_i)
    {
        // Visible declaration rows are compacted in token order. Digit zero
        // establishes that identity order while building its histogram.
        if (gParams.key_step == 0u)
            radix_order_in[order_i] = order_i;
        return radix_order_in[order_i];
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
