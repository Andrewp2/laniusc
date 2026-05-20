// Top-level brace semantic kinds for token retagging.

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
StructuredBuffer<int> depth_brace_inblock;
StructuredBuffer<int> block_prefix_brace;
StructuredBuffer<uint> top_brace_owner_block_prefix;

RWStructuredBuffer<uint> brace_semantic_kind;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_IMPL_LBRACE = 121u;
static const uint TK_IMPL_RBRACE = 122u;
static const uint TK_TRAIT_LBRACE = 123u;
static const uint TK_TRAIT_RBRACE = 124u;
static const uint TK_STRUCT_LIT_LBRACE = 125u;
static const uint TK_STRUCT_LIT_RBRACE = 126u;
static const uint TK_STRUCT_DECL_LBRACE = 127u;
static const uint TK_STRUCT_DECL_RBRACE = 128u;
static const uint TK_ENUM_LBRACE = 129u;
static const uint TK_ENUM_RBRACE = 130u;
static const uint TK_FN_BLOCK_LBRACE = 149u;
static const uint TK_FN_BLOCK_RBRACE = 150u;
static const uint TK_IMPL_FN_BLOCK_LBRACE = 151u;
static const uint TK_IMPL_FN_BLOCK_RBRACE = 152u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
}

uint encode_owner_event(uint token_i, uint owner_kind)
{
    return owner_kind == 0u ? 0u : ((token_i + 1u) << 8u) | (owner_kind & 0xffu);
}

uint decode_owner_kind(uint event)
{
    return event & 0xffu;
}

uint close_kind_for_open_kind(uint open_kind)
{
    if (open_kind == TK_IMPL_LBRACE)
        return TK_IMPL_RBRACE;
    if (open_kind == TK_TRAIT_LBRACE)
        return TK_TRAIT_RBRACE;
    if (open_kind == TK_STRUCT_LIT_LBRACE)
        return TK_STRUCT_LIT_RBRACE;
    if (open_kind == TK_STRUCT_DECL_LBRACE)
        return TK_STRUCT_DECL_RBRACE;
    if (open_kind == TK_ENUM_LBRACE)
        return TK_ENUM_RBRACE;
    if (open_kind == TK_FN_BLOCK_LBRACE)
        return TK_FN_BLOCK_RBRACE;
    if (open_kind == TK_IMPL_FN_BLOCK_LBRACE)
        return TK_IMPL_FN_BLOCK_RBRACE;
    return TK_RBRACE;
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
    int depth_before = token_i < gParams.n_tokens
        ? block_prefix_brace[block_idx] + depth_brace_inblock[token_i]
        : 0;
    uint recorded_open_kind = token_i < gParams.n_tokens ? brace_semantic_kind[token_i] : 0u;

    uint owner_event = 0u;
    if (token_i < count && kind == TK_LBRACE && depth_before == 0)
        owner_event = encode_owner_event(token_i, recorded_open_kind);
    uint local_owner_prefix = prefix_scan_u32_max_256(lane, owner_event);
    uint owner_kind = decode_owner_kind(max(
        top_brace_owner_block_prefix[block_idx],
        local_owner_prefix));

    uint semantic_kind = 0u;
    if (token_i < count && kind == TK_LBRACE && depth_before == 0)
        semantic_kind = recorded_open_kind;
    else if (token_i < count && kind == TK_RBRACE && depth_before == 1)
        semantic_kind = close_kind_for_open_kind(owner_kind);

    if (token_i < gParams.n_tokens)
        brace_semantic_kind[token_i] = semantic_kind;
}
