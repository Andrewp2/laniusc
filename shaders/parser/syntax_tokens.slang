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
StructuredBuffer<uint> token_file_id;

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
static const uint TK_CONST = 92u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;
static const uint TK_MATCH = 95u;
static const uint TK_IMPORT = 96u;
static const uint TK_MODULE = 97u;
static const uint TK_IMPL = 98u;
static const uint TK_TRAIT = 99u;
static const uint TK_FOR = 100u;
static const uint TK_IN = 101u;
static const uint TK_EXTERN = 102u;
static const uint TK_TYPE = 103u;
static const uint TK_WHERE = 104u;
static const uint TK_SELF_VALUE = 105u;

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

uint token_file(uint i)
{
    uint n_active = active_token_count();
    return i < n_active ? token_file_id[i] : INVALID;
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
           kind == TK_FOR ||
           kind == TK_BREAK || kind == TK_CONTINUE || kind == TK_FN || kind == TK_CONST ||
           kind == TK_TYPE ||
           kind == TK_ENUM || kind == TK_STRUCT || kind == TK_IMPORT || kind == TK_MODULE ||
           kind == TK_IMPL || kind == TK_TRAIT || kind == TK_EXTERN;
}

bool is_stmt_boundary(uint kind)
{
    return kind == TK_RBRACE || kind == TK_IF_RBRACE || kind == TK_ELSE || is_stmt_keyword(kind);
}

