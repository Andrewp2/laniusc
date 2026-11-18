struct LinkParams
{
    uint function_count;
    uint type_len;
    uint body_len;
    uint entry_function;
    uint symbol_count;
    uint relocation_count;
    uint hash_capacity;
    uint output_len;
    uint output_page_base;
    uint output_page_len;
    uint type_input_base;
    uint body_input_base;
};
struct LinkRelocation
{
    uint body_offset;
    uint target_kind;
    uint target_index;
    uint addend;
    uint3 target_identity;
    uint padding;
};
ConstantBuffer<LinkParams> gLink;
StructuredBuffer<uint4> link_symbol;
RWStructuredBuffer<uint> link_hash_table;
RWStructuredBuffer<uint> link_symbol_definition;
RWStructuredBuffer<uint> link_status;
static const uint INVALID = 0xffffffffu;

uint identity_hash(uint3 value)
{
    uint h = 2166136261u;
    h = (h ^ value.x) * 16777619u;
    h = (h ^ value.y) * 16777619u;
    h = (h ^ value.z) * 16777619u;
    h ^= h >> 16u;
    return h;
}

bool same_identity(uint a, uint b) { return all(link_symbol[a].xyz == link_symbol[b].xyz); }

uint lookup_identity(uint symbol_i)
{
    return lookup_identity_value(link_symbol[symbol_i].xyz);
}

uint lookup_identity_value(uint3 identity)
{
    uint mask = gLink.hash_capacity - 1u;
    uint slot = identity_hash(identity) & mask;
    for (uint probe = 0u; probe < gLink.hash_capacity; probe += 1u)
    {
        uint candidate = link_hash_table[slot];
        if (candidate == INVALID) return INVALID;
        if (all(link_symbol[candidate].xyz == identity)) return candidate;
        slot = (slot + 1u) & mask;
    }
    return INVALID;
}

void fail(uint code, uint detail)
{
    InterlockedMin(link_status[2u], detail);
    link_status[1u] = code;
    link_status[0u] = 0u;
}
