// Phase-specific predicate-obligation validation entry point. This pass only
// reads the count and scanned-prefix products emitted by preceding graph passes.
#define LANIUS_OBLIGATION_VALIDATE_PASS 1
#include "02_obligations.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    validate_call_predicate_obligation_pair(linear_thread_id(dtid));
}
