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
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_decl_name_id;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> module_value_path_status;

// Shared with type_check_tokens: [0] ok, [1] first error token, [2] error code, [3] detail.
RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> visible_decl;
RWStructuredBuffer<uint> visible_type;

static const uint INVALID = 0xffffffffu;

static const uint ERR_UNRESOLVED_IDENT = 2u;
static const uint ERR_BAD_HIR = 6u;
static const uint ERR_INVALID_MEMBER_ACCESS = 8u;

static const uint HIR_NAME_EXPR = 22u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_INVALID = 0xffffffffu;
static const uint INTRINSIC_NONE = 0u;

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
static const uint LANGUAGE_DECL_COUNT = 18u;
static const uint LANGUAGE_PRIMITIVE_DECL_FIRST = 3u;

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
static const uint TK_AMPERSAND = 25u;
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
static const uint TK_PREFIX_PLUS = 58u;
static const uint TK_PREFIX_MINUS = 60u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_ARROW = 75u;
static const uint TK_PARAM_LPAREN = 76u;
static const uint TK_PARAM_RPAREN = 77u;
static const uint TK_FN = 67u;
static const uint TK_LET = 68u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_LET_ASSIGN = 81u;
static const uint TK_ARG_COMMA = 82u;
static const uint TK_PARAM_COMMA = 84u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_IF_RBRACE = 89u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_CONST = 92u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;
static const uint TK_MATCH = 95u;
static const uint TK_IMPORT = 96u;
static const uint TK_IMPL = 98u;
static const uint TK_TRAIT = 99u;
static const uint TK_FOR = 100u;
static const uint TK_WHERE = 104u;
static const uint TK_SELF_VALUE = 105u;

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool has_token_aligned_hir()
{
    return active_hir_node_count() == active_token_count() + 1u;
}

uint token_kind(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].kind : 0u;
}

bool is_intrinsic_name(uint i)
{
    return i < active_token_count() && call_intrinsic_tag[i] != INTRINSIC_NONE;
}

uint name_id_for_token(uint i)
{
    uint n = active_token_count();
    return i < n ? name_id_by_token[i] : INVALID;
}

bool same_name_id(uint a, uint b)
{
    uint an = name_id_for_token(a);
    uint bn = name_id_for_token(b);
    return an != INVALID && an == bn;
}

