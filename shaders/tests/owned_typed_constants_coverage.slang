#include "owned_typed_constant_fixtures.slang"

[shader("compute")]
[numthreads(4, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint id = tid.x; if (id >= 4u || thread_scratch_begin(id) <= id) return;
    OwnedConstraintState state;
    owned_pattern_begin<TypedLeftGraph>(10u, 12u, 512u, typed_limits(), owned_constraint_frame(0u), state);
    uint2 root = id == 0u ? uint2(C | 3u, 1u) : id == 1u ? uint2(C | 3u, 10u) :
        id == 2u ? uint2(3u, 8u) : uint2(C | 1u, 0u);
    owned_pattern_visit<TypedLeftGraph>(root, state);
    owned_pattern_finish<TypedLeftGraph>(state);
    typed_result(id, state, id == 1u || id == 3u ? OWNED_CONSTRAINT_INVALID_INPUT : OWNED_CONSTRAINT_MATCHED);
}
