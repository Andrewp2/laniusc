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
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_decl_name_id;
StructuredBuffer<uint> language_decl_kind;
StructuredBuffer<uint> language_decl_tag;

RWStructuredBuffer<uint> call_intrinsic_tag;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_CALL_EXPR = 19u;

static const uint TY_VOID = 1u;

static const uint INTRINSIC_NONE = 0u;
static const uint LANGUAGE_DECL_COUNT = 18u;
static const uint LANGUAGE_DECL_INTRINSIC = 2u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint intrinsic_tag_for_name_id(uint name_id)
{
    if (name_id == INVALID)
        return INTRINSIC_NONE;

    [unroll]
    for (uint decl_i = 0u; decl_i < LANGUAGE_DECL_COUNT; decl_i += 1u)
    {
        if (language_decl_kind[decl_i] == LANGUAGE_DECL_INTRINSIC &&
            language_decl_name_id[decl_i] == name_id)
            return language_decl_tag[decl_i];
    }
    return INTRINSIC_NONE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_hir_node_count() || hir_kind[i] != HIR_CALL_EXPR)
        return;

    uint callee_node = hir_call_callee_node[i];
    if (callee_node == INVALID || callee_node >= active_hir_node_count())
        return;

    uint callee_token = hir_token_pos[callee_node];
    if (callee_token == INVALID || callee_token >= gParams.n_tokens)
        return;

    uint intrinsic_tag = intrinsic_tag_for_name_id(name_id_by_token[callee_token]);
    if (intrinsic_tag == INTRINSIC_NONE)
        return;

    call_intrinsic_tag[callee_token] = intrinsic_tag;
    call_return_type[callee_token] = TY_VOID;
    call_return_type_token[callee_token] = INVALID;
}
