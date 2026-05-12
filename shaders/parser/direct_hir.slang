// Direct token-to-HIR bridge for the resident compiler path.
//
// This pass does not build the full LL(1) production tree. It emits the coarse
// HIR roles and spans consumed by GPU type checking and C codegen directly from
// the resident lexer token stream, one thread per token.

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

RWStructuredBuffer<uint> hir_kind;
RWStructuredBuffer<uint> hir_token_pos;
RWStructuredBuffer<uint> hir_token_end;
RWStructuredBuffer<uint> hir_token_file_id;
RWStructuredBuffer<uint> hir_status;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint INVALID = 0xffffffffu;

static const uint HIR_NONE = 0u;
static const uint HIR_FILE = 1u;
static const uint HIR_FN = 3u;
static const uint HIR_PARAM = 4u;
static const uint HIR_TYPE = 5u;
static const uint HIR_BLOCK = 6u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_BREAK_STMT = 12u;
static const uint HIR_CONTINUE_STMT = 13u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_CONST_ITEM = 25u;
static const uint HIR_ENUM_ITEM = 26u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_TYPE_ALIAS_ITEM = 29u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_MODULE_ITEM = 31u;
static const uint HIR_IMPORT_ITEM = 32u;
static const uint HIR_PATH_EXPR = 33u;

static const uint TK_IDENT = 1u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_ASSIGN = 8u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_AMPERSAND = 25u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_DOT = 35u;
static const uint TK_COMMA = 36u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
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
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_PUB = 66u;
static const uint TK_FN = 67u;
static const uint TK_LET = 68u;
static const uint TK_RETURN = 69u;
static const uint TK_IF = 70u;
static const uint TK_WHILE = 72u;
static const uint TK_BREAK = 73u;
static const uint TK_CONTINUE = 74u;
static const uint TK_ARROW = 75u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_LET_ASSIGN = 81u;
static const uint TK_ARG_COMMA = 82u;
static const uint TK_PARAM_COMMA = 84u;
static const uint TK_PARAM_LPAREN = 76u;
static const uint TK_PARAM_RPAREN = 77u;
static const uint TK_LET_IDENT = 78u;
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
static const uint TK_IMPORT = 96u;
static const uint TK_MODULE = 97u;
static const uint TK_IMPL = 98u;
static const uint TK_FOR = 100u;
static const uint TK_IN = 101u;
static const uint TK_TYPE = 103u;
static const uint TK_SELF_VALUE = 105u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint token_kind(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].kind : 0u;
}

uint token_file(uint i)
{
    uint n = active_token_count();
    return i < n ? token_file_id[i] : INVALID;
}

bool is_open_brace(uint kind)
{
    return kind == TK_LBRACE || kind == TK_IF_LBRACE;
}

bool is_close_brace(uint kind)
{
    return kind == TK_RBRACE || kind == TK_IF_RBRACE;
}

bool is_type_open(uint kind)
{
    return kind == TK_TYPE_ARRAY_LBRACKET || kind == TK_LBRACKET;
}

bool is_type_close(uint kind)
{
    return kind == TK_TYPE_ARRAY_RBRACKET || kind == TK_RBRACKET;
}

bool is_array_literal_open(uint kind)
{
    return kind == TK_ARRAY_LBRACKET || kind == TK_LBRACKET;
}

bool is_array_literal_close(uint kind)
{
    return kind == TK_ARRAY_RBRACKET || kind == TK_RBRACKET;
}

bool is_assignment_operator(uint kind)
{
    return kind == TK_ASSIGN || kind == TK_PLUS_ASSIGN || kind == TK_MINUS_ASSIGN ||
           kind == TK_STAR_ASSIGN || kind == TK_SLASH_ASSIGN || kind == TK_PERCENT_ASSIGN ||
           kind == TK_CARET_ASSIGN || kind == TK_SHL_ASSIGN || kind == TK_SHR_ASSIGN ||
           kind == TK_AMP_ASSIGN || kind == TK_PIPE_ASSIGN;
}

bool is_struct_literal_open_at(uint i)
{
    if (token_kind(i) != TK_LBRACE || i == 0u || token_kind(i - 1u) != TK_IDENT)
        return false;
    uint before_name = i > 1u ? token_kind(i - 2u) : 0u;
    return before_name != TK_STRUCT && before_name != TK_ENUM && before_name != TK_TYPE &&
           before_name != TK_IMPL && before_name != TK_FOR && before_name != TK_IN &&
           before_name != TK_ARROW &&
           before_name != TK_COLON;
}

