// x86_64 call-argument vreg range planning.
//
// Prefix planning owns argument base computation. This pass consumes explicit
// prefix/total rows and materializes argument result ranges plus per-call vreg
// summaries.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint4> x86_call_record;
StructuredBuffer<uint> call_record_status;
StructuredBuffer<uint4> x86_call_abi_record;
StructuredBuffer<uint> call_abi_status;
StructuredBuffer<uint4> x86_call_arg_prefix_record;
StructuredBuffer<uint4> x86_call_arg_total_width_record;
StructuredBuffer<uint> call_arg_prefix_status;
RWStructuredBuffer<uint4> x86_call_arg_range_record;
RWStructuredBuffer<uint4> x86_call_vreg_summary_record;
RWStructuredBuffer<uint4> x86_call_vreg_count_record;
RWStructuredBuffer<uint> call_arg_vreg_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_CALL_RECORDS_OK = 1u;
static const uint X86_CALL_ABI_OK = 1u;
static const uint X86_CALL_ARG_PREFIX_OK = 1u;
static const uint X86_CALL_ARG_VREGS_OK = 1u;
static const uint MAX_X86_VREGS = 8u;

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

bool call_records_ok()
{
    return call_record_status[0u] == X86_CALL_RECORDS_OK && call_record_status[1u] == 0u;
}

bool call_abi_ok()
{
    return call_abi_status[0u] == X86_CALL_ABI_OK && call_abi_status[1u] == 0u;
}

bool call_arg_prefix_ok()
{
    return call_arg_prefix_status[0u] == X86_CALL_ARG_PREFIX_OK &&
           call_arg_prefix_status[1u] == 0u;
}

bool upstream_ok()
{
    return call_records_ok() && call_abi_ok() && call_arg_prefix_ok();
}

bool has_call_record(uint call_node)
{
    if (!valid_node(call_node))
        return false;

    uint4 record = x86_call_record[call_node];
    return record.x != INVALID || record.y != INVALID ||
           record.z != INVALID || record.w != INVALID;
}

uint call_abi_base_row(uint call_node)
{
    return call_node * 2u;
}

uint4 call_abi_header(uint call_node)
{
    return x86_call_abi_record[call_abi_base_row(call_node)];
}

bool call_vreg_window_ok(uint call_node, uint arg_count, out uint total_width, out uint call_vreg)
{
    uint4 total_record = x86_call_arg_total_width_record[call_node];
    total_width = total_record.z;
    call_vreg = total_record.w;
    return total_record.x == call_node &&
           total_record.y == arg_count &&
           total_width == call_vreg &&
           total_width < MAX_X86_VREGS;
}

void publish_upstream_error()
{
    call_arg_vreg_status[0u] = 0u;
    call_arg_vreg_status[1u] = call_records_ok() ?
                               (call_abi_ok() ? call_arg_prefix_status[1u] : call_abi_status[1u]) :
                               call_record_status[1u];
    call_arg_vreg_status[2u] = call_records_ok() ?
                               (call_abi_ok() ? call_arg_prefix_status[2u] : call_abi_status[2u]) :
                               call_record_status[2u];
    call_arg_vreg_status[3u] = 0u;
}

void publish_arg_range(uint arg_node)
{
    uint4 prefix_record = x86_call_arg_prefix_record[arg_node];
    uint call_node = prefix_record.x;
    uint ordinal = prefix_record.y;
    uint base_vreg = prefix_record.z;
    uint width = prefix_record.w;
    if (!has_call_record(call_node) ||
        base_vreg == INVALID ||
        width == 0u ||
        width == INVALID)
        return;

    uint arg_count = x86_call_record[call_node].w;
    if (ordinal >= arg_count)
        return;

    uint next_vreg = base_vreg + width;
    if (next_vreg >= MAX_X86_VREGS)
        return;

    x86_call_arg_range_record[arg_node] = uint4(call_node, ordinal, base_vreg, next_vreg - 1u);
    uint old_count = 0u;
    InterlockedAdd(call_arg_vreg_status[3u], 1u, old_count);
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

    publish_arg_range(node_i);
}
