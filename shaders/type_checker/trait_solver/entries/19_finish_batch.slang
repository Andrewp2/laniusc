import type_checker.trait_solver.abi;
import type_checker.trait_solver.batch_stages;

// One workgroup finishes the batch (ts_batch_finish).
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 lane : SV_GroupThreadID, uint3 group : SV_GroupID)
{
    if (trait_solver_params.phase != 19u) return;
    if (any(group != uint3(0u, 0u, 0u)) ||
        trait_solver_params.dispatch_first != 0u || trait_solver_params.dispatch_count != 1u) return;
    ts_batch_finish(lane.x);
}
