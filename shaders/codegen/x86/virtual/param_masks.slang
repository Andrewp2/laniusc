// x86_64 per-function incoming parameter register masks.
//
// Register allocation needs to avoid assigning temporaries to ABI parameter
// registers that are still live as incoming values. This pass scatters those
// masks from virtual PARAM rows in parallel so regalloc does not do a
// function-local row scan just to recover the same relation.

import atomics;
import bitset;
import bit_packing;
import gpu_index;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
    uint virtual_next_call_step_count;
    uint regalloc_rows_per_chunk;
    uint regalloc_chunk_count;
    uint function_slot_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint4> x86_virtual_inst_record;
StructuredBuffer<uint4> x86_virtual_inst_args;
StructuredBuffer<uint> x86_virtual_inst_status;
StructuredBuffer<uint> x86_virtual_func_slot;

RWStructuredBuffer<uint> x86_func_param_reg_mask;
RWStructuredBuffer<uint> x86_func_param_reg_mask_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_FUNC_PARAM_REG_MASK_OK = 1u;
static const uint X86_ERR_FUNC_PARAM_REG_MASK = 20u;
static const uint X86_VINST_PARAM = 2u;
static const uint X86_VINST_CALL_MIXED = 20u;
static const uint X86_VINST_LOAD_PARAM_INDEX = 21u;
static const uint X86_VINST_LOAD_PARAM_SLOT = 26u;
static const uint X86_VINST_FOR_PARAM_ARRAY_LOAD = 31u;
static const uint X86_VINST_STORE_PARAM_INDEX = 32u;
static const uint X86_ARG_PARAM_PTR = 3u;
static const uint X86_REG_EDI = 7u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint virtual_inst_count()
{
    return min(x86_virtual_inst_status[3u], gParams.inst_capacity);
}

bool upstream_ok()
{
    return x86_virtual_inst_status[0u] == X86_VIRTUAL_INST_OK &&
           x86_virtual_inst_status[1u] == 0u &&
           x86_virtual_inst_status[3u] <= gParams.inst_capacity;
}

void publish_status(bool ok, uint count)
{
    write_stage_status4_from_result(
        x86_func_param_reg_mask_status,
        ok,
        X86_FUNC_PARAM_REG_MASK_OK,
        INVALID,
        X86_ERR_FUNC_PARAM_REG_MASK,
        x86_virtual_inst_status[1u],
        count,
        x86_virtual_inst_status[2u],
        count);
}

uint mixed_arg_kind(uint info, uint ordinal)
{
    if (ordinal < 4u)
        return packed_u2_at_offset(info, 12u, ordinal);
    if (ordinal < 6u)
        return packed_u2_at_offset(info, 20u, ordinal - 4u);
    return 0u;
}

bool mixed_arg_payload_row(uint row, uint count, out uint payload_row)
{
    payload_row = INVALID;
    uint4 call_inst = x86_virtual_inst_record[row];
    if (call_inst.z != X86_VINST_CALL_MIXED)
        return false;

    uint payload = x86_virtual_inst_args[row].z;
    if (payload == INVALID || payload >= count)
        return false;

    uint4 payload_inst = x86_virtual_inst_record[payload];
    if (payload_inst.x != call_inst.x ||
        payload_inst.y != 1u ||
        payload_inst.z != 0u)
        return false;

    payload_row = payload;
    return true;
}

uint mixed_arg_payload(uint row, uint ordinal, uint count)
{
    uint payload_row = INVALID;
    if (!mixed_arg_payload_row(row, count, payload_row) || ordinal >= 6u)
        return INVALID;
    if (ordinal < 3u)
        return x86_virtual_inst_args[payload_row][ordinal];

    uint payload_row_hi = x86_virtual_inst_record[payload_row].w;
    if (payload_row_hi == INVALID || payload_row_hi >= count)
        return INVALID;
    return x86_virtual_inst_args[payload_row_hi][ordinal - 3u];
}

void add_param_register(uint fn_slot, uint reg)
{
    if (!bitset32_valid_bit(reg))
    {
        publish_stage_error_min_detail4(
            x86_func_param_reg_mask_status,
            X86_ERR_FUNC_PARAM_REG_MASK,
            reg);
        return;
    }

    atomic_u32_or(x86_func_param_reg_mask, fn_slot, bitset32_single(reg));
    if (reg != X86_REG_EDI)
        atomic_u32_or(x86_func_param_reg_mask, fn_slot, bitset32_single(X86_REG_EDI));
}

void add_param_pointer_call_arg(uint row, uint fn_slot, uint ordinal, uint count)
{
    uint info = x86_virtual_inst_args[row].w;
    if (mixed_arg_kind(info, ordinal) != X86_ARG_PARAM_PTR)
        return;

    uint payload = mixed_arg_payload(row, ordinal, count);
    if (payload == INVALID)
        return;
    add_param_register(fn_slot, unpack_u16_pair_low(payload));
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    bool ok = upstream_ok();
    uint count = ok ? virtual_inst_count() : 0u;

    if (row == 0u)
        publish_status(ok, count);

    if (!ok || row >= count)
        return;

    uint op = x86_virtual_inst_record[row].z;
    if (op != X86_VINST_PARAM &&
        op != X86_VINST_CALL_MIXED &&
        op != X86_VINST_LOAD_PARAM_INDEX &&
        op != X86_VINST_LOAD_PARAM_SLOT &&
        op != X86_VINST_FOR_PARAM_ARRAY_LOAD &&
        op != X86_VINST_STORE_PARAM_INDEX)
        return;

    uint fn_slot = x86_virtual_func_slot[row];
    if (fn_slot >= gParams.function_slot_capacity)
        return;

    if (op == X86_VINST_CALL_MIXED)
    {
        add_param_pointer_call_arg(row, fn_slot, 0u, count);
        add_param_pointer_call_arg(row, fn_slot, 1u, count);
        add_param_pointer_call_arg(row, fn_slot, 2u, count);
        add_param_pointer_call_arg(row, fn_slot, 3u, count);
        add_param_pointer_call_arg(row, fn_slot, 4u, count);
        add_param_pointer_call_arg(row, fn_slot, 5u, count);
        return;
    }

    uint payload = x86_virtual_inst_args[row].x;
    uint reg = op == X86_VINST_PARAM
                   ? x86_virtual_inst_args[row].z
                   : op == X86_VINST_LOAD_PARAM_SLOT
                         ? payload
                         : unpack_u16_pair_low(payload);
    if (!bitset32_valid_bit(reg))
    {
        publish_stage_error_min_detail4(
            x86_func_param_reg_mask_status,
            X86_ERR_FUNC_PARAM_REG_MASK,
            row);
        return;
    }

    atomic_u32_or(x86_func_param_reg_mask, fn_slot, bitset32_single(reg));
    if (op != X86_VINST_PARAM && reg != X86_REG_EDI)
        atomic_u32_or(x86_func_param_reg_mask, fn_slot, bitset32_single(X86_REG_EDI));
}
