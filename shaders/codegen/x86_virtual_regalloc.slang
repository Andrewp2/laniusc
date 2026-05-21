// x86_64 register allocation over virtual-instruction liveness intervals.

import bitset;
import gpu_index;
import linear_scan;
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

struct RegallocParams
{
    uint chunk_start;
    uint chunk_len;
    uint init_status;
    uint reserved;
};

[__AttributeUsage(_AttributeTargets.Var)]
struct DynamicOffsetAttribute
{
};

ConstantBuffer<Params> gParams;
[DynamicOffset]
ConstantBuffer<RegallocParams> gRegalloc;

StructuredBuffer<uint> x86_func_meta;
StructuredBuffer<uint> x86_func_slot_by_index;
StructuredBuffer<uint4> x86_virtual_inst_record;
StructuredBuffer<uint4> x86_virtual_inst_args;
StructuredBuffer<uint> x86_virtual_live_start;
StructuredBuffer<uint> x86_virtual_live_end;
StructuredBuffer<uint> x86_virtual_liveness_status;
StructuredBuffer<uint> x86_virtual_next_call_status;
StructuredBuffer<uint> x86_func_param_reg_mask;
StructuredBuffer<uint> x86_func_param_reg_mask_status;
StructuredBuffer<uint> x86_func_first_virtual_row;
StructuredBuffer<uint> x86_func_last_virtual_row;
StructuredBuffer<uint> x86_func_first_virtual_row_status;
StructuredBuffer<uint> x86_virtual_value_def_status;
StructuredBuffer<uint> x86_virtual_func_slot;

RWStructuredBuffer<uint> x86_virtual_regalloc_active_end;
RWStructuredBuffer<uint> x86_virtual_regalloc_param_rank_mask;
RWStructuredBuffer<uint> x86_virtual_phys_reg;
RWStructuredBuffer<uint> x86_virtual_call_live_reg_mask;
RWStructuredBuffer<uint> x86_virtual_regalloc_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_VIRTUAL_LIVENESS_OK = 1u;
static const uint X86_VIRTUAL_NEXT_CALLS_OK = 1u;
static const uint X86_FUNC_PARAM_REG_MASK_OK = 1u;
static const uint X86_FUNC_FIRST_VIRTUAL_ROW_OK = 1u;
static const uint X86_VIRTUAL_VALUE_DEFS_OK = 1u;
static const uint X86_VIRTUAL_REGALLOC_OK = 1u;
static const uint X86_ERR_VIRTUAL_REGALLOC = 15u;
static const uint X86_VINST_PARAM = 2u;
static const uint X86_VINST_BINARY = 4u;
static const uint X86_VINST_CALL_MIXED = 20u;
static const uint X86_OP_SHL_I32 = 11u;
static const uint X86_OP_SHR_I32 = 12u;
static const uint FUNC_META_FUNC_COUNT = 0u;
static const uint FUNC_META_REGALLOC_ACTIVE_CHUNKS = 6u;
static const uint FUNC_META_REGALLOC_RECORDED_CHUNKS = 7u;
static const uint MAX_REGALLOC_ROWS_PER_CHUNK = 256u;
static const int X86_TEMP_REG_RANK_COUNT = 14;
static const uint X86_TEMP_REG_RANK_MASK = 0x3fffu;
static const uint X86_RANK_MASK_EAX = 0x0001u;
static const uint X86_RANK_MASK_R10D = 0x0002u;
static const uint X86_RANK_MASK_R8D = 0x0004u;
static const uint X86_RANK_MASK_R9D = 0x0008u;
static const uint X86_RANK_MASK_ECX = 0x0010u;
static const uint X86_RANK_MASK_EDX = 0x0020u;
static const uint X86_RANK_MASK_ESI = 0x0040u;
static const uint X86_RANK_MASK_EDI = 0x0080u;
static const uint X86_RANK_MASK_R11D = 0x0100u;
static const uint X86_RANK_MASK_EBX = 0x0200u;
static const uint X86_RANK_MASK_R12D = 0x0400u;
static const uint X86_RANK_MASK_R13D = 0x0800u;
static const uint X86_RANK_MASK_R14D = 0x1000u;
static const uint X86_RANK_MASK_R15D = 0x2000u;
static const uint X86_FIXED_BARRIER_RANK_MASK =
    X86_RANK_MASK_EAX |
    X86_RANK_MASK_ECX |
    X86_RANK_MASK_EDX |
    X86_RANK_MASK_EBX |
    X86_RANK_MASK_R12D |
    X86_RANK_MASK_R13D |
    X86_RANK_MASK_R14D |
    X86_RANK_MASK_R15D;

