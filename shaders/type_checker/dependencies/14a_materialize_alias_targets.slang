import type_checker.dependencies.constant_view;
#include "../type/instances/materialize_application_inputs.slang"
#include "../type/instances/materialize_application.slang"

StructuredBuffer<uint> path_kind;
StructuredBuffer<uint4> resolved_value_qualifier_binding;
StructuredBuffer<uint> resolved_dependency_library_id;
StructuredBuffer<uint> resolved_dependency_unit_id;
StructuredBuffer<uint> resolved_dependency_local_index;
RWStructuredBuffer<uint2> imported_type_alias_target;

// Each page contributes caller-owned target graphs. The source application
// stays immutable until every page has contributed; a later normalization
// follows nested alias targets without depending on dependency page order.
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path = dtid.x + dtid.y * 16776960u;
    if (path >= min(path_count_out[0u], gParams.n_hir_nodes)) return;
    uint count = path_segment_count[path];
    uint4 parent = resolved_value_qualifier_binding[path];
    bool qualified_value = path_kind[path] == 3u && count >= 2u && parent.x == 2u;
    if (count == 0u || (path_kind[path] != 4u && !qualified_value)) return;
    uint leaf = path_segment_token[path_segment_base[path] + count - (qualified_value ? 2u : 1u)];
    if (leaf >= gParams.n_tokens || type_instance_kind[leaf] != 1u || type_instance_state[leaf] != 1u) return;
    uint declaration = qualified_value
        ? dependency_find_declaration(parent.y, parent.z, parent.w)
        : dependency_find_declaration(resolved_dependency_library_id[path],
            resolved_dependency_unit_id[path], resolved_dependency_local_index[path]);
    if (declaration == INVALID || dependency_declaration_word(declaration * 14u + 6u) != 8u) return;
    uint signature = dependency_declaration_word(declaration * 14u + 7u);
    uint created[DEPTH_LIMIT]; uint created_count = 0u;
    uint2 result; uint failure;
    if (!materialize<MutableCheckedTypeGraph>(uint3(5u, signature, leaf), created, created_count,
        result, failure))
    {
        record_min_token_error(status, leaf, 6u, 0x41490000u | failure);
        return;
    }
    imported_type_alias_target[leaf] = result;
}
