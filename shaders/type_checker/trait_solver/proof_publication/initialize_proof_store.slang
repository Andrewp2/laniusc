import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_publication.proof_store_lifecycle;

// One workgroup initializes the store (pps_initialize_store_group).
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 lane : SV_GroupThreadID, uint3 group : SV_GroupID)
{
    if (trait_solver_params.phase != 40u || proof_store_params.phase != 40u) return;
    if (any(group != uint3(0u, 0u, 0u)) ||
        trait_solver_params.dispatch_first != 0u || trait_solver_params.dispatch_count != 1u) return;
    pps_initialize_store_group(lane.x);
}