bool token_is_identifier(uint kind)
{
    return kind == TK_IDENT || kind == TK_TYPE_IDENT || kind == TK_PARAM_IDENT || kind == TK_LET_IDENT;
}

bool is_struct_literal_field_value_context(uint value_i)
{
    if (value_i == 0u || token_kind(value_i - 1u) != TK_COLON)
        return false;

    if (value_i < 2u || !token_is_identifier(token_kind(value_i - 2u)))
        return false;

    uint j = value_i - 2u;
    [loop]
    for (uint guard = 0u; guard < 64u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind == TK_LBRACE)
        {
            if (j == 0u)
                return false;
            if (token_kind(j - 1u) == TK_STRUCT)
                return false;
            return token_is_identifier(token_kind(j - 1u));
        }
        if (kind == TK_SEMICOLON || kind == TK_RETURN || kind == TK_FN || kind == TK_STRUCT ||
            kind == TK_ENUM || kind == TK_TYPE || kind == TK_LET || kind == TK_CONST ||
            kind == TK_IF || kind == TK_WHILE || kind == TK_FOR)
        {
            return false;
        }
    }
    return false;
}

bool is_paren_open(uint kind)
{
    return kind == TK_LPAREN || kind == TK_CALL_LPAREN || kind == TK_GROUP_LPAREN ||
           kind == TK_PARAM_LPAREN;
}

bool is_paren_close(uint kind)
{
    return kind == TK_RPAREN || kind == TK_CALL_RPAREN || kind == TK_GROUP_RPAREN ||
           kind == TK_PARAM_RPAREN;
}

bool is_expr_end_kind(uint kind)
{
    return kind == TK_IDENT || kind == TK_RPAREN || kind == TK_RBRACKET ||
           kind == TK_TRUE || kind == TK_FALSE || kind == TK_SELF_VALUE ||
           kind == TK_ARRAY_RBRACKET;
}

bool is_path_segment(uint kind)
{
    return kind == TK_IDENT || kind == TK_TYPE_IDENT || kind == TK_PARAM_IDENT ||
           kind == TK_LET_IDENT;
}

bool is_qualified_type_context(uint prev)
{
    return prev == TK_COLON || prev == TK_ARROW || prev == TK_LT || prev == TK_COMMA ||
           prev == TK_PARAM_COMMA;
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

uint item_semicolon_end(uint item_i)
{
    uint n = active_token_count();
    [loop]
    for (uint j = item_i + 1u; j < n; j += 1u)
    {
        if (!same_token_file(j, item_i))
            return j;
        if (token_kind(j) == TK_SEMICOLON)
            return j + 1u;
        uint kind = token_kind(j);
        if (is_open_brace(kind) || is_close_brace(kind) || kind == TK_FN || kind == TK_CONST ||
            kind == TK_ENUM || kind == TK_STRUCT || kind == TK_TYPE)
            return j;
    }
    return n;
}

uint enclosing_module_or_import_item(uint i)
{
    uint file = token_file(i);
    if (file == INVALID)
        return INVALID;

    uint j = i;
    [loop]
    for (uint guard = 0u; guard < 128u && j > 0u; guard += 1u)
    {
        j -= 1u;
        if (token_file(j) != file)
            return INVALID;
        uint kind = token_kind(j);
        if (kind == TK_MODULE || kind == TK_IMPORT)
        {
            uint end = item_semicolon_end(j);
            return i < end ? j : INVALID;
        }
        if (kind == TK_SEMICOLON || is_open_brace(kind) || is_close_brace(kind) ||
            kind == TK_FN || kind == TK_CONST || kind == TK_ENUM || kind == TK_STRUCT ||
            kind == TK_TYPE)
            return INVALID;
    }
    return INVALID;
}

uint qualified_path_end(uint start)
{
    uint n = active_token_count();
    uint end = start + 1u;
    [loop]
    for (uint guard = 0u; guard < 32u && end + 2u < n; guard += 1u)
    {
        if (token_kind(end) != TK_COLON || token_kind(end + 1u) != TK_COLON ||
            !is_path_segment(token_kind(end + 2u)))
            break;
        end += 3u;
    }
    return end;
}

bool is_qualified_path_head(uint i)
{
    if (!is_path_segment(token_kind(i)))
        return false;
    if (i > 0u && token_kind(i - 1u) == TK_COLON)
        return false;
    if (token_kind(i + 1u) != TK_COLON || token_kind(i + 2u) != TK_COLON ||
        !is_path_segment(token_kind(i + 3u)))
        return false;
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    return !is_qualified_type_context(prev);
}

bool token_in_qualified_path_tail(uint i)
{
    if (!is_path_segment(token_kind(i)) || i < 3u ||
        token_kind(i - 1u) != TK_COLON || token_kind(i - 2u) != TK_COLON)
        return false;

    uint start = i - 3u;
    [loop]
    for (uint guard = 0u; guard < 32u && start >= 3u; guard += 1u)
    {
        if (token_kind(start - 1u) != TK_COLON || token_kind(start - 2u) != TK_COLON ||
            !is_path_segment(token_kind(start - 3u)))
            break;
        start -= 3u;
    }
    if (!is_path_segment(token_kind(start)))
        return false;
    uint prev = start > 0u ? token_kind(start - 1u) : 0u;
    return !is_qualified_type_context(prev);
}

bool token_in_qualified_type_path(uint i)
{
    if (!is_path_segment(token_kind(i)))
        return false;

    uint start = i;
    [loop]
    for (uint guard = 0u; guard < 32u && start >= 3u; guard += 1u)
    {
        if (token_kind(start - 1u) != TK_COLON || token_kind(start - 2u) != TK_COLON ||
            !is_path_segment(token_kind(start - 3u)))
            break;
        start -= 3u;
    }

    if (!is_path_segment(token_kind(start)))
        return false;
    uint prev = start > 0u ? token_kind(start - 1u) : 0u;
    if (!is_qualified_type_context(prev))
        return false;
    return qualified_path_end(start) > start + 1u;
}

uint matching_brace_end(uint open_i)
{
    uint n = active_token_count();
    uint depth = 0u;
    [loop]
    for (uint j = open_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_open_brace(kind))
        {
            depth += 1u;
            continue;
        }
        if (!is_close_brace(kind))
            continue;
        if (depth == 0u)
            return j + 1u;
        depth -= 1u;
    }
    return n;
}

