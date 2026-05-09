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
StructuredBuffer<uint> bool_probe_status;
RWStructuredBuffer<uint> body_dispatch_args;
RWStructuredBuffer<uint> bool_body_slots;
RWStructuredBuffer<uint> bool_stmt_len;

static const uint BOOL_BODY_BYTES_PER_TOKEN = 96u;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_PLUS = 6u;
static const uint TK_STAR = 7u;
static const uint TK_ASSIGN = 8u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LE = 14u;
static const uint TK_GE = 15u;
static const uint TK_EQEQ = 16u;
static const uint TK_ANDAND = 17u;
static const uint TK_OROR = 18u;
static const uint TK_NOT = 19u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_MINUS = 27u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_NOT_EQUAL = 40u;
static const uint TK_PREFIX_MINUS = 60u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_FN = 67u;
static const uint TK_LET = 68u;
static const uint TK_IF = 70u;
static const uint TK_ELSE = 71u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_LET_ASSIGN = 81u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_IF_RBRACE = 89u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_CONST = 92u;

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

uint statement_end(uint start_i)
{
    uint n = active_token_count();
    uint depth = 0u;
    [loop]
    for (uint i = start_i; i < n; i += 1u)
    {
        uint kind = token_kind(i);
        if (is_open_paren(kind))
            depth += 1u;
        else if (is_close_paren(kind) && depth > 0u)
            depth -= 1u;
        else if (kind == TK_SEMICOLON && depth == 0u)
            return i;
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

void put_byte(inout uint cursor, uint value, bool write, uint lane)
{
    uint slot_capacity = gParams.out_capacity;
    if (write && cursor < slot_capacity)
        bool_body_slots[cursor] = value & 0xffu;
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
    uint semi = statement_end(decl_i);
    uint assign_i = find_next_kind(decl_i + 1u, semi, TK_ASSIGN);
    if (assign_i == 0xffffffffu || assign_i + 1u >= semi)
        return 0xffffffffu;

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

void emit_i64_atom_range(inout uint cursor, uint start_i, uint end_i, bool write, uint lane)
{
    [loop]
    for (uint i = start_i; i < end_i && i < active_token_count(); i += 1u)
    {
        uint kind = token_kind(i);
        if (kind == TK_INT)
        {
            emit_i64_const_u32(cursor, parse_uint_token(i), write, lane);
            return;
        }
        if (kind == TK_TRUE || kind == TK_FALSE)
        {
            emit_i64_const_u32(cursor, kind == TK_TRUE ? 1u : 0u, write, lane);
            return;
        }
        if (kind == TK_IDENT || kind == TK_LET_IDENT)
        {
            uint decl = visible_decl[i];
            if (decl != 0xffffffffu)
            {
                if (is_const_decl_at(decl))
                    emit_const_decl_value(cursor, decl, write, lane);
                else
                    emit_local_get(cursor, decl, write, lane);
                return;
            }
        }
    }
    emit_i64_const_u32(cursor, 0u, write, lane);
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

uint unwrap_start(uint start_i, uint end_i)
{
    if (start_i + 1u < end_i && is_open_paren(token_kind(start_i)))
    {
        uint close_i = matching_paren(start_i);
        if (close_i + 1u == end_i)
            return start_i + 1u;
    }
    return start_i;
}

uint unwrap_end(uint start_i, uint end_i)
{
    if (start_i + 1u < end_i && is_open_paren(token_kind(start_i)))
    {
        uint close_i = matching_paren(start_i);
        if (close_i + 1u == end_i)
            return close_i;
    }
    return end_i;
}

uint find_top_level_logic(uint start_i, uint end_i, uint wanted)
{
    uint depth = 0u;
    [loop]
    for (uint i = start_i; i < end_i && i < active_token_count(); i += 1u)
    {
        uint kind = token_kind(i);
        if (is_open_paren(kind))
            depth += 1u;
        else if (is_close_paren(kind) && depth > 0u)
            depth -= 1u;
        else if (kind == wanted && depth == 0u)
            return i;
    }
    return 0xffffffffu;
}

void emit_simple_bool_expr(inout uint cursor, uint start_i, uint end_i, bool write, uint lane)
{
    bool negate = false;
    if (start_i < end_i && token_kind(start_i) == TK_NOT)
    {
        negate = true;
        start_i += 1u;
    }
    uint s = unwrap_start(start_i, end_i);
    uint e = unwrap_end(start_i, end_i);
    uint op_i = 0xffffffffu;
    [loop]
    for (uint i = s; i < e && i < active_token_count(); i += 1u)
    {
        if (is_compare_op(token_kind(i)))
        {
            op_i = i;
            break;
        }
    }
    if (op_i != 0xffffffffu)
    {
        emit_i64_atom_range(cursor, s, op_i, write, lane);
        emit_i64_atom_range(cursor, op_i + 1u, e, write, lane);
        emit_compare_op(cursor, token_kind(op_i), write, lane);
    }
    else
    {
        emit_i64_atom_range(cursor, s, e, write, lane);
        emit_i64_const_u32(cursor, 0u, write, lane);
        put_byte(cursor, 0x52u, write, lane);
    }
    if (negate)
        put_byte(cursor, 0x45u, write, lane);
}

void emit_bool_expr(inout uint cursor, uint start_i, uint end_i, bool write, uint lane)
{
    uint s = unwrap_start(start_i, end_i);
    uint e = unwrap_end(start_i, end_i);
    uint or_i = find_top_level_logic(s, e, TK_OROR);
    if (or_i != 0xffffffffu)
    {
        emit_simple_bool_expr(cursor, s, or_i, write, lane);
        emit_simple_bool_expr(cursor, or_i + 1u, e, write, lane);
        put_byte(cursor, 0x72u, write, lane);
        return;
    }
    uint and_i = find_top_level_logic(s, e, TK_ANDAND);
    if (and_i != 0xffffffffu)
    {
        emit_simple_bool_expr(cursor, s, and_i, write, lane);
        emit_simple_bool_expr(cursor, and_i + 1u, e, write, lane);
        put_byte(cursor, 0x71u, write, lane);
        return;
    }
    emit_simple_bool_expr(cursor, s, e, write, lane);
}

void emit_print_value(inout uint cursor, uint start_i, uint end_i, bool write, uint lane)
{
    emit_i64_atom_range(cursor, start_i, end_i, write, lane);
    put_byte(cursor, 0x10u, write, lane);
    emit_u32_leb(cursor, 0u, write, lane);
}

void emit_bool_let(inout uint cursor, uint let_i, uint semi, bool write, uint lane)
{
    uint assign_i = find_assign(let_i, semi);
    if (assign_i == 0xffffffffu)
        return;
    emit_bool_expr(cursor, assign_i + 1u, semi, write, lane);
    put_byte(cursor, 0xacu, write, lane);
    emit_local_set(cursor, let_i + 1u, write, lane);
}

void emit_if_body(inout uint cursor, uint start_i, uint end_i, bool write, uint lane)
{
    uint n = min(end_i, active_token_count());
    [loop]
    for (uint i = start_i; i < n; i += 1u)
    {
        if (i + 1u < n && token_kind(i) == TK_IDENT && is_print_name(i) &&
            (token_kind(i + 1u) == TK_CALL_LPAREN || token_kind(i + 1u) == TK_LPAREN))
        {
            uint close_i = matching_paren(i + 1u);
            emit_print_value(cursor, i + 2u, close_i, write, lane);
            i = close_i;
        }
    }
}

uint emit_if_statement(inout uint cursor, uint if_i, bool write, uint lane)
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

    emit_bool_expr(cursor, cond_open + 1u, cond_close, write, lane);
    put_byte(cursor, 0x04u, write, lane);
    put_byte(cursor, 0x40u, write, lane);
    emit_if_body(cursor, then_open + 1u, then_close, write, lane);
    if (else_open != 0xffffffffu && else_close != 0xffffffffu)
    {
        put_byte(cursor, 0x05u, write, lane);
        emit_if_body(cursor, else_open + 1u, else_close, write, lane);
    }
    put_byte(cursor, 0x0bu, write, lane);
    return else_close != 0xffffffffu ? else_close : then_close;
}

bool has_bool_program_shape()
{
    uint n = active_token_count();
    [loop]
    for (uint i = 0u; i < n; i += 1u)
    {
        uint kind = token_kind(i);
        if (kind == TK_ANDAND || kind == TK_OROR || kind == TK_NOT)
            return true;
    }
    return false;
}

void emit_body_header(inout uint cursor, bool write, uint lane)
{
    emit_u32_leb(cursor, 1u, write, lane);
    emit_u32_leb5(cursor, active_token_count() + 1u, write, lane);
    put_byte(cursor, 0x7eu, write, lane);
}

void emit_body_footer(inout uint cursor, bool write, uint lane)
{
    put_byte(cursor, 0x41u, write, lane);
    emit_u32_leb(cursor, 0u, write, lane);
    put_byte(cursor, 0x0bu, write, lane);
}

bool is_top_level_token(uint token_i)
{
    uint depth = 0u;
    uint root_depth = token_kind(0u) == TK_FN ? 1u : 0u;
    uint n = min(token_i, active_token_count());
    [loop]
    for (uint i = 0u; i < n; i += 1u)
    {
        uint kind = token_kind(i);
        if (is_open_brace(kind))
            depth += 1u;
        else if (is_close_brace(kind) && depth > 0u)
            depth -= 1u;
    }
    return depth == root_depth;
}

bool is_top_level_statement(uint i)
{
    uint kind = token_kind(i);
    return kind == TK_LET || kind == TK_IF;
}

uint emit_statement(inout uint cursor, uint i, bool write, uint lane)
{
    uint n = active_token_count();
    if (token_kind(i) == TK_LET)
    {
        uint semi = statement_end(i);
        emit_bool_let(cursor, i, semi, write, lane);
        return semi;
    }
    if (token_kind(i) == TK_IF)
        return emit_if_statement(cursor, i, write, lane);
    if (i + 1u < n && token_kind(i) == TK_IDENT && is_print_name(i) &&
        (token_kind(i + 1u) == TK_CALL_LPAREN || token_kind(i + 1u) == TK_LPAREN))
    {
        uint close_i = matching_paren(i + 1u);
        emit_print_value(cursor, i + 2u, close_i, write, lane);
        return close_i;
    }
    return i;
}

uint top_level_statement_bytes_before(uint end_i)
{
    uint cursor = 0u;
    uint n = min(end_i, active_token_count());
    [loop]
    for (uint i = 0u; i < n; i += 1u)
    {
        if (is_top_level_statement(i))
        {
            uint next_i = emit_statement(cursor, i, false, 0u);
            i = next_i;
        }
    }
    return cursor;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (tid.x < active_token_count())
        bool_stmt_len[tid.x] = 0u;
    if (body_status[1u] == 2u)
        return;
    if (bool_probe_status[1u] == 0u)
        return;

    if (tid.x == 0u)
    {
        body_dispatch_args[0u] = 0u;
        body_dispatch_args[1u] = 0u;
        body_dispatch_args[2u] = 0u;
    }

    if (tid.x < active_token_count())
    {
        if (is_top_level_statement(tid.x))
        {
            uint start = tid.x * BOOL_BODY_BYTES_PER_TOKEN;
            uint cursor = start;
            emit_statement(cursor, tid.x, true, tid.x);
            bool_stmt_len[tid.x] = min(cursor - start, BOOL_BODY_BYTES_PER_TOKEN);
        }
    }
}
