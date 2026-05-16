import utils;

// Bounded HIR-driven WASM array helper body emitter.
//
// This pass consumes GPU-produced HIR spans, resolver call metadata, and the
// array literal table built by wasm_arrays. It lowers the selected fixed array
// helper shape whose helper body returns one constant index from an array
// parameter, for example `return values[3];`, plus the bounded conditional
// helper shape that returns an indexed element or a scalar fallback argument,
// and a bounded scan helper shape that returns a boolean scalar from a fixed
// array comparison.

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
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> array_len;
StructuredBuffer<uint> array_values;

RWStructuredBuffer<uint> body_words;
RWStructuredBuffer<uint> body_status;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

static const uint HIR_FN = 3u;
static const uint HIR_PARAM = 4u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_ASSIGN = 8u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_EQEQ = 16u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_MINUS = 27u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_INDEX_LBRACKET = 30u;
static const uint TK_COMMA = 36u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_PLUS_ASSIGN = 46u;
static const uint TK_INFIX_MINUS = 61u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_LET = 68u;
static const uint TK_RETURN = 69u;
static const uint TK_IF = 70u;
static const uint TK_ELSE = 71u;
static const uint TK_WHILE = 72u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_LET_ASSIGN = 81u;
static const uint TK_ARG_COMMA = 82u;
static const uint TK_PARAM_COMMA = 84u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_IF_RBRACE = 89u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;

static const uint MAX_ARRAY_ELEMS = 16u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint active_token_count()
{
    return min(token_count[0u], gParams.n_tokens);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
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

bool token_text_eq4(uint i, uint a, uint b, uint c, uint d)
{
    uint start = token_start(i);
    return token_len(i) == 4u && source_at(start, 0u) == a && source_at(start, 1u) == b &&
           source_at(start, 2u) == c && source_at(start, 3u) == d;
}

bool token_text_same(uint left, uint right)
{
    uint len = token_len(left);
    if (len != token_len(right) || len > 64u)
        return false;
    uint left_start = token_start(left);
    uint right_start = token_start(right);
    [loop]
    for (uint i = 0u; i < 64u; i += 1u)
    {
        if (i >= len)
            break;
        if (source_at(left_start, i) != source_at(right_start, i))
            return false;
    }
    return true;
}

bool is_identifier_token(uint kind)
{
    return kind == TK_IDENT || kind == TK_LET_IDENT || kind == TK_PARAM_IDENT;
}

bool is_open_paren(uint kind)
{
    return kind == TK_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_CALL_LPAREN;
}

bool is_close_paren(uint kind)
{
    return kind == TK_RPAREN || kind == TK_GROUP_RPAREN || kind == TK_CALL_RPAREN;
}

bool is_index_open(uint kind)
{
    return kind == TK_LBRACKET || kind == TK_INDEX_LBRACKET;
}

bool is_index_close(uint kind)
{
    return kind == TK_RBRACKET || kind == TK_INDEX_RBRACKET;
}

bool is_comma(uint kind)
{
    return kind == TK_COMMA || kind == TK_ARG_COMMA || kind == TK_PARAM_COMMA;
}

bool is_open_brace(uint kind)
{
    return kind == TK_LBRACE || kind == TK_IF_LBRACE;
}

bool is_close_brace(uint kind)
{
    return kind == TK_RBRACE || kind == TK_IF_RBRACE;
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

void put_body(uint pos, uint value, bool write, uint target)
{
    if (write && pos < gParams.out_capacity && pos == target)
        body_words[pos] = value & 0xffu;
}

void put_byte(inout uint cursor, uint value, bool write, uint target)
{
    put_body(cursor, value, write, target);
    cursor += 1u;
}

void put_u32_leb(inout uint cursor, uint value, bool write, uint target)
{
    [loop]
    for (uint guard = 0u; guard < 5u; guard += 1u)
    {
        uint byte_value = value & 0x7fu;
        value = value >> 7u;
        if (value != 0u)
            byte_value |= 0x80u;
        put_byte(cursor, byte_value, write, target);
        if (value == 0u)
            break;
    }
}

void put_u32_leb5(inout uint cursor, uint value, bool write, uint target)
{
    [unroll]
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = (value >> (i * 7u)) & 0x7fu;
        if (i < 4u)
            byte_value |= 0x80u;
        put_byte(cursor, byte_value, write, target);
    }
}

void emit_i32_const_u32(inout uint cursor, uint value, bool write, uint target)
{
    put_byte(cursor, 0x41u, write, target);
    put_u32_leb5(cursor, value, write, target);
}

bool emit_local_decls(inout uint cursor, uint local_count, bool write, uint target)
{
    if (local_count == 0u)
    {
        put_u32_leb(cursor, 0u, write, target);
        return true;
    }
    put_u32_leb(cursor, 1u, write, target);
    put_u32_leb(cursor, local_count, write, target);
    put_byte(cursor, 0x7fu, write, target);
    return true;
}

uint matching_paren(uint open_i, uint end_i)
{
    if (open_i == INVALID || !is_open_paren(token_kind(open_i)))
        return INVALID;
    uint depth = 0u;
    uint limit = min(end_i, active_token_count());
    [loop]
    for (uint i = open_i + 1u; i < limit; i += 1u)
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
    return INVALID;
}

uint matching_brace(uint open_i, uint end_i)
{
    if (open_i == INVALID || !is_open_brace(token_kind(open_i)))
        return INVALID;
    uint depth = 0u;
    uint limit = min(end_i, active_token_count());
    [loop]
    for (uint i = open_i + 1u; i < limit; i += 1u)
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
    return INVALID;
}

uint find_next_open_paren(uint start_i, uint end_i)
{
    uint limit = min(end_i, active_token_count());
    [loop]
    for (uint i = start_i; i < limit; i += 1u)
    {
        if (is_open_paren(token_kind(i)))
            return i;
    }
    return INVALID;
}

uint find_next_open_brace(uint start_i, uint end_i)
{
    uint limit = min(end_i, active_token_count());
    [loop]
    for (uint i = start_i; i < limit; i += 1u)
    {
        if (is_open_brace(token_kind(i)))
            return i;
    }
    return INVALID;
}

uint normalized_call_open(uint marker_i, uint end_i)
{
    if (marker_i < active_token_count() && is_open_paren(token_kind(marker_i)))
        return marker_i;
    return find_next_open_paren(marker_i, end_i);
}

uint find_main_fn_node()
{
    uint found = INVALID;
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        if (hir_kind[i] != HIR_FN)
            continue;
        uint fn_i = hir_token_pos[i];
        if (fn_i == INVALID || fn_i + 1u >= active_token_count() ||
            token_kind(fn_i + 1u) != TK_IDENT)
            continue;
        if (!token_text_eq4(fn_i + 1u, 109u, 97u, 105u, 110u))
            continue;
        if (found != INVALID)
            return INVALID;
        found = i;
    }
    return found;
}

uint find_fn_node_for_token(uint fn_token)
{
    if (fn_token == INVALID)
        return INVALID;
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        if (hir_kind[i] == HIR_FN && hir_token_pos[i] == fn_token)
            return i;
    }
    return INVALID;
}

uint find_fn_body_open(uint fn_node)
{
    uint fn_start = hir_token_pos[fn_node];
    uint fn_end = hir_token_end[fn_node];
    if (fn_start == INVALID || fn_end == INVALID || fn_start >= fn_end)
        return INVALID;
    [loop]
    for (uint i = fn_start; i < fn_end && i < active_token_count(); i += 1u)
    {
        if (token_kind(i) == TK_LBRACE)
            return i;
    }
    return INVALID;
}

uint first_let_before_return(uint fn_node, uint ret_node)
{
    uint fn_start = hir_token_pos[fn_node];
    uint ret_i = hir_token_pos[ret_node];
    uint found = INVALID;
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        if (hir_kind[i] != HIR_LET_STMT)
            continue;
        uint let_i = hir_token_pos[i];
        if (let_i <= fn_start || let_i >= ret_i)
            continue;
        if (found != INVALID)
            return INVALID;
        found = i;
    }
    return found;
}

uint find_return_node(uint fn_node)
{
    uint fn_start = hir_token_pos[fn_node];
    uint fn_end = hir_token_end[fn_node];
    uint found = INVALID;
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        if (hir_kind[i] != HIR_RETURN_STMT)
            continue;
        uint ret_i = hir_token_pos[i];
        if (ret_i <= fn_start || ret_i >= fn_end)
            continue;
        if (found != INVALID)
            return INVALID;
        found = i;
    }
    return found;
}

