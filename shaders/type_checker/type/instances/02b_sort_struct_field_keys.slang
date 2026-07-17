// GPU struct-field key radix histogram.
//
// Rows are compact field rows sorted by (dense owner, interned field name,
// field row). Non-declaration rows encode to sentinel 0. Consumers range-query the sorted
// table instead of scanning a struct declaration's field slice.

import gpu_index;
import radix;

struct Params
{
    uint hir_node_capacity;
    uint token_capacity;
    uint n_blocks;
    uint key_step;
    uint radix_bytes;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirField { uint owner; uint name_token; uint value; uint ordinal; };
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> struct_field_key_order_in;

RWStructuredBuffer<uint> radix_block_histogram;

static const uint INVALID = 0xffffffffu;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;

uint linear_group_id(uint3 gid)
{
    return linear_group_id_2d(gid, MAX_GROUPS_X);
}

uint active_struct_field_order_count()
{
    return min(compact_field_count[0u], gParams.hir_node_capacity);
}

uint active_compact_hir_count()
{
    return min(compact_hir_count[0u], gParams.token_capacity);
}

bool valid_field_key_row(uint row)
{
    if (row == INVALID || row >= active_struct_field_order_count())
        return false;
    HirField field = compact_fields[row];
    if (field.owner >= active_compact_hir_count() ||
        compact_hir_core[field.owner].kind != HIR_STRUCT_ITEM)
        return false;
    uint token = field.name_token;
    return token != INVALID && token < gParams.token_capacity &&
           name_id_by_token[token] != INVALID;
}

uint struct_field_key_field(uint row, uint field_i)
{
    if (!valid_field_key_row(row))
        return 0u;
    HirField field = compact_fields[row];
    if (field_i == 0u)
        return encode_nullable_id(row, INVALID);
    if (field_i == 1u)
        return encode_nullable_id(name_id_by_token[field.name_token], INVALID);
    return encode_nullable_id(field.owner, INVALID);
}

uint struct_field_radix_key(uint node, uint key_step)
{
    uint bytes_per_field = clamp(gParams.radix_bytes, 1u, 4u);
    uint field_i = min(key_step / bytes_per_field, 2u);
    uint byte_i = key_step - field_i * bytes_per_field;
    return radix_byte_key(struct_field_key_field(node, field_i), byte_i);
}

public struct StructFieldKeyRadixSource : IRadixU8KeySource
{
    public static uint active_count()
    {
        return active_struct_field_order_count();
    }

    public static uint ordered_row(uint order_i)
    {
        return struct_field_key_order_in[order_i];
    }

    public static uint radix_key(uint row, uint key_step)
    {
        return struct_field_radix_key(row, key_step);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    radix_u8_histogram_block<StructFieldKeyRadixSource>(
        linear_group_id(gid),
        ltid.x,
        gParams.n_blocks,
        gParams.key_step,
        WG_SIZE,
        RADIX_BUCKETS,
        radix_block_histogram);
}
