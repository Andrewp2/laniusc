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
StructuredBuffer<uint> token_count;

// [0] ok, [1] first error token, [2] error code, [3] detail
RWStructuredBuffer<uint> status;
StructuredBuffer<int> depth_paren_inblock;
StructuredBuffer<int> depth_bracket_inblock;
StructuredBuffer<int> depth_brace_inblock;
StructuredBuffer<int> block_prefix_paren;
StructuredBuffer<int> block_prefix_bracket;
StructuredBuffer<int> block_prefix_brace;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint ERR_UNEXPECTED_TOKEN = 1u;
static const uint ERR_EXPECTED_TOKEN = 2u;
static const uint ERR_MISSING_SEMICOLON = 3u;
static const uint ERR_STMT_OVERLAP = 4u;
static const uint ERR_UNBALANCED_DELIMITER = 5u;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_PLUS = 6u;
static const uint TK_STAR = 7u;
static const uint TK_ASSIGN = 8u;
static const uint TK_SLASH = 9u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LE = 14u;
static const uint TK_GE = 15u;
static const uint TK_EQEQ = 16u;
static const uint TK_ANDAND = 17u;
static const uint TK_OROR = 18u;
static const uint TK_NOT = 19u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_AMPERSAND = 25u;
static const uint TK_PIPE = 26u;
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
static const uint TK_NOT_EQUAL = 40u;
static const uint TK_PERCENT = 41u;
static const uint TK_CARET = 42u;
static const uint TK_SHL = 43u;
static const uint TK_SHR = 44u;
static const uint TK_TILDE = 45u;
static const uint TK_PLUS_ASSIGN = 46u;
static const uint TK_MINUS_ASSIGN = 47u;
static const uint TK_STAR_ASSIGN = 48u;
static const uint TK_SLASH_ASSIGN = 49u;
static const uint TK_PERCENT_ASSIGN = 50u;
static const uint TK_CARET_ASSIGN = 51u;
static const uint TK_SHL_ASSIGN = 52u;
static const uint TK_SHR_ASSIGN = 53u;
static const uint TK_AMP_ASSIGN = 54u;
static const uint TK_PIPE_ASSIGN = 55u;
static const uint TK_INC = 56u;
static const uint TK_DEC = 57u;
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
static const uint TK_ELSE = 71u;
static const uint TK_WHILE = 72u;
static const uint TK_BREAK = 73u;
static const uint TK_CONTINUE = 74u;
static const uint TK_ARROW = 75u;
static const uint TK_PARAM_LPAREN = 76u;
static const uint TK_PARAM_RPAREN = 77u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_LET_ASSIGN = 81u;
static const uint TK_ARG_COMMA = 82u;
static const uint TK_ARRAY_COMMA = 83u;
static const uint TK_PARAM_COMMA = 84u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;
static const uint TK_TYPE_SEMICOLON = 87u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_IF_RBRACE = 89u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint token_kind(uint i)
{
    uint n_active = active_token_count();
    return i < n_active ? token_words[i].kind : 0u;
}

void record_error(uint token_i, uint code, uint detail)
{
    uint old;
    InterlockedMin(status[1], token_i, old);
    if (token_i <= old)
    {
        status[0] = 0u;
        status[2] = code;
        status[3] = detail;
    }
}

bool is_stmt_keyword(uint kind)
{
    return kind == TK_LET || kind == TK_RETURN || kind == TK_IF || kind == TK_WHILE ||
           kind == TK_BREAK || kind == TK_CONTINUE || kind == TK_FN;
}

bool is_stmt_boundary(uint kind)
{
    return kind == TK_RBRACE || kind == TK_IF_RBRACE || kind == TK_ELSE || is_stmt_keyword(kind);
}

bool is_type_start(uint kind)
{
    return kind == TK_TYPE_IDENT || kind == TK_IDENT || kind == TK_TYPE_ARRAY_LBRACKET ||
           kind == TK_ARRAY_LBRACKET || kind == TK_LBRACKET;
}

