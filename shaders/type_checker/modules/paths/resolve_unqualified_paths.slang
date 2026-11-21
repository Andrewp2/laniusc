// Resolve each unqualified path in its local namespace, then in the
// imported-public index. Dependency pages consume the published status.

import shared.buffers.gpu_index;
import type_checker.modules.decl_lookup;
import type_checker.modules.import_visible_lookup;

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
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_name_id;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> decl_lookup_state;

StructuredBuffer<uint> import_visible_count_out;
StructuredBuffer<uint> import_visible_key_module_id;
StructuredBuffer<uint> import_visible_key_name_id;
StructuredBuffer<uint> import_visible_key_to_decl_id;
StructuredBuffer<uint> import_visible_status;
StructuredBuffer<uint> import_visible_lookup_state;

RWStructuredBuffer<uint> resolved_decl;
RWStructuredBuffer<uint> resolved_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;
static const uint PATH_RECORD_KIND_HIR_BOUND_TYPE_EXPR = 5u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_SKIPPED = 1u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED = 2u;
static const uint PATH_RESOLVE_STATUS_INVALID_OWNER = 3u;
static const uint PATH_RESOLVE_STATUS_AMBIGUOUS = 4u;
static const uint IMPORT_VISIBLE_STATUS_OK = 0u;
static const uint IMPORT_VISIBLE_STATUS_AMBIGUOUS = 1u;
static const uint HIR_ITEM_NAMESPACE_VALUE = 2u;
static const uint HIR_ITEM_NAMESPACE_TYPE = 3u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.capacity);
}

DeclLookupResult find_decl(uint module_id, uint name_id)
{
    uint namespace_id = gParams.key_step == 0u
        ? HIR_ITEM_NAMESPACE_TYPE
        : HIR_ITEM_NAMESPACE_VALUE;
    return decl_lookup_query(
        module_id, namespace_id, name_id, DECL_LOOKUP_ANY_PARENT,
        min(decl_count_out[0], gParams.capacity),
        decl_module_id, decl_namespace, decl_name_id,
        decl_parent_type_decl, decl_lookup_state);
}

uint visible_capacity()
{
    return gParams.reserved == 0u ? gParams.capacity : gParams.reserved;
}

uint active_visible_count()
{
    return min(import_visible_count_out[0], visible_capacity());
}

uint find_visible_row(uint module_id, uint name_id)
{
    return import_visible_lookup_find(
        module_id,
        name_id,
        active_visible_count(),
        visible_capacity(),
        import_visible_key_module_id,
        import_visible_key_name_id,
        import_visible_key_to_decl_id,
        import_visible_lookup_state);
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
         path_kind[path_i] != PATH_RECORD_KIND_HIR_TYPE_EXPR &&
         path_kind[path_i] != PATH_RECORD_KIND_HIR_BOUND_TYPE_EXPR))
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
    DeclLookupResult found = find_decl(owner_module, name_id);
    if (found.matches != 0u)
    {
        resolved_decl[path_i] = found.unique();
        resolved_status[path_i] = found.matches == 1u
            ? PATH_RESOLVE_STATUS_OK : PATH_RESOLVE_STATUS_AMBIGUOUS;
        return;
    }

    uint row = find_visible_row(owner_module, name_id);
    uint visibility = row == INVALID ? INVALID : import_visible_status[row];
    if (visibility == IMPORT_VISIBLE_STATUS_OK)
    {
        resolved_decl[path_i] = import_visible_key_to_decl_id[row];
        resolved_status[path_i] = PATH_RESOLVE_STATUS_OK;
    }
    else
        resolved_status[path_i] = visibility == IMPORT_VISIBLE_STATUS_AMBIGUOUS
            ? PATH_RESOLVE_STATUS_AMBIGUOUS : PATH_RESOLVE_STATUS_UNRESOLVED;
}
