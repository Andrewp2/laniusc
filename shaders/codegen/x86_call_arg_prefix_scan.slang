// x86_64 call-argument width prefix scan.
//
// This pass scans the per-call argument width slots produced by
// x86_call_arg_prefix_seed and scatters explicit base/width records back to the
// original argument HIR nodes. It also writes a per-call total width / call-vreg
// summary row for later lowering.

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
StructuredBuffer<uint4> x86_call_arg_width_slot_record;
StructuredBuffer<uint> call_arg_prefix_seed_status;

RWStructuredBuffer<uint4> x86_call_arg_prefix_record;
RWStructuredBuffer<uint4> x86_call_arg_total_width_record;
RWStructuredBuffer<uint> call_arg_prefix_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_CALL_RECORDS_OK = 1u;
static const uint X86_CALL_ARG_PREFIX_SEED_OK = 1u;
static const uint X86_CALL_ARG_PREFIX_OK = 1u;
static const uint X86_SYSV_MAX_INTEGER_ARGS = 6u;
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

bool seed_ok()
{
    return call_arg_prefix_seed_status[0u] == X86_CALL_ARG_PREFIX_SEED_OK &&
           call_arg_prefix_seed_status[1u] == 0u;
}

bool upstream_ok()
{
    return call_records_ok() && seed_ok();
}

bool has_call_record(uint call_node)
{
    if (!valid_node(call_node))
        return false;

    uint4 record = x86_call_record[call_node];
    return record.x != INVALID || record.y != INVALID ||
           record.z != INVALID || record.w != INVALID;
}

uint width_slot_index(uint call_node, uint ordinal)
{
    return call_node * X86_SYSV_MAX_INTEGER_ARGS + ordinal;
}

void publish_upstream_error()
{
    call_arg_prefix_status[0u] = 0u;
    call_arg_prefix_status[1u] = call_records_ok() ?
                                 call_arg_prefix_seed_status[1u] :
                                 call_record_status[1u];
    call_arg_prefix_status[2u] = call_records_ok() ?
                                 call_arg_prefix_seed_status[2u] :
                                 call_record_status[2u];
    call_arg_prefix_status[3u] = 0u;
}

void publish_prefix_for_call(uint call_node)
{
    if (!has_call_record(call_node))
        return;

    uint arg_count = x86_call_record[call_node].w;
    if (arg_count > X86_SYSV_MAX_INTEGER_ARGS)
        return;

    uint base_vreg = 0u;
    [loop]
    for (uint ordinal = 0u; ordinal < X86_SYSV_MAX_INTEGER_ARGS; ordinal += 1u)
    {
        if (ordinal >= arg_count)
            break;

        uint4 slot_record = x86_call_arg_width_slot_record[width_slot_index(call_node, ordinal)];
        if (slot_record.x != call_node || slot_record.y == INVALID ||
            slot_record.z == 0u || slot_record.z == INVALID)
            return;

        uint arg_node = slot_record.y;
        uint width = slot_record.z;
        uint abi_reg = slot_record.w;
        uint next_vreg = base_vreg + width;
        if (!valid_node(arg_node) || abi_reg == INVALID || next_vreg >= MAX_X86_VREGS)
            return;

        x86_call_arg_prefix_record[arg_node] =
            uint4(call_node, ordinal, base_vreg, width);
        base_vreg = next_vreg;
    }

    x86_call_arg_total_width_record[call_node] =
        uint4(call_node, arg_count, base_vreg, base_vreg);
    uint old_count = 0u;
    InterlockedAdd(call_arg_prefix_status[3u], arg_count, old_count);
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

    publish_prefix_for_call(node_i);
}