bool is_type_start(uint kind)
{
    return kind == TK_TYPE_IDENT || kind == TK_IDENT || kind == TK_TYPE_ARRAY_LBRACKET ||
           kind == TK_ARRAY_LBRACKET || kind == TK_LBRACKET || kind == TK_AMPERSAND;
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

bool is_self_receiver_ref_amp(uint i)
{
    if (token_kind(i) != TK_AMPERSAND || token_kind(i + 1u) != TK_SELF_VALUE || i == 0u)
        return false;
    uint prev = token_kind(i - 1u);
    return prev == TK_PARAM_LPAREN || prev == TK_LPAREN || prev == TK_PARAM_COMMA ||
           prev == TK_COMMA;
}

bool is_expr_start(uint kind)
{
    return kind == TK_IDENT || kind == TK_INT || kind == TK_FLOAT || kind == TK_STRING ||
           kind == TK_TRUE || kind == TK_FALSE || kind == TK_SELF_VALUE ||
           kind == TK_CHAR || kind == TK_GROUP_LPAREN || kind == TK_LPAREN ||
           kind == TK_ARRAY_LBRACKET || kind == TK_LBRACKET || kind == TK_PREFIX_PLUS ||
           kind == TK_PREFIX_MINUS || kind == TK_NOT || kind == TK_TILDE || kind == TK_INC ||
           kind == TK_DEC || kind == TK_MATCH;
}

bool is_expr_end(uint kind)
{
    return kind == TK_IDENT || kind == TK_INT || kind == TK_FLOAT || kind == TK_STRING ||
           kind == TK_TRUE || kind == TK_FALSE || kind == TK_SELF_VALUE ||
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

bool is_impl_trait_for(uint i)
{
    if (token_kind(i) != TK_FOR || !is_type_start(token_kind(i + 1u)))
        return false;

    uint j = i;
    [loop]
    for (uint guard = 0u; guard < 256u && j > 0u; guard += 1u)
    {
        j -= 1u;
        if (!same_delimiter_depth_before(i, j))
            continue;

        uint kind = token_kind(j);
        if (kind == TK_IMPL)
            return true;
        if (kind == TK_SEMICOLON || kind == TK_LBRACE || kind == TK_IF_LBRACE ||
            kind == TK_RBRACE || kind == TK_IF_RBRACE || kind == TK_ELSE ||
            (is_stmt_keyword(kind) && kind != TK_IMPL))
            return false;
    }
    return false;
}

bool is_generic_name_kind(uint kind)
{
    return kind == TK_IDENT || kind == TK_TYPE_IDENT || kind == TK_PARAM_IDENT;
}

bool can_start_generic_angle_list(uint lt_i)
{
    if (token_kind(lt_i) != TK_LT || lt_i == 0u)
        return false;

    uint prev = token_kind(lt_i - 1u);
    if (!is_generic_name_kind(prev))
        return false;

    uint before = lt_i > 1u ? token_kind(lt_i - 2u) : 0u;
    return before == TK_FN || before == TK_ENUM || before == TK_STRUCT || before == TK_TYPE ||
           before == TK_IMPL || before == TK_TRAIT || before == TK_COLON || before == TK_ARROW || before == TK_COMMA ||
           before == TK_ARG_COMMA || before == TK_PARAM_COMMA || before == TK_LT ||
           before == TK_PLUS || before == TK_PREFIX_PLUS || before == TK_INFIX_PLUS ||
           before == TK_LPAREN || before == TK_GROUP_LPAREN || before == TK_CALL_LPAREN ||
           before == TK_PARAM_LPAREN || before == TK_TYPE_ARRAY_LBRACKET ||
           before == TK_ARRAY_LBRACKET || before == TK_AMPERSAND || before == TK_WHERE;
}

bool is_generic_angle_boundary(uint kind)
{
    return kind == TK_SEMICOLON || kind == TK_LBRACE || kind == TK_IF_LBRACE ||
           kind == TK_RBRACE || kind == TK_IF_RBRACE || kind == TK_FN ||
           kind == TK_LET || kind == TK_RETURN || kind == TK_IF || kind == TK_WHILE ||
           kind == TK_FOR ||
           kind == TK_BREAK || kind == TK_CONTINUE || kind == TK_ENUM ||
           kind == TK_STRUCT || kind == TK_TYPE || kind == TK_IMPORT || kind == TK_MODULE ||
           kind == TK_IMPL || kind == TK_TRAIT || kind == TK_EXTERN || kind == TK_WHERE;
}

uint generic_angle_list_end(uint open_i)
{
    uint n_active = active_token_count();
    uint depth = 0u;
    [loop]
    for (uint j = open_i + 1u; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT && can_start_generic_angle_list(j))
        {
            depth += 1u;
            continue;
        }
        if (kind == TK_GT)
        {
            if (depth == 0u)
                return j + 1u;
            depth -= 1u;
            continue;
        }
        if (is_generic_angle_boundary(kind))
            return INVALID;
    }
    return INVALID;
}

bool token_in_generic_angle_list(uint token_i)
{
    if (token_kind(token_i) == TK_LT && can_start_generic_angle_list(token_i))
    {
        uint close = generic_angle_list_end(token_i);
        return close != INVALID && token_i < close;
    }

    uint depth = 0u;
    uint j = token_i;
    [loop]
    for (uint guard = 0u; guard < 128u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind == TK_GT)
        {
            depth += 1u;
            continue;
        }
        if (kind == TK_LT)
        {
            if (depth > 0u)
            {
                depth -= 1u;
                continue;
            }
            if (!can_start_generic_angle_list(j))
                return false;
            uint close = generic_angle_list_end(j);
            return close != INVALID && token_i < close;
        }
        if (is_generic_angle_boundary(kind))
            return false;
    }
    return false;
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
        if (token_in_generic_angle_list(j))
            continue;
        if (is_stmt_boundary(kind))
            return INVALID;
    }
    return INVALID;
}

uint find_stmt_semicolon(uint start_i)
{
    return find_before_boundary_at_depth(start_i + 1u, TK_SEMICOLON, start_i);
}

uint find_type_alias_semicolon(uint start_i)
{
    uint n_active = active_token_count();
    uint angle_depth = 0u;
    uint array_depth = 0u;
    uint limit = min(n_active, start_i + 256u);
    [loop]
    for (uint j = start_i + 1u; j < limit; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT)
            angle_depth += 1u;
        else if (kind == TK_GT && angle_depth > 0u)
            angle_depth -= 1u;
        else if (kind == TK_LBRACKET || kind == TK_TYPE_ARRAY_LBRACKET)
            array_depth += 1u;
        else if ((kind == TK_RBRACKET || kind == TK_TYPE_ARRAY_RBRACKET) && array_depth > 0u)
            array_depth -= 1u;
        else if ((kind == TK_SEMICOLON || kind == TK_TYPE_SEMICOLON) && angle_depth == 0u &&
                 array_depth == 0u)
            return j;
        else if (is_stmt_keyword(kind) && angle_depth == 0u && array_depth == 0u)
            return INVALID;
    }
    return INVALID;
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

