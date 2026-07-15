import codegen.x86.link.symbol_partition_common;
import gpu_index;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint definition_i = linear_dispatch_thread_id_2d(tid, 16776960u);
    if (definition_i >= gSymbolPartition.definition_count)
        return;
    uint mask = gSymbolPartition.hash_capacity - 1u;
    uint slot = partition_identity_hash(link_partition_definition[definition_i].xyz) & mask;
    for (uint probe = 0u; probe < gSymbolPartition.hash_capacity; probe += 1u)
    {
        uint prior;
        InterlockedCompareExchange(
            link_partition_hash_table[slot],
            INVALID,
            definition_i,
            prior);
        if (prior == INVALID || partition_same_identity(prior, definition_i))
            return;
        slot = (slot + 1u) & mask;
    }
    partition_fail(1u, link_partition_definition[definition_i].w);
}