bool is_assignment_operator(uint kind)
{
    return kind == TK_ASSIGN || kind == TK_PLUS_ASSIGN || kind == TK_MINUS_ASSIGN ||
           kind == TK_STAR_ASSIGN || kind == TK_SLASH_ASSIGN || kind == TK_PERCENT_ASSIGN ||
           kind == TK_CARET_ASSIGN || kind == TK_SHL_ASSIGN || kind == TK_SHR_ASSIGN ||
           kind == TK_AMP_ASSIGN || kind == TK_PIPE_ASSIGN;
}

bool is_binary_operator(uint kind)
{
    return kind == TK_INFIX_PLUS || kind == TK_INFIX_MINUS || kind == TK_STAR ||
           kind == TK_SLASH || kind == TK_PERCENT || kind == TK_LT || kind == TK_GT ||
           kind == TK_LE || kind == TK_GE || kind == TK_EQEQ || kind == TK_NOT_EQUAL ||
           kind == TK_ANDAND || kind == TK_OROR || kind == TK_AMPERSAND || kind == TK_PIPE ||
           kind == TK_CARET || kind == TK_SHL || kind == TK_SHR;
}

bool is_expr_start(uint kind)
{
    return kind == TK_IDENT || kind == TK_INT || kind == TK_FLOAT || kind == TK_STRING ||
           kind == TK_TRUE || kind == TK_FALSE ||
           kind == TK_CHAR || kind == TK_GROUP_LPAREN || kind == TK_LPAREN ||
           kind == TK_ARRAY_LBRACKET || kind == TK_LBRACKET || kind == TK_PREFIX_PLUS ||
           kind == TK_PREFIX_MINUS || kind == TK_NOT || kind == TK_TILDE || kind == TK_INC ||
           kind == TK_DEC;
}

bool is_expr_end(uint kind)
{
    return kind == TK_IDENT || kind == TK_INT || kind == TK_FLOAT || kind == TK_STRING ||
           kind == TK_TRUE || kind == TK_FALSE ||
           kind == TK_CHAR || kind == TK_GROUP_RPAREN || kind == TK_RPAREN ||
           kind == TK_CALL_RPAREN || kind == TK_INDEX_RBRACKET || kind == TK_ARRAY_RBRACKET ||
           kind == TK_RBRACKET || kind == TK_INC || kind == TK_DEC;
}

int paren_depth_before(uint i)
{
    uint block_idx = i / WG_SIZE;
    return block_prefix_paren[block_idx] + depth_paren_inblock[i];
}

int bracket_depth_before(uint i)
{
    uint block_idx = i / WG_SIZE;
    return block_prefix_bracket[block_idx] + depth_bracket_inblock[i];
}

int brace_depth_before(uint i)
{
    uint block_idx = i / WG_SIZE;
    return block_prefix_brace[block_idx] + depth_brace_inblock[i];
}

bool same_delimiter_depth_before(uint a, uint b)
{
    return paren_depth_before(a) == paren_depth_before(b) &&
           bracket_depth_before(a) == bracket_depth_before(b) &&
           brace_depth_before(a) == brace_depth_before(b);
}

uint find_before_boundary_at_depth(uint start_i, uint want, uint base_i)
{
    uint n_active = active_token_count();
    for (uint j = start_i; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (!same_delimiter_depth_before(base_i, j))
            continue;
        if (kind == want)
            return j;
        if (is_stmt_boundary(kind))
            return INVALID;
    }
    return INVALID;
}

uint find_stmt_semicolon(uint start_i)
{
    return find_before_boundary_at_depth(start_i + 1u, TK_SEMICOLON, start_i);
}

uint find_let_assign(uint start_i, uint end_i, uint base_i)
{
    uint n_active = active_token_count();
    for (uint j = start_i; j < end_i && j < n_active; j += 1u)
    {
        if (!same_delimiter_depth_before(base_i, j))
            continue;
        uint kind = token_kind(j);
        if (kind == TK_LET_ASSIGN || kind == TK_ASSIGN)
            return j;
    }
    return INVALID;
}

bool has_statement_keyword_before(uint start_i, uint end_i, uint base_i)
{
    uint n_active = active_token_count();
    for (uint j = start_i; j < end_i && j < n_active; j += 1u)
    {
        if (!same_delimiter_depth_before(base_i, j))
            continue;
        if (is_stmt_keyword(token_kind(j)))
            return true;
    }
    return false;
}

