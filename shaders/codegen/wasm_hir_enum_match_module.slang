import utils;

// Bounded HIR-driven WASM emitter for unit-enum tags and match dispatch.
//
// This pass consumes parser-owned HIR enum/match arrays plus existing GPU
// resolver outputs. It does not recognize stdlib names or variant spellings.

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
StructuredBuffer<uint> hir_variant_ordinal;
StructuredBuffer<uint4> hir_enum_match_record;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_param_count;

RWStructuredBuffer<uint> out_words;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

static const uint HIR_FN = 3u;
static const uint HIR_PARAM = 4u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_MATCH_EXPR = 34u;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_ASSIGN = 8u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LE = 14u;
static const uint TK_GE = 15u;
static const uint TK_EQEQ = 16u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_COMMA = 36u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_NOT_EQUAL = 40u;
static const uint TK_LET = 68u;
static const uint TK_RETURN = 69u;
static const uint TK_IF = 70u;
static const uint TK_ELSE = 71u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_LET_ASSIGN = 81u;
static const uint TK_ARG_COMMA = 82u;
static const uint TK_PARAM_COMMA = 84u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_MATCH = 95u;

static const uint MAX_PARAM_COUNT = 8u;
static const uint MAX_MATCH_ARMS = 8u;
static const uint HIR_MODULE_OUTPUT_TARGET_LIMIT = 512u;
static const uint ERR_ENUM_MODULE_BASE = 900u;

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

bool is_comma(uint kind)
{
    return kind == TK_COMMA || kind == TK_ARG_COMMA || kind == TK_PARAM_COMMA;
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

void put_byte(inout uint cursor, uint byte_value, bool write, uint target)
{
    if (write && cursor < gParams.out_capacity && cursor == target)
        out_words[target] = byte_value & 0xffu;
    cursor += 1u;
}

void put_u32_leb(inout uint cursor, uint value, bool write, uint target)
{
    uint v = value;
    [loop]
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = v & 0x7fu;
        v >>= 7u;
        if (v != 0u)
            byte_value |= 0x80u;
        put_byte(cursor, byte_value, write, target);
        if (v == 0u)
            break;
    }
}

void put_u32_leb5(inout uint cursor, uint value, bool write, uint target)
{
    uint v = value;
    [unroll]
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = v & 0x7fu;
        v >>= 7u;
        if (i < 4u)
            byte_value |= 0x80u;
        put_byte(cursor, byte_value, write, target);
    }
}

uint leb5_byte(uint value, uint i)
{
    uint shifted = value >> (7u * i);
    uint byte_value = shifted & 0x7fu;
    if (i < 4u)
        byte_value |= 0x80u;
    return byte_value;
}

void write_u32_leb5_at(uint pos, uint value, bool write, uint target)
{
    [unroll]
    for (uint i = 0u; i < 5u; i += 1u)
    {
        if (write && pos + i < gParams.out_capacity && target == pos + i)
            out_words[target] = leb5_byte(value, i);
    }
}

void emit_i32_const_u32(inout uint cursor, uint value, bool write, uint target)
{
    put_byte(cursor, 0x41u, write, target);
    put_u32_leb(cursor, value, write, target);
}

void emit_local_get(inout uint cursor, uint local_i, bool write, uint target)
{
    put_byte(cursor, 0x20u, write, target);
    put_u32_leb(cursor, local_i, write, target);
}

void emit_local_set(inout uint cursor, uint local_i, bool write, uint target)
{
    put_byte(cursor, 0x21u, write, target);
    put_u32_leb(cursor, local_i, write, target);
}

bool emit_compare_op(inout uint cursor, uint op, bool write, uint target)
{
    if (op == TK_EQEQ)
        put_byte(cursor, 0x46u, write, target);
    else if (op == TK_NOT_EQUAL)
        put_byte(cursor, 0x47u, write, target);
    else if (op == TK_LT)
        put_byte(cursor, 0x48u, write, target);
    else if (op == TK_GT)
        put_byte(cursor, 0x4au, write, target);
    else if (op == TK_LE)
        put_byte(cursor, 0x4cu, write, target);
    else if (op == TK_GE)
        put_byte(cursor, 0x4eu, write, target);
    else
        return false;
    return true;
}

uint matching_delim(uint open_i, uint end_i, uint open_kind, uint close_kind)
{
    if (open_i == INVALID || open_i >= end_i || token_kind(open_i) != open_kind)
        return INVALID;
    uint depth = 0u;
    [loop]
    for (uint i = open_i; i < end_i && i < active_token_count(); i += 1u)
    {
        uint kind = token_kind(i);
        if (kind == open_kind)
            depth += 1u;
        else if (kind == close_kind)
        {
            if (depth == 0u)
                return INVALID;
            depth -= 1u;
            if (depth == 0u)
                return i;
        }
    }
    return INVALID;
}

uint matching_paren(uint open_i, uint end_i)
{
    uint kind = token_kind(open_i);
    uint close_kind = TK_RPAREN;
    if (kind == TK_CALL_LPAREN)
        close_kind = TK_CALL_RPAREN;
    else if (kind == TK_GROUP_LPAREN)
        close_kind = TK_GROUP_RPAREN;
    return matching_delim(open_i, end_i, kind, close_kind);
}

uint matching_brace(uint open_i, uint end_i)
{
    return matching_delim(open_i, end_i, TK_LBRACE, TK_RBRACE);
}

uint find_next_open_paren(uint start_i, uint end_i)
{
    [loop]
    for (uint i = start_i; i < end_i && i < active_token_count(); i += 1u)
    {
        if (is_open_paren(token_kind(i)))
            return i;
    }
    return INVALID;
}

uint find_next_open_brace(uint start_i, uint end_i)
{
    [loop]
    for (uint i = start_i; i < end_i && i < active_token_count(); i += 1u)
    {
        if (token_kind(i) == TK_LBRACE)
            return i;
    }
    return INVALID;
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
    return INVALID;
}

uint hir_node_starting_at(uint token_i, uint target_kind)
{
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        if (hir_kind[i] == target_kind && hir_token_pos[i] == token_i)
            return i;
    }
    return INVALID;
}

