import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_solver_wave;

// One planning point of the recorded solver rounds (proof_solver_wave.slang),
// one workgroup: lane 0 plans and the lanes fill the point's slots.
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 lane : SV_GroupThreadID)
{
    if (trait_solver_params.phase != 70u || proof_store_params.phase != 70u) return;
    psw_plan(lane.x);
}
