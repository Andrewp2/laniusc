// GPU import-to-module lookup.
//
// Scheduling contract:
// - Dispatch after import records have been scattered and module key rows have
//   been sorted by the GPU radix passes.
// - Each path import performs a sorted-table lookup against
//   sorted_module_key_order using path segment name ids.
// - This pass writes import_target_module_id and import_status only. It does
//   not make declarations visible, resolve value/type paths, perform CPU path
//   lookup, scan source bytes, use hashes, or apply same-source shortcuts.

import fixed_key;
import range_query;
import sorted_join;
import status;

struct Params
{
    uint module_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> import_count_out;
StructuredBuffer<uint> import_kind;
StructuredBuffer<uint> import_path_id;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_name_id;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> sorted_module_key_order;
StructuredBuffer<uint> module_key_segment_count;
StructuredBuffer<uint> module_key_segment_base;
StructuredBuffer<uint> module_key_segment_name_id;

RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> import_target_module_id;
RWStructuredBuffer<uint> import_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint SORT_PATH_SEGMENTS = 8u;
static const uint PATH_SEGMENT_ROW_WIDTH = SORT_PATH_SEGMENTS + 1u;
static const uint MODULE_KEY_SEGMENT_ROW_WIDTH = SORT_PATH_SEGMENTS;

static const uint HIR_ITEM_IMPORT_TARGET_PATH = 1u;

static const uint IMPORT_STATUS_OK = 0u;
static const uint IMPORT_STATUS_UNRESOLVED = 1u;
static const uint IMPORT_STATUS_UNSUPPORTED_STRING = 2u;
static const uint IMPORT_STATUS_PATH_TOO_DEEP = 3u;

static const uint ERR_BAD_HIR = 6u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint record_capacity()
{
    return gParams.module_capacity;
}

uint module_capacity()
{
    return gParams.reserved == 0u ? gParams.module_capacity : gParams.reserved;
}

uint active_import_count()
{
    return min(import_count_out[0], record_capacity());
}

uint active_module_count()
{
    return min(module_count_out[0], module_capacity());
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

uint path_segment_value(uint path_id, uint segment_i)
{
    if (path_id >= record_capacity())
        return 0u;
    if (segment_i >= min(path_segment_count[path_id], PATH_SEGMENT_ROW_WIDTH))
        return 0u;

    uint base = path_segment_base[path_id];
    uint name_id = path_segment_name_id[base + segment_i];
    return name_id == INVALID ? 0u : name_id + 1u;
}

uint module_segment_value(uint module_i, uint segment_i)
{
    if (module_i >= active_module_count())
        return 0u;
    if (segment_i >= min(module_key_segment_count[module_i], MODULE_KEY_SEGMENT_ROW_WIDTH))
        return 0u;

    uint base = module_key_segment_base[module_i];
    uint name_id = module_key_segment_name_id[base + segment_i];
    return name_id == INVALID ? 0u : name_id + 1u;
}

public struct ImportPathLookupKey
{
    uint path_id;
}

public struct ImportModulePathKey : IFixedU32RowKey<ImportPathLookupKey>
{
    public static uint row_lane(uint module_i, uint lane)
    {
        return module_segment_value(module_i, lane);
    }

    public static uint key_lane(ImportPathLookupKey key, uint lane)
    {
        return path_segment_value(key.path_id, lane);
    }
}

public struct ImportModuleCompare : IRowQueryCompare<ImportPathLookupKey>
{
    public static int compare(uint row, ImportPathLookupKey key)
    {
        uint module_i = sorted_module_key_order[row];
        return fixed_u32_row_key_compare<ImportPathLookupKey, ImportModulePathKey>(
            module_i,
            key,
            SORT_PATH_SEGMENTS);
    }
}

public struct ImportModuleValue : ISortedJoinValue<uint>
{
    public static uint invalid_value()
    {
        return INVALID;
    }

    public static uint row_value(uint row)
    {
        return row < active_module_count() ? sorted_module_key_order[row] : INVALID;
    }
}

uint find_module_for_path(uint path_id)
{
    ImportPathLookupKey key;
    key.path_id = path_id;
    return sorted_join_project_key_or_invalid<
        ImportPathLookupKey,
        uint,
        ImportModuleCompare,
        ImportModuleValue>(
        active_module_count(),
        key,
        INVALID);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint import_i = linear_thread_id(dtid);
    if (import_i >= active_import_count())
        return;

    import_target_module_id[import_i] = INVALID;

    if (import_kind[import_i] != HIR_ITEM_IMPORT_TARGET_PATH)
    {
        import_status[import_i] = IMPORT_STATUS_UNSUPPORTED_STRING;
        record_error(import_i, ERR_BAD_HIR, IMPORT_STATUS_UNSUPPORTED_STRING);
        return;
    }

    uint path_id = import_path_id[import_i];
    if (path_id >= record_capacity())
    {
        import_status[import_i] = IMPORT_STATUS_UNRESOLVED;
        record_error(import_i, ERR_BAD_HIR, IMPORT_STATUS_UNRESOLVED);
        return;
    }

    uint count = path_segment_count[path_id];
    if (count == 0u)
    {
        import_status[import_i] = IMPORT_STATUS_UNRESOLVED;
        record_error(path_owner_token[path_id], ERR_BAD_HIR, IMPORT_STATUS_UNRESOLVED);
        return;
    }
    if (count > SORT_PATH_SEGMENTS)
    {
        import_status[import_i] = IMPORT_STATUS_PATH_TOO_DEEP;
        record_error(path_owner_token[path_id], ERR_BAD_HIR, IMPORT_STATUS_PATH_TOO_DEEP);
        return;
    }

    uint module_i = find_module_for_path(path_id);
    if (module_i == INVALID)
    {
        import_status[import_i] = IMPORT_STATUS_UNRESOLVED;
        record_error(path_owner_token[path_id], ERR_BAD_HIR, IMPORT_STATUS_UNRESOLVED);
        return;
    }

    import_target_module_id[import_i] = module_i;
    import_status[import_i] = IMPORT_STATUS_OK;
}
