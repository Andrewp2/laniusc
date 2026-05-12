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
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> type_instance_state;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;

RWStructuredBuffer<uint> call_return_type;

static const uint INVALID = 0xffffffffu;
static const uint ARRAY_RETURN_OK = 0xfffffffeu;

static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_RESOLVED = 1u;
static const uint TYPE_LEN_LITERAL = 1u;

static const uint TY_INT = 3u;

static const uint TK_IDENT = 1u;
static const uint TK_LBRACKET = 20u;
static const uint TK_FN = 67u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_RETURN = 69u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;

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

bool is_value_name_token(uint i)
{
    uint kind = token_kind(i);
    return kind == TK_IDENT || kind == TK_LET_IDENT || kind == TK_PARAM_IDENT;
}

bool is_type_array_open(uint kind)
{
    return kind == TK_TYPE_ARRAY_LBRACKET || kind == TK_LBRACKET;
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

uint concrete_i32_array_instance(uint instance_i)
{
    if (instance_i >= active_token_count())
        return INVALID;
    if (type_instance_state[instance_i] != TYPE_INSTANCE_RESOLVED ||
        type_instance_kind[instance_i] != TYPE_INSTANCE_ARRAY)
        return INVALID;
    if (type_instance_elem_ref_tag[instance_i] != TYPE_REF_SCALAR ||
        type_instance_elem_ref_payload[instance_i] != TY_INT)
        return INVALID;
    if (type_instance_len_kind[instance_i] != TYPE_LEN_LITERAL)
        return INVALID;
    return instance_i;
}

uint annotated_decl_instance(uint decl_i)
{
    if (decl_i + 2u >= active_token_count() || token_kind(decl_i + 1u) != TK_COLON)
        return INVALID;
    uint type_head = decl_i + 2u;
    if (!is_type_array_open(token_kind(type_head)))
        return INVALID;
    return concrete_i32_array_instance(
        instance_from_ref(type_expr_ref_tag[type_head], type_expr_ref_payload[type_head]));
}

bool same_concrete_array(uint lhs_instance, uint rhs_instance)
{
    lhs_instance = concrete_i32_array_instance(lhs_instance);
    rhs_instance = concrete_i32_array_instance(rhs_instance);
    if (lhs_instance == INVALID || rhs_instance == INVALID)
        return false;
    return type_instance_len_payload[lhs_instance] == type_instance_len_payload[rhs_instance];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint n = active_token_count();
    if (i >= n || token_kind(i) != TK_RETURN)
        return;

    uint first = i + 1u;
    if (first + 1u >= n || !is_value_name_token(first) || token_kind(first + 1u) != TK_SEMICOLON)
        return;

    uint fn_i = enclosing_function_start(i);
    if (fn_i == INVALID)
        return;

    uint dst_instance =
        concrete_i32_array_instance(instance_from_ref(fn_return_ref_tag[fn_i], fn_return_ref_payload[fn_i]));
    if (dst_instance == INVALID)
        return;

    uint decl_i = visible_decl[first];
    uint src_instance = annotated_decl_instance(decl_i);
    if (src_instance == INVALID)
        return;
    if (same_concrete_array(dst_instance, src_instance))
        call_return_type[i] = ARRAY_RETURN_OK;
}
