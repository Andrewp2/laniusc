// Validate one positional forwarding edge per generic argument in parallel.
// The final count check in root initialization rejects missing/duplicate rows.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_type_arg_owner;
StructuredBuffer<uint> hir_type_arg_rank;
StructuredBuffer<uint> type_generic_param_slot_by_token;
RWStructuredBuffer<uint> alias_forwarding;
RWStructuredBuffer<uint> alias_forwarding_valid_arg_count;
StructuredBuffer<uint> alias_decl_by_target_hir;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= active_hir_count())
        return;
    uint owner = hir_type_arg_owner[node];
    uint decl_i = owner < active_hir_count() ? alias_decl_by_target_hir[owner] : INVALID;
    if (decl_i >= gParams.n_hir_nodes || alias_forwarding[decl_i] == 0u)
        return;

    uint token = hir_token_pos[node];
    uint slot = token < gParams.n_tokens ? type_generic_param_slot_by_token[token] : INVALID;
    uint rank = hir_type_arg_rank[node];
    if (slot == INVALID || slot != rank)
    {
        uint ignored;
        InterlockedAnd(alias_forwarding[decl_i], 0u, ignored);
        return;
    }
    uint ignored;
    InterlockedAdd(alias_forwarding_valid_arg_count[decl_i], 1u, ignored);
}
