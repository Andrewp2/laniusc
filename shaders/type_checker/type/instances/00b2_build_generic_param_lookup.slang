import type_checker.type.instances.generic_param_lookup;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_token;
StructuredBuffer<uint> generic_param_name_id;
RWStructuredBuffer<uint> generic_param_lookup_state;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    uint count = min(generic_param_count_out[0u], gParams.n_tokens);
    generic_param_lookup_insert(
        row, count, gParams.n_tokens,
        generic_param_owner_token, generic_param_name_id,
        generic_param_lookup_state);
}
