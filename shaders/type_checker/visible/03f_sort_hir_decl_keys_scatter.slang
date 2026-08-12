// GPU HIR declaration-key radix stable scatter.
//
// Scheduling contract:
// - Dispatch after type_check_visible_03e_sort_hir_decl_keys and GPU scans over
//   radix bucket counts for the same key_step.
// - Input records are already in declaration-token order. Stable byte passes
//   produce (owner function, interned name id, declaration token) order using
//   only owner and name as explicit radix fields.
// - This pass only reorders compact declaration rows. It does not inspect source
//   text, token spelling, helper names, or function body shapes.

import gpu_index;
import radix;
import scatter;
import stable_radix_scatter;

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
StructuredBuffer<uint> radix_order_in;
StructuredBuffer<uint> radix_bucket_base;
StructuredBuffer<uint> radix_block_bucket_prefix;

RWStructuredBuffer<uint> radix_order_out;

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

public struct HirVisibleDeclKeyScatterSource : IStableRadixScatterSource<uint>
{
    public static uint active_count()
    {
        return active_decl_count();
    }

    public static uint inactive_value()
    {
        return INVALID;
    }

    public static uint ordered_value(uint order_i)
    {
        return radix_order_in[order_i];
    }

    public static uint radix_key(uint value, uint key_step)
    {
        return decl_key_radix_key(value, key_step);
    }
}

public struct HirVisibleDeclKeyOrderOutSink : IScatterSink<uint>
{
    public static void store(uint dst, uint value)
    {
        radix_order_out[dst] = value;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    uint lane = ltid.x;
    stable_radix_scatter_block<HirVisibleDeclKeyScatterSource,
        HirVisibleDeclKeyOrderOutSink,
        256>(
        block_idx,
        lane,
        gParams.n_blocks,
        gParams.key_step,
        RADIX_BUCKETS,
        radix_bucket_base,
        radix_block_bucket_prefix);
}
