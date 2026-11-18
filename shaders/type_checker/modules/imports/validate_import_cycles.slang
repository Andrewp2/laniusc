// GPU import-cycle validation over the exact resolved-import set.
//
// Scheduling contract:
// - Dispatch after every resolved edge has been published to the GPU hash set.
// - Each resolved import performs one exact reverse-edge lookup. This slice
//   rejects direct two-module cycles without scanning source bytes or walking
//   module graphs on the CPU. Longer cycles require the GPU topological check.

import status;
import type_checker.modules.import_edge_set;

struct Params
{
    uint import_capacity;
    uint path_capacity;
    uint path_segment_capacity;
    uint module_capacity;
    uint dependency_interfaces_present;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> import_count_out;
StructuredBuffer<uint> import_module_id;
StructuredBuffer<uint> import_target_module_id;
StructuredBuffer<uint> import_path_id;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> import_edge_set_state;

RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> import_status;

public struct ImportEdgeStatusSource : IImportEdgeStatusSource
{
    public static uint status(uint row) { return import_status[row]; }
}

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
    return gParams.import_capacity;
}

uint active_import_count()
{
    return min(import_count_out[0], import_capacity());
}

bool has_reverse_edge(uint importing_module, uint target_module)
{
    return import_edge_set_contains<ImportEdgeStatusSource>(
        target_module,
        importing_module,
        active_import_count(),
        import_module_id,
        import_target_module_id,
        import_edge_set_state);
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
    if (!import_edge_row_valid<ImportEdgeStatusSource>(
        import_i,
        active_import_count(),
        import_module_id,
        import_target_module_id))
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
