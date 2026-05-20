// x86_64 register allocation over virtual-instruction liveness intervals.

import bitset;
import gpu_index;
import intervals;
import linear_scan;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

struct RegallocParams
{
    uint chunk_start;
    uint chunk_len;
    uint init_status;
    uint reserved;
};

ConstantBuffer<Params> gParams;
ConstantBuffer<RegallocParams> gRegalloc;

StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> x86_decl_node_by_token;
StructuredBuffer<uint> x86_func_meta;
StructuredBuffer<uint> x86_func_slot_by_index;
StructuredBuffer<uint4> x86_virtual_inst_record;
StructuredBuffer<uint4> x86_virtual_inst_args;
StructuredBuffer<uint> x86_node_func;
StructuredBuffer<uint> x86_virtual_live_start;
StructuredBuffer<uint> x86_virtual_live_end;
StructuredBuffer<uint> x86_virtual_liveness_status;
StructuredBuffer<uint> x86_virtual_next_call_a;
StructuredBuffer<uint> x86_virtual_next_call_b;
StructuredBuffer<uint> x86_virtual_next_call_status;
StructuredBuffer<uint> x86_func_param_reg_mask;
StructuredBuffer<uint> x86_func_param_reg_mask_status;
StructuredBuffer<uint> x86_func_first_virtual_row;
StructuredBuffer<uint> x86_func_last_virtual_row;
StructuredBuffer<uint> x86_func_first_virtual_row_status;

RWStructuredBuffer<uint> x86_virtual_regalloc_active_end;
RWStructuredBuffer<uint> x86_virtual_phys_reg;
RWStructuredBuffer<uint> x86_virtual_regalloc_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_VIRTUAL_LIVENESS_OK = 1u;
static const uint X86_VIRTUAL_NEXT_CALLS_OK = 1u;
static const uint X86_FUNC_PARAM_REG_MASK_OK = 1u;
static const uint X86_FUNC_FIRST_VIRTUAL_ROW_OK = 1u;
static const uint X86_VIRTUAL_REGALLOC_OK = 1u;
static const uint X86_ERR_VIRTUAL_REGALLOC = 15u;
static const uint X86_VINST_BINARY = 4u;
static const uint X86_VINST_CALL_MIXED = 20u;
static const uint X86_OP_SHL_I32 = 11u;
static const uint X86_OP_SHR_I32 = 12u;
static const uint FUNC_META_FUNC_COUNT = 0u;
static const uint HIR_FN = 3u;
static const int X86_TEMP_REG_RANK_COUNT = 14;

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

