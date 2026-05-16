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
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_state;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;

RWStructuredBuffer<uint> call_return_type;

static const uint INVALID = 0xffffffffu;
static const uint GENERIC_ENUM_CTOR_OK = 0xfffffffdu;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TYPE_INSTANCE_RESOLVED = 1u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_ASSIGN = 8u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_STRING = 32u;
static const uint TK_FLOAT = 33u;
static const uint TK_CHAR = 34u;
static const uint TK_COMMA = 36u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_FN = 67u;
static const uint TK_LET = 68u;
static const uint TK_RETURN = 69u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_LET_ASSIGN = 81u;
static const uint TK_ARG_COMMA = 82u;
static const uint TK_ENUM = 93u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

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

uint name_id_for_token(uint i)
{
    return i < active_token_count() ? name_id_by_token[i] : INVALID;
}

bool same_name_id(uint a, uint b)
{
    uint an = name_id_for_token(a);
    uint bn = name_id_for_token(b);
    return an != INVALID && an == bn;
}

bool is_type_name_token(uint i)
{
    uint kind = token_kind(i);
    return kind == TK_IDENT || kind == TK_TYPE_IDENT || kind == TK_PARAM_IDENT;
}

bool is_value_name_token(uint i)
{
    uint kind = token_kind(i);
    return kind == TK_IDENT || kind == TK_LET_IDENT || kind == TK_PARAM_IDENT;
}

bool is_enum_decl_name_at(uint i)
{
    uint kind = token_kind(i);
    return (kind == TK_IDENT || kind == TK_TYPE_IDENT) && i > 0u &&
           token_kind(i - 1u) == TK_ENUM;
}

uint enum_decl_open(uint enum_i)
{
    uint n = active_token_count();
    [loop]
    for (uint j = enum_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACE)
            return j;
        if (kind == TK_SEMICOLON || kind == TK_FN)
            return INVALID;
    }
    return INVALID;
}

uint enum_decl_close(uint enum_i)
{
    uint open_i = enum_decl_open(enum_i);
    if (open_i == INVALID)
        return INVALID;

    uint n = active_token_count();
    uint depth = 0u;
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
            return j;
    }
    return INVALID;
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

bool is_group_open_kind(uint kind)
{
    return kind == TK_GROUP_LPAREN || kind == TK_LPAREN || kind == TK_CALL_LPAREN;
}

bool is_group_close_kind(uint kind)
{
    return kind == TK_GROUP_RPAREN || kind == TK_RPAREN || kind == TK_CALL_RPAREN;
}

