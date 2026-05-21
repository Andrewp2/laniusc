// x86_64 virtual-instruction suffix scan for call-clobber facts.
//
// Each step materializes, for every virtual instruction row, the nearest call
// row at or after that row within the same function segment. Register
// allocation consumes this explicit relation instead of using the physical
// register output buffer as temporary scratch.

import gpu_index;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint inst_capacity;
};

[__AttributeUsage(_AttributeTargets.Var)]
struct DynamicOffsetAttribute
{
};

ConstantBuffer<Params> gParams;
[DynamicOffset]
ConstantBuffer<ScanParams> gNextCallScan;

StructuredBuffer<uint4> x86_virtual_inst_record;
StructuredBuffer<uint4> x86_virtual_inst_args;
StructuredBuffer<uint> x86_virtual_inst_status;
StructuredBuffer<uint> x86_virtual_func_slot;
StructuredBuffer<uint> x86_virtual_next_call_in;

RWStructuredBuffer<uint> x86_virtual_next_call_out;
RWStructuredBuffer<uint> x86_virtual_next_call_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_VIRTUAL_NEXT_CALLS_OK = 1u;
static const uint X86_ERR_VIRTUAL_NEXT_CALLS = 19u;
static const uint X86_VINST_BINARY = 4u;
static const uint X86_VINST_CALL_MIXED = 20u;
static const uint X86_OP_MOD_I32 = 6u;
static const uint X86_OP_DIV_I32 = 7u;
static const uint X86_OP_SHL_I32 = 11u;
static const uint X86_OP_SHR_I32 = 12u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint virtual_inst_count()
{
    return min(x86_virtual_inst_status[3u], min(gNextCallScan.n_items, gParams.inst_capacity));
}

bool upstream_ok()
{
    return x86_virtual_inst_status[0u] == X86_VIRTUAL_INST_OK &&
           x86_virtual_inst_status[1u] == 0u &&
           x86_virtual_inst_status[3u] <= gNextCallScan.n_items &&
           gNextCallScan.n_items <= gParams.inst_capacity &&
           gNextCallScan.inst_capacity == gParams.inst_capacity;
}

uint row_function_slot(uint row, uint inst_count)
{
    if (row >= inst_count)
        return INVALID;
    uint slot = x86_virtual_func_slot[row];
    return slot < gParams.n_tokens ? slot : INVALID;
}

bool call_belongs_to_row_function(uint row, uint call_row, uint inst_count)
{
    uint row_slot = row_function_slot(row, inst_count);
    if (row_slot == INVALID)
        return true;
    return call_row < inst_count && row_slot == row_function_slot(call_row, inst_count);
}

bool row_has_fixed_register_barrier(uint row, uint inst_count)
{
    if (row >= inst_count)
        return false;
    uint4 inst = x86_virtual_inst_record[row];
    if (inst.z == X86_VINST_CALL_MIXED)
        return true;
    if (inst.z != X86_VINST_BINARY)
        return false;
    uint op = x86_virtual_inst_args[row].x;
    return op == X86_OP_DIV_I32 ||
           op == X86_OP_MOD_I32 ||
           op == X86_OP_SHL_I32 ||
           op == X86_OP_SHR_I32;
}

uint nearest_valid_call(uint current, uint right)
{
    return current != INVALID ? current : right;
}

uint next_call_scan_value(uint row, uint inst_count)
{
    if (row >= inst_count)
        return INVALID;

    if (gNextCallScan.scan_step == 0u)
        return row_has_fixed_register_barrier(row, inst_count) ? row : INVALID;

    uint current = x86_virtual_next_call_in[row];
    uint right_row = row + gNextCallScan.scan_step;
    uint right = right_row < inst_count ? x86_virtual_next_call_in[right_row] : INVALID;

    uint next = nearest_valid_call(current, right);
    return call_belongs_to_row_function(row, next, inst_count) ? next : INVALID;
}

void publish_status(bool ok, uint count)
{
    write_stage_status4_from_result(
        x86_virtual_next_call_status,
        ok,
        X86_VIRTUAL_NEXT_CALLS_OK,
        INVALID,
        X86_ERR_VIRTUAL_NEXT_CALLS,
        x86_virtual_inst_status[1u],
        count,
        x86_virtual_inst_status[2u],
        count);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    uint count = virtual_inst_count();
    bool ok = upstream_ok();

    if (row == 0u)
        publish_status(ok, count);

    if (row >= gNextCallScan.n_items)
        return;

    if (gNextCallScan.scan_step >= count && gNextCallScan.scan_step != 0u)
        return;

    x86_virtual_next_call_out[row] = ok ? next_call_scan_value(row, count) : INVALID;
}
