import primitive_types;
import native_value_layout;
import codegen.lir.x86.index_address_layout;
import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.storage_layout;
import codegen.lir.x86.runtime_abi;
import codegen.lir.x86.location_common;
import codegen.lir.x86.frame_layout;
import codegen.lir.x86.parameter_values;
import codegen.lir.x86.encoding;
import codegen.lir.x86.instruction_plan;
import gpu_index;

struct Params
{
    uint target_capacity;
    uint token_capacity;
    uint function_capacity;
    uint artifact_capacity;
    uint target_start;
    uint page_capacity;
    uint semantic_capacity;
    uint reserved1;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<X86LirCore> target_lir_core;
StructuredBuffer<X86LirOperands> target_lir_operands;
StructuredBuffer<X86LirLocations> target_lir_locations;
StructuredBuffer<uint> target_semantic_origin;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> opt_ir_semantic_row;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<uint> target_function_count;
StructuredBuffer<TargetLirFunction> target_functions;
StructuredBuffer<uint> target_function_index_by_semantic;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
StructuredBuffer<uint> x86_decl_location_by_token;
StructuredBuffer<uint4> x86_place_storage_by_token;
StructuredBuffer<uint> x86_saved_gpr_mask_by_function;
RWStructuredBuffer<uint> target_byte_length;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_unsupported(uint page_row, uint source_hir)
{
    uint opt_row = target_semantic_origin[page_row];
    uint semantic_row = opt_row < gParams.semantic_capacity
        ? opt_ir_semantic_row[opt_row] : INVALID;
    InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
    InterlockedMin(lowering_status[0u].first_unsupported_hir, source_hir);
    InterlockedMin(lowering_status[0u].first_unsupported_semantic_row, semantic_row);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, opt_row);
    InterlockedMin(lowering_status[0u].first_unsupported_target_op,
        target_lir_core[page_row].op);
}

uint declaration_location(uint token)
{
    uint location = token < gParams.token_capacity
        ? x86_decl_location_by_token[token] : X86_LOCATION_INVALID;
    return location == X86_LOCATION_INVALID ? 0u : location;
}

uint hidden_sret_slot(TargetLirFunction function)
{
    return function.flags & X86_TARGET_FUNCTION_FRAME_SLOT_MASK;
}

uint param_store_bytes(TargetLirFunction target_function,
                       SemanticLirFunction function, uint hidden_sret)
{
    uint bytes = hidden_sret != 0u
        ? x86_stack64_operand_bytes(hidden_sret_slot(target_function)) : 0u;
    uint abi_ordinal = hidden_sret;
    for (uint ordinal = 0u; ordinal < function.param_count; ordinal += 1u)
    {
        SemanticLirParam param = semantic_lir_params[function.param_start + ordinal];
        uint width = x86_abi_param_width(param);
        uint destination = declaration_location(param.declaration_id);
        for (uint component = 0u; component < width; component += 1u)
        {
            uint incoming = abi_ordinal + component;
            bytes += incoming < 6u
                ? x86_move64_from_fixed_bytes(x86_abi_argument_register(incoming), destination + component)
                : (frameless_function(target_function, function) ||
                   stackless_caller(target_function, function) ? 8u : 7u) +
                  x86_move64_from_fixed_bytes(0u, destination + component);
        }
        abi_ordinal += width;
    }
    return bytes + x86_parameter_copy_bytes(target_function, function,
        semantic_lir_params, x86_decl_location_by_token);
}

uint function_abi_param_count(SemanticLirFunction function)
{
    uint count = 0u;
    for (uint ordinal = 0u; ordinal < function.param_count; ordinal += 1u)
        count += x86_abi_param_width(
            semantic_lir_params[function.param_start + ordinal]);
    return count;
}