uint find_group_close(uint open_i)
{
    uint depth = 0u;
    uint n = active_token_count();
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

uint call_arg_count(uint open_i, uint close_i)
{
    if (close_i == INVALID || open_i + 1u >= close_i)
        return 0u;
    uint bracket_depth = 0u;
    uint group_depth = 0u;
    uint count = 1u;
    [loop]
    for (uint j = open_i + 1u; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if ((kind == TK_ARG_COMMA || kind == TK_COMMA) && bracket_depth == 0u &&
                 group_depth == 0u)
            count += 1u;
    }
    return count;
}

uint call_arg_start(uint open_i, uint close_i, uint arg_index)
{
    uint current = 0u;
    uint start = open_i + 1u;
    uint group_depth = 0u;
    [loop]
    for (uint j = open_i + 1u; j <= close_i; j += 1u)
    {
        uint kind = j < close_i ? token_kind(j) : TK_COMMA;
        bool boundary = j == close_i ||
                        ((kind == TK_ARG_COMMA || kind == TK_COMMA) && group_depth == 0u);
        if (boundary)
        {
            if (current == arg_index)
                return start < j ? start : INVALID;
            current += 1u;
            start = j + 1u;
            continue;
        }
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
    }
    return INVALID;
}

uint call_arg_end(uint arg_start_i, uint close_i)
{
    uint group_depth = 0u;
    [loop]
    for (uint j = arg_start_i; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if ((kind == TK_ARG_COMMA || kind == TK_COMMA) && group_depth == 0u)
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
    return open_i == INVALID ? INVALID : find_group_close(open_i);
}

uint enum_variant_payload_count(uint variant_i)
{
    uint open_i = enum_variant_payload_open(variant_i);
    if (open_i == INVALID)
        return 0u;
    uint close_i = enum_variant_payload_close(variant_i);
    return close_i == INVALID ? 0u : call_arg_count(open_i, close_i);
}

uint enum_variant_payload_type_head(uint variant_i, uint field_index)
{
    uint open_i = enum_variant_payload_open(variant_i);
    if (open_i == INVALID)
        return INVALID;
    uint close_i = enum_variant_payload_close(variant_i);
    if (close_i == INVALID)
        return INVALID;
    return call_arg_start(open_i, close_i, field_index);
}

uint instance_from_type_head(uint type_head)
{
    if (type_head == INVALID || type_expr_ref_tag[type_head] != TYPE_REF_INSTANCE)
        return INVALID;
    uint instance_i = type_expr_ref_payload[type_head];
    if (instance_i >= active_token_count() || type_instance_state[instance_i] != TYPE_INSTANCE_RESOLVED)
        return INVALID;
    return instance_i;
}

bool instance_args_are_concrete_scalars(uint instance_i)
{
    if (instance_i >= active_token_count())
        return false;
    uint count = type_instance_arg_count[instance_i];
    if (count > TYPE_INSTANCE_ARG_REF_STRIDE)
        return false;
    [loop]
    for (uint slot = 0u; slot < TYPE_INSTANCE_ARG_REF_STRIDE; slot += 1u)
    {
        if (slot >= count)
            break;
        uint arg_i = type_instance_arg_start[instance_i] + slot;
        if (type_instance_arg_ref_tag[arg_i] != TYPE_REF_SCALAR)
            return false;
    }
    return true;
}

bool instance_args_are_supported(uint instance_i, bool allow_generic_params)
{
    if (instance_i >= active_token_count())
        return false;
    uint count = type_instance_arg_count[instance_i];
    if (count > TYPE_INSTANCE_ARG_REF_STRIDE)
        return false;
    [loop]
    for (uint slot = 0u; slot < TYPE_INSTANCE_ARG_REF_STRIDE; slot += 1u)
    {
        if (slot >= count)
            break;
        uint arg_i = type_instance_arg_start[instance_i] + slot;
        uint tag = type_instance_arg_ref_tag[arg_i];
        if (tag == TYPE_REF_SCALAR)
            continue;
        if (allow_generic_params && tag == TYPE_REF_GENERIC_PARAM)
            continue;
        return false;
    }
    return true;
}

uint instance_from_annotated_let(uint callee_i)
{
    uint assign_i = INVALID;
    uint j = callee_i;
    [loop]
    for (uint guard = 0u; guard < 128u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind == TK_LET_ASSIGN || kind == TK_ASSIGN)
        {
            assign_i = j;
            break;
        }
        if (kind == TK_SEMICOLON || kind == TK_LBRACE || kind == TK_RBRACE || kind == TK_FN ||
            kind == TK_RETURN)
            return INVALID;
    }
    if (assign_i == INVALID)
        return INVALID;

    j = assign_i;
    [loop]
    for (uint guard = 0u; guard < 128u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind == TK_LET_IDENT || (kind == TK_IDENT && j > 0u && token_kind(j - 1u) == TK_LET))
        {
            if (j + 2u < active_token_count() && token_kind(j + 1u) == TK_COLON)
                return instance_from_type_head(j + 2u);
            return INVALID;
        }
        if (kind == TK_SEMICOLON || kind == TK_LBRACE || kind == TK_RBRACE || kind == TK_FN)
            return INVALID;
    }
    return INVALID;
}

uint enclosing_function_start(uint token_i)
{
    if (token_i >= active_token_count())
        return INVALID;
    uint encoded = enclosing_fn[token_i];
    if (encoded != 0u)
        return encoded - 1u;

    uint j = token_i;
    [loop]
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        j -= 1u;
        if (token_kind(j) == TK_FN)
            return j;
    }
    return INVALID;
}

uint instance_from_ref(uint tag, uint payload)
{
    return tag == TYPE_REF_INSTANCE && payload < active_token_count() ? payload : INVALID;
}

uint instance_from_enclosing_return(uint callee_i, out uint return_i)
{
    return_i = INVALID;
    uint j = callee_i;
    [loop]
    for (uint guard = 0u; guard < 128u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind == TK_RETURN)
        {
            return_i = j;
            uint fn_i = enclosing_function_start(j);
            if (fn_i == INVALID)
                return INVALID;
            return instance_from_ref(fn_return_ref_tag[fn_i], fn_return_ref_payload[fn_i]);
        }
        if (kind == TK_SEMICOLON || kind == TK_LBRACE || kind == TK_RBRACE ||
            kind == TK_LET_ASSIGN || kind == TK_ASSIGN)
            return INVALID;
    }
    return INVALID;
}

uint context_instance_for_constructor(uint callee_i, out uint return_i)
{
    return_i = INVALID;
    uint instance_i = instance_from_annotated_let(callee_i);
    if (instance_i != INVALID)
        return instance_i;
    return instance_from_enclosing_return(callee_i, return_i);
}

uint generic_param_list_open(uint item_i)
{
    uint n = active_token_count();
    [loop]
    for (uint j = item_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LPAREN || kind == TK_LBRACE || kind == TK_SEMICOLON)
            return INVALID;
        if (kind == TK_IDENT && token_kind(j - 1u) == TK_LPAREN)
            return INVALID;
        if (kind == TK_COLON)
            return INVALID;
        if (kind == TK_LT)
            return j;
    }
    return INVALID;
}

uint generic_param_list_close(uint open_i)
{
    if (open_i == INVALID)
        return INVALID;
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
    return param_i > open_i && param_i < close_i && is_type_name_token(param_i);
}

