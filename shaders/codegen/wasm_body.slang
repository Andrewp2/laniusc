import utils;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
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
ByteAddressBuffer source_bytes;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> array_len;
StructuredBuffer<uint> array_values;
StructuredBuffer<uint> bool_body_status;
RWStructuredBuffer<uint> body_words;
RWStructuredBuffer<uint> body_status;

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
static const uint TK_SEMICOLON = 37u;
static const uint TK_NOT_EQUAL = 40u;
static const uint TK_PERCENT = 41u;
static const uint TK_CARET = 42u;
static const uint TK_SHL = 43u;
static const uint TK_SHR = 44u;
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
static const uint TK_INFIX_PLUS = 59u;
static const uint TK_PREFIX_MINUS = 60u;
static const uint TK_INFIX_MINUS = 61u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_LET = 68u;
static const uint TK_IF = 70u;
static const uint TK_ELSE = 71u;
static const uint TK_WHILE = 72u;
static const uint TK_BREAK = 73u;
static const uint TK_CONTINUE = 74u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_LET_ASSIGN = 81u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_IF_RBRACE = 89u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint MAX_ARRAY_ELEMS = 16u;

static const uint OP_PAREN = 1000u;
static const uint OP_PREFIX_NEG = 1001u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint active_token_count()
{
    return min(token_count[0u], gParams.n_tokens);
}

uint token_kind(uint i)
{
    return i < active_token_count() ? token_words[i].kind : 0u;
}

uint token_start(uint i)
{
    return i < active_token_count() ? token_words[i].start : 0u;
}

uint token_len(uint i)
{
    return i < active_token_count() ? token_words[i].len : 0u;
}

uint source_at(uint start, uint delta)
{
    uint idx = start + delta;
    return idx < gParams.source_len ? load_byte_at(source_bytes, idx) : 0u;
}

bool token_text_eq5(uint i, uint a, uint b, uint c, uint d, uint e)
{
    uint start = token_start(i);
    return token_len(i) == 5u && source_at(start, 0u) == a && source_at(start, 1u) == b &&
           source_at(start, 2u) == c && source_at(start, 3u) == d &&
           source_at(start, 4u) == e;
}

bool is_print_name(uint i)
{
    return token_text_eq5(i, 112u, 114u, 105u, 110u, 116u);
}

bool is_open_paren(uint kind)
{
    return kind == TK_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_CALL_LPAREN;
}

bool is_close_paren(uint kind)
{
    return kind == TK_RPAREN || kind == TK_GROUP_RPAREN || kind == TK_CALL_RPAREN;
}

bool is_open_brace(uint kind)
{
    return kind == TK_LBRACE || kind == TK_IF_LBRACE;
}

bool is_close_brace(uint kind)
{
    return kind == TK_RBRACE || kind == TK_IF_RBRACE;
}

bool is_index_open(uint kind)
{
    return kind == TK_LBRACKET || kind == TK_INDEX_LBRACKET;
}

bool is_index_close(uint kind)
{
    return kind == TK_RBRACKET || kind == TK_INDEX_RBRACKET;
}

bool is_array_open(uint kind)
{
    return kind == TK_LBRACKET || kind == TK_ARRAY_LBRACKET;
}

bool is_bracket_open(uint kind)
{
    return kind == TK_LBRACKET || kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET;
}

bool is_bracket_close(uint kind)
{
    return kind == TK_RBRACKET || kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET;
}

uint matching_paren(uint open_i)
{
    uint depth = 0u;
    uint n = active_token_count();
    [loop]
    for (uint i = open_i + 1u; i < n; i += 1u)
    {
        uint kind = token_kind(i);
        if (is_open_paren(kind))
            depth += 1u;
        else if (is_close_paren(kind))
        {
            if (depth == 0u)
                return i;
            depth -= 1u;
        }
    }
    return n;
}

uint matching_brace(uint open_i)
{
    uint depth = 0u;
    uint n = active_token_count();
    [loop]
    for (uint i = open_i + 1u; i < n; i += 1u)
    {
        uint kind = token_kind(i);
        if (is_open_brace(kind))
            depth += 1u;
        else if (is_close_brace(kind))
        {
            if (depth == 0u)
                return i;
            depth -= 1u;
        }
    }
    return n;
}

