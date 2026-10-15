// Imported match payloads: the variant's declared payload type under the
// scrutinee's nominal environment, substituted over canonical IDs while the
// dependency page is resident and realized as a caller-side checked row.
// Canonical row numbers never cross the page boundary.
import hir_records;
import status;
import dependency_interface;
import type_checker.checked_pattern_path;
import type_checker.mutable_checked_type_graph;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_dependency;
import type_checker.substitution.ct_subst;
import type_checker.substitution.ct_rows;
import type_checker.substitution.ct_realize;
import type_checker.substitution.source_slots;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<HirMatchPayload> compact_match_payloads;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<uint> resolved_dependency_value_library_id;
StructuredBuffer<uint> resolved_dependency_value_unit_id;
StructuredBuffer<uint> resolved_dependency_value_local_index;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
RWStructuredBuffer<uint> imported_match_payload_ref_tag;
RWStructuredBuffer<uint> imported_match_payload_ref_payload;
RWStructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

uint hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }

#include "../checked_referent.slang"

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
    uint variant = dependency_find_declaration(resolved_dependency_value_library_id[path],
        resolved_dependency_value_unit_id[path], resolved_dependency_value_local_index[path]);
    if (variant >= dependency_declaration_count() ||
        dependency_declaration_word(variant * 14u + 6u) != 9u) return;
    uint parent = dependency_declaration_word(variant * 14u + 10u);
    if (parent >= dependency_declaration_count()) return;
    uint scrutinee = compact_hir_payload[arm.owner].a;
    if (scrutinee >= hir_count()) return;
    uint tag = call_inference_result_tag[scrutinee];
    uint instance = call_inference_result_payload[scrutinee];
    uint reference_depth;
    if (!checked_referent_reference(tag, instance, reference_depth) || tag != 3u ||
        instance >= mutable_type_capacity() || type_instance_kind[instance] != 1u ||
        external_type_library_id[instance] != dependency_declaration_library_id(parent) ||
        external_type_unit_id[instance] != dependency_declaration_unit_id(parent) ||
        external_type_local_index[instance] != dependency_declaration_local_index(parent)) return;
    uint types = dependency_type_count();
    uint signature = dependency_declaration_word(variant * 14u + 7u);
    signature = signature < types ? canonical_type_roots[signature] : INVALID;
    if (signature >= types || dependency_type_word(signature * 9u) != 7u) return;
    uint start = dependency_type_word(signature * 9u + 3u);
    uint count = dependency_type_word(signature * 9u + 4u);
    uint edges = dependency_count(5u);
    if (count == 0u || value.ordinal >= count - 1u || start > edges || count > edges - start) return;
    // The scrutinee's application is the environment: type slot i is its
    // i-th type operand.
    uint environment = ct_ref(3u, instance);
    uint pattern = ct_dependency_state(dependency_type_edge_word(start + value.ordinal));
    if (!ct_is_record(environment) || !ct_is_resolved(pattern)) return;
    CtSpare spare = ct_spare_none();
    uint payload_type = ct_subst(SourceSlots(), environment, pattern, true, spare);
    uint failure = 0u;
    uint2 result = uint2(0u, INVALID);
    if (ct_is_resolved(payload_type)) result = ct_realize(payload_type, failure);
    else if ((ct_subst_counts[CT_SUBST_COUNT_OVERFLOW] & ~CT_SUBST_OVERFLOW_WORK) != 0u ||
        ct_counts[CT_COUNT_OVERFLOW] != 0u) failure = CT_REALIZE_CAPACITY;
    else if (ct_subst_counts[CT_SUBST_COUNT_OVERFLOW] != 0u) failure = CT_REALIZE_LIMIT;
    if (result.x == 0u)
    {
        if (failure == CT_REALIZE_CAPACITY || failure == CT_REALIZE_LIMIT)
            record_min_token_error(status, compact_hir_core[value.pattern].token_start,
                6u, 0x474e0000u | failure);
        // Another lane is writing the row: look again next round.
        if (failure == CT_REALIZE_BUSY) { uint ignored; InterlockedAdd(call_inference_state[1u], 1u, ignored); }
        return;
    }
    uint prior_tag = imported_match_payload_ref_tag[value.pattern];
    uint prior = imported_match_payload_ref_payload[value.pattern];
    if (prior_tag == result.x && prior == result.y) return;
    imported_match_payload_ref_tag[value.pattern] = result.x;
    imported_match_payload_ref_payload[value.pattern] = result.y;
    // Rows are unique per ID; another producer's row compares by its ID.
    if (ct_ref(prior_tag, prior) != payload_type)
    { uint ignored; InterlockedAdd(call_inference_state[1u], 1u, ignored); }
}
