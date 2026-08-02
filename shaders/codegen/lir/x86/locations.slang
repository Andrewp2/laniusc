import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint target_capacity; uint target_start; uint page_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<X86LirCore> target_lir_core;
StructuredBuffer<X86LirOperands> target_lir_operands;
StructuredBuffer<uint> target_semantic_origin;
StructuredBuffer<uint> semantic_to_target_start;
StructuredBuffer<uint> x86_location_by_semantic;
RWStructuredBuffer<X86LirLocations> target_lir_locations;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint stack_location(uint target_row)
{
    return target_row < X86_LOCATION_PAYLOAD_MASK ? target_row : X86_LOCATION_INVALID;
}

uint value_location(uint semantic_row, uint total)
{
    if (semantic_row >= gParams.semantic_capacity) return X86_LOCATION_INVALID;
    uint allocated = x86_location_by_semantic[semantic_row];
    if ((allocated & X86_LOCATION_REGISTER) != 0u && allocated != X86_LOCATION_INVALID)
        return allocated;
    uint target_row = semantic_to_target_start[semantic_row];
    return target_row < total ? stack_location(target_row) : X86_LOCATION_INVALID;
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
    uint semantic_row = target_semantic_origin[page_row];

    X86LirLocations locations;
    locations.result = core.result_or_target == INVALID
        ? X86_LOCATION_INVALID : stack_location(row);
    locations.a = X86_LOCATION_INVALID;
    locations.b = X86_LOCATION_INVALID;
    locations.c = X86_LOCATION_INVALID;
    if (semantic_row < gParams.semantic_capacity &&
        core.result_or_target != INVALID &&
        semantic_to_target_start[semantic_row] == row)
    {
        uint allocated = x86_location_by_semantic[semantic_row];
        if ((allocated & X86_LOCATION_REGISTER) != 0u &&
            allocated != X86_LOCATION_INVALID)
            locations.result = allocated;
    }

    if (core.op == X86_LIR_OP_STORE_LOCAL)
        locations.b = value_location(operands.b, total);
    else if (core.op == X86_LIR_OP_BINARY || core.op == X86_LIR_OP_COMPARE)
    {
        locations.b = value_location(operands.b, total);
        locations.c = value_location(operands.c, total);
    }
    else if (core.op == X86_LIR_OP_UNARY)
        locations.b = value_location(operands.b, total);
    else if (core.op == X86_LIR_OP_RETURN)
        locations.a = value_location(operands.a, total);
    else if (core.op == X86_LIR_OP_AGGREGATE_RETURN_WORD)
        locations.a = value_location(operands.a, total);
    else if (core.op == X86_LIR_OP_CALL_ARG)
        locations.a = value_location(operands.a, total);
    else if (core.op == X86_LIR_OP_ARRAY_INIT)
    {
        locations.a = value_location(operands.a, total);
        locations.c = stack_location(operands.c);
    }
    else if (core.op == X86_LIR_OP_INDEX_LOAD)
    {
        locations.a = value_location(operands.a, total);
        locations.b = value_location(operands.b, total);
    }
    else if (core.op == X86_LIR_OP_FIELD_LOAD)
        locations.a = value_location(operands.a, total);
    else if (core.op == X86_LIR_OP_INDEX_STORE)
    {
        locations.a = value_location(operands.a, total);
        locations.b = value_location(operands.b, total);
        locations.c = value_location(operands.c, total);
    }
    else if (core.op == X86_LIR_OP_FIELD_STORE)
    {
        locations.a = value_location(operands.a, total);
        locations.c = value_location(operands.c, total);
    }
    else if (core.op == X86_LIR_OP_BRANCH && operands.a != INVALID)
        locations.a = value_location(operands.a, total);

    target_lir_locations[page_row] = locations;
}
