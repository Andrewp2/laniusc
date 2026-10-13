// GPU qualified path resolution for one namespace table.
//
// Scheduling contract:
// - Dispatch after the direct module table and sorted declaration namespace
//   lookup tables are materialized.
// - Multi-segment HIR path expressions resolve by indexing the prefix's exact
//   canonical id and then looking up the leaf in that module's declaration
//   table. Private declarations are visible only from the owning module.
//   Public cross-module declarations are visible only through an explicit
//   resolved import edge from the consuming module to the prefix module.
//   One-segment paths are handled by local/imported lookup passes.
// - It does not scan source bytes, perform CPU lookup, or apply same-source
//   shortcuts.

import gpu_index;
import type_checker.modules.qualified_type_parent;
import type_checker.modules.import_edge_set;
import type_checker.modules.decl_lookup;
import type_checker.modules.module_lookup;
import type_checker.modules.import_visible_lookup;

struct Params
{
    uint record_capacity;
    uint path_segment_capacity;
    uint module_capacity;
    uint reserved;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_token;
RWStructuredBuffer<uint4> resolved_value_qualifier_binding;

RWStructuredBuffer<uint> resolved_decl;
RWStructuredBuffer<uint> resolved_status;
RWStructuredBuffer<uint> resolved_value_type_qualifier_token;

public struct ImportEdgeStatusSource : IImportEdgeStatusSource
{
    public static uint status(uint row) { return import_status[row]; }
}

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;
static const uint PATH_RECORD_KIND_HIR_BOUND_TYPE_EXPR = 5u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_INVALID_OWNER = 3u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED_MODULE = 5u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED_DECL = 6u;
static const uint PATH_RESOLVE_STATUS_MISSING_IMPORT_EDGE = 7u;
static const uint HIR_ITEM_VIS_PUBLIC = 1u;
static const uint IMPORT_STATUS_OK = 0u;
static const uint HIR_ITEM_NAMESPACE_VALUE = 2u;
static const uint HIR_ITEM_NAMESPACE_TYPE = 3u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.record_capacity);
}

uint active_module_count()
{
    return min(module_count_out[0], gParams.module_capacity);
}

uint active_import_count()
{
    return min(import_count_out[0], gParams.record_capacity);
}

uint find_module_for_path_prefix(uint path_i, uint prefix_count)
{
    uint canonical_id = path_prefix_id[
        path_segment_base[path_i] + prefix_count - 1u];
    uint module_id = module_lookup_find(
        canonical_id,
        gParams.path_segment_capacity,
        module_by_canonical_id);
    return module_id < active_module_count() ? module_id : INVALID;
}

bool has_import_edge(uint importing_module, uint target_module)
{
    return import_edge_set_contains<ImportEdgeStatusSource>(
        importing_module,
        target_module,
        active_import_count(),
        import_module_id,
        import_target_module_id,
        import_edge_set_state);
}

uint find_decl_in_scope(uint module_id, uint namespace_id, uint name_id, uint parent)
{
    return decl_lookup_query(
        module_id, namespace_id, name_id, parent,
        min(decl_count_out[0], gParams.record_capacity),
        decl_module_id, decl_namespace, decl_name_id,
        decl_parent_type_decl, decl_lookup_state).unique();
}

uint find_decl(uint module_id, uint name_id)
{
    return find_decl_in_scope(module_id, gParams.reserved == 0u
        ? HIR_ITEM_NAMESPACE_TYPE : HIR_ITEM_NAMESPACE_VALUE,
        name_id, DECL_LOOKUP_ANY_PARENT);
}

bool decl_visible_from_path(uint path_i, uint decl_i)
{
    if (decl_i >= gParams.record_capacity)
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

uint find_qualified_variant(uint path_i, uint count)
{
    if (gParams.reserved == 0u || path_kind[path_i] != PATH_RECORD_KIND_HIR_PATH_EXPR)
        return INVALID;
    uint4 binding = resolved_value_qualifier_binding[path_i];
    if (binding.x == 3u)
    { resolved_status[path_i] = 4u; return INVALID; }
    if (binding.x != 1u) return INVALID;
    uint base = path_segment_base[path_i];
    uint parent = binding.y;
    if (parent >= min(decl_count_out[0u], gParams.record_capacity) ||
        decl_kind[parent] != 7u || !decl_visible_from_path(path_i, parent)) return INVALID;
    uint variant = find_decl_in_scope(decl_module_id[parent], HIR_ITEM_NAMESPACE_VALUE,
        path_segment_name_id[base + count - 1u], parent);
    return variant < gParams.record_capacity && decl_kind[variant] == 9u ? variant : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id(dtid);
    if (path_i >= active_path_count() ||
        (path_kind[path_i] != PATH_RECORD_KIND_HIR_PATH_EXPR &&
         path_kind[path_i] != PATH_RECORD_KIND_HIR_TYPE_EXPR &&
         path_kind[path_i] != PATH_RECORD_KIND_HIR_BOUND_TYPE_EXPR))
        return;

    // Bind the parent independently of whether its member is already known.
    // Dependency lookup has precedence rules across pages; only fill an empty
    // binding here for jobs with no matching dependency parent.
    uint count = path_segment_count[path_i];
    if (gParams.reserved != 0u && path_kind[path_i] == PATH_RECORD_KIND_HIR_PATH_EXPR &&
        count > 1u && resolved_value_qualifier_binding[path_i].x == 0u)
    {
        DeclLookupResult parent = qualified_local_type_parent(path_i, count - 1u);
        if (parent.matches != 0u)
            resolved_value_qualifier_binding[path_i] = parent.matches == 1u
                ? uint4(1u, parent.first, INVALID, INVALID)
                : uint4(3u, INVALID, INVALID, INVALID);
    }

    // Dependency pages resolve imported qualified paths before this local
    // module-table pass. Their stable identity must not be overwritten merely
    // because an imported module is absent from the current unit's module rows.
    if (resolved_status[path_i] == PATH_RESOLVE_STATUS_OK || resolved_status[path_i] == 4u)
        return;

    if (count <= 1u)
        return;
    uint module_i = find_module_for_path_prefix(path_i, count - 1u);
    if (module_i == INVALID)
    {
        uint variant = find_qualified_variant(path_i, count);
        if (resolved_status[path_i] == 4u) return;
        resolved_decl[path_i] = variant;
        resolved_status[path_i] = variant != INVALID
            ? PATH_RESOLVE_STATUS_OK : PATH_RESOLVE_STATUS_UNRESOLVED_MODULE;
        if (variant != INVALID)
            resolved_value_type_qualifier_token[path_i] =
                path_segment_token[path_segment_base[path_i] + count - 2u];
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
        resolved_status[path_i] = PATH_RESOLVE_STATUS_MISSING_IMPORT_EDGE;
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