uint find_next_kind(uint start_i, uint end_i, uint wanted)
{
    [loop]
    for (uint i = start_i; i < end_i && i < active_token_count(); i += 1u)
    {
        if (token_kind(i) == wanted)
            return i;
    }
    return 0xffffffffu;
}

uint statement_end(uint start_i)
{
    uint n = active_token_count();
    uint paren_depth = 0u;
    uint bracket_depth = 0u;
    [loop]
    for (uint i = start_i; i < n; i += 1u)
    {
        uint kind = token_kind(i);
        if (is_open_paren(kind))
            paren_depth += 1u;
        else if (is_close_paren(kind) && paren_depth > 0u)
            paren_depth -= 1u;
        else if (is_bracket_open(kind))
            bracket_depth += 1u;
        else if (is_bracket_close(kind) && bracket_depth > 0u)
            bracket_depth -= 1u;
        else if (kind == TK_SEMICOLON && paren_depth == 0u && bracket_depth == 0u)
            return i;
    }
    return n;
}

uint find_assign(uint start_i, uint end_i)
{
    [loop]
    for (uint i = start_i; i < end_i && i < active_token_count(); i += 1u)
    {
        uint kind = token_kind(i);
        if (kind == TK_LET_ASSIGN || kind == TK_ASSIGN)
            return i;
    }
    return 0xffffffffu;
}

void put_byte(inout uint cursor, uint value, bool write, uint target)
{
    if (write && cursor < gParams.out_capacity && cursor == target)
        body_words[cursor] = value & 0xffu;
    cursor += 1u;
}

void emit_u32_leb(inout uint cursor, uint value, bool write, uint lane)
{
    [loop]
    for (uint guard = 0u; guard < 5u; guard += 1u)
    {
        uint byte_value = value & 0x7fu;
        value = value >> 7u;
        if (value != 0u)
            byte_value |= 0x80u;
        put_byte(cursor, byte_value, write, lane);
        if (value == 0u)
            break;
    }
}

void emit_u32_leb5(inout uint cursor, uint value, bool write, uint lane)
{
    [unroll]
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = (value >> (i * 7u)) & 0x7fu;
        if (i < 4u)
            byte_value |= 0x80u;
        put_byte(cursor, byte_value, write, lane);
    }
}

void emit_i64_const_u32(inout uint cursor, uint value, bool write, uint lane)
{
    put_byte(cursor, 0x42u, write, lane);
    [loop]
    for (uint i = 0u; i < 10u; i += 1u)
    {
        if (i < 5u)
            put_byte(cursor, ((value >> (i * 7u)) & 0x7fu) | 0x80u, write, lane);
        else if (i < 9u)
            put_byte(cursor, 0x80u, write, lane);
        else
            put_byte(cursor, 0x00u, write, lane);
    }
}

void emit_i32_const_u32(inout uint cursor, uint value, bool write, uint lane)
{
    put_byte(cursor, 0x41u, write, lane);
    emit_u32_leb5(cursor, value, write, lane);
}

void emit_i64_const_minus_one(inout uint cursor, bool write, uint lane)
{
    put_byte(cursor, 0x42u, write, lane);
    [loop]
    for (uint i = 0u; i < 9u; i += 1u)
        put_byte(cursor, 0xffu, write, lane);
    put_byte(cursor, 0x7fu, write, lane);
}

uint parse_uint_token(uint token_i)
{
    uint value = 0u;
    uint start = token_start(token_i);
    uint len = token_len(token_i);
    [loop]
    for (uint i = 0u; i < len && i < 10u; i += 1u)
    {
        uint ch = source_at(start, i);
        if (ch < 48u || ch > 57u)
            break;
        value = value * 10u + (ch - 48u);
    }
    return value;
}

bool is_binary_op(uint kind)
{
    return kind == TK_PLUS || kind == TK_INFIX_PLUS || kind == TK_MINUS ||
           kind == TK_INFIX_MINUS || kind == TK_STAR || kind == TK_SLASH ||
           kind == TK_PERCENT || kind == TK_SHL || kind == TK_SHR ||
           kind == TK_AMPERSAND || kind == TK_CARET || kind == TK_PIPE;
}

