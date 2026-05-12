import utils;

struct Params
{
    uint n_tokens;
    uint source_len;
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
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_type;
StructuredBuffer<uint> enclosing_fn;

// [0] ok, [1] first error token, [2] error code, [3] detail
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint ERR_UNKNOWN_TYPE = 1u;
static const uint ERR_UNRESOLVED_IDENT = 2u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_RETURN_MISMATCH = 4u;
static const uint ERR_COND_TYPE = 5u;
static const uint ERR_BAD_HIR = 6u;
static const uint ERR_INVALID_MEMBER_ACCESS = 8u;
static const uint ERR_INVALID_ARRAY_RETURN = 9u;
static const uint ERR_CALL_MISMATCH = 10u;

static const uint HIR_FILE = 1u;
static const uint HIR_TYPE = 5u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_BREAK_STMT = 12u;
static const uint HIR_CONTINUE_STMT = 13u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_CONST_ITEM = 25u;
static const uint HIR_ENUM_ITEM = 26u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;

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
static const uint TK_ANDAND = 17u;
static const uint TK_OROR = 18u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
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
static const uint TK_PREFIX_PLUS = 58u;
static const uint TK_PREFIX_MINUS = 60u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_FN = 67u;
static const uint TK_LET = 68u;
static const uint TK_RETURN = 69u;
static const uint TK_IF = 70u;
static const uint TK_WHILE = 72u;
static const uint TK_BREAK = 73u;
static const uint TK_CONTINUE = 74u;
static const uint TK_ARROW = 75u;
static const uint TK_PARAM_LPAREN = 76u;
static const uint TK_PARAM_RPAREN = 77u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_LET_ASSIGN = 81u;
static const uint TK_ARG_COMMA = 82u;
static const uint TK_ARRAY_COMMA = 83u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;
static const uint TK_TYPE_SEMICOLON = 87u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_IF_RBRACE = 89u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_CONST = 92u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;
static const uint PARAM_CACHE_STRIDE = 16u;

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint token_kind(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].kind : 0u;
}

uint token_start(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].start : 0u;
}

uint token_len(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].len : 0u;
}

uint source_at(uint start, uint delta)
{
    uint idx = start + delta;
    return idx < gParams.source_len ? load_byte_at(source_bytes, idx) : 0u;
}

uint parse_uint_token(uint i)
{
    uint start = token_start(i);
    uint len = token_len(i);
    if (len == 0u)
        return INVALID;

    uint value = 0u;
    for (uint d = 0u; d < len; d += 1u)
    {
        uint ch = source_at(start, d);
        if (ch < 48u || ch > 57u)
            return INVALID;
        value = value * 10u + (ch - 48u);
    }
    return value;
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
    return span4(token_start(i), token_len(i), a, b, c, d);
}

bool token_text_eq5(uint i, uint a, uint b, uint c, uint d, uint e)
{
    return span5(token_start(i), token_len(i), a, b, c, d, e);
}

bool is_print_name(uint i)
{
    return token_text_eq5(i, 112u, 114u, 105u, 110u, 116u);
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

bool is_close(uint kind)
{
    return kind == TK_RPAREN || kind == TK_GROUP_RPAREN || kind == TK_CALL_RPAREN ||
           kind == TK_RBRACKET || kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET ||
           kind == TK_RBRACE || kind == TK_IF_RBRACE;
}

bool is_bool_result_operator(uint kind)
{
    return kind == TK_LT || kind == TK_GT || kind == TK_LE || kind == TK_GE || kind == TK_EQEQ ||
           kind == TK_NOT_EQUAL || kind == TK_ANDAND || kind == TK_OROR;
}

uint primitive_type_code(uint type_i)
{
    uint start = token_start(type_i);
    uint len = token_len(type_i);

    if (span2(start, len, 105u, 56u) || span3(start, len, 105u, 49u, 54u) ||
        span3(start, len, 105u, 51u, 50u) || span3(start, len, 105u, 54u, 52u) ||
        span5(start, len, 105u, 115u, 105u, 122u, 101u))
        return TY_INT;

    if (span2(start, len, 117u, 56u) || span3(start, len, 117u, 49u, 54u) ||
        span3(start, len, 117u, 51u, 50u) || span3(start, len, 117u, 54u, 52u) ||
        span5(start, len, 117u, 115u, 105u, 122u, 101u))
        return TY_UINT;

    if (span3(start, len, 102u, 51u, 50u) || span3(start, len, 102u, 54u, 52u))
        return TY_FLOAT;
    if (span4(start, len, 98u, 111u, 111u, 108u))
        return TY_BOOL;
    if (span4(start, len, 99u, 104u, 97u, 114u))
        return TY_CHAR;
    if (span3(start, len, 115u, 116u, 114u))
        return TY_STRING;

    return TY_UNKNOWN;
}

bool is_struct_type(uint ty)
{
    return ty >= TY_STRUCT_BASE && ty < TY_ENUM_BASE;
}

bool is_enum_type(uint ty)
{
    return ty >= TY_ENUM_BASE && ty < TY_GENERIC_BASE;
}

bool is_generic_type(uint ty)
{
    return ty >= TY_GENERIC_BASE;
}

bool is_array_type(uint ty)
{
    return ty >= TY_ARRAY_BASE && ty < TY_STRUCT_BASE;
}

uint struct_decl_name_from_type(uint ty)
{
    return is_struct_type(ty) ? ty - TY_STRUCT_BASE : INVALID;
}

uint enum_decl_name_from_type(uint ty)
{
    return is_enum_type(ty) ? ty - TY_ENUM_BASE : INVALID;
}

bool is_struct_decl_name_at(uint i)
{
    return token_kind(i) == TK_IDENT && i > 0u && token_kind(i - 1u) == TK_STRUCT;
}

uint find_struct_decl_name(uint name_i)
{
    uint n_active = active_token_count();
    [loop]
    for (uint j = 1u; j < n_active; j += 1u)
    {
        if (is_struct_decl_name_at(j) && same_text(j, name_i))
            return j;
    }
    return INVALID;
}

uint struct_type_code_for_name(uint name_i)
{
    uint decl_i = find_struct_decl_name(name_i);
    return decl_i == INVALID ? TY_UNKNOWN : TY_STRUCT_BASE + decl_i;
}

bool is_enum_decl_name_at(uint i)
{
    return token_kind(i) == TK_IDENT && i > 0u && token_kind(i - 1u) == TK_ENUM;
}

uint find_enum_decl_name(uint name_i)
{
    uint n_active = active_token_count();
    [loop]
    for (uint j = 1u; j < n_active; j += 1u)
    {
        if (is_enum_decl_name_at(j) && same_text(j, name_i))
            return j;
    }
    return INVALID;
}

uint enum_type_code_for_name(uint name_i)
{
    uint decl_i = find_enum_decl_name(name_i);
    return decl_i == INVALID ? TY_UNKNOWN : TY_ENUM_BASE + decl_i;
}

uint find_brace_close(uint open_i, uint limit_i)
{
    uint depth = 0u;
    uint n_active = min(limit_i, active_token_count());
    [loop]
    for (uint j = open_i; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACE || kind == TK_IF_LBRACE)
            depth += 1u;
        else if (kind == TK_RBRACE || kind == TK_IF_RBRACE)
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

uint struct_decl_open(uint decl_name_i)
{
    uint n_active = active_token_count();
    [loop]
    for (uint j = decl_name_i + 1u; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACE)
            return j;
        if (kind == TK_SEMICOLON || kind == TK_FN || kind == TK_CONST || kind == TK_ENUM ||
            kind == TK_STRUCT)
            return INVALID;
    }
    return INVALID;
}

uint struct_decl_close(uint decl_name_i)
{
    uint open_i = struct_decl_open(decl_name_i);
    return open_i == INVALID ? INVALID : find_brace_close(open_i, active_token_count());
}

uint enum_decl_open(uint decl_name_i)
{
    uint n_active = active_token_count();
    [loop]
    for (uint j = decl_name_i + 1u; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACE)
            return j;
        if (kind == TK_SEMICOLON || kind == TK_FN || kind == TK_ENUM || kind == TK_STRUCT)
            return INVALID;
    }
    return INVALID;
}

uint enum_decl_close(uint decl_name_i)
{
    uint open_i = enum_decl_open(decl_name_i);
    return open_i == INVALID ? INVALID : find_brace_close(open_i, active_token_count());
}

uint enum_type_for_variant_decl(uint variant_i)
{
    uint j = variant_i;
    [loop]
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        j -= 1u;
        if (!is_enum_decl_name_at(j))
            continue;
        uint open_i = enum_decl_open(j);
        uint close_i = enum_decl_close(j);
        if (open_i != INVALID && close_i != INVALID && variant_i > open_i && variant_i < close_i)
            return TY_ENUM_BASE + j;
    }
    return TY_UNKNOWN;
}

