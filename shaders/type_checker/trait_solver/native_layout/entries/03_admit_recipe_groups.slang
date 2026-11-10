import type_checker.trait_solver.abi;
import type_checker.trait_solver.native_layout.recipe_abi;
import type_checker.trait_solver.native_layout.recipe_admission;
import gpu_index;

bool plr_dispatch_row(uint local, uint count, out uint row)
{
    row = TS_INVALID;
    if (local >= trait_solver_params.dispatch_count ||
        trait_solver_params.dispatch_first > count ||
        local >= count - trait_solver_params.dispatch_first) return false;
    row = trait_solver_params.dispatch_first + local; return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 3u) return;
    if (dtid.z != 0u) return;
    uint local = linear_dispatch_thread_id_2d(dtid, 16776960u);
    if (!plr_building()) return;
    uint row; uint offset; uint count; uint width;
    if (!plr_table(1u, offset, count, width) || !plr_dispatch_row(local, count, row)) return;
    EvidenceStatus status;
    if (ts_bind_scratch(local, row, status)) status = plr_admit_group(row);
    plr_failure(status);
}
