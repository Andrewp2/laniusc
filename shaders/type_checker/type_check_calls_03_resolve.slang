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
StructuredBuffer<uint4> call_arg_record;

RWStructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_intrinsic_tag;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_type;
StructuredBuffer<uint> function_lookup_key;
StructuredBuffer<uint> function_lookup_fn;

static const uint INVALID = 0xffffffffu;
static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint LANGUAGE_DECL_COUNT = 18u;
static const uint LANGUAGE_PRIMITIVE_DECL_FIRST = 3u;
static const uint ERR_UNRESOLVED_IDENT = 2u;
static const uint ERR_ASSIGN_MISMATCH = 3u;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_STRING = 32u;
static const uint TK_FLOAT = 33u;
static const uint TK_CHAR = 34u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_FN = 67u;
static const uint TK_LET = 68u;
static const uint TK_ARROW = 75u;
static const uint TK_PARAM_LPAREN = 76u;
static const uint TK_PARAM_RPAREN = 77u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_PARAM_COMMA = 84u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_CONST = 92u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint PARAM_CACHE_STRIDE = 16u;
static const uint INTRINSIC_NONE = 0u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint lookup_capacity()
{
    return max(gParams.n_tokens * 2u, 1u);
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

bool is_generic_type(uint ty)
{
    return ty >= TY_GENERIC_BASE;
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

uint enclosing_function_start(uint target_i)
{
    uint j = min(target_i, active_token_count());
    [loop]
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        j -= 1u;
        if (token_kind(j) == TK_FN)
            return j;
    }
    return INVALID;
}

uint generic_type_code_for_name(uint name_i)
{
    uint fn_i = enclosing_function_start(name_i);
    if (fn_i == INVALID)
        return TY_UNKNOWN;

    uint open_i = generic_param_list_open(fn_i);
    if (open_i == INVALID)
        return TY_UNKNOWN;
    uint close_i = generic_param_list_close(open_i);
    if (close_i == INVALID)
        return TY_UNKNOWN;

    [loop]
    for (uint p = open_i + 1u; p < close_i; p += 1u)
    {
        if (is_type_generic_param_token(p, open_i, close_i) && same_name_id(p, name_i))
            return TY_GENERIC_BASE + p;
    }
    return TY_UNKNOWN;
}

uint type_code_for_type_expr(uint type_i)
{
    uint kind = token_kind(type_i);
    if (kind != TK_TYPE_IDENT && kind != TK_IDENT)
        return TY_UNKNOWN;

    uint elem = language_type_code_for_token(type_i);
    if (elem == TY_UNKNOWN)
        elem = generic_type_code_for_name(type_i);
    return elem;
}

uint call_node_for_callee_token(uint callee_i)
{
    if (callee_i >= active_token_count())
        return INVALID;
    return call_arg_record[callee_i * PARAM_CACHE_STRIDE].z;
}

uint call_arg_count_for_callee(uint callee_i)
{
    if (callee_i >= active_token_count())
        return 0u;
    return call_arg_record[callee_i * PARAM_CACHE_STRIDE].w;
}

bool call_arg_token_range(uint callee_i, uint ordinal, out uint arg_start_i, out uint arg_end_i)
{
    arg_start_i = INVALID;
    arg_end_i = INVALID;
    if (callee_i >= active_token_count() || ordinal >= PARAM_CACHE_STRIDE)
        return false;
    uint4 record = call_arg_record[callee_i * PARAM_CACHE_STRIDE + ordinal];
    arg_start_i = record.x;
    arg_end_i = record.y;
    return arg_start_i != INVALID && arg_end_i != INVALID && arg_start_i < arg_end_i;
}

uint function_value_params_start(uint fn_i)
{
    uint n_active = active_token_count();
    uint j = fn_i + 2u;
    if (j < n_active && token_kind(j) == TK_LT)
    {
        uint close_i = generic_param_list_close(j);
        if (close_i == INVALID)
            return INVALID;
        j = close_i + 1u;
    }

    [loop]
    for (; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_PARAM_LPAREN || kind == TK_LPAREN)
            return j + 1u;
        if (kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_SEMICOLON)
            return INVALID;
    }
    return INVALID;
}

bool is_param_decl(uint i)
{
    uint n_active = active_token_count();
    uint kind = token_kind(i);
    return (kind == TK_PARAM_IDENT || kind == TK_IDENT) && i + 1u < n_active &&
           token_kind(i + 1u) == TK_COLON;
}

