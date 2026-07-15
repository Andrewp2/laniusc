import codegen.x86.link.symbol_partition_common;
import gpu_index;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint query_i = linear_dispatch_thread_id_2d(tid, 16776960u);
    if (query_i >= gSymbolPartition.query_count)
        return;
    uint representative = partition_lookup_identity(link_partition_query[query_i].xyz);
    if (representative == INVALID)
    {
        partition_fail(4u, link_partition_query[query_i].w);
        return;
    }
    uint definition = link_partition_definition_value[representative];
    if (definition == INVALID)
    {
        partition_fail(5u, link_partition_query[query_i].w);
        return;
    }
    link_partition_resolved_value[query_i] = definition;
}