uint find_fn_body_open(uint fn_node)
{
    uint start_i = hir_token_pos[fn_node];
    uint end_i = hir_token_end[fn_node];
    if (start_i == INVALID || end_i == INVALID)
        return INVALID;
    return find_next_open_brace(start_i, end_i);
}

bool function_has_match(uint fn_node)
{
    uint start_i = hir_token_pos[fn_node];
    uint end_i = hir_token_end[fn_node];
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        if (hir_kind[i] == HIR_MATCH_EXPR && hir_token_pos[i] > start_i &&
            hir_token_pos[i] < end_i)
            return true;
    }
    return false;
}

uint scrutinee_token_for_match_node(uint match_node)
{
    if (match_node == INVALID || match_node >= active_hir_node_count())
        return INVALID;
    uint scrutinee_node = hir_enum_match_record[match_node].x;
    if (scrutinee_node == INVALID || scrutinee_node >= active_hir_node_count())
        return INVALID;
    uint start_i = hir_token_pos[scrutinee_node];
    uint end_i = hir_token_end[scrutinee_node];
    if (start_i == INVALID || end_i == INVALID || start_i >= end_i)
        return INVALID;
    return start_i;
}

uint pattern_name_end_from_metadata(uint pattern_node, uint arm_node)
{
    if (pattern_node == INVALID || pattern_node >= active_hir_node_count())
        return INVALID;
    uint4 arm_record = hir_enum_match_record[arm_node];
    uint payload_count = arm_record.z;
    if (payload_count == 0u)
        return hir_token_end[pattern_node];
    uint payload_node = arm_record.y;
    if (payload_node == INVALID || payload_node >= active_hir_node_count())
        return INVALID;
    return hir_token_pos[payload_node];
}

uint find_main_match_fn_node()
{
    uint found = INVALID;
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        if (hir_kind[i] != HIR_FN)
            continue;
        uint fn_i = hir_token_pos[i];
        if (fn_i != INVALID && call_param_count[fn_i] == 0u && function_has_match(i))
        {
            if (found != INVALID)
                return INVALID;
            found = i;
        }
    }
    return found;
}

uint find_fn_node_for_token(uint fn_token)
{
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        if (hir_kind[i] == HIR_FN && hir_token_pos[i] == fn_token)
            return i;
    }
    return INVALID;
}

uint find_called_helper_fn_node(uint main_node, out uint helper_count)
{
    uint found = INVALID;
    uint found_fn_token = INVALID;
    helper_count = 0u;
    uint main_fn_token = hir_token_pos[main_node];
    uint main_end = hir_token_end[main_node];
    [loop]
    for (uint i = main_fn_token + 1u; i < main_end && i < active_token_count(); i += 1u)
    {
        uint target_fn = call_fn_index[i];
        if (target_fn == INVALID || target_fn == main_fn_token)
            continue;
        uint node = find_fn_node_for_token(target_fn);
        if (node == INVALID)
            return INVALID;
        if (found_fn_token == INVALID)
        {
            found_fn_token = target_fn;
            found = node;
            helper_count = 1u;
        }
        else if (target_fn != found_fn_token)
        {
            helper_count = 2u;
            return found;
        }
    }
    return found;
}

bool find_tag_match_main_and_helper(out uint main_node, out uint helper_node, out uint helper_count)
{
    main_node = INVALID;
    helper_node = INVALID;
    helper_count = 0u;
    uint candidates = 0u;
    uint last_rejected_helper_count = 0u;
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        if (hir_kind[i] != HIR_FN)
            continue;
        uint fn_i = hir_token_pos[i];
        if (fn_i == INVALID || call_param_count[fn_i] != 0u || function_has_match(i))
            continue;
        uint body_open = find_fn_body_open(i);
        uint body_close = matching_brace(body_open, hir_token_end[i]);
        if (body_open == INVALID || body_close == INVALID)
            continue;
        uint let_i = body_open + 1u;
        if (token_kind(let_i) != TK_LET)
            continue;
        uint let_node = hir_node_starting_at(let_i, HIR_LET_STMT);
        if (let_node == INVALID || hir_token_end[let_node] == INVALID)
            continue;
        uint ret_i = hir_token_end[let_node];
        if (ret_i >= body_close || token_kind(ret_i) != TK_RETURN)
            continue;
        uint return_node = hir_node_starting_at(ret_i, HIR_RETURN_STMT);
        if (return_node == INVALID || hir_token_end[return_node] != body_close)
            continue;
        uint expr_start = ret_i + 1u;
        uint expr_end = body_close;
        if (expr_end > 0u && token_kind(expr_end - 1u) == TK_SEMICOLON)
            expr_end -= 1u;
        if (expr_start >= expr_end || !is_identifier_token(token_kind(expr_start)))
            continue;
        uint target_fn = call_fn_index[expr_start];
        if (target_fn == INVALID || target_fn == fn_i)
            continue;
        uint candidate_helper = find_fn_node_for_token(target_fn);
        if (candidate_helper == INVALID || !function_has_match(candidate_helper))
        {
            last_rejected_helper_count = 1u;
            continue;
        }
        if (candidate_helper != INVALID)
        {
            main_node = i;
            helper_node = candidate_helper;
            helper_count = 1u;
            candidates += 1u;
        }
    }
    if (candidates != 1u)
    {
        main_node = INVALID;
        helper_node = INVALID;
        helper_count = candidates == 0u ? last_rejected_helper_count : candidates;
        return false;
    }
    return true;
}

bool enum_variant_tag_for_decl(uint variant_token, out uint tag)
{
    tag = INVALID;
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        if (hir_variant_ordinal[i] != INVALID && hir_token_pos[i] == variant_token)
        {
            tag = hir_variant_ordinal[i];
            return true;
        }
    }
    return false;
}

uint last_identifier_token(uint start_i, uint end_i)
{
    uint found = INVALID;
    [loop]
    for (uint i = start_i; i < end_i && i < active_token_count(); i += 1u)
    {
        if (is_identifier_token(token_kind(i)))
            found = i;
    }
    return found;
}

