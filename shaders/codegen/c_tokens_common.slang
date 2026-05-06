import utils;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint segment_count;
    uint segment_len;
    uint block_count;
    uint scan_step;
    uint n_hir_nodes;
    uint emit_phase;
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
StructuredBuffer<uint> segments;
StructuredBuffer<uint> segment_meta;
StructuredBuffer<uint> token_hir_role;
StructuredBuffer<uint> token_codegen_flags;
StructuredBuffer<uint> codegen_bounds;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> out_words;

static const uint INVALID = 0xffffffffu;
static const uint FLAG_IN_FUNCTION_ITEM = 1u;
static const uint HIR_ROLE_SHIFT = 24u;
static const uint HIR_ROLE_END_MASK = 0x00ffffffu;

static const uint HIR_FN = 3u;
static const uint HIR_PARAM = 4u;
static const uint HIR_TYPE = 5u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_ARRAY_EXPR = 24u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;

static const uint EMIT_PHASE_LEGACY = 0u;
static const uint EMIT_PHASE_FUNCTIONS = 1u;
static const uint EMIT_PHASE_TOP_LEVEL = 2u;

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

bool has_hir_roles()
{
    return gParams.n_hir_nodes != 0u;
}

uint token_role(uint i)
{
    return i < active_token_count() ? token_hir_role[i] >> HIR_ROLE_SHIFT : 0u;
}

uint token_role_end(uint i)
{
    if (i >= active_token_count())
        return INVALID;
    uint packed = token_hir_role[i];
    return packed == 0u ? INVALID : packed & HIR_ROLE_END_MASK;
}

uint token_flags(uint i)
{
    return i < active_token_count() ? token_codegen_flags[i] : 0u;
}

static const uint SEG_HEADER = 0u;
static const uint SEG_INT = 1u;
static const uint SEG_VOID = 2u;
static const uint SEG_INT8 = 3u;
static const uint SEG_INT16 = 4u;
static const uint SEG_INT32 = 5u;
static const uint SEG_INT64 = 6u;
static const uint SEG_INTPTR = 7u;
static const uint SEG_UINT8 = 8u;
static const uint SEG_UINT16 = 9u;
static const uint SEG_UINT32 = 10u;
static const uint SEG_UINT64 = 11u;
static const uint SEG_UINTPTR = 12u;
static const uint SEG_FLOAT = 13u;
static const uint SEG_DOUBLE = 14u;
static const uint SEG_BOOL = 15u;
static const uint SEG_CHAR = 16u;
static const uint SEG_SPACE = 17u;
static const uint SEG_LPAREN = 18u;
static const uint SEG_RPAREN = 19u;
static const uint SEG_VOID_RPAREN = 20u;
static const uint SEG_COMMA = 21u;
static const uint SEG_ASSIGN = 22u;
static const uint SEG_SEMI_NL = 23u;
static const uint SEG_RETURN = 24u;
static const uint SEG_IF = 25u;
static const uint SEG_WHILE = 26u;
static const uint SEG_LBRACE_NL = 27u;
static const uint SEG_RBRACE_NL = 28u;
static const uint SEG_ELSE = 29u;
static const uint SEG_PRINT_I64 = 30u;
static const uint SEG_LBRACKET = 31u;
static const uint SEG_RBRACKET = 32u;
static const uint SEG_LBRACKET_INIT = 33u;
static const uint SEG_RBRACKET_INIT = 34u;
static const uint SEG_DOT = 35u;
static const uint SEG_PLUS = 36u;
static const uint SEG_MINUS = 37u;
static const uint SEG_STAR = 38u;
static const uint SEG_SLASH = 39u;
static const uint SEG_PERCENT = 40u;
static const uint SEG_LT = 41u;
static const uint SEG_GT = 42u;
static const uint SEG_LE = 43u;
static const uint SEG_GE = 44u;
static const uint SEG_EQEQ = 45u;
static const uint SEG_NE = 46u;
static const uint SEG_ANDAND = 47u;
static const uint SEG_OROR = 48u;
static const uint SEG_NOT = 49u;
static const uint SEG_AMP = 50u;
static const uint SEG_PIPE = 51u;
static const uint SEG_CARET = 52u;
static const uint SEG_SHL = 53u;
static const uint SEG_SHR = 54u;
static const uint SEG_TILDE = 55u;
static const uint SEG_PLUS_ASSIGN = 56u;
static const uint SEG_MINUS_ASSIGN = 57u;
static const uint SEG_STAR_ASSIGN = 58u;
static const uint SEG_SLASH_ASSIGN = 59u;
static const uint SEG_PERCENT_ASSIGN = 60u;
static const uint SEG_CARET_ASSIGN = 61u;
static const uint SEG_SHL_ASSIGN = 62u;
static const uint SEG_SHR_ASSIGN = 63u;
static const uint SEG_AMP_ASSIGN = 64u;
static const uint SEG_PIPE_ASSIGN = 65u;
static const uint SEG_INC = 66u;
static const uint SEG_DEC = 67u;
static const uint SEG_TOP_MAIN = 68u;
static const uint SEG_TOP_RETURN = 69u;
static const uint SEG_CONST_CHAR_PTR = 70u;

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
static const uint TK_QUESTION = 39u;
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

bool token_in_role_span(uint i, uint role)
{
    if (!has_hir_roles() || i >= active_token_count())
        return false;

    uint j = i;
    [loop]
    for (uint guard = 0u; guard < 64u; guard += 1u)
    {
        if (token_role(j) == role)
        {
            uint end_i = token_role_end(j);
            if (end_i != INVALID && j <= i && i < end_i)
                return true;
        }
        if (j == 0u)
            break;
        j -= 1u;
    }
    return false;
}

