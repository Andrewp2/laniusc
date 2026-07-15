// GPU qualified path resolution for one namespace table.
//
// Scheduling contract:
// - Dispatch after module keys and declaration namespace lookup tables are
//   sorted and materialized.
// - Multi-segment HIR path expressions resolve by looking up the prefix's exact
//   canonical id and then looking up the leaf in that module's declaration
//   table. Private declarations are visible only from the owning module.
//   Public cross-module declarations are visible only through an explicit
//   resolved import edge from the consuming module to the prefix module.
//   One-segment paths are handled by local/imported lookup passes.
// - It does not scan source bytes, use hashes, perform CPU lookup, or apply
//   same-source shortcuts.

import fixed.key;
import gpu_index;
import range_query;
import sorted.join;

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
StructuredBuffer<uint> path_prefix_id;
StructuredBuffer<uint> path_owner_module_id;
StructuredBuffer<uint> module_table_count_out;
StructuredBuffer<uint> sorted_module_key_order;
StructuredBuffer<uint> module_key_canonical_id;
StructuredBuffer<uint> import_count_out;
StructuredBuffer<uint> import_status;
StructuredBuffer<uint> import_module_id;
StructuredBuffer<uint> import_target_module_id;
StructuredBuffer<uint> import_edge_key_order;
StructuredBuffer<uint> decl_key_count_out;
StructuredBuffer<uint> decl_key_to_decl_id;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> decl_visibility;
StructuredBuffer<uint> decl_name_id;

RWStructuredBuffer<uint> resolved_decl;
RWStructuredBuffer<uint> resolved_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_INVALID_OWNER = 3u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED_MODULE = 5u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED_DECL = 6u;
static const uint HIR_ITEM_VIS_PUBLIC = 1u;
static const uint IMPORT_STATUS_OK = 0u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.capacity);
}

uint module_capacity()
{
    return gParams.reserved == 0u ? gParams.capacity : gParams.reserved;
}

uint active_module_count()
{
    return min(module_table_count_out[0], module_capacity());
}

uint active_import_count()
{
    return min(import_count_out[0], gParams.capacity);
}

uint active_decl_count()
{
    return min(decl_key_count_out[0], gParams.capacity);
}

bool valid_import_edge(uint import_i)
{
    return import_i < active_import_count() &&
           import_status[import_i] == IMPORT_STATUS_OK &&
           import_module_id[import_i] != INVALID &&
           import_target_module_id[import_i] != INVALID;
}

public struct ModulePrefixLookupKey
{
    uint canonical_id;
}

public struct ModulePrefixCompare : IRowQueryCompare<ModulePrefixLookupKey>
{
    public static int compare(uint row, ModulePrefixLookupKey key)
    {
        uint module_i = sorted_module_key_order[row];
        uint row_id = module_key_canonical_id[module_i];
        return row_id < key.canonical_id ? -1 : (row_id > key.canonical_id ? 1 : 0);
    }
}

public struct ModulePrefixValue : ISortedJoinValue<uint>
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

uint find_module_for_path_prefix(uint path_i, uint prefix_count)
{
    ModulePrefixLookupKey key;
    key.canonical_id = path_prefix_id[
        path_segment_base[path_i] + prefix_count - 1u];
    return sorted_join_project_key_or_invalid<
        ModulePrefixLookupKey,
        uint,
        ModulePrefixCompare,
        ModulePrefixValue>(
        active_module_count(),
        key,
        INVALID);
}

public struct ImportEdgeLookupKey
{
    uint importing_module;
    uint target_module;
}

public struct ImportEdgeFixedKey : IFixedU32RowKey<ImportEdgeLookupKey>
{
    public static uint row_lane(uint row, uint lane)
    {
        if (row >= active_import_count())
            return 0u;
        uint import_i = import_edge_key_order[row];
        if (!valid_import_edge(import_i))
            return 0u;
        uint value = lane == 0u
            ? import_module_id[import_i]
            : import_target_module_id[import_i];
        return fixed_key_encode_nullable_u32(value, INVALID);
    }

