// Validate trait and impl method contract predicate rows.

#include "collect_methods_common.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    if (trait_method_node(node))
    {
        validate_trait_method_contract_node(node);
        return;
    }

    if (impl_method_node(node))
    {
        validate_impl_method_contract_record_node(node);
        return;
    }
}