static const uint X86_REG_EAX = 0u;
static const uint X86_REG_ECX = 1u;
static const uint X86_REG_EDX = 2u;
static const uint X86_REG_EBX = 3u;
static const uint X86_REG_ESI = 6u;
static const uint X86_REG_EDI = 7u;
static const uint X86_REG_R8D = 8u;
static const uint X86_REG_R9D = 9u;
static const uint X86_REG_R10D = 10u;
static const uint X86_REG_R11D = 11u;
static const uint X86_REG_R12D = 12u;
static const uint X86_REG_R13D = 13u;
static const uint X86_REG_R14D = 14u;
static const uint X86_REG_R15D = 15u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

bool inst_has_value_def(uint4 inst, uint row)
{
    return inst.x != INVALID && inst.z != 0u && inst.w == row;
}

uint temp_register_for_rank(uint rank)
{
    if (rank == 0u) return X86_REG_EAX;
    if (rank == 1u) return X86_REG_R10D;
    if (rank == 2u) return X86_REG_R8D;
    if (rank == 3u) return X86_REG_R9D;
    if (rank == 4u) return X86_REG_ECX;
    if (rank == 5u) return X86_REG_EDX;
    if (rank == 6u) return X86_REG_ESI;
    if (rank == 7u) return X86_REG_EDI;
    if (rank == 8u) return X86_REG_R11D;
    if (rank == 9u) return X86_REG_EBX;
    if (rank == 10u) return X86_REG_R12D;
    if (rank == 11u) return X86_REG_R13D;
    if (rank == 12u) return X86_REG_R14D;
    if (rank == 13u) return X86_REG_R15D;
    return INVALID;
}

bool reg_mask_contains(uint mask, uint reg)
{
    return bitset32_contains(mask, reg);
}

uint rank_mask_for_register(uint reg)
{
    if (reg == X86_REG_EAX) return X86_RANK_MASK_EAX;
    if (reg == X86_REG_R10D) return X86_RANK_MASK_R10D;
    if (reg == X86_REG_R8D) return X86_RANK_MASK_R8D;
    if (reg == X86_REG_R9D) return X86_RANK_MASK_R9D;
    if (reg == X86_REG_ECX) return X86_RANK_MASK_ECX;
    if (reg == X86_REG_EDX) return X86_RANK_MASK_EDX;
    if (reg == X86_REG_ESI) return X86_RANK_MASK_ESI;
    if (reg == X86_REG_EDI) return X86_RANK_MASK_EDI;
    if (reg == X86_REG_R11D) return X86_RANK_MASK_R11D;
    if (reg == X86_REG_EBX) return X86_RANK_MASK_EBX;
    if (reg == X86_REG_R12D) return X86_RANK_MASK_R12D;
    if (reg == X86_REG_R13D) return X86_RANK_MASK_R13D;
    if (reg == X86_REG_R14D) return X86_RANK_MASK_R14D;
    if (reg == X86_REG_R15D) return X86_RANK_MASK_R15D;
    return 0u;
}

uint call_live_mask_for_rank(uint rank)
{
    if (rank == 1u) return 1u << 6u; // R10D
    if (rank == 2u) return 1u << 4u; // R8D
    if (rank == 3u) return 1u << 5u; // R9D
    if (rank == 4u) return 1u << 0u; // ECX
    if (rank == 5u) return 1u << 1u; // EDX
    if (rank == 6u) return 1u << 2u; // ESI
    if (rank == 7u) return 1u << 3u; // EDI
    if (rank == 8u) return 1u << 7u; // R11D
    return 0u;
}

void active_rank_masks(
    uint start,
    bool compute_call_live_mask,
    uint active_end[X86_TEMP_REG_RANK_COUNT],
    out uint available_mask,
    out uint call_live_mask)
{
    uint available = 0u;
    uint live_across_call = 0u;
    [unroll]
    for (uint rank = 0u; rank < uint(X86_TEMP_REG_RANK_COUNT); rank += 1u)
    {
        uint end = active_end[rank];
        if (end == INVALID || end < start)
        {
            available |= 1u << rank;
        }
        else if (compute_call_live_mask && end > start)
        {
            live_across_call |= call_live_mask_for_rank(rank);
        }
    }
    available_mask = available & X86_TEMP_REG_RANK_MASK;
    call_live_mask = live_across_call;
}

