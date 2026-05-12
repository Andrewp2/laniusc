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

StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_head_token;
StructuredBuffer<uint> type_instance_arg_count;

RWStructuredBuffer<uint> type_instance_decl_token;
RWStructuredBuffer<uint> type_instance_arg_start;
RWStructuredBuffer<uint> type_instance_arg_ref_tag;
RWStructuredBuffer<uint> type_instance_arg_ref_payload;
RWStructuredBuffer<uint> type_instance_state;

static const uint INVALID = 0xffffffffu;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_ERROR = 4u;

static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_EMPTY = 0u;
static const uint TYPE_INSTANCE_RESOLVED = 1u;
static const uint TYPE_INSTANCE_UNRESOLVED = 2u;
static const uint TYPE_INSTANCE_UNSUPPORTED = 3u;

static const uint TK_IDENT = 1u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LPAREN = 4u;
static const uint TK_LBRACE = 22u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COMMA = 36u;
static const uint TK_PARAM_COMMA = 84u;
static const uint TK_CONST = 92u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_TYPE_SCAN = 64u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;

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

bool is_enum_decl_name_at(uint i)
{
    return token_kind(i) == TK_IDENT && i > 0u && token_kind(i - 1u) == TK_ENUM;
}

uint find_named_type_decl(uint name_i)
{
    uint n = active_token_count();
    [loop]
    for (uint j = 1u; j < n; j += 1u)
    {
        if ((is_struct_decl_name_at(j) || is_enum_decl_name_at(j)) && same_text(j, name_i))
            return j;
    }
    return INVALID;
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

uint generic_type_param_count(uint decl_i)
{
    uint open_i = generic_param_list_open(decl_i);
    uint close_i = generic_param_list_close(open_i);
    if (open_i == INVALID || close_i == INVALID)
        return 0u;

    uint count = 0u;
    [loop]
    for (uint p = open_i + 1u; p < close_i; p += 1u)
    {
        if (is_type_generic_param_token(p, open_i, close_i))
            count += 1u;
    }
    return count;
}

uint find_matching_gt(uint lt_i)
{
    uint n = active_token_count();
    uint depth = 0u;
    uint limit = min(n, lt_i + MAX_TYPE_SCAN);
    [loop]
    for (uint j = lt_i; j < limit; j += 1u)
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
    }
    return INVALID;
}

uint top_level_type_arg_head(uint lt_i, uint gt_i, uint slot)
{
    uint current = 0u;
    uint start = lt_i + 1u;
    uint angle_depth = 0u;
    uint array_depth = 0u;

    [loop]
    for (uint j = lt_i + 1u; j <= gt_i; j += 1u)
    {
        uint kind = j < gt_i ? token_kind(j) : TK_COMMA;
        bool boundary = j == gt_i ||
                        ((kind == TK_COMMA || kind == TK_PARAM_COMMA) && angle_depth == 0u &&
                         array_depth == 0u);
        if (boundary)
        {
            if (current == slot)
                return start < j ? start : INVALID;
            current += 1u;
            start = j + 1u;
            continue;
        }

        if (kind == TK_LT)
            angle_depth += 1u;
        else if (kind == TK_GT && angle_depth > 0u)
            angle_depth -= 1u;
        else if (kind == TK_TYPE_ARRAY_LBRACKET)
            array_depth += 1u;
        else if (kind == TK_TYPE_ARRAY_RBRACKET && array_depth > 0u)
            array_depth -= 1u;
    }
    return INVALID;
}

uint arg_ref_index(uint instance_i, uint slot)
{
    return instance_i * TYPE_INSTANCE_ARG_REF_STRIDE + slot;
}

void clear_instance_slot(uint i)
{
    type_instance_decl_token[i] = INVALID;
    type_instance_arg_start[i] = INVALID;

    [unroll]
    for (uint slot = 0u; slot < TYPE_INSTANCE_ARG_REF_STRIDE; slot += 1u)
    {
        uint idx = arg_ref_index(i, slot);
        type_instance_arg_ref_tag[idx] = TYPE_REF_INVALID;
        type_instance_arg_ref_payload[idx] = INVALID;
    }

    if (type_instance_kind[i] == TYPE_INSTANCE_NAMED)
        type_instance_state[i] = TYPE_INSTANCE_UNRESOLVED;
    else if (type_instance_state[i] == TYPE_INSTANCE_EMPTY)
        type_instance_state[i] = TYPE_INSTANCE_EMPTY;
}

void bind_named_instance(uint i)
{
    if (type_instance_kind[i] != TYPE_INSTANCE_NAMED)
        return;

    uint head_i = type_instance_head_token[i];
    uint decl_i = find_named_type_decl(head_i);
    if (decl_i == INVALID)
        return;

    type_instance_decl_token[i] = decl_i;

    uint actual_count = type_instance_arg_count[i];
    uint expected_count = generic_type_param_count(decl_i);
    if (actual_count != expected_count || actual_count > TYPE_INSTANCE_ARG_REF_STRIDE)
    {
        type_instance_state[i] = TYPE_INSTANCE_UNSUPPORTED;
        return;
    }

    uint lt_i = head_i + 1u;
    uint gt_i = find_matching_gt(lt_i);
    if (gt_i == INVALID)
    {
        type_instance_state[i] = TYPE_INSTANCE_UNSUPPORTED;
        return;
    }

    type_instance_arg_start[i] = arg_ref_index(i, 0u);
    [loop]
    for (uint slot = 0u; slot < TYPE_INSTANCE_ARG_REF_STRIDE; slot += 1u)
    {
        if (slot >= actual_count)
            break;

        uint arg_head = top_level_type_arg_head(lt_i, gt_i, slot);
        uint out_i = arg_ref_index(i, slot);
        if (arg_head == INVALID)
        {
            type_instance_arg_ref_tag[out_i] = TYPE_REF_ERROR;
            type_instance_arg_ref_payload[out_i] = head_i;
            type_instance_state[i] = TYPE_INSTANCE_UNSUPPORTED;
            return;
        }

        type_instance_arg_ref_tag[out_i] = type_expr_ref_tag[arg_head];
        type_instance_arg_ref_payload[out_i] = type_expr_ref_payload[arg_head];
        if (type_instance_arg_ref_tag[out_i] == TYPE_REF_INVALID)
        {
            type_instance_arg_ref_tag[out_i] = TYPE_REF_ERROR;
            type_instance_arg_ref_payload[out_i] = arg_head;
            type_instance_state[i] = TYPE_INSTANCE_UNSUPPORTED;
            return;
        }
    }

    type_instance_state[i] = TYPE_INSTANCE_RESOLVED;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_token_count())
        return;

    clear_instance_slot(i);
    bind_named_instance(i);
}