uint find_condition_close(uint start_i)
{
    uint n_active = active_token_count();
    int open_paren_depth = paren_depth_before(start_i);
    int open_bracket_depth = bracket_depth_before(start_i);
    int open_brace_depth = brace_depth_before(start_i);
    for (uint j = start_i + 1u; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        bool at_condition_depth = paren_depth_before(j) == open_paren_depth + 1 &&
                                  bracket_depth_before(j) == open_bracket_depth &&
                                  brace_depth_before(j) == open_brace_depth;
        if ((kind == TK_GROUP_RPAREN || kind == TK_RPAREN) && at_condition_depth)
            return j;
        if ((kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_SEMICOLON ||
             kind == TK_RBRACE || kind == TK_IF_RBRACE) &&
            at_condition_depth)
            return INVALID;
    }
    return INVALID;
}

uint delimiter_class(uint kind)
{
    if (kind == TK_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_CALL_LPAREN ||
        kind == TK_PARAM_LPAREN || kind == TK_RPAREN || kind == TK_GROUP_RPAREN ||
        kind == TK_CALL_RPAREN || kind == TK_PARAM_RPAREN)
        return 1u;
    if (kind == TK_LBRACKET || kind == TK_INDEX_LBRACKET || kind == TK_ARRAY_LBRACKET ||
        kind == TK_TYPE_ARRAY_LBRACKET || kind == TK_RBRACKET || kind == TK_INDEX_RBRACKET ||
        kind == TK_ARRAY_RBRACKET || kind == TK_TYPE_ARRAY_RBRACKET)
        return 2u;
    if (kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_RBRACE || kind == TK_IF_RBRACE)
        return 3u;
    return 0u;
}

bool is_open_delimiter(uint kind)
{
    return kind == TK_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_CALL_LPAREN ||
           kind == TK_PARAM_LPAREN || kind == TK_LBRACKET || kind == TK_INDEX_LBRACKET ||
           kind == TK_ARRAY_LBRACKET || kind == TK_TYPE_ARRAY_LBRACKET || kind == TK_LBRACE ||
           kind == TK_IF_LBRACE;
}

bool is_close_delimiter(uint kind)
{
    return kind == TK_RPAREN || kind == TK_GROUP_RPAREN || kind == TK_CALL_RPAREN ||
           kind == TK_PARAM_RPAREN || kind == TK_RBRACKET || kind == TK_INDEX_RBRACKET ||
           kind == TK_ARRAY_RBRACKET || kind == TK_TYPE_ARRAY_RBRACKET || kind == TK_RBRACE ||
           kind == TK_IF_RBRACE;
}

bool delimiter_prefix_underflows(uint close_i)
{
    uint close_kind = token_kind(close_i);
    uint class_id = delimiter_class(close_kind);
    if (class_id == 0u || !is_close_delimiter(close_kind))
        return false;

    uint block_idx = close_i / WG_SIZE;
    int depth = 0;
    if (class_id == 1u)
        depth = block_prefix_paren[block_idx] + depth_paren_inblock[close_i];
    else if (class_id == 2u)
        depth = block_prefix_bracket[block_idx] + depth_bracket_inblock[close_i];
    else
        depth = block_prefix_brace[block_idx] + depth_brace_inblock[close_i];
    return depth <= 0;
}

void check_fn(uint i)
{
    if (token_kind(i + 1u) != TK_IDENT)
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
        return;
    }
    uint params_open = token_kind(i + 2u);
    if (params_open != TK_PARAM_LPAREN && params_open != TK_LPAREN)
    {
        record_error(i + 2u, ERR_EXPECTED_TOKEN, TK_LPAREN);
        return;
    }

    uint body = find_before_boundary_at_depth(i + 3u, TK_LBRACE, i);
    if (body == INVALID)
        record_error(i, ERR_EXPECTED_TOKEN, TK_LBRACE);
}