uint first_rank_from_mask(uint mask)
{
    mask &= X86_TEMP_REG_RANK_MASK;
    return mask == 0u ? INVALID : uint(firstbitlow(mask));
}

bool allocation_status_inputs_valid(uint inst_count)
{
    return x86_virtual_liveness_status[0u] == X86_VIRTUAL_LIVENESS_OK &&
           x86_virtual_liveness_status[1u] == 0u &&
           x86_virtual_liveness_status[3u] == inst_count &&
           x86_virtual_next_call_status[0u] == X86_VIRTUAL_NEXT_CALLS_OK &&
           x86_virtual_next_call_status[1u] == 0u &&
           x86_virtual_next_call_status[3u] == inst_count &&
           x86_func_param_reg_mask_status[0u] == X86_FUNC_PARAM_REG_MASK_OK &&
           x86_func_param_reg_mask_status[1u] == 0u &&
           x86_func_param_reg_mask_status[3u] == inst_count &&
           x86_func_first_virtual_row_status[0u] == X86_FUNC_FIRST_VIRTUAL_ROW_OK &&
           x86_func_first_virtual_row_status[1u] == 0u &&
           x86_func_first_virtual_row_status[3u] == inst_count &&
           x86_virtual_value_def_status[0u] == X86_VIRTUAL_VALUE_DEFS_OK &&
           x86_virtual_value_def_status[1u] == 0u &&
           x86_virtual_value_def_status[3u] <= inst_count &&
           inst_count <= gParams.inst_capacity;
}

bool inst_is_call_result(uint4 inst)
{
    return inst.z == X86_VINST_CALL_MIXED;
}

bool inst_is_param_copy(uint4 inst)
{
    return inst.z == X86_VINST_PARAM;
}

bool inst_is_shift_result(uint row, uint4 inst)
{
    if (inst.z != X86_VINST_BINARY)
        return false;
    uint op = x86_virtual_inst_args[row].x;
    return op == X86_OP_SHL_I32 || op == X86_OP_SHR_I32;
}

uint fixed_disallowed_rank_mask(bool spans_fixed_barrier, bool call_result, bool shift_result)
{
    uint mask = 0u;
    if (spans_fixed_barrier)
        mask |= X86_FIXED_BARRIER_RANK_MASK;
    if (call_result)
        mask |= X86_RANK_MASK_EAX;
    if (shift_result)
        mask |= X86_RANK_MASK_ECX;
    return mask;
}

uint param_disallowed_rank_mask(uint register_mask)
{
    if (register_mask == 0u)
        return 0u;
    uint mask = 0u;
    if (reg_mask_contains(register_mask, X86_REG_EAX)) mask |= rank_mask_for_register(X86_REG_EAX);
    if (reg_mask_contains(register_mask, X86_REG_R10D)) mask |= rank_mask_for_register(X86_REG_R10D);
    if (reg_mask_contains(register_mask, X86_REG_R8D)) mask |= rank_mask_for_register(X86_REG_R8D);
    if (reg_mask_contains(register_mask, X86_REG_R9D)) mask |= rank_mask_for_register(X86_REG_R9D);
    if (reg_mask_contains(register_mask, X86_REG_ECX)) mask |= rank_mask_for_register(X86_REG_ECX);
    if (reg_mask_contains(register_mask, X86_REG_EDX)) mask |= rank_mask_for_register(X86_REG_EDX);
    if (reg_mask_contains(register_mask, X86_REG_ESI)) mask |= rank_mask_for_register(X86_REG_ESI);
    if (reg_mask_contains(register_mask, X86_REG_EDI)) mask |= rank_mask_for_register(X86_REG_EDI);
    if (reg_mask_contains(register_mask, X86_REG_R11D)) mask |= rank_mask_for_register(X86_REG_R11D);
    if (reg_mask_contains(register_mask, X86_REG_EBX)) mask |= rank_mask_for_register(X86_REG_EBX);
    if (reg_mask_contains(register_mask, X86_REG_R12D)) mask |= rank_mask_for_register(X86_REG_R12D);
    if (reg_mask_contains(register_mask, X86_REG_R13D)) mask |= rank_mask_for_register(X86_REG_R13D);
    if (reg_mask_contains(register_mask, X86_REG_R14D)) mask |= rank_mask_for_register(X86_REG_R14D);
    if (reg_mask_contains(register_mask, X86_REG_R15D)) mask |= rank_mask_for_register(X86_REG_R15D);
    return mask;
}

