import atomics;
import gpu_index;

struct SymbolPartitionParams
{
    uint definition_count;
    uint query_count;
    uint hash_capacity;
    uint reserved;
};

ConstantBuffer<SymbolPartitionParams> gSymbolPartition;

// definition: exact 96-bit identity, global symbol-record index
StructuredBuffer<uint4> link_partition_definition;
// query: exact 96-bit identity, relocation index (for diagnostics)
StructuredBuffer<uint4> link_partition_query;
RWStructuredBuffer<uint> link_partition_hash_table;
RWStructuredBuffer<uint> link_partition_definition_value;
RWStructuredBuffer<uint> link_partition_resolved_value;
RWStructuredBuffer<uint> link_partition_status;

static const uint INVALID = 0xffffffffu;

uint partition_identity_hash(uint3 value)
{
    uint h = 2166136261u;
    h = (h ^ value.x) * 16777619u;
    h = (h ^ value.y) * 16777619u;
    h = (h ^ value.z) * 16777619u;
    h ^= h >> 16u;
    return h;
}

bool partition_same_identity(uint left, uint right)
{
    return all(link_partition_definition[left].xyz == link_partition_definition[right].xyz);
}

uint partition_lookup_identity(uint3 identity)
{
    uint mask = gSymbolPartition.hash_capacity - 1u;
    uint slot = partition_identity_hash(identity) & mask;
    for (uint probe = 0u; probe < gSymbolPartition.hash_capacity; probe += 1u)
    {
        uint candidate = link_partition_hash_table[slot];
        if (candidate == INVALID)
            return INVALID;
        if (all(link_partition_definition[candidate].xyz == identity))
            return candidate;
        slot = (slot + 1u) & mask;
    }
    return INVALID;
}

void partition_fail(uint code, uint detail)
{
    atomic_u32_min(link_partition_status, 2u, detail);
    link_partition_status[1u] = code;
    link_partition_status[0u] = 0u;
}
