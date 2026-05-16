// HIR member receiver type-reference projection.
//
// This pass records the receiver type ref for each HIR member expression and,
// for generic receiver instances, the receiver instance token needed by the
// later generic substitution pass.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_member_receiver_token;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> method_decl_param_offset;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;

RWStructuredBuffer<uint> member_result_context_instance;
RWStructuredBuffer<uint> member_result_ref_tag;
RWStructuredBuffer<uint> member_result_ref_payload;
RWStructuredBuffer<uint> member_result_field_ordinal;

static const uint INVALID = 0xffffffffu;

static const uint HIR_FN = 3u;
static const uint HIR_MEMBER_EXPR = 21u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint parent_node(uint node)
{
    uint p = valid_node(node) ? parent[node] : INVALID;
    return valid_node(p) ? p : INVALID;
}

uint member_node_for_token(uint member_token)
{
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_kind[node] != HIR_MEMBER_EXPR)
            continue;
        if (hir_member_name_token[node] == member_token)
            return node;
    }
    return INVALID;
}

uint receiver_token_for_member(uint member_node)
{
    return valid_node(member_node) ? hir_member_receiver_token[member_node] : INVALID;
}

uint enclosing_function_node(uint node)
{
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 96u; guard += 1u)
    {
        if (!valid_node(cur))
            return INVALID;
        if (hir_kind[cur] == HIR_FN)
            return cur;
        uint p = parent_node(cur);
        if (!valid_node(p) || p == cur)
            return INVALID;
        cur = p;
    }
    return INVALID;
}

bool receiver_decl_type_ref(uint receiver_token, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;

    uint decl_token = valid_token(receiver_token) ? visible_decl[receiver_token] : INVALID;
    if (!valid_token(decl_token))
        return false;

    tag = decl_type_ref_tag[decl_token];
    payload = decl_type_ref_payload[decl_token];
    return tag != TYPE_REF_INVALID && payload != INVALID;
}

bool method_receiver_type_ref(uint receiver_token, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;

    uint decl_token = valid_token(receiver_token) ? visible_decl[receiver_token] : INVALID;
    if (!valid_token(decl_token))
        return false;

    [loop]
    for (uint fn_token = 0u; fn_token < gParams.n_tokens; fn_token += 1u)
    {
        if (method_decl_param_offset[fn_token] != decl_token)
            continue;
        tag = method_decl_receiver_ref_tag[fn_token];
        payload = method_decl_receiver_ref_payload[fn_token];
        return tag != TYPE_REF_INVALID && payload != INVALID;
    }
    return false;
}

bool enclosing_method_receiver_type_ref(uint member_node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;

    uint fn_node = enclosing_function_node(member_node);
    uint fn_token = valid_node(fn_node) ? hir_token_pos[fn_node] : INVALID;
    if (!valid_token(fn_token))
        return false;

    tag = method_decl_receiver_ref_tag[fn_token];
    payload = method_decl_receiver_ref_payload[fn_token];
    return tag != TYPE_REF_INVALID && payload != INVALID;
}

void publish_receiver_ref(uint member_token)
{
    uint member_node = member_node_for_token(member_token);
    if (!valid_node(member_node))
        return;

    uint receiver_token = receiver_token_for_member(member_node);
    if (!valid_token(receiver_token))
        return;

    uint tag = TYPE_REF_INVALID;
    uint payload = INVALID;
    if (!receiver_decl_type_ref(receiver_token, tag, payload))
    {
        if (!method_receiver_type_ref(receiver_token, tag, payload))
            enclosing_method_receiver_type_ref(member_node, tag, payload);
    }
    if (tag == TYPE_REF_INVALID || payload == INVALID)
        return;

    member_result_ref_tag[member_token] = tag;
    member_result_ref_payload[member_token] = payload;
    member_result_context_instance[member_token] =
        tag == TYPE_REF_INSTANCE && valid_token(payload) ? payload : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token = linear_thread_id(dtid);
    if (!valid_token(token))
        return;

    member_result_context_instance[token] = INVALID;
    member_result_ref_tag[token] = TYPE_REF_INVALID;
    member_result_ref_payload[token] = INVALID;
    member_result_field_ordinal[token] = INVALID;
    publish_receiver_ref(token);
}
