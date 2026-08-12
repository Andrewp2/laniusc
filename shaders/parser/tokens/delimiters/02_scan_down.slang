// Carry propagation for delimiter depths and token-context events.

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

ConstantBuffer<Params> gDelimiterScan;
RWStructuredBuffer<int> block_prefix_brace;
RWStructuredBuffer<int> block_prefix_bracket;
RWStructuredBuffer<int> block_prefix_paren;
RWStructuredBuffer<int> block_prefix_angle;
RWStructuredBuffer<uint> top_brace_owner_block_prefix;
RWStructuredBuffer<uint> statement_event_block_prefix;
RWStructuredBuffer<int> hierarchy_brace;
RWStructuredBuffer<int> hierarchy_bracket;
RWStructuredBuffer<int> hierarchy_paren;
RWStructuredBuffer<int> hierarchy_angle;
RWStructuredBuffer<uint> hierarchy_owner;
RWStructuredBuffer<uint> hierarchy_event;

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
    uint count = (gDelimiterScan.n_blocks + gDelimiterScan.level_divisor - 1u)
        / gDelimiterScan.level_divisor;
    if (i >= count) return;
    uint group_i = i / WG_SIZE;
    int4 depth_carry = int4(0, 0, 0, 0);
    uint2 event_carry = uint2(0u, 0u);
    if (group_i != 0u)
    {
        uint carry_row = gDelimiterScan.parent_offset + group_i - 1u;
        depth_carry = int4(
            hierarchy_brace[carry_row], hierarchy_bracket[carry_row],
            hierarchy_paren[carry_row], hierarchy_angle[carry_row]);
        event_carry = uint2(hierarchy_owner[carry_row], hierarchy_event[carry_row]);
    }
    if (gDelimiterScan.level_divisor == 1u)
    {
        block_prefix_brace[i] += depth_carry.x;
        block_prefix_bracket[i] += depth_carry.y;
        block_prefix_paren[i] += depth_carry.z;
        block_prefix_angle[i] += depth_carry.w;
        top_brace_owner_block_prefix[i] = max(top_brace_owner_block_prefix[i], event_carry.x);
        statement_event_block_prefix[i] = max(statement_event_block_prefix[i], event_carry.y);
    }
    else
    {
        uint row = gDelimiterScan.level_offset + i;
        hierarchy_brace[row] += depth_carry.x;
        hierarchy_bracket[row] += depth_carry.y;
        hierarchy_paren[row] += depth_carry.z;
        hierarchy_angle[row] += depth_carry.w;
        hierarchy_owner[row] = max(hierarchy_owner[row], event_carry.x);
        hierarchy_event[row] = max(hierarchy_event[row], event_carry.y);
    }
}
