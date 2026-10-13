#include "owned_typed_constant_fixtures.slang"

[shader("compute")]
[numthreads(16, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint id = tid.x; if (id >= 13u) return;
    uint left_owner = id == 4u || id == 5u ? 11u : id == 7u || id == 8u ? 0u : 10u;
    uint right_owner = id == 4u || id == 5u ? 21u : id == 7u || id == 8u ? 0u : 20u;
    if (id == 12u) { left_owner = 30u; right_owner = 0u; }
    OwnedConstraintState state;
    owned_overlap_begin<TypedLeftGraph, TypedRightGraph>(left_owner, right_owner,
        12u, 12u, 512u, typed_limits(), state);
    uint2 left = uint2(C | 3u, 0u); uint2 right = left;
    if (id == 2u || id == 3u) { left.y = 4u; right.y = 5u; }
    if (id == 4u || id == 5u) { left = uint2(3u, 7u); right = left; }
    if (id == 6u) { left = uint2(3u, 0u); right = left; }
    if (id == 7u || id == 8u) { left.y = 8u; right.y = id == 7u ? 9u : 8u; }
    if (id == 9u) right.y = 2u;
    if (id == 10u) { left = uint2(3u, 0u); right = uint2(3u, 11u); }
    if (id == 11u) { left.y = 10u; right.y = 10u; }
    // Capture a compound type whose array count is a rigid projection. The
    // occurs walk must retain the constant resolver inside the captured type.
    if (id == 12u) { left = uint2(2u, 400u); right = uint2(3u, 5u); }
    // Each case performs the same ordered matches through one call site. This
    // keeps the GPU driver from compiling three copies of the overlap engine.
    uint matches = id <= 6u || id == 12u ? 2u : 1u;
    [loop]
    for (uint match_index = 0u; match_index < matches; match_index++)
    {
        uint2 match_left = left; uint2 match_right = right;
        if (match_index != 0u)
        {
            if (id == 12u)
            {
                // Revisit the captured compound against its direct rigid count.
                match_left = uint2(2u, 400u); match_right = uint2(3u, 6u);
            }
            else
            {
                match_left = uint2(C | 1u, (id == 0u || id == 3u) ? 2u : 0u);
                match_right = uint2(C | 2u, 200u);
                if (id == 4u || id == 5u) { match_left.y = id == 4u ? 9u : 10u; match_right.y = 201u; }
                if (id == 6u) { match_left = uint2(3u, 2u); match_right = uint2(3u, 0u); }
            }
        }
        owned_overlap_match<TypedLeftGraph, TypedRightGraph>(match_left, match_right, state);
    }
    owned_overlap_finish<TypedLeftGraph, TypedRightGraph>(state);
    uint expected = id == 11u ? OWNED_CONSTRAINT_INVALID_INPUT :
        id == 0u || id == 3u || id == 5u || id == 7u || id == 9u || id == 10u
            ? OWNED_CONSTRAINT_NO_MATCH : OWNED_CONSTRAINT_MATCHED;
    // The self equation must not manufacture a right-side recursive edge.
    bool extra = id != 6u || state.bound.w == 0u;
    if (id == 12u)
        extra = all(state.counts == uint4(1u, 0u, 0u, 0u)) &&
            all(state.bound == uint4(1u, 0u, 0u, 0u)) &&
            all(state.bindings[0u] == uint4(1u, 3u, 5u, 0u)) &&
            state.work.occurs_visits != 0u && state.work.substitution_steps != 0u &&
            state.work.pair_visits > 1u;
    typed_result(id, state, expected, extra);
}
