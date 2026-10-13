import type_checker.program_evidence.abi;
import type_checker.program_evidence.native_layout.recipe_abi;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (program_evidence_params.phase != 4u) return;
    if (any(dtid != uint3(0u, 0u, 0u)) || program_evidence_params.dispatch_first != 0u ||
        program_evidence_params.dispatch_count != 1u) return;
    if (!plr_building()) return;
    plr_write_status(pev_ok());
}
