import type_checker.program_evidence.abi;
import type_checker.program_evidence.native_layout.recipe_abi;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (program_evidence_params.phase != 0u) return;
    if (any(dtid != uint3(0u, 0u, 0u)) || program_evidence_params.dispatch_first != 0u ||
        program_evidence_params.dispatch_count != 1u) return;
    if (!plr_header_is_valid()) return;
    EvidenceStatus status = pev_ok(); status.state = PLR_BUILDING;
    plr_write_status(status);
}