uint disallowed_rank_mask(uint param_rank_mask, bool spans_fixed_barrier, bool call_result, bool shift_result)
{
    return bitset32_union(
        fixed_disallowed_rank_mask(spans_fixed_barrier, call_result, shift_result),
        param_rank_mask);
}

bool function_row_bounds(uint fn_slot, uint inst_count, out uint start_row, out uint end_row)
{
    start_row = x86_func_first_virtual_row[fn_slot];
    uint last_row = x86_func_last_virtual_row[fn_slot];
    end_row = INVALID;

    if (start_row == INVALID)
        return false;

    if (start_row > last_row ||
        last_row >= inst_count)
        return true;

    end_row = last_row + 1u;
    return true;
}

uint active_end_slot(uint func_i, uint rank)
{
    return func_i * uint(X86_TEMP_REG_RANK_COUNT) + rank;
}

void load_active_end(uint func_i, inout uint active_end[X86_TEMP_REG_RANK_COUNT])
{
    [unroll]
    for (uint rank = 0u; rank < uint(X86_TEMP_REG_RANK_COUNT); rank += 1u)
    {
        active_end[rank] = gRegalloc.chunk_start == 0u
            ? INVALID
            : x86_virtual_regalloc_active_end[active_end_slot(func_i, rank)];
    }
}

void store_active_end(uint func_i, uint active_end[X86_TEMP_REG_RANK_COUNT])
{
    [unroll]
    for (uint rank = 0u; rank < uint(X86_TEMP_REG_RANK_COUNT); rank += 1u)
        x86_virtual_regalloc_active_end[active_end_slot(func_i, rank)] = active_end[rank];
}

uint load_param_rank_mask(uint func_i, uint fn_slot)
{
    return gRegalloc.chunk_start == 0u
        ? param_disallowed_rank_mask(x86_func_param_reg_mask[fn_slot])
        : x86_virtual_regalloc_param_rank_mask[func_i];
}

bool allocate_virtual_row(
    uint row,
    uint fn_slot,
    inout uint active_end[X86_TEMP_REG_RANK_COUNT],
    inout uint current_param_rank_mask)
{
    uint4 inst = x86_virtual_inst_record[row];
    if (inst_has_value_def(inst, row) && x86_virtual_func_slot[row] == fn_slot)
    {
        uint start = x86_virtual_live_start[row];
        uint end = x86_virtual_live_end[row];
        if (start == INVALID || end == INVALID || start > end)
            return false;

        bool spans_fixed_barrier = x86_virtual_call_live_reg_mask[row] != 0u;
        bool call_result = inst_is_call_result(inst);
        bool shift_result = inst_is_shift_result(row, inst);
        uint available_rank_mask = 0u;
        uint call_live_mask = 0u;
        active_rank_masks(start, call_result, active_end, available_rank_mask, call_live_mask);
        if (call_result)
            x86_virtual_call_live_reg_mask[row] = call_live_mask;

        uint candidate_rank_mask = available_rank_mask &
            ~disallowed_rank_mask(
                current_param_rank_mask,
                spans_fixed_barrier,
                call_result,
                shift_result);
        uint selected_rank = first_rank_from_mask(candidate_rank_mask);

        if (selected_rank == INVALID)
            return false;
        uint selected_reg = temp_register_for_rank(selected_rank);
        x86_virtual_phys_reg[row] = selected_reg;
        linear_scan_activate_rank<X86_TEMP_REG_RANK_COUNT>(
            selected_rank,
            end,
            active_end);
        if (inst_is_param_copy(inst))
            current_param_rank_mask &= ~rank_mask_for_register(x86_virtual_inst_args[row].z);
    }
    return true;
}

