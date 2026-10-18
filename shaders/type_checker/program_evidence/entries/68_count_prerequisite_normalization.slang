// Counts the rows phase 42 will reserve for the prerequisite Works just
// admitted (proof_demand.slang).
import type_checker.program_evidence.abi;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_normalization_stages;
import type_checker.program_evidence.proof_demand;
import gpu_index;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (program_evidence_params.phase != 68u || proof_store_params.phase != 68u) return;
    if (dtid.z != 0u || !pps_building() || !pev_batch_is_building()) return;
    uint local = linear_dispatch_thread_id_2d(dtid, 16776960u);
    uint count; uint row;
    if (!pps_count(PPS_WORK, count) || !pev_dispatch_row(local, count, row)) return;
    EvidenceStatus status; uint nodes; uint edges; uint roots;
    if (!pev_bind_scratch(local, row, status)) return;
    if (pps_measure_prerequisite_work(row, nodes, edges, roots))
        pps_add_normalization_demand(nodes, edges, roots);
}
