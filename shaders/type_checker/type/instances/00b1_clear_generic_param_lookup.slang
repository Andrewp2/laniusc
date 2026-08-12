import type_checker.type.instances.generic_param_lookup;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> generic_param_lookup_state;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    if (row < generic_param_lookup_capacity(gParams.n_tokens))
        generic_param_lookup_state[row] = GENERIC_PARAM_LOOKUP_EMPTY;
}
