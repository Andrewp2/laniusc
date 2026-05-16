// x86_64 call-argument evaluation width projection.
//
// This pass classifies each HIR-derived argument evaluation row into the number
// of backend vregs it requires. Later range planning consumes these sparse
// width rows and assigns bases/results.

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
StructuredBuffer<uint4> x86_call_arg_value_record;
StructuredBuffer<uint4> x86_call_arg_eval_record;
StructuredBuffer<uint> call_arg_value_status;
StructuredBuffer<uint4> x86_call_arg_abi_record;
StructuredBuffer<uint> call_abi_status;

RWStructuredBuffer<uint4> x86_call_arg_width_record;
RWStructuredBuffer<uint> call_arg_width_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_CALL_RECORDS_OK = 1u;
static const uint X86_CALL_ARG_VALUES_OK = 1u;
static const uint X86_CALL_ABI_OK = 1u;
static const uint X86_CALL_ARG_WIDTHS_OK = 1u;
static const uint X86_CALL_ARG_VALUE_SCALAR = 1u;
static const uint X86_CALL_ARG_VALUE_BINARY_IMM = 2u;
static const uint X86_CALL_ARG_EVAL_SCALAR_IMM = 1u;
static const uint X86_CALL_ARG_EVAL_BINARY_IMM = 2u;
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

bool call_records_ok()
{
    return call_record_status[0u] == X86_CALL_RECORDS_OK && call_record_status[1u] == 0u;
}

bool call_arg_values_ok()
{
    return call_arg_value_status[0u] == X86_CALL_ARG_VALUES_OK &&
           call_arg_value_status[1u] == 0u;
}

bool call_abi_ok()
{
    return call_abi_status[0u] == X86_CALL_ABI_OK && call_abi_status[1u] == 0u;
}

bool upstream_ok()
{
    return call_records_ok() && call_arg_values_ok() && call_abi_ok();
}

bool has_call_record(uint call_node)
{
    if (!valid_node(call_node))
        return false;

    uint4 record = x86_call_record[call_node];
    return record.x != INVALID || record.y != INVALID ||
           record.z != INVALID || record.w != INVALID;
}

bool eval_matches_value_kind(uint value_kind, uint eval_kind)
{
    if (value_kind == X86_CALL_ARG_VALUE_SCALAR)
        return eval_kind == X86_CALL_ARG_EVAL_SCALAR_IMM;
    if (value_kind == X86_CALL_ARG_VALUE_BINARY_IMM)
        return eval_kind == X86_CALL_ARG_EVAL_BINARY_IMM;
    return false;
}

uint arg_eval_width(uint value_kind, uint eval_kind)
{
    if (!eval_matches_value_kind(value_kind, eval_kind))
        return 0u;
    if (value_kind == X86_CALL_ARG_VALUE_SCALAR)
        return 1u;
    if (value_kind == X86_CALL_ARG_VALUE_BINARY_IMM)
        return 3u;
    return 0u;
}

void publish_upstream_error()
{
    call_arg_width_status[0u] = 0u;
    call_arg_width_status[1u] = call_records_ok() ?
                                (call_arg_values_ok() ? call_abi_status[1u] : call_arg_value_status[1u]) :
                                call_record_status[1u];
    call_arg_width_status[2u] = call_records_ok() ?
                                (call_arg_values_ok() ? call_abi_status[2u] : call_arg_value_status[2u]) :
                                call_record_status[2u];
    call_arg_width_status[3u] = 0u;
}

void publish_arg_width(uint arg_node)
{
    uint4 value_record = x86_call_arg_value_record[arg_node];
    uint call_node = value_record.x;
    uint ordinal = value_record.y;
    uint value_kind = value_record.z;
    if (!has_call_record(call_node))
        return;

    uint arg_count = x86_call_record[call_node].w;
    if (ordinal >= arg_count || ordinal >= X86_SYSV_MAX_INTEGER_ARGS)
        return;

    uint4 abi_record = x86_call_arg_abi_record[arg_node];
    if (abi_record.x != call_node || abi_record.y != ordinal || abi_record.z == INVALID)
        return;

    uint4 eval_record = x86_call_arg_eval_record[arg_node];
    uint width = arg_eval_width(value_kind, eval_record.x);
    if (width == 0u)
        return;

    x86_call_arg_width_record[arg_node] = uint4(call_node, ordinal, width, abi_record.z);
    uint old_count = 0u;
    InterlockedAdd(call_arg_width_status[3u], 1u, old_count);
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

    publish_arg_width(node_i);
}