uint precedence(uint op)
{
    if (op == TK_STAR || op == TK_SLASH || op == TK_PERCENT)
        return 7u;
    if (op == TK_PLUS || op == TK_INFIX_PLUS || op == TK_MINUS || op == TK_INFIX_MINUS)
        return 6u;
    if (op == TK_SHL || op == TK_SHR)
        return 5u;
    if (op == TK_AMPERSAND)
        return 4u;
    if (op == TK_CARET)
        return 3u;
    if (op == TK_PIPE)
        return 2u;
    if (op == OP_PREFIX_NEG)
        return 8u;
    return 0u;
}

void emit_op(inout uint cursor, uint op, bool write, uint lane)
{
    if (op == OP_PREFIX_NEG)
    {
        emit_i64_const_minus_one(cursor, write, lane);
        put_byte(cursor, 0x7eu, write, lane);
    }
    else if (op == TK_PLUS || op == TK_INFIX_PLUS)
        put_byte(cursor, 0x7cu, write, lane);
    else if (op == TK_MINUS || op == TK_INFIX_MINUS)
        put_byte(cursor, 0x7du, write, lane);
    else if (op == TK_STAR)
        put_byte(cursor, 0x7eu, write, lane);
    else if (op == TK_SLASH)
        put_byte(cursor, 0x7fu, write, lane);
    else if (op == TK_PERCENT)
        put_byte(cursor, 0x81u, write, lane);
    else if (op == TK_AMPERSAND)
        put_byte(cursor, 0x83u, write, lane);
    else if (op == TK_PIPE)
        put_byte(cursor, 0x84u, write, lane);
    else if (op == TK_CARET)
        put_byte(cursor, 0x85u, write, lane);
    else if (op == TK_SHL)
        put_byte(cursor, 0x86u, write, lane);
    else if (op == TK_SHR)
        put_byte(cursor, 0x87u, write, lane);
}

void emit_local_get(inout uint cursor, uint local_i, bool write, uint lane)
{
    put_byte(cursor, 0x20u, write, lane);
    emit_u32_leb5(cursor, local_i, write, lane);
}

void emit_local_set(inout uint cursor, uint local_i, bool write, uint lane)
{
    put_byte(cursor, 0x21u, write, lane);
    emit_u32_leb5(cursor, local_i, write, lane);
}

void emit_i32_index_atom(inout uint cursor, uint token_i, bool write, uint lane)
{
    uint kind = token_kind(token_i);
    if (kind == TK_INT)
    {
        emit_i32_const_u32(cursor, parse_uint_token(token_i), write, lane);
    }
    else if (kind == TK_TRUE || kind == TK_FALSE)
    {
        emit_i32_const_u32(cursor, kind == TK_TRUE ? 1u : 0u, write, lane);
    }
    else if (kind == TK_IDENT || kind == TK_LET_IDENT)
    {
        uint decl = visible_decl[token_i];
        if (decl != 0xffffffffu)
        {
            emit_local_get(cursor, decl, write, lane);
            put_byte(cursor, 0xa7u, write, lane);
        }
        else
        {
            emit_i32_const_u32(cursor, 0u, write, lane);
        }
    }
    else
    {
        emit_i32_const_u32(cursor, 0u, write, lane);
    }
}

void emit_array_lookup(inout uint cursor, uint decl, uint index_i, bool write, uint lane)
{
    emit_i64_const_u32(cursor, 0u, write, lane);
    emit_local_set(cursor, 0u, write, lane);

    uint len = decl < active_token_count() ? min(array_len[decl], MAX_ARRAY_ELEMS) : 0u;
    [loop]
    for (uint elem = 0u; elem < MAX_ARRAY_ELEMS; elem += 1u)
    {
        if (elem >= len)
            break;
        emit_local_get(cursor, 0u, write, lane);
        emit_i64_const_u32(cursor, array_values[decl * MAX_ARRAY_ELEMS + elem], write, lane);
        emit_i32_index_atom(cursor, index_i, write, lane);
        emit_i32_const_u32(cursor, elem, write, lane);
        put_byte(cursor, 0x46u, write, lane);
        put_byte(cursor, 0x45u, write, lane);
        put_byte(cursor, 0x1bu, write, lane);
        emit_local_set(cursor, 0u, write, lane);
    }
    emit_local_get(cursor, 0u, write, lane);
}

