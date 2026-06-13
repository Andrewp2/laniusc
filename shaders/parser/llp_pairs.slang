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
StructuredBuffer<uint> token_file_id;
StructuredBuffer<ActionHeader> action_table;
RWStructuredBuffer<ActionHeader> out_headers;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 gid, uint3 ltid)
{
    return (gid.x + gid.y * MAX_GROUPS_X) * WG_SIZE + ltid.x;
}

ActionHeader zero_header()
{
    ActionHeader z = { 0, 0, 0, 0 };
    return z;
}

bool valid_kind(uint kind)
{
    return kind < gParams.n_kinds;
}

ActionHeader table_header(uint prev_kind, uint this_kind)
{
    if (!valid_kind(prev_kind) || !valid_kind(this_kind))
        return zero_header();
    return action_table[prev_kind * gParams.n_kinds + this_kind];
}

bool source_file_boundary_pair(uint pair_i, uint token_count_value)
{
    if (pair_i == 0u || pair_i >= token_count_value)
        return false;

    uint prev_file = token_file_id[pair_i - 1u];
    uint this_file = token_file_id[pair_i];
    return prev_file != 0xffffffffu &&
           this_file != 0xffffffffu &&
           prev_file != this_file;
}

ActionHeader combine_virtual_boundary_headers(uint prev_kind, uint this_kind)
{
    ActionHeader close_prev = table_header(prev_kind, 0u);
    ActionHeader open_next = table_header(0u, this_kind);
    ActionHeader combined;
    combined.push_len = close_prev.push_len + open_next.push_len;
    combined.emit_len = close_prev.emit_len + open_next.emit_len;
    combined.pop_tag = 0u;
    combined.pop_count = close_prev.pop_count + open_next.pop_count;
    return combined;
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
        out_headers[i] = zero_header();
        return;
    }

    uint prev_kind = token_kinds[i];
    uint this_kind = token_kinds[i + 1];

    if (!valid_kind(prev_kind) || !valid_kind(this_kind))
    {
        out_headers[i] = zero_header();
        return;
    }

    uint count = min(token_count[0u], gParams.n_tokens > 2u ? gParams.n_tokens - 2u : 0u);
    out_headers[i] = source_file_boundary_pair(i, count)
        ? combine_virtual_boundary_headers(prev_kind, this_kind)
        : table_header(prev_kind, this_kind);
}
