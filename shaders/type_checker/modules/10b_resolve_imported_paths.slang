// GPU imported unqualified path resolution for one namespace table.
//
// Scheduling contract:
// - Dispatch after local unqualified resolution and imported visibility table
//   validation.
// - This pass resolves still-unresolved one-segment HIR path expressions
//   against sorted imported-public declaration tables for the owner module.
// - It does not scan source bytes, use hashes, perform CPU lookup, or apply
//   same-source shortcuts.

import fixed.key;
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

StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_name_id;
StructuredBuffer<uint> path_owner_module_id;
StructuredBuffer<uint> import_visible_count_out;
StructuredBuffer<uint> import_visible_key_module_id;
StructuredBuffer<uint> import_visible_key_name_id;
StructuredBuffer<uint> import_visible_key_to_decl_id;
StructuredBuffer<uint> import_visible_status;

RWStructuredBuffer<uint> resolved_decl;
RWStructuredBuffer<uint> resolved_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED = 2u;
static const uint PATH_RESOLVE_STATUS_INVALID_OWNER = 3u;
static const uint PATH_RESOLVE_STATUS_AMBIGUOUS_IMPORT = 4u;
static const uint IMPORT_VISIBLE_STATUS_OK = 0u;
static const uint IMPORT_VISIBLE_STATUS_AMBIGUOUS = 1u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.capacity);
}

uint visible_capacity()
{
    return gParams.reserved == 0u ? gParams.capacity : gParams.reserved;
}

uint active_visible_count()
{
    return min(import_visible_count_out[0], visible_capacity());
}

public struct VisibleLookupKey
{
    uint module_id;
    uint name_id;
}

public struct VisibleFixedKey : IFixedU32RowKey<VisibleLookupKey>
{
    public static uint row_lane(uint row, uint lane)
    {
        uint value = lane == 0u
            ? import_visible_key_module_id[row]
            : import_visible_key_name_id[row];
        return fixed_key_encode_nullable_u32(value, INVALID);
    }

    public static uint key_lane(VisibleLookupKey key, uint lane)
    {
        uint value = lane == 0u ? key.module_id : key.name_id;
        return fixed_key_encode_nullable_u32(value, INVALID);
    }
}

public struct VisibleKeyCompare : IRowQueryCompare<VisibleLookupKey>
{
    public static int compare(uint row, VisibleLookupKey key)
    {
        return fixed_u32_row_key_compare<VisibleLookupKey, VisibleFixedKey>(
            row,
            key,
            2u);
    }
}

uint find_visible_row(uint module_id, uint name_id)
{
    VisibleLookupKey key;
    key.module_id = module_id;
    key.name_id = name_id;
    return find_equal_query<VisibleLookupKey, VisibleKeyCompare>(active_visible_count(), key);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id(dtid);
    if (path_i >= active_path_count() ||
        (path_kind[path_i] != PATH_RECORD_KIND_HIR_PATH_EXPR &&
         path_kind[path_i] != PATH_RECORD_KIND_HIR_TYPE_EXPR))
        return;
    if (path_segment_count[path_i] != 1u || resolved_decl[path_i] != INVALID)
        return;

    uint owner_module = path_owner_module_id[path_i];
    if (owner_module == INVALID)
    {
        resolved_status[path_i] = PATH_RESOLVE_STATUS_INVALID_OWNER;
        return;
    }

    uint name_id = path_segment_name_id[path_segment_base[path_i]];
    uint row = find_visible_row(owner_module, name_id);
    if (row == INVALID)
    {
        if (resolved_status[path_i] != PATH_RESOLVE_STATUS_OK)
            resolved_status[path_i] = PATH_RESOLVE_STATUS_UNRESOLVED;
        return;
    }

    if (import_visible_status[row] == IMPORT_VISIBLE_STATUS_AMBIGUOUS)
    {
        resolved_status[path_i] = PATH_RESOLVE_STATUS_AMBIGUOUS_IMPORT;
        return;
    }
    if (import_visible_status[row] != IMPORT_VISIBLE_STATUS_OK)
    {
        resolved_status[path_i] = PATH_RESOLVE_STATUS_UNRESOLVED;
        return;
    }

    resolved_decl[path_i] = import_visible_key_to_decl_id[row];
    resolved_status[path_i] = PATH_RESOLVE_STATUS_OK;
}