void pop_op(inout uint cursor, inout uint op_top, inout uint op_stack[64], bool write, uint lane)
{
    if (op_top == 0u)
        return;
    op_top -= 1u;
    emit_op(cursor, op_stack[op_top], write, lane);
}

void push_op(inout uint op_top, inout uint op_stack[64], uint op)
{
    if (op_top < 64u)
    {
        op_stack[op_top] = op;
        op_top += 1u;
    }
}

void pop_until_paren(inout uint cursor, inout uint op_top, inout uint op_stack[64], bool write, uint lane)
{
    [loop]
    for (uint guard = 0u; guard < 64u && op_top > 0u; guard += 1u)
    {
        if (op_stack[op_top - 1u] == OP_PAREN)
            break;
        pop_op(cursor, op_top, op_stack, write, lane);
    }
}

void emit_int_expr(inout uint cursor, uint start_i, uint end_i, bool write, uint lane)
{
    uint op_stack[64];
    uint op_top = 0u;
    [loop]
    for (uint i = start_i; i < end_i && i < active_token_count(); i += 1u)
    {
        uint kind = token_kind(i);
        if (kind == TK_INT)
        {
            emit_i64_const_u32(cursor, parse_uint_token(i), write, lane);
        }
        else if (kind == TK_TRUE || kind == TK_FALSE)
        {
            emit_i64_const_u32(cursor, kind == TK_TRUE ? 1u : 0u, write, lane);
        }
        else if (kind == TK_IDENT || kind == TK_LET_IDENT)
        {
            uint decl = visible_decl[i];
            if (decl != 0xffffffffu)
            {
                if (i + 3u < end_i && is_index_open(token_kind(i + 1u)) &&
                    is_index_close(token_kind(i + 3u)))
                {
                    emit_array_lookup(cursor, decl, i + 2u, write, lane);
                    i += 3u;
                }
                else
                {
                    emit_local_get(cursor, decl, write, lane);
                }
            }
        }
        else if (kind == TK_PREFIX_MINUS || kind == TK_MINUS)
        {
            uint prev = i > start_i ? token_kind(i - 1u) : 0u;
            bool prefix = kind == TK_PREFIX_MINUS || i == start_i || is_binary_op(prev) ||
                          is_open_paren(prev);
            uint op = prefix ? OP_PREFIX_NEG : TK_MINUS;
            [loop]
            for (uint guard = 0u; guard < 64u && op_top > 0u; guard += 1u)
            {
                uint top = op_stack[op_top - 1u];
                if (top == OP_PAREN || precedence(top) < precedence(op))
                    break;
                pop_op(cursor, op_top, op_stack, write, lane);
            }
            push_op(op_top, op_stack, op);
        }
        else if (is_binary_op(kind))
        {
            uint op = kind == TK_INFIX_PLUS ? TK_PLUS : (kind == TK_INFIX_MINUS ? TK_MINUS : kind);
            [loop]
            for (uint guard = 0u; guard < 64u && op_top > 0u; guard += 1u)
            {
                uint top = op_stack[op_top - 1u];
                if (top == OP_PAREN || precedence(top) < precedence(op))
                    break;
                pop_op(cursor, op_top, op_stack, write, lane);
            }
            push_op(op_top, op_stack, op);
        }
        else if (is_open_paren(kind))
        {
            push_op(op_top, op_stack, OP_PAREN);
        }
        else if (is_close_paren(kind))
        {
            pop_until_paren(cursor, op_top, op_stack, write, lane);
            if (op_top > 0u && op_stack[op_top - 1u] == OP_PAREN)
                op_top -= 1u;
        }
    }
    [loop]
    for (uint guard = 0u; guard < 64u && op_top > 0u; guard += 1u)
        pop_op(cursor, op_top, op_stack, write, lane);
}

bool is_compare_op(uint kind)
{
    return kind == TK_LT || kind == TK_GT || kind == TK_LE || kind == TK_GE ||
           kind == TK_EQEQ || kind == TK_NOT_EQUAL;
}