uint return_node_starting_at(uint token_i)
{
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        if (hir_kind[i] == HIR_RETURN_STMT && hir_token_pos[i] == token_i)
            return i;
    }
    return INVALID;
}

uint if_node_starting_at(uint token_i)
{
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        if (hir_kind[i] == HIR_IF_STMT && hir_token_pos[i] == token_i)
            return i;
    }
    return INVALID;
}

uint let_node_starting_at(uint token_i)
{
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        if (hir_kind[i] == HIR_LET_STMT && hir_token_pos[i] == token_i)
            return i;
    }
    return INVALID;
}

uint while_node_starting_at(uint token_i)
{
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        if (hir_kind[i] == HIR_WHILE_STMT && hir_token_pos[i] == token_i)
            return i;
    }
    return INVALID;
}

bool parse_if_layout(
    uint if_node,
    out uint cond_start,
    out uint cond_end,
    out uint then_start,
    out uint then_end,
    out uint else_start,
    out uint else_end)
{
    cond_start = INVALID;
    cond_end = INVALID;
    then_start = INVALID;
    then_end = INVALID;
    else_start = INVALID;
    else_end = INVALID;

    uint if_i = hir_token_pos[if_node];
    uint if_end = hir_token_end[if_node];
    if (if_i == INVALID || if_end == INVALID || token_kind(if_i) != TK_IF)
        return false;

    uint cond_open = find_next_open_paren(if_i + 1u, if_end);
    uint cond_close = matching_paren(cond_open, if_end);
    if (cond_open == INVALID || cond_close == INVALID || cond_open + 1u >= cond_close)
        return false;
    uint then_open = find_next_open_brace(cond_close + 1u, if_end);
    uint then_close = matching_brace(then_open, if_end);
    if (then_open == INVALID || then_close == INVALID)
        return false;
    uint else_i = then_close + 1u;
    if (else_i >= if_end || token_kind(else_i) != TK_ELSE)
        return false;
    uint else_open = find_next_open_brace(else_i + 1u, if_end);
    uint else_close = matching_brace(else_open, if_end);
    if (else_open == INVALID || else_close == INVALID)
        return false;

    cond_start = cond_open + 1u;
    cond_end = cond_close;
    then_start = then_open;
    then_end = then_close;
    else_start = else_open;
    else_end = else_close;
    return true;
}

bool parse_if_then_layout(
    uint if_node,
    out uint cond_start,
    out uint cond_end,
    out uint then_start,
    out uint then_end,
    out uint after_if)
{
    cond_start = INVALID;
    cond_end = INVALID;
    then_start = INVALID;
    then_end = INVALID;
    after_if = INVALID;

    uint if_i = hir_token_pos[if_node];
    uint if_end = hir_token_end[if_node];
    if (if_i == INVALID || if_end == INVALID || token_kind(if_i) != TK_IF)
        return false;

    uint cond_open = find_next_open_paren(if_i + 1u, if_end);
    uint cond_close = matching_paren(cond_open, if_end);
    if (cond_open == INVALID || cond_close == INVALID || cond_open + 1u >= cond_close)
        return false;
    uint then_open = find_next_open_brace(cond_close + 1u, if_end);
    uint then_close = matching_brace(then_open, if_end);
    if (then_open == INVALID || then_close == INVALID)
        return false;

    cond_start = cond_open + 1u;
    cond_end = cond_close;
    then_start = then_open;
    then_end = then_close;
    after_if = then_close + 1u;
    return true;
}

bool parse_while_layout(
    uint while_node,
    out uint cond_start,
    out uint cond_end,
    out uint loop_start,
    out uint loop_end)
{
    cond_start = INVALID;
    cond_end = INVALID;
    loop_start = INVALID;
    loop_end = INVALID;

    uint while_i = hir_token_pos[while_node];
    uint while_end = hir_token_end[while_node];
    if (while_i == INVALID || while_end == INVALID || token_kind(while_i) != TK_WHILE)
        return false;

    uint cond_open = find_next_open_paren(while_i + 1u, while_end);
    uint cond_close = matching_paren(cond_open, while_end);
    if (cond_open == INVALID || cond_close == INVALID || cond_open + 1u >= cond_close)
        return false;
    uint body_open = find_next_open_brace(cond_close + 1u, while_end);
    uint body_close = matching_brace(body_open, while_end);
    if (body_open == INVALID || body_close == INVALID)
        return false;

    cond_start = cond_open + 1u;
    cond_end = cond_close;
    loop_start = body_open;
    loop_end = body_close;
    return true;
}

bool find_single_call_in_span(
    uint start_i,
    uint end_i,
    out uint callee_i,
    out uint call_open_i,
    out uint call_close_i)
{
    callee_i = INVALID;
    call_open_i = INVALID;
    call_close_i = INVALID;
    uint found_target = INVALID;
    [loop]
    for (uint i = start_i; i < end_i && i < active_token_count(); i += 1u)
    {
        uint target_fn = call_fn_index[i];
        if (target_fn == INVALID)
            continue;
        uint open_i = normalized_call_open(i + 1u, end_i);
        uint close_i = matching_paren(open_i, end_i);
        if (open_i == INVALID || close_i == INVALID)
            return false;
        if (callee_i == INVALID)
        {
            callee_i = i;
            call_open_i = open_i;
            call_close_i = close_i;
            found_target = target_fn;
        }
        else if (open_i != call_open_i || found_target != target_fn)
            return false;
    }
    return callee_i != INVALID;
}

bool nth_call_arg_range(uint call_open_i, uint close_i, uint target_slot, out uint arg_start, out uint arg_end)
{
    arg_start = INVALID;
    arg_end = INVALID;
    if (call_open_i == INVALID || close_i == INVALID || call_open_i >= close_i)
        return false;
    uint slot = 0u;
    uint start_i = call_open_i + 1u;
    uint depth = 0u;
    [loop]
    for (uint i = start_i; i <= close_i && i < active_token_count(); i += 1u)
    {
        uint kind = i < close_i ? token_kind(i) : TK_ARG_COMMA;
        if (i < close_i && is_open_paren(kind))
            depth += 1u;
        else if (i < close_i && is_close_paren(kind) && depth > 0u)
            depth -= 1u;
        bool at_arg_end = i == close_i || (is_comma(kind) && depth == 0u);
        if (!at_arg_end)
            continue;
        if (slot == target_slot)
        {
            arg_start = start_i;
            arg_end = i;
            return start_i < i;
        }
        slot += 1u;
        start_i = i + 1u;
    }
    return false;
}

bool call_arg_uint_literal(uint call_open_i, uint close_i, uint slot, out uint value)
{
    value = 0u;
    uint arg_start = INVALID;
    uint arg_end = INVALID;
    if (!nth_call_arg_range(call_open_i, close_i, slot, arg_start, arg_end))
        return false;
    if (arg_start + 1u != arg_end || token_kind(arg_start) != TK_INT)
        return false;
    value = parse_uint_token(arg_start);
    return true;
}

bool helper_param_slot_for_expr(uint helper_node, uint expr_i, out uint slot)
{
    slot = INVALID;
    uint expr_decl_i = expr_i < active_token_count() ? visible_decl[expr_i] : INVALID;
    uint fn_start = hir_token_pos[helper_node];
    uint body_open = find_fn_body_open(helper_node);
    if (fn_start == INVALID || body_open == INVALID || expr_i == INVALID)
        return false;
    uint seen = 0u;
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        if (hir_kind[i] != HIR_PARAM)
            continue;
        uint pos = hir_token_pos[i];
        if (pos == INVALID || pos <= fn_start || pos >= body_open)
            continue;
        if (pos == expr_decl_i || token_text_same(pos, expr_i))
        {
            slot = seen;
            return true;
        }
        seen += 1u;
    }
    return false;
}

bool call_arg_is_array_local(uint call_open_i, uint call_close_i, uint slot, uint local_name_i)
{
    uint arg_start = INVALID;
    uint arg_end = INVALID;
    if (!nth_call_arg_range(call_open_i, call_close_i, slot, arg_start, arg_end))
        return false;
    if (arg_start + 1u != arg_end || !is_identifier_token(token_kind(arg_start)))
        return false;
    uint decl_i = visible_decl[arg_start];
    return decl_i == local_name_i || token_text_same(arg_start, local_name_i);
}