uint find_enum_variant_decl(uint name_i)
{
    uint n_active = active_token_count();
    [loop]
    for (uint enum_name_i = 1u; enum_name_i < n_active; enum_name_i += 1u)
    {
        if (!is_enum_decl_name_at(enum_name_i))
            continue;
        bool in_body = false;
        [loop]
        for (uint j = enum_name_i + 1u; j < n_active; j += 1u)
        {
            uint kind = token_kind(j);
            if (!in_body)
            {
                if (kind == TK_LBRACE)
                    in_body = true;
                else if (kind == TK_SEMICOLON || kind == TK_FN || kind == TK_ENUM ||
                         kind == TK_STRUCT)
                    break;
                continue;
            }
            if (kind == TK_RBRACE)
                break;
            uint prev = j > 0u ? token_kind(j - 1u) : 0u;
            if (kind == TK_IDENT && same_text(j, name_i) &&
                (prev == TK_LBRACE || prev == TK_COMMA || prev == TK_ARG_COMMA))
                return j;
        }
    }
    return INVALID;
}

uint enum_type_for_variant_name(uint name_i)
{
    uint variant_i = find_enum_variant_decl(name_i);
    return variant_i == INVALID ? TY_UNKNOWN : enum_type_for_variant_decl(variant_i);
}

uint generic_param_list_open(uint item_i)
{
    uint n_active = active_token_count();
    [loop]
    for (uint j = item_i + 1u; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT)
            return j;
        if (kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_LPAREN ||
            kind == TK_PARAM_LPAREN || kind == TK_SEMICOLON)
            return INVALID;
    }
    return INVALID;
}

uint generic_param_list_close(uint open_i)
{
    uint n_active = active_token_count();
    uint depth = 0u;
    [loop]
    for (uint j = open_i; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT)
            depth += 1u;
        else if (kind == TK_GT)
        {
            if (depth == 0u)
                return INVALID;
            depth -= 1u;
            if (depth == 0u)
                return j;
        }
        else if (kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_SEMICOLON)
        {
            return INVALID;
        }
    }
    return INVALID;
}

uint generic_item_end(uint item_i)
{
    uint n_active = active_token_count();
    [loop]
    for (uint j = item_i + 1u; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACE || kind == TK_IF_LBRACE)
            return find_brace_close(j, n_active);
        if (kind == TK_SEMICOLON)
            return j;
    }
    return INVALID;
}

bool is_type_generic_param_token(uint param_i, uint open_i, uint close_i)
{
    uint kind = token_kind(param_i);
    if (param_i <= open_i || param_i >= close_i ||
        (kind != TK_IDENT && kind != TK_TYPE_IDENT && kind != TK_PARAM_IDENT))
        return false;
    if (param_i > open_i + 1u && token_kind(param_i - 1u) == TK_CONST)
        return false;
    if (param_i + 1u < close_i && token_kind(param_i + 1u) == TK_COLON)
        return false;
    return true;
}

uint find_generic_type_param_decl(uint name_i)
{
    uint j = name_i;
    [loop]
    for (uint guard = 0u; guard < 256u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind != TK_FN && kind != TK_ENUM && kind != TK_STRUCT)
            continue;

        uint item_end = generic_item_end(j);
        if (item_end != INVALID && name_i > item_end)
            continue;

        uint open_i = generic_param_list_open(j);
        if (open_i == INVALID)
            continue;
        uint close_i = generic_param_list_close(open_i);
        if (close_i == INVALID)
            continue;
        [loop]
        for (uint p = open_i + 1u; p < close_i; p += 1u)
        {
            if (is_type_generic_param_token(p, open_i, close_i) && same_text(p, name_i))
                return p;
        }
    }
    return INVALID;
}

uint generic_type_code_for_name(uint name_i)
{
    uint decl_i = find_generic_type_param_decl(name_i);
    return decl_i == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + decl_i;
}

uint type_code_for_type_expr(uint type_i)
{
    uint cur = type_i;
    uint array_depth = 0u;
    uint n_active = active_token_count();
    for (uint guard = 0u; guard < 16u && cur < n_active; guard += 1u)
    {
        uint kind = token_kind(cur);
        if (kind != TK_TYPE_ARRAY_LBRACKET && kind != TK_ARRAY_LBRACKET && kind != TK_LBRACKET)
            break;
        array_depth += 1u;
        cur += 1u;
    }

    uint kind = token_kind(cur);
    uint elem = TY_UNKNOWN;
    if (kind == TK_TYPE_IDENT || kind == TK_IDENT)
    {
        elem = primitive_type_code(cur);
        if (elem == TY_UNKNOWN)
            elem = generic_type_code_for_name(cur);
        if (elem == TY_UNKNOWN && array_depth == 0u)
            elem = struct_type_code_for_name(cur);
        if (elem == TY_UNKNOWN && array_depth == 0u)
            elem = enum_type_code_for_name(cur);
    }

    if (elem == TY_UNKNOWN)
        return TY_UNKNOWN;
    if (array_depth > 0u && (is_struct_type(elem) || is_enum_type(elem) || is_generic_type(elem)))
        return TY_UNKNOWN;
    return array_depth == 0u ? elem : TY_ARRAY_BASE + elem;
}

uint struct_field_type(uint struct_ty, uint member_i)
{
    uint decl_name_i = struct_decl_name_from_type(struct_ty);
    if (decl_name_i == INVALID)
        return TY_UNKNOWN;
    uint open_i = struct_decl_open(decl_name_i);
    uint close_i = struct_decl_close(decl_name_i);
    if (open_i == INVALID || close_i == INVALID)
        return TY_UNKNOWN;

    [loop]
    for (uint j = open_i + 1u; j + 2u < close_i; j += 1u)
    {
        if ((token_kind(j) == TK_IDENT || token_kind(j) == TK_TYPE_IDENT) &&
            token_kind(j + 1u) == TK_COLON && same_text(j, member_i))
            return type_code_for_type_expr(j + 2u);
    }
    return TY_UNKNOWN;
}

uint type_array_decl_len(uint type_i, uint limit_i)
{
    uint first = token_kind(type_i);
    if (first != TK_TYPE_ARRAY_LBRACKET && first != TK_ARRAY_LBRACKET && first != TK_LBRACKET)
        return INVALID;

    uint depth = 0u;
    uint n_active = min(limit_i, active_token_count());
    for (uint j = type_i; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_TYPE_ARRAY_LBRACKET || kind == TK_ARRAY_LBRACKET || kind == TK_LBRACKET)
            depth += 1u;
        else if (kind == TK_TYPE_ARRAY_RBRACKET || kind == TK_ARRAY_RBRACKET ||
                 kind == TK_RBRACKET)
        {
            if (depth == 0u)
                return INVALID;
            depth -= 1u;
            if (depth == 0u)
                return INVALID;
        }
        else if ((kind == TK_TYPE_SEMICOLON || kind == TK_SEMICOLON) && depth == 1u)
        {
            return parse_uint_token(j + 1u);
        }
    }
    return INVALID;
}