void emit_compare_op(inout uint cursor, uint op, bool write, uint lane)
{
    if (op == TK_LT)
        put_byte(cursor, 0x53u, write, lane);
    else if (op == TK_GT)
        put_byte(cursor, 0x55u, write, lane);
    else if (op == TK_LE)
        put_byte(cursor, 0x57u, write, lane);
    else if (op == TK_GE)
        put_byte(cursor, 0x59u, write, lane);
    else if (op == TK_EQEQ)
        put_byte(cursor, 0x51u, write, lane);
    else if (op == TK_NOT_EQUAL)
        put_byte(cursor, 0x52u, write, lane);
}

uint assignment_binary_op(uint kind)
{
    if (kind == TK_PLUS_ASSIGN)
        return TK_PLUS;
    if (kind == TK_MINUS_ASSIGN)
        return TK_MINUS;
    if (kind == TK_STAR_ASSIGN)
        return TK_STAR;
    if (kind == TK_SLASH_ASSIGN)
        return TK_SLASH;
    if (kind == TK_PERCENT_ASSIGN)
        return TK_PERCENT;
    if (kind == TK_CARET_ASSIGN)
        return TK_CARET;
    if (kind == TK_SHL_ASSIGN)
        return TK_SHL;
    if (kind == TK_SHR_ASSIGN)
        return TK_SHR;
    if (kind == TK_AMP_ASSIGN)
        return TK_AMPERSAND;
    if (kind == TK_PIPE_ASSIGN)
        return TK_PIPE;
    return 0u;
}

bool is_assignment_op(uint kind)
{
    return kind == TK_ASSIGN || assignment_binary_op(kind) != 0u;
}

void emit_let_statement(inout uint cursor, uint let_i, uint semi, bool write, uint lane)
{
    uint decl = let_i + 1u;
    uint assign_i = find_assign(let_i, semi);
    if (assign_i == 0xffffffffu)
        return;

    uint rhs_start = assign_i + 1u;
    if (rhs_start < semi && is_array_open(token_kind(rhs_start)))
    {
        emit_i64_const_u32(cursor, 0u, write, lane);
        emit_local_set(cursor, decl, write, lane);
    }
    else
    {
        emit_int_expr(cursor, rhs_start, semi, write, lane);
        emit_local_set(cursor, decl, write, lane);
    }
}

void emit_assignment_statement(inout uint cursor, uint name_i, uint semi, bool write, uint lane)
{
    uint op = token_kind(name_i + 1u);
    uint decl = visible_decl[name_i];
    if (decl == 0xffffffffu)
        return;

    if (op == TK_ASSIGN)
    {
        emit_int_expr(cursor, name_i + 2u, semi, write, lane);
        emit_local_set(cursor, decl, write, lane);
        return;
    }

    uint binary = assignment_binary_op(op);
    if (binary == 0u)
        return;
    emit_local_get(cursor, decl, write, lane);
    emit_int_expr(cursor, name_i + 2u, semi, write, lane);
    emit_op(cursor, binary, write, lane);
    emit_local_set(cursor, decl, write, lane);
}

void emit_print_statement(inout uint cursor, uint name_i, bool write, uint lane)
{
    uint close_i = matching_paren(name_i + 1u);
    emit_int_expr(cursor, name_i + 2u, close_i, write, lane);
    put_byte(cursor, 0x10u, write, lane);
    emit_u32_leb(cursor, 0u, write, lane);
}

void emit_cond_expr(inout uint cursor, uint start_i, uint end_i, bool write, uint lane)
{
    uint op_i = 0xffffffffu;
    [loop]
    for (uint i = start_i; i < end_i && i < active_token_count(); i += 1u)
    {
        uint kind = token_kind(i);
        if (is_compare_op(kind))
        {
            op_i = i;
            break;
        }
    }
    if (op_i == 0xffffffffu)
    {
        emit_int_expr(cursor, start_i, end_i, write, lane);
        emit_i64_const_u32(cursor, 0u, write, lane);
        put_byte(cursor, 0x52u, write, lane);
        return;
    }
    emit_int_expr(cursor, start_i, op_i, write, lane);
    emit_int_expr(cursor, op_i + 1u, end_i, write, lane);
    emit_compare_op(cursor, token_kind(op_i), write, lane);
}

void emit_branch(inout uint cursor, uint label, bool write, uint lane)
{
    put_byte(cursor, 0x0cu, write, lane);
    emit_u32_leb(cursor, label, write, lane);
}

