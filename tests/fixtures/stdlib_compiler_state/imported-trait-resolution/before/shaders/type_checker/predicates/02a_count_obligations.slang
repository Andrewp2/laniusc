// Phase-specific predicate-obligation count entry point. Keeping this interface
// separate from validation makes its write ownership visible to the compiler graph.
#define LANIUS_OBLIGATION_COUNT_PASS 1
#include "02_obligations.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    predicate_obligation_count_by_call[node] = 0u;
    validate_predicate_fail_closed_status(node);
    validate_unique_impl_key(node);
    count_call_predicate_obligations(node);
}