uint language_type_code_for_decl(uint decl_i)
{
    if (decl_i == 3u)
        return TY_BOOL;
    if (decl_i >= 4u && decl_i <= 8u)
        return TY_INT;
    if (decl_i >= 9u && decl_i <= 13u)
        return TY_UINT;
    if (decl_i >= 14u && decl_i <= 15u)
        return TY_FLOAT;
    if (decl_i == 16u)
        return TY_CHAR;
    if (decl_i == 17u)
        return TY_STRING;
    return TY_UNKNOWN;
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

uint language_type_code_for_token(uint type_i)
{
    uint name_id = name_id_for_token(type_i);
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

bool is_struct_decl_name_at(uint i)
{
    uint kind = token_kind(i);
    return (kind == TK_IDENT || kind == TK_TYPE_IDENT) && i > 0u &&
           token_kind(i - 1u) == TK_STRUCT;
}

uint find_struct_decl_name(uint name_i)
{
    uint n_active = active_token_count();
    [loop]
    for (uint j = 1u; j < n_active; j += 1u)
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

bool is_enum_decl_name_at(uint i)
{
    uint kind = token_kind(i);
    return (kind == TK_IDENT || kind == TK_TYPE_IDENT) && i > 0u &&
           token_kind(i - 1u) == TK_ENUM;
}

uint find_enum_decl_name(uint name_i)
{
    uint n_active = active_token_count();
    [loop]
    for (uint j = 1u; j < n_active; j += 1u)
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

bool is_group_open_kind(uint kind)
{
    return kind == TK_GROUP_LPAREN || kind == TK_LPAREN || kind == TK_CALL_LPAREN ||
           kind == TK_PARAM_LPAREN;
}

bool is_group_close_kind(uint kind)
{
    return kind == TK_RPAREN || kind == TK_GROUP_RPAREN || kind == TK_CALL_RPAREN ||
           kind == TK_PARAM_RPAREN;
}

uint matching_group_open_before(uint close_i)
{
    uint depth = 0u;
    [loop]
    for (uint guard = 0u; guard < 64u && close_i > guard; guard += 1u)
    {
        uint j = close_i - guard;
        uint kind = token_kind(j);
        if (is_group_close_kind(kind))
            depth += 1u;
        else if (is_group_open_kind(kind))
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

uint match_token_for_brace(uint brace_i)
{
    if (brace_i == 0u)
        return INVALID;
    uint close_i = brace_i - 1u;
    if (!is_group_close_kind(token_kind(close_i)))
        return INVALID;
    uint open_i = matching_group_open_before(close_i);
    if (open_i == INVALID || open_i == 0u)
        return INVALID;
    return token_kind(open_i - 1u) == TK_MATCH ? open_i - 1u : INVALID;
}

uint enclosing_match_token(uint token_i)
{
    uint depth = 0u;
    [loop]
    for (uint guard = 0u; guard < 256u && token_i > guard; guard += 1u)
    {
        uint j = token_i - guard;
        uint kind = token_kind(j);
        if (kind == TK_RBRACE)
            depth += 1u;
        else if (kind == TK_LBRACE)
        {
            if (depth == 0u)
                return match_token_for_brace(j);
            depth -= 1u;
        }
    }
    return INVALID;
}

bool is_in_match_pattern(uint i)
{
    uint group_depth = 0u;
    [loop]
    for (uint j = i; j < active_token_count(); j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if (group_depth == 0u && kind == TK_ARROW)
            return enclosing_match_token(i) != INVALID;
        else if (group_depth == 0u &&
                 (kind == TK_COMMA || kind == TK_RBRACE || kind == TK_SEMICOLON))
            return false;
    }
    return false;
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
    if (variant_i == INVALID)
        return TY_UNKNOWN;
    uint j = variant_i;
    [loop]
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        j -= 1u;
        if (is_enum_decl_name_at(j))
            return TY_ENUM_BASE + j;
    }
    return TY_UNKNOWN;
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

bool is_generic_bound_colon(uint colon_i)
{
    if (token_kind(colon_i) != TK_COLON || colon_i == 0u)
        return false;
    uint before = token_kind(colon_i - 1u);
    if (before != TK_IDENT && before != TK_TYPE_IDENT && before != TK_PARAM_IDENT)
        return false;
    if (colon_i > 1u && token_kind(colon_i - 2u) == TK_CONST)
        return false;

    uint depth = 0u;
    uint j = colon_i;
    [loop]
    for (uint guard = 0u; guard < 128u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind == TK_GT)
            depth += 1u;
        else if (kind == TK_LT)
        {
            if (depth == 0u)
                return true;
            depth -= 1u;
        }
        else if (kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_SEMICOLON ||
                 kind == TK_PARAM_LPAREN || kind == TK_LPAREN)
        {
            return false;
        }
    }
    return false;
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

uint find_const_generic_param_decl(uint name_i)
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
        uint close_i = generic_param_list_close(open_i);
        if (open_i == INVALID || close_i == INVALID)
            return INVALID;
        [loop]
        for (uint p = open_i + 1u; p < close_i; p += 1u)
        {
            if (p > open_i + 1u && token_kind(p - 1u) == TK_CONST && same_name_id(p, name_i))
                return p;
        }
        return INVALID;
    }
    return INVALID;
}

bool is_type_array_open(uint kind)
{
    return kind == TK_TYPE_ARRAY_LBRACKET || kind == TK_ARRAY_LBRACKET || kind == TK_LBRACKET;
}

bool is_type_array_close(uint kind)
{
    return kind == TK_TYPE_ARRAY_RBRACKET || kind == TK_ARRAY_RBRACKET || kind == TK_RBRACKET;
}

uint find_matching_type_array_rbracket(uint open_i)
{
    uint n = active_token_count();
    uint depth = 0u;
    [loop]
    for (uint j = open_i; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_type_array_open(kind))
            depth += 1u;
        else if (is_type_array_close(kind))
        {
            if (depth == 0u)
                return INVALID;
            depth -= 1u;
            if (depth == 0u)
                return j;
        }
        else if (kind == TK_LBRACE)
            return INVALID;
    }
    return INVALID;
}

uint find_type_array_semicolon(uint open_i, uint close_i)
{
    [loop]
    for (uint j = open_i + 1u; j < close_i; j += 1u)
    {
        if (token_kind(j) == TK_SEMICOLON)
            return j;
    }
    return INVALID;
}

bool generic_array_decl_context_allowed(uint open_i)
{
    if (open_i < 2u || token_kind(open_i - 1u) != TK_COLON)
        return false;

    uint decl_i = open_i - 2u;
    uint decl_kind = token_kind(decl_i);
    if (decl_kind == TK_PARAM_IDENT)
        return true;
    if (decl_kind != TK_IDENT || decl_i + 1u >= active_token_count() ||
        token_kind(decl_i + 1u) != TK_COLON)
        return false;
    if (decl_i > 0u)
    {
        uint prev = token_kind(decl_i - 1u);
        if (prev == TK_LET || prev == TK_CONST || prev == TK_ENUM || prev == TK_STRUCT)
            return false;
    }
    return true;
}

bool is_invalid_generic_array_or_slice_type(uint open_i)
{
    if (!is_type_array_open(token_kind(open_i)))
        return false;

    uint close_i = find_matching_type_array_rbracket(open_i);
    if (close_i == INVALID)
        return true;

    uint elem_i = open_i + 1u;
    uint elem_kind = token_kind(elem_i);
    bool elem_is_name =
        elem_kind == TK_IDENT || elem_kind == TK_TYPE_IDENT || elem_kind == TK_PARAM_IDENT;
    if (!elem_is_name)
        return false;

    bool elem_is_primitive = language_type_code_for_token(elem_i) != TY_UNKNOWN;
    bool elem_is_generic = generic_type_code_for_name(elem_i) != TY_UNKNOWN;
    uint semicolon_i = find_type_array_semicolon(open_i, close_i);
    bool len_name_is_present = false;
    bool len_is_generic = false;
    if (semicolon_i != INVALID && semicolon_i + 1u < close_i)
    {
        uint len_i = semicolon_i + 1u;
        uint len_kind = token_kind(len_i);
        len_name_is_present =
            len_kind == TK_IDENT || len_kind == TK_TYPE_IDENT || len_kind == TK_PARAM_IDENT;
        if (len_name_is_present)
            len_is_generic = find_const_generic_param_decl(len_i) != INVALID;
    }

    if (!elem_is_generic && !len_name_is_present)
        return false;
    if (!generic_array_decl_context_allowed(open_i))
        return true;
    if (!elem_is_generic && !elem_is_primitive)
        return true;
    if (len_name_is_present && !len_is_generic)
        return true;
    return false;
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
        elem = language_type_code_for_token(cur);
        if (elem == TY_UNKNOWN)
            elem = generic_type_code_for_name(cur);
        if (elem == TY_UNKNOWN && array_depth == 0u && cur < active_token_count())
            elem = module_type_path_type[cur];
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

bool is_self_receiver_decl_at(uint i)
{
    if (token_kind(i) != TK_SELF_VALUE || i == 0u)
        return false;
    uint prev = token_kind(i - 1u);
    uint next = i + 1u < active_token_count() ? token_kind(i + 1u) : 0u;
    bool prev_ok = prev == TK_PARAM_LPAREN || prev == TK_LPAREN || prev == TK_PARAM_COMMA ||
                   prev == TK_COMMA || prev == TK_AMPERSAND;
    bool next_ok = next == TK_COLON || next == TK_PARAM_RPAREN || next == TK_RPAREN ||
                   next == TK_PARAM_COMMA || next == TK_COMMA;
    return prev_ok && next_ok;
}

uint impl_body_open(uint impl_i)
{
    uint n_active = active_token_count();
    [loop]
    for (uint j = impl_i + 1u; j < n_active; j += 1u)
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

bool is_bool_result_operator(uint kind)
{
    return kind == TK_LT || kind == TK_GT || kind == TK_LE || kind == TK_GE || kind == TK_EQEQ ||
           kind == TK_NOT_EQUAL || kind == TK_ANDAND || kind == TK_OROR;
}

bool token_in_impl_header(uint token_i)
{
    uint j = token_i;
    [loop]
    for (uint guard = 0u; guard < 128u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind == TK_IMPL)
        {
            uint open_i = impl_body_open(j);
            return open_i != INVALID && token_i > j && token_i < open_i;
        }
        if (kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_RBRACE ||
            kind == TK_IF_RBRACE || kind == TK_FN || kind == TK_SEMICOLON)
            return false;
    }
    return false;
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

uint let_decl_semicolon(uint decl_i)
{
    if (has_token_aligned_hir() && decl_i > 0u && token_kind(decl_i - 1u) == TK_LET &&
        decl_i < active_hir_node_count())
    {
        uint end_i = hir_token_end[decl_i];
        if (end_i != INVALID && end_i > decl_i)
        {
            uint semi = end_i - 1u;
            if (token_kind(semi) == TK_SEMICOLON)
                return semi;
        }
    }
    return find_stmt_semicolon(decl_i);
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
                    !(variant_decl + 1u < n_active && is_group_open_kind(token_kind(variant_decl + 1u))))
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

bool find_named_function(uint name_i)
{
    return name_i < active_token_count() && call_fn_index[name_i] != INVALID;
}

uint resolved_visible_decl(uint ident_i)
{
    if (ident_i >= active_token_count())
        return INVALID;
    return visible_decl[ident_i];
}

uint declaration_type_shallow(uint decl_i)
{
    uint kind = token_kind(decl_i);
    if (kind == TK_SELF_VALUE && is_self_receiver_decl_at(decl_i))
        return decl_i + 2u < active_token_count() && token_kind(decl_i + 1u) == TK_COLON
                   ? type_code_for_type_expr(decl_i + 2u)
                   : TY_UNKNOWN;
    if (kind == TK_SELF_VALUE)
        return TY_UNKNOWN;
    if ((kind == TK_IDENT || kind == TK_TYPE_IDENT) && visible_decl[decl_i] == decl_i &&
        visible_type[decl_i] != TY_UNKNOWN &&
        !(decl_i + 1u < active_token_count() && token_kind(decl_i + 1u) == TK_COLON))
        return visible_type[decl_i];

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

        uint semi = let_decl_semicolon(decl_i);
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
                if (is_intrinsic_name(cur))
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

uint declaration_type(uint decl_i)
{
    for (uint depth = 0u; depth < 8u && decl_i != INVALID; depth += 1u)
    {
        uint shallow = declaration_type_shallow(decl_i);
        if (shallow != TY_UNKNOWN)
            return shallow;

        if (!(token_kind(decl_i) == TK_LET_IDENT ||
              (token_kind(decl_i) == TK_IDENT && decl_i > 0u && token_kind(decl_i - 1u) == TK_LET)))
            return TY_UNKNOWN;

        uint semi = let_decl_semicolon(decl_i);
        if (semi == INVALID)
            return TY_UNKNOWN;
        uint assign_i = find_let_assign(decl_i, semi);
        if (assign_i == INVALID || assign_i + 1u >= semi)
            return TY_UNKNOWN;

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
            if (head_kind == TK_IDENT &&
                !(cur + 1u < semi &&
                  (token_kind(cur + 1u) == TK_CALL_LPAREN || token_kind(cur + 1u) == TK_LPAREN)))
            {
                uint next_decl = resolved_visible_decl(cur);
                if (next_decl == INVALID || next_decl == decl_i)
                    return TY_UNKNOWN;
                decl_i = next_decl;
                followed = true;
            }
            break;
        }
        if (!followed)
            return TY_UNKNOWN;
    }
    return TY_UNKNOWN;
}

bool ident_is_use(uint i)
{
    uint kind = token_kind(i);
    if (kind == TK_SELF_VALUE)
    {
        return !is_self_receiver_decl_at(i) && (i == 0u || token_kind(i - 1u) != TK_DOT);
    }
    if (kind != TK_IDENT)
        return false;
    if (is_in_match_pattern(i))
        return false;
    if (token_in_impl_header(i))
        return false;
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    if (prev == TK_FN || prev == TK_DOT || prev == TK_LET || prev == TK_CONST ||
        prev == TK_ENUM || prev == TK_STRUCT || prev == TK_COLON)
        return false;
    uint next = i + 1u < active_token_count() ? token_kind(i + 1u) : 0u;
    if (next == TK_COLON)
        return false;
    return true;
}

bool ident_resolves_in_scope(uint i)
{
    if (module_value_path_status[i] == PATH_RESOLVE_STATUS_OK)
        return true;
    if (is_intrinsic_name(i))
        return true;
    if (i + 1u < active_token_count() && token_kind(i + 1u) == TK_LBRACE &&
        find_struct_decl_name(i) != INVALID)
        return true;
    if (find_enum_variant_decl(i) != INVALID)
        return true;
    if (i + 1u < active_token_count() &&
        (token_kind(i + 1u) == TK_CALL_LPAREN || token_kind(i + 1u) == TK_LPAREN))
        return find_named_function(i);
    return resolved_visible_decl(i) != INVALID;
}

void check_ident_use(uint i)
{
    if (!ident_is_use(i))
        return;
    if (!ident_resolves_in_scope(i))
        record_error(i, ERR_UNRESOLVED_IDENT, 0u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i < active_token_count())
    {
        if (token_kind(i) == TK_TRAIT)
            record_error(i, ERR_BAD_HIR, TK_TRAIT);
        if (token_kind(i) == TK_FOR && token_in_impl_header(i))
            record_error(i, ERR_BAD_HIR, TK_FOR);
        if (token_kind(i) == TK_WHERE)
            record_error(i, ERR_BAD_HIR, TK_WHERE);
        if (is_generic_bound_colon(i))
            record_error(i, ERR_BAD_HIR, TK_COLON);
        if (is_invalid_generic_array_or_slice_type(i))
            record_error(i, ERR_BAD_HIR, TK_TYPE_ARRAY_LBRACKET);
        uint value_path_status = module_value_path_status[i];
        if (value_path_status != PATH_RESOLVE_STATUS_INVALID &&
            value_path_status != PATH_RESOLVE_STATUS_OK)
            record_error(i, ERR_UNRESOLVED_IDENT, value_path_status);
        if (is_self_receiver_decl_at(i) ||
            token_kind(i) == TK_PARAM_IDENT ||
            (token_kind(i) == TK_IDENT && i + 1u < active_token_count() &&
             token_kind(i + 1u) == TK_COLON &&
             (i == 0u ||
              (token_kind(i - 1u) != TK_LET && token_kind(i - 1u) != TK_CONST &&
               token_kind(i - 1u) != TK_ENUM && token_kind(i - 1u) != TK_STRUCT))) ||
            token_kind(i) == TK_LET_IDENT ||
            (token_kind(i) == TK_IDENT && i > 0u && token_kind(i - 1u) == TK_LET) ||
            is_const_decl_at(i))
        {
            visible_type[i] = declaration_type(i);
        }

        if (ident_is_use(i) && !is_intrinsic_name(i) &&
            !(i + 1u < active_token_count() &&
              (token_kind(i + 1u) == TK_CALL_LPAREN || token_kind(i + 1u) == TK_LPAREN)))
        {
            uint decl = resolved_visible_decl(i);
            if (decl != INVALID)
                visible_type[i] = declaration_type(decl);
        }

        if (token_kind(i) == TK_SELF_VALUE)
            check_ident_use(i);
    }

    uint n_hir = active_hir_node_count();
    if (i < n_hir)
    {
        if (hir_kind[i] == HIR_NAME_EXPR)
        {
            uint pos = hir_token_pos[i];
            if (pos == INVALID || pos >= active_token_count())
                record_error(active_token_count(), ERR_BAD_HIR, pos);
            else
                check_ident_use(pos);
        }
    }

    if (n_hir != 0u || i >= active_token_count())
        return;

    check_ident_use(i);
}
