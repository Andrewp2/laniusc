// Copy the compact argument-to-parameter friend vector for one list-match step.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> call_arg_row_count_out;
StructuredBuffer<uint> call_arg_param_row_in;

RWStructuredBuffer<uint> call_arg_param_row_out;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint count = min(call_arg_row_count_out[0u], active_hir_node_count());
    if (row < count)
        call_arg_param_row_out[row] = call_arg_param_row_in[row];
}