bool is_call_open_kind(uint kind)
{
    return kind == TK_CALL_LPAREN || kind == TK_LPAREN;
}

bool is_index_open_kind(uint kind)
{
    return kind == TK_INDEX_LBRACKET || kind == TK_LBRACKET;
}

bool is_array_open_kind(uint kind)
{
    return kind == TK_ARRAY_LBRACKET || kind == TK_LBRACKET;
}

bool is_array_close_kind(uint kind)
{
    return kind == TK_ARRAY_RBRACKET || kind == TK_RBRACKET;
}

bool is_list_comma_kind(uint kind)
{
    return kind == TK_ARG_COMMA || kind == TK_ARRAY_COMMA || kind == TK_PARAM_COMMA ||
           kind == TK_COMMA;
}

bool is_type_array_open_kind(uint kind)
{
    return kind == TK_TYPE_ARRAY_LBRACKET || kind == TK_ARRAY_LBRACKET || kind == TK_LBRACKET;
}

bool is_type_array_close_kind(uint kind)
{
    return kind == TK_TYPE_ARRAY_RBRACKET || kind == TK_ARRAY_RBRACKET || kind == TK_RBRACKET;
}

bool is_any_bracket_open_kind(uint kind)
{
    return kind == TK_LBRACKET || kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET ||
           kind == TK_TYPE_ARRAY_LBRACKET;
}

bool is_any_bracket_close_kind(uint kind)
{
    return kind == TK_RBRACKET || kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET ||
           kind == TK_TYPE_ARRAY_RBRACKET;
}

bool is_raw_type_candidate_kind(uint kind)
{
    return kind == TK_IDENT || kind == TK_INT || kind == TK_LBRACKET || kind == TK_RBRACKET ||
           kind == TK_SEMICOLON;
}

bool raw_lbracket_starts_type_array(uint open_i)
{
    if (open_i >= active_token_count() || token_kind(open_i) != TK_LBRACKET)
        return false;
    if (token_role(open_i) == HIR_TYPE || token_in_role_span(open_i, HIR_TYPE))
        return true;
    uint prev = open_i > 0u ? token_kind(open_i - 1u) : 0u;
    return prev == TK_COLON || prev == TK_ARROW;
}

bool raw_type_array_contains(uint i)
{
    if (i >= active_token_count() || !is_raw_type_candidate_kind(token_kind(i)))
        return false;

    uint open_i = i;
    [loop]
    for (uint back_guard = 0u; back_guard < 64u; back_guard += 1u)
    {
        if (token_kind(open_i) == TK_LBRACKET && raw_lbracket_starts_type_array(open_i))
        {
            uint depth = 0u;
            uint n_active = active_token_count();
            [loop]
            for (uint fwd_guard = 0u; fwd_guard < 64u && open_i + fwd_guard < n_active;
                 fwd_guard += 1u)
            {
                uint j = open_i + fwd_guard;
                uint kind = token_kind(j);
                if (kind == TK_LBRACKET)
                {
                    depth += 1u;
                }
                else if (kind == TK_RBRACKET)
                {
                    if (depth == 0u)
                        return false;
                    depth -= 1u;
                    if (depth == 0u)
                        return i <= j;
                }
            }
            return false;
        }

        if (open_i == 0u)
            break;
        open_i -= 1u;
    }
    return false;
}

bool is_type_annotation_token(uint i)
{
    if (i >= active_token_count())
        return false;
    uint role = token_role(i);
    if (role == HIR_TYPE || token_in_role_span(i, HIR_TYPE))
        return true;
    if (raw_type_array_contains(i))
        return true;
    uint kind = token_kind(i);
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    return kind == TK_IDENT && (prev == TK_COLON || prev == TK_ARROW);
}

bool is_let_decl_ident(uint i)
{
    if (i >= active_token_count())
        return false;
    uint kind = token_kind(i);
    return kind == TK_LET_IDENT ||
           (kind == TK_IDENT && i > 0u && token_role(i - 1u) == HIR_LET_STMT);
}

bool is_param_decl_ident(uint i)
{
    if (i >= active_token_count())
        return false;
    uint kind = token_kind(i);
    return kind == TK_PARAM_IDENT || (kind == TK_IDENT && token_role(i) == HIR_PARAM);
}

uint source_at(uint start, uint delta)
{
    uint idx = start + delta;
    return idx < gParams.source_len ? load_byte_at(source_bytes, idx) : 0u;
}

void put_byte(inout uint cursor, uint value, bool write)
{
    if (write && cursor < gParams.out_capacity)
        out_words[cursor] = value & 0xffu;
    cursor += 1u;
}

void emit_segment_id(inout uint cursor, uint seg_id, bool write)
{
    if (seg_id >= gParams.segment_count)
        return;

    uint off = segment_meta[seg_id * 2u];
    uint len = segment_meta[seg_id * 2u + 1u];
    for (uint i = 0u; i < len; i += 1u)
    {
        uint idx = off + i;
        if (idx < gParams.segment_len)
            put_byte(cursor, segments[idx], write);
    }
}

void emit_source_span(inout uint cursor, uint start, uint len, bool write)
{
    for (uint i = 0u; i < len; i += 1u)
    {
        uint idx = start + i;
        if (idx < gParams.source_len)
            put_byte(cursor, load_byte_at(source_bytes, idx), write);
    }
}

void emit_uint_decimal(inout uint cursor, uint value, bool write)
{
    uint div = 1000000000u;
    bool started = false;
    [loop]
    for (uint guard = 0u; guard < 10u; guard += 1u)
    {
        uint digit = value / div;
        if (digit != 0u || started || div == 1u)
        {
            put_byte(cursor, 48u + digit, write);
            started = true;
        }
        value = value - digit * div;
        div = div / 10u;
    }
}

