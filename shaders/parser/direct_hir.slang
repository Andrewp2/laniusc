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

RWStructuredBuffer<uint> hir_kind;
RWStructuredBuffer<uint> hir_token_pos;
RWStructuredBuffer<uint> hir_token_end;
RWStructuredBuffer<uint> hir_status;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

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

static const uint TK_IDENT = 1u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_ASSIGN = 8u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_DOT = 35u;
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
static const uint TK_PARAM_LPAREN = 76u;
static const uint TK_PARAM_RPAREN = 77u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_IF_RBRACE = 89u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_CONST = 92u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;

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
    return before_name != TK_STRUCT && before_name != TK_ENUM && before_name != TK_ARROW &&
           before_name != TK_COLON;
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
           kind == TK_TRUE || kind == TK_FALSE ||
           kind == TK_ARRAY_RBRACKET;
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
        return token_i < min(end, n);
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

uint enum_end(uint enum_i)
{
    uint n = active_token_count();
    [loop]
    for (uint j = enum_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_open_brace(kind))
            return matching_brace_end(j);
        if (kind == TK_SEMICOLON || kind == TK_FN || kind == TK_CONST || kind == TK_ENUM ||
            kind == TK_STRUCT)
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
        if (kind == TK_SEMICOLON || kind == TK_FN || kind == TK_CONST || kind == TK_ENUM ||
            kind == TK_STRUCT)
            return j;
    }
    return n;
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
    if (token_in_type_decl(i))
        return HIR_NONE;
    if (kind == TK_PARAM_IDENT ||
        (kind == TK_IDENT && i + 1u < n && token_kind(i + 1u) == TK_COLON &&
         (i == 0u || (token_kind(i - 1u) != TK_LET && token_kind(i - 1u) != TK_CONST))))
        return HIR_PARAM;
    if (kind == TK_TYPE_IDENT ||
        (kind == TK_IDENT &&
         ((i > 0u && (token_kind(i - 1u) == TK_COLON || token_kind(i - 1u) == TK_ARROW)) ||
          token_in_type_array(i))))
        return HIR_TYPE;
    if (is_type_open(kind))
    {
        uint prev = i > 0u ? token_kind(i - 1u) : 0u;
        if (prev == TK_COLON || prev == TK_ARROW || kind == TK_TYPE_ARRAY_LBRACKET)
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
        return HIR_MEMBER_EXPR;
    if (kind == TK_IDENT)
    {
        uint prev = i > 0u ? token_kind(i - 1u) : 0u;
        if (prev == TK_FN || prev == TK_LET || prev == TK_DOT || prev == TK_CONST ||
            prev == TK_ENUM || prev == TK_STRUCT)
            return HIR_NONE;
        return HIR_NAME_EXPR;
    }
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
    }

    if (i >= n)
        return;

    uint end = i + 1u;
    uint kind = classify(i, end);
    uint out_i = i + 1u;
    hir_kind[out_i] = kind;
    hir_token_pos[out_i] = i;
    hir_token_end[out_i] = min(end, n);
}
