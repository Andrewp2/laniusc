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

RWStructuredBuffer<uint> method_decl_receiver_type;
RWStructuredBuffer<uint> method_decl_impl_token;
RWStructuredBuffer<uint> method_decl_name_token;
RWStructuredBuffer<uint> method_decl_param_offset;
RWStructuredBuffer<uint> method_lookup_key;
RWStructuredBuffer<uint> method_lookup_receiver;
RWStructuredBuffer<uint> method_lookup_name_token;
RWStructuredBuffer<uint> method_lookup_fn;

static const uint INVALID = 0xffffffffu;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;

static const uint TK_IDENT = 1u;
static const uint TK_LPAREN = 4u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_ARROW = 75u;
static const uint TK_PARAM_LPAREN = 76u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_IF_RBRACE = 89u;
static const uint TK_FN = 67u;
static const uint TK_CONST = 92u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;
static const uint TK_IMPL = 98u;
static const uint TK_FOR = 100u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_IMPL_HEADER_SCAN = 96u;
static const uint MAX_IMPL_BODY_SCAN = 512u;
static const uint MAX_METHOD_HEADER_SCAN = 96u;
static const uint MAX_LOOKUP_PROBE = 32u;

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

uint token_hash(uint i)
{
    uint h = 2166136261u;
    uint start = token_start(i);
    uint len = token_len(i);
    [loop]
    for (uint d = 0u; d < len; d += 1u)
    {
        h = (h ^ source_at(start, d)) * 16777619u;
    }
    return h ^ len;
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

bool is_struct_decl_name_at(uint i)
{
    return token_kind(i) == TK_IDENT && i > 0u && token_kind(i - 1u) == TK_STRUCT;
}

uint struct_type_code_for_name(uint name_i)
{
    uint n_active = active_token_count();
    [loop]
    for (uint j = 1u; j < n_active; j += 1u)
    {
        if (is_struct_decl_name_at(j) && same_text(j, name_i))
            return TY_STRUCT_BASE + j;
    }
    return TY_UNKNOWN;
}

bool is_enum_decl_name_at(uint i)
{
    return token_kind(i) == TK_IDENT && i > 0u && token_kind(i - 1u) == TK_ENUM;
}

uint enum_type_code_for_name(uint name_i)
{
    uint n_active = active_token_count();
    [loop]
    for (uint j = 1u; j < n_active; j += 1u)
    {
        if (is_enum_decl_name_at(j) && same_text(j, name_i))
            return TY_ENUM_BASE + j;
    }
    return TY_UNKNOWN;
}

uint type_code_for_type_expr(uint type_i)
{
    uint kind = token_kind(type_i);
    if (kind != TK_IDENT && kind != TK_TYPE_IDENT)
        return TY_UNKNOWN;

    uint primitive = primitive_type_code(type_i);
    if (primitive != TY_UNKNOWN)
        return primitive;

    uint struct_ty = struct_type_code_for_name(type_i);
    if (struct_ty != TY_UNKNOWN)
        return struct_ty;

    return enum_type_code_for_name(type_i);
}

uint generic_param_list_close(uint open_i)
{
    uint n_active = active_token_count();
    uint limit = min(n_active, open_i + MAX_IMPL_HEADER_SCAN);
    uint depth = 0u;
    [loop]
    for (uint j = open_i; j < limit; j += 1u)
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

uint impl_body_open(uint impl_i)
{
    uint n_active = active_token_count();
    uint limit = min(n_active, impl_i + MAX_IMPL_HEADER_SCAN);
    [loop]
    for (uint j = impl_i + 1u; j < limit; j += 1u)
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

uint matching_block_close_bounded(uint open_i)
{
    uint depth = 0u;
    uint n_active = active_token_count();
    uint limit = min(n_active, open_i + MAX_IMPL_BODY_SCAN);
    [loop]
    for (uint j = open_i; j < limit; j += 1u)
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

uint impl_receiver_type_start(uint impl_i)
{
    uint n_active = active_token_count();
    uint first_type = impl_i + 1u;
    if (first_type < n_active && token_kind(first_type) == TK_LT)
    {
        uint close_i = generic_param_list_close(first_type);
        if (close_i == INVALID || close_i + 1u >= n_active)
            return INVALID;
        first_type = close_i + 1u;
    }

    uint angle_depth = 0u;
    uint limit = min(n_active, first_type + MAX_IMPL_HEADER_SCAN);
    [loop]
    for (uint j = first_type; j < limit; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT)
            angle_depth += 1u;
        else if (kind == TK_GT && angle_depth > 0u)
            angle_depth -= 1u;
        else if (kind == TK_FOR && angle_depth == 0u)
            return j + 1u < n_active ? j + 1u : INVALID;
        else if ((kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_SEMICOLON) &&
                 angle_depth == 0u)
            return first_type;
    }
    return INVALID;
}

uint method_param_offset(uint fn_i)
{
    uint n_active = active_token_count();
    uint limit = min(n_active, fn_i + MAX_METHOD_HEADER_SCAN);
    [loop]
    for (uint j = fn_i + 1u; j < limit; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_PARAM_LPAREN || kind == TK_LPAREN)
            return j + 1u;
        if (kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_SEMICOLON ||
            kind == TK_ARROW)
            return INVALID;
    }
    return INVALID;
}

uint method_key(uint receiver_ty, uint name_i)
{
    return (receiver_ty * 16777619u) ^ token_hash(name_i);
}

void insert_method_lookup(uint fn_i, uint receiver_ty, uint name_i)
{
    if (receiver_ty == TY_UNKNOWN || name_i >= active_token_count())
        return;

    uint cap = lookup_capacity();
    uint key = method_key(receiver_ty, name_i);
    uint start_slot = key % cap;
    uint probe_limit = min(cap, MAX_LOOKUP_PROBE);
    [loop]
    for (uint probe = 0u; probe < probe_limit; probe += 1u)
    {
        uint slot = (start_slot + probe) % cap;
        uint old_fn;
        InterlockedCompareExchange(method_lookup_fn[slot], INVALID, fn_i, old_fn);
        if (old_fn == INVALID)
        {
            method_lookup_key[slot] = key;
            method_lookup_receiver[slot] = receiver_ty;
            method_lookup_name_token[slot] = name_i;
            return;
        }
        if (method_lookup_key[slot] == key && method_lookup_receiver[slot] == receiver_ty &&
            same_text(method_lookup_name_token[slot], name_i))
        {
            uint old_min;
            InterlockedMin(method_lookup_fn[slot], fn_i, old_min);
            return;
        }
    }
}

void collect_impl_methods(uint impl_i)
{
    uint type_i = impl_receiver_type_start(impl_i);
    uint receiver_ty = type_i == INVALID ? TY_UNKNOWN : type_code_for_type_expr(type_i);
    uint open_i = impl_body_open(impl_i);
    uint close_i = open_i == INVALID ? INVALID : matching_block_close_bounded(open_i);
    if (open_i == INVALID || close_i == INVALID)
        return;

    [loop]
    for (uint j = open_i + 1u; j < close_i; j += 1u)
    {
        if (token_kind(j) != TK_FN)
            continue;
        uint name_i = j + 1u;
        method_decl_receiver_type[j] = receiver_ty;
        method_decl_impl_token[j] = impl_i;
        method_decl_name_token[j] = name_i;
        method_decl_param_offset[j] = method_param_offset(j);
        insert_method_lookup(j, receiver_ty, name_i);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_token_count() || token_kind(i) != TK_IMPL)
        return;

    collect_impl_methods(i);
}