bool span2(uint start, uint len, uint a, uint b)
{
    return len == 2u && source_at(start, 0u) == a && source_at(start, 1u) == b;
}

bool span3(uint start, uint len, uint a, uint b, uint c)
{
    return len == 3u && source_at(start, 0u) == a && source_at(start, 1u) == b &&
           source_at(start, 2u) == c;
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

bool token_text_eq(uint i, uint a, uint b, uint c, uint d)
{
    uint start = token_start(i);
    uint len = token_len(i);
    return span4(start, len, a, b, c, d);
}

bool token_text_eq5(uint i, uint a, uint b, uint c, uint d, uint e)
{
    uint start = token_start(i);
    uint len = token_len(i);
    return span5(start, len, a, b, c, d, e);
}

bool same_text(uint a, uint b)
{
    uint len = token_len(a);
    if (len != token_len(b))
        return false;
    uint sa = token_start(a);
    uint sb = token_start(b);
    for (uint i = 0u; i < len; i += 1u)
    {
        if (source_at(sa, i) != source_at(sb, i))
            return false;
    }
    return true;
}

uint type_segment_for(uint type_i)
{
    uint start = token_start(type_i);
    uint len = token_len(type_i);

    if (span2(start, len, 105u, 56u))
        return SEG_INT8;
    if (span3(start, len, 105u, 49u, 54u))
        return SEG_INT16;
    if (span3(start, len, 105u, 51u, 50u))
        return SEG_INT32;
    if (span3(start, len, 105u, 54u, 52u))
        return SEG_INT64;
    if (span5(start, len, 105u, 115u, 105u, 122u, 101u))
        return SEG_INTPTR;

    if (span2(start, len, 117u, 56u))
        return SEG_UINT8;
    if (span3(start, len, 117u, 49u, 54u))
        return SEG_UINT16;
    if (span3(start, len, 117u, 51u, 50u))
        return SEG_UINT32;
    if (span3(start, len, 117u, 54u, 52u))
        return SEG_UINT64;
    if (span5(start, len, 117u, 115u, 105u, 122u, 101u))
        return SEG_UINTPTR;

    if (span3(start, len, 102u, 51u, 50u))
        return SEG_FLOAT;
    if (span3(start, len, 102u, 54u, 52u))
        return SEG_DOUBLE;
    if (span4(start, len, 98u, 111u, 111u, 108u))
        return SEG_BOOL;
    if (span4(start, len, 99u, 104u, 97u, 114u))
        return SEG_CHAR;

    return INVALID;
}

uint find_type_semi(uint type_i)
{
    uint depth = 0u;
    uint n_active = active_token_count();
    for (uint j = type_i + 1u; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_type_array_open_kind(kind))
        {
            depth += 1u;
        }
        else if (is_type_array_close_kind(kind))
        {
            if (depth == 0u)
                return INVALID;
            depth -= 1u;
        }
        else if ((kind == TK_TYPE_SEMICOLON || kind == TK_SEMICOLON) && depth == 0u)
        {
            return j;
        }
    }
    return INVALID;
}

void emit_type_base(inout uint cursor, uint type_i, bool write)
{
    uint name_i = type_i;
    uint n_active = active_token_count();
    for (uint guard = 0u; guard < 32u && name_i < n_active; guard += 1u)
    {
        if (!is_type_array_open_kind(token_kind(name_i)))
            break;
        name_i += 1u;
    }

    uint seg = type_segment_for(name_i);
    if (seg != INVALID)
        emit_segment_id(cursor, seg, write);
    else
        emit_source_span(cursor, token_start(name_i), token_len(name_i), write);
}

void emit_array_suffixes(inout uint cursor, uint type_i, bool write)
{
    uint cur = type_i;
    uint n_active = active_token_count();
    for (uint guard = 0u; guard < 32u && cur < n_active; guard += 1u)
    {
        if (!is_type_array_open_kind(token_kind(cur)))
            break;

        uint semi = find_type_semi(cur);
        if (semi == INVALID || semi + 1u >= n_active)
            break;

        emit_segment_id(cursor, SEG_LBRACKET, write);
        emit_source_span(cursor, token_start(semi + 1u), token_len(semi + 1u), write);
        emit_segment_id(cursor, SEG_RBRACKET, write);
        cur += 1u;
    }
}

void emit_decl_from_type(inout uint cursor, uint type_i, uint name_i, bool write)
{
    emit_type_base(cursor, type_i, write);
    emit_segment_id(cursor, SEG_SPACE, write);
    emit_source_span(cursor, token_start(name_i), token_len(name_i), write);
    emit_array_suffixes(cursor, type_i, write);
}

uint find_fn_return_type(uint fn_i)
{
    uint n_active = active_token_count();
    for (uint j = fn_i + 2u; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACE || kind == TK_IF_LBRACE)
            return INVALID;
        if (kind == TK_ARROW)
            return j + 1u;
    }
    return INVALID;
}

bool is_function_main(uint fn_i)
{
    return fn_i + 1u < active_token_count() &&
           token_text_eq(fn_i + 1u, 109u, 97u, 105u, 110u);
}

bool token_opens_block(uint kind)
{
    return kind == TK_LBRACE || kind == TK_IF_LBRACE;
}

bool token_closes_block(uint kind)
{
    return kind == TK_RBRACE || kind == TK_IF_RBRACE;
}

