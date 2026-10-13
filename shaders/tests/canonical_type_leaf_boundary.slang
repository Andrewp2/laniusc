import tests.canonical_type_boundary_fixture;
import type_checker.dependencies.canonical_field_types;

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    uint row = dtid.x;
    if (row >= boundary_params.queries) return;
    uint base = row * 8u;
    uint2 reference = uint2(boundary_queries[base + 6u], boundary_queries[base + 7u]);
    bool accepted = canonical_type_field_leaf<BoundaryGraph>(boundary_queries[base + 1u], reference);
    boundary_results[row * 4u] = accepted ? 1u : 0u;
    boundary_results[row * 4u + 1u] = reference.x;
    boundary_results[row * 4u + 2u] = reference.y;
    boundary_results[row * 4u + 3u] = 0u;
}
