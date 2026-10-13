// Projects bracket roles after statement context is available. Raw delimiter
// depths and their search hierarchy are published independently, before this pass.
struct Params { uint n_tokens; };
ConstantBuffer<Params> gParams;
struct TokenIn { uint kind; uint start; uint len; };
StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> lexer_token_count;
StructuredBuffer<uint> statement_context_kind;
RWStructuredBuffer<uint> bracket_semantic_kind;
static const uint MAX_GROUPS_X = 65535u;
static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_AMPERSAND = 25u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_INDEX_LBRACKET = 30u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_STRING = 32u;
static const uint TK_FLOAT = 33u;
static const uint TK_CHAR = 34u;
static const uint TK_COLON = 38u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_ARROW = 75u;
static const uint TK_PARAM_LPAREN = 76u;
static const uint TK_PARAM_RPAREN = 77u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_SELF_VALUE = 105u;
static const uint TK_TYPE_ARG_LT = 131u;
static const uint TK_TYPE_ARG_GT = 132u;
static const uint TK_GENERIC_PARAM_LT = 133u;
static const uint TK_GENERIC_PARAM_GT = 134u;
static const uint TK_PATTERN_RPAREN = 141u;
static const uint TK_ENUM_PAYLOAD_RPAREN = 143u;
static const uint TK_BOUND_TYPE_ARG_LT = 175u;
static const uint TK_BOUND_TYPE_ARG_GT = 176u;
static const uint TK_PATH_TYPE_ARG_LT = 184u;
static const uint TK_PATH_TYPE_ARG_GT = 185u;
static const uint STATEMENT_CONTEXT_TYPE_ALIAS_RHS = 254u;

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
    return kind == TK_IDENT || kind == TK_INT || kind == TK_RPAREN ||
           kind == TK_RBRACKET || kind == TK_CALL_RPAREN || kind == TK_GROUP_RPAREN ||
           kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET ||
           kind == TK_TYPE_ARRAY_RBRACKET || kind == TK_PATTERN_RPAREN ||
           kind == TK_ENUM_PAYLOAD_RPAREN || kind == TK_STRING || kind == TK_FLOAT ||
           kind == TK_CHAR || kind == TK_TRUE || kind == TK_FALSE ||
           kind == TK_SELF_VALUE;
}

uint bracket_open_kind(uint parser_i, uint count)
{
    uint previous = raw_kind_at(parser_i - 1u, count);
    if (in_type_alias_rhs_context(parser_i, count))
        return TK_TYPE_ARRAY_LBRACKET;
    if (previous == TK_COLON || previous == TK_ARROW || previous == TK_AMPERSAND)
        return TK_TYPE_ARRAY_LBRACKET;
    return semantic_token_ends_primary(previous) ? TK_INDEX_LBRACKET : TK_ARRAY_LBRACKET;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint token_i = (gid.x + gid.y * MAX_GROUPS_X) * 256u + ltid.x;
    if (token_i >= gParams.n_tokens) return;
    uint count = min(lexer_token_count[0], gParams.n_tokens);
    bracket_semantic_kind[token_i] = token_i < count &&
        token_words[token_i].kind == TK_LBRACKET
        ? bracket_open_kind(token_i + 1u, count) : 0u;
}
