// Token relations shared by the semantic token-kind passes. Including passes
// own the buffer views and gParams.token_capacity.
//
// Delimiter ownership is read from token_enclosing_open, published once per
// token by tokens_delimiter_match_03_enclosing_opens. Each helper here applies
// the opener-kind and depth checks that turn that raw previous-smaller row
// into "the delimiter enclosing this token", so classification is a few
// reads per relation instead of a hierarchy search.

static const uint WG_SIZE = 256u;
static const uint INVALID = 0xffffffffu;
static const int INF = 2147483647;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_PLUS = 6u;
static const uint TK_ASSIGN = 8u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_AMPERSAND = 25u;
static const uint TK_MINUS = 27u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_INDEX_LBRACKET = 30u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_STRING = 32u;
static const uint TK_FLOAT = 33u;
static const uint TK_CHAR = 34u;
static const uint TK_DOT = 35u;
static const uint TK_COMMA = 36u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_SHR = 44u;
static const uint TK_PREFIX_PLUS = 58u;
static const uint TK_INFIX_PLUS = 59u;
static const uint TK_PREFIX_MINUS = 60u;
static const uint TK_INFIX_MINUS = 61u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_PUB = 66u;
static const uint TK_FN = 67u;
static const uint TK_LET = 68u;
static const uint TK_RETURN = 69u;
static const uint TK_IF = 70u;
static const uint TK_WHILE = 72u;
static const uint TK_BREAK = 73u;
static const uint TK_CONTINUE = 74u;
static const uint TK_ARROW = 75u;
static const uint TK_PARAM_LPAREN = 76u;
static const uint TK_PARAM_RPAREN = 77u;
static const uint TK_LET_ASSIGN = 81u;
static const uint TK_ARG_COMMA = 82u;
static const uint TK_ARRAY_COMMA = 83u;
static const uint TK_PARAM_COMMA = 84u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;
static const uint TK_TYPE_SEMICOLON = 87u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_CONST = 92u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;
static const uint TK_IMPORT = 96u;
static const uint TK_MODULE = 97u;
static const uint TK_IMPL = 98u;
static const uint TK_TRAIT = 99u;
static const uint TK_FOR = 100u;
static const uint TK_EXTERN = 102u;
static const uint TK_TYPE = 103u;
static const uint TK_SELF_VALUE = 105u;
static const uint TK_BOUND_COLON = 107u;
static const uint TK_TYPE_COLON = 108u;
static const uint TK_TYPE_ALIAS_ASSIGN = 110u;
static const uint TK_CONST_ASSIGN = 111u;
static const uint TK_RETURN_ARROW = 112u;
static const uint TK_MATCH_ARROW = 113u;
static const uint TK_PATH_COLON = 114u;
static const uint TK_MATCH_LBRACE = 119u;
static const uint TK_IMPL_LBRACE = 121u;
static const uint TK_TRAIT_LBRACE = 123u;
static const uint TK_STRUCT_LIT_LBRACE = 125u;
static const uint TK_STRUCT_LIT_RBRACE = 126u;
static const uint TK_STRUCT_DECL_LBRACE = 127u;
static const uint TK_ENUM_LBRACE = 129u;
static const uint TK_TYPE_ARG_LT = 131u;
static const uint TK_TYPE_ARG_GT = 132u;
static const uint TK_GENERIC_PARAM_LT = 133u;
static const uint TK_GENERIC_PARAM_GT = 134u;
static const uint TK_TYPE_ARG_COMMA = 135u;
static const uint TK_GENERIC_PARAM_COMMA = 136u;
static const uint TK_ENUM_FIELD_COMMA = 137u;
static const uint TK_MATCH_ARM_COMMA = 138u;
static const uint TK_PATTERN_COMMA = 139u;
static const uint TK_PATTERN_LPAREN = 140u;
static const uint TK_PATTERN_RPAREN = 141u;
static const uint TK_ENUM_PAYLOAD_LPAREN = 142u;
static const uint TK_ENUM_PAYLOAD_RPAREN = 143u;
static const uint TK_TYPE_AMPERSAND = 144u;
static const uint TK_BOUND_PLUS = 145u;
static const uint TK_TRAIT_METHOD_SEMICOLON = 146u;
static const uint TK_IMPL_PUB = 147u;
static const uint TK_TRAIT_PUB = 148u;
static const uint TK_WHERE_COMMA = 157u;
static const uint TK_ENUM_VARIANT_COMMA = 158u;
static const uint TK_STRUCT_FIELD_COMMA = 159u;
static const uint TK_STRUCT_LIT_COMMA = 160u;
static const uint TK_IMPORT_STRING = 161u;
static const uint TK_IMPORT_SEMICOLON = 162u;
static const uint TK_MODULE_SEMICOLON = 163u;
static const uint TK_EXTERN_SEMICOLON = 164u;
static const uint TK_TYPE_ALIAS_SEMICOLON = 165u;
static const uint TK_CONST_SEMICOLON = 166u;
static const uint TK_LET_SEMICOLON = 167u;
static const uint TK_RETURN_SEMICOLON = 168u;
static const uint TK_EXPR_SEMICOLON = 169u;
static const uint TK_BREAK_SEMICOLON = 170u;
static const uint TK_CONTINUE_SEMICOLON = 171u;
static const uint TK_IMPL_FOR = 172u;
static const uint TK_BOUND_TYPE_ARG_LT = 175u;
static const uint TK_BOUND_TYPE_ARG_GT = 176u;
static const uint TK_BOUND_TYPE_ARG_COMMA = 177u;
static const uint TK_BOUND_TYPE_AMPERSAND = 179u;
static const uint TK_INHERENT_IMPL = 180u;
static const uint TK_TRAIT_IMPL = 181u;
static const uint TK_PATH_TYPE_ARG_LT = 184u;
static const uint TK_PATH_TYPE_ARG_GT = 185u;
static const uint TK_PATH_TYPE_ARG_COMMA = 186u;
static const uint TK_EXTERN_ABI_STRING = 188u;
static const uint TK_DOT_DOT_EQUAL = 189u;
static const uint TK_RANGE_INCLUSIVE_ASSIGN = 190u;
static const uint TK_MEMBER_TYPE_ARG_GT = 191u;
static const uint TK_CONSTANT_ARGUMENT_PLUS = 192u;
static const uint TK_CONSTANT_ARGUMENT_MINUS = 193u;
static const uint STATEMENT_CONTEXT_CONST_RHS = 250u;
static const uint STATEMENT_CONTEXT_ASSIGN_RHS = 251u;
static const uint STATEMENT_CONTEXT_FOR_IN = 252u;
static const uint STATEMENT_CONTEXT_LET_RHS = 253u;
static const uint STATEMENT_CONTEXT_TYPE_ALIAS_RHS = 254u;
static const uint WHERE_CLAUSE_CONTEXT = 1u;
static const uint MATCH_PATTERN_CONTEXT = 1u;

