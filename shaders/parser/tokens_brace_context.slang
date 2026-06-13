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
StructuredBuffer<int> depth_bracket_inblock;
StructuredBuffer<int> block_prefix_brace;
StructuredBuffer<int> block_prefix_bracket;
StructuredBuffer<uint> top_brace_owner_block_prefix;
StructuredBuffer<uint> statement_event_block_prefix;

RWStructuredBuffer<uint> brace_semantic_kind;
RWStructuredBuffer<uint> statement_context_kind;

groupshared uint statement_event_prefix_values[256];

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_FN = 67u;
static const uint TK_LET = 68u;
static const uint TK_RETURN = 69u;
static const uint TK_IF = 70u;
static const uint TK_ELSE = 71u;
static const uint TK_WHILE = 72u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_IF_RBRACE = 89u;
static const uint TK_BREAK = 73u;
static const uint TK_CONTINUE = 74u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;
static const uint TK_IMPORT = 96u;
static const uint TK_MODULE = 97u;
static const uint TK_IMPL = 98u;
static const uint TK_TRAIT = 99u;
static const uint TK_FOR = 100u;
static const uint TK_EXTERN = 102u;
static const uint TK_TYPE = 103u;
static const uint TK_CONST = 92u;
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
static const uint TK_DEFERRED_FN_BLOCK_LBRACE = 0x80000000u;

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
    if (open_kind == TK_IF_LBRACE)
        return TK_IF_RBRACE;
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

bool is_statement_starter(uint kind)
{
    return kind == TK_IMPORT ||
           kind == TK_MODULE ||
           kind == TK_EXTERN ||
           kind == TK_TYPE ||
           kind == TK_CONST ||
           kind == TK_LET ||
           kind == TK_RETURN ||
           kind == TK_IF ||
           kind == TK_ELSE ||
           kind == TK_WHILE ||
           kind == TK_FOR ||
           kind == TK_BREAK ||
           kind == TK_CONTINUE ||
           kind == TK_FN ||
           kind == TK_ENUM ||
           kind == TK_STRUCT ||
           kind == TK_IMPL ||
           kind == TK_TRAIT;
}

bool is_statement_reset_boundary(uint kind)
{
    return kind == TK_SEMICOLON || kind == TK_LBRACE || kind == TK_RBRACE;
}

uint statement_event_for(uint token_i, uint kind, int global_bracket_depth_before)
{
    if (global_bracket_depth_before != 0)
        return 0u;
    if (is_statement_starter(kind))
        return ((token_i + 1u) << 8u) | (kind & 0xffu);
    if (is_statement_reset_boundary(kind))
        return (token_i + 1u) << 8u;
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
    int depth_before = token_i < gParams.n_tokens
        ? block_prefix_brace[block_idx] + depth_brace_inblock[token_i]
        : 0;
    int bracket_depth_before = token_i < gParams.n_tokens
        ? block_prefix_bracket[block_idx] + depth_bracket_inblock[token_i]
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
    if (token_i < count && kind == TK_LBRACE)
    {
        semantic_kind = recorded_open_kind == TK_DEFERRED_FN_BLOCK_LBRACE
            ? (owner_kind == TK_IMPL_LBRACE ? TK_IMPL_FN_BLOCK_LBRACE : TK_FN_BLOCK_LBRACE)
            : recorded_open_kind;
    }
    else if (token_i < count && kind == TK_RBRACE)
    {
        if (depth_before == 1)
        {
            semantic_kind = close_kind_for_open_kind(owner_kind);
        }
        else if (depth_before == 2 && owner_kind == TK_IMPL_LBRACE)
        {
            semantic_kind = TK_IMPL_FN_BLOCK_RBRACE;
        }
        else if (depth_before == 2 && owner_kind == TK_TRAIT_LBRACE)
        {
            semantic_kind = TK_FN_BLOCK_RBRACE;
        }
    }

    if (token_i < gParams.n_tokens)
        brace_semantic_kind[token_i] = semantic_kind;

    uint statement_event = token_i < count
        ? statement_event_for(token_i, kind, bracket_depth_before)
        : 0u;
    prefix_scan_inclusive<uint, PrefixScanU32Max, 256>(
        lane,
        statement_event,
        statement_event_prefix_values);
    uint local_statement_before = lane == 0u ? 0u : statement_event_prefix_values[lane - 1u];
    uint statement_before = max(
        statement_event_block_prefix[block_idx],
        local_statement_before);
    if (token_i < gParams.n_tokens)
        statement_context_kind[token_i] = bracket_depth_before == 0 ? (statement_before & 0xffu) : 0u;
}