bool enum_variant_tag_for_name_token(uint name_token, out uint tag)
{
    tag = INVALID;
    if (name_token >= active_token_count())
        return false;
    uint name_id = name_id_by_token[name_token];
    if (name_id == INVALID)
        return false;

    uint matches = 0u;
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        if (hir_variant_ordinal[i] == INVALID)
            continue;
        uint variant_token = hir_token_pos[i];
        if (variant_token < active_token_count() && name_id_by_token[variant_token] == name_id)
        {
            tag = hir_variant_ordinal[i];
            matches += 1u;
        }
    }
    return matches == 1u;
}

bool enum_variant_tag_for_path_span(uint start_i, uint end_i, out uint tag)
{
    tag = INVALID;
    uint leaf = last_identifier_token(start_i, end_i);
    return leaf != INVALID && enum_variant_tag_for_name_token(leaf, tag);
}

bool enum_variant_tag_for_expr(uint token_i, out uint tag)
{
    tag = INVALID;
    if (token_i >= active_token_count() || !is_identifier_token(token_kind(token_i)))
        return false;
    uint decl = visible_decl[token_i];
    if (decl != INVALID && decl < active_token_count() && enum_variant_tag_for_decl(decl, tag))
        return true;
    return enum_variant_tag_for_name_token(token_i, tag);
}

uint param_index_for_token(uint token_i, uint fn_node)
{
    uint decl_i = token_i < active_token_count() ? visible_decl[token_i] : INVALID;
    uint fn_start = hir_token_pos[fn_node];
    uint body_open = find_fn_body_open(fn_node);
    uint param_count = 0u;
    uint count = active_hir_node_count();
    [loop]
    for (uint i = 0u; i < count; i += 1u)
    {
        uint pos = hir_token_pos[i];
        if (hir_kind[i] != HIR_PARAM || pos == INVALID || pos <= fn_start || pos >= body_open)
            continue;
        if (token_i == pos || decl_i == pos)
            return param_count;
        param_count += 1u;
    }
    return INVALID;
}

bool emit_value_atom(
    inout uint cursor,
    uint start_i,
    uint end_i,
    uint fn_node,
    bool main_local_allowed,
    bool write,
    uint target)
{
    if (start_i + 1u != end_i)
        return false;
    uint kind = token_kind(start_i);
    if (kind == TK_INT)
    {
        emit_i32_const_u32(cursor, parse_uint_token(start_i), write, target);
        return true;
    }
    if (kind == TK_TRUE || kind == TK_FALSE)
    {
        emit_i32_const_u32(cursor, kind == TK_TRUE ? 1u : 0u, write, target);
        return true;
    }
    if (!is_identifier_token(kind))
        return false;
    if (main_local_allowed)
    {
        emit_local_get(cursor, 0u, write, target);
        return true;
    }
    uint param_i = param_index_for_token(start_i, fn_node);
    if (param_i == INVALID)
        return false;
    emit_local_get(cursor, param_i, write, target);
    return true;
}

bool emit_compare_expr(
    inout uint cursor,
    uint start_i,
    uint end_i,
    uint fn_node,
    bool write,
    uint target)
{
    uint op_i = INVALID;
    [loop]
    for (uint i = start_i; i < end_i && i < active_token_count(); i += 1u)
    {
        uint kind = token_kind(i);
        if (kind == TK_LT || kind == TK_GT || kind == TK_LE || kind == TK_GE ||
            kind == TK_EQEQ || kind == TK_NOT_EQUAL)
        {
            op_i = i;
            break;
        }
    }
    if (op_i == INVALID || op_i == start_i || op_i + 1u >= end_i)
        return false;
    if (!emit_value_atom(cursor, start_i, op_i, fn_node, false, write, target))
        return false;
    if (!emit_value_atom(cursor, op_i + 1u, end_i, fn_node, false, write, target))
        return false;
    return emit_compare_op(cursor, token_kind(op_i), write, target);
}

