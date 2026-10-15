#include "owned_typed_constant_fixtures.slang"

[shader("compute")]
[numthreads(16, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint id = tid.x; if (id >= 12u || thread_scratch_begin(id) <= id) return;
    uint owner = id < 3u || id == 10u ? 0u : id == 4u || id == 5u ? 11u : 10u;
    uint2 pattern = uint2(C | 1u, 0u); uint2 goal = uint2(C | 1u, 1u);
    if (id == 1u) goal.y = 3u;
    if (id == 2u) goal.y = 4u;
    if (id == 3u) { pattern = uint2(3u, 0u); goal = uint2(3u, 10u); }
    if (id == 4u || id == 5u) { pattern = uint2(3u, 7u); goal = uint2(3u, id == 4u ? 3u : 4u); }
    if (id == 6u) { pattern = uint2(C | 2u, 100u); goal = uint2(C | 1u, 3u); }
    if (id == 7u) { pattern = uint2(C | 3u, 0u); goal = uint2(C | 3u, 7u); }
    if (id == 8u) { pattern = uint2(C | 3u, 1u); goal = uint2(C | 3u, 9u); }
    if (id == 9u) { pattern = uint2(3u, 0u); goal = uint2(3u, 5u); }
    if (id == 10u) { pattern = uint2(C | 1u, 0u); goal = uint2(C | 3u, 11u); }
    if (id == 11u) { pattern = uint2(C | 3u, 0u); goal = uint2(C | 1u, 5u); }
    OwnedConstraintState state;
    owned_constraints_begin<TypedLeftGraph>(owner, 12u, 12u, 512u, typed_limits(), owned_constraint_frame(0u), state);
    owned_constraints_match<TypedLeftGraph, TypedRightGraph>(pattern, goal, state);
    owned_constraints_finish<TypedLeftGraph, TypedRightGraph>(state);
    bool request_ok = true;
    if (state.status.state == OWNED_CONSTRAINT_MATCHED && owner != 0u)
    {
        OwnedConstraintBindingRequest request;
        request_ok = owned_constraint_binding<TypedLeftGraph, TypedRightGraph>(state, true, 0u, request) &&
            request.reference.x == 1u;
        if (id == 3u) request_ok = request_ok && request.target_count == 1u &&
            owned_constraint_target(request.targets, 0u) == SCALAR_U64 && all(request.reference.yz == uint2(C | 1u, 3u));
        if (id == 4u) request_ok = request_ok && request.target_count == 1u &&
            owned_constraint_target(request.targets, 0u) == SCALAR_U8 && all(request.reference.yz == uint2(C | 1u, 0u));
        if (id == 7u) request_ok = request_ok && request.target_count == 0u &&
            all(request.reference.yz == uint2(C | 2u, 300u));
        if (id == 9u) request_ok = request_ok && request.target_count == 1u &&
            owned_constraint_target(request.targets, 0u) == SCALAR_U64 && all(request.reference.yz == uint2(C | 2u, 300u));
        if (id == 11u) request_ok = request_ok && request.target_count == 1u &&
            owned_constraint_target(request.targets, 0u) == SCALAR_U64 && all(request.reference.yz == uint2(C | 1u, 5u));
    }
    uint expected = id == 1u || id == 2u || id == 5u || id == 6u || id == 8u
        ? OWNED_CONSTRAINT_NO_MATCH : OWNED_CONSTRAINT_MATCHED;
    typed_result(id, state, expected, request_ok);
}
