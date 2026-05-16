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
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> module_type_path_status;
StructuredBuffer<uint> module_value_path_status;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_decl_name_id;

RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint ARRAY_RETURN_OK = 0xfffffffeu;
static const uint GENERIC_ENUM_CTOR_OK = 0xfffffffdu;

static const uint ERR_UNKNOWN_TYPE = 1u;
static const uint ERR_UNRESOLVED_IDENT = 2u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_RETURN_MISMATCH = 4u;
static const uint ERR_BAD_HIR = 6u;
static const uint ERR_INVALID_MEMBER_ACCESS = 8u;
static const uint ERR_INVALID_ARRAY_RETURN = 9u;
static const uint ERR_CALL_MISMATCH = 10u;

static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_CONST_ITEM = 25u;
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
static const uint PATH_RESOLVE_STATUS_OK = 0u;

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
static const uint TK_LET_IDENT = 78u;
static const uint TK_IF = 70u;
static const uint TK_WHILE = 72u;
static const uint TK_ARROW = 75u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_LET_ASSIGN = 81u;
static const uint TK_ARG_COMMA = 82u;
static const uint TK_ARRAY_COMMA = 83u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;
static const uint TK_TYPE_SEMICOLON = 87u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_CONST = 92u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;
static const uint TK_MATCH = 95u;
static const uint TK_TRAIT = 99u;
static const uint TK_SELF_VALUE = 105u;

static const uint LANGUAGE_PRIMITIVE_DECL_FIRST = 3u;
static const uint LANGUAGE_DECL_COUNT = 18u;

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

bool same_name_id(uint a, uint b)
{
    uint n = active_token_count();
    if (a >= n || b >= n)
        return false;
    uint left = name_id_by_token[a];
    uint right = name_id_by_token[b];
    return left != INVALID && left == right;
}

uint language_type_code_for_decl(uint decl_i)
{
    if (decl_i >= 4u && decl_i <= 8u)
        return TY_INT;
    if (decl_i >= 9u && decl_i <= 13u)
        return TY_UINT;
    if (decl_i >= 14u && decl_i <= 15u)
        return TY_FLOAT;
    if (decl_i == 3u)
        return TY_BOOL;
    if (decl_i == 16u)
        return TY_CHAR;
    if (decl_i == 17u)
        return TY_STRING;
    return TY_UNKNOWN;
}

