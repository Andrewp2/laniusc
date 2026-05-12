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
RWStructuredBuffer<uint> visible_type;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;

RWStructuredBuffer<uint> member_result_ref_tag;
RWStructuredBuffer<uint> member_result_ref_payload;

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
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LPAREN = 4u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_DOT = 35u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_FN = 67u;
static const uint TK_CONST = 92u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;
static const uint TK_IMPL = 98u;
static const uint TK_FOR = 100u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_IF_RBRACE = 89u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_SELF_VALUE = 105u;

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

bool is_struct_decl_name_at(uint i)
{
    uint kind = token_kind(i);
    return i > 0u && (kind == TK_IDENT || kind == TK_TYPE_IDENT) &&
           token_kind(i - 1u) == TK_STRUCT;
}

bool is_enum_decl_name_at(uint i)
{
    uint kind = token_kind(i);
    return i > 0u && (kind == TK_IDENT || kind == TK_TYPE_IDENT) &&
           token_kind(i - 1u) == TK_ENUM;
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

uint find_enum_decl_name(uint name_i)
{
    uint n = active_token_count();
    [loop]
    for (uint j = 1u; j < n; j += 1u)
    {
        if (is_enum_decl_name_at(j) && same_text(j, name_i))
            return j;
    }
    return INVALID;
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

uint direct_ref_to_type_code(uint tag, uint payload)
{
    if (tag != TYPE_REF_GENERIC_PARAM)
        return type_ref_to_type_code(tag, payload);

    uint decl_i = find_struct_decl_name(payload);
    if (decl_i == INVALID)
        decl_i = find_enum_decl_name(payload);
    return decl_i == INVALID ? TY_GENERIC_BASE + payload : decl_to_type_code(decl_i);
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
        if (kind == TK_SEMICOLON || kind == TK_STRUCT)
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

uint declaration_type_head(uint decl_i)
{
    if (decl_i == INVALID || decl_i + 2u >= active_token_count())
        return INVALID;
    return token_kind(decl_i + 1u) == TK_COLON ? decl_i + 2u : INVALID;
}

uint instance_for_decl(uint decl_i)
{
    uint type_head = declaration_type_head(decl_i);
    if (type_head == INVALID || type_expr_ref_tag[type_head] != TYPE_REF_INSTANCE)
        return INVALID;
    return type_expr_ref_payload[type_head];
}

uint matching_block_close(uint open_i)
{
    uint n = active_token_count();
    uint depth = 0u;
    [loop]
    for (uint j = open_i; j < n; j += 1u)
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

uint impl_body_open(uint impl_i)
{
    uint n = active_token_count();
    [loop]
    for (uint j = impl_i + 1u; j < n; j += 1u)
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

uint enclosing_impl_start(uint token_i)
{
    uint j = token_i;
    [loop]
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        j -= 1u;
        if (token_kind(j) != TK_IMPL)
            continue;

        uint open_i = impl_body_open(j);
        uint close_i = open_i == INVALID ? INVALID : matching_block_close(open_i);
        if (open_i != INVALID && close_i != INVALID && token_i > open_i && token_i < close_i)
            return j;
    }
    return INVALID;
}

uint impl_receiver_type_start(uint impl_i)
{
    if (impl_i == INVALID)
        return INVALID;

    uint n = active_token_count();
    uint first_type = impl_i + 1u;
    if (first_type < n && token_kind(first_type) == TK_LT)
    {
        uint close_i = generic_param_list_close(first_type);
        if (close_i == INVALID || close_i + 1u >= n)
            return INVALID;
        first_type = close_i + 1u;
    }

    uint angle_depth = 0u;
    [loop]
    for (uint j = first_type; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT)
            angle_depth += 1u;
        else if (kind == TK_GT && angle_depth > 0u)
            angle_depth -= 1u;
        else if (kind == TK_FOR && angle_depth == 0u)
            return j + 1u < n ? j + 1u : INVALID;
        else if ((kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_SEMICOLON) &&
                 angle_depth == 0u)
            return first_type;
    }
    return INVALID;
}

uint impl_receiver_decl_token(uint self_i)
{
    uint type_head = impl_receiver_type_start(enclosing_impl_start(self_i));
    if (type_head == INVALID)
        return INVALID;

    if (type_expr_ref_tag[type_head] == TYPE_REF_INSTANCE)
    {
        uint instance_i = type_expr_ref_payload[type_head];
        return instance_i == INVALID ? INVALID : type_instance_decl_token[instance_i];
    }

    uint decl_i = find_struct_decl_name(type_head);
    if (decl_i == INVALID)
        decl_i = find_enum_decl_name(type_head);
    return decl_i;
}

uint instance_for_self_base(uint self_i)
{
    uint decl_instance = instance_for_decl(visible_decl[self_i]);
    if (decl_instance != INVALID)
        return decl_instance;

    uint type_head = impl_receiver_type_start(enclosing_impl_start(self_i));
    if (type_head == INVALID || type_expr_ref_tag[type_head] != TYPE_REF_INSTANCE)
        return INVALID;
    return type_expr_ref_payload[type_head];
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

bool publish_direct_member_result(uint member_i, uint decl_i)
{
    uint open_i = struct_decl_open(decl_i);
    uint close_i = open_i == INVALID ? INVALID : struct_decl_close(open_i);
    if (open_i == INVALID || close_i == INVALID)
        return false;

    [loop]
    for (uint j = open_i + 1u; j + 2u < close_i; j += 1u)
    {
        if (!is_type_name_token(j) || token_kind(j + 1u) != TK_COLON || !same_text(j, member_i))
            continue;

        uint tag = type_expr_ref_tag[j + 2u];
        uint payload = type_expr_ref_payload[j + 2u];
        member_result_ref_tag[member_i] = tag;
        member_result_ref_payload[member_i] = payload;
        uint ty = direct_ref_to_type_code(tag, payload);
        if (ty != TY_UNKNOWN)
            visible_type[member_i] = ty;
        return true;
    }
    return false;
}

void publish_member_result(uint member_i)
{
    if (member_i < 2u || member_i >= active_token_count())
        return;
    uint dot_i = member_i - 1u;
    uint base_i = member_i - 2u;
    uint base_kind = token_kind(base_i);
    if (token_kind(member_i) != TK_IDENT || token_kind(dot_i) != TK_DOT ||
        (base_kind != TK_IDENT && base_kind != TK_SELF_VALUE))
        return;

    uint instance_i = base_kind == TK_SELF_VALUE ? instance_for_self_base(base_i)
                                                 : instance_for_decl(visible_decl[base_i]);
    if (instance_i == INVALID && base_kind == TK_SELF_VALUE)
    {
        uint decl_i = impl_receiver_decl_token(base_i);
        if (decl_i != INVALID)
            publish_direct_member_result(member_i, decl_i);
        return;
    }
    if (instance_i == INVALID || type_instance_decl_token[instance_i] == INVALID)
        return;

    uint decl_i = type_instance_decl_token[instance_i];
    uint open_i = struct_decl_open(decl_i);
    uint close_i = open_i == INVALID ? INVALID : struct_decl_close(open_i);
    if (open_i == INVALID || close_i == INVALID)
        return;

    [loop]
    for (uint j = open_i + 1u; j + 2u < close_i; j += 1u)
    {
        if (!is_type_name_token(j) || token_kind(j + 1u) != TK_COLON || !same_text(j, member_i))
            continue;

        uint tag = TYPE_REF_INVALID;
        uint payload = INVALID;
        substituted_ref(instance_i, j + 2u, tag, payload);
        member_result_ref_tag[member_i] = tag;
        member_result_ref_payload[member_i] = payload;
        uint ty = type_ref_to_type_code(tag, payload);
        if (ty != TY_UNKNOWN)
            visible_type[member_i] = ty;
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

    member_result_ref_tag[i] = TYPE_REF_INVALID;
    member_result_ref_payload[i] = INVALID;
    publish_member_result(i);
}
