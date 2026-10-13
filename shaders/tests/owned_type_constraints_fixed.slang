#include "owned_type_constraints.slang"

// Static dispatch keeps unrelated production walkers out of this pipeline.
struct FixedFixtureOperations : IOwnedFixtureOperations
{
    static bool execute(uint opcode, uint4 args, OwnedConstraintLimits budget,
        inout OwnedConstraintState state)
    {
        switch (opcode)
        {
        case OP_BEGIN_MATCH:
            owned_constraints_begin<LeftGraph>(args.x, 17u, 17u, 128u, budget, state); return true;
        case OP_MATCH:
            owned_constraints_match<LeftGraph, GoalGraph>(args.xy, args.zw, state); return true;
        case OP_FINISH_MATCH:
            owned_constraints_finish<LeftGraph, GoalGraph>(state); return true;
        case OP_FIXED_MATCH:
            owned_constraints_match_fixed<LeftGraph, GoalGraph>(args.xy, args.zw, state); return true;
        case OP_CHECK_BINDING:
        {
            OwnedConstraintBindingRequest binding;
            return args.x <= 1u && owned_constraint_binding<LeftGraph, GoalGraph>(state, args.x != 0u, args.y, binding) &&
                binding.reference.x == 1u && binding.target_count == 0u && all(binding.reference.yz == args.zw);
        }
        default: return false;
        }
    }
}

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    run_owned_fixture<FixedFixtureOperations>(tid.x);
}
