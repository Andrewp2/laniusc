// Admission is a complete graph validation and work bound, not a second solver.
import type_checker.program_evidence.graph_admission;
import type_checker.program_evidence.abi;
import type_checker.program_evidence.packed_graph;
import type_checker.scoped_type_equality;
import type_checker.scoped_type_hash;

public EvidenceStatus pev_admit_environment(
    uint environment, uint expected_owner, uint caller_owner, uint form)
{
    EvidenceStatus status = pev_admit_environment_header(environment, expected_owner, form);
    if (status.state != PEV_VALID) return status;
    uint4 env;
    if (!pev_environment_header(environment, env)) return pev_invalid(1u, environment, PEV_INVALID);
    for (uint index = 0u; index < env.z; index++)
    {
        uint root;
        if (!pev_word(12u, env.y + index, 2u, root)) return pev_invalid(1u, environment, index);
        uint visits;
        // Even parameters unused by a predicate must have admitted values.
        // A concrete body environment requires closed roots; call bindings may
        // retain exact parameters of the actual caller's lexical owner chain.
        status = pev_admit_root(root, PEV_INVALID, caller_owner, form == 0u, visits);
        if (status.state != PEV_VALID) return status;
    }
    return pev_ok();
}

// Caller must first admit each supplied environment with its exact target owner
// and caller scope. An INVALID environment is the original symbolic context.
// Each root has an independent budget; 32 operands do not share one 64-node cap.
public EvidenceStatus pev_hash_root(
    uint root, uint environment, uint visible_owner, bool require_closed, out uint hash)
{
    hash = 0u;
    uint visits;
    EvidenceStatus status = pev_admit_root(root, environment, visible_owner, require_closed, visits);
    if (status.state != PEV_VALID) return status;
    uint2 reference; uint nodes; uint atoms;
    if (!pev_read_root(root, reference) || !pev_table_count(5u, nodes) || !pev_table_count(1u, atoms))
        return pev_invalid(1u, root, PEV_INVALID);
    if (!scoped_type_ref_hash<ProgramEvidenceTypeGraph>(
        reference.x, reference.y, environment, nodes, atoms, hash))
        return pev_invalid(15u, root, PEV_INVALID);
    return pev_ok();
}

public EvidenceStatus pev_equal_roots(
    uint left_root, uint left_environment, uint left_visible_owner, bool left_closed,
    uint right_root, uint right_environment, uint right_visible_owner, bool right_closed,
    out bool equal)
{
    equal = false;
    uint visits;
    EvidenceStatus status = pev_admit_root(
        left_root, left_environment, left_visible_owner, left_closed, visits);
    if (status.state != PEV_VALID) return status;
    status = pev_admit_root(right_root, right_environment, right_visible_owner, right_closed, visits);
    if (status.state != PEV_VALID) return status;
    uint2 left; uint2 right; uint nodes; uint atoms;
    if (!pev_read_root(left_root, left) || !pev_read_root(right_root, right) ||
        !pev_table_count(5u, nodes) || !pev_table_count(1u, atoms))
        return pev_invalid(1u, left_root, right_root);
    equal = scoped_type_refs_equal<ProgramEvidenceTypeGraph>(
        left.x, left.y, left_environment, right.x, right.y, right_environment, nodes, atoms);
    // Preflight proved both complete input graphs well formed, bounded and
    // fully substitutable. A false shared comparison here means valid inequality.
    return pev_ok();
}
