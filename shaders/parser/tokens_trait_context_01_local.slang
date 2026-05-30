// Trait-body context block summaries for syntax checks.
//
// The syntax checker consumes this prefix-scanned record to decide whether a
// `fn` token belongs to a trait body without walking backward through tokens.

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
StructuredBuffer<uint> token_count;

RWStructuredBuffer<uint> trait_context_event_block;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TK_RBRACE = 23u;
static const uint TK_IMPL = 98u;
static const uint TK_TRAIT = 99u;
static const uint TK_IF_RBRACE = 89u;
static const uint TK_IMPL_RBRACE = 122u;
static const uint TK_TRAIT_RBRACE = 124u;
static const uint TK_STRUCT_LIT_RBRACE = 126u;
static const uint TK_STRUCT_DECL_RBRACE = 128u;
static const uint TK_ENUM_RBRACE = 130u;
static const uint TK_FN_BLOCK_RBRACE = 150u;
static const uint TK_IMPL_FN_BLOCK_RBRACE = 152u;

static const uint TRAIT_BODY_CONTEXT = 1u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint encode_trait_event(uint token_i, uint payload)
{
    return ((token_i + 1u) << 8u) | (payload & 0xffu);
}

bool is_context_reset(uint kind)
{
    return kind == TK_IMPL ||
           kind == TK_RBRACE ||
           kind == TK_IF_RBRACE ||
           kind == TK_IMPL_RBRACE ||
           kind == TK_TRAIT_RBRACE ||
           kind == TK_STRUCT_LIT_RBRACE ||
           kind == TK_STRUCT_DECL_RBRACE ||
           kind == TK_ENUM_RBRACE ||
           kind == TK_FN_BLOCK_RBRACE ||
           kind == TK_IMPL_FN_BLOCK_RBRACE;
}

uint trait_event_for(uint token_i, uint kind)
{
    if (kind == TK_TRAIT)
        return encode_trait_event(token_i, TRAIT_BODY_CONTEXT);
    if (is_context_reset(kind))
        return encode_trait_event(token_i, 0u);
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
    uint event = token_i < count ? trait_event_for(token_i, kind) : 0u;
    uint prefix = prefix_scan_u32_max_256(lane, event);
    if (lane + 1u == WG_SIZE)
        trait_context_event_block[block_idx] = prefix;
}
