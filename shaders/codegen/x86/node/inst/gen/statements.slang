// Non-control statement instruction generation. Dedicated eager passes own
// if/while/for emission, while this category owns returns, locals, and loop
// control statements.

#define LANIUS_X86_NODE_GEN_CATEGORY 2
#include "common.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    run_node_inst_gen(tid);
}