uint language_type_code_for_token(uint type_i)
{
    if (type_i >= active_token_count())
        return TY_UNKNOWN;
    uint name_id = name_id_by_token[type_i];
    if (name_id == INVALID)
        return TY_UNKNOWN;
    [loop]
    for (uint decl_i = LANGUAGE_PRIMITIVE_DECL_FIRST; decl_i < LANGUAGE_DECL_COUNT; decl_i += 1u)
    {
        if (language_decl_name_id[decl_i] == name_id)
            return language_type_code_for_decl(decl_i);
    }
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

uint indexed_element_type(uint base_ty)
{
    return is_array_type(base_ty) ? base_ty - TY_ARRAY_BASE : TY_UNKNOWN;
}

bool is_struct_decl_name_at(uint i)
{
    uint kind = token_kind(i);
    return (kind == TK_IDENT || kind == TK_TYPE_IDENT) && i > 0u && token_kind(i - 1u) == TK_STRUCT;
}

uint find_struct_decl_name(uint name_i)
{
    uint n = active_token_count();
    [loop]
    for (uint j = 1u; j < n; j += 1u)
    {
        if (is_struct_decl_name_at(j) && same_name_id(j, name_i))
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
    uint kind = token_kind(i);
    return (kind == TK_IDENT || kind == TK_TYPE_IDENT) && i > 0u && token_kind(i - 1u) == TK_ENUM;
}

uint find_enum_decl_name(uint name_i)
{
    uint n = active_token_count();
    [loop]
    for (uint j = 1u; j < n; j += 1u)
    {
        if (is_enum_decl_name_at(j) && same_name_id(j, name_i))
            return j;
    }
    return INVALID;
}

uint enum_type_code_for_name(uint name_i)
{
    uint decl_i = find_enum_decl_name(name_i);
    return decl_i == INVALID ? TY_UNKNOWN : TY_ENUM_BASE + decl_i;
}

uint generic_param_list_open(uint item_i)
{
    uint n = active_token_count();
    [loop]
    for (uint j = item_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT)
            return j;
        if (kind == TK_LBRACE || kind == TK_LPAREN || kind == TK_SEMICOLON)
            return INVALID;
    }
    return INVALID;
}

uint generic_param_list_close(uint open_i)
{
    uint n = active_token_count();
    uint depth = 0u;
    [loop]
    for (uint j = open_i; j < n; j += 1u)
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
        else if (kind == TK_LBRACE || kind == TK_SEMICOLON)
            return INVALID;
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

        uint open_i = generic_param_list_open(j);
        if (open_i == INVALID)
            return INVALID;
        uint close_i = generic_param_list_close(open_i);
        if (close_i == INVALID)
            return INVALID;
        [loop]
        for (uint p = open_i + 1u; p < close_i; p += 1u)
        {
            if (is_type_generic_param_token(p, open_i, close_i) && same_name_id(p, name_i))
                return p;
        }
        return INVALID;
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
    uint n = active_token_count();
    [loop]
    for (uint guard = 0u; guard < 16u && cur < n; guard += 1u)
    {
        uint kind = token_kind(cur);
        if (kind != TK_TYPE_ARRAY_LBRACKET && kind != TK_ARRAY_LBRACKET && kind != TK_LBRACKET)
            break;
        array_depth += 1u;
        cur += 1u;
    }

    uint elem = language_type_code_for_token(cur);
    if (elem == TY_UNKNOWN && (token_kind(cur) == TK_IDENT || token_kind(cur) == TK_TYPE_IDENT))
        elem = generic_type_code_for_name(cur);
    if (elem == TY_UNKNOWN && array_depth == 0u && cur < active_token_count())
        elem = module_type_path_type[cur];
    if (elem == TY_UNKNOWN && (token_kind(cur) == TK_IDENT || token_kind(cur) == TK_TYPE_IDENT))
        elem = struct_type_code_for_name(cur);
    if (elem == TY_UNKNOWN && (token_kind(cur) == TK_IDENT || token_kind(cur) == TK_TYPE_IDENT))
        elem = enum_type_code_for_name(cur);
    if (elem == TY_UNKNOWN)
        return TY_UNKNOWN;
    if (array_depth > 0u && (is_struct_type(elem) || is_enum_type(elem) || is_generic_type(elem)))
        return TY_UNKNOWN;
    return array_depth == 0u ? elem : TY_ARRAY_BASE + elem;
}

uint explicit_let_decl_type(uint decl_i)
{
    return type_code_for_type_expr(decl_i + 2u);
}

uint struct_decl_name_from_type(uint ty)
{
    return is_struct_type(ty) ? ty - TY_STRUCT_BASE : INVALID;
}

uint struct_decl_open(uint decl_i)
{
    uint n = active_token_count();
    [loop]
    for (uint j = decl_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACE)
            return j;
        if (kind == TK_SEMICOLON || kind == TK_STRUCT || kind == TK_ENUM || kind == TK_FN)
            return INVALID;
    }
    return INVALID;
}

