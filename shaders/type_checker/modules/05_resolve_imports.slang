// GPU import-to-module lookup.
//
// Scheduling contract:
// - Dispatch after import records have been scattered and the direct module
//   table has been populated.
// - Each path import indexes that table with its exact canonical path-prefix id.
// - Dispatch after type_check_modules_05d_attach_record_modules has attached
//   import records to their owning module ids.
// - Direct self-imports are rejected here. The following sorted import-edge
//   pass rejects two-module cycles through GPU range lookups.
// - This pass writes import_target_module_id and import_status only. It does
//   not make declarations visible, resolve value/type paths, perform CPU path
//   lookup, scan source bytes, use hashes, or apply same-source shortcuts.

import status;
import hir_records;
import type_checker.modules.module_lookup;

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
StructuredBuffer<uint> import_kind;
StructuredBuffer<uint> import_path_id;
StructuredBuffer<uint> import_module_id;
StructuredBuffer<uint> import_owner_hir;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_prefix_id;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> module_by_canonical_id;

RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> import_target_module_id;
RWStructuredBuffer<uint> import_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_ITEM_IMPORT_TARGET_PATH = 1u;

static const uint IMPORT_STATUS_OK = 0u;
static const uint IMPORT_STATUS_UNRESOLVED = 1u;
static const uint IMPORT_STATUS_UNSUPPORTED_STRING = 2u;
static const uint IMPORT_STATUS_SELF_CYCLE = 4u;

static const uint ERR_BAD_HIR = 6u;
static const uint ERR_IMPORT_CYCLE = 12u;
static const uint ERR_UNRESOLVED_IMPORT = 15u;
static const uint ERR_UNSUPPORTED_IMPORT = 16u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_import_count()
{
    return min(import_count_out[0], gParams.import_capacity);
}

uint active_module_count()
{
    return min(module_count_out[0], gParams.module_capacity);
}

uint active_compact_hir_count()
{
    return compact_hir_count[0];
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

uint import_owner_token(uint import_i)
{
    uint owner = import_owner_hir[import_i];
    if (owner == INVALID)
        return import_i;
    if (owner >= active_compact_hir_count())
        return import_i;
    return compact_hir_core[owner].token_start;
}

uint find_module_for_path(uint path_id)
{
    uint count = path_segment_count[path_id];
    uint canonical_id = path_prefix_id[path_segment_base[path_id] + count - 1u];
    uint module_id = module_lookup_find(
        canonical_id,
        gParams.path_segment_capacity,
        module_by_canonical_id);
    return module_id < active_module_count() ? module_id : INVALID;
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
        record_error(
            import_owner_token(import_i),
            ERR_UNSUPPORTED_IMPORT,
            IMPORT_STATUS_UNSUPPORTED_STRING);
        return;
    }

    uint path_id = import_path_id[import_i];
    if (path_id >= gParams.path_capacity)
    {
        import_status[import_i] = IMPORT_STATUS_UNRESOLVED;
        if (gParams.dependency_interfaces_present == 0u)
            record_error(import_i, ERR_UNRESOLVED_IMPORT, IMPORT_STATUS_UNRESOLVED);
        return;
    }

    uint count = path_segment_count[path_id];
    if (count == 0u)
    {
        import_status[import_i] = IMPORT_STATUS_UNRESOLVED;
        if (gParams.dependency_interfaces_present == 0u)
            record_error(path_owner_token[path_id], ERR_UNRESOLVED_IMPORT, IMPORT_STATUS_UNRESOLVED);
        return;
    }
    uint module_i = find_module_for_path(path_id);
    if (module_i == INVALID)
    {
        import_status[import_i] = IMPORT_STATUS_UNRESOLVED;
        if (gParams.dependency_interfaces_present == 0u)
            record_error(path_owner_token[path_id], ERR_UNRESOLVED_IMPORT, IMPORT_STATUS_UNRESOLVED);
        return;
    }

    uint importing_module = import_module_id[import_i];
    if (importing_module != INVALID && importing_module == module_i)
    {
        import_status[import_i] = IMPORT_STATUS_SELF_CYCLE;
        record_error(path_owner_token[path_id], ERR_IMPORT_CYCLE, IMPORT_STATUS_SELF_CYCLE);
        return;
    }

    import_target_module_id[import_i] = module_i;
    import_status[import_i] = IMPORT_STATUS_OK;
}
