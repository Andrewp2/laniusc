import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.x86.location_common;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint target_capacity;
    uint target_start;
    uint page_capacity;
    uint token_capacity;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<X86LirCore> target_lir_core;
StructuredBuffer<X86LirOperands> target_lir_operands;
StructuredBuffer<uint> target_semantic_origin;
StructuredBuffer<uint> target_lir_flags;
StructuredBuffer<uint> semantic_to_target_start;
StructuredBuffer<uint> x86_location_by_semantic;
StructuredBuffer<uint> x86_live_by_semantic;
StructuredBuffer<X86ValueAnalysis> x86_value_by_semantic;
StructuredBuffer<X86DeclarationAnalysis> x86_decl_analysis_by_token;
StructuredBuffer<uint> x86_decl_location_by_token;
StructuredBuffer<X86SelectInfo> x86_select_by_semantic;
RWStructuredBuffer<X86LirLocations> target_lir_locations;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint stack_location(uint slot)
{
    return slot < X86_LOCATION_PAYLOAD_MASK ? slot : X86_LOCATION_INVALID;
}

uint value_location(uint semantic_row)
{
    if (semantic_row >= gParams.semantic_capacity) return X86_LOCATION_INVALID;
    uint replacement = x86_value_by_semantic[semantic_row].replacement;
    if (replacement < gParams.semantic_capacity)
        semantic_row = replacement;
    OptIrNodeCore core = opt_ir_core[semantic_row];
    uint allocated = x86_location_by_semantic[semantic_row];
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_GET &&
        (core.type_id == 1u || core.type_id == 2u || core.type_id == 3u ||
         core.type_id == 4u || core.type_id == 6u || core.type_id == 8u))
    {
        uint declaration = opt_ir_operands[semantic_row].a;
        if (declaration < gParams.token_capacity)
        {
            uint location = x86_decl_location_by_token[declaration];
            bool explicit_alias = x86_live_by_semantic[semantic_row] ==
                X86_SEMANTIC_COALESCED_ALIAS;
            bool parameter_read =
                x86_decl_analysis_by_token[declaration].definition ==
                    X86_LOCATION_INVALID;
            bool allocated_across_call = allocated != X86_LOCATION_INVALID &&
                ((x86_location_is_register(allocated) &&
                  (x86_location_payload(allocated) == 3u ||
                   x86_location_payload(allocated) == 12u ||
                   x86_location_payload(allocated) == 13u ||
                   x86_location_payload(allocated) == 14u)) ||
                 !x86_location_is_register(allocated));
            if (location != X86_LOCATION_INVALID &&
                (explicit_alias ||
                 (parameter_read && !allocated_across_call)))
                return location;
        }
    }
    if ((allocated & X86_LOCATION_DECLARATION) != 0u)
    {
        uint declaration = allocated & X86_LOCATION_PAYLOAD_MASK;
        if (declaration < gParams.token_capacity)
        {
            uint location = x86_decl_location_by_token[declaration];
            if (location != X86_LOCATION_INVALID) return location;
        }
        return X86_LOCATION_INVALID;
    }
    return allocated;
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
    locations.result = X86_LOCATION_INVALID;
    locations.a = X86_LOCATION_INVALID;
    locations.b = X86_LOCATION_INVALID;
    locations.c = X86_LOCATION_INVALID;
    if (semantic_row < gParams.semantic_capacity &&
        core.result_or_target != INVALID && core.op != X86_LIR_OP_SELECT_STORE)
    {
        uint allocated = value_location(semantic_row);
        uint producer = semantic_to_target_start[semantic_row];
        bool inline_clone =
            (target_lir_flags[page_row] & TARGET_LIR_FLAG_INLINE_CLONE) != 0u;
        if ((allocated & X86_LOCATION_REGISTER) != 0u && allocated != INVALID &&
            (producer == row || inline_clone))
            locations.result = allocated;
        else if (allocated != INVALID && row >= producer)
            locations.result = stack_location(allocated + row - producer);
    }

    if (core.op == X86_LIR_OP_STORE_LOCAL)
    {
        locations.b = value_location(operands.b);
        if ((operands.metadata & X86_LIR_METADATA_STRING_PAIR) != 0u)
        {
            uint string_start = value_location(operands.b);
            locations.c = string_start != INVALID &&
                (string_start & X86_LOCATION_REGISTER) == 0u
                    ? stack_location(string_start + 1u) : X86_LOCATION_INVALID;
        }
    }
    else if (core.op == X86_LIR_OP_BINARY || core.op == X86_LIR_OP_COMPARE)
    {
        locations.b = value_location(operands.b);
        if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) == 0u &&
            (core.op != X86_LIR_OP_BINARY ||
             (operands.a != X86_LIR_BINARY_DIV_CONST_POW2_I32 &&
              operands.a != X86_LIR_BINARY_REM_CONST_POW2_I32 &&
              operands.a != X86_LIR_BINARY_DIV_CONST_I32 &&
              operands.a != X86_LIR_BINARY_REM_CONST_I32)))
            locations.c = value_location(operands.c);
    }
    else if (core.op == X86_LIR_OP_UNARY)
        locations.b = value_location(operands.b);
    else if (core.op == X86_LIR_OP_RETURN)
        locations.a = value_location(operands.a);
    else if (core.op == X86_LIR_OP_INLINE_RESULT)
        locations.a = value_location(operands.a);
    else if (core.op == X86_LIR_OP_AGGREGATE_RETURN_WORD)
        locations.a = value_location(operands.a);
    else if (core.op == X86_LIR_OP_AGGREGATE_COPY_WORD)
        locations.a = value_location(operands.a);
    else if (core.op == X86_LIR_OP_CALL_ARG)
    {
        if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u)
            locations.a = X86_LOCATION_INVALID;
        else if ((operands.metadata & X86_LIR_METADATA_STRING_LEN) != 0u)
        {
            uint string_start = value_location(operands.a);
            locations.a = string_start != INVALID &&
                (string_start & X86_LOCATION_REGISTER) == 0u
                    ? stack_location(string_start + 1u) : X86_LOCATION_INVALID;
        }
        else locations.a = value_location(operands.a);
    }
    else if (core.op == X86_LIR_OP_AGGREGATE_INIT)
    {
        locations.a = (operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u
            ? X86_LOCATION_INVALID : value_location(operands.a);
        locations.c = locations.result;
    }
    else if (core.op == X86_LIR_OP_INDEX_LOAD)
    {
        locations.a = value_location(operands.a);
        locations.b = value_location(operands.b);
    }
    else if (core.op == X86_LIR_OP_FIELD_LOAD)
        locations.a = value_location(operands.a);
    else if (core.op == X86_LIR_OP_INDEX_STORE)
    {
        locations.a = value_location(operands.a);
        locations.b = value_location(operands.b);
        locations.c = value_location(operands.c);
    }
    else if (core.op == X86_LIR_OP_FIELD_STORE)
    {
        locations.a = value_location(operands.a);
        locations.c = value_location(operands.c);
    }
    else if (core.op == X86_LIR_OP_COMPARE_BRANCH_FALSE)
    {
        locations.a = value_location(operands.a);
        if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) == 0u)
            locations.b = value_location(operands.b);
    }
    else if (core.op == X86_LIR_OP_SELECT_STORE)
    {
        X86SelectInfo info = x86_select_by_semantic[semantic_row];
        locations.result = value_location(info.false_value);
        locations.a = value_location(operands.a);
        if ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) == 0u)
            locations.b = value_location(operands.b);
        locations.c = value_location(operands.c);
    }
    else if (core.op == X86_LIR_OP_BRANCH && operands.a != INVALID)
        locations.a = value_location(operands.a);

    target_lir_locations[page_row] = locations;
}
