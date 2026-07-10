// x86_64 register allocation over virtual-instruction liveness intervals.
//
// Allocation is segmented by function: one GPU lane owns one function's
// contiguous virtual-instruction interval. This preserves the allocator's
// loop-carried active register state without multiplying every global value-def
// chunk by every function. Region/keyed state composition can further
// parallelize unusually large individual functions later.

import bitset;
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
StructuredBuffer<uint> x86_virtual_value_def_row;
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
static const uint X86_ERR_REGALLOC_BOUNDARY = 48u;
static const uint X86_VINST_PARAM = 2u;
static const uint X86_VINST_BINARY = 4u;
static const uint X86_VINST_CALL_MIXED = 20u;
static const uint X86_OP_SHL_I32 = 11u;
static const uint X86_OP_SHR_I32 = 12u;
static const uint FUNC_META_FUNC_COUNT = 0u;
static const uint FUNC_META_REGALLOC_ACTIVE_CHUNKS = 6u;
static const uint FUNC_META_REGALLOC_RECORDED_CHUNKS = 7u;
// Fixed local width for the current serial value-definition helper chunk. This
// is intentionally small and fail-closed; source scaling is carried by the
// recorded regalloc chunk count, not by this shader loop bound.
static const uint REGALLOC_LOCAL_CHUNK_WIDTH = 32u;
static const int X86_TEMP_REG_RANK_COUNT = 13;
static const uint X86_TEMP_REG_RANK_MASK = 0x1fffu;
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

uint call_live_mask_for_rank_mask(uint rank_mask)
{
    uint mask = 0u;
    if ((rank_mask & (1u << 0u)) != 0u) mask |= call_live_mask_for_rank(0u);
    if ((rank_mask & (1u << 1u)) != 0u) mask |= call_live_mask_for_rank(1u);
    if ((rank_mask & (1u << 2u)) != 0u) mask |= call_live_mask_for_rank(2u);
    if ((rank_mask & (1u << 3u)) != 0u) mask |= call_live_mask_for_rank(3u);
    if ((rank_mask & (1u << 4u)) != 0u) mask |= call_live_mask_for_rank(4u);
    if ((rank_mask & (1u << 5u)) != 0u) mask |= call_live_mask_for_rank(5u);
    if ((rank_mask & (1u << 6u)) != 0u) mask |= call_live_mask_for_rank(6u);
    if ((rank_mask & (1u << 7u)) != 0u) mask |= call_live_mask_for_rank(7u);
    if ((rank_mask & (1u << 8u)) != 0u) mask |= call_live_mask_for_rank(8u);
    if ((rank_mask & (1u << 9u)) != 0u) mask |= call_live_mask_for_rank(9u);
    if ((rank_mask & (1u << 10u)) != 0u) mask |= call_live_mask_for_rank(10u);
    if ((rank_mask & (1u << 11u)) != 0u) mask |= call_live_mask_for_rank(11u);
    if ((rank_mask & (1u << 12u)) != 0u) mask |= call_live_mask_for_rank(12u);
    if ((rank_mask & (1u << 13u)) != 0u) mask |= call_live_mask_for_rank(13u);
    return mask;
}

uint active_rank_available_bit(uint start, uint active_end[X86_TEMP_REG_RANK_COUNT], uint rank)
{
    uint end = active_end[rank];
    return (end == INVALID || end < start) ? (1u << rank) : 0u;
}

uint active_rank_call_live_bit(
    uint start,
    bool compute_call_live_mask,
    uint active_end[X86_TEMP_REG_RANK_COUNT],
    uint rank)
{
    uint end = active_end[rank];
    return compute_call_live_mask && end != INVALID && end > start
               ? call_live_mask_for_rank(rank)
               : 0u;
}

