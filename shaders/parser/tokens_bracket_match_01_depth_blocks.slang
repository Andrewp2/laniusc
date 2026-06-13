import prefix_scan;

struct Params
{
    uint n_tokens;
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

RWStructuredBuffer<uint> bracket_semantic_kind;
RWStructuredBuffer<int> bracket_match_depth;
RWStructuredBuffer<int> bracket_match_block_min;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_RPAREN = 5u;
static const uint TK_ASSIGN = 8u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_STRING = 32u;
static const uint TK_FLOAT = 33u;
static const uint TK_CHAR = 34u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_ARROW = 75u;
static const uint TK_TYPE = 103u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_SELF_VALUE = 105u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;
static const uint TK_PATTERN_RPAREN = 141u;
static const uint TK_ENUM_PAYLOAD_RPAREN = 143u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_INDEX_LBRACKET = 30u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_AMPERSAND = 25u;
static const uint STATEMENT_CONTEXT_TYPE_ALIAS_RHS = 254u;
static const int INF = 2147483647;

groupshared int local_depth[256];

public struct PrefixScanI32Min : IPrefixScanOp<int>
{
    public static int identity()
    {
        return INF;
    }

    public static int combine(int left, int right)
    {
        return min(left, right);
    }
}

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

bool in_type_alias_rhs_context(uint parser_i, uint count)
{
    uint token_i = parser_i - 1u;
    return token_i < count &&
           (statement_context_kind[token_i] & 0xffu) == STATEMENT_CONTEXT_TYPE_ALIAS_RHS;
}

bool semantic_token_ends_primary(uint kind)
{
    return kind == TK_IDENT ||
           kind == TK_INT ||
           kind == TK_RPAREN ||
           kind == TK_RBRACKET ||
           kind == TK_CALL_RPAREN ||
           kind == TK_GROUP_RPAREN ||
           kind == TK_ARRAY_RBRACKET ||
           kind == TK_INDEX_RBRACKET ||
           kind == TK_TYPE_ARRAY_RBRACKET ||
           kind == TK_PATTERN_RPAREN ||
           kind == TK_ENUM_PAYLOAD_RPAREN ||
           kind == TK_STRING ||
           kind == TK_FLOAT ||
           kind == TK_CHAR ||
           kind == TK_TRUE ||
           kind == TK_FALSE ||
           kind == TK_SELF_VALUE;
}

uint bracket_open_kind(uint parser_i, uint count)
{
    uint prev = raw_kind_at(parser_i - 1u, count);
    if (in_type_alias_rhs_context(parser_i, count))
        return TK_TYPE_ARRAY_LBRACKET;
    if (prev == TK_COLON || prev == TK_ARROW || prev == TK_AMPERSAND)
        return TK_TYPE_ARRAY_LBRACKET;
    return semantic_token_ends_primary(prev) ? TK_INDEX_LBRACKET : TK_ARRAY_LBRACKET;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    uint lane = ltid.x;
    uint token_i = block_idx * WG_SIZE + lane;
    uint count = active_token_count();

    int event_depth = INF;
    uint semantic_kind = 0u;
    if (token_i < gParams.n_tokens && token_i < count)
    {
        uint kind = token_words[token_i].kind;
        int depth_before = block_prefix_bracket[block_idx] + depth_bracket_inblock[token_i];
        if (kind == TK_LBRACKET)
        {
            event_depth = depth_before;
            semantic_kind = bracket_open_kind(token_i + 1u, count);
        }
        else if (kind == TK_RBRACKET)
        {
            event_depth = depth_before - 1;
        }
        bracket_semantic_kind[token_i] = semantic_kind;
        bracket_match_depth[token_i] = event_depth;
    }
    else if (token_i < gParams.n_tokens)
    {
        bracket_semantic_kind[token_i] = 0u;
        bracket_match_depth[token_i] = INF;
    }

    int block_min = prefix_scan_inclusive<int, PrefixScanI32Min, 256>(
        lane,
        event_depth,
        local_depth);

    if (lane == WG_SIZE - 1u)
        bracket_match_block_min[block_idx] = block_min;
}