bool token_in_function_item(uint target_i)
{
    if (has_hir_roles())
        return (token_flags(target_i) & FLAG_IN_FUNCTION_ITEM) != 0u;

    bool in_fn = false;
    bool pub_fn_pending = false;
    uint fn_depth = 0u;
    uint n_active = active_token_count();
    for (uint j = 0u; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);

        bool pub_starts_fn = kind == TK_PUB && j + 1u < n_active && token_kind(j + 1u) == TK_FN;
        if (!in_fn && pub_starts_fn)
            pub_fn_pending = true;
        if (!in_fn && kind == TK_FN)
        {
            in_fn = true;
            pub_fn_pending = false;
        }

        bool selected = in_fn || pub_starts_fn || pub_fn_pending;
        if (j == target_i)
            return selected;

        if (in_fn)
        {
            if (token_opens_block(kind))
            {
                fn_depth += 1u;
            }
            else if (token_closes_block(kind))
            {
                if (fn_depth > 0u)
                    fn_depth -= 1u;
                if (fn_depth == 0u)
                    in_fn = false;
            }
        }
    }

    return false;
}

bool token_in_top_level_item(uint i)
{
    return i < active_token_count() && !token_in_function_item(i);
}

bool first_top_level_token(uint i)
{
    if (has_hir_roles())
        return token_in_top_level_item(i) && i == codegen_bounds[0u];

    if (!token_in_top_level_item(i))
        return false;
    for (uint j = 0u; j < i; j += 1u)
    {
        if (token_in_top_level_item(j))
            return false;
    }
    return true;
}

bool last_top_level_token(uint i)
{
    if (has_hir_roles())
        return token_in_top_level_item(i) && i == codegen_bounds[1u];

    if (!token_in_top_level_item(i))
        return false;
    uint n_active = active_token_count();
    for (uint j = i + 1u; j < n_active; j += 1u)
    {
        if (token_in_top_level_item(j))
            return false;
    }
    return true;
}

bool token_selected_for_phase(uint i)
{
    if (gParams.emit_phase == EMIT_PHASE_FUNCTIONS)
        return token_in_function_item(i);
    if (gParams.emit_phase == EMIT_PHASE_TOP_LEVEL)
        return token_in_top_level_item(i);
    return true;
}

bool empty_param_list(uint rparen_i)
{
    if (rparen_i == 0u)
        return false;
    uint prev = token_kind(rparen_i - 1u);
    if (prev == TK_PARAM_LPAREN)
        return true;
    return prev == TK_LPAREN && rparen_i >= 3u && token_kind(rparen_i - 3u) == TK_FN;
}

bool int_is_type_array_len(uint i)
{
    return i > 0u && (token_kind(i - 1u) == TK_TYPE_SEMICOLON ||
                      (token_kind(i - 1u) == TK_SEMICOLON && is_type_annotation_token(i)));
}

bool is_bool_result_operator(uint kind)
{
    return kind == TK_LT || kind == TK_GT || kind == TK_LE || kind == TK_GE || kind == TK_EQEQ ||
           kind == TK_NOT_EQUAL || kind == TK_ANDAND || kind == TK_OROR;
}

uint find_stmt_semicolon(uint start_i)
{
    if (has_hir_roles() && start_i < active_token_count())
    {
        uint role_i = start_i;
        if (start_i > 0u && is_let_decl_ident(start_i))
            role_i = start_i - 1u;

        uint end_i = token_role_end(role_i);
        if (end_i != INVALID && end_i > start_i)
            return end_i - 1u;
    }

    uint bracket_depth = 0u;
    uint n_active = active_token_count();
    for (uint j = start_i + 1u; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_type_array_open_kind(kind) || kind == TK_INDEX_LBRACKET)
        {
            bracket_depth += 1u;
        }
        else if (is_type_array_close_kind(kind) || kind == TK_INDEX_RBRACKET)
        {
            if (bracket_depth > 0u)
                bracket_depth -= 1u;
        }
        else if (kind == TK_SEMICOLON && bracket_depth == 0u)
        {
            return j;
        }
    }
    return INVALID;
}

uint find_let_assign(uint let_ident_i, uint semi_i)
{
    uint n_active = active_token_count();
    for (uint j = let_ident_i + 1u; j < semi_i && j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LET_ASSIGN || kind == TK_ASSIGN)
            return j;
    }
    return INVALID;
}

uint find_array_literal_close(uint open_i, uint limit_i)
{
    uint depth = 0u;
    for (uint j = open_i; j < limit_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_array_open_kind(kind))
            depth += 1u;
        else if (is_array_close_kind(kind))
        {
            if (depth == 0u)
                return INVALID;
            depth -= 1u;
            if (depth == 0u)
                return j;
        }
    }
    return INVALID;
}

uint array_literal_len(uint open_i, uint close_i)
{
    if (close_i == INVALID || open_i + 1u >= close_i)
        return 0u;

    uint depth = 0u;
    uint count = 1u;
    for (uint j = open_i + 1u; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_array_open_kind(kind))
            depth += 1u;
        else if (is_array_close_kind(kind) && depth > 0u)
            depth -= 1u;
        else if (is_list_comma_kind(kind) && depth == 0u)
            count += 1u;
    }
    return count;
}

uint array_first_elem_end(uint open_i, uint close_i)
{
    uint depth = 0u;
    for (uint j = open_i + 1u; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_array_open_kind(kind))
            depth += 1u;
        else if (is_array_close_kind(kind) && depth > 0u)
            depth -= 1u;
        else if (is_list_comma_kind(kind) && depth == 0u)
            return j;
    }
    return close_i;
}

bool array_literal_is_direct_let_initializer(uint open_i)
{
    if (open_i == 0u)
        return false;
    uint prev = token_kind(open_i - 1u);
    return prev == TK_ASSIGN || prev == TK_LET_ASSIGN;
}

