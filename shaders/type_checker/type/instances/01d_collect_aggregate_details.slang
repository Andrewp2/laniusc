// HIR-driven array/slice details and reference forwarding.
//
// This pass runs after scalar/path refs, named instances, and aggregate headers
// are present. It attaches element refs and array length records, and forwards
// reference type nodes to their child type refs.

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
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_type_value_node;
StructuredBuffer<uint> hir_type_len_token;
StructuredBuffer<uint> hir_type_len_value;

RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> type_instance_elem_ref_tag;
RWStructuredBuffer<uint> type_instance_elem_ref_payload;
RWStructuredBuffer<uint> type_instance_len_kind;
RWStructuredBuffer<uint> type_instance_len_payload;
RWStructuredBuffer<uint> type_instance_state;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;

static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint HIR_TYPE_FORM_SLICE = 3u;
static const uint HIR_TYPE_FORM_REF = 4u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_ERROR = 4u;

static const uint TYPE_INSTANCE_RESOLVED = 1u;
static const uint TYPE_INSTANCE_UNSUPPORTED = 3u;

static const uint TYPE_LEN_CONST_PARAM = 2u;
static const uint TYPE_LEN_UNSUPPORTED = 3u;
static const uint TYPE_LEN_LITERAL = 1u;

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

bool child_ref(uint node, out uint tag, out uint payload)
{
    tag = TYPE_REF_ERROR;
    payload = valid_node(node) ? hir_token_pos[node] : INVALID;
    if (!valid_node(node))
        return false;
    uint token = hir_token_pos[node];
    if (!valid_token(token))
        return false;
    tag = type_expr_ref_tag[token];
    payload = type_expr_ref_payload[token];
    return tag != TYPE_REF_INVALID;
}

void publish_array_or_slice_details(uint node, uint token, bool is_array)
{
    uint elem_tag = TYPE_REF_INVALID;
    uint elem_payload = INVALID;
    bool ok = child_ref(hir_type_value_node[node], elem_tag, elem_payload);

    type_instance_elem_ref_tag[token] = ok ? elem_tag : TYPE_REF_ERROR;
    type_instance_elem_ref_payload[token] = ok ? elem_payload : token;
    type_instance_state[token] = ok ? TYPE_INSTANCE_RESOLVED : TYPE_INSTANCE_UNSUPPORTED;

    if (!is_array)
        return;

    uint len_token = hir_type_len_token[node];
    if (!valid_token(len_token))
    {
        type_instance_len_kind[token] = TYPE_LEN_UNSUPPORTED;
        type_instance_len_payload[token] = token;
    }
    else
    {
        uint len_value = hir_type_len_value[node];
        if (len_value != INVALID)
        {
            type_instance_len_kind[token] = TYPE_LEN_LITERAL;
            type_instance_len_payload[token] = len_value;
        }
        else
        {
            type_instance_len_kind[token] = TYPE_LEN_CONST_PARAM;
            type_instance_len_payload[token] = len_token;
        }
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node) || hir_kind[node] != HIR_TYPE)
        return;

    uint token = hir_token_pos[node];
    if (!valid_token(token))
        return;

    uint form = hir_type_form[node];
    if (form == HIR_TYPE_FORM_ARRAY || form == HIR_TYPE_FORM_SLICE)
    {
        publish_array_or_slice_details(node, token, form == HIR_TYPE_FORM_ARRAY);
        return;
    }

    if (form == HIR_TYPE_FORM_REF)
    {
        uint tag = TYPE_REF_INVALID;
        uint payload = INVALID;
        if (child_ref(hir_type_value_node[node], tag, payload))
        {
            type_expr_ref_tag[token] = tag;
            type_expr_ref_payload[token] = payload;
        }
        else
        {
            type_expr_ref_tag[token] = TYPE_REF_ERROR;
            type_expr_ref_payload[token] = token;
        }
    }
}
