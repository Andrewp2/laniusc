import tests.canonical_type_boundary_fixture;
import type_checker.dependencies.canonical_field_types;
import type_checker.scoped_type_hash;

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    uint row = dtid.x;
    if (row >= boundary_params.queries) return;
    uint base = row * 8u;
    uint type = boundary_queries[base];
    uint environment = boundary_queries[base + 1u];
    uint candidate = boundary_queries[base + 3u];
    uint canonical_hash; uint source_hash;
    bool canonical_ok = canonical_field_ref_hash<BoundaryGraph>(environment, type,
        boundary_params.nodes, boundary_params.tokens, canonical_hash);
    bool matches = canonical_field_ref_matches<BoundaryGraph>(environment, type, candidate,
        boundary_params.nodes, boundary_params.tokens);
    bool source_ok = scoped_type_ref_hash<BoundaryGraph>(3u, candidate, BOUNDARY_INVALID,
        boundary_params.nodes, boundary_params.tokens, source_hash);
    boundary_results[row * 4u] = canonical_ok ? 1u : 0u;
    boundary_results[row * 4u + 1u] = matches ? 1u : 0u;
    boundary_results[row * 4u + 2u] = source_ok ? 1u : 0u;
    boundary_results[row * 4u + 3u] = canonical_ok && source_ok && canonical_hash == source_hash ? 1u : 0u;
}
