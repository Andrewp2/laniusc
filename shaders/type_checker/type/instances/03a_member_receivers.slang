// HIR member receiver type-reference projection.
//
// This pass records the receiver type ref for each HIR member expression and,
// for generic receiver instances, the receiver instance token needed by the
// later generic substitution pass.

import generated_parse_production_ids;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_receiver_token;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_state;

RWStructuredBuffer<uint> member_result_context_instance;
RWStructuredBuffer<uint> member_result_ref_tag;
RWStructuredBuffer<uint> member_result_ref_payload;
RWStructuredBuffer<uint> member_result_field_ordinal;
RWStructuredBuffer<uint> member_result_field_node;

static const uint INVALID = 0xffffffffu;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_ERROR = 4u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint TYPE_INSTANCE_RESOLVED = 1u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint HIR_EXPR_NAME = 2u;

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

uint expr_slot(uint node, uint slot)
{
    return valid_node(node) ? hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + slot] : INVALID;
}

uint result_expr(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    return valid_node(root) ? root : node;
}

uint name_or_path_token_for_node(uint node)
{
    if (!valid_node(node) ||
        (hir_kind[node] != HIR_NAME_EXPR && hir_kind[node] != HIR_PATH_EXPR))
        return INVALID;

    uint token = expr_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN);
    return valid_token(token) ? token : INVALID;
}

uint name_token_for_expr(uint node)
{
    uint token = name_or_path_token_for_node(node);
    if (valid_token(token))
        return token;

    return name_or_path_token_for_node(result_expr(node));
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

bool array_or_slice_instance_from_ref(uint ref_tag, uint ref_payload, out uint instance)
{
    instance = INVALID;
    if (ref_tag != TYPE_REF_INSTANCE || !valid_token(ref_payload))
        return false;

    uint kind = type_instance_kind[ref_payload];
    if (kind != TYPE_INSTANCE_ARRAY && kind != TYPE_INSTANCE_SLICE)
        return false;

    uint elem_tag = type_instance_elem_ref_tag[ref_payload];
    uint elem_payload = type_instance_elem_ref_payload[ref_payload];
    if (elem_tag == TYPE_REF_INVALID || elem_tag == TYPE_REF_ERROR ||
        elem_payload == INVALID)
        return false;

    instance = ref_payload;
    return true;
}

bool indexed_receiver_element_type_ref(uint member_node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;

    uint receiver_node = valid_node(member_node) ? hir_member_receiver_node[member_node] : INVALID;
    if (!valid_node(receiver_node) || hir_kind[receiver_node] != HIR_INDEX_EXPR)
        return false;

    uint receiver_base = expr_slot(receiver_node, HIR_EXPR_RECORD_LEFT);
    uint receiver_token = name_token_for_expr(receiver_base);
    uint receiver_decl = valid_token(receiver_token) ? visible_decl[receiver_token] : INVALID;
    if (!valid_token(receiver_decl))
        return false;

    uint array_instance = INVALID;
    if (!array_or_slice_instance_from_ref(
            decl_type_ref_tag[receiver_decl],
            decl_type_ref_payload[receiver_decl],
            array_instance))
        return false;

    tag = type_instance_elem_ref_tag[array_instance];
    payload = type_instance_elem_ref_payload[array_instance];
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

bool indexed_receiver_type_ref(uint member_node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;

    return indexed_receiver_element_type_ref(member_node, tag, payload);
}

bool member_receiver_is_self(uint member_node)
{
    uint receiver_node = valid_node(member_node) ? hir_member_receiver_node[member_node] : INVALID;
    return valid_node(receiver_node) && node_kind[receiver_node] == PROD_SELF_VALUE;
}

bool member_expr_is_call_callee(uint node)
{
    if (!valid_node(node) || hir_kind[node] != HIR_MEMBER_EXPR)
        return false;

    uint owner = parent[node];
    if (valid_node(owner) &&
        hir_kind[owner] == HIR_CALL_EXPR &&
        hir_call_callee_node[owner] == node)
        return true;

    uint child = first_child[node];
    return valid_node(child) &&
           hir_kind[child] == HIR_CALL_EXPR &&
           hir_call_callee_node[child] == node;
}

void clear_member_result(uint member_token)
{
    if (!valid_token(member_token))
        return;

    member_result_ref_tag[member_token] = TYPE_REF_INVALID;
    member_result_ref_payload[member_token] = INVALID;
    member_result_context_instance[member_token] = INVALID;
    member_result_field_ordinal[member_token] = INVALID;
    member_result_field_node[member_token] = INVALID;
}

void publish_receiver_ref_for_node(uint member_node)
{
    if (!valid_node(member_node) || hir_kind[member_node] != HIR_MEMBER_EXPR)
        return;

    uint member_token = hir_member_name_token[member_node];
    if (!valid_token(member_token))
        return;

    if (member_expr_is_call_callee(member_node))
    {
        clear_member_result(member_token);
        return;
    }

    uint receiver_token = receiver_token_for_member(member_node);
    if (!valid_token(receiver_token))
        receiver_token = name_token_for_expr(hir_member_receiver_node[member_node]);
    if (!valid_token(receiver_token))
        return;

    uint tag = TYPE_REF_INVALID;
    uint payload = INVALID;
    if (!indexed_receiver_type_ref(member_node, tag, payload) &&
        !receiver_decl_type_ref(receiver_token, tag, payload) &&
        member_receiver_is_self(member_node))
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
