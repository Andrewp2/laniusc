// GPU imported declaration visibility counting.
//
// Scheduling contract:
// - Dispatch after imports have target module ids and declaration namespace
//   lookup tables have been materialized.
// - For each resolved path import, find the target module's type/value
//   declaration ranges in the sorted declaration tables and read public row
//   counts from GPU prefix sums over those sorted declaration tables.
// - This pass writes per-import counts only. A GPU prefix scan over these
//   counts allocates compact import-visible rows for the scatter pass.
// - It does not resolve paths, scan source bytes, use hashes, append with
//   atomics, perform CPU lookup, or apply same-source shortcuts.

import gpu_index;
import range_query;

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
StructuredBuffer<uint> decl_type_public_flag;
StructuredBuffer<uint> decl_value_public_flag;
StructuredBuffer<uint> decl_type_public_prefix;
StructuredBuffer<uint> decl_value_public_prefix;
StructuredBuffer<uint> decl_module_id;

RWStructuredBuffer<uint> import_visible_type_count;
RWStructuredBuffer<uint> import_visible_value_count;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint IMPORT_STATUS_OK = 0u;
uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
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

uint type_decl_module_for_table_row(uint row)
{
    uint decl_i = decl_type_key_to_decl_id[row];
    return decl_i >= gParams.capacity ? INVALID : decl_module_id[decl_i];
}

uint value_decl_module_for_table_row(uint row)
{
    uint decl_i = decl_value_key_to_decl_id[row];
    return decl_i >= gParams.capacity ? INVALID : decl_module_id[decl_i];
}

public struct ModuleLookupKey
{
    uint module_id;
}

public struct TypeDeclModuleCompare : IRowQueryCompare<ModuleLookupKey>
{
    public static int compare(uint row, ModuleLookupKey key)
    {
        return compare_nullable_id(type_decl_module_for_table_row(row), key.module_id, INVALID);
    }
}

public struct ValueDeclModuleCompare : IRowQueryCompare<ModuleLookupKey>
{
    public static int compare(uint row, ModuleLookupKey key)
    {
        return compare_nullable_id(value_decl_module_for_table_row(row), key.module_id, INVALID);
    }
}

uint type_public_prefix_after(uint row)
{
    uint count = active_type_decl_count();
    if (row == 0u)
        return 0u;
    if (row >= count)
        row = count;
    uint last = row - 1u;
    return decl_type_public_prefix[last] + decl_type_public_flag[last];
}

uint value_public_prefix_after(uint row)
{
    uint count = active_value_decl_count();
    if (row == 0u)
        return 0u;
    if (row >= count)
        row = count;
    uint last = row - 1u;
    return decl_value_public_prefix[last] + decl_value_public_flag[last];
}

uint type_public_count_in_range(uint begin, uint end)
{
    if (end <= begin)
        return 0u;
    return type_public_prefix_after(end) - type_public_prefix_after(begin);
}

uint value_public_count_in_range(uint begin, uint end)
{
    if (end <= begin)
        return 0u;
    return value_public_prefix_after(end) - value_public_prefix_after(begin);
}

uint public_type_decl_count_in_module(uint module_id)
{
    ModuleLookupKey key;
    key.module_id = module_id;
    QueryRange range =
        equal_range_query<ModuleLookupKey, TypeDeclModuleCompare>(
            active_type_decl_count(),
            key);
    return type_public_count_in_range(range.begin, range.end);
}

uint public_value_decl_count_in_module(uint module_id)
{
    ModuleLookupKey key;
    key.module_id = module_id;
    QueryRange range =
        equal_range_query<ModuleLookupKey, ValueDeclModuleCompare>(
            active_value_decl_count(),
            key);
    return value_public_count_in_range(range.begin, range.end);
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

    import_visible_type_count[import_i] = public_type_decl_count_in_module(target_module);
    import_visible_value_count[import_i] = public_value_decl_count_in_module(target_module);
}
