// GPU path projection clear.
//
// Scheduling contract:
// - Dispatch before type_check_modules_10e_project_type_paths.slang,
//   type_check_modules_10f_mark_value_call_paths.slang, and
//   type_check_modules_10g_project_value_paths.slang.
// - This pass clears token-indexed bridges consumed by existing semantic
//   passes while full consumers migrate to path-resolution arrays.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> module_type_path_type;
RWStructuredBuffer<uint> module_type_path_status;
RWStructuredBuffer<uint> module_value_path_expr_head;
RWStructuredBuffer<uint> module_value_path_call_head;
RWStructuredBuffer<uint> module_value_path_call_open;
RWStructuredBuffer<uint> module_value_path_const_head;
RWStructuredBuffer<uint> module_value_path_const_end;
RWStructuredBuffer<uint> module_value_path_status;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint INVALID = 0xffffffffu;
static const uint TY_UNKNOWN = 0u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_tokens)
        return;

    module_type_path_type[i] = TY_UNKNOWN;
    module_type_path_status[i] = INVALID;
    module_value_path_expr_head[i] = 0u;
    module_value_path_call_head[i] = 0u;
    module_value_path_call_open[i] = INVALID;
    module_value_path_const_head[i] = 0u;
    module_value_path_const_end[i] = INVALID;
    module_value_path_status[i] = INVALID;
}
