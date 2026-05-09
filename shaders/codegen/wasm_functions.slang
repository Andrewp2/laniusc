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
StructuredBuffer<uint> body_status;
RWStructuredBuffer<uint> out_words;
RWStructuredBuffer<uint> status;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_ASSIGN = 8u;
static const uint TK_PLUS = 6u;
static const uint TK_STAR = 7u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LE = 14u;
static const uint TK_GE = 15u;
static const uint TK_EQEQ = 16u;
static const uint TK_MINUS = 27u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_NOT_EQUAL = 40u;
static const uint TK_INFIX_PLUS = 59u;
static const uint TK_PREFIX_MINUS = 60u;
static const uint TK_INFIX_MINUS = 61u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_FN = 67u;
static const uint TK_RETURN = 69u;
static const uint TK_IF = 70u;
static const uint TK_ELSE = 71u;
static const uint TK_PARAM_LPAREN = 76u;
static const uint TK_PARAM_RPAREN = 77u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_IF_RBRACE = 89u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_CONST = 92u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

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

bool span4(uint start, uint len, uint a, uint b, uint c, uint d)
{
    return len == 4u && source_at(start, 0u) == a && source_at(start, 1u) == b &&
           source_at(start, 2u) == c && source_at(start, 3u) == d;
}

bool span5(uint start, uint len, uint a, uint b, uint c, uint d, uint e)
{
    return len == 5u && source_at(start, 0u) == a && source_at(start, 1u) == b &&
           source_at(start, 2u) == c && source_at(start, 3u) == d &&
           source_at(start, 4u) == e;
}

bool is_main_name(uint i)
{
    return span4(token_start(i), token_len(i), 109u, 97u, 105u, 110u);
}

bool is_print_name(uint i)
{
    return span5(token_start(i), token_len(i), 112u, 114u, 105u, 110u, 116u);
}

bool is_assert_name(uint i)
{
    uint start = token_start(i);
    return token_len(i) == 6u && source_at(start, 0u) == 97u &&
           source_at(start, 1u) == 115u && source_at(start, 2u) == 115u &&
           source_at(start, 3u) == 101u && source_at(start, 4u) == 114u &&
           source_at(start, 5u) == 116u;
}

bool is_builtin_name(uint i)
{
    return is_print_name(i) || is_assert_name(i);
}

bool same_text(uint a_i, uint b_i)
{
    uint len = token_len(a_i);
    if (len != token_len(b_i))
        return false;
    uint a = token_start(a_i);
    uint b = token_start(b_i);
    [loop]
    for (uint i = 0u; i < len && i < 64u; i += 1u)
    {
        if (source_at(a, i) != source_at(b, i))
            return false;
    }
    return true;
}

bool is_open_paren(uint kind)
{
    return kind == TK_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_CALL_LPAREN ||
           kind == TK_PARAM_LPAREN;
}

bool is_close_paren(uint kind)
{
    return kind == TK_RPAREN || kind == TK_GROUP_RPAREN || kind == TK_CALL_RPAREN ||
           kind == TK_PARAM_RPAREN;
}

bool is_open_brace(uint kind)
{
    return kind == TK_LBRACE || kind == TK_IF_LBRACE;
}

