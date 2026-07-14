// One race-free pointer-doubling round over non-generic alias declarations.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> alias_root_decl_in;
RWStructuredBuffer<uint> alias_root_decl_out;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint decl_i = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    if (decl_i >= gParams.n_hir_nodes)
        return;
    uint parent = alias_root_decl_in[decl_i];
    alias_root_decl_out[decl_i] = parent < gParams.n_hir_nodes
        ? alias_root_decl_in[parent]
        : decl_i;
}