bool helper_return_array_index(uint helper_node, out uint param_slot, out uint index)
{
    param_slot = INVALID;
    index = INVALID;
    uint ret_node = find_return_node(helper_node);
    if (ret_node == INVALID)
        return false;
    uint ret_i = hir_token_pos[ret_node];
    uint ret_end = hir_token_end[ret_node];
    if (ret_i == INVALID || ret_end == INVALID || token_kind(ret_i) != TK_RETURN)
        return false;
    uint expr_start = ret_i + 1u;
    uint expr_end = ret_end > 0u && token_kind(ret_end - 1u) == TK_SEMICOLON ? ret_end - 1u
                                                                             : ret_end;
    if (expr_start + 4u != expr_end)
        return false;
    if (!is_identifier_token(token_kind(expr_start)) ||
        !is_index_open(token_kind(expr_start + 1u)) ||
        token_kind(expr_start + 2u) != TK_INT ||
        !is_index_close(token_kind(expr_start + 3u)))
        return false;
    if (!helper_param_slot_for_expr(helper_node, expr_start, param_slot))
        return false;
    index = parse_uint_token(expr_start + 2u);
    return true;
}

bool return_array_index_from_block(
    uint helper_node,
    uint block_open,
    uint block_close,
    out uint param_slot,
    out uint index)
{
    param_slot = INVALID;
    index = INVALID;
    if (block_open == INVALID || block_close == INVALID || block_open + 1u >= block_close)
        return false;
    uint ret_i = block_open + 1u;
    if (token_kind(ret_i) != TK_RETURN)
        return false;
    uint ret_node = return_node_starting_at(ret_i);
    if (ret_node == INVALID || hir_token_end[ret_node] != block_close)
        return false;

    uint expr_start = ret_i + 1u;
    uint expr_end = block_close > 0u && token_kind(block_close - 1u) == TK_SEMICOLON
                        ? block_close - 1u
                        : block_close;
    if (expr_start + 4u != expr_end)
        return false;
    if (!is_identifier_token(token_kind(expr_start)) ||
        !is_index_open(token_kind(expr_start + 1u)) ||
        token_kind(expr_start + 2u) != TK_INT ||
        !is_index_close(token_kind(expr_start + 3u)))
        return false;
    if (!helper_param_slot_for_expr(helper_node, expr_start, param_slot))
        return false;
    index = parse_uint_token(expr_start + 2u);
    return true;
}

bool return_param_slot_from_block(
    uint helper_node,
    uint block_open,
    uint block_close,
    out uint param_slot)
{
    param_slot = INVALID;
    if (block_open == INVALID || block_close == INVALID || block_open + 1u >= block_close)
        return false;
    uint ret_i = block_open + 1u;
    if (token_kind(ret_i) != TK_RETURN)
        return false;
    uint ret_node = return_node_starting_at(ret_i);
    if (ret_node == INVALID || hir_token_end[ret_node] != block_close)
        return false;

    uint expr_start = ret_i + 1u;
    uint expr_end = block_close > 0u && token_kind(block_close - 1u) == TK_SEMICOLON
                        ? block_close - 1u
                        : block_close;
    if (expr_start + 1u != expr_end || !is_identifier_token(token_kind(expr_start)))
        return false;
    return helper_param_slot_for_expr(helper_node, expr_start, param_slot);
}

bool parse_param_eq_literal_condition(
    uint helper_node,
    uint cond_start,
    uint cond_end,
    out uint param_slot,
    out uint value)
{
    param_slot = INVALID;
    value = 0u;
    if (cond_start + 3u != cond_end || token_kind(cond_start + 1u) != TK_EQEQ ||
        token_kind(cond_start + 2u) != TK_INT)
        return false;
    if (!is_identifier_token(token_kind(cond_start)))
        return false;
    if (!helper_param_slot_for_expr(helper_node, cond_start, param_slot))
        return false;
    value = parse_uint_token(cond_start + 2u);
    return true;
}

bool parse_local_lt_literal_condition(
    uint cond_start,
    uint cond_end,
    uint local_name_i,
    out uint limit)
{
    limit = 0u;
    if (cond_start + 3u != cond_end || token_kind(cond_start + 1u) != TK_LT ||
        token_kind(cond_start + 2u) != TK_INT)
        return false;
    if (!is_identifier_token(token_kind(cond_start)) || !token_text_same(cond_start, local_name_i))
        return false;
    limit = parse_uint_token(cond_start + 2u);
    return true;
}

bool parse_index_let_zero(uint let_node, out uint local_name_i)
{
    uint value = 0u;
    return parse_local_let_uint_literal(let_node, 0u, local_name_i, value);
}

bool parse_local_let_uint_literal(
    uint let_node,
    uint expected_value,
    out uint local_name_i,
    out uint value)
{
    local_name_i = INVALID;
    value = 0u;
    uint let_i = hir_token_pos[let_node];
    uint let_end = hir_token_end[let_node];
    if (let_i == INVALID || let_end == INVALID || let_i + 1u >= let_end ||
        token_kind(let_i) != TK_LET || !is_identifier_token(token_kind(let_i + 1u)))
        return false;
    uint assign_i = INVALID;
    [loop]
    for (uint i = let_i + 2u; i < let_end && i < active_token_count(); i += 1u)
    {
        if (token_kind(i) == TK_ASSIGN || token_kind(i) == TK_LET_ASSIGN)
        {
            assign_i = i;
            break;
        }
    }
    uint expr_end = let_end > 0u && token_kind(let_end - 1u) == TK_SEMICOLON ? let_end - 1u
                                                                              : let_end;
    if (assign_i == INVALID || assign_i + 2u != expr_end ||
        token_kind(assign_i + 1u) != TK_INT)
        return false;
    value = parse_uint_token(assign_i + 1u);
    if (value != expected_value)
        return false;
    local_name_i = let_i + 1u;
    return true;
}

bool parse_increment_by_one(uint start_i, uint end_i, uint local_name_i)
{
    if (start_i == INVALID || end_i == INVALID || start_i + 4u != end_i ||
        !is_identifier_token(token_kind(start_i)) || !token_text_same(start_i, local_name_i) ||
        token_kind(start_i + 1u) != TK_PLUS_ASSIGN || token_kind(start_i + 2u) != TK_INT ||
        parse_uint_token(start_i + 2u) != 1u || token_kind(start_i + 3u) != TK_SEMICOLON)
        return false;
    return true;
}

bool return_bool_literal_from_block(uint block_open, uint block_close, out uint value)
{
    value = 0u;
    if (block_open == INVALID || block_close == INVALID || block_open + 1u >= block_close)
        return false;
    uint ret_i = block_open + 1u;
    if (token_kind(ret_i) != TK_RETURN)
        return false;
    uint ret_node = return_node_starting_at(ret_i);
    if (ret_node == INVALID || hir_token_end[ret_node] != block_close)
        return false;
    uint expr_start = ret_i + 1u;
    uint expr_end = block_close > 0u && token_kind(block_close - 1u) == TK_SEMICOLON
                        ? block_close - 1u
                        : block_close;
    if (expr_start + 1u != expr_end ||
        (token_kind(expr_start) != TK_TRUE && token_kind(expr_start) != TK_FALSE))
        return false;
    value = token_kind(expr_start) == TK_TRUE ? 1u : 0u;
    return true;
}

bool return_bool_literal_from_node(uint ret_node, out uint value)
{
    value = 0u;
    uint ret_i = hir_token_pos[ret_node];
    uint ret_end = hir_token_end[ret_node];
    if (ret_i == INVALID || ret_end == INVALID || token_kind(ret_i) != TK_RETURN)
        return false;
    uint expr_start = ret_i + 1u;
    uint expr_end = ret_end > 0u && token_kind(ret_end - 1u) == TK_SEMICOLON ? ret_end - 1u
                                                                             : ret_end;
    if (expr_start + 1u != expr_end ||
        (token_kind(expr_start) != TK_TRUE && token_kind(expr_start) != TK_FALSE))
        return false;
    value = token_kind(expr_start) == TK_TRUE ? 1u : 0u;
    return true;
}

bool return_local_from_block(uint block_open, uint block_close, uint local_name_i)
{
    if (block_open == INVALID || block_close == INVALID || block_open + 1u >= block_close)
        return false;
    uint ret_i = block_open + 1u;
    if (token_kind(ret_i) != TK_RETURN)
        return false;
    uint ret_node = return_node_starting_at(ret_i);
    if (ret_node == INVALID || hir_token_end[ret_node] != block_close)
        return false;
    uint expr_start = ret_i + 1u;
    uint expr_end = block_close > 0u && token_kind(block_close - 1u) == TK_SEMICOLON
                        ? block_close - 1u
                        : block_close;
    return expr_start + 1u == expr_end &&
           is_identifier_token(token_kind(expr_start)) &&
           (visible_decl[expr_start] == local_name_i || token_text_same(expr_start, local_name_i));
}

