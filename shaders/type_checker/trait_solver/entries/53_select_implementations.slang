import type_checker.trait_solver.abi;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_frontier_selection;
import type_checker.trait_solver.proof_frontier_stages;

// Exact implementation match (phase 53) or generic match (phase 65).
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 thread_id : SV_DispatchThreadID)
{
    uint phase = proof_store_params.phase;
    if (trait_solver_params.phase != phase ||
        (phase != PPS_SELECT_PHASE_EXACT && phase != PPS_SELECT_PHASE_GENERIC)) return;
    pps_stage_select_implementations(thread_id.x, phase == PPS_SELECT_PHASE_GENERIC);
}
