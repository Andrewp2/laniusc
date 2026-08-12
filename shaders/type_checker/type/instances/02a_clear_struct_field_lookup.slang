import type_checker.type.instances.struct_field_lookup;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> struct_field_lookup_state;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    if (row < struct_field_lookup_capacity(gParams.n_tokens))
        struct_field_lookup_state[row] = STRUCT_FIELD_LOOKUP_EMPTY;
}
