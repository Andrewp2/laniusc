#include "owned_type_constraints.slang"

// Static dispatch keeps unrelated production walkers out of this pipeline.
struct OverlapFixtureOperations : IOwnedFixtureOperations
{
    static bool execute(uint opcode, uint4 args, OwnedConstraintLimits budget,
        inout OwnedConstraintState state)
    {
        switch (opcode)
        {
        case OP_BEGIN_OVERLAP:
            owned_overlap_begin<LeftGraph, RightGraph>(args.x, args.y, 17u, 17u, 128u, budget, owned_constraint_frame(0u), state); return true;
        case OP_OVERLAP:
            owned_overlap_match<LeftGraph, RightGraph>(args.xy, args.zw, state); return true;
        case OP_FINISH_OVERLAP:
            owned_overlap_finish<LeftGraph, RightGraph>(state); return true;
        default: return false;
        }
    }
}

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    run_owned_fixture<OverlapFixtureOperations>(tid.x);
}
