import codegen.x86.link.symbol_partition_common;
import gpu_index;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_thread_id_2d(tid, 16776960u);
    if (i < gSymbolPartition.hash_capacity)
        link_partition_hash_table[i] = INVALID;
    if (i < gSymbolPartition.definition_count)
        link_partition_definition_value[i] = INVALID;
    if (i < gSymbolPartition.query_count)
        link_partition_resolved_value[i] = INVALID;
    if (i == 0u)
    {
        link_partition_status[0u] = 1u;
        link_partition_status[1u] = 0u;
        link_partition_status[2u] = INVALID;
        link_partition_status[3u] = gSymbolPartition.query_count;
    }
}