bool return_local_from_node(uint ret_node, uint local_name_i)
{
    uint ret_i = hir_token_pos[ret_node];
    uint ret_end = hir_token_end[ret_node];
    if (ret_i == INVALID || ret_end == INVALID || token_kind(ret_i) != TK_RETURN)
        return false;
    uint expr_start = ret_i + 1u;
    uint expr_end = ret_end > 0u && token_kind(ret_end - 1u) == TK_SEMICOLON ? ret_end - 1u
                                                                             : ret_end;
    return expr_start + 1u == expr_end &&
           is_identifier_token(token_kind(expr_start)) &&
           (visible_decl[expr_start] == local_name_i || token_text_same(expr_start, local_name_i));
}

bool return_param_slot_from_node(uint helper_node, uint ret_node, out uint param_slot)
{
    param_slot = INVALID;
    uint ret_i = hir_token_pos[ret_node];
    uint ret_end = hir_token_end[ret_node];
    if (ret_i == INVALID || ret_end == INVALID || token_kind(ret_i) != TK_RETURN)
        return false;
    uint expr_start = ret_i + 1u;
    uint expr_end = ret_end > 0u && token_kind(ret_end - 1u) == TK_SEMICOLON ? ret_end - 1u
                                                                             : ret_end;
    if (expr_start + 1u != expr_end || !is_identifier_token(token_kind(expr_start)))
        return false;
    return helper_param_slot_for_expr(helper_node, expr_start, param_slot);
}

bool parse_array_index_expr(
    uint helper_node,
    uint expr_start,
    uint expr_end,
    uint index_local_i,
    out uint array_param_slot)
{
    array_param_slot = INVALID;
    if (expr_start + 4u != expr_end ||
        !is_identifier_token(token_kind(expr_start)) ||
        !is_index_open(token_kind(expr_start + 1u)) ||
        !is_identifier_token(token_kind(expr_start + 2u)) ||
        !token_text_same(expr_start + 2u, index_local_i) ||
        !is_index_close(token_kind(expr_start + 3u)))
        return false;
    return helper_param_slot_for_expr(helper_node, expr_start, array_param_slot);
}

bool parse_local_let_array_index(
    uint helper_node,
    uint let_node,
    out uint local_name_i,
    out uint array_param_slot,
    out uint array_index)
{
    local_name_i = INVALID;
    array_param_slot = INVALID;
    array_index = INVALID;
    uint let_i = hir_token_pos[let_node];
    uint let_end = hir_token_end[let_node];
    if (let_i == INVALID || let_end == INVALID || let_i + 1u >= let_end ||
        token_kind(let_i) != TK_LET || !is_identifier_token(token_kind(let_i + 1u)))
        return false;
    uint assign_i = INVALID;
    [loop]
    for (uint i = let_i + 2u; i < let_end && i < active_token_count(); i += 1u)
    {
        if (token_kind(i) == TK_ASSIGN || token_kind(i) == TK_LET_ASSIGN)
        {
            assign_i = i;
            break;
        }
    }
    uint expr_end = let_end > 0u && token_kind(let_end - 1u) == TK_SEMICOLON ? let_end - 1u
                                                                              : let_end;
    if (assign_i == INVALID || assign_i + 5u != expr_end ||
        !is_identifier_token(token_kind(assign_i + 1u)) ||
        !is_index_open(token_kind(assign_i + 2u)) ||
        token_kind(assign_i + 3u) != TK_INT ||
        !is_index_close(token_kind(assign_i + 4u)))
        return false;
    if (!helper_param_slot_for_expr(helper_node, assign_i + 1u, array_param_slot))
        return false;
    array_index = parse_uint_token(assign_i + 3u);
    local_name_i = let_i + 1u;
    return true;
}

bool parse_add_array_index(
    uint helper_node,
    uint start_i,
    uint end_i,
    uint accumulator_local_i,
    uint index_local_i,
    out uint array_param_slot)
{
    array_param_slot = INVALID;
    if (start_i == INVALID || end_i == INVALID || start_i + 7u != end_i ||
        !is_identifier_token(token_kind(start_i)) ||
        !token_text_same(start_i, accumulator_local_i) ||
        token_kind(start_i + 1u) != TK_PLUS_ASSIGN ||
        token_kind(start_i + 6u) != TK_SEMICOLON)
        return false;
    return parse_array_index_expr(
        helper_node,
        start_i + 2u,
        start_i + 6u,
        index_local_i,
        array_param_slot);
}

bool parse_assign_array_index(
    uint helper_node,
    uint start_i,
    uint end_i,
    uint target_local_i,
    uint index_local_i,
    out uint array_param_slot)
{
    array_param_slot = INVALID;
    if (start_i == INVALID || end_i == INVALID || start_i + 7u != end_i ||
        !is_identifier_token(token_kind(start_i)) ||
        !token_text_same(start_i, target_local_i) ||
        token_kind(start_i + 1u) != TK_ASSIGN ||
        token_kind(start_i + 6u) != TK_SEMICOLON)
        return false;
    return parse_array_index_expr(
        helper_node,
        start_i + 2u,
        start_i + 6u,
        index_local_i,
        array_param_slot);
}

bool parse_array_index_eq_param_condition(
    uint helper_node,
    uint cond_start,
    uint cond_end,
    uint index_local_i,
    out uint array_param_slot,
    out uint needle_param_slot)
{
    array_param_slot = INVALID;
    needle_param_slot = INVALID;
    if (cond_start + 6u != cond_end ||
        !is_identifier_token(token_kind(cond_start)) ||
        !is_index_open(token_kind(cond_start + 1u)) ||
        !is_identifier_token(token_kind(cond_start + 2u)) ||
        !token_text_same(cond_start + 2u, index_local_i) ||
        !is_index_close(token_kind(cond_start + 3u)) ||
        token_kind(cond_start + 4u) != TK_EQEQ ||
        !is_identifier_token(token_kind(cond_start + 5u)))
        return false;
    if (!helper_param_slot_for_expr(helper_node, cond_start, array_param_slot))
        return false;
    if (!helper_param_slot_for_expr(helper_node, cond_start + 5u, needle_param_slot))
        return false;
    return true;
}

bool parse_array_index_cmp_local_condition(
    uint helper_node,
    uint cond_start,
    uint cond_end,
    uint index_local_i,
    uint target_local_i,
    out uint array_param_slot,
    out uint compare_op)
{
    array_param_slot = INVALID;
    compare_op = 0u;
    if (cond_start + 6u != cond_end ||
        !is_identifier_token(token_kind(cond_start)) ||
        !is_index_open(token_kind(cond_start + 1u)) ||
        !is_identifier_token(token_kind(cond_start + 2u)) ||
        !token_text_same(cond_start + 2u, index_local_i) ||
        !is_index_close(token_kind(cond_start + 3u)) ||
        (token_kind(cond_start + 4u) != TK_LT && token_kind(cond_start + 4u) != TK_GT) ||
        !is_identifier_token(token_kind(cond_start + 5u)) ||
        !token_text_same(cond_start + 5u, target_local_i))
        return false;
    if (!helper_param_slot_for_expr(helper_node, cond_start, array_param_slot))
        return false;
    compare_op = token_kind(cond_start + 4u);
    return true;
}

