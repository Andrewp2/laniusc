// Imported match payloads materialize complete declaration-side patterns while
// their dependency page is resident. Only caller-side references survive to
// match binding; canonical row numbers never cross the page boundary.
#include "../type/instances/materialize_application_inputs.slang"
import type_checker.checked_pattern_path;
#include "../type/instances/materialize_application.slang"

StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<HirMatchPayload> compact_match_payloads;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<uint> resolved_dependency_library_id;
StructuredBuffer<uint> resolved_dependency_unit_id;
StructuredBuffer<uint> resolved_dependency_local_index;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
RWStructuredBuffer<uint> imported_match_payload_ref_tag;
RWStructuredBuffer<uint> imported_match_payload_ref_payload;
RWStructuredBuffer<uint> call_inference_state;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    if (row >= min(compact_match_payload_row_count[0u], gParams.n_hir_nodes)) return;
    HirMatchPayload value = compact_match_payloads[row];
    if (value.arm >= min(compact_match_arm_count[0u], gParams.n_hir_nodes) ||
        value.pattern >= hir_count() || value.parent_pattern >= hir_count()) return;
    HirMatchArm arm = compact_match_arms[value.arm];
    if (value.parent_pattern != arm.pattern || arm.owner >= hir_count()) return;
    uint path = checked_pattern_path(value.parent_pattern, hir_count(),
        min(path_count_out[0u], gParams.n_hir_nodes), compact_hir_links, path_id_by_owner_hir);
    if (path >= min(path_count_out[0u], gParams.n_hir_nodes)) return;
    uint variant = dependency_find_declaration(resolved_dependency_library_id[path],
        resolved_dependency_unit_id[path], resolved_dependency_local_index[path]);
    if (variant >= dependency_declaration_count() ||
        dependency_declaration_word(variant * 14u + 6u) != 9u) return;
    uint parent = dependency_declaration_word(variant * 14u + 10u);
    if (parent >= dependency_declaration_count()) return;
    uint scrutinee = compact_hir_payload[arm.owner].a;
    if (scrutinee >= hir_count() || call_inference_result_tag[scrutinee] != 3u) return;
    uint instance = call_inference_result_payload[scrutinee];
    if (instance >= mutable_type_capacity() || type_instance_kind[instance] != 1u ||
        external_type_library_id[instance] != dependency_declaration_library_id(parent) ||
        external_type_unit_id[instance] != dependency_declaration_unit_id(parent) ||
        external_type_local_index[instance] != dependency_declaration_local_index(parent)) return;
    uint signature = canonical_field_root(dependency_declaration_word(variant * 14u + 7u));
    if (signature == INVALID || dependency_type_word(signature * 9u) != 7u) return;
    uint start = dependency_type_word(signature * 9u + 3u);
    uint count = dependency_type_word(signature * 9u + 4u);
    uint edges = dependency_count(5u);
    if (count == 0u || value.ordinal >= count - 1u || start > edges || count > edges - start) return;
    uint pattern = dependency_type_edge_word(start + value.ordinal);
    uint prior_tag = imported_match_payload_ref_tag[value.pattern];
    uint prior = imported_match_payload_ref_payload[value.pattern];
    if (prior_tag == 3u && canonical_field_ref_matches<MutableCheckedTypeGraph>(instance,
        pattern, prior, mutable_type_capacity(), gParams.n_tokens)) return;
    uint created[DEPTH_LIMIT]; uint created_count = 0u; uint failure; uint2 result;
    if (!materialize<MutableCheckedTypeGraph>(uint3(5u, pattern, instance),
        created, created_count, result, failure))
    {
        if (failure == 1u || failure == 2u)
            record_min_token_error(status, compact_hir_core[value.pattern].token_start,
                6u, 0x474e0000u | failure);
        return;
    }
    imported_match_payload_ref_tag[value.pattern] = result.x;
    imported_match_payload_ref_payload[value.pattern] = result.y;
    if (!scoped_type_refs_equal<MutableCheckedTypeGraph>(prior_tag, prior, INVALID,
        result.x, result.y, INVALID, mutable_type_capacity(), gParams.n_tokens))
    { uint ignored; InterlockedAdd(call_inference_state[1u], 1u, ignored); }
}