uint generic_param_slot(uint decl_i, uint param_i)
{
    uint open_i = generic_param_list_open(decl_i);
    uint close_i = generic_param_list_close(open_i);
    if (open_i == INVALID || close_i == INVALID)
        return INVALID;

    uint slot = 0u;
    [loop]
    for (uint p = open_i + 1u; p < close_i; p += 1u)
    {
        if (!is_type_generic_param_token(p, open_i, close_i))
            continue;
        if (same_name_id(p, param_i))
            return slot;
        slot += 1u;
    }
    return INVALID;
}

uint generic_param_decl_for_use(uint name_i)
{
    uint j = name_i;
    [loop]
    for (uint guard = 0u; guard < 256u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind != TK_FN && kind != TK_ENUM)
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
            if (is_type_generic_param_token(p, open_i, close_i) && same_name_id(p, name_i))
                return p;
        }
    }
    return INVALID;
}

void substituted_ref(uint instance_i, uint type_head, out uint tag, out uint payload)
{
    tag = type_expr_ref_tag[type_head];
    payload = type_expr_ref_payload[type_head];
    if (tag != TYPE_REF_GENERIC_PARAM)
        return;

    uint decl_i = type_instance_decl_token[instance_i];
    uint slot = generic_param_slot(decl_i, payload);
    if (slot == INVALID || slot >= type_instance_arg_count[instance_i])
        return;

    uint arg_i = type_instance_arg_start[instance_i] + slot;
    tag = type_instance_arg_ref_tag[arg_i];
    payload = type_instance_arg_ref_payload[arg_i];
}

uint type_ref_to_type_code(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint decl_i = generic_param_decl_for_use(payload);
        return decl_i == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + decl_i;
    }
    return TY_UNKNOWN;
}

uint actual_arg_type(uint arg_start_i, uint arg_end_i)
{
    uint cur = arg_start_i;
    [loop]
    for (uint guard = 0u; guard < 16u && cur < arg_end_i && cur < active_token_count();
         guard += 1u)
    {
        uint kind = token_kind(cur);
        if (is_group_open_kind(kind))
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
        if (is_value_name_token(cur))
        {
            if (cur + 1u < arg_end_i &&
                (token_kind(cur + 1u) == TK_CALL_LPAREN || token_kind(cur + 1u) == TK_LPAREN))
                return call_return_type[cur];
            return visible_type[cur];
        }
        return TY_UNKNOWN;
    }
    return TY_UNKNOWN;
}

bool assignable(uint dst, uint src)
{
    if (dst == TY_UNKNOWN || src == TY_UNKNOWN)
        return false;
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

bool validate_generic_enum_constructor(uint callee_i, uint open_i, uint close_i, out uint return_i)
{
    return_i = INVALID;
    uint variant_i = find_enum_variant_decl(callee_i);
    if (variant_i == INVALID)
        return false;

    uint enum_decl_i = enum_type_for_variant_decl(variant_i);
    if (enum_decl_i == INVALID)
        return false;

    uint instance_i = context_instance_for_constructor(callee_i, return_i);
    if (instance_i == INVALID || type_instance_decl_token[instance_i] != enum_decl_i ||
        !instance_args_are_supported(instance_i, return_i != INVALID))
        return false;

    uint expected_count = enum_variant_payload_count(variant_i);
    uint actual_count = call_arg_count(open_i, close_i);
    if (actual_count != expected_count)
        return false;

    [loop]
    for (uint arg_i = 0u; arg_i < actual_count && arg_i < 16u; arg_i += 1u)
    {
        uint payload_type_head = enum_variant_payload_type_head(variant_i, arg_i);
        if (payload_type_head == INVALID)
            return false;

        uint tag = TYPE_REF_INVALID;
        uint payload = INVALID;
        substituted_ref(instance_i, payload_type_head, tag, payload);
        uint dst = type_ref_to_type_code(tag, payload);
        uint arg_start_i = call_arg_start(open_i, close_i, arg_i);
        if (arg_start_i == INVALID)
            return false;
        uint src = actual_arg_type(arg_start_i, call_arg_end(arg_start_i, close_i));
        if (!assignable(dst, src))
            return false;
    }

    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint n = active_token_count();
    if (i >= n)
        return;

    if (token_kind(i) != TK_IDENT || i + 1u >= n)
        return;

    uint open_kind = token_kind(i + 1u);
    if (open_kind != TK_CALL_LPAREN && open_kind != TK_LPAREN)
        return;

    uint close_i = find_group_close(i + 1u);
    if (close_i == INVALID)
        return;

    uint return_i = INVALID;
    if (validate_generic_enum_constructor(i, i + 1u, close_i, return_i))
    {
        call_return_type[i] = GENERIC_ENUM_CTOR_OK;
        if (return_i != INVALID)
            call_return_type[return_i] = GENERIC_ENUM_CTOR_OK;
    }
}
