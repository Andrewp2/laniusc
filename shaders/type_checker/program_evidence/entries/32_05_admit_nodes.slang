import type_checker.program_evidence.abi;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.batch_admission_dispatch;
import type_checker.program_evidence.batch_row_admission;
import gpu_index;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (program_evidence_params.phase != 37u || dtid.z != 0u) return;
    uint local = linear_dispatch_thread_id_2d(dtid, 16776960u);
    uint row;
    if (!pev_batch_admission_row(5u, local, row)) return;
    pev_batch_failure(pev_admit_batch_node(row));
}