void emit_if_body_statements(
    inout uint cursor,
    uint start_i,
    uint end_i,
    bool inside_loop,
    bool write,
    uint lane)
{
    uint n = min(end_i, active_token_count());
    [loop]
    for (uint i = start_i; i < n; i += 1u)
    {
        if (i + 1u < n && token_kind(i) == TK_IDENT && is_print_name(i) &&
            (token_kind(i + 1u) == TK_CALL_LPAREN || token_kind(i + 1u) == TK_LPAREN))
        {
            uint close_i = matching_paren(i + 1u);
            emit_print_statement(cursor, i, write, lane);
            i = close_i;
        }
        else if (token_kind(i) == TK_CONTINUE)
        {
            if (inside_loop)
                emit_branch(cursor, 1u, write, lane);
            i = statement_end(i);
        }
        else if (token_kind(i) == TK_BREAK)
        {
            if (inside_loop)
                emit_branch(cursor, 2u, write, lane);
            i = statement_end(i);
        }
    }
}

uint emit_if_statement(inout uint cursor, uint if_i, bool inside_loop, bool write, uint lane)
{
    uint cond_open = find_next_kind(if_i + 1u, active_token_count(), TK_GROUP_LPAREN);
    if (cond_open == 0xffffffffu)
        cond_open = find_next_kind(if_i + 1u, active_token_count(), TK_LPAREN);
    if (cond_open == 0xffffffffu)
        return if_i;
    uint cond_close = matching_paren(cond_open);
    uint then_open = find_next_kind(cond_close + 1u, active_token_count(), TK_LBRACE);
    if (then_open == 0xffffffffu)
        then_open = find_next_kind(cond_close + 1u, active_token_count(), TK_IF_LBRACE);
    if (then_open == 0xffffffffu)
        return cond_close;
    uint then_close = matching_brace(then_open);

    uint else_open = 0xffffffffu;
    uint else_close = 0xffffffffu;
    uint after_then = then_close + 1u;
    if (after_then < active_token_count() && token_kind(after_then) == TK_ELSE)
    {
        else_open = find_next_kind(after_then + 1u, active_token_count(), TK_LBRACE);
        if (else_open == 0xffffffffu)
            else_open = find_next_kind(after_then + 1u, active_token_count(), TK_IF_LBRACE);
        if (else_open != 0xffffffffu)
            else_close = matching_brace(else_open);
    }

    emit_cond_expr(cursor, cond_open + 1u, cond_close, write, lane);
    put_byte(cursor, 0x04u, write, lane);
    put_byte(cursor, 0x40u, write, lane);
    emit_if_body_statements(cursor, then_open + 1u, then_close, inside_loop, write, lane);
    if (else_open != 0xffffffffu && else_close != 0xffffffffu)
    {
        put_byte(cursor, 0x05u, write, lane);
        emit_if_body_statements(cursor, else_open + 1u, else_close, inside_loop, write, lane);
    }
    put_byte(cursor, 0x0bu, write, lane);
    return else_close != 0xffffffffu ? else_close : then_close;
}

void emit_block_statements(inout uint cursor, uint start_i, uint end_i, bool inside_loop, bool write, uint lane)
{
    uint n = min(end_i, active_token_count());
    [loop]
    for (uint i = start_i; i < n; i += 1u)
    {
        if (token_kind(i) == TK_IF)
        {
            i = emit_if_statement(cursor, i, inside_loop, write, lane);
        }
        else if (token_kind(i) == TK_CONTINUE)
        {
            if (inside_loop)
                emit_branch(cursor, 0u, write, lane);
            i = statement_end(i);
        }
        else if (token_kind(i) == TK_BREAK)
        {
            if (inside_loop)
                emit_branch(cursor, 1u, write, lane);
            i = statement_end(i);
        }
        else if (token_kind(i) == TK_LET && i + 1u < n)
        {
            uint semi = statement_end(i);
            emit_let_statement(cursor, i, semi, write, lane);
            i = semi;
        }
        else if (i + 1u < n && token_kind(i) == TK_IDENT && is_assignment_op(token_kind(i + 1u)))
        {
            uint semi = statement_end(i);
            emit_assignment_statement(cursor, i, semi, write, lane);
            i = semi;
        }
        else if (i + 1u < n && token_kind(i) == TK_IDENT && is_print_name(i) &&
            (token_kind(i + 1u) == TK_CALL_LPAREN || token_kind(i + 1u) == TK_LPAREN))
        {
            uint close_i = matching_paren(i + 1u);
            emit_print_statement(cursor, i, write, lane);
            i = close_i;
        }
    }
}

