// GPU imported-visibility sorted key validation.
//
// Scheduling contract:
// - Dispatch after final sorted imported-visibility key tables have been built.
// - Dispatch twice. key_step == 0 initializes row status; key_step != 0 marks
//   adjacent distinct-declaration boundaries and the lower-bound row for that
//   equal-key run.
// - Equal keys with different declarations are ambiguous imported declarations
//   for the same importing module and namespace. The lower-bound row for a
//   conflicting equal-key run is marked ambiguous so lookup cannot accept it.
//   Equal keys that name the same declaration are harmless re-imports.
// - It does not resolve paths, scan source bytes, use hashes, perform CPU
//   lookup, or apply same-source shortcuts.

import atomics;
import fixed.key;
import range_query;

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

int compare_encoded_u32(uint left, uint right)
{
    return fixed_u32_lane_compare(
        fixed_key_encode_nullable_u32(left, INVALID),
        fixed_key_encode_nullable_u32(right, INVALID));
}

int compare_type_row_key(uint row, uint module_id, uint name_id)
{
    int cmp = compare_encoded_u32(import_visible_type_key_module_id[row], module_id);
    if (cmp != 0)
        return cmp;
    return compare_encoded_u32(import_visible_type_key_name_id[row], name_id);
}

int compare_value_row_key(uint row, uint module_id, uint name_id)
{
    int cmp = compare_encoded_u32(import_visible_value_key_module_id[row], module_id);
    if (cmp != 0)
        return cmp;
    return compare_encoded_u32(import_visible_value_key_name_id[row], name_id);
}

public struct ImportVisibleLookupKey
{
    uint module_id;
    uint name_id;
}

public struct ImportVisibleTypeCompare : IRowQueryCompare<ImportVisibleLookupKey>
{
    public static int compare(uint row, ImportVisibleLookupKey key)
    {
        return compare_type_row_key(row, key.module_id, key.name_id);
    }
}

public struct ImportVisibleValueCompare : IRowQueryCompare<ImportVisibleLookupKey>
{
    public static int compare(uint row, ImportVisibleLookupKey key)
    {
        return compare_value_row_key(row, key.module_id, key.name_id);
    }
}

QueryRange type_key_range(uint count, uint module_id, uint name_id)
{
    ImportVisibleLookupKey key;
    key.module_id = module_id;
    key.name_id = name_id;
    return equal_range_query<ImportVisibleLookupKey, ImportVisibleTypeCompare>(count, key);
}

QueryRange value_key_range(uint count, uint module_id, uint name_id)
{
    ImportVisibleLookupKey key;
    key.module_id = module_id;
    key.name_id = name_id;
    return equal_range_query<ImportVisibleLookupKey, ImportVisibleValueCompare>(count, key);
}

void mark_type_ambiguous(uint row, uint duplicate_of)
{
    atomic_u32_max(import_visible_type_status, row, IMPORT_VISIBLE_STATUS_AMBIGUOUS);
    atomic_u32_min(import_visible_type_duplicate_of, row, duplicate_of);
}

void mark_value_ambiguous(uint row, uint duplicate_of)
{
    atomic_u32_max(import_visible_value_status, row, IMPORT_VISIBLE_STATUS_AMBIGUOUS);
    atomic_u32_min(import_visible_value_duplicate_of, row, duplicate_of);
}

uint adjacent_distinct_type_decl(uint i, uint count)
{
    uint decl_i = import_visible_type_key_to_decl_id[i];
    if (i > 0u &&
        same_type_key(i - 1u, i) &&
        import_visible_type_key_to_decl_id[i - 1u] != decl_i)
        return i - 1u;
    if (i + 1u < count &&
        same_type_key(i, i + 1u) &&
        import_visible_type_key_to_decl_id[i + 1u] != decl_i)
        return i + 1u;
    return INVALID;
}

uint adjacent_distinct_value_decl(uint i, uint count)
{
    uint decl_i = import_visible_value_key_to_decl_id[i];
    if (i > 0u &&
        same_value_key(i - 1u, i) &&
        import_visible_value_key_to_decl_id[i - 1u] != decl_i)
        return i - 1u;
    if (i + 1u < count &&
        same_value_key(i, i + 1u) &&
        import_visible_value_key_to_decl_id[i + 1u] != decl_i)
        return i + 1u;
    return INVALID;
}

void mark_type_boundary(uint i, uint count)
{
    if (i >= count || !valid_type_key(i))
        return;

    uint duplicate_of = adjacent_distinct_type_decl(i, count);
    if (duplicate_of == INVALID)
        return;

    mark_type_ambiguous(i, duplicate_of);

    QueryRange range = type_key_range(
        count,
        import_visible_type_key_module_id[i],
        import_visible_type_key_name_id[i]);
    uint first = range.begin;
    if (first < count && same_type_key(first, i))
        mark_type_ambiguous(first, duplicate_of);
}

void mark_value_boundary(uint i, uint count)
{
    if (i >= count || !valid_value_key(i))
        return;

    uint duplicate_of = adjacent_distinct_value_decl(i, count);
    if (duplicate_of == INVALID)
        return;

    mark_value_ambiguous(i, duplicate_of);

    QueryRange range = value_key_range(
        count,
        import_visible_value_key_module_id[i],
        import_visible_value_key_name_id[i]);
    uint first = range.begin;
    if (first < count && same_value_key(first, i))
        mark_value_ambiguous(first, duplicate_of);
}

void initialize_type_row(uint i)
{
    if (i >= active_type_count())
        return;

    import_visible_type_status[i] = valid_type_key(i)
        ? IMPORT_VISIBLE_STATUS_OK
        : IMPORT_VISIBLE_STATUS_INVALID_KEY;
    import_visible_type_duplicate_of[i] = INVALID;
}

void initialize_value_row(uint i)
{
    if (i >= active_value_count())
        return;

    import_visible_value_status[i] = valid_value_key(i)
        ? IMPORT_VISIBLE_STATUS_OK
        : IMPORT_VISIBLE_STATUS_INVALID_KEY;
    import_visible_value_duplicate_of[i] = INVALID;
}

void mark_boundary_rows(uint i)
{
    mark_type_boundary(i, active_type_count());
    mark_value_boundary(i, active_value_count());
}

void initialize_rows(uint i)
{
    initialize_type_row(i);
    initialize_value_row(i);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= visible_capacity())
        return;

    if (gParams.key_step == 0u)
    {
        initialize_rows(i);
        return;
    }

    mark_boundary_rows(i);
}
