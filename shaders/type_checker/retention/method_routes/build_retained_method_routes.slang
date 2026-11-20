import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.method_routes.retained_method_route_workspace;
import type_checker.retention.method_routes.resolve_retained_method_routes;
import type_checker.retention.substitution.retained_substitution_results;

struct PublishedMethods : IMethodResults
{
    uint4 request(uint row) { return mr_requests[row]; }
    uint instance_decl(uint instance) { return mr_instances[2u * instance].x; }
    uint4 result(uint row) { return sb_results[row * SB_RESULT_WORDS]; }
    bool current(uint row) { return sb_result_current(mr_config[0u], row); }
}

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    if (!resolve_retained_method_routes(program, mr_config[2u], PublishedMethods())) return;
    step_program_end(program);
}