bool helper_array_scan_position_or_value(
    uint helper_node,
    uint call_open_i,
    uint call_close_i,
    uint local_name_i,
    out uint value,
    out uint reject_stage,
    out uint reject_detail)
{
    value = 0u;
    reject_stage = 60u;
    reject_detail = hir_token_pos[helper_node];
    uint body_open = find_fn_body_open(helper_node);
    uint body_close = hir_token_end[helper_node];
    if (body_open == INVALID || body_close == INVALID || body_open + 1u >= body_close)
    {
        reject_detail = body_open;
        return false;
    }

    uint index_let_i = body_open + 1u;
    uint index_let_node = let_node_starting_at(index_let_i);
    uint index_local_i = INVALID;
    if (token_kind(index_let_i) != TK_LET || index_let_node == INVALID ||
        !parse_index_let_zero(index_let_node, index_local_i))
    {
        reject_stage = 61u;
        reject_detail = index_let_i;
        return false;
    }

    uint while_i = hir_token_end[index_let_node];
    uint while_node = while_node_starting_at(while_i);
    if (while_i == INVALID || token_kind(while_i) != TK_WHILE || while_node == INVALID)
    {
        reject_stage = 62u;
        reject_detail = while_i;
        return false;
    }

    uint cond_start = INVALID;
    uint cond_end = INVALID;
    uint loop_start = INVALID;
    uint loop_end = INVALID;
    if (!parse_while_layout(while_node, cond_start, cond_end, loop_start, loop_end))
    {
        reject_stage = 63u;
        reject_detail = while_i;
        return false;
    }
    uint scan_limit = 0u;
    if (!parse_local_lt_literal_condition(cond_start, cond_end, index_local_i, scan_limit) ||
        scan_limit == 0u || scan_limit > MAX_ARRAY_ELEMS ||
        scan_limit > array_len[local_name_i])
    {
        reject_stage = 64u;
        reject_detail = cond_start;
        return false;
    }

    uint if_i = loop_start + 1u;
    uint if_node = if_node_starting_at(if_i);
    uint if_cond_start = INVALID;
    uint if_cond_end = INVALID;
    uint then_start = INVALID;
    uint then_end = INVALID;
    uint after_if = INVALID;
    if (token_kind(if_i) != TK_IF || if_node == INVALID ||
        !parse_if_then_layout(
            if_node,
            if_cond_start,
            if_cond_end,
            then_start,
            then_end,
            after_if))
    {
        reject_stage = 65u;
        reject_detail = if_i;
        return false;
    }
    if (!return_local_from_block(then_start, then_end, index_local_i))
    {
        reject_stage = 66u;
        reject_detail = then_start;
        return false;
    }

    uint array_param_slot = INVALID;
    uint needle_param_slot = INVALID;
    if (!parse_array_index_eq_param_condition(
            helper_node,
            if_cond_start,
            if_cond_end,
            index_local_i,
            array_param_slot,
            needle_param_slot))
    {
        reject_stage = 67u;
        reject_detail = if_cond_start;
        return false;
    }
    if (!call_arg_is_array_local(call_open_i, call_close_i, array_param_slot, local_name_i))
    {
        reject_stage = 68u;
        reject_detail = call_open_i;
        return false;
    }
    uint needle_value = 0u;
    if (!call_arg_uint_literal(call_open_i, call_close_i, needle_param_slot, needle_value))
    {
        reject_stage = 69u;
        reject_detail = call_open_i;
        return false;
    }
    if (!parse_increment_by_one(after_if, loop_end, index_local_i))
    {
        reject_stage = 70u;
        reject_detail = after_if;
        return false;
    }

    uint return_i = hir_token_end[while_node];
    uint final_ret = return_node_starting_at(return_i);
    uint fallback_param_slot = INVALID;
    uint fallback_value = 0u;
    if (return_i == INVALID || token_kind(return_i) != TK_RETURN || final_ret == INVALID ||
        !return_param_slot_from_node(helper_node, final_ret, fallback_param_slot) ||
        !call_arg_uint_literal(call_open_i, call_close_i, fallback_param_slot, fallback_value) ||
        hir_token_end[final_ret] == INVALID || hir_token_end[final_ret] > body_close)
    {
        reject_stage = 71u;
        reject_detail = return_i;
        return false;
    }

    [loop]
    for (uint i = 0u; i < MAX_ARRAY_ELEMS; i += 1u)
    {
        if (i >= scan_limit)
            break;
        if (array_values[local_name_i * MAX_ARRAY_ELEMS + i] == needle_value)
        {
            value = i;
            reject_stage = 0u;
            reject_detail = INVALID;
            return true;
        }
    }
    value = fallback_value;
    reject_stage = 0u;
    reject_detail = INVALID;
    return true;
}

bool helper_array_scan_tally_value(
    uint helper_node,
    uint call_open_i,
    uint call_close_i,
    uint local_name_i,
    out uint value,
    out uint reject_stage,
    out uint reject_detail)
{
    value = 0u;
    reject_stage = 80u;
    reject_detail = hir_token_pos[helper_node];
    uint body_open = find_fn_body_open(helper_node);
    uint body_close = hir_token_end[helper_node];
    if (body_open == INVALID || body_close == INVALID || body_open + 1u >= body_close)
    {
        reject_detail = body_open;
        return false;
    }

    uint index_let_i = body_open + 1u;
    uint index_let_node = let_node_starting_at(index_let_i);
    uint index_local_i = INVALID;
    if (token_kind(index_let_i) != TK_LET || index_let_node == INVALID ||
        !parse_index_let_zero(index_let_node, index_local_i))
    {
        reject_stage = 81u;
        reject_detail = index_let_i;
        return false;
    }

    uint tally_let_i = hir_token_end[index_let_node];
    uint tally_let_node = let_node_starting_at(tally_let_i);
    uint tally_local_i = INVALID;
    if (tally_let_i == INVALID || token_kind(tally_let_i) != TK_LET ||
        tally_let_node == INVALID || !parse_index_let_zero(tally_let_node, tally_local_i))
    {
        reject_stage = 82u;
        reject_detail = tally_let_i;
        return false;
    }

    uint while_i = hir_token_end[tally_let_node];
    uint while_node = while_node_starting_at(while_i);
    if (while_i == INVALID || token_kind(while_i) != TK_WHILE || while_node == INVALID)
    {
        reject_stage = 83u;
        reject_detail = while_i;
        return false;
    }

    uint cond_start = INVALID;
    uint cond_end = INVALID;
    uint loop_start = INVALID;
    uint loop_end = INVALID;
    if (!parse_while_layout(while_node, cond_start, cond_end, loop_start, loop_end))
    {
        reject_stage = 84u;
        reject_detail = while_i;
        return false;
    }
    uint scan_limit = 0u;
    if (!parse_local_lt_literal_condition(cond_start, cond_end, index_local_i, scan_limit) ||
        scan_limit == 0u || scan_limit > MAX_ARRAY_ELEMS ||
        scan_limit > array_len[local_name_i])
    {
        reject_stage = 85u;
        reject_detail = cond_start;
        return false;
    }

    uint if_i = loop_start + 1u;
    uint if_node = if_node_starting_at(if_i);
    uint if_cond_start = INVALID;
    uint if_cond_end = INVALID;
    uint then_start = INVALID;
    uint then_end = INVALID;
    uint after_if = INVALID;
    if (token_kind(if_i) != TK_IF || if_node == INVALID ||
        !parse_if_then_layout(
            if_node,
            if_cond_start,
            if_cond_end,
            then_start,
            then_end,
            after_if))
    {
        reject_stage = 86u;
        reject_detail = if_i;
        return false;
    }
    if (!parse_increment_by_one(then_start + 1u, then_end, tally_local_i))
    {
        reject_stage = 87u;
        reject_detail = then_start;
        return false;
    }

    uint array_param_slot = INVALID;
    uint needle_param_slot = INVALID;
    if (!parse_array_index_eq_param_condition(
            helper_node,
            if_cond_start,
            if_cond_end,
            index_local_i,
            array_param_slot,
            needle_param_slot))
    {
        reject_stage = 88u;
        reject_detail = if_cond_start;
        return false;
    }
    if (!call_arg_is_array_local(call_open_i, call_close_i, array_param_slot, local_name_i))
    {
        reject_stage = 89u;
        reject_detail = call_open_i;
        return false;
    }
    uint needle_value = 0u;
    if (!call_arg_uint_literal(call_open_i, call_close_i, needle_param_slot, needle_value))
    {
        reject_stage = 90u;
        reject_detail = call_open_i;
        return false;
    }
    if (!parse_increment_by_one(after_if, loop_end, index_local_i))
    {
        reject_stage = 91u;
        reject_detail = after_if;
        return false;
    }

    uint return_i = hir_token_end[while_node];
    uint final_ret = return_node_starting_at(return_i);
    if (return_i == INVALID || token_kind(return_i) != TK_RETURN || final_ret == INVALID ||
        !return_local_from_node(final_ret, tally_local_i) ||
        hir_token_end[final_ret] == INVALID || hir_token_end[final_ret] > body_close)
    {
        reject_stage = 92u;
        reject_detail = return_i;
        return false;
    }

    uint tally = 0u;
    [loop]
    for (uint i = 0u; i < MAX_ARRAY_ELEMS; i += 1u)
    {
        if (i >= scan_limit)
            break;
        if (array_values[local_name_i * MAX_ARRAY_ELEMS + i] == needle_value)
            tally += 1u;
    }
    value = tally;
    reject_stage = 0u;
    reject_detail = INVALID;
    return true;
}