uint matching_type_array_end(uint open_i)
{
    uint n = active_token_count();
    uint depth = 0u;
    [loop]
    for (uint j = open_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_type_open(kind))
        {
            depth += 1u;
            continue;
        }
        if (!is_type_close(kind))
            continue;
        if (depth == 0u)
            return j + 1u;
        depth -= 1u;
    }
    return n;
}

uint matching_array_literal_end(uint open_i)
{
    uint n = active_token_count();
    uint depth = 0u;
    [loop]
    for (uint j = open_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_array_literal_open(kind))
        {
            depth += 1u;
            continue;
        }
        if (!is_array_literal_close(kind))
            continue;
        if (depth == 0u)
            return j + 1u;
        depth -= 1u;
    }
    return n;
}

uint matching_call_end(uint open_i)
{
    uint n = active_token_count();
    uint depth = 0u;
    [loop]
    for (uint j = open_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_paren_open(kind))
        {
            depth += 1u;
            continue;
        }
        if (!is_paren_close(kind))
            continue;
        if (depth == 0u)
            return j + 1u;
        depth -= 1u;
    }
    return n;
}

bool token_in_type_array(uint token_i)
{
    uint n = active_token_count();
    uint open_i = token_i;
    [loop]
    for (uint guard = 0u; guard < 64u && open_i > 0u; guard += 1u)
    {
        open_i -= 1u;
        uint open_kind = token_kind(open_i);
        if (!is_type_open(open_kind))
            continue;

        uint prev = open_i > 0u ? token_kind(open_i - 1u) : 0u;
        if (prev != TK_COLON && prev != TK_ARROW && open_kind != TK_TYPE_ARRAY_LBRACKET)
            continue;

        uint end = matching_type_array_end(open_i);
        if (token_i >= min(end, n))
            return false;

        uint depth = 0u;
        [loop]
        for (uint j = open_i + 1u; j < token_i; j += 1u)
        {
            uint kind = token_kind(j);
            if (is_type_open(kind))
            {
                depth += 1u;
                continue;
            }
            if (is_type_close(kind))
            {
                if (depth > 0u)
                    depth -= 1u;
                continue;
            }
            if (kind == TK_SEMICOLON && depth == 0u)
                return false;
        }
        return true;
    }
    return false;
}