uint find_for_in(uint for_i)
{
    uint n_active = active_token_count();
    for (uint j = for_i + 1u; j < n_active; j += 1u)
    {
        if (!same_delimiter_depth_before(for_i, j))
            continue;
        uint kind = token_kind(j);
        if (kind == TK_IN)
            return j;
        if (token_in_generic_angle_list(j))
            continue;
        if (kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_SEMICOLON ||
            is_stmt_boundary(kind))
            return INVALID;
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

uint find_fn_param_open(uint fn_i)
{
    uint n_active = active_token_count();
    uint angle_depth = 0u;
    [loop]
    for (uint j = fn_i + 2u; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT)
        {
            angle_depth += 1u;
            continue;
        }
        if (kind == TK_GT && angle_depth > 0u)
        {
            angle_depth -= 1u;
            continue;
        }
        if (angle_depth != 0u)
            continue;
        if (kind == TK_PARAM_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_LPAREN)
            return j;
        if (kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_SEMICOLON ||
            is_stmt_boundary(kind))
            return INVALID;
    }
    return INVALID;
}

bool is_trait_method_fn(uint fn_i)
{
    uint j = fn_i;
    [loop]
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind == TK_TRAIT)
            return true;
        if (kind == TK_IMPL || kind == TK_RBRACE || kind == TK_IF_RBRACE)
            return false;
    }
    return false;
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
    uint params_open_i = find_fn_param_open(i);
    if (params_open_i == INVALID)
    {
        record_error(i + 2u, ERR_EXPECTED_TOKEN, TK_LPAREN);
        return;
    }

    bool semicolon_terminated = (i > 0u && token_kind(i - 1u) == TK_EXTERN) ||
                                (i > 1u && token_kind(i - 1u) == TK_STRING &&
                                 token_kind(i - 2u) == TK_EXTERN) ||
                                is_trait_method_fn(i);
    if (semicolon_terminated)
    {
        uint semi = find_stmt_semicolon(i);
        if (semi == INVALID)
            record_error(i, ERR_MISSING_SEMICOLON, 0u);
    }
    else
    {
        uint body = find_before_boundary_at_depth(params_open_i + 1u, TK_LBRACE, i);
        if (body == INVALID)
            record_error(i, ERR_EXPECTED_TOKEN, TK_LBRACE);
    }
}

void check_extern(uint i)
{
    uint next = token_kind(i + 1u);
    if (next == TK_FN)
        return;
    if (next == TK_STRING && token_kind(i + 2u) == TK_FN)
        return;
    record_error(i + 1u, ERR_EXPECTED_TOKEN, TK_FN);
}

void check_enum(uint i)
{
    if (token_kind(i + 1u) != TK_IDENT)
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
        return;
    }
    uint body = find_before_boundary_at_depth(i + 2u, TK_LBRACE, i);
    if (body == INVALID)
        record_error(i, ERR_EXPECTED_TOKEN, TK_LBRACE);
}

void check_struct(uint i)
{
    if (token_kind(i + 1u) != TK_IDENT)
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
        return;
    }
    uint body = find_before_boundary_at_depth(i + 2u, TK_LBRACE, i);
    if (body == INVALID)
        record_error(i, ERR_EXPECTED_TOKEN, TK_LBRACE);
}

void check_type_alias(uint i)
{
    if (token_kind(i + 1u) != TK_IDENT)
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
        return;
    }

    uint semi = find_type_alias_semicolon(i);
    if (semi == INVALID)
    {
        record_error(i, ERR_MISSING_SEMICOLON, 0u);
        return;
    }

    uint assign_i = INVALID;
    uint angle_depth = 0u;
    uint array_depth = 0u;
    [loop]
    for (uint j = i + 2u; j < semi; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT)
            angle_depth += 1u;
        else if (kind == TK_GT && angle_depth > 0u)
            angle_depth -= 1u;
        else if (kind == TK_LBRACKET || kind == TK_TYPE_ARRAY_LBRACKET)
            array_depth += 1u;
        else if ((kind == TK_RBRACKET || kind == TK_TYPE_ARRAY_RBRACKET) && array_depth > 0u)
            array_depth -= 1u;
        else if (kind == TK_ASSIGN && angle_depth == 0u && array_depth == 0u)
        {
            assign_i = j;
            break;
        }
    }

    if (assign_i == INVALID)
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_ASSIGN);
        return;
    }
    if (assign_i + 1u >= semi || !is_type_start(token_kind(assign_i + 1u)))
        record_error(assign_i + 1u, ERR_EXPECTED_TOKEN, TK_TYPE_IDENT);
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

