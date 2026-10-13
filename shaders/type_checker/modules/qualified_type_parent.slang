// Type qualifiers bind independently of member lookup. Local declarations and
// source-pack imports use the same exact scope rules before dependency lookup.
import type_checker.modules.decl_lookup;
import type_checker.modules.module_lookup;
import type_checker.modules.import_visible_lookup;
import type_checker.modules.import_edge_set;

public StructuredBuffer<uint> path_segment_base;
public StructuredBuffer<uint> path_segment_name_id;
public StructuredBuffer<uint> path_prefix_id;
public StructuredBuffer<uint> path_owner_module_id;
public StructuredBuffer<uint> module_count_out;
public StructuredBuffer<uint> module_by_canonical_id;
public StructuredBuffer<uint> import_count_out;
public StructuredBuffer<uint> import_status;
public StructuredBuffer<uint> import_module_id;
public StructuredBuffer<uint> import_target_module_id;
public StructuredBuffer<uint> import_edge_set_state;
public StructuredBuffer<uint> decl_count_out;
public StructuredBuffer<uint> decl_module_id;
public StructuredBuffer<uint> decl_namespace;
public StructuredBuffer<uint> decl_kind;
public StructuredBuffer<uint> decl_visibility;
public StructuredBuffer<uint> decl_name_id;
public StructuredBuffer<uint> decl_parent_type_decl;
public StructuredBuffer<uint> decl_lookup_state;
public StructuredBuffer<uint> import_visible_type_count_out;
public StructuredBuffer<uint> import_visible_type_key_module_id;
public StructuredBuffer<uint> import_visible_type_key_name_id;
public StructuredBuffer<uint> import_visible_type_key_to_decl_id;
public StructuredBuffer<uint> import_visible_type_lookup_state;
public StructuredBuffer<uint> import_visible_type_status;

public struct QualifierImportStatus : IImportEdgeStatusSource
{
    public static uint status(uint row) { return import_status[row]; }
}

public DeclLookupResult qualified_local_type_parent(uint path, uint prefix_count)
{
    DeclLookupResult result;
    result.first = 0xffffffffu; result.matches = 0u;
    if (prefix_count == 0u) return result;
    uint base = path_segment_base[path];
    uint name = path_segment_name_id[base + prefix_count - 1u];
    uint owner = path_owner_module_id[path];
    uint module = owner;
    uint capacity; uint stride;
    if (prefix_count > 1u)
    {
        module_by_canonical_id.GetDimensions(capacity, stride);
        uint canonical = path_prefix_id[base + prefix_count - 2u];
        if (canonical >= capacity) return result;
        module = module_lookup_decode(module_by_canonical_id[canonical]);
        if (module >= module_count_out[0u]) return result;
        if (module != owner && !import_edge_set_contains<QualifierImportStatus>(
            owner, module, import_count_out[0u], import_module_id,
            import_target_module_id, import_edge_set_state)) return result;
    }
    decl_module_id.GetDimensions(capacity, stride);
    result = decl_lookup_query(module, 3u, name, 0xffffffffu,
        min(decl_count_out[0u], capacity), decl_module_id, decl_namespace,
        decl_name_id, decl_parent_type_decl, decl_lookup_state);
    if (prefix_count == 1u && result.matches == 0u)
    {
        import_visible_type_key_module_id.GetDimensions(capacity, stride);
        uint row = import_visible_lookup_find(owner, name,
            min(import_visible_type_count_out[0u], capacity), capacity,
            import_visible_type_key_module_id, import_visible_type_key_name_id,
            import_visible_type_key_to_decl_id, import_visible_type_lookup_state);
        if (row != 0xffffffffu)
        {
            uint state = import_visible_type_status[row];
            result.matches = state == 0u ? 1u : state == 1u ? 2u : 0u;
            result.first = import_visible_type_key_to_decl_id[row];
        }
    }
    if (result.matches == 1u && decl_module_id[result.first] != owner &&
        decl_visibility[result.first] != 1u)
    { result.first = 0xffffffffu; result.matches = 0u; }
    return result;
}
