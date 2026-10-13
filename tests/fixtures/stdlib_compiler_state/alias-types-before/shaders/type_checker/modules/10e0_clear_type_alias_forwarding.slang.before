// Clear the compact identity-forwarding relation used by alias root discovery.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> alias_forwarding;
RWStructuredBuffer<uint> alias_forwarding_target_decl;
RWStructuredBuffer<uint> alias_forwarding_valid_arg_count;
RWStructuredBuffer<uint> alias_decl_by_target_hir;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_hir_nodes)
        return;
    alias_forwarding[i] = 0u;
    alias_forwarding_target_decl[i] = INVALID;
    alias_forwarding_valid_arg_count[i] = 0u;
    alias_decl_by_target_hir[i] = INVALID;
}