bool allocate_function_row_offset(uint func_i, uint fn_slot, uint inst_count)
{
    uint start_row = INVALID;
    uint end_row = INVALID;
    if (!function_row_bounds(fn_slot, inst_count, start_row, end_row))
        return true;
    if (end_row == INVALID)
        return false;

    uint chunk_start_row = start_row + gRegalloc.chunk_start;
    if (chunk_start_row >= end_row || chunk_start_row < start_row)
        return true;

    uint active_end[X86_TEMP_REG_RANK_COUNT];
    load_active_end(func_i, active_end);
    // Scalar parameter rows copy incoming ABI registers into frame slots at
    // function entry, before the rest of the function has live temporaries.
    // After that copy, those ABI registers are ordinary allocatable temps.
    uint current_param_rank_mask = load_param_rank_mask(func_i, fn_slot);
    uint chunk_len = min(gRegalloc.chunk_len, MAX_REGALLOC_ROWS_PER_CHUNK);
    uint last_processed_row = chunk_start_row;
    bool processed_any = false;

    [unroll]
    for (uint local_i = 0u; local_i < MAX_REGALLOC_ROWS_PER_CHUNK; local_i += 1u)
    {
        if (local_i < chunk_len)
        {
            uint row = chunk_start_row + local_i;
            if (row >= chunk_start_row && row < end_row)
            {
                if (!allocate_virtual_row(row, fn_slot, active_end, current_param_rank_mask))
                    return false;
                last_processed_row = row;
                processed_any = true;
            }
        }
    }

    if (processed_any && last_processed_row + 1u < end_row)
    {
        store_active_end(func_i, active_end);
        x86_virtual_regalloc_param_rank_mask[func_i] = current_param_rank_mask;
    }
    return true;
}

void initialize_status(uint inst_count)
{
    uint active_chunks = x86_func_meta[FUNC_META_REGALLOC_ACTIVE_CHUNKS];
    uint recorded_chunks = x86_func_meta[FUNC_META_REGALLOC_RECORDED_CHUNKS];
    bool recorded_span_ok = recorded_chunks >= active_chunks;
    bool ok = allocation_status_inputs_valid(inst_count) && recorded_span_ok;
    if (!ok)
    {
        uint upstream_error = !recorded_span_ok
            ? X86_ERR_VIRTUAL_REGALLOC
            : (x86_virtual_liveness_status[1u] != 0u
            ? x86_virtual_liveness_status[1u]
            : (x86_virtual_next_call_status[1u] != 0u
                ? x86_virtual_next_call_status[1u]
                : (x86_func_param_reg_mask_status[1u] != 0u
                    ? x86_func_param_reg_mask_status[1u]
                    : (x86_func_first_virtual_row_status[1u] != 0u
                        ? x86_func_first_virtual_row_status[1u]
                        : x86_virtual_value_def_status[1u]))));
        uint upstream_detail = !recorded_span_ok
            ? active_chunks
            : (x86_virtual_liveness_status[1u] != 0u
            ? x86_virtual_liveness_status[2u]
            : (x86_virtual_next_call_status[1u] != 0u
                ? x86_virtual_next_call_status[2u]
                : (x86_func_param_reg_mask_status[1u] != 0u
                    ? x86_func_param_reg_mask_status[2u]
                    : (x86_func_first_virtual_row_status[1u] != 0u
                        ? x86_func_first_virtual_row_status[2u]
                        : x86_virtual_value_def_status[2u]))));
        write_stage_status4_from_result(
            x86_virtual_regalloc_status,
            false,
            X86_VIRTUAL_REGALLOC_OK,
            INVALID,
            X86_ERR_VIRTUAL_REGALLOC,
            upstream_error,
            inst_count,
            upstream_detail,
            inst_count);
        return;
    }

    x86_virtual_regalloc_status[0u] = X86_VIRTUAL_REGALLOC_OK;
    x86_virtual_regalloc_status[3u] = inst_count;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint func_i = linear_dispatch_id(tid);
    uint inst_count = x86_virtual_liveness_status[3u];

    if (func_i == 0u && gRegalloc.init_status != 0u)
        initialize_status(inst_count);
    if (gRegalloc.chunk_start >= inst_count)
        return;

    uint func_count = min(x86_func_meta[FUNC_META_FUNC_COUNT], gParams.function_slot_capacity);
    if (func_i >= func_count)
        return;

    uint fn_slot = x86_func_slot_by_index[func_i];
    if (fn_slot >= gParams.n_tokens)
        return;

    if (!allocation_status_inputs_valid(inst_count))
        return;

    if (!allocate_function_row_offset(func_i, fn_slot, inst_count))
        publish_stage_error_min_detail4(
            x86_virtual_regalloc_status,
            X86_ERR_VIRTUAL_REGALLOC,
            fn_slot);
}
