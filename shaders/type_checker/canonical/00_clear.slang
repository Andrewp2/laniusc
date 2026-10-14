// Reset canonical interning state for one type-check job. One lane per hash
// slot; row, atom and record clears share the same lanes.
import type_checker.canonical.canonical_types;
import type_checker.checked_type_graph;
import type_checker.constant_atoms;
import constant_value;
import primitive_types;

// Debug validation counters (90_validate); cleared here so every job's
// validation starts from zero whether or not the validator is recorded.
RWStructuredBuffer<uint> canonical_validation;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * 16776960u;
    if (i < canonical_slot_capacity()) canonical_ct_slot[i] = 0u;
    uint count; uint stride;
    canonical_row.GetDimensions(count, stride);
    if (i < count) canonical_row[i] = CANON_PENDING;
    canonical_atom.GetDimensions(count, stride);
    if (i < count) canonical_atom[i] = CANON_PENDING;
    canonical_cand_state.GetDimensions(count, stride);
    if (i < count) canonical_cand_state[i] = CAND_IDLE;
    if (i < canonical_record_capacity())
    {
        // Scalar codes are their own canonical IDs.
        bool scalar = i >= 1u && i <= SCALAR_USIZE;
        canonical_ct_key_a[i] = scalar ? uint4(CT_SCALAR, i, 0u, 0u) : uint4(0u, 0u, 0u, 0u);
        canonical_ct_key_b[i] = uint4(0u, 0u, 0u, 0u);
        canonical_ct_rep[i] = 0xffffffffu;
    }
    canonical_validation.GetDimensions(count, stride);
    if (i < count) canonical_validation[i] = 0u;
    if (i == 0u)
    {
        canonical_counts[0u] = CANON_FIRST_DYNAMIC;
        canonical_counts[1u] = 0u;
        canonical_counts[2u] = 0u;
        canonical_counts[3u] = 0u;
    }
}