bool helper_array_scan_fold_value(
    uint helper_node,
    uint call_open_i,
    uint call_close_i,
    uint local_name_i,
    out uint value,
    out uint reject_stage,
    out uint reject_detail)
{
    value = 0u;
    reject_stage = 100u;
    reject_detail = hir_token_pos[helper_node];
    uint body_open = find_fn_body_open(helper_node);
    uint body_close = hir_token_end[helper_node];
    if (body_open == INVALID || body_close == INVALID || body_open + 1u >= body_close)
    {
        reject_detail = body_open;
        return false;
    }

    uint index_let_i = body_open + 1u;
    uint index_let_node = let_node_starting_at(index_let_i);
    uint index_local_i = INVALID;
    if (token_kind(index_let_i) != TK_LET || index_let_node == INVALID ||
        !parse_index_let_zero(index_let_node, index_local_i))
    {
        reject_stage = 101u;
        reject_detail = index_let_i;
        return false;
    }

    uint accumulator_let_i = hir_token_end[index_let_node];
    uint accumulator_let_node = let_node_starting_at(accumulator_let_i);
    uint accumulator_local_i = INVALID;
    if (accumulator_let_i == INVALID || token_kind(accumulator_let_i) != TK_LET ||
        accumulator_let_node == INVALID ||
        !parse_index_let_zero(accumulator_let_node, accumulator_local_i))
    {
        reject_stage = 102u;
        reject_detail = accumulator_let_i;
        return false;
    }

    uint while_i = hir_token_end[accumulator_let_node];
    uint while_node = while_node_starting_at(while_i);
    if (while_i == INVALID || token_kind(while_i) != TK_WHILE || while_node == INVALID)
    {
        reject_stage = 103u;
        reject_detail = while_i;
        return false;
    }

    uint cond_start = INVALID;
    uint cond_end = INVALID;
    uint loop_start = INVALID;
    uint loop_end = INVALID;
    if (!parse_while_layout(while_node, cond_start, cond_end, loop_start, loop_end))
    {
        reject_stage = 104u;
        reject_detail = while_i;
        return false;
    }
    uint scan_limit = 0u;
    if (!parse_local_lt_literal_condition(cond_start, cond_end, index_local_i, scan_limit) ||
        scan_limit == 0u || scan_limit > MAX_ARRAY_ELEMS ||
        scan_limit > array_len[local_name_i])
    {
        reject_stage = 105u;
        reject_detail = cond_start;
        return false;
    }

    uint array_param_slot = INVALID;
    uint add_start = loop_start + 1u;
    uint increment_start = add_start + 7u;
    if (!parse_add_array_index(
            helper_node,
            add_start,
            increment_start,
            accumulator_local_i,
            index_local_i,
            array_param_slot))
    {
        reject_stage = 106u;
        reject_detail = add_start;
        return false;
    }
    if (!call_arg_is_array_local(call_open_i, call_close_i, array_param_slot, local_name_i))
    {
        reject_stage = 107u;
        reject_detail = call_open_i;
        return false;
    }
    if (!parse_increment_by_one(increment_start, loop_end, index_local_i))
    {
        reject_stage = 108u;
        reject_detail = increment_start;
        return false;
    }

    uint return_i = hir_token_end[while_node];
    uint final_ret = return_node_starting_at(return_i);
    if (return_i == INVALID || token_kind(return_i) != TK_RETURN || final_ret == INVALID ||
        !return_local_from_node(final_ret, accumulator_local_i) ||
        hir_token_end[final_ret] == INVALID || hir_token_end[final_ret] > body_close)
    {
        reject_stage = 109u;
        reject_detail = return_i;
        return false;
    }

    uint folded = 0u;
    [loop]
    for (uint i = 0u; i < MAX_ARRAY_ELEMS; i += 1u)
    {
        if (i >= scan_limit)
            break;
        folded += array_values[local_name_i * MAX_ARRAY_ELEMS + i];
    }
    value = folded;
    reject_stage = 0u;
    reject_detail = INVALID;
    return true;
}

bool helper_array_scan_extreme_value(
    uint helper_node,
    uint call_open_i,
    uint call_close_i,
    uint local_name_i,
    out uint value,
    out uint reject_stage,
    out uint reject_detail)
{
    value = 0u;
    reject_stage = 120u;
    reject_detail = hir_token_pos[helper_node];
    uint body_open = find_fn_body_open(helper_node);
    uint body_close = hir_token_end[helper_node];
    if (body_open == INVALID || body_close == INVALID || body_open + 1u >= body_close)
    {
        reject_detail = body_open;
        return false;
    }

    uint index_let_i = body_open + 1u;
    uint index_let_node = let_node_starting_at(index_let_i);
    uint index_local_i = INVALID;
    uint index_start_value = 0u;
    if (token_kind(index_let_i) != TK_LET || index_let_node == INVALID ||
        !parse_local_let_uint_literal(index_let_node, 1u, index_local_i, index_start_value))
    {
        reject_stage = 121u;
        reject_detail = index_let_i;
        return false;
    }

    uint accumulator_let_i = hir_token_end[index_let_node];
    uint accumulator_let_node = let_node_starting_at(accumulator_let_i);
    uint accumulator_local_i = INVALID;
    uint init_array_param_slot = INVALID;
    uint init_array_index = INVALID;
    if (accumulator_let_i == INVALID || token_kind(accumulator_let_i) != TK_LET ||
        accumulator_let_node == INVALID ||
        !parse_local_let_array_index(
            helper_node,
            accumulator_let_node,
            accumulator_local_i,
            init_array_param_slot,
            init_array_index))
    {
        reject_stage = 122u;
        reject_detail = accumulator_let_i;
        return false;
    }
    if (init_array_index >= MAX_ARRAY_ELEMS || init_array_index >= array_len[local_name_i] ||
        !call_arg_is_array_local(call_open_i, call_close_i, init_array_param_slot, local_name_i))
    {
        reject_stage = 123u;
        reject_detail = init_array_index;
        return false;
    }

    uint while_i = hir_token_end[accumulator_let_node];
    uint while_node = while_node_starting_at(while_i);
    if (while_i == INVALID || token_kind(while_i) != TK_WHILE || while_node == INVALID)
    {
        reject_stage = 124u;
        reject_detail = while_i;
        return false;
    }

    uint cond_start = INVALID;
    uint cond_end = INVALID;
    uint loop_start = INVALID;
    uint loop_end = INVALID;
    if (!parse_while_layout(while_node, cond_start, cond_end, loop_start, loop_end))
    {
        reject_stage = 125u;
        reject_detail = while_i;
        return false;
    }
    uint scan_limit = 0u;
    if (!parse_local_lt_literal_condition(cond_start, cond_end, index_local_i, scan_limit) ||
        scan_limit == 0u || scan_limit > MAX_ARRAY_ELEMS ||
        scan_limit > array_len[local_name_i])
    {
        reject_stage = 126u;
        reject_detail = cond_start;
        return false;
    }

    uint if_i = loop_start + 1u;
    uint if_node = if_node_starting_at(if_i);
    uint if_cond_start = INVALID;
    uint if_cond_end = INVALID;
    uint then_start = INVALID;
    uint then_end = INVALID;
    uint after_if = INVALID;
    if (token_kind(if_i) != TK_IF || if_node == INVALID ||
        !parse_if_then_layout(
            if_node,
            if_cond_start,
            if_cond_end,
            then_start,
            then_end,
            after_if))
    {
        reject_stage = 127u;
        reject_detail = if_i;
        return false;
    }

    uint cond_array_param_slot = INVALID;
    uint compare_op = 0u;
    if (!parse_array_index_cmp_local_condition(
            helper_node,
            if_cond_start,
            if_cond_end,
            index_local_i,
            accumulator_local_i,
            cond_array_param_slot,
            compare_op))
    {
        reject_stage = 128u;
        reject_detail = if_cond_start;
        return false;
    }
    if (!call_arg_is_array_local(call_open_i, call_close_i, cond_array_param_slot, local_name_i))
    {
        reject_stage = 129u;
        reject_detail = call_open_i;
        return false;
    }

    uint assign_array_param_slot = INVALID;
    if (!parse_assign_array_index(
            helper_node,
            then_start + 1u,
            then_end,
            accumulator_local_i,
            index_local_i,
            assign_array_param_slot))
    {
        reject_stage = 130u;
        reject_detail = then_start;
        return false;
    }
    if (!call_arg_is_array_local(call_open_i, call_close_i, assign_array_param_slot, local_name_i))
    {
        reject_stage = 131u;
        reject_detail = call_open_i;
        return false;
    }
    if (!parse_increment_by_one(after_if, loop_end, index_local_i))
    {
        reject_stage = 132u;
        reject_detail = after_if;
        return false;
    }

    uint return_i = hir_token_end[while_node];
    uint final_ret = return_node_starting_at(return_i);
    if (return_i == INVALID || token_kind(return_i) != TK_RETURN || final_ret == INVALID ||
        !return_local_from_node(final_ret, accumulator_local_i) ||
        hir_token_end[final_ret] == INVALID || hir_token_end[final_ret] > body_close)
    {
        reject_stage = 133u;
        reject_detail = return_i;
        return false;
    }

    uint extreme = array_values[local_name_i * MAX_ARRAY_ELEMS + init_array_index];
    [loop]
    for (uint i = 0u; i < MAX_ARRAY_ELEMS; i += 1u)
    {
        if (i < index_start_value)
            continue;
        if (i >= scan_limit)
            break;
        uint candidate = array_values[local_name_i * MAX_ARRAY_ELEMS + i];
        if ((compare_op == TK_LT && candidate < extreme) ||
            (compare_op == TK_GT && candidate > extreme))
            extreme = candidate;
    }
    value = extreme;
    reject_stage = 0u;
    reject_detail = INVALID;
    return true;
}