bool token_in_type_array_length(uint token_i)
{
    uint n = active_token_count();
    uint open_i = token_i;
    [loop]
    for (uint guard = 0u; guard < 64u && open_i > 0u; guard += 1u)
    {
        open_i -= 1u;
        uint open_kind = token_kind(open_i);
        if (!is_type_open(open_kind))
            continue;

        uint prev = open_i > 0u ? token_kind(open_i - 1u) : 0u;
        if (prev != TK_COLON && prev != TK_ARROW && open_kind != TK_TYPE_ARRAY_LBRACKET)
            continue;

        uint end = matching_type_array_end(open_i);
        if (token_i >= min(end, n))
            return false;

        uint depth = 0u;
        bool saw_len_sep = false;
        [loop]
        for (uint j = open_i + 1u; j < token_i; j += 1u)
        {
            uint kind = token_kind(j);
            if (is_type_open(kind))
            {
                depth += 1u;
                continue;
            }
            if (is_type_close(kind))
            {
                if (depth > 0u)
                    depth -= 1u;
                continue;
            }
            if ((kind == TK_SEMICOLON || kind == TK_TYPE_SEMICOLON) && depth == 0u)
                saw_len_sep = true;
        }
        return saw_len_sep;
    }
    return false;
}

uint statement_end(uint start_i)
{
    uint n = active_token_count();
    uint bracket_depth = 0u;
    uint struct_literal_depth = 0u;
    [loop]
    for (uint j = start_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_struct_literal_open_at(j))
        {
            struct_literal_depth += 1u;
            continue;
        }
        if (kind == TK_RBRACE && struct_literal_depth > 0u)
        {
            struct_literal_depth -= 1u;
            continue;
        }
        if (kind == TK_LBRACKET || kind == TK_TYPE_ARRAY_LBRACKET)
        {
            bracket_depth += 1u;
            continue;
        }
        if (kind == TK_RBRACKET || kind == TK_TYPE_ARRAY_RBRACKET)
        {
            if (bracket_depth > 0u)
                bracket_depth -= 1u;
            continue;
        }
        if (kind == TK_SEMICOLON && bracket_depth == 0u && struct_literal_depth == 0u)
            return j + 1u;
        if (is_close_brace(kind) && bracket_depth == 0u && struct_literal_depth == 0u)
            return j;
    }
    return n;
}

bool is_let_initializer_assignment(uint assign_i)
{
    uint j = assign_i;
    uint bracket_depth = 0u;
    [loop]
    for (uint guard = 0u; guard < 128u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind == TK_RBRACKET || kind == TK_TYPE_ARRAY_RBRACKET)
        {
            bracket_depth += 1u;
            continue;
        }
        if (kind == TK_LBRACKET || kind == TK_TYPE_ARRAY_LBRACKET)
        {
            if (bracket_depth > 0u)
            {
                bracket_depth -= 1u;
                continue;
            }
        }
        if (kind == TK_LET)
            return true;
        if (bracket_depth == 0u &&
            (kind == TK_SEMICOLON || is_open_brace(kind) || is_close_brace(kind) || kind == TK_FN))
            return false;
    }
    return false;
}

uint function_end(uint fn_i)
{
    uint n = active_token_count();
    uint bracket_depth = 0u;
    [loop]
    for (uint j = fn_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACKET || kind == TK_TYPE_ARRAY_LBRACKET)
        {
            bracket_depth += 1u;
            continue;
        }
        if (kind == TK_RBRACKET || kind == TK_TYPE_ARRAY_RBRACKET)
        {
            if (bracket_depth > 0u)
                bracket_depth -= 1u;
            continue;
        }
        if (is_open_brace(kind) && bracket_depth == 0u)
            return matching_brace_end(j);
        if (kind == TK_SEMICOLON && bracket_depth == 0u)
            return j + 1u;
    }
    return n;
}

uint fn_type_params_end(uint fn_i)
{
    uint n = active_token_count();
    if (fn_i + 2u >= n || token_kind(fn_i + 2u) != TK_LT)
        return INVALID;

    uint depth = 0u;
    [loop]
    for (uint j = fn_i + 2u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT)
        {
            depth += 1u;
            continue;
        }
        if (kind != TK_GT)
            continue;
        if (depth == 0u)
            return INVALID;
        depth -= 1u;
        if (depth == 0u)
            return j + 1u;
    }
    return INVALID;
}

