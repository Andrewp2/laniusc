import type_checker.program_evidence.abi;
import type_checker.program_evidence.native_layout.work_abi;
import type_checker.program_evidence.native_layout.materialize;
import thread_scratch;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (program_evidence_params.phase != 5u || any(dtid != uint3(0u, 0u, 0u)) ||
        program_evidence_params.dispatch_first != 0u || program_evidence_params.dispatch_count != 1u ||
        !plm_header_is_valid()) return;
    // Fresh exclusive arena only. A previous result cannot act as a completion
    // receipt for a different source term or a second request.
    if (plm_used(0u) != 0u || plm_used(1u) != 0u || plm_used(2u) != 0u || plm_used(3u) != 0u ||
        program_evidence_native_layout_work[18u] != 0u || program_evidence_native_layout_work[19u] != 0u ||
        program_evidence_native_layout_work[20u] != 0u) return;
    uint4 prior;
    if (!plm_read4(5u, 0u, 0u, false, prior) || prior.x != 0u) return;
    plm_write4(6u, 0u, 0u, uint4(0u, PEV_INVALID, PEV_INVALID, 0u));
    uint2 source = uint2(program_evidence_native_layout_work[8u], program_evidence_native_layout_work[9u]);
    // One status write site. The single materialization thread owns scratch slot 0.
    EvidenceStatus status = pev_invalid(173u, source.y, source.x);
    if (source.x == 1u || source.x == 3u)
    {
        status = pev_limit(190u, source.y, 1u, 0u);
        if (thread_scratch_begin(0u) != 0u) status = plm_materialize(source);
    }
    plm_status(status);
}