// Parser indices are token index + 1; index 0 is the start sentinel.
uint raw_kind_at(uint parser_i, uint count)
{
    if (parser_i == 0u || parser_i > count)
        return 0u;
    return token_words[parser_i - 1u].kind;
}

uint raw_statement_context_kind(uint token_i)
{
    return token_i < gParams.token_capacity ? (statement_context_kind[token_i] & 0xffu) : 0u;
}

uint statement_context_token_kind(uint token_i)
{
    if (token_i >= gParams.token_capacity)
        return 0u;
    uint kind = statement_context_kind[token_i] & 0xffu;
    if (kind == STATEMENT_CONTEXT_CONST_RHS)
        return TK_CONST;
    if (kind == STATEMENT_CONTEXT_LET_RHS)
        return TK_LET;
    return kind == STATEMENT_CONTEXT_TYPE_ALIAS_RHS ? TK_TYPE : kind;
}

bool impl_type_context_before(uint parser_i, uint count)
{
    if (parser_i == 0u)
        return false;
    uint token_i = parser_i - 1u;
    return token_i < min(count, gParams.token_capacity) &&
           (token_impl_context_event[token_i] & 0xffu) == 1u;
}

bool where_clause_context_before(uint parser_i, uint count)
{
    if (parser_i == 0u)
        return false;
    uint token_i = parser_i - 1u;
    return token_i < count &&
           token_i < gParams.token_capacity &&
           (token_where_context_event[token_i] & 0xffu) == WHERE_CLAUSE_CONTEXT;
}

