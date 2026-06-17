// One Hillis-Steele linked-list matching step for call arguments and params.
//
// Given a friend vector from argument rows to parameter rows and jump pointers
// that advance by 2^k rows inside each list, this pass writes the 2^(k+1)
// friend/jump state. It is the compact-row analogue of pareas `match_lists`.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> call_arg_row_count_out;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_arg_param_row_in;
StructuredBuffer<uint> call_arg_match_jump_in;
StructuredBuffer<uint> call_param_match_jump_in;

RWStructuredBuffer<uint> call_arg_param_row_out;
RWStructuredBuffer<uint> call_arg_match_jump_out;
RWStructuredBuffer<uint> call_param_match_jump_out;

static const uint INVALID = 0xffffffffu;
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

uint active_arg_row_count()
{
    return min(call_arg_row_count_out[0u], active_hir_node_count());
}

uint active_param_row_count()
{
    return min(call_param_row_count_out[0u], active_hir_node_count());
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint arg_rows = active_arg_row_count();
    uint param_rows = active_param_row_count();

    if (row < arg_rows)
    {
        uint next_arg = call_arg_match_jump_in[row];
        call_arg_match_jump_out[row] =
            next_arg != INVALID && next_arg < arg_rows
                ? call_arg_match_jump_in[next_arg]
                : INVALID;

        uint friend = call_arg_param_row_in[row];
        if (friend != INVALID &&
            friend < param_rows &&
            next_arg != INVALID &&
            next_arg < arg_rows)
        {
            uint next_param = call_param_match_jump_in[friend];
            if (next_param != INVALID && next_param < param_rows)
                call_arg_param_row_out[next_arg] = next_param;
        }
    }

    if (row < param_rows)
    {
        uint next_param = call_param_match_jump_in[row];
        call_param_match_jump_out[row] =
            next_param != INVALID && next_param < param_rows
                ? call_param_match_jump_in[next_param]
                : INVALID;
    }
}