void emit_while_statement(inout uint cursor, uint while_i, bool write, uint lane)
{
    uint cond_open = find_next_kind(while_i + 1u, active_token_count(), TK_GROUP_LPAREN);
    if (cond_open == 0xffffffffu)
        cond_open = find_next_kind(while_i + 1u, active_token_count(), TK_LPAREN);
    if (cond_open == 0xffffffffu)
        return;
    uint cond_close = matching_paren(cond_open);
    uint body_open = find_next_kind(cond_close + 1u, active_token_count(), TK_LBRACE);
    if (body_open == 0xffffffffu)
        body_open = find_next_kind(cond_close + 1u, active_token_count(), TK_IF_LBRACE);
    if (body_open == 0xffffffffu)
        return;
    uint body_close = matching_brace(body_open);

    put_byte(cursor, 0x02u, write, lane);
    put_byte(cursor, 0x40u, write, lane);
    put_byte(cursor, 0x03u, write, lane);
    put_byte(cursor, 0x40u, write, lane);
    emit_cond_expr(cursor, cond_open + 1u, cond_close, write, lane);
    put_byte(cursor, 0x45u, write, lane);
    put_byte(cursor, 0x0du, write, lane);
    emit_u32_leb(cursor, 1u, write, lane);
    emit_block_statements(cursor, body_open + 1u, body_close, true, write, lane);
    put_byte(cursor, 0x0cu, write, lane);
    emit_u32_leb(cursor, 0u, write, lane);
    put_byte(cursor, 0x0bu, write, lane);
    put_byte(cursor, 0x0bu, write, lane);
}

void emit_body(inout uint cursor, bool write, uint lane)
{
    emit_u32_leb(cursor, 1u, write, lane);
    emit_u32_leb5(cursor, active_token_count() + 1u, write, lane);
    put_byte(cursor, 0x7eu, write, lane);
    uint n = active_token_count();
    [loop]
    for (uint i = 0u; i < n; i += 1u)
    {
        if (token_kind(i) == TK_LET && i + 1u < n)
        {
            uint semi = statement_end(i);
            emit_let_statement(cursor, i, semi, write, lane);
            i = semi;
        }
        else if (i + 1u < n && token_kind(i) == TK_IDENT && is_assignment_op(token_kind(i + 1u)))
        {
            uint semi = statement_end(i);
            emit_assignment_statement(cursor, i, semi, write, lane);
            i = semi;
        }
        else if (token_kind(i) == TK_WHILE)
        {
            uint body_open = find_next_kind(i + 1u, n, TK_LBRACE);
            if (body_open == 0xffffffffu)
                body_open = find_next_kind(i + 1u, n, TK_IF_LBRACE);
            uint body_close = body_open == 0xffffffffu ? n : matching_brace(body_open);
            emit_while_statement(cursor, i, write, lane);
            i = body_close;
        }
        else if (token_kind(i) == TK_IF)
        {
            i = emit_if_statement(cursor, i, false, write, lane);
        }
        else if (i + 1u < n && token_kind(i) == TK_IDENT && is_print_name(i) &&
            (token_kind(i + 1u) == TK_CALL_LPAREN || token_kind(i + 1u) == TK_LPAREN))
        {
            uint close_i = matching_paren(i + 1u);
            emit_print_statement(cursor, i, write, lane);
            i = close_i;
        }
    }
    put_byte(cursor, 0x41u, write, lane);
    emit_u32_leb(cursor, 0u, write, lane);
    put_byte(cursor, 0x0bu, write, lane);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (body_status[1u] == 2u)
        return;
    if (bool_body_status[1u] != 0u)
        return;
    uint target = linear_dispatch_id(tid);
    if (target >= gParams.out_capacity)
        return;

    uint len = 0u;
    emit_body(len, true, target);
    if (target == 0u)
    {
        body_status[0u] = len;
        body_status[1u] = len <= gParams.out_capacity ? 1u : 0u;
    }
}