void emit_array_literal_open(inout uint cursor, uint open_i, bool write)
{
    if (array_literal_is_direct_let_initializer(open_i))
    {
        emit_segment_id(cursor, SEG_LBRACKET_INIT, write);
        return;
    }

    emit_segment_id(cursor, SEG_LPAREN, write);
    emit_segment_id(cursor, SEG_INT64, write);
    emit_segment_id(cursor, SEG_LBRACKET, write);
    emit_segment_id(cursor, SEG_RBRACKET, write);
    emit_segment_id(cursor, SEG_RPAREN, write);
    emit_segment_id(cursor, SEG_LBRACKET_INIT, write);
}

bool closes_hir_array_literal(uint close_i)
{
    uint depth = 0u;
    uint j = close_i;
    [loop]
    for (uint guard = 0u; guard < 128u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (is_any_bracket_close_kind(kind))
        {
            depth += 1u;
            continue;
        }
        if (!is_any_bracket_open_kind(kind))
            continue;
        if (depth > 0u)
        {
            depth -= 1u;
            continue;
        }
        return token_role(j) == HIR_ARRAY_EXPR;
    }
    return false;
}

uint find_named_function(uint name_i)
{
    if (name_i < active_token_count() && call_fn_index[name_i] != INVALID)
        return call_fn_index[name_i];

    uint n_active = active_token_count();
    for (uint j = 0u; j + 1u < n_active; j += 1u)
    {
        if (token_kind(j) == TK_FN && same_text(j + 1u, name_i))
            return j;
    }
    return INVALID;
}

uint function_return_segment(uint fn_i)
{
    if (fn_i == INVALID)
        return INVALID;
    if (is_function_main(fn_i))
        return SEG_INT;
    uint ret_i = find_fn_return_type(fn_i);
    if (ret_i == INVALID)
        return SEG_VOID;
    return type_segment_for(ret_i);
}

uint type_code_segment(uint ty)
{
    [loop]
    for (uint guard = 0u; guard < 8u && ty >= TY_ARRAY_BASE; guard += 1u)
        ty -= TY_ARRAY_BASE;

    if (ty == TY_VOID)
        return SEG_VOID;
    if (ty == TY_BOOL)
        return SEG_BOOL;
    if (ty == TY_INT)
        return SEG_INT64;
    if (ty == TY_UINT)
        return SEG_UINT64;
    if (ty == TY_FLOAT)
        return SEG_DOUBLE;
    if (ty == TY_CHAR)
        return SEG_CHAR;
    if (ty == TY_STRING)
        return SEG_CONST_CHAR_PTR;
    return INVALID;
}

uint call_return_segment(uint name_i)
{
    return name_i < active_token_count() ? type_code_segment(call_return_type[name_i]) : INVALID;
}

uint enclosing_function_start_for_ident(uint i)
{
    uint j = i;
    while (j > 0u)
    {
        j -= 1u;
        if (token_kind(j) == TK_FN)
            return j;
    }
    return 0u;
}

uint expr_type_segment_shallow(uint expr_i, uint limit_i)
{
    bool saw_float = false;
    uint head = INVALID;
    for (uint j = expr_i; j < limit_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_bool_result_operator(kind))
            return SEG_BOOL;
        if (kind == TK_FLOAT)
            saw_float = true;
        if (head == INVALID)
        {
            if (kind == TK_GROUP_LPAREN || kind == TK_LPAREN || kind == TK_PREFIX_PLUS ||
                kind == TK_PREFIX_MINUS)
                continue;
            head = j;
        }
    }

    if (head == INVALID)
        return INVALID;

    uint head_kind = token_kind(head);
    if (head_kind == TK_STRING)
        return SEG_CONST_CHAR_PTR;
    if (head_kind == TK_CHAR)
        return SEG_CHAR;
    if (head_kind == TK_FLOAT || saw_float)
        return SEG_DOUBLE;
    if (head_kind == TK_INT)
        return SEG_INT64;
    if (head_kind == TK_IDENT && head + 1u < limit_i && is_call_open_kind(token_kind(head + 1u)))
    {
        if (has_hir_roles())
            return call_return_segment(head);
        return function_return_segment(find_named_function(head));
    }

    return INVALID;
}

uint declaration_type_segment_shallow(uint decl_i)
{
    uint kind = token_kind(decl_i);
    if (is_param_decl_ident(decl_i))
        return type_segment_for(decl_i + 2u);

    if (is_let_decl_ident(decl_i))
    {
        if (token_kind(decl_i + 1u) == TK_COLON)
            return type_segment_for(decl_i + 2u);

        uint semi = find_stmt_semicolon(decl_i);
        if (semi == INVALID)
            return INVALID;
        uint assign_i = find_let_assign(decl_i, semi);
        if (assign_i == INVALID || assign_i + 1u >= semi)
            return INVALID;

        for (uint j = assign_i + 1u; j < semi; j += 1u)
        {
            if (token_kind(j) == TK_IDENT && same_text(j, decl_i))
                return INVALID;
        }
        return expr_type_segment_shallow(assign_i + 1u, semi);
    }

    return INVALID;
}

uint visible_declaration_for(uint ident_i)
{
    return ident_i < active_token_count() ? visible_decl[ident_i] : INVALID;
}

uint visible_type_for(uint ident_i)
{
    return ident_i < active_token_count() ? visible_type[ident_i] : TY_UNKNOWN;
}

