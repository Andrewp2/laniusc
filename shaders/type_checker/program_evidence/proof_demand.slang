// Exact row demand of the next normalization, counted before it reserves
// anything. The host reads it with the solver's counter readback that
// precedes the normalization and grows the proof store in place first
// (dispatch/mod.rs, run_solver_attempt), so the reservations never fail for
// capacity. One word per proof-store table; the host zeroes it per count.
import type_checker.program_evidence.proof_store_abi;

public RWStructuredBuffer<uint> program_evidence_proof_demand;

public void pps_add_demand(uint table, uint count)
{
    if (count != 0u && table < PPS_TABLES)
        InterlockedAdd(program_evidence_proof_demand[table], count);
}

// The five reservations of one Work's normalization (pps_emit_normalization).
public void pps_add_normalization_demand(uint nodes, uint edges, uint roots)
{
    pps_add_demand(PPS_TERM_NODES, nodes);
    pps_add_demand(PPS_TERM_EDGES, edges);
    pps_add_demand(PPS_TERM_ROOTS, roots);
    pps_add_demand(PPS_NORMALIZATION_REQUESTS, roots);
    pps_add_demand(PPS_GOALS, 1u);
}
