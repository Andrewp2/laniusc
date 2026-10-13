// Static source capabilities keep original-call and prerequisite normalization
// in separate shader entry call graphs. The common stage has no runtime branch
// into both complete structural walkers.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.proof_term_graph;
import type_checker.program_evidence.proof_term_normalization;
import type_checker.program_evidence.proof_normalization_admission;

public interface IWorkNormalizationSource
{
    static uint kind();
    static EvidenceStatus transform(uint2 input, uint environment, uint owner, uint domain,
        bool emit, ProofNormalizationReservation reservation, out uint2 normalized,
        out bool closed, out ProofNormalizationCounts measured);
    static EvidenceStatus validate(uint input_root, uint environment, uint owner, uint domain,
        ProofNormalizationReservation reservation, uint2 expected_root, out bool closed);
}
public struct OriginalWorkNormalizationSource : IWorkNormalizationSource
{
    public static uint kind() { return 0u; }
    public static EvidenceStatus transform(uint2 input, uint environment, uint owner, uint domain,
        bool emit, ProofNormalizationReservation reservation, out uint2 normalized,
        out bool closed, out ProofNormalizationCounts measured)
    {
        return pev_normalize_proof_root<InputProofNormalizationGraph,
            InputProofNormalizationGraph, InputProofNormalizationBindings,
            SolverProofTermSink>(input, environment, owner, domain, emit, reservation,
                normalized, closed, measured);
    }
    public static EvidenceStatus validate(uint input_root, uint environment, uint owner, uint domain,
        ProofNormalizationReservation reservation, uint2 expected_root, out bool closed)
    {
        return pps_validate_original_normalization(input_root, environment, owner,
            domain, reservation, expected_root, closed);
    }
}
public struct PrerequisiteWorkNormalizationSource : IWorkNormalizationSource
{
    public static uint kind() { return 1u; }
    public static EvidenceStatus transform(uint2 input, uint substitution, uint owner, uint domain,
        bool emit, ProofNormalizationReservation reservation, out uint2 normalized,
        out bool closed, out ProofNormalizationCounts measured)
    {
        return pev_normalize_proof_root<InputProofNormalizationGraph,
            SolverProofTermGraph, SolverProofBindings, SolverProofTermSink>(
                input, substitution, owner, domain, emit, reservation, normalized, closed, measured);
    }
    public static EvidenceStatus validate(uint input_root, uint substitution, uint owner, uint domain,
        ProofNormalizationReservation reservation, uint2 expected_root, out bool closed)
    {
        return pps_validate_prerequisite_normalization(input_root, substitution,
            owner, domain, reservation, expected_root, closed);
    }
}
