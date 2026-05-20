struct ActionHeader
{
    uint push_len;
    uint emit_len;
    uint pop_tag;
    uint pop_count;
};

struct Params
{
    uint n_tokens;
    uint n_kinds;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> token_kinds;
StructuredBuffer<uint> token_count;
StructuredBuffer<ActionHeader> action_table;
RWStructuredBuffer<ActionHeader> out_headers;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 gid, uint3 ltid)
{
    return (gid.x + gid.y * MAX_GROUPS_X) * WG_SIZE + ltid.x;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint i = linear_thread_id(gid, ltid);
    if (gParams.n_tokens < 2)
        return;
    uint capacity_pairs = gParams.n_tokens - 1;
    if (i >= capacity_pairs)
        return;

    uint active_tokens = min(gParams.n_tokens, token_count[0u] + 2u);
    uint n_pairs = active_tokens > 0u ? active_tokens - 1u : 0u;
    if (i >= n_pairs)
    {
        ActionHeader z = { 0, 0, 0, 0 };
        out_headers[i] = z;
        return;
    }

    uint prev_kind = token_kinds[i];
    uint this_kind = token_kinds[i + 1];

    if (prev_kind >= gParams.n_kinds || this_kind >= gParams.n_kinds)
    {
        ActionHeader z = { 0, 0, 0, 0 };
        out_headers[i] = z;
        return;
    }

    uint idx = prev_kind * gParams.n_kinds + this_kind;
    out_headers[i] = action_table[idx];
}
