// GPU imported declaration visibility scatter for one namespace table.
//
// Scheduling contract:
// - Dispatch once for type imported-visibility rows and once for value rows
//   after per-import visibility counts have been prefix-scanned on the GPU.
// - For each compact output row, find the owning import by binary search over
//   import-visible prefixes, then find the local public declaration by binary
//   search over public declaration prefixes in the target module range.
// - This pass seeds row-order arrays for later stable radix sorting. It does
//   not resolve paths, scan source bytes, use hashes, append with atomics,
//   perform CPU lookup, or apply same-source shortcuts.

import gpu_index;
import range_query;
import status;

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
StructuredBuffer<uint> import_visible_count;
StructuredBuffer<uint> import_visible_count_out;
StructuredBuffer<uint> import_visible_prefix;
StructuredBuffer<uint> decl_key_count_out;
StructuredBuffer<uint> decl_key_to_decl_id;
StructuredBuffer<uint> decl_public_flag;
StructuredBuffer<uint> decl_public_prefix;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> decl_name_id;

RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> import_visible_module_id;
RWStructuredBuffer<uint> import_visible_name_id;
RWStructuredBuffer<uint> import_visible_decl_id;
RWStructuredBuffer<uint> import_visible_key_order;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint IMPORT_STATUS_OK = 0u;
static const uint ERR_NAME_LIMIT = 11u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

uint active_import_count()
{
    return min(import_count_out[0], gParams.capacity);
}

uint active_decl_count()
{
    return min(decl_key_count_out[0], gParams.capacity);
}

uint visible_capacity()
{
    return gParams.reserved == 0u ? gParams.capacity : gParams.reserved;
}

uint active_visible_count()
{
    return min(import_visible_count_out[0], visible_capacity());
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

uint decl_module_for_table_row(uint row)
{
    uint decl_i = decl_key_to_decl_id[row];
    return decl_i >= gParams.capacity ? INVALID : decl_module_id[decl_i];
}

int compare_decl_module_key(uint row, uint module_id)
{
    return compare_nullable_id(decl_module_for_table_row(row), module_id, INVALID);
}

public struct ModuleLookupKey
{
    uint module_id;
}

public struct DeclModuleCompare : IRowQueryCompare<ModuleLookupKey>
{
    public static int compare(uint row, ModuleLookupKey key)
    {
        return compare_decl_module_key(row, key.module_id);
    }
}

uint import_for_visible_row(uint visible_i)
{
    uint count = active_import_count();
    uint lo = 0u;
    uint hi = count;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        uint prefix = import_visible_prefix[mid];
        if (prefix <= visible_i)
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo == 0u ? INVALID : lo - 1u;
}

uint public_prefix_after_row(uint row)
{
    return decl_public_prefix[row] + decl_public_flag[row];
}

uint public_prefix_before_row(uint row)
{
    return row == 0u ? 0u : public_prefix_after_row(row - 1u);
}

uint public_decl_row_for_local_index(uint begin, uint end, uint local_i)
{
    if (end <= begin)
        return INVALID;

    uint target_prefix_after = public_prefix_before_row(begin) + local_i + 1u;
    uint lo = begin;
    uint hi = end;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (public_prefix_after_row(mid) < target_prefix_after)
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo < end &&
           decl_public_flag[lo] != 0u &&
           public_prefix_after_row(lo) == target_prefix_after
               ? lo
               : INVALID;
}

QueryRange target_module_decl_range(uint module_id)
{
    ModuleLookupKey key;
    key.module_id = module_id;
    return equal_range_query<ModuleLookupKey, DeclModuleCompare>(active_decl_count(), key);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint visible_i = linear_thread_id(dtid);
    uint total_visible_count = import_visible_count_out[0];
    if (visible_i == 0u && total_visible_count > visible_capacity())
        record_error(0u, ERR_NAME_LIMIT, total_visible_count);

    if (visible_i >= active_visible_count())
        return;

    uint import_i = import_for_visible_row(visible_i);
    if (import_i == INVALID)
        return;

    uint import_prefix = import_visible_prefix[import_i];
    uint import_count = import_visible_count[import_i];
    if (visible_i < import_prefix || visible_i >= import_prefix + import_count)
        return;

    uint importing_module = import_module_id[import_i];
    uint target_module = import_target_module_id[import_i];
    if (import_status[import_i] != IMPORT_STATUS_OK || importing_module == INVALID ||
        target_module == INVALID)
        return;

    QueryRange range = target_module_decl_range(target_module);
    if (range.end <= range.begin)
        return;

    uint local_i = visible_i - import_prefix;
    uint decl_row = public_decl_row_for_local_index(range.begin, range.end, local_i);
    if (decl_row == INVALID)
        return;

    uint decl_i = decl_key_to_decl_id[decl_row];
    if (decl_i >= gParams.capacity)
        return;

    import_visible_module_id[visible_i] = importing_module;
    import_visible_name_id[visible_i] = decl_name_id[decl_i];
    import_visible_decl_id[visible_i] = decl_i;
    import_visible_key_order[visible_i] = visible_i;
}