bool is_close_brace(uint kind)
{
    return kind == TK_RBRACE || kind == TK_IF_RBRACE;
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

uint statement_end(uint start_i, uint limit_i)
{
    uint depth = 0u;
    [loop]
    for (uint i = start_i; i < limit_i && i < active_token_count(); i += 1u)
    {
        uint kind = token_kind(i);
        if (is_open_paren(kind))
            depth += 1u;
        else if (is_close_paren(kind) && depth > 0u)
            depth -= 1u;
        else if (kind == TK_SEMICOLON && depth == 0u)
            return i;
    }
    return limit_i;
}

uint find_next_kind(uint start_i, uint end_i, uint wanted)
{
    [loop]
    for (uint i = start_i; i < end_i && i < active_token_count(); i += 1u)
    {
        if (token_kind(i) == wanted)
            return i;
    }
    return INVALID;
}

uint function_count()
{
    uint count = 0u;
    uint n = active_token_count();
    [loop]
    for (uint i = 0u; i < n; i += 1u)
    {
        if (token_kind(i) == TK_FN)
            count += 1u;
    }
    return count;
}

uint function_order(uint fn_i)
{
    uint order = 0u;
    [loop]
    for (uint i = 0u; i < fn_i && i < active_token_count(); i += 1u)
    {
        if (token_kind(i) == TK_FN)
            order += 1u;
    }
    return order;
}

uint function_by_order(uint wanted)
{
    uint order = 0u;
    uint n = active_token_count();
    [loop]
    for (uint i = 0u; i < n; i += 1u)
    {
        if (token_kind(i) == TK_FN)
        {
            if (order == wanted)
                return i;
            order += 1u;
        }
    }
    return INVALID;
}

uint find_named_function(uint name_i)
{
    uint n = active_token_count();
    [loop]
    for (uint i = 0u; i + 1u < n; i += 1u)
    {
        if (token_kind(i) == TK_FN && same_text(i + 1u, name_i))
            return i;
    }
    return INVALID;
}

uint main_function()
{
    uint n = active_token_count();
    [loop]
    for (uint i = 0u; i + 1u < n; i += 1u)
    {
        if (token_kind(i) == TK_FN && is_main_name(i + 1u))
            return i;
    }
    return INVALID;
}

uint function_body_open(uint fn_i)
{
    return find_next_kind(fn_i + 1u, active_token_count(), TK_LBRACE);
}

uint function_body_close(uint fn_i)
{
    uint open_i = function_body_open(fn_i);
    return open_i == INVALID ? active_token_count() : matching_brace(open_i);
}

uint function_param_count(uint fn_i)
{
    uint open_i = find_next_kind(fn_i + 1u, active_token_count(), TK_PARAM_LPAREN);
    if (open_i == INVALID)
        open_i = find_next_kind(fn_i + 1u, active_token_count(), TK_LPAREN);
    if (open_i == INVALID)
        open_i = find_next_kind(fn_i + 1u, active_token_count(), TK_GROUP_LPAREN);
    if (open_i == INVALID)
        return 0u;
    uint close_i = matching_paren(open_i);
    uint count = 0u;
    [loop]
    for (uint i = open_i + 1u; i < close_i && i < active_token_count(); i += 1u)
    {
        uint kind = token_kind(i);
        if (kind == TK_PARAM_IDENT || (kind == TK_IDENT && i + 1u < close_i &&
                                        token_kind(i + 1u) == TK_COLON))
            count += 1u;
    }
    return count;
}

uint function_param_token(uint fn_i, uint param_index)
{
    uint open_i = find_next_kind(fn_i + 1u, active_token_count(), TK_PARAM_LPAREN);
    if (open_i == INVALID)
        open_i = find_next_kind(fn_i + 1u, active_token_count(), TK_LPAREN);
    if (open_i == INVALID)
        open_i = find_next_kind(fn_i + 1u, active_token_count(), TK_GROUP_LPAREN);
    if (open_i == INVALID)
        return INVALID;
    uint close_i = matching_paren(open_i);
    uint count = 0u;
    [loop]
    for (uint i = open_i + 1u; i < close_i && i < active_token_count(); i += 1u)
    {
        uint kind = token_kind(i);
        if (kind == TK_PARAM_IDENT || (kind == TK_IDENT && i + 1u < close_i &&
                                        token_kind(i + 1u) == TK_COLON))
        {
            if (count == param_index)
                return i;
            count += 1u;
        }
    }
    return INVALID;
}

bool has_user_call()
{
    uint n = active_token_count();
    [loop]
    for (uint i = 0u; i + 1u < n; i += 1u)
    {
        if (token_kind(i) == TK_IDENT &&
            (token_kind(i + 1u) == TK_CALL_LPAREN || token_kind(i + 1u) == TK_LPAREN) &&
            (i == 0u || token_kind(i - 1u) != TK_FN) &&
            !is_builtin_name(i) && find_named_function(i) != INVALID)
            return true;
    }
    return false;
}

void put_byte(inout uint cursor, uint value, bool write, uint target)
{
    if (write && cursor < gParams.out_capacity && cursor == target)
        out_words[cursor] = value & 0xffu;
    cursor += 1u;
}

void put_byte_at(uint cursor, uint value, bool write, uint target)
{
    if (write && cursor < gParams.out_capacity && cursor == target)
        out_words[cursor] = value & 0xffu;
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

void patch_u32_leb5(uint cursor, uint value, bool write, uint lane)
{
    [unroll]
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = (value >> (i * 7u)) & 0x7fu;
        if (i < 4u)
            byte_value |= 0x80u;
        put_byte_at(cursor + i, byte_value, write, lane);
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

void emit_i64_const_minus_one(inout uint cursor, bool write, uint lane)
{
    put_byte(cursor, 0x42u, write, lane);
    [loop]
    for (uint i = 0u; i < 9u; i += 1u)
        put_byte(cursor, 0xffu, write, lane);
    put_byte(cursor, 0x7fu, write, lane);
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

bool is_const_decl_at(uint decl_i)
{
    return decl_i < active_token_count() && token_kind(decl_i) == TK_IDENT && decl_i > 0u &&
           token_kind(decl_i - 1u) == TK_CONST;
}

uint const_value_token(uint decl_i, out bool negate)
{
    negate = false;
    uint semi = statement_end(decl_i, active_token_count());
    uint assign_i = find_next_kind(decl_i + 1u, semi, TK_ASSIGN);
    if (assign_i == INVALID || assign_i + 1u >= semi)
        return INVALID;

    uint value_i = assign_i + 1u;
    uint kind = token_kind(value_i);
    if ((kind == TK_MINUS || kind == TK_PREFIX_MINUS) && value_i + 1u < semi)
    {
        negate = true;
        value_i += 1u;
    }
    return value_i;
}

void emit_const_decl_value(inout uint cursor, uint decl_i, bool write, uint lane)
{
    bool negate = false;
    uint value_i = const_value_token(decl_i, negate);
    uint kind = token_kind(value_i);
    if (kind == TK_INT)
    {
        emit_i64_const_u32(cursor, parse_uint_token(value_i), write, lane);
        if (negate)
        {
            emit_i64_const_minus_one(cursor, write, lane);
            put_byte(cursor, 0x7eu, write, lane);
        }
        return;
    }
    if (kind == TK_TRUE || kind == TK_FALSE)
    {
        emit_i64_const_u32(cursor, kind == TK_TRUE ? 1u : 0u, write, lane);
        return;
    }
    emit_i64_const_u32(cursor, 0u, write, lane);
}

void emit_atom(inout uint cursor, uint token_i, bool write, uint lane)
{
    uint kind = token_kind(token_i);
    if (kind == TK_INT)
        emit_i64_const_u32(cursor, parse_uint_token(token_i), write, lane);
    else if (kind == TK_TRUE || kind == TK_FALSE)
        emit_i64_const_u32(cursor, kind == TK_TRUE ? 1u : 0u, write, lane);
    else if (kind == TK_IDENT || kind == TK_PARAM_IDENT)
    {
        uint decl = visible_decl[token_i];
        if (decl != INVALID)
        {
            if (is_const_decl_at(decl))
                emit_const_decl_value(cursor, decl, write, lane);
            else
                emit_local_get(cursor, decl, write, lane);
        }
        else
            emit_i64_const_u32(cursor, 0u, write, lane);
    }
    else
        emit_i64_const_u32(cursor, 0u, write, lane);
}

void emit_simple_expr(inout uint cursor, uint start_i, uint end_i, bool write, uint lane)
{
    bool have_value = false;
    uint pending_op = 0u;
    bool negate_next = false;
    [loop]
    for (uint i = start_i; i < end_i && i < active_token_count(); i += 1u)
    {
        uint kind = token_kind(i);
        if (kind == TK_MINUS || kind == TK_PREFIX_MINUS)
        {
            if (!have_value && pending_op == 0u)
                negate_next = true;
            else
                pending_op = TK_MINUS;
        }
        else if (kind == TK_PLUS || kind == TK_INFIX_PLUS || kind == TK_INFIX_MINUS ||
                 kind == TK_STAR)
        {
            pending_op = kind == TK_INFIX_MINUS ? TK_MINUS : kind;
        }
        else if (kind == TK_INT || kind == TK_TRUE || kind == TK_FALSE ||
                 kind == TK_IDENT || kind == TK_PARAM_IDENT)
        {
            emit_atom(cursor, i, write, lane);
            if (negate_next)
            {
                emit_i64_const_minus_one(cursor, write, lane);
                put_byte(cursor, 0x7eu, write, lane);
                negate_next = false;
            }
            if (have_value)
            {
                if (pending_op == TK_MINUS)
                    put_byte(cursor, 0x7du, write, lane);
                else if (pending_op == TK_STAR)
                    put_byte(cursor, 0x7eu, write, lane);
                else
                    put_byte(cursor, 0x7cu, write, lane);
            }
            have_value = true;
            pending_op = 0u;
        }
    }
    if (!have_value)
        emit_i64_const_u32(cursor, 0u, write, lane);
}

uint arg_start(uint open_i, uint close_i, uint wanted)
{
    uint current = 0u;
    uint start = open_i + 1u;
    [loop]
    for (uint i = open_i + 1u; i < close_i && i < active_token_count(); i += 1u)
    {
        if (token_kind(i) == 36u || token_kind(i) == 82u)
        {
            if (current == wanted)
                return start;
            current += 1u;
            start = i + 1u;
        }
    }
    return current == wanted ? start : INVALID;
}

uint arg_end(uint start_i, uint close_i)
{
    [loop]
    for (uint i = start_i; i < close_i && i < active_token_count(); i += 1u)
    {
        if (token_kind(i) == 36u || token_kind(i) == 82u)
            return i;
    }
    return close_i;
}

void emit_call(inout uint cursor, uint callee_i, uint close_i, bool write, uint lane)
{
    uint fn_i = find_named_function(callee_i);
    uint params = function_param_count(fn_i);
    [loop]
    for (uint arg = 0u; arg < 2u; arg += 1u)
    {
        if (arg >= params)
            break;
        uint s = arg_start(callee_i + 1u, close_i, arg);
        if (s != INVALID)
            emit_simple_expr(cursor, s, arg_end(s, close_i), write, lane);
    }
    put_byte(cursor, 0x10u, write, lane);
    emit_u32_leb(cursor, 1u + function_order(fn_i), write, lane);
}

void emit_expr(inout uint cursor, uint start_i, uint end_i, bool write, uint lane)
{
    bool have_value = false;
    uint pending_op = 0u;
    bool negate_next = false;
    [loop]
    for (uint i = start_i; i < end_i && i < active_token_count(); i += 1u)
    {
        uint kind = token_kind(i);
        if ((kind == TK_IDENT || kind == TK_PARAM_IDENT) && i + 1u < end_i &&
            (token_kind(i + 1u) == TK_CALL_LPAREN || token_kind(i + 1u) == TK_LPAREN) &&
            find_named_function(i) != INVALID)
        {
            uint close_i = matching_paren(i + 1u);
            emit_call(cursor, i, close_i, write, lane);
            if (negate_next)
            {
                emit_i64_const_minus_one(cursor, write, lane);
                put_byte(cursor, 0x7eu, write, lane);
                negate_next = false;
            }
            if (have_value)
            {
                if (pending_op == TK_STAR)
                    put_byte(cursor, 0x7eu, write, lane);
                else if (pending_op == TK_MINUS)
                    put_byte(cursor, 0x7du, write, lane);
                else
                    put_byte(cursor, 0x7cu, write, lane);
            }
            have_value = true;
            pending_op = 0u;
            i = close_i;
        }
        else if (kind == TK_MINUS || kind == TK_PREFIX_MINUS)
        {
            if (!have_value && pending_op == 0u)
                negate_next = true;
            else
                pending_op = TK_MINUS;
        }
        else if (kind == TK_PLUS || kind == TK_INFIX_PLUS || kind == TK_INFIX_MINUS ||
                 kind == TK_STAR)
        {
            pending_op = kind == TK_INFIX_MINUS ? TK_MINUS : kind;
        }
        else if (kind == TK_INT || kind == TK_TRUE || kind == TK_FALSE ||
                 kind == TK_IDENT || kind == TK_PARAM_IDENT)
        {
            emit_atom(cursor, i, write, lane);
            if (negate_next)
            {
                emit_i64_const_minus_one(cursor, write, lane);
                put_byte(cursor, 0x7eu, write, lane);
                negate_next = false;
            }
            if (have_value)
            {
                if (pending_op == TK_STAR)
                    put_byte(cursor, 0x7eu, write, lane);
                else if (pending_op == TK_MINUS)
                    put_byte(cursor, 0x7du, write, lane);
                else
                    put_byte(cursor, 0x7cu, write, lane);
            }
            have_value = true;
            pending_op = 0u;
        }
    }
    if (!have_value)
        emit_i64_const_u32(cursor, 0u, write, lane);
}

void emit_cond(inout uint cursor, uint start_i, uint end_i, bool write, uint lane)
{
    uint op_i = INVALID;
    [loop]
    for (uint i = start_i; i < end_i && i < active_token_count(); i += 1u)
    {
        if (token_kind(i) == TK_LT || token_kind(i) == TK_GT || token_kind(i) == TK_LE ||
            token_kind(i) == TK_GE || token_kind(i) == TK_EQEQ || token_kind(i) == TK_NOT_EQUAL)
        {
            op_i = i;
            break;
        }
    }
    if (op_i == INVALID)
    {
        emit_expr(cursor, start_i, end_i, write, lane);
        emit_i64_const_u32(cursor, 0u, write, lane);
        put_byte(cursor, 0x52u, write, lane);
        return;
    }
    emit_expr(cursor, start_i, op_i, write, lane);
    emit_expr(cursor, op_i + 1u, end_i, write, lane);
    uint op = token_kind(op_i);
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

void emit_assert_statement(inout uint cursor, uint name_i, bool write, uint lane)
{
    uint call_close = matching_paren(name_i + 1u);
    emit_cond(cursor, name_i + 2u, call_close, write, lane);
    put_byte(cursor, 0x45u, write, lane);
    put_byte(cursor, 0x04u, write, lane);
    put_byte(cursor, 0x40u, write, lane);
    put_byte(cursor, 0x00u, write, lane);
    put_byte(cursor, 0x0bu, write, lane);
}

uint first_return_expr_start(uint start_i, uint end_i)
{
    [loop]
    for (uint i = start_i; i < end_i && i < active_token_count(); i += 1u)
    {
        if (token_kind(i) == TK_RETURN)
            return i + 1u;
    }
    return INVALID;
}

void emit_if_return(inout uint cursor, uint if_i, bool write, uint lane)
{
    uint cond_open = find_next_kind(if_i + 1u, active_token_count(), TK_GROUP_LPAREN);
    if (cond_open == INVALID)
        cond_open = find_next_kind(if_i + 1u, active_token_count(), TK_LPAREN);
    uint cond_close = matching_paren(cond_open);
    uint then_open = find_next_kind(cond_close + 1u, active_token_count(), TK_LBRACE);
    if (then_open == INVALID)
        then_open = find_next_kind(cond_close + 1u, active_token_count(), TK_IF_LBRACE);
    uint then_close = matching_brace(then_open);
    uint else_open = find_next_kind(then_close + 1u, active_token_count(), TK_LBRACE);
    if (else_open == INVALID)
        else_open = find_next_kind(then_close + 1u, active_token_count(), TK_IF_LBRACE);
    uint else_close = matching_brace(else_open);

    uint then_ret = first_return_expr_start(then_open + 1u, then_close);
    uint else_ret = first_return_expr_start(else_open + 1u, else_close);
    emit_cond(cursor, cond_open + 1u, cond_close, write, lane);
    put_byte(cursor, 0x04u, write, lane);
    put_byte(cursor, 0x7eu, write, lane);
    emit_expr(cursor, then_ret, statement_end(then_ret, then_close), write, lane);
    put_byte(cursor, 0x05u, write, lane);
    emit_expr(cursor, else_ret, statement_end(else_ret, else_close), write, lane);
    put_byte(cursor, 0x0bu, write, lane);
    put_byte(cursor, 0x0fu, write, lane);
}

uint if_statement_end(uint if_i, uint limit_i)
{
    uint cond_open = find_next_kind(if_i + 1u, limit_i, TK_GROUP_LPAREN);
    if (cond_open == INVALID)
        cond_open = find_next_kind(if_i + 1u, limit_i, TK_LPAREN);
    uint cond_close = matching_paren(cond_open);
    uint then_open = find_next_kind(cond_close + 1u, limit_i, TK_LBRACE);
    if (then_open == INVALID)
        then_open = find_next_kind(cond_close + 1u, limit_i, TK_IF_LBRACE);
    uint then_close = matching_brace(then_open);
    uint else_open = find_next_kind(then_close + 1u, limit_i, TK_LBRACE);
    if (else_open == INVALID)
        else_open = find_next_kind(then_close + 1u, limit_i, TK_IF_LBRACE);
    if (else_open == INVALID)
        return then_close;
    return matching_brace(else_open);
}

void emit_type_section_payload(inout uint cursor, bool write, uint lane)
{
    emit_u32_leb(cursor, 4u, write, lane);
    put_byte(cursor, 0x60u, write, lane);
    emit_u32_leb(cursor, 1u, write, lane);
    put_byte(cursor, 0x7eu, write, lane);
    emit_u32_leb(cursor, 0u, write, lane);
    put_byte(cursor, 0x60u, write, lane);
    emit_u32_leb(cursor, 0u, write, lane);
    emit_u32_leb(cursor, 1u, write, lane);
    put_byte(cursor, 0x7fu, write, lane);
    put_byte(cursor, 0x60u, write, lane);
    emit_u32_leb(cursor, 1u, write, lane);
    put_byte(cursor, 0x7eu, write, lane);
    emit_u32_leb(cursor, 1u, write, lane);
    put_byte(cursor, 0x7eu, write, lane);
    put_byte(cursor, 0x60u, write, lane);
    emit_u32_leb(cursor, 2u, write, lane);
    put_byte(cursor, 0x7eu, write, lane);
    put_byte(cursor, 0x7eu, write, lane);
    emit_u32_leb(cursor, 1u, write, lane);
    put_byte(cursor, 0x7eu, write, lane);
}

void emit_import_section_payload(inout uint cursor, bool write, uint lane)
{
    emit_u32_leb(cursor, 1u, write, lane);
    emit_u32_leb(cursor, 3u, write, lane);
    put_byte(cursor, 101u, write, lane);
    put_byte(cursor, 110u, write, lane);
    put_byte(cursor, 118u, write, lane);
    emit_u32_leb(cursor, 9u, write, lane);
    put_byte(cursor, 112u, write, lane);
    put_byte(cursor, 114u, write, lane);
    put_byte(cursor, 105u, write, lane);
    put_byte(cursor, 110u, write, lane);
    put_byte(cursor, 116u, write, lane);
    put_byte(cursor, 95u, write, lane);
    put_byte(cursor, 105u, write, lane);
    put_byte(cursor, 54u, write, lane);
    put_byte(cursor, 52u, write, lane);
    put_byte(cursor, 0x00u, write, lane);
    emit_u32_leb(cursor, 0u, write, lane);
}

void emit_function_section_payload(inout uint cursor, bool write, uint lane)
{
    uint count = function_count();
    emit_u32_leb(cursor, count, write, lane);
    [loop]
    for (uint order = 0u; order < count && order < 16u; order += 1u)
    {
        uint fn_i = function_by_order(order);
        if (fn_i == main_function())
            emit_u32_leb(cursor, 1u, write, lane);
        else
        {
            uint params = function_param_count(fn_i);
            emit_u32_leb(cursor, params == 2u ? 3u : 2u, write, lane);
        }
    }
}

void emit_export_section_payload(inout uint cursor, bool write, uint lane)
{
    uint main_i = main_function();
    emit_u32_leb(cursor, 1u, write, lane);
    emit_u32_leb(cursor, 4u, write, lane);
    put_byte(cursor, 109u, write, lane);
    put_byte(cursor, 97u, write, lane);
    put_byte(cursor, 105u, write, lane);
    put_byte(cursor, 110u, write, lane);
    put_byte(cursor, 0x00u, write, lane);
    emit_u32_leb(cursor, 1u + function_order(main_i), write, lane);
}

void emit_function_body(inout uint cursor, uint fn_i, bool write, uint lane)
{
    bool is_main = fn_i == main_function();
    uint params = function_param_count(fn_i);
    emit_u32_leb(cursor, 1u, write, lane);
    emit_u32_leb5(cursor, active_token_count() + 1u, write, lane);
    put_byte(cursor, 0x7eu, write, lane);

    [loop]
    for (uint p = 0u; p < 2u; p += 1u)
    {
        if (p >= params)
            break;
        uint param_tok = function_param_token(fn_i, p);
        if (param_tok != INVALID)
        {
            emit_local_get(cursor, p, write, lane);
            emit_local_set(cursor, param_tok, write, lane);
        }
    }

    uint open_i = function_body_open(fn_i);
    uint close_i = function_body_close(fn_i);
    [loop]
    for (uint i = open_i + 1u; i < close_i && i < active_token_count(); i += 1u)
    {
        if (token_kind(i) == TK_IF && !is_main)
        {
            emit_if_return(cursor, i, write, lane);
            i = if_statement_end(i, close_i);
        }
        else if (token_kind(i) == TK_RETURN && !is_main)
        {
            uint semi = statement_end(i, close_i);
            emit_expr(cursor, i + 1u, semi, write, lane);
            put_byte(cursor, 0x0fu, write, lane);
            i = semi;
        }
        else if (i + 1u < close_i && token_kind(i) == TK_IDENT && is_assert_name(i) &&
                 (token_kind(i + 1u) == TK_CALL_LPAREN || token_kind(i + 1u) == TK_LPAREN))
        {
            uint call_close = matching_paren(i + 1u);
            emit_assert_statement(cursor, i, write, lane);
            i = call_close;
        }
        else if (is_main && i + 1u < close_i && token_kind(i) == TK_IDENT && is_print_name(i) &&
                 (token_kind(i + 1u) == TK_CALL_LPAREN || token_kind(i + 1u) == TK_LPAREN))
        {
            uint call_close = matching_paren(i + 1u);
            emit_expr(cursor, i + 2u, call_close, write, lane);
            put_byte(cursor, 0x10u, write, lane);
            emit_u32_leb(cursor, 0u, write, lane);
            i = call_close;
        }
    }

    if (is_main)
    {
        put_byte(cursor, 0x41u, write, lane);
        emit_u32_leb(cursor, 0u, write, lane);
    }
    else
    {
        emit_i64_const_u32(cursor, 0u, write, lane);
    }
    put_byte(cursor, 0x0bu, write, lane);
}

void emit_code_section_payload(inout uint cursor, bool write, uint lane)
{
    uint count = function_count();
    emit_u32_leb(cursor, count, write, lane);
    [loop]
    for (uint order = 0u; order < count && order < 16u; order += 1u)
    {
        uint len_pos = cursor;
        emit_u32_leb5(cursor, 0u, write, lane);
        uint body_start = cursor;
        emit_function_body(cursor, function_by_order(order), write, lane);
        patch_u32_leb5(len_pos, cursor - body_start, write, lane);
    }
}

void emit_section(inout uint cursor, uint section_id, bool write, uint lane)
{
    put_byte(cursor, section_id, write, lane);
    uint len_pos = cursor;
    emit_u32_leb5(cursor, 0u, write, lane);
    uint start = cursor;
    if (section_id == 1u) emit_type_section_payload(cursor, write, lane);
    else if (section_id == 2u) emit_import_section_payload(cursor, write, lane);
    else if (section_id == 3u) emit_function_section_payload(cursor, write, lane);
    else if (section_id == 7u) emit_export_section_payload(cursor, write, lane);
    else if (section_id == 10u) emit_code_section_payload(cursor, write, lane);
    patch_u32_leb5(len_pos, cursor - start, write, lane);
}

uint emit_module(bool write, uint lane)
{
    uint cursor = 0u;
    put_byte(cursor, 0x00u, write, lane);
    put_byte(cursor, 0x61u, write, lane);
    put_byte(cursor, 0x73u, write, lane);
    put_byte(cursor, 0x6du, write, lane);
    put_byte(cursor, 0x01u, write, lane);
    put_byte(cursor, 0x00u, write, lane);
    put_byte(cursor, 0x00u, write, lane);
    put_byte(cursor, 0x00u, write, lane);
    emit_section(cursor, 1u, write, lane);
    emit_section(cursor, 2u, write, lane);
    emit_section(cursor, 3u, write, lane);
    emit_section(cursor, 7u, write, lane);
    emit_section(cursor, 10u, write, lane);
    return cursor;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (body_status[1u] == 2u)
        return;
    if ((status[1u] & 4u) == 0u)
        return;
    uint target = linear_dispatch_id(tid);
    if (target >= gParams.out_capacity)
        return;

    uint len = emit_module(true, target);
    if (target == 0u)
    {
        status[0u] = len;
        status[1u] = len <= gParams.out_capacity && main_function() != INVALID ? 5u : 0u;
    }
}
