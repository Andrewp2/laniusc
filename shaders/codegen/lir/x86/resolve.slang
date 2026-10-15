import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint target_capacity; uint target_start; uint page_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
RWStructuredBuffer<X86LirCore> target_lir_core;
RWStructuredBuffer<X86LirOperands> target_lir_operands;
StructuredBuffer<uint> target_semantic_origin;
StructuredBuffer<uint> target_lir_flags;
StructuredBuffer<uint> semantic_to_target_start;
StructuredBuffer<X86ValueAnalysis> x86_value_by_semantic;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<uint> x86_position_by_semantic;
StructuredBuffer<uint> target_lir_offset;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint target_value(uint semantic_row, uint total)
{
    if (semantic_row < gParams.semantic_capacity)
    {
        uint replacement = x86_value_by_semantic[semantic_row].replacement;
        if (replacement < gParams.semantic_capacity)
            semantic_row = replacement;
    }
    uint target_row = semantic_row < gParams.semantic_capacity
        ? semantic_to_target_start[semantic_row] : INVALID;
    return target_row < total ? target_row : INVALID;
}

// A branch names its destination by a control row of the semantic schedule.
// `after` selects the first target row after that control row's own
// instructions: an IF_BEGIN's false edge skips the ELSE row's jump to the
// join. A control row in an unreachable block emits no instruction (the
// ELSE after a then-arm that returns), so scatter never publishes its start.
// The schedule offsets place it anyway: its instructions begin at its own
// offset and end at the next position's offset. Inline clones sit at the
// call site, one instruction per row, and scatter publishes each clone's row.
uint branch_target(uint semantic_row, uint after, bool inline_clone, uint total)
{
    if (inline_clone)
    {
        uint start = target_value(semantic_row, total);
        return start < total && after < total - start ? start + after : INVALID;
    }
    uint semantic_count = min(gParams.semantic_capacity, opt_ir_total[0u]);
    uint position = semantic_row < semantic_count
        ? x86_position_by_semantic[semantic_row] : INVALID;
    if (position >= semantic_count) return INVALID;
    uint target_row = after == 0u ? target_lir_offset[position]
        : position + 1u < semantic_count ? target_lir_offset[position + 1u]
        : total;
    return target_row < total ? target_row : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (page_row >= gParams.page_capacity) return;
    uint row = gParams.target_start + page_row;
    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    if (row >= total) return;

    X86LirCore core = target_lir_core[page_row];
    X86LirOperands operands = target_lir_operands[page_row];
    bool inline_clone =
        (target_lir_flags[page_row] & TARGET_LIR_FLAG_INLINE_CLONE) != 0u;
    if (core.result_or_target != INVALID &&
        core.op != X86_LIR_OP_COMPARE_BRANCH_FALSE &&
        core.op != X86_LIR_OP_SELECT_STORE &&
        (operands.metadata & X86_LIR_METADATA_INDEX_AGGREGATE_COPY) == 0u)
        core.result_or_target = row;
    if (core.op == X86_LIR_OP_BINARY || core.op == X86_LIR_OP_COMPARE)
    {
        operands.b = target_value(operands.b, total);
        if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) == 0u &&
            (core.op != X86_LIR_OP_BINARY ||
             (operands.a != X86_LIR_BINARY_DIV_CONST_POW2_I32 &&
              operands.a != X86_LIR_BINARY_REM_CONST_POW2_I32 &&
              operands.a != X86_LIR_BINARY_DIV_CONST_I32 &&
              operands.a != X86_LIR_BINARY_REM_CONST_I32)))
            operands.c = target_value(operands.c, total);
    }
    else if (core.op == X86_LIR_OP_UNARY)
        operands.b = target_value(operands.b, total);
    else if (core.op == X86_LIR_OP_RETURN)
        operands.a = target_value(operands.a, total);
    else if (core.op == X86_LIR_OP_INLINE_RESULT)
        operands.a = target_value(operands.a, total);
    else if (core.op == X86_LIR_OP_AGGREGATE_RETURN_WORD)
        operands.a = target_value(operands.a, total);
    else if (core.op == X86_LIR_OP_AGGREGATE_COPY_WORD)
        operands.a = target_value(operands.a, total);
    else if (core.op == X86_LIR_OP_CALL_ARG)
    {
        if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) == 0u)
        {
            uint base = target_value(operands.a, total);
            if ((operands.metadata & X86_LIR_METADATA_INDIRECT_ARRAY_PAIR) != 0u)
            {
                // Both components read the same descriptor address. The
                // emitter uses c to select its pointer or length word.
                operands.a = base;
            }
            else
            {
                uint component = operands.c;
                operands.a = base < total && component < total - base
                    ? base + component : INVALID;
                operands.c = 0u;
            }
        }
        // Immediate array stride retains its component tag for sign extension.
    }
    else if (core.op == X86_LIR_OP_PLACE_STORE)
    {
        operands.a = target_value(operands.a, total);
        operands.b = target_value(operands.b, total);
    }
    else if (core.op == X86_LIR_OP_PLACE_LOAD || core.op == X86_LIR_OP_FIELD_ADDRESS)
        operands.a = target_value(operands.a, total);
    else if (core.op == X86_LIR_OP_STORE_LOCAL)
        operands.b = target_value(operands.b, total);
    else if (core.op == X86_LIR_OP_AGGREGATE_INIT &&
             (operands.metadata & X86_LIR_METADATA_IMMEDIATE) == 0u)
        operands.a = target_value(operands.a, total);
    else if (core.op == X86_LIR_OP_INDEX_LOAD || core.op == X86_LIR_OP_INDEX_ADDRESS)
    {
        operands.a = target_value(operands.a, total);
        operands.b = target_value(operands.b, total);
    }
    else if (core.op == X86_LIR_OP_FIELD_LOAD)
        operands.a = target_value(operands.a, total);
    else if (core.op == X86_LIR_OP_INDEX_STORE)
    {
        operands.a = target_value(operands.a, total);
        operands.b = target_value(operands.b, total);
        operands.c = target_value(operands.c, total);
    }
    else if (core.op == X86_LIR_OP_FIELD_STORE)
    {
        operands.a = target_value(operands.a, total);
        operands.c = target_value(operands.c, total);
    }
    else if (core.op == X86_LIR_OP_COMPARE_BRANCH_FALSE)
    {
        operands.a = target_value(operands.a, total);
        if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) == 0u)
            operands.b = target_value(operands.b, total);
        core.result_or_target = branch_target(core.result_or_target,
            operands.c, inline_clone, total);
        operands.c = 0u;
    }
    else if (core.op == X86_LIR_OP_SELECT_STORE)
    {
        operands.a = target_value(operands.a, total);
        if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) == 0u)
            operands.b = target_value(operands.b, total);
        operands.c = target_value(operands.c, total);
    }
    if (core.op == X86_LIR_OP_BRANCH)
    {
        operands.a = target_value(operands.a, total);
        operands.b = branch_target(operands.b, operands.c, inline_clone, total);
        operands.c = 0u;
    }

    target_lir_core[page_row] = core;
    target_lir_operands[page_row] = operands;
}
