// Materialize stable per-kind rows after the paired exclusive prefix scan.

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> generic_type_param_prefix;
RWStructuredBuffer<uint> generic_type_param_rows;

static const uint GENERIC_PARAM_KIND_TYPE = 1u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    uint count = min(generic_param_count_out[0u], gParams.n_tokens);
    if (row >= count)
        return;
    uint kind = generic_param_kind[row];
    if (kind == GENERIC_PARAM_KIND_TYPE)
        generic_type_param_rows[generic_type_param_prefix[row]] = row;
}
