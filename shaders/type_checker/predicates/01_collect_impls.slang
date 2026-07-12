// Validate trait and inherent impl header predicate rows.

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
