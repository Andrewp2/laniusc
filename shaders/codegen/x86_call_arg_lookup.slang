// x86_64 call-argument lookup scatter.
//
// x86_call_arg_values publishes sparse per-HIR-node argument value records.
// This pass scatters those rows into stable per-call/per-ordinal lookup slots
// so ABI projection can read argument identity without rediscovering
// relationships by scanning the whole HIR node set.

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
StructuredBuffer<uint> call_arg_value_status;

RWStructuredBuffer<uint4> x86_call_arg_lookup_record;
RWStructuredBuffer<uint> call_arg_lookup_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_CALL_RECORDS_OK = 1u;
static const uint X86_CALL_ARG_VALUES_OK = 1u;
static const uint X86_CALL_ARG_LOOKUP_OK = 1u;
static const uint X86_CALL_ARG_VALUE_SCALAR = 1u;
static const uint X86_CALL_ARG_VALUE_BINARY_IMM = 2u;
static const uint X86_CALL_ARG_VALUE_PARAM = 3u;
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

bool upstream_ok()
{
    return call_records_ok() && call_arg_values_ok();
}

bool supported_arg_value_kind(uint kind)
{
    return kind == X86_CALL_ARG_VALUE_SCALAR ||
           kind == X86_CALL_ARG_VALUE_BINARY_IMM ||
           kind == X86_CALL_ARG_VALUE_PARAM;
}

bool has_call_record(uint call_node)
{
    if (!valid_node(call_node))
        return false;

    uint4 record = x86_call_record[call_node];
    return record.x != INVALID || record.y != INVALID ||
           record.z != INVALID || record.w != INVALID;
}

uint lookup_slot(uint call_node, uint ordinal)
{
    return call_node * X86_SYSV_MAX_INTEGER_ARGS + ordinal;
}

void publish_upstream_error()
{
    call_arg_lookup_status[0u] = 0u;
    call_arg_lookup_status[1u] = call_records_ok() ?
                                 call_arg_value_status[1u] :
                                 call_record_status[1u];
    call_arg_lookup_status[2u] = call_records_ok() ?
                                 call_arg_value_status[2u] :
                                 call_record_status[2u];
    call_arg_lookup_status[3u] = 0u;
}

void scatter_arg_lookup(uint arg_node)
{
    uint4 value_record = x86_call_arg_value_record[arg_node];
    uint call_node = value_record.x;
    uint ordinal = value_record.y;
    uint value_kind = value_record.z;
    if (!supported_arg_value_kind(value_kind) || !has_call_record(call_node))
        return;

    uint arg_count = x86_call_record[call_node].w;
    if (ordinal >= arg_count || ordinal >= X86_SYSV_MAX_INTEGER_ARGS)
        return;

    x86_call_arg_lookup_record[lookup_slot(call_node, ordinal)] =
        uint4(call_node, ordinal, arg_node, value_kind);
    uint old_count = 0u;
    InterlockedAdd(call_arg_lookup_status[3u], 1u, old_count);
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

    scatter_arg_lookup(node_i);
}
