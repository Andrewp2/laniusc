// HIR-driven array and slice instance headers.
//
// The pass publishes token-indexed instance refs for aggregate type forms.
// Element and length refs are filled in a later pass after all child type refs
// have been materialized.

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

RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> type_instance_kind;
RWStructuredBuffer<uint> type_instance_head_token;
RWStructuredBuffer<uint> type_instance_state;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;

static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint HIR_TYPE_FORM_SLICE = 3u;

static const uint TYPE_REF_INSTANCE = 3u;

static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint TYPE_INSTANCE_UNRESOLVED = 2u;

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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node) || hir_kind[node] != HIR_TYPE)
        return;

    uint form = hir_type_form[node];
    if (form != HIR_TYPE_FORM_ARRAY && form != HIR_TYPE_FORM_SLICE)
        return;

    uint token = hir_token_pos[node];
    if (!valid_token(token))
        return;

    type_expr_ref_tag[token] = TYPE_REF_INSTANCE;
    type_expr_ref_payload[token] = token;
    type_instance_kind[token] = form == HIR_TYPE_FORM_ARRAY ? TYPE_INSTANCE_ARRAY
                                                            : TYPE_INSTANCE_SLICE;
    type_instance_head_token[token] = token;
    type_instance_state[token] = TYPE_INSTANCE_UNRESOLVED;
}