void check_for_stmt(uint i)
{
    if (token_kind(i + 1u) != TK_IDENT)
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
        return;
    }
    uint in_i = find_for_in(i);
    if (in_i == INVALID || in_i <= i + 1u)
    {
        record_error(i + 1u, ERR_EXPECTED_TOKEN, TK_IN);
        return;
    }
    if (!is_expr_start(token_kind(in_i + 1u)))
    {
        record_error(in_i + 1u, ERR_EXPECTED_TOKEN, TK_IDENT);
        return;
    }
    uint body = find_before_boundary_at_depth(in_i + 1u, TK_LBRACE, i);
    if (body == INVALID)
        record_error(in_i + 1u, ERR_EXPECTED_TOKEN, TK_LBRACE);
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
    if (prev == TK_CALL_LPAREN || prev == TK_ARG_COMMA || next == TK_ARG_COMMA)
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

void check_array_comma(uint i)
{
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    uint next = token_kind(i + 1u);
    if (prev == TK_ARRAY_LBRACKET || prev == TK_LBRACKET || prev == TK_ARRAY_COMMA ||
        prev == TK_COMMA || next == TK_ARRAY_COMMA || next == TK_COMMA)
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

bool is_open_paren_kind(uint kind)
{
    return kind == TK_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_CALL_LPAREN ||
           kind == TK_PARAM_LPAREN;
}

bool is_close_paren_kind(uint kind)
{
    return kind == TK_RPAREN || kind == TK_GROUP_RPAREN || kind == TK_CALL_RPAREN ||
           kind == TK_PARAM_RPAREN;
}

uint matching_open_paren_before(uint close_i)
{
    uint depth = 0u;
    uint j = close_i;
    [loop]
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (is_close_paren_kind(kind))
        {
            depth += 1u;
            continue;
        }
        if (!is_open_paren_kind(kind))
            continue;
        if (depth == 0u)
            return j;
        depth -= 1u;
    }
    return INVALID;
}

bool is_fn_param_open_token(uint open_i)
{
    uint j = open_i;
    [loop]
    for (uint guard = 0u; guard < 256u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind == TK_FN)
            return find_fn_param_open(j) == open_i;
        if (kind == TK_SEMICOLON || kind == TK_LBRACE || kind == TK_IF_LBRACE ||
            kind == TK_RBRACE || kind == TK_IF_RBRACE)
            return false;
    }
    return false;
}

bool is_trailing_param_comma(uint i)
{
    uint next = token_kind(i + 1u);
    if (next != TK_RPAREN && next != TK_PARAM_RPAREN)
        return false;
    if (token_kind(i) == TK_PARAM_COMMA)
        return true;

    uint open_i = matching_open_paren_before(i + 1u);
    return open_i != INVALID && is_fn_param_open_token(open_i);
}

bool is_allowed_trailing_list_comma(uint i)
{
    uint kind = token_kind(i);
    uint next = token_kind(i + 1u);
    if (is_trailing_param_comma(i))
        return true;
    if (kind == TK_ARG_COMMA)
        return next == TK_CALL_RPAREN || next == TK_RPAREN;
    if (kind == TK_ARRAY_COMMA)
        return next == TK_ARRAY_RBRACKET || next == TK_RBRACKET;
    if (kind != TK_COMMA)
        return false;
    return next == TK_RBRACE || next == TK_IF_RBRACE || next == TK_RPAREN ||
           next == TK_GROUP_RPAREN || next == TK_CALL_RPAREN || next == TK_PARAM_RPAREN ||
           next == TK_RBRACKET || next == TK_ARRAY_RBRACKET || next == TK_INDEX_RBRACKET;
}

void check_comma(uint i)
{
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    uint next = token_kind(i + 1u);
    if (is_allowed_trailing_list_comma(i))
        return;
    if (prev == TK_LPAREN || prev == TK_CALL_LPAREN || prev == TK_GROUP_LPAREN ||
        prev == TK_ARRAY_LBRACKET || prev == TK_LBRACKET || prev == TK_ARG_COMMA ||
        prev == TK_ARRAY_COMMA || prev == TK_PARAM_COMMA || prev == TK_COMMA ||
        next == TK_RPAREN || next == TK_CALL_RPAREN || next == TK_GROUP_RPAREN ||
        next == TK_ARRAY_RBRACKET || next == TK_RBRACKET || next == TK_ARG_COMMA ||
        next == TK_ARRAY_COMMA || next == TK_PARAM_COMMA || next == TK_COMMA)
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
}

