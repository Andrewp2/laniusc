import type_checker.trait_solver.abi;
import type_checker.trait_solver.catalog_stages;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    if (trait_solver_params.phase != 0u) return;
    if (any(dtid != uint3(0u, 0u, 0u)) ||
        trait_solver_params.dispatch_first != 0u ||
        trait_solver_params.dispatch_count != 1u) return;
    ts_catalog_initialize();
}

