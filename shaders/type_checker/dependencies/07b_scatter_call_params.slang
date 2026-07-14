// Scatter dependency parameter staging rows after the shared parameter-count
// scan. A call-site token is the local function identity for imported calls.

import gpu_index;

struct Params
{
    uint declaration_count;
    uint import_capacity;
    uint visible_capacity;
    uint lookup_capacity;
    uint source_len;
    uint path_capacity;
    uint namespace;
    uint hir_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint> hir_call_arg_ordinal;
StructuredBuffer<uint> call_dependency_decl;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_node_type;
StructuredBuffer<uint> call_param_row_node_ref_tag;
StructuredBuffer<uint> call_param_row_node_ref_payload;
RWStructuredBuffer<uint> call_param_row_node;
RWStructuredBuffer<uint> call_param_row_fn_token;
RWStructuredBuffer<uint> call_param_row_ordinal;
RWStructuredBuffer<uint> call_param_row_type;
RWStructuredBuffer<uint> call_param_row_ref_tag;
RWStructuredBuffer<uint> call_param_row_ref_payload;
RWStructuredBuffer<uint> call_param_row_start;
RWStructuredBuffer<uint> call_param_row_count;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_hir_count()
{
    return gParams.hir_capacity == 0u ? 0u : min(gParams.hir_capacity, hir_status[5u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint arg_node = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (arg_node >= active_hir_count())
        return;
    uint call_node = hir_call_arg_parent_call[arg_node];
    if (call_node >= active_hir_count())
        return;
    uint callee_node = hir_call_callee_node[call_node];
    if (callee_node >= active_hir_count())
        return;
    uint callee_token = hir_token_pos[callee_node];
    if (callee_token >= gParams.visible_capacity ||
        call_dependency_decl[callee_token] == INVALID)
        return;
    uint ordinal = hir_call_arg_ordinal[arg_node];
    uint count = call_param_count[callee_token];
    uint start = call_param_row_start[callee_token];
    uint row = start + ordinal;
    if (start == INVALID || ordinal >= count || row < start ||
        row >= call_param_row_count_out[0u] || row >= active_hir_count())
        return;

    call_param_row_node[row] = arg_node;
    call_param_row_fn_token[row] = callee_token;
    call_param_row_ordinal[row] = ordinal;
    call_param_row_type[row] = call_param_row_node_type[arg_node];
    call_param_row_ref_tag[row] = call_param_row_node_ref_tag[arg_node];
    call_param_row_ref_payload[row] = call_param_row_node_ref_payload[arg_node];
    if (ordinal == 0u)
        call_param_row_count[callee_token] = count;
}