bool helper_array_scan_bool_value(
    uint helper_node,
    uint call_open_i,
    uint call_close_i,
    uint local_name_i,
    out uint value,
    out uint reject_stage,
    out uint reject_detail)
{
    value = 0u;
    reject_stage = 40u;
    reject_detail = hir_token_pos[helper_node];
    uint body_open = find_fn_body_open(helper_node);
    uint body_close = hir_token_end[helper_node];
    if (body_open == INVALID || body_close == INVALID || body_open + 1u >= body_close)
    {
        reject_stage = 40u;
        reject_detail = body_open;
        return false;
    }

    uint index_let_i = body_open + 1u;
    if (token_kind(index_let_i) != TK_LET)
    {
        reject_stage = 41u;
        reject_detail = index_let_i;
        return false;
    }
    uint index_let_node = let_node_starting_at(index_let_i);
    uint index_local_i = INVALID;
    if (index_let_node == INVALID || !parse_index_let_zero(index_let_node, index_local_i))
    {
        reject_stage = 42u;
        reject_detail = index_let_i;
        return false;
    }

    uint while_i = hir_token_end[index_let_node];
    if (while_i == INVALID || token_kind(while_i) != TK_WHILE)
    {
        reject_stage = 43u;
        reject_detail = while_i;
        return false;
    }
    uint while_node = while_node_starting_at(while_i);
    if (while_node == INVALID)
    {
        reject_stage = 44u;
        reject_detail = while_i;
        return false;
    }

    uint cond_start = INVALID;
    uint cond_end = INVALID;
    uint loop_start = INVALID;
    uint loop_end = INVALID;
    if (!parse_while_layout(while_node, cond_start, cond_end, loop_start, loop_end))
    {
        reject_stage = 45u;
        reject_detail = while_i;
        return false;
    }

    uint scan_limit = 0u;
    if (!parse_local_lt_literal_condition(cond_start, cond_end, index_local_i, scan_limit))
    {
        reject_stage = 46u;
        reject_detail = cond_start;
        return false;
    }
    if (scan_limit == 0u || scan_limit > MAX_ARRAY_ELEMS || scan_limit > array_len[local_name_i])
    {
        reject_stage = 47u;
        reject_detail = scan_limit;
        return false;
    }

    uint if_i = loop_start + 1u;
    if (token_kind(if_i) != TK_IF)
    {
        reject_stage = 48u;
        reject_detail = if_i;
        return false;
    }
    uint if_node = if_node_starting_at(if_i);
    if (if_node == INVALID)
    {
        reject_stage = 49u;
        reject_detail = if_i;
        return false;
    }
    uint if_cond_start = INVALID;
    uint if_cond_end = INVALID;
    uint then_start = INVALID;
    uint then_end = INVALID;
    uint after_if = INVALID;
    if (!parse_if_then_layout(
            if_node,
            if_cond_start,
            if_cond_end,
            then_start,
            then_end,
            after_if))
    {
        reject_stage = 50u;
        reject_detail = if_i;
        return false;
    }

    uint found_return_value = 0u;
    if (!return_bool_literal_from_block(then_start, then_end, found_return_value) ||
        found_return_value != 1u)
    {
        reject_stage = 51u;
        reject_detail = then_start;
        return false;
    }

    uint array_param_slot = INVALID;
    uint needle_param_slot = INVALID;
    if (!parse_array_index_eq_param_condition(
            helper_node,
            if_cond_start,
            if_cond_end,
            index_local_i,
            array_param_slot,
            needle_param_slot))
    {
        reject_stage = 52u;
        reject_detail = if_cond_start;
        return false;
    }
    if (!call_arg_is_array_local(call_open_i, call_close_i, array_param_slot, local_name_i))
    {
        reject_stage = 53u;
        reject_detail = call_open_i;
        return false;
    }
    uint needle_value = 0u;
    if (!call_arg_uint_literal(call_open_i, call_close_i, needle_param_slot, needle_value))
    {
        reject_stage = 54u;
        reject_detail = call_open_i;
        return false;
    }
    if (!parse_increment_by_one(after_if, loop_end, index_local_i))
    {
        reject_stage = 55u;
        reject_detail = after_if;
        return false;
    }

    uint return_i = hir_token_end[while_node];
    if (return_i == INVALID || token_kind(return_i) != TK_RETURN)
    {
        reject_stage = 56u;
        reject_detail = return_i;
        return false;
    }
    uint final_ret = return_node_starting_at(return_i);
    uint not_found_value = 0u;
    if (final_ret == INVALID ||
        !return_bool_literal_from_node(final_ret, not_found_value) ||
        not_found_value != 0u ||
        hir_token_end[final_ret] == INVALID ||
        hir_token_end[final_ret] > body_close)
    {
        reject_stage = 57u;
        reject_detail = return_i;
        return false;
    }

    [loop]
    for (uint i = 0u; i < MAX_ARRAY_ELEMS; i += 1u)
    {
        if (i >= scan_limit)
            break;
        if (array_values[local_name_i * MAX_ARRAY_ELEMS + i] == needle_value)
        {
            value = 1u;
            return true;
        }
    }
    value = 0u;
    reject_stage = 0u;
    reject_detail = INVALID;
    return true;
}

bool helper_conditional_array_lookup_value(
    uint helper_node,
    uint call_open_i,
    uint call_close_i,
    uint local_name_i,
    out uint value)
{
    value = 0u;
    uint body_open = find_fn_body_open(helper_node);
    uint body_close = hir_token_end[helper_node];
    if (body_open == INVALID || body_close == INVALID || body_open + 1u >= body_close)
        return false;

    uint block_open = body_open;
    uint block_close = body_close;
    [loop]
    for (uint guard = 0u; guard < MAX_ARRAY_ELEMS + 1u; guard += 1u)
    {
        uint first_i = block_open + 1u;
        if (first_i >= block_close)
            return false;
        if (token_kind(first_i) == TK_RETURN)
        {
            uint fallback_slot = INVALID;
            uint fallback_value = 0u;
            if (!return_param_slot_from_block(helper_node, block_open, block_close, fallback_slot))
                return false;
            if (!call_arg_uint_literal(call_open_i, call_close_i, fallback_slot, fallback_value))
                return false;
            value = fallback_value;
            return true;
        }
        if (token_kind(first_i) != TK_IF)
            return false;
        uint if_node = if_node_starting_at(first_i);
        if (if_node == INVALID)
            return false;

        uint cond_start = INVALID;
        uint cond_end = INVALID;
        uint then_start = INVALID;
        uint then_end = INVALID;
        uint else_start = INVALID;
        uint else_end = INVALID;
        if (!parse_if_layout(
                if_node,
                cond_start,
                cond_end,
                then_start,
                then_end,
                else_start,
                else_end))
            return false;

        uint index_param_slot = INVALID;
        uint matched_index_value = 0u;
        uint call_index_value = 0u;
        if (!parse_param_eq_literal_condition(
                helper_node,
                cond_start,
                cond_end,
                index_param_slot,
                matched_index_value))
            return false;
        if (!call_arg_uint_literal(call_open_i, call_close_i, index_param_slot, call_index_value))
            return false;

        if (call_index_value == matched_index_value)
        {
            uint array_param_slot = INVALID;
            uint array_index = INVALID;
            if (!return_array_index_from_block(
                    helper_node,
                    then_start,
                    then_end,
                    array_param_slot,
                    array_index))
                return false;
            if (array_index >= MAX_ARRAY_ELEMS || array_index >= array_len[local_name_i])
                return false;
            if (!call_arg_is_array_local(
                    call_open_i,
                    call_close_i,
                    array_param_slot,
                    local_name_i))
                return false;
            value = array_values[local_name_i * MAX_ARRAY_ELEMS + array_index];
            return true;
        }

        block_open = else_start;
        block_close = else_end;
    }
    return false;
}

