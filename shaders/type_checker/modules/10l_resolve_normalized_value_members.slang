// A type qualifier owns a complete checked application. Resolve its enum
// member after normalization so aliases can change identity and operands.
// Scope/ambiguity belongs to the earlier stable parent binding.
import type_checker.modules.decl_lookup;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_segment_name_id;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> path_owner_module_id;
StructuredBuffer<uint4> resolved_value_qualifier_binding;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_name_id;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> decl_lookup_state;
StructuredBuffer<uint> decl_visibility;
RWStructuredBuffer<uint> resolved_value_decl;
RWStructuredBuffer<uint> resolved_value_status;
RWStructuredBuffer<uint> resolved_value_type_qualifier_token;
RWStructuredBuffer<uint> module_value_path_status;
static const uint INVALID = 0xffffffffu;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path = dtid.x + dtid.y * 16776960u;
    if (path >= min(path_count_out[0u], gParams.n_hir_nodes) || path_kind[path] != 3u ||
        path_segment_count[path] < 2u || resolved_value_qualifier_binding[path].x != 1u ||
        resolved_value_status[path] == 0u || resolved_value_status[path] == 4u) return;
    uint last = path_segment_base[path] + path_segment_count[path] - 1u;
    uint qualifier = path_segment_token[last - 1u];
    if (qualifier >= gParams.n_tokens || type_expr_ref_tag[qualifier] != 3u) return;
    uint instance = type_expr_ref_payload[qualifier];
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    if (instance >= capacity || type_instance_kind[instance] != 1u) return;
    uint token = type_instance_decl_token[instance];
    if (token >= gParams.n_tokens) return;
    uint parent = decl_id_by_name_token[token];
    uint count = min(decl_count_out[0u], gParams.n_hir_nodes);
    if (parent >= count || decl_kind[parent] != 7u) return;
    DeclLookupResult members = decl_lookup_query(decl_module_id[parent], 2u,
        path_segment_name_id[last], parent, count, decl_module_id, decl_namespace,
        decl_name_id, decl_parent_type_decl, decl_lookup_state);
    uint member = members.unique();
    if (member >= count || decl_kind[member] != 9u ||
        (decl_module_id[member] != path_owner_module_id[path] && decl_visibility[member] != 1u)) return;
    resolved_value_decl[path] = member;
    resolved_value_status[path] = 0u;
    resolved_value_type_qualifier_token[path] = qualifier;
    uint owner = path_owner_token[path];
    if (owner < gParams.n_tokens) module_value_path_status[owner] = 0u;
}