uint declaration_type_segment(uint decl_i)
{
    for (uint depth = 0u; depth < 8u && decl_i != INVALID; depth += 1u)
    {
        uint shallow = declaration_type_segment_shallow(decl_i);
        if (shallow != INVALID)
            return shallow;

        if (!is_let_decl_ident(decl_i))
            return INVALID;

        uint semi = find_stmt_semicolon(decl_i);
        if (semi == INVALID)
            return INVALID;
        uint assign_i = find_let_assign(decl_i, semi);
        if (assign_i == INVALID || assign_i + 1u >= semi)
            return INVALID;

        for (uint j = assign_i + 1u; j < semi; j += 1u)
        {
            if (token_kind(j) == TK_IDENT && same_text(j, decl_i))
                return INVALID;
        }

        uint cur = assign_i + 1u;
        uint n_active = active_token_count();
        bool followed = false;
        for (uint guard = 0u; guard < 16u && cur < semi && cur < n_active; guard += 1u)
        {
            uint head_kind = token_kind(cur);
            if (head_kind == TK_GROUP_LPAREN || head_kind == TK_LPAREN ||
                head_kind == TK_PREFIX_PLUS || head_kind == TK_PREFIX_MINUS)
            {
                cur += 1u;
                continue;
            }
            if (head_kind == TK_IDENT && !(cur + 1u < semi && is_call_open_kind(token_kind(cur + 1u))))
            {
                uint decl = visible_declaration_for(cur);
                if (decl == INVALID || decl == decl_i)
                    return INVALID;
                decl_i = decl;
                followed = true;
            }
            break;
        }
        if (!followed)
            return INVALID;
    }

    return INVALID;
}

uint identifier_type_segment(uint ident_i)
{
    uint decl = visible_declaration_for(ident_i);
    if (decl != INVALID)
        return declaration_type_segment(decl);

    if (has_hir_roles())
        return INVALID;

    uint lower = enclosing_function_start_for_ident(ident_i);
    uint j = ident_i;
    while (j > lower)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if ((is_let_decl_ident(j) || is_param_decl_ident(j)) && same_text(j, ident_i))
            return declaration_type_segment(j);
    }
    return INVALID;
}

uint expr_type_segment(uint expr_i, uint limit_i)
{
    uint shallow = expr_type_segment_shallow(expr_i, limit_i);
    if (shallow != INVALID)
        return shallow;

    uint cur = expr_i;
    uint n_active = active_token_count();
    for (uint guard = 0u; guard < 16u && cur < limit_i && cur < n_active; guard += 1u)
    {
        uint head_kind = token_kind(cur);
        if (head_kind == TK_GROUP_LPAREN || head_kind == TK_LPAREN || head_kind == TK_PREFIX_PLUS ||
            head_kind == TK_PREFIX_MINUS)
        {
            cur += 1u;
            continue;
        }
        if (head_kind == TK_IDENT)
            return identifier_type_segment(cur);
        break;
    }

    return INVALID;
}

uint inferred_let_type_segment(uint let_ident_i)
{
    uint semi = find_stmt_semicolon(let_ident_i);
    if (semi == INVALID)
        return SEG_INT64;

    uint assign_i = find_let_assign(let_ident_i, semi);
    if (assign_i == INVALID || assign_i + 1u >= semi)
        return SEG_INT64;

    uint seg = expr_type_segment(assign_i + 1u, semi);
    return seg == INVALID || seg == SEG_VOID ? SEG_INT64 : seg;
}

uint inferred_let_array_open(uint let_ident_i, uint semi)
{
    uint assign_i = find_let_assign(let_ident_i, semi);
    if (assign_i == INVALID || assign_i + 1u >= semi)
        return INVALID;

    uint cur = assign_i + 1u;
    for (uint guard = 0u; guard < 16u && cur < semi; guard += 1u)
    {
        uint kind = token_kind(cur);
        if (kind == TK_GROUP_LPAREN || kind == TK_LPAREN || kind == TK_PREFIX_PLUS ||
            kind == TK_PREFIX_MINUS)
        {
            cur += 1u;
            continue;
        }
        return is_array_open_kind(kind) ? cur : INVALID;
    }
    return INVALID;
}

void emit_inferred_let_decl(inout uint cursor, uint let_ident_i, bool write)
{
    uint known_ty = has_hir_roles() ? visible_type_for(let_ident_i) : TY_UNKNOWN;
    if (known_ty == TY_BOOL || known_ty == TY_CHAR || known_ty == TY_STRING)
    {
        uint seg = type_code_segment(known_ty);
        if (seg != INVALID && seg != SEG_VOID)
        {
            emit_segment_id(cursor, seg, write);
            emit_segment_id(cursor, SEG_SPACE, write);
            emit_source_span(cursor, token_start(let_ident_i), token_len(let_ident_i), write);
            return;
        }
    }

    uint semi = find_stmt_semicolon(let_ident_i);
    uint array_open = semi == INVALID ? INVALID : inferred_let_array_open(let_ident_i, semi);
    uint array_close = array_open == INVALID ? INVALID : find_array_literal_close(array_open, semi);
    uint len = array_literal_len(array_open, array_close);
    if (array_open != INVALID && array_close != INVALID && len > 0u)
    {
        uint elem_end = array_first_elem_end(array_open, array_close);
        uint elem_seg = expr_type_segment(array_open + 1u, elem_end);
        if (elem_seg == INVALID || elem_seg == SEG_VOID || elem_seg == SEG_CONST_CHAR_PTR)
            elem_seg = SEG_INT64;
        emit_segment_id(cursor, elem_seg, write);
        emit_segment_id(cursor, SEG_SPACE, write);
        emit_source_span(cursor, token_start(let_ident_i), token_len(let_ident_i), write);
        emit_segment_id(cursor, SEG_LBRACKET, write);
        emit_uint_decimal(cursor, len, write);
        emit_segment_id(cursor, SEG_RBRACKET, write);
        return;
    }

    emit_segment_id(cursor, inferred_let_type_segment(let_ident_i), write);
    emit_segment_id(cursor, SEG_SPACE, write);
    emit_source_span(cursor, token_start(let_ident_i), token_len(let_ident_i), write);
}