bool emit_return_array_helper_projection(
    inout uint cursor,
    uint ret_node,
    uint local_name_i,
    bool write,
    uint target,
    out uint reject_stage,
    out uint reject_detail)
{
    reject_stage = 0u;
    reject_detail = INVALID;
    uint ret_i = hir_token_pos[ret_node];
    uint ret_end = hir_token_end[ret_node];
    if (ret_i == INVALID || ret_end == INVALID || token_kind(ret_i) != TK_RETURN)
    {
        reject_stage = 21u;
        reject_detail = ret_i;
        return false;
    }
    uint expr_start = ret_i + 1u;
    uint expr_end = ret_end > 0u && token_kind(ret_end - 1u) == TK_SEMICOLON ? ret_end - 1u
                                                                             : ret_end;
    uint callee_i = INVALID;
    uint call_open_i = INVALID;
    uint call_close_i = INVALID;
    if (!find_single_call_in_span(expr_start, expr_end, callee_i, call_open_i, call_close_i))
    {
        reject_stage = 22u;
        reject_detail = expr_start;
        return false;
    }

    uint helper_node = find_fn_node_for_token(call_fn_index[callee_i]);
    if (helper_node == INVALID)
    {
        reject_stage = 23u;
        reject_detail = callee_i;
        return false;
    }

    uint selected_value = 0u;
    uint param_slot = INVALID;
    uint index = INVALID;
    if (helper_return_array_index(helper_node, param_slot, index))
    {
        if (index >= MAX_ARRAY_ELEMS || index >= array_len[local_name_i])
        {
            reject_stage = 25u;
            reject_detail = index;
            return false;
        }
        if (!call_arg_is_array_local(call_open_i, call_close_i, param_slot, local_name_i))
        {
            reject_stage = 26u;
            reject_detail = call_open_i;
            return false;
        }
        selected_value = array_values[local_name_i * MAX_ARRAY_ELEMS + index];
    }
    else
    {
        bool selected = helper_conditional_array_lookup_value(
            helper_node,
            call_open_i,
            call_close_i,
            local_name_i,
            selected_value);
        if (!selected)
        {
            uint scan_reject_stage = 0u;
            uint scan_reject_detail = INVALID;
            selected = helper_array_scan_bool_value(
                helper_node,
                call_open_i,
                call_close_i,
                local_name_i,
                selected_value,
                scan_reject_stage,
                scan_reject_detail);
            if (!selected && scan_reject_stage != 0u)
            {
                reject_stage = scan_reject_stage;
                reject_detail = scan_reject_detail;
            }
            if (!selected)
            {
                selected = helper_array_scan_position_or_value(
                    helper_node,
                    call_open_i,
                    call_close_i,
                    local_name_i,
                    selected_value,
                    scan_reject_stage,
                    scan_reject_detail);
                if (!selected && scan_reject_stage != 0u)
                {
                    reject_stage = scan_reject_stage;
                    reject_detail = scan_reject_detail;
                }
            }
            if (!selected)
            {
                selected = helper_array_scan_tally_value(
                    helper_node,
                    call_open_i,
                    call_close_i,
                    local_name_i,
                    selected_value,
                    scan_reject_stage,
                    scan_reject_detail);
                if (!selected && scan_reject_stage != 0u)
                {
                    reject_stage = scan_reject_stage;
                    reject_detail = scan_reject_detail;
                }
            }
            if (!selected)
            {
                selected = helper_array_scan_fold_value(
                    helper_node,
                    call_open_i,
                    call_close_i,
                    local_name_i,
                    selected_value,
                    scan_reject_stage,
                    scan_reject_detail);
                if (!selected && scan_reject_stage != 0u)
                {
                    reject_stage = scan_reject_stage;
                    reject_detail = scan_reject_detail;
                }
            }
            if (!selected)
            {
                selected = helper_array_scan_extreme_value(
                    helper_node,
                    call_open_i,
                    call_close_i,
                    local_name_i,
                    selected_value,
                    scan_reject_stage,
                    scan_reject_detail);
                if (!selected && scan_reject_stage != 0u)
                {
                    reject_stage = scan_reject_stage;
                    reject_detail = scan_reject_detail;
                }
            }
        }
        if (!selected)
        {
            if (reject_stage == 0u)
            {
                reject_stage = 24u;
                reject_detail = hir_token_pos[helper_node];
            }
            return false;
        }
    }

    emit_i32_const_u32(cursor, selected_value, write, target);

    uint op_i = call_close_i + 1u;
    if (op_i == expr_end)
        return true;
    if (op_i + 2u != expr_end ||
        (token_kind(op_i) != TK_INFIX_MINUS && token_kind(op_i) != TK_MINUS) ||
        token_kind(op_i + 1u) != TK_INT)
    {
        reject_stage = 27u;
        reject_detail = op_i;
        return false;
    }
    emit_i32_const_u32(cursor, parse_uint_token(op_i + 1u), write, target);
    put_byte(cursor, 0x6bu, write, target);
    return true;
}

void record_array_reject(uint stage, uint detail, uint target)
{
    if (target == 0u)
    {
        status[1u] = 0u;
        status[2u] = 800u + stage;
        status[3u] = detail;
    }
}

bool emit_body(out uint body_len, out uint reject_stage, out uint reject_detail, bool write, uint target)
{
    body_len = 0u;
    reject_stage = 0u;
    reject_detail = INVALID;
    uint fn_node = find_main_fn_node();
    if (fn_node == INVALID)
    {
        reject_stage = 1u;
        return false;
    }
    uint ret_node = find_return_node(fn_node);
    if (ret_node == INVALID)
    {
        reject_stage = 2u;
        reject_detail = hir_token_pos[fn_node];
        return false;
    }
    uint let_node = first_let_before_return(fn_node, ret_node);
    if (let_node == INVALID)
    {
        reject_stage = 3u;
        reject_detail = hir_token_pos[ret_node];
        return false;
    }

    uint let_i = hir_token_pos[let_node];
    uint local_name_i = let_i + 1u;
    if (token_kind(let_i) != TK_LET ||
        (token_kind(local_name_i) != TK_IDENT && token_kind(local_name_i) != TK_LET_IDENT))
    {
        reject_stage = 4u;
        reject_detail = let_i;
        return false;
    }
    if (array_len[local_name_i] == 0u || array_len[local_name_i] > MAX_ARRAY_ELEMS)
    {
        reject_stage = 5u;
        reject_detail = local_name_i;
        return false;
    }

    uint cursor = 0u;
    if (!emit_local_decls(cursor, 0u, write, target))
    {
        reject_stage = 6u;
        return false;
    }
    if (!emit_return_array_helper_projection(
            cursor,
            ret_node,
            local_name_i,
            write,
            target,
            reject_stage,
            reject_detail))
        return false;
    put_byte(cursor, 0x0bu, write, target);
    body_len = cursor;
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint target = linear_dispatch_id(tid);
    if (target >= gParams.out_capacity && target != 0u)
        return;

    uint body_len = 0u;
    uint reject_stage = 0u;
    uint reject_detail = INVALID;
    if (!emit_body(body_len, reject_stage, reject_detail, false, target))
    {
        if (reject_stage > 5u)
            record_array_reject(reject_stage, reject_detail, target);
        return;
    }
    if (body_len == 0u || body_len > gParams.out_capacity)
        return;
    if (!emit_body(body_len, reject_stage, reject_detail, true, target))
    {
        if (reject_stage > 5u)
            record_array_reject(reject_stage, reject_detail, target);
        return;
    }

    if (target == 0u)
    {
        body_status[0u] = body_len;
        body_status[1u] = 1u;
        status[1u] = 0u;
        status[2u] = 0u;
        status[3u] = INVALID;
    }
}
