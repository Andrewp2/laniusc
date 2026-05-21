// Global-depth top-level brace owner summaries.
//
// The first delimiter pass computes brace depth only within a 256-token block.
// A block can start inside a function, so local depth alone cannot identify
// top-level function-body opens. This pass runs after the brace-depth block
// prefix exists and records the latest globally top-level brace owner per block.

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

RWStructuredBuffer<uint> top_brace_owner_block;
RWStructuredBuffer<uint> brace_semantic_kind;
RWStructuredBuffer<uint> statement_event_block;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_RPAREN = 5u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_LPAREN = 4u;
static const uint TK_STRING = 32u;
static const uint TK_FLOAT = 33u;
static const uint TK_CHAR = 34u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_FN = 67u;
static const uint TK_LET = 68u;
static const uint TK_RETURN = 69u;
static const uint TK_IF = 70u;
static const uint TK_ELSE = 71u;
static const uint TK_WHILE = 72u;
static const uint TK_BREAK = 73u;
static const uint TK_CONTINUE = 74u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;
static const uint TK_MATCH = 95u;
static const uint TK_IMPORT = 96u;
static const uint TK_MODULE = 97u;
static const uint TK_IMPL = 98u;
static const uint TK_TRAIT = 99u;
static const uint TK_FOR = 100u;
static const uint TK_EXTERN = 102u;
static const uint TK_TYPE = 103u;
static const uint TK_SELF_VALUE = 105u;
static const uint TK_CONST = 92u;
static const uint TK_MATCH_LBRACE = 119u;
static const uint TK_FN_BLOCK_LBRACE = 149u;
static const uint TK_IMPL_LBRACE = 121u;
static const uint TK_TRAIT_LBRACE = 123u;
static const uint TK_STRUCT_LIT_LBRACE = 125u;
static const uint TK_STRUCT_DECL_LBRACE = 127u;
static const uint TK_ENUM_LBRACE = 129u;
static const uint TK_DEFERRED_FN_BLOCK_LBRACE = 0x80000000u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
}

uint raw_kind_at(uint parser_i, uint count)
{
    if (parser_i == 0u || parser_i > count)
        return 0u;
    return token_words[parser_i - 1u].kind;
}

bool semantic_token_ends_primary(uint kind)
{
    return kind == TK_IDENT ||
           kind == TK_INT ||
           kind == TK_RPAREN ||
           kind == TK_RBRACKET ||
           kind == TK_RBRACE ||
           kind == TK_STRING ||
           kind == TK_FLOAT ||
           kind == TK_CHAR ||
           kind == TK_TRUE ||
           kind == TK_FALSE ||
           kind == TK_SELF_VALUE;
}

bool raw_kind_starts_item(uint kind)
{
    return kind == TK_FN || kind == TK_ENUM || kind == TK_STRUCT ||
           kind == TK_IMPL || kind == TK_TRAIT;
}

uint top_level_brace_open_kind_for(uint parser_i, uint count)
{
    uint prev_raw = raw_kind_at(parser_i - 1u, count);
    if (prev_raw == TK_RPAREN)
    {
        uint open_i = parser_i - 1u;
        uint depth = 0u;
        [loop]
        for (uint guard = 0u; guard < 512u && open_i > 0u; guard += 1u)
        {
            open_i -= 1u;
            uint kind = raw_kind_at(open_i, count);
            if (kind == TK_RPAREN)
            {
                depth += 1u;
                continue;
            }
            if (kind != TK_LPAREN)
                continue;
            if (depth == 0u)
            {
                uint owner = raw_kind_at(open_i - 1u, count);
                if (owner == TK_MATCH)
                    return TK_MATCH_LBRACE;
                if (owner == TK_IF || owner == TK_WHILE)
                    return TK_LBRACE;
                break;
            }
            depth -= 1u;
        }
    }

    uint j = parser_i;
    uint paren_depth = 0u;
    uint bracket_depth = 0u;
    uint angle_depth = 0u;

    [loop]
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = raw_kind_at(j, count);
        if (kind == TK_RPAREN)
        {
            paren_depth += 1u;
            continue;
        }
        if (kind == TK_LPAREN && paren_depth > 0u)
        {
            paren_depth -= 1u;
            continue;
        }
        if (kind == TK_RBRACKET)
        {
            bracket_depth += 1u;
            continue;
        }
        if (kind == TK_LBRACKET && bracket_depth > 0u)
        {
            bracket_depth -= 1u;
            continue;
        }
        if (kind == TK_GT)
        {
            angle_depth += 1u;
            continue;
        }
        if (kind == TK_LT && angle_depth > 0u)
        {
            angle_depth -= 1u;
            continue;
        }
        if (paren_depth != 0u || bracket_depth != 0u || angle_depth != 0u)
            continue;

        if (kind == TK_FN)
            return TK_FN_BLOCK_LBRACE;
        if (kind == TK_IMPL)
            return TK_IMPL_LBRACE;
        if (kind == TK_TRAIT)
            return TK_TRAIT_LBRACE;
        if (kind == TK_STRUCT)
            return TK_STRUCT_DECL_LBRACE;
        if (kind == TK_ENUM)
            return TK_ENUM_LBRACE;
        if (kind == TK_MATCH)
            return TK_MATCH_LBRACE;
        if (kind == TK_IF || kind == TK_ELSE || kind == TK_WHILE || kind == TK_FOR)
            return TK_LBRACE;
        if (kind == TK_SEMICOLON || kind == TK_LBRACE || raw_kind_starts_item(kind))
            break;
    }

    if (semantic_token_ends_primary(prev_raw))
        return TK_STRUCT_LIT_LBRACE;

    return TK_LBRACE;
}

uint encode_owner_event(uint token_i, uint owner_kind)
{
    return owner_kind == 0u ? 0u : ((token_i + 1u) << 8u) | (owner_kind & 0xffu);
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
           kind == TK_BREAK ||
           kind == TK_CONTINUE;
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
    uint parser_i = token_i + 1u;
    uint kind = token_i < count ? token_words[token_i].kind : 0u;
    int global_depth_before = token_i < gParams.n_tokens
        ? block_prefix_brace[block_idx] + depth_brace_inblock[token_i]
        : 0;
    int global_bracket_depth_before = token_i < gParams.n_tokens
        ? block_prefix_bracket[block_idx] + depth_bracket_inblock[token_i]
        : 0;

    uint owner_event = 0u;
    uint open_kind = 0u;
    if (token_i < count && kind == TK_LBRACE)
    {
        uint candidate = top_level_brace_open_kind_for(parser_i, count);
        bool defer_impl_method_body = global_depth_before != 0 && candidate == TK_FN_BLOCK_LBRACE;
        open_kind = defer_impl_method_body ? TK_DEFERRED_FN_BLOCK_LBRACE : candidate;
        if (global_depth_before == 0)
            owner_event = encode_owner_event(token_i, open_kind);
    }

    if (token_i < gParams.n_tokens)
        brace_semantic_kind[token_i] = open_kind;

    uint owner_prefix = prefix_scan_u32_max_256(lane, owner_event);
    if (lane + 1u == WG_SIZE)
        top_brace_owner_block[block_idx] = owner_prefix;

    uint statement_event = token_i < count
        ? statement_event_for(token_i, kind, global_bracket_depth_before)
        : 0u;
    uint statement_prefix = prefix_scan_u32_max_256(lane, statement_event);
    if (lane + 1u == WG_SIZE)
        statement_event_block[block_idx] = statement_prefix;
}
