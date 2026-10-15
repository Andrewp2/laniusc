import type_checker.program_evidence.abi;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.catalog_admission_dispatch;
import type_checker.program_evidence.catalog_row_admission;
import gpu_index;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (program_evidence_params.phase != 2u || dtid.z != 0u) return;
    uint local = linear_dispatch_thread_id_2d(dtid, 16776960u);
    uint row;
    if (!pev_catalog_admission_row(8u, local, row)) return;
    EvidenceStatus status;
    if (pev_bind_scratch(local, row, status)) status = pev_admit_catalog_predicate(row);
    pev_catalog_failure(status);
}
