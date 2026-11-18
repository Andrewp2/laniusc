// Clear the token-indexed function entrypoint relation independently from the
// legacy call-table mega-clear. Keeping this pass single-resource lets the
// compiler graph own and color the relation with a complete reflected access
// contract.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> fn_entrypoint_tag;

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
    if (i < max(gParams.n_tokens, gParams.n_hir_nodes))
        fn_entrypoint_tag[i] = 0u;
}
