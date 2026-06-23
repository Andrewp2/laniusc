struct Params
{
    uint token_capacity;
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
StructuredBuffer<uint> token_impl_context_event;
StructuredBuffer<uint> token_type_path_context_kind;

RWStructuredBuffer<uint> semantic_token_kinds;

static const uint TK_IDENT = 1u;
static const uint TK_DOT = 35u;
static const uint TK_LET = 68u;
static const uint TK_PARAM_LPAREN = 76u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_PARAM_COMMA = 84u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_IMPL = 98u;
static const uint TK_TRAIT = 99u;
static const uint TK_FOR = 100u;
static const uint TK_TYPE = 103u;
static const uint TK_WHERE = 104u;
static const uint TK_SELF_VALUE = 105u;
static const uint TK_BOUND_COLON = 107u;
static const uint TK_TYPE_COLON = 108u;
static const uint TK_MEMBER_IDENT = 109u;
static const uint TK_TYPE_ALIAS_ASSIGN = 110u;
static const uint TK_RETURN_ARROW = 112u;
static const uint TK_TYPE_ARG_LT = 131u;
static const uint TK_GENERIC_PARAM_LT = 133u;
static const uint TK_GENERIC_PARAM_GT = 134u;
static const uint TK_TYPE_ARG_COMMA = 135u;
static const uint TK_GENERIC_PARAM_COMMA = 136u;
static const uint TK_ENUM_FIELD_COMMA = 137u;
static const uint TK_ENUM_PAYLOAD_LPAREN = 142u;
static const uint TK_TYPE_AMPERSAND = 144u;
static const uint TK_BOUND_PLUS = 145u;
static const uint TK_TYPE_ALIAS_NAME_IDENT = 153u;
static const uint TK_TRAIT_NAME_IDENT = 154u;
static const uint TK_GENERIC_PARAM_IDENT = 155u;
static const uint TK_WHERE_IDENT = 156u;
static const uint TK_WHERE_COMMA = 157u;
static const uint TK_PARAM_SELF_VALUE = 173u;
static const uint TK_BOUND_TYPE_IDENT = 174u;
static const uint TK_BOUND_TYPE_ARG_LT = 175u;
static const uint TK_BOUND_TYPE_ARG_COMMA = 177u;
static const uint TK_PARAM_SELF_REF_VALUE = 178u;
static const uint TK_ASSIGN = 8u;
static const uint TK_DOT_DOT = 182u;
static const uint TK_DOT_DOT_EQUAL = 189u;
static const uint TK_RANGE_END_IDENT = 183u;
static const uint TK_PATH_TYPE_ARG_LT = 184u;
static const uint TK_PATH_TYPE_ARG_COMMA = 186u;
static const uint TK_PATH_GENERIC_IDENT = 187u;
static const uint IMPL_HEADER_CONTEXT = 1u;

uint raw_kind_at(uint parser_i, uint count)
{
    if (parser_i == 0u || parser_i > count)
        return 0u;
    return token_words[parser_i - 1u].kind;
}

uint semantic_kind_at(uint parser_i, uint count)
{
    if (parser_i == 0u || parser_i > count + 1u)
        return 0u;
    return semantic_token_kinds[parser_i];
}

uint previous_symbol_kind(uint parser_i, uint count)
{
    uint prev_parser_i = parser_i - 1u;
    uint prev_raw = raw_kind_at(prev_parser_i, count);
    // This pass writes identifier/self slots. For those previous-token cases,
    // the first pass intentionally left the raw value, which is also what the
    // old on-the-fly previous-token classifier returned.
    if (prev_raw == TK_IDENT || prev_raw == TK_SELF_VALUE)
        return prev_raw;
    return semantic_kind_at(prev_parser_i, count);
}

bool impl_type_context_before(uint parser_i, uint count)
{
    if (parser_i == 0u)
        return false;
    uint token_i = parser_i - 1u;
    return token_i < count &&
           token_i < gParams.token_capacity &&
           (token_impl_context_event[token_i] & 0xffu) == IMPL_HEADER_CONTEXT;
}

uint type_context_identifier_kind(uint prev, bool impl_context)
{
    if (prev == TK_BOUND_COLON || prev == TK_BOUND_PLUS ||
        prev == TK_BOUND_TYPE_ARG_LT || prev == TK_BOUND_TYPE_ARG_COMMA)
        return TK_BOUND_TYPE_IDENT;
    if (prev == TK_TYPE_COLON || prev == TK_RETURN_ARROW ||
        prev == TK_TYPE_ALIAS_ASSIGN || prev == TK_TYPE_AMPERSAND ||
        prev == TK_TYPE_ARG_LT || prev == TK_TYPE_ARG_COMMA ||
        prev == TK_PATH_TYPE_ARG_LT || prev == TK_PATH_TYPE_ARG_COMMA ||
        prev == TK_GENERIC_PARAM_LT || prev == TK_GENERIC_PARAM_COMMA ||
        prev == TK_TYPE_ARRAY_LBRACKET || impl_context)
        return TK_TYPE_IDENT;
    return 0u;
}

uint identifier_kind_for(uint parser_i, uint count)
{
    uint prev_raw = raw_kind_at(parser_i - 1u, count);
    uint prev_prev_raw = raw_kind_at(parser_i - 2u, count);
    if (prev_raw == TK_DOT)
        return TK_MEMBER_IDENT;
    if (prev_raw == TK_DOT_DOT || prev_raw == TK_DOT_DOT_EQUAL ||
        (prev_raw == TK_ASSIGN && prev_prev_raw == TK_DOT_DOT_EQUAL))
        return TK_RANGE_END_IDENT;
    if (prev_raw == TK_LET)
        return TK_LET_IDENT;
    if (prev_raw == TK_TYPE)
        return TK_TYPE_ALIAS_NAME_IDENT;
    if (prev_raw == TK_TRAIT)
        return TK_TRAIT_NAME_IDENT;
    if (prev_raw == TK_WHERE)
        return TK_WHERE_IDENT;

    uint prev = previous_symbol_kind(parser_i, count);
    if (prev == TK_GENERIC_PARAM_LT || prev == TK_GENERIC_PARAM_COMMA)
        return TK_GENERIC_PARAM_IDENT;
    if (prev == TK_WHERE_COMMA)
        return TK_WHERE_IDENT;

    uint token_i = parser_i - 1u;
    uint qualified_kind = token_i < gParams.token_capacity
        ? (token_type_path_context_kind[token_i] & 0xffu)
        : 0u;
    if (qualified_kind != 0u)
        return qualified_kind;

    uint type_context_kind = type_context_identifier_kind(
        prev,
        impl_type_context_before(parser_i, count));
    if (type_context_kind != 0u)
        return type_context_kind;
    if (prev_raw == TK_IMPL || prev_raw == TK_FOR ||
        prev == TK_GENERIC_PARAM_GT || impl_type_context_before(parser_i, count))
    {
        if (impl_type_context_before(parser_i, count))
            return TK_TYPE_IDENT;
    }
    if (prev == TK_PARAM_LPAREN || prev == TK_PARAM_COMMA)
        return TK_PARAM_IDENT;
    if (prev == TK_TYPE_ARRAY_LBRACKET)
        return TK_TYPE_IDENT;
    if (prev == TK_ENUM_PAYLOAD_LPAREN || prev == TK_ENUM_FIELD_COMMA)
        return TK_TYPE_IDENT;
    if (semantic_kind_at(parser_i + 1u, count) == TK_PATH_TYPE_ARG_LT)
        return TK_PATH_GENERIC_IDENT;
    return TK_IDENT;
}

uint self_kind_for(uint parser_i, uint count)
{
    uint prev = previous_symbol_kind(parser_i, count);
    if (prev == TK_TYPE_AMPERSAND)
        return TK_PARAM_SELF_REF_VALUE;
    if (prev == TK_PARAM_LPAREN || prev == TK_PARAM_COMMA)
        return TK_PARAM_SELF_VALUE;
    return TK_SELF_VALUE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint parser_i = tid.x;
    uint count = min(lexer_token_count[0], gParams.token_capacity);
    if (parser_i == 0u || parser_i > count)
        return;

    uint raw_kind = token_words[parser_i - 1u].kind;
    if (raw_kind == TK_IDENT)
    {
        semantic_token_kinds[parser_i] = identifier_kind_for(parser_i, count);
    }
    else if (raw_kind == TK_SELF_VALUE)
    {
        semantic_token_kinds[parser_i] = self_kind_for(parser_i, count);
    }
}
