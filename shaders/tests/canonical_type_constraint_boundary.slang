import tests.canonical_type_boundary_fixture;
import type_checker.constant_constraints;
import type_checker.dependencies.canonical_field_types;

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    uint row = dtid.x;
    if (row >= boundary_params.queries) return;
    uint base = row * 8u;
    uint2 inferred[32]; uint mask; InferredConstant constants[32]; uint constant_mask;
    bool accepted = canonical_type_and_constant_constraints<BoundaryGraph>(
        boundary_queries[base + 1u], boundary_queries[base],
        boundary_queries[base + 2u], boundary_queries[base + 3u],
        boundary_params.nodes, boundary_params.tokens, boundary_queries[base + 4u] != 0u,
        inferred, mask, constants, constant_mask, boundary_queries[base + 5u] != 0u);
    bool type_tail_clear = true; bool constants_clear = true;
    for (uint slot = 2u; slot < 32u; slot++)
        type_tail_clear = type_tail_clear && all(inferred[slot] == uint2(0u, BOUNDARY_INVALID));
    for (uint slot = 0u; slot < 32u; slot++)
        constants_clear = constants_clear && all(constants[slot].reference == uint2(0u, BOUNDARY_INVALID));
    uint output = row * 12u;
    boundary_results[output] = accepted ? 1u : 0u;
    boundary_results[output + 1u] = mask;
    boundary_results[output + 2u] = constant_mask;
    boundary_results[output + 3u] = inferred[0u].x;
    boundary_results[output + 4u] = inferred[0u].y;
    boundary_results[output + 5u] = inferred[1u].x;
    boundary_results[output + 6u] = inferred[1u].y;
    boundary_results[output + 7u] = type_tail_clear ? 1u : 0u;
    boundary_results[output + 8u] = constants_clear ? 1u : 0u;
    boundary_results[output + 9u] = constants[0u].reference.x;
    boundary_results[output + 10u] = constants[0u].reference.y;
    boundary_results[output + 11u] = constants[0u].identity_mode;
}