uint find_brace_close(uint open_i, uint limit_i)
{
    uint depth = 0u;
    uint n = min(limit_i, active_token_count());
    [loop]
    for (uint j = open_i; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACE)
            depth += 1u;
        else if (kind == TK_RBRACE)
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

uint enum_decl_open(uint decl_name_i)
{
    uint n = active_token_count();
    [loop]
    for (uint j = decl_name_i + 1u; j < n; j += 1u)
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

bool enum_decl_has_generic_params(uint decl_name_i)
{
    if (!is_enum_decl_name_at(decl_name_i))
        return false;
    uint open_i = generic_param_list_open(decl_name_i);
    if (open_i == INVALID)
        return false;
    uint close_i = generic_param_list_close(open_i);
    uint body_i = enum_decl_open(decl_name_i);
    return close_i != INVALID && body_i != INVALID && close_i < body_i;
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

uint enum_decl_for_variant_decl(uint variant_i)
{
    uint ty = enum_type_for_variant_decl(variant_i);
    return is_enum_type(ty) ? ty - TY_ENUM_BASE : INVALID;
}

uint find_enum_variant_decl(uint name_i)
{
    uint n = active_token_count();
    [loop]
    for (uint enum_name_i = 1u; enum_name_i < n; enum_name_i += 1u)
    {
        if (!is_enum_decl_name_at(enum_name_i))
            continue;
        uint open_i = enum_decl_open(enum_name_i);
        uint close_i = enum_decl_close(enum_name_i);
        if (open_i == INVALID || close_i == INVALID)
            continue;
        [loop]
        for (uint j = open_i + 1u; j < close_i; j += 1u)
        {
            uint kind = token_kind(j);
            uint prev = j > 0u ? token_kind(j - 1u) : 0u;
            if (kind == TK_IDENT && same_name_id(j, name_i) &&
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

uint struct_field_type(uint struct_ty, uint member_i)
{
    uint decl_name_i = struct_decl_name_from_type(struct_ty);
    if (decl_name_i == INVALID)
        return TY_UNKNOWN;
    uint open_i = struct_decl_open(decl_name_i);
    uint close_i = open_i == INVALID ? INVALID : find_brace_close(open_i, active_token_count());
    if (open_i == INVALID || close_i == INVALID)
        return TY_UNKNOWN;
    [loop]
    for (uint j = open_i + 1u; j + 2u < close_i; j += 1u)
    {
        if ((token_kind(j) == TK_IDENT || token_kind(j) == TK_TYPE_IDENT) &&
            token_kind(j + 1u) == TK_COLON && same_name_id(j, member_i))
            return type_code_for_type_expr(j + 2u);
    }
    return TY_UNKNOWN;
}

bool is_bool_result_operator(uint kind)
{
    return kind == TK_LT || kind == TK_GT || kind == TK_LE || kind == TK_GE || kind == TK_EQEQ ||
           kind == TK_NOT_EQUAL || kind == TK_ANDAND || kind == TK_OROR;
}

bool is_group_open_kind(uint kind)
{
    return kind == TK_GROUP_LPAREN || kind == TK_LPAREN || kind == TK_CALL_LPAREN;
}

bool is_group_close_kind(uint kind)
{
    return kind == TK_GROUP_RPAREN || kind == TK_RPAREN || kind == TK_CALL_RPAREN;
}

uint simple_expr_type(uint expr_i, uint limit_i)
{
    bool saw_float = false;
    uint n = active_token_count();
    [loop]
    for (uint j = expr_i; j < limit_i && j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_bool_result_operator(kind))
            return TY_BOOL;
        if (kind == TK_FLOAT)
            saw_float = true;
    }
    if (saw_float)
        return TY_FLOAT;

    uint cur = expr_i;
    [loop]
    for (uint guard = 0u; guard < 16u && cur < limit_i && cur < n; guard += 1u)
    {
        uint kind = token_kind(cur);
        if (is_group_open_kind(kind) || kind == TK_PREFIX_PLUS || kind == TK_PREFIX_MINUS)
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
        if (kind == TK_ARRAY_LBRACKET || kind == TK_LBRACKET)
            return TY_ARRAY_BASE + TY_INT;
        if (kind == TK_MATCH)
            return call_return_type[cur];
        if (kind == TK_IDENT || kind == TK_TYPE_IDENT || kind == TK_SELF_VALUE)
        {
            if (cur + 1u < limit_i && token_kind(cur + 1u) == TK_LBRACE)
                return struct_type_code_for_name(cur);
            if (kind == TK_IDENT || kind == TK_TYPE_IDENT)
            {
                uint variant_ty = enum_type_for_variant_name(cur);
                uint variant_decl = variant_ty == TY_UNKNOWN ? INVALID : find_enum_variant_decl(cur);
                if (variant_ty != TY_UNKNOWN && variant_decl != INVALID)
                {
                    bool ctor_call = cur + 1u < limit_i &&
                                     (token_kind(cur + 1u) == TK_CALL_LPAREN ||
                                      token_kind(cur + 1u) == TK_LPAREN);
                    bool decl_has_payload =
                        variant_decl + 1u < n && is_group_open_kind(token_kind(variant_decl + 1u));
                    if (ctor_call || !decl_has_payload)
                        return variant_ty;
                }
            }
            if (cur + 2u < limit_i && token_kind(cur + 1u) == TK_DOT &&
                token_kind(cur + 2u) == TK_IDENT)
            {
                uint member_ty = visible_type[cur + 2u];
                if (member_ty != TY_UNKNOWN)
                    return member_ty;
                return struct_field_type(visible_type[cur], cur + 2u);
            }
            if (cur + 1u < limit_i &&
                (token_kind(cur + 1u) == TK_CALL_LPAREN || token_kind(cur + 1u) == TK_LPAREN))
                return call_return_type[cur];
            uint ty = visible_type[cur];
            if (ty == TY_UNKNOWN)
                ty = call_return_type[cur];
            if (cur + 1u < limit_i &&
                (token_kind(cur + 1u) == TK_INDEX_LBRACKET || token_kind(cur + 1u) == TK_LBRACKET))
            {
                uint indexed_ty = call_return_type[cur + 1u];
                if (indexed_ty != TY_UNKNOWN)
                    return indexed_ty;
                return indexed_element_type(ty);
            }
            return ty;
        }
        return TY_UNKNOWN;
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
    return false;
}

uint find_stmt_semicolon(uint start_i)
{
    uint bracket_depth = 0u;
    uint n = active_token_count();
    [loop]
    for (uint j = start_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACKET || kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET ||
            kind == TK_TYPE_ARRAY_LBRACKET)
            bracket_depth += 1u;
        else if (kind == TK_RBRACKET || kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET ||
                 kind == TK_TYPE_ARRAY_RBRACKET)
        {
            if (bracket_depth > 0u)
                bracket_depth -= 1u;
        }
        else if (kind == TK_SEMICOLON && bracket_depth == 0u)
            return j;
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
    [loop]
    for (uint j = let_ident_i + 1u; j < semi_i && j < active_token_count(); j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LET_ASSIGN || kind == TK_ASSIGN)
            return j;
    }
    return INVALID;
}

uint enclosing_function_start(uint target_i)
{
    if (target_i < active_token_count())
    {
        uint encoded = enclosing_fn[target_i];
        if (encoded != 0u)
        {
            uint cached = encoded - 1u;
            if (cached < active_token_count() && token_kind(cached) == TK_FN)
                return cached;
        }
    }
    uint j = target_i;
    [loop]
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        j -= 1u;
        if (token_kind(j) == TK_FN)
            return j;
    }
    return INVALID;
}

uint function_return_type_start(uint fn_start)
{
    if (fn_start == INVALID)
        return INVALID;
    uint n = active_token_count();
    uint bracket_depth = 0u;
    [loop]
    for (uint j = fn_start + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACKET || kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET ||
            kind == TK_TYPE_ARRAY_LBRACKET)
        {
            bracket_depth += 1u;
            continue;
        }
        if (kind == TK_RBRACKET || kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET ||
            kind == TK_TYPE_ARRAY_RBRACKET)
        {
            if (bracket_depth > 0u)
                bracket_depth -= 1u;
            continue;
        }
        if (kind == TK_ARROW && bracket_depth == 0u)
            return j + 1u < n ? j + 1u : INVALID;
        if (bracket_depth == 0u && (kind == TK_LBRACE || kind == TK_SEMICOLON || kind == TK_FN))
            return INVALID;
    }
    return INVALID;
}

uint enclosing_function_return_type(uint i)
{
    uint fn_start = enclosing_function_start(i);
    if (fn_start == INVALID)
        return TY_INT;
    uint ret_i = function_return_type_start(fn_start);
    if (ret_i < active_token_count())
    {
        uint parsed = type_code_for_type_expr(ret_i);
        if (parsed != TY_UNKNOWN)
            return parsed;
    }
    return call_return_type[fn_start];
}

bool function_return_syntax_is_array(uint fn_start)
{
    uint type_i = function_return_type_start(fn_start);
    if (type_i == INVALID)
        return false;
    uint kind = token_kind(type_i);
    return kind == TK_TYPE_ARRAY_LBRACKET || kind == TK_ARRAY_LBRACKET || kind == TK_LBRACKET;
}

uint array_decl_len(uint type_i)
{
    if (token_kind(type_i) != TK_TYPE_ARRAY_LBRACKET && token_kind(type_i) != TK_LBRACKET)
        return INVALID;
    uint depth = 0u;
    uint n = active_token_count();
    [loop]
    for (uint j = type_i; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_TYPE_ARRAY_LBRACKET || kind == TK_LBRACKET)
            depth += 1u;
        else if (kind == TK_TYPE_ARRAY_RBRACKET || kind == TK_RBRACKET)
        {
            if (depth == 0u)
                return INVALID;
            depth -= 1u;
            if (depth == 0u)
                return INVALID;
        }
        else if ((kind == TK_TYPE_SEMICOLON || kind == TK_SEMICOLON) && depth == 1u)
            return 0u;
    }
    return INVALID;
}

void check_let(uint decl_i, uint end_i)
{
    bool has_type = token_kind(decl_i + 1u) == TK_COLON;
    uint dst = has_type ? explicit_let_decl_type(decl_i) : TY_UNKNOWN;
    if (has_type && dst == TY_UNKNOWN)
    {
        record_error(decl_i + 2u, ERR_UNKNOWN_TYPE, 0u);
        return;
    }
    uint semi = stmt_semicolon_from_hir_end(decl_i, end_i);
    if (semi == INVALID)
        return;
    uint assign_i = find_let_assign(decl_i, semi);
    if (assign_i == INVALID || assign_i + 1u >= semi)
        return;
    uint src = simple_expr_type(assign_i + 1u, semi);
    if (!assignable(dst, src))
        record_error(assign_i + 1u, ERR_ASSIGN_MISMATCH, dst * 256u + src);
}

void check_const(uint const_i, uint end_i)
{
    if (const_i + 3u >= active_token_count())
    {
        record_error(const_i, ERR_BAD_HIR, HIR_CONST_ITEM);
        return;
    }
    uint decl_i = const_i + 1u;
    uint dst = token_kind(decl_i + 1u) == TK_COLON ? type_code_for_type_expr(decl_i + 2u) : TY_UNKNOWN;
    uint semi = stmt_semicolon_from_hir_end(const_i, end_i);
    if (semi == INVALID)
        return;
    uint assign_i = find_let_assign(decl_i, semi);
    if (assign_i == INVALID || assign_i + 1u >= semi)
        return;
    uint src = simple_expr_type(assign_i + 1u, semi);
    if (!assignable(dst, src))
        record_error(assign_i + 1u, ERR_ASSIGN_MISMATCH, dst * 256u + src);
}

void check_return(uint return_i, uint end_i)
{
    uint semi = stmt_semicolon_from_hir_end(return_i, end_i);
    if (semi == INVALID)
        return;
    uint first = return_i + 1u;
    if (first < semi && (token_kind(first) == TK_ARRAY_LBRACKET || token_kind(first) == TK_LBRACKET))
    {
        if (call_return_type[return_i] != ARRAY_RETURN_OK)
            record_error(first, ERR_INVALID_ARRAY_RETURN, 0u);
        return;
    }
    uint fn_start = enclosing_function_start(return_i);
    uint ret_i = function_return_type_start(fn_start);
    uint dst = TY_UNKNOWN;
    if (ret_i < active_token_count())
        dst = type_code_for_type_expr(ret_i);
    if (dst == TY_UNKNOWN)
        dst = enclosing_function_return_type(return_i);
    if ((is_array_type(dst) || function_return_syntax_is_array(fn_start)) &&
        call_return_type[return_i] != ARRAY_RETURN_OK)
    {
        record_error(first, ERR_INVALID_ARRAY_RETURN, 0u);
        return;
    }
    if (call_return_type[return_i] == ARRAY_RETURN_OK)
        return;
    if (call_return_type[return_i] == GENERIC_ENUM_CTOR_OK)
        return;
    uint src = first == semi ? TY_VOID : simple_expr_type(first, semi);
    if (is_generic_type(dst) && src == TY_UNKNOWN)
    {
        record_error(return_i, ERR_RETURN_MISMATCH, dst * 256u + src);
        return;
    }
    if (!assignable(dst, src))
        record_error(return_i, ERR_RETURN_MISMATCH, dst * 256u + src);
}

uint find_group_close(uint open_i, uint limit_i)
{
    uint depth = 0u;
    uint n = min(limit_i, active_token_count());
    [loop]
    for (uint j = open_i; j < n; j += 1u)
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

uint call_arg_count(uint call_lparen_i, uint close_i)
{
    if (close_i == INVALID || call_lparen_i + 1u >= close_i)
        return 0u;
    uint bracket_depth = 0u;
    uint group_depth = 0u;
    uint count = 1u;
    [loop]
    for (uint j = call_lparen_i + 1u; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if (kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET || kind == TK_LBRACKET)
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
    [loop]
    for (uint j = call_lparen_i + 1u; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if (kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET || kind == TK_LBRACKET)
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
    [loop]
    for (uint j = arg_start_i; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if (kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET || kind == TK_LBRACKET)
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

bool is_match_pattern_tuple(uint callee_i, uint open_i, uint close_i)
{
    if (open_i != callee_i + 1u || close_i == INVALID)
        return false;
    uint n = active_token_count();
    [loop]
    for (uint j = close_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_ARROW)
            return true;
        if (kind == TK_COMMA || kind == TK_RBRACE || kind == TK_SEMICOLON)
            return false;
    }
    return false;
}

bool check_enum_constructor_call(uint callee_i, uint open_i, uint close_i)
{
    if (is_match_pattern_tuple(callee_i, open_i, close_i))
        return true;

    uint variant_i = find_enum_variant_decl(callee_i);
    if (variant_i == INVALID)
        return false;

    uint enum_decl_i = enum_decl_for_variant_decl(variant_i);
    if (enum_decl_i != INVALID && enum_decl_has_generic_params(enum_decl_i))
    {
        if (call_return_type[callee_i] == GENERIC_ENUM_CTOR_OK)
            return true;
        record_error(callee_i, ERR_CALL_MISMATCH, TY_ENUM_BASE + enum_decl_i);
        return true;
    }

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

void check_condition(uint keyword_i)
{
    uint open_i = keyword_i + 1u;
    if (!is_group_open_kind(token_kind(open_i)))
        return;
    uint close_i = find_group_close(open_i, active_token_count());
    if (close_i == INVALID)
        return;
    uint ty = simple_expr_type(open_i + 1u, close_i);
    if (ty != TY_UNKNOWN && ty != TY_BOOL)
        record_error(open_i + 1u, ERR_ASSIGN_MISMATCH, TY_BOOL * 256u + ty);
}

bool is_assignment_operator(uint kind)
{
    return kind == TK_ASSIGN || kind == TK_PLUS_ASSIGN || kind == TK_MINUS_ASSIGN ||
           kind == TK_STAR_ASSIGN || kind == TK_SLASH_ASSIGN || kind == TK_PERCENT_ASSIGN ||
           kind == TK_CARET_ASSIGN || kind == TK_SHL_ASSIGN || kind == TK_SHR_ASSIGN ||
           kind == TK_AMP_ASSIGN || kind == TK_PIPE_ASSIGN;
}

void check_assignment(uint assign_i, uint end_i)
{
    if (assign_i == 0u)
        return;
    uint dst = visible_type[assign_i - 1u];
    uint semi = stmt_semicolon_from_hir_end(assign_i, end_i);
    if (semi == INVALID || assign_i + 1u >= semi)
        return;
    uint src = simple_expr_type(assign_i + 1u, semi);
    if (!assignable(dst, src))
        record_error(assign_i + 1u, ERR_ASSIGN_MISMATCH, dst * 256u + src);
}

uint struct_literal_value_end(uint value_i, uint close_i)
{
    uint brace_depth = 0u;
    uint group_depth = 0u;
    uint bracket_depth = 0u;
    [loop]
    for (uint j = value_i; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACE)
            brace_depth += 1u;
        else if (kind == TK_RBRACE && brace_depth > 0u)
            brace_depth -= 1u;
        else if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if (kind == TK_LBRACKET || kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET)
            bracket_depth += 1u;
        else if ((kind == TK_RBRACKET || kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET) &&
                 bracket_depth > 0u)
            bracket_depth -= 1u;
        else if ((kind == TK_COMMA || kind == TK_ARRAY_COMMA) && brace_depth == 0u &&
                 group_depth == 0u && bracket_depth == 0u)
            return j;
    }
    return close_i;
}

void check_struct_literal(uint open_i, uint end_i)
{
    uint head_kind = open_i == 0u ? 0u : token_kind(open_i - 1u);
    if (open_i == 0u || (head_kind != TK_IDENT && head_kind != TK_TYPE_IDENT))
        return;
    uint struct_ty = struct_type_code_for_name(open_i - 1u);
    if (struct_ty == TY_UNKNOWN)
    {
        record_error(open_i - 1u, ERR_UNKNOWN_TYPE, 0u);
        return;
    }
    uint close_i = find_brace_close(open_i, end_i == INVALID ? active_token_count() : end_i);
    if (close_i == INVALID)
        return;
    [loop]
    for (uint field_i = open_i + 1u; field_i + 2u < close_i; field_i += 1u)
    {
        if (token_kind(field_i) != TK_IDENT || token_kind(field_i + 1u) != TK_COLON)
            continue;
        uint expected = visible_type[field_i];
        if (expected == TY_UNKNOWN)
            expected = struct_field_type(struct_ty, field_i);
        if (expected == TY_UNKNOWN)
        {
            record_error(field_i, ERR_INVALID_MEMBER_ACCESS, struct_ty);
            continue;
        }
        uint value_i = field_i + 2u;
        uint value_end = struct_literal_value_end(value_i, close_i);
        uint actual = simple_expr_type(value_i, value_end);
        if (!assignable(expected, actual))
            record_error(value_i, ERR_ASSIGN_MISMATCH, expected * 256u + actual);
    }
}

void check_hir_node(uint node_i)
{
    uint kind = hir_kind[node_i];
    if (kind == 0u)
        return;
    uint pos = hir_token_pos[node_i];
    uint end_i = hir_token_end[node_i];
    if (end_i != INVALID)
        end_i = min(end_i, active_token_count());
    if (pos >= active_token_count())
    {
        record_error(active_token_count(), ERR_BAD_HIR, pos);
        return;
    }
    if (kind == HIR_LET_STMT)
    {
        if (token_kind(pos) == TK_LET_IDENT)
            check_let(pos, end_i);
        else if (token_kind(pos) == TK_LET && pos + 1u < active_token_count())
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
    {
        check_assignment(pos, end_i);
        return;
    }
    if (kind == HIR_STRUCT_LITERAL_EXPR)
    {
        if (token_kind(pos) == TK_LBRACE)
            check_struct_literal(pos, end_i);
        else
            record_error(pos, ERR_BAD_HIR, kind);
    }
}

void check_token(uint i)
{
    uint kind = token_kind(i);
    uint type_path_status = module_type_path_status[i];
    if (type_path_status != INVALID && type_path_status != PATH_RESOLVE_STATUS_OK)
    {
        record_error(i, ERR_UNKNOWN_TYPE, type_path_status);
        return;
    }
    uint value_path_status = module_value_path_status[i];
    if (value_path_status != INVALID)
    {
        record_error(i, ERR_UNRESOLVED_IDENT, value_path_status);
        return;
    }
    if (kind == TK_TRAIT)
    {
        record_error(i, ERR_BAD_HIR, TK_TRAIT);
        return;
    }
    if (kind == TK_LET_IDENT)
    {
        check_let(i, INVALID);
        return;
    }
    if (kind == TK_LET && i + 1u < active_token_count())
    {
        check_let(i + 1u, INVALID);
        return;
    }
    if (kind == TK_CONST)
    {
        check_const(i, INVALID);
        return;
    }
    if (kind == TK_RETURN)
    {
        check_return(i, INVALID);
        return;
    }
    if (kind == TK_IF || kind == TK_WHILE)
        return;
    if (is_assignment_operator(kind))
    {
        check_assignment(i, INVALID);
        return;
    }
    if (kind == TK_IDENT && i + 1u < active_token_count() &&
        (token_kind(i + 1u) == TK_CALL_LPAREN || token_kind(i + 1u) == TK_LPAREN))
    {
        if (find_enum_variant_decl(i) != i)
        {
            uint close_i = find_group_close(i + 1u, active_token_count());
            if (close_i != INVALID)
                check_enum_constructor_call(i, i + 1u, close_i);
        }
        return;
    }
    uint prev_kind = i > 0u ? token_kind(i - 1u) : 0u;
    if (kind == TK_LBRACE && i > 0u && (prev_kind == TK_IDENT || prev_kind == TK_TYPE_IDENT) &&
        !(i >= 2u && token_kind(i - 2u) == TK_STRUCT) &&
        (token_kind(i + 1u) == TK_RBRACE ||
         ((token_kind(i + 1u) == TK_IDENT || token_kind(i + 1u) == TK_TYPE_IDENT) &&
          token_kind(i + 2u) == TK_COLON)))
    {
        check_struct_literal(i, INVALID);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i < active_token_count())
        check_token(i);
}
