// General scalar-expression instruction generation. Other HIR categories use
// sibling eager passes so no one NVIDIA pipeline owns the full backend graph.

#define LANIUS_X86_NODE_GEN_CATEGORY 0
#include "gen/common.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    run_node_inst_gen(tid);
}