// Body bytes from the shared instruction plan, the same micro-ops emission
// encodes. The implicit footer is counted separately below.
uint instruction_bytes(X86LirCore core, X86LirOperands operands,
                       X86LirLocations locations,
                       TargetLirFunction function,
                       SemanticLirFunction semantic_function,
                       uint saved_mask)
{
    X86PlanInput input;
    input.core = core;
    input.operands = operands;
    input.locations = locations;
    input.hidden_sret_slot = hidden_sret_slot(function);
    input.saved_first_slot = base_frame_slots(function, semantic_function);
    input.saved_mask = saved_mask;
    input.frameless = frameless_function(function, semantic_function);
    input.stackless = stackless_caller(function, semantic_function);
    input.decl_a = declaration_location(operands.a);
    input.decl_target = declaration_location(core.result_or_target);
    input.place_slot = operands.a < gParams.token_capacity
        ? x86_place_storage_by_token[operands.a].x : 0u;
    input.callee_row = INVALID;
    if (core.op == X86_LIR_OP_CALL)
    {
        uint callee_index = operands.a < gParams.function_capacity
            ? target_function_index_by_semantic[operands.a] : INVALID;
        if (callee_index < target_function_count[0u])
            input.callee_row = target_functions[callee_index].instruction_start;
    }
    input.specialized = x86_is_specialized_instruction(core, operands);
    input.footer = false;
    input.skip_body = false;
    uint bytes = 0u;
    for (uint step = 0u; ; step += 1u)
    {
        X86PlanOp op = x86_plan(input, step);
        if (x86_op_kind(op.head) == X86_OP_END) break;
        bytes += x86_encode(op).length;
    }
    return bytes;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (page_row >= gParams.page_capacity) return;
    uint row = gParams.target_start + page_row;
    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    if (row >= gParams.target_capacity) return;
    target_byte_length[row] = 0u;
    if (row >= total) return;
    X86LirCore core = target_lir_core[page_row];
    X86LirOperands operands = target_lir_operands[page_row];
    X86LirLocations locations = target_lir_locations[page_row];
    uint function_id = semantic_function_id_by_hir[core.source_hir];
    uint function_count = min(gParams.function_capacity,
        min(target_function_count[0u], semantic_lir_function_total[0u]));
    uint function_index = function_id < gParams.function_capacity
        ? target_function_index_by_semantic[function_id] : INVALID;
    if (function_index >= function_count)
    {
        report_unsupported(page_row, core.source_hir);
        return;
    }
    TargetLirFunction function = target_functions[function_index];
    SemanticLirFunction semantic_function = semantic_lir_functions[function_id];
    uint saved_mask = x86_saved_gpr_mask_by_function[function_id];
    bool frameless = frameless_function(function, semantic_function);
    bool stackless = stackless_caller(function, semantic_function);
    uint bytes = instruction_bytes(core, operands, locations, function,
        semantic_function, saved_mask);
    if (bytes == 0u && x86_is_specialized_scalar_instruction(core, operands))
    {
        // Scalar bodies selected by the shared partition must encode.
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        InterlockedMin(lowering_status[0u].first_unsupported_hir, core.source_hir);
    }
    bool zero_binary_identity = core.op == X86_LIR_OP_BINARY &&
        (operands.metadata & X86_LIR_METADATA_IMMEDIATE) != 0u &&
        x86_binary_immediate_identity(operands.a, operands.c) &&
        locations.b == locations.result;
    bool supported_zero = x86_is_specialized_scalar_instruction(core, operands) ||
        core.op == X86_LIR_OP_LABEL ||
        core.op == X86_LIR_OP_AGGREGATE_RESULT_SLOT ||
        core.op == X86_LIR_OP_ALIAS ||
        core.op == X86_LIR_OP_STORE_LOCAL ||
        core.op == X86_LIR_OP_CALL_ARG ||
        core.op == X86_LIR_OP_INLINE_RESULT ||
        core.op == X86_LIR_OP_INTRINSIC_IDENTITY ||
        (core.op == X86_LIR_OP_INDEX_STORE &&
         (operands.metadata & X86_LIR_METADATA_INDEX_AGGREGATE_COPY) != 0u &&
         core.result_or_target == 0u) ||
        (core.op == X86_LIR_OP_AGGREGATE_RETURN_WORD &&
         operands.c == 2u && operands.b == 1u) || zero_binary_identity;
    if (bytes == 0u && !supported_zero)
    {
        report_unsupported(page_row, core.source_hir);
    }
    if (core.op == X86_LIR_OP_DECL_ADDRESS)
    {
        uint4 storage = operands.a < gParams.token_capacity ? x86_place_storage_by_token[operands.a]
            : uint4(INVALID, 0u, 0u, 0u);
        uint frame = function.flags & X86_TARGET_FUNCTION_FRAME_SLOT_MASK;
        uint words = max(storage.y, 1u);
        if (storage.z == 0u || storage.z > 3u || storage.x >= frame || words > frame - storage.x ||
            locations.result == X86_LOCATION_INVALID || frame >= 0x10000000u)
            report_unsupported(page_row, core.source_hir);
    }
    if ((core.op == X86_LIR_OP_FIELD_ADDRESS || core.op == X86_LIR_OP_PLACE_LOAD) &&
        (operands.a >= total || locations.a == X86_LOCATION_INVALID || locations.result == X86_LOCATION_INVALID))
        report_unsupported(page_row, core.source_hir);
    if (core.op == X86_LIR_OP_PLACE_STORE &&
        (operands.a >= total || operands.b >= total || locations.a == X86_LOCATION_INVALID || locations.b == X86_LOCATION_INVALID))
        report_unsupported(page_row, core.source_hir);
    if (core.op == X86_LIR_OP_INDEX_ADDRESS &&
        (operands.a >= total || operands.b >= total || locations.a == X86_LOCATION_INVALID ||
         locations.b == X86_LOCATION_INVALID || locations.result == X86_LOCATION_INVALID || core.local_ordinal == INVALID))
        report_unsupported(page_row, core.source_hir);
    if (core.op == X86_LIR_OP_CALL_ARG &&
        (operands.metadata & X86_LIR_METADATA_IMMEDIATE) == 0u &&
        operands.a >= total)
    {
        report_unsupported(page_row, core.source_hir);
    }
    if ((core.op == X86_LIR_OP_AGGREGATE_INIT &&
         (operands.metadata & X86_LIR_METADATA_IMMEDIATE) == 0u &&
         operands.a >= total) ||
        (core.op == X86_LIR_OP_INDEX_LOAD &&
         (operands.a >= total || operands.b >= total)) ||
        (core.op == X86_LIR_OP_FIELD_LOAD && operands.a >= total))
    {
        report_unsupported(page_row, core.source_hir);
    }
    if ((core.op == X86_LIR_OP_INDEX_STORE &&
         (operands.a >= total || operands.b >= total || operands.c >= total)) ||
        (core.op == X86_LIR_OP_FIELD_STORE &&
         (operands.a >= total || operands.c >= total)))
    {
        report_unsupported(page_row, core.source_hir);
    }
    if (core.op == X86_LIR_OP_COMPARE_BRANCH_FALSE &&
        (operands.a >= total || core.result_or_target >= total ||
         ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) == 0u &&
          operands.b >= total)))
    {
        report_unsupported(page_row, core.source_hir);
    }
    if (core.op == X86_LIR_OP_SELECT_STORE &&
        (declaration_location(core.result_or_target) == X86_LOCATION_INVALID ||
         locations.result == X86_LOCATION_INVALID || operands.a >= total ||
         operands.c >= total ||
         ((operands.metadata & X86_LIR_METADATA_IMMEDIATE) == 0u &&
          operands.b >= total)))
    {
        report_unsupported(page_row, core.source_hir);
    }
    uint callee_index = operands.a < gParams.function_capacity
        ? target_function_index_by_semantic[operands.a] : INVALID;
    if (core.op == X86_LIR_OP_CALL && callee_index >= function_count)
    {
        report_unsupported(page_row, core.source_hir);
    }
    if (core.op == X86_LIR_OP_CALL_SYMBOL &&
        ((operands.a == INVALID) != (operands.b == INVALID) || operands.c == INVALID))
    {
        report_unsupported(page_row, core.source_hir);
    }
    if (core.op == X86_LIR_OP_CALL_HOST && operands.a != HOST_SERVICE_I32_TO_F32 &&
        !x86_runtime_service_supported(operands.a))
    {
        report_unsupported(page_row, core.source_hir);
    }
    uint hidden_sret = semantic_function.result_word_count > 2u ? 1u : 0u;
    if (row == function.instruction_start)
    {
        uint first_saved_slot = base_frame_slots(function, semantic_function);
        uint frame_slots = first_saved_slot + x86_saved_gpr_count(saved_mask);
        uint saved_bytes = x86_saved_gpr_frame_bytes(
            saved_mask, first_saved_slot);
        bytes += (frameless ? 0u : stackless ? 1u :
            4u + (frame_slots == 0u ? 0u : 7u) +
            saved_bytes) +
            param_store_bytes(function, semantic_function, hidden_sret);
    }
    bool final_explicit_return = core.op == X86_LIR_OP_RETURN ||
        core.op == X86_LIR_OP_RETURN_VOID || core.op == X86_LIR_OP_TRAP;
    if (row + 1u == function.instruction_start + function.instruction_count &&
        !final_explicit_return)
        bytes += implicit_footer_bytes(function, semantic_function, saved_mask);
    target_byte_length[row] = bytes;
}
