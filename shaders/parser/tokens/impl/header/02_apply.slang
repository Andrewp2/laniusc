// Apply prefix-scanned impl-header context rows.

import prefix_scan;

struct Params
{
    uint n_tokens;
    uint n_blocks;
    uint scan_step;
};

ConstantBuffer<Params> gParams;

struct TokenIn
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> lexer_token_count;
StructuredBuffer<uint> statement_event_block_prefix;

RWStructuredBuffer<uint> token_impl_header_kind;
RWStructuredBuffer<uint> token_impl_context_event;

groupshared uint impl_prefix_values[256];

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TK_FOR = 100u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_IMPL = 98u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_TRAIT_IMPL = 181u;

static const uint IMPL_HEADER_CONTEXT = 1u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
}

uint encode_impl_event(uint token_i, uint payload)
{
    return ((token_i + 1u) << 8u) | (payload & 0xffu);
}

uint event_payload(uint event)
{
    return event & 0xffu;
}

uint event_token_index(uint event)
{
    uint encoded = event >> 8u;
    return encoded == 0u ? 0xffffffffu : encoded - 1u;
}

uint impl_event_for(uint token_i, uint kind)
{
    if (kind == TK_IMPL)
        return encode_impl_event(token_i, IMPL_HEADER_CONTEXT);
    if (kind == TK_LBRACE || kind == TK_RBRACE || kind == TK_SEMICOLON)
        return encode_impl_event(token_i, 0u);
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    if (block_idx >= gParams.n_blocks)
        return;

    uint lane = ltid.x;
    uint token_i = block_idx * WG_SIZE + lane;
    uint count = active_token_count();
    uint kind = token_i < count ? token_words[token_i].kind : 0u;
    uint event = token_i < count ? impl_event_for(token_i, kind) : 0u;
    prefix_scan_inclusive<uint, PrefixScanU32Max, 256>(
        lane,
        event,
        impl_prefix_values);

    uint local_before = lane == 0u ? 0u : impl_prefix_values[lane - 1u];
    uint before = max(statement_event_block_prefix[block_idx], local_before);
    if (token_i < gParams.n_tokens)
        token_impl_context_event[token_i] = before;

    if (token_i < count && kind == TK_FOR && event_payload(before) == IMPL_HEADER_CONTEXT)
    {
        uint impl_i = event_token_index(before);
        if (impl_i < gParams.n_tokens)
            token_impl_header_kind[impl_i] = TK_TRAIT_IMPL;
    }
}
