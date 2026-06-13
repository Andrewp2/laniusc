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
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_member_receiver_token;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;

RWStructuredBuffer<uint> member_result_context_instance;
RWStructuredBuffer<uint> member_result_ref_tag;
RWStructuredBuffer<uint> member_result_ref_payload;
RWStructuredBuffer<uint> member_result_field_ordinal;

static const uint INVALID = 0xffffffffu;

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

uint receiver_token_for_member(uint member_node)
{
    return valid_node(member_node) ? hir_member_receiver_token[member_node] : INVALID;
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

bool enclosing_method_receiver_type_ref(uint member_node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;

    uint member_token = valid_node(member_node) ? hir_member_name_token[member_node] : INVALID;
    if (!valid_token(member_token))
        return false;

    uint encoded_fn = enclosing_fn[member_token];
    uint fn_token = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    if (!valid_token(fn_token))
        return false;

    tag = method_decl_receiver_ref_tag[fn_token];
    payload = method_decl_receiver_ref_payload[fn_token];
    return tag != TYPE_REF_INVALID && payload != INVALID;
}

void publish_receiver_ref_for_node(uint member_node)
{
    if (!valid_node(member_node) || hir_kind[member_node] != HIR_MEMBER_EXPR)
        return;

    uint member_token = hir_member_name_token[member_node];
    if (!valid_token(member_token))
        return;

    uint receiver_token = receiver_token_for_member(member_node);
    if (!valid_token(receiver_token))
        return;

    uint tag = TYPE_REF_INVALID;
    uint payload = INVALID;
    if (!receiver_decl_type_ref(receiver_token, tag, payload))
        enclosing_method_receiver_type_ref(member_node, tag, payload);
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
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;
    publish_receiver_ref_for_node(node);
}
