// Validate trait and inherent impl-header rows from the bounds/impl shared module.

#define PREDICATE_COLLECT_IMPL_RECORDS 1
#define PREDICATE_BOUND_DECL_RESOLUTION 0
#define PREDICATE_BOUND_ARGUMENT_VALIDATION 0
#include "collect_common.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    if (node_kind[node] == PROD_IMPL_TRAIT)
    {
        validate_trait_impl_node(node);
        return;
    }

    if (node_kind[node] == PROD_IMPL_INHERENT)
    {
        validate_inherent_impl_header_node(node);
        return;
    }
}
