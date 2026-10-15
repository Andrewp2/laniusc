import type_checker.program_evidence.abi;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_normalization_stages;
import gpu_index;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (program_evidence_params.phase != 44u || proof_store_params.phase != 44u) return;
    if (dtid.z != 0u || !pps_building() || !pev_batch_is_building()) return;
    uint local = linear_dispatch_thread_id_2d(dtid, 16776960u);
    uint count; uint row;
    if (!pps_count(PPS_WORK, count))
    { pev_batch_failure(pev_invalid(1u, PPS_WORK, PEV_INVALID)); return; }
    if (!pev_dispatch_row(local, count, row)) return;
    EvidenceStatus status;
    if (pev_bind_scratch(local, row, status)) status = pps_validate_prerequisite_work(row);
    pev_batch_failure(status);
}