void active_rank_masks(
    uint start,
    bool compute_call_live_mask,
    uint active_end[X86_TEMP_REG_RANK_COUNT],
    out uint available_mask,
    out uint call_live_mask)
{
    uint available =
        active_rank_available_bit(start, active_end, 0u) |
        active_rank_available_bit(start, active_end, 1u) |
        active_rank_available_bit(start, active_end, 2u) |
        active_rank_available_bit(start, active_end, 3u) |
        active_rank_available_bit(start, active_end, 4u) |
        active_rank_available_bit(start, active_end, 5u) |
        active_rank_available_bit(start, active_end, 6u) |
        active_rank_available_bit(start, active_end, 7u) |
        active_rank_available_bit(start, active_end, 8u) |
        active_rank_available_bit(start, active_end, 9u) |
        active_rank_available_bit(start, active_end, 10u) |
        active_rank_available_bit(start, active_end, 11u) |
        active_rank_available_bit(start, active_end, 12u) |
        active_rank_available_bit(start, active_end, 13u);
    uint live_across_call =
        active_rank_call_live_bit(start, compute_call_live_mask, active_end, 0u) |
        active_rank_call_live_bit(start, compute_call_live_mask, active_end, 1u) |
        active_rank_call_live_bit(start, compute_call_live_mask, active_end, 2u) |
        active_rank_call_live_bit(start, compute_call_live_mask, active_end, 3u) |
        active_rank_call_live_bit(start, compute_call_live_mask, active_end, 4u) |
        active_rank_call_live_bit(start, compute_call_live_mask, active_end, 5u) |
        active_rank_call_live_bit(start, compute_call_live_mask, active_end, 6u) |
        active_rank_call_live_bit(start, compute_call_live_mask, active_end, 7u) |
        active_rank_call_live_bit(start, compute_call_live_mask, active_end, 8u) |
        active_rank_call_live_bit(start, compute_call_live_mask, active_end, 9u) |
        active_rank_call_live_bit(start, compute_call_live_mask, active_end, 10u) |
        active_rank_call_live_bit(start, compute_call_live_mask, active_end, 11u) |
        active_rank_call_live_bit(start, compute_call_live_mask, active_end, 12u) |
        active_rank_call_live_bit(start, compute_call_live_mask, active_end, 13u);
    available_mask = available & X86_TEMP_REG_RANK_MASK;
    call_live_mask = live_across_call;
}

uint first_rank_from_mask(uint mask)
{
    mask &= X86_TEMP_REG_RANK_MASK;
    return mask == 0u ? INVALID : uint(firstbitlow(mask));
}

bool regalloc_chunk_shape_valid()
{
    uint rows_per_chunk = gParams.regalloc_rows_per_chunk;
    if (rows_per_chunk == 0u ||
        rows_per_chunk > REGALLOC_LOCAL_CHUNK_WIDTH ||
        gParams.regalloc_chunk_count == 0u ||
        gRegalloc.chunk_len != rows_per_chunk)
        return false;

    return gRegalloc.chunk_start % rows_per_chunk == 0u &&
           gRegalloc.chunk_start / rows_per_chunk < gParams.regalloc_chunk_count;
}

bool recorded_chunk_span_covers_inst_capacity(out uint required_chunks)
{
    required_chunks = 1u;
    uint rows_per_chunk = gParams.regalloc_rows_per_chunk;
    if (rows_per_chunk == 0u)
        return false;

    uint capacity_rows = max(gParams.inst_capacity, 1u);
    required_chunks = ((capacity_rows - 1u) / rows_per_chunk) + 1u;
    return gParams.regalloc_chunk_count >= required_chunks &&
           x86_func_meta[FUNC_META_REGALLOC_RECORDED_CHUNKS] >= required_chunks;
}

uint required_regalloc_chunk_count(uint value_def_count)
{
    if (value_def_count == 0u)
        return 1u;

    uint rows_per_chunk = max(gParams.regalloc_rows_per_chunk, 1u);
    return ((value_def_count - 1u) / rows_per_chunk) + 1u;
}