uint find_stmt_semicolon(uint start_i)
{
    uint bracket_depth = 0u;
    uint n_active = active_token_count();
    for (uint j = start_i + 1u; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACKET || kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET ||
            kind == TK_TYPE_ARRAY_LBRACKET)
        {
            bracket_depth += 1u;
        }
        else if (kind == TK_RBRACKET || kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET ||
                 kind == TK_TYPE_ARRAY_RBRACKET)
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

uint stmt_semicolon_from_hir_end(uint start_i, uint end_i)
{
    if (end_i != INVALID && end_i > start_i)
    {
        uint semi = end_i - 1u;
        if (token_kind(semi) == TK_SEMICOLON)
            return semi;
    }
    return find_stmt_semicolon(start_i);
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

bool is_const_decl_at(uint i)
{
    return token_kind(i) == TK_IDENT && i > 0u && token_kind(i - 1u) == TK_CONST;
}

uint find_function_return_type(uint fn_i)
{
    return fn_i < active_token_count() ? call_return_type[fn_i] : TY_UNKNOWN;
}

uint find_named_function_return(uint name_i)
{
    return name_i < active_token_count() ? call_return_type[name_i] : TY_UNKNOWN;
}

uint find_named_function(uint name_i)
{
    return name_i < active_token_count() ? call_fn_index[name_i] : INVALID;
}

uint literal_head_type(uint expr_i, uint limit_i)
{
    uint cur = expr_i;
    uint n_active = active_token_count();
    for (uint guard = 0u; guard < 16u && cur < limit_i && cur < n_active; guard += 1u)
    {
        uint kind = token_kind(cur);
        if (kind == TK_GROUP_LPAREN || kind == TK_LPAREN || kind == TK_PREFIX_PLUS ||
            kind == TK_PREFIX_MINUS)
        {
            cur += 1u;
            continue;
        }

        if (kind == TK_INT)
            return TY_INT;
        if (kind == TK_TRUE || kind == TK_FALSE)
            return TY_BOOL;
        if (kind == TK_FLOAT)
            return TY_FLOAT;
        if (kind == TK_STRING)
            return TY_STRING;
        if (kind == TK_CHAR)
            return TY_CHAR;
        if (kind == TK_IDENT && cur + 1u < limit_i && token_kind(cur + 1u) == TK_LBRACE)
            return struct_type_code_for_name(cur);
        if (kind == TK_IDENT)
        {
            uint variant_ty = enum_type_for_variant_name(cur);
            if (variant_ty != TY_UNKNOWN)
            {
                uint variant_decl = find_enum_variant_decl(cur);
                if (variant_decl != INVALID &&
                    !(variant_decl + 1u < active_token_count() &&
                      is_group_open_kind(token_kind(variant_decl + 1u))))
                    return variant_ty;
            }
        }
        if (kind == TK_ARRAY_LBRACKET || kind == TK_LBRACKET)
        {
            uint elem_cur = cur + 1u;
            for (uint elem_guard = 0u;
                 elem_guard < 16u && elem_cur < limit_i && elem_cur < n_active;
                 elem_guard += 1u)
            {
                uint elem_kind = token_kind(elem_cur);
                if (elem_kind == TK_GROUP_LPAREN || elem_kind == TK_LPAREN ||
                    elem_kind == TK_PREFIX_PLUS || elem_kind == TK_PREFIX_MINUS)
                {
                    elem_cur += 1u;
                    continue;
                }
                if (elem_kind == TK_INT)
                    return TY_ARRAY_BASE + TY_INT;
                if (elem_kind == TK_TRUE || elem_kind == TK_FALSE)
                    return TY_ARRAY_BASE + TY_BOOL;
                if (elem_kind == TK_FLOAT)
                    return TY_ARRAY_BASE + TY_FLOAT;
                if (elem_kind == TK_STRING)
                    return TY_ARRAY_BASE + TY_STRING;
                if (elem_kind == TK_CHAR)
                    return TY_ARRAY_BASE + TY_CHAR;
                break;
            }
            return TY_UNKNOWN;
        }
        return TY_UNKNOWN;
    }
    return TY_UNKNOWN;
}

uint struct_literal_head_type(uint expr_i, uint limit_i)
{
    uint cur = expr_i;
    uint n_active = active_token_count();
    for (uint guard = 0u; guard < 16u && cur < limit_i && cur < n_active; guard += 1u)
    {
        uint kind = token_kind(cur);
        if (kind == TK_GROUP_LPAREN || kind == TK_LPAREN || kind == TK_PREFIX_PLUS ||
            kind == TK_PREFIX_MINUS)
        {
            cur += 1u;
            continue;
        }
        if (kind == TK_IDENT && cur + 1u < limit_i && token_kind(cur + 1u) == TK_LBRACE)
            return struct_type_code_for_name(cur);
        return TY_UNKNOWN;
    }
    return TY_UNKNOWN;
}

uint scanned_expr_result_type(uint expr_i, uint limit_i)
{
    bool saw_float = false;
    uint n_active = active_token_count();
    for (uint j = expr_i; j < limit_i && j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_bool_result_operator(kind))
            return TY_BOOL;
        if (kind == TK_FLOAT)
            saw_float = true;
    }
    return saw_float ? TY_FLOAT : TY_UNKNOWN;
}

uint declaration_type_shallow(uint decl_i)
{
    uint kind = token_kind(decl_i);
    if (kind == TK_PARAM_IDENT ||
        (kind == TK_IDENT && decl_i + 1u < active_token_count() &&
         token_kind(decl_i + 1u) == TK_COLON &&
         (decl_i == 0u ||
          (token_kind(decl_i - 1u) != TK_LET && token_kind(decl_i - 1u) != TK_CONST &&
           token_kind(decl_i - 1u) != TK_ENUM && token_kind(decl_i - 1u) != TK_STRUCT))))
        return type_code_for_type_expr(decl_i + 2u);

    if (is_const_decl_at(decl_i))
        return type_code_for_type_expr(decl_i + 2u);

    if (kind == TK_LET_IDENT ||
        (kind == TK_IDENT && decl_i > 0u && token_kind(decl_i - 1u) == TK_LET))
    {
        if (token_kind(decl_i + 1u) == TK_COLON)
            return type_code_for_type_expr(decl_i + 2u);

        uint semi = find_stmt_semicolon(decl_i);
        if (semi == INVALID)
            return TY_UNKNOWN;
        uint assign_i = find_let_assign(decl_i, semi);
        if (assign_i == INVALID || assign_i + 1u >= semi)
            return TY_UNKNOWN;
        uint struct_head = struct_literal_head_type(assign_i + 1u, semi);
        if (struct_head != TY_UNKNOWN)
            return struct_head;
        uint scanned = scanned_expr_result_type(assign_i + 1u, semi);
        if (scanned != TY_UNKNOWN)
            return scanned;

        uint head = literal_head_type(assign_i + 1u, semi);
        if (head != TY_UNKNOWN)
            return head;

        uint cur = assign_i + 1u;
        uint n_active = active_token_count();
        for (uint guard = 0u; guard < 16u && cur < semi && cur < n_active; guard += 1u)
        {
            uint head_kind = token_kind(cur);
            if (head_kind == TK_GROUP_LPAREN || head_kind == TK_LPAREN ||
                head_kind == TK_PREFIX_PLUS || head_kind == TK_PREFIX_MINUS)
            {
                cur += 1u;
                continue;
            }
            if (head_kind == TK_IDENT && cur + 1u < semi &&
                (token_kind(cur + 1u) == TK_CALL_LPAREN || token_kind(cur + 1u) == TK_LPAREN))
            {
                if (is_builtin_name(cur))
                    return TY_VOID;
                uint fn_ret = find_named_function_return(cur);
                if (fn_ret != TY_UNKNOWN)
                    return fn_ret;
                return enum_type_for_variant_name(cur);
            }
            break;
        }
    }

    return TY_UNKNOWN;
}

uint visible_type_for(uint ident_i)
{
    return ident_i < active_token_count() ? visible_type[ident_i] : TY_UNKNOWN;
}

uint visible_decl_for(uint ident_i)
{
    return ident_i < active_token_count() ? visible_decl[ident_i] : INVALID;
}

uint declaration_type(uint decl_i)
{
    uint cached = visible_type_for(decl_i);
    if (cached != TY_UNKNOWN)
        return cached;

    uint shallow = declaration_type_shallow(decl_i);
    if (shallow != TY_UNKNOWN)
        return shallow;

        if (token_kind(decl_i) == TK_LET_IDENT ||
            (token_kind(decl_i) == TK_IDENT && decl_i > 0u && token_kind(decl_i - 1u) == TK_LET))
    {
        uint semi = find_stmt_semicolon(decl_i);
        if (semi == INVALID)
            return TY_UNKNOWN;
        uint assign_i = find_let_assign(decl_i, semi);
        if (assign_i == INVALID || assign_i + 1u >= semi)
            return TY_UNKNOWN;

        for (uint j = assign_i + 1u; j < semi; j += 1u)
        {
            if (token_kind(j) == TK_IDENT && same_text(j, decl_i))
                return TY_UNKNOWN;
        }

        uint cur = assign_i + 1u;
        uint n_active = active_token_count();
        for (uint guard = 0u; guard < 16u && cur < semi && cur < n_active; guard += 1u)
        {
            uint head_kind = token_kind(cur);
            if (head_kind == TK_GROUP_LPAREN || head_kind == TK_LPAREN ||
                head_kind == TK_PREFIX_PLUS || head_kind == TK_PREFIX_MINUS)
            {
                cur += 1u;
                continue;
        }
        if (head_kind == TK_IDENT &&
            !(cur + 1u < semi &&
              (token_kind(cur + 1u) == TK_CALL_LPAREN || token_kind(cur + 1u) == TK_LPAREN)))
        {
            uint ty = visible_type_for(cur);
            if (ty != TY_UNKNOWN)
                return ty;
        }
        break;
    }
    }

    return TY_UNKNOWN;
}

bool is_open_block_token(uint kind)
{
    return kind == TK_LBRACE || kind == TK_IF_LBRACE;
}

bool is_close_block_token(uint kind)
{
    return kind == TK_RBRACE || kind == TK_IF_RBRACE;
}

uint enclosing_function_start(uint target_i)
{
    if (target_i >= active_token_count())
        return INVALID;
    uint encoded = enclosing_fn[target_i];
    return encoded == 0u ? INVALID : encoded - 1u;
}

uint identifier_type(uint ident_i)
{
    return visible_type_for(ident_i);
}

bool identifier_decl_exists(uint ident_i)
{
    return visible_decl_for(ident_i) != INVALID;
}

uint indexed_element_type(uint base_ty)
{
    return is_array_type(base_ty) ? base_ty - TY_ARRAY_BASE : TY_UNKNOWN;
}

bool is_group_open_kind(uint kind)
{
    return kind == TK_GROUP_LPAREN || kind == TK_LPAREN || kind == TK_CALL_LPAREN ||
           kind == TK_PARAM_LPAREN;
}

bool is_group_close_kind(uint kind)
{
    return kind == TK_GROUP_RPAREN || kind == TK_RPAREN || kind == TK_CALL_RPAREN ||
           kind == TK_PARAM_RPAREN;
}

bool is_index_open_kind(uint kind)
{
    return kind == TK_INDEX_LBRACKET || kind == TK_LBRACKET;
}

bool is_index_close_kind(uint kind)
{
    return kind == TK_INDEX_RBRACKET || kind == TK_RBRACKET;
}

uint find_group_close(uint open_i, uint limit_i)
{
    uint depth = 0u;
    uint n_active = active_token_count();
    for (uint j = open_i; j < limit_i && j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            depth += 1u;
        else if (is_group_close_kind(kind))
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

uint grouped_index_base_type(uint expr_i, uint limit_i)
{
    uint cur = expr_i;
    uint n_active = active_token_count();
    for (uint guard = 0u; guard < 16u && cur < limit_i && cur < n_active; guard += 1u)
    {
        uint kind = token_kind(cur);
        if (is_group_open_kind(kind) || kind == TK_PREFIX_PLUS || kind == TK_PREFIX_MINUS)
        {
            cur += 1u;
            continue;
        }
        if (kind == TK_ARRAY_LBRACKET || kind == TK_LBRACKET)
            return TY_ARRAY_BASE + TY_INT;
        if (kind == TK_IDENT)
            return identifier_type(cur);
        return literal_head_type(cur, limit_i);
    }
    return TY_UNKNOWN;
}

uint simple_expr_type(uint expr_i, uint limit_i)
{
    uint cur = expr_i;
    uint struct_head = struct_literal_head_type(expr_i, limit_i);
    if (struct_head != TY_UNKNOWN)
        return struct_head;

    uint scanned = scanned_expr_result_type(expr_i, limit_i);
    if (scanned != TY_UNKNOWN)
        return scanned;

    uint n_active = active_token_count();
    for (uint guard = 0u; guard < 16u && cur < limit_i && cur < n_active; guard += 1u)
    {
        uint head_kind = token_kind(cur);
        if (is_group_open_kind(head_kind))
        {
            uint close_i = find_group_close(cur, limit_i);
            if (close_i != INVALID && close_i + 1u < limit_i &&
                (token_kind(close_i + 1u) == TK_INDEX_LBRACKET ||
                 token_kind(close_i + 1u) == TK_LBRACKET))
            {
                return indexed_element_type(grouped_index_base_type(cur + 1u, close_i));
            }
            cur += 1u;
            continue;
        }
        if (head_kind == TK_PREFIX_PLUS || head_kind == TK_PREFIX_MINUS)
        {
            cur += 1u;
            continue;
        }

        uint head = literal_head_type(cur, limit_i);
        if (head != TY_UNKNOWN)
            return head;

        break;
    }

    if (cur >= limit_i || cur >= n_active)
        return TY_UNKNOWN;

    uint kind = token_kind(cur);
    if (kind == TK_IDENT)
    {
        if (cur + 1u < limit_i && token_kind(cur + 1u) == TK_LBRACE)
            return struct_type_code_for_name(cur);

        if (cur + 2u < limit_i && token_kind(cur + 1u) == TK_DOT &&
            token_kind(cur + 2u) == TK_IDENT)
        {
            uint member_ty = visible_type_for(cur + 2u);
            if (member_ty != TY_UNKNOWN)
                return member_ty;
            return struct_field_type(identifier_type(cur), cur + 2u);
        }

        if (cur + 1u < limit_i &&
            (token_kind(cur + 1u) == TK_CALL_LPAREN || token_kind(cur + 1u) == TK_LPAREN))
        {
            if (is_builtin_name(cur))
                return TY_VOID;
            uint fn_ret = find_named_function_return(cur);
            if (fn_ret != TY_UNKNOWN)
                return fn_ret;
            return enum_type_for_variant_name(cur);
        }

        uint variant_ty = enum_type_for_variant_name(cur);
        if (variant_ty != TY_UNKNOWN)
        {
            uint variant_decl = find_enum_variant_decl(cur);
            if (variant_decl != INVALID &&
                !(variant_decl + 1u < n_active && is_group_open_kind(token_kind(variant_decl + 1u))))
                return variant_ty;
        }

        uint ty = identifier_type(cur);
        if (cur + 1u < limit_i &&
            (token_kind(cur + 1u) == TK_INDEX_LBRACKET || token_kind(cur + 1u) == TK_LBRACKET))
            return indexed_element_type(ty);
        return ty;
    }

    return TY_UNKNOWN;
}

bool assignable(uint dst, uint src)
{
    if (dst == TY_UNKNOWN || src == TY_UNKNOWN)
        return true;
    if (dst == src)
        return true;
    if (dst == TY_INT)
        return src == TY_UINT || src == TY_CHAR;
    if (dst == TY_UINT)
        return src == TY_INT || src == TY_CHAR;
    if (dst == TY_FLOAT)
        return src == TY_INT || src == TY_UINT || src == TY_CHAR;
    if (dst == TY_CHAR)
        return src == TY_INT || src == TY_UINT;
    if (is_array_type(dst) || is_array_type(src) || is_struct_type(dst) || is_struct_type(src) ||
        is_enum_type(dst) || is_enum_type(src) || is_generic_type(dst) || is_generic_type(src))
        return dst == src;
    return false;
}

bool is_numeric_scalar_type(uint ty)
{
    return ty == TY_UNKNOWN || ty == TY_INT || ty == TY_UINT || ty == TY_FLOAT || ty == TY_CHAR;
}

bool is_integer_scalar_type(uint ty)
{
    return ty == TY_UNKNOWN || ty == TY_INT || ty == TY_UINT || ty == TY_CHAR;
}

bool is_assignment_operator(uint kind)
{
    return kind == TK_ASSIGN || kind == TK_PLUS_ASSIGN || kind == TK_MINUS_ASSIGN ||
           kind == TK_STAR_ASSIGN || kind == TK_SLASH_ASSIGN || kind == TK_PERCENT_ASSIGN ||
           kind == TK_CARET_ASSIGN || kind == TK_SHL_ASSIGN || kind == TK_SHR_ASSIGN ||
           kind == TK_AMP_ASSIGN || kind == TK_PIPE_ASSIGN;
}

bool compound_assignment_compatible(uint op, uint dst, uint src)
{
    if (op == TK_ASSIGN)
        return assignable(dst, src);
    if (dst == TY_UNKNOWN || src == TY_UNKNOWN)
        return true;

    if (op == TK_PLUS_ASSIGN || op == TK_MINUS_ASSIGN || op == TK_STAR_ASSIGN ||
        op == TK_SLASH_ASSIGN)
        return is_numeric_scalar_type(dst) && is_numeric_scalar_type(src) && assignable(dst, src);

    if (op == TK_PERCENT_ASSIGN || op == TK_CARET_ASSIGN || op == TK_SHL_ASSIGN ||
        op == TK_SHR_ASSIGN || op == TK_AMP_ASSIGN || op == TK_PIPE_ASSIGN)
        return is_integer_scalar_type(dst) && is_integer_scalar_type(src) && assignable(dst, src);

    return false;
}

void assignment_target_info(uint assign_i, out bool is_lvalue, out uint target_ty)
{
    is_lvalue = false;
    target_ty = TY_UNKNOWN;
    if (assign_i == 0u)
        return;

    uint prev_i = assign_i - 1u;
    uint prev = token_kind(prev_i);
    if (prev == TK_IDENT)
    {
        if (assign_i >= 3u && token_kind(assign_i - 2u) == TK_DOT &&
            token_kind(assign_i - 3u) == TK_IDENT)
        {
            uint base_decl = visible_decl_for(assign_i - 3u);
            if (is_const_decl_at(base_decl))
                return;
            uint field_ty = struct_field_type(identifier_type(assign_i - 3u), prev_i);
            if (field_ty == TY_UNKNOWN)
                return;
            is_lvalue = true;
            target_ty = field_ty;
            return;
        }
        uint decl = visible_decl_for(prev_i);
        if (is_const_decl_at(decl))
            return;
        is_lvalue = true;
        target_ty = identifier_type(prev_i);
        return;
    }

    if (prev == TK_INDEX_RBRACKET || prev == TK_RBRACKET)
    {
        uint j = prev_i;
        while (j > 0u)
        {
            j -= 1u;
            if (token_kind(j) != TK_INDEX_LBRACKET && token_kind(j) != TK_LBRACKET)
                continue;
            if (j > 0u && token_kind(j - 1u) == TK_IDENT)
            {
                is_lvalue = true;
                target_ty = indexed_element_type(identifier_type(j - 1u));
            }
            return;
        }
    }
}

bool array_literal_is_let_initializer(uint open_i)
{
    if (open_i == 0u)
        return false;

    uint assign_i = open_i - 1u;
    uint assign_kind = token_kind(assign_i);
    if (assign_kind != TK_ASSIGN && assign_kind != TK_LET_ASSIGN)
        return false;

    uint j = assign_i;
    uint bracket_depth = 0u;
    [loop]
    for (uint guard = 0u; guard < 128u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind == TK_RBRACKET || kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET ||
            kind == TK_TYPE_ARRAY_RBRACKET)
        {
            bracket_depth += 1u;
            continue;
        }
        if (kind == TK_LBRACKET || kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET ||
            kind == TK_TYPE_ARRAY_LBRACKET)
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
            (kind == TK_SEMICOLON || kind == TK_LBRACE || kind == TK_IF_LBRACE ||
             kind == TK_RBRACE || kind == TK_IF_RBRACE || kind == TK_FN))
            return false;
    }

    return false;
}

uint find_call_close(uint call_lparen_i)
{
    uint n_active = active_token_count();
    uint depth = 0u;
    for (uint j = call_lparen_i; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_CALL_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_LPAREN)
            depth += 1u;
        else if (kind == TK_CALL_RPAREN || kind == TK_GROUP_RPAREN || kind == TK_RPAREN)
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

uint find_index_open_for_close(uint close_i)
{
    if (close_i >= active_token_count() || !is_index_close_kind(token_kind(close_i)))
        return INVALID;

    uint depth = 1u;
    uint j = close_i;
    for (uint guard = 0u; guard < 128u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (is_index_close_kind(kind) || kind == TK_ARRAY_RBRACKET)
        {
            depth += 1u;
            continue;
        }
        if (is_index_open_kind(kind) || kind == TK_ARRAY_LBRACKET)
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

uint find_index_close(uint open_i, uint limit_i)
{
    uint depth = 0u;
    uint n_active = min(limit_i, active_token_count());
    for (uint j = open_i; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_index_open_kind(kind) || kind == TK_ARRAY_LBRACKET)
            depth += 1u;
        else if (is_index_close_kind(kind) || kind == TK_ARRAY_RBRACKET)
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

uint index_base_type(uint open_i)
{
    if (open_i == 0u)
        return TY_UNKNOWN;

    uint base_i = open_i - 1u;
    uint base_kind = token_kind(base_i);
    if (base_kind == TK_IDENT)
        return identifier_type(base_i);
    return TY_UNKNOWN;
}

bool check_index(uint open_i, uint end_i)
{
    if (open_i == INVALID || !is_index_open_kind(token_kind(open_i)))
        return true;

    uint close_i = INVALID;
    if (end_i != INVALID && end_i > open_i)
    {
        uint candidate = end_i - 1u;
        if (is_index_close_kind(token_kind(candidate)))
            close_i = candidate;
    }
    if (close_i == INVALID)
        close_i = find_index_close(open_i, end_i == INVALID ? active_token_count() : end_i);
    if (close_i == INVALID || close_i <= open_i)
        return true;

    uint base_ty = index_base_type(open_i);
    if (base_ty != TY_UNKNOWN && !is_array_type(base_ty))
    {
        record_error(open_i, ERR_ASSIGN_MISMATCH, base_ty);
        return false;
    }

    uint index_ty = simple_expr_type(open_i + 1u, close_i);
    if (!is_integer_scalar_type(index_ty))
    {
        record_error(open_i + 1u, ERR_ASSIGN_MISMATCH, TY_INT * 256u + index_ty);
        return false;
    }
    return true;
}

void check_assignment(uint assign_i, uint end_i)
{
    uint semi = stmt_semicolon_from_hir_end(assign_i, end_i);
    if (semi == INVALID || assign_i + 1u >= semi)
        return;

    bool is_lvalue = false;
    uint dst = TY_UNKNOWN;
    assignment_target_info(assign_i, is_lvalue, dst);
    if (assign_i > 0u && is_index_close_kind(token_kind(assign_i - 1u)))
    {
        uint open_i = find_index_open_for_close(assign_i - 1u);
        if (open_i != INVALID && !check_index(open_i, assign_i))
            return;
    }
    if (!is_lvalue)
    {
        record_error(assign_i, ERR_ASSIGN_MISMATCH, 0u);
        return;
    }

    uint src = simple_expr_type(assign_i + 1u, semi);
    if (is_array_type(dst))
    {
        record_error(assign_i, ERR_ASSIGN_MISMATCH, dst);
        return;
    }
    if (!compound_assignment_compatible(token_kind(assign_i), dst, src))
        record_error(assign_i + 1u, ERR_ASSIGN_MISMATCH, dst * 256u + src);
}

uint find_array_literal_close(uint open_i, uint limit_i)
{
    uint depth = 0u;
    for (uint j = open_i; j < limit_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_ARRAY_LBRACKET || kind == TK_LBRACKET)
            depth += 1u;
        else if (kind == TK_ARRAY_RBRACKET || kind == TK_RBRACKET)
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

uint array_elem_end(uint elem_start_i, uint close_i)
{
    uint bracket_depth = 0u;
    uint group_depth = 0u;
    for (uint j = elem_start_i; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if (kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET ||
                 kind == TK_LBRACKET)
            bracket_depth += 1u;
        else if ((kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET ||
                  kind == TK_RBRACKET) &&
                 bracket_depth > 0u)
            bracket_depth -= 1u;
        else if ((kind == TK_ARRAY_COMMA || kind == TK_COMMA) && bracket_depth == 0u &&
                 group_depth == 0u)
            return j;
    }
    return close_i;
}

uint array_literal_len(uint open_i, uint close_i)
{
    if (open_i == INVALID || close_i == INVALID || open_i + 1u >= close_i)
        return 0u;

    uint bracket_depth = 0u;
    uint group_depth = 0u;
    uint count = 1u;
    for (uint j = open_i + 1u; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if (kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET ||
                 kind == TK_LBRACKET)
            bracket_depth += 1u;
        else if ((kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET ||
                  kind == TK_RBRACKET) &&
                 bracket_depth > 0u)
            bracket_depth -= 1u;
        else if ((kind == TK_ARRAY_COMMA || kind == TK_COMMA) && bracket_depth == 0u &&
                 group_depth == 0u)
            count += 1u;
    }
    return count;
}

void check_array_literal_elements(uint open_i, uint close_i, uint elem_ty)
{
    if (open_i == INVALID || close_i == INVALID || elem_ty == TY_UNKNOWN)
        return;

    uint elem_start = open_i + 1u;
    for (uint guard = 0u; guard < 64u && elem_start < close_i; guard += 1u)
    {
        uint elem_end = array_elem_end(elem_start, close_i);
        if (elem_end <= elem_start)
            return;
        uint actual = simple_expr_type(elem_start, elem_end);
        if (!assignable(elem_ty, actual))
        {
            record_error(elem_start, ERR_ASSIGN_MISMATCH, elem_ty * 256u + actual);
            return;
        }
        elem_start = elem_end + 1u;
    }
}

uint struct_literal_field_value_end(uint value_start_i, uint close_i)
{
    uint bracket_depth = 0u;
    uint group_depth = 0u;
    uint brace_depth = 0u;
    for (uint j = value_start_i; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if (kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET ||
                 kind == TK_LBRACKET)
            bracket_depth += 1u;
        else if ((kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET ||
                  kind == TK_RBRACKET) &&
                 bracket_depth > 0u)
            bracket_depth -= 1u;
        else if (kind == TK_LBRACE || kind == TK_IF_LBRACE)
            brace_depth += 1u;
        else if ((kind == TK_RBRACE || kind == TK_IF_RBRACE) && brace_depth > 0u)
            brace_depth -= 1u;
        else if ((kind == TK_ARG_COMMA || kind == TK_COMMA) && bracket_depth == 0u &&
                 group_depth == 0u && brace_depth == 0u)
            return j;
    }
    return close_i;
}

bool struct_literal_has_field(uint open_i, uint close_i, uint decl_field_i)
{
    uint field_i = open_i + 1u;
    [loop]
    for (uint guard = 0u; guard < 64u && field_i < close_i; guard += 1u)
    {
        if ((token_kind(field_i) == TK_IDENT || token_kind(field_i) == TK_TYPE_IDENT) &&
            same_text(field_i, decl_field_i))
            return true;
        if (field_i + 1u >= close_i || token_kind(field_i + 1u) != TK_COLON)
            return false;
        uint value_end = struct_literal_field_value_end(field_i + 2u, close_i);
        if (value_end <= field_i)
            return false;
        field_i = value_end + 1u;
    }
    return false;
}

void check_struct_literal_required_fields(uint open_i, uint close_i, uint struct_ty)
{
    uint decl_name_i = struct_decl_name_from_type(struct_ty);
    uint decl_open = struct_decl_open(decl_name_i);
    uint decl_close = struct_decl_close(decl_name_i);
    if (decl_open == INVALID || decl_close == INVALID)
        return;

    [loop]
    for (uint j = decl_open + 1u; j + 2u < decl_close; j += 1u)
    {
        if (!((token_kind(j) == TK_IDENT || token_kind(j) == TK_TYPE_IDENT) &&
              token_kind(j + 1u) == TK_COLON))
            continue;
        if (!struct_literal_has_field(open_i, close_i, j))
        {
            record_error(open_i, ERR_INVALID_MEMBER_ACCESS, j);
            return;
        }
    }
}

void check_struct_literal(uint open_i, uint end_i)
{
    if (open_i == 0u || token_kind(open_i) != TK_LBRACE || token_kind(open_i - 1u) != TK_IDENT)
    {
        record_error(open_i, ERR_BAD_HIR, HIR_STRUCT_LITERAL_EXPR);
        return;
    }

    uint struct_ty = struct_type_code_for_name(open_i - 1u);
    if (struct_ty == TY_UNKNOWN)
    {
        record_error(open_i - 1u, ERR_UNKNOWN_TYPE, 0u);
        return;
    }

    uint close_i = INVALID;
    if (end_i != INVALID && end_i > open_i)
    {
        uint candidate = end_i - 1u;
        if (token_kind(candidate) == TK_RBRACE)
            close_i = candidate;
    }
    if (close_i == INVALID)
        close_i = find_brace_close(open_i, active_token_count());
    if (close_i == INVALID)
    {
        record_error(open_i, ERR_BAD_HIR, HIR_STRUCT_LITERAL_EXPR);
        return;
    }

    uint field_i = open_i + 1u;
    [loop]
    for (uint guard = 0u; guard < 64u && field_i < close_i; guard += 1u)
    {
        if (!((token_kind(field_i) == TK_IDENT || token_kind(field_i) == TK_TYPE_IDENT) &&
              field_i + 2u < close_i && token_kind(field_i + 1u) == TK_COLON))
        {
            record_error(field_i, ERR_BAD_HIR, HIR_STRUCT_LITERAL_EXPR);
            return;
        }

        uint expected = struct_field_type(struct_ty, field_i);
        uint resolved_expected = visible_type_for(field_i);
        if (resolved_expected != TY_UNKNOWN)
            expected = resolved_expected;
        if (expected == TY_UNKNOWN)
        {
            record_error(field_i, ERR_INVALID_MEMBER_ACCESS, struct_ty);
            return;
        }

        uint value_start = field_i + 2u;
        uint value_end = struct_literal_field_value_end(value_start, close_i);
        if (value_end <= value_start)
        {
            record_error(field_i, ERR_BAD_HIR, HIR_STRUCT_LITERAL_EXPR);
            return;
        }
        uint actual = simple_expr_type(value_start, value_end);
        if (!assignable(expected, actual))
        {
            record_error(value_start, ERR_ASSIGN_MISMATCH, expected * 256u + actual);
            return;
        }
        field_i = value_end + 1u;
    }

    check_struct_literal_required_fields(open_i, close_i, struct_ty);
}

uint array_literal_element_type(uint open_i, uint close_i, uint array_ty)
{
    uint elem_ty = indexed_element_type(array_ty);
    if (elem_ty != TY_UNKNOWN || open_i == INVALID || close_i == INVALID ||
        open_i + 1u >= close_i)
        return elem_ty;

    uint elem_end = array_elem_end(open_i + 1u, close_i);
    if (elem_end <= open_i + 1u)
        return TY_UNKNOWN;
    return simple_expr_type(open_i + 1u, elem_end);
}

uint function_param_count(uint fn_i)
{
    if (fn_i < active_token_count())
        return call_param_count[fn_i];
    return 0u;
}

uint function_param_type(uint fn_i, uint param_index)
{
    if (fn_i < active_token_count() && param_index < PARAM_CACHE_STRIDE)
        return call_param_type[fn_i * PARAM_CACHE_STRIDE + param_index];
    return TY_UNKNOWN;
}

uint call_arg_count(uint call_lparen_i, uint close_i)
{
    if (close_i == INVALID || call_lparen_i + 1u >= close_i)
        return 0u;
    uint bracket_depth = 0u;
    uint group_depth = 0u;
    uint count = 1u;
    for (uint j = call_lparen_i + 1u; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if (kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET ||
                 kind == TK_LBRACKET)
            bracket_depth += 1u;
        else if ((kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET ||
                  kind == TK_RBRACKET) &&
                 bracket_depth > 0u)
            bracket_depth -= 1u;
        else if ((kind == TK_ARG_COMMA || kind == TK_COMMA) && bracket_depth == 0u &&
                 group_depth == 0u)
            count += 1u;
    }
    return count;
}

uint call_arg_start(uint call_lparen_i, uint close_i, uint arg_index)
{
    uint current = 0u;
    uint start = call_lparen_i + 1u;
    uint bracket_depth = 0u;
    uint group_depth = 0u;
    for (uint j = call_lparen_i + 1u; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if (kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET ||
                 kind == TK_LBRACKET)
            bracket_depth += 1u;
        else if ((kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET ||
                  kind == TK_RBRACKET) &&
                 bracket_depth > 0u)
            bracket_depth -= 1u;
        else if ((kind == TK_ARG_COMMA || kind == TK_COMMA) && bracket_depth == 0u &&
                 group_depth == 0u)
        {
            if (current == arg_index)
                return start < j ? start : INVALID;
            current += 1u;
            start = j + 1u;
        }
    }
    if (current == arg_index)
        return start < close_i ? start : INVALID;
    return INVALID;
}

uint call_arg_end(uint arg_start_i, uint close_i)
{
    uint bracket_depth = 0u;
    uint group_depth = 0u;
    for (uint j = arg_start_i; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if (kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET ||
                 kind == TK_LBRACKET)
            bracket_depth += 1u;
        else if ((kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET ||
                  kind == TK_RBRACKET) &&
                 bracket_depth > 0u)
            bracket_depth -= 1u;
        else if ((kind == TK_ARG_COMMA || kind == TK_COMMA) && bracket_depth == 0u &&
                 group_depth == 0u)
            return j;
    }
    return close_i;
}

bool is_call_close_kind(uint kind)
{
    return kind == TK_CALL_RPAREN || kind == TK_RPAREN;
}

uint enum_variant_payload_open(uint variant_i)
{
    if (variant_i == INVALID || variant_i + 1u >= active_token_count())
        return INVALID;
    return is_group_open_kind(token_kind(variant_i + 1u)) ? variant_i + 1u : INVALID;
}

uint enum_variant_payload_close(uint variant_i)
{
    uint open_i = enum_variant_payload_open(variant_i);
    if (open_i == INVALID)
        return INVALID;
    return find_group_close(open_i, active_token_count());
}

uint enum_variant_payload_count(uint variant_i)
{
    uint open_i = enum_variant_payload_open(variant_i);
    if (open_i == INVALID)
        return 0u;
    uint close_i = enum_variant_payload_close(variant_i);
    if (close_i == INVALID)
        return 0u;
    return call_arg_count(open_i, close_i);
}

uint enum_variant_payload_type(uint variant_i, uint field_index)
{
    uint open_i = enum_variant_payload_open(variant_i);
    if (open_i == INVALID)
        return TY_UNKNOWN;
    uint close_i = enum_variant_payload_close(variant_i);
    if (close_i == INVALID)
        return TY_UNKNOWN;
    uint field_i = call_arg_start(open_i, close_i, field_index);
    return field_i == INVALID ? TY_UNKNOWN : type_code_for_type_expr(field_i);
}

bool check_enum_constructor_call(uint callee_i, uint open_i, uint close_i)
{
    uint variant_i = find_enum_variant_decl(callee_i);
    if (variant_i == INVALID)
        return false;

    uint expected_count = enum_variant_payload_count(variant_i);
    uint actual_count = call_arg_count(open_i, close_i);
    if (actual_count != expected_count)
    {
        record_error(callee_i, ERR_CALL_MISMATCH, expected_count * 256u + actual_count);
        return true;
    }

    [loop]
    for (uint arg_i = 0u; arg_i < actual_count && arg_i < 16u; arg_i += 1u)
    {
        uint arg_start_i = call_arg_start(open_i, close_i, arg_i);
        if (arg_start_i == INVALID)
            return true;
        uint arg_end_i = call_arg_end(arg_start_i, close_i);
        uint dst = enum_variant_payload_type(variant_i, arg_i);
        uint src = simple_expr_type(arg_start_i, arg_end_i);
        if (!assignable(dst, src))
        {
            record_error(arg_start_i, ERR_ASSIGN_MISMATCH, dst * 256u + src);
            return true;
        }
    }

    return true;
}

void check_call(uint callee_i, uint end_i)
{
    uint open_i = callee_i + 1u;
    uint close_i = INVALID;
    if (end_i != INVALID && end_i > open_i)
    {
        uint candidate = end_i - 1u;
        if (is_call_close_kind(token_kind(candidate)))
            close_i = candidate;
    }
    if (close_i == INVALID)
        close_i = find_call_close(open_i);
    if (close_i == INVALID)
        return;

    uint arg_count = call_arg_count(open_i, close_i);
    if (is_print_name(callee_i))
    {
        if (arg_count != 1u)
        {
            record_error(callee_i, ERR_CALL_MISMATCH, arg_count);
            return;
        }
        uint arg_start_i = call_arg_start(open_i, close_i, 0u);
        if (arg_start_i == INVALID)
            return;
        uint arg_ty = simple_expr_type(arg_start_i, call_arg_end(arg_start_i, close_i));
        if (!assignable(TY_INT, arg_ty))
            record_error(arg_start_i, ERR_ASSIGN_MISMATCH, TY_INT * 256u + arg_ty);
        return;
    }

    if (is_assert_name(callee_i))
    {
        if (arg_count != 1u)
        {
            record_error(callee_i, ERR_CALL_MISMATCH, arg_count);
            return;
        }
        uint arg_start_i = call_arg_start(open_i, close_i, 0u);
        if (arg_start_i == INVALID)
            return;
        uint arg_ty = simple_expr_type(arg_start_i, call_arg_end(arg_start_i, close_i));
        if (!assignable(TY_BOOL, arg_ty))
            record_error(arg_start_i, ERR_ASSIGN_MISMATCH, TY_BOOL * 256u + arg_ty);
        return;
    }

    uint fn_i = find_named_function(callee_i);
    if (fn_i == INVALID)
    {
        if (check_enum_constructor_call(callee_i, open_i, close_i))
            return;

        uint callee_ty = visible_type_for(callee_i);
        if (callee_ty == TY_UNKNOWN)
        {
            uint callee_decl = visible_decl_for(callee_i);
            if (callee_decl != INVALID)
                callee_ty = declaration_type(callee_decl);
        }
        if (callee_ty != TY_UNKNOWN)
            record_error(callee_i, ERR_CALL_MISMATCH, callee_ty);
        return;
    }

    uint param_count = function_param_count(fn_i);
    if (arg_count != param_count)
    {
        record_error(callee_i, ERR_CALL_MISMATCH, param_count * 256u + arg_count);
        return;
    }

    for (uint arg_i = 0u; arg_i < arg_count && arg_i < 16u; arg_i += 1u)
    {
        uint arg_start_i = call_arg_start(open_i, close_i, arg_i);
        if (arg_start_i == INVALID)
            return;
        uint arg_end_i = call_arg_end(arg_start_i, close_i);
        uint dst = function_param_type(fn_i, arg_i);
        uint src = simple_expr_type(arg_start_i, arg_end_i);
        if (!assignable(dst, src))
        {
            record_error(arg_start_i, ERR_ASSIGN_MISMATCH, dst * 256u + src);
            return;
        }
    }
}

bool ident_is_use(uint i)
{
    if (token_kind(i) != TK_IDENT)
        return false;
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    if (prev == TK_FN || prev == TK_DOT || prev == TK_CONST || prev == TK_ENUM ||
        prev == TK_STRUCT)
        return false;
    return true;
}

bool ident_resolves(uint i)
{
    if (is_builtin_name(i))
        return true;
    if (i + 1u < active_token_count() && token_kind(i + 1u) == TK_LBRACE &&
        find_struct_decl_name(i) != INVALID)
        return true;
    if (find_enum_variant_decl(i) != INVALID)
        return true;
    if (i + 1u < active_token_count() &&
        (token_kind(i + 1u) == TK_CALL_LPAREN || token_kind(i + 1u) == TK_LPAREN) &&
        find_named_function(i) != INVALID)
        return true;
    if (visible_type_for(i) != TY_UNKNOWN)
        return true;
    return visible_decl_for(i) != INVALID;
}

uint enclosing_function_return_type(uint i)
{
    uint fn_start = enclosing_function_start(i);
    if (fn_start == INVALID)
    {
        uint j = i;
        [loop]
        for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
        {
            j -= 1u;
            if (token_kind(j) == TK_FN)
            {
                fn_start = j;
                break;
            }
        }
    }
    return fn_start == INVALID ? TY_INT : find_function_return_type(fn_start);
}

void check_let(uint i, uint end_i)
{
    bool has_type = token_kind(i + 1u) == TK_COLON;
    uint dst = has_type ? type_code_for_type_expr(i + 2u) : TY_UNKNOWN;
    if (has_type && dst == TY_UNKNOWN)
    {
        record_error(i + 2u, ERR_UNKNOWN_TYPE, 0u);
        return;
    }

    uint semi = stmt_semicolon_from_hir_end(i, end_i);
    if (semi == INVALID)
        return;
    uint assign_i = find_let_assign(i, semi);
    if (assign_i == INVALID || assign_i + 1u >= semi)
        return;

    uint src = simple_expr_type(assign_i + 1u, semi);
    if (has_type && !assignable(dst, src))
    {
        record_error(assign_i + 1u, ERR_ASSIGN_MISMATCH, dst * 256u + src);
        return;
    }

    if (token_kind(assign_i + 1u) == TK_ARRAY_LBRACKET || token_kind(assign_i + 1u) == TK_LBRACKET)
    {
        uint close_i = find_array_literal_close(assign_i + 1u, semi);
        uint elem_ty = has_type ? indexed_element_type(dst)
                                : array_literal_element_type(assign_i + 1u, close_i, src);
        uint actual_len = array_literal_len(assign_i + 1u, close_i);
        uint declared_len = has_type ? type_array_decl_len(i + 2u, semi) : INVALID;
        if (declared_len != INVALID && actual_len != declared_len)
        {
            record_error(assign_i + 1u, ERR_ASSIGN_MISMATCH, declared_len * 256u + actual_len);
            return;
        }
        check_array_literal_elements(assign_i + 1u, close_i, elem_ty);
    }
}

void check_const(uint const_i, uint end_i)
{
    uint n_active = active_token_count();
    if (const_i + 4u >= n_active || token_kind(const_i + 1u) != TK_IDENT ||
        token_kind(const_i + 2u) != TK_COLON)
    {
        record_error(const_i, ERR_BAD_HIR, HIR_CONST_ITEM);
        return;
    }

    uint decl_i = const_i + 1u;
    uint dst = type_code_for_type_expr(decl_i + 2u);
    if (dst == TY_UNKNOWN)
    {
        record_error(decl_i + 2u, ERR_UNKNOWN_TYPE, 0u);
        return;
    }

    uint semi = stmt_semicolon_from_hir_end(const_i, end_i);
    if (semi == INVALID)
        return;
    uint assign_i = find_let_assign(decl_i, semi);
    if (assign_i == INVALID || assign_i + 1u >= semi)
    {
        record_error(const_i, ERR_BAD_HIR, HIR_CONST_ITEM);
        return;
    }

    uint src = simple_expr_type(assign_i + 1u, semi);
    if (!assignable(dst, src))
        record_error(assign_i + 1u, ERR_ASSIGN_MISMATCH, dst * 256u + src);
}

void check_return(uint i, uint end_i)
{
    uint semi = stmt_semicolon_from_hir_end(i, end_i);
    if (semi == INVALID)
        return;

    uint dst = enclosing_function_return_type(i);
    uint first = i + 1u;
    if (first < semi && (token_kind(first) == TK_ARRAY_LBRACKET || token_kind(first) == TK_LBRACKET))
    {
        record_error(first, ERR_INVALID_ARRAY_RETURN, 0u);
        return;
    }

    uint src = TY_VOID;
    if (i + 1u != semi)
    {
        uint expr_i = i + 1u;
        uint first_kind = token_kind(expr_i);
        uint close_i = is_group_open_kind(first_kind) ? find_group_close(expr_i, semi) : INVALID;
        if (close_i != INVALID && close_i + 1u < semi &&
            (token_kind(close_i + 1u) == TK_INDEX_LBRACKET ||
             token_kind(close_i + 1u) == TK_LBRACKET))
            src = TY_INT;
        else
            src = simple_expr_type(expr_i, semi);
    }
    if (!assignable(dst, src))
        record_error(i, ERR_RETURN_MISMATCH, dst * 256u + src);
}

void check_condition(uint i, uint end_i)
{
    uint expr_i = i + 2u;
    uint close_i = end_i == INVALID ? active_token_count() : min(end_i, active_token_count());
    uint n_active = active_token_count();
    for (uint j = i + 1u; j < close_i && j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_GROUP_RPAREN || kind == TK_RPAREN)
        {
            close_i = j;
            break;
        }
    }
    uint ty = simple_expr_type(expr_i, close_i);
    if (ty != TY_UNKNOWN && ty != TY_BOOL)
        record_error(expr_i, ERR_COND_TYPE, ty);
}

void check_member(uint dot_i)
{
    if (dot_i == 0u || dot_i + 1u >= active_token_count() ||
        token_kind(dot_i - 1u) != TK_IDENT || token_kind(dot_i + 1u) != TK_IDENT)
    {
        record_error(dot_i, ERR_INVALID_MEMBER_ACCESS, 0u);
        return;
    }

    uint member_ty = visible_type_for(dot_i + 1u);
    if (member_ty != TY_UNKNOWN)
        return;

    uint base_ty = identifier_type(dot_i - 1u);
    if (!is_struct_type(base_ty))
    {
        record_error(dot_i, ERR_INVALID_MEMBER_ACCESS, base_ty);
        return;
    }
    if (struct_field_type(base_ty, dot_i + 1u) == TY_UNKNOWN)
        record_error(dot_i + 1u, ERR_INVALID_MEMBER_ACCESS, base_ty);
}

void check_file_shape()
{
}

void check_hir_node(uint i)
{
    uint kind = hir_kind[i];
    if (kind == 0u)
        return;

    uint n_active = active_token_count();
    uint pos = hir_token_pos[i];
    uint end_i = i < active_hir_node_count() ? hir_token_end[i] : INVALID;
    if (end_i != INVALID)
        end_i = min(end_i, n_active);
    if (pos != INVALID && pos >= n_active)
    {
        record_error(n_active, ERR_BAD_HIR, pos);
        return;
    }
    if (i == 0u && kind != HIR_FILE)
    {
        record_error(0u, ERR_BAD_HIR, kind);
        return;
    }
    if (kind == HIR_FILE)
        check_file_shape();

    if (kind == HIR_TYPE)
    {
        if (pos > 0u && token_kind(pos - 1u) == TK_ARROW &&
            (token_kind(pos) == TK_TYPE_ARRAY_LBRACKET || token_kind(pos) == TK_LBRACKET))
        {
            record_error(pos, ERR_INVALID_ARRAY_RETURN, 0u);
            return;
        }
        if ((token_kind(pos) == TK_TYPE_IDENT || token_kind(pos) == TK_IDENT) &&
            primitive_type_code(pos) == TY_UNKNOWN && find_generic_type_param_decl(pos) == INVALID &&
            find_struct_decl_name(pos) == INVALID && find_enum_decl_name(pos) == INVALID)
            record_error(pos, ERR_UNKNOWN_TYPE, 0u);
        return;
    }

    if (kind == HIR_LET_STMT)
    {
        if (token_kind(pos) != TK_LET || pos + 1u >= n_active ||
            !(token_kind(pos + 1u) == TK_LET_IDENT || token_kind(pos + 1u) == TK_IDENT))
        {
            record_error(pos, ERR_BAD_HIR, kind);
            return;
        }
        check_let(pos + 1u, end_i);
        return;
    }

    if (kind == HIR_CONST_ITEM)
    {
        if (token_kind(pos) != TK_CONST)
        {
            record_error(pos, ERR_BAD_HIR, kind);
            return;
        }
        check_const(pos, end_i);
        return;
    }

    if (kind == HIR_ENUM_ITEM)
    {
        if (token_kind(pos) != TK_ENUM)
            record_error(pos, ERR_BAD_HIR, kind);
        return;
    }

    if (kind == HIR_STRUCT_ITEM)
    {
        if (token_kind(pos) != TK_STRUCT)
            record_error(pos, ERR_BAD_HIR, kind);
        return;
    }

    if (kind == HIR_STRUCT_LITERAL_EXPR)
    {
        if (token_kind(pos) != TK_LBRACE)
            record_error(pos, ERR_BAD_HIR, kind);
        return;
    }

    if (kind == HIR_RETURN_STMT)
    {
        if (token_kind(pos) != TK_RETURN)
        {
            record_error(pos, ERR_BAD_HIR, kind);
            return;
        }
        check_return(pos, end_i);
        return;
    }

    if (kind == HIR_IF_STMT || kind == HIR_WHILE_STMT)
    {
        uint want = kind == HIR_IF_STMT ? TK_IF : TK_WHILE;
        if (token_kind(pos) != want)
        {
            record_error(pos, ERR_BAD_HIR, kind);
            return;
        }
        check_condition(pos, end_i);
        return;
    }

    if (kind == HIR_ASSIGN_EXPR)
    {
        if (is_assignment_operator(token_kind(pos)))
            check_assignment(pos, end_i);
        return;
    }

    if (kind == HIR_NAME_EXPR)
    {
        if (token_kind(pos) != TK_IDENT)
        {
            record_error(pos, ERR_BAD_HIR, kind);
            return;
        }
        bool followed_by_call = pos + 1u < n_active &&
                                (token_kind(pos + 1u) == TK_CALL_LPAREN ||
                                 token_kind(pos + 1u) == TK_LPAREN);
        if (!followed_by_call && visible_decl_for(pos) == INVALID &&
            (find_named_function(pos) != INVALID || is_builtin_name(pos)))
        {
            record_error(pos, ERR_CALL_MISMATCH, 0u);
            return;
        }
        if (!ident_resolves(pos))
            record_error(pos, ERR_UNRESOLVED_IDENT, 0u);
        return;
    }

    if (kind == HIR_CALL_EXPR)
    {
        if (!((token_kind(pos) == TK_CALL_LPAREN || token_kind(pos) == TK_LPAREN) &&
              pos > 0u && token_kind(pos - 1u) == TK_IDENT))
        {
            record_error(pos, ERR_BAD_HIR, kind);
            return;
        }
        check_call(pos - 1u, end_i);
        return;
    }

    if (kind == HIR_INDEX_EXPR)
    {
        if (!is_index_open_kind(token_kind(pos)))
        {
            record_error(pos, ERR_BAD_HIR, kind);
            return;
        }
        check_index(pos, end_i);
        return;
    }

    if (kind == HIR_MEMBER_EXPR)
    {
        if (token_kind(pos) != TK_DOT)
        {
            record_error(pos, ERR_BAD_HIR, kind);
            return;
        }
        check_member(pos);
        return;
    }

    if (kind == HIR_ARRAY_EXPR)
    {
        uint token = token_kind(pos);
        if (token != TK_ARRAY_LBRACKET && token != TK_LBRACKET)
        {
            record_error(pos, ERR_BAD_HIR, kind);
            return;
        }
        uint close_i = find_array_literal_close(pos, active_token_count());
        if (close_i == INVALID)
        {
            record_error(pos, ERR_BAD_HIR, kind);
            return;
        }
        uint elem_ty = TY_UNKNOWN;
        if (array_literal_is_let_initializer(pos) && pos + 1u < close_i)
        {
            uint elem_end = array_elem_end(pos + 1u, close_i);
            elem_ty = simple_expr_type(pos + 1u, elem_end);
        }
        check_array_literal_elements(pos, close_i, elem_ty);
        return;
    }

}

void check_hir_node_min(uint node_i)
{
    uint kind = hir_kind[node_i];
    if (kind == 0u)
        return;

    uint pos = hir_token_pos[node_i];
    uint end_i = hir_token_end[node_i];
    uint n_active = active_token_count();
    if (pos >= n_active)
    {
        record_error(n_active, ERR_BAD_HIR, pos);
        return;
    }

    if (kind == HIR_LET_STMT)
    {
        if (token_kind(pos) == TK_LET_IDENT)
            check_let(pos, end_i);
        else if (token_kind(pos) == TK_LET && pos + 1u < n_active)
            check_let(pos + 1u, end_i);
        else
            record_error(pos, ERR_BAD_HIR, kind);
        return;
    }

    if (kind == HIR_CONST_ITEM)
    {
        if (token_kind(pos) == TK_CONST)
            check_const(pos, end_i);
        else
            record_error(pos, ERR_BAD_HIR, kind);
        return;
    }

    if (kind == HIR_RETURN_STMT)
    {
        if (token_kind(pos) == TK_RETURN)
            check_return(pos, end_i);
        else
            record_error(pos, ERR_BAD_HIR, kind);
        return;
    }

    if (kind == HIR_ASSIGN_EXPR && is_assignment_operator(token_kind(pos)))
        check_assignment(pos, end_i);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i < active_hir_node_count())
        check_hir_node_min(i);
}
