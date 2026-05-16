// GPU imported declaration visibility counting.
//
// Scheduling contract:
// - Dispatch after imports have target module ids and declaration namespace
//   lookup tables have been materialized.
// - For each resolved path import, find the target module's type/value
//   declaration ranges in the sorted declaration tables and count public rows.
// - This pass writes per-import counts only. A GPU prefix scan over these
//   counts allocates compact import-visible rows for the scatter pass.
// - It does not resolve paths, scan source bytes, use hashes, append with
//   atomics, perform CPU lookup, or apply same-source shortcuts.

struct Params
{
    uint capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> import_count_out;
StructuredBuffer<uint> import_status;
StructuredBuffer<uint> import_module_id;
StructuredBuffer<uint> import_target_module_id;
StructuredBuffer<uint> decl_type_key_count_out;
StructuredBuffer<uint> decl_value_key_count_out;
StructuredBuffer<uint> decl_type_key_to_decl_id;
StructuredBuffer<uint> decl_value_key_to_decl_id;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> decl_visibility;

RWStructuredBuffer<uint> import_visible_type_count;
RWStructuredBuffer<uint> import_visible_value_count;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint IMPORT_STATUS_OK = 0u;
static const uint HIR_ITEM_VIS_PUBLIC = 1u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_import_count()
{
    return min(import_count_out[0], gParams.capacity);
}

uint active_type_decl_count()
{
    return min(decl_type_key_count_out[0], gParams.capacity);
}

uint active_value_decl_count()
{
    return min(decl_value_key_count_out[0], gParams.capacity);
}

uint decl_module_for_table_row(StructuredBuffer<uint> table, uint row)
{
    uint decl_i = table[row];
    return decl_i >= gParams.capacity ? INVALID : decl_module_id[decl_i];
}

uint lower_bound_module(StructuredBuffer<uint> table, uint count, uint module_id)
{
    uint lo = 0u;
    uint hi = count;
    [loop]
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        uint mid_module = decl_module_for_table_row(table, mid);
        uint key = mid_module == INVALID ? 0u : mid_module + 1u;
        uint target = module_id == INVALID ? 0u : module_id + 1u;
        if (key < target)
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo;
}

uint upper_bound_module(StructuredBuffer<uint> table, uint count, uint module_id)
{
    uint lo = 0u;
    uint hi = count;
    [loop]
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        uint mid_module = decl_module_for_table_row(table, mid);
        uint key = mid_module == INVALID ? 0u : mid_module + 1u;
        uint target = module_id == INVALID ? 0u : module_id + 1u;
        if (key <= target)
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo;
}

uint public_decl_count_in_module(StructuredBuffer<uint> table, uint count, uint module_id)
{
    uint begin = lower_bound_module(table, count, module_id);
    uint end = upper_bound_module(table, count, module_id);
    uint public_count = 0u;
    [loop]
    for (uint row = begin; row < end; row += 1u)
    {
        uint decl_i = table[row];
        if (decl_i < gParams.capacity && decl_visibility[decl_i] == HIR_ITEM_VIS_PUBLIC)
            public_count += 1u;
    }
    return public_count;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint import_i = linear_thread_id(dtid);
    if (import_i >= gParams.capacity)
        return;

    import_visible_type_count[import_i] = 0u;
    import_visible_value_count[import_i] = 0u;

    if (import_i >= active_import_count())
        return;

    uint importing_module = import_module_id[import_i];
    uint target_module = import_target_module_id[import_i];
    if (import_status[import_i] != IMPORT_STATUS_OK || importing_module == INVALID ||
        target_module == INVALID)
        return;

    import_visible_type_count[import_i] = public_decl_count_in_module(
        decl_type_key_to_decl_id, active_type_decl_count(), target_module);
    import_visible_value_count[import_i] = public_decl_count_in_module(
        decl_value_key_to_decl_id, active_value_decl_count(), target_module);
}