bool is_path_segment(uint kind)
{
    return kind == TK_IDENT || kind == TK_TYPE_IDENT || kind == TK_PARAM_IDENT ||
           kind == TK_LET_IDENT;
}

bool is_module_path_segment(uint kind)
{
    return kind == TK_IDENT || kind == TK_TYPE_IDENT;
}

bool same_token_file(uint a, uint b)
{
    uint file = token_file(a);
    return file != INVALID && file == token_file(b);
}

uint file_first_token(uint i)
{
    uint file = token_file(i);
    if (file == INVALID)
        return i;

    uint n = active_token_count();
    uint first = i;
    [loop]
    for (uint guard = 0u; guard < n && first > 0u; guard += 1u)
    {
        if (token_file(first - 1u) != file)
            break;
        first -= 1u;
    }
    return first;
}

uint leading_module_decl_end(uint file_start)
{
    if (token_file(file_start) == INVALID || token_kind(file_start) != TK_MODULE)
        return INVALID;

    uint n = active_token_count();
    [loop]
    for (uint j = file_start + 1u; j < n; j += 1u)
    {
        if (!same_token_file(j, file_start))
            return INVALID;
        if (token_kind(j) == TK_SEMICOLON)
            return j;
    }
    return INVALID;
}

bool token_in_leading_module_decl(uint i)
{
    uint file_start = file_first_token(i);
    uint end = leading_module_decl_end(file_start);
    return end != INVALID && i >= file_start && i <= end && same_token_file(i, file_start);
}

uint import_decl_end(uint import_i)
{
    if (token_kind(import_i) != TK_IMPORT)
        return INVALID;

    uint n = active_token_count();
    [loop]
    for (uint j = import_i + 1u; j < n; j += 1u)
    {
        if (!same_token_file(j, import_i))
            return INVALID;
        uint kind = token_kind(j);
        if (kind == TK_SEMICOLON)
            return j;
        if (kind == TK_FN || kind == TK_CONST || kind == TK_ENUM || kind == TK_STRUCT ||
            kind == TK_IMPL || kind == TK_TRAIT || kind == TK_EXTERN || kind == TK_MODULE ||
            kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_RBRACE ||
            kind == TK_IF_RBRACE)
            return INVALID;
    }
    return INVALID;
}

uint first_token_after_optional_module(uint file_start)
{
    if (token_kind(file_start) != TK_MODULE)
        return file_start;
    uint module_end = leading_module_decl_end(file_start);
    return module_end == INVALID ? file_start : module_end + 1u;
}

bool is_leading_import_decl(uint import_i)
{
    if (token_file(import_i) == INVALID || token_kind(import_i) != TK_IMPORT)
        return false;

    uint n = active_token_count();
    uint file_start = file_first_token(import_i);
    uint j = first_token_after_optional_module(file_start);
    [loop]
    for (uint guard = 0u; guard < 256u && j < n; guard += 1u)
    {
        if (!same_token_file(j, file_start))
            return false;
        if (j == import_i)
            return true;
        if (j > import_i || token_kind(j) != TK_IMPORT)
            return false;
        uint end = import_decl_end(j);
        if (end == INVALID)
            return false;
        j = end + 1u;
    }
    return false;
}

bool token_in_leading_import_decl(uint i)
{
    if (token_file(i) == INVALID)
        return false;

    uint n = active_token_count();
    uint file_start = file_first_token(i);
    uint j = first_token_after_optional_module(file_start);
    [loop]
    for (uint guard = 0u; guard < 256u && j < n; guard += 1u)
    {
        if (!same_token_file(j, file_start))
            return false;
        if (token_kind(j) != TK_IMPORT)
            return false;
        uint end = import_decl_end(j);
        if (end == INVALID)
            return false;
        if (i >= j && i <= end)
            return true;
        if (i < j)
            return false;
        j = end + 1u;
    }
    return false;
}

