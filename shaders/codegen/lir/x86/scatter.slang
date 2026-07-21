import codegen.lir.x86.common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint target_capacity; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<SemanticLirCore> semantic_lir_core;
StructuredBuffer<SemanticLirOperands> semantic_lir_operands;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> semantic_lir_call_arg_start_by_instruction;
StructuredBuffer<uint> semantic_lir_call_arg_count_by_instruction;
StructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
StructuredBuffer<uint> semantic_lir_aggregate_element_total;
StructuredBuffer<SemanticLirAggregateElement> semantic_lir_aggregate_elements;
StructuredBuffer<uint> target_lir_offset;
StructuredBuffer<uint> target_lir_total;
RWStructuredBuffer<uint> semantic_to_target_start;
RWStructuredBuffer<X86LirCore> target_lir_core;
RWStructuredBuffer<X86LirOperands> target_lir_operands;
RWStructuredBuffer<uint> target_semantic_origin;
RWStructuredBuffer<uint> target_lir_flags;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint scheduled_owner(uint target_row, uint semantic_count)
{
    uint lo = 0u;
    uint hi = semantic_count;
    while (lo + 1u < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (target_lir_offset[mid] <= target_row) lo = mid;
        else hi = mid;
    }
    return lo;
}

void write_call_arg(uint row, uint semantic_row, uint local_row,
                    SemanticLirCore source, uint argument_start)
{
    SemanticLirCallArg argument = semantic_lir_call_args[argument_start + local_row];
    X86LirCore core;
    core.source_hir = source.source_hir;
    core.local_ordinal = argument.ordinal;
    core.op = X86_LIR_OP_CALL_ARG;
    core.result_or_target = INVALID;
    X86LirOperands operands;
    operands.a = argument.value_instruction;
    operands.b = argument.ordinal;
    operands.c = 0u;
    // Carry the checked semantic value type through target resolution. The
    // emitter uses this target-IR fact to choose word- versus dword-sized ABI
    // moves without chasing the source expression's producer shape.
    uint argument_type = argument.value_instruction < gParams.semantic_capacity
        ? semantic_lir_core[argument.value_instruction].type_id : 0u;
    operands.metadata = (argument_type & 0xffu) |
        (argument_type >= 128u ? X86_LIR_METADATA_AGGREGATE : 0u);
    target_lir_core[row] = core;
    target_lir_operands[row] = operands;
    target_semantic_origin[row] = semantic_row;
    target_lir_flags[row] = argument.call_instruction == semantic_row &&
        argument.value_instruction < gParams.semantic_capacity && argument.ordinal < 6u
        ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint target_total = min(gParams.target_capacity, target_lir_total[0u]);
    if (row >= target_total) return;
    uint semantic_count = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    if (semantic_count == 0u) return;

    uint scheduled_row = scheduled_owner(row, semantic_count);
    uint semantic_row = semantic_schedule_order[scheduled_row];
    uint target_start = target_lir_offset[scheduled_row];
    SemanticLirCore source = semantic_lir_core[semantic_row];
    uint argument_count = semantic_lir_call_arg_count_by_instruction[semantic_row];
    // A call expands to argument-move rows followed by the value-producing
    // call row. Semantic operands name values, so their target projection must
    // point at the producer rather than the beginning of the expansion.
    semantic_to_target_start[semantic_row] = target_start + argument_count;
    uint local_row = row - target_start;
    if (local_row < argument_count)
    {
        write_call_arg(row, semantic_row, local_row, source,
            semantic_lir_call_arg_start_by_instruction[semantic_row]);
        return;
    }

    SemanticLirOperands args = semantic_lir_operands[semantic_row];
    uint operation_row = local_row - argument_count;
    if (source.op == SEMANTIC_LIR_OP_AGGREGATE_NEW && operation_row != 0u)
    {
        uint element_row = args.a + operation_row - 1u;
        SemanticLirAggregateElement element;
        element.aggregate_instruction = INVALID;
        element.value_instruction = INVALID;
        element.ordinal = INVALID;
        element.name_token = INVALID;
        uint element_total = semantic_lir_aggregate_element_total[0u];
        if (element_row < element_total)
            element = semantic_lir_aggregate_elements[element_row];
        X86LirCore core;
        core.source_hir = source.source_hir;
        core.local_ordinal = operation_row;
        core.op = X86_LIR_OP_ARRAY_INIT;
        core.result_or_target = row;
        X86LirOperands operands;
        operands.a = element.value_instruction;
        operands.b = element.ordinal;
        operands.c = target_start + 1u + element.ordinal;
        operands.metadata = source.type_id;
        target_lir_core[row] = core;
        target_lir_operands[row] = operands;
        target_semantic_origin[row] = semantic_row;
        target_lir_flags[row] = element.aggregate_instruction == semantic_row &&
            element.value_instruction < gParams.semantic_capacity &&
            element.ordinal < args.b ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
        return;
    }
    uint op = x86_lir_opcode(source);
    uint result = args.result;
    uint a = args.a;
    uint b = args.b;
    uint c = args.c;
    uint flags = x86_lir_supported(source) ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
    if (source.op == SEMANTIC_LIR_OP_CALL_HOST && (args.a == 28u || args.a == 29u)) flags = 0u;
    uint metadata = (source.type_id & 0xffu) | (source.flags << 8u) |
        (source.type_id >= 128u ? X86_LIR_METADATA_AGGREGATE : 0u);

    if (op == X86_LIR_OP_IMM_I32) { a = args.a; b = 0u; c = 0u; }
    else if (op == X86_LIR_OP_ARRAY_ADDR)
    {
        a = target_start + 1u;
        b = args.b;
        c = 0u;
    }
    else if (op == X86_LIR_OP_INDEX_LOAD)
    {
        a = args.a;
        b = args.b;
        c = 8u;
    }
    else if (op == X86_LIR_OP_FIELD_LOAD)
    {
        a = args.a;
        b = args.b;
        // x86 aggregates currently live in descending eight-byte frame value
        // slots. This concrete stride is deliberately target LIR metadata;
        // semantic LIR carries only the canonical field ordinal.
        c = 8u;
    }
    else if (op == X86_LIR_OP_BINARY) { c = args.b; b = args.a; a = x86_binary_payload(source); }
    else if (op == X86_LIR_OP_COMPARE) { c = args.b; b = args.a; a = source.flags; }
    else if (op == X86_LIR_OP_UNARY)
    {
        a = source.op == SEMANTIC_LIR_OP_LOGICAL_NOT ? X86_LIR_UNARY_NOT_BOOL
            : source.type_id == X86_LIR_TY_FLOAT ? X86_LIR_UNARY_NEG_F32
            : X86_LIR_UNARY_NEG_I32;
        b = args.a; c = 0u;
    }
    else if (op == X86_LIR_OP_RETURN)
    {
        result = INVALID; a = args.a; b = 0u; c = 0u;
        if (a == INVALID) op = X86_LIR_OP_RETURN_VOID;
    }
    else if (op == X86_LIR_OP_BRANCH)
    {
        result = INVALID;
        if (source.op == SEMANTIC_LIR_OP_IF_BEGIN) { a = args.a; b = args.b; c = args.c; }
        else if (source.op == SEMANTIC_LIR_OP_BRANCH_IF) { a = args.a; b = args.c; c = 0u; }
        else { a = INVALID; b = args.a; c = 0u; }
    }
    else if (op == X86_LIR_OP_LABEL)
    {
        result = INVALID; a = 0u; b = 0u; c = 0u;
    }
    else if ((op == X86_LIR_OP_CALL || op == X86_LIR_OP_CALL_HOST) && args.a == INVALID)
        flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    if (op == X86_LIR_OP_BRANCH && b == INVALID) flags |= TARGET_LIR_FLAG_UNSUPPORTED;

    X86LirCore core;
    core.source_hir = source.source_hir;
    core.local_ordinal = 0u;
    core.op = op;
    core.result_or_target = result;
    X86LirOperands operands;
    operands.a = a;
    operands.b = b;
    operands.c = c;
    operands.metadata = metadata;
    target_lir_core[row] = core;
    target_lir_operands[row] = operands;
    target_semantic_origin[row] = semantic_row;
    target_lir_flags[row] = flags;
}
