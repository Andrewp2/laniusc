import type_checker.trait_solver.abi;
import type_checker.trait_solver.catalog_stages;
import gpu_index;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 8u) return;
    if (dtid.z != 0u) return;
    uint local = linear_dispatch_thread_id_2d(dtid, 16776960u);
    ts_catalog_clear_implementation_indexes(local);
}

