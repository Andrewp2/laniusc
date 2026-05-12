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
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;

RWStructuredBuffer<uint> visible_type;
RWStructuredBuffer<uint> struct_init_field_expected_ref_tag;
RWStructuredBuffer<uint> struct_init_field_expected_ref_payload;

static const uint INVALID = 0xffffffffu;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint TK_IDENT = 1u;
static const uint TK_ASSIGN = 8u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LPAREN = 4u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_CONST = 92u;
static const uint TK_FN = 67u;
static const uint TK_LET = 68u;
static const uint TK_RETURN = 69u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_LET_ASSIGN = 81u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_PARAM_IDENT = 79u;

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

bool is_type_name_token(uint i)
{
    uint kind = token_kind(i);
    return kind == TK_IDENT || kind == TK_TYPE_IDENT || kind == TK_PARAM_IDENT;
}

bool is_struct_decl_name_at(uint i)
{
    return token_kind(i) == TK_IDENT && i > 0u && token_kind(i - 1u) == TK_STRUCT;
}

uint find_struct_decl_name(uint name_i)
{
    uint n = active_token_count();
    [loop]
    for (uint j = 1u; j < n; j += 1u)
    {
        if (is_struct_decl_name_at(j) && same_text(j, name_i))
            return j;
    }
    return INVALID;
}

uint decl_to_type_code(uint decl_i)
{
    if (decl_i == INVALID)
        return TY_UNKNOWN;
    if (decl_i > 0u && token_kind(decl_i - 1u) == TK_STRUCT)
        return TY_STRUCT_BASE + decl_i;
    if (decl_i > 0u && token_kind(decl_i - 1u) == TK_ENUM)
        return TY_ENUM_BASE + decl_i;
    return TY_UNKNOWN;
}

uint type_ref_to_type_code(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM)
        return TY_GENERIC_BASE + payload;
    if (tag == TYPE_REF_INSTANCE && payload < active_token_count())
        return decl_to_type_code(type_instance_decl_token[payload]);
    return TY_UNKNOWN;
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
        {
            return INVALID;
        }
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
        if (same_text(p, param_i))
            return slot;
        slot += 1u;
    }
    return INVALID;
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
        if (kind == TK_SEMICOLON || kind == TK_STRUCT || kind == TK_FN)
            return INVALID;
    }
    return INVALID;
}

uint struct_decl_close(uint open_i)
{
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

uint enclosing_function_start(uint token_i)
{
    if (token_i >= active_token_count())
        return INVALID;
    uint encoded = enclosing_fn[token_i];
    return encoded == 0u ? INVALID : encoded - 1u;
}

uint instance_from_type_head(uint type_head)
{
    if (type_head == INVALID || type_expr_ref_tag[type_head] != TYPE_REF_INSTANCE)
        return INVALID;
    return type_expr_ref_payload[type_head];
}

uint instance_from_annotated_let(uint head_i)
{
    if (head_i == 0u)
        return INVALID;
    uint assign_i = head_i - 1u;
    uint assign_kind = token_kind(assign_i);
    if (assign_kind != TK_ASSIGN && assign_kind != TK_LET_ASSIGN)
        return INVALID;

    uint j = assign_i;
    [loop]
    for (uint guard = 0u; guard < 128u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind == TK_LET_IDENT ||
            (kind == TK_IDENT && j > 0u && token_kind(j - 1u) == TK_LET))
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

uint context_instance_for_struct_literal_head(uint head_i)
{
    uint instance_i = instance_from_annotated_let(head_i);
    if (instance_i != INVALID)
        return instance_i;

    if (head_i > 0u && token_kind(head_i - 1u) == TK_RETURN)
    {
        uint fn_i = enclosing_function_start(head_i);
        if (fn_i != INVALID && fn_return_ref_tag[fn_i] == TYPE_REF_INSTANCE)
            return fn_return_ref_payload[fn_i];
    }
    return INVALID;
}

uint struct_literal_open_for_field(uint field_i)
{
    if (field_i == 0u || token_kind(field_i) != TK_IDENT || token_kind(field_i + 1u) != TK_COLON)
        return INVALID;

    uint j = field_i;
    [loop]
    for (uint guard = 0u; guard < 128u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind == TK_LBRACE)
        {
            if (j == 0u || token_kind(j - 1u) != TK_IDENT)
                return INVALID;
            if (j >= 2u && token_kind(j - 2u) == TK_STRUCT)
                return INVALID;
            return j;
        }
        if (kind == TK_SEMICOLON || kind == TK_FN)
            return INVALID;
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

void publish_struct_init_field(uint field_i)
{
    uint open_i = struct_literal_open_for_field(field_i);
    if (open_i == INVALID)
        return;

    uint head_i = open_i - 1u;
    uint instance_i = context_instance_for_struct_literal_head(head_i);
    if (instance_i == INVALID || type_instance_decl_token[instance_i] == INVALID)
        return;

    uint decl_i = type_instance_decl_token[instance_i];
    uint literal_decl_i = find_struct_decl_name(head_i);
    if (literal_decl_i == INVALID || literal_decl_i != decl_i)
        return;

    uint decl_open = struct_decl_open(decl_i);
    uint decl_close = decl_open == INVALID ? INVALID : struct_decl_close(decl_open);
    if (decl_open == INVALID || decl_close == INVALID)
        return;

    [loop]
    for (uint j = decl_open + 1u; j + 2u < decl_close; j += 1u)
    {
        if (!is_type_name_token(j) || token_kind(j + 1u) != TK_COLON || !same_text(j, field_i))
            continue;

        uint tag = TYPE_REF_INVALID;
        uint payload = INVALID;
        substituted_ref(instance_i, j + 2u, tag, payload);
        struct_init_field_expected_ref_tag[field_i] = tag;
        struct_init_field_expected_ref_payload[field_i] = payload;
        uint ty = type_ref_to_type_code(tag, payload);
        if (ty != TY_UNKNOWN)
            visible_type[field_i] = ty;
        return;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_token_count())
        return;

    struct_init_field_expected_ref_tag[i] = TYPE_REF_INVALID;
    struct_init_field_expected_ref_payload[i] = INVALID;
    publish_struct_init_field(i);
}