    public static uint key_lane(ImportEdgeLookupKey key, uint lane)
    {
        uint value = lane == 0u ? key.importing_module : key.target_module;
        return fixed_key_encode_nullable_u32(value, INVALID);
    }
}

public struct ImportEdgeCompare : IRowQueryCompare<ImportEdgeLookupKey>
{
    public static int compare(uint row, ImportEdgeLookupKey key)
    {
        return fixed_u32_row_key_compare<ImportEdgeLookupKey, ImportEdgeFixedKey>(
            row,
            key,
            2u);
    }
}

bool has_import_edge(uint importing_module, uint target_module)
{
    ImportEdgeLookupKey key;
    key.importing_module = importing_module;
    key.target_module = target_module;
    QueryRange range = equal_range_query<ImportEdgeLookupKey, ImportEdgeCompare>(
        active_import_count(),
        key);
    return range.begin < range.end;
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

public struct DeclValue : ISortedJoinValue<uint>
{
    public static uint invalid_value()
    {
        return INVALID;
    }

    public static uint row_value(uint row)
    {
        return row < active_decl_count() ? decl_key_to_decl_id[row] : INVALID;
    }
}

uint find_decl(uint module_id, uint name_id)
{
    DeclLookupKey key;
    key.module_id = module_id;
    key.name_id = name_id;
    return sorted_join_project_key_or_invalid<
        DeclLookupKey,
        uint,
        DeclKeyCompare,
        DeclValue>(
        active_decl_count(),
        key,
        INVALID);
}

bool decl_visible_from_path(uint path_i, uint decl_i)
{
    if (decl_i >= gParams.capacity)
        return false;

    uint owner_module = path_owner_module_id[path_i];
    uint decl_module = decl_module_id[decl_i];
    if (owner_module != INVALID && decl_module != INVALID && owner_module == decl_module)
        return true;

    return decl_visibility[decl_i] == HIR_ITEM_VIS_PUBLIC;
}

bool module_prefix_visible_from_path(uint path_i, uint module_i)
{
    uint owner_module = path_owner_module_id[path_i];
    if (owner_module == INVALID)
        return false;
    if (owner_module == module_i)
        return true;
    return has_import_edge(owner_module, module_i);
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

    uint count = path_segment_count[path_i];
    if (count <= 1u)
        return;
    uint module_i = find_module_for_path_prefix(path_i, count - 1u);
    if (module_i == INVALID)
    {
        resolved_decl[path_i] = INVALID;
        resolved_status[path_i] = PATH_RESOLVE_STATUS_UNRESOLVED_MODULE;
        return;
    }
    if (path_owner_module_id[path_i] == INVALID)
    {
        resolved_decl[path_i] = INVALID;
        resolved_status[path_i] = PATH_RESOLVE_STATUS_INVALID_OWNER;
        return;
    }
    if (!module_prefix_visible_from_path(path_i, module_i))
    {
        resolved_decl[path_i] = INVALID;
        resolved_status[path_i] = PATH_RESOLVE_STATUS_UNRESOLVED_MODULE;
        return;
    }

    uint leaf_name_id = path_segment_name_id[path_segment_base[path_i] + count - 1u];
    uint decl_i = find_decl(module_i, leaf_name_id);
    if (decl_i == INVALID)
    {
        resolved_decl[path_i] = INVALID;
        resolved_status[path_i] = PATH_RESOLVE_STATUS_UNRESOLVED_DECL;
        return;
    }
    if (!decl_visible_from_path(path_i, decl_i))
    {
        resolved_decl[path_i] = INVALID;
        resolved_status[path_i] = PATH_RESOLVE_STATUS_UNRESOLVED_DECL;
        return;
    }

    resolved_decl[path_i] = decl_i;
    resolved_status[path_i] = PATH_RESOLVE_STATUS_OK;
}