void emit_operator(inout uint cursor, uint seg, bool write)
{
    emit_segment_id(cursor, seg, write);
}

uint emit_token_fragment(uint i, uint base, bool write)
{
    uint cursor = base;
    if (i == 0u)
    {
        if (gParams.emit_phase != EMIT_PHASE_TOP_LEVEL)
            emit_segment_id(cursor, SEG_HEADER, write);
    }
    if ((gParams.emit_phase == EMIT_PHASE_LEGACY ||
         gParams.emit_phase == EMIT_PHASE_TOP_LEVEL) &&
        first_top_level_token(i))
        emit_segment_id(cursor, SEG_TOP_MAIN, write);

    bool selected = token_selected_for_phase(i);
    if (!selected)
    {
        if ((gParams.emit_phase == EMIT_PHASE_LEGACY ||
             gParams.emit_phase == EMIT_PHASE_TOP_LEVEL) &&
            last_top_level_token(i))
            emit_segment_id(cursor, SEG_TOP_RETURN, write);
        return cursor - base;
    }

    uint kind = token_kind(i);
    if (is_type_annotation_token(i))
        return cursor - base;

    if (kind == TK_IDENT && is_param_decl_ident(i))
    {
        emit_decl_from_type(cursor, i + 2u, i, write);
        return cursor - base;
    }

    if (kind == TK_IDENT && is_let_decl_ident(i))
    {
        if (i + 1u < active_token_count() && token_kind(i + 1u) == TK_COLON)
            emit_decl_from_type(cursor, i + 2u, i, write);
        else
            emit_inferred_let_decl(cursor, i, write);
        return cursor - base;
    }

    switch (kind)
    {
    case TK_PUB:
    case TK_LET:
    case TK_COLON:
    case TK_ARROW:
    case TK_TYPE_IDENT:
    case TK_TYPE_ARRAY_LBRACKET:
    case TK_TYPE_ARRAY_RBRACKET:
    case TK_TYPE_SEMICOLON:
        break;

    case TK_FN:
    {
        if (has_hir_roles() && token_role(i) != HIR_FN)
            break;
        emit_segment_id(cursor, function_return_segment(i), write);
        emit_segment_id(cursor, SEG_SPACE, write);
        break;
    }

    case TK_IDENT:
        if (i + 1u < active_token_count() && is_call_open_kind(token_kind(i + 1u)) &&
            (!has_hir_roles() || token_role(i + 1u) == HIR_CALL_EXPR) &&
            token_text_eq5(i, 112u, 114u, 105u, 110u, 116u))
            emit_segment_id(cursor, SEG_PRINT_I64, write);
        else
            emit_source_span(cursor, token_start(i), token_len(i), write);
        break;

    case TK_PARAM_IDENT:
        emit_decl_from_type(cursor, i + 2u, i, write);
        break;

    case TK_LET_IDENT:
        if (has_hir_roles() && (i == 0u || token_role(i - 1u) != HIR_LET_STMT))
            break;
        if (i + 1u < active_token_count() && token_kind(i + 1u) == TK_COLON)
            emit_decl_from_type(cursor, i + 2u, i, write);
        else
            emit_inferred_let_decl(cursor, i, write);
        break;

    case TK_INT:
        if (!int_is_type_array_len(i))
            emit_source_span(cursor, token_start(i), token_len(i), write);
        break;

    case TK_FLOAT:
    case TK_STRING:
    case TK_CHAR:
        emit_source_span(cursor, token_start(i), token_len(i), write);
        break;

    case TK_PARAM_LPAREN:
    case TK_CALL_LPAREN:
    case TK_GROUP_LPAREN:
    case TK_LPAREN:
        emit_segment_id(cursor, SEG_LPAREN, write);
        break;

    case TK_PARAM_RPAREN:
        if (empty_param_list(i))
            emit_segment_id(cursor, SEG_VOID_RPAREN, write);
        else
            emit_segment_id(cursor, SEG_RPAREN, write);
        break;
    case TK_CALL_RPAREN:
    case TK_GROUP_RPAREN:
    case TK_RPAREN:
        if (empty_param_list(i))
            emit_segment_id(cursor, SEG_VOID_RPAREN, write);
        else
            emit_segment_id(cursor, SEG_RPAREN, write);
        break;

    case TK_PARAM_COMMA:
    case TK_ARG_COMMA:
    case TK_ARRAY_COMMA:
    case TK_COMMA:
        emit_segment_id(cursor, SEG_COMMA, write);
        break;

    case TK_LET_ASSIGN:
    case TK_ASSIGN:
        emit_operator(cursor, SEG_ASSIGN, write);
        break;
    case TK_SEMICOLON:
        emit_segment_id(cursor, SEG_SEMI_NL, write);
        break;
    case TK_RETURN:
        if (has_hir_roles() && token_role(i) != HIR_RETURN_STMT)
            break;
        emit_segment_id(cursor, SEG_RETURN, write);
        break;
    case TK_IF:
        if (has_hir_roles() && token_role(i) != HIR_IF_STMT)
            break;
        emit_segment_id(cursor, SEG_IF, write);
        break;
    case TK_WHILE:
        if (has_hir_roles() && token_role(i) != HIR_WHILE_STMT)
            break;
        emit_segment_id(cursor, SEG_WHILE, write);
        break;
    case TK_ELSE:
        emit_segment_id(cursor, SEG_ELSE, write);
        break;
    case TK_BREAK:
        emit_source_span(cursor, token_start(i), token_len(i), write);
        break;
    case TK_CONTINUE:
        emit_source_span(cursor, token_start(i), token_len(i), write);
        break;

    case TK_LBRACE:
    case TK_IF_LBRACE:
        emit_segment_id(cursor, SEG_LBRACE_NL, write);
        break;
    case TK_RBRACE:
    case TK_IF_RBRACE:
        emit_segment_id(cursor, SEG_RBRACE_NL, write);
        break;

    case TK_INDEX_LBRACKET:
    case TK_LBRACKET:
        if (token_role(i) == HIR_ARRAY_EXPR)
            emit_array_literal_open(cursor, i, write);
        else
            emit_segment_id(cursor, SEG_LBRACKET, write);
        break;
    case TK_INDEX_RBRACKET:
        emit_segment_id(cursor, SEG_RBRACKET, write);
        break;
    case TK_RBRACKET:
        if (closes_hir_array_literal(i))
            emit_segment_id(cursor, SEG_RBRACKET_INIT, write);
        else
            emit_segment_id(cursor, SEG_RBRACKET, write);
        break;
    case TK_ARRAY_LBRACKET:
        emit_array_literal_open(cursor, i, write);
        break;
    case TK_ARRAY_RBRACKET:
        emit_segment_id(cursor, SEG_RBRACKET_INIT, write);
        break;
    case TK_DOT:
        emit_segment_id(cursor, SEG_DOT, write);
        break;

    case TK_PLUS:
    case TK_PREFIX_PLUS:
    case TK_INFIX_PLUS:
        emit_operator(cursor, SEG_PLUS, write);
        break;
    case TK_MINUS:
    case TK_PREFIX_MINUS:
    case TK_INFIX_MINUS:
        emit_operator(cursor, SEG_MINUS, write);
        break;
    case TK_STAR:
        emit_operator(cursor, SEG_STAR, write);
        break;
    case TK_SLASH:
        emit_operator(cursor, SEG_SLASH, write);
        break;
    case TK_PERCENT:
        emit_operator(cursor, SEG_PERCENT, write);
        break;
    case TK_LT:
        emit_operator(cursor, SEG_LT, write);
        break;
    case TK_GT:
        emit_operator(cursor, SEG_GT, write);
        break;
    case TK_LE:
        emit_operator(cursor, SEG_LE, write);
        break;
    case TK_GE:
        emit_operator(cursor, SEG_GE, write);
        break;
    case TK_EQEQ:
        emit_operator(cursor, SEG_EQEQ, write);
        break;
    case TK_NOT_EQUAL:
        emit_operator(cursor, SEG_NE, write);
        break;
    case TK_ANDAND:
        emit_operator(cursor, SEG_ANDAND, write);
        break;
    case TK_OROR:
        emit_operator(cursor, SEG_OROR, write);
        break;
    case TK_NOT:
        emit_operator(cursor, SEG_NOT, write);
        break;
    case TK_AMPERSAND:
        emit_operator(cursor, SEG_AMP, write);
        break;
    case TK_PIPE:
        emit_operator(cursor, SEG_PIPE, write);
        break;
    case TK_CARET:
        emit_operator(cursor, SEG_CARET, write);
        break;
    case TK_SHL:
        emit_operator(cursor, SEG_SHL, write);
        break;
    case TK_SHR:
        emit_operator(cursor, SEG_SHR, write);
        break;
    case TK_TILDE:
        emit_operator(cursor, SEG_TILDE, write);
        break;
    case TK_PLUS_ASSIGN:
        emit_operator(cursor, SEG_PLUS_ASSIGN, write);
        break;
    case TK_MINUS_ASSIGN:
        emit_operator(cursor, SEG_MINUS_ASSIGN, write);
        break;
    case TK_STAR_ASSIGN:
        emit_operator(cursor, SEG_STAR_ASSIGN, write);
        break;
    case TK_SLASH_ASSIGN:
        emit_operator(cursor, SEG_SLASH_ASSIGN, write);
        break;
    case TK_PERCENT_ASSIGN:
        emit_operator(cursor, SEG_PERCENT_ASSIGN, write);
        break;
    case TK_CARET_ASSIGN:
        emit_operator(cursor, SEG_CARET_ASSIGN, write);
        break;
    case TK_SHL_ASSIGN:
        emit_operator(cursor, SEG_SHL_ASSIGN, write);
        break;
    case TK_SHR_ASSIGN:
        emit_operator(cursor, SEG_SHR_ASSIGN, write);
        break;
    case TK_AMP_ASSIGN:
        emit_operator(cursor, SEG_AMP_ASSIGN, write);
        break;
    case TK_PIPE_ASSIGN:
        emit_operator(cursor, SEG_PIPE_ASSIGN, write);
        break;
    case TK_INC:
        emit_operator(cursor, SEG_INC, write);
        break;
    case TK_DEC:
        emit_operator(cursor, SEG_DEC, write);
        break;

    default:
        emit_source_span(cursor, token_start(i), token_len(i), write);
        break;
    }

    if ((gParams.emit_phase == EMIT_PHASE_LEGACY ||
         gParams.emit_phase == EMIT_PHASE_TOP_LEVEL) &&
        last_top_level_token(i))
        emit_segment_id(cursor, SEG_TOP_RETURN, write);

    return cursor - base;
}

uint token_fragment_len(uint i)
{
    return emit_token_fragment(i, 0u, false);
}