uint local_identifier_type(uint name_i)
{
    uint fn_i = enclosing_function_start(name_i);
    if (fn_i == INVALID)
        return TY_UNKNOWN;

    uint start_i = function_value_params_start(fn_i);
    if (start_i == INVALID)
        return TY_UNKNOWN;

    [loop]
    for (uint j = start_i; j < name_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_PARAM_RPAREN || kind == TK_RPAREN || kind == TK_LBRACE ||
            kind == TK_IF_LBRACE)
            break;
        if (is_param_decl(j) && same_name_id(j, name_i))
            return type_code_for_type_expr(j + 2u);
    }

    [loop]
    for (uint j = fn_i + 1u; j + 3u < name_i; j += 1u)
    {
        if (token_kind(j) != TK_LET)
            continue;
        uint ident_i = j + 1u;
        if ((token_kind(ident_i) == TK_LET_IDENT || token_kind(ident_i) == TK_IDENT) &&
            same_name_id(ident_i, name_i) && token_kind(ident_i + 1u) == TK_COLON)
            return type_code_for_type_expr(ident_i + 2u);
    }

    return TY_UNKNOWN;
}

uint find_function_decl_by_name(uint name_i)
{
    if (name_i >= active_token_count() || token_kind(name_i) != TK_IDENT)
        return INVALID;

    uint cap = lookup_capacity();
    uint key = name_id_by_token[name_i];
    if (key == INVALID)
        return INVALID;
    uint start_slot = key % cap;
    [loop]
    for (uint probe = 0u; probe < cap; probe += 1u)
    {
        uint slot = (start_slot + probe) % cap;
        uint fn_i = function_lookup_fn[slot];
        if (fn_i == INVALID)
            return INVALID;
        if (function_lookup_key[slot] == key)
            return fn_i;
    }
    return INVALID;
}

uint leading_arg_token(uint arg_start_i, uint arg_end_i)
{
    uint cur = arg_start_i;
    [loop]
    for (uint guard = 0u; guard < 16u && cur < arg_end_i && cur < active_token_count();
         guard += 1u)
    {
        uint kind = token_kind(cur);
        if (kind == TK_GROUP_LPAREN || kind == TK_LPAREN)
        {
            cur += 1u;
            continue;
        }
        break;
    }
    return cur;
}

uint literal_or_identifier_arg_type_direct(uint arg_start_i, uint arg_end_i)
{
    uint cur = leading_arg_token(arg_start_i, arg_end_i);
    uint kind = token_kind(cur);
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
    if (kind == TK_IDENT)
        return local_identifier_type(cur);
    return TY_UNKNOWN;
}

uint inferred_generic_return_type_direct(uint callee_i, uint fn_i, uint ret_ty)
{
    if (call_node_for_callee_token(callee_i) == INVALID)
        return TY_UNKNOWN;

    uint param_count = fn_i < active_token_count() ? call_param_count[fn_i] : 0u;
    uint arg_count = call_arg_count_for_callee(callee_i);
    if (arg_count != param_count)
        return TY_UNKNOWN;

    uint inferred = TY_UNKNOWN;
    [loop]
    for (uint arg_i = 0u; arg_i < arg_count && arg_i < PARAM_CACHE_STRIDE; arg_i += 1u)
    {
        uint param_ty = call_param_type[fn_i * PARAM_CACHE_STRIDE + arg_i];
        if (param_ty != ret_ty)
            continue;

        uint arg_start_i;
        uint arg_end_i;
        if (!call_arg_token_range(callee_i, arg_i, arg_start_i, arg_end_i))
            return TY_UNKNOWN;
        uint arg_ty = literal_or_identifier_arg_type_direct(arg_start_i, arg_end_i);
        if (arg_ty == TY_UNKNOWN)
            return TY_UNKNOWN;
        if (inferred == TY_UNKNOWN)
            inferred = arg_ty;
        else if (inferred != arg_ty)
            return TY_UNKNOWN;
    }

    return inferred;
}

uint direct_call_return_type_direct(uint callee_i)
{
    uint fn_i = find_function_decl_by_name(callee_i);
    if (fn_i == INVALID)
        return TY_UNKNOWN;

    uint ret_ty = call_return_type[fn_i];
    if (!is_generic_type(ret_ty))
        return ret_ty;
    return inferred_generic_return_type_direct(callee_i, fn_i, ret_ty);
}

uint literal_or_identifier_arg_type(uint arg_start_i, uint arg_end_i)
{
    uint cur = leading_arg_token(arg_start_i, arg_end_i);
    uint call_node = call_node_for_callee_token(cur);
    if (call_node != INVALID)
    {
        uint cached_call_ty = call_return_type[cur];
        if (cached_call_ty != TY_UNKNOWN)
            return cached_call_ty;
        return direct_call_return_type_direct(cur);
    }
    return literal_or_identifier_arg_type_direct(arg_start_i, arg_end_i);
}

