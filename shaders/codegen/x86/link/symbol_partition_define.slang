import codegen.x86.link.symbol_partition_common;
import gpu_index;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint definition_i = linear_dispatch_thread_id_2d(tid, 16776960u);
    if (definition_i >= gSymbolPartition.definition_count)
        return;
    uint representative = partition_lookup_identity(link_partition_definition[definition_i].xyz);
    if (representative == INVALID)
    {
        partition_fail(2u, link_partition_definition[definition_i].w);
        return;
    }
    uint prior;
    InterlockedCompareExchange(
        link_partition_definition_value[representative],
        INVALID,
        link_partition_definition[definition_i].w,
        prior);
    if (prior != INVALID)
        partition_fail(3u, min(prior, link_partition_definition[definition_i].w));
}
