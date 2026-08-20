struct ActionHeader
{
    uint push_len;
    uint emit_len;
    uint pop_tag;
    uint pop_count;
};

struct Params
{
    uint n_pairs;
    uint emit_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> token_count;
StructuredBuffer<ActionHeader> out_headers;
StructuredBuffer<uint> sc_offsets;
StructuredBuffer<uint> emit_offsets;
RWStructuredBuffer<uint> partial_parse_status;
RWStructuredBuffer<uint> active_stack_thread_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint ERR_NONE = 0u;
static const uint ERR_OUTPUT_CAPACITY = 3u;
static const uint ERR_TOKEN_CAPACITY = 5u;

void write_stack_dispatch_args(uint rows)
{
    uint groups = max(1u, (rows + WG_SIZE - 1u) / WG_SIZE);
    active_stack_thread_dispatch_args[0u] = min(groups, MAX_GROUPS_X);
    active_stack_thread_dispatch_args[1u] =
        max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    active_stack_thread_dispatch_args[2u] = 1u;
}

uint linear_thread_id(uint3 gid, uint3 ltid)
{
    return (gid.x + gid.y * MAX_GROUPS_X) * WG_SIZE + ltid.x;
}

uint active_pair_count()
{
    uint active_tokens = token_count[0u] + 2u;
    uint active_pairs = active_tokens > 0u ? active_tokens - 1u : 0u;
    return min(gParams.n_pairs, active_pairs);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint i = linear_thread_id(gid, ltid);
    if (i != 0u)
        return;

    uint n_active = active_pair_count();
    bool token_overflow = token_count[0u] > (gParams.n_pairs > 0u ? gParams.n_pairs - 1u : 0u);
    if (token_overflow)
    {
        write_stack_dispatch_args(0u);
        partial_parse_status[0u] = 0u;
        partial_parse_status[1u] = gParams.n_pairs > 0u ? gParams.n_pairs - 1u : 0u;
        partial_parse_status[2u] = ERR_TOKEN_CAPACITY;
        partial_parse_status[3u] = token_count[0u];
        partial_parse_status[4u] = 0u;
        partial_parse_status[5u] = 0u;
        return;
    }
    if (n_active == 0u || gParams.n_pairs == 0u)
    {
        write_stack_dispatch_args(0u);
        partial_parse_status[0u] = 1u;
        partial_parse_status[1u] = 0u;
        partial_parse_status[2u] = ERR_NONE;
        partial_parse_status[3u] = 0u;
        partial_parse_status[4u] = 0u;
        partial_parse_status[5u] = 0u;
        return;
    }

    uint last = n_active - 1u;
    ActionHeader header = out_headers[last];
    uint sc_total = sc_offsets[last] + header.push_len + header.pop_count;
    uint emit_total = emit_offsets[last] + header.emit_len;
    bool emit_overflow = emit_total > gParams.emit_capacity;
    uint reported_emit = min(emit_total, gParams.emit_capacity);
    write_stack_dispatch_args(sc_total);

    partial_parse_status[0u] = emit_overflow ? 0u : 1u;
    partial_parse_status[1u] = emit_overflow ? last : 0u;
    partial_parse_status[2u] = emit_overflow ? ERR_OUTPUT_CAPACITY : ERR_NONE;
    partial_parse_status[3u] = emit_overflow ? emit_total : 0u;
    partial_parse_status[4u] = sc_total;
    partial_parse_status[5u] = reported_emit;
}