uint inferred_generic_return_type(uint callee_i, uint fn_i, uint ret_ty)
{
    if (call_node_for_callee_token(callee_i) == INVALID)
        return TY_UNKNOWN;

    uint param_count = fn_i < active_token_count() ? call_param_count[fn_i] : 0u;
    uint arg_count = call_arg_count_for_callee(callee_i);
    if (arg_count != param_count)
        return TY_UNKNOWN;

    uint inferred = TY_UNKNOWN;
    [loop]
    for (uint arg_i = 0u; arg_i < arg_count && arg_i < PARAM_CACHE_STRIDE; arg_i += 1u)
    {
        uint param_ty = call_param_type[fn_i * PARAM_CACHE_STRIDE + arg_i];
        if (param_ty != ret_ty)
            continue;

        uint arg_start_i;
        uint arg_end_i;
        if (!call_arg_token_range(callee_i, arg_i, arg_start_i, arg_end_i))
            return TY_UNKNOWN;
        uint arg_ty = literal_or_identifier_arg_type(arg_start_i, arg_end_i);
        if (arg_ty == TY_UNKNOWN)
            return TY_UNKNOWN;
        if (inferred == TY_UNKNOWN)
            inferred = arg_ty;
        else if (inferred != arg_ty)
            return TY_UNKNOWN;
    }

    return inferred;
}

bool check_generic_argument_consistency(uint callee_i, uint fn_i)
{
    if (call_node_for_callee_token(callee_i) == INVALID)
        return true;

    uint param_count = fn_i < active_token_count() ? call_param_count[fn_i] : 0u;
    uint arg_count = call_arg_count_for_callee(callee_i);
    if (arg_count != param_count)
        return true;

    [loop]
    for (uint arg_i = 0u; arg_i < arg_count && arg_i < PARAM_CACHE_STRIDE; arg_i += 1u)
    {
        uint param_ty = call_param_type[fn_i * PARAM_CACHE_STRIDE + arg_i];
        if (!is_generic_type(param_ty))
            continue;

        uint arg_start_i;
        uint arg_end_i;
        if (!call_arg_token_range(callee_i, arg_i, arg_start_i, arg_end_i))
            continue;
        uint arg_ty = literal_or_identifier_arg_type(arg_start_i, arg_end_i);
        if (arg_ty == TY_UNKNOWN)
            continue;

        [loop]
        for (uint prev_i = 0u; prev_i < arg_i && prev_i < PARAM_CACHE_STRIDE; prev_i += 1u)
        {
            uint prev_param_ty = call_param_type[fn_i * PARAM_CACHE_STRIDE + prev_i];
            if (prev_param_ty != param_ty)
                continue;

            uint prev_start_i;
            uint prev_end_i;
            if (!call_arg_token_range(callee_i, prev_i, prev_start_i, prev_end_i))
                continue;
            uint prev_ty = literal_or_identifier_arg_type(prev_start_i, prev_end_i);
            if (prev_ty != TY_UNKNOWN && prev_ty != arg_ty)
            {
                record_error(arg_start_i, ERR_ASSIGN_MISMATCH, param_ty * 256u + arg_ty);
                return false;
            }
        }
    }
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint n_active = active_token_count();
    if (i >= n_active || token_kind(i) != TK_IDENT)
        return;

    uint call_node = call_node_for_callee_token(i);
    bool is_call = call_node != INVALID;

    if (call_intrinsic_tag[i] != INTRINSIC_NONE)
    {
        return;
    }

    uint cap = lookup_capacity();
    uint key = name_id_by_token[i];
    if (key == INVALID)
    {
        call_return_type[i] = TY_UNKNOWN;
        return;
    }
    uint start_slot = key % cap;
    [loop]
    for (uint probe = 0u; probe < cap; probe += 1u)
    {
        uint slot = (start_slot + probe) % cap;
        uint fn_i = function_lookup_fn[slot];
        if (fn_i == INVALID)
            return;
        if (function_lookup_key[slot] == key)
        {
            call_fn_index[i] = fn_i;
            if (is_call)
            {
                uint ret_ty = call_return_type[fn_i];
                if (!check_generic_argument_consistency(i, fn_i))
                    return;
                if (is_generic_type(ret_ty))
                {
                    uint inferred = inferred_generic_return_type(i, fn_i, ret_ty);
                    if (inferred != TY_UNKNOWN)
                        ret_ty = inferred;
                }
                call_return_type[i] = ret_ty;
                call_return_type_token[i] = call_return_type_token[fn_i];
            }
            return;
        }
    }

    call_return_type[i] = TY_UNKNOWN;
}