uint qualified_path_start(uint first_colon_i)
{
    uint start = first_colon_i > 0u ? first_colon_i - 1u : 0u;
    [loop]
    for (uint guard = 0u; guard < 32u && start >= 3u; guard += 1u)
    {
        if (token_kind(start - 1u) != TK_COLON || token_kind(start - 2u) != TK_COLON ||
            !is_path_segment(token_kind(start - 3u)))
            break;
        start -= 3u;
    }
    return start;
}

uint qualified_path_end(uint start)
{
    uint n = active_token_count();
    uint end = start;
    [loop]
    for (uint guard = 0u; guard < 32u && end + 3u < n; guard += 1u)
    {
        if (token_kind(end + 1u) != TK_COLON || token_kind(end + 2u) != TK_COLON ||
            !is_path_segment(token_kind(end + 3u)))
            break;
        end += 3u;
    }
    return end;
}

bool is_qualified_type_context(uint prev)
{
    return prev == TK_COLON || prev == TK_ARROW || prev == TK_LT || prev == TK_COMMA ||
           prev == TK_PARAM_COMMA;
}

bool is_qualified_value_path(uint start)
{
    if (!is_path_segment(token_kind(start)))
        return false;
    uint leaf = qualified_path_end(start);
    return leaf > start + 1u;
}

void check_qualified_path_colon(uint i)
{
    if (token_kind(i + 1u) != TK_COLON)
        return;
    if (token_in_leading_module_decl(i))
        return;
    if (token_in_leading_import_decl(i))
        return;
    uint start = qualified_path_start(i);
    uint prev = start > 0u ? token_kind(start - 1u) : 0u;
    if (!is_qualified_type_context(prev) && !is_qualified_value_path(start))
        record_error(i, ERR_UNEXPECTED_TOKEN, TK_COLON);
}

void check_module_decl(uint i)
{
    uint file_start = file_first_token(i);
    if (i != file_start)
    {
        record_error(i, ERR_UNEXPECTED_TOKEN, TK_MODULE);
        return;
    }

    uint n = active_token_count();
    if (i + 1u >= n || !same_token_file(i + 1u, i))
    {
        record_error(i, ERR_EXPECTED_TOKEN, TK_IDENT);
        return;
    }

    uint j = i + 1u;
    bool expect_segment = true;
    bool saw_segment = false;
    [loop]
    for (uint guard = 0u; guard < 128u && j < n; guard += 1u)
    {
        if (!same_token_file(j, i))
        {
            record_error(saw_segment ? j - 1u : i, ERR_MISSING_SEMICOLON, TK_SEMICOLON);
            return;
        }
        uint kind = token_kind(j);
        if (expect_segment)
        {
            if (!is_module_path_segment(kind))
            {
                record_error(j, ERR_EXPECTED_TOKEN, TK_IDENT);
                return;
            }
            saw_segment = true;
            expect_segment = false;
            j += 1u;
            continue;
        }

        if (kind == TK_SEMICOLON)
            return;
        if (kind == TK_COLON && token_kind(j + 1u) == TK_COLON)
        {
            expect_segment = true;
            j += 2u;
            continue;
        }

        record_error(j, ERR_EXPECTED_TOKEN, TK_SEMICOLON);
        return;
    }

    record_error(saw_segment ? n - 1u : i, ERR_MISSING_SEMICOLON, TK_SEMICOLON);
}