bool parse_if_layout(
    uint if_i,
    uint if_end,
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
    if (if_i == INVALID || if_end == INVALID || token_kind(if_i) != TK_IF)
        return false;
    uint cond_open = find_next_open_paren(if_i + 1u, if_end);
    uint cond_close = matching_paren(cond_open, if_end);
    uint then_open = find_next_open_brace(cond_close + 1u, if_end);
    uint then_close = matching_brace(then_open, if_end);
    if (cond_open == INVALID || cond_close == INVALID || then_open == INVALID ||
        then_close == INVALID)
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

bool emit_return_variant_from_block(
    inout uint cursor,
    uint block_open,
    uint block_close,
    bool write,
    uint target)
{
    if (block_open == INVALID || block_close == INVALID || block_open + 1u >= block_close)
        return false;
    uint ret_i = block_open + 1u;
    if (token_kind(ret_i) != TK_RETURN)
        return false;
    uint ret_node = hir_node_starting_at(ret_i, HIR_RETURN_STMT);
    if (ret_node == INVALID || hir_token_end[ret_node] != block_close)
        return false;
    uint expr_start = ret_i + 1u;
    uint expr_end = block_close;
    if (expr_end > 0u && token_kind(expr_end - 1u) == TK_SEMICOLON)
        expr_end -= 1u;
    uint tag;
    if (expr_start >= expr_end || !enum_variant_tag_for_path_span(expr_start, expr_end, tag))
        return false;
    emit_i32_const_u32(cursor, tag, write, target);
    return true;
}

bool result_bool_literal_token(uint result_node, out uint literal_i, out uint value)
{
    literal_i = INVALID;
    value = INVALID;
    if (result_node == INVALID)
        return false;
    uint result_start = hir_token_pos[result_node];
    uint result_end = hir_token_end[result_node];
    if (result_start == INVALID || result_end == INVALID || result_start >= result_end)
        return false;
    uint kind = token_kind(result_start);
    if (kind != TK_TRUE && kind != TK_FALSE)
        return false;
    if (result_start + 1u != result_end &&
        !(result_start + 2u == result_end && is_comma(token_kind(result_start + 1u))))
        return false;
    literal_i = result_start;
    value = kind == TK_TRUE ? 1u : 0u;
    return true;
}

bool emit_tag_match_expr(
    inout uint cursor,
    uint match_i,
    uint match_end,
    uint helper_node,
    out uint fail_stage,
    out uint fail_detail,
    bool write,
    uint target)
{
    fail_stage = 500u;
    fail_detail = match_i;
    uint match_node = hir_node_starting_at(match_i, HIR_MATCH_EXPR);
    fail_stage = 501u;
    if (token_kind(match_i) != TK_MATCH || match_node == INVALID)
        return false;
    fail_stage = 502u;
    uint scrutinee_i = scrutinee_token_for_match_node(match_node);
    fail_detail = scrutinee_i;
    if (scrutinee_i == INVALID || !is_identifier_token(token_kind(scrutinee_i)) ||
        param_index_for_token(scrutinee_i, helper_node) != 0u)
        return false;

    uint arm_count = count_match_arms_from_metadata(match_node);
    fail_stage = 504u;
    fail_detail = arm_count;
    if (arm_count == 0u || arm_count > MAX_MATCH_ARMS)
        return false;

    uint after_token = match_i;
    uint emitted = 0u;
    [loop]
    for (uint guard = 0u; guard < MAX_MATCH_ARMS; guard += 1u)
    {
        if (emitted >= arm_count)
            break;
        uint arm_node = next_match_arm_from_metadata(match_node, after_token);
        fail_stage = 510u;
        fail_detail = after_token;
        if (arm_node == INVALID)
            return false;

        uint4 arm_record = hir_enum_match_record[arm_node];
        uint pattern_node = arm_record.x;
        uint result_node = arm_record.w;
        uint pattern_i = hir_token_pos[pattern_node];
        uint result_i = INVALID;
        uint result_value = INVALID;
        fail_stage = 511u;
        fail_detail = hir_token_pos[result_node];
        if (!result_bool_literal_token(result_node, result_i, result_value))
            return false;
        uint tag;
        fail_stage = 512u;
        fail_detail = pattern_i;
        uint pattern_name_end = pattern_name_end_from_metadata(pattern_node, arm_node);
        if (pattern_name_end == INVALID)
            return false;
        if (!enum_variant_tag_for_path_span(pattern_i, pattern_name_end, tag))
            return false;

        bool last = emitted + 1u == arm_count;
        if (!last)
        {
            emit_local_get(cursor, 0u, write, target);
            emit_i32_const_u32(cursor, tag, write, target);
            put_byte(cursor, 0x46u, write, target);
            put_byte(cursor, 0x04u, write, target);
            put_byte(cursor, 0x7fu, write, target);
        }
        emit_i32_const_u32(cursor, result_value, write, target);
        if (!last)
            put_byte(cursor, 0x05u, write, target);
        emitted += 1u;
        after_token = hir_token_pos[arm_node];
    }

    fail_stage = 513u;
    fail_detail = emitted;
    [loop]
    for (uint i = 1u; i < MAX_MATCH_ARMS; i += 1u)
    {
        if (i >= arm_count)
            break;
        put_byte(cursor, 0x0bu, write, target);
    }
    fail_stage = 0u;
    fail_detail = INVALID;
    return emitted == arm_count;
}

bool emit_tag_match_helper_body(
    inout uint cursor,
    uint helper_node,
    out uint body_len,
    out uint param_count,
    out uint fail_stage,
    out uint fail_detail,
    bool write,
    uint target)
{
    body_len = 0u;
    fail_stage = 520u;
    fail_detail = hir_token_pos[helper_node];
    param_count = min(call_param_count[hir_token_pos[helper_node]], MAX_PARAM_COUNT);
    if (param_count != 1u)
        return false;

    uint body_open = find_fn_body_open(helper_node);
    uint body_close = matching_brace(body_open, hir_token_end[helper_node]);
    if (body_open == INVALID || body_close == INVALID || body_open + 1u >= body_close)
        return false;

    uint ret_i = body_open + 1u;
    uint ret_node = hir_node_starting_at(ret_i, HIR_RETURN_STMT);
    fail_stage = 521u;
    fail_detail = ret_i;
    if (token_kind(ret_i) != TK_RETURN || ret_node == INVALID || hir_token_end[ret_node] != body_close)
        return false;

    uint expr_start = ret_i + 1u;
    uint expr_end = body_close;
    if (expr_end > 0u && token_kind(expr_end - 1u) == TK_SEMICOLON)
        expr_end -= 1u;

    uint body_start = cursor;
    put_u32_leb(cursor, 0u, write, target);
    uint match_fail_stage = 0u;
    uint match_fail_detail = INVALID;
    if (!emit_tag_match_expr(
            cursor,
            expr_start,
            expr_end,
            helper_node,
            match_fail_stage,
            match_fail_detail,
            write,
            target))
    {
        fail_stage = match_fail_stage;
        fail_detail = match_fail_detail;
        return false;
    }
    put_byte(cursor, 0x0bu, write, target);
    body_len = cursor - body_start;
    fail_stage = 0u;
    fail_detail = INVALID;
    return true;
}

bool emit_if_function_body(
    inout uint cursor,
    uint fn_node,
    out uint body_len,
    out uint param_count,
    bool write,
    uint target)
{
    body_len = 0u;
    param_count = min(call_param_count[hir_token_pos[fn_node]], MAX_PARAM_COUNT);
    uint body_open = find_fn_body_open(fn_node);
    uint body_close = matching_brace(body_open, hir_token_end[fn_node]);
    if (body_open == INVALID || body_close == INVALID || body_open + 1u >= body_close)
        return false;

    uint if_i = body_open + 1u;
    uint if_node = hir_node_starting_at(if_i, HIR_IF_STMT);
    if (if_node == INVALID || hir_token_end[if_node] != body_close)
        return false;

    uint cond_start;
    uint cond_end;
    uint then_start;
    uint then_end;
    uint else_start;
    uint else_end;
    if (!parse_if_layout(
            if_i,
            body_close,
            cond_start,
            cond_end,
            then_start,
            then_end,
            else_start,
            else_end))
        return false;

    uint body_start = cursor;
    put_u32_leb(cursor, 0u, write, target);
    if (!emit_compare_expr(cursor, cond_start, cond_end, fn_node, write, target))
        return false;
    put_byte(cursor, 0x04u, write, target);
    put_byte(cursor, 0x7fu, write, target);
    if (!emit_return_variant_from_block(cursor, then_start, then_end, write, target))
        return false;
    put_byte(cursor, 0x05u, write, target);

    uint else_first = else_start + 1u;
    if (token_kind(else_first) == TK_RETURN)
    {
        if (!emit_return_variant_from_block(cursor, else_start, else_end, write, target))
            return false;
    }
    else if (token_kind(else_first) == TK_IF)
    {
        uint nested_node = hir_node_starting_at(else_first, HIR_IF_STMT);
        if (nested_node == INVALID || hir_token_end[nested_node] != else_end)
            return false;
        uint nested_cond_start;
        uint nested_cond_end;
        uint nested_then_start;
        uint nested_then_end;
        uint nested_else_start;
        uint nested_else_end;
        if (!parse_if_layout(
                else_first,
                else_end,
                nested_cond_start,
                nested_cond_end,
                nested_then_start,
                nested_then_end,
                nested_else_start,
                nested_else_end))
            return false;
        if (!emit_compare_expr(cursor, nested_cond_start, nested_cond_end, fn_node, write, target))
            return false;
        put_byte(cursor, 0x04u, write, target);
        put_byte(cursor, 0x7fu, write, target);
        if (!emit_return_variant_from_block(cursor, nested_then_start, nested_then_end, write, target))
            return false;
        put_byte(cursor, 0x05u, write, target);
        if (!emit_return_variant_from_block(cursor, nested_else_start, nested_else_end, write, target))
            return false;
        put_byte(cursor, 0x0bu, write, target);
    }
    else
        return false;

    put_byte(cursor, 0x0bu, write, target);
    put_byte(cursor, 0x0bu, write, target);
    body_len = cursor - body_start;
    return true;
}

bool emit_call_args_and_call(
    inout uint cursor,
    uint callee_i,
    uint call_open_i,
    uint close_i,
    uint helper_fn_token,
    bool write,
    uint target)
{
    if (call_fn_index[callee_i] != helper_fn_token)
        return false;
    uint expected_arg_count = min(call_param_count[helper_fn_token], MAX_PARAM_COUNT);
    uint arg_start = call_open_i + 1u;
    uint arg_count = 0u;
    uint depth = 0u;
    [loop]
    for (uint i = arg_start; i <= close_i && i < active_token_count(); i += 1u)
    {
        uint kind = i < close_i ? token_kind(i) : TK_ARG_COMMA;
        if (i < close_i && is_open_paren(kind))
            depth += 1u;
        else if (i < close_i && is_close_paren(kind) && depth > 0u)
            depth -= 1u;
        bool at_arg_end = i == close_i || (is_comma(kind) && depth == 0u);
        if (!at_arg_end)
            continue;
        if (arg_start >= i || arg_count >= MAX_PARAM_COUNT)
            return false;
        if (!emit_value_atom(cursor, arg_start, i, INVALID, false, write, target))
            return false;
        arg_count += 1u;
        arg_start = i + 1u;
    }
    if (arg_count != expected_arg_count)
        return false;
    put_byte(cursor, 0x10u, write, target);
    put_u32_leb(cursor, 1u, write, target);
    return true;
}

bool find_main_let_and_return(uint fn_node, out uint let_node, out uint return_node)
{
    let_node = INVALID;
    return_node = INVALID;
    uint body_open = find_fn_body_open(fn_node);
    uint body_close = matching_brace(body_open, hir_token_end[fn_node]);
    if (body_open == INVALID || body_close == INVALID)
        return false;
    uint let_i = body_open + 1u;
    if (token_kind(let_i) != TK_LET)
        return false;
    let_node = hir_node_starting_at(let_i, HIR_LET_STMT);
    if (let_node == INVALID || hir_token_end[let_node] == INVALID)
        return false;
    uint ret_i = hir_token_end[let_node];
    if (ret_i >= body_close || token_kind(ret_i) != TK_RETURN)
        return false;
    return_node = hir_node_starting_at(ret_i, HIR_RETURN_STMT);
    return return_node != INVALID && hir_token_end[return_node] == body_close;
}

bool emit_main_let_call(
    inout uint cursor,
    uint let_node,
    uint helper_fn_token,
    bool write,
    uint target)
{
    uint let_i = hir_token_pos[let_node];
    uint let_end = hir_token_end[let_node];
    uint assign_i = find_assign(let_i, let_end);
    if (assign_i == INVALID || assign_i + 1u >= let_end)
        return false;
    uint callee_i = assign_i + 1u;
    if (!is_identifier_token(token_kind(callee_i)))
        return false;
    uint call_open = find_next_open_paren(callee_i + 1u, let_end);
    uint call_close = matching_paren(call_open, let_end);
    if (call_open == INVALID || call_close == INVALID)
        return false;
    if (!emit_call_args_and_call(cursor, callee_i, call_open, call_close, helper_fn_token, write, target))
        return false;
    emit_local_set(cursor, 0u, write, target);
    return true;
}

bool emit_main_let_constructor_tag(
    inout uint cursor,
    uint let_node,
    bool write,
    uint target)
{
    uint let_i = hir_token_pos[let_node];
    uint let_end = hir_token_end[let_node];
    uint assign_i = find_assign(let_i, let_end);
    if (assign_i == INVALID || assign_i + 1u >= let_end)
        return false;
    uint callee_i = assign_i + 1u;
    if (!is_identifier_token(token_kind(callee_i)))
        return false;
    uint tag;
    uint call_open = find_next_open_paren(callee_i + 1u, let_end);
    uint name_end = call_open == INVALID ? let_end : call_open;
    if (!enum_variant_tag_for_path_span(callee_i, name_end, tag))
        return false;
    emit_i32_const_u32(cursor, tag, write, target);
    emit_local_set(cursor, 0u, write, target);
    return true;
}

bool emit_return_helper_call_from_single_local(
    inout uint cursor,
    uint return_node,
    uint helper_fn_token,
    bool write,
    uint target)
{
    uint ret_i = hir_token_pos[return_node];
    uint ret_end = hir_token_end[return_node];
    uint expr_start = ret_i + 1u;
    uint expr_end = ret_end;
    if (expr_end > 0u && token_kind(expr_end - 1u) == TK_SEMICOLON)
        expr_end -= 1u;
    if (expr_start >= expr_end || !is_identifier_token(token_kind(expr_start)))
        return false;
    if (call_fn_index[expr_start] != helper_fn_token)
        return false;
    uint call_open = find_next_open_paren(expr_start + 1u, expr_end);
    uint call_close = matching_paren(call_open, expr_end);
    if (call_open == INVALID || call_close == INVALID || call_open + 2u != call_close)
        return false;
    if (!is_identifier_token(token_kind(call_open + 1u)))
        return false;
    emit_local_get(cursor, 0u, write, target);
    put_byte(cursor, 0x10u, write, target);
    put_u32_leb(cursor, 1u, write, target);
    return true;
}

bool emit_tag_match_main_body(
    inout uint cursor,
    uint main_node,
    uint helper_fn_token,
    out uint body_len,
    out uint fail_stage,
    out uint fail_detail,
    bool write,
    uint target)
{
    body_len = 0u;
    fail_stage = 530u;
    fail_detail = hir_token_pos[main_node];
    uint let_node;
    uint return_node;
    if (!find_main_let_and_return(main_node, let_node, return_node))
        return false;

    uint body_start = cursor;
    put_u32_leb(cursor, 1u, write, target);
    put_u32_leb(cursor, 1u, write, target);
    put_byte(cursor, 0x7fu, write, target);

    fail_stage = 531u;
    fail_detail = hir_token_pos[let_node];
    if (!emit_main_let_constructor_tag(cursor, let_node, write, target))
        return false;

    fail_stage = 532u;
    fail_detail = hir_token_pos[return_node];
    if (!emit_return_helper_call_from_single_local(cursor, return_node, helper_fn_token, write, target))
        return false;

    put_byte(cursor, 0x0bu, write, target);
    body_len = cursor - body_start;
    fail_stage = 0u;
    fail_detail = INVALID;
    return true;
}

bool arm_node_in_match_span(uint node, uint match_i, uint match_end)
{
    uint4 arm_record = hir_enum_match_record[node];
    uint pattern_node = arm_record.x;
    uint result_node = arm_record.w;
    if (pattern_node == INVALID || result_node == INVALID)
        return false;
    uint arm_start = hir_token_pos[node];
    uint pattern_i = hir_token_pos[pattern_node];
    uint result_i = hir_token_pos[result_node];
    return arm_start > match_i && arm_start < match_end && pattern_i < match_end &&
           result_i < match_end;
}

uint count_match_arms_from_metadata(uint match_node)
{
    if (match_node == INVALID || match_node >= active_hir_node_count())
        return 0u;
    return hir_enum_match_record[match_node].z;
}

uint next_match_arm_from_metadata(uint match_node, uint after_token)
{
    if (match_node == INVALID || match_node >= active_hir_node_count())
        return INVALID;
    uint match_i = hir_token_pos[match_node];
    uint match_end = hir_token_end[match_node];
    uint best = INVALID;
    uint best_pos = INVALID;
    uint first_arm = hir_enum_match_record[match_node].y;
    if (first_arm == INVALID || first_arm >= active_hir_node_count())
        return INVALID;
    uint count = active_hir_node_count();
    [loop]
    for (uint node = first_arm; node < count; node += 1u)
    {
        if (!arm_node_in_match_span(node, match_i, match_end))
            continue;
        uint pos = hir_token_pos[node];
        if (pos > after_token && (best_pos == INVALID || pos < best_pos))
        {
            best = node;
            best_pos = pos;
        }
    }
    return best;
}

bool result_int_literal_token(uint result_node, out uint literal_i)
{
    literal_i = INVALID;
    if (result_node == INVALID)
        return false;
    uint result_start = hir_token_pos[result_node];
    uint result_end = hir_token_end[result_node];
    if (result_start == INVALID || result_end == INVALID || result_start >= result_end)
        return false;
    if (token_kind(result_start) != TK_INT)
        return false;
    if (result_start + 1u == result_end ||
        (result_start + 2u == result_end && is_comma(token_kind(result_start + 1u))))
    {
        literal_i = result_start;
        return true;
    }
    return false;
}

bool emit_match_expr(
    inout uint cursor,
    uint match_i,
    uint match_end,
    out uint fail_stage,
    out uint fail_detail,
    bool write,
    uint target)
{
    fail_stage = 400u;
    fail_detail = match_i;
    uint match_node = hir_node_starting_at(match_i, HIR_MATCH_EXPR);
    fail_stage = 401u;
    if (token_kind(match_i) != TK_MATCH || match_node == INVALID)
        return false;
    fail_stage = 402u;
    uint scrutinee_i = scrutinee_token_for_match_node(match_node);
    fail_detail = scrutinee_i;
    if (scrutinee_i == INVALID || !is_identifier_token(token_kind(scrutinee_i)))
        return false;
    uint arm_count = count_match_arms_from_metadata(match_node);
    fail_stage = 404u;
    fail_detail = arm_count;
    if (arm_count == 0u || arm_count > MAX_MATCH_ARMS)
        return false;

    uint after_token = match_i;
    uint emitted = 0u;
    [loop]
    for (uint guard = 0u; guard < MAX_MATCH_ARMS; guard += 1u)
    {
        if (emitted >= arm_count)
            break;
        uint arm_node = next_match_arm_from_metadata(match_node, after_token);
        fail_stage = 410u;
        fail_detail = after_token;
        if (arm_node == INVALID)
            return false;

        uint4 arm_record = hir_enum_match_record[arm_node];
        uint pattern_node = arm_record.x;
        uint result_node = arm_record.w;
        uint pattern_i = hir_token_pos[pattern_node];
        uint result_start = INVALID;
        fail_stage = 411u;
        fail_detail = hir_token_pos[result_node];
        if (!result_int_literal_token(result_node, result_start))
            return false;
        uint tag;
        fail_stage = 412u;
        fail_detail = pattern_i;
        uint pattern_name_end = pattern_name_end_from_metadata(pattern_node, arm_node);
        if (pattern_name_end == INVALID)
            return false;
        if (!enum_variant_tag_for_path_span(pattern_i, pattern_name_end, tag))
            return false;
        bool last = emitted + 1u == arm_count;
        if (!last)
        {
            emit_local_get(cursor, 0u, write, target);
            emit_i32_const_u32(cursor, tag, write, target);
            put_byte(cursor, 0x46u, write, target);
            put_byte(cursor, 0x04u, write, target);
            put_byte(cursor, 0x7fu, write, target);
        }
        emit_i32_const_u32(cursor, parse_uint_token(result_start), write, target);
        if (!last)
        {
            put_byte(cursor, 0x05u, write, target);
        }
        emitted += 1u;
        after_token = hir_token_pos[arm_node];
    }
    fail_stage = 413u;
    fail_detail = emitted;
    [loop]
    for (uint i = 1u; i < MAX_MATCH_ARMS; i += 1u)
    {
        if (i >= arm_count)
            break;
        put_byte(cursor, 0x0bu, write, target);
    }
    fail_stage = 0u;
    fail_detail = INVALID;
    return emitted == arm_count;
}

bool emit_main_function_body(
    inout uint cursor,
    uint main_node,
    uint helper_fn_token,
    out uint body_len,
    out uint fail_stage,
    out uint fail_detail,
    bool write,
    uint target)
{
    body_len = 0u;
    fail_stage = 300u;
    fail_detail = INVALID;
    uint let_node;
    uint return_node;
    fail_stage = 301u;
    fail_detail = hir_token_pos[main_node];
    if (!find_main_let_and_return(main_node, let_node, return_node))
        return false;

    uint body_start = cursor;
    put_u32_leb(cursor, 1u, write, target);
    put_u32_leb(cursor, 1u, write, target);
    put_byte(cursor, 0x7fu, write, target);
    fail_stage = 302u;
    fail_detail = hir_token_pos[let_node];
    if (!emit_main_let_call(cursor, let_node, helper_fn_token, write, target))
        return false;

    uint ret_i = hir_token_pos[return_node];
    uint ret_end = hir_token_end[return_node];
    uint expr_start = ret_i + 1u;
    uint expr_end = ret_end;
    if (expr_end > 0u && token_kind(expr_end - 1u) == TK_SEMICOLON)
        expr_end -= 1u;
    fail_stage = 303u;
    fail_detail = expr_start;
    uint match_fail_stage = 0u;
    uint match_fail_detail = INVALID;
    if (!emit_match_expr(
            cursor,
            expr_start,
            expr_end,
            match_fail_stage,
            match_fail_detail,
            write,
            target))
    {
        fail_stage = match_fail_stage;
        fail_detail = match_fail_detail;
        return false;
    }
    put_byte(cursor, 0x0bu, write, target);
    body_len = cursor - body_start;
    fail_stage = 0u;
    fail_detail = INVALID;
    return true;
}

void emit_type_section(inout uint cursor, uint helper_param_count, bool write, uint target)
{
    uint payload_len = 13u + helper_param_count;
    put_byte(cursor, 1u, write, target);
    put_u32_leb5(cursor, payload_len, write, target);
    put_byte(cursor, 3u, write, target);

    put_byte(cursor, 0x60u, write, target);
    put_byte(cursor, 1u, write, target);
    put_byte(cursor, 0x7eu, write, target);
    put_byte(cursor, 0u, write, target);

    put_byte(cursor, 0x60u, write, target);
    put_u32_leb(cursor, helper_param_count, write, target);
    [loop]
    for (uint i = 0u; i < MAX_PARAM_COUNT; i += 1u)
    {
        if (i >= helper_param_count)
            break;
        put_byte(cursor, 0x7fu, write, target);
    }
    put_byte(cursor, 1u, write, target);
    put_byte(cursor, 0x7fu, write, target);

    put_byte(cursor, 0x60u, write, target);
    put_byte(cursor, 0u, write, target);
    put_byte(cursor, 1u, write, target);
    put_byte(cursor, 0x7fu, write, target);
}

void emit_import_section(inout uint cursor, bool write, uint target)
{
    put_byte(cursor, 2u, write, target);
    put_u32_leb5(cursor, 17u, write, target);
    put_byte(cursor, 1u, write, target);
    put_byte(cursor, 3u, write, target);
    put_byte(cursor, 101u, write, target);
    put_byte(cursor, 110u, write, target);
    put_byte(cursor, 118u, write, target);
    put_byte(cursor, 9u, write, target);
    put_byte(cursor, 112u, write, target);
    put_byte(cursor, 114u, write, target);
    put_byte(cursor, 105u, write, target);
    put_byte(cursor, 110u, write, target);
    put_byte(cursor, 116u, write, target);
    put_byte(cursor, 95u, write, target);
    put_byte(cursor, 105u, write, target);
    put_byte(cursor, 54u, write, target);
    put_byte(cursor, 52u, write, target);
    put_byte(cursor, 0u, write, target);
    put_byte(cursor, 0u, write, target);
}

void emit_function_section(inout uint cursor, bool write, uint target)
{
    put_byte(cursor, 3u, write, target);
    put_u32_leb5(cursor, 3u, write, target);
    put_byte(cursor, 2u, write, target);
    put_byte(cursor, 1u, write, target);
    put_byte(cursor, 2u, write, target);
}

void emit_export_section(inout uint cursor, bool write, uint target)
{
    put_byte(cursor, 7u, write, target);
    put_u32_leb5(cursor, 8u, write, target);
    put_byte(cursor, 1u, write, target);
    put_byte(cursor, 4u, write, target);
    put_byte(cursor, 109u, write, target);
    put_byte(cursor, 97u, write, target);
    put_byte(cursor, 105u, write, target);
    put_byte(cursor, 110u, write, target);
    put_byte(cursor, 0u, write, target);
    put_byte(cursor, 2u, write, target);
}

bool emit_module(out uint module_len, out uint fail_stage, out uint fail_detail, bool write, uint target)
{
    module_len = 0u;
    fail_stage = 0u;
    fail_detail = INVALID;
    uint main_node = find_main_match_fn_node();
    uint helper_count = 0u;
    uint helper_node = INVALID;
    bool tag_match_mode = false;
    fail_stage = 10u;
    fail_detail = 0u;
    if (main_node != INVALID)
    {
        helper_node = find_called_helper_fn_node(main_node, helper_count);
        fail_stage = 11u;
        fail_detail = helper_count;
        if (helper_count != 1u || helper_node == INVALID)
            return false;
    }
    else
    {
        fail_stage = 40u;
        fail_detail = 0u;
        if (!find_tag_match_main_and_helper(main_node, helper_node, helper_count))
        {
            fail_detail = helper_count;
            return false;
        }
        tag_match_mode = true;
    }

    uint main_fn_token = hir_token_pos[main_node];
    uint helper_fn_token = hir_token_pos[helper_node];
    uint helper_param_count = min(call_param_count[helper_fn_token], MAX_PARAM_COUNT);
    fail_stage = 12u;
    fail_detail = helper_fn_token;
    if (call_param_count[main_fn_token] != 0u || helper_param_count == 0u)
        return false;

    uint cursor = 0u;
    put_byte(cursor, 0x00u, write, target);
    put_byte(cursor, 0x61u, write, target);
    put_byte(cursor, 0x73u, write, target);
    put_byte(cursor, 0x6du, write, target);
    put_byte(cursor, 0x01u, write, target);
    put_byte(cursor, 0x00u, write, target);
    put_byte(cursor, 0x00u, write, target);
    put_byte(cursor, 0x00u, write, target);
    emit_type_section(cursor, helper_param_count, write, target);
    emit_import_section(cursor, write, target);
    emit_function_section(cursor, write, target);
    emit_export_section(cursor, write, target);

    put_byte(cursor, 10u, write, target);
    uint code_payload_len_pos = cursor;
    put_u32_leb5(cursor, 0u, write, target);
    uint code_payload_start = cursor;
    put_byte(cursor, 2u, write, target);

    uint body_len_pos = cursor;
    put_u32_leb5(cursor, 0u, write, target);
    uint body_start = cursor;
    uint body_len;
    uint emitted_param_count;
    fail_stage = 20u;
    fail_detail = helper_fn_token;
    if (tag_match_mode)
    {
        uint helper_fail_stage = 0u;
        uint helper_fail_detail = INVALID;
        if (!emit_tag_match_helper_body(
                cursor,
                helper_node,
                body_len,
                emitted_param_count,
                helper_fail_stage,
                helper_fail_detail,
                write,
                target))
        {
            fail_stage = helper_fail_stage;
            fail_detail = helper_fail_detail;
            return false;
        }
    }
    else if (!emit_if_function_body(
                 cursor,
                 helper_node,
                 body_len,
                 emitted_param_count,
                 write,
                 target))
        return false;
    fail_stage = 21u;
    fail_detail = body_len;
    if (emitted_param_count != helper_param_count || body_len != cursor - body_start)
        return false;
    write_u32_leb5_at(body_len_pos, body_len, write, target);

    body_len_pos = cursor;
    put_u32_leb5(cursor, 0u, write, target);
    body_start = cursor;
    fail_stage = 30u;
    fail_detail = main_fn_token;
    uint main_fail_stage = 0u;
    uint main_fail_detail = INVALID;
    bool emitted_main = false;
    if (tag_match_mode)
    {
        emitted_main = emit_tag_match_main_body(
            cursor,
            main_node,
            helper_fn_token,
            body_len,
            main_fail_stage,
            main_fail_detail,
            write,
            target);
    }
    else
    {
        emitted_main = emit_main_function_body(
            cursor,
            main_node,
            helper_fn_token,
            body_len,
            main_fail_stage,
            main_fail_detail,
            write,
            target);
    }
    if (!emitted_main)
    {
        fail_stage = main_fail_stage;
        fail_detail = main_fail_detail;
        return false;
    }
    fail_stage = 31u;
    fail_detail = body_len;
    if (body_len != cursor - body_start)
        return false;
    write_u32_leb5_at(body_len_pos, body_len, write, target);

    write_u32_leb5_at(code_payload_len_pos, cursor - code_payload_start, write, target);
    module_len = cursor;
    fail_stage = 0u;
    fail_detail = INVALID;
    return true;
}

void record_enum_reject(uint detail, uint value, uint target)
{
    if (target == 0u && status[2u] == 0u)
    {
        status[0u] = value;
        status[1u] = 2u;
        status[2u] = ERR_ENUM_MODULE_BASE + detail;
        status[3u] = value;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint target = linear_dispatch_id(tid);
    uint target_limit = min(gParams.out_capacity, HIR_MODULE_OUTPUT_TARGET_LIMIT);
    if (target >= target_limit && target != 0u)
        return;
    if (status[1u] == 1u || status[1u] == 2u || status[1u] == 3u || status[1u] == 5u)
        return;

    uint module_len = 0u;
    uint fail_stage = 0u;
    uint fail_detail = INVALID;
    if (!emit_module(module_len, fail_stage, fail_detail, true, target))
    {
        record_enum_reject(fail_stage, fail_detail, target);
        return;
    }
    if (module_len == 0u || module_len > gParams.out_capacity ||
        module_len > HIR_MODULE_OUTPUT_TARGET_LIMIT)
    {
        record_enum_reject(1u, module_len, target);
        return;
    }

    if (target == 0u)
    {
        status[0u] = module_len;
        status[1u] = 5u;
        status[2u] = 0u;
        status[3u] = INVALID;
    }
}