// Delimiter depths before a token (the raw stack effects of tokens_delimiters
// and the clamped angle relation).
int paren_depth_at(uint token_i)
{
    return block_prefix_paren[token_i / WG_SIZE] + depth_paren_inblock[token_i];
}

int brace_depth_at(uint token_i)
{
    return block_prefix_brace[token_i / WG_SIZE] + depth_brace_inblock[token_i];
}

int bracket_depth_at(uint token_i)
{
    return block_prefix_bracket[token_i / WG_SIZE] + depth_bracket_inblock[token_i];
}

int angle_depth_at(uint token_i)
{
    return block_prefix_angle[token_i / WG_SIZE] + depth_angle_inblock[token_i];
}

bool active_token(uint parser_i, uint count)
{
    return parser_i != 0u && parser_i - 1u < count && parser_i - 1u < gParams.token_capacity;
}

// The raw `(` enclosing the token at parser_i.
bool matching_raw_paren_open_before(uint parser_i, uint count, out uint open_i)
{
    open_i = INVALID;
    if (!active_token(parser_i, count))
        return false;
    uint token_i = parser_i - 1u;
    int depth_before = paren_depth_at(token_i);
    if (depth_before <= 0)
        return false;
    open_i = token_enclosing_open[token_i].x;
    return open_i < count &&
           token_words[open_i].kind == TK_LPAREN &&
           paren_match_depth[open_i] == depth_before - 1;
}

// The raw `[` enclosing the token at parser_i.
bool matching_raw_bracket_open_before(uint parser_i, uint count, out uint open_i)
{
    open_i = INVALID;
    if (!active_token(parser_i, count))
        return false;
    uint token_i = parser_i - 1u;
    int depth_before = bracket_depth_at(token_i);
    if (depth_before <= 0)
        return false;
    open_i = token_enclosing_open[token_i].z;
    return open_i < count &&
           token_words[open_i].kind == TK_LBRACKET &&
           bracket_match_depth[open_i] == depth_before - 1;
}

// The raw `<` enclosing the token at parser_i. A raw `>>` publishes its outer
// opener instead (matching_raw_angle_open_for_close), so this is only asked of
// other tokens.
bool matching_raw_angle_open_before(uint parser_i, uint count, out uint open_i)
{
    open_i = INVALID;
    if (!active_token(parser_i, count))
        return false;
    uint token_i = parser_i - 1u;
    int depth_before = angle_depth_at(token_i);
    open_i = token_enclosing_open[token_i].w;
    return open_i < count &&
           token_words[open_i].kind == TK_LT &&
           angle_match_depth[open_i] == depth_before - 1;
}

// The raw `<` that a raw `>` closes, or the outer one of the two that `>>`
// closes.
bool matching_raw_angle_open_for_close(uint close_parser_i, uint count, out uint open_i)
{
    open_i = INVALID;
    uint close_kind = raw_kind_at(close_parser_i, count);
    if (close_parser_i == 0u || (close_kind != TK_GT && close_kind != TK_SHR))
        return false;
    if (!active_token(close_parser_i, count))
        return false;
    uint close_i = close_parser_i - 1u;
    int owner_depth = angle_depth_at(close_i) - (close_kind == TK_SHR ? 2 : 1);
    open_i = token_enclosing_open[close_i].w;
    return open_i < count &&
           token_words[open_i].kind == TK_LT &&
           angle_match_depth[open_i] == owner_depth;
}

// The raw `{` enclosing the token at parser_i and its recorded semantic kind
// (brace classification is owned by tokens_delimiters_03_owner_local plus
// tokens_brace_context; an unrecorded brace keeps its raw kind).
bool enclosing_semantic_brace_open_before_with_index(
    uint parser_i,
    uint count,
    out uint open_i,
    out uint semantic_kind)
{
    open_i = 0u;
    semantic_kind = 0u;
    if (!active_token(parser_i, count))
        return false;
    uint token_i = parser_i - 1u;
    if (brace_depth_at(token_i) <= 0)
        return false;
    uint found = token_enclosing_open[token_i].y;
    if (found >= count || token_words[found].kind != TK_LBRACE)
        return false;
    open_i = found;
    uint recorded = brace_semantic_kind[found];
    semantic_kind = recorded != 0u ? recorded : TK_LBRACE;
    return true;
}