void check_import_decl(uint i)
{
    if (!is_leading_import_decl(i))
    {
        record_error(i, ERR_UNEXPECTED_TOKEN, TK_IMPORT);
        return;
    }

    uint end = import_decl_end(i);
    if (end == INVALID)
    {
        record_error(i, ERR_MISSING_SEMICOLON, TK_SEMICOLON);
        return;
    }

    if (token_kind(i + 1u) == TK_STRING)
    {
        if (i + 2u != end)
            record_error(i + 2u, ERR_EXPECTED_TOKEN, TK_SEMICOLON);
        return;
    }

    uint j = i + 1u;
    bool expect_segment = true;
    bool saw_segment = false;
    [loop]
    for (uint guard = 0u; guard < 128u && j <= end; guard += 1u)
    {
        uint kind = token_kind(j);
        if (expect_segment)
        {
            if (!is_module_path_segment(kind))
            {
                record_error(j, ERR_EXPECTED_TOKEN, TK_IDENT);
                return;
            }
            saw_segment = true;
            expect_segment = false;
            j += 1u;
            continue;
        }

        if (kind == TK_SEMICOLON)
            return;
        if (kind == TK_COLON && token_kind(j + 1u) == TK_COLON)
        {
            expect_segment = true;
            j += 2u;
            continue;
        }

        record_error(j, ERR_EXPECTED_TOKEN, TK_SEMICOLON);
        return;
    }

    record_error(saw_segment ? end : i, ERR_MISSING_SEMICOLON, TK_SEMICOLON);
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

bool is_for_iter_expr_end(uint i)
{
    if (token_kind(i + 1u) != TK_LBRACE)
        return false;

    bool saw_in = false;
    [loop]
    for (uint j = i; j > 0u; j -= 1u)
    {
        uint kind = token_kind(j - 1u);
        if (kind == TK_IN)
        {
            saw_in = true;
            continue;
        }
        if (saw_in && kind == TK_FOR)
            return true;
        if (kind == TK_SEMICOLON || kind == TK_RBRACE || kind == TK_IF_RBRACE ||
            kind == TK_ELSE)
            return false;
        if (is_stmt_keyword(kind) && kind != TK_FOR)
            return false;
    }
    return false;
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
    if (is_for_iter_expr_end(i))
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
    if (prev == TK_FN || prev == TK_IF || prev == TK_WHILE || prev == TK_MATCH)
        return;
    if (prev == TK_GT)
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

    if (token_file(i) == INVALID)
        record_error(i, ERR_UNEXPECTED_TOKEN, kind);

    if (delimiter_prefix_underflows(i))
        record_error(i, ERR_UNBALANCED_DELIMITER, kind);

    if (token_in_generic_angle_list(i))
        return;
    if (kind != TK_IMPORT && token_in_leading_import_decl(i))
        return;

    if (kind == TK_PUB && token_kind(i + 1u) != TK_FN && token_kind(i + 1u) != TK_CONST &&
        token_kind(i + 1u) != TK_ENUM && token_kind(i + 1u) != TK_STRUCT &&
        token_kind(i + 1u) != TK_IMPL && token_kind(i + 1u) != TK_TRAIT &&
        token_kind(i + 1u) != TK_EXTERN && token_kind(i + 1u) != TK_TYPE)
        record_error(i, ERR_EXPECTED_TOKEN, TK_FN);
    else if (kind == TK_FN)
        check_fn(i);
    else if (kind == TK_ENUM)
        check_enum(i);
    else if (kind == TK_STRUCT)
        check_struct(i);
    else if (kind == TK_TYPE)
        check_type_alias(i);
    else if (kind == TK_IMPORT)
        check_import_decl(i);
    else if (kind == TK_MODULE)
        check_module_decl(i);
    else if (kind == TK_EXTERN)
        check_extern(i);
    else if (kind == TK_PARAM_IDENT && (token_kind(i + 1u) != TK_COLON || !is_type_start(token_kind(i + 2u))))
        record_error(i, ERR_EXPECTED_TOKEN, TK_COLON);
    else if (kind == TK_PARAM_COMMA &&
             token_kind(i + 1u) != TK_PARAM_IDENT && token_kind(i + 1u) != TK_IDENT &&
             token_kind(i + 1u) != TK_SELF_VALUE && token_kind(i + 1u) != TK_AMPERSAND &&
             token_kind(i + 1u) != TK_PARAM_RPAREN)
        record_error(i, ERR_EXPECTED_TOKEN, TK_PARAM_IDENT);
    else if (kind == TK_ARROW && !is_type_start(token_kind(i + 1u)) &&
             !is_expr_start(token_kind(i + 1u)))
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
    else if (kind == TK_COLON)
        check_qualified_path_colon(i);
    else if (kind == TK_LET)
        check_let(i);
    else if (kind == TK_RETURN || kind == TK_BREAK || kind == TK_CONTINUE)
        check_return_like(i);
    else if (kind == TK_IF)
        check_condition_stmt(i, TK_IF_LBRACE);
    else if (kind == TK_WHILE)
        check_condition_stmt(i, TK_LBRACE);
    else if (kind == TK_FOR)
    {
        if (!is_impl_trait_for(i))
            check_for_stmt(i);
    }
    else if (is_assignment_operator(kind))
        check_assignment(i);
    else if (kind == TK_PLUS || kind == TK_MINUS)
        check_raw_plus_minus(i);
    else if (is_self_receiver_ref_amp(i))
    {
    }
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
