// Recheck the exact source-to-owned-term transform using the same traversal as
// counting and emission. This sink never writes. It validates the unpublished
// reservation, including every child and reserved field, before any normalized
// root can participate in goal equality or support a proof.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_term_graph;
import type_checker.program_evidence.proof_term_normalization;

public struct SolverProofNormalizationCheckSink : IProofNormalizationSink
{
    public static bool begin_node(uint mode, uint row, uint4 expected_low, uint4 unused_high)
    {
        uint4 low; uint4 high;
        if (!pps_read_pending8(PPS_TERM_NODES, row, low, high) ||
            any(low != expected_low)) return false;
        // The emitter initially cleared children, then filled them. Compare
        // filled child slots individually below; all nonchild slots stay zero.
        return (low.x == 1u || low.x == 6u) ? all(high == uint4(0u, 0u, 0u, 0u)) :
            (low.x == 2u || (high.z == 0u && high.w == 0u));
    }
    public static bool set_child(uint mode, uint row, uint ordinal, uint2 expected)
    {
        uint4 low; uint4 high;
        if (!pps_read_pending8(PPS_TERM_NODES, row, low, high)) return false;
        if (low.x == 1u)
        {
            if (low.w > 32u || ordinal >= low.w || low.z > PEV_INVALID - ordinal)
                return false;
            uint address;
            if (!pps_address(PPS_TERM_EDGES, low.z + ordinal, 0u, 2u, true, address))
                return false;
            return program_evidence_proof_store[address] == expected.x &&
                program_evidence_proof_store[address + 1u] == expected.y;
        }
        if (low.x < 2u || low.x > 5u || ordinal > (low.x == 2u ? 1u : 0u))
            return false;
        return all((ordinal == 0u ? high.xy : high.zw) == expected);
    }
}

// Required order: complete source/environment admission; count; disjoint
// reservation; emit; barrier; this exact-transform check; candidate graph row
// admission; barrier; advance term/edge admitted prefixes. Reservation and
// source inputs are immutable throughout. No root is published by this helper.
// The caller must derive source/environment/owner/domain from the admitted
// obligation or implementation prerequisite, never from an untrusted request's
// self-asserted provenance. Exact request ownership is a separate stage gate.
public EvidenceStatus pps_validate_original_normalization(
    uint input_root, uint environment, uint owner, uint domain,
    ProofNormalizationReservation reservation, uint2 expected_root,
    out bool closed)
{
    closed = false; uint2 source; uint2 normalized; ProofNormalizationCounts counts;
    if (!pev_read_root(input_root, source)) return pev_invalid(1u, input_root, PEV_INVALID);
    EvidenceStatus status = pev_normalize_proof_root<
        SameProofNormalizationGraph<InputProofNormalizationGraph>, InputProofNormalizationBindings,
        SolverProofNormalizationCheckSink>(source, environment, owner, domain,
            true, reservation, normalized, closed, counts);
    if (status.state != PEV_VALID) return status;
    if (any(normalized != expected_root)) return pev_invalid(65u, input_root, expected_root.y);
    return pev_ok();
}

public EvidenceStatus pps_validate_prerequisite_normalization(
    uint input_root, uint substitution, uint caller_owner, uint domain,
    ProofNormalizationReservation reservation, uint2 expected_root,
    out bool closed)
{
    closed = false; uint2 source; uint2 normalized; ProofNormalizationCounts counts;
    if (!pev_read_root(input_root, source)) return pev_invalid(1u, input_root, PEV_INVALID);
    EvidenceStatus status = pev_normalize_proof_root<
        SplitProofNormalizationGraphs<InputProofNormalizationGraph, SolverProofTermGraph>,
        SolverProofBindings, SolverProofNormalizationCheckSink>(
            source, substitution, caller_owner, domain, true, reservation,
            normalized, closed, counts);
    if (status.state != PEV_VALID) return status;
    if (any(normalized != expected_root)) return pev_invalid(65u, input_root, expected_root.y);
    return pev_ok();
}