void check_let(uint i)
{
    uint ident_kind = token_kind(i + 1u);
    if (ident_kind != TK_LET_IDENT && ident_kind != TK_IDENT)
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
        return;
    }
    uint semi = find_stmt_semicolon(i);
    if (semi == INVALID)
    {
        record_error(i, ERR_MISSING_SEMICOLON, 0u);
        return;
    }
    if (token_kind(i + 2u) == TK_COLON && !is_type_start(token_kind(i + 3u)))
    {
        record_error(i + 3u, ERR_EXPECTED_TOKEN, TK_TYPE_IDENT);
        return;
    }
    uint assign_i = find_let_assign(i + 2u, semi, i);
    if (assign_i != INVALID && assign_i + 1u >= semi)
    {
        record_error(assign_i, ERR_EXPECTED_TOKEN, TK_IDENT);
        return;
    }
    if (has_statement_keyword_before(i + 2u, semi, i))
        record_error(i, ERR_STMT_OVERLAP, 0u);
}

void check_return_like(uint i)
{
    uint semi = find_stmt_semicolon(i);
    if (semi == INVALID)
    {
        record_error(i, ERR_MISSING_SEMICOLON, 0u);
        return;
    }
    if (has_statement_keyword_before(i + 1u, semi, i))
        record_error(i, ERR_STMT_OVERLAP, 0u);
}

void check_condition_stmt(uint i, uint brace_kind)
{
    uint open_kind = token_kind(i + 1u);
    if (open_kind != TK_GROUP_LPAREN && open_kind != TK_LPAREN)
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_LPAREN);
        return;
    }
    uint close = find_condition_close(i + 1u);
    if (close == INVALID || close <= i + 2u)
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_GROUP_RPAREN);
        return;
    }
    uint actual_brace = token_kind(close + 1u);
    if (actual_brace != brace_kind && actual_brace != TK_LBRACE)
        record_error(close + 1u, ERR_EXPECTED_TOKEN, brace_kind);
}

