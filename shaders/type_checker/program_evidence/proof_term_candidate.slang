import primitive_types;
import constant_value;
// Validator-only view of a completely emitted term wave. Initialization must
// already admit the store layout, then count/reserve/emit must finish before a
// compute-pass barrier. Node/edge rows and all directory counts stay frozen
// until the entire wave passes validation. This view never advances admission.
// Ordinary graph, matcher and proof-child consumers remain admitted-only.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_term_normalization;

// The candidate namespace includes the immutable admitted prefix and this
// stage's reserved suffix. No other persistent table acquires pending reads.
public bool pps_term_candidate_count(uint table, out uint count)
{
    count = 0u; uint4 span; uint accepted;
    if ((table != PPS_TERM_NODES && table != PPS_TERM_EDGES) || !pps_building() ||
        !pps_descriptor(table, span, accepted)) return false;
    count = span.y; return true;
}
public bool pps_term_candidate_span(uint table, uint first, uint count)
{
    uint rows;
    return pps_term_candidate_count(table, rows) && first <= rows && count <= rows - first;
}
public bool pps_term_candidate_type_reference(uint2 reference)
{
    if (reference.y == PEV_INVALID) return false;
    if (reference.x == 1u) return pev_scalar_is_valid(reference.y);
    if (reference.x == 2u) return pev_admitted_parameter_has_domain(reference.y, false);
    uint4 low; uint4 high;
    return reference.x == 3u && pps_read_term_candidate_node(reference.y, low, high) &&
        low.x >= 1u && low.x <= 4u;
}
public bool pps_term_candidate_constant_reference(uint2 reference)
{
    if (reference.y == PEV_INVALID) return false;
    if (reference.x == 0x80000002u) return pev_admitted_parameter_has_domain(reference.y, true);
    uint4 low; uint4 high;
    if (!pps_read_term_candidate_node(reference.y, low, high)) return false;
    return (reference.x == 0x80000001u && low.x == 6u) ||
        (reference.x == 0x80000003u && low.x == 5u);
}
public bool pps_read_term_candidate_node(uint row, out uint4 low, out uint4 high)
{
    low = uint4(PEV_INVALID, PEV_INVALID, PEV_INVALID, PEV_INVALID); high = low;
    uint reserved; uint admitted;
    if (!pps_term_candidate_count(PPS_TERM_NODES, reserved) || row >= reserved ||
        !pps_count(PPS_TERM_NODES, admitted)) return false;
    bool read = row < admitted ? pps_read8(PPS_TERM_NODES, row, low, high) :
        pps_read_pending8(PPS_TERM_NODES, row, low, high);
    if (!read || low.x < 1u || low.x > 6u) return false;
    if (low.x == 1u)
        return low.w <= 32u && (low.w != 0u || low.z == 0u) &&
            all(high == uint4(0u, 0u, 0u, 0u)) &&
            pps_term_candidate_span(PPS_TERM_EDGES, low.z, low.w);
    if (low.x == 6u) return constant_value_is_valid(low.yzw) && all(high == uint4(0u, 0u, 0u, 0u));
    if (low.x == 5u) return scalar_is_integer(low.y) && all(low.zw == uint2(0u, 0u)) &&
        all(high.zw == uint2(0u, 0u)) && high.x >= 0x80000001u && high.x <= 0x80000003u && high.y != PEV_INVALID;
    // Normalization writes a canonical header and only declared child slots.
    return all(low.yzw == uint3(0u, 0u, 0u)) &&
        (low.x == 2u || all(high.zw == uint2(0u, 0u)));
}
public bool pps_read_term_candidate_edge(uint row, out uint2 reference)
{
    reference = uint2(0u, PEV_INVALID); uint reserved; uint admitted;
    if (!pps_term_candidate_count(PPS_TERM_EDGES, reserved) || row >= reserved ||
        !pps_count(PPS_TERM_EDGES, admitted)) return false;
    return row < admitted ? pps_read2(PPS_TERM_EDGES, row, 0u, reference) :
        pps_read_pending2(PPS_TERM_EDGES, row, 0u, reference);
}

// Deliberately has no IConstraintMatchGraph or equality/hash capability. A
// pending term can be traversed for admission, never offered as proof evidence.
public struct CandidateProofTermGraph : IProofNormalizationGraph
{
    public static bool constant_value(uint row, out uint3 value)
    {
        value = uint3(0u, 0u, 0u); uint4 low; uint4 high;
        if (!pps_read_term_candidate_node(row, low, high) || low.x != 6u) return false;
        value = low.yzw; return true;
    }
    public static bool node(uint row, out uint4 low, out uint4 high)
    { return pps_read_term_candidate_node(row, low, high); }
    public static bool child(uint4 low, uint4 high, uint slot,
        out uint2 reference, out uint domain)
    {
        reference = uint2(0u, PEV_INVALID); domain = PEV_ADMITTED_DOMAIN_TYPE;
        if (low.x == 1u)
        {
            domain = PEV_ADMITTED_DOMAIN_EITHER;
            return low.w <= 32u && slot < low.w &&
                pps_term_candidate_span(PPS_TERM_EDGES, low.z, low.w) &&
                pps_read_term_candidate_edge(low.z + slot, reference);
        }
        if (low.x == 5u && slot == 0u)
        { domain = PEV_ADMITTED_DOMAIN_CONSTANT; reference = high.xy; return pps_term_candidate_constant_reference(reference); }
        if (low.x == 2u && slot == 1u)
        {
            domain = PEV_ADMITTED_DOMAIN_CONSTANT; reference = high.zw;
            return pps_term_candidate_constant_reference(reference);
        }
        if (low.x >= 2u && low.x <= 4u && slot == 0u)
        {
            reference = high.xy; return pps_term_candidate_type_reference(reference);
        }
        return false;
    }
}