bool inst_belongs_to_function(uint4 inst, uint fn_node)
{
    return inst.x != INVALID &&
           inst.x < gParams.n_hir_nodes &&
           x86_node_func[inst.x] == fn_node;
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

bool row_belongs_to_function(uint row, uint fn_node, uint inst_count)
{
    if (row >= inst_count)
        return false;
    uint node = x86_virtual_inst_record[row].x;
    return node != INVALID && node < gParams.n_hir_nodes && x86_node_func[node] == fn_node;
}

bool reg_mask_contains(uint mask, uint reg)
{
    return bitset32_contains(mask, reg);
}

uint ceil_log2_u32(uint value)
{
    if (value <= 1u)
        return 0u;
    uint x = value - 1u;
    uint result = 0u;
    if (x >= 0x10000u)
    {
        x >>= 16u;
        result += 16u;
    }
    if (x >= 0x100u)
    {
        x >>= 8u;
        result += 8u;
    }
    if (x >= 0x10u)
    {
        x >>= 4u;
        result += 4u;
    }
    if (x >= 0x4u)
    {
        x >>= 2u;
        result += 2u;
    }
    if (x >= 0x2u)
        result += 1u;
    return result + 1u;
}

bool final_next_call_buffer_is_a(uint inst_count)
{
    return (ceil_log2_u32(inst_count) & 1u) == 0u;
}

uint virtual_next_call_row(uint row, uint inst_count)
{
    if (row >= inst_count)
        return INVALID;
    return final_next_call_buffer_is_a(inst_count)
               ? x86_virtual_next_call_a[row]
               : x86_virtual_next_call_b[row];
}

uint next_call_after_row(uint row, uint fn_node, uint inst_count)
{
    if (row >= inst_count)
        return INVALID;
    uint next_call = virtual_next_call_row(row, inst_count);
    if (next_call == row)
    {
        uint right_row = row + 1u;
        next_call = right_row < inst_count && row_belongs_to_function(right_row, fn_node, inst_count)
            ? virtual_next_call_row(right_row, inst_count)
            : INVALID;
    }
    return row_belongs_to_function(next_call, fn_node, inst_count) ? next_call : INVALID;
}

bool interval_spans_precomputed_call(
    uint row,
    uint fn_node,
    uint inst_count,
    uint start,
    uint end)
{
    uint next_call = next_call_after_row(row, fn_node, inst_count);
    return next_call != INVALID &&
           interval_u32_strictly_contains_point(
               interval_u32(start, end),
               next_call,
               INVALID);
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
           inst_count <= gParams.inst_capacity;
}

bool inst_is_call_result(uint4 inst)
{
    return inst.z == X86_VINST_CALL_MIXED;
}

bool inst_is_shift_result(uint row, uint4 inst)
{
    if (inst.z != X86_VINST_BINARY)
        return false;
    uint op = x86_virtual_inst_args[row].x;
    return op == X86_OP_SHL_I32 || op == X86_OP_SHR_I32;
}

uint disallowed_rank_mask(uint register_mask, bool spans_fixed_barrier, bool call_result, bool shift_result)
{
    uint mask = 0u;
    [unroll]
    for (uint rank = 0u; rank < uint(X86_TEMP_REG_RANK_COUNT); rank += 1u)
    {
        uint candidate = temp_register_for_rank(rank);
        if (candidate == INVALID ||
            (candidate == X86_REG_EAX && (spans_fixed_barrier || call_result)) ||
            (candidate == X86_REG_ECX && (spans_fixed_barrier || shift_result)) ||
            (candidate == X86_REG_EDX && spans_fixed_barrier) ||
            ((candidate == X86_REG_EBX ||
              candidate == X86_REG_R12D ||
              candidate == X86_REG_R13D ||
              candidate == X86_REG_R14D ||
              candidate == X86_REG_R15D) && spans_fixed_barrier) ||
            reg_mask_contains(register_mask, candidate))
            mask = bitset32_insert(mask, rank);
    }
    return mask;
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

uint active_end_slot(uint fn_slot, uint rank)
{
    return fn_slot * uint(X86_TEMP_REG_RANK_COUNT) + rank;
}

void load_active_end(uint fn_slot, inout uint active_end[X86_TEMP_REG_RANK_COUNT])
{
    [unroll]
    for (uint rank = 0u; rank < uint(X86_TEMP_REG_RANK_COUNT); rank += 1u)
    {
        active_end[rank] = gRegalloc.chunk_start == 0u
            ? INVALID
            : x86_virtual_regalloc_active_end[active_end_slot(fn_slot, rank)];
    }
}

void store_active_end(uint fn_slot, uint active_end[X86_TEMP_REG_RANK_COUNT])
{
    [unroll]
    for (uint rank = 0u; rank < uint(X86_TEMP_REG_RANK_COUNT); rank += 1u)
        x86_virtual_regalloc_active_end[active_end_slot(fn_slot, rank)] = active_end[rank];
}

bool allocate_function_rows(uint fn_slot, uint fn_node, uint inst_count)
{
    if (!allocation_status_inputs_valid(inst_count))
        return false;

    if (fn_slot >= gParams.n_tokens || fn_node >= gParams.n_hir_nodes || hir_kind[fn_node] != HIR_FN)
        return false;
    uint start_row = INVALID;
    uint end_row = INVALID;
    if (!function_row_bounds(fn_slot, inst_count, start_row, end_row))
        return true;
    if (end_row == INVALID)
        return false;

    uint active_end[X86_TEMP_REG_RANK_COUNT];
    load_active_end(fn_slot, active_end);
    // Scalar parameter rows copy incoming ABI registers into frame slots at
    // function entry, before the rest of the function has live temporaries.
    // After that copy, those ABI registers are ordinary allocatable temps.
    uint current_param_mask = 0u;
    uint chunk_begin = start_row + gRegalloc.chunk_start;
    uint chunk_end = min(end_row, chunk_begin + max(gRegalloc.chunk_len, 1u));
    if (chunk_begin >= end_row || chunk_begin < start_row)
    {
        store_active_end(fn_slot, active_end);
        return true;
    }

    [loop]
    for (uint row = chunk_begin; row < chunk_end && row < inst_count; row += 1u)
    {
        uint4 inst = x86_virtual_inst_record[row];
        if (!inst_belongs_to_function(inst, fn_node))
            continue;
        if (!inst_has_value_def(inst, row))
            continue;

        uint start = x86_virtual_live_start[row];
        uint end = x86_virtual_live_end[row];
        if (!interval_u32_valid(interval_u32(start, end), INVALID))
            return false;

        bool spans_fixed_barrier = interval_spans_precomputed_call(row, fn_node, inst_count, start, end);
        uint selected_rank = linear_scan_first_available_rank<X86_TEMP_REG_RANK_COUNT>(
            start,
            disallowed_rank_mask(
                current_param_mask,
                spans_fixed_barrier,
                inst_is_call_result(inst),
                inst_is_shift_result(row, inst)),
            active_end,
            INVALID);
        uint selected_reg = temp_register_for_rank(selected_rank);

        if (selected_reg == INVALID)
            return false;
        x86_virtual_phys_reg[row] = selected_reg;
        linear_scan_activate_rank<X86_TEMP_REG_RANK_COUNT>(
            selected_rank,
            end,
            active_end);
    }
    store_active_end(fn_slot, active_end);
    return true;
}

void initialize_status(uint inst_count)
{
    bool ok = allocation_status_inputs_valid(inst_count);
    if (!ok)
    {
        uint upstream_error = x86_virtual_liveness_status[1u] != 0u
            ? x86_virtual_liveness_status[1u]
            : (x86_virtual_next_call_status[1u] != 0u
                ? x86_virtual_next_call_status[1u]
                : (x86_func_param_reg_mask_status[1u] != 0u
                    ? x86_func_param_reg_mask_status[1u]
                    : x86_func_first_virtual_row_status[1u]));
        uint upstream_detail = x86_virtual_liveness_status[1u] != 0u
            ? x86_virtual_liveness_status[2u]
            : (x86_virtual_next_call_status[1u] != 0u
                ? x86_virtual_next_call_status[2u]
                : (x86_func_param_reg_mask_status[1u] != 0u
                    ? x86_func_param_reg_mask_status[2u]
                    : x86_func_first_virtual_row_status[2u]));
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
    x86_virtual_regalloc_status[2u] = INVALID;
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

    uint func_count = min(x86_func_meta[FUNC_META_FUNC_COUNT], gParams.n_tokens);
    if (func_i >= func_count)
        return;

    uint fn_slot = x86_func_slot_by_index[func_i];
    if (fn_slot >= gParams.n_tokens)
        return;

    uint fn_node = x86_decl_node_by_token[fn_slot];
    if (fn_node >= gParams.n_hir_nodes || hir_kind[fn_node] != HIR_FN)
        return;
    if (!allocation_status_inputs_valid(inst_count))
        return;

    if (!allocate_function_rows(fn_slot, fn_node, inst_count))
        publish_stage_error_min_detail4(
            x86_virtual_regalloc_status,
            X86_ERR_VIRTUAL_REGALLOC,
            fn_node);
}
