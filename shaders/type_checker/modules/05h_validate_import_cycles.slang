// GPU import-cycle validation over sorted import edges.
//
// Scheduling contract:
// - Dispatch after the import-edge radix sort has produced rows ordered by
//   (importing module id, target module id).
// - Each resolved import performs equal-range lookups over the sorted edge
//   table. This slice rejects direct two-module cycles without scanning source
//   bytes, walking module graphs on the CPU, using hashes, or performing broad
//   per-module loops. Longer cycles require a dedicated GPU SCC/topological
//   checkpoint.

import fixed.key;
import range_query;
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
StructuredBuffer<uint> import_module_id;
StructuredBuffer<uint> import_target_module_id;
StructuredBuffer<uint> import_path_id;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> import_edge_key_order;

RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> import_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint IMPORT_STATUS_OK = 0u;
static const uint IMPORT_STATUS_SELF_CYCLE = 4u;

static const uint ERR_IMPORT_CYCLE = 12u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint import_capacity()
{
    return gParams.module_capacity;
}

uint active_import_count()
{
    return min(import_count_out[0], import_capacity());
}

bool valid_import_edge(uint import_i)
{
    return import_i < active_import_count() &&
           import_status[import_i] == IMPORT_STATUS_OK &&
           import_module_id[import_i] != INVALID &&
           import_target_module_id[import_i] != INVALID;
}

uint encoded_module_id(uint module_id)
{
    return fixed_key_encode_nullable_u32(module_id, INVALID);
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
        return encoded_module_id(value);
    }

    public static uint key_lane(ImportEdgeLookupKey key, uint lane)
    {
        uint value = lane == 0u ? key.importing_module : key.target_module;
        return encoded_module_id(value);
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

bool has_reverse_edge(uint importing_module, uint target_module)
{
    ImportEdgeLookupKey key;
    key.importing_module = target_module;
    key.target_module = importing_module;
    QueryRange range = equal_range_query<ImportEdgeLookupKey, ImportEdgeCompare>(
        active_import_count(),
        key);
    return range.begin < range.end;
}

uint import_error_token(uint import_i)
{
    uint path_id = import_path_id[import_i];
    if (path_id >= import_capacity())
        return import_i;
    uint token = path_owner_token[path_id];
    return token == INVALID ? import_i : token;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint import_i = linear_thread_id(dtid);
    if (!valid_import_edge(import_i))
        return;

    uint importing_module = import_module_id[import_i];
    uint target_module = import_target_module_id[import_i];
    if (importing_module == target_module)
        return;

    if (!has_reverse_edge(importing_module, target_module))
        return;

    import_status[import_i] = IMPORT_STATUS_SELF_CYCLE;
    record_min_token_error(
        status,
        import_error_token(import_i),
        ERR_IMPORT_CYCLE,
        IMPORT_STATUS_SELF_CYCLE);
}
