// GPU imported-visibility sorted key validation.
//
// Scheduling contract:
// - Dispatch after final sorted imported-visibility key tables have been built.
// - Equal keys with different declarations are ambiguous imported declarations
//   for the same importing module and namespace. Every row in that equal-key
//   run is marked ambiguous so lower-bound lookup cannot accept the first row.
//   Equal keys that name the same declaration are harmless re-imports.
// - It does not resolve paths, scan source bytes, use hashes, perform CPU
//   lookup, or apply same-source shortcuts.

import fixed_key;

struct Params
{
    uint capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> import_visible_type_count_out;
StructuredBuffer<uint> import_visible_type_key_module_id;
StructuredBuffer<uint> import_visible_type_key_name_id;
StructuredBuffer<uint> import_visible_type_key_to_decl_id;
StructuredBuffer<uint> import_visible_value_count_out;
StructuredBuffer<uint> import_visible_value_key_module_id;
StructuredBuffer<uint> import_visible_value_key_name_id;
StructuredBuffer<uint> import_visible_value_key_to_decl_id;

RWStructuredBuffer<uint> import_visible_type_status;
RWStructuredBuffer<uint> import_visible_type_duplicate_of;
RWStructuredBuffer<uint> import_visible_value_status;
RWStructuredBuffer<uint> import_visible_value_duplicate_of;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint IMPORT_VISIBLE_STATUS_OK = 0u;
static const uint IMPORT_VISIBLE_STATUS_AMBIGUOUS = 1u;
static const uint IMPORT_VISIBLE_STATUS_INVALID_KEY = 2u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint visible_capacity()
{
    return gParams.reserved == 0u ? gParams.capacity : gParams.reserved;
}

uint active_type_count()
{
    return min(import_visible_type_count_out[0], visible_capacity());
}

uint active_value_count()
{
    return min(import_visible_value_count_out[0], visible_capacity());
}

bool valid_type_key(uint i)
{
    return import_visible_type_key_module_id[i] != INVALID &&
           import_visible_type_key_name_id[i] != INVALID &&
           import_visible_type_key_to_decl_id[i] != INVALID;
}

bool valid_value_key(uint i)
{
    return import_visible_value_key_module_id[i] != INVALID &&
           import_visible_value_key_name_id[i] != INVALID &&
           import_visible_value_key_to_decl_id[i] != INVALID;
}

public struct ImportVisibleTypeFixedKey : IFixedU32RowKey<uint>
{
    public static uint row_lane(uint i, uint lane)
    {
        uint value = lane == 0u
            ? import_visible_type_key_module_id[i]
            : import_visible_type_key_name_id[i];
        return fixed_key_encode_nullable_u32(value, INVALID);
    }

    public static uint key_lane(uint i, uint lane)
    {
        return row_lane(i, lane);
    }
}

public struct ImportVisibleValueFixedKey : IFixedU32RowKey<uint>
{
    public static uint row_lane(uint i, uint lane)
    {
        uint value = lane == 0u
            ? import_visible_value_key_module_id[i]
            : import_visible_value_key_name_id[i];
        return fixed_key_encode_nullable_u32(value, INVALID);
    }

    public static uint key_lane(uint i, uint lane)
    {
        return row_lane(i, lane);
    }
}

bool same_type_key(uint left_i, uint right_i)
{
    return valid_type_key(left_i) && valid_type_key(right_i) &&
           fixed_u32_row_key_equal<uint, ImportVisibleTypeFixedKey>(
               left_i,
               right_i,
               2u);
}

bool same_value_key(uint left_i, uint right_i)
{
    return valid_value_key(left_i) && valid_value_key(right_i) &&
           fixed_u32_row_key_equal<uint, ImportVisibleValueFixedKey>(
               left_i,
               right_i,
               2u);
}

bool type_key_has_distinct_decl_in_run(uint i, uint count, out uint duplicate_of)
{
    duplicate_of = INVALID;
    uint decl_i = import_visible_type_key_to_decl_id[i];

    [loop]
    for (uint cursor = i; cursor > 0u;)
    {
        cursor -= 1u;
        if (!same_type_key(cursor, i))
            break;
        if (import_visible_type_key_to_decl_id[cursor] != decl_i)
        {
            duplicate_of = cursor;
            return true;
        }
    }

    [loop]
    for (uint cursor = i + 1u; cursor < count; cursor += 1u)
    {
        if (!same_type_key(i, cursor))
            break;
        if (import_visible_type_key_to_decl_id[cursor] != decl_i)
        {
            duplicate_of = cursor;
            return true;
        }
    }

    return false;
}

bool value_key_has_distinct_decl_in_run(uint i, uint count, out uint duplicate_of)
{
    duplicate_of = INVALID;
    uint decl_i = import_visible_value_key_to_decl_id[i];

    [loop]
    for (uint cursor = i; cursor > 0u;)
    {
        cursor -= 1u;
        if (!same_value_key(cursor, i))
            break;
        if (import_visible_value_key_to_decl_id[cursor] != decl_i)
        {
            duplicate_of = cursor;
            return true;
        }
    }

    [loop]
    for (uint cursor = i + 1u; cursor < count; cursor += 1u)
    {
        if (!same_value_key(i, cursor))
            break;
        if (import_visible_value_key_to_decl_id[cursor] != decl_i)
        {
            duplicate_of = cursor;
            return true;
        }
    }

    return false;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= visible_capacity())
        return;

    if (i < active_type_count())
    {
        import_visible_type_status[i] = IMPORT_VISIBLE_STATUS_OK;
        import_visible_type_duplicate_of[i] = INVALID;
        if (!valid_type_key(i))
        {
            import_visible_type_status[i] = IMPORT_VISIBLE_STATUS_INVALID_KEY;
        }
        else
        {
            uint duplicate_of;
            if (type_key_has_distinct_decl_in_run(i, active_type_count(), duplicate_of))
            {
                import_visible_type_status[i] = IMPORT_VISIBLE_STATUS_AMBIGUOUS;
                import_visible_type_duplicate_of[i] = duplicate_of;
            }
        }
    }

    if (i < active_value_count())
    {
        import_visible_value_status[i] = IMPORT_VISIBLE_STATUS_OK;
        import_visible_value_duplicate_of[i] = INVALID;
        if (!valid_value_key(i))
        {
            import_visible_value_status[i] = IMPORT_VISIBLE_STATUS_INVALID_KEY;
        }
        else
        {
            uint duplicate_of;
            if (value_key_has_distinct_decl_in_run(i, active_value_count(), duplicate_of))
            {
                import_visible_value_status[i] = IMPORT_VISIBLE_STATUS_AMBIGUOUS;
                import_visible_value_duplicate_of[i] = duplicate_of;
            }
        }
    }
}
