// Carry propagation for the exclusive token-context max hierarchy.

struct Params
{
    uint n_blocks;
    uint level_divisor;
    uint level_offset;
    uint parent_divisor;
    uint parent_offset;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<Params> gContextScan;
RWStructuredBuffer<uint> statement_event_block_prefix;
RWStructuredBuffer<uint> statement_event_hierarchy;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint count = (gContextScan.n_blocks + gContextScan.level_divisor - 1u)
        / gContextScan.level_divisor;
    if (i >= count)
        return;

    uint group_i = i / WG_SIZE;
    uint carry = group_i == 0u
        ? 0u
        : statement_event_hierarchy[gContextScan.parent_offset + group_i - 1u];
    if (gContextScan.level_divisor == 1u)
        statement_event_block_prefix[i] = max(statement_event_block_prefix[i], carry);
    else
        statement_event_hierarchy[gContextScan.level_offset + i] =
            max(statement_event_hierarchy[gContextScan.level_offset + i], carry);
}
