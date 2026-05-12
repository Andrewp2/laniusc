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
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_state;

RWStructuredBuffer<uint> call_return_type;

static const uint INVALID = 0xffffffffu;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint TYPE_INSTANCE_RESOLVED = 1u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_STRING = 7u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint TK_IDENT = 1u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LBRACKET = 20u;
static const uint TK_LBRACE = 22u;
static const uint TK_INDEX_LBRACKET = 30u;
static const uint TK_COMMA = 36u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_FN = 67u;
static const uint TK_CONST = 92u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;

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

bool same_text(uint a, uint b)
{
    uint len = token_len(a);
    if (len != token_len(b))
        return false;

    uint sa = token_start(a);
    uint sb = token_start(b);
    [loop]
    for (uint i = 0u; i < len; i += 1u)
    {
        if (source_at(sa, i) != source_at(sb, i))
            return false;
    }
    return true;
}

bool is_index_open(uint kind)
{
    return kind == TK_INDEX_LBRACKET || kind == TK_LBRACKET;
}

bool is_type_name_token(uint i)
{
    return token_kind(i) == TK_IDENT;
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
        if (kind == TK_LBRACE || kind == TK_SEMICOLON)
            return INVALID;
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
    if (param_i <= open_i || param_i >= close_i || !is_type_name_token(param_i))
        return false;
    if (param_i > open_i + 1u && token_kind(param_i - 1u) == TK_CONST)
        return false;
    return true;
}

uint generic_param_decl_for_use(uint name_i)
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
            if (is_type_generic_param_token(p, open_i, close_i) && same_text(p, name_i))
                return p;
        }
        return INVALID;
    }
    return INVALID;
}

uint instance_from_ref(uint tag, uint payload)
{
    return tag == TYPE_REF_INSTANCE ? payload : INVALID;
}

uint array_or_slice_instance_from_decl(uint decl_i)
{
    if (decl_i == INVALID || decl_i + 2u >= active_token_count() ||
        token_kind(decl_i + 1u) != TK_COLON)
        return INVALID;

    uint type_head = decl_i + 2u;
    if (type_expr_ref_tag[type_head] != TYPE_REF_INSTANCE)
        return INVALID;

    uint instance_i = instance_from_ref(type_expr_ref_tag[type_head], type_expr_ref_payload[type_head]);
    if (instance_i >= active_token_count() || type_instance_state[instance_i] != TYPE_INSTANCE_RESOLVED)
        return INVALID;

    uint kind = type_instance_kind[instance_i];
    return kind == TYPE_INSTANCE_ARRAY || kind == TYPE_INSTANCE_SLICE ? instance_i : INVALID;
}

uint type_ref_to_type_code(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
    {
        if (payload <= TY_STRING)
            return payload;
        uint decl_i = generic_param_decl_for_use(payload);
        return decl_i == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + decl_i;
    }
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint decl_i = generic_param_decl_for_use(payload);
        return decl_i == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + decl_i;
    }
    return TY_UNKNOWN;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint n = active_token_count();
    if (i + 1u >= n || token_kind(i) != TK_IDENT || !is_index_open(token_kind(i + 1u)))
        return;

    uint decl_i = visible_decl[i];
    uint instance_i = array_or_slice_instance_from_decl(decl_i);
    if (instance_i == INVALID)
        return;

    uint elem_ty = type_ref_to_type_code(type_instance_elem_ref_tag[instance_i],
                                         type_instance_elem_ref_payload[instance_i]);
    if (elem_ty != TY_UNKNOWN)
        call_return_type[i + 1u] = elem_ty;
}
