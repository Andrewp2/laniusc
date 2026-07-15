// Match-expression instruction generation.

#define LANIUS_X86_NODE_GEN_CATEGORY 3
#include "common.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    run_node_inst_gen(tid);
}
