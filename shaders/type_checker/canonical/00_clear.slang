// Reset canonical interning for one type-check job (docs/canonical-type-ids.md).
// One lane per hash slot; candidate and counter resets share the lanes.
import type_checker.canonical.canonical_api;

// The type-check params prefix through the job's unit identity.
struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
    uint parser_feature_flags;
    uint dependency_interfaces_present;
    uint retain_callable_owners;
    uint trait_obligation_mode;
    uint authorized_replay_callable;
    uint canonical_library_id;
    uint canonical_unit_id;
};
ConstantBuffer<Params> gParams;

// Debug validation counters (88_validate_table, 90_validate); cleared so a
// job's validation starts from zero whether or not a validator is recorded.
RWStructuredBuffer<uint> canonical_validation;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * 16776960u;
    if (i < ct_slot_capacity()) ct_slot[i] = 0u;
    if (i < ct_row_capacity()) canonical_row[i] = CT_PENDING;
    if (i < ct_atom_capacity()) canonical_atom[i] = CT_PENDING;
    if (i < ct_projection_capacity()) canonical_projection[i] = CT_PENDING;
    if (i < ct_dependency_capacity()) canonical_dependency_type[i] = CT_PENDING;
    uint count; uint stride;
    canonical_validation.GetDimensions(count, stride);
    if (i < count) canonical_validation[i] = 0u;
    if (i < CT_COUNT_WORDS)
    {
        uint value = 0u;
        if (i == CT_COUNT_NEXT_RECORD) value = CT_FIRST_RECORD;
        if (i == CT_COUNT_PENDING) value = ct_candidate_count();
        if (i == CT_COUNT_LIBRARY) value = gParams.canonical_library_id;
        if (i == CT_COUNT_UNIT) value = gParams.canonical_unit_id;
        ct_counts[i] = value;
    }
}
