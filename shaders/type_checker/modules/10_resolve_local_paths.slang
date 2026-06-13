// GPU local unqualified path resolution for one namespace table.
//
// Scheduling contract:
// - Dispatch after declaration lookup tables are materialized.
// - This pass initializes one resolved declaration/status array and resolves
//   one-segment HIR path expressions against declarations in the owner module.
// - Imported visibility and qualified module-prefix paths are handled by later
//   passes over the same arrays.
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
StructuredBuffer<uint> decl_key_count_out;
StructuredBuffer<uint> decl_key_to_decl_id;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> decl_name_id;

RWStructuredBuffer<uint> resolved_decl;
RWStructuredBuffer<uint> resolved_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_SKIPPED = 1u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED = 2u;
static const uint PATH_RESOLVE_STATUS_INVALID_OWNER = 3u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.capacity);
}

uint active_decl_count()
{
    return min(decl_key_count_out[0], gParams.capacity);
}

public struct DeclLookupKey
{
    uint module_id;
    uint name_id;
}

public struct DeclFixedKey : IFixedU32RowKey<DeclLookupKey>
{
    public static uint row_lane(uint row, uint lane)
    {
        uint decl_i = decl_key_to_decl_id[row];
        uint value = INVALID;
        if (decl_i < gParams.capacity)
            value = lane == 0u ? decl_module_id[decl_i] : decl_name_id[decl_i];
        return fixed_key_encode_nullable_u32(value, INVALID);
    }

    public static uint key_lane(DeclLookupKey key, uint lane)
    {
        uint value = lane == 0u ? key.module_id : key.name_id;
        return fixed_key_encode_nullable_u32(value, INVALID);
    }
}

public struct DeclKeyCompare : IRowQueryCompare<DeclLookupKey>
{
    public static int compare(uint row, DeclLookupKey key)
    {
        return fixed_u32_row_key_compare<DeclLookupKey, DeclFixedKey>(
            row,
            key,
            2u);
    }
}

uint find_decl(uint module_id, uint name_id)
{
    DeclLookupKey key;
    key.module_id = module_id;
    key.name_id = name_id;
    uint row = find_equal_query<DeclLookupKey, DeclKeyCompare>(active_decl_count(), key);
    if (row != INVALID)
        return decl_key_to_decl_id[row];
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id(dtid);
    if (path_i >= active_path_count())
        return;

    resolved_decl[path_i] = INVALID;
    resolved_status[path_i] = PATH_RESOLVE_STATUS_SKIPPED;

    if ((path_kind[path_i] != PATH_RECORD_KIND_HIR_PATH_EXPR &&
         path_kind[path_i] != PATH_RECORD_KIND_HIR_TYPE_EXPR))
        return;

    if (path_segment_count[path_i] != 1u)
        return;

    uint owner_module = path_owner_module_id[path_i];
    if (owner_module == INVALID)
    {
        resolved_status[path_i] = PATH_RESOLVE_STATUS_INVALID_OWNER;
        return;
    }

    uint name_id = path_segment_name_id[path_segment_base[path_i]];
    uint decl_i = find_decl(owner_module, name_id);
    if (decl_i == INVALID)
    {
        resolved_status[path_i] = PATH_RESOLVE_STATUS_UNRESOLVED;
        return;
    }

    resolved_decl[path_i] = decl_i;
    resolved_status[path_i] = PATH_RESOLVE_STATUS_OK;
}
