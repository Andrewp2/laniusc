// Statement phase block summaries for token retagging.
//
// tokens_brace_context records the statement owner before each token. This pass
// turns the type-alias `=` boundary into another prefix-scanned statement event
// so later token classifiers can ask "am I in the type alias RHS?" without
// walking backward through source tokens.

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
StructuredBuffer<int> depth_bracket_inblock;
StructuredBuffer<int> block_prefix_bracket;
StructuredBuffer<uint> statement_context_kind;

RWStructuredBuffer<uint> statement_event_block;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TK_ASSIGN = 8u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_LET = 68u;
static const uint TK_RETURN = 69u;
static const uint TK_BREAK = 73u;
static const uint TK_CONTINUE = 74u;
static const uint TK_IMPORT = 96u;
static const uint TK_MODULE = 97u;
static const uint TK_EXTERN = 102u;
static const uint TK_TYPE = 103u;
static const uint TK_CONST = 92u;

static const uint STATEMENT_CONTEXT_TYPE_ALIAS_RHS = 254u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_token_count()
{
    return min(lexer_token_count[0], gParams.n_tokens);
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

uint statement_context_token_kind(uint context)
{
    uint kind = context & 0xffu;
    return kind == STATEMENT_CONTEXT_TYPE_ALIAS_RHS ? TK_TYPE : kind;
}

uint encode_statement_event(uint token_i, uint payload)
{
    return ((token_i + 1u) << 8u) | (payload & 0xffu);
}

uint statement_phase_event_for(uint token_i, uint kind, int bracket_depth_before)
{
    if (bracket_depth_before != 0)
        return 0u;
    if (is_statement_starter(kind))
        return encode_statement_event(token_i, kind);
    if (is_statement_reset_boundary(kind))
        return encode_statement_event(token_i, 0u);
    if (kind == TK_ASSIGN && statement_context_token_kind(statement_context_kind[token_i]) == TK_TYPE)
        return encode_statement_event(token_i, STATEMENT_CONTEXT_TYPE_ALIAS_RHS);
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
    int bracket_depth_before = token_i < gParams.n_tokens
        ? block_prefix_bracket[block_idx] + depth_bracket_inblock[token_i]
        : 0;
    uint event = token_i < count
        ? statement_phase_event_for(token_i, kind, bracket_depth_before)
        : 0u;
    uint prefix = prefix_scan_u32_max_256(lane, event);
    if (lane + 1u == WG_SIZE)
        statement_event_block[block_idx] = prefix;
}