void check_assignment(uint i)
{
    uint semi = find_stmt_semicolon(i);
    if (semi == INVALID)
    {
        record_error(i, ERR_MISSING_SEMICOLON, 0u);
        return;
    }
    if (i + 1u >= semi)
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

void check_arg_comma(uint i)
{
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    uint next = token_kind(i + 1u);
    if (prev == TK_CALL_LPAREN || prev == TK_ARG_COMMA || next == TK_CALL_RPAREN ||
        next == TK_ARG_COMMA)
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

void check_array_comma(uint i)
{
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    uint next = token_kind(i + 1u);
    if (prev == TK_ARRAY_LBRACKET || prev == TK_LBRACKET || prev == TK_ARRAY_COMMA ||
        prev == TK_COMMA || next == TK_ARRAY_RBRACKET || next == TK_RBRACKET ||
        next == TK_ARRAY_COMMA || next == TK_COMMA)
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

void check_comma(uint i)
{
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    uint next = token_kind(i + 1u);
    if (prev == TK_LPAREN || prev == TK_CALL_LPAREN || prev == TK_GROUP_LPAREN ||
        prev == TK_ARRAY_LBRACKET || prev == TK_LBRACKET || prev == TK_ARG_COMMA ||
        prev == TK_ARRAY_COMMA || prev == TK_PARAM_COMMA || prev == TK_COMMA ||
        next == TK_RPAREN || next == TK_CALL_RPAREN || next == TK_GROUP_RPAREN ||
        next == TK_ARRAY_RBRACKET || next == TK_RBRACKET || next == TK_ARG_COMMA ||
        next == TK_ARRAY_COMMA || next == TK_PARAM_COMMA || next == TK_COMMA)
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

void check_binary_operator(uint i)
{
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    uint next = token_kind(i + 1u);
    if (!is_expr_end(prev) || !is_expr_start(next))
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

void check_raw_plus_minus(uint i)
{
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    uint next = token_kind(i + 1u);
    bool infix = is_expr_end(prev);
    bool prefix = is_expr_start(next);
    if (infix && !prefix)
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
    else if (!infix && !prefix)
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

void check_expr_end(uint i)
{
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    uint next = token_kind(i + 1u);
    if (prev == TK_FN || prev == TK_DOT)
        return;
    if (next == TK_LPAREN || next == TK_CALL_LPAREN || next == TK_PARAM_LPAREN ||
        next == TK_COLON)
        return;
    if (next == TK_INDEX_LBRACKET || next == TK_LBRACKET)
        return;
    if (next == TK_INC || next == TK_DEC)
        return;
    if (is_expr_start(next))
        record_error(i + 1u, ERR_EXPECTED_TOKEN, TK_SEMICOLON);
}

void check_incdec(uint i)
{
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    uint next = token_kind(i + 1u);
    bool postfix = is_expr_end(prev);
    bool prefix = is_expr_start(next);
    if (!postfix && !prefix)
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
    else if (postfix && prefix)
        record_error(i + 1u, ERR_EXPECTED_TOKEN, TK_SEMICOLON);
}

void check_group_lparen(uint i)
{
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    if (prev == TK_FN || prev == TK_IF || prev == TK_WHILE)
        return;
    if (prev == TK_IDENT)
        return;
    uint next = token_kind(i + 1u);
    if (next == TK_GROUP_RPAREN || next == TK_RPAREN)
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

void check_index_lbracket(uint i)
{
    if (!is_expr_start(token_kind(i + 1u)))
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(tid);
    if (i >= active_token_count())
        return;

    uint kind = token_kind(i);

    if (delimiter_prefix_underflows(i))
        record_error(i, ERR_UNBALANCED_DELIMITER, kind);

    if (kind == TK_PUB && token_kind(i + 1u) != TK_FN)
        record_error(i, ERR_EXPECTED_TOKEN, TK_FN);
    else if (kind == TK_FN)
        check_fn(i);
    else if (kind == TK_PARAM_IDENT && (token_kind(i + 1u) != TK_COLON || !is_type_start(token_kind(i + 2u))))
        record_error(i, ERR_EXPECTED_TOKEN, TK_COLON);
    else if (kind == TK_PARAM_COMMA &&
             token_kind(i + 1u) != TK_PARAM_IDENT && token_kind(i + 1u) != TK_IDENT)
        record_error(i, ERR_EXPECTED_TOKEN, TK_PARAM_IDENT);
    else if (kind == TK_ARROW && !is_type_start(token_kind(i + 1u)))
        record_error(i, ERR_EXPECTED_TOKEN, TK_TYPE_IDENT);
    else if (kind == TK_ARG_COMMA)
        check_arg_comma(i);
    else if (kind == TK_ARRAY_COMMA)
        check_array_comma(i);
    else if (kind == TK_COMMA)
        check_comma(i);
    else if (kind == TK_GROUP_LPAREN || kind == TK_LPAREN)
        check_group_lparen(i);
    else if (kind == TK_INDEX_LBRACKET ||
             (kind == TK_LBRACKET && i > 0u && is_expr_end(token_kind(i - 1u))))
        check_index_lbracket(i);
    else if (kind == TK_TYPE_ARRAY_LBRACKET &&
             (!is_type_start(token_kind(i + 1u)) || token_kind(i + 2u) != TK_TYPE_SEMICOLON))
        record_error(i, ERR_EXPECTED_TOKEN, TK_TYPE_SEMICOLON);
    else if (kind == TK_LET)
        check_let(i);
    else if (kind == TK_RETURN || kind == TK_BREAK || kind == TK_CONTINUE)
        check_return_like(i);
    else if (kind == TK_IF)
        check_condition_stmt(i, TK_IF_LBRACE);
    else if (kind == TK_WHILE)
        check_condition_stmt(i, TK_LBRACE);
    else if (is_assignment_operator(kind))
        check_assignment(i);
    else if (kind == TK_PLUS || kind == TK_MINUS)
        check_raw_plus_minus(i);
    else if (is_binary_operator(kind))
        check_binary_operator(i);
    else if (kind == TK_INC || kind == TK_DEC)
        check_incdec(i);
    else if (is_expr_end(kind))
        check_expr_end(i);
    else if (kind == TK_ELSE)
    {
        if (i == 0u || (token_kind(i - 1u) != TK_IF_RBRACE && token_kind(i - 1u) != TK_RBRACE))
            record_error(i, ERR_EXPECTED_TOKEN, TK_IF);
        else if (token_kind(i + 1u) != TK_LBRACE)
            record_error(i, ERR_EXPECTED_TOKEN, TK_LBRACE);
    }
}
