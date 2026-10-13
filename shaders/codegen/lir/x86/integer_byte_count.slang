// Ordered after byte_count, before prefix scan, once per retained target page.
// Base counting owns initialization, ordinary bodies and prologue/footer.
// This existing pass adds guards and all selected integer, pointer and float
// bodies. Shared ownership predicates keep each body in exactly one counter.
import primitive_types;
import codegen.lowering_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.safety;
import codegen.lir.x86.location_common;
import gpu_index;
struct Params
{
    uint target_capacity; uint token_capacity; uint function_capacity; uint artifact_capacity;
    uint target_start; uint page_capacity; uint semantic_capacity; uint reserved1;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<X86LirCore> target_lir_core;
StructuredBuffer<X86LirOperands> target_lir_operands;
StructuredBuffer<X86LirLocations> target_lir_locations;
StructuredBuffer<uint> target_lir_flags;
RWStructuredBuffer<uint> target_byte_length;
RWStructuredBuffer<LoweringStatus> lowering_status;
uint integer_width_binary_bytes(X86LirOperands operands, X86LirLocations locations)
{
    uint type = operands.metadata & 0xffu;
    bool wide = scalar_is_wide_integer(type);
    bool shift = operands.a == X86_LIR_BINARY_SHL_I32 || operands.a == X86_LIR_BINARY_SHR_I32;
    bool wide_rhs = wide && (!shift || (operands.metadata & X86_LIR_METADATA_RHS_NARROW) == 0u);
    uint operation;
    if (operands.a == X86_LIR_BINARY_DIV_I32 || operands.a == X86_LIR_BINARY_REM_I32)
    {
        operation = scalar_is_signed_integer(type) ? (wide ? 2u : 1u) : 2u;
        operation += wide ? 3u : 2u;
        if (operands.a == X86_LIR_BINARY_REM_I32) operation += wide ? 3u : 2u;
    }
    else operation = (wide ? 1u : 0u) + (operands.a == X86_LIR_BINARY_MUL_I32 ? 3u : 2u);
    return (wide ? x86_move64_to_fixed_bytes(locations.b, 0u) : x86_move32_to_fixed_bytes(locations.b, 0u)) +
        (wide_rhs ? x86_move64_to_fixed_bytes(locations.c, 1u) : x86_move32_to_fixed_bytes(locations.c, 1u)) +
        operation + (scalar_is_narrow_integer(type) ? 3u : 0u) +
        (wide ? x86_move64_from_fixed_bytes(0u, locations.result) : x86_move32_from_fixed_bytes(0u, locations.result));
}

uint specialized_scalar_instruction_bytes(X86LirCore core, X86LirOperands operands, X86LirLocations locations)
{
    uint integer_type = operands.metadata & 0xffu;
    bool distinct_integer_width = scalar_is_wide_integer(integer_type) || scalar_is_narrow_integer(integer_type);
    if (core.op == X86_LIR_OP_IMM_I64)
        return 10u + (x86_scalar_f64(operands.metadata)
            ? x86_move_float_from_gpr_bytes(0u, locations.result, true)
            : x86_move64_from_fixed_bytes(0u, locations.result));
    if (x86_is_specialized_float_instruction(core, operands))
    {
        bool wide = x86_scalar_f64(operands.metadata);
        if (core.op == X86_LIR_OP_BINARY)
            return float_binary_bytes(operands.a, locations.b, locations.c, locations.result, wide);
        if (core.op == X86_LIR_OP_UNARY)
            return x86_move_float_to_gpr_bytes(locations.b, 0u, wide) + 5u +
                x86_move_float_from_gpr_bytes(0u, locations.result, wide);
        if (core.op == X86_LIR_OP_COMPARE_BRANCH_FALSE)
            return float_compare_instruction_bytes(locations.a, locations.b, wide) + 16u;
        return float_compare_bytes(locations.b, locations.c, locations.result, wide);
    }
    if (core.op == X86_LIR_OP_BINARY && integer_type == SCALAR_PTR)
        return x86_move64_to_fixed_bytes(locations.b, 0u) +
            (scalar_is_wide_integer(core.local_ordinal)
                ? x86_move64_to_fixed_bytes(locations.c, 1u)
                : x86_move32_to_fixed_bytes(locations.c, 1u) +
                    (scalar_is_signed_integer(core.local_ordinal) ? 3u : 0u)) + 3u +
            x86_move64_from_fixed_bytes(0u, locations.result);
    if (core.op == X86_LIR_OP_COMPARE || core.op == X86_LIR_OP_COMPARE_BRANCH_FALSE)
    {
        bool branch = core.op == X86_LIR_OP_COMPARE_BRANCH_FALSE;
        uint left = branch ? locations.a : locations.b;
        uint right = branch ? locations.b : locations.c;
        return x86_move64_to_fixed_bytes(left, 0u) +
            ((operands.metadata & X86_LIR_METADATA_RHS_NARROW) != 0u
                ? x86_move32_to_fixed_bytes(right, 1u) : x86_move64_to_fixed_bytes(right, 1u)) + 3u +
            (branch ? 6u : x86_boolean_result_bytes(locations.result));
    }
    if (core.op == X86_LIR_OP_BINARY && distinct_integer_width)
        return integer_width_binary_bytes(operands, locations);
    if (core.op == X86_LIR_OP_UNARY && distinct_integer_width && operands.a == X86_LIR_UNARY_NEG_I32)
        return scalar_is_wide_integer(integer_type)
            ? x86_move64_to_fixed_bytes(locations.b, 0u) + 3u + x86_move64_from_fixed_bytes(0u, locations.result)
            : x86_move32_to_fixed_bytes(locations.b, 0u) + 5u + x86_move32_from_fixed_bytes(0u, locations.result);
    return 0u;
}
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_row = linear_dispatch_thread_id_2d(dtid, 16776960u);
    if (page_row >= gParams.page_capacity) return;
    uint row = gParams.target_start + page_row;
    if (row >= min(gParams.target_capacity, target_lir_total[0u])) return;
    if ((target_lir_flags[page_row] & TARGET_LIR_FLAG_UNSUPPORTED) != 0u) return;
    X86LirCore core = target_lir_core[page_row];
    X86LirOperands operands = target_lir_operands[page_row];
    bool width_body = x86_is_specialized_scalar_instruction(core, operands);
    X86LirLocations locations = target_lir_locations[page_row];
    uint body = width_body ? specialized_scalar_instruction_bytes(core, operands, locations) : 0u;
    uint guards = x86_safety_guard_bytes(core, operands, locations);
    uint prior = target_byte_length[row];
    if (width_body && body == 0u)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
        return;
    }
    uint addition = body + guards;
    if (addition < body || addition > gParams.artifact_capacity ||
        prior > gParams.artifact_capacity - addition)
    {
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_ARTIFACT_CAPACITY);
        return;
    }
    target_byte_length[row] = prior + addition;
}