bool token_in_fn_type_params(uint token_i)
{
    uint j = token_i;
    [loop]
    for (uint guard = 0u; guard < 128u && j > 0u; guard += 1u)
    {
        j -= 1u;
        if (token_kind(j) != TK_FN)
            continue;
        uint end = fn_type_params_end(j);
        if (end == INVALID)
            return false;
        return token_i >= j + 2u && token_i < end;
    }
    return false;
}

bool generic_type_name_context(uint type_name_i)
{
    if (type_name_i == 0u)
        return false;
    uint prev = token_kind(type_name_i - 1u);
    return prev == TK_COLON || prev == TK_ARROW || prev == TK_LT || prev == TK_COMMA ||
           prev == TK_ARG_COMMA || prev == TK_PARAM_COMMA;
}

bool token_in_shallow_generic_type_arg(uint token_i)
{
    if (token_i >= 2u && token_kind(token_i - 1u) == TK_LT &&
        (token_kind(token_i - 2u) == TK_IDENT || token_kind(token_i - 2u) == TK_TYPE_IDENT) &&
        generic_type_name_context(token_i - 2u))
        return true;
    if (token_i >= 4u &&
        (token_kind(token_i - 1u) == TK_COMMA || token_kind(token_i - 1u) == TK_ARG_COMMA ||
         token_kind(token_i - 1u) == TK_PARAM_COMMA) &&
        token_kind(token_i - 3u) == TK_LT &&
        (token_kind(token_i - 4u) == TK_IDENT || token_kind(token_i - 4u) == TK_TYPE_IDENT) &&
        generic_type_name_context(token_i - 4u))
        return true;
    return false;
}

bool token_in_for_iterable(uint token_i)
{
    uint token = token_kind(token_i);
    if (token_i == 0u || (token != TK_IDENT && token != TK_TYPE_IDENT))
        return false;

    uint j = token_i;
    [loop]
    for (uint guard = 0u; guard < 128u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind == TK_IN)
        {
            uint k = j;
            [loop]
            for (uint inner_guard = 0u; inner_guard < 128u && k > 0u; inner_guard += 1u)
            {
                k -= 1u;
                uint before = token_kind(k);
                if (before == TK_FOR)
                    return true;
                if (before == TK_SEMICOLON || before == TK_FN ||
                    is_open_brace(before) || is_close_brace(before))
                    return false;
            }
            return false;
        }
        if (kind == TK_FOR || kind == TK_SEMICOLON || kind == TK_FN ||
            is_open_brace(kind) || is_close_brace(kind))
            return false;
    }
    return false;
}

uint item_type_params_end(uint item_i)
{
    uint n = active_token_count();
    if (item_i + 2u >= n || token_kind(item_i + 2u) != TK_LT)
        return INVALID;

    uint depth = 0u;
    [loop]
    for (uint j = item_i + 2u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT)
        {
            depth += 1u;
            continue;
        }
        if (kind != TK_GT)
            continue;
        if (depth == 0u)
            return INVALID;
        depth -= 1u;
        if (depth == 0u)
            return j + 1u;
    }
    return INVALID;
}

bool token_in_item_type_params(uint token_i, uint item_i)
{
    uint end = item_type_params_end(item_i);
    return end != INVALID && token_i >= item_i + 2u && token_i < end;
}

uint enum_end(uint enum_i)
{
    uint n = active_token_count();
    [loop]
    for (uint j = enum_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_open_brace(kind))
            return matching_brace_end(j);
        if (token_in_item_type_params(j, enum_i))
            continue;
        if (kind == TK_SEMICOLON || kind == TK_FN || kind == TK_CONST || kind == TK_ENUM ||
            kind == TK_STRUCT || kind == TK_TYPE)
            return j;
    }
    return n;
}

uint struct_end(uint struct_i)
{
    uint n = active_token_count();
    [loop]
    for (uint j = struct_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_open_brace(kind))
            return matching_brace_end(j);
        if (token_in_item_type_params(j, struct_i))
            continue;
        if (kind == TK_SEMICOLON || kind == TK_FN || kind == TK_CONST || kind == TK_ENUM ||
            kind == TK_STRUCT || kind == TK_TYPE)
            return j;
    }
    return n;
}

uint type_alias_end(uint alias_i)
{
    return statement_end(alias_i);
}

