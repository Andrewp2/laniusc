import type_checker.program_evidence.abi;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_solver_wave;

// One planning point of the recorded solver rounds (proof_solver_wave.slang).
[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 thread_id : SV_DispatchThreadID)
{
    if (program_evidence_params.phase != 70u || proof_store_params.phase != 70u) return;
    psw_plan();
}
