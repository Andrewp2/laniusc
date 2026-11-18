// Validates exact imported-visibility lookup rows for both namespaces.
//
// key_step == 0 initializes row status. key_step != 0 queries the exact table
// and marks a key ambiguous when two imports expose different declarations.
// Re-importing the same declaration remains valid.

import atomics;
import type_checker.modules.import_visible_lookup;

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
StructuredBuffer<uint> import_visible_type_lookup_state;
StructuredBuffer<uint> import_visible_value_count_out;
StructuredBuffer<uint> import_visible_value_key_module_id;
StructuredBuffer<uint> import_visible_value_key_name_id;
StructuredBuffer<uint> import_visible_value_key_to_decl_id;
StructuredBuffer<uint> import_visible_value_lookup_state;

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

bool valid_type_row(uint row)
{
    return import_visible_lookup_row_valid(
        row,
        active_type_count(),
        import_visible_type_key_module_id,
        import_visible_type_key_name_id,
        import_visible_type_key_to_decl_id);
}

bool valid_value_row(uint row)
{
    return import_visible_lookup_row_valid(
        row,
        active_value_count(),
        import_visible_value_key_module_id,
        import_visible_value_key_name_id,
        import_visible_value_key_to_decl_id);
}

void initialize_type(uint row)
{
    if (row >= active_type_count())
        return;
    import_visible_type_status[row] = valid_type_row(row)
        ? IMPORT_VISIBLE_STATUS_OK
        : IMPORT_VISIBLE_STATUS_INVALID_KEY;
    import_visible_type_duplicate_of[row] = INVALID;
}

void initialize_value(uint row)
{
    if (row >= active_value_count())
        return;
    import_visible_value_status[row] = valid_value_row(row)
        ? IMPORT_VISIBLE_STATUS_OK
        : IMPORT_VISIBLE_STATUS_INVALID_KEY;
    import_visible_value_duplicate_of[row] = INVALID;
}

void mark_type_ambiguity(uint row)
{
    if (!valid_type_row(row))
        return;
    uint owner = import_visible_lookup_find(
        import_visible_type_key_module_id[row],
        import_visible_type_key_name_id[row],
        active_type_count(),
        visible_capacity(),
        import_visible_type_key_module_id,
        import_visible_type_key_name_id,
        import_visible_type_key_to_decl_id,
        import_visible_type_lookup_state);
    if (owner == INVALID || owner == row ||
        import_visible_type_key_to_decl_id[owner] == import_visible_type_key_to_decl_id[row])
        return;
    atomic_u32_max(import_visible_type_status, owner, IMPORT_VISIBLE_STATUS_AMBIGUOUS);
    atomic_u32_max(import_visible_type_status, row, IMPORT_VISIBLE_STATUS_AMBIGUOUS);
    atomic_u32_min(import_visible_type_duplicate_of, owner, row);
    atomic_u32_min(import_visible_type_duplicate_of, row, owner);
}

void mark_value_ambiguity(uint row)
{
    if (!valid_value_row(row))
        return;
    uint owner = import_visible_lookup_find(
        import_visible_value_key_module_id[row],
        import_visible_value_key_name_id[row],
        active_value_count(),
        visible_capacity(),
        import_visible_value_key_module_id,
        import_visible_value_key_name_id,
        import_visible_value_key_to_decl_id,
        import_visible_value_lookup_state);
    if (owner == INVALID || owner == row ||
        import_visible_value_key_to_decl_id[owner] == import_visible_value_key_to_decl_id[row])
        return;
    atomic_u32_max(import_visible_value_status, owner, IMPORT_VISIBLE_STATUS_AMBIGUOUS);
    atomic_u32_max(import_visible_value_status, row, IMPORT_VISIBLE_STATUS_AMBIGUOUS);
    atomic_u32_min(import_visible_value_duplicate_of, owner, row);
    atomic_u32_min(import_visible_value_duplicate_of, row, owner);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= visible_capacity())
        return;

    if (gParams.key_step == 0u)
    {
        initialize_type(row);
        initialize_value(row);
    }
    else
    {
        mark_type_ambiguity(row);
        mark_value_ambiguity(row);
    }
}