bool function_slice_recorded()
{
    return x86_func_meta[FUNC_META_FUNC_COUNT] <= gParams.function_slot_capacity;
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

bool regalloc_recorded_span_valid(uint inst_count, out uint required_chunks)
{
    required_chunks = 1u;
    if (!regalloc_chunk_shape_valid() ||
        !function_slice_recorded() ||
        !allocation_status_inputs_valid(inst_count))
        return false;

    if (!recorded_chunk_span_covers_inst_capacity(required_chunks))
        return false;

    required_chunks = required_regalloc_chunk_count(x86_virtual_value_def_status[3u]);
    return x86_func_meta[FUNC_META_REGALLOC_RECORDED_CHUNKS] >= required_chunks &&
           x86_func_meta[FUNC_META_REGALLOC_ACTIVE_CHUNKS] >= required_chunks &&
           gParams.regalloc_chunk_count >= required_chunks;
}

uint recorded_regalloc_chunk_count()
{
    return min(
        min(
            x86_func_meta[FUNC_META_REGALLOC_RECORDED_CHUNKS],
            x86_func_meta[FUNC_META_REGALLOC_ACTIVE_CHUNKS]),
        gParams.regalloc_chunk_count);
}

bool valid_hir_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

uint regalloc_span_diagnostic_node(uint inst_count)
{
    uint rows_per_chunk = max(gParams.regalloc_rows_per_chunk, 1u);
    uint recorded_chunks = recorded_regalloc_chunk_count();
    if (recorded_chunks > 0xffffffffu / rows_per_chunk)
        return INVALID;

    uint first_missing_ordinal = recorded_chunks * rows_per_chunk;
    if (first_missing_ordinal >= x86_virtual_value_def_status[3u])
        return INVALID;

    uint row = x86_virtual_value_def_row[first_missing_ordinal];
    if (row >= inst_count || row >= gParams.inst_capacity)
        return INVALID;

    uint node = x86_virtual_inst_record[row].x;
    return valid_hir_node(node) ? node : INVALID;
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

bool valid_compact_value_def_row(uint value_def_i, uint row, uint inst_count, out uint failed_node)
{
    failed_node = INVALID;
    if (row >= inst_count)
        return false;

    uint4 inst = x86_virtual_inst_record[row];
    uint node = inst.x;
    if (!inst_has_value_def(inst, row))
    {
        failed_node = valid_hir_node(node) ? node : INVALID;
        return false;
    }

    if (value_def_i > 0u)
    {
        uint previous_row = x86_virtual_value_def_row[value_def_i - 1u];
        if (previous_row >= row)
        {
            failed_node = valid_hir_node(node) ? node : INVALID;
            return false;
        }
        uint4 previous_inst = x86_virtual_inst_record[previous_row];
        uint previous_node = previous_inst.x;
        if (!inst_has_value_def(previous_inst, previous_row))
        {
            failed_node = valid_hir_node(previous_node)
                ? previous_node
                : (valid_hir_node(node) ? node : INVALID);
            return false;
        }
    }

    return true;
}

uint active_end_slot(uint func_i, uint rank)
{
    return func_i * uint(X86_TEMP_REG_RANK_COUNT) + rank;
}

uint load_active_end_rank(uint func_i, uint rank)
{
    return gRegalloc.chunk_start == 0u
        ? INVALID
        : x86_virtual_regalloc_active_end[active_end_slot(func_i, rank)];
}

void load_active_end(uint func_i, inout uint active_end[X86_TEMP_REG_RANK_COUNT])
{
    active_end[0u] = load_active_end_rank(func_i, 0u);
    active_end[1u] = load_active_end_rank(func_i, 1u);
    active_end[2u] = load_active_end_rank(func_i, 2u);
    active_end[3u] = load_active_end_rank(func_i, 3u);
    active_end[4u] = load_active_end_rank(func_i, 4u);
    active_end[5u] = load_active_end_rank(func_i, 5u);
    active_end[6u] = load_active_end_rank(func_i, 6u);
    active_end[7u] = load_active_end_rank(func_i, 7u);
    active_end[8u] = load_active_end_rank(func_i, 8u);
    active_end[9u] = load_active_end_rank(func_i, 9u);
    active_end[10u] = load_active_end_rank(func_i, 10u);
    active_end[11u] = load_active_end_rank(func_i, 11u);
    active_end[12u] = load_active_end_rank(func_i, 12u);
}

void store_active_end(uint func_i, uint active_end[X86_TEMP_REG_RANK_COUNT])
{
    x86_virtual_regalloc_active_end[active_end_slot(func_i, 0u)] = active_end[0u];
    x86_virtual_regalloc_active_end[active_end_slot(func_i, 1u)] = active_end[1u];
    x86_virtual_regalloc_active_end[active_end_slot(func_i, 2u)] = active_end[2u];
    x86_virtual_regalloc_active_end[active_end_slot(func_i, 3u)] = active_end[3u];
    x86_virtual_regalloc_active_end[active_end_slot(func_i, 4u)] = active_end[4u];
    x86_virtual_regalloc_active_end[active_end_slot(func_i, 5u)] = active_end[5u];
    x86_virtual_regalloc_active_end[active_end_slot(func_i, 6u)] = active_end[6u];
    x86_virtual_regalloc_active_end[active_end_slot(func_i, 7u)] = active_end[7u];
    x86_virtual_regalloc_active_end[active_end_slot(func_i, 8u)] = active_end[8u];
    x86_virtual_regalloc_active_end[active_end_slot(func_i, 9u)] = active_end[9u];
    x86_virtual_regalloc_active_end[active_end_slot(func_i, 10u)] = active_end[10u];
    x86_virtual_regalloc_active_end[active_end_slot(func_i, 11u)] = active_end[11u];
    x86_virtual_regalloc_active_end[active_end_slot(func_i, 12u)] = active_end[12u];
}

uint load_param_rank_mask(uint func_i, uint fn_slot)
{
    uint mask = gRegalloc.chunk_start == 0u
        ? param_disallowed_rank_mask(x86_func_param_reg_mask[fn_slot])
        : x86_virtual_regalloc_param_rank_mask[func_i];
    return mask | rank_mask_for_register(X86_REG_EDI);
}

void activate_rank(uint selected_rank, uint end, inout uint active_end[X86_TEMP_REG_RANK_COUNT])
{
    if (selected_rank == 0u) active_end[0u] = end;
    if (selected_rank == 1u) active_end[1u] = end;
    if (selected_rank == 2u) active_end[2u] = end;
    if (selected_rank == 3u) active_end[3u] = end;
    if (selected_rank == 4u) active_end[4u] = end;
    if (selected_rank == 5u) active_end[5u] = end;
    if (selected_rank == 6u) active_end[6u] = end;
    if (selected_rank == 7u) active_end[7u] = end;
    if (selected_rank == 8u) active_end[8u] = end;
    if (selected_rank == 9u) active_end[9u] = end;
    if (selected_rank == 10u) active_end[10u] = end;
    if (selected_rank == 11u) active_end[11u] = end;
    if (selected_rank == 12u) active_end[12u] = end;
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
            x86_virtual_call_live_reg_mask[row] = call_live_mask | call_live_mask_for_rank_mask(current_param_rank_mask);

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
        activate_rank(selected_rank, end, active_end);
        if (inst_is_param_copy(inst))
            current_param_rank_mask &= ~rank_mask_for_register(x86_virtual_inst_args[row].z);
    }
    return true;
}

bool allocate_function_row_offset(uint func_i, uint fn_slot, uint inst_count, out uint failed_node)
{
    failed_node = INVALID;
    uint start_row = INVALID;
    uint end_row = INVALID;
    if (!function_row_bounds(fn_slot, inst_count, start_row, end_row))
        return true;
    if (end_row == INVALID)
        return false;

    uint value_def_count = x86_virtual_value_def_status[3u];
    uint chunk_start = gRegalloc.chunk_start;
    if (chunk_start >= value_def_count)
        return true;

    uint active_end[X86_TEMP_REG_RANK_COUNT];
    load_active_end(func_i, active_end);
    // Scalar parameter rows copy incoming ABI registers into frame slots at
    // function entry, before the rest of the function has live temporaries.
    // After that copy, those ABI registers are ordinary allocatable temps.
    uint current_param_rank_mask = load_param_rank_mask(func_i, fn_slot);
    uint chunk_len = min(gRegalloc.chunk_len, REGALLOC_LOCAL_CHUNK_WIDTH);
    uint chunk_end = chunk_start + chunk_len;
    if (chunk_end < chunk_start)
        chunk_end = value_def_count;

    // Loop-carried active_end/current_param_rank_mask make this the exact
    // blocker for a map/scan/scatter allocator. Splitting these rows into
    // parallel threads without a new state-composition relation would race and
    // produce non-deterministic register choices.
    for (uint local_i = 0u; local_i < REGALLOC_LOCAL_CHUNK_WIDTH; local_i += 1u)
    {
        if (local_i < chunk_len)
        {
            uint value_def_i = chunk_start + local_i;
            if (value_def_i >= chunk_start && value_def_i < value_def_count)
            {
                uint row = x86_virtual_value_def_row[value_def_i];
                uint compact_failed_node = INVALID;
                if (!valid_compact_value_def_row(
                        value_def_i,
                        row,
                        inst_count,
                        compact_failed_node))
                {
                    failed_node = compact_failed_node;
                    return false;
                }
                if (row >= start_row && row < end_row)
                {
                    if (!allocate_virtual_row(row, fn_slot, active_end, current_param_rank_mask))
                    {
                        uint node = x86_virtual_inst_record[row].x;
                        failed_node = valid_hir_node(node) ? node : INVALID;
                        return false;
                    }
                }
            }
        }
    }

    if (chunk_end < value_def_count)
    {
        store_active_end(func_i, active_end);
        x86_virtual_regalloc_param_rank_mask[func_i] = current_param_rank_mask;
    }
    return true;
}

bool allocate_function_interval(uint func_i, uint fn_slot, uint inst_count, out uint failed_node)
{
    failed_node = INVALID;
    uint start_row = INVALID;
    uint end_row = INVALID;
    if (!function_row_bounds(fn_slot, inst_count, start_row, end_row))
        return true;
    if (end_row == INVALID)
        return false;

    uint active_end[X86_TEMP_REG_RANK_COUNT];
    active_end[0u] = INVALID;
    active_end[1u] = INVALID;
    active_end[2u] = INVALID;
    active_end[3u] = INVALID;
    active_end[4u] = INVALID;
    active_end[5u] = INVALID;
    active_end[6u] = INVALID;
    active_end[7u] = INVALID;
    active_end[8u] = INVALID;
    active_end[9u] = INVALID;
    active_end[10u] = INVALID;
    active_end[11u] = INVALID;
    active_end[12u] = INVALID;
    uint current_param_rank_mask = load_param_rank_mask(func_i, fn_slot);

    for (uint row = start_row; row < end_row; row += 1u)
    {
        if (!allocate_virtual_row(row, fn_slot, active_end, current_param_rank_mask))
        {
            uint node = x86_virtual_inst_record[row].x;
            failed_node = valid_hir_node(node) ? node : INVALID;
            return false;
        }
    }
    return true;
}

uint first_allocation_upstream_error()
{
    if (x86_virtual_liveness_status[1u] != 0u)
        return x86_virtual_liveness_status[1u];
    if (x86_virtual_next_call_status[1u] != 0u)
        return x86_virtual_next_call_status[1u];
    if (x86_func_param_reg_mask_status[1u] != 0u)
        return x86_func_param_reg_mask_status[1u];
    if (x86_func_first_virtual_row_status[1u] != 0u)
        return x86_func_first_virtual_row_status[1u];
    return x86_virtual_value_def_status[1u];
}

uint first_allocation_upstream_detail()
{
    if (x86_virtual_liveness_status[1u] != 0u)
        return x86_virtual_liveness_status[2u];
    if (x86_virtual_next_call_status[1u] != 0u)
        return x86_virtual_next_call_status[2u];
    if (x86_func_param_reg_mask_status[1u] != 0u)
        return x86_func_param_reg_mask_status[2u];
    if (x86_func_first_virtual_row_status[1u] != 0u)
        return x86_func_first_virtual_row_status[2u];
    return x86_virtual_value_def_status[2u];
}

void initialize_status(uint inst_count)
{
    bool function_slice_ok = function_slice_recorded();
    bool inputs_ok = function_slice_ok && allocation_status_inputs_valid(inst_count);
    bool dispatch_shape_ok = gParams.regalloc_chunk_count == 2u;
    bool ok = inputs_ok && dispatch_shape_ok;
    if (!ok)
    {
        uint upstream_error = (!function_slice_ok || !dispatch_shape_ok)
            ? X86_ERR_VIRTUAL_REGALLOC
            : first_allocation_upstream_error();
        uint upstream_detail = !dispatch_shape_ok
            ? gParams.regalloc_chunk_count
            : (!function_slice_ok
                ? x86_func_meta[FUNC_META_FUNC_COUNT]
                : first_allocation_upstream_detail());
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

    if (gRegalloc.init_status != 0u)
    {
        if (func_i == 0u)
            initialize_status(inst_count);
        return;
    }
    if (x86_virtual_regalloc_status[0u] != X86_VIRTUAL_REGALLOC_OK ||
        x86_virtual_regalloc_status[1u] != 0u)
        return;

    uint func_count = min(x86_func_meta[FUNC_META_FUNC_COUNT], gParams.function_slot_capacity);
    if (func_i >= func_count)
        return;

    uint fn_slot = x86_func_slot_by_index[func_i];
    if (fn_slot >= gParams.function_slot_capacity)
    {
        publish_stage_error_min_detail4(
            x86_virtual_regalloc_status,
            X86_ERR_VIRTUAL_REGALLOC,
            func_i);
        return;
    }

    uint failed_node = INVALID;
    if (!allocate_function_interval(func_i, fn_slot, inst_count, failed_node))
    {
        uint error = valid_hir_node(failed_node)
            ? X86_ERR_REGALLOC_BOUNDARY
            : X86_ERR_VIRTUAL_REGALLOC;
        uint detail = valid_hir_node(failed_node) ? failed_node : fn_slot;
        publish_stage_error_min_detail4(
            x86_virtual_regalloc_status,
            error,
            detail);
    }
}
