// x86_64 call-argument width slot scatter.
//
// Width rows are sparse by HIR argument node. This pass scatters them into a
// per-call/per-ordinal slot table so the following prefix pass can scan each
// call's argument widths without searching the full HIR node set.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint4> x86_call_arg_width_record;
StructuredBuffer<uint> call_arg_width_status;

RWStructuredBuffer<uint4> x86_call_arg_width_slot_record;
RWStructuredBuffer<uint> call_arg_prefix_seed_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_CALL_ARG_WIDTHS_OK = 1u;
static const uint X86_CALL_ARG_PREFIX_SEED_OK = 1u;
static const uint X86_SYSV_MAX_INTEGER_ARGS = 6u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool upstream_ok()
{
    return call_arg_width_status[0u] == X86_CALL_ARG_WIDTHS_OK &&
           call_arg_width_status[1u] == 0u;
}

uint width_slot_index(uint call_node, uint ordinal)
{
    return call_node * X86_SYSV_MAX_INTEGER_ARGS + ordinal;
}

void publish_upstream_error()
{
    call_arg_prefix_seed_status[0u] = 0u;
    call_arg_prefix_seed_status[1u] = call_arg_width_status[1u];
    call_arg_prefix_seed_status[2u] = call_arg_width_status[2u];
    call_arg_prefix_seed_status[3u] = 0u;
}

void scatter_width_slot(uint arg_node)
{
    uint4 width_record = x86_call_arg_width_record[arg_node];
    uint call_node = width_record.x;
    uint ordinal = width_record.y;
    uint width = width_record.z;
    uint abi_reg = width_record.w;
    if (!valid_node(call_node) || ordinal >= X86_SYSV_MAX_INTEGER_ARGS ||
        width == 0u || width == INVALID || abi_reg == INVALID)
        return;

    x86_call_arg_width_slot_record[width_slot_index(call_node, ordinal)] =
        uint4(call_node, arg_node, width, abi_reg);
    uint old_count = 0u;
    InterlockedAdd(call_arg_prefix_seed_status[3u], 1u, old_count);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (node_i == 0u && !upstream_ok())
        publish_upstream_error();

    if (!upstream_ok() || node_i >= active_hir_node_count())
        return;

    scatter_width_slot(node_i);
}