uint enclosing_semantic_brace_open_before(uint parser_i, uint count)
{
    uint open_i;
    uint semantic_kind;
    enclosing_semantic_brace_open_before_with_index(parser_i, count, open_i, semantic_kind);
    return semantic_kind;
}

bool in_enum_variant_context(uint parser_i, uint count)
{
    return enclosing_semantic_brace_open_before(parser_i, count) == TK_ENUM_LBRACE;
}

bool raw_angle_open_can_contain_bound_colon(uint open_parser_i, uint count)
{
    uint prev_raw = raw_kind_at(open_parser_i - 1u, count);
    uint prev2_raw = raw_kind_at(open_parser_i - 2u, count);
    if (prev_raw == TK_IMPL || prev2_raw == TK_FN || prev2_raw == TK_STRUCT ||
        prev2_raw == TK_ENUM || prev2_raw == TK_TRAIT || prev2_raw == TK_TYPE)
    {
        return true;
    }

    return prev_raw == TK_IDENT &&
           (prev2_raw == TK_COLON || prev2_raw == TK_ARROW || prev2_raw == TK_AMPERSAND ||
            prev2_raw == TK_LT || prev2_raw == TK_COMMA || prev2_raw == TK_LBRACKET ||
            impl_type_context_before(open_parser_i, count) ||
            where_clause_context_before(open_parser_i, count));
}

bool raw_kind_can_end_bound_plus_lhs(uint kind)
{
    return kind == TK_IDENT ||
           kind == TK_GT ||
           kind == TK_SELF_VALUE;
}

// Whether the raw `:` or `+` at parser_i introduces or continues trait
// bounds: inside a where clause, or inside an angle list that can declare
// bounded parameters.
bool bound_context(uint parser_i, uint count)
{
    if (raw_kind_at(parser_i, count) == TK_COLON)
    {
        if (raw_kind_at(parser_i - 2u, count) == TK_CONST)
            return false;
    }
    else if (!raw_kind_can_end_bound_plus_lhs(raw_kind_at(parser_i - 1u, count)))
    {
        return false;
    }

    if (where_clause_context_before(parser_i, count))
        return true;

    uint open_i;
    if (!matching_raw_angle_open_before(parser_i, count, open_i))
        return false;
    // A comparison's `<` never closes, so its raw angle depth stays open over
    // later statements. A generic parameter list and its bounds lie within one
    // statement context (the statement event scan records its start), so an
    // angle opened in an earlier statement cannot own this `:` or `+`.
    if (statement_context_kind[open_i] != statement_context_kind[parser_i - 1u])
        return false;

    return raw_angle_open_can_contain_bound_colon(open_i + 1u, count);
}

bool bound_type_context_before(uint parser_i, uint count)
{
    // The bound `:` or `+` that this token directly follows, or that the
    // identifier before it follows.
    uint prev = raw_kind_at(parser_i - 1u, count);
    uint anchor_i = parser_i - 1u;
    if (prev != TK_COLON && prev != TK_PLUS)
    {
        if (where_clause_context_before(parser_i, count) &&
            (prev == TK_LT || prev == TK_COMMA || prev == TK_AMPERSAND))
        {
            return true;
        }
        if (prev != TK_IDENT)
            return false;
        if (where_clause_context_before(parser_i, count))
            return true;

        anchor_i = parser_i - 2u;
        uint kind = raw_kind_at(anchor_i, count);
        if (kind == TK_COLON)
        {
            if (raw_kind_at(anchor_i - 1u, count) == TK_COLON ||
                raw_kind_at(anchor_i + 1u, count) == TK_COLON)
            {
                return false;
            }
        }
        else if (kind != TK_PLUS)
        {
            return false;
        }
    }
    return bound_context(anchor_i, count);
}

uint semantic_colon_kind_for(uint parser_i, uint count)
{
    uint prev_raw = raw_kind_at(parser_i - 1u, count);
    uint next_raw = raw_kind_at(parser_i + 1u, count);
    if (prev_raw == TK_COLON || next_raw == TK_COLON)
        return TK_PATH_COLON;
    if (enclosing_semantic_brace_open_before(parser_i, count) == TK_STRUCT_LIT_LBRACE)
        return TK_COLON;
    if (bound_context(parser_i, count))
        return TK_BOUND_COLON;
    return TK_TYPE_COLON;
}
