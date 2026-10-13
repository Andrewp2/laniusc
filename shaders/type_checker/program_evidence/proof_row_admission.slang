import type_checker.program_evidence.constant_atoms;
// Reverse ownership checks cover every pending Binding and ProofEdge, including
// rows unreachable from successful roots. Owning substitutions/proofs receive
// their complete semantic validators in the same frozen wave before commit.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_term_graph;
import type_checker.program_evidence.proof_term_candidate;
import type_checker.program_evidence.proof_binding_materialization;

public EvidenceStatus pps_admit_binding_row(uint binding)
{
    uint4 bindings; uint4 substitutions; uint accepted;
    if (!pps_building() || !pps_descriptor(PPS_BINDINGS, bindings, accepted) ||
        !pps_descriptor(PPS_SUBSTITUTIONS, substitutions, accepted) || binding >= bindings.y)
        return pev_invalid(68u, binding, PPS_BINDINGS);
    uint4 row; uint4 allocation; uint4 owner;
    bool read = binding < bindings.w ? pps_read8(PPS_BINDINGS, binding, row, allocation) :
        pps_read_pending8(PPS_BINDINGS, binding, row, allocation);
    if (!read || !pps_binding_node_span(allocation, binding >= bindings.w) || row.x >= substitutions.y ||
        (binding >= bindings.w && row.x < substitutions.w))
        return pev_invalid(68u, binding, PPS_SUBSTITUTIONS);
    read = row.x < substitutions.w ? pps_read4(PPS_SUBSTITUTIONS, row.x, 0u, owner) :
        pps_read_pending4(PPS_SUBSTITUTIONS, row.x, 0u, owner);
    uint4 parameter;
    if (!read || owner.z > 64u || owner.y > bindings.y || owner.z > bindings.y - owner.y ||
        binding < owner.y || binding - owner.y >= owner.z ||
        !pev_read_admitted_parameter(row.y, parameter))
        return pev_invalid(68u, binding, row.x);
    uint scalar = 0u;
    if (allocation.y == 0u)
    {
        if (!(parameter.z == 0u ? pps_type_reference(row.zw) : pps_constant_reference(row.zw)))
            return pev_invalid(68u, binding, row.x);
        if (parameter.z == 1u) scalar = pps_constant_reference_scalar(row.zw);
    }
    else
    {
        uint4 low; uint4 high;
        if (parameter.z != 1u || row.w != allocation.x ||
            !pps_read_term_candidate_node(row.w, low, high) ||
            !((row.z == 0x80000001u && low.x == 6u) || (row.z == 0x80000003u && low.x == 5u)))
            return pev_invalid(68u, binding, row.x);
        scalar = low.y;
    }
    if (parameter.z == 1u && scalar != pev_constant_parameter_scalar(row.y))
        return pev_invalid(68u, binding, row.y);
    return pev_ok();
}

public EvidenceStatus pps_admit_proof_edge_row(uint edge)
{
    uint4 edges; uint4 proofs; uint accepted;
    if (!pps_building() || !pps_descriptor(PPS_PROOF_EDGES, edges, accepted) ||
        !pps_descriptor(PPS_PROOFS, proofs, accepted) || edge >= edges.y)
        return pev_invalid(68u, edge, PPS_PROOF_EDGES);
    uint4 row; uint4 parent; uint4 extra;
    bool read = edge < edges.w ? pps_read4(PPS_PROOF_EDGES, edge, 0u, row) :
        pps_read_pending4(PPS_PROOF_EDGES, edge, 0u, row);
    if (!read || row.w != 0u || row.x >= proofs.y || row.z >= row.x || row.z >= proofs.w ||
        (edge >= edges.w && row.x < proofs.w))
        return pev_invalid(68u, edge, PPS_PROOFS);
    read = row.x < proofs.w ? pps_read8(PPS_PROOFS, row.x, parent, extra) :
        pps_read_pending8(PPS_PROOFS, row.x, parent, extra);
    if (!read || parent.x != 1u || extra.y > edges.y || extra.z > edges.y - extra.y ||
        edge < extra.y || edge - extra.y >= extra.z)
        return pev_invalid(68u, edge, row.x);
    uint4 prerequisites; uint4 child; uint4 child_extra;
    if (!pev_read4(9u, parent.w, 8u, prerequisites) || extra.z != prerequisites.y ||
        edge - extra.y >= prerequisites.y || row.y != prerequisites.x + (edge - extra.y) ||
        !pps_read8(PPS_PROOFS, row.z, child, child_extra) || child.z != parent.z)
        return pev_invalid(68u, edge, row.x);
    // Exact prerequisite goal and propagated classification are checked by the
    // owning proof validator, using its already-fixed complete head bindings.
    return pev_ok();
}