bool token_in_type_decl(uint token_i)
{
    uint j = token_i;
    [loop]
    for (uint guard = 0u; guard < 256u && j > 0u; guard += 1u)
    {
        j -= 1u;
        if (token_kind(j) == TK_ENUM)
            return token_i < enum_end(j);
        if (token_kind(j) == TK_STRUCT)
            return token_i < struct_end(j);
        if (token_kind(j) == TK_TYPE)
            return token_i < type_alias_end(j);
    }
    return false;
}

uint control_stmt_end(uint stmt_i)
{
    uint n = active_token_count();
    [loop]
    for (uint j = stmt_i + 1u; j < n; j += 1u)
    {
        if (is_open_brace(token_kind(j)))
            return matching_brace_end(j);
    }
    return n;
}

uint classify(uint i, out uint end)
{
    uint n = active_token_count();
    uint kind = token_kind(i);
    end = min(i + 1u, n);

    if (kind == TK_MODULE)
    {
        end = item_semicolon_end(i);
        return HIR_MODULE_ITEM;
    }
    if (kind == TK_IMPORT)
    {
        end = item_semicolon_end(i);
        return HIR_IMPORT_ITEM;
    }
    if (enclosing_module_or_import_item(i) != INVALID)
        return HIR_NONE;
    if (token_in_leading_module_decl(i))
        return HIR_NONE;

    if (kind == TK_FN)
    {
        end = function_end(i);
        return HIR_FN;
    }
    if (kind == TK_ENUM)
    {
        end = enum_end(i);
        return HIR_ENUM_ITEM;
    }
    if (kind == TK_STRUCT)
    {
        end = struct_end(i);
        return HIR_STRUCT_ITEM;
    }
    if (kind == TK_TYPE)
    {
        end = type_alias_end(i);
        return HIR_TYPE_ALIAS_ITEM;
    }
    if (token_in_type_decl(i))
        return HIR_NONE;
    if (token_in_fn_type_params(i))
        return HIR_NONE;
    if ((kind == TK_IDENT || kind == TK_TYPE_IDENT) && token_in_type_array_length(i))
        return HIR_NONE;
    if (token_in_qualified_type_path(i))
        return HIR_NONE;
    if (is_qualified_path_head(i))
    {
        end = qualified_path_end(i);
        return HIR_PATH_EXPR;
    }
    if (token_in_qualified_path_tail(i))
        return HIR_NONE;
    bool self_param =
        kind == TK_SELF_VALUE && i > 0u &&
        (token_kind(i - 1u) == TK_PARAM_LPAREN || token_kind(i - 1u) == TK_LPAREN ||
         token_kind(i - 1u) == TK_PARAM_COMMA || token_kind(i - 1u) == TK_COMMA ||
         token_kind(i - 1u) == TK_AMPERSAND);
    if (kind == TK_PARAM_IDENT || self_param ||
        (kind == TK_IDENT && i + 1u < n && token_kind(i + 1u) == TK_COLON &&
         (i == 0u || (token_kind(i - 1u) != TK_LET && token_kind(i - 1u) != TK_CONST &&
                      token_kind(i - 1u) != TK_TYPE))))
        return HIR_PARAM;
    if ((kind == TK_IDENT || kind == TK_TYPE_IDENT) &&
        ((i > 0u && token_kind(i - 1u) == TK_IN) || token_in_for_iterable(i)))
        return HIR_NAME_EXPR;
    if (kind == TK_TYPE_IDENT &&
        ((i > 0u && ((token_kind(i - 1u) == TK_COLON &&
                      !is_struct_literal_field_value_context(i)) ||
                     token_kind(i - 1u) == TK_ARROW ||
                     token_kind(i - 1u) == TK_AMPERSAND ||
                     token_in_type_array(i) ||
                     token_in_shallow_generic_type_arg(i)))))
    {
        return HIR_TYPE;
    }
    if (kind == TK_IDENT &&
        ((i > 0u && token_kind(i - 1u) == TK_IN) || token_in_for_iterable(i)))
        return HIR_NAME_EXPR;
    if (kind == TK_IDENT &&
        (i > 0u && ((token_kind(i - 1u) == TK_COLON &&
                     !is_struct_literal_field_value_context(i)) ||
                    token_kind(i - 1u) == TK_ARROW ||
                    token_kind(i - 1u) == TK_AMPERSAND ||
                    token_in_type_array(i) ||
                    token_in_shallow_generic_type_arg(i))) &&
        token_kind(i - 1u) != TK_IN)
    {
        return HIR_TYPE;
    }
    if (kind == TK_AMPERSAND)
    {
        uint prev = i > 0u ? token_kind(i - 1u) : 0u;
        if (prev == TK_COLON || prev == TK_ARROW || prev == TK_AMPERSAND ||
            token_in_type_array(i))
            return HIR_TYPE;
    }
    if (is_type_open(kind))
    {
        uint prev = i > 0u ? token_kind(i - 1u) : 0u;
        if (prev == TK_COLON || prev == TK_ARROW || prev == TK_AMPERSAND ||
            kind == TK_TYPE_ARRAY_LBRACKET)
        {
            end = matching_type_array_end(i);
            return HIR_TYPE;
        }
    }
    if (is_struct_literal_open_at(i))
    {
        end = matching_brace_end(i);
        return HIR_STRUCT_LITERAL_EXPR;
    }
    if (is_open_brace(kind))
    {
        end = matching_brace_end(i);
        return HIR_BLOCK;
    }
    if (kind == TK_LET)
    {
        end = statement_end(i);
        return HIR_LET_STMT;
    }
    if (kind == TK_CONST)
    {
        end = statement_end(i);
        return HIR_CONST_ITEM;
    }
    if (kind == TK_RETURN)
    {
        end = statement_end(i);
        return HIR_RETURN_STMT;
    }
    if (kind == TK_IF)
    {
        end = control_stmt_end(i);
        return HIR_IF_STMT;
    }
    if (kind == TK_WHILE)
    {
        end = control_stmt_end(i);
        return HIR_WHILE_STMT;
    }
    if (kind == TK_FOR)
    {
        end = control_stmt_end(i);
        return HIR_FOR_STMT;
    }
    if (kind == TK_BREAK)
    {
        end = statement_end(i);
        return HIR_BREAK_STMT;
    }
    if (kind == TK_CONTINUE)
    {
        end = statement_end(i);
        return HIR_CONTINUE_STMT;
    }
    if (is_assignment_operator(kind) && !is_let_initializer_assignment(i))
    {
        end = statement_end(i);
        return HIR_ASSIGN_EXPR;
    }
    if (kind == TK_CALL_LPAREN ||
        (kind == TK_LPAREN && i > 0u && token_kind(i - 1u) == TK_IDENT &&
         (i < 2u || token_kind(i - 2u) != TK_FN)))
    {
        end = matching_call_end(i);
        return HIR_CALL_EXPR;
    }
    if (kind == TK_ARRAY_LBRACKET ||
        (kind == TK_LBRACKET && (i == 0u || !is_expr_end_kind(token_kind(i - 1u)))))
    {
        end = matching_array_literal_end(i);
        return HIR_ARRAY_EXPR;
    }
    if (kind == TK_DOT)
    {
        if (i > 0u && token_kind(i - 1u) == TK_SELF_VALUE)
            return HIR_NONE;
        return HIR_MEMBER_EXPR;
    }
    if (kind == TK_TYPE_IDENT)
        return HIR_NAME_EXPR;
    if (kind == TK_IDENT)
    {
        uint prev = i > 0u ? token_kind(i - 1u) : 0u;
        if (prev == TK_FN || prev == TK_LET || prev == TK_DOT || prev == TK_CONST ||
            prev == TK_TYPE || prev == TK_FOR ||
            prev == TK_ENUM || prev == TK_STRUCT)
            return HIR_NONE;
        return HIR_NAME_EXPR;
    }
    if (kind == TK_SELF_VALUE)
        return HIR_NONE;
    return HIR_NONE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint n = active_token_count();

    if (i == 0u)
    {
        hir_status[0u] = 1u;
        hir_status[1u] = 0u;
        hir_status[2u] = 0u;
        hir_status[3u] = 0u;
        hir_status[4u] = 0u;
        hir_status[5u] = min(n + 1u, gParams.n_tokens + 1u);

        hir_kind[0u] = HIR_FILE;
        hir_token_pos[0u] = 0u;
        hir_token_end[0u] = n;
        hir_token_file_id[0u] = 0u;
    }

    if (i >= n)
        return;

    uint end = i + 1u;
    uint kind = classify(i, end);
    uint out_i = i + 1u;
    hir_kind[out_i] = kind;
    hir_token_pos[out_i] = i;
    hir_token_end[out_i] = min(end, n);
    hir_token_file_id[out_i] = token_file(i);
}
