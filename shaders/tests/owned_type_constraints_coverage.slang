#include "owned_type_constraints.slang"

// Static dispatch keeps unrelated production walkers out of this pipeline.
struct CoverageFixtureOperations : IOwnedFixtureOperations
{
    static bool execute(uint opcode, uint4 args, OwnedConstraintLimits budget,
        inout OwnedConstraintState state)
    {
        switch (opcode)
        {
        case OP_BEGIN_PATTERN:
            owned_pattern_begin<LeftGraph>(args.x, 17u, 128u, budget, owned_constraint_frame(0u), state); return true;
        case OP_VISIT:
            owned_pattern_visit<LeftGraph>(args.xy, state); return true;
        case OP_FINISH_PATTERN:
            owned_pattern_finish<LeftGraph>(state); return true;
        default: return false;
        }
    }
}

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    run_owned_fixture<CoverageFixtureOperations>(tid.x);
}
