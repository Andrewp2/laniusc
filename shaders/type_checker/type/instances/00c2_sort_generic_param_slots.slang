// GPU generic-parameter slot-order radix histogram.
//
// Rows are sorted by (owner declaration, parameter kind, HIR node). This order
// is used only for declaration-order slot IDs; name lookup keeps its separate
// owner/name/HIR-node order.

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

StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_token;
StructuredBuffer<uint> generic_param_node;
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> generic_param_slot_order_in;

RWStructuredBuffer<uint> radix_block_histogram;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;

uint linear_group_id(uint3 gid)
{
    return linear_group_id_2d(gid, MAX_GROUPS_X);
}

uint active_generic_param_count()
{
    return min(generic_param_count_out[0u], gParams.decl_capacity);
}

uint generic_param_slot_field(uint row, uint field_i)
{
    if (row >= active_generic_param_count())
        return 0u;

    if (field_i == 0u)
        return encode_nullable_id(generic_param_node[row], INVALID);
    if (field_i == 1u)
        return generic_param_kind[row];
    return encode_nullable_id(generic_param_owner_token[row], INVALID);
}

uint generic_param_radix_key(uint row, uint key_step)
{
    uint bytes_per_field = clamp(gParams.reserved, 1u, 4u);
    uint field_i = min(key_step / bytes_per_field, 2u);
    uint byte_i = key_step - field_i * bytes_per_field;
    return radix_byte_key(generic_param_slot_field(row, field_i), byte_i);
}

public struct GenericParamSlotRadixSource : IRadixU8KeySource
{
    public static uint active_count()
    {
        return active_generic_param_count();
    }

    public static uint ordered_row(uint order_i)
    {
        return generic_param_slot_order_in[order_i];
    }

    public static uint radix_key(uint row, uint key_step)
    {
        return generic_param_radix_key(row, key_step);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    radix_u8_histogram_block<GenericParamSlotRadixSource>(
        linear_group_id(gid),
        ltid.x,
        gParams.n_blocks,
        gParams.key_step,
        WG_SIZE,
        RADIX_BUCKETS,
        radix_block_histogram);
}
